<#
.SYNOPSIS
  Claude Enterprise Compliance API collector for Activity Feed and eDiscovery content.

.DESCRIPTION
  - Stores Activity Feed Activity objects as date-partitioned raw JSONL.
  - Uses first_id / last_id checkpoints for Activity Feed backfill and tail.
  - Optionally collects chat messages, artifact text, project details, and project text documents.
  - Does NOT download uploaded file binaries or Claude-generated binary files.
  - Designed for Windows Task Scheduler daily execution.

.NOTES
  API key is read from an environment variable. Do not hard-code API keys.
  Default environment variable: ANTHROPIC_COMPLIANCE_ACCESS_KEY
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('ActivityBackfill','ActivityTail','ContentBackfill','ContentTail','AllBackfill','AllTail','Status')]
    [string]$Mode = 'ActivityTail',

    [Parameter(Mandatory = $false)]
    [string]$Root = 'C:\ProgramData\ClaudeComplianceCollector',

    [Parameter(Mandatory = $false)]
    [string]$ApiKeyEnvName = 'ANTHROPIC_COMPLIANCE_ACCESS_KEY',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,5000)]
    [int]$ActivityLimit = 5000,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,1000)]
    [int]$ChatListLimit = 100,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,5000)]
    [int]$ChatMessagesLimit = 500,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,1000)]
    [int]$ProjectListLimit = 100,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,1000)]
    [int]$ProjectAttachmentsLimit = 100,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0,20)]
    [int]$MaxRetries = 8,

    [Parameter(Mandatory = $false)]
    [ValidateRange(10,1800)]
    [int]$TimeoutSec = 120,

    # 250ms ~= 240 requests/minute from this collector, intentionally below the documented 600 RPM org-wide budget.
    [Parameter(Mandatory = $false)]
    [ValidateRange(0,60000)]
    [int]$MinDelayMs = 250,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0,600)]
    [int]$ThrottleWhenRemainingBelow = 30,

    # Skip daily full scan of project metadata/details/attachments. Chat content collection still runs in Content* modes.
    [Parameter(Mandatory = $false)]
    [switch]$SkipProjectFullScan,

    # Skip downloading text artifact versions. Uploaded file binaries and generated binary files are always skipped.
    [Parameter(Mandatory = $false)]
    [switch]$SkipArtifactText
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# -----------------------------
# Global runtime state
# -----------------------------
$script:ApiBase = 'https://api.anthropic.com'
$script:RunId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$script:RunStartUtc = (Get-Date).ToUniversalTime()
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:ApiKey = $null
$script:Mutex = $null
$script:MutexAcquired = $false
$script:LastRequestUtc = [DateTime]::MinValue
$script:IndexCache = @{}
$script:CompleteIndexCache = @{}
$script:LogFile = $null
$script:ErrorLogFile = $null
$script:RequestLogFile = $null

$script:Stats = [ordered]@{
    run_id                    = $script:RunId
    mode                      = $Mode
    root                      = $Root
    start_utc                 = $script:RunStartUtc.ToString('o')
    end_utc                   = $null
    duration_seconds          = $null
    api_requests              = 0
    retry_count               = 0
    rate_limit_429_count      = 0
    error_count               = 0
    activity_fetched          = 0
    activity_saved            = 0
    activity_duplicate        = 0
    chat_list_items           = 0
    chat_metadata_saved       = 0
    chat_message_pages_saved  = 0
    artifact_text_saved       = 0
    projects_seen             = 0
    project_records_saved     = 0
    project_attachments_seen  = 0
    project_documents_saved   = 0
    file_binaries_skipped     = 0
    content_not_found         = 0
    start_checkpoint          = $null
    end_checkpoint            = $null
    last_request_id           = $null
    request_ids               = @()
    last_success_utc          = $null
    status                    = 'running'
    error                     = $null
}

# -----------------------------
# Filesystem helpers
# -----------------------------
function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Initialize-Folders {
    Ensure-Directory -Path $Root
    foreach ($child in @(
        'state',
        'locks',
        'logs',
        'data\raw\activities',
        'data\raw\chats',
        'data\raw\chat_messages',
        'data\raw\artifacts',
        'data\raw\projects',
        'data\raw\project_details',
        'data\raw\project_attachments',
        'data\raw\project_documents',
        'data\raw\content_missing',
        'data\index',
        'data\index\complete'
    )) {
        Ensure-Directory -Path (Join-Path $Root $child)
    }

    $today = (Get-Date).ToUniversalTime().ToString('yyyyMMdd')
    $script:LogFile = Join-Path (Join-Path $Root 'logs') ("run_$today.txt")
    $script:ErrorLogFile = Join-Path (Join-Path $Root 'logs') ("error_$today.txt")
    $script:RequestLogFile = Join-Path (Join-Path $Root 'logs') ("requests_$today.jsonl")
}

function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $dir = Split-Path -Parent $Path
    Ensure-Directory -Path $dir
    $tmp = "$Path.tmp.$($script:RunId).$PID"
    [System.IO.File]::WriteAllText($tmp, $Content, $script:Utf8NoBom)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Append-Text {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Text
    )
    $dir = Split-Path -Parent $Path
    Ensure-Directory -Path $dir
    [System.IO.File]::AppendAllText($Path, $Text, $script:Utf8NoBom)
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString('o')
    $line = "$timestamp`t$Level`t$Message"
    Append-Text -Path $script:LogFile -Text ($line + [Environment]::NewLine)
    if ($Level -eq 'ERROR') {
        Append-Text -Path $script:ErrorLogFile -Text ($line + [Environment]::NewLine)
    }
    Write-Host $line
}

function Write-RequestLog {
    param([Parameter(Mandatory=$true)][hashtable]$Record)
    $json = ($Record | ConvertTo-Json -Depth 20 -Compress)
    Append-Text -Path $script:RequestLogFile -Text ($json + [Environment]::NewLine)
}

function Get-StatePath {
    return (Join-Path (Join-Path $Root 'state') 'checkpoint.json')
}

function Get-DefaultState {
    return [ordered]@{
        schema_version                  = 1
        activity_first_id               = $null
        activity_last_id                = $null
        activity_backfill_complete      = $false
        chat_last_id                    = $null
        chat_backfill_complete          = $false
        project_last_full_scan_utc      = $null
        last_success_utc                = $null
        last_success_mode               = $null
        updated_at_utc                  = $null
    }
}

