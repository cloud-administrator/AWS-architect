#requires -Version 7.6
<#
Collect-ClaudeCompliance.ps1
Windows / PowerShell 7.6 LTS / local NTFS. No additional PowerShell module.
Read-only: only GET, fixed api.anthropic.com host, no /content downloads.
Documentation reviewed: 2026-09-08. See README.ja.md before production use.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Backfill','Tail')][string]$Mode,
    [string]$ConfigPath = 'C:\ClaudeComplianceCollector\config\collector.config.json'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Framework assemblies shipped with PowerShell; no third-party installation.
Add-Type -AssemblyName System.Text.Json
Add-Type -AssemblyName System.Net.Http
$script:Root = 'C:\ClaudeComplianceCollector'
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:State = $null
$script:Client = $null
$script:Lock = $null
$script:Config = $null
$script:Seq = 0L
$script:Chain = ''
$script:ReceiptHashes = @{}
$script:EventIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:BodyIndex = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
$script:NextRequest = [DateTimeOffset]::MinValue
$script:RunId = [Guid]::NewGuid().ToString('N')
$script:Started = [DateTimeOffset]::UtcNow
$script:Clock = [Diagnostics.Stopwatch]::StartNew()
$script:LastApi = @{}
$script:Metrics = [ordered]@{
    activity_received=0L; activity_saved=0L; activity_duplicates=0L
    body_responses_received=0L; body_responses_saved=0L; body_response_duplicates=0L
    chat_messages_received=0L; chat_messages_in_new_responses=0L
    chats_walked=0L; projects_walked=0L; project_docs_received=0L
    unavailable_responses=0L; gap_findings=0L; warning_findings=0L
    errors=0L; retries=0L; http_429=0L; api_requests=0L
}

# All exception messages generated here are controlled codes, never HTTP bodies.
function Stop-Collector([string]$Code, [int]$ExitCode = 1) {
    $e = [InvalidOperationException]::new($Code)
    $e.Data['CollectorCode'] = $Code
    $e.Data['CollectorExit'] = $ExitCode
    throw $e
}
function Get-Utc { [DateTimeOffset]::UtcNow.ToString('o') }
function Get-Jst { [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(9)) }
function Get-Hash([byte[]]$Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
function Get-StringHash([string]$Text) { Get-Hash ($script:Utf8.GetBytes($Text)) }
function Convert-ControlJson($Value) {
    ConvertTo-Json -InputObject $Value -Depth 64 -Compress -WarningAction Stop
}
function Read-Control([string]$Path) {
    ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path, $script:Utf8)) `
        -AsHashtable -Depth 64 -DateKind String
}
function Parse-ApiJson([byte[]]$Bytes) {
    $opt = [Text.Json.JsonDocumentOptions]::new()
    $opt.MaxDepth = 2048  # Exceeding this is a hard failure, not silent truncation.
    [Text.Json.JsonDocument]::Parse($script:Utf8.GetString($Bytes), $opt)
}
function Get-J([Text.Json.JsonElement]$Value, [string]$Name) {
    $v = [Text.Json.JsonElement]::new()
    if ($Value.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        [void]$Value.TryGetProperty($Name, [ref]$v)
    }
    $v
}
function Get-JString([Text.Json.JsonElement]$Value, [string]$Name) {
    $v = Get-J $Value $Name
    if ($v.ValueKind -eq [Text.Json.JsonValueKind]::String) { $v.GetString() }
    else { $null }
}
function Require-Id([Text.Json.JsonElement]$Value, [string]$Name = 'id') {
    $id = Get-JString $Value $Name
    if ([string]::IsNullOrWhiteSpace($id)) { Stop-Collector "Schema_Missing_$Name" }
    $id
}
function Safe-Id([string]$Value) {
    if (!$Value) { return '' }
    if ($Value -cmatch '^[A-Za-z0-9_.:/=+\-]{1,512}$') { return $Value }
    'sha256:' + (Get-StringHash $Value)
}
function Test-Deleted([Text.Json.JsonElement]$Value) {
    ![string]::IsNullOrEmpty((Get-JString $Value 'deleted_at'))
}
function Get-Array([Text.Json.JsonElement]$Value, [string]$Name, [switch]$Required) {
    $a = Get-J $Value $Name
    if ($a.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($v in $a.EnumerateArray()) { $v }
    } elseif ($Required -or $a.ValueKind -notin @(
        [Text.Json.JsonValueKind]::Null, [Text.Json.JsonValueKind]::Undefined)) {
        Stop-Collector "Schema_Array_$Name"
    }
}
function Check-Scope([Text.Json.JsonElement]$Value) {
    $org = Require-Id $Value 'organization_uuid'
    if ($org -notin $script:Config.OrganizationUuids) { Stop-Collector 'Unexpected_Organization' }
}
function Write-DurableFile([string]$Path, [byte[]]$Bytes) {
    $f = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None, 65536, [IO.FileOptions]::WriteThrough)
    try { $f.Write($Bytes, 0, $Bytes.Length); $f.Flush($true) } finally { $f.Dispose() }
}
function Write-Atomic([string]$Path, [byte[]]$Bytes) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $tmp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    Write-DurableFile $tmp $Bytes
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, $null) }
    else { [IO.File]::Move($tmp, $Path) }
}
function Write-Control([string]$Path, $Value) {
    Write-Atomic $Path ($script:Utf8.GetBytes((Convert-ControlJson $Value)))
}
function Write-Log([string]$Event, $Fields = @{}, [switch]$ErrorLog) {
    $date = (Get-Jst).ToString('yyyyMMdd')
    $dir = Join-Path $script:Root 'logs'
    [void][IO.Directory]::CreateDirectory($dir)
    $row = @{ time_jst=(Get-Jst).ToString('o'); run_id=$script:RunId; event=$Event; fields=$Fields }
    $bytes = $script:Utf8.GetBytes((Convert-ControlJson $row) + "`n")
    $names = @("run_$date.txt")
    if ($ErrorLog) { $names += "error_$date.txt" }
    foreach ($name in $names) {
        $f = [IO.FileStream]::new((Join-Path $dir $name), [IO.FileMode]::Append,
            [IO.FileAccess]::Write, [IO.FileShare]::Read)
        try { $f.Write($bytes,0,$bytes.Length); $f.Flush($true) } finally { $f.Dispose() }
    }
}
function Save-Checkpoint {
    $script:State.archive_sequence = $script:Seq
    $script:State.archive_hash = $script:Chain
    Write-Control (Join-Path $script:Root 'state\checkpoint.json') $script:State
}
function Check-Budget {
    if ($script:Clock.Elapsed.TotalMinutes -ge $script:Config.MaxRunMinutes) {
        Stop-Collector 'Run_Budget_Reached' 3
    }
}
function Wait-Collector([double]$Seconds) {
    if ($Seconds -le 0) { return }
    if (($script:Clock.Elapsed.TotalSeconds + $Seconds) -ge
        (60 * $script:Config.MaxRunMinutes)) { Stop-Collector 'Run_Budget_Reached' 3 }
    # Sleep in short intervals; never cut short a required wait to send a request.
    $end = [DateTimeOffset]::UtcNow.AddSeconds($Seconds)
    while ([DateTimeOffset]::UtcNow -lt $end) {
        Check-Budget
        Start-Sleep -Milliseconds ([int][Math]::Max(1,[Math]::Min(1000,
            ($end-[DateTimeOffset]::UtcNow).TotalMilliseconds)))
    }
}
function Resolve-ArchivePath([string]$Relative) {
    $p = [IO.Path]::GetFullPath((Join-Path $script:Root $Relative))
    $prefix = $script:Root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (!$p.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Collector 'Archive_Path_Outside_Root'
    }
    $p
}

