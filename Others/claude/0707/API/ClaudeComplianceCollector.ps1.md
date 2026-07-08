<#
.SYNOPSIS
  Claude Enterprise Compliance API から監査ログと eDiscovery 用コンテンツを取得するコレクターです。

.DESCRIPTION
  このスクリプトは、Claude Enterprise の Compliance API を使って、次の情報を取得・保存します。

  1. Activity Feed
     - 監査ログの中心となる Activity オブジェクトを取得します。
     - API から返された Activity オブジェクトは、後から監査・再解析できるよう raw JSON のまま JSONL 形式で保存します。
     - activity.id を一意キーとして扱い、再取得やリトライで同じログが返っても重複保存しないようにします。

  2. chat / project content
     - chat metadata、chat messages、artifact text、project metadata、project details、project documents を取得します。
     - 添付ファイルや Claude が生成したバイナリファイルの中身は取得しません。
       ファイルIDやメタデータは保存しますが、容量を圧迫するバイナリ content endpoint は呼び出しません。

  3. checkpoint
     - Activity Feed は first_id / last_id を checkpoint.json に保存します。
     - 初回の Backfill では last_id を after_id として使い、過去方向に取得します。
     - 継続取得の Tail では first_id を before_id として使い、新しいログだけを取得します。
     - API から取得しただけでは checkpoint を進めません。
       必ず「ファイル保存」と「重複排除用 index 保存」が成功した後に checkpoint を更新します。

  4. 運用ログ
     - 通常ログ、エラーログ、API request-id ログ、実行サマリーを出力します。
     - タスクスケジューラで 1 日 1 回実行しても、前回実行中であれば多重起動を防ぎます。

  主な保存先:
    C:\ProgramData\ClaudeComplianceCollector\data\raw\...
    C:\ProgramData\ClaudeComplianceCollector\state\checkpoint.json
    C:\ProgramData\ClaudeComplianceCollector\logs\...

.NOTES
  - API キーはスクリプトに直書きしません。
  - 既定では ANTHROPIC_COMPLIANCE_ACCESS_KEY 環境変数から読み込みます。
  - 文字化け防止のため、このファイルは UTF-8 with BOM で保存することを推奨します。
#>

[CmdletBinding()]
param(
    # 実行モードを指定します。
    # - ActivityBackfill : 初回または過去方向の Activity Feed 取得
    # - ActivityTail     : checkpoint 以降の新しい Activity Feed 取得
    # - ContentBackfill  : chat / project content の取得
    # - ContentTail      : chat / project content の継続取得
    # - AllBackfill      : ActivityBackfill + content 取得
    # - AllTail          : ActivityTail + content 取得
    # - Status           : checkpoint と最新実行状態の表示のみ
    [Parameter(Mandatory = $false)]
    [ValidateSet('ActivityBackfill','ActivityTail','ContentBackfill','ContentTail','AllBackfill','AllTail','Status')]
    [string]$Mode = 'ActivityTail',

    # 保存先のルートフォルダです。
    # C ドライブ直下ではなく、ProgramData 配下の専用フォルダを既定値にしています。
    [Parameter(Mandatory = $false)]
    [string]$Root = 'C:\ProgramData\ClaudeComplianceCollector',

    # Compliance Access Key を格納した Windows 環境変数名です。
    # キーをコードやログに出さないため、値そのものではなく環境変数名だけを指定します。
    [Parameter(Mandatory = $false)]
    [string]$ApiKeyEnvName = 'ANTHROPIC_COMPLIANCE_ACCESS_KEY',

    # Activity Feed の 1 API 呼び出しあたりの最大取得件数です。
    # 大量ログ環境では大きくすると効率は良い一方、1 回の保存処理も重くなります。
    [Parameter(Mandatory = $false)]
    [ValidateRange(1,5000)]
    [int]$ActivityLimit = 5000,

    # chat 一覧を取得する際の 1 ページあたりの件数です。
    [Parameter(Mandatory = $false)]
    [ValidateRange(1,1000)]
    [int]$ChatListLimit = 100,

    # 1 つの chat に含まれる message を取得する際の 1 ページあたりの件数です。
    [Parameter(Mandatory = $false)]
    [ValidateRange(1,5000)]
    [int]$ChatMessagesLimit = 500,

    # project 一覧を取得する際の 1 ページあたりの件数です。
    [Parameter(Mandatory = $false)]
    [ValidateRange(1,1000)]
    [int]$ProjectListLimit = 100,

    # project attachment 一覧を取得する際の 1 ページあたりの件数です。
    [Parameter(Mandatory = $false)]
    [ValidateRange(1,1000)]
    [int]$ProjectAttachmentsLimit = 100,

    # 一時的な API エラーや通信エラーが起きた場合の最大リトライ回数です。
    # checkpoint を進めず、同じ位置から再試行します。
    [Parameter(Mandatory = $false)]
    [ValidateRange(0,20)]
    [int]$MaxRetries = 8,

    # API 呼び出しのタイムアウト秒数です。
    [Parameter(Mandatory = $false)]
    [ValidateRange(10,1800)]
    [int]$TimeoutSec = 120,

    # API 呼び出し間に最低限あける待機時間です。
    # 250ms の場合、このコレクター単体ではおおむね 240 requests/minute 以下になります。
    # Compliance API のレート制限は組織全体で共有されるため、他の連携がある場合は 500ms や 1000ms に増やしてください。
    [Parameter(Mandatory = $false)]
    [ValidateRange(0,60000)]
    [int]$MinDelayMs = 250,

    # レスポンスヘッダー上の残りリクエスト数がこの値以下になったら、リセット時刻まで待機します。
    # 429 になる前に自発的に減速するための安全弁です。
    [Parameter(Mandatory = $false)]
    [ValidateRange(0,600)]
    [int]$ThrottleWhenRemainingBelow = 30,

    # project のフルスキャンをスキップします。
    # chat content は取得したいが、project の件数が多く処理時間を抑えたい場合に使います。
    [Parameter(Mandatory = $false)]
    [switch]$SkipProjectFullScan,

    # artifact のテキスト本文取得をスキップします。
    # なお、アップロードファイルや生成ファイルのバイナリ本文は、この指定に関係なく常に取得しません。
    [Parameter(Mandatory = $false)]
    [switch]$SkipArtifactText
)

# 未定義変数の利用などを早めに検出し、想定外の状態で処理を続けないようにします。
Set-StrictMode -Version 2.0
# エラー発生時は原則として catch に入り、checkpoint を進めずに終了できるようにします。
$ErrorActionPreference = 'Stop'

# -----------------------------
# グローバル実行状態
# -----------------------------
# ここでは、1 回の実行中に共有する値をまとめて保持します。
# $script:Stats は最後に summary_*.json / latest_status.json に保存され、監視にも使えます。
# Anthropic Compliance API のベース URL です。
$script:ApiBase = 'https://api.anthropic.com'
# 1 回の実行を識別する ID です。ログファイルや一時ファイル名に使います。
$script:RunId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$script:RunStartUtc = (Get-Date).ToUniversalTime()
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:ApiKey = $null
$script:Mutex = $null
$script:MutexAcquired = $false
$script:LastRequestUtc = [DateTime]::MinValue
$script:IndexCache = @{}
$script:CompleteIndexCache = @{}
$script:LogFile = $null
$script:ErrorLogFile = $null
$script:RequestLogFile = $null

# 監視・監査に必要な統計情報を 1 か所に集めます。
# 最終的に logs\summary_<RunId>.json と state\latest_status.json に保存されます。
$script:Stats = [ordered]@{
    run_id                    = $script:RunId
    mode                      = $Mode
    root                      = $Root
    start_utc                 = $script:RunStartUtc.ToString('o')
    end_utc                   = $null
    duration_seconds          = $null
    api_requests              = 0
    retry_count               = 0
    rate_limit_429_count      = 0
    error_count               = 0
    activity_fetched          = 0
    activity_saved            = 0
    activity_duplicate        = 0
    chat_list_items           = 0
    chat_metadata_saved       = 0
    chat_message_pages_saved  = 0
    artifact_text_saved       = 0
    projects_seen             = 0
    project_records_saved     = 0
    project_attachments_seen  = 0
    project_documents_saved   = 0
    file_binaries_skipped     = 0
    content_not_found         = 0
    start_checkpoint          = $null
    end_checkpoint            = $null
    last_request_id           = $null
    request_ids               = @()
    last_success_utc          = $null
    status                    = 'running'
    error                     = $null
}