function Load-State {
    $path = Get-StatePath
    $default = Get-DefaultState
    if (-not (Test-Path -LiteralPath $path)) {
        return $default
    }
    try {
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $default }
        $obj = $raw | ConvertFrom-Json
        foreach ($k in @($default.Keys)) {
            if (-not ($obj.PSObject.Properties.Name -contains $k)) {
                Add-Member -InputObject $obj -NotePropertyName $k -NotePropertyValue $default[$k]
            }
        }
        return $obj
    }
    catch {
        throw "checkpoint.json の読み込みまたは JSON 変換に失敗しました。checkpoint は更新しません。詳細: $($_.Exception.Message)"
    }
}

function Save-State {
    param([Parameter(Mandatory=$true)]$State)
    $State.updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    $json = ($State | ConvertTo-Json -Depth 30)
    Write-TextFileAtomic -Path (Get-StatePath) -Content $json
}

function Get-DateFromRfc3339OrNow {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return (Get-Date).ToUniversalTime()
    }
    try {
        return ([DateTimeOffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).UtcDateTime
    }
    catch {
        Write-Log -Level 'WARN' -Message "RFC3339日時として解析できませんでした。現在UTCで保存します。value=$Value"
        return (Get-Date).ToUniversalTime()
    }
}

function Get-PartitionPaths {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][datetime]$DateUtc,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [Parameter(Mandatory=$false)][string]$Extension = 'jsonl'
    )
    $yyyy = $DateUtc.ToString('yyyy')
    $mm = $DateUtc.ToString('MM')
    $dd = $DateUtc.ToString('dd')
    $yyyymmdd = $DateUtc.ToString('yyyyMMdd')
    $dataDir = Join-Path $Root ("data\raw\$Category\$yyyy\$mm\$dd")
    $indexDir = Join-Path $Root ("data\index\$Category\$yyyy\$mm")
    Ensure-Directory -Path $dataDir
    Ensure-Directory -Path $indexDir
    return [ordered]@{
        data_path  = (Join-Path $dataDir ("${Prefix}_${yyyymmdd}.${Extension}"))
        index_path = (Join-Path $indexDir ("${Prefix}_${yyyymmdd}.idx"))
    }
}

function Convert-ToJsonLine {
    param([Parameter(Mandatory=$true)][string]$Raw)
    # JSON bodies returned by the API are expected to be valid JSON. JSONL needs one physical line per record.
    return (($Raw.Trim()) -replace "`r`n", '' -replace "`n", '' -replace "`r", '')
}

function Get-Sha256Hex {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:Utf8NoBom.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ObjectIdFromJsonLine {
    param([Parameter(Mandatory=$true)][string]$Line)
    try {
        $obj = $Line | ConvertFrom-Json
        return [string]$obj.id
    }
    catch {
        return $null
    }
}

function Rebuild-ActivityIndexIfNeeded {
    param(
        [Parameter(Mandatory=$true)][string]$DataPath,
        [Parameter(Mandatory=$true)][string]$IndexPath
    )
    $shouldRebuild = $false
    if ((Test-Path -LiteralPath $DataPath) -and (-not (Test-Path -LiteralPath $IndexPath))) {
        $shouldRebuild = $true
    }
    elseif ((Test-Path -LiteralPath $DataPath) -and (Test-Path -LiteralPath $IndexPath)) {
        $dataTime = (Get-Item -LiteralPath $DataPath).LastWriteTimeUtc
        $indexTime = (Get-Item -LiteralPath $IndexPath).LastWriteTimeUtc
        if ($dataTime -gt $indexTime.AddSeconds(2)) { $shouldRebuild = $true }
    }
    if (-not $shouldRebuild) { return }

    Write-Log -Level 'WARN' -Message "Activity index を data から再構築します。data=$DataPath index=$IndexPath"
    $dir = Split-Path -Parent $IndexPath
    Ensure-Directory -Path $dir
    $tmp = "$IndexPath.rebuild.$($script:RunId).tmp"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    if (Test-Path -LiteralPath $DataPath) {
        Get-Content -LiteralPath $DataPath -Encoding UTF8 -ReadCount 1000 | ForEach-Object {
            foreach ($line in $_) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $id = Get-ObjectIdFromJsonLine -Line $line
                if (-not [string]::IsNullOrWhiteSpace($id)) {
                    Append-Text -Path $tmp -Text ($id + [Environment]::NewLine)
                }
            }
        }
    }
    if (Test-Path -LiteralPath $IndexPath) { Remove-Item -LiteralPath $IndexPath -Force }
    if (Test-Path -LiteralPath $tmp) { Move-Item -LiteralPath $tmp -Destination $IndexPath -Force }
}

function Get-IndexSet {
    param(
        [Parameter(Mandatory=$true)][string]$IndexPath,
        [Parameter(Mandatory=$false)][string]$DataPath,
        [Parameter(Mandatory=$false)][switch]$RebuildActivityIndex
    )
    if ($RebuildActivityIndex) {
        Rebuild-ActivityIndexIfNeeded -DataPath $DataPath -IndexPath $IndexPath
    }
    if ($script:IndexCache.ContainsKey($IndexPath)) {
        return $script:IndexCache[$IndexPath]
    }
    $set = @{}
    if (Test-Path -LiteralPath $IndexPath) {
        Get-Content -LiteralPath $IndexPath -Encoding UTF8 -ReadCount 1000 | ForEach-Object {
            foreach ($line in $_) {
                $key = [string]$line
                if (-not [string]::IsNullOrWhiteSpace($key)) { $set[$key] = $true }
            }
        }
    }
    $script:IndexCache[$IndexPath] = $set
    return $set
}

function Append-JsonLineDedup {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][datetime]$DateUtc,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [Parameter(Mandatory=$true)][string]$UniqueKey,
        [Parameter(Mandatory=$true)][string]$RawJsonLine,
        [Parameter(Mandatory=$false)][switch]$RebuildActivityIndex
    )
    if ([string]::IsNullOrWhiteSpace($UniqueKey)) {
        throw "UniqueKey が空のため保存できません。category=$Category prefix=$Prefix"
    }
    $paths = Get-PartitionPaths -Category $Category -DateUtc $DateUtc -Prefix $Prefix
    $set = Get-IndexSet -IndexPath $paths.index_path -DataPath $paths.data_path -RebuildActivityIndex:$RebuildActivityIndex
    if ($set.ContainsKey($UniqueKey)) {
        return $false
    }

    $line = Convert-ToJsonLine -Raw $RawJsonLine
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "保存対象 JSON line が空です。category=$Category key=$UniqueKey"
    }

    # Important order: data first, index second. Checkpoints are updated only after both succeed.
    Append-Text -Path $paths.data_path -Text ($line + [Environment]::NewLine)
    Append-Text -Path $paths.index_path -Text ($UniqueKey + [Environment]::NewLine)
    $set[$UniqueKey] = $true
    return $true
}