# An immutable directory is the commit unit: payload(s) + receipt, then rename.
# Receipts form a sequence/hash chain. Startup checks it AND the actual payloads.
function Publish-Record(
    [string]$Stream, [string]$Kind, $Job, [byte[]]$Bytes, $Info,
    [string]$CycleId = '', [switch]$NoPayload
) {
    $seq = $script:Seq + 1L
    $id = '{0:D12}_{1}' -f $seq, [Guid]::NewGuid().ToString('N')
    $jst = Get-Jst
    $relDir = 'data/{0}/{1}/{2}' -f $Stream, $jst.ToString('yyyy/MM/dd'), $id
    $dest = Resolve-ArchivePath $relDir
    $stage = Join-Path $script:Root ('staging/' + $id)
    [void][IO.Directory]::CreateDirectory($stage)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
    $payload = $null; $sha = $null; $isNew = $false; $key = $null
    if (!$NoPayload) {
        $sha = Get-Hash $Bytes
        if ($Stream -eq 'content') { $key = $Job.path + '|' + $sha }
        if ($key -and $script:BodyIndex.ContainsKey($key)) {
            $payload = $script:BodyIndex[$key]
        } else {
            $name = if ($Stream -eq 'raw') { 'activities_' + $jst.ToString('yyyyMMdd') + '.jsonl' }
                    elseif ($Stream -eq 'content') { 'response.json' } else { 'report.json' }
            $payload = "$relDir/$name"
            Write-DurableFile (Join-Path $stage $name) $Bytes
            $isNew = $true
        }
    }
    $record = [ordered]@{
        sequence=$seq; previous_receipt_sha256=$script:Chain
        stream=$Stream; kind=$Kind; cycle_id=$CycleId; run_id=$script:RunId
        collected_at_utc=(Get-Utc); collected_at_jst=$jst.ToString('o')
        request=@{ kind=$Job.kind; id=$Job.id; path=$Job.path; query=$Job.query; root_id=$Job.root_id }; info=$Info
        payload_ref=$payload; payload_sha256=$sha; payload_is_new=$isNew
    }
    $manifest = $script:Utf8.GetBytes((Convert-ControlJson $record))
    Write-DurableFile (Join-Path $stage 'receipt.json') $manifest
    [IO.Directory]::Move($stage, $dest)  # Same-volume publication; never append to a payload.
    $script:Seq = $seq
    $script:Chain = Get-Hash $manifest
    $script:ReceiptHashes[$seq] = $script:Chain
    if ($key -and !$script:BodyIndex.ContainsKey($key)) { $script:BodyIndex.Add($key,$payload) }
    @{ receipt_ref="$relDir/receipt.json"; payload_ref=$payload; is_new=$isNew; sha256=$sha }
}
function Verify-Archive {
    $data = Join-Path $script:Root 'data'
    if (![IO.Directory]::Exists($data)) { return }
    $checked = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $files = @(Get-ChildItem -LiteralPath $data -Recurse -File -Filter receipt.json |
        Sort-Object { [long]($_.Directory.Name.Split('_')[0]) })
    foreach ($file in $files) {
        Check-Budget
        $raw = [IO.File]::ReadAllBytes($file.FullName)
        $r = Read-Control $file.FullName
        if ([long]$r.sequence -ne ($script:Seq+1) -or
            $r.previous_receipt_sha256 -cne $script:Chain) { Stop-Collector 'Archive_Chain_Broken' }
        if ($r.payload_ref) {
            $p = Resolve-ArchivePath $r.payload_ref
            if (!$checked.ContainsKey($r.payload_ref)) {
                if (![IO.File]::Exists($p)) { Stop-Collector 'Archive_Payload_Missing' }
                $fs = [IO.File]::OpenRead($p)
                try { $h = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($fs)).ToLowerInvariant() }
                finally { $fs.Dispose() }
                $checked.Add($r.payload_ref,$h)
            }
            if ($checked[$r.payload_ref] -cne $r.payload_sha256) { Stop-Collector 'Archive_Hash_Mismatch' }
            if ($r.stream -eq 'raw') {
                foreach ($line in [IO.File]::ReadLines($p,$script:Utf8)) {
                    $d = Parse-ApiJson ($script:Utf8.GetBytes($line))
                    try {
                        $eid = Require-Id $d.RootElement
                        if (!$script:EventIds.Add($eid)) { Stop-Collector 'Archive_Duplicate_ActivityId' }
                    } finally { $d.Dispose() }
                }
            } elseif ($r.stream -eq 'content') {
                $key = $r.request.path + '|' + $r.payload_sha256
                if (!$script:BodyIndex.ContainsKey($key)) { $script:BodyIndex.Add($key,$r.payload_ref) }
            }
        }
        $script:Seq = [long]$r.sequence
        $script:Chain = Get-Hash $raw
        $script:ReceiptHashes[$script:Seq] = $script:Chain
    }
}
function Get-Header($Response, [string]$Name) {
    if ($Response.Headers.Contains($Name)) { return [string]::Join(',', $Response.Headers.GetValues($Name)) }
    if ($Response.Content.Headers.Contains($Name)) { return [string]::Join(',', $Response.Content.Headers.GetValues($Name)) }
    ''
}
function New-RequestUri($Job) {
    # URLs are constructed here, never taken from href, MCP URLs or file references.
    if ($Job.path -notmatch '^/v1/compliance/' -or $Job.path.EndsWith('/content') -or
        $Job.path.Contains('?') -or $Job.path.Contains('..')) { Stop-Collector 'Unsafe_Request_Path' }
    $pairs = [Collections.Generic.List[string]]::new()
    foreach ($k in @($Job.query.Keys | Sort-Object)) {
        foreach ($v in @($Job.query[$k])) {
            if ($null -ne $v -and [string]$v -ne '') {
                $pairs.Add([Uri]::EscapeDataString([string]$k)+'='+[Uri]::EscapeDataString([string]$v))
            }
        }
    }
    'https://api.anthropic.com' + $Job.path + $(if ($pairs.Count) { '?' + ($pairs -join '&') } else { '' })
}
function Send-Api($Job) {
    $uri = New-RequestUri $Job
    for ($attempt=0; $attempt -le $script:Config.MaxRetries; $attempt++) {
        Check-Budget
        if ($script:State.not_before_utc) {
            $nb = [DateTimeOffset]::Parse($script:State.not_before_utc)
            if ($nb -gt $script:NextRequest) { $script:NextRequest = $nb }
        }
        Wait-Collector (($script:NextRequest-[DateTimeOffset]::UtcNow).TotalSeconds)
        $script:NextRequest = [DateTimeOffset]::UtcNow.AddSeconds(60.0/$script:Config.RequestsPerMinute)
        $script:Metrics.api_requests++
        $response=$null; $bytes=$null; $netError=$false; $cts=[Threading.CancellationTokenSource]::new()
        $req=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$uri)
        $cts.CancelAfter([TimeSpan]::FromSeconds($script:Config.TimeoutSeconds))
        $script:LastApi = @{ kind=$Job.kind; resource_id=(Safe-Id $Job.id); path=$Job.path;
            attempt=($attempt+1); status=$null; request_id=''; error_type='' }
        try {
            try {
                $response=$script:Client.SendAsync($req,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,
                    $cts.Token).GetAwaiter().GetResult()
                $script:LastApi.status=[int]$response.StatusCode
                $script:LastApi.request_id=Safe-Id (Get-Header $response 'request-id')
                $bytes=$response.Content.ReadAsByteArrayAsync($cts.Token).GetAwaiter().GetResult()
            } catch {
                $base=$_.Exception.GetBaseException()
                if ($base -is [OutOfMemoryException]) { Stop-Collector 'Response_Exceeds_Local_Memory' }
                $netError=$true
                $script:LastApi.error_type=$base.GetType().FullName
            }
            $retry=$false; $hint=''; $status=$null
            $delay=[Math]::Min(60,[Math]::Pow(2,$attempt)) + (Get-Random -Minimum 0 -Maximum 500)/1000.0
            # Process headers even when reading the response BODY failed or timed out.
            if ($null -ne $response) {
                $status=[int]$response.StatusCode
                $h=(Get-Header $response 'x-should-retry').ToLowerInvariant()
                if ($h -in @('true','false')) { $hint=$h }
                $script:LastApi.retry_hint=$hint
                $remaining=0L; $limit=0L; $reset=[DateTimeOffset]::MinValue
                $remainingOk=[long]::TryParse((Get-Header $response 'anthropic-ratelimit-requests-remaining'),[ref]$remaining)
                if ([long]::TryParse((Get-Header $response 'anthropic-ratelimit-requests-limit'),[ref]$limit) -and $limit -gt 0) {
                    $candidate=[DateTimeOffset]::UtcNow.AddSeconds(60.0/[Math]::Min($limit,$script:Config.RequestsPerMinute))
                    if ($candidate -gt $script:NextRequest) { $script:NextRequest=$candidate }
                }
                if ($remainingOk -and $remaining -le 1 -and
                    [DateTimeOffset]::TryParse((Get-Header $response 'anthropic-ratelimit-requests-reset'),[ref]$reset)) {
                    if ($reset.AddSeconds(0.25) -gt $script:NextRequest) { $script:NextRequest=$reset.AddSeconds(0.25) }
                }
                if ($status -eq 429) {
                    $script:Metrics.http_429++
                    $ra=0.0
                    if ([double]::TryParse((Get-Header $response 'retry-after'),
                        [Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$ra) -and
                        [double]::IsFinite($ra) -and $ra -ge 0) { $delay=$ra }
                    $script:State.not_before_utc=[DateTimeOffset]::UtcNow.AddSeconds($delay).ToString('o')
                    Save-Checkpoint  # Only a wait deadline; no cursor/job advancement.
                }
            }
            if ($netError) {
                $retry=($status -notin @(401,403) -and $hint -ne 'false')
            } else {
                if ($status -ge 200 -and $status -lt 300) {
                    if ($status -ne 200) { Stop-Collector 'Unexpected_Success_Status' }
                    Write-Log 'api_response' $script:LastApi
                    return @{ bytes=$bytes; status=$status; meta=$script:LastApi.Clone() }
                }
                # No raw HTTP error message is logged: it could echo sensitive input.
                $script:LastApi.response_sha256=Get-Hash $bytes
                $ed=$null
                try {
                    $ed=Parse-ApiJson $bytes
                    $et=Get-JString (Get-J $ed.RootElement 'error') 'type'
                    if ($et -cmatch '^[a-z_]{1,80}$') { $script:LastApi.error_type=$et }
                } catch { $script:LastApi.error_type='unparseable_error_response' }
                finally { if ($null -ne $ed) { $ed.Dispose() } }
                if ($status -notin @(401,403)) {
                    if ($hint -eq 'true') { $retry=$true }
                    elseif ($hint -ne 'false' -and $status -in @(408,429,500,502,503,504,529)) { $retry=$true }
                }
                if ($status -eq 404 -and !$retry -and $Job.kind -notin @('activities','chats_list','projects_list')) {
                    $script:Metrics.unavailable_responses++
                    $script:Metrics.errors++
                    Write-Log 'resource_unavailable' $script:LastApi -ErrorLog
                    return @{ bytes=$null; status=404; meta=$script:LastApi.Clone() }
                }
            }
            $script:Metrics.errors++
            Write-Log 'api_error' $script:LastApi -ErrorLog
            if (!$retry) {
                if ($script:LastApi.status -in @(401,403)) { Stop-Collector 'Authentication_Or_Scope_Error' }
                Stop-Collector 'Non_Retryable_API_Error'
            }
            if ($attempt -ge $script:Config.MaxRetries) { Stop-Collector 'Retry_Limit_Reached' }
            $script:Metrics.retries++
            Write-Log 'retry' @{ resource_id=(Safe-Id $Job.id); wait_seconds=$delay; next_attempt=($attempt+2) }
        } finally {
            if ($null -ne $response) { $response.Dispose() }
            $req.Dispose(); $cts.Dispose()
        }
        Wait-Collector $delay
    }
    Stop-Collector 'Retry_Loop_Unexpected_End'
}

