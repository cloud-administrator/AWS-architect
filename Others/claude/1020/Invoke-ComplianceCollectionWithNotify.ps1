#requires -Version 5.0
<#
Windows PowerShell 5.0/5.1 用の収集実行・App Bridge 通知ラッパー。
元の収集スクリプトは変更せず、指定した PowerShell の別プロセスで実行します。
日本語を含むため、このファイルは UTF-8 BOM 付きで保存してください。

通常実行 : -File このファイル.ps1
正常試験 : -File このファイル.ps1 -TestMode Success
失敗試験 : -File このファイル.ps1 -TestMode Failure
試験モードでは収集本体を起動しません。Failure は実際に App Bridge に通知します。

ラッパーの終了コード:
  0 = 設定した正常終了コードで収集完了（通知なし）
  1 = 収集または起動準備に失敗。SendErrorEx は正常終了
  2 = 収集または起動準備に失敗。SendErrorEx も失敗／起動できない
SendErrorEx の正常終了は、メールの配送完了を意味しません。
#>
[CmdletBinding()]
param(
    [ValidateSet('None', 'Success', 'Failure')]
    [string]$TestMode = 'None'
)

# ==================== 設定する変数（ここから） ====================
$JobName = 'Claude'

# 添付 Claude 版は、64bit PowerShell 7.4 以上が必要です。
$CollectorPowerShell = 'C:\Program Files\PowerShell\7\pwsh.exe'
$CollectorScript = 'C:\ClaudeComplianceCollector\Collect-ClaudeCompliance.ps1'
$CollectorArguments = @('-ConfigPath', 'C:\ClaudeComplianceCollector\config.json')
$CollectorWorkingDirectory = 'C:\ClaudeComplianceCollector'

# 添付 Claude 版の処理完了は 2。ChatGPT 用は本体の仕様を確認して変更します。
$SuccessExitCodes = @(2)

# 実際の Agent インストール先に必ず変更してください。製品の既定パスではありません。
$SendErrorExPath = 'C:\REPLACE_WITH_AGENT_FOLDER\CLI\SendErrorEx.exe'
$NotificationCode = '9100-101-A'  # ChatGPT 用の例: 9100-102-A

$WrapperLogDirectory = 'C:\ComplianceNotification\logs\Claude'
$CollectorLogHint = 'C:\ClaudeComplianceCollector\logs'

# 収集本体を呼ぶ PowerShell のオプション。既存タスクに必要な指定があれば合わせます。
# -File と本体の引数は自動付与するため、この配列には入れません。
$CollectorHostArguments = @('-NoLogo', '-NoProfile', '-NonInteractive')
# ==================== 設定する変数（ここまで） ====================

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$RunId = [guid]::NewGuid().ToString('N')
$StartedAt = [DateTimeOffset]::Now
$RunLogPath = $null
$CollectorExitCode = $null
$SendExitCode = $null
$FailureReason = $null
$FailureException = $null
$Phase = 'WRAPPER_SETUP'

function Write-RunLog {
    param([string]$EventName, [string]$Detail)
    $line = '{0} run={1} event={2} {3}{4}' -f (
        [DateTimeOffset]::Now.ToString('o'), $RunId, $EventName,
        ($Detail -replace '[\r\n]+', ' '), [Environment]::NewLine
    )
    if ($null -ne $RunLogPath) {
        try {
            [IO.File]::AppendAllText($RunLogPath, $line, $Utf8)
            return
        } catch {
            # ログ保存失敗で通知処理まで停止させないよう、コンソールへ退避します。
        }
    }
    [Console]::Error.WriteLine($line.TrimEnd())
}