function Get-CompleteIndexPath {
    param([Parameter(Mandatory=$true)][string]$Name)
    return (Join-Path (Join-Path (Join-Path $Root 'data\index') 'complete') ("$Name.idx"))
}

function Get-CompleteSet {
    param([Parameter(Mandatory=$true)][string]$Name)
    $path = Get-CompleteIndexPath -Name $Name
    if ($script:CompleteIndexCache.ContainsKey($path)) { return $script:CompleteIndexCache[$path] }
    $set = @{}
    if (Test-Path -LiteralPath $path) {
        Get-Content -LiteralPath $path -Encoding UTF8 -ReadCount 1000 | ForEach-Object {
            foreach ($line in $_) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { $set[[string]$line] = $true }
            }
        }
    }
    $script:CompleteIndexCache[$path] = $set
    return $set
}

function Test-CompleteKey {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Key
    )
    $set = Get-CompleteSet -Name $Name
    return $set.ContainsKey($Key)
}

function Mark-CompleteKey {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Key
    )
    $set = Get-CompleteSet -Name $Name
    if ($set.ContainsKey($Key)) { return }
    $path = Get-CompleteIndexPath -Name $Name
    Append-Text -Path $path -Text ($Key + [Environment]::NewLine)
    $set[$Key] = $true
}

# -----------------------------
# Locking
# -----------------------------
function Acquire-CollectorLock {
    $mutexName = 'Global\ClaudeComplianceCollector'
    try {
        $script:Mutex = New-Object System.Threading.Mutex($false, $mutexName)
    }
    catch {
        $mutexName = 'Local\ClaudeComplianceCollector'
        $script:Mutex = New-Object System.Threading.Mutex($false, $mutexName)
    }
    $script:MutexAcquired = $script:Mutex.WaitOne(0)
    if (-not $script:MutexAcquired) {
        Write-Log -Level 'WARN' -Message "別の ClaudeComplianceCollector が実行中です。多重起動を防止して終了します。mutex=$mutexName"
        exit 2
    }

    $lockPath = Join-Path (Join-Path $Root 'locks') 'collector.lock'
    $lock = [ordered]@{
        run_id = $script:RunId
        pid = $PID
        mode = $Mode
        start_utc = $script:RunStartUtc.ToString('o')
        mutex = $mutexName
    }
    Write-TextFileAtomic -Path $lockPath -Content ($lock | ConvertTo-Json -Depth 10)
}

function Release-CollectorLock {
    $lockPath = Join-Path (Join-Path $Root 'locks') 'collector.lock'
    try {
        if (Test-Path -LiteralPath $lockPath) { Remove-Item -LiteralPath $lockPath -Force }
    } catch { }
    try {
        if ($script:MutexAcquired -and $null -ne $script:Mutex) { $script:Mutex.ReleaseMutex() | Out-Null }
    } catch { }
    try {
        if ($null -ne $script:Mutex) { $script:Mutex.Dispose() }
    } catch { }
}

# -----------------------------
# HTTP helpers
# -----------------------------
function Initialize-Tls {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch { }
}

function Get-EnvVarValue {
    param([Parameter(Mandatory=$true)][string]$Name)
    foreach ($scope in @('Process','User','Machine')) {
        $value = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $null
}

function Escape-QueryValue {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Uri]::EscapeDataString($Value)
}

function Escape-PathSegment {
    param([Parameter(Mandatory=$true)][string]$Value)
    return [System.Uri]::EscapeDataString($Value)
}

function New-ClaudeUrl {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$false)]$QueryPairs
    )
    $url = $script:ApiBase.TrimEnd('/') + $Path
    $parts = New-Object System.Collections.Generic.List[string]
    if ($null -ne $QueryPairs) {
        foreach ($pair in $QueryPairs) {
            if ($null -eq $pair) { continue }
            $name = [string]$pair.Name
            $value = $pair.Value
            if ([string]::IsNullOrWhiteSpace($name) -or $null -eq $value) { continue }
            $parts.Add((Escape-QueryValue $name) + '=' + (Escape-QueryValue ([string]$value)))
        }
    }
    if ($parts.Count -gt 0) {
        $url = $url + '?' + ([string]::Join('&', $parts.ToArray()))
    }
    return $url
}

