[CmdletBinding()]
param(
    [string]$TargetListPath,
    [string]$CodexToolRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($TargetListPath)) {
    $TargetListPath = Join-Path $PSScriptRoot 'targets.csv'
}
if ([string]::IsNullOrWhiteSpace($CodexToolRoot)) {
    $CodexToolRoot = Join-Path $PSScriptRoot 'CodexTool'
}

$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$currentSid = $currentIdentity.User.Value
if ($currentSid -ne 'S-1-5-18') {
    Write-Error "LocalSystemで実行されていません。Current=$($currentIdentity.Name) SID=$currentSid"
    exit 10
}
if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
    Write-Error '64ビットWindows PowerShellで実行されていません。RUN_AS_SYSTEM.cmdを使用してください。'
    exit 10
}

$computerName = [string]$env:COMPUTERNAME

function Test-EnabledValue {
    param([object]$Value)
    $text = ([string]$Value).Trim()
    if ($text -eq '1') { return $true }
    if ($text -eq '0') { return $false }
    throw "Enabled列は1または0で指定してください。値='$text'"
}

function Get-LocalTarget {
    param(
        [Parameter(Mandatory = $true)][string]$CsvPath,
        [Parameter(Mandatory = $true)][string]$LocalComputerName
    )

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        throw "targets.csvが見つかりません: $CsvPath"
    }
    $rows = @(Import-Csv -LiteralPath $CsvPath -Encoding UTF8)
    if ($rows.Count -eq 0) { throw 'targets.csvにデータ行がありません。' }
    $headers = @($rows[0].PSObject.Properties.Name)
    $expected = @('ComputerName', 'Domain', 'SamAccountName', 'Enabled')
    if ($headers.Count -ne $expected.Count) {
        throw 'targets.csvの列はComputerName,Domain,SamAccountName,Enabledの4列だけにしてください。'
    }
    foreach ($column in $expected) {
        if ($headers -notcontains $column) { throw "targets.csvに必須列'$column'がありません。" }
    }

    $enabled = @()
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $line = $i + 2
        $isEnabled = Test-EnabledValue -Value $row.Enabled
        $computer = ([string]$row.ComputerName).Trim()
        $domain = ([string]$row.Domain).Trim()
        $sam = ([string]$row.SamAccountName).Trim()
        if ([string]::IsNullOrWhiteSpace($computer) -or
            [string]::IsNullOrWhiteSpace($domain) -or
            [string]::IsNullOrWhiteSpace($sam)) {
            throw "targets.csvの${line}行目に空欄があります。"
        }
        if ($computer -notmatch '^[A-Za-z0-9-]{1,63}$') {
            throw "targets.csvの${line}行目: ComputerNameが不正です。"
        }
        if ($domain -match '[\\/@]' -or $sam -match '[\\/@]') {
            throw "targets.csvの${line}行目: DomainとSamAccountNameは分けて入力してください。"
        }
        if ($isEnabled) {
            $enabled += [PSCustomObject]@{
                ComputerName = $computer
                Domain = $domain
                SamAccountName = $sam
                RowNumber = $line
            }
        }
    }

    $duplicates = @($enabled | Group-Object -Property ComputerName | Where-Object { $_.Count -gt 1 })
    if ($duplicates.Count -gt 0) {
        throw ("同じComputerNameにEnabled=1の行が複数あります: {0}" -f (($duplicates | ForEach-Object { $_.Name }) -join ', '))
    }
    $local = @($enabled | Where-Object { $_.ComputerName -ieq $LocalComputerName })
    if ($local.Count -eq 0) {
        return $null
    }
    if ($local.Count -ne 1) { throw "端末'$LocalComputerName'の対象行を一意に特定できません。" }
    return $local[0]
}

try {
    $target = Get-LocalTarget -CsvPath $TargetListPath -LocalComputerName $computerName
} catch {
    Write-Error $_.Exception.Message
    exit 20
}
if ($null -eq $target) {
    Write-Error "端末'$computerName'に一致するEnabled=1の行がありません。何も変更していません。"
    exit 20
}

$openAIRoot = Join-Path $env:ProgramData 'OpenAI'
$deploymentRoot = Join-Path $openAIRoot 'CodexDeployment'
$logsRoot = Join-Path $deploymentRoot 'Logs'
$toolsRoot = Join-Path $deploymentRoot 'Tools'
$stateRoot = Join-Path $deploymentRoot 'State'
$authorizedStatePath = Join-Path $stateRoot 'AuthorizedTarget.json'

function Assert-NotReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "再解析ポイントは許可しません: $Path"
    }
}