function ConvertTo-WindowsArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value.IndexOf([char]0) -ge 0) { throw 'ARGUMENT_CONTAINS_NUL' }
    # Windows のネイティブ引数規則: 引用符直前と末尾の \ を適切に二重化します。
    # cmd.exe / Invoke-Expression は使用せず、値を PowerShell コードとして評価しません。
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)\z', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-NativeProcess {
    param(
        [string]$Executable,
        [string[]]$ArgumentValues,
        [string]$WorkingDirectory
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $quotedArguments = @($ArgumentValues | ForEach-Object {
        ConvertTo-WindowsArgument -Value $_
    })
    $info.Arguments = $quotedArguments -join ' '
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true

    # 標準出力・標準エラーは親のハンドルを継承。途中のエラー出力では判定しません。
    # 収集本体の詳細は本体が保存する既存ログを確認してください。
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'PROCESS_START_FAILED' }
        $process.WaitForExit()
        return [int]$process.ExitCode
    } finally {
        $process.Dispose()
    }
}

function Limit-Utf8Text {
    param([string]$Text, [int]$MaxBytes)
    if ($Utf8.GetByteCount($Text) -le $MaxBytes) { return $Text }
    $suffix = '...'
    $builder = New-Object System.Text.StringBuilder
    $bytes = 0
    $limit = $MaxBytes - $Utf8.GetByteCount($suffix)
    # サロゲートペアを途中で分割しないよう、テキスト要素単位で短くします。
    $elements = [Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($elements.MoveNext()) {
        $element = $elements.GetTextElement()
        $elementBytes = $Utf8.GetByteCount($element)
        if (($bytes + $elementBytes) -gt $limit) { break }
        [void]$builder.Append($element)
        $bytes += $elementBytes
    }
    return $builder.ToString() + $suffix
}

try {
    if (-not [IO.Path]::IsPathRooted($WrapperLogDirectory)) {
        throw 'WRAPPER_LOG_DIRECTORY_MUST_BE_ABSOLUTE'
    }
    [void][IO.Directory]::CreateDirectory($WrapperLogDirectory)
    $RunLogPath = Join-Path $WrapperLogDirectory (
        '{0}_{1}.log' -f $StartedAt.ToString('yyyyMMdd_HHmmss'), $RunId
    )
    # この最初の書込みができなければ起動準備の失敗として通知します。
    [IO.File]::WriteAllText($RunLogPath, '', $Utf8)
    Write-RunLog 'START' ('job={0}; test={1}; collector={2}' -f $JobName, $TestMode, $CollectorScript)

    if (@($SuccessExitCodes).Count -eq 0) { throw 'SUCCESS_EXIT_CODES_EMPTY' }

    if ($TestMode -eq 'Success') {
        $CollectorExitCode = [int]$SuccessExitCodes[0]
        Write-RunLog 'TEST_SUCCESS' 'Collector was not started.'
    } elseif ($TestMode -eq 'Failure') {
        $FailureReason = 'TEST_FAILURE'
        Write-RunLog 'TEST_FAILURE' 'Collector was not started; one notification will be attempted.'
    } else {
        $Phase = 'COLLECTOR_POWERSHELL_NOT_FOUND'
        if (-not [IO.Path]::IsPathRooted($CollectorPowerShell) -or
            -not [IO.File]::Exists($CollectorPowerShell)) { throw $Phase }
        $Phase = 'COLLECTOR_SCRIPT_NOT_FOUND'
        if (-not [IO.Path]::IsPathRooted($CollectorScript) -or
            -not [IO.File]::Exists($CollectorScript)) { throw $Phase }
        $Phase = 'COLLECTOR_WORKING_DIRECTORY_NOT_FOUND'
        if (-not [IO.Path]::IsPathRooted($CollectorWorkingDirectory) -or
            -not [IO.Directory]::Exists($CollectorWorkingDirectory)) { throw $Phase }

        $Phase = 'COLLECTOR_START_OR_WAIT_FAILED'
        $arguments = @($CollectorHostArguments) + @('-File', $CollectorScript) + @($CollectorArguments)
        $CollectorExitCode = Invoke-NativeProcess -Executable $CollectorPowerShell `
            -ArgumentValues $arguments -WorkingDirectory $CollectorWorkingDirectory
        Write-RunLog 'COLLECTOR_EXIT' ('exit={0}' -f $CollectorExitCode)
        if ($SuccessExitCodes -notcontains $CollectorExitCode) {
            $FailureReason = 'COLLECTOR_EXIT_NOT_ACCEPTED'
        }
    }
} catch {
    $FailureReason = $Phase
    $baseException = $_.Exception.GetBaseException()
    $FailureException = '{0}; hresult={1}' -f $baseException.GetType().FullName, $baseException.HResult
    Write-RunLog 'WRAPPER_FAILURE' ('reason={0}; exception={1}' -f $FailureReason, $FailureException)
}

if ($null -eq $FailureReason) {
    Write-RunLog 'SUCCESS' ('collectorExit={0}; wrapperExit=0; notification=none' -f $CollectorExitCode)
    exit 0
}

$EndedAt = [DateTimeOffset]::Now
$exitText = if ($null -eq $CollectorExitCode) { '未取得（起動準備失敗または試験）' } else { [string]$CollectorExitCode }
$logText = if ($null -eq $RunLogPath) { $WrapperLogDirectory } else { $RunLogPath }
$subjectText = '[{0}] コンプライアンスログ収集失敗' -f $JobName
if ($TestMode -eq 'Failure') { $subjectText = '[TEST] ' + $subjectText }
$subject = Limit-Utf8Text -Text ($subjectText -replace '[\r\n\t]+', ' ') -MaxBytes 180
$body = Limit-Utf8Text -MaxBytes 3500 -Text (@(
    '最終的に処理が失敗したため通知します。'
    ('対象: {0}' -f $JobName)
    ('ホスト: {0}' -f [Environment]::MachineName)
    ('開始: {0}' -f $StartedAt.ToString('o'))
    ('終了: {0}' -f $EndedAt.ToString('o'))
    ('実行ID: {0}' -f $RunId)
    ('収集本体の終了コード: {0}' -f $exitText)
    ('判定理由: {0}' -f $FailureReason)
    ('ラッパーログ: {0}' -f $logText)
    ('収集本体のログ: {0}' -f $CollectorLogHint)
) -join [Environment]::NewLine)

# 通知を呼ぶ箇所はここだけ。失敗・戻り値不明でも再送しません。
$NotificationPhase = 'INVALID_NOTIFICATION_CODE'
try {
    if ($NotificationCode -notmatch '^9[1-5][A-Za-z0-9]{2}-[A-Za-z0-9]{3}-[A-Za-z0-9]\z') {
        throw 'INVALID_NOTIFICATION_CODE'
    }
    $NotificationPhase = 'SEND_ERROR_EX_NOT_FOUND'
    if (-not [IO.Path]::IsPathRooted($SendErrorExPath) -or
        -not [IO.File]::Exists($SendErrorExPath)) { throw 'SEND_ERROR_EX_NOT_FOUND' }
    $NotificationPhase = 'SEND_ERROR_EX_START_OR_WAIT_FAILED'
    Write-RunLog 'NOTIFY_ATTEMPT' ('reason={0}; code={1}' -f $FailureReason, $NotificationCode)
    $SendExitCode = Invoke-NativeProcess -Executable $SendErrorExPath `
        -ArgumentValues @('-c', $NotificationCode, '-s', $subject, '-m', $body, '-l', 'node') `
        -WorkingDirectory ([IO.Path]::GetDirectoryName($SendErrorExPath))
    Write-RunLog 'NOTIFY_EXIT' ('exit={0}' -f $SendExitCode)
    $NotificationPhase = 'SEND_ERROR_EX_NONZERO_EXIT'
    if ($SendExitCode -ne 0) { throw $NotificationPhase }
} catch {
    $baseException = $_.Exception.GetBaseException()
    Write-RunLog 'NOTIFY_FAILED' ('senderExit={0}; exception={1}; hresult={2}; reason={3}; wrapperExit=2' -f (
        $SendExitCode, $baseException.GetType().FullName, $baseException.HResult, $NotificationPhase
    ))
    [Console]::Error.WriteLine('App Bridge notification failed. Check the wrapper log and SendErrorEx configuration.')
    exit 2
}

Write-RunLog 'FAILURE_NOTIFIED' ('collectorExit={0}; senderExit=0; wrapperExit=1' -f $CollectorExitCode)
exit 1