# -----------------------------
# ファイル・フォルダ操作の共通関数
# -----------------------------
# 保存先ディレクトリ作成、ログ出力、checkpoint 保存、JSONL 保存などをここに集約します。
# 指定されたフォルダがなければ作成します。
# 保存先やログ先は事前に存在するとは限らないため、各所から安全に呼び出せる小さな共通関数にしています。
function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# このスクリプトが使うフォルダ構成を作成し、当日分のログファイルパスを決定します。
# 初回実行時でも C:\ProgramData\ClaudeComplianceCollector 配下に必要な state / logs / data / index を自動作成します。
function Initialize-Folders {
    Ensure-Directory -Path $Root
    foreach ($child in @(
        'state',
        'locks',
        'logs',
        'data\raw\activities',
        'data\raw\chats',
        'data\raw\chat_messages',
        'data\raw\artifacts',
        'data\raw\projects',
        'data\raw\project_details',
        'data\raw\project_attachments',
        'data\raw\project_documents',
        'data\raw\content_missing',
        'data\index',
        'data\index\complete'
    )) {
        Ensure-Directory -Path (Join-Path $Root $child)
    }

    $today = (Get-Date).ToUniversalTime().ToString('yyyyMMdd')
    $script:LogFile = Join-Path (Join-Path $Root 'logs') ("run_$today.txt")
    $script:ErrorLogFile = Join-Path (Join-Path $Root 'logs') ("error_$today.txt")
    $script:RequestLogFile = Join-Path (Join-Path $Root 'logs') ("requests_$today.jsonl")
}

# checkpoint や latest_status のような重要ファイルを「一時ファイルに書いてから置き換える」方式で保存します。
# 途中でプロセスが落ちても、壊れた半端なファイルが残りにくくなります。
function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $dir = Split-Path -Parent $Path
    Ensure-Directory -Path $dir
    # 直接本番ファイルに書かず、まず一時ファイルへ完全に書き込みます。
    $tmp = "$Path.tmp.$($script:RunId).$PID"
    [System.IO.File]::WriteAllText($tmp, $Content, $script:Utf8NoBom)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
    # 一時ファイルの書き込みが成功してから置き換えることで、半端な checkpoint を残しにくくします。
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# ログや JSONL のように追記型で保存するファイルへ、UTF-8 で文字列を追加します。
function Append-Text {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Text
    )
    $dir = Split-Path -Parent $Path
    Ensure-Directory -Path $dir
    [System.IO.File]::AppendAllText($Path, $Text, $script:Utf8NoBom)
}

# 通常の実行ログを書きます。ERROR の場合は、調査しやすいように error_YYYYMMDD.txt にも同じ内容を出力します。
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString('o')
    $line = "$timestamp`t$Level`t$Message"
    Append-Text -Path $script:LogFile -Text ($line + [Environment]::NewLine)
    if ($Level -eq 'ERROR') {
        Append-Text -Path $script:ErrorLogFile -Text ($line + [Environment]::NewLine)
    }
    Write-Host $line
}

# API 呼び出しごとの status code、request-id、rate-limit 情報を JSONL 形式で保存します。
# Anthropic サポートへの問い合わせや監査証跡で request-id を追えるようにするためです。
function Write-RequestLog {
    param([Parameter(Mandatory=$true)][hashtable]$Record)
    $json = ($Record | ConvertTo-Json -Depth 20 -Compress)
    Append-Text -Path $script:RequestLogFile -Text ($json + [Environment]::NewLine)
}

# checkpoint.json のフルパスを返します。checkpoint は取得再開位置を保持する最重要ファイルです。
function Get-StatePath {
    return (Join-Path (Join-Path $Root 'state') 'checkpoint.json')
}

# checkpoint.json がまだ存在しない初回実行時に使う既定状態を作ります。
# スクリプトの更新で新しい項目が増えた場合の初期値としても使います。
function Get-DefaultState {
    return [ordered]@{
        schema_version                  = 1
        activity_first_id               = $null
        activity_last_id                = $null
        activity_backfill_complete      = $false
        chat_last_id                    = $null
        chat_backfill_complete          = $false
        project_last_full_scan_utc      = $null
        last_success_utc                = $null
        last_success_mode               = $null
        updated_at_utc                  = $null
    }
}

# checkpoint.json を読み込みます。ファイルがない場合は初期状態を返します。
# JSON が壊れている場合は checkpoint を進めると危険なため、例外として停止します。
function Load-State {
    $path = Get-StatePath
    $default = Get-DefaultState
    if (-not (Test-Path -LiteralPath $path)) {
        return $default
    }
    try {
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $default }
        $obj = $raw | ConvertFrom-Json
        foreach ($k in @($default.Keys)) {
            if (-not ($obj.PSObject.Properties.Name -contains $k)) {
                Add-Member -InputObject $obj -NotePropertyName $k -NotePropertyValue $default[$k]
            }
        }
        return $obj
    }
    catch {
        throw "checkpoint.json の読み込みまたは JSON 変換に失敗しました。checkpoint は更新しません。詳細: $($_.Exception.Message)"
    }
}

# checkpoint.json を保存します。updated_at_utc を現在時刻に更新し、atomic write で安全に書き込みます。
function Save-State {
    param([Parameter(Mandatory=$true)]$State)
    $State.updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    $json = ($State | ConvertTo-Json -Depth 30)
    Write-TextFileAtomic -Path (Get-StatePath) -Content $json
}

# API が返す created_at / updated_at などの日時文字列を UTC の DateTime に変換します。
# 解析できない場合でも保存処理を止めず、警告ログを残して現在UTCを使います。
function Get-DateFromRfc3339OrNow {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return (Get-Date).ToUniversalTime()
    }
    try {
        return ([DateTimeOffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).UtcDateTime
    }
    catch {
        Write-Log -Level 'WARN' -Message "RFC3339日時として解析できませんでした。現在UTCで保存します。value=$Value"
        return (Get-Date).ToUniversalTime()
    }
}

# 日付単位の保存先パスと、重複排除用 index パスを作ります。
# 例: data\raw\activities\2026\07\07\activities_20260707.jsonl
function Get-PartitionPaths {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][datetime]$DateUtc,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [Parameter(Mandatory=$false)][string]$Extension = 'jsonl'
    )
    $yyyy = $DateUtc.ToString('yyyy')
    $mm = $DateUtc.ToString('MM')
    $dd = $DateUtc.ToString('dd')
    $yyyymmdd = $DateUtc.ToString('yyyyMMdd')
    $dataDir = Join-Path $Root ("data\raw\$Category\$yyyy\$mm\$dd")
    $indexDir = Join-Path $Root ("data\index\$Category\$yyyy\$mm")
    Ensure-Directory -Path $dataDir
    Ensure-Directory -Path $indexDir
    return [ordered]@{
        data_path  = (Join-Path $dataDir ("${Prefix}_${yyyymmdd}.${Extension}"))
        index_path = (Join-Path $indexDir ("${Prefix}_${yyyymmdd}.idx"))
    }
}

# JSONL は 1 レコード 1 行で保存する必要があるため、改行を取り除いて 1 行に整形します。
# Activity オブジェクト自体のフィールドは変更しません。
function Convert-ToJsonLine {
    param([Parameter(Mandatory=$true)][string]$Raw)
    # API から返る本文は有効な JSON である前提です。JSONL では 1 レコードを 1 物理行にする必要があります。
    return (($Raw.Trim()) -replace "`r`n", '' -replace "`n", '' -replace "`r", '')
}

# 文字列の SHA-256 ハッシュを返します。
# 本文や raw JSON の内容が同じかどうかを一意キーに含めるために使います。
function Get-Sha256Hex {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:Utf8NoBom.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

# 既存 JSONL 行から id を読み取ります。index 再構築時に activity.id を取り出すために使います。
function Get-ObjectIdFromJsonLine {
    param([Parameter(Mandatory=$true)][string]$Line)
    try {
        $obj = $Line | ConvertFrom-Json
        return [string]$obj.id
    }
    catch {
        return $null
    }
}

# Activity の重複排除 index が存在しない、または data より古い場合に再構築します。
# data に保存済みの activity.id を読み直して index を作るため、index 破損時の復旧に役立ちます。
function Rebuild-ActivityIndexIfNeeded {
    param(
        [Parameter(Mandatory=$true)][string]$DataPath,
        [Parameter(Mandatory=$true)][string]$IndexPath
    )
    $shouldRebuild = $false
    if ((Test-Path -LiteralPath $DataPath) -and (-not (Test-Path -LiteralPath $IndexPath))) {
        $shouldRebuild = $true
    }
    elseif ((Test-Path -LiteralPath $DataPath) -and (Test-Path -LiteralPath $IndexPath)) {
        $dataTime = (Get-Item -LiteralPath $DataPath).LastWriteTimeUtc
        $indexTime = (Get-Item -LiteralPath $IndexPath).LastWriteTimeUtc
        if ($dataTime -gt $indexTime.AddSeconds(2)) { $shouldRebuild = $true }
    }
    if (-not $shouldRebuild) { return }

    Write-Log -Level 'WARN' -Message "Activity index を data から再構築します。data=$DataPath index=$IndexPath"
    $dir = Split-Path -Parent $IndexPath
    Ensure-Directory -Path $dir
    $tmp = "$IndexPath.rebuild.$($script:RunId).tmp"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    if (Test-Path -LiteralPath $DataPath) {
        Get-Content -LiteralPath $DataPath -Encoding UTF8 -ReadCount 1000 | ForEach-Object {
            foreach ($line in $_) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $id = Get-ObjectIdFromJsonLine -Line $line
                if (-not [string]::IsNullOrWhiteSpace($id)) {
                    Append-Text -Path $tmp -Text ($id + [Environment]::NewLine)
                }
            }
        }
    }
    if (Test-Path -LiteralPath $IndexPath) { Remove-Item -LiteralPath $IndexPath -Force }
    if (Test-Path -LiteralPath $tmp) { Move-Item -LiteralPath $tmp -Destination $IndexPath -Force }
}

