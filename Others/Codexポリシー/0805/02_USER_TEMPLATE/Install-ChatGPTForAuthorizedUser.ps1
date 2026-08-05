[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$currentSid = $currentIdentity.User.Value
$sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
if ($currentSid -eq 'S-1-5-18' -or $sessionId -eq 0) {
    Write-Error 'ログオンユーザーのセッションで実行されていません。SKYSEAの「システム権限で実行する」をOFFにしてください。'
    exit 10
}
if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
    Write-Error '64ビットWindows PowerShellで実行されていません。RUN_AS_TARGET_USER.cmdを使用してください。'
    exit 10
}

$AuthorizedStatePath = Join-Path $env:ProgramData 'OpenAI\CodexDeployment\State\AuthorizedTarget.json'

$computerName = [string]$env:COMPUTERNAME
$logRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexDeployment\Logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $logRoot ("{0}_{1}_chatgpt-install.log" -f $timestamp, $computerName)
$resultFile = Join-Path $logRoot 'ChatGPTInstallState.json'
$script:Result = [ordered]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    ComputerName = $computerName
    ExecutionIdentity = $currentIdentity.Name
    ExecutionSid = $currentSid
    SessionId = $sessionId
    AuthorizedUser = $null
    ProfilePath = $null
    WingetVersion = $null
    ProductId = '9PLM9XGG6VKS'
    Status = 'Started'
    ExitCode = 99
    Message = $null
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Save-Result {
    try {
        $script:Result.TimestampUtc = [DateTime]::UtcNow.ToString('o')
        $script:Result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultFile -Encoding UTF8
    } catch {
        Write-Log -Level 'WARN' -Message ("結果JSONの保存に失敗しました: {0}" -f $_.Exception.Message)
    }
}

function Stop-Deployment {
    param(
        [Parameter(Mandatory = $true)][int]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:Result.Status = 'Failed'
    $script:Result.ExitCode = $Code
    $script:Result.Message = $Message
    Write-Log -Level 'ERROR' -Message $Message
    Save-Result
    exit $Code
}

function Assert-NotReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "再解析ポイントは許可しません: $Path"
    }
}

function Get-CodexConfigState {
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    $state = [ordered]@{
        TopLevelMode = $null
        ProfileSandboxEntries = @()
        LegacyKeys = @()
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return [PSCustomObject]$state }
    $lines = @(Get-Content -LiteralPath $ConfigPath -Encoding UTF8)
    $section = ''
    foreach ($raw in $lines) {
        $line = ([string]$raw).Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[([^\]]+)\]\s*(?:#.*)?$') {
            $section = $matches[1].Trim()
            continue
        }
        if ($section -ieq 'windows' -and $line -match '^sandbox\s*=\s*["'']([^"'']+)["'']\s*(?:#.*)?$') {
            $state.TopLevelMode = $matches[1].Trim()
        }
        if ([string]::IsNullOrWhiteSpace($section) -and $line -match '^windows\.sandbox\s*=\s*["'']([^"'']+)["'']\s*(?:#.*)?$') {
            $state.TopLevelMode = $matches[1].Trim()
        }
        if ($section -match '^(?i:profiles\..+\.windows)$' -and $line -match '^sandbox\s*=\s*["'']([^"'']+)["'']\s*(?:#.*)?$') {
            $state.ProfileSandboxEntries += ("[{0}] sandbox={1}" -f $section, $matches[1].Trim())
        }
        if ($section -match '^(?i:profiles\..+)$' -and $line -match '^(?i:windows\.sandbox)\s*=\s*["'']([^"'']+)["'']\s*(?:#.*)?$') {
            $state.ProfileSandboxEntries += ("[{0}] windows.sandbox={1}" -f $section, $matches[1].Trim())
        }
        if ($section -match '^(?i:profiles\..+)$' -and $line -match '^(?i:windows)\s*=\s*\{.*\bsandbox\s*=\s*["'']([^"'']+)["'']') {
            $state.ProfileSandboxEntries += ("[{0}] windows.inline.sandbox={1}" -f $section, $matches[1].Trim())
        }
        if ([string]::IsNullOrWhiteSpace($section) -and $line -match '^(?i:profiles\..+\.windows\.sandbox)\s*=\s*["'']([^"'']+)["'']') {
            $state.ProfileSandboxEntries += ("{0}={1}" -f $matches[1], $matches[2].Trim())
        }
        if ($line -match '(?i)(^|\.)(experimental_windows_sandbox|elevated_windows_sandbox|enable_experimental_windows_sandbox)\s*=') {
            $state.LegacyKeys += ("[{0}] {1}" -f $section, $matches[2])
        }
    }
    return [PSCustomObject]$state
}

