[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f ]{40,59}$')]
    [string]$ApprovedSignerThumbprint
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:DefaultStateRoot = 'C:\ProgramData\Company\CodexProvisioning'
$script:StateRoot = $script:DefaultStateRoot
$script:LogPath = Join-Path $script:StateRoot 'provisioning.jsonl'
$script:Mutex = $null
$script:MutexOwned = $false

function ConvertTo-NormalizedThumbprint {
    param([string]$Value)
    return (($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant())
}

function New-ExitException {
    param(
        [int]$Code,
        [string]$Message
    )
    $exception = New-Object System.Exception($Message)
    $exception.Data['ExitCode'] = $Code
    return $exception
}

function Throw-Exit {
    param(
        [int]$Code,
        [string]$Message
    )
    throw (New-ExitException -Code $Code -Message $Message)
}

function Initialize-RestrictedDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    $SystemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $AdministratorsSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $Inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $Propagation = [Security.AccessControl.PropagationFlags]::None
    $Allow = [Security.AccessControl.AccessControlType]::Allow

    $Acl = New-Object Security.AccessControl.DirectorySecurity
    $Acl.SetAccessRuleProtection($true, $false)
    $Acl.SetOwner($SystemSid)
    $Acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $SystemSid,
        [Security.AccessControl.FileSystemRights]::FullControl,
        $Inheritance,
        $Propagation,
        $Allow
    ))
    $Acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $AdministratorsSid,
        [Security.AccessControl.FileSystemRights]::FullControl,
        $Inheritance,
        $Propagation,
        $Allow
    ))

    try {
        Set-Acl -LiteralPath $Path -AclObject $Acl
        if (Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Select-Object -First 1) {
            & "$env:SystemRoot\System32\icacls.exe" (Join-Path $Path '*') /reset /T /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Throw-Exit -Code 13 -Message "状態ディレクトリ配下のACLリセットに失敗しました: $Path / ExitCode=$LASTEXITCODE"
            }
        }
        Set-Acl -LiteralPath $Path -AclObject $Acl
    } catch {
        if ($_.Exception.Data.Contains('ExitCode')) { throw }
        Throw-Exit -Code 13 -Message "状態ディレクトリのACL設定に失敗しました: $Path / $($_.Exception.Message)"
    }
}

function Write-ProvisionEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$Code = 0,
        [hashtable]$Data = @{}
    )

    try {
        if (-not (Test-Path -LiteralPath $script:StateRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
        }
        $record = [ordered]@{
            timestampUtc = [DateTime]::UtcNow.ToString('o')
            event = $Event
            code = $Code
            computer = $env:COMPUTERNAME
            message = $Message
        }
        foreach ($key in $Data.Keys) {
            if ($key -notmatch '(?i)password|secret|token|credential') {
                $record[$key] = $Data[$key]
            }
        }
        ($record | ConvertTo-Json -Compress -Depth 6) | Add-Content -LiteralPath $script:LogPath -Encoding UTF8
    } catch {
        # ログ失敗で元のエラーを隠さない。
    }
}

function Assert-SystemIdentity {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.User.Value -ne 'S-1-5-18') {
        Throw-Exit -Code 10 -Message "NT AUTHORITY\SYSTEMではありません。現在のSID: $($identity.User.Value)"
    }
}

function Acquire-ProvisioningMutex {
    try {
        $script:Mutex = New-Object System.Threading.Mutex($false, 'Global\Company-CodexElevatedSandbox-Provisioning')
        $script:MutexOwned = $script:Mutex.WaitOne(0)
    } catch {
        Throw-Exit -Code 11 -Message "多重実行防止Mutexの取得に失敗しました: $($_.Exception.Message)"
    }
    if (-not $script:MutexOwned) {
        Throw-Exit -Code 11 -Message '別のプロビジョニング処理が実行中です。'
    }
}

function Assert-ApprovedSignature {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedThumbprint
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Throw-Exit -Code 12 -Message "署名検証対象がありません: $Path"
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) {
        Throw-Exit -Code 12 -Message "署名が有効ではありません: $Path / Status=$($signature.Status)"
    }
    $actual = ConvertTo-NormalizedThumbprint $signature.SignerCertificate.Thumbprint
    if ($actual -ne $ExpectedThumbprint) {
        Throw-Exit -Code 12 -Message "署名者Thumbprintが承認値と一致しません: $Path"
    }
}