function Get-HeaderValue {
    param(
        [Parameter(Mandatory=$false)]$Headers,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if ($null -eq $Headers) { return $null }
    try {
        foreach ($key in $Headers.AllKeys) {
            if ($key -ieq $Name) { return [string]$Headers[$key] }
        }
    } catch { }
    try {
        foreach ($key in $Headers.Keys) {
            if ([string]$key -ieq $Name) { return [string]$Headers[$key] }
        }
    } catch { }
    return $null
}

function Read-ResponseBody {
    param([Parameter(Mandatory=$true)]$Response)
    $stream = $Response.GetResponseStream()
    if ($null -eq $stream) { return '' }
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

function Invoke-HttpGetRaw {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Accept
    )
    $request = [System.Net.WebRequest]::Create($Url)
    $request.Method = 'GET'
    $request.Timeout = $TimeoutSec * 1000
    $request.ReadWriteTimeout = $TimeoutSec * 1000
    $request.Headers.Add('x-api-key', $script:ApiKey)
    $request.Headers.Add('User-Agent', 'ClaudeComplianceCollector-PowerShell/1.0')
    try { $request.Accept = $Accept } catch { }

    try {
        $response = $request.GetResponse()
        try {
            $statusCode = [int]$response.StatusCode
            $body = Read-ResponseBody -Response $response
            return [pscustomobject]@{
                StatusCode = $statusCode
                Headers    = $response.Headers
                Body       = $body
                Error      = $null
            }
        }
        finally { $response.Close() }
    }
    catch [System.Net.WebException] {
        $webEx = $_.Exception
        if ($null -ne $webEx.Response) {
            $response = $webEx.Response
            try {
                $statusCode = [int]$response.StatusCode
                $body = Read-ResponseBody -Response $response
                return [pscustomobject]@{
                    StatusCode = $statusCode
                    Headers    = $response.Headers
                    Body       = $body
                    Error      = $webEx.Message
                }
            }
            finally { $response.Close() }
        }
        return [pscustomobject]@{
            StatusCode = $null
            Headers    = $null
            Body       = ''
            Error      = $webEx.Message
        }
    }
}

function Sleep-BeforeRequestIfNeeded {
    if ($MinDelayMs -le 0) { return }
    if ($script:LastRequestUtc -eq [DateTime]::MinValue) { return }
    $elapsed = ((Get-Date).ToUniversalTime() - $script:LastRequestUtc).TotalMilliseconds
    $remaining = $MinDelayMs - [int]$elapsed
    if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
}

function Sleep-ForRateLimitHeaders {
    param([Parameter(Mandatory=$false)]$Headers)
    $remainingRaw = Get-HeaderValue -Headers $Headers -Name 'anthropic-ratelimit-requests-remaining'
    $resetRaw = Get-HeaderValue -Headers $Headers -Name 'anthropic-ratelimit-requests-reset'
    if ([string]::IsNullOrWhiteSpace($remainingRaw) -or [string]::IsNullOrWhiteSpace($resetRaw)) { return }
    $remaining = 0
    if (-not [int]::TryParse($remainingRaw, [ref]$remaining)) { return }
    if ($remaining -gt $ThrottleWhenRemainingBelow) { return }
    try {
        $resetUtc = ([DateTimeOffset]::Parse($resetRaw, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).UtcDateTime
        $sleepSec = [Math]::Ceiling(($resetUtc - (Get-Date).ToUniversalTime()).TotalSeconds) + 1
        if ($sleepSec -gt 0) {
            Write-Log -Level 'WARN' -Message "Rate-limit 残数が少ないためリセットまで待機します。remaining=$remaining reset=$resetRaw sleep=${sleepSec}s"
            Start-Sleep -Seconds $sleepSec
        }
    } catch { }
}

function Invoke-ClaudeGet {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$false)]$QueryPairs,
        [Parameter(Mandatory=$false)][string]$Accept = 'application/json',
        [Parameter(Mandatory=$false)][switch]$AllowNotFound
    )
    $url = New-ClaudeUrl -Path $Path -QueryPairs $QueryPairs
    $attempt = 0
    while ($true) {
        Sleep-BeforeRequestIfNeeded
        $script:LastRequestUtc = (Get-Date).ToUniversalTime()
        $resp = Invoke-HttpGetRaw -Url $url -Accept $Accept
        $script:Stats.api_requests++

        $requestId = Get-HeaderValue -Headers $resp.Headers -Name 'request-id'
        if (-not [string]::IsNullOrWhiteSpace($requestId)) {
            $script:Stats.last_request_id = $requestId
            if ($script:Stats.request_ids.Count -lt 2000) {
                $script:Stats.request_ids += $requestId
            }
        }
        $rateRemaining = Get-HeaderValue -Headers $resp.Headers -Name 'anthropic-ratelimit-requests-remaining'
        $rateReset = Get-HeaderValue -Headers $resp.Headers -Name 'anthropic-ratelimit-requests-reset'
        $retryAfter = Get-HeaderValue -Headers $resp.Headers -Name 'retry-after'
        Write-RequestLog -Record @{
            timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
            run_id = $script:RunId
            endpoint = $Path
            status_code = $resp.StatusCode
            request_id = $requestId
            rate_remaining = $rateRemaining
            rate_reset = $rateReset
            retry_after = $retryAfter
            attempt = $attempt
        }

        if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
            Sleep-ForRateLimitHeaders -Headers $resp.Headers
            return [pscustomobject]@{
                StatusCode = $resp.StatusCode
                Headers    = $resp.Headers
                Body       = $resp.Body
                RequestId  = $requestId
            }
        }

        if ($AllowNotFound -and $resp.StatusCode -eq 404) {
            $script:Stats.content_not_found++
            return [pscustomobject]@{
                StatusCode = $resp.StatusCode
                Headers    = $resp.Headers
                Body       = $resp.Body
                RequestId  = $requestId
            }
        }

        if ($resp.StatusCode -eq 401 -or $resp.StatusCode -eq 403) {
            throw "HTTP $($resp.StatusCode): APIキー不正または権限不足です。checkpoint は更新しません。request-id=$requestId body=$($resp.Body)"
        }

        if ($resp.StatusCode -eq 429) {
            $script:Stats.rate_limit_429_count++
            $sleepSeconds = 0
            if (-not [string]::IsNullOrWhiteSpace($retryAfter)) {
                [int]::TryParse($retryAfter, [ref]$sleepSeconds) | Out-Null
            }
            if ($sleepSeconds -le 0) {
                $sleepSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt))
            }
            Write-Log -Level 'WARN' -Message "HTTP 429。retry-after に従って同じ checkpoint で再試行します。sleep=${sleepSeconds}s request-id=$requestId"
            Start-Sleep -Seconds $sleepSeconds
        }
        elseif ($resp.StatusCode -eq $null -or $resp.StatusCode -eq 502 -or $resp.StatusCode -eq 503 -or $resp.StatusCode -eq 504 -or $resp.StatusCode -eq 529) {
            $sleepSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt))
            Write-Log -Level 'WARN' -Message "一時的な通信/APIエラー。HTTP=$($resp.StatusCode) sleep=${sleepSeconds}s request-id=$requestId error=$($resp.Error)"
            Start-Sleep -Seconds $sleepSeconds
        }
        elseif ($resp.StatusCode -eq 500) {
            $shouldRetry = Get-HeaderValue -Headers $resp.Headers -Name 'x-should-retry'
            if ($shouldRetry -ieq 'false') {
                throw "HTTP 500 かつ x-should-retry=false。checkpoint は更新しません。request-id=$requestId body=$($resp.Body)"
            }
            $sleepSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt))
            Write-Log -Level 'WARN' -Message "HTTP 500。x-should-retry=false ではないため同じ checkpoint で再試行します。sleep=${sleepSeconds}s request-id=$requestId"
            Start-Sleep -Seconds $sleepSeconds
        }
        else {
            throw "HTTP $($resp.StatusCode): 再試行対象外の API エラーです。checkpoint は更新しません。request-id=$requestId body=$($resp.Body)"
        }

        $attempt++
        $script:Stats.retry_count++
        if ($attempt -gt $MaxRetries) {
            throw "最大リトライ回数を超過しました。checkpoint は更新しません。endpoint=$Path last_status=$($resp.StatusCode) request-id=$requestId"
        }
    }
}

# -----------------------------
# JSON helpers
# -----------------------------
function Get-RawJsonArrayItems {
    param(
        [Parameter(Mandatory=$true)][string]$Json,
        [Parameter(Mandatory=$false)][string]$PropertyName = 'data'
    )
    $pattern = '"' + [Regex]::Escape($PropertyName) + '"\s*:\s*\['
    $match = [Regex]::Match($Json, $pattern)
    if (-not $match.Success) {
        throw "JSON response 内に配列プロパティ '$PropertyName' が見つかりません。"
    }

    $items = New-Object System.Collections.Generic.List[string]
    $i = $match.Index + $match.Length
    $depth = 0
    $itemStart = -1
    $inString = $false
    $escape = $false

    while ($i -lt $Json.Length) {
        $ch = $Json[$i]
        if ($inString) {
            if ($escape) { $escape = $false }
            elseif ($ch -eq '\') { $escape = $true }
            elseif ($ch -eq '"') { $inString = $false }
            $i++
            continue
        }

        if ($ch -eq '"') { $inString = $true; $i++; continue }
        if ($ch -eq '{') {
            if ($depth -eq 0) { $itemStart = $i }
            $depth++
        }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0 -and $itemStart -ge 0) {
                $items.Add($Json.Substring($itemStart, $i - $itemStart + 1))
                $itemStart = -1
            }
            elseif ($depth -lt 0) {
                throw "JSON array extraction failed: object depth became negative."
            }
        }
        elseif ($ch -eq ']' -and $depth -eq 0) {
            break
        }
        $i++
    }
    return $items
}