# 指定された index ファイルを読み込み、重複チェック用のハッシュテーブルとして返します。
# 同じ実行中はメモリにキャッシュし、毎回ファイルを読み直さないようにします。
function Get-IndexSet {
    param(
        [Parameter(Mandatory=$true)][string]$IndexPath,
        [Parameter(Mandatory=$false)][string]$DataPath,
        [Parameter(Mandatory=$false)][switch]$RebuildActivityIndex
    )
    if ($RebuildActivityIndex) {
        Rebuild-ActivityIndexIfNeeded -DataPath $DataPath -IndexPath $IndexPath
    }
    if ($script:IndexCache.ContainsKey($IndexPath)) {
        return $script:IndexCache[$IndexPath]
    }
    $set = @{}
    if (Test-Path -LiteralPath $IndexPath) {
        Get-Content -LiteralPath $IndexPath -Encoding UTF8 -ReadCount 1000 | ForEach-Object {
            foreach ($line in $_) {
                $key = [string]$line
                if (-not [string]::IsNullOrWhiteSpace($key)) { $set[$key] = $true }
            }
        }
    }
    $script:IndexCache[$IndexPath] = $set
    return $set
}

# JSONL に 1 レコードを保存します。UniqueKey が index に存在する場合は重複として保存しません。
# 重要: data への保存 → index への保存の順で行います。checkpoint はこの後でしか更新しません。
function Append-JsonLineDedup {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][datetime]$DateUtc,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [Parameter(Mandatory=$true)][string]$UniqueKey,
        [Parameter(Mandatory=$true)][string]$RawJsonLine,
        [Parameter(Mandatory=$false)][switch]$RebuildActivityIndex
    )
    if ([string]::IsNullOrWhiteSpace($UniqueKey)) {
        throw "UniqueKey が空のため保存できません。category=$Category prefix=$Prefix"
    }
    $paths = Get-PartitionPaths -Category $Category -DateUtc $DateUtc -Prefix $Prefix
    $set = Get-IndexSet -IndexPath $paths.index_path -DataPath $paths.data_path -RebuildActivityIndex:$RebuildActivityIndex
    if ($set.ContainsKey($UniqueKey)) {
        return $false
    }

    $line = Convert-ToJsonLine -Raw $RawJsonLine
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "保存対象 JSON line が空です。category=$Category key=$UniqueKey"
    }

    # 重要: 保存順序は data → index です。
    # checkpoint はこの関数の呼び出し元で、data と index の両方が成功した後にだけ更新します。
    # これにより、保存前に checkpoint だけ進んでログが欠落する事故を防ぎます。
    Append-Text -Path $paths.data_path -Text ($line + [Environment]::NewLine)
    Append-Text -Path $paths.index_path -Text ($UniqueKey + [Environment]::NewLine)
    $set[$UniqueKey] = $true
    return $true
}

# chat version や artifact version など「処理済み」と判断するための complete index ファイルパスを返します。
function Get-CompleteIndexPath {
    param([Parameter(Mandatory=$true)][string]$Name)
    return (Join-Path (Join-Path (Join-Path $Root 'data\index') 'complete') ("$Name.idx"))
}

# complete index を読み込みます。処理済みの chat / artifact / project document を再処理しないために使います。
function Get-CompleteSet {
    param([Parameter(Mandatory=$true)][string]$Name)
    $path = Get-CompleteIndexPath -Name $Name
    if ($script:CompleteIndexCache.ContainsKey($path)) { return $script:CompleteIndexCache[$path] }
    $set = @{}
    if (Test-Path -LiteralPath $path) {
        Get-Content -LiteralPath $path -Encoding UTF8 -ReadCount 1000 | ForEach-Object {
            foreach ($line in $_) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { $set[[string]$line] = $true }
            }
        }
    }
    $script:CompleteIndexCache[$path] = $set
    return $set
}

# 指定したキーが処理済みかどうかを確認します。true の場合は同じ content の再取得をスキップできます。
function Test-CompleteKey {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Key
    )
    $set = Get-CompleteSet -Name $Name
    return $set.ContainsKey($Key)
}

# 指定したキーを処理済みとして complete index に記録します。
# 404 で取得不可だった場合も、証跡を保存したうえで処理済みにして繰り返し取得を避けます。
function Mark-CompleteKey {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Key
    )
    $set = Get-CompleteSet -Name $Name
    if ($set.ContainsKey($Key)) { return }
    $path = Get-CompleteIndexPath -Name $Name
    Append-Text -Path $path -Text ($Key + [Environment]::NewLine)
    $set[$Key] = $true
}

# -----------------------------
# 多重起動防止
# -----------------------------
# Windows Mutex と lock ファイルの二重構成で、タスクスケジューラから重複起動されても同時実行しないようにします。
# 多重起動を防ぐため、Windows Mutex を即時取得します。取得できなければ別プロセス実行中として終了します。
# あわせて lock ファイルに PID / run_id / mode を書き、運用者が実行中プロセスを確認できるようにします。
function Acquire-CollectorLock {
    $mutexName = 'Global\ClaudeComplianceCollector'
    try {
        $script:Mutex = New-Object System.Threading.Mutex($false, $mutexName)
    }
    catch {
        $mutexName = 'Local\ClaudeComplianceCollector'
        $script:Mutex = New-Object System.Threading.Mutex($false, $mutexName)
    }
    # WaitOne(0) は待たずに即時取得を試します。
    # 取得できない場合は、すでに別の実行が動いていると判断します。
    $script:MutexAcquired = $script:Mutex.WaitOne(0)
    if (-not $script:MutexAcquired) {
        Write-Log -Level 'WARN' -Message "別の ClaudeComplianceCollector が実行中です。多重起動を防止して終了します。mutex=$mutexName"
        exit 2
    }

    $lockPath = Join-Path (Join-Path $Root 'locks') 'collector.lock'
    $lock = [ordered]@{
        run_id = $script:RunId
        pid = $PID
        mode = $Mode
        start_utc = $script:RunStartUtc.ToString('o')
        mutex = $mutexName
    }
    Write-TextFileAtomic -Path $lockPath -Content ($lock | ConvertTo-Json -Depth 10)
}

# 終了時に lock ファイルを削除し、Mutex を解放します。
# finally ブロックから呼ぶことで、正常終了・異常終了のどちらでも後片付けします。
function Release-CollectorLock {
    $lockPath = Join-Path (Join-Path $Root 'locks') 'collector.lock'
    try {
        if (Test-Path -LiteralPath $lockPath) { Remove-Item -LiteralPath $lockPath -Force }
    } catch { }
    try {
        if ($script:MutexAcquired -and $null -ne $script:Mutex) { $script:Mutex.ReleaseMutex() | Out-Null }
    } catch { }
    try {
        if ($null -ne $script:Mutex) { $script:Mutex.Dispose() }
    } catch { }
}

# -----------------------------
# HTTP / API 呼び出しの共通関数
# -----------------------------
# API キー付与、URL 組み立て、リトライ、429 待機、request-id 記録をここで扱います。
# 古い Windows PowerShell 環境でも TLS 1.2 を使えるように設定します。
# 設定できない環境では例外を握りつぶし、既定の通信設定に任せます。
function Initialize-Tls {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch { }
}

# API キーを Process → User → Machine の順に環境変数から探します。
# キー値はログに出さず、メモリ上の $script:ApiKey にだけ保持します。
function Get-EnvVarValue {
    param([Parameter(Mandatory=$true)][string]$Name)
    foreach ($scope in @('Process','User','Machine')) {
        $value = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $null
}

# URL クエリ文字列に入れる値を安全にエスケープします。before_id / after_id / limit などに使います。
function Escape-QueryValue {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Uri]::EscapeDataString($Value)
}

# chat_id や project_id など、URL パスの一部に入る値を安全にエスケープします。
function Escape-PathSegment {
    param([Parameter(Mandatory=$true)][string]$Value)
    return [System.Uri]::EscapeDataString($Value)
}