function Test-IsReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Assert-NoBroadWriteAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $broadSids = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545')
    $writeMask = [int64]([Security.AccessControl.FileSystemRights]::WriteData -bor
        [Security.AccessControl.FileSystemRights]::CreateFiles -bor
        [Security.AccessControl.FileSystemRights]::CreateDirectories -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership)

    $acl = Get-Acl -LiteralPath $Path
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) {
            continue
        }
        try {
            $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        } catch {
            continue
        }
        if ($broadSids -contains $sid) {
            $rights = [int64]$rule.FileSystemRights
            if (($rights -band $writeMask) -ne 0) {
                Throw-Exit -Code 13 -Message "一般ユーザーに書込み可能なACLを検出しました: $Path / $sid / $($rule.FileSystemRights)"
            }
        }
    }
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected
    )
    if ($Expected -notmatch '^[0-9A-Fa-f]{64}$') {
        Throw-Exit -Code 13 -Message "SHA-256設定値が64桁ではありません: $Path"
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Throw-Exit -Code 13 -Message "必須ファイルがありません: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $Expected.ToUpperInvariant()) {
        Throw-Exit -Code 13 -Message "SHA-256不一致: $Path"
    }
    return $actual
}

function Escape-LdapFilterValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    $builder = New-Object Text.StringBuilder
    foreach ($character in $Value.ToCharArray()) {
        switch ([int][char]$character) {
            0  { [void]$builder.Append('\00') }
            40 { [void]$builder.Append('\28') }
            41 { [void]$builder.Append('\29') }
            42 { [void]$builder.Append('\2a') }
            92 { [void]$builder.Append('\5c') }
            default { [void]$builder.Append($character) }
        }
    }
    return $builder.ToString()
}

function Get-DirectoryEntryPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$SearchResult,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $values = $SearchResult.Properties[$Name]
    if ($null -eq $values -or $values.Count -eq 0) {
        return $null
    }
    return $values[0]
}

