# Consomme 設定スクリプト。Windows PowerShell 5.1 / PowerShell 7 対応。
# 実行すると、このユーザーの WSL 2 全体の設定を変更して WSL を停止します。
$ErrorActionPreference = 'Stop'

try {
    if (-not $env:USERPROFILE) { throw 'USERPROFILE が見つかりません。' }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe が見つかりません。WSL の導入状態を確認してください。' }

    # consomme への名称変更が記載された WSL 2.9.3 より古い場合は書き換えない。
    $versionOutput = (& wsl.exe --version 2>&1 | Out-String).Replace([string][char]0, '')
    if ($LASTEXITCODE -ne 0) { throw 'wsl --version を実行できません。WSL のバージョンを確認してください。' }
    $versionMatch = [regex]::Match($versionOutput, '(?m)^\s*WSL[^\r\n]*?\b(\d+\.\d+\.\d+(?:\.\d+)?)\b')
    if (-not $versionMatch.Success) { throw 'WSL のバージョンを判定できません。設定は変更していません。' }
    $wslVersion = [version]$versionMatch.Groups[1].Value
    if ($wslVersion -lt [version]'2.9.3') { throw "WSL $wslVersion はこのスクリプトの対象外です。管理者に対応バージョンを確認してください。" }

    $configPath = Join-Path $env:USERPROFILE '.wslconfig'
    $configExists = Test-Path -LiteralPath $configPath
    $backupPath = $null
    $originalHash = $null
    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $newLine = "`r`n"
    $originalText = ''

    if ($configExists) {
        if ((Get-Item -LiteralPath $configPath).PSIsContainer) { throw '.wslconfig はファイルではありません。' }
        $originalBytes = [System.IO.File]::ReadAllBytes($configPath)
        if (($originalBytes.Length -ge 2) -and ((($originalBytes[0] -eq 0xFF) -and ($originalBytes[1] -eq 0xFE)) -or (($originalBytes[0] -eq 0xFE) -and ($originalBytes[1] -eq 0xFF)))) {
            throw '既存の .wslconfig が UTF-16 のため、安全に変更できません。文字コードを確認してください。'
        }
        try { $originalText = $strictUtf8.GetString($originalBytes) } catch { throw '既存の .wslconfig は有効な UTF-8 ではありません。安全のため変更しません。' }
        $originalText = $originalText.TrimStart([char]0xFEFF)
        if ($originalText.Contains([char]0)) { throw '既存の .wslconfig に不正な NUL 文字があります。変更しません。' }
        if ($originalText.Contains("`r`n")) { $newLine = "`r`n" } elseif ($originalText.Contains("`n")) { $newLine = "`n" } elseif ($originalText.Contains("`r")) { $newLine = "`r" }
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try { $originalHash = [BitConverter]::ToString($sha256.ComputeHash($originalBytes)).Replace('-', '') } finally { $sha256.Dispose() }
    }

    # 行以外の内容を維持し、同じセクション・設定が重複している曖昧なファイルは拒否。
    $lines = New-Object 'System.Collections.Generic.List[string]'
    if ($originalText.Length -gt 0) { $lines.AddRange([string[]]([regex]::Split($originalText, '\r\n|\n|\r'))) }
    $section = ''
    $wsl2Count = 0
    $keyCount = 0
    $wsl2Start = -1
    $wsl2End = $lines.Count
    $keyIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*[#;]') { continue }
        if ($line -match '^\s*\[(?<section>[^\]]+)\]\s*(?:[#;].*)?$') {
            if (($section -eq 'wsl2') -and ($wsl2End -eq $lines.Count)) { $wsl2End = $i }
            $section = $Matches['section'].Trim().ToLowerInvariant()
            if ($section -eq 'wsl2') { $wsl2Count++; $wsl2Start = $i }
            continue
        }
        if ($line -match '^\s*\[') { throw '解析できないセクション行があります。安全のため変更しません。' }
        if ($line -match '^\s*networkingMode\s*=') {
            if ($section -eq 'experimental') { throw '[experimental] に networkingMode があるため、競合を避けて変更しません。' }
            if ($section -eq 'wsl2') { $keyCount++; $keyIndex = $i }
        }
    }
    if ($wsl2Count -gt 1) { throw '[wsl2] が重複しているため、変更しません。' }
    if ($keyCount -gt 1) { throw '[wsl2] の networkingMode が重複しているため、変更しません。' }

    if ($keyIndex -ge 0) {
        $match = [regex]::Match($lines[$keyIndex], '^(?<prefix>\s*networkingMode\s*=\s*)(?<value>[^#;]*?)(?<tail>\s*(?:[#;].*)?)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { throw 'networkingMode の行を解析できないため、変更しません。' }
        $lines[$keyIndex] = $match.Groups['prefix'].Value + 'consomme' + $match.Groups['tail'].Value
    } elseif ($wsl2Start -ge 0) {
        $lines.Insert($wsl2End, 'networkingMode=consomme')
    } else {
        if (($lines.Count -gt 0) -and ($lines[$lines.Count - 1] -ne '')) { $lines.Add('') }
        $lines.Add('[wsl2]')
        $lines.Add('networkingMode=consomme')
    }
    $newText = [string]::Join($newLine, $lines)
    if (-not $newText.EndsWith($newLine)) { $newText += $newLine }

    # 同じフォルダに一時ファイルを完全に書き、既存ファイルは原子的に差し替える。
    # 書き込み途中の失敗では元ファイルを触らない。
    $stagePath = Join-Path $env:USERPROFILE ('.wslconfig.consomme-stage-' + [guid]::NewGuid().ToString('N'))
    try {
        $newBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($newText)
        $stageStream = [System.IO.File]::Open($stagePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try { $stageStream.Write($newBytes, 0, $newBytes.Length); $stageStream.Flush($true) } finally { $stageStream.Dispose() }
        if ($configExists) {
            if ((Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne $originalHash) { throw '設定ファイルが処理中に変更されました。再度実行してください。' }
            $backupPath = Join-Path $env:USERPROFILE ('.wslconfig.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            if (Test-Path -LiteralPath $backupPath) { throw 'バックアップ先がすでに存在します。再度実行してください。' }
            [System.IO.File]::Replace($stagePath, $configPath, $backupPath)
            Write-Host "既存設定のバックアップ: $backupPath"
        } else {
            if (Test-Path -LiteralPath $configPath) { throw '処理中に設定ファイルが作成されました。再度実行してください。' }
            [System.IO.File]::Move($stagePath, $configPath)
            Write-Host '設定前の .wslconfig: なし'
        }
    } catch {
        if (Test-Path -LiteralPath $stagePath) {
            $archiveDir = Join-Path $PSScriptRoot '削除対象フォルダ'
            New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
            $archivePath = Join-Path $archiveDir ('.wslconfig-stage-' + [guid]::NewGuid().ToString('N') + '.txt')
            Move-Item -LiteralPath $stagePath -Destination $archivePath -ErrorAction Stop
        }
        throw
    }
    $writtenHash = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
    Write-Host "設定を書き込みました: $configPath"
    Write-Host '実行中のすべての WSL ディストリビューションを停止します。'
    try {
        & wsl.exe --shutdown
        if ($LASTEXITCODE -ne 0) { throw "wsl --shutdown が終了コード $LASTEXITCODE で失敗しました。" }
    } catch {
        # 変更後ファイルを捨てずに退避し、バックアップがある場合は元に戻す。
        if (-not (Test-Path -LiteralPath $configPath) -or ((Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne $writtenHash)) {
            throw "WSL の停止後に設定が変化したため、自動復元しません。バックアップ: $backupPath。詳細: $_"
        }
        $archiveDir = Join-Path $PSScriptRoot '削除対象フォルダ'
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
        $archivePath = Join-Path $archiveDir ('.wslconfig-failed-' + [guid]::NewGuid().ToString('N') + '.txt')
        Move-Item -LiteralPath $configPath -Destination $archivePath -ErrorAction Stop
        if ($backupPath) { Copy-Item -LiteralPath $backupPath -Destination $configPath -ErrorAction Stop }
        throw "WSL の停止に失敗したため、設定を元に戻しました。退避先: $archivePath。詳細: $_"
    }
    Write-Host ''
    Write-Host '設定を保存し、WSL を停止しました。次回 Ubuntu 起動時に設定が読み込まれます。'
    Write-Host '適用成功や MAC の固定は保証されません。Ubuntu で ip -br link と ip -4 -br address を確認し、Claude Code と必要な業務アプリをテストしてください。'
    Write-Host '問題があれば「Consomme設定手順書.md」の元に戻す方法を参照してください。'
    exit 0
} catch {
    Write-Error "設定に失敗しました: $_" -ErrorAction Continue
    exit 1
}