# API のパスとクエリパラメータから完全な URL を組み立てます。
# null や空のクエリ値は送らないため、不要なパラメータ混入を防ぎます。
function New-ClaudeUrl {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$false)]$QueryPairs
    )
    $url = $script:ApiBase.TrimEnd('/') + $Path
    $parts = New-Object System.Collections.Generic.List[string]
    if ($null -ne $QueryPairs) {
        foreach ($pair in $QueryPairs) {
            if ($null -eq $pair) { continue }
            $name = [string]$pair.Name
            $value = $pair.Value
            if ([string]::IsNullOrWhiteSpace($name) -or $null -eq $value) { continue }
            $parts.Add((Escape-QueryValue $name) + '=' + (Escape-QueryValue ([string]$value)))
        }
    }
    if ($parts.Count -gt 0) {
        $url = $url + '?' + ([string]::Join('&', $parts.ToArray()))
    }
    return $url
}

# レスポンスヘッダーから指定名の値を大文字小文字を区別せず取り出します。
# request-id、retry-after、rate-limit 系ヘッダーの取得に使います。
function Get-HeaderValue {
    param(
        [Parameter(Mandatory=$false)]$Headers,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if ($null -eq $Headers) { return $null }
    try {
        foreach ($key in $Headers.AllKeys) {
            if ($key -ieq $Name) { return [string]$Headers[$key] }
        }
    } catch { }
    try {
        foreach ($key in $Headers.Keys) {
            if ([string]$key -ieq $Name) { return [string]$Headers[$key] }
        }
    } catch { }
    return $null
}

# HTTP レスポンス本文を UTF-8 文字列として読み込みます。成功時もエラー時も body を記録できるようにします。
function Read-ResponseBody {
    param([Parameter(Mandatory=$true)]$Response)
    $stream = $Response.GetResponseStream()
    if ($null -eq $stream) { return '' }
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

# 低レベルの GET リクエストを実行します。
# ここではリトライ判断をせず、status code、headers、body、通信エラー情報を上位関数へ返します。
function Invoke-HttpGetRaw {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Accept
    )
    $request = [System.Net.WebRequest]::Create($Url)
    $request.Method = 'GET'
    $request.Timeout = $TimeoutSec * 1000
    $request.ReadWriteTimeout = $TimeoutSec * 1000
    # API キーはヘッダーにだけ設定します。ログには出力しません。
    $request.Headers.Add('x-api-key', $script:ApiKey)
    $request.Headers.Add('User-Agent', 'ClaudeComplianceCollector-PowerShell/1.0')
    try { $request.Accept = $Accept } catch { }

    try {
        $response = $request.GetResponse()
        try {
            $statusCode = [int]$response.StatusCode
            $body = Read-ResponseBody -Response $response
            return [pscustomobject]@{
                StatusCode = $statusCode
                Headers    = $response.Headers
                Body       = $body
                Error      = $null
            }
        }
        finally { $response.Close() }
    }
    catch [System.Net.WebException] {
        $webEx = $_.Exception
        if ($null -ne $webEx.Response) {
            $response = $webEx.Response
            try {
                $statusCode = [int]$response.StatusCode
                $body = Read-ResponseBody -Response $response
                return [pscustomobject]@{
                    StatusCode = $statusCode
                    Headers    = $response.Headers
                    Body       = $body
                    Error      = $webEx.Message
                }
            }
            finally { $response.Close() }
        }
        return [pscustomobject]@{
            StatusCode = $null
            Headers    = $null
            Body       = ''
            Error      = $webEx.Message
        }
    }
}

# 前回 API 呼び出しから MinDelayMs 以上あくように待機します。
# 大量ログ取得時に自分自身でレート制限に近づきすぎないための基本スロットリングです。
function Sleep-BeforeRequestIfNeeded {
    if ($MinDelayMs -le 0) { return }
    if ($script:LastRequestUtc -eq [DateTime]::MinValue) { return }
    $elapsed = ((Get-Date).ToUniversalTime() - $script:LastRequestUtc).TotalMilliseconds
    $remaining = $MinDelayMs - [int]$elapsed
    if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
}

# レスポンスヘッダーの残りリクエスト数が少ない場合、リセット時刻まで待機します。
# 429 エラーになる前に処理を減速させる予防的な制御です。
function Sleep-ForRateLimitHeaders {
    param([Parameter(Mandatory=$false)]$Headers)
    $remainingRaw = Get-HeaderValue -Headers $Headers -Name 'anthropic-ratelimit-requests-remaining'
    $resetRaw = Get-HeaderValue -Headers $Headers -Name 'anthropic-ratelimit-requests-reset'
    if ([string]::IsNullOrWhiteSpace($remainingRaw) -or [string]::IsNullOrWhiteSpace($resetRaw)) { return }
    $remaining = 0
    if (-not [int]::TryParse($remainingRaw, [ref]$remaining)) { return }
    if ($remaining -gt $ThrottleWhenRemainingBelow) { return }
    try {
        $resetUtc = ([DateTimeOffset]::Parse($resetRaw, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).UtcDateTime
        $sleepSec = [Math]::Ceiling(($resetUtc - (Get-Date).ToUniversalTime()).TotalSeconds) + 1
        if ($sleepSec -gt 0) {
            Write-Log -Level 'WARN' -Message "Rate-limit 残数が少ないためリセットまで待機します。remaining=$remaining reset=$resetRaw sleep=${sleepSec}s"
            Start-Sleep -Seconds $sleepSec
        }
    } catch { }
}

# Claude Compliance API を GET で呼び出す中心関数です。
# 429 は retry-after に従い、5xx / 529 / timeout は同じ checkpoint でリトライします。
# 401 / 403 はキー不正または権限不足として即時停止し、checkpoint を進めません。
function Invoke-ClaudeGet {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$false)]$QueryPairs,
        [Parameter(Mandatory=$false)][string]$Accept = 'application/json',
        [Parameter(Mandatory=$false)][switch]$AllowNotFound
    )
    $url = New-ClaudeUrl -Path $Path -QueryPairs $QueryPairs
    $attempt = 0
    while ($true) {
        # リトライ時も同じ URL を使います。checkpoint は進めず、同じ位置からやり直します。
        Sleep-BeforeRequestIfNeeded
        $script:LastRequestUtc = (Get-Date).ToUniversalTime()
        $resp = Invoke-HttpGetRaw -Url $url -Accept $Accept
        $script:Stats.api_requests++

        $requestId = Get-HeaderValue -Headers $resp.Headers -Name 'request-id'
        if (-not [string]::IsNullOrWhiteSpace($requestId)) {
            $script:Stats.last_request_id = $requestId
            if ($script:Stats.request_ids.Count -lt 2000) {
                $script:Stats.request_ids += $requestId
            }
        }
        $rateRemaining = Get-HeaderValue -Headers $resp.Headers -Name 'anthropic-ratelimit-requests-remaining'
        $rateReset = Get-HeaderValue -Headers $resp.Headers -Name 'anthropic-ratelimit-requests-reset'
        $retryAfter = Get-HeaderValue -Headers $resp.Headers -Name 'retry-after'
        Write-RequestLog -Record @{
            timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
            run_id = $script:RunId
            endpoint = $Path
            status_code = $resp.StatusCode
            request_id = $requestId
            rate_remaining = $rateRemaining
            rate_reset = $rateReset
            retry_after = $retryAfter
            attempt = $attempt
        }

        # 2xx は成功です。rate-limit 残数が少ない場合だけ追加で待機してから呼び出し元へ返します。
        if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
            Sleep-ForRateLimitHeaders -Headers $resp.Headers
            return [pscustomobject]@{
                StatusCode = $resp.StatusCode
                Headers    = $resp.Headers
                Body       = $resp.Body
                RequestId  = $requestId
            }
        }

        # content 系では、削除済み・保持期間切れなどで 404 になることがあります。
        # AllowNotFound 指定時はエラーにせず、呼び出し元で content_missing として記録します。
        if ($AllowNotFound -and $resp.StatusCode -eq 404) {
            $script:Stats.content_not_found++
            return [pscustomobject]@{
                StatusCode = $resp.StatusCode
                Headers    = $resp.Headers
                Body       = $resp.Body
                RequestId  = $requestId
            }
        }

        # 401 / 403 は一時的な問題ではなく、API キー不正またはスコープ不足の可能性が高いため即時停止します。
        if ($resp.StatusCode -eq 401 -or $resp.StatusCode -eq 403) {
            throw "HTTP $($resp.StatusCode): APIキー不正または権限不足です。checkpoint は更新しません。request-id=$requestId body=$($resp.Body)"
        }

        # 429 はレート制限です。retry-after ヘッダーがあれば必ず尊重します。
        if ($resp.StatusCode -eq 429) {
            $script:Stats.rate_limit_429_count++
            $sleepSeconds = 0
            if (-not [string]::IsNullOrWhiteSpace($retryAfter)) {
                [int]::TryParse($retryAfter, [ref]$sleepSeconds) | Out-Null
            }
            if ($sleepSeconds -le 0) {
                $sleepSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt))
            }
            Write-Log -Level 'WARN' -Message "HTTP 429。retry-after に従って同じ checkpoint で再試行します。sleep=${sleepSeconds}s request-id=$requestId"
            Start-Sleep -Seconds $sleepSeconds
        }
        elseif ($resp.StatusCode -eq $null -or $resp.StatusCode -eq 502 -or $resp.StatusCode -eq 503 -or $resp.StatusCode -eq 504 -or $resp.StatusCode -eq 529) {
            $sleepSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt))
            Write-Log -Level 'WARN' -Message "一時的な通信/APIエラー。HTTP=$($resp.StatusCode) sleep=${sleepSeconds}s request-id=$requestId error=$($resp.Error)"
            Start-Sleep -Seconds $sleepSeconds
        }
        elseif ($resp.StatusCode -eq 500) {
            $shouldRetry = Get-HeaderValue -Headers $resp.Headers -Name 'x-should-retry'
            if ($shouldRetry -ieq 'false') {
                throw "HTTP 500 かつ x-should-retry=false。checkpoint は更新しません。request-id=$requestId body=$($resp.Body)"
            }
            $sleepSeconds = [Math]::Min(60, [Math]::Pow(2, $attempt))
            Write-Log -Level 'WARN' -Message "HTTP 500。x-should-retry=false ではないため同じ checkpoint で再試行します。sleep=${sleepSeconds}s request-id=$requestId"
            Start-Sleep -Seconds $sleepSeconds
        }
        else {
            throw "HTTP $($resp.StatusCode): 再試行対象外の API エラーです。checkpoint は更新しません。request-id=$requestId body=$($resp.Body)"
        }

        $attempt++
        $script:Stats.retry_count++
        if ($attempt -gt $MaxRetries) {
            throw "最大リトライ回数を超過しました。checkpoint は更新しません。endpoint=$Path last_status=$($resp.StatusCode) request-id=$requestId"
        }
    }
}