function Get-AuthorizedTargetFromAd {
    param(
        [Parameter(Mandatory = $true)][string]$AuthorizedGroupDn,
        [Parameter(Mandatory = $true)][string]$ExpectedDomainNetBIOS
    )

    try {
        $rootDse = [ADSI]'LDAP://RootDSE'
        $defaultNamingContext = [string]$rootDse.defaultNamingContext
        if ([string]::IsNullOrWhiteSpace($defaultNamingContext)) {
            Throw-Exit -Code 30 -Message 'AD defaultNamingContextを取得できません。'
        }

        $searchRoot = New-Object DirectoryServices.DirectoryEntry("LDAP://$defaultNamingContext")
        $computerSearcher = New-Object DirectoryServices.DirectorySearcher($searchRoot)
        $computerName = Escape-LdapFilterValue ($env:COMPUTERNAME + '$')
        $computerSearcher.Filter = "(&(objectCategory=computer)(sAMAccountName=$computerName))"
        [void]$computerSearcher.PropertiesToLoad.Add('managedBy')
        [void]$computerSearcher.PropertiesToLoad.Add('distinguishedName')
        $computerResult = $computerSearcher.FindOne()
        if ($null -eq $computerResult) {
            Throw-Exit -Code 20 -Message "ADに自端末のコンピューターオブジェクトがありません: $env:COMPUTERNAME"
        }
        $managedBy = [string](Get-DirectoryEntryPropertyValue -SearchResult $computerResult -Name 'managedby')
        if ([string]::IsNullOrWhiteSpace($managedBy)) {
            Throw-Exit -Code 20 -Message "AD computer.managedByが未設定です: $env:COMPUTERNAME"
        }

        $userEntry = New-Object DirectoryServices.DirectoryEntry("LDAP://$managedBy")
        $null = $userEntry.NativeObject
        $samAccountName = [string]$userEntry.Properties['sAMAccountName'].Value
        $userAccountControl = [int]$userEntry.Properties['userAccountControl'].Value
        $userDn = [string]$userEntry.Properties['distinguishedName'].Value
        $objectSidBytes = [byte[]]$userEntry.Properties['objectSid'].Value
        $objectClass = @($userEntry.Properties['objectClass'] | ForEach-Object { [string]$_ })

        if ([string]::IsNullOrWhiteSpace($samAccountName) -or $objectClass -notcontains 'user') {
            Throw-Exit -Code 20 -Message "managedByが有効なADユーザーを指していません: $managedBy"
        }
        if (($userAccountControl -band 2) -ne 0) {
            Throw-Exit -Code 21 -Message "managedByのユーザーが無効です: $samAccountName"
        }

        $userSid = New-Object Security.Principal.SecurityIdentifier($objectSidBytes, 0)
        $ntAccount = $userSid.Translate([Security.Principal.NTAccount]).Value
        $accountParts = $ntAccount.Split('\', 2)
        if ($accountParts.Count -ne 2 -or $accountParts[0] -ine $ExpectedDomainNetBIOS) {
            Throw-Exit -Code 21 -Message "対象ユーザーが期待ドメイン外です: $ntAccount"
        }

        $membershipSearcher = New-Object DirectoryServices.DirectorySearcher($searchRoot)
        $escapedUserDn = Escape-LdapFilterValue $userDn
        $escapedGroupDn = Escape-LdapFilterValue $AuthorizedGroupDn
        $membershipSearcher.Filter = "(&(objectCategory=person)(objectClass=user)(distinguishedName=$escapedUserDn)(memberOf:1.2.840.113556.1.4.1941:=$escapedGroupDn))"
        [void]$membershipSearcher.PropertiesToLoad.Add('distinguishedName')
        if ($null -eq $membershipSearcher.FindOne()) {
            Throw-Exit -Code 21 -Message "対象ユーザーはCodex認可グループの実効メンバーではありません: $ntAccount"
        }

        return [pscustomobject]@{
            Account = $ntAccount
            SamAccountName = $samAccountName
            Sid = $userSid.Value
            DistinguishedName = $userDn
            ComputerDistinguishedName = [string](Get-DirectoryEntryPropertyValue -SearchResult $computerResult -Name 'distinguishedname')
        }
    } catch {
        if ($_.Exception.Data.Contains('ExitCode')) {
            throw
        }
        Throw-Exit -Code 30 -Message "AD照会に失敗しました: $($_.Exception.Message)"
    }
}

function Get-TargetProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Sid,
        [bool]$AllowRoamingProfile
    )

    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID = '$Sid'" -ErrorAction Stop)
    $profiles = @($profiles | Where-Object { -not $_.Special })
    if ($profiles.Count -ne 1) {
        Throw-Exit -Code 22 -Message "SIDに一致する通常プロファイルが1件ではありません: SID=$Sid / Count=$($profiles.Count)"
    }
    $profile = $profiles[0]
    $status = [int]$profile.Status
    if (($status -band 1) -ne 0 -or ($status -band 4) -ne 0 -or ($status -band 8) -ne 0) {
        Throw-Exit -Code 22 -Message "一時・強制・破損プロファイルは対象外です: Status=$status"
    }
    if (($status -band 2) -ne 0 -and -not $AllowRoamingProfile) {
        Throw-Exit -Code 22 -Message 'ローミングプロファイルは設定で許可されていません。'
    }

    $localPath = [string]$profile.LocalPath
    if ([string]::IsNullOrWhiteSpace($localPath) -or -not [IO.Path]::IsPathRooted($localPath) -or $localPath.StartsWith('\\')) {
        Throw-Exit -Code 22 -Message "プロファイルLocalPathが不正です: $localPath"
    }
    if (-not (Test-Path -LiteralPath $localPath -PathType Container)) {
        Throw-Exit -Code 22 -Message "プロファイルLocalPathが存在しません: $localPath"
    }
    if (Test-IsReparsePoint -Path $localPath) {
        Throw-Exit -Code 22 -Message "プロファイルルートが再解析ポイントです: $localPath"
    }
    return [pscustomobject]@{
        LocalPath = $localPath
        CodexHome = Join-Path $localPath '.codex'
        Loaded = [bool]$profile.Loaded
        Status = $status
    }
}

function Get-CodexVersion {
    param([Parameter(Mandatory = $true)][string]$CodexExe)
    $output = (& $CodexExe --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $output -notmatch '(?<version>\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)') {
        Throw-Exit -Code 14 -Message "Codexバージョンを取得できません: $output"
    }
    return $Matches['version']
}