function New-Job([string]$Kind,[string]$Id,[string]$Path,$Query=@{},[string]$RootId='') {
    @{ kind=$Kind; id=$Id; path=$Path; query=$Query; root_id=$RootId; trail=@() }
}
function Copy-Job($Job) {
    # Only our shallow control objects, never an API response.
    ConvertFrom-Json -InputObject (Convert-ControlJson $Job) -AsHashtable -Depth 64 -DateKind String
}
function Get-Pagination([Text.Json.JsonElement]$Root,[string]$Scheme,[string]$ArrayName) {
    $a=Get-J $Root $ArrayName
    if ($a.ValueKind -ne [Text.Json.JsonValueKind]::Array) { Stop-Collector 'Schema_Page_Array' }
    $more=Get-J $Root 'has_more'
    if ($more.ValueKind -notin @([Text.Json.JsonValueKind]::True,[Text.Json.JsonValueKind]::False)) {
        Stop-Collector 'Schema_HasMore'
    }
    $p=@{ has_more=$more.GetBoolean(); count=$a.GetArrayLength();
        first_id=(Get-JString $Root 'first_id'); last_id=(Get-JString $Root 'last_id');
        next_page=(Get-JString $Root 'next_page') }
    if ($p.has_more -and ($p.count -eq 0 -or
        ($Scheme -eq 'page' -and !$p.next_page) -or
        ($Scheme -eq 'cursor' -and (!$p.first_id -or !$p.last_id)))) {
        Stop-Collector 'Schema_Missing_Page_Cursor'
    }
    if ($Scheme -eq 'cursor' -and $p.count -gt 0 -and (!$p.first_id -or !$p.last_id)) {
        Stop-Collector 'Schema_Missing_Page_Cursor'
    }
    $p
}
function Next-Job($Job,$Pagination,[string]$Parameter,[string]$Cursor) {
    if (!$Pagination.has_more) { return $null }
    if (!$Cursor -or $Cursor -in $Job.trail -or
        ($Job.query.Contains($Parameter) -and $Cursor -ceq $Job.query[$Parameter])) {
        Stop-Collector 'Pagination_Cycle'
    }
    $n=Copy-Job $Job
    $n.query[$Parameter]=$Cursor
    $n.trail=@(@($Job.trail | Select-Object -Last 63)+@($Cursor)) # Bounded cycle guard; run budget is an additional guard.
    $n
}
function Save-Activities($Job,$Reply,[Text.Json.JsonElement]$Root,$Pagination) {
    $new=[Collections.Generic.List[string]]::new()
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($v in (Get-Array $Root 'data' -Required)) {
        $id=Require-Id $v
        if (!$script:EventIds.Contains($id) -and $ids.Add($id)) {
            # Valid JSON cannot contain literal CR/LF inside a string. Only layout is removed.
            $new.Add($v.GetRawText().Replace("`r",'').Replace("`n",''))
        }
    }
    $received=$Pagination.count; $saved=$new.Count
    $script:Metrics.activity_received += $received
    $text=if ($saved) { ($new -join "`n")+"`n" } else { '' }
    $info=@{ http=$Reply.meta; pagination=$Pagination; received=$received; saved=$saved;
        duplicates=($received-$saved) }
    [void](Publish-Record 'raw' 'activities' $Job ($script:Utf8.GetBytes($text)) $info -NoPayload:($saved -eq 0))
    foreach ($id in $ids) { [void]$script:EventIds.Add($id) }
    $script:Metrics.activity_saved += $saved
    $script:Metrics.activity_duplicates += ($received-$saved)
}
function Activity-Page($Job) {
    $r=Send-Api $Job
    $d=Parse-ApiJson $r.bytes
    try {
        $p=Get-Pagination $d.RootElement 'cursor' 'data'
        Save-Activities $Job $r $d.RootElement $p
        $p
    } finally { $d.Dispose() }
}
function Activity-Query([string]$Upper) {
    @{ 'organization_ids[]'=@($script:Config.OrganizationUuids);
       'created_at.lt'=$Upper; limit=$script:Config.ActivityPageSize }
}
function Invoke-Activities {
    $a=$script:State.activity
    if (!$a.backfill_done) {
        if ($null -eq $a.backfill_job) {
            $a.backfill_upper=[DateTimeOffset]::UtcNow.AddSeconds(-$script:Config.LagSeconds).ToString('o')
            $a.backfill_job=New-Job 'activities' '' '/v1/compliance/activities' (Activity-Query $a.backfill_upper)
            Save-Checkpoint
        }
        while (!$a.backfill_done) {
            Check-Budget
            $job=$a.backfill_job
            $p=Activity-Page $job
            $next=Next-Job $job $p 'after_id' $p.last_id
            if (!$a.backfill_first_seen) {
                $a.backfill_anchor=$p.first_id; $a.backfill_first_seen=$true
            }
            if ($p.last_id) { $a.backfill_last_id=$p.last_id }
            if ($null -ne $next) { $a.backfill_job=$next }
            else {
                $a.backfill_done=$true; $a.backfill_job=$null
                $a.tail_first_id=$a.backfill_anchor; $a.last_window_upper=$a.backfill_upper
            }
            Save-Checkpoint
        }
    }
    $target=[DateTimeOffset]::UtcNow.AddSeconds(-$script:Config.LagSeconds).ToString('o')
    while ($true) {
        # Freeze the upper bound, including across restarts; avoid chasing our own API events.
        if ($null -eq $a.work) {
            $upper=$target
            $q=Activity-Query $upper
            $direction=if ($a.tail_first_id) { 'before_id' } else { 'after_id' }
            if ($a.tail_first_id) { $q['before_id']=$a.tail_first_id }
            $a.work=@{ phase='forward'; upper=$upper;
                lower=([DateTimeOffset]::Parse($a.last_window_upper).AddMinutes(-$script:Config.OverlapMinutes).ToString('o'));
                direction=$direction; candidate=$a.tail_first_id; bootstrap_first_seen=$false;
                job=(New-Job 'activities' '' '/v1/compliance/activities' $q) }
            Save-Checkpoint
        }
        while ($null -ne $a.work) {
            Check-Budget
            $w=$a.work; $job=$w.job; $p=Activity-Page $job
            if ($w.phase -eq 'forward') {
                if ($w.direction -eq 'before_id') {
                    if ($p.first_id) { $w.candidate=$p.first_id }
                    $next=Next-Job $job $p 'before_id' $p.first_id
                } else {
                    # Empty initial feed: seed from the newest page, then drain older pages.
                    if (!$w.bootstrap_first_seen) { $w.candidate=$p.first_id; $w.bootstrap_first_seen=$true }
                    $next=Next-Job $job $p 'after_id' $p.last_id
                }
                if ($null -ne $next) { $w.job=$next }
                else {
                    $a.tail_first_id=$w.candidate  # Committed forward cursor, only after has_more=false.
                    $w.phase='overlap'
                    $q=Activity-Query $w.upper; $q['created_at.gte']=$w.lower
                    $w.job=New-Job 'activities' '' '/v1/compliance/activities' $q
                }
            } else {
                $next=Next-Job $job $p 'after_id' $p.last_id
                if ($null -ne $next) { $w.job=$next }
                else {
                    $a.last_window_upper=$w.upper; $a.work=$null
                    $a.last_success_utc=Get-Utc
                }
            }
            Save-Checkpoint
        }
        if ([DateTimeOffset]::Parse($a.last_window_upper) -ge [DateTimeOffset]::Parse($target)) { break }
    }
    Write-Log 'activity_complete' @{ last_success_utc=$a.last_success_utc; through_utc=$a.last_window_upper }
}