# -----------------------------
# JSON 処理の共通関数
# -----------------------------
# raw JSON をできるだけ加工せず保存するため、配列内の各オブジェクトを文字列として切り出す処理を含みます。
# レスポンス JSON の data 配列から、各オブジェクトの raw JSON 文字列を切り出します。
# ConvertFrom-Json で再シリアライズすると順序や表現が変わる可能性があるため、監査用 raw 保存ではこの関数を使います。
function Get-RawJsonArrayItems {
    param(
        [Parameter(Mandatory=$true)][string]$Json,
        [Parameter(Mandatory=$false)][string]$PropertyName = 'data'
    )
    $pattern = '"' + [Regex]::Escape($PropertyName) + '"\s*:\s*\['
    $match = [Regex]::Match($Json, $pattern)
    if (-not $match.Success) {
        throw "JSON response 内に配列プロパティ '$PropertyName' が見つかりません。"
    }

    $items = New-Object System.Collections.Generic.List[string]
    $i = $match.Index + $match.Length
    $depth = 0
    $itemStart = -1
    $inString = $false
    $escape = $false

    while ($i -lt $Json.Length) {
        $ch = $Json[$i]
        if ($inString) {
            if ($escape) { $escape = $false }
            elseif ($ch -eq '\') { $escape = $true }
            elseif ($ch -eq '"') { $inString = $false }
            $i++
            continue
        }

        if ($ch -eq '"') { $inString = $true; $i++; continue }
        if ($ch -eq '{') {
            if ($depth -eq 0) { $itemStart = $i }
            $depth++
        }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0 -and $itemStart -ge 0) {
                $items.Add($Json.Substring($itemStart, $i - $itemStart + 1))
                $itemStart = -1
            }
            elseif ($depth -lt 0) {
                throw "JSON array extraction failed: object depth became negative."
            }
        }
        elseif ($ch -eq ']' -and $depth -eq 0) {
            break
        }
        $i++
    }
    return $items
}

# 404 で content を取得できなかった場合の証跡レコードを作ります。
# 削除済みや保持期間切れの可能性を後から確認できるようにします。
function New-ContentMissingRecordJson {
    param(
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceId,
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [Parameter(Mandatory=$false)][string]$RequestId,
        [Parameter(Mandatory=$false)][string]$Body
    )
    $record = [ordered]@{
        resource_type = $ResourceType
        resource_id = $ResourceId
        endpoint = $Endpoint
        retrieved_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        status_code = 404
        request_id = $RequestId
        response_body = $Body
    }
    return ($record | ConvertTo-Json -Depth 20 -Compress)
}

# 取得できなかった content の証跡を content_missing JSONL に保存します。
# 同じ 404 を何度も保存しないよう、resource type / id / response body hash で重複排除します。
function Save-ContentMissingRecord {
    param(
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceId,
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [Parameter(Mandatory=$false)][string]$RequestId,
        [Parameter(Mandatory=$false)][string]$Body
    )
    $date = (Get-Date).ToUniversalTime()
    $json = New-ContentMissingRecordJson -ResourceType $ResourceType -ResourceId $ResourceId -Endpoint $Endpoint -RequestId $RequestId -Body $Body
    $key = "$ResourceType|$ResourceId|404|" + (Get-Sha256Hex $Body)
    [void](Append-JsonLineDedup -Category 'content_missing' -DateUtc $date -Prefix 'content_missing' -UniqueKey $key -RawJsonLine $json)
}

# -----------------------------
# Activity Feed 取得処理
# -----------------------------
# 監査ログの中心です。first_id / last_id を checkpoint として保存し、Backfill と Tail で使い分けます。
# Activity Feed の 1 ページ分のレスポンスから Activity オブジェクトを raw JSONL 保存します。
# activity.id がない場合は信頼できる重複排除ができないため、checkpoint を進めず停止します。
function Save-ActivityItemsFromResponse {
    param([Parameter(Mandatory=$true)][string]$RawBody)
    $rawItems = Get-RawJsonArrayItems -Json $RawBody -PropertyName 'data'
    $saved = 0
    $duplicate = 0
    foreach ($raw in $rawItems) {
        $obj = $raw | ConvertFrom-Json
        $id = [string]$obj.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw "Activity object に id がありません。checkpoint は更新しません。"
        }
        $date = Get-DateFromRfc3339OrNow -Value ([string]$obj.created_at)
        $ok = Append-JsonLineDedup -Category 'activities' -DateUtc $date -Prefix 'activities' -UniqueKey $id -RawJsonLine $raw -RebuildActivityIndex
        if ($ok) { $saved++ } else { $duplicate++ }
    }
    $script:Stats.activity_fetched += $rawItems.Count
    $script:Stats.activity_saved += $saved
    $script:Stats.activity_duplicate += $duplicate
    return [pscustomobject]@{ fetched = $rawItems.Count; saved = $saved; duplicate = $duplicate }
}

