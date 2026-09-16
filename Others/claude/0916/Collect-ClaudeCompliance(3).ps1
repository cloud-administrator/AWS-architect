#requires -Version 7.4
<#
Claude Enterprise Compliance collector. Official specifications reviewed 2026-09-16.
Windows / local NTFS / PowerShell 7.4+ (7.6 LTS recommended).
GET only. No SDK, database, background worker, or file-content download.
See README.md before enabling collection; the inline-content policy requires a decision.
#>
[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:Root = 'C:\ClaudeComplianceCollector'
$script:Utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:JsonOptions = [System.Text.Json.JsonDocumentOptions]::new()
$script:JsonOptions.MaxDepth = 2048
$script:CP = $null
$script:Lock = $null
$script:Client = $null
$script:Key = $null
$script:RunLog = $null
$script:ErrorLog = $null
$script:CurrentRequest = $null
$script:Ready = $false
$script:FailurePhase = 'startup'
$script:ApiNextUtc = [datetimeoffset]::MinValue
$script:RunId = [guid]::NewGuid().ToString('N')
$script:StartedUtc = [datetimeoffset]::UtcNow
$script:Cache = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
$script:EventIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:RunReused = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:ScanTouched = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:Stats = @{
    fetched = @{}; saved = @{}; replayed = @{}; activityDuplicates = 0L
    apiAttempts = 0L; retries = 0L; http429 = 0L; errors = 0L
    unavailableRecorded = 0L; responsesCommitted = 0L; recoveredBundles = 0L
}
$script:Constraints = @(
    'NON_ATOMIC_CONTENT_SCAN', 'UNREFERENCED_FILES_AND_ARTIFACT_VERSIONS_NOT_ENUMERABLE',
    'TOOL_RESULT_NON_TEXT_OMITTED_BY_API', 'MISSING_TRUNCATION_FLAG_IS_UNKNOWN',
    'INLINE_FILE_OR_ARTIFACT_TEXT_NOT_REMOVED', 'ACTIVITY_DELAY_BEYOND_OVERLAP_NOT_GUARANTEED',
    'ORGANIZATION_NULL_ACTIVITIES_COVERAGE_UNKNOWN', 'PRE_ENABLEMENT_ACTIVITY_UNAVAILABLE'
)

function Stop-Collector([string]$Code, [int]$ExitCode = 1) {
    $e = [System.InvalidOperationException]::new($Code)
    $e.Data['CollectorCode'] = $Code
    $e.Data['CollectorExitCode'] = $ExitCode
    throw $e
}
function Utc-Text([datetimeoffset]$Time = [datetimeoffset]::UtcNow) {
    return $Time.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'", [cultureinfo]::InvariantCulture)
}
function Parse-Utc([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch 'Z$') {
        Stop-Collector 'INVALID_UTC_IN_STATE' 4
    }
    return [datetimeoffset]::Parse($Value, [cultureinfo]::InvariantCulture).ToUniversalTime()
}
function Get-J([System.Text.Json.JsonElement]$Element, [string]$Name) {
    $v = [System.Text.Json.JsonElement]::new()
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        [void]$Element.TryGetProperty($Name, [ref]$v)
    }
    return $v
}
function Get-JString([System.Text.Json.JsonElement]$Element, [string]$Name, [switch]$Required) {
    $v = Get-J $Element $Name
    if ($v.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
        $s = $v.GetString()
        if (-not $Required -or -not [string]::IsNullOrEmpty($s)) { return $s }
    }
    if ($Required) { Stop-Collector 'API_REQUIRED_STRING_MISSING' }
    return $null
}
function Assert-Array([System.Text.Json.JsonElement]$Value) {
    if ($Value.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
        Stop-Collector 'API_REQUIRED_ARRAY_MISSING'
    }
}
function Assert-Organization([System.Text.Json.JsonElement]$Element, [switch]$Nullable) {
    $field = Get-J $Element 'organization_uuid'
    if ($Nullable -and $field.ValueKind -in @([System.Text.Json.JsonValueKind]::Null,
        [System.Text.Json.JsonValueKind]::Undefined)) { return }
    $v = Get-JString $Element 'organization_uuid'
    $actual = [guid]::Empty
    if (-not [guid]::TryParseExact($v, 'D', [ref]$actual) -or
        $actual -ne [guid]$script:CP.organizationUuid) { Stop-Collector 'API_ORGANIZATION_MISMATCH' 4 }
}
function New-JsonDocument([byte[]]$Bytes) {
    # Inspection only: API JSON is never round-tripped through PowerShell objects.
    return [System.Text.Json.JsonDocument]::Parse([System.ReadOnlyMemory[byte]]::new($Bytes), $script:JsonOptions)
}
function Convert-OwnElement([System.Text.Json.JsonElement]$Element, [int]$Depth = 0) {
    # Used ONLY for this collector's management JSON, preserving timestamps as strings.
    if ($Depth -gt 64) { Stop-Collector 'MANAGEMENT_JSON_TOO_DEEP' 4 }
    switch ($Element.ValueKind.ToString()) {
        'Object' {
            $h = @{}
            foreach ($p in $Element.EnumerateObject()) {
                if ($h.ContainsKey($p.Name)) { Stop-Collector 'DUPLICATE_MANAGEMENT_PROPERTY' 4 }
                $h[$p.Name] = Convert-OwnElement $p.Value ($Depth + 1)
            }
            return $h
        }
        'Array' {
            $a = [System.Collections.Generic.List[object]]::new()
            foreach ($v in $Element.EnumerateArray()) { $a.Add((Convert-OwnElement $v ($Depth + 1))) }
            return ,($a.ToArray())
        }
        'String' { return $Element.GetString() }
        'Number' { return $Element.GetInt64() }
        'True' { return $true }
        'False' { return $false }
        'Null' { return $null }
        default { Stop-Collector 'INVALID_MANAGEMENT_JSON' 4 }
    }
}
function Hash-Bytes([byte[]]$Bytes) {
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
function Hash-File([string]$Path) {
    $s = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($s)).ToLowerInvariant() }
    finally { $s.Dispose() }
}
function Own-Json($Object) { return ConvertTo-Json -InputObject $Object -Depth 64 -Compress }
function Write-Durable([string]$Path, [byte[]]$Bytes) {
    $s = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
        [IO.FileShare]::None, 65536, [IO.FileOptions]::WriteThrough)
    try { $s.Write($Bytes, 0, $Bytes.Length); $s.Flush($true) }
    finally { $s.Dispose() }
}
function Write-CheckedJson([string]$Path, $Object, [switch]$Replace) {
    $payload = Own-Json $Object
    $hash = Hash-Bytes ($script:Utf8.GetBytes($payload))
    $bytes = $script:Utf8.GetBytes('{"sha256":"' + $hash + '","payload":' + $payload + '}')
    if (-not $Replace) { Write-Durable $Path $bytes; return }
    $tmp = $Path + '.tmp.' + [guid]::NewGuid().ToString('N')
    Write-Durable $tmp $bytes
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, $null) }
    else { [IO.File]::Move($tmp, $Path) }
}
function Read-CheckedJson([string]$Path) {
    $d = New-JsonDocument ([IO.File]::ReadAllBytes($Path))
    try {
        $p = Get-J $d.RootElement 'payload'
        if ($p.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { Stop-Collector 'BAD_MANAGEMENT_ENVELOPE' 4 }
        $expected = Get-JString $d.RootElement 'sha256' -Required
        if ((Hash-Bytes ($script:Utf8.GetBytes($p.GetRawText()))) -cne $expected) {
            Stop-Collector 'MANAGEMENT_CHECKSUM_MISMATCH' 4
        }
        return Convert-OwnElement $p
    } finally { $d.Dispose() }
}
function Save-Checkpoint { Write-CheckedJson $script:CheckpointPath $script:CP -Replace }
function Safe-Token([string]$Value) {
    if ($null -ne $Value -and $Value -cmatch '^[A-Za-z0-9_.:-]{1,200}$' -and
        -not ($script:Key -and $Value.Contains($script:Key))) { return $Value }
    return 'unknown_or_omitted'
}
function Write-Log([string]$Code, [hashtable]$Fields = @{}, [switch]$ErrorEntry) {
    # Callers supply only management values; never pass exception.Message/API bodies/headers here.
    $line = (Utc-Text) + ' ' + $Code + ' ' + (Own-Json $Fields) + "`n"
    if ($script:RunLog) { [IO.File]::AppendAllText($script:RunLog, $line, $script:Utf8) }
    if ($ErrorEntry -and $script:ErrorLog) { [IO.File]::AppendAllText($script:ErrorLog, $line, $script:Utf8) }
}
function Add-Counts([hashtable]$Target, [hashtable]$Values) {
    foreach ($k in $Values.Keys) {
        if (-not $Target.ContainsKey($k)) { $Target[$k] = 0L }
        $Target[$k] += [long]$Values[$k]
    }
}
function Request-Identity([string]$Path, [hashtable]$Query) {
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($k in ($Query.Keys | Sort-Object -CaseSensitive)) {
        $parts.Add([uri]::EscapeDataString([string]$k) + '=' + [uri]::EscapeDataString([string]$Query[$k]))
    }
    $uri = $Path
    if ($parts.Count -gt 0) { $uri += '?' + [string]::Join('&', $parts) }
    return @{ relativeUri = $uri; hash = (Hash-Bytes ($script:Utf8.GetBytes($uri))) }
}
function Get-Header($Response, [string]$Name) {
    $values = $null
    if ($Response.Headers.TryGetValues($Name, [ref]$values)) {
        foreach ($v in $values) { return [string]$v }
    }
    return $null
}
function Wait-Seconds([double]$Seconds) {
    if ($Seconds -le 0) { return }
    # Do not retry earlier than a long server instruction: stop unfinished instead.
    if ($Seconds -gt 3600) { Stop-Collector 'SERVER_WAIT_EXCEEDS_ONE_HOUR' }
    [System.Threading.Thread]::Sleep([timespan]::FromSeconds($Seconds))
}
function Get-RetryDelay([string]$RetryAfter, [int]$Attempt) {
    $delay = [math]::Min(60, [math]::Pow(2, $Attempt))
    if ($RetryAfter) {
        $seconds = 0.0
        $when = [datetimeoffset]::MinValue
        if ([double]::TryParse($RetryAfter, [Globalization.NumberStyles]::Float,
            [cultureinfo]::InvariantCulture, [ref]$seconds) -and
            [double]::IsFinite($seconds) -and $seconds -ge 0) { return $seconds }
        if ([datetimeoffset]::TryParse($RetryAfter, [cultureinfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$when)) {
            return [math]::Max(0, ($when - [datetimeoffset]::UtcNow).TotalSeconds)
        }
    }
    return $delay
}
function Update-RateLimitClock($Response) {
    $remainingText = Get-Header $Response 'anthropic-ratelimit-requests-remaining'
    $resetText = Get-Header $Response 'anthropic-ratelimit-requests-reset'
    $remaining = 0L
    $resetAt = [datetimeoffset]::MinValue
    if ([long]::TryParse($remainingText, [ref]$remaining) -and $remaining -le 1 -and
        [datetimeoffset]::TryParse($resetText, [cultureinfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$resetAt)) {
        if ($resetAt.AddSeconds(1) -gt $script:ApiNextUtc) { $script:ApiNextUtc = $resetAt.AddSeconds(1) }
    }
}
function Invoke-ApiGet([string]$RelativeUri, [string]$Kind, [string]$ResourceId, [bool]$AllowUnavailable) {
    if (-not $RelativeUri.StartsWith('/v1/compliance/', [StringComparison]::Ordinal) -or
        $RelativeUri -match '/content(?:\?|$)' -or $RelativeUri.Contains('://')) {
        Stop-Collector 'DISALLOWED_ENDPOINT' 5
    }
    for ($attempt = 0; $attempt -le 6; $attempt++) {
        Wait-Seconds (($script:ApiNextUtc - [datetimeoffset]::UtcNow).TotalSeconds)
        $script:ApiNextUtc = [datetimeoffset]::UtcNow.AddMilliseconds(250)
        $script:Stats.apiAttempts++
        $script:CurrentRequest = @{ kind = $Kind; resourceId = (Safe-Token $ResourceId); requestId = 'unknown_or_omitted' }
        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get,
            ('https://api.anthropic.com' + $RelativeUri))
        [void]$req.Headers.TryAddWithoutValidation('x-api-key', $script:Key)
        [void]$req.Headers.TryAddWithoutValidation('anthropic-version', '2023-06-01')
        $cts = [System.Threading.CancellationTokenSource]::new([timespan]::FromSeconds(120))
        $resp = $null
        $networkFailed = $false
        $bytes = $null
        try {
            $resp = $script:Client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead,
                $cts.Token).GetAwaiter().GetResult()
            $bytes = $resp.Content.ReadAsByteArrayAsync($cts.Token).GetAwaiter().GetResult()
        } catch { $networkFailed = $true }
        finally { $req.Dispose(); $cts.Dispose() }
        if ($networkFailed) {
            $script:Stats.errors++
            $delay = Get-RetryDelay $null $attempt
            if ($null -ne $resp) {
                try {
                    $status = [int]$resp.StatusCode
                    $script:CurrentRequest.requestId = Safe-Token (Get-Header $resp 'request-id')
                    $script:CurrentRequest.httpStatus = $status
                    Update-RateLimitClock $resp
                    if ($status -eq 429) {
                        $script:Stats.http429++
                        $delay = Get-RetryDelay (Get-Header $resp 'retry-after') $attempt
                    }
                    Write-Log 'RESPONSE_BODY_READ_FAILED' $script:CurrentRequest -ErrorEntry
                    if ($status -in @(401,403)) { Stop-Collector 'AUTHENTICATION_OR_PERMISSION_ERROR' 3 }
                    if ((Get-Header $resp 'x-should-retry') -ieq 'false') { Stop-Collector 'SERVER_DISALLOWED_RETRY' }
                } finally { $resp.Dispose() }
            } else { Write-Log 'NETWORK_OR_TIMEOUT' $script:CurrentRequest -ErrorEntry }
            if ($attempt -ge 6) { Stop-Collector 'NETWORK_RETRIES_EXHAUSTED' }
            $script:Stats.retries++
            Wait-Seconds $delay
            continue
        }
        try {
            $status = [int]$resp.StatusCode
            $rid = Safe-Token (Get-Header $resp 'request-id')
            $script:CurrentRequest.requestId = $rid
            $shouldRetry = Get-Header $resp 'x-should-retry'
            $retryAfter = Get-Header $resp 'retry-after'
            Update-RateLimitClock $resp
            Write-Log 'HTTP_RESPONSE' @{ kind = $Kind; resourceId = (Safe-Token $ResourceId)
                httpStatus = $status; requestId = $rid; attempt = ($attempt + 1) }
            if ($status -ge 200 -and $status -lt 300) {
                return @{ available = $true; bytes = $bytes; httpStatus = $status; requestId = $rid; fetchedAtUtc = (Utc-Text) }
            }
            $script:Stats.errors++
            if ($status -eq 429) { $script:Stats.http429++ }
            $errorType = 'unknown'
            $bareNotFound = $false
            $knownCause = '不明'
            $ed = $null
            try {
                $ed = New-JsonDocument $bytes
                $err = Get-J $ed.RootElement 'error'
                $t = Get-JString $err 'type'
                if ($t -in @('authentication_error','permission_error','invalid_request_error',
                    'not_found_error','rate_limit_error','api_error','overloaded_error')) { $errorType = $t }
                $message = Get-JString $err 'message'
                $bareNotFound = ($message -ceq 'Not found')
                if ($message -ceq 'Compliance API is not enabled for this organization') { $knownCause = 'COMPLIANCE_API_NOT_ENABLED' }
                if ($bareNotFound) { $knownCause = 'NOT_AUTHENTICATED_OR_PATH_NOT_FOUND' }
                # Message is compared in memory only, never emitted or persisted.
            } catch { $knownCause = 'ERROR_RESPONSE_NOT_VALID_JSON_OR_UNKNOWN' }
            finally { if ($null -ne $ed) { $ed.Dispose() } }
            Write-Log 'API_ERROR' @{ kind = $Kind; resourceId = (Safe-Token $ResourceId)
                httpStatus = $status; requestId = $rid; errorType = $errorType; reason = $knownCause } -ErrorEntry
            if ($status -in @(401,403)) { Stop-Collector 'AUTHENTICATION_OR_PERMISSION_ERROR' 3 }
            if ($bareNotFound) { Stop-Collector 'UNAUTHENTICATED_OR_INVALID_PATH' 3 }
            $retry = ($status -eq 429 -or $status -in @(500,502,503,504,529))
            if ($shouldRetry -ieq 'true') { $retry = $true }
            if ($shouldRetry -ieq 'false') { $retry = $false }
            if ($retry) {
                if ($attempt -ge 6) { Stop-Collector 'API_RETRIES_EXHAUSTED' }
                $delay = Get-RetryDelay $null $attempt
                if ($status -eq 429) { $delay = Get-RetryDelay $retryAfter $attempt }
                $script:Stats.retries++
                Write-Log 'RETRY_WAIT' @{ kind = $Kind; requestId = $rid; seconds = [long][math]::Ceiling($delay) }
                Wait-Seconds $delay
                continue
            }
            if ($status -eq 404 -and $AllowUnavailable) {
                return @{ available = $false; bytes = $null; httpStatus = $status; requestId = $rid
                    fetchedAtUtc = (Utc-Text); errorType = $errorType; reason = '不明' }
            }
            Stop-Collector 'NON_RETRYABLE_HTTP_ERROR'
        } finally { $resp.Dispose() }
    }
    Stop-Collector 'UNEXPECTED_RETRY_LOOP_END'
}

function Get-PageInfo([System.Text.Json.JsonElement]$Root, [string]$CursorName) {
    $hm = Get-J $Root 'has_more'
    if ($hm.ValueKind -notin @([System.Text.Json.JsonValueKind]::True, [System.Text.Json.JsonValueKind]::False)) {
        Stop-Collector 'API_HAS_MORE_MISSING'
    }
    $next = Get-JString $Root $CursorName
    if ($hm.GetBoolean() -and [string]::IsNullOrEmpty($next)) { Stop-Collector 'API_NEXT_CURSOR_MISSING' }
    return @{ hasMore = $hm.GetBoolean(); next = $next }
}
function New-Issue([string]$Code, [string]$ResourceId, [string]$MessageId = '', [int]$BlockIndex = -1) {
    return @{ code = $Code; resourceId = $ResourceId; messageId = $MessageId; blockIndex = $BlockIndex }
}
function Inspect-Response([string]$Kind, [System.Text.Json.JsonElement]$Root, [string]$ResourceId) {
    if ($Root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { Stop-Collector 'API_ROOT_NOT_OBJECT' }
    $counts = @{}
    $issues = [System.Collections.Generic.List[object]]::new()
    $page = $null
    $truncation = '不明'
    $blocking = 0L
    if ($Kind -in @('activities','chats','projects','attachments')) {
        $data = Get-J $Root 'data'; Assert-Array $data
        $cursorName = if ($Kind -in @('projects','attachments')) { 'next_page' } else { 'last_id' }
        $page = Get-PageInfo $Root $cursorName
        $unit = (@{ activities='activity_events'; chats='chat_list_records'; projects='project_list_records'; attachments='attachment_references' })[$Kind]
        $counts[$unit] = [long]$data.GetArrayLength()
        foreach ($item in $data.EnumerateArray()) {
            $id = Get-JString $item 'id' -Required
            if ($Kind -in @('chats','projects')) { Assert-Organization $item }
            if ($Kind -eq 'activities') { Assert-Organization $item -Nullable }
            if ($Kind -eq 'attachments') {
                $t = Get-JString $item 'type' -Required
                if ($t -notin @('project_file','project_doc')) {
                    $issues.Add((New-Issue 'UNKNOWN_ATTACHMENT_TYPE_NOT_FETCHED' $id)); $blocking++
                }
            }
            $deleted = Get-JString $item 'deleted_at'
            if ($deleted -and $Kind -in @('chats','projects')) {
                $issues.Add((New-Issue 'DELETED_AT_REPORTED_BODY_AVAILABILITY_UNKNOWN' $id)); $blocking++
            }
        }
    } elseif ($Kind -eq 'messages') {
        if ((Get-JString $Root 'id' -Required) -cne $ResourceId) { Stop-Collector 'API_RESOURCE_ID_MISMATCH' 4 }
        Assert-Organization $Root
        $data = Get-J $Root 'chat_messages'; Assert-Array $data
        $page = Get-PageInfo $Root 'last_id'
        $counts.message_records = [long]$data.GetArrayLength()
        $counts.tool_use_blocks = 0L; $counts.tool_result_blocks = 0L
        $truncation = 'returned_flags_false'
        if (Get-JString $Root 'deleted_at') {
            $issues.Add((New-Issue 'DELETED_AT_REPORTED_BODY_AVAILABILITY_UNKNOWN' $ResourceId)); $blocking++
        }
        foreach ($m in $data.EnumerateArray()) {
            $mid = Get-JString $m 'id' -Required
            foreach ($field in @('files','generated_files','artifacts')) {
                $refs = Get-J $m $field
                if ($refs.ValueKind -in @([System.Text.Json.JsonValueKind]::Null, [System.Text.Json.JsonValueKind]::Undefined)) { continue }
                Assert-Array $refs
                foreach ($ref in $refs.EnumerateArray()) {
                    [void](Get-JString $ref 'id' -Required)
                    if ($field -eq 'artifacts') { [void](Get-JString $ref 'version_id' -Required) }
                }
            }
            $blocks = Get-J $m 'content'; Assert-Array $blocks
            $index = 0
            foreach ($b in $blocks.EnumerateArray()) {
                $bt = Get-JString $b 'type'
                if ($bt -eq 'tool_use') { $counts.tool_use_blocks++ }
                if ($bt -eq 'tool_result') {
                    $counts.tool_result_blocks++
                    $issues.Add((New-Issue 'NON_TEXT_TOOL_RESULT_OMISSION_PRESENCE_UNKNOWN' $ResourceId $mid $index))
                }
                if ($bt -notin @('text','tool_use','tool_result')) {
                    $issues.Add((New-Issue 'UNKNOWN_CONTENT_BLOCK_PRESERVED_RAW' $ResourceId $mid $index))
                }
                $flag = Get-J $b 'truncated'
                if ($flag.ValueKind -eq [System.Text.Json.JsonValueKind]::True) {
                    $issues.Add((New-Issue 'API_REPORTED_TRUNCATED_REASON_OTHERWISE_UNKNOWN' $ResourceId $mid $index))
                    $truncation = 'reported_true'; $blocking++
                } elseif ($flag.ValueKind -ne [System.Text.Json.JsonValueKind]::False) {
                    $issues.Add((New-Issue 'TRUNCATION_UNKNOWN' $ResourceId $mid $index))
                    if ($truncation -ne 'reported_true') { $truncation = '不明' }
                }
                if ((Get-J $b 'thinking_redacted').ValueKind -eq [System.Text.Json.JsonValueKind]::True) {
                    $issues.Add((New-Issue 'INTERNAL_REASONING_REDACTED_BY_API' $ResourceId $mid $index))
                }
                $index++
            }
        }
    } else {
        $idField = if ($Kind -eq 'artifact') { 'version_id' } else { 'id' }
        if ((Get-JString $Root $idField -Required) -cne $ResourceId) { Stop-Collector 'API_RESOURCE_ID_MISMATCH' 4 }
        switch ($Kind) {
            'project' {
                Assert-Organization $Root; $counts.project_details = 1L
                foreach ($f in @('description','instructions')) {
                    $v = Get-J $Root $f
                    if ($v.ValueKind -notin @([System.Text.Json.JsonValueKind]::String, [System.Text.Json.JsonValueKind]::Null)) {
                        Stop-Collector 'PROJECT_DESCRIPTION_OR_INSTRUCTIONS_MISSING'
                    }
                    if ($v.ValueKind -eq [System.Text.Json.JsonValueKind]::Null) {
                        $issues.Add((New-Issue ('PROJECT_' + $f.ToUpperInvariant() + '_NULL_AVAILABILITY_UNKNOWN') $ResourceId))
                        $blocking++
                    }
                }
                if (Get-JString $Root 'deleted_at') {
                    $issues.Add((New-Issue 'DELETED_AT_REPORTED_BODY_AVAILABILITY_UNKNOWN' $ResourceId)); $blocking++
                }
            }
            'document' {
                $counts.project_docs = 1L
                if ((Get-J $Root 'content').ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                    Stop-Collector 'PROJECT_DOC_CONTENT_MISSING'
                }
                $issues.Add((New-Issue 'TRUNCATION_UNKNOWN' $ResourceId))
            }
            'file' { $counts.uploaded_file_metadata = 1L }
            'generated_file' { $counts.generated_file_metadata = 1L }
            'artifact' { $counts.artifact_version_metadata = 1L }
            default { Stop-Collector 'UNKNOWN_REQUEST_KIND' 5 }
        }
    }
    return @{ counts = $counts; page = $page; quality = @{ truncation = $truncation
        issues = $issues.ToArray(); blockingObservations = $blocking; unspecifiedUnavailableReason = '不明' } }
}

function Publish-Bundle([string]$Stream, [string]$ScanId, [string]$Kind, [string]$ResourceId,
    [string]$ParentId, [hashtable]$Request, [hashtable]$Http, $Document) {
    $sequence = [long]$script:CP.sequence + 1L
    $when = Parse-Utc $Http.fetchedAtUtc
    $jst = $when.ToOffset([timespan]::FromHours(9))
    $datePath = $jst.ToString('yyyy\\MM\\dd', [cultureinfo]::InvariantCulture)
    $dateName = $jst.ToString('yyyyMMdd', [cultureinfo]::InvariantCulture)
    $destParent = Join-Path $script:RawPath (Join-Path $datePath $Stream)
    [void][IO.Directory]::CreateDirectory($destParent)
    $bundleName = 'b_' + $sequence.ToString('D14', [cultureinfo]::InvariantCulture)
    $dest = Join-Path $destParent $bundleName
    $stage = Join-Path $script:StagingPath ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $newIds = [System.Collections.Generic.List[string]]::new()
    $dedupCount = 0L
    if ($Http.available) {
        $inspection = Inspect-Response $Kind $Document.RootElement $ResourceId
        Add-Counts $script:Stats.fetched $inspection.counts
        $savedCounts = $inspection.counts.Clone()
        if ($Stream -eq 'activities') {
            $payloadName = 'activities_' + $dateName + '.jsonl'
            $builder = [System.Text.StringBuilder]::new()
            $pageIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($a in (Get-J $Document.RootElement 'data').EnumerateArray()) {
                $id = Get-JString $a 'id' -Required
                if ($script:EventIds.Contains($id) -or -not $pageIds.Add($id)) { $dedupCount++; continue }
                $newIds.Add($id)
                # Only insignificant whitespace outside strings is removed. Tokens stay unchanged.
                [void]$builder.Append([ClaudeCollector.JsonLexical]::Compact($a.GetRawText())).Append("`n")
            }
            $payload = $script:Utf8.GetBytes($builder.ToString())
            $savedCounts.activity_events = [long]$newIds.Count
        } else {
            $payloadName = 'response.json'; $payload = [byte[]]$Http.bytes
        }
        Write-Durable (Join-Path $stage $payloadName) $payload
        $payloadHash = Hash-Bytes $payload
        $payloadLength = [long]$payload.Length
    } else {
        $inspection = @{ counts = @{}; page = $null; quality = @{ truncation = '不明'
            issues = @((New-Issue 'HTTP_404_UNAVAILABLE_REASON_UNKNOWN' $ResourceId)); blockingObservations = 1L
            unspecifiedUnavailableReason = '不明' } }
        $savedCounts = @{}; $payloadName = $null; $payloadHash = $null; $payloadLength = 0L
    }
    $m = @{
        schemaVersion = 1L; collectionId = $script:CP.collectionId; organizationUuid = $script:CP.organizationUuid
        sequence = $sequence; previousManifestHash = $script:CP.lastManifestHash
        stream = $Stream; scanId = $ScanId; kind = $Kind; resourceId = $ResourceId; parentId = $ParentId
        requestHash = $Request.hash; relativeUri = $Request.relativeUri
        fetchedAtUtc = $Http.fetchedAtUtc; acquiredDateJst = $jst.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        httpStatus = [long]$Http.httpStatus; requestId = $Http.requestId
        result = $(if ($Http.available) { 'saved' } else { 'unavailable_recorded' })
        reason = $(if ($Http.available) { $null } else { '不明' })
        errorType = $(if ($Http.available) { $null } else { $Http.errorType })
        payloadFile = $payloadName; payloadSha256 = $payloadHash; payloadLength = $payloadLength
        fetchedCounts = $inspection.counts; savedCounts = $savedCounts
        duplicateActivityEvents = $dedupCount; page = $inspection.page; quality = $inspection.quality
    }
    Write-CheckedJson (Join-Path $stage 'manifest.json') $m
    $manifestHash = Hash-File (Join-Path $stage 'manifest.json')
    # One same-volume rename commits raw JSON/JSONL and its receipt together.
    [IO.Directory]::Move($stage, $dest)
    foreach ($id in $newIds) { [void]$script:EventIds.Add($id) }
    $script:CP.sequence = $sequence
    $script:CP.lastManifestHash = $manifestHash
    $script:CP.lastDataSaveUtc = $Http.fetchedAtUtc
    $script:CP[$Stream].active.lastSavedSequence = $sequence
    Add-Counts $script:Stats.saved $savedCounts
    $script:Stats.activityDuplicates += $dedupCount
    $script:Stats.responsesCommitted++
    if (-not $Http.available) { $script:Stats.unavailableRecorded++ }
    Save-Checkpoint
    $entry = @{ manifest = $m; directory = $dest }
    $script:Cache.Add(($ScanId + ':' + $Request.hash), $entry)
    Write-Log 'BUNDLE_COMMITTED' @{ sequence = $sequence; stream = $Stream; kind = $Kind
        result = $m.result; requestId = $m.requestId; savedCounts = $savedCounts; duplicateActivityEvents = $dedupCount }
    return $entry
}
function Get-Unit([string]$Stream, [string]$ScanId, [string]$Kind, [string]$Path,
    [hashtable]$Query, [string]$ResourceId = '', [string]$ParentId = '', [bool]$AllowUnavailable = $false) {
    $request = Request-Identity $Path $Query
    $key = $ScanId + ':' + $request.hash
    $entry = $null
    if ($script:Cache.TryGetValue($key, [ref]$entry)) {
        if ($script:RunReused.Add($key)) { Add-Counts $script:Stats.replayed $entry.manifest.savedCounts }
        $doc = $null
        if ($Stream -eq 'content' -and $entry.manifest.result -eq 'saved') {
            $doc = New-JsonDocument ([IO.File]::ReadAllBytes((Join-Path $entry.directory $entry.manifest.payloadFile)))
        }
        return @{ entry = $entry; document = $doc }
    }
    $http = Invoke-ApiGet $request.relativeUri $Kind $ResourceId $AllowUnavailable
    $doc = $null
    try {
        if ($http.available) { $doc = New-JsonDocument $http.bytes }
        $entry = Publish-Bundle $Stream $ScanId $Kind $ResourceId $ParentId $request $http $doc
        if ($Stream -eq 'activities' -and $null -ne $doc) { $doc.Dispose(); $doc = $null }
        return @{ entry = $entry; document = $doc }
    } catch {
        if ($null -ne $doc) { $doc.Dispose() }
        throw
    }
}
function Close-Unit($Unit) { if ($null -ne $Unit.document) { $Unit.document.Dispose() } }
function Touch-ContentUnit($Unit) {
    $m = $Unit.entry.manifest
    $key = $m.scanId + ':' + $m.requestHash
    if ($script:ScanTouched.Add($key)) {
        $script:ScanSummary.responses++
        Add-Counts $script:ScanSummary.savedCounts $m.savedCounts
        $script:ScanSummary.blockingObservations += [long]$m.quality.blockingObservations
        if ($m.result -ne 'saved') { $script:ScanSummary.unavailableResponses++ }
        foreach ($issue in $m.quality.issues) {
            if (-not $script:ScanSummary.issueCounts.ContainsKey($issue.code)) { $script:ScanSummary.issueCounts[$issue.code] = 0L }
            $script:ScanSummary.issueCounts[$issue.code]++
        }
    }
}
function Assert-NewCursor([System.Collections.Generic.HashSet[string]]$Seen, [string]$Cursor) {
    if ([string]::IsNullOrEmpty($Cursor) -or -not $Seen.Add($Cursor)) { Stop-Collector 'REPEATED_OR_EMPTY_PAGINATION_CURSOR' }
}
function Get-ReferencedMetadata([System.Text.Json.JsonElement]$Message, [string]$ScanId, [string]$ChatId) {
    foreach ($field in @('files','generated_files','artifacts')) {
        $refs = Get-J $Message $field
        if ($refs.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) { continue }
        foreach ($ref in $refs.EnumerateArray()) {
            if ($field -eq 'artifacts') {
                $id = Get-JString $ref 'version_id' -Required
                $kind = 'artifact'; $path = '/v1/compliance/apps/artifacts/' + [uri]::EscapeDataString($id)
            } elseif ($field -eq 'generated_files') {
                $id = Get-JString $ref 'id' -Required
                $kind = 'generated_file'; $path = '/v1/compliance/apps/chats/generated-files/' + [uri]::EscapeDataString($id)
            } else {
                $id = Get-JString $ref 'id' -Required
                $kind = 'file'; $path = '/v1/compliance/apps/chats/files/' + [uri]::EscapeDataString($id)
            }
            $u = Get-Unit 'content' $ScanId $kind $path @{} $id $ChatId $true
            try { Touch-ContentUnit $u } finally { Close-Unit $u }
        }
    }
}
function Collect-Chat([string]$ScanId, [string]$ChatId) {
    $cursor = $null
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while ($true) {
        $q = @{ limit = '100'; order = 'asc'; tool_use_input_max_chars = '-1'; tool_result_max_chars = '-1' }
        if ($cursor) { $q.after_id = $cursor }
        $u = Get-Unit 'content' $ScanId 'messages' ('/v1/compliance/apps/chats/' + [uri]::EscapeDataString($ChatId) + '/messages') $q $ChatId '' $true
        try {
            Touch-ContentUnit $u
            if ($u.entry.manifest.result -ne 'saved') { break }
            foreach ($m in (Get-J $u.document.RootElement 'chat_messages').EnumerateArray()) {
                Get-ReferencedMetadata $m $ScanId $ChatId
            }
            $p = $u.entry.manifest.page
            if (-not $p.hasMore) { break }
            Assert-NewCursor $seen $p.next; $cursor = $p.next
        } finally { Close-Unit $u }
    }
}
function Collect-Project([string]$ScanId, [string]$ProjectId) {
    $path = '/v1/compliance/apps/projects/' + [uri]::EscapeDataString($ProjectId)
    $detail = Get-Unit 'content' $ScanId 'project' $path @{} $ProjectId '' $true
    try { Touch-ContentUnit $detail } finally { Close-Unit $detail }
    # Still check attachments if detail was unavailable; do not infer their availability.
    $page = $null
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while ($true) {
        $q = @{ limit = '100' }; if ($page) { $q.page = $page }
        $u = Get-Unit 'content' $ScanId 'attachments' ($path + '/attachments') $q $ProjectId '' $true
        try {
            Touch-ContentUnit $u
            if ($u.entry.manifest.result -ne 'saved') { break }
            foreach ($a in (Get-J $u.document.RootElement 'data').EnumerateArray()) {
                $id = Get-JString $a 'id' -Required
                $attachmentType = Get-JString $a 'type'
                if ($attachmentType -eq 'project_doc') {
                    $kind = 'document'; $childPath = '/v1/compliance/apps/projects/documents/' + [uri]::EscapeDataString($id)
                } elseif ($attachmentType -eq 'project_file') {
                    $kind = 'file'; $childPath = '/v1/compliance/apps/chats/files/' + [uri]::EscapeDataString($id)
                } else { continue }
                $child = Get-Unit 'content' $ScanId $kind $childPath @{} $id $ProjectId $true
                try { Touch-ContentUnit $child } finally { Close-Unit $child }
            }
            $p = $u.entry.manifest.page
            if (-not $p.hasMore) { break }
            Assert-NewCursor $seen $p.next; $page = $p.next
        } finally { Close-Unit $u }
    }
}
function Run-ContentScan {
    $a = $script:CP.content.active
    $script:ScanTouched.Clear()
    $script:ScanSummary = @{ scanId = $a.id; startedAtUtc = $a.startedAtUtc; completedAtUtc = $null
        responses = 0L; unavailableResponses = 0L; blockingObservations = 0L
        savedCounts = @{}; issueCounts = @{}; allDiscoveredFetchesSaved = $false
        withoutBlockingIssues = $false; allRequestedDataSaved = '不明'; completeness = '不明' }
    $cursor = $null
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while ($true) {
        $q = @{ 'organization_ids[]' = $script:CP.organizationUuid; limit = '100'; order_by = 'created_at' }
        if ($cursor) { $q.after_id = $cursor }
        $u = Get-Unit 'content' $a.id 'chats' '/v1/compliance/apps/chats' $q
        try {
            Touch-ContentUnit $u
            foreach ($chat in (Get-J $u.document.RootElement 'data').EnumerateArray()) {
                Collect-Chat $a.id (Get-JString $chat 'id' -Required)
            }
            $p = $u.entry.manifest.page
            if (-not $p.hasMore) { break }
            Assert-NewCursor $seen $p.next; $cursor = $p.next
        } finally { Close-Unit $u }
    }
    $page = $null; $seen.Clear()
    while ($true) {
        $q = @{ 'organization_ids[]' = $script:CP.organizationUuid; limit = '100' }
        if ($page) { $q.page = $page }
        $u = Get-Unit 'content' $a.id 'projects' '/v1/compliance/apps/projects' $q
        try {
            Touch-ContentUnit $u
            foreach ($project in (Get-J $u.document.RootElement 'data').EnumerateArray()) {
                Collect-Project $a.id (Get-JString $project 'id' -Required)
            }
            $p = $u.entry.manifest.page
            if (-not $p.hasMore) { break }
            Assert-NewCursor $seen $p.next; $page = $p.next
        } finally { Close-Unit $u }
    }
    $now = Utc-Text
    $script:ScanSummary.completedAtUtc = $now
    $script:ScanSummary.allDiscoveredFetchesSaved = ($script:ScanSummary.unavailableResponses -eq 0)
    $script:ScanSummary.withoutBlockingIssues = ($script:ScanSummary.blockingObservations -eq 0)
    $script:CP.content.lastScan = $script:ScanSummary
    $script:CP.content.lastCompletedScanUtc = $now
    if ($script:ScanSummary.withoutBlockingIssues) { $script:CP.content.lastSuccessUtc = $now }
    if ($a.initial) {
        $script:CP.content.initialEnumerationComplete = $true
        $script:CP.content.initialWithoutBlockingIssues = $script:ScanSummary.withoutBlockingIssues
    }
    $script:CP.content.active = $null
    Save-Checkpoint
    Write-Log 'CONTENT_SCAN_COMPLETED' $script:ScanSummary
}
function Start-ContentScan {
    $script:CP.content.active = @{ id = [guid]::NewGuid().ToString('N')
        initial = (-not $script:CP.content.initialEnumerationComplete); startedAtUtc = (Utc-Text)
        lastSavedSequence = $null }
    Save-Checkpoint
    Write-Log 'CONTENT_SCAN_STARTED' @{ scanId = $script:CP.content.active.id; initial = $script:CP.content.active.initial }
}
function Run-ActivityWindow {
    $a = $script:CP.activities.active
    $cursor = $null
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pages = 0L
    while ($true) {
        $q = @{ 'organization_ids[]' = $script:CP.organizationUuid; limit = '1000'; 'created_at.lt' = $a.upperUtc }
        if ($a.lowerUtc) { $q['created_at.gte'] = $a.lowerUtc }
        if ($cursor) { $q.after_id = $cursor }
        $u = Get-Unit 'activities' $a.id 'activities' '/v1/compliance/activities' $q
        try {
            $pages++
            $p = $u.entry.manifest.page
            if (-not $p.hasMore) { break }
            Assert-NewCursor $seen $p.next; $cursor = $p.next
        } finally { Close-Unit $u }
    }
    $script:CP.activities.initialComplete = $true
    $script:CP.activities.completedThroughUtc = $a.upperUtc
    $script:CP.activities.lastSuccessUtc = Utc-Text
    $script:CP.activities.lastWindow = @{ scanId = $a.id; lowerUtc = $a.lowerUtc; upperUtc = $a.upperUtc; pages = $pages }
    $script:CP.activities.active = $null
    Save-Checkpoint
    Write-Log 'ACTIVITY_WINDOW_COMPLETED' $script:CP.activities.lastWindow
}
function Start-ActivityWindow([datetimeoffset]$Upper) {
    $lower = $null
    if ($script:CP.activities.initialComplete) {
        $lower = Utc-Text ((Parse-Utc $script:CP.activities.completedThroughUtc).AddHours(-24))
    }
    $script:CP.activities.active = @{ id = [guid]::NewGuid().ToString('N')
        initial = (-not $script:CP.activities.initialComplete); lowerUtc = $lower; upperUtc = (Utc-Text $Upper)
        startedAtUtc = (Utc-Text); lastSavedSequence = $null }
    Save-Checkpoint
    Write-Log 'ACTIVITY_WINDOW_STARTED' $script:CP.activities.active
}

function Validate-Checkpoint {
    $c = $script:CP
    if ($c.schemaVersion -ne 1 -or $c.organizationUuid -cne $script:OrganizationUuid -or
        $c.collectionId -cnotmatch '^[a-f0-9]{32}$' -or $c.sequence -lt 0) {
        Stop-Collector 'CHECKPOINT_SCHEMA_OR_ORGANIZATION_MISMATCH' 4
    }
    if ($c.activities.initialComplete -isnot [bool] -or $c.content.initialEnumerationComplete -isnot [bool]) {
        Stop-Collector 'CHECKPOINT_COMPLETION_STATE_INVALID' 4
    }
    if ($c.sequence -eq 0 -and $null -ne $c.lastManifestHash) { Stop-Collector 'CHECKPOINT_SEQUENCE_INVALID' 4 }
    if ($c.sequence -gt 0 -and $c.lastManifestHash -cnotmatch '^[a-f0-9]{64}$') { Stop-Collector 'CHECKPOINT_HASH_MISSING' 4 }
    if ($c.activities.initialComplete) {
        [void](Parse-Utc $c.activities.completedThroughUtc); [void](Parse-Utc $c.activities.lastSuccessUtc)
        if ($null -eq $c.activities.lastWindow) { Stop-Collector 'ACTIVITY_COMPLETION_EVIDENCE_MISSING' 4 }
    } elseif ($null -ne $c.activities.completedThroughUtc -or $null -ne $c.activities.lastSuccessUtc) {
        Stop-Collector 'ACTIVITY_INITIAL_STATE_INCONSISTENT' 4
    }
    if ($c.content.initialEnumerationComplete) {
        if ($null -eq $c.content.lastScan -or $c.content.initialWithoutBlockingIssues -isnot [bool]) {
            Stop-Collector 'CONTENT_COMPLETION_EVIDENCE_MISSING' 4
        }
        [void](Parse-Utc $c.content.lastCompletedScanUtc)
    } elseif ($null -ne $c.content.lastCompletedScanUtc -or $null -ne $c.content.lastScan) {
        Stop-Collector 'CONTENT_INITIAL_STATE_INCONSISTENT' 4
    }
    foreach ($stream in @('activities','content')) {
        $a = $c[$stream].active
        if ($null -eq $a) { continue }
        if ($a.id -cnotmatch '^[a-f0-9]{32}$' -or $a.initial -isnot [bool]) { Stop-Collector 'ACTIVE_SCAN_INVALID' 4 }
        [void](Parse-Utc $a.startedAtUtc)
        $done = if ($stream -eq 'activities') { $c.activities.initialComplete } else { $c.content.initialEnumerationComplete }
        if ($a.initial -eq $done) { Stop-Collector 'ACTIVE_INITIAL_STATE_INCONSISTENT' 4 }
        if ($stream -eq 'activities') {
            $upper = Parse-Utc $a.upperUtc
            if ($a.initial -and $null -ne $a.lowerUtc) { Stop-Collector 'INITIAL_LOWER_BOUND_INVALID' 4 }
            if (-not $a.initial) {
                if ((Parse-Utc $a.lowerUtc) -ge $upper) { Stop-Collector 'ACTIVITY_WINDOW_INVALID' 4 }
                if ($a.lowerUtc -cne (Utc-Text ((Parse-Utc $c.activities.completedThroughUtc).AddHours(-24)))) {
                    Stop-Collector 'ACTIVITY_WINDOW_START_INCONSISTENT' 4
                }
            }
        }
    }
}
function Restore-Storage {
    # Integrity is checked from disk, not from a potentially ahead-of-data dedup index.
    $allFiles = @(Get-ChildItem -LiteralPath $script:RawPath -Recurse -File -Force)
    $expectedFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $manifestFiles = @($allFiles | Where-Object { $_.Name -ceq 'manifest.json' })
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $manifestFiles) {
        $m = Read-CheckedJson $f.FullName
        if ($m.schemaVersion -ne 1 -or $m.collectionId -cne $script:CP.collectionId -or
            $m.organizationUuid -cne $script:OrganizationUuid -or $m.stream -notin @('activities','content')) {
            Stop-Collector 'BUNDLE_IDENTITY_MISMATCH' 4
        }
        $when = Parse-Utc $m.fetchedAtUtc
        $jst = $when.ToOffset([timespan]::FromHours(9))
        $expected = Join-Path $script:RawPath (Join-Path $jst.ToString('yyyy\\MM\\dd')
            (Join-Path $m.stream ('b_' + ([long]$m.sequence).ToString('D14'))))
        if (-not [string]::Equals($f.DirectoryName, $expected, [StringComparison]::OrdinalIgnoreCase) -or
            $m.acquiredDateJst -cne $jst.ToString('yyyy-MM-dd')) { Stop-Collector 'BUNDLE_PATH_MISMATCH' 4 }
        if ($m.scanId -cnotmatch '^[a-f0-9]{32}$' -or
            (Hash-Bytes ($script:Utf8.GetBytes($m.relativeUri))) -cne $m.requestHash) { Stop-Collector 'BUNDLE_REQUEST_INVALID' 4 }
        [void]$expectedFiles.Add($f.FullName)
        if ($m.result -eq 'saved') {
            $expectedName = if ($m.stream -eq 'activities') { 'activities_' + $jst.ToString('yyyyMMdd') + '.jsonl' } else { 'response.json' }
            if ($m.payloadFile -cne $expectedName) { Stop-Collector 'BUNDLE_PAYLOAD_NAME_INVALID' 4 }
            $p = Join-Path $f.DirectoryName $expectedName
            if (-not [IO.File]::Exists($p) -or ([IO.FileInfo]::new($p)).Length -ne $m.payloadLength -or
                (Hash-File $p) -cne $m.payloadSha256) { Stop-Collector 'PAYLOAD_MISSING_OR_CORRUPT' 4 }
            [void]$expectedFiles.Add($p)
            if ($m.stream -eq 'activities') {
                $bs = [IO.File]::ReadAllBytes($p)
                if ($bs.Length -gt 0 -and $bs[-1] -ne 10) { Stop-Collector 'INCOMPLETE_JSONL_LAST_LINE' 4 }
                $reader = [IO.StringReader]::new($script:Utf8.GetString($bs))
                $n = 0L
                try {
                    while ($null -ne ($line = $reader.ReadLine())) {
                        if ($line.Length -eq 0) { Stop-Collector 'EMPTY_JSONL_LINE' 4 }
                        $d = New-JsonDocument ($script:Utf8.GetBytes($line))
                        try {
                            $id = Get-JString $d.RootElement 'id' -Required
                            Assert-Organization $d.RootElement -Nullable
                            if (-not $script:EventIds.Add($id)) { Stop-Collector 'DUPLICATE_SAVED_ACTIVITY_ID' 4 }
                            $n++
                        } finally { $d.Dispose() }
                    }
                } finally { $reader.Dispose() }
                if ($n -ne $m.savedCounts.activity_events) { Stop-Collector 'ACTIVITY_COUNT_INCONSISTENT' 4 }
            } else {
                $d = New-JsonDocument ([IO.File]::ReadAllBytes($p))
                try { [void](Inspect-Response $m.kind $d.RootElement $m.resourceId) } finally { $d.Dispose() }
            }
        } elseif ($m.result -ne 'unavailable_recorded' -or $null -ne $m.payloadFile -or $m.httpStatus -ne 404) {
            Stop-Collector 'BUNDLE_RESULT_INVALID' 4
        }
        $entries.Add(@{ manifest = $m; directory = $f.DirectoryName; manifestHash = (Hash-File $f.FullName) })
    }
    foreach ($f in $allFiles) {
        if (-not $expectedFiles.Contains($f.FullName)) { Stop-Collector 'UNRECOGNIZED_RAW_FILE_RECOVERY_REQUIRED' 4 }
    }
    $sequence = 0L; $previousHash = $null; $checkpointHash = $null; $orphan = $null
    $scanIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($e in ($entries | Sort-Object { [long]$_.manifest.sequence })) {
        $m = $e.manifest; $sequence++
        if ($m.sequence -ne $sequence -or $m.previousManifestHash -cne $previousHash) { Stop-Collector 'BUNDLE_SEQUENCE_OR_CHAIN_BROKEN' 4 }
        $previousHash = $e.manifestHash
        if ($sequence -eq $script:CP.sequence) { $checkpointHash = $previousHash }
        if ($sequence -gt $script:CP.sequence) {
            if ($sequence -ne ([long]$script:CP.sequence + 1) -or $null -eq $script:CP[$m.stream].active -or
                $script:CP[$m.stream].active.id -cne $m.scanId) { Stop-Collector 'UNEXPECTED_UNCHECKPOINTED_BUNDLE' 4 }
            $orphan = $e
        }
        [void]$scanIds.Add($m.scanId)
        $cacheKey = $m.scanId + ':' + $m.requestHash
        if ($script:Cache.ContainsKey($cacheKey)) { Stop-Collector 'DUPLICATE_SCAN_REQUEST_BUNDLE' 4 }
        # Only unfinished scans need replay caches; historical receipts remain on disk.
        if ($null -ne $script:CP[$m.stream].active -and $script:CP[$m.stream].active.id -ceq $m.scanId) {
            $script:Cache.Add($cacheKey, $e)
        }
    }
    if ($sequence -lt $script:CP.sequence -or $checkpointHash -cne $script:CP.lastManifestHash) {
        Stop-Collector 'CHECKPOINT_AHEAD_OF_DATA_OR_HASH_MISMATCH' 4
    }
    if ($script:CP.activities.initialComplete -and -not $scanIds.Contains($script:CP.activities.lastWindow.scanId)) {
        Stop-Collector 'ACTIVITY_COMPLETION_DATA_MISSING' 4
    }
    if ($script:CP.content.initialEnumerationComplete -and -not $scanIds.Contains($script:CP.content.lastScan.scanId)) {
        Stop-Collector 'CONTENT_COMPLETION_DATA_MISSING' 4
    }
    if ($null -ne $orphan) {
        $m = $orphan.manifest
        $script:CP.sequence = $m.sequence; $script:CP.lastManifestHash = $orphan.manifestHash
        $script:CP.lastDataSaveUtc = $m.fetchedAtUtc
        $script:CP[$m.stream].active.lastSavedSequence = $m.sequence
        Save-Checkpoint
        $script:Stats.recoveredBundles++
        Write-Log 'DURABLE_BUNDLE_ADOPTED' @{ sequence = $m.sequence; stream = $m.stream; scanId = $m.scanId }
    }
    # Unpublished staging/temp files are retained, not counted as saved data.
    $leftovers = @((Get-ChildItem -LiteralPath $script:StagingPath -Force))
    $leftovers += @(Get-ChildItem -LiteralPath $script:StatePath -Filter 'checkpoint.json.tmp.*' -File -Force)
    if ($leftovers.Count -gt 0) {
        $quarantine = Join-Path (Join-Path $script:StatePath 'recovery') $script:RunId
        [void][IO.Directory]::CreateDirectory($quarantine)
        foreach ($f in $leftovers) {
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $quarantine $f.Name)
        }
        Write-Log 'UNCOMMITTED_FILES_QUARANTINED' @{ count = $leftovers.Count }
    }
    Write-Log 'STORAGE_VALIDATED' @{ bundles = $sequence; uniqueActivityEvents = $script:EventIds.Count }
}
function New-Checkpoint {
    return @{ schemaVersion = 1L; collectionId = [guid]::NewGuid().ToString('N'); organizationUuid = $script:OrganizationUuid
        sequence = 0L; lastManifestHash = $null; lastDataSaveUtc = $null
        activities = @{ initialComplete = $false; completedThroughUtc = $null; lastSuccessUtc = $null; lastWindow = $null; active = $null }
        content = @{ initialEnumerationComplete = $false; initialWithoutBlockingIssues = $null
            lastCompletedScanUtc = $null; lastSuccessUtc = $null; lastScan = $null; active = $null } }
}
function Get-Mode([string]$Stream) {
    if ($null -ne $script:CP[$Stream].active) { return '途中再開' }
    $done = if ($Stream -eq 'activities') { $script:CP.activities.initialComplete } else { $script:CP.content.initialEnumerationComplete }
    if ($done) { return '日次取得' }
    return '初回取得'
}

