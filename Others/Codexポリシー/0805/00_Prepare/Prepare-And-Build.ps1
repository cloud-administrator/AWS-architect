[CmdletBinding()]
param(
    [ValidateSet('Auto', 'x64', 'arm64')]
    [string]$Architecture = 'Auto',
    [string]$OutputDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($env:OS -ne 'Windows_NT') {
    throw 'この準備スクリプトは64ビットWindows上で実行してください。'
}
if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
    throw '64ビットPowerShellで実行してください。Run-Prepare-And-Build.cmdを使用します。'
}

$packageRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $packageRoot 'Output'
}

$versionPath = Join-Path $packageRoot 'APPROVED_CODEX_VERSION.txt'
$hashTablePath = Join-Path $packageRoot 'APPROVED_CODEX_PACKAGE_HASHES.csv'
$targetsPath = Join-Path $packageRoot 'targets.csv'
$systemTemplate = Join-Path $packageRoot '01_SYSTEM_TEMPLATE'
$userTemplate = Join-Path $packageRoot '02_USER_TEMPLATE'

foreach ($required in @($versionPath, $hashTablePath, $targetsPath, $systemTemplate, $userTemplate)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "必要なファイルまたはフォルダーがありません: $required"
    }
}

$approvedVersion = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
if ($approvedVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') {
    throw "APPROVED_CODEX_VERSION.txtの値が不正です: $approvedVersion"
}

function Test-EnabledValue {
    param([object]$Value)
    $text = ([string]$Value).Trim()
    if ($text -eq '1') { return $true }
    if ($text -eq '0') { return $false }
    throw "Enabled列は1または0で指定してください。値='$text'"
}

function Test-TargetCsv {
    param([Parameter(Mandatory = $true)][string]$Path)

    $rows = @(Import-Csv -LiteralPath $Path -Encoding UTF8)
    if ($rows.Count -eq 0) { throw 'targets.csvにデータ行がありません。' }
    $headers = @($rows[0].PSObject.Properties.Name)
    $expected = @('ComputerName', 'Domain', 'SamAccountName', 'Enabled')
    if ($headers.Count -ne $expected.Count) {
        throw 'targets.csvの列は ComputerName,Domain,SamAccountName,Enabled の4列だけにしてください。'
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
            throw "targets.csvの${line}行目: ComputerNameが不正です。FQDNではなくhostnameの結果を指定してください。"
        }
        if ($domain -match '[\\/@]' -or $sam -match '[\\/@]') {
            throw "targets.csvの${line}行目: DomainとSamAccountNameは分けて入力してください。"
        }
        if ($isEnabled) {
            $enabled += [PSCustomObject]@{
                ComputerName = $computer
                Domain = $domain
                SamAccountName = $sam
                Line = $line
            }
        }
    }
    if ($enabled.Count -eq 0) { throw 'targets.csvにEnabled=1の行がありません。' }
    $duplicates = @($enabled | Group-Object -Property ComputerName | Where-Object { $_.Count -gt 1 })
    if ($duplicates.Count -gt 0) {
        throw ("同じComputerNameにEnabled=1の行が複数あります: {0}" -f (($duplicates | ForEach-Object { $_.Name }) -join ', '))
    }
}

function Get-HostArchitecture {
    $arch = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($arch -ieq 'X64') { return 'x64' }
    if ($arch -ieq 'Arm64') { return 'arm64' }
    throw "未対応の準備端末アーキテクチャです: $arch"
}

function Get-PackageRoot {
    param([Parameter(Mandatory = $true)][string]$ExtractRoot)

    $required = @(
        'codex-package.json',
        'bin\codex.exe',
        'bin\codex-code-mode-host.exe',
        'codex-path\rg.exe',
        'codex-resources\codex-command-runner.exe',
        'codex-resources\codex-windows-sandbox-setup.exe'
    )
    $candidates = @()
    foreach ($descriptor in Get-ChildItem -LiteralPath $ExtractRoot -Filter 'codex-package.json' -File -Recurse -Force) {
        $candidate = $descriptor.Directory.FullName
        $complete = $true
        foreach ($relative in $required) {
            if (-not (Test-Path -LiteralPath (Join-Path $candidate $relative) -PathType Leaf)) {
                $complete = $false
                break
            }
        }
        if ($complete) { $candidates += $candidate }
    }
    if ($candidates.Count -ne 1) {
        throw "完全なCodex Windowsフルパッケージを一意に検出できません。候補数=$($candidates.Count)"
    }
    return $candidates[0]
}