# Activity Feed を Backfill または Tail の方向で取得します。
# Backfill は last_id → after_id で過去方向、Tail は first_id → before_id で新しいログ方向に進みます。
function Collect-Activities {
    param([Parameter(Mandatory=$true)][ValidateSet('Backfill','Tail')][string]$Direction)

    $state = Load-State
    $script:Stats.start_checkpoint = [ordered]@{
        activity_first_id = $state.activity_first_id
        activity_last_id = $state.activity_last_id
        activity_backfill_complete = $state.activity_backfill_complete
    }

    if ($Direction -eq 'Tail' -and [string]::IsNullOrWhiteSpace([string]$state.activity_first_id)) {
        throw "ActivityTail には activity_first_id checkpoint が必要です。先に ActivityBackfill を実行してください。"
    }

    $cursor = $null
    # Backfill は、これまで取得した最古側の last_id からさらに過去へ進みます。
    # Tail は、これまで取得した最新側の first_id より新しいログを取りに行きます。
    if ($Direction -eq 'Backfill') { $cursor = [string]$state.activity_last_id } else { $cursor = [string]$state.activity_first_id }
    $newTailFirstId = [string]$state.activity_first_id
    $pageNo = 0

    Write-Log -Level 'INFO' -Message "Activity $Direction 開始。cursor=$cursor limit=$ActivityLimit"

    while ($true) {
        $pageNo++
        $query = @(@{ Name='limit'; Value=$ActivityLimit })
        if (-not [string]::IsNullOrWhiteSpace($cursor)) {
            if ($Direction -eq 'Backfill') { $query += @{ Name='after_id'; Value=$cursor } }
            else { $query += @{ Name='before_id'; Value=$cursor } }
        }

        # API から 1 ページ分を取得します。
        $resp = Invoke-ClaudeGet -Path '/v1/compliance/activities' -QueryPairs $query
        $json = $resp.Body | ConvertFrom-Json
        # checkpoint を更新する前に、必ず raw Activity を保存します。
        $result = Save-ActivityItemsFromResponse -RawBody $resp.Body
        Write-Log -Level 'INFO' -Message "Activity page saved. direction=$Direction page=$pageNo fetched=$($result.fetched) saved=$($result.saved) duplicate=$($result.duplicate) has_more=$($json.has_more) first_id=$($json.first_id) last_id=$($json.last_id) request-id=$($resp.RequestId)"

        if ($Direction -eq 'Backfill') {
            if ([string]::IsNullOrWhiteSpace([string]$state.activity_first_id) -and -not [string]::IsNullOrWhiteSpace([string]$json.first_id)) {
                $state.activity_first_id = [string]$json.first_id
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$json.last_id)) {
                $state.activity_last_id = [string]$json.last_id
                $cursor = [string]$json.last_id
            }
            if (-not [bool]$json.has_more) {
                $state.activity_backfill_complete = $true
            }
            # Backfill では、このページの保存が完了した後なので last_id checkpoint を進めて安全です。
            Save-State -State $state
            if (-not [bool]$json.has_more) { break }
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace([string]$json.first_id)) {
                $newTailFirstId = [string]$json.first_id
                $cursor = [string]$json.first_id
            }
            # Tail では、途中ページで first_id を保存すると、まだ取得していない新しいページを飛ばす可能性があります。
            # そのため has_more=false、つまり新しいログ方向を取り切った後にだけ first_id checkpoint を保存します。
            if (-not [bool]$json.has_more) {
                $state.activity_first_id = $newTailFirstId
                Save-State -State $state
                break
            }
        }
    }

    $state = Load-State
    $script:Stats.end_checkpoint = [ordered]@{
        activity_first_id = $state.activity_first_id
        activity_last_id = $state.activity_last_id
        activity_backfill_complete = $state.activity_backfill_complete
    }
    Write-Log -Level 'INFO' -Message "Activity $Direction 完了。first_id=$($state.activity_first_id) last_id=$($state.activity_last_id) backfill_complete=$($state.activity_backfill_complete)"
}

# -----------------------------
# Chat / Message / Artifact 取得処理
# -----------------------------
# chat metadata と message ページを保存します。message に紐づく artifact version のテキストも必要に応じて取得します。
# PowerShell オブジェクトのプロパティ名一覧を返します。
# 将来 API のフィールドが増減しても、存在確認してからアクセスするために使います。
function Get-JsonPropertyNames {
    param([Parameter(Mandatory=$true)]$Object)
    return @($Object.PSObject.Properties.Name)
}

# テキスト本文を raw body として保存するためのラッパーレコードを作ります。
# endpoint、request-id、content type、SHA-256 も一緒に保存し、後から取得証跡を確認できるようにします。
function Save-TextContentWrapper {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][datetime]$DateUtc,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [Parameter(Mandatory=$true)][string]$UniqueKey,
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceId,
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [Parameter(Mandatory=$false)][string]$RequestId,
        [Parameter(Mandatory=$false)][string]$ContentType,
        [Parameter(Mandatory=$true)][string]$Body
    )
    $record = [ordered]@{
        resource_type = $ResourceType
        resource_id = $ResourceId
        endpoint = $Endpoint
        retrieved_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        request_id = $RequestId
        content_type = $ContentType
        content_sha256 = Get-Sha256Hex $Body
        content = $Body
    }
    $json = $record | ConvertTo-Json -Depth 30 -Compress
    return (Append-JsonLineDedup -Category $Category -DateUtc $DateUtc -Prefix $Prefix -UniqueKey $UniqueKey -RawJsonLine $json)
}