$exitCode = 1
$failure = $null
$startCheckpoint = $null
$modes = @{}
$processCompleted = $false
try {
    if (-not $IsWindows -or -not [Environment]::Is64BitProcess) { Stop-Collector 'REQUIRES_64_BIT_WINDOWS_POWERSHELL_7' 5 }
    [void][IO.Directory]::CreateDirectory($script:Root)
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($script:Root))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed -or $drive.DriveFormat -ne 'NTFS') { Stop-Collector 'LOCAL_FIXED_NTFS_REQUIRED' 5 }
    $script:StatePath = Join-Path $script:Root 'state'
    $script:RawPath = Join-Path $script:Root 'data\raw'
    $script:StagingPath = Join-Path $script:StatePath 'staging'
    $script:CheckpointPath = Join-Path $script:StatePath 'checkpoint.json'
    $logRoot = Join-Path $script:Root 'logs'
    foreach ($p in @($script:StatePath, $script:RawPath, $script:StagingPath, $logRoot)) { [void][IO.Directory]::CreateDirectory($p) }
    $script:RunLog = Join-Path $logRoot ('run_' + $script:StartedUtc.ToOffset([timespan]::FromHours(9)).ToString('yyyyMMdd_HHmmss') + '_' + $script:RunId + '.txt')
    $script:ErrorLog = Join-Path $logRoot ('error_' + $script:RunId + '.txt')
    Write-Durable $script:RunLog ([byte[]]::new(0)); Write-Durable $script:ErrorLog ([byte[]]::new(0))
    Write-Log 'START' @{ runId = $script:RunId; startedAtUtc = (Utc-Text $script:StartedUtc) }
    try {
        $script:Lock = [IO.File]::Open((Join-Path $script:StatePath 'collector.lock'),
            [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [System.IO.IOException] {
        $win32 = $_.Exception.GetBaseException().HResult -band 0xFFFF
        if ($win32 -in @(32,33)) { Stop-Collector 'ANOTHER_INSTANCE_HOLDS_LOCK' 6 }
        throw
    }
    $rootItem = Get-Item -LiteralPath $script:Root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Collector 'REPARSE_POINT_NOT_ALLOWED' 5 }
    foreach ($f in (Get-ChildItem -LiteralPath $script:Root -Recurse -Force)) {
        if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Collector 'REPARSE_POINT_NOT_ALLOWED' 5 }
    }
    $script:FailurePhase = 'configuration'
    $configDoc = New-JsonDocument ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($ConfigPath)))
    try { $config = Convert-OwnElement $configDoc.RootElement } finally { $configDoc.Dispose() }
    if ($config -isnot [hashtable] -or $config.Count -ne 2 -or
        -not $config.ContainsKey('organizationUuid') -or -not $config.ContainsKey('acceptInlineContentInMessages')) {
        Stop-Collector 'CONFIG_REQUIRES_EXACTLY_TWO_FIELDS' 5
    }
    $uuid = [guid]::Empty
    if (-not [guid]::TryParseExact([string]$config.organizationUuid, 'D', [ref]$uuid) -or $uuid -eq [guid]::Empty) {
        Stop-Collector 'CONFIG_ORGANIZATION_UUID_REQUIRED' 5
    }
    $script:OrganizationUuid = $uuid.ToString('D')
    Write-Log 'ORGANIZATION' @{ organizationUuid = $script:OrganizationUuid }
    if ($config.acceptInlineContentInMessages -isnot [bool] -or -not $config.acceptInlineContentInMessages) {
        Stop-Collector 'INLINE_CONTENT_POLICY_NOT_ACCEPTED_READ_README' 5
    }
    # User scope belongs to the Windows account running THIS process, not the setup operator.
    $script:Key = [Environment]::GetEnvironmentVariable('CLAUDE_COMPLIANCE_ACCESS_KEY', [EnvironmentVariableTarget]::User)
    if ([string]::IsNullOrWhiteSpace($script:Key)) {
        $script:Key = [Environment]::GetEnvironmentVariable('CLAUDE_COMPLIANCE_ACCESS_KEY', [EnvironmentVariableTarget]::Process)
    }
    if ([string]::IsNullOrWhiteSpace($script:Key) -or -not $script:Key.StartsWith('sk-ant-api01-', [StringComparison]::Ordinal) -or
        $script:Key.Contains("`r") -or $script:Key.Contains("`n")) { Stop-Collector 'COMPLIANCE_ACCESS_KEY_MISSING_OR_WRONG_TYPE' 5 }
    if (-not ('ClaudeCollector.JsonLexical' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
namespace ClaudeCollector {
    public static class JsonLexical {
        // Input has already passed JsonDocument.Parse. Do not decode/re-encode JSON tokens.
        public static string Compact(string s) {
            var b = new StringBuilder(s.Length);
            bool quoted = false, escaped = false;
            foreach (char c in s) {
                if (quoted) {
                    b.Append(c);
                    if (escaped) escaped = false;
                    else if (c == '\\') escaped = true;
                    else if (c == '"') quoted = false;
                } else {
                    if (c == '"') { quoted = true; b.Append(c); }
                    else if (c != ' ' && c != '\t' && c != '\r' && c != '\n') b.Append(c);
                }
            }
            return b.ToString();
        }
    }
}
'@ -ErrorAction Stop
    }
    $script:FailurePhase = 'integrity'
    if ([IO.File]::Exists($script:CheckpointPath)) {
        $script:CP = Read-CheckedJson $script:CheckpointPath
        Validate-Checkpoint
    } else {
        $existingRaw = @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'data') -Recurse -Force | Where-Object { $_.FullName -ine $script:RawPath })
        $existingStage = @(Get-ChildItem -LiteralPath $script:StagingPath -Force)
        $existingState = @(Get-ChildItem -LiteralPath $script:StatePath -Force | Where-Object { $_.Name -notin @('collector.lock','staging','status.json') })
        $oldStatusPath = Join-Path $script:StatePath 'status.json'
        if ([IO.File]::Exists($oldStatusPath)) {
            $oldStatus = Read-CheckedJson $oldStatusPath
            if ($null -ne $oldStatus.endCheckpoint) { Stop-Collector 'CHECKPOINT_MISSING_RECOVERY_REQUIRED' 4 }
        }
        if ($existingRaw.Count -gt 0 -or $existingStage.Count -gt 0 -or $existingState.Count -gt 0) {
            Stop-Collector 'CHECKPOINT_MISSING_RECOVERY_REQUIRED' 4
        }
        $script:CP = New-Checkpoint
        Save-Checkpoint
    }
    $startCheckpoint = Own-Json $script:CP
    Restore-Storage
    $modes = @{ activities = (Get-Mode 'activities'); content = (Get-Mode 'content') }
    $script:Ready = $true
    $script:FailurePhase = 'collection'
    Write-Log 'RUN_MODES_AND_START_CHECKPOINT' @{ modes = $modes; checkpoint = $script:CP }
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $script:Client = [System.Net.Http.HttpClient]::new($handler, $true)
    $script:Client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    $cutoff = $script:StartedUtc.AddMinutes(-5)
    $resumingContent = ($null -ne $script:CP.content.active)
    if ($null -ne $script:CP.activities.active) { Run-ActivityWindow }
    if (-not $script:CP.activities.initialComplete -or (Parse-Utc $script:CP.activities.completedThroughUtc) -lt $cutoff) {
        Start-ActivityWindow $cutoff
        Run-ActivityWindow
    }
    if ($resumingContent) { Run-ContentScan }
    Start-ContentScan
    Run-ContentScan
    $processCompleted = $true
    # The API has documented/unknown coverage limits, even with all GETs saved.
    $exitCode = 2
} catch {
    $script:Stats.errors++
    $code = 'LOCAL_OR_JSON_OR_IO_FAILURE'
    $ex = $_.Exception
    $requestedExit = $null
    $candidate = $ex
    while ($null -ne $candidate) {
        if ($candidate.Data.Contains('CollectorCode')) { $code = [string]$candidate.Data['CollectorCode'] }
        if ($candidate.Data.Contains('CollectorExitCode')) { $requestedExit = [int]$candidate.Data['CollectorExitCode']; break }
        $candidate = $candidate.InnerException
    }
    if ($null -ne $requestedExit) { $exitCode = $requestedExit }
    elseif ($script:FailurePhase -eq 'integrity') { $exitCode = 4 }
    elseif ($script:FailurePhase -eq 'configuration') { $exitCode = 5 }
    else { $exitCode = 1 }
    $baseException = $ex.GetBaseException()
    $failure = @{ code = $code; exceptionType = $baseException.GetType().FullName; hresult = [long]$baseException.HResult
        scriptLine = [long]$_.InvocationInfo.ScriptLineNumber; request = $script:CurrentRequest }
    try { Write-Log 'STOPPED' $failure -ErrorEntry } catch { }
} finally {
    $ended = Utc-Text
    $incomplete = (-not $processCompleted)
    $endCheckpoint = $null
    $endCheckpointRead = 'not_loaded'
    if ($null -ne $script:CP) {
        # Report the persisted checkpoint, never a mutated in-memory value whose save failed.
        try {
            $endCheckpoint = Read-CheckedJson $script:CheckpointPath
            $endCheckpointRead = 'read_from_disk'
        } catch {
            $endCheckpointRead = 'unreadable_or_not_saved'
            $script:Stats.errors++
            if ($processCompleted) { $exitCode = 4 }
            $processCompleted = $false; $incomplete = $true
            if ($null -eq $failure) { $failure = @{ code = 'END_CHECKPOINT_UNREADABLE'; request = $script:CurrentRequest } }
        }
    }
    $status = @{ schemaVersion = 1L; runId = $script:RunId; startedAtUtc = (Utc-Text $script:StartedUtc)
        endedAtUtc = $ended; exitCode = [long]$exitCode; processCompleted = $processCompleted
        incomplete = $incomplete; coverage = '不明'; constraints = $script:Constraints
        modes = $modes; counts = $script:Stats; failure = $failure
        startCheckpointJson = $startCheckpoint; endCheckpoint = $endCheckpoint; endCheckpointRead = $endCheckpointRead }
    # A competing invocation must not overwrite the real collector's status.
    if ($null -ne $script:Lock) {
        try {
            $statusName = Join-Path $script:StatePath 'status.json'
            Write-CheckedJson $statusName $status -Replace
        } catch { $exitCode = 1; $processCompleted = $false; $status.exitCode = 1L; $status.incomplete = $true; $status.processCompleted = $false }
    }
    try { Write-Log 'END' $status } catch { $exitCode = 1; $processCompleted = $false }
    if ($null -ne $script:Client) { $script:Client.Dispose() }
    if ($null -ne $script:Lock) { $script:Lock.Dispose() }
    $script:Key = $null
    # Only fixed labels/numbers are written to the console, never raw exception text.
    [Console]::WriteLine(('ClaudeComplianceCollector exit={0}; processCompleted={1}; see protected logs/state.' -f $exitCode, $processCompleted))
}
exit $exitCode
