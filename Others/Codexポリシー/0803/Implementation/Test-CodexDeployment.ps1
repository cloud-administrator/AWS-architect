[CmdletBinding()]
param(
    [string]$ConfigPath = 'C:\Program Files\Company\CodexProvisioning\CodexDeploymentConfig.psd1',
    [string]$ReportPath = 'C:\ProgramData\Company\CodexProvisioning\validation-report.json'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function ConvertTo-NormalizedThumbprint {
    param([string]$Value)
    return (($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant())
}

function Add-Check {
    param(
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Name,
        [bool]$Passed,
        [string]$Detail,
        [bool]$Critical = $true
    )
    $Checks.Add([pscustomobject]@{
        name = $Name
        passed = $Passed
        critical = $Critical
        detail = $Detail
    })
}

function Get-SimpleTomlValueMap {
    param([string]$Path)
    $map = @{}
    $section = ''
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = ($rawLine -replace '\s+#.*$', '').Trim()
        if (-not $line) { continue }
        if ($line -match '^\[(.+)\]$') { $section = $Matches[1].Trim(); continue }
        if ($line -match '^([A-Za-z0-9_.-]+)\s*=\s*"([^"]*)"\s*$') {
            $key = if ($section) { "$section.$($Matches[1])" } else { $Matches[1] }
            $map[$key] = $Matches[2]
        }
    }
    return $map
}

function Escape-LdapFilterValue {
    param([string]$Value)
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

function Get-SearchPropertyValue {
    param($SearchResult, [string]$Name)
    $values = $SearchResult.Properties[$Name]
    if ($null -eq $values -or $values.Count -eq 0) { return $null }
    return $values[0]
}

function Get-CurrentAdAssignment {
    param(
        [string]$ExpectedDomainNetBIOS,
        [string]$AuthorizedGroupDn
    )

    $rootDse = [ADSI]'LDAP://RootDSE'
    $defaultNamingContext = [string]$rootDse.defaultNamingContext
    if ([string]::IsNullOrWhiteSpace($defaultNamingContext)) {
        throw 'AD defaultNamingContext を取得できません。'
    }

    $searchRoot = New-Object DirectoryServices.DirectoryEntry("LDAP://$defaultNamingContext")
    $computerSearcher = New-Object DirectoryServices.DirectorySearcher($searchRoot)
    $computerSam = Escape-LdapFilterValue ($env:COMPUTERNAME + '$')
    $computerSearcher.Filter = "(&(objectCategory=computer)(sAMAccountName=$computerSam))"
    [void]$computerSearcher.PropertiesToLoad.Add('managedBy')
    [void]$computerSearcher.PropertiesToLoad.Add('distinguishedName')
    $computerResult = $computerSearcher.FindOne()
    if ($null -eq $computerResult) { throw "AD コンピューターがありません: $env:COMPUTERNAME" }

    $managedBy = [string](Get-SearchPropertyValue -SearchResult $computerResult -Name 'managedby')
    if ([string]::IsNullOrWhiteSpace($managedBy)) { throw 'computer.managedBy が未設定です。' }

    $userEntry = New-Object DirectoryServices.DirectoryEntry("LDAP://$managedBy")
    $null = $userEntry.NativeObject
    $sam = [string]$userEntry.Properties['sAMAccountName'].Value
    $userDn = [string]$userEntry.Properties['distinguishedName'].Value
    $uac = [int]$userEntry.Properties['userAccountControl'].Value
    $sidBytes = [byte[]]$userEntry.Properties['objectSid'].Value
    $classes = @($userEntry.Properties['objectClass'] | ForEach-Object { [string]$_ })
    if ([string]::IsNullOrWhiteSpace($sam) -or $classes -notcontains 'user') {
        throw 'managedBy が AD ユーザーを指していません。'
    }

    $sid = [Security.Principal.SecurityIdentifier]::new($sidBytes, 0)
    $account = $sid.Translate([Security.Principal.NTAccount]).Value
    $parts = $account.Split('\', 2)
    $domainMatches = ($parts.Count -eq 2 -and $parts[0] -ieq $ExpectedDomainNetBIOS)
    $enabled = (($uac -band 2) -eq 0)

    $membershipSearcher = New-Object DirectoryServices.DirectorySearcher($searchRoot)
    $escapedUserDn = Escape-LdapFilterValue $userDn
    $escapedGroupDn = Escape-LdapFilterValue $AuthorizedGroupDn
    $membershipSearcher.Filter = "(&(objectCategory=person)(objectClass=user)(distinguishedName=$escapedUserDn)(memberOf:1.2.840.113556.1.4.1941:=$escapedGroupDn))"
    [void]$membershipSearcher.PropertiesToLoad.Add('distinguishedName')
    $authorized = ($null -ne $membershipSearcher.FindOne())

    return [pscustomobject]@{
        Account = $account
        Sid = $sid.Value
        UserDistinguishedName = $userDn
        ComputerDistinguishedName = [string](Get-SearchPropertyValue -SearchResult $computerResult -Name 'distinguishedname')
        Enabled = $enabled
        DomainMatches = $domainMatches
        Authorized = $authorized
    }
}

$checks = New-Object 'System.Collections.Generic.List[object]'
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$statePath = Join-Path ([string]$config.StateRoot) 'state.json'
$state = $null
$assignment = $null
$task = $null
$packageInstall = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Add-Check $checks 'state.json' $true $statePath
} else {
    Add-Check $checks 'state.json' $false "不存在: $statePath"
}

if ($null -ne $state) {
    Add-Check $checks 'state.json の端末名' `
        ([string]$state.computer -ieq [string]$env:COMPUTERNAME) `
        "State=$($state.computer), Current=$env:COMPUTERNAME"
    Add-Check $checks 'state.json の Codex バージョン' `
        ([string]$state.codexVersion -ceq [string]$config.ApprovedCodexVersion) `
        "State=$($state.codexVersion), Approved=$($config.ApprovedCodexVersion)"
    Add-Check $checks 'state.json のポリシー版' `
        ([string]$state.policyVersion -ceq [string]$config.PolicyVersion) `
        "State=$($state.policyVersion), Config=$($config.PolicyVersion)"

    try {
        $profileCandidates = @(Get-CimInstance -ClassName Win32_UserProfile -Filter "SID = '$($state.targetSid)'" -ErrorAction Stop |
            Where-Object { -not $_.Special })
        $profilePassed = $false
        $profileDetail = "Count=$($profileCandidates.Count)"
        if ($profileCandidates.Count -eq 1) {
            $profile = $profileCandidates[0]
            $status = [int]$profile.Status
            $localPath = [string]$profile.LocalPath
            $expectedCodexHome = if (-not [string]::IsNullOrWhiteSpace($localPath)) {
                Join-Path $localPath '.codex'
            } else { '' }
            $pathMatches = $false
            if (-not [string]::IsNullOrWhiteSpace($expectedCodexHome) -and
                -not [string]::IsNullOrWhiteSpace([string]$state.codexHome)) {
                $expectedFull = [IO.Path]::GetFullPath($expectedCodexHome).TrimEnd([IO.Path]::DirectorySeparatorChar)
                $stateFull = [IO.Path]::GetFullPath([string]$state.codexHome).TrimEnd([IO.Path]::DirectorySeparatorChar)
                $pathMatches = [string]::Equals($expectedFull, $stateFull, [StringComparison]::OrdinalIgnoreCase)
            }
            $statusAllowed = (($status -band 1) -eq 0 -and ($status -band 4) -eq 0 -and ($status -band 8) -eq 0)
            if (($status -band 2) -ne 0 -and -not [bool]$config.AllowRoamingProfile) {
                $statusAllowed = $false
            }
            $pathExists = (-not [string]::IsNullOrWhiteSpace($localPath) -and
                (Test-Path -LiteralPath $localPath -PathType Container))
            $reparse = $false
            if ($pathExists) {
                $reparse = (((Get-Item -LiteralPath $localPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
            }
            $profilePassed = ($pathExists -and -not $reparse -and $statusAllowed -and $pathMatches)
            $profileDetail = "SID=$($profile.SID), LocalPath=$localPath, Status=$status, Reparse=$reparse, StateCodexHome=$($state.codexHome)"
        }
        Add-Check $checks '対象 Windows プロファイルと CODEX_HOME' $profilePassed $profileDetail
    } catch {
        Add-Check $checks '対象 Windows プロファイルと CODEX_HOME' $false $_.Exception.Message
    }

    try {
        $assignment = Get-CurrentAdAssignment `
            -ExpectedDomainNetBIOS ([string]$config.ExpectedDomainNetBIOS) `
            -AuthorizedGroupDn ([string]$config.AuthorizedUserGroupDistinguishedName)
        Add-Check $checks '現在の managedBy と state.json の SID' `
            ([string]$assignment.Sid -eq [string]$state.targetSid) `
            "AD=$($assignment.Account)/$($assignment.Sid), State=$($state.targetAccount)/$($state.targetSid)"
        Add-Check $checks '現在の managedBy と state.json のアカウント' `
            ([string]$assignment.Account -ieq [string]$state.targetAccount) `
            "AD=$($assignment.Account), State=$($state.targetAccount)"
        Add-Check $checks '現在の managedBy と state.json のユーザー DN' `
            ([string]$assignment.UserDistinguishedName -ieq [string]$state.targetDistinguishedName) `
            "AD=$($assignment.UserDistinguishedName), State=$($state.targetDistinguishedName)"
        Add-Check $checks '現在のコンピューター DN と state.json' `
            ([string]$assignment.ComputerDistinguishedName -ieq [string]$state.computerDistinguishedName) `
            "AD=$($assignment.ComputerDistinguishedName), State=$($state.computerDistinguishedName)"
        Add-Check $checks '現在の対象ユーザー有効性／ドメイン' `
            ($assignment.Enabled -and $assignment.DomainMatches) `
            "Enabled=$($assignment.Enabled), DomainMatches=$($assignment.DomainMatches), Account=$($assignment.Account)"
        Add-Check $checks '現在の Codex 認可グループ所属' `
            ([bool]$assignment.Authorized) `
            "Authorized=$($assignment.Authorized), Group=$($config.AuthorizedUserGroupDistinguishedName)"
    } catch {
        Add-Check $checks '現在の AD 割当／認可' $false $_.Exception.Message
    }
}

try {
    $task = Get-ScheduledTask -TaskName ([string]$config.TaskName) -ErrorAction Stop
    $system = ($task.Principal.UserId -match '(?i)SYSTEM|S-1-5-18')
    $highest = ($task.Principal.RunLevel -eq 'Highest')
    Add-Check $checks 'GPOタスク実行主体' ($system -and $highest) "UserId=$($task.Principal.UserId), RunLevel=$($task.Principal.RunLevel)"
} catch {
    Add-Check $checks 'GPOタスク実行主体' $false $_.Exception.Message
}

foreach ($relativePath in $config.RequiredFiles.Keys) {
    $path = Join-Path ([string]$config.CodexPackageRoot) ([string]$relativePath)
    $passed = $false
    $detail = "不存在: $path"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $passed = ($actual -ieq [string]$config.RequiredFiles[$relativePath])
        $detail = "Actual=$actual"
    }
    Add-Check $checks "SHA-256: $relativePath" $passed $detail
}

$requirementsPassed = $false
$requirementsDetail = "不存在: $($config.RequirementsPath)"
if (Test-Path -LiteralPath ([string]$config.RequirementsPath) -PathType Leaf) {
    $actual = (Get-FileHash -LiteralPath ([string]$config.RequirementsPath) -Algorithm SHA256).Hash
    $requirementsPassed = ($actual -ieq [string]$config.RequirementsSha256)
    $requirementsDetail = "Actual=$actual"
}
Add-Check $checks 'requirements.toml SHA-256' $requirementsPassed $requirementsDetail
if (Test-Path -LiteralPath ([string]$config.RequirementsPath) -PathType Leaf) {
    $requirementsBytes = [IO.File]::ReadAllBytes([string]$config.RequirementsPath)
    $hasUtf8Bom = ($requirementsBytes.Length -ge 3 -and
        $requirementsBytes[0] -eq 0xEF -and
        $requirementsBytes[1] -eq 0xBB -and
        $requirementsBytes[2] -eq 0xBF)
    Add-Check $checks 'requirements.toml は UTF-8 BOM なし' (-not $hasUtf8Bom) "Utf8Bom=$hasUtf8Bom"
}

if ($null -ne $state) {
    $codexHome = [string]$state.codexHome
    $configToml = Join-Path $codexHome 'config.toml'
    $marker = Join-Path $codexHome '.sandbox\setup_marker.json'
    $secrets = Join-Path $codexHome '.sandbox-secrets\sandbox_users.json'
    Add-Check $checks 'config.toml' (Test-Path -LiteralPath $configToml -PathType Leaf) $configToml
    Add-Check $checks 'setup_marker.json' (Test-Path -LiteralPath $marker -PathType Leaf) $marker
    Add-Check $checks 'sandbox_users.json' (Test-Path -LiteralPath $secrets -PathType Leaf) '存在だけを確認。内容は表示・収集しない。'

    if (Test-Path -LiteralPath $configToml -PathType Leaf) {
        $values = Get-SimpleTomlValueMap $configToml
        $effective = ($values.ContainsKey('windows.sandbox') -and $values['windows.sandbox'] -eq 'elevated')
        $detail = "top-level=$($values['windows.sandbox'])"
        if ($values.ContainsKey('profile')) {
            $profile = [string]$values['profile']
            $key = "profiles.$profile.windows.sandbox"
            if ($values.ContainsKey($key) -and $values[$key] -ne 'elevated') {
                $effective = $false
                $detail += ", active-profile=${profile}:$($values[$key])"
            }
        }
        Add-Check $checks '有効なWindows sandbox設定' $effective $detail
    }
}

foreach ($name in @('CodexSandboxOffline', 'CodexSandboxOnline')) {
    try {
        $entry = [ADSI]("WinNT://./$name,user")
        $null = $entry.Name
        Add-Check $checks "ローカルsandboxユーザー: $name" $true '存在'
    } catch {
        Add-Check $checks "ローカルsandboxユーザー: $name" $false $_.Exception.Message
    }
}

try {
    $sandboxGroup = [ADSI]'WinNT://./CodexSandboxUsers,group'
    $memberNames = @($sandboxGroup.psbase.Invoke('Members') | ForEach-Object {
        $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null)
    })
    Add-Check $checks 'ローカルsandboxグループ: CodexSandboxUsers' $true ("Members=" + ($memberNames -join ','))
    foreach ($expectedMember in @('CodexSandboxOffline', 'CodexSandboxOnline')) {
        Add-Check $checks "sandboxグループ所属: $expectedMember" ($memberNames -contains $expectedMember) ("Members=" + ($memberNames -join ','))
    }
} catch {
    Add-Check $checks 'ローカルsandboxグループ: CodexSandboxUsers' $false $_.Exception.Message
}

$packageInstallPath = Join-Path ([string]$config.StateRoot) 'package-install.json'
if (Test-Path -LiteralPath $packageInstallPath -PathType Leaf) {
    try {
        $packageInstall = Get-Content -LiteralPath $packageInstallPath -Raw | ConvertFrom-Json
        $installVersionMatches = ([string]$packageInstall.codexVersion -ceq [string]$config.ApprovedCodexVersion)
        $installPolicyMatches = ([string]$packageInstall.policyVersion -ceq [string]$config.PolicyVersion)
        Add-Check $checks 'package-install.json の版' `
            ($installVersionMatches -and $installPolicyMatches) `
            "Version=$($packageInstall.codexVersion), Policy=$($packageInstall.policyVersion), Path=$packageInstallPath"
    } catch {
        Add-Check $checks 'package-install.json の版' $false $_.Exception.Message
    }
} else {
    Add-Check $checks 'package-install.json の版' $false "不存在: $packageInstallPath"
}

if ($null -ne $packageInstall) {
    $expectedSigner = ConvertTo-NormalizedThumbprint ([string]$packageInstall.signerThumbprint)
    Add-Check $checks '承認済み署名者 Thumbprint' ($expectedSigner.Length -eq 40) "Thumbprint=$expectedSigner"

    $signedFiles = @(
        (Join-Path ([string]$config.ScriptRoot) 'Provision-CodexSandbox.ps1'),
        (Join-Path ([string]$config.ScriptRoot) 'Test-CodexDeployment.ps1'),
        $ConfigPath
    )
    foreach ($signedFile in $signedFiles) {
        try {
            $signature = Get-AuthenticodeSignature -LiteralPath $signedFile
            $actualSigner = if ($null -ne $signature.SignerCertificate) {
                ConvertTo-NormalizedThumbprint ([string]$signature.SignerCertificate.Thumbprint)
            } else { '' }
            Add-Check $checks "署名: $signedFile" `
                ($signature.Status -eq 'Valid' -and $actualSigner -eq $expectedSigner) `
                "Status=$($signature.Status), Signer=$actualSigner"
        } catch {
            Add-Check $checks "署名: $signedFile" $false $_.Exception.Message
        }
    }

    if ($null -ne $task) {
        $execAction = @($task.Actions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Execute) } | Select-Object -First 1)
        if ($execAction.Count -eq 1) {
            $action = $execAction[0]
            $arguments = [string]$action.Arguments
            $expectedProvision = Join-Path ([string]$config.ScriptRoot) 'Provision-CodexSandbox.ps1'
            $expectedPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $executeMatches = [string]::Equals([string]$action.Execute, $expectedPowerShell, [StringComparison]::OrdinalIgnoreCase)
            $argumentMatches = (
                $arguments.IndexOf('-ExecutionPolicy AllSigned', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $arguments.IndexOf($expectedProvision, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $arguments.IndexOf($ConfigPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $arguments.IndexOf($expectedSigner, [StringComparison]::OrdinalIgnoreCase) -ge 0
            )
            $workingDirectoryMatches = [string]::Equals(
                [string]$action.WorkingDirectory,
                [string]$config.ScriptRoot,
                [StringComparison]::OrdinalIgnoreCase
            )
            Add-Check $checks 'GPO タスクの操作' `
                ($executeMatches -and $argumentMatches -and $workingDirectoryMatches) `
                "Execute=$($action.Execute), WorkingDirectory=$($action.WorkingDirectory), Arguments=$arguments"
        } else {
            Add-Check $checks 'GPO タスクの操作' $false '実行アクションが 1 件ではありません。'
        }
    }
}

$criticalFailures = @($checks | Where-Object { $_.critical -and -not $_.passed })
$report = [ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    computer = $env:COMPUTERNAME
    passed = ($criticalFailures.Count -eq 0)
    criticalFailureCount = $criticalFailures.Count
    checks = $checks
}
$reportDirectory = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $reportDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
$checks | Format-Table -AutoSize
if ($criticalFailures.Count -gt 0) { exit 1 }
exit 0
