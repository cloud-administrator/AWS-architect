#requires -Version 7.4
<#
Runs the supplied Claude compliance collector unchanged, then submits at most
one App Bridge user message if final completion cannot be confirmed.
Read AppBridge_Setup_Guide_JA.md before scheduling this file.

IMPORTANT: This particular collector completes with exit 2, not exit 0.
Wrapper exits: 0 = completed / notification test accepted;
               1 = collection or launch failed, notification command returned 0;
              10 = notification command failed or could not be started.
#>
[CmdletBinding()]
param(
    # EDIT THESE THREE PATHS to match the current Windows installation.
    [string]$CollectorPath = 'C:\ClaudeComplianceCollector\Collect-ClaudeCompliance(3)(1).ps1',
    [string]$ConfigPath = 'C:\ClaudeComplianceCollector\config.json',
    [string]$SendErrorExPath = 'C:\REPLACE_WITH_AGENT_INSTALL_FOLDER\CLI\SendErrorEx.exe',

    [string]$LogDirectory = 'C:\ClaudeComplianceCollector\logs\AppBridgeWrapper',
    [string]$PowerShellPath = (Join-Path $PSHOME 'pwsh.exe'),

    # Sends one real TEST notification; does not run the collector.
    [switch]$TestNotification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# A deliberate native exit 2 must not become a terminating PowerShell error.
$PSNativeCommandUseErrorActionPreference = $false

# Must match the App Bridge routing condition: ^91CC-001-E$
$notificationCode = '91CC-001-E'
$expectedCompletionLine = 'ClaudeComplianceCollector exit=2; processCompleted=True; see protected logs/state.'
$runId = [guid]::NewGuid().ToString('N')
$startedAt = [datetimeoffset]::Now
$utf8 = [System.Text.UTF8Encoding]::new($false)
$script:WrapperLogPath = $null
$script:LogWarningShown = $false
$collectorExitCode = $null
$collectorCompleted = $false
$failureKind = 'COLLECTOR_NOT_STARTED'
$failureType = 'none'

# Log failure must not prevent the single notification attempt.
function Write-WrapperLog([string]$Text) {
    try {
        if (-not $script:WrapperLogPath) { throw 'WRAPPER_LOG_UNAVAILABLE' }
        [IO.File]::AppendAllText($script:WrapperLogPath, $Text + "`r`n", $utf8)
    } catch {
        if (-not $script:LogWarningShown) {
            [Console]::Error.WriteLine('Wrapper log unavailable. Check LogDirectory permission and free space.')
            $script:LogWarningShown = $true
        }
    }
}

try {
    if (-not [IO.Path]::IsPathFullyQualified($LogDirectory)) { throw 'ABSOLUTE_LOG_PATH_REQUIRED' }
    [void][IO.Directory]::CreateDirectory($LogDirectory)
    $script:WrapperLogPath = Join-Path $LogDirectory ('wrapper_' + $startedAt.ToString('yyyyMMdd_HHmmss') + '_' + $runId + '.log')
} catch {
    $script:WrapperLogPath = $null
}
Write-WrapperLog ('START runId={0}; startedAt={1}; testNotification={2}' -f $runId, $startedAt.ToString('o'), [bool]$TestNotification)

if ($TestNotification) {
    $failureKind = 'TEST_NOTIFICATION'
    Write-WrapperLog 'TEST: collector skipped; one real notification will be submitted.'
} else {
    try {
        foreach ($requiredPath in @($PowerShellPath, $CollectorPath, $ConfigPath)) {
            if (-not [IO.Path]::IsPathFullyQualified($requiredPath)) { throw 'ABSOLUTE_PATH_REQUIRED' }
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw 'REQUIRED_FILE_NOT_FOUND' }
        }

        # Use a child process so the collector's exit cannot terminate this wrapper.
        # Its own retries run to completion before anything is notified here.
        Push-Location -LiteralPath ([IO.Path]::GetDirectoryName($CollectorPath))
        try {
            $LASTEXITCODE = $null
            $collectorOutput = @(& $PowerShellPath -NoLogo -NoProfile -NonInteractive -File $CollectorPath -ConfigPath $ConfigPath 2>&1)
            $collectorExitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        $lines = @($collectorOutput | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $markerLines = @($lines | Where-Object { $_ -ceq $expectedCompletionLine })
        $lastLineMatches = ($lines.Count -gt 0 -and $lines[-1] -ceq $expectedCompletionLine)
        $collectorCompleted = ($null -ne $collectorExitCode -and $collectorExitCode -eq 2 -and $markerLines.Count -eq 1 -and $lastLineMatches)

        Write-WrapperLog ('COLLECTOR exit={0}; completed={1}' -f $collectorExitCode, $collectorCompleted)
        foreach ($line in $lines) { Write-WrapperLog ('COLLECTOR_OUTPUT ' + $line) }

        if (-not $collectorCompleted) {
            $failureKind = if ($collectorExitCode -in @(1, 3, 4, 5, 6)) { 'COLLECTOR_FINAL_FAILURE' } else { 'COMPLETION_NOT_CONFIRMED' }
        }
    } catch {
        $collectorCompleted = $false
        $failureKind = 'WRAPPER_OR_LAUNCH_FAILURE'
        $failureType = $_.Exception.GetType().FullName
        # Do not send raw exception text, API bodies, credentials or log contents.
        Write-WrapperLog ('WRAPPER_FAILURE type={0}; line={1}' -f $failureType, $_.InvocationInfo.ScriptLineNumber)
    }

    if ($collectorCompleted) {
        Write-WrapperLog ('END wrapperExit=0; notificationAttempted=False; endedAt=' + [datetimeoffset]::Now.ToString('o'))
        [Console]::WriteLine('Collection procedure completed (collector exit 2). No notification. Wrapper exit 0.')
        exit 0
    }
}

$endedAt = [datetimeoffset]::Now
$exitText = if ($null -eq $collectorExitCode) { 'not_available' } else { [string]$collectorExitCode }
$logText = if ($script:WrapperLogPath) { $script:WrapperLogPath } else { 'unavailable' }
$subject = if ($TestNotification) { '[TEST] Claude コンプライアンスログ収集 通知確認' } else { '[ERROR] Claude コンプライアンスログ収集 最終失敗' }
# SendErrorEx removes newlines/tabs. Use a short, single-line management summary.
$message = if ($TestNotification) {
    '通知経路の動作確認です。収集スクリプトは実行していません。'
} else {
    '収集処理の正常完了を確認できませんでした。保護されたローカルログを確認してください。'
}
$message += (' Host={0}; Node=%NodeCD%; RunId={1}; Started={2}; Ended={3}; CollectorExit={4}; Reason={5}; ExceptionType={6}; WrapperLog={7}; CollectorLogs=C:\ClaudeComplianceCollector\logs' -f [Environment]::MachineName, $runId, $startedAt.ToString('o'), $endedAt.ToString('o'), $exitText, $failureKind, $failureType, $logText)

# This is the ONLY notification call site. No notification retry is performed.
$notifySucceeded = $false
$notifyExitCode = $null
Write-WrapperLog ('NOTIFY code={0}; reason={1}; collectorExit={2}' -f $notificationCode, $failureKind, $exitText)
try {
    if (-not [IO.Path]::IsPathFullyQualified($SendErrorExPath)) { throw 'ABSOLUTE_NOTIFY_PATH_REQUIRED' }
    if (-not (Test-Path -LiteralPath $SendErrorExPath -PathType Leaf)) { throw 'SEND_ERROR_EX_NOT_FOUND' }
    if ($utf8.GetByteCount($subject) -ge 200 -or $utf8.GetByteCount($message) -ge 4000) { throw 'NOTIFICATION_TOO_LONG' }
    Push-Location -LiteralPath ([IO.Path]::GetDirectoryName($SendErrorExPath))
    try {
        $LASTEXITCODE = $null
        $notifyOutput = @(& $SendErrorExPath -c $notificationCode -s $subject -m $message -l node 2>&1)
        $notifyExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $notifySucceeded = ($null -ne $notifyExitCode -and $notifyExitCode -eq 0)
    Write-WrapperLog ('NOTIFY_RESULT exit={0}; commandSucceeded={1}' -f $notifyExitCode, $notifySucceeded)
    foreach ($line in $notifyOutput) { Write-WrapperLog ('NOTIFY_OUTPUT ' + [string]$line) }
} catch {
    Write-WrapperLog ('NOTIFY_FAILURE type={0}; line={1}' -f $_.Exception.GetType().FullName, $_.InvocationInfo.ScriptLineNumber)
    [Console]::Error.WriteLine('Notification command could not complete. Check SendErrorExPath, permissions and wrapper log. No retry.')
}

$wrapperExitCode = if (-not $notifySucceeded) { 10 } elseif ($TestNotification) { 0 } else { 1 }
Write-WrapperLog ('END wrapperExit={0}; notificationCommandSucceeded={1}; endedAt={2}' -f $wrapperExitCode, $notifySucceeded, [datetimeoffset]::Now.ToString('o'))
[Console]::WriteLine(('Wrapper exit={0}; collectorExit={1}; notifyExit={2}; log={3}' -f $wrapperExitCode, $exitText, $notifyExitCode, $logText))
exit $wrapperExitCode