function Get-DesiredFingerprint {
    param(
        [string]$TargetSid,
        [string]$PolicyVersion,
        [string]$CodexVersion,
        [hashtable]$Hashes,
        [string]$RequirementsHash
    )
    $parts = @($TargetSid, $PolicyVersion, $CodexVersion, $RequirementsHash)
    foreach ($key in ($Hashes.Keys | Sort-Object)) {
        $parts += "$key=$($Hashes[$key])"
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join '|'))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function Get-SimpleTomlValueMap {
    param([Parameter(Mandatory = $true)][string]$Path)
    $map = @{}
    $section = ''
    foreach ($rawLine in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $line = ($rawLine -replace '\s+#.*$', '').Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim()
            continue
        }
        if ($line -match '^([A-Za-z0-9_.-]+)\s*=\s*"([^"]*)"\s*$') {
            $key = if ($section) { "$section.$($Matches[1])" } else { $Matches[1] }
            $map[$key] = $Matches[2]
        }
    }
    return $map
}

function Assert-EffectiveElevatedConfig {
    param([Parameter(Mandatory = $true)][string]$CodexHome)
    $configPath = Join-Path $CodexHome 'config.toml'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Throw-Exit -Code 51 -Message "config.tomlがありません: $configPath"
    }
    $values = Get-SimpleTomlValueMap -Path $configPath
    if (-not $values.ContainsKey('windows.sandbox') -or $values['windows.sandbox'] -ne 'elevated') {
        Throw-Exit -Code 51 -Message 'config.tomlのトップレベル windows.sandbox が elevated ではありません。'
    }
    if ($values.ContainsKey('profile')) {
        $profile = [string]$values['profile']
        $profileKey = "profiles.$profile.windows.sandbox"
        if ($values.ContainsKey($profileKey) -and $values[$profileKey] -ne 'elevated') {
            Throw-Exit -Code 51 -Message "有効プロファイル $profile がWindows sandboxを上書きしています: $($values[$profileKey])"
        }
    }
    return $configPath
}

function Test-ProvisioningArtifacts {
    param([Parameter(Mandatory = $true)][string]$CodexHome)
    $required = @(
        (Join-Path $CodexHome '.sandbox\setup_marker.json'),
        (Join-Path $CodexHome '.sandbox-secrets\sandbox_users.json')
    )
    foreach ($path in $required) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $false
        }
    }
    try {
        [void](Assert-EffectiveElevatedConfig -CodexHome $CodexHome)
        return $true
    } catch {
        return $false
    }
}

function Invoke-CodexSetup {
    param(
        [Parameter(Mandatory = $true)][string]$CodexExe,
        [Parameter(Mandatory = $true)][string]$TargetAccount,
        [Parameter(Mandatory = $true)][string]$CodexHome,
        [int]$TimeoutSeconds
    )

    $arguments = @('sandbox', 'setup', '--elevated', '--user', $TargetAccount, '--codex-home', $CodexHome)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $CodexExe
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Windows PowerShell 5.1 / .NET Framework向け。今回の値に末尾バックスラッシュは許可しない。
    $quoted = $arguments | ForEach-Object {
        $value = [string]$_
        if ($value.EndsWith('\')) {
            Throw-Exit -Code 13 -Message "プロセス引数の末尾バックスラッシュは許可されません: $value"
        }
        '"' + ($value -replace '"', '\"') + '"'
    }
    $psi.Arguments = $quoted -join ' '

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        Throw-Exit -Code 50 -Message 'Codex setupプロセスを開始できません。'
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch {}
        Throw-Exit -Code 50 -Message "Codex setupがタイムアウトしました: ${TimeoutSeconds}秒"
    }
    $stdout = $stdoutTask.Result.Trim()
    $stderr = $stderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) {
        $safeError = ($stderr + ' ' + $stdout).Trim()
        if ($safeError.Length -gt 2000) { $safeError = $safeError.Substring(0, 2000) }
        Throw-Exit -Code 50 -Message "Codex setupが失敗しました。ExitCode=$($process.ExitCode) / $safeError"
    }
    return $stdout
}

