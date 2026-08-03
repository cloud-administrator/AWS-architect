[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PayloadRoot,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f ]{40,59}$')]
    [string]$ApprovedSignerThumbprint
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function ConvertTo-NormalizedThumbprint {
    param([string]$Value)
    return (($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant())
}

function Assert-SystemIdentity {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($Identity.User.Value -ne 'S-1-5-18') {
        throw "このインストーラーは NT AUTHORITY\SYSTEM で実行してください。CurrentSid=$($Identity.User.Value)"
    }
}

function Assert-ApprovedSignature {
    param([string]$Path, [string]$ExpectedThumbprint)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "署名検証対象がありません: $Path"
    }
    $Signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($Signature.Status -ne 'Valid' -or $null -eq $Signature.SignerCertificate) {
        throw "署名が有効ではありません: $Path / Status=$($Signature.Status)"
    }
    $Actual = ConvertTo-NormalizedThumbprint $Signature.SignerCertificate.Thumbprint
    if ($Actual -ne $ExpectedThumbprint) {
        throw "署名者 Thumbprint が不一致です: $Path"
    }
}

function Invoke-RobocopyChecked {
    param([string]$Source, [string]$Destination)

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    & "$env:SystemRoot\System32\robocopy.exe" $Source $Destination /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:3 /NFL /NDL /NP
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy に失敗しました。Source=$Source Destination=$Destination ExitCode=$LASTEXITCODE"
    }
}

function New-ManagedDirectorySecurity {
    param([switch]$IncludeUsersReadAndExecute)

    $SystemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $AdministratorsSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $UsersSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
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
    if ($IncludeUsersReadAndExecute) {
        $Acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $UsersSid,
            [Security.AccessControl.FileSystemRights]::ReadAndExecute,
            $Inheritance,
            $Propagation,
            $Allow
        ))
    }
    return $Acl
}

function Set-ManagedDirectoryAcl {
    param(
        [string]$Path,
        [switch]$IncludeUsersReadAndExecute
    )

    $Acl = New-ManagedDirectorySecurity -IncludeUsersReadAndExecute:$IncludeUsersReadAndExecute
    Set-Acl -LiteralPath $Path -AclObject $Acl

    # 既存の子要素に保護済み／明示 ACL が残っていても、管理ルートから継承する状態へ戻す。
    if (Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Select-Object -First 1) {
        & "$env:SystemRoot\System32\icacls.exe" (Join-Path $Path '*') /reset /T /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "子要素の ACL リセットに失敗しました: $Path / ExitCode=$LASTEXITCODE"
        }
    }
    Set-Acl -LiteralPath $Path -AclObject $Acl
}

function Set-ManagedFileAcl {
    param(
        [string]$Path,
        [switch]$IncludeUsersRead
    )

    $SystemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $AdministratorsSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $UsersSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    $Allow = [Security.AccessControl.AccessControlType]::Allow

    $Acl = New-Object Security.AccessControl.FileSecurity
    $Acl.SetAccessRuleProtection($true, $false)
    $Acl.SetOwner($SystemSid)
    $Acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $SystemSid,
        [Security.AccessControl.FileSystemRights]::FullControl,
        $Allow
    ))
    $Acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $AdministratorsSid,
        [Security.AccessControl.FileSystemRights]::FullControl,
        $Allow
    ))
    if ($IncludeUsersRead) {
        $Acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $UsersSid,
            [Security.AccessControl.FileSystemRights]::Read,
            $Allow
        ))
    }
    Set-Acl -LiteralPath $Path -AclObject $Acl
}

function Assert-Hash {
    param([string]$Path, [string]$Expected)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "必須ファイルがありません: $Path"
    }
    $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Actual -ine $Expected) {
        throw "SHA-256 不一致: $Path"
    }
}

Assert-SystemIdentity
$ExpectedSigner = ConvertTo-NormalizedThumbprint $ApprovedSignerThumbprint
if ($ExpectedSigner.Length -ne 40) {
    throw 'ApprovedSignerThumbprint は空白なし 40 桁の証明書 Thumbprint で指定してください。'
}

$SourceCodex = Join-Path $PayloadRoot 'CodexCLI'
$SourceScripts = Join-Path $PayloadRoot 'CodexProvisioning'
$SourceRequirements = Join-Path $PayloadRoot 'OpenAI-Codex\requirements.toml'
$SourceConfig = Join-Path $SourceScripts 'CodexDeploymentConfig.psd1'
$SourceProvision = Join-Path $SourceScripts 'Provision-CodexSandbox.ps1'
$SourceTest = Join-Path $SourceScripts 'Test-CodexDeployment.ps1'
$InstallerPath = $MyInvocation.MyCommand.Path