function New-ContentMissingRecordJson {
    param(
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceId,
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [Parameter(Mandatory=$false)][string]$RequestId,
        [Parameter(Mandatory=$false)][string]$Body
    )
    $record = [ordered]@{
        resource_type = $ResourceType
        resource_id = $ResourceId
        endpoint = $Endpoint
        retrieved_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        status_code = 404
        request_id = $RequestId
        response_body = $Body
    }
    return ($record | ConvertTo-Json -Depth 20 -Compress)
}

function Save-ContentMissingRecord {
    param(
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceId,
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [Parameter(Mandatory=$false)][string]$RequestId,
        [Parameter(Mandatory=$false)][string]$Body
    )
    $date = (Get-Date).ToUniversalTime()
    $json = New-ContentMissingRecordJson -ResourceType $ResourceType -ResourceId $ResourceId -Endpoint $Endpoint -RequestId $RequestId -Body $Body
    $key = "$ResourceType|$ResourceId|404|" + (Get-Sha256Hex $Body)
    [void](Append-JsonLineDedup -Category 'content_missing' -DateUtc $date -Prefix 'content_missing' -UniqueKey $key -RawJsonLine $json)
}

# -----------------------------
# Activity Feed collection
# -----------------------------
function Save-ActivityItemsFromResponse {
    param([Parameter(Mandatory=$true)][string]$RawBody)
    $rawItems = Get-RawJsonArrayItems -Json $RawBody -PropertyName 'data'
    $saved = 0
    $duplicate = 0
    foreach ($raw in $rawItems) {
        $obj = $raw | ConvertFrom-Json
        $id = [string]$obj.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw "Activity object に id がありません。checkpoint は更新しません。"
        }
        $date = Get-DateFromRfc3339OrNow -Value ([string]$obj.created_at)
        $ok = Append-JsonLineDedup -Category 'activities' -DateUtc $date -Prefix 'activities' -UniqueKey $id -RawJsonLine $raw -RebuildActivityIndex
        if ($ok) { $saved++ } else { $duplicate++ }
    }
    $script:Stats.activity_fetched += $rawItems.Count
    $script:Stats.activity_saved += $saved
    $script:Stats.activity_duplicate += $duplicate
    return [pscustomobject]@{ fetched = $rawItems.Count; saved = $saved; duplicate = $duplicate }
}

function Collect-Activities {
    param([Parameter(Mandatory=$true)][ValidateSet('Backfill','Tail')][string]$Direction)

    $state = Load-State
    $script:Stats.start_checkpoint = [ordered]@{
        activity_first_id = $state.activity_first_id
        activity_last_id = $state.activity_last_id
        activity_backfill_complete = $state.activity_backfill_complete
    }

    if ($Direction -eq 'Tail' -and [string]::IsNullOrWhiteSpace([string]$state.activity_first_id)) {
        throw "ActivityTail には activity_first_id checkpoint が必要です。先に ActivityBackfill を実行してください。"
    }

    $cursor = $null
    if ($Direction -eq 'Backfill') { $cursor = [string]$state.activity_last_id } else { $cursor = [string]$state.activity_first_id }
    $newTailFirstId = [string]$state.activity_first_id
    $pageNo = 0

    Write-Log -Level 'INFO' -Message "Activity $Direction 開始。cursor=$cursor limit=$ActivityLimit"

    while ($true) {
        $pageNo++
        $query = @(@{ Name='limit'; Value=$ActivityLimit })
        if (-not [string]::IsNullOrWhiteSpace($cursor)) {
            if ($Direction -eq 'Backfill') { $query += @{ Name='after_id'; Value=$cursor } }
            else { $query += @{ Name='before_id'; Value=$cursor } }
        }

        $resp = Invoke-ClaudeGet -Path '/v1/compliance/activities' -QueryPairs $query
        $json = $resp.Body | ConvertFrom-Json
        $result = Save-ActivityItemsFromResponse -RawBody $resp.Body
        Write-Log -Level 'INFO' -Message "Activity page saved. direction=$Direction page=$pageNo fetched=$($result.fetched) saved=$($result.saved) duplicate=$($result.duplicate) has_more=$($json.has_more) first_id=$($json.first_id) last_id=$($json.last_id) request-id=$($resp.RequestId)"

        if ($Direction -eq 'Backfill') {
            if ([string]::IsNullOrWhiteSpace([string]$state.activity_first_id) -and -not [string]::IsNullOrWhiteSpace([string]$json.first_id)) {
                $state.activity_first_id = [string]$json.first_id
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$json.last_id)) {
                $state.activity_last_id = [string]$json.last_id
                $cursor = [string]$json.last_id
            }
            if (-not [bool]$json.has_more) {
                $state.activity_backfill_complete = $true
            }
            # Safe for backfill: this page has already been stored, so the older-cursor may be persisted now.
            Save-State -State $state
            if (-not [bool]$json.has_more) { break }
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace([string]$json.first_id)) {
                $newTailFirstId = [string]$json.first_id
                $cursor = [string]$json.first_id
            }
            # For tail, persist only after has_more=false so newer unread pages are not skipped.
            if (-not [bool]$json.has_more) {
                $state.activity_first_id = $newTailFirstId
                Save-State -State $state
                break
            }
        }
    }

    $state = Load-State
    $script:Stats.end_checkpoint = [ordered]@{
        activity_first_id = $state.activity_first_id
        activity_last_id = $state.activity_last_id
        activity_backfill_complete = $state.activity_backfill_complete
    }
    Write-Log -Level 'INFO' -Message "Activity $Direction 完了。first_id=$($state.activity_first_id) last_id=$($state.activity_last_id) backfill_complete=$($state.activity_backfill_complete)"
}

# -----------------------------
# Chat and message collection
# -----------------------------
function Get-JsonPropertyNames {
    param([Parameter(Mandatory=$true)]$Object)
    return @($Object.PSObject.Properties.Name)
}