function Save-State {
    param(
        [string]$Path,
        [System.Collections.IDictionary]$State
    )
    $temporaryPath = "$Path.tmp.$PID"
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$exitCode = 99
try {
    Assert-SystemIdentity
    Acquire-ProvisioningMutex

    Initialize-RestrictedDirectory -Path $script:DefaultStateRoot
    $expectedSigner = ConvertTo-NormalizedThumbprint $ApprovedSignerThumbprint
    if ($expectedSigner.Length -ne 40) {
        Throw-Exit -Code 12 -Message 'ApprovedSignerThumbprintは40桁のSHA-1 Thumbprintで指定してください。'
    }

    $scriptPath = $MyInvocation.MyCommand.Path
    Assert-ApprovedSignature -Path $scriptPath -ExpectedThumbprint $expectedSigner
    Assert-ApprovedSignature -Path $ConfigPath -ExpectedThumbprint $expectedSigner

    $config = Import-PowerShellDataFile -LiteralPath $ConfigPath
    $requiredConfigKeys = @(
        'SchemaVersion', 'PolicyVersion', 'ExpectedDomainNetBIOS',
        'AuthorizedUserGroupDistinguishedName', 'CodexPackageRoot',
        'CodexExeRelativePath', 'ApprovedCodexVersion', 'RequiredFiles',
        'RequirementsPath', 'RequirementsSha256', 'ScriptRoot', 'StateRoot',
        'AllowRoamingProfile', 'AllowTargetChange', 'SetupTimeoutSeconds'
    )
    foreach ($key in $requiredConfigKeys) {
        if (-not $config.ContainsKey($key)) {
            Throw-Exit -Code 13 -Message "設定キーが不足しています: $key"
        }
    }
    if ([int]$config.SchemaVersion -ne 1) {
        Throw-Exit -Code 13 -Message "未対応のSchemaVersionです: $($config.SchemaVersion)"
    }

    $script:StateRoot = [string]$config.StateRoot
    $script:LogPath = Join-Path $script:StateRoot 'provisioning.jsonl'
    Initialize-RestrictedDirectory -Path $script:StateRoot

    foreach ($path in @([string]$config.ScriptRoot, [string]$config.CodexPackageRoot)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            Throw-Exit -Code 13 -Message "必須ディレクトリがありません: $path"
        }
        if (Test-IsReparsePoint -Path $path) {
            Throw-Exit -Code 13 -Message "必須ディレクトリが再解析ポイントです: $path"
        }
        Assert-NoBroadWriteAcl -Path $path
    }
    Assert-NoBroadWriteAcl -Path $ConfigPath

    $verifiedHashes = @{}
    foreach ($relativePath in $config.RequiredFiles.Keys) {
        $fullPath = Join-Path ([string]$config.CodexPackageRoot) ([string]$relativePath)
        $verifiedHashes[[string]$relativePath] = Assert-Sha256 -Path $fullPath -Expected ([string]$config.RequiredFiles[$relativePath])
    }
    $requirementsHash = Assert-Sha256 -Path ([string]$config.RequirementsPath) -Expected ([string]$config.RequirementsSha256)
    Assert-NoBroadWriteAcl -Path ([string]$config.RequirementsPath)

    $codexExe = Join-Path ([string]$config.CodexPackageRoot) ([string]$config.CodexExeRelativePath)
    $codexVersion = Get-CodexVersion -CodexExe $codexExe
    if ($codexVersion -cne [string]$config.ApprovedCodexVersion) {
        Throw-Exit -Code 14 -Message "Codexバージョンが承認値と一致しません。Actual=$codexVersion / Approved=$($config.ApprovedCodexVersion)"
    }

    $target = Get-AuthorizedTargetFromAd `
        -AuthorizedGroupDn ([string]$config.AuthorizedUserGroupDistinguishedName) `
        -ExpectedDomainNetBIOS ([string]$config.ExpectedDomainNetBIOS)
    $profile = Get-TargetProfile -Sid $target.Sid -AllowRoamingProfile ([bool]$config.AllowRoamingProfile)

    $statePath = Join-Path $script:StateRoot 'state.json'
    $existingState = $null
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        try { $existingState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch {
            Throw-Exit -Code 13 -Message "state.jsonを読み取れません: $($_.Exception.Message)"
        }
    }
    if ($null -ne $existingState -and [string]$existingState.targetSid -ne $target.Sid -and -not [bool]$config.AllowTargetChange) {
        Throw-Exit -Code 23 -Message "端末の対象ユーザー変更を検出しました。承認済み再割当手順が必要です。Old=$($existingState.targetAccount) / New=$($target.Account)"
    }

    $fingerprint = Get-DesiredFingerprint `
        -TargetSid $target.Sid `
        -PolicyVersion ([string]$config.PolicyVersion) `
        -CodexVersion $codexVersion `
        -Hashes $verifiedHashes `
        -RequirementsHash $requirementsHash

    if ($null -ne $existingState -and [string]$existingState.fingerprint -eq $fingerprint -and (Test-ProvisioningArtifacts -CodexHome $profile.CodexHome)) {
        Write-ProvisionEvent -Event 'compliant' -Message '既に承認済み状態です。setupの再実行を省略しました。' -Code 0 -Data @{
            targetAccount = $target.Account
            targetSid = $target.Sid
            targetDistinguishedName = $target.DistinguishedName
            computerDistinguishedName = $target.ComputerDistinguishedName
            codexHome = $profile.CodexHome
            codexVersion = $codexVersion
            policyVersion = [string]$config.PolicyVersion
        }
        $exitCode = 0
    } else {
        Write-ProvisionEvent -Event 'setup-start' -Message 'Codex Elevated Sandboxの事前構成を開始します。' -Code 0 -Data @{
            targetAccount = $target.Account
            targetSid = $target.Sid
            targetDistinguishedName = $target.DistinguishedName
            computerDistinguishedName = $target.ComputerDistinguishedName
            codexHome = $profile.CodexHome
            codexVersion = $codexVersion
            policyVersion = [string]$config.PolicyVersion
        }

        $setupOutput = [string](Invoke-CodexSetup `
            -CodexExe $codexExe `
            -TargetAccount $target.Account `
            -CodexHome $profile.CodexHome `
            -TimeoutSeconds ([int]$config.SetupTimeoutSeconds))

        $configTomlPath = Assert-EffectiveElevatedConfig -CodexHome $profile.CodexHome
        if (-not (Test-ProvisioningArtifacts -CodexHome $profile.CodexHome)) {
            Throw-Exit -Code 51 -Message 'setup成功応答後に必須成果物が不足しています。'
        }

        $state = [ordered]@{
            schemaVersion = 1
            completedAtUtc = [DateTime]::UtcNow.ToString('o')
            computer = $env:COMPUTERNAME
            targetAccount = $target.Account
            targetSid = $target.Sid
            targetDistinguishedName = $target.DistinguishedName
            computerDistinguishedName = $target.ComputerDistinguishedName
            codexHome = $profile.CodexHome
            configToml = $configTomlPath
            codexVersion = $codexVersion
            policyVersion = [string]$config.PolicyVersion
            fingerprint = $fingerprint
            requirementsSha256 = $requirementsHash
            packageHashes = $verifiedHashes
            profileStatus = $profile.Status
            profileLoadedAtSetup = $profile.Loaded
        }
        Save-State -Path $statePath -State $state

        Write-ProvisionEvent -Event 'setup-success' -Message 'Codex Elevated Sandboxの事前構成が完了しました。' -Code 0 -Data @{
            targetAccount = $target.Account
            targetSid = $target.Sid
            targetDistinguishedName = $target.DistinguishedName
            computerDistinguishedName = $target.ComputerDistinguishedName
            codexHome = $profile.CodexHome
            codexVersion = $codexVersion
            policyVersion = [string]$config.PolicyVersion
            output = if ($setupOutput.Length -gt 500) { $setupOutput.Substring(0, 500) } else { $setupOutput }
        }
        $exitCode = 0
    }
} catch {
    $exitCode = 99
    if ($_.Exception.Data.Contains('ExitCode')) {
        $exitCode = [int]$_.Exception.Data['ExitCode']
    }
    Write-ProvisionEvent -Event 'failure' -Message $_.Exception.Message -Code $exitCode
} finally {
    if ($script:MutexOwned -and $null -ne $script:Mutex) {
        try { $script:Mutex.ReleaseMutex() } catch {}
    }
    if ($null -ne $script:Mutex) {
        $script:Mutex.Dispose()
    }
}

exit $exitCode
