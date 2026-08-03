[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [ValidateSet('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')]
    [string]$Target,

    [string]$OutputRoot = 'C:\CodexDeployment\Staging'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($env:OS -ne 'Windows_NT') {
    throw 'このスクリプトは Windows 専用です。'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Codex CLI は 64-bit Windows が必要です。'
}
if ([version]$Version -lt [version]'0.138.0') {
    throw 'Codex CLI は 0.138.0 以上を指定してください。'
}

$Tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path -LiteralPath $Tar -PathType Leaf)) {
    throw "tar.exe がありません: $Tar"
}

$StageRoot = Join-Path $OutputRoot "$Version-$Target"
$PackageRoot = Join-Path $StageRoot 'CodexCLI'
$DownloadRoot = Join-Path $StageRoot 'Download'
$BaseUri = "https://releases.openai.com/codex/releases/$Version"
$MetadataUri = "$BaseUri/release.json"
$PackageName = "codex-package-$Target.tar.gz"
$ChecksumName = 'codex-package_SHA256SUMS'
$PackagePath = Join-Path $DownloadRoot $PackageName
$ChecksumPath = Join-Path $DownloadRoot $ChecksumName

Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $PackageRoot, $DownloadRoot | Out-Null

function Get-OfficialAssetDigest {
    param(
        [Parameter(Mandatory = $true)]$ReleaseMetadata,
        [Parameter(Mandatory = $true)][string]$AssetName
    )

    $Asset = @($ReleaseMetadata.assets | Where-Object { $_.name -eq $AssetName }) |
        Select-Object -First 1
    if ($null -eq $Asset) {
        throw "リリースに資産がありません: $AssetName"
    }

    $Match = [regex]::Match([string]$Asset.digest, '^sha256:([0-9a-fA-F]{64})$')
    if (-not $Match.Success) {
        throw "公式メタデータに SHA-256 がありません: $AssetName"
    }
    return $Match.Groups[1].Value.ToLowerInvariant()
}

Write-Host "Release metadata: $MetadataUri"
$Metadata = Invoke-RestMethod -Uri $MetadataUri -TimeoutSec 60
$ResolvedVersion = ([string]$Metadata.tag_name) -replace '^rust-v', ''
$ResolvedVersion = $ResolvedVersion -replace '^v', ''
if ($ResolvedVersion -cne $Version) {
    throw "リリースメタデータの版が不一致です。Expected=$Version Actual=$ResolvedVersion"
}

$OfficialChecksumHash = Get-OfficialAssetDigest -ReleaseMetadata $Metadata -AssetName $ChecksumName
$OfficialPackageHash = Get-OfficialAssetDigest -ReleaseMetadata $Metadata -AssetName $PackageName

Invoke-WebRequest -UseBasicParsing -Uri "$BaseUri/$ChecksumName" -OutFile $ChecksumPath -TimeoutSec 300
Invoke-WebRequest -UseBasicParsing -Uri "$BaseUri/$PackageName" -OutFile $PackagePath -TimeoutSec 900

$ActualChecksumHash = (Get-FileHash -LiteralPath $ChecksumPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualChecksumHash -ne $OfficialChecksumHash) {
    throw "SHA256SUMS 自体のハッシュが不一致です。Expected=$OfficialChecksumHash Actual=$ActualChecksumHash"
}

$EscapedName = [regex]::Escape($PackageName)
$PackageHashMatch = $null
foreach ($Line in Get-Content -LiteralPath $ChecksumPath) {
    $Match = [regex]::Match($Line, "^\s*([0-9a-fA-F]{64})\s+$EscapedName\s*$")
    if ($Match.Success) {
        $PackageHashMatch = $Match
        break
    }
}
if ($null -eq $PackageHashMatch) {
    throw "公式 SHA256SUMS に $PackageName がありません。"
}

$ExpectedPackageHash = $PackageHashMatch.Groups[1].Value.ToLowerInvariant()
if ($ExpectedPackageHash -ne $OfficialPackageHash) {
    throw "release.json と SHA256SUMS のハッシュが一致しません。Metadata=$OfficialPackageHash SHA256SUMS=$ExpectedPackageHash"
}

$ActualPackageHash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualPackageHash -ne $ExpectedPackageHash) {
    throw "Codex パッケージの SHA-256 が不一致です。Expected=$ExpectedPackageHash Actual=$ActualPackageHash"
}

& $Tar -xzf $PackagePath -C $PackageRoot
if ($LASTEXITCODE -ne 0) {
    throw "Codex パッケージの展開に失敗しました。ExitCode=$LASTEXITCODE"
}

$Required = @(
    'codex-package.json',
    'bin\codex.exe',
    'bin\codex-code-mode-host.exe',
    'codex-path\rg.exe',
    'codex-resources\codex-command-runner.exe',
    'codex-resources\codex-windows-sandbox-setup.exe'
)

$FileHashes = [ordered]@{}
foreach ($RelativePath in $Required) {
    $FullPath = Join-Path $PackageRoot $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "公式パッケージ構造が不足しています: $FullPath"
    }
    $FileHashes[$RelativePath] = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash.ToUpperInvariant()
}

$VersionOutput = (& (Join-Path $PackageRoot 'bin\codex.exe') --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $VersionOutput -notmatch '([0-9][0-9A-Za-z.+-]*)$') {
    throw "codex.exe の版を取得できません: $VersionOutput"
}
$BinaryVersion = $Matches[1]
if ($BinaryVersion -cne $Version) {
    throw "codex.exe の版が不一致です。Expected=$Version Actual=$BinaryVersion"
}

$VerificationRecord = [ordered]@{
    schemaVersion = 1
    verifiedAtUtc = [DateTime]::UtcNow.ToString('o')
    version = $Version
    target = $Target
    releaseMetadata = $MetadataUri
    packageName = $PackageName
    packageSha256 = $ActualPackageHash
    checksumManifestName = $ChecksumName
    checksumManifestSha256 = $ActualChecksumHash
    packageRoot = $PackageRoot
    codexVersionOutput = $VersionOutput
    fileHashes = $FileHashes
}
$VerificationPath = Join-Path $StageRoot 'package-verification.json'
$VerificationRecord |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $VerificationPath -Encoding UTF8

Write-Host 'Codex official package verification completed.' -ForegroundColor Green
Write-Host "PackageRoot: $PackageRoot" -ForegroundColor Green
Write-Host "Verification: $VerificationPath" -ForegroundColor Green
Write-Host "Archive SHA-256: $ActualPackageHash" -ForegroundColor Green
exit 0
