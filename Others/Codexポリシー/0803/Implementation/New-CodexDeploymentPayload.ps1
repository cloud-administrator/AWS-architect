[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [ValidateSet('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyVersion,

    [string]$AuthorizedUserGroupSamAccountName = 'GG-Codex-Users',
    [string]$KitRoot = 'C:\CodexDeployment\Kit',
    [string]$StagingRoot = 'C:\CodexDeployment\Staging',
    [string]$PayloadBase = 'C:\CodexDeployment\Payload',
    [switch]$Force
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

$SourcePackage = Join-Path $StagingRoot "$Version-$Target\CodexCLI"
$PackageVerification = Join-Path $StagingRoot "$Version-$Target\package-verification.json"
$PayloadRoot = Join-Path $PayloadBase "$Version-$Target"
$PayloadCodex = Join-Path $PayloadRoot 'CodexCLI'
$PayloadScripts = Join-Path $PayloadRoot 'CodexProvisioning'
$PayloadRequirementsDir = Join-Path $PayloadRoot 'OpenAI-Codex'
$PayloadRequirements = Join-Path $PayloadRequirementsDir 'requirements.toml'
$ConfigOut = Join-Path $PayloadScripts 'CodexDeploymentConfig.psd1'
$InstallerOut = Join-Path $PayloadRoot 'Install-CodexProvisioningPayload.ps1'

$RequiredKitFiles = @(
    'Provision-CodexSandbox.ps1',
    'Test-CodexDeployment.ps1',
    'Install-CodexProvisioningPayload.ps1',
    'requirements.toml'
)
foreach ($Name in $RequiredKitFiles) {
    $Path = Join-Path $KitRoot $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "実装キットの必須ファイルがありません: $Path"
    }
}
if (-not (Test-Path -LiteralPath $SourcePackage -PathType Container)) {
    throw "検証済み Codex パッケージがありません: $SourcePackage"
}
if (-not (Test-Path -LiteralPath $PackageVerification -PathType Leaf)) {
    throw "package-verification.json がありません: $PackageVerification"
}

if (Test-Path -LiteralPath $PayloadRoot) {
    if (-not $Force) {
        throw "既存ペイロードがあります。承認後に -Force を指定してください: $PayloadRoot"
    }
    Remove-Item -LiteralPath $PayloadRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $PayloadCodex, $PayloadScripts, $PayloadRequirementsDir | Out-Null
Copy-Item -Path (Join-Path $SourcePackage '*') -Destination $PayloadCodex -Recurse -Force
Copy-Item -LiteralPath (Join-Path $KitRoot 'Provision-CodexSandbox.ps1') -Destination $PayloadScripts -Force
Copy-Item -LiteralPath (Join-Path $KitRoot 'Test-CodexDeployment.ps1') -Destination $PayloadScripts -Force
Copy-Item -LiteralPath (Join-Path $KitRoot 'Install-CodexProvisioningPayload.ps1') -Destination $InstallerOut -Force
Copy-Item -LiteralPath (Join-Path $KitRoot 'requirements.toml') -Destination $PayloadRequirements -Force
Copy-Item -LiteralPath $PackageVerification -Destination (Join-Path $PayloadRoot 'package-verification.json') -Force

$Domain = Get-ADDomain -ErrorAction Stop
$DomainNetBIOS = [string]$Domain.NetBIOSName
$AuthorizedGroup = Get-ADGroup -Identity $AuthorizedUserGroupSamAccountName -ErrorAction Stop
$AuthorizedGroupDn = [string]$AuthorizedGroup.DistinguishedName

$RelativeFiles = @(
    'codex-package.json',
    'bin\codex.exe',
    'bin\codex-code-mode-host.exe',
    'codex-path\rg.exe',
    'codex-resources\codex-command-runner.exe',
    'codex-resources\codex-windows-sandbox-setup.exe'
)
$Hashes = [ordered]@{}
foreach ($RelativePath in $RelativeFiles) {
    $FullPath = Join-Path $PayloadCodex $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "必須ファイルがありません: $FullPath"
    }
    $Hashes[$RelativePath] = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash.ToUpperInvariant()
}
$RequirementsBytes = [IO.File]::ReadAllBytes($PayloadRequirements)
if ($RequirementsBytes.Length -ge 3 -and
    $RequirementsBytes[0] -eq 0xEF -and
    $RequirementsBytes[1] -eq 0xBB -and
    $RequirementsBytes[2] -eq 0xBF) {
    throw 'requirements.toml は UTF-8 BOM なしで保存してください。'
}
$RequirementsHash = (Get-FileHash -LiteralPath $PayloadRequirements -Algorithm SHA256).Hash.ToUpperInvariant()

$VersionOutput = (& (Join-Path $PayloadCodex 'bin\codex.exe') --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $VersionOutput -notmatch '([0-9][0-9A-Za-z.+-]*)$') {
    throw "codex.exe の版を取得できません: $VersionOutput"
}
if ($Matches[1] -cne $Version) {
    throw "codex.exe の版が不一致です。Expected=$Version Actual=$($Matches[1])"
}

function Escape-SingleQuotedPowerShellString {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

$EscapedDomain = Escape-SingleQuotedPowerShellString $DomainNetBIOS
$EscapedGroupDn = Escape-SingleQuotedPowerShellString $AuthorizedGroupDn
$EscapedVersion = Escape-SingleQuotedPowerShellString $Version
$EscapedPolicyVersion = Escape-SingleQuotedPowerShellString $PolicyVersion

$ConfigText = @"
@{
    SchemaVersion = 1
    PolicyVersion = '$EscapedPolicyVersion'
    ExpectedDomainNetBIOS = '$EscapedDomain'
    AuthorizedUserGroupDistinguishedName = '$EscapedGroupDn'

    CodexPackageRoot = 'C:\Program Files\OpenAI\CodexCLI'
    CodexExeRelativePath = 'bin\codex.exe'
    ApprovedCodexVersion = '$EscapedVersion'

    RequiredFiles = @{
        'codex-package.json' = '$($Hashes['codex-package.json'])'
        'bin\codex.exe' = '$($Hashes['bin\codex.exe'])'
        'bin\codex-code-mode-host.exe' = '$($Hashes['bin\codex-code-mode-host.exe'])'
        'codex-path\rg.exe' = '$($Hashes['codex-path\rg.exe'])'
        'codex-resources\codex-command-runner.exe' = '$($Hashes['codex-resources\codex-command-runner.exe'])'
        'codex-resources\codex-windows-sandbox-setup.exe' = '$($Hashes['codex-resources\codex-windows-sandbox-setup.exe'])'
    }

    RequirementsPath = 'C:\ProgramData\OpenAI\Codex\requirements.toml'
    RequirementsSha256 = '$RequirementsHash'

    ScriptRoot = 'C:\Program Files\Company\CodexProvisioning'
    StateRoot = 'C:\ProgramData\Company\CodexProvisioning'
    TaskName = 'OpenAI Codex Elevated Sandbox Provisioning'

    AllowRoamingProfile = `$false
    AllowTargetChange = `$false
    SetupTimeoutSeconds = 720
}
"@

$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($ConfigOut, $ConfigText, $Utf8Bom)
$Config = Import-PowerShellDataFile -LiteralPath $ConfigOut
if ([string]$Config.ApprovedCodexVersion -cne $Version) {
    throw '生成した CodexDeploymentConfig.psd1 の版が不一致です。'
}

$Manifest = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    version = $Version
    target = $Target
    policyVersion = $PolicyVersion
    expectedDomainNetBIOS = $DomainNetBIOS
    authorizedUserGroupDistinguishedName = $AuthorizedGroupDn
    requirementsSha256 = $RequirementsHash
    packageHashes = $Hashes
    payloadRoot = $PayloadRoot
}
$Manifest |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $PayloadRoot 'payload-manifest.json') -Encoding UTF8

Write-Host 'Codex deployment payload created.' -ForegroundColor Green
Write-Host "PayloadRoot: $PayloadRoot" -ForegroundColor Green
Write-Host "Config: $ConfigOut" -ForegroundColor Green
exit 0