foreach ($Required in @($SourceCodex, $SourceScripts, $SourceRequirements, $SourceConfig, $SourceProvision, $SourceTest)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        throw "配布元がありません: $Required"
    }
}

foreach ($SignedFile in @($InstallerPath, $SourceConfig, $SourceProvision, $SourceTest)) {
    Assert-ApprovedSignature -Path $SignedFile -ExpectedThumbprint $ExpectedSigner
}

$Config = Import-PowerShellDataFile -LiteralPath $SourceConfig
foreach ($RelativePath in $Config.RequiredFiles.Keys) {
    Assert-Hash -Path (Join-Path $SourceCodex ([string]$RelativePath)) -Expected ([string]$Config.RequiredFiles[$RelativePath])
}
Assert-Hash -Path $SourceRequirements -Expected ([string]$Config.RequirementsSha256)

$SourceVersion = (& (Join-Path $SourceCodex 'bin\codex.exe') --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $SourceVersion -notmatch '([0-9][0-9A-Za-z.+-]*)$' -or $Matches[1] -cne [string]$Config.ApprovedCodexVersion) {
    throw "配布元 Codex バージョン不一致: $SourceVersion"
}

$DestCodex = 'C:\Program Files\OpenAI\CodexCLI'
$DestScripts = 'C:\Program Files\Company\CodexProvisioning'
$DestRequirementsDir = 'C:\ProgramData\OpenAI\Codex'
$DestRequirements = Join-Path $DestRequirementsDir 'requirements.toml'
$InstallStateRoot = 'C:\ProgramData\Company\CodexProvisioning'

Invoke-RobocopyChecked -Source $SourceCodex -Destination $DestCodex
Invoke-RobocopyChecked -Source $SourceScripts -Destination $DestScripts
New-Item -ItemType Directory -Force -Path $DestRequirementsDir, $InstallStateRoot | Out-Null
Copy-Item -LiteralPath $SourceRequirements -Destination $DestRequirements -Force

Set-ManagedDirectoryAcl -Path $DestCodex -IncludeUsersReadAndExecute
Set-ManagedDirectoryAcl -Path $DestScripts -IncludeUsersReadAndExecute
Set-ManagedDirectoryAcl -Path $DestRequirementsDir -IncludeUsersReadAndExecute
Set-ManagedFileAcl -Path $DestRequirements -IncludeUsersRead

Set-ManagedDirectoryAcl -Path $InstallStateRoot

$DestConfig = Join-Path $DestScripts 'CodexDeploymentConfig.psd1'
$DestProvision = Join-Path $DestScripts 'Provision-CodexSandbox.ps1'
$DestTest = Join-Path $DestScripts 'Test-CodexDeployment.ps1'
foreach ($SignedFile in @($DestConfig, $DestProvision, $DestTest)) {
    Assert-ApprovedSignature -Path $SignedFile -ExpectedThumbprint $ExpectedSigner
}

$InstalledConfig = Import-PowerShellDataFile -LiteralPath $DestConfig
foreach ($RelativePath in $InstalledConfig.RequiredFiles.Keys) {
    Assert-Hash -Path (Join-Path $DestCodex ([string]$RelativePath)) -Expected ([string]$InstalledConfig.RequiredFiles[$RelativePath])
}
Assert-Hash -Path $DestRequirements -Expected ([string]$InstalledConfig.RequirementsSha256)

$VersionOutput = (& (Join-Path $DestCodex 'bin\codex.exe') --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $VersionOutput -notmatch '([0-9][0-9A-Za-z.+-]*)$' -or $Matches[1] -cne [string]$InstalledConfig.ApprovedCodexVersion) {
    throw "配布後 Codex バージョン不一致: $VersionOutput"
}

$InstallState = [ordered]@{
    schemaVersion = 1
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    computer = $env:COMPUTERNAME
    codexVersion = [string]$InstalledConfig.ApprovedCodexVersion
    policyVersion = [string]$InstalledConfig.PolicyVersion
    signerThumbprint = $ExpectedSigner
    codexPackageRoot = $DestCodex
    scriptRoot = $DestScripts
    requirementsPath = $DestRequirements
}
$InstallState |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $InstallStateRoot 'package-install.json') -Encoding UTF8

Write-Host 'Codex provisioning payload installation completed.' -ForegroundColor Green
exit 0