function Write-FileManifest {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $rows = @()
    foreach ($file in Get-ChildItem -LiteralPath $RootPath -File -Recurse -Force | Sort-Object -Property FullName) {
        if ($file.Name -ieq 'PACKAGE_SHA256.csv') { continue }
        $relative = $file.FullName.Substring($rootFull.Length).TrimStart('\')
        $rows += [PSCustomObject]@{
            RelativePath = $relative
            SHA256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
            Length = [int64]$file.Length
        }
    }
    $rows | Export-Csv -LiteralPath (Join-Path $RootPath 'PACKAGE_SHA256.csv') -NoTypeInformation -Encoding UTF8
}

Test-TargetCsv -Path $targetsPath

$hostArchitecture = Get-HostArchitecture
$selectedArchitecture = if ($Architecture -ieq 'Auto') { $hostArchitecture } else { $Architecture.ToLowerInvariant() }
if ($selectedArchitecture -ine $hostArchitecture) {
    throw "実行ファイル検証のため、$selectedArchitecture 用媒体は同じアーキテクチャのWindows準備端末で作成してください。準備端末=$hostArchitecture"
}

$hashRows = @(Import-Csv -LiteralPath $hashTablePath -Encoding UTF8)
$approved = @($hashRows | Where-Object {
    ([string]$_.Version).Trim() -eq $approvedVersion -and
    ([string]$_.Architecture).Trim() -ieq $selectedArchitecture
})
if ($approved.Count -ne 1) {
    throw "承認済みハッシュを一意に特定できません。Version=$approvedVersion Architecture=$selectedArchitecture"
}
$approvedRow = $approved[0]
$packageName = ([string]$approvedRow.PackageName).Trim()
$expectedSha256 = ([string]$approvedRow.SHA256).Trim().ToUpperInvariant()
if ($expectedSha256 -notmatch '^[0-9A-F]{64}$') { throw '承認済みSHA-256の形式が不正です。' }

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # Newer PowerShell negotiates TLS automatically.
}