function Save-TextContentWrapper {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][datetime]$DateUtc,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [Parameter(Mandatory=$true)][string]$UniqueKey,
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceId,
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [Parameter(Mandatory=$false)][string]$RequestId,
        [Parameter(Mandatory=$false)][string]$ContentType,
        [Parameter(Mandatory=$true)][string]$Body
    )
    $record = [ordered]@{
        resource_type = $ResourceType
        resource_id = $ResourceId
        endpoint = $Endpoint
        retrieved_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        request_id = $RequestId
        content_type = $ContentType
        content_sha256 = Get-Sha256Hex $Body
        content = $Body
    }
    $json = $record | ConvertTo-Json -Depth 30 -Compress
    return (Append-JsonLineDedup -Category $Category -DateUtc $DateUtc -Prefix $Prefix -UniqueKey $UniqueKey -RawJsonLine $json)
}

function Collect-ArtifactText {
    param(
        [Parameter(Mandatory=$true)][string]$ArtifactVersionId,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    if ($SkipArtifactText) { return }
    if ([string]::IsNullOrWhiteSpace($ArtifactVersionId)) { return }
    if (Test-CompleteKey -Name 'artifact_versions' -Key $ArtifactVersionId) { return }

    $idEsc = Escape-PathSegment -Value $ArtifactVersionId
    $path = "/v1/compliance/apps/artifacts/$idEsc/content"
    $resp = Invoke-ClaudeGet -Path $path -Accept 'text/plain,application/json' -AllowNotFound
    if ($resp.StatusCode -eq 404) {
        Save-ContentMissingRecord -ResourceType 'artifact_version' -ResourceId $ArtifactVersionId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
        Mark-CompleteKey -Name 'artifact_versions' -Key $ArtifactVersionId
        return
    }

    $hash = Get-Sha256Hex $resp.Body
    $key = "$ArtifactVersionId|$hash"
    $contentType = Get-HeaderValue -Headers $resp.Headers -Name 'Content-Type'
    $ok = Save-TextContentWrapper -Category 'artifacts' -DateUtc $DateUtc -Prefix 'artifacts' -UniqueKey $key -ResourceType 'artifact_version' -ResourceId $ArtifactVersionId -Endpoint $path -RequestId $resp.RequestId -ContentType $contentType -Body $resp.Body
    if ($ok) { $script:Stats.artifact_text_saved++ }
    Mark-CompleteKey -Name 'artifact_versions' -Key $ArtifactVersionId
}

function Collect-ArtifactsFromChatMessagePage {
    param(
        [Parameter(Mandatory=$true)]$ChatMessagePage,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    if ($SkipArtifactText) { return }
    if (-not (Get-JsonPropertyNames -Object $ChatMessagePage | Where-Object { $_ -eq 'chat_messages' })) { return }
    foreach ($msg in @($ChatMessagePage.chat_messages)) {
        if ($null -eq $msg) { continue }
        if (-not (Get-JsonPropertyNames -Object $msg | Where-Object { $_ -eq 'artifacts' })) { continue }
        if ($null -eq $msg.artifacts) { continue }
        foreach ($artifact in @($msg.artifacts)) {
            if ($null -eq $artifact) { continue }
            $versionId = $null
            if (Get-JsonPropertyNames -Object $artifact | Where-Object { $_ -eq 'version_id' }) { $versionId = [string]$artifact.version_id }
            if (-not [string]::IsNullOrWhiteSpace($versionId)) {
                Collect-ArtifactText -ArtifactVersionId $versionId -DateUtc $DateUtc
            }
        }
    }
}

function Collect-ChatMessages {
    param(
        [Parameter(Mandatory=$true)][string]$ChatId,
        [Parameter(Mandatory=$false)][string]$ChatUpdatedAt,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    $chatEsc = Escape-PathSegment -Value $ChatId
    $path = "/v1/compliance/apps/chats/$chatEsc/messages"
    $cursor = $null
    $pageNo = 0
    while ($true) {
        $pageNo++
        $query = @(
            @{ Name='limit'; Value=$ChatMessagesLimit },
            @{ Name='order'; Value='asc' }
        )
        if (-not [string]::IsNullOrWhiteSpace($cursor)) { $query += @{ Name='after_id'; Value=$cursor } }
        $resp = Invoke-ClaudeGet -Path $path -QueryPairs $query -AllowNotFound
        if ($resp.StatusCode -eq 404) {
            Save-ContentMissingRecord -ResourceType 'chat' -ResourceId $ChatId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
            return
        }
        $json = $resp.Body | ConvertFrom-Json
        $first = [string]$json.first_id
        $last = [string]$json.last_id
        $key = "$ChatId|$ChatUpdatedAt|$pageNo|$first|$last"
        $ok = Append-JsonLineDedup -Category 'chat_messages' -DateUtc $DateUtc -Prefix 'chat_messages' -UniqueKey $key -RawJsonLine $resp.Body
        if ($ok) { $script:Stats.chat_message_pages_saved++ }

        Collect-ArtifactsFromChatMessagePage -ChatMessagePage $json -DateUtc $DateUtc

        Write-Log -Level 'INFO' -Message "Chat messages page saved. chat_id=$ChatId page=$pageNo has_more=$($json.has_more) first_id=$first last_id=$last request-id=$($resp.RequestId)"
        if (-not [string]::IsNullOrWhiteSpace($last)) { $cursor = $last }
        if (-not [bool]$json.has_more) { break }
    }
}

function Collect-Chats {
    $state = Load-State
    $script:Stats.start_checkpoint = [ordered]@{
        chat_last_id = $state.chat_last_id
        chat_backfill_complete = $state.chat_backfill_complete
    }

    $cursor = [string]$state.chat_last_id
    $pageNo = 0
    Write-Log -Level 'INFO' -Message "Chat content collection 開始。cursor=$cursor limit=$ChatListLimit"

    while ($true) {
        $pageNo++
        $query = @(
            @{ Name='order_by'; Value='updated_at' },
            @{ Name='limit'; Value=$ChatListLimit }
        )
        if (-not [string]::IsNullOrWhiteSpace($cursor)) { $query += @{ Name='after_id'; Value=$cursor } }
        $resp = Invoke-ClaudeGet -Path '/v1/compliance/apps/chats' -QueryPairs $query
        $json = $resp.Body | ConvertFrom-Json
        $rawChats = Get-RawJsonArrayItems -Json $resp.Body -PropertyName 'data'

        foreach ($rawChat in $rawChats) {
            $chat = $rawChat | ConvertFrom-Json
            $chatId = [string]$chat.id
            if ([string]::IsNullOrWhiteSpace($chatId)) { throw "Chat metadata に id がありません。checkpoint は更新しません。" }
            $updatedAt = [string]$chat.updated_at
            $createdAt = [string]$chat.created_at
            $date = Get-DateFromRfc3339OrNow -Value $(if (-not [string]::IsNullOrWhiteSpace($updatedAt)) { $updatedAt } else { $createdAt })
            $versionKey = "$chatId|$updatedAt"
            $script:Stats.chat_list_items++
            $ok = Append-JsonLineDedup -Category 'chats' -DateUtc $date -Prefix 'chats' -UniqueKey $versionKey -RawJsonLine $rawChat
            if ($ok) { $script:Stats.chat_metadata_saved++ }

            if (Test-CompleteKey -Name 'chat_versions' -Key $versionKey) {
                continue
            }
            Collect-ChatMessages -ChatId $chatId -ChatUpdatedAt $updatedAt -DateUtc $date
            Mark-CompleteKey -Name 'chat_versions' -Key $versionKey
        }

        Write-Log -Level 'INFO' -Message "Chat list page processed. page=$pageNo items=$($rawChats.Count) has_more=$($json.has_more) last_id=$($json.last_id) request-id=$($resp.RequestId)"

        if (-not [string]::IsNullOrWhiteSpace([string]$json.last_id)) {
            # Safe: every chat in this list page and its message pages have been stored or recorded as unavailable.
            $state.chat_last_id = [string]$json.last_id
            $cursor = [string]$json.last_id
            Save-State -State $state
        }
        if (-not [bool]$json.has_more) {
            $state.chat_backfill_complete = $true
            Save-State -State $state
            break
        }
    }

    $state = Load-State
    $script:Stats.end_checkpoint = [ordered]@{
        chat_last_id = $state.chat_last_id
        chat_backfill_complete = $state.chat_backfill_complete
    }
    Write-Log -Level 'INFO' -Message "Chat content collection 完了。chat_last_id=$($state.chat_last_id) chat_backfill_complete=$($state.chat_backfill_complete)"
}

# -----------------------------
# Project collection
# -----------------------------
function Collect-ProjectDocumentContent {
    param(
        [Parameter(Mandatory=$true)][string]$DocumentId,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    if ([string]::IsNullOrWhiteSpace($DocumentId)) { return }
    if (Test-CompleteKey -Name 'project_documents' -Key $DocumentId) { return }

    $docEsc = Escape-PathSegment -Value $DocumentId
    $path = "/v1/compliance/apps/projects/documents/$docEsc"
    $resp = Invoke-ClaudeGet -Path $path -Accept 'application/json,text/plain' -AllowNotFound
    if ($resp.StatusCode -eq 404) {
        Save-ContentMissingRecord -ResourceType 'project_document' -ResourceId $DocumentId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
        Mark-CompleteKey -Name 'project_documents' -Key $DocumentId
        return
    }

    $hash = Get-Sha256Hex $resp.Body
    $key = "$DocumentId|$hash"
    $contentType = Get-HeaderValue -Headers $resp.Headers -Name 'Content-Type'
    $ok = Save-TextContentWrapper -Category 'project_documents' -DateUtc $DateUtc -Prefix 'project_documents' -UniqueKey $key -ResourceType 'project_document' -ResourceId $DocumentId -Endpoint $path -RequestId $resp.RequestId -ContentType $contentType -Body $resp.Body
    if ($ok) { $script:Stats.project_documents_saved++ }
    Mark-CompleteKey -Name 'project_documents' -Key $DocumentId
}

function Collect-ProjectDetails {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectId,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    $projEsc = Escape-PathSegment -Value $ProjectId
    $path = "/v1/compliance/apps/projects/$projEsc"
    $resp = Invoke-ClaudeGet -Path $path -AllowNotFound
    if ($resp.StatusCode -eq 404) {
        Save-ContentMissingRecord -ResourceType 'project' -ResourceId $ProjectId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
        return
    }
    $hash = Get-Sha256Hex $resp.Body
    $key = "$ProjectId|$hash"
    $ok = Append-JsonLineDedup -Category 'project_details' -DateUtc $DateUtc -Prefix 'project_details' -UniqueKey $key -RawJsonLine $resp.Body
    if ($ok) { $script:Stats.project_records_saved++ }
}

function Collect-ProjectAttachments {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectId,
        [Parameter(Mandatory=$true)][datetime]$ProjectDateUtc
    )
    $projEsc = Escape-PathSegment -Value $ProjectId
    $path = "/v1/compliance/apps/projects/$projEsc/attachments"
    $pageToken = $null
    $pageNo = 0
    while ($true) {
        $pageNo++
        $query = @(@{ Name='limit'; Value=$ProjectAttachmentsLimit })
        if (-not [string]::IsNullOrWhiteSpace($pageToken)) { $query += @{ Name='page'; Value=$pageToken } }
        $resp = Invoke-ClaudeGet -Path $path -QueryPairs $query -AllowNotFound
        if ($resp.StatusCode -eq 404) {
            Save-ContentMissingRecord -ResourceType 'project_attachments' -ResourceId $ProjectId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
            return
        }
        $json = $resp.Body | ConvertFrom-Json
        $rawItems = Get-RawJsonArrayItems -Json $resp.Body -PropertyName 'data'
        foreach ($raw in $rawItems) {
            $att = $raw | ConvertFrom-Json
            $attId = [string]$att.id
            $attType = [string]$att.type
            $createdAt = [string]$att.created_at
            $date = Get-DateFromRfc3339OrNow -Value $(if (-not [string]::IsNullOrWhiteSpace($createdAt)) { $createdAt } else { $ProjectDateUtc.ToString('o') })
            $script:Stats.project_attachments_seen++
            $key = "$ProjectId|$attId|$attType|$createdAt"
            [void](Append-JsonLineDedup -Category 'project_attachments' -DateUtc $date -Prefix 'project_attachments' -UniqueKey $key -RawJsonLine $raw)

            if ($attType -eq 'project_doc') {
                Collect-ProjectDocumentContent -DocumentId $attId -DateUtc $date
            }
            elseif ($attType -eq 'project_file') {
                # Intentionally do not call file content endpoints. Metadata is already stored above.
                $script:Stats.file_binaries_skipped++
            }
            else {
                # Forward-compatible: store raw metadata and continue.
                Write-Log -Level 'WARN' -Message "未知の project attachment type です。raw metadata は保存済みのため処理を継続します。project_id=$ProjectId attachment_id=$attId type=$attType"
            }
        }
        Write-Log -Level 'INFO' -Message "Project attachments page processed. project_id=$ProjectId page=$pageNo items=$($rawItems.Count) has_more=$($json.has_more) request-id=$($resp.RequestId)"
        if (-not [bool]$json.has_more) { break }
        $pageToken = [string]$json.next_page
        if ([string]::IsNullOrWhiteSpace($pageToken)) { break }
    }
}

function Collect-Projects {
    if ($SkipProjectFullScan) {
        Write-Log -Level 'INFO' -Message 'SkipProjectFullScan が指定されたため project collection をスキップします。'
        return
    }

    Write-Log -Level 'INFO' -Message "Project full scan 開始。limit=$ProjectListLimit"
    $pageToken = $null
    $pageNo = 0
    while ($true) {
        $pageNo++
        $query = @(@{ Name='limit'; Value=$ProjectListLimit })
        if (-not [string]::IsNullOrWhiteSpace($pageToken)) { $query += @{ Name='page'; Value=$pageToken } }
        $resp = Invoke-ClaudeGet -Path '/v1/compliance/apps/projects' -QueryPairs $query
        $json = $resp.Body | ConvertFrom-Json
        $rawProjects = Get-RawJsonArrayItems -Json $resp.Body -PropertyName 'data'
        foreach ($rawProject in $rawProjects) {
            $project = $rawProject | ConvertFrom-Json
            $projectId = [string]$project.id
            if ([string]::IsNullOrWhiteSpace($projectId)) { throw "Project metadata に id がありません。" }
            $createdAt = $null
            if (Get-JsonPropertyNames -Object $project | Where-Object { $_ -eq 'created_at' }) { $createdAt = [string]$project.created_at }
            $date = Get-DateFromRfc3339OrNow -Value $createdAt
            $script:Stats.projects_seen++
            $key = "$projectId|$createdAt|" + (Get-Sha256Hex $rawProject)
            $ok = Append-JsonLineDedup -Category 'projects' -DateUtc $date -Prefix 'projects' -UniqueKey $key -RawJsonLine $rawProject
            if ($ok) { $script:Stats.project_records_saved++ }

            Collect-ProjectDetails -ProjectId $projectId -DateUtc $date
            Collect-ProjectAttachments -ProjectId $projectId -ProjectDateUtc $date
        }
        Write-Log -Level 'INFO' -Message "Project list page processed. page=$pageNo items=$($rawProjects.Count) has_more=$($json.has_more) request-id=$($resp.RequestId)"
        if (-not [bool]$json.has_more) { break }
        $pageToken = [string]$json.next_page
        if ([string]::IsNullOrWhiteSpace($pageToken)) { break }
    }
    $state = Load-State
    $state.project_last_full_scan_utc = (Get-Date).ToUniversalTime().ToString('o')
    Save-State -State $state
    Write-Log -Level 'INFO' -Message 'Project full scan 完了。'
}

function Collect-Content {
    Collect-Chats
    Collect-Projects
}

# -----------------------------
# Status and finalization
# -----------------------------
function Write-StatusFiles {
    param([Parameter(Mandatory=$true)][string]$Status)
    $script:Stats.status = $Status
    $script:Stats.end_utc = (Get-Date).ToUniversalTime().ToString('o')
    $script:Stats.duration_seconds = [Math]::Round(((Get-Date).ToUniversalTime() - $script:RunStartUtc).TotalSeconds, 3)
    $json = $script:Stats | ConvertTo-Json -Depth 50
    $summaryPath = Join-Path (Join-Path $Root 'logs') ("summary_$($script:RunId).json")
    Write-TextFileAtomic -Path $summaryPath -Content $json
    $latestPath = Join-Path (Join-Path $Root 'state') 'latest_status.json'
    Write-TextFileAtomic -Path $latestPath -Content $json
    if ($Status -eq 'success') {
        $successPath = Join-Path (Join-Path $Root 'state') 'latest_success.json'
        Write-TextFileAtomic -Path $successPath -Content $json
    }
}

function Show-Status {
    $checkpoint = Get-StatePath
    $latest = Join-Path (Join-Path $Root 'state') 'latest_status.json'
    Write-Host "Root: $Root"
    if (Test-Path -LiteralPath $checkpoint) {
        Write-Host "Checkpoint:"
        Get-Content -LiteralPath $checkpoint -Encoding UTF8 | Write-Host
    } else {
        Write-Host 'Checkpoint: not found'
    }
    if (Test-Path -LiteralPath $latest) {
        Write-Host "Latest status:"
        Get-Content -LiteralPath $latest -Encoding UTF8 | Write-Host
    } else {
        Write-Host 'Latest status: not found'
    }
}

# -----------------------------
# Main
# -----------------------------
try {
    Initialize-Folders
    if ($Mode -eq 'Status') {
        Show-Status
        exit 0
    }

    Acquire-CollectorLock
    Initialize-Tls

    $script:ApiKey = Get-EnvVarValue -Name $ApiKeyEnvName
    if ([string]::IsNullOrWhiteSpace($script:ApiKey)) {
        throw "環境変数 '$ApiKeyEnvName' から API キーを取得できません。スクリプトには API キーを直書きしないでください。"
    }

    Write-Log -Level 'INFO' -Message "Claude Compliance Collector 開始。run_id=$($script:RunId) mode=$Mode root=$Root api_key_env=$ApiKeyEnvName pid=$PID"

    switch ($Mode) {
        'ActivityBackfill' { Collect-Activities -Direction 'Backfill' }
        'ActivityTail'     { Collect-Activities -Direction 'Tail' }
        'ContentBackfill'  { Collect-Content }
        'ContentTail'      { Collect-Content }
        'AllBackfill'      { Collect-Activities -Direction 'Backfill'; Collect-Content }
        'AllTail'          { Collect-Activities -Direction 'Tail'; Collect-Content }
        default            { throw "Unsupported mode: $Mode" }
    }

    $state = Load-State
    $state.last_success_utc = (Get-Date).ToUniversalTime().ToString('o')
    $state.last_success_mode = $Mode
    Save-State -State $state
    $script:Stats.last_success_utc = $state.last_success_utc
    Write-StatusFiles -Status 'success'
    Write-Log -Level 'INFO' -Message "Claude Compliance Collector 正常終了。run_id=$($script:RunId) activity_saved=$($script:Stats.activity_saved) activity_duplicate=$($script:Stats.activity_duplicate) retries=$($script:Stats.retry_count) 429=$($script:Stats.rate_limit_429_count) errors=$($script:Stats.error_count)"
    exit 0
}
catch {
    $script:Stats.error_count++
    $script:Stats.error = [ordered]@{
        message = $_.Exception.Message
        type = $_.Exception.GetType().FullName
        script_stack_trace = $_.ScriptStackTrace
    }
    try { Write-StatusFiles -Status 'error' } catch { }
    try { Write-Log -Level 'ERROR' -Message "異常終了。checkpoint は失敗位置より先へ進めません。run_id=$($script:RunId) error=$($_.Exception.Message)" } catch { }
    exit 1
}
finally {
    Release-CollectorLock
}
