# requirements.toml の配置先
$DestinationFolder = "$env:ProgramData\OpenAI\Codex"
$DestinationFile = Join-Path $DestinationFolder "requirements.toml"

# このPS1ファイルと同じフォルダにある requirements.toml
$SourceFile = Join-Path $PSScriptRoot "requirements.toml"

# 配布元ファイルの存在確認
if (-not (Test-Path $SourceFile)) {
    Write-Error "requirements.toml が見つかりません: $SourceFile"
    exit 1
}

# 配置先フォルダが存在しない場合は作成
if (-not (Test-Path $DestinationFolder)) {
    New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
}

# requirements.toml をコピー
# 既に存在する場合は上書き
Copy-Item -Path $SourceFile -Destination $DestinationFile -Force

Write-Host "requirements.toml を配置しました。"
Write-Host "配置先: $DestinationFile"

exit 0