function Set-ProtectedDirectoryAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ReadSid
    )

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $security = [System.Security.AccessControl.DirectorySecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $none = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $full = [System.Security.AccessControl.FileSystemRights]::FullControl
    $read = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
    $systemSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $adminsSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $security.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($systemSid, $full, $inherit, $none, $allow))
    $security.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($adminsSid, $full, $inherit, $none, $allow))
    if (-not [string]::IsNullOrWhiteSpace($ReadSid)) {
        $readerSid = [System.Security.Principal.SecurityIdentifier]::new($ReadSid)
        $security.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($readerSid, $read, $inherit, $none, $allow))
    }
    $security.SetOwner($adminsSid)
    Set-Acl -LiteralPath $Path -AclObject $security
}

try {
    New-Item -ItemType Directory -Path $openAIRoot -Force | Out-Null
    Assert-NotReparsePoint -Path $openAIRoot
    foreach ($path in @($deploymentRoot, $logsRoot, $toolsRoot, $stateRoot)) {
        Assert-NotReparsePoint -Path $path
        Set-ProtectedDirectoryAcl -Path $path
    }
} catch {
    Write-Error ("CodexDeployment管理領域の初期化に失敗しました: {0}" -f $_.Exception.Message)
    exit 20
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $logsRoot ("{0}_{1}_sandbox-setup.log" -f $timestamp, $computerName)
$resultFile = Join-Path $logsRoot ("{0}_sandbox_latest.json" -f $computerName)
$script:Result = [ordered]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    ComputerName = $computerName
    ExecutionIdentity = $currentIdentity.Name
    ExecutionSid = $currentSid
    TargetUser = $null
    TargetSid = $null
    ProfilePath = $null
    CodexHome = $null
    CodexVersion = $null
    PackageArchiveSha256 = $null
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
    try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch { }
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

function Assert-NoReparseTree {
    param([Parameter(Mandatory = $true)][string]$Path)
    Assert-NotReparsePoint -Path $Path
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "パッケージ内に再解析ポイントがあります: $($item.FullName)"
        }
    }
}