function Get-WingetExecutable {
    $command = Get-Command 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) { return $command.Source }
    $aliasPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $aliasPath -PathType Leaf) { return $aliasPath }
    $appInstaller = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($null -ne $appInstaller) {
        $candidate = Join-Path $appInstaller.InstallLocation 'winget.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Invoke-WingetLogged {
    param(
        [Parameter(Mandatory = $true)][string]$WingetPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )
    Write-Log -Message "winget $Label"
    $lines = @(& $WingetPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $lines) { Write-Log -Message ("[winget] {0}" -f ([string]$line)) }
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Text = (($lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    }
}

function Test-ChatGPTInstalled {
    param([Parameter(Mandatory = $true)][string]$WingetPath)
    $result = Invoke-WingetLogged -WingetPath $WingetPath -Label 'list' -Arguments @(
        'list', '--id', '9PLM9XGG6VKS', '--exact', '--disable-interactivity'
    )
    return ($result.ExitCode -eq 0 -and $result.Text -match '9PLM9XGG6VKS')
}

Write-Log -Message '対象ユーザーへの新しいChatGPT Windowsアプリ導入を開始します。'
Write-Log -Message ("実行主体={0} SID={1} SessionId={2}" -f $currentIdentity.Name, $currentSid, $sessionId)

try {
    if (-not (Test-Path -LiteralPath $AuthorizedStatePath -PathType Leaf)) {
        Stop-Deployment -Code 30 -Message 'SYSTEMジョブの承認状態がありません。先にSYSTEMジョブを成功させてください。'
    }
    Assert-NotReparsePoint -Path (Split-Path -Parent $AuthorizedStatePath)
    Assert-NotReparsePoint -Path $AuthorizedStatePath
    try {
        $state = Get-Content -LiteralPath $AuthorizedStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Stop-Deployment -Code 30 -Message ("AuthorizedTarget.jsonを読み取れません: {0}" -f $_.Exception.Message)
    }

    if ([int]$state.SchemaVersion -ne 1) { Stop-Deployment -Code 30 -Message 'AuthorizedTarget.jsonのSchemaVersionが未対応です。' }
    if ([string]$state.ComputerName -ine $computerName) { Stop-Deployment -Code 20 -Message '承認状態の端末名が現在の端末と一致しません。何も変更していません。' }
    if ([string]$state.UserSid -ne $currentSid) { Stop-Deployment -Code 20 -Message '現在のログオンユーザーはこの端末の承認対象ではありません。何も変更していません。' }

    $authorizedUser = [string]$state.QualifiedUser
    $profilePath = [System.IO.Path]::GetFullPath([string]$state.ProfilePath).TrimEnd('\')
    $currentProfilePath = [System.IO.Path]::GetFullPath([string]$env:USERPROFILE).TrimEnd('\')
    if (-not [string]::Equals($profilePath, $currentProfilePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Deployment -Code 40 -Message "AuthorizedTarget.jsonとUSERPROFILEが一致しません。Authorized='$profilePath' Current='$currentProfilePath'"
    }

    $profileKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$currentSid"
    if (-not (Test-Path -LiteralPath $profileKey)) { Stop-Deployment -Code 40 -Message '現在のSIDに対応するProfileListがありません。' }
    $registeredRaw = [string](Get-ItemProperty -LiteralPath $profileKey -Name 'ProfileImagePath').ProfileImagePath
    $registeredPath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($registeredRaw)).TrimEnd('\')
    if (-not [string]::Equals($registeredPath, $profilePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Deployment -Code 40 -Message "ProfileListと承認済みプロファイルが一致しません。Registry='$registeredPath' Authorized='$profilePath'"
    }
    Assert-NotReparsePoint -Path $profilePath
    $codexHome = [System.IO.Path]::GetFullPath([string]$state.CodexHome).TrimEnd('\')
    $configPath = [System.IO.Path]::GetFullPath([string]$state.ConfigPath)
    $markerPath = [System.IO.Path]::GetFullPath([string]$state.SetupMarkerPath)
    $expectedCodexHome = [System.IO.Path]::GetFullPath((Join-Path $profilePath '.codex')).TrimEnd('\')
    $expectedConfigPath = [System.IO.Path]::GetFullPath((Join-Path $expectedCodexHome 'config.toml'))
    $expectedMarkerPath = [System.IO.Path]::GetFullPath((Join-Path $expectedCodexHome '.sandbox\setup_marker.json'))
    if (-not [string]::Equals($codexHome, $expectedCodexHome, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($configPath, $expectedConfigPath, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($markerPath, $expectedMarkerPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Deployment -Code 40 -Message '承認状態のCodexパスが対象ユーザープロファイルの標準パスと一致しません。'
    }
    foreach ($path in @($codexHome, $configPath, (Split-Path -Parent $markerPath), $markerPath)) { Assert-NotReparsePoint -Path $path }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { Stop-Deployment -Code 40 -Message 'Codex config.tomlがありません。' }
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { Stop-Deployment -Code 40 -Message 'Codex setup_marker.jsonがありません。' }

    $configState = Get-CodexConfigState -ConfigPath $configPath
    if ($configState.TopLevelMode -ine 'elevated') { Stop-Deployment -Code 40 -Message 'CodexのトップレベルWindows sandboxがelevatedではありません。' }
    if (@($configState.LegacyKeys).Count -gt 0) { Stop-Deployment -Code 40 -Message 'Codex設定に旧Windows sandboxキーが残っています。' }
    $nonElevated = @($configState.ProfileSandboxEntries | Where-Object { $_ -notmatch '(?i)=elevated$' })
    if ($nonElevated.Count -gt 0) { Stop-Deployment -Code 40 -Message 'プロファイル配下にelevated以外のWindows sandbox設定があります。' }

    try {
        $marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $markerVersion = [int]$marker.version
        if ($markerVersion -le 0 -or $markerVersion -ne [int]$state.SetupMarkerVersion) { throw 'setup marker versionが承認状態と一致しません。' }
    } catch {
        Stop-Deployment -Code 40 -Message ("Codex setup markerを検証できません: {0}" -f $_.Exception.Message)
    }

    $script:Result.AuthorizedUser = $authorizedUser
    $script:Result.ProfilePath = $profilePath
    Write-Log -Message "対象照合: OK / $authorizedUser / $profilePath"

    $winget = Get-WingetExecutable
    if ([string]::IsNullOrWhiteSpace($winget)) { Stop-Deployment -Code 50 -Message 'winget.exeが見つかりません。Microsoft App Installerを対象ユーザーへ登録してください。' }
    $versionOutput = @(& $winget --version 2>&1)
    if ($LASTEXITCODE -ne 0) { Stop-Deployment -Code 50 -Message "winget --versionに失敗しました。Exit=$LASTEXITCODE" }
    $wingetVersion = (($versionOutput | ForEach-Object { [string]$_ }) -join ' ').Trim()
    $script:Result.WingetVersion = $wingetVersion
    Write-Log -Message "winget=$wingetVersion"

    $showResult = Invoke-WingetLogged -WingetPath $winget -Label 'show' -Arguments @(
        'show', '--id', '9PLM9XGG6VKS', '--source', 'msstore', '--exact',
        '--accept-source-agreements', '--disable-interactivity'
    )
    if ($showResult.ExitCode -ne 0 -or $showResult.Text -notmatch '9PLM9XGG6VKS' -or $showResult.Text -notmatch '(?i)OpenAI') {
        Stop-Deployment -Code 50 -Message "Microsoft Store上で製品ID 9PLM9XGG6VKS／発行元OpenAIを確認できません。Exit=$($showResult.ExitCode)"
    }

    if (Test-ChatGPTInstalled -WingetPath $winget) {
        $script:Result.Status = 'Succeeded'
        $script:Result.ExitCode = 0
        $script:Result.Message = '新しいChatGPT Windowsアプリは既にインストール済みです。'
        Write-Log -Message $script:Result.Message
        Save-Result
        exit 0
    }

    $installResult = Invoke-WingetLogged -WingetPath $winget -Label 'install' -Arguments @(
        'install', '--id', '9PLM9XGG6VKS', '--source', 'msstore', '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    if ($installResult.ExitCode -ne 0 -and -not (Test-ChatGPTInstalled -WingetPath $winget)) {
        Stop-Deployment -Code 60 -Message "ChatGPTアプリのインストールに失敗しました。winget Exit=$($installResult.ExitCode)"
    }
    if (-not (Test-ChatGPTInstalled -WingetPath $winget)) {
        Stop-Deployment -Code 70 -Message 'winget install後に製品ID 9PLM9XGG6VKSを確認できません。'
    }

    $script:Result.Status = 'Succeeded'
    $script:Result.ExitCode = 0
    $script:Result.Message = '新しいChatGPT Windowsアプリを承認対象ユーザーへインストールしました。'
    Write-Log -Message $script:Result.Message
    Save-Result
    exit 0
} catch {
    Stop-Deployment -Code 99 -Message ("予期しないエラー: {0}" -f $_.Exception.Message)
}