$tempRoot = Join-Path $env:TEMP ("OpenAI-Codex-SKYSEA-Build-{0}" -f [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $tempRoot $packageName
$sumPath = Join-Path $tempRoot 'codex-package_SHA256SUMS'
$extractRoot = Join-Path $tempRoot 'Extracted'
$payloadRoot = Join-Path $tempRoot 'Payload'

try {
    New-Item -ItemType Directory -Path $tempRoot, $extractRoot, $payloadRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

    $baseUrl = "https://releases.openai.com/codex/releases/$approvedVersion"
    $archiveUrl = "$baseUrl/$packageName"
    $sumUrl = "$baseUrl/codex-package_SHA256SUMS"

    Write-Host "OpenAI公式フルパッケージを取得します: $archiveUrl"
    Invoke-WebRequest -UseBasicParsing -Uri $archiveUrl -OutFile $archivePath
    Invoke-WebRequest -UseBasicParsing -Uri $sumUrl -OutFile $sumPath

    $actualSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualSha256 -cne $expectedSha256) {
        throw "アーカイブSHA-256が承認値と一致しません。Expected=$expectedSha256 Actual=$actualSha256"
    }
    $upstreamLine = @(Get-Content -LiteralPath $sumPath | Where-Object { $_ -match ([regex]::Escape($packageName) + '$') })
    if ($upstreamLine.Count -ne 1) { throw 'OpenAI SHA256SUMSから対象アーカイブを一意に特定できません。' }
    $upstreamSha256 = (($upstreamLine[0] -split '\s+')[0]).Trim().ToUpperInvariant()
    if ($upstreamSha256 -cne $expectedSha256) {
        throw "ローカル承認値とOpenAI公開SHA-256が一致しません。Approved=$expectedSha256 Upstream=$upstreamSha256"
    }

    $tar = Get-Command 'tar.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $tar) { throw 'tar.exeが見つかりません。更新済みWindows 10/11で実行してください。' }
    & $tar.Source -xzf $archivePath -C $extractRoot
    if ($LASTEXITCODE -ne 0) { throw "Codexアーカイブの展開に失敗しました。終了コード=$LASTEXITCODE" }

    $codexPackageRoot = Get-PackageRoot -ExtractRoot $extractRoot
    $codexExe = Join-Path $codexPackageRoot 'bin\codex.exe'
    $versionOutput = @(& $codexExe --version 2>&1)
    if ($LASTEXITCODE -ne 0) { throw '取得したcodex.exeのバージョン確認に失敗しました。' }
    $versionText = (($versionOutput | ForEach-Object { [string]$_ }) -join ' ').Trim()
    if ($versionText -notmatch [regex]::Escape($approvedVersion)) {
        throw "codex --versionが承認版と一致しません。Output=$versionText Approved=$approvedVersion"
    }
    $helpOutput = @(& $codexExe sandbox setup --help 2>&1)
    $helpText = (($helpOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    if ($LASTEXITCODE -ne 0 -or
        $helpText -notmatch [regex]::Escape('--elevated') -or
        $helpText -notmatch [regex]::Escape('--user') -or
        $helpText -notmatch [regex]::Escape('--codex-home')) {
        throw '取得したCodexに管理配布用sandbox setupコマンドがありません。'
    }

    $systemPayload = Join-Path $payloadRoot "SYSTEM-$selectedArchitecture"
    New-Item -ItemType Directory -Path $systemPayload -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $systemTemplate 'RUN_AS_SYSTEM.cmd') -Destination $systemPayload -Force
    Copy-Item -LiteralPath (Join-Path $systemTemplate 'Deploy-CodexSandbox.ps1') -Destination $systemPayload -Force
    Copy-Item -LiteralPath $targetsPath -Destination (Join-Path $systemPayload 'targets.csv') -Force
    $toolDestination = Join-Path $systemPayload 'CodexTool'
    New-Item -ItemType Directory -Path $toolDestination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $codexPackageRoot -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $toolDestination -Recurse -Force
    }
    $packageInfo = [ordered]@{
        SchemaVersion = 1
        ApprovedVersion = $approvedVersion
        Architecture = $selectedArchitecture
        PackageName = $packageName
        PackageArchiveSha256 = $expectedSha256
        SourceUrl = $archiveUrl
        CodexVersionOutput = $versionText
        PreparedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $packageInfo | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $toolDestination 'PACKAGE_INFO.json') -Encoding UTF8
    Write-FileManifest -RootPath $toolDestination

    $systemZip = Join-Path $OutputDirectory ("SKYSEA_CodexSandbox_SYSTEM_{0}_{1}.zip" -f $approvedVersion, $selectedArchitecture)
    if (Test-Path -LiteralPath $systemZip) { Remove-Item -LiteralPath $systemZip -Force }
    Compress-Archive -Path (Join-Path $systemPayload '*') -DestinationPath $systemZip -CompressionLevel Optimal

    $userPayload = Join-Path $payloadRoot 'USER'
    New-Item -ItemType Directory -Path $userPayload -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $userTemplate 'RUN_AS_TARGET_USER.cmd') -Destination $userPayload -Force
    Copy-Item -LiteralPath (Join-Path $userTemplate 'Install-ChatGPTForAuthorizedUser.ps1') -Destination $userPayload -Force
    $userZip = Join-Path $OutputDirectory 'SKYSEA_ChatGPT_USER.zip'
    if (Test-Path -LiteralPath $userZip) { Remove-Item -LiteralPath $userZip -Force }
    Compress-Archive -Path (Join-Path $userPayload '*') -DestinationPath $userZip -CompressionLevel Optimal

    $outputRows = @()
    foreach ($file in @($systemZip, $userZip)) {
        $item = Get-Item -LiteralPath $file
        $outputRows += [PSCustomObject]@{
            FileName = $item.Name
            SHA256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
            Length = [int64]$item.Length
        }
    }
    $outputHashPath = Join-Path $OutputDirectory 'SKYSEA_MEDIA_SHA256.csv'
    $outputRows | Export-Csv -LiteralPath $outputHashPath -NoTypeInformation -Encoding UTF8

    Write-Host ''
    Write-Host 'SKYSEA登録用媒体の作成が完了しました。'
    Write-Host "Codex: $versionText"
    Write-Host "SYSTEM媒体: $systemZip"
    Write-Host "USER媒体: $userZip"
    Write-Host "ハッシュ一覧: $outputHashPath"
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