function Get-CodexConfigState {
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    $state = [ordered]@{
        TopLevelMode = $null
        ActiveProfile = $null
        ProfileSandboxEntries = @()
        LegacyKeys = @()
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return [PSCustomObject]$state
    }

    $lines = @(Get-Content -LiteralPath $ConfigPath -Encoding UTF8)
    $section = ''
    foreach ($raw in $lines) {
        $line = ([string]$raw).Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[([^\]]+)\]\s*(?:#.*)?$') {
            $section = $matches[1].Trim()
            continue
        }
        if ([string]::IsNullOrWhiteSpace($section) -and $line -match '^profile\s*=\s*["'']([^"'']+)["'']\s*(?:#.*)?$') {
            $state.ActiveProfile = $matches[1].Trim()
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

function Get-ConfigConflict {
    param([Parameter(Mandatory = $true)][string]$ConfigPath)
    $state = Get-CodexConfigState -ConfigPath $ConfigPath
    if (@($state.LegacyKeys).Count -gt 0) {
        return ("旧Windows sandboxキーを検出しました。自動削除せず停止します: {0}" -f ((@($state.LegacyKeys)) -join ', '))
    }
    $nonElevated = @($state.ProfileSandboxEntries | Where-Object { $_ -notmatch '(?i)=elevated$' })
    if ($nonElevated.Count -gt 0) {
        return ("プロファイル配下にelevated以外のWindows sandbox設定があります。トップレベル設定を上書きし得るため停止します: {0}" -f ($nonElevated -join ', '))
    }
    return $null
}

function Test-CodexPackageIntegrity {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) { throw "CodexToolがありません: $RootPath" }
    $required = @(
        'codex-package.json',
        'bin\codex.exe',
        'bin\codex-code-mode-host.exe',
        'codex-path\rg.exe',
        'codex-resources\codex-command-runner.exe',
        'codex-resources\codex-windows-sandbox-setup.exe',
        'PACKAGE_INFO.json',
        'PACKAGE_SHA256.csv'
    )
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf)) {
            throw "Codexフルパッケージが不足しています: $relative"
        }
    }

    $manifestPath = Join-Path $RootPath 'PACKAGE_SHA256.csv'
    $rows = @(Import-Csv -LiteralPath $manifestPath -Encoding UTF8)
    if ($rows.Count -eq 0) { throw 'PACKAGE_SHA256.csvが空です。' }
    $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $manifestPaths = @{}
    foreach ($row in $rows) {
        $relative = ([string]$row.RelativePath).Trim().Replace('/', '\')
        $expectedHash = ([string]$row.SHA256).Trim().ToUpperInvariant()
        [int64]$expectedLength = 0
        if ([string]::IsNullOrWhiteSpace($relative) -or [System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.(\\|$)') {
            throw "マニフェスト相対パスが不正です: $relative"
        }
        if ($expectedHash -notmatch '^[0-9A-F]{64}$') { throw "マニフェストSHA-256が不正です: $relative" }
        if (-not [int64]::TryParse(([string]$row.Length).Trim(), [ref]$expectedLength)) { throw "Lengthが不正です: $relative" }
        $key = $relative.ToLowerInvariant()
        if ($manifestPaths.ContainsKey($key)) { throw "マニフェストに重複パスがあります: $relative" }
        $manifestPaths[$key] = $true
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $rootFull $relative))
        if (-not $candidate.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw "パッケージ外のパスです: $relative" }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "ファイルがありません: $relative" }
        $item = Get-Item -LiteralPath $candidate -Force
        if ([int64]$item.Length -ne $expectedLength) { throw "ファイルサイズ不一致: $relative" }
        $actualHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($actualHash -cne $expectedHash) { throw "SHA-256不一致: $relative" }
    }
    foreach ($file in Get-ChildItem -LiteralPath $RootPath -File -Recurse -Force) {
        $relative = $file.FullName.Substring($rootFull.Length).TrimStart('\')
        if ($relative -ieq 'PACKAGE_SHA256.csv') { continue }
        if (-not $manifestPaths.ContainsKey($relative.ToLowerInvariant())) { throw "未承認ファイルがあります: $relative" }
    }
    return (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToUpperInvariant()
}

Write-Log -Message 'Codex elevated sandboxの事前構成を開始します。'
Write-Log -Message ("端末={0} 実行主体={1}" -f $computerName, $currentIdentity.Name)

try {
    $qualifiedUser = "{0}\{1}" -f $target.Domain, $target.SamAccountName
    $script:Result.TargetUser = $qualifiedUser
    Write-Log -Message ("CSV一致: 行={0} 対象={1}" -f $target.RowNumber, $qualifiedUser)

    try {
        $targetSidObject = ([System.Security.Principal.NTAccount]::new($qualifiedUser)).Translate([System.Security.Principal.SecurityIdentifier])
        $targetSid = $targetSidObject.Value
    } catch {
        Stop-Deployment -Code 30 -Message ("ADアカウントをSIDへ変換できません: {0} / {1}" -f $qualifiedUser, $_.Exception.Message)
    }
    $script:Result.TargetSid = $targetSid

    # この端末に対する対象行を確認できた後でのみ、以前の承認状態を失効させます。
    if (Test-Path -LiteralPath $authorizedStatePath) {
        Remove-Item -LiteralPath $authorizedStatePath -Force
        Write-Log -Message '以前のAuthorizedTarget.jsonを失効させました。'
    }

    $profileKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$targetSid"
    if (-not (Test-Path -LiteralPath $profileKey)) {
        Stop-Deployment -Code 30 -Message "対象SIDのProfileListエントリがありません: $targetSid"
    }
    $registeredRaw = [string](Get-ItemProperty -LiteralPath $profileKey -Name 'ProfileImagePath').ProfileImagePath
    $registeredPath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($registeredRaw)).TrimEnd('\')

    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile | Where-Object { ([string]$_.SID) -eq $targetSid })
    if ($profiles.Count -ne 1) { Stop-Deployment -Code 30 -Message "対象SIDのWin32_UserProfileを一意に特定できません。Count=$($profiles.Count)" }
    $profile = $profiles[0]
    if ([bool]$profile.Special) { Stop-Deployment -Code 30 -Message '特殊プロファイルは対象にできません。' }
    [uint32]$profileStatus = [uint32]$profile.Status
    if (($profileStatus -band 1) -ne 0 -or ($profileStatus -band 4) -ne 0 -or ($profileStatus -band 8) -ne 0) {
        Stop-Deployment -Code 30 -Message "一時・必須・破損プロファイルは対象にできません。Status=$profileStatus"
    }
    $cimPath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$profile.LocalPath)).TrimEnd('\')
    if (-not [string]::Equals($registeredPath, $cimPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Deployment -Code 30 -Message "ProfileListとWin32_UserProfileのパスが一致しません。Registry='$registeredPath' CIM='$cimPath'"
    }
    $usersRoot = [System.IO.Path]::GetFullPath((Join-Path $env:SystemDrive 'Users')).TrimEnd('\')
    if (-not $registeredPath.StartsWith($usersRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Deployment -Code 30 -Message "プロファイルが許可範囲外です: $registeredPath"
    }
    if (-not (Test-Path -LiteralPath $registeredPath -PathType Container)) { Stop-Deployment -Code 30 -Message "プロファイルフォルダーがありません: $registeredPath" }
    $ntUser = Join-Path $registeredPath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $ntUser -PathType Leaf)) { Stop-Deployment -Code 30 -Message "NTUSER.DATがありません: $ntUser" }
    if ([bool]$profile.Loaded -or (Test-Path -LiteralPath "Registry::HKEY_USERS\$targetSid")) {
        Stop-Deployment -Code 30 -Message '対象ユーザーがログオン中、またはプロファイルハイブがロード中です。対象ユーザーをサインアウトして再実行してください。'
    }

    Assert-NotReparsePoint -Path $registeredPath
    Assert-NotReparsePoint -Path $ntUser
    $codexHome = Join-Path $registeredPath '.codex'
    Assert-NotReparsePoint -Path $codexHome
    $configPath = Join-Path $codexHome 'config.toml'
    Assert-NotReparsePoint -Path $configPath
    $script:Result.ProfilePath = $registeredPath
    $script:Result.CodexHome = $codexHome

    $conflict = Get-ConfigConflict -ConfigPath $configPath
    if (-not [string]::IsNullOrWhiteSpace($conflict)) { Stop-Deployment -Code 40 -Message $conflict }

    try {
        Assert-NoReparseTree -Path $CodexToolRoot
        $sourceManifestHash = Test-CodexPackageIntegrity -RootPath $CodexToolRoot
        $packageInfo = Get-Content -LiteralPath (Join-Path $CodexToolRoot 'PACKAGE_INFO.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $approvedVersion = ([string]$packageInfo.ApprovedVersion).Trim()
        $packageArchitecture = ([string]$packageInfo.Architecture).Trim().ToLowerInvariant()
        $archiveSha256 = ([string]$packageInfo.PackageArchiveSha256).Trim().ToUpperInvariant()
        if ($approvedVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') { throw 'PACKAGE_INFO.jsonのApprovedVersionが不正です。' }
        if ($archiveSha256 -notmatch '^[0-9A-F]{64}$') { throw 'PACKAGE_INFO.jsonのPackageArchiveSha256が不正です。' }
        $hostArchitecture = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        $expectedArchitecture = if ($hostArchitecture -ieq 'X64') { 'x64' } elseif ($hostArchitecture -ieq 'Arm64') { 'arm64' } else { throw "未対応アーキテクチャ: $hostArchitecture" }
        if ($packageArchitecture -ine $expectedArchitecture) { throw "CodexToolと端末のアーキテクチャが不一致です。Tool=$packageArchitecture Host=$expectedArchitecture" }
        Write-Log -Message "配布元パッケージ検証: OK / manifest=$sourceManifestHash / archive=$archiveSha256"
    } catch {
        Stop-Deployment -Code 50 -Message ("CodexToolの検証に失敗しました: {0}" -f $_.Exception.Message)
    }

    $stageRoot = Join-Path $toolsRoot ("{0}-{1}" -f $approvedVersion, $packageArchitecture)
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
    Set-ProtectedDirectoryAcl -Path $stageRoot
    foreach ($item in Get-ChildItem -LiteralPath $CodexToolRoot -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $stageRoot -Recurse -Force
    }
    try {
        $stageManifestHash = Test-CodexPackageIntegrity -RootPath $stageRoot
        if ($stageManifestHash -cne $sourceManifestHash) { throw 'コピー前後でPACKAGE_SHA256.csvのハッシュが変化しました。' }
    } catch {
        Stop-Deployment -Code 50 -Message ("管理領域へ配置したCodexToolの検証に失敗しました: {0}" -f $_.Exception.Message)
    }

    $codexExe = Join-Path $stageRoot 'bin\codex.exe'
    Push-Location (Split-Path -Parent $codexExe)
    try {
        $versionOutput = @(& $codexExe --version 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "codex --version失敗。Exit=$LASTEXITCODE" }
        $versionText = (($versionOutput | ForEach-Object { [string]$_ }) -join ' ').Trim()
        if ($versionText -notmatch [regex]::Escape($approvedVersion)) { throw "実行版が承認版と一致しません。Output=$versionText Approved=$approvedVersion" }
        $helpOutput = @(& $codexExe sandbox setup --help 2>&1)
        $helpText = (($helpOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
        if ($LASTEXITCODE -ne 0 -or $helpText -notmatch [regex]::Escape('--elevated') -or $helpText -notmatch [regex]::Escape('--user') -or $helpText -notmatch [regex]::Escape('--codex-home')) {
            throw '管理配布用sandbox setup引数を確認できません。'
        }
        $script:Result.CodexVersion = $versionText
        $script:Result.PackageArchiveSha256 = $archiveSha256
        Write-Log -Message "実行版: $versionText"

        $arguments = @('sandbox', 'setup', '--elevated', '--user', $qualifiedUser, '--codex-home', $codexHome)
        Write-Log -Message ("実行: codex sandbox setup --elevated --user `"{0}`" --codex-home `"{1}`"" -f $qualifiedUser, $codexHome)
        $commandOutput = @(& $codexExe @arguments 2>&1)
        $commandExit = $LASTEXITCODE
        foreach ($line in $commandOutput) { Write-Log -Message ("[codex] {0}" -f ([string]$line)) }
        if ($commandExit -ne 0) { Stop-Deployment -Code 60 -Message "codex sandbox setupが失敗しました。Exit=$commandExit" }
    } catch {
        Stop-Deployment -Code 60 -Message ("Codex実行に失敗しました: {0}" -f $_.Exception.Message)
    } finally {
        Pop-Location
    }

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { Stop-Deployment -Code 70 -Message "config.tomlがありません: $configPath" }
    Assert-NotReparsePoint -Path $configPath
    $postState = Get-CodexConfigState -ConfigPath $configPath
    if ($postState.TopLevelMode -ine 'elevated') { Stop-Deployment -Code 70 -Message "トップレベル[windows] sandboxがelevatedではありません。Mode=$($postState.TopLevelMode)" }
    if (@($postState.LegacyKeys).Count -gt 0) { Stop-Deployment -Code 70 -Message 'セットアップ後も旧Windows sandboxキーが残っています。' }
    $postNonElevated = @($postState.ProfileSandboxEntries | Where-Object { $_ -notmatch '(?i)=elevated$' })
    if ($postNonElevated.Count -gt 0) { Stop-Deployment -Code 70 -Message ("プロファイル配下にelevated以外の設定が残っています: {0}" -f ($postNonElevated -join ', ')) }

    $sandboxDirectory = Join-Path $codexHome '.sandbox'
    $markerPath = Join-Path $sandboxDirectory 'setup_marker.json'
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { Stop-Deployment -Code 70 -Message "setup_marker.jsonがありません: $markerPath" }
    Assert-NotReparsePoint -Path $sandboxDirectory
    Assert-NotReparsePoint -Path $markerPath
    try {
        $marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
        [int]$markerVersion = [int]$marker.version
        if ($markerVersion -le 0 -or [string]::IsNullOrWhiteSpace([string]$marker.offline_username) -or [string]::IsNullOrWhiteSpace([string]$marker.online_username)) {
            throw 'setup markerの必須値が不足しています。'
        }
    } catch {
        Stop-Deployment -Code 70 -Message ("setup markerを検証できません: {0}" -f $_.Exception.Message)
    }

    Set-ProtectedDirectoryAcl -Path $deploymentRoot -ReadSid $targetSid
    Set-ProtectedDirectoryAcl -Path $stateRoot -ReadSid $targetSid
    $authorizedState = [ordered]@{
        SchemaVersion = 1
        ComputerName = $computerName
        QualifiedUser = $qualifiedUser
        UserSid = $targetSid
        ProfilePath = $registeredPath
        CodexHome = $codexHome
        ConfigPath = $configPath
        SetupMarkerPath = $markerPath
        SetupMarkerVersion = $markerVersion
        ApprovedCodexVersion = $approvedVersion
        CodexPackageArchitecture = $packageArchitecture
        PackageArchiveSha256 = $archiveSha256
        ProvisionedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $temporaryState = Join-Path $stateRoot ("AuthorizedTarget.{0}.tmp" -f [Guid]::NewGuid().ToString('N'))
    $authorizedState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporaryState -Encoding UTF8
    Move-Item -LiteralPath $temporaryState -Destination $authorizedStatePath -Force

    $script:Result.Status = 'Succeeded'
    $script:Result.ExitCode = 0
    $script:Result.Message = 'Codex elevated sandboxの事前構成と対象ユーザー承認状態の作成が完了しました。'
    Write-Log -Message $script:Result.Message
    Save-Result
    exit 0
} catch {
    Stop-Deployment -Code 99 -Message ("予期しないエラー: {0}" -f $_.Exception.Message)
}