# chat message に含まれる artifact version のテキスト本文を取得します。
# SkipArtifactText 指定時や処理済み version はスキップし、404 は content_missing に記録します。
function Collect-ArtifactText {
    param(
        [Parameter(Mandatory=$true)][string]$ArtifactVersionId,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    if ($SkipArtifactText) { return }
    if ([string]::IsNullOrWhiteSpace($ArtifactVersionId)) { return }
    if (Test-CompleteKey -Name 'artifact_versions' -Key $ArtifactVersionId) { return }

    $idEsc = Escape-PathSegment -Value $ArtifactVersionId
    $path = "/v1/compliance/apps/artifacts/$idEsc/content"
    $resp = Invoke-ClaudeGet -Path $path -Accept 'text/plain,application/json' -AllowNotFound
    if ($resp.StatusCode -eq 404) {
        Save-ContentMissingRecord -ResourceType 'artifact_version' -ResourceId $ArtifactVersionId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
        Mark-CompleteKey -Name 'artifact_versions' -Key $ArtifactVersionId
        return
    }

    $hash = Get-Sha256Hex $resp.Body
    $key = "$ArtifactVersionId|$hash"
    $contentType = Get-HeaderValue -Headers $resp.Headers -Name 'Content-Type'
    $ok = Save-TextContentWrapper -Category 'artifacts' -DateUtc $DateUtc -Prefix 'artifacts' -UniqueKey $key -ResourceType 'artifact_version' -ResourceId $ArtifactVersionId -Endpoint $path -RequestId $resp.RequestId -ContentType $contentType -Body $resp.Body
    if ($ok) { $script:Stats.artifact_text_saved++ }
    Mark-CompleteKey -Name 'artifact_versions' -Key $ArtifactVersionId
}

# chat messages の 1 ページを調べ、含まれている artifact version_id を見つけて本文取得へ渡します。
# artifacts プロパティがないメッセージでもエラーにせず、そのまま処理を続けます。
function Collect-ArtifactsFromChatMessagePage {
    param(
        [Parameter(Mandatory=$true)]$ChatMessagePage,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    if ($SkipArtifactText) { return }
    if (-not (Get-JsonPropertyNames -Object $ChatMessagePage | Where-Object { $_ -eq 'chat_messages' })) { return }
    foreach ($msg in @($ChatMessagePage.chat_messages)) {
        if ($null -eq $msg) { continue }
        if (-not (Get-JsonPropertyNames -Object $msg | Where-Object { $_ -eq 'artifacts' })) { continue }
        if ($null -eq $msg.artifacts) { continue }
        foreach ($artifact in @($msg.artifacts)) {
            if ($null -eq $artifact) { continue }
            $versionId = $null
            if (Get-JsonPropertyNames -Object $artifact | Where-Object { $_ -eq 'version_id' }) { $versionId = [string]$artifact.version_id }
            if (-not [string]::IsNullOrWhiteSpace($versionId)) {
                Collect-ArtifactText -ArtifactVersionId $versionId -DateUtc $DateUtc
            }
        }
    }
}

# 指定された chat の message ページを order=asc で順に取得し、ページ単位で JSONL 保存します。
# message ページ保存後に artifact text も取得します。chat が 404 の場合は証跡だけ残して続行します。
function Collect-ChatMessages {
    param(
        [Parameter(Mandatory=$true)][string]$ChatId,
        [Parameter(Mandatory=$false)][string]$ChatUpdatedAt,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    $chatEsc = Escape-PathSegment -Value $ChatId
    $path = "/v1/compliance/apps/chats/$chatEsc/messages"
    $cursor = $null
    $pageNo = 0
    while ($true) {
        $pageNo++
        $query = @(
            @{ Name='limit'; Value=$ChatMessagesLimit },
            @{ Name='order'; Value='asc' }
        )
        if (-not [string]::IsNullOrWhiteSpace($cursor)) { $query += @{ Name='after_id'; Value=$cursor } }
        $resp = Invoke-ClaudeGet -Path $path -QueryPairs $query -AllowNotFound
        if ($resp.StatusCode -eq 404) {
            Save-ContentMissingRecord -ResourceType 'chat' -ResourceId $ChatId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
            return
        }
        $json = $resp.Body | ConvertFrom-Json
        $first = [string]$json.first_id
        $last = [string]$json.last_id
        $key = "$ChatId|$ChatUpdatedAt|$pageNo|$first|$last"
        $ok = Append-JsonLineDedup -Category 'chat_messages' -DateUtc $DateUtc -Prefix 'chat_messages' -UniqueKey $key -RawJsonLine $resp.Body
        if ($ok) { $script:Stats.chat_message_pages_saved++ }

        Collect-ArtifactsFromChatMessagePage -ChatMessagePage $json -DateUtc $DateUtc

        Write-Log -Level 'INFO' -Message "Chat messages page saved. chat_id=$ChatId page=$pageNo has_more=$($json.has_more) first_id=$first last_id=$last request-id=$($resp.RequestId)"
        if (-not [string]::IsNullOrWhiteSpace($last)) { $cursor = $last }
        if (-not [bool]$json.has_more) { break }
    }
}

# chat 一覧を updated_at 順で取得し、各 chat の metadata と messages を保存します。
# chat_last_id checkpoint は、そのページの chat と message 処理が終わった後にだけ更新します。
function Collect-Chats {
    $state = Load-State
    $script:Stats.start_checkpoint = [ordered]@{
        chat_last_id = $state.chat_last_id
        chat_backfill_complete = $state.chat_backfill_complete
    }

    $cursor = [string]$state.chat_last_id
    $pageNo = 0
    Write-Log -Level 'INFO' -Message "Chat content collection 開始。cursor=$cursor limit=$ChatListLimit"

    while ($true) {
        $pageNo++
        $query = @(
            @{ Name='order_by'; Value='updated_at' },
            @{ Name='limit'; Value=$ChatListLimit }
        )
        if (-not [string]::IsNullOrWhiteSpace($cursor)) { $query += @{ Name='after_id'; Value=$cursor } }
        $resp = Invoke-ClaudeGet -Path '/v1/compliance/apps/chats' -QueryPairs $query
        $json = $resp.Body | ConvertFrom-Json
        $rawChats = Get-RawJsonArrayItems -Json $resp.Body -PropertyName 'data'

        foreach ($rawChat in $rawChats) {
            $chat = $rawChat | ConvertFrom-Json
            $chatId = [string]$chat.id
            if ([string]::IsNullOrWhiteSpace($chatId)) { throw "Chat metadata に id がありません。checkpoint は更新しません。" }
            $updatedAt = [string]$chat.updated_at
            $createdAt = [string]$chat.created_at
            $date = Get-DateFromRfc3339OrNow -Value $(if (-not [string]::IsNullOrWhiteSpace($updatedAt)) { $updatedAt } else { $createdAt })
            $versionKey = "$chatId|$updatedAt"
            $script:Stats.chat_list_items++
            $ok = Append-JsonLineDedup -Category 'chats' -DateUtc $date -Prefix 'chats' -UniqueKey $versionKey -RawJsonLine $rawChat
            if ($ok) { $script:Stats.chat_metadata_saved++ }

            # 同じ chat の同じ updated_at version を処理済みなら、messages の再取得を省略します。
            if (Test-CompleteKey -Name 'chat_versions' -Key $versionKey) {
                continue
            }
            Collect-ChatMessages -ChatId $chatId -ChatUpdatedAt $updatedAt -DateUtc $date
            # metadata と message の保存が終わってから処理済みにします。
            Mark-CompleteKey -Name 'chat_versions' -Key $versionKey
        }

        Write-Log -Level 'INFO' -Message "Chat list page processed. page=$pageNo items=$($rawChats.Count) has_more=$($json.has_more) last_id=$($json.last_id) request-id=$($resp.RequestId)"

        if (-not [string]::IsNullOrWhiteSpace([string]$json.last_id)) {
            # このページ内の chat metadata と message ページをすべて保存済み、または取得不可として記録済みです。
            # ここまで終わってから chat_last_id checkpoint を進めます。
            $state.chat_last_id = [string]$json.last_id
            $cursor = [string]$json.last_id
            Save-State -State $state
        }
        if (-not [bool]$json.has_more) {
            $state.chat_backfill_complete = $true
            Save-State -State $state
            break
        }
    }

    $state = Load-State
    $script:Stats.end_checkpoint = [ordered]@{
        chat_last_id = $state.chat_last_id
        chat_backfill_complete = $state.chat_backfill_complete
    }
    Write-Log -Level 'INFO' -Message "Chat content collection 完了。chat_last_id=$($state.chat_last_id) chat_backfill_complete=$($state.chat_backfill_complete)"
}

# -----------------------------
# Project / Project attachment 取得処理
# -----------------------------
# project metadata、project details、project_doc 本文を保存します。project_file のバイナリ本文は取得しません。
# project_doc attachment のテキスト本文を取得して保存します。
# project_file のバイナリ添付とは別扱いで、テキスト document のみ取得対象です。
function Collect-ProjectDocumentContent {
    param(
        [Parameter(Mandatory=$true)][string]$DocumentId,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    if ([string]::IsNullOrWhiteSpace($DocumentId)) { return }
    if (Test-CompleteKey -Name 'project_documents' -Key $DocumentId) { return }

    $docEsc = Escape-PathSegment -Value $DocumentId
    $path = "/v1/compliance/apps/projects/documents/$docEsc"
    $resp = Invoke-ClaudeGet -Path $path -Accept 'application/json,text/plain' -AllowNotFound
    if ($resp.StatusCode -eq 404) {
        Save-ContentMissingRecord -ResourceType 'project_document' -ResourceId $DocumentId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
        Mark-CompleteKey -Name 'project_documents' -Key $DocumentId
        return
    }

    $hash = Get-Sha256Hex $resp.Body
    $key = "$DocumentId|$hash"
    $contentType = Get-HeaderValue -Headers $resp.Headers -Name 'Content-Type'
    $ok = Save-TextContentWrapper -Category 'project_documents' -DateUtc $DateUtc -Prefix 'project_documents' -UniqueKey $key -ResourceType 'project_document' -ResourceId $DocumentId -Endpoint $path -RequestId $resp.RequestId -ContentType $contentType -Body $resp.Body
    if ($ok) { $script:Stats.project_documents_saved++ }
    Mark-CompleteKey -Name 'project_documents' -Key $DocumentId
}

# project の詳細情報を取得し、レスポンス本文のハッシュを含むキーで重複排除して保存します。
function Collect-ProjectDetails {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectId,
        [Parameter(Mandatory=$true)][datetime]$DateUtc
    )
    $projEsc = Escape-PathSegment -Value $ProjectId
    $path = "/v1/compliance/apps/projects/$projEsc"
    $resp = Invoke-ClaudeGet -Path $path -AllowNotFound
    if ($resp.StatusCode -eq 404) {
        Save-ContentMissingRecord -ResourceType 'project' -ResourceId $ProjectId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
        return
    }
    $hash = Get-Sha256Hex $resp.Body
    $key = "$ProjectId|$hash"
    $ok = Append-JsonLineDedup -Category 'project_details' -DateUtc $DateUtc -Prefix 'project_details' -UniqueKey $key -RawJsonLine $resp.Body
    if ($ok) { $script:Stats.project_records_saved++ }
}

# project に紐づく attachment 一覧を取得して raw metadata を保存します。
# type=project_doc は本文も取得し、type=project_file は容量抑制のため本文を取得しません。未知 type でも止めません。
function Collect-ProjectAttachments {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectId,
        [Parameter(Mandatory=$true)][datetime]$ProjectDateUtc
    )
    $projEsc = Escape-PathSegment -Value $ProjectId
    $path = "/v1/compliance/apps/projects/$projEsc/attachments"
    $pageToken = $null
    $pageNo = 0
    while ($true) {
        $pageNo++
        $query = @(@{ Name='limit'; Value=$ProjectAttachmentsLimit })
        if (-not [string]::IsNullOrWhiteSpace($pageToken)) { $query += @{ Name='page'; Value=$pageToken } }
        $resp = Invoke-ClaudeGet -Path $path -QueryPairs $query -AllowNotFound
        if ($resp.StatusCode -eq 404) {
            Save-ContentMissingRecord -ResourceType 'project_attachments' -ResourceId $ProjectId -Endpoint $path -RequestId $resp.RequestId -Body $resp.Body
            return
        }
        $json = $resp.Body | ConvertFrom-Json
        $rawItems = Get-RawJsonArrayItems -Json $resp.Body -PropertyName 'data'
        foreach ($raw in $rawItems) {
            $att = $raw | ConvertFrom-Json
            $attId = [string]$att.id
            $attType = [string]$att.type
            $createdAt = [string]$att.created_at
            $date = Get-DateFromRfc3339OrNow -Value $(if (-not [string]::IsNullOrWhiteSpace($createdAt)) { $createdAt } else { $ProjectDateUtc.ToString('o') })
            $script:Stats.project_attachments_seen++
            $key = "$ProjectId|$attId|$attType|$createdAt"
            [void](Append-JsonLineDedup -Category 'project_attachments' -DateUtc $date -Prefix 'project_attachments' -UniqueKey $key -RawJsonLine $raw)

            if ($attType -eq 'project_doc') {
                # project_doc はテキスト文書として eDiscovery 対象にするため本文を取得します。
                Collect-ProjectDocumentContent -DocumentId $attId -DateUtc $date
            }
            elseif ($attType -eq 'project_file') {
                # project_file は添付ファイルです。容量圧迫を避けるため、本文取得 endpoint は呼びません。
                # ただし、上で raw metadata は保存しているため、ファイルIDなどの証跡は残ります。
                $script:Stats.file_binaries_skipped++
            }
            else {
                # 将来追加される未知 type に備え、raw metadata は保存したうえで処理を継続します。
                Write-Log -Level 'WARN' -Message "未知の project attachment type です。raw metadata は保存済みのため処理を継続します。project_id=$ProjectId attachment_id=$attId type=$attType"
            }
        }
        Write-Log -Level 'INFO' -Message "Project attachments page processed. project_id=$ProjectId page=$pageNo items=$($rawItems.Count) has_more=$($json.has_more) request-id=$($resp.RequestId)"
        if (-not [bool]$json.has_more) { break }
        $pageToken = [string]$json.next_page
        if ([string]::IsNullOrWhiteSpace($pageToken)) { break }
    }
}

# project 一覧をフルスキャンし、各 project の詳細と attachments を取得します。
# SkipProjectFullScan が指定された場合は project 処理を丸ごとスキップします。
function Collect-Projects {
    if ($SkipProjectFullScan) {
        Write-Log -Level 'INFO' -Message 'SkipProjectFullScan が指定されたため project collection をスキップします。'
        return
    }

    Write-Log -Level 'INFO' -Message "Project full scan 開始。limit=$ProjectListLimit"
    $pageToken = $null
    $pageNo = 0
    while ($true) {
        $pageNo++
        $query = @(@{ Name='limit'; Value=$ProjectListLimit })
        if (-not [string]::IsNullOrWhiteSpace($pageToken)) { $query += @{ Name='page'; Value=$pageToken } }
        $resp = Invoke-ClaudeGet -Path '/v1/compliance/apps/projects' -QueryPairs $query
        $json = $resp.Body | ConvertFrom-Json
        $rawProjects = Get-RawJsonArrayItems -Json $resp.Body -PropertyName 'data'
        foreach ($rawProject in $rawProjects) {
            $project = $rawProject | ConvertFrom-Json
            $projectId = [string]$project.id
            if ([string]::IsNullOrWhiteSpace($projectId)) { throw "Project metadata に id がありません。" }
            $createdAt = $null
            if (Get-JsonPropertyNames -Object $project | Where-Object { $_ -eq 'created_at' }) { $createdAt = [string]$project.created_at }
            $date = Get-DateFromRfc3339OrNow -Value $createdAt
            $script:Stats.projects_seen++
            $key = "$projectId|$createdAt|" + (Get-Sha256Hex $rawProject)
            $ok = Append-JsonLineDedup -Category 'projects' -DateUtc $date -Prefix 'projects' -UniqueKey $key -RawJsonLine $rawProject
            if ($ok) { $script:Stats.project_records_saved++ }

            Collect-ProjectDetails -ProjectId $projectId -DateUtc $date
            Collect-ProjectAttachments -ProjectId $projectId -ProjectDateUtc $date
        }
        Write-Log -Level 'INFO' -Message "Project list page processed. page=$pageNo items=$($rawProjects.Count) has_more=$($json.has_more) request-id=$($resp.RequestId)"
        if (-not [bool]$json.has_more) { break }
        $pageToken = [string]$json.next_page
        if ([string]::IsNullOrWhiteSpace($pageToken)) { break }
    }
    $state = Load-State
    $state.project_last_full_scan_utc = (Get-Date).ToUniversalTime().ToString('o')
    Save-State -State $state
    Write-Log -Level 'INFO' -Message 'Project full scan 完了。'
}

# content 取得の入口です。chat 系を取得した後、project 系を取得します。
function Collect-Content {
    Collect-Chats
    Collect-Projects
}

# -----------------------------
# 実行結果・状態表示
# -----------------------------
# 成功/失敗の summary と最新状態ファイルを書き出し、監視や障害調査で参照できるようにします。
# 実行サマリーを summary_<RunId>.json と latest_status.json に保存します。
# 成功時だけ latest_success.json も更新し、監視側が最後の成功状態を見られるようにします。
function Write-StatusFiles {
    param([Parameter(Mandatory=$true)][string]$Status)
    $script:Stats.status = $Status
    $script:Stats.end_utc = (Get-Date).ToUniversalTime().ToString('o')
    $script:Stats.duration_seconds = [Math]::Round(((Get-Date).ToUniversalTime() - $script:RunStartUtc).TotalSeconds, 3)
    $json = $script:Stats | ConvertTo-Json -Depth 50
    $summaryPath = Join-Path (Join-Path $Root 'logs') ("summary_$($script:RunId).json")
    Write-TextFileAtomic -Path $summaryPath -Content $json
    $latestPath = Join-Path (Join-Path $Root 'state') 'latest_status.json'
    Write-TextFileAtomic -Path $latestPath -Content $json
    if ($Status -eq 'success') {
        $successPath = Join-Path (Join-Path $Root 'state') 'latest_success.json'
        Write-TextFileAtomic -Path $successPath -Content $json
    }
}

# Status モード用の表示処理です。API には接続せず、checkpoint と latest_status の内容だけを表示します。
function Show-Status {
    $checkpoint = Get-StatePath
    $latest = Join-Path (Join-Path $Root 'state') 'latest_status.json'
    Write-Host "Root: $Root"
    if (Test-Path -LiteralPath $checkpoint) {
        Write-Host "Checkpoint:"
        Get-Content -LiteralPath $checkpoint -Encoding UTF8 | Write-Host
    } else {
        Write-Host 'Checkpoint: not found'
    }
    if (Test-Path -LiteralPath $latest) {
        Write-Host "Latest status:"
        Get-Content -LiteralPath $latest -Encoding UTF8 | Write-Host
    } else {
        Write-Host 'Latest status: not found'
    }
}

# -----------------------------
# メイン処理
# -----------------------------
# 初期化 → 多重起動防止 → API キー読込 → 指定モード実行 → 成功/失敗状態保存、という順序で実行します。
try {
    # 最初に保存先・ログ先を作成します。以降の処理でログを必ず出せるようにするためです。
    Initialize-Folders
    if ($Mode -eq 'Status') {
        Show-Status
        exit 0
    }

    # API キー取得や API 呼び出しの前に多重起動を防ぎます。
    Acquire-CollectorLock
    Initialize-Tls

    # API キーは環境変数から読み込みます。キー値はログに出しません。
    $script:ApiKey = Get-EnvVarValue -Name $ApiKeyEnvName
    if ([string]::IsNullOrWhiteSpace($script:ApiKey)) {
        throw "環境変数 '$ApiKeyEnvName' から API キーを取得できません。スクリプトには API キーを直書きしないでください。"
    }

    Write-Log -Level 'INFO' -Message "Claude Compliance Collector 開始。run_id=$($script:RunId) mode=$Mode root=$Root api_key_env=$ApiKeyEnvName pid=$PID"

    # 指定されたモードに応じて、Activity Feed / content の取得処理を実行します。
    switch ($Mode) {
        'ActivityBackfill' { Collect-Activities -Direction 'Backfill' }
        'ActivityTail'     { Collect-Activities -Direction 'Tail' }
        'ContentBackfill'  { Collect-Content }
        'ContentTail'      { Collect-Content }
        'AllBackfill'      { Collect-Activities -Direction 'Backfill'; Collect-Content }
        'AllTail'          { Collect-Activities -Direction 'Tail'; Collect-Content }
        default            { throw "Unsupported mode: $Mode" }
    }

    # ここまで例外なく到達した場合のみ、最終成功時刻を checkpoint に保存します。
    $state = Load-State
    $state.last_success_utc = (Get-Date).ToUniversalTime().ToString('o')
    $state.last_success_mode = $Mode
    Save-State -State $state
    $script:Stats.last_success_utc = $state.last_success_utc
    Write-StatusFiles -Status 'success'
    Write-Log -Level 'INFO' -Message "Claude Compliance Collector 正常終了。run_id=$($script:RunId) activity_saved=$($script:Stats.activity_saved) activity_duplicate=$($script:Stats.activity_duplicate) retries=$($script:Stats.retry_count) 429=$($script:Stats.rate_limit_429_count) errors=$($script:Stats.error_count)"
    exit 0
}
catch {
    # どこかで失敗した場合は error 状態を書き出します。
    # checkpoint は各処理で安全な位置までしか保存していないため、次回は同じ位置から再開できます。
    $script:Stats.error_count++
    $script:Stats.error = [ordered]@{
        message = $_.Exception.Message
        type = $_.Exception.GetType().FullName
        script_stack_trace = $_.ScriptStackTrace
    }
    try { Write-StatusFiles -Status 'error' } catch { }
    try { Write-Log -Level 'ERROR' -Message "異常終了。checkpoint は失敗位置より先へ進めません。run_id=$($script:RunId) error=$($_.Exception.Message)" } catch { }
    exit 1
}
finally {
    # 正常終了・異常終了のどちらでも、必ず多重起動防止ロックを解放します。
    Release-CollectorLock
}