function New-Finding([string]$Code,[string]$Id,[string]$Severity='gap') {
    @{ code=$Code; resource_id=(Safe-Id $Id); severity=$Severity }
}
function Find-Flags([Text.Json.JsonElement]$Value,[string]$Owner) {
    # Do not deserialize/rewrite the payload or parse tool-input strings.
    $stack=[Collections.Generic.Stack[object]]::new()
    $stack.Push(@{ value=$Value; owner=$Owner })
    while ($stack.Count -gt 0) {
        $item=$stack.Pop(); $v=$item.value; $id=$item.owner
        if ($v.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
            $ownId=Get-JString $v 'id'
            if (!$ownId) { $ownId=Get-JString $v 'tool_use_id' }
            if ($ownId) { $id=$ownId }
            foreach ($pair in @(@('truncated','api_truncated','gap'),
                                @('thinking_redacted','api_thinking_redacted','warning'))) {
                if ((Get-J $v $pair[0]).ValueKind -eq [Text.Json.JsonValueKind]::True) {
                    New-Finding $pair[1] $id $pair[2]
                }
            }
            foreach ($prop in $v.EnumerateObject()) { $stack.Push(@{ value=$prop.Value; owner=$id }) }
        } elseif ($v.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
            foreach ($child in $v.EnumerateArray()) { $stack.Push(@{ value=$child; owner=$id }) }
        }
    }
}
function Message-Job([string]$Id) {
    New-Job 'messages' $Id ('/v1/compliance/apps/chats/'+[Uri]::EscapeDataString($Id)+'/messages') `
        @{ limit=$script:Config.MessagePageSize; order='asc';
           tool_use_input_max_chars=-1; tool_result_max_chars=-1 } $Id
}
function Project-Job([string]$Id) {
    New-Job 'project' $Id ('/v1/compliance/apps/projects/'+[Uri]::EscapeDataString($Id)) @{} $Id
}
function Finish-Job([string]$Id) { New-Job 'finish_resource' $Id '' @{} $Id }
function Expand-BodyJob($Job,[Text.Json.JsonElement]$Root) {
    $children=[Collections.Generic.List[object]]::new()
    $findings=[Collections.Generic.List[object]]::new()
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pagination=$null; $messages=0
    foreach ($f in (Find-Flags $Root $Job.id)) { $findings.Add($f) }
    if ($Job.kind -notin @('chats_list','projects_list','attachments')) {
        $rid=Require-Id $Root
        if ($Job.kind -eq 'artifact_meta') { $rid=Require-Id $Root 'version_id' }
        if ($rid -cne $Job.id) { Stop-Collector 'Unexpected_Resource_Id' }
    }
    switch ($Job.kind) {
        'chats_list' {
            $pagination=Get-Pagination $Root 'cursor' 'data'
            foreach ($item in (Get-Array $Root 'data' -Required)) {
                Check-Scope $item
                $children.Add((Message-Job (Require-Id $item)))
            }
            $n=Next-Job $Job $pagination 'after_id' $pagination.last_id
            if ($null -ne $n) { $children.Add($n) }
        }
        'projects_list' {
            $pagination=Get-Pagination $Root 'page' 'data'
            foreach ($item in (Get-Array $Root 'data' -Required)) {
                Check-Scope $item
                $children.Add((Project-Job (Require-Id $item)))
            }
            $n=Next-Job $Job $pagination 'page' $pagination.next_page
            if ($null -ne $n) { $children.Add($n) }
        }
        'messages' {
            Check-Scope $Root
            $pagination=Get-Pagination $Root 'cursor' 'chat_messages'
            $messages=$pagination.count
            if (Test-Deleted $Root) { $findings.Add((New-Finding 'chat_deleted_content_unavailable' $Job.id)) }
            foreach ($m in (Get-Array $Root 'chat_messages' -Required)) {
                $mid=Require-Id $m
                $content=Get-J $m 'content'
                if ($content.ValueKind -ne [Text.Json.JsonValueKind]::Array) {
                    $findings.Add((New-Finding 'message_content_not_returned' $mid))
                }
                # Never remove file/artifact references from the saved messages response.
                foreach ($spec in @(
                    @('files','id','file_meta','/v1/compliance/apps/chats/files/'),
                    @('generated_files','id','generated_meta','/v1/compliance/apps/chats/generated-files/'),
                    @('artifacts','version_id','artifact_meta','/v1/compliance/apps/artifacts/'))) {
                    foreach ($ref in (Get-Array $m $spec[0])) {
                        $refid=Get-JString $ref $spec[1]
                        if (!$refid) {
                            $findings.Add((New-Finding 'reference_identifier_not_returned' $mid))
                            continue
                        }
                        $path=$spec[3]+[Uri]::EscapeDataString($refid)
                        if ($seen.Add($path)) {
                            $children.Add((New-Job $spec[2] $refid $path @{} $Job.root_id))
                        }
                    }
                }
            }
            $n=Next-Job $Job $pagination 'after_id' $pagination.last_id
            if ($null -ne $n) { $children.Add($n) }
            else { $children.Add((Finish-Job $Job.root_id)) }
        }
        'project' {
            Check-Scope $Root
            if (Test-Deleted $Root) { $findings.Add((New-Finding 'project_deleted' $Job.id)) }
            foreach ($field in @('description','instructions')) {
                if ((Get-J $Root $field).ValueKind -ne [Text.Json.JsonValueKind]::String) {
                    $findings.Add((New-Finding ($field+'_not_returned') $Job.id))
                }
            }
            $children.Add((New-Job 'attachments' $Job.id ($Job.path+'/attachments') `
                @{ limit=$script:Config.ProjectPageSize } $Job.root_id))
        }
        'attachments' {
            $pagination=Get-Pagination $Root 'page' 'data'
            foreach ($ref in (Get-Array $Root 'data' -Required)) {
                $refid=Require-Id $ref
                switch (Get-JString $ref 'type') {
                    'project_doc' {
                        $children.Add((New-Job 'project_doc' $refid `
                            ('/v1/compliance/apps/projects/documents/'+[Uri]::EscapeDataString($refid)) @{} $Job.root_id))
                    }
                    'project_file' {
                        $children.Add((New-Job 'file_meta' $refid `
                            ('/v1/compliance/apps/chats/files/'+[Uri]::EscapeDataString($refid)) @{} $Job.root_id))
                    }
                    default { $findings.Add((New-Finding 'unknown_attachment_type_saved_reference_only' $refid)) }
                }
            }
            $n=Next-Job $Job $pagination 'page' $pagination.next_page
            if ($null -ne $n) { $children.Add($n) }
            else { $children.Add((Finish-Job $Job.root_id)) }
        }
        'project_doc' {
            if ((Get-J $Root 'content').ValueKind -ne [Text.Json.JsonValueKind]::String) {
                $findings.Add((New-Finding 'project_doc_content_not_returned' $Job.id))
            }
        }
        'file_meta' { }
        'generated_meta' { }
        'artifact_meta' { }
        default { Stop-Collector 'Unknown_Internal_Job' }
    }
    @{ children=@($children.ToArray()); findings=@($findings.ToArray()); pagination=$pagination; messages=$messages }
}
function Start-BodyCycle([string]$Cutoff) {
    $c=@{ id=[Guid]::NewGuid().ToString('N'); started_utc=(Get-Utc); cutoff_utc=$Cutoff;
        gaps=0L; warnings=0L; responses=0L; chats=0L; projects=0L; project_docs=0L }
    $script:State.body.cycle=$c
    # Full reconciliation is deliberate. No user directory, visibility or membership filter.
    # Stable created_at ordering avoids relying on undocumented parent updated_at propagation.
    $script:State.body.queue=@(
        (New-Job 'chats_list' '' '/v1/compliance/apps/chats' @{
            'organization_ids[]'=@($script:Config.OrganizationUuids); order_by='created_at';
            'created_at.lt'=$Cutoff; limit=$script:Config.ChatPageSize }),
        (New-Job 'projects_list' '' '/v1/compliance/apps/projects' @{
            'organization_ids[]'=@($script:Config.OrganizationUuids);
            'created_at.lt'=$Cutoff; limit=$script:Config.ProjectPageSize })
    )
    $script:State.body.current=$null
    Save-Checkpoint
}
function Start-CurrentResource($Job) {
    $b=$script:State.body
    if (!$Job.root_id) { return }
    if ($null -eq $b.current) {
        if ($Job.kind -notin @('messages','project')) { Stop-Collector 'Broken_Resource_Queue' }
        $b.current=@{ id=$Job.root_id; type=$(if ($Job.kind -eq 'messages') { 'chat' } else { 'project' });
            started_utc=(Get-Utc); receipts=@(); findings=@(); messages=0L }
        Save-Checkpoint  # A started job is not a saved body.
    } elseif ($b.current.id -cne $Job.root_id) { Stop-Collector 'Broken_Resource_Queue' }
}
function Complete-Resource($Job) {
    $b=$script:State.body; $cur=$b.current
    if ($null -eq $cur -or $cur.id -cne $Job.id) { Stop-Collector 'Broken_Resource_Queue' }
    $gaps=@($cur.findings | Where-Object { $_.severity -eq 'gap' }).Count
    $report=@{ resource_id=$cur.id; resource_type=$cur.type; cycle_id=$b.cycle.id;
        started_utc=$cur.started_utc; ended_utc=(Get-Utc); response_receipts=$cur.receipts;
        message_rows=$cur.messages; findings=$cur.findings;
        status=$(if ($gaps) { 'completed_with_gaps' } else { 'returned_data_saved' });
        point_in_time_snapshot_guaranteed=$false }
    [void](Publish-Record 'reports' 'resource_result' $Job `
        ($script:Utf8.GetBytes((Convert-ControlJson $report))) @{} $b.cycle.id)
    if ($cur.type -eq 'chat') { $b.cycle.chats++; $script:Metrics.chats_walked++ }
    else { $b.cycle.projects++; $script:Metrics.projects_walked++ }
    $b.current=$null
    $b.queue=@($b.queue | Select-Object -Skip 1)
    Save-Checkpoint
}
function Invoke-BodyQueue {
    $b=$script:State.body
    while (@($b.queue).Count -gt 0) {
        Check-Budget
        $job=$b.queue[0]
        if ($job.kind -eq 'finish_resource') { Complete-Resource $job; continue }
        Start-CurrentResource $job
        $r=Send-Api $job
        $doc=$null
        try {
            if ($r.status -eq 404) {
                $ex=@{ children=@(); findings=@((New-Finding 'http_404_cause_not_distinguishable' $job.id));
                    pagination=$null; messages=0 }
                if ($job.kind -in @('messages','project','attachments')) {
                    $ex.children=@((Finish-Job $job.root_id))
                }
            } else {
                $script:Metrics.body_responses_received++
                $doc=Parse-ApiJson $r.bytes
                $ex=Expand-BodyJob $job $doc.RootElement
                $script:Metrics.chat_messages_received += $ex.messages
                if ($job.kind -eq 'project_doc') { $script:Metrics.project_docs_received++ }
            }
            $info=@{ http=$r.meta; pagination=$ex.pagination; findings=$ex.findings;
                status=$(if ($r.status -eq 404) { 'unavailable' }
                         elseif (@($ex.findings | Where-Object { $_.severity -eq 'gap' }).Count) { 'partial' }
                         else { 'returned_data_saved' }) }
            $saved=Publish-Record 'content' $job.kind $job $r.bytes $info $b.cycle.id -NoPayload:($r.status -eq 404)
            if ($r.status -eq 200) {
                if ($saved.is_new) {
                    $script:Metrics.body_responses_saved++
                    $script:Metrics.chat_messages_in_new_responses += $ex.messages
                } else { $script:Metrics.body_response_duplicates++ }
            }
            $b.cycle.responses++
            if ($job.kind -eq 'project_doc' -and $r.status -eq 200) { $b.cycle.project_docs++ }
            foreach ($f in $ex.findings) {
                if ($f.severity -eq 'gap') { $b.cycle.gaps++; $script:Metrics.gap_findings++ }
                else { $b.cycle.warnings++; $script:Metrics.warning_findings++ }
                Write-Log 'content_finding' @{ code=$f.code; resource_id=$f.resource_id;
                    root_id=(Safe-Id $job.root_id); severity=$f.severity; request_id=$r.meta.request_id } -ErrorLog
            }
            if ($null -ne $b.current) {
                $b.current.receipts=@($b.current.receipts)+@($saved.receipt_ref)
                $b.current.findings=@($b.current.findings)+@($ex.findings)
                $b.current.messages += $ex.messages
            }
            # Publish data and all findings first; then replace the persisted work queue.
            $b.queue=@($ex.children)+@($b.queue | Select-Object -Skip 1)
            Save-Checkpoint
        } finally { if ($null -ne $doc) { $doc.Dispose() } }
    }
}
function Invoke-Bodies {
    $b=$script:State.body
    $target=[DateTimeOffset]::UtcNow.AddSeconds(-$script:Config.LagSeconds).ToString('o')
    while ($true) {
        if ($null -eq $b.cycle) { Start-BodyCycle $target }
        Invoke-BodyQueue
        if ($null -ne $b.current) { Stop-Collector 'Unfinished_Resource_With_Empty_Queue' }
        $done=$b.cycle
        $report=@{ cycle=$done; ended_utc=(Get-Utc);
            status=$(if ($done.gaps) { 'completed_with_gaps' } else { 'returned_data_saved' });
            strategy='organization_wide_full_reconciliation_and_hash_based_storage';
            limits=@('No point-in-time snapshot guarantee','API-omitted content cannot be detected exhaustively',
                'File and artifact bodies are not requested','Tool-result non-text items may be omitted by API') }
        [void](Publish-Record 'reports' 'body_cycle_result' (New-Job 'body_cycle_result' $done.id '') `
            ($script:Utf8.GetBytes((Convert-ControlJson $report))) @{} $done.id)
        $b.initial_done=$true
        $b.last_sweep_utc=Get-Utc
        $b.last_sweep_cutoff_utc=$done.cutoff_utc
        $b.last_sweep_gaps=$done.gaps; $b.last_sweep_warnings=$done.warnings
        if ($done.gaps -eq 0) { $b.last_no_gap_utc=$b.last_sweep_utc }
        $b.cycle=$null
        Save-Checkpoint
        Write-Log 'body_sweep_complete' $report
        # After resuming an old sweep, perform one fresh sweep, not a false 'caught up'.
        if ([DateTimeOffset]::Parse($done.cutoff_utc) -ge [DateTimeOffset]::Parse($target)) { break }
        Check-Budget
        Start-BodyCycle $target
    }
}
function Checkpoint-Summary($S) {
    if ($null -eq $S) { return $null }
    $b=$S.body
    @{ archive_sequence=$S.archive_sequence; archive_hash=$S.archive_hash;
        activity=@{ backfill_done=$S.activity.backfill_done; backfill_last_id=$S.activity.backfill_last_id;
            backfill_anchor=$S.activity.backfill_anchor; tail_first_id=$S.activity.tail_first_id;
            work=$S.activity.work; last_success_utc=$S.activity.last_success_utc;
            last_window_upper=$S.activity.last_window_upper };
        body=@{ initial_done=$b.initial_done; cycle=$b.cycle; pending_jobs=@($b.queue).Count;
            next_job=$(if (@($b.queue).Count) { $b.queue[0] } else { $null });
            current_resource=$(if ($null -ne $b.current) { $b.current.id } else { $null });
            last_sweep_utc=$b.last_sweep_utc; last_sweep_cutoff_utc=$b.last_sweep_cutoff_utc;
            last_sweep_gaps=$b.last_sweep_gaps; last_sweep_warnings=$b.last_sweep_warnings;
            last_no_gap_utc=$b.last_no_gap_utc };
        last_no_gap_success_utc=$S.last_no_gap_success_utc }
}
function New-State([string]$Fingerprint) {
    @{ version=1; configuration_fingerprint=$Fingerprint; archive_sequence=0L; archive_hash='';
        not_before_utc=$null; last_no_gap_success_utc=$null;
        activity=@{ backfill_done=$false; backfill_job=$null; backfill_upper=$null;
            backfill_anchor=$null; backfill_first_seen=$false; backfill_last_id=$null;
            tail_first_id=$null; last_window_upper=$null; work=$null; last_success_utc=$null };
        body=@{ initial_done=$false; cycle=$null; queue=@(); current=$null;
            last_sweep_utc=$null; last_sweep_cutoff_utc=$null; last_sweep_gaps=$null;
            last_sweep_warnings=$null; last_no_gap_utc=$null } }
}
function Read-Configuration([string]$Path) {
    $c=Read-Control $Path
    $defaults=@{ KeyEnvironmentVariable='ANTHROPIC_COMPLIANCE_ACCESS_KEY'; KeyEnvironmentScope='User';
        RequestsPerMinute=120; ActivityPageSize=1000; ChatPageSize=100; MessagePageSize=20;
        ProjectPageSize=100; LagSeconds=120; OverlapMinutes=10; MaxRetries=6;
        TimeoutSeconds=120; MaxRunMinutes=1200 }
    foreach ($k in $defaults.Keys) { if (!$c.Contains($k)) { $c[$k]=$defaults[$k] } }
    if (!$c.Contains('OrganizationUuids') -or @($c.OrganizationUuids).Count -eq 0) {
        Stop-Collector 'Configuration_OrganizationUuids_Required'
    }
    $orgs=[Collections.Generic.List[string]]::new()
    foreach ($v in @($c.OrganizationUuids)) {
        $g=[Guid]::Empty
        if (![Guid]::TryParse([string]$v,[ref]$g) -or $g -eq [Guid]::Empty) {
            Stop-Collector 'Configuration_Use_Actual_Organization_UUID'
        }
        $orgs.Add($g.ToString('D'))
    }
    $c.OrganizationUuids=@($orgs | Sort-Object -Unique)
    if ($c.KeyEnvironmentScope -notin @('User','Process') -or
        $c.KeyEnvironmentVariable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { Stop-Collector 'Configuration_Key_Environment' }
    $bounds=@{ RequestsPerMinute=@(1,600); ActivityPageSize=@(1,5000); ChatPageSize=@(1,1000);
        MessagePageSize=@(1,1000); ProjectPageSize=@(1,100); LagSeconds=@(60,86400);
        OverlapMinutes=@(2,525600); MaxRetries=@(0,20); TimeoutSeconds=@(10,3600); MaxRunMinutes=@(1,10080) }
    foreach ($k in $bounds.Keys) {
        $n=0
        if (![int]::TryParse([string]$c[$k],[ref]$n) -or $n -lt $bounds[$k][0] -or $n -gt $bounds[$k][1]) {
            Stop-Collector ('Configuration_Invalid_'+$k)
        }
        $c[$k]=$n
    }
    $c
}

# ----------------------------- MAIN ------------------------------------------
$exitCode=1; $beginCheckpoint=$null; $endCheckpoint=$null
$activityResult='not_started'; $bodyResult='not_started'; $failure=$null; $canReport=$false
try {
    if (!$IsWindows) { Stop-Collector 'Windows_Required' }
    if (([IO.DriveInfo]::new('C:\')).DriveFormat -ne 'NTFS') { Stop-Collector 'Local_NTFS_Required' }
    if (![IO.Directory]::Exists($script:Root)) { Stop-Collector 'Prepare_Secured_Root_First' }
    if (([IO.File]::GetAttributes($script:Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Collector 'Root_Must_Not_Be_ReparsePoint'
    }
    $script:Config=Read-Configuration $ConfigPath
    $lockPath=Join-Path $script:Root 'collector.lock'
    try {
        $script:Lock=[IO.FileStream]::new($lockPath,[IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    } catch {
        if (($_.Exception.GetBaseException().HResult -band 0xFFFF) -in @(32,33)) {
            $exitCode=4
            Write-Control (Join-Path $script:Root ("logs/skipped_$($script:RunId).txt")) `
                @{ run_id=$script:RunId; time_utc=(Get-Utc); mode=$Mode; reason='another_instance_holds_lock'; exit_code=4 }
            Stop-Collector 'Another_Instance_Running' 4
        }
        throw
    }
    $canReport=$true
    $fingerprint=Get-StringHash ('collector-v1|full-body-reconciliation|' + ($script:Config.OrganizationUuids -join ','))
    $statePath=Join-Path $script:Root 'state/checkpoint.json'
    if ([IO.File]::Exists($statePath)) {
        $script:State=Read-Control $statePath
        if ($script:State.version -ne 1 -or $script:State.configuration_fingerprint -cne $fingerprint) {
            Stop-Collector 'Checkpoint_Configuration_Mismatch'
        }
    }
    $beginCheckpoint=Checkpoint-Summary $script:State
    Write-Log 'run_start' @{ mode=$Mode; started_utc=$script:Started.ToString('o'); checkpoint=$beginCheckpoint }
    Verify-Archive
    if ($null -eq $script:State) {
        if ($script:Seq -gt 0) { Stop-Collector 'Checkpoint_Missing_Do_Not_Reset_Archive' }
        if ($Mode -eq 'Tail') { Stop-Collector 'Run_Backfill_First' }
        $script:State=New-State $fingerprint
        Save-Checkpoint
    } else {
        $savedSeq=[long]$script:State.archive_sequence
        if ($savedSeq -gt $script:Seq -or ($savedSeq -gt 0 -and
            $script:ReceiptHashes[$savedSeq] -cne $script:State.archive_hash)) {
            Stop-Collector 'Checkpoint_Ahead_Of_Or_Inconsistent_With_Archive'
        }
    }
    if ($Mode -eq 'Tail' -and (!$script:State.activity.backfill_done -or !$script:State.body.initial_done)) {
        Stop-Collector 'Initial_Backfill_Not_Complete'
    }
    # Explicit User lookup avoids stale inherited environment blocks in scheduled tasks.
    $target=[EnvironmentVariableTarget]($script:Config.KeyEnvironmentScope)
    $key=[Environment]::GetEnvironmentVariable($script:Config.KeyEnvironmentVariable,$target)
    if ([string]::IsNullOrWhiteSpace($key)) { Stop-Collector 'Compliance_Key_Environment_Missing' }
    $handler=[Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect=$false
    $script:Client=[Net.Http.HttpClient]::new($handler,$true)
    $script:Client.Timeout=[Threading.Timeout]::InfiniteTimeSpan
    [void]$script:Client.DefaultRequestHeaders.TryAddWithoutValidation('x-api-key',$key)
    [void]$script:Client.DefaultRequestHeaders.TryAddWithoutValidation('anthropic-version','2023-06-01')
    $key=$null
    $activityResult='incomplete'
    Invoke-Activities
    $activityResult='completed'
    $bodyResult='incomplete'
    Invoke-Bodies
    $bodyResult=if ($script:State.body.last_sweep_gaps -gt 0) { 'completed_with_gaps' } else { 'returned_data_saved' }
    if ($script:State.body.last_sweep_gaps -eq 0) {
        $script:State.last_no_gap_success_utc=Get-Utc
        Save-Checkpoint
        $exitCode=0
    } else { $exitCode=2 }
} catch {
    $e=$_.Exception
    $code='Unhandled_Local_Error'
    while ($null -ne $e) {
        if ($e.Data.Contains('CollectorCode')) { $code=[string]$e.Data['CollectorCode']; $exitCode=[int]$e.Data['CollectorExit']; break }
        $e=$e.InnerException
    }
    $failure=@{ code=$code; exception_type=$_.Exception.GetType().FullName;
        hresult=$_.Exception.HResult; base_exception_type=$_.Exception.GetBaseException().GetType().FullName;
        base_hresult=$_.Exception.GetBaseException().HResult; script_line=$_.InvocationInfo.ScriptLineNumber; api_context=$script:LastApi }
    if ($exitCode -notin @(3,4)) { $script:Metrics.errors++ }
    if ($canReport) { try { Write-Log 'run_stopped' $failure -ErrorLog } catch { } }
    elseif ($exitCode -ne 4 -and [IO.Directory]::Exists((Join-Path $script:Root 'logs'))) {
        try { Write-Control (Join-Path $script:Root ("logs/preflight_error_$($script:RunId).txt")) `
            @{ run_id=$script:RunId; started_utc=$script:Started.ToString('o'); ended_utc=(Get-Utc);
               mode=$Mode; exit_code=$exitCode; failure=$failure; incomplete=$true } } catch { }
    }
    [Console]::Error.WriteLine(('Collector stopped. Code={0}; Exit={1}; Run={2}' -f $code,$exitCode,$script:RunId))
} finally {
    if ($null -ne $script:Client) { $script:Client.Dispose() }
    if ($canReport) {
        try {
            $p=Join-Path $script:Root 'state/checkpoint.json'
            # Never persist possibly half-mutated in-memory state from a failed handler.
            if ([IO.File]::Exists($p)) { $endCheckpoint=Checkpoint-Summary (Read-Control $p) }
            $result=@{ run_id=$script:RunId; mode=$Mode; started_utc=$script:Started.ToString('o');
                ended_utc=(Get-Utc); elapsed_seconds=[Math]::Round($script:Clock.Elapsed.TotalSeconds,3);
                exit_code=$exitCode; activity_result=$activityResult; body_result=$bodyResult;
                incomplete=($exitCode -ne 0); metrics=$script:Metrics; failure=$failure;
                start_checkpoint=$beginCheckpoint; end_checkpoint=$endCheckpoint;
                completeness_claim='Only the API-returned data and completed walks described by receipts; no historical or point-in-time completeness guarantee.' }
            Write-Log 'run_end' $result
            Write-Control (Join-Path $script:Root ("logs/runs/$($script:RunId).json")) $result
            Write-Control (Join-Path $script:Root 'state/status.json') $result
        } catch {
            $exitCode=1
            [Console]::Error.WriteLine(('Unable to persist final status. Run={0}. Check disk/ACL and external monitoring.' -f $script:RunId))
        }
    }
    if ($null -ne $script:Lock) { $script:Lock.Dispose() }
}
exit $exitCode
