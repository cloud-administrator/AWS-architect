# Claude Enterprise Compliance Collector

公式資料確認日：**2026年9月16日（日本時間）**  
対象：Windows、ローカルNTFS、64ビットPowerShell 7.4以降。新規導入には**PowerShell 7.6 LTS**を推奨します。[M1][M2]

## 1. 最初に確認してください

この一式は、`Collect-ClaudeCompliance.ps1`、`config.json`、この`README.md`の3ファイルです。スクリプトの処理に未実装の穴やサンプルAPIはありません。ただし、**本番のCompliance Access Keyを使った実行、Windows上でのPowerShell実行、実テナントとの突合は実施していません**。公式仕様に基づく実装と静的な点検を行ったものであり、「本番動作確認済み」ではありません。後述の受入確認を経て運用してください。

対象は、**それぞれのAPIを呼び出した時点で取得できる内容**です。削除前の本文、過去の編集状態、APIが返さない内容を復元するものではありません。日次の全件走査は、開始時点の厳密なスナップショットでも、実行終了時点の完全なスナップショットでもありません。

### 1.1 本文除外とraw保存の両立について：設定前に必要な判断

Artifacts、アップロードファイル、生成ファイルの**専用の本文・ダウンロードAPIは呼びません**。URLや参照先もたどりません。一方、メッセージやツール入出力の中に、ファイルやArtifactと同じテキストがインラインで含まれる可能性を排除する公式保証や、その部分だけを除外する公式パラメータは確認できませんでした。実際に何が含まれるかは利用ツール・レスポンスに依存し、未確認部分は「不明」です。

したがって、「専用のファイル／Artifact本文を取得しない」と「返されたチャット／ツールJSONを欠落なく保存する」は実装できますが、**同じ内容の文字列を、メッセージ・ツール入出力も含めて一切保存しない**という意味の除外を同時には保証できません。文字列を推定して削る処理は、raw保存・ツール入出力の省略禁止と矛盾するため実装していません。

この解釈を黙って変更しないよう、同梱configは `acceptInlineContentInMessages: false` です。この状態ではAPIを呼ばず、終了コード5で停止します。要件責任者が「専用本文APIは呼ばないが、保存対象レスポンスに含まれるインライン文字列・参照情報はそのまま保存する」という対応を認めた場合にだけ `true` にしてください。**厳密な文字列単位の除外が必要な場合、このスクリプトをそのまま本番投入してはいけません。** この値は初回／日次を切り替える設定ではありません。

### 1.2 「処理完了」と「すべて取得できた」は別です

実行が最後まで進んでも、404で取得できない対象、削除表示、切り詰め、API側の未確認事項があり得ます。保存データ、manifest、checkpoint、statusで区別します。

本版は、公式APIの網羅性・非原子的走査などの制約が残るため、**処理が最後まで進んだ場合も終了コード2（制約あり）**です。0を「すべての必要データを検証済み」として安易に返しません。コード2だけで取得不能の有無は分からないため、`status.json`と本文の`lastScan`も確認してください。

## 2. 採用した構成

APIは1件ずつ順に呼びます。PowerShellの標準機能、.NETのHttpClient／System.Text.Json／ファイル機能だけを使用します。SDK、追加PowerShellモジュール、DB、キュー、並列処理、常駐サービスは使いません。スクリプト内の短いC#クラスは、ActivityのJSON文字列から**文字列の外側の空白だけ**を除去するものです。`Add-Type`で読み込み、別ファイルや別のコンパイラの設置は不要です。ただし、組織のアプリケーション制御・Constrained Language Modeが`Add-Type`を禁止する環境では実行できません。組織の許可・署名方針を確認し、制御を迂回しないでください。

| 対象 | 初回 | 初回走査後 |
|---|---|---|
| Activity Feed | 下限時刻を指定せず、固定した上限までAPIに残る履歴を全ページ取得 | 前回完了上限の24時間前から、今回の固定上限まで再取得。ID重複排除 |
| チャット | 対象組織全体を列挙し、各チャットのメッセージを全ページ取得 | 組織一覧・全メッセージを再取得 |
| プロジェクト | 組織一覧、詳細、添付一覧全ページ、project_doc本文 | 同じ全件確認・本文再取得 |
| ファイル等 | メッセージ／添付一覧で得た参照IDからメタデータ取得 | 同じ走査内の同一リクエストは再利用、次の走査では再取得 |

チャットには公式の更新日時順取得もありますが、関連メタデータの全変更が親チャットの`updated_at`に必ず反映されることや、走査中の同時更新を含む完全なスナップショット保証は確認できませんでした。そのため本版は、`order_by=created_at`で組織全体を毎回確認し、本文も再取得します。更新時刻の同値比較で再取得を省略しません。チャットIDが同じという理由で、別の走査の本文を捨てることもありません。[A4][A5]

project_docの添付参照の`updated_at`は、公式資料では将来用で現在は常にnullです。親プロジェクトの日時だけを使って本文の取得を省くことはしません。[A8]

### 2.1 実装しているAPIとパラメータ

基点は固定の `https://api.anthropic.com`、メソッドはすべてGETです。ヘッダーは`x-api-key`と`anthropic-version: 2023-06-01`です。リダイレクト先に認証情報を送らないよう、自動リダイレクトは無効です。TLS検証を無効化する処理はありません。[A1]

| 用途／参照 | パス | 実装で送るパラメータ／ページング |
|---|---|---|
| 監査 [A2] | `/v1/compliance/activities` | `organization_ids[]`、`limit=1000`、`created_at.lt`、日次は`created_at.gte`。`last_id`を`after_id`へ渡す |
| チャット一覧 [A5] | `/v1/compliance/apps/chats` | `organization_ids[]`、`limit=100`、`order_by=created_at`。`last_id`→`after_id` |
| メッセージ [A6] | `/v1/compliance/apps/chats/{chat_id}/messages` | `limit=100`、`order=asc`、`tool_use_input_max_chars=-1`、`tool_result_max_chars=-1`。`last_id`→`after_id` |
| プロジェクト一覧 [A7] | `/v1/compliance/apps/projects` | `organization_ids[]`、`limit=100`。`next_page`→`page` |
| プロジェクト詳細 [A9] | `/v1/compliance/apps/projects/{project_id}` | パラメータなし。`description`、`instructions`を含むレスポンス全体 |
| 添付一覧 [A8] | `/v1/compliance/apps/projects/{project_id}/attachments` | `limit=100`。`next_page`→`page` |
| テキスト文書 [A10] | `/v1/compliance/apps/projects/documents/{document_id}` | パラメータなし。`content`を含むJSON全体 |
| アップロードファイルのメタデータ [A11] | `/v1/compliance/apps/chats/files/{file_id}` | パラメータなし。project_fileのIDも対象 |
| 生成ファイルのメタデータ [A12] | `/v1/compliance/apps/chats/generated-files/{generated_file_id}` | パラメータなし。パスはハイフンの`generated-files` |
| Artifactバージョンのメタデータ [A13] | `/v1/compliance/apps/artifacts/{artifact_version_id}` | パラメータなし。Artifactの安定IDではなく**version_id**を指定 |

一覧・メッセージは、いずれも`has_more=false`まで進みます。カーソルやページトークンは不透明な文字列としてそのまま渡し、分解・独自生成しません。監査は新しい順、チャットは作成時刻の古い順、メッセージは`asc`、プロジェクト・添付一覧も作成順です。監査・チャット・添付の同時刻はIDで順序が付くことが記載されています。プロジェクト一覧の同時刻処理の詳細を独自に仮定する処理はありません。[A2][A5][A6][A7][A8]

ファイルとArtifactのメタデータのパスは、各APIリファレンスの**GET操作行とリクエスト例**に従っています。一部のフィールド説明には`/metadata`という表記もありますが、本版は架空の代替パスを組み立てたり、404時に別パスへ自動フォールバックしたりしません。表記の不一致を含め、実テナントでこの表のパスを受入確認してください。[A8][A11][A12][A13]

### 2.2 時間範囲と遅延対策

APIの時間条件はUTCです。日付フォルダは取得時刻を**UTC+09:00の日本時間**へ変換して決めます。Windowsの表示タイムゾーンやイベント発生日には依存しません。

各実行の開始UTC時刻から5分引いた値を、その実行の固定上限とします。初回は`created_at.lt=固定上限`だけを指定します。日次は`[前回完了上限－24時間, 今回固定上限)`です。`gte`は下限を含み、`lt`は上限を含みません。数日停止しても「前日だけ」にはせず、保存済みの完了位置から追いつきます。未完了の古い固定範囲があれば先に完了させ、今回の上限まで追加で取得します。[A2][A3]

公式ガイドは、イベントが通常1分以内に照会可能になること、上限を少なくとも1分前に置くこと、数分の重複や過去範囲の再照会を示しています。**5分の待機幅と24時間の重複幅は本版の設計値で、公式推奨の数値そのものではありません。** 全過去期間の定期再照会は実装していません。反映遅延の全障害ケースまで含むゼロ漏れSLAは確認しておらず、重複幅を超える例外的な遅延などで絶対に漏れないとは保証しません。[A2][A3]

## 3. 権限・Compliance APIの準備

組織の管理者に、Compliance APIの有効化と**本番用Compliance Access Key**の作成を依頼してください。通常の推論APIキーやAdminキーではなく、`sk-ant-api01-`で始まるCompliance Access Keyを使用します。必要なスコープは次の2つだけです。[A1]

- `read:compliance_activities`
- `read:compliance_user_data`

`delete:compliance_user_data`は不要で、付けないでください。DELETEや他の変更APIはコードにありません。組織ディレクトリ照会用の`read:compliance_org_data`も要求しません。組織UUIDはconfigに指定し、ディレクトリAPIは呼びません。

可能なら対象組織に限定したキーを使ってください。親組織のキーを使う場合も、一覧には対象UUIDを渡します。チャット・プロジェクトのレスポンスの`organization_uuid`がconfigと違う場合は停止します。ファイル／文書のように組織UUIDを直接返さないレスポンスは、検証済みの親レスポンスの参照から到達したものとして親IDを記録します。別組織由来の参照を一切返さないことまで、メタデータ単独で再検証できるとは説明しません。

対象の**Claude Enterprise組織UUID**を管理者またはAnthropicに確認してください。親組織・別のConsole組織と取り違えないでください。UUIDの形式が正しいことや、APIが空配列を返したことだけでは、指定組織が正しいことの証明にはなりません。[A1][A5]

## 4. WindowsとPowerShellを準備する

Windows PowerShell 5.1の`powershell.exe`ではなく、PowerShell 7の`pwsh.exe`を使います。Microsoft公式のWindowsインストール手順から64ビットMSI等で導入してください。[M1][M2]

PowerShell 7で次を実行し、バージョンと64ビット動作を確認します。

```powershell
$PSVersionTable.PSVersion
[Environment]::Is64BitProcess
```

7.4以降かつ`True`が必要です。新規導入はサポート中の7.6 LTSを推奨します。7.4のサポート終了予定は2026年11月10日なので、7.4を採用する場合は更新計画が必要です。[M1]

企業の実行ポリシー・アプリケーション制御に従ってください。ダウンロードブロックを解除する場合は、内容をレビューしてから管理者が次を実行します。組織が署名を要求する場合は署名手続きを優先し、`Bypass`で迂回しないでください。

```powershell
Unblock-File -LiteralPath 'C:\ClaudeComplianceCollector\Collect-ClaudeCompliance.ps1'
```

## 5. ファイル配置とNTFSアクセス権

配置は次のとおりです。

```text
C:\ClaudeComplianceCollector\
  Collect-ClaudeCompliance.ps1
  config.json
  README.md
  data\                 ← 以降は収集用
  state\
  logs\
```

スクリプトは必要な日付フォルダ、raw保存先、staging、ロック、進捗、ログを作ります。ただし、最小権限で運用するため、管理者が先に**アクセス権の境界となるルート、data、state、logs**を用意することを推奨します。通常のタスク実行アカウントにCドライブ全体への書き込み権限を与える必要はありません。

### 5.1 推奨する権限

専用の通常ユーザーアカウントをタスク用に用意します。例は`CONTOSO\svc-claude-collector`です。Administrator権限を与えません。SYSTEMとAdministratorsはフルコントロール、タスク用アカウントはルートとコードに読み取り・実行、`data`、`state`、`logs`配下に変更権限を付けます。「変更」は一時ファイルの作成・置換・移動に必要です。利用者一般への読み取りは不要です。管理者によるアクセスまで防ぐものではありません。[M4]

以下は**管理者として起動したPowerShell**で実行する初期構築例です。アカウント名を実在するものに変更してください。既存環境の独自ACLを置き換えるので、新規専用フォルダ向けです。既存データがある場合は管理者がACLとバックアップを確認してから適用してください。

```powershell
$ErrorActionPreference = 'Stop'
$root = 'C:\ClaudeComplianceCollector'
$account = 'CONTOSO\svc-claude-collector'
$svc = ([System.Security.Principal.NTAccount]::new($account)).Translate(
    [System.Security.Principal.SecurityIdentifier])
$admins = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$system = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
$none = [System.Security.AccessControl.PropagationFlags]::None
$allow = [System.Security.AccessControl.AccessControlType]::Allow

foreach ($path in @($root, "$root\data", "$root\state", "$root\logs")) {
    [void][System.IO.Directory]::CreateDirectory($path)
}

function Set-CollectorDirectoryAcl([string]$Path, [string]$ServiceRights) {
    $acl = [System.Security.AccessControl.DirectorySecurity]::new()
    # 親から継承した許可をコピーせず、指定した3主体だけで作り直す。
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($admins)
    foreach ($sid in @($admins, $system)) {
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
            $sid, 'FullControl', $inherit, $none, $allow))
    }
    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
        $svc, $ServiceRights, $inherit, $none, $allow))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

Set-CollectorDirectoryAcl $root 'ReadAndExecute'
# 配置済みの子ファイル・フォルダに残った明示的な広い許可も除く。
& icacls.exe "$root\*" /reset /T /C
if ($LASTEXITCODE -ne 0) { throw 'ACL reset failed; inspect permissions before continuing.' }
foreach ($path in @("$root\data", "$root\state", "$root\logs")) {
    Set-CollectorDirectoryAcl $path 'Modify'
}
& icacls.exe $root
& icacls.exe "$root\data"
& icacls.exe "$root\state"
& icacls.exe "$root\logs"
```

3ファイルの配置・config編集は管理者が行います。ルートのACLを設定した**後**に配置したファイルも、意図した権限を継承しているか確認してください。他の場所からの同一ボリューム内移動などで以前のACLが残っている場合は、管理者が対象ファイルのACLを正してください。タスクアカウントでコードの編集はできず、data/state/logsに作成・変更できることを確認します。

NTFSはアクセス制御であり、暗号化や改ざん不能保管の代わりではありません。既存の端末・バックアップ暗号化、権限管理、監査方針も適用してください。ハッシュは事故による不整合の検出用で、ハッシュとデータを両方書き換えられる管理者への証拠保全機構ではありません。

## 6. configを設定する

```json
{
  "organizationUuid": "実際の対象組織のUUID",
  "acceptInlineContentInMessages": true
}
```

UUID以外に任意のURLやキーは入れません。2つ目の値をtrueにする意味は「1.1」のとおりです。未承認ならfalseのまま停止させてください。保存先、ページサイズ、リトライ値はコード内で固定し、不必要な切替機能は設けていません。

**収集開始後に別組織のUUIDへ書き換えて同じ保存先を再利用しないでください。** checkpointや保存済みmanifestと一致しなければエラーで止まります。キーのローテーションは同じ組織・必要スコープを維持して行えます。公式ガイドではカーソルはキーではなく組織に結び付き、キーのローテーションをまたいで利用できます。[A1]

## 7. APIキーをWindows環境変数に設定する

本番キーをチャット、ps1、config、コマンドの文字列リテラルに貼り付けないでください。スクリプトは次の順に読みます。

1. **実行中のWindowsアカウント自身のUser環境変数** `CLAUDE_COMPLIANCE_ACCESS_KEY`
2. それが空の場合だけ、同名のProcess環境変数

Machine環境変数への保存は推奨しません。別の手動実行ユーザーのUser変数がタスクアカウントへ共有されるとは扱いません。User環境変数をAPIで毎回直接読み取るため、スケジューラサービスが古い環境ブロックを持っていても、それだけに依存しません。[M3]

### 7.1 必ずタスクで使用するアカウントとして設定する

管理者が許可した方法で、**タスクに設定する専用アカウントとして**PowerShell 7を起動します。まず`whoami`で、そのアカウントになっていることを確認します。管理者アカウントのPowerShellで以下を実行しても、専用アカウントのUser変数にはなりません。

対話ログオンを許可しないサービスアカウント、gMSA、SYSTEM等の環境構築は、この対話的なUser環境変数設定手順とは別です。本手順では、初期設定を管理者の許可の下で実施でき、ユーザープロファイルを持つ専用アカウントを想定します。

```powershell
whoami
$secret = Read-Host 'Compliance Access Keyを入力（画面には表示しません）' -AsSecureString
$ptr = [IntPtr]::Zero
try {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    [Environment]::SetEnvironmentVariable(
        'CLAUDE_COMPLIANCE_ACCESS_KEY',
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr),
        [EnvironmentVariableTarget]::User)
}
finally {
    if ($ptr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
    $secret.Dispose()
    Remove-Variable secret, ptr -ErrorAction SilentlyContinue
}
```

次は有無だけの確認です。変数の値そのものを表示するコマンドは実行しないでください。

```powershell
-not [string]::IsNullOrWhiteSpace(
    [Environment]::GetEnvironmentVariable(
        'CLAUDE_COMPLIANCE_ACCESS_KEY', [EnvironmentVariableTarget]::User))
```

`True`を確認します。タスクから実際に読み取れることは、専用アカウントを設定したタスクを手動で「実行」して確認してください。

WindowsのUser環境変数は秘密保管庫ではなく、当該アカウントの設定やプロセスから読み取れる平文の値です。同じアカウントの他のプロセスや管理者からの秘匿まで保証しません。専用アカウントを共用せず、余計なソフトウェアを動かさないでください。設定作業中のトランスクリプトや画面収録など、周辺の記録方法にも注意してください。上のSecureStringは入力表示と一時バッファの扱いの対策であり、永続環境変数を暗号化するものではありません。[M3]

## 8. 初回実行と、停止後の再実行

以後、初回・日次・失敗後で**次のコマンドを変えません**。キーを設定したタスクアカウントとして実行します。

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive `
  -File 'C:\ClaudeComplianceCollector\Collect-ClaudeCompliance.ps1' `
  -ConfigPath 'C:\ClaudeComplianceCollector\config.json'
$LASTEXITCODE
```

新規保存先では初回になります。途中までのcheckpointがある場合は、APIレスポンス単位の保存記録から再開します。ファイルが1つでも存在すれば初回完了、という判断はしません。

監査の初回範囲完了と、本文の初回走査完了は独立しています。監査が終わって本文が途中なら、次回は監査の追いつき取得と本文の再開を行います。前回の本文走査を再開した場合は、その走査を終えた後、今回分としてもう一度全件走査します。これにより、前回の停止前に処理済みだったチャット等も再確認します。通常の日次実行では全件走査は1回です。

大量データで実行が長くなっても、別のBackfillコマンドへ切り替えたり、checkpointを削除したりしません。プロセスが終了してロックが解放された後、上記を再実行してください。

### 8.1 実行後の確認

以下は管理情報だけを表示します。`data\raw`の本文ファイルをコンソールにまとめて表示する必要はありません。

```powershell
$root = 'C:\ClaudeComplianceCollector'
$s = (Get-Content -LiteralPath "$root\state\status.json" -Raw | ConvertFrom-Json).payload
$s | Select-Object runId, startedAtUtc, endedAtUtc, exitCode, processCompleted, incomplete, coverage
$s.modes
$s.counts
$s.endCheckpoint.activities
$s.endCheckpoint.content
```

`status.json`は管理情報を`payload`に持つチェックサム付きJSONです。上の閲覧例自体はチェックサム検証ツールではありません。収集スクリプトが起動時にcheckpoint・保存データを検証します。

| 確認項目 | 意味 |
|---|---|
| `processCompleted=true` | その実行の予定された処理が最後まで進んだ |
| `incomplete=true` | 未完了で停止した。再開または設定・復旧が必要 |
| `activities.initialComplete=true` | 監査の初回固定範囲を全ページ保存済み |
| `content.initialEnumerationComplete=true` | 初回の組織一覧・関連一覧の走査を完了した。取得不能の記録を含み得る |
| `content.initialWithoutBlockingIssues` | 初回走査が、取得不能・明示的切り詰め・削除表示等のブロック対象の問題なしで終了したか。未確認事項まで解消した意味ではない |
| `content.lastScan.allDiscoveredFetchesSaved` | 最新の本文走査で、発見した各取得リクエストが404記録ではなく保存成功になったか |
| `content.lastScan.withoutBlockingIssues` | 最新走査で、取得不能・明示的切り詰め・削除表示・未対応添付型というブロック対象の問題がなかったか |
| `content.lastScan.allRequestedDataSaved` | 本版では「不明」。取得可能な全対象の完全性を独立に証明したものではない |
| `coverage` / `lastScan.completeness` | 本版では「不明」。APIが列挙しない対象や全体スナップショットまで証明しない |
| `activities.lastSuccessUtc` | 監査の固定範囲の全ページ保存を最後に完了したUTC時刻 |
| `content.lastSuccessUtc` | 本文走査が完了し、`withoutBlockingIssues=true`だった最後のUTC時刻。APIレスポンスの収集・保存成功であり、未知の内容まで完全性を保証する時刻ではない |
| `content.lastCompletedScanUtc` | 本文走査を最後に終えた時刻。取得不能等がある場合も更新されるため、成功時刻と区別する |
| `lastDataSaveUtc` | 最後にレスポンスまたは取得不能の記録を確定した時刻。本文成功の代用にしない |

`status.json`の`endCheckpoint`は終了処理でディスクから読み直した値です。保存に失敗したメモリ上の進捗を終了checkpointとして載せません。`endCheckpointRead=read_from_disk`以外の場合は、進捗を未読込み／読み出し不能として扱い、ログと実ファイルを調査してください。

`initialEnumerationComplete=true`でも`initialWithoutBlockingIssues=false`なら、「初回走査は終了したが、必要な本文に未取得等がある」です。`initialWithoutBlockingIssues=true`でも、切り詰めフラグがない対象やAPIの列挙限界については「不明」のままです。次回は日次走査として再確認します。404記録だけで本文取得成功に変換しません。初回評価は初回時点の記録として残り、日次の結果は`lastScan`で確認します。

削除情報が一覧と本文の両方で返る場合、`blockingObservations`は同じ対象について複数になることがあります。これは**問題の観測数**で、ユニークなリソース数ではありません。問題の対象IDは該当manifestにあります。削除済み対象が一覧に残る組織では、本文の厳格な`lastSuccessUtc`が更新されないことがあります。`lastCompletedScanUtc`や問題一覧と併せて、収集停止と既知の欠損を区別してください。

### 8.2 件数の読み方

`counts.fetched`は今回新たにAPIから取得・JSON検証できたレコード、`counts.saved`は今回確定した保存レコード、`counts.replayed`は保存済みレスポンスを再開・同一走査内で再利用したレコードです。再利用は同じリクエストを実行中に初めて再利用した時にだけ数えます。これらを単純合計して組織全体のユニーク件数にしないでください。

主要な単位は、`activity_events`（監査イベント）、`chat_list_records`（一覧のチャット）、`message_records`（メッセージ）、`tool_use_blocks`／`tool_result_blocks`（ブロック）、`project_list_records`（一覧のプロジェクト）、`project_details`（詳細JSON）、`project_docs`（文書本文JSON）、`attachment_references`（添付参照）、`uploaded_file_metadata`、`generated_file_metadata`、`artifact_version_metadata`です。一覧の成功件数と本文の保存件数を別々に確認できます。

`activityDuplicates`は今回APIから受け取った重複監査イベント数です。`unavailableRecorded`は今回確定した取得不能**レスポンス記録数**です。再開済みの記録も含む走査全体の取得不能数は`content.lastScan.unavailableResponses`を見ます。`errors`は各失敗試行と最終停止の記録数なので、ユニークな障害件数ではありません。`apiAttempts`、`retries`、`http429`はそれぞれAPI試行数、再試行予定回数、受信した429の件数です。

## 9. 1日1回のタスクスケジューラ設定

Windowsの「タスク スケジューラ」で「タスクの作成」を開きます。以下の03:00はWindowsのタイムゾーンが日本の場合です。サーバーがUTC等なら現地設定に合わせて時刻を換算してください。保存先の日付は、サーバーのタイムゾーンに関係なく日本時間です。

| 項目 | 設定 |
|---|---|
| 名前 | 例：`ClaudeComplianceCollector` |
| 実行ユーザー | APIキーを設定した専用アカウント |
| ログオン | 「ユーザーがログオンしているかどうかにかかわらず実行する」 |
| 最上位の特権 | 通常は不要。チェックしない |
| トリガー | 毎日03:00、1日ごと、有効 |
| プログラム | `C:\Program Files\PowerShell\7\pwsh.exe` |
| 引数 | 下記の1行 |
| 開始（オプション） | `C:\ClaudeComplianceCollector` |
| 予定時刻に実行できなかった場合 | できるだけ早く実行する |
| 既に実行中の場合 | **新しいインスタンスを開始しない**（IgnoreNew） |
| 実行時間制限 | **「タスクを停止するまでの時間」のチェックを外す** |

```text
-NoLogo -NoProfile -NonInteractive -File "C:\ClaudeComplianceCollector\Collect-ClaudeCompliance.ps1" -ConfigPath "C:\ClaudeComplianceCollector\config.json"
```

初回の大量取得が既定の実行時間制限で終了しないよう、時間制限を必ず確認します。バッテリー、アイドル、ネットワーク条件等が原因で起動・継続できない設定も見直してください。タスクアカウントには「バッチジョブとしてログオン」等の必要な権利が必要です。組織ポリシーによる拒否、アカウントロック、パスワード期限切れにも注意します。[M5]

タスクを保存した後、右クリックの「実行」で確認します。キーの読取り、ファイル書込み、API接続は、**手動の管理者セッションではなくこのタスクアカウントで**成功する必要があります。ネットワークは`api.anthropic.com:443`へのHTTPS通信を許可してください。企業プロキシ・TLS検査の可否は実環境で確認し、証明書検証を無効化して回避しないでください。

### 二重起動の防止

タスクのIgnoreNewに加えて、`state\collector.lock`を`FileShare.None`で開いたまま実行します。同じ保存先を使う手動実行とタスク実行も排他対象です。別プロセスがロック中なら終了コード6になります。ロックファイルの「存在」ではなくOSのオープン排他を使うため、異常終了後にファイルだけ残っていても再実行できます。ロックファイルを手動で削除する必要はありません。[M5]

## 10. 保存データと、安全な再開の仕組み

取得日の日本時間で、例えば次のように保存します。1日の巨大なJSONLに追記せず、**APIの1レスポンス単位**の小さな確定フォルダに分けます。この分割により、追記途中の末尾を修復して正常データまで傷つける処理を避けます。

```text
C:\ClaudeComplianceCollector\
  data\raw\2026\09\16\
    activities\b_00000000000001\
      activities_20260916.jsonl
      manifest.json
    content\b_00000000000002\
      response.json
      manifest.json
    content\b_00000000000003\
      manifest.json             ← 例：404で取得不能の記録。本文保存成功ではない
  state\
    checkpoint.json
    status.json
    collector.lock
    staging\                    ← 未確定の書き込み
    recovery\...                ← 中断時の未確定ファイルを保管
  logs\
    run_20260916_030000_<run-id>.txt
    error_<run-id>.txt
```

`b_...`は保存単位の通し番号です。実際の番号・実行時刻は実行結果で決まります。取得範囲の途中で日本時間の日付が変われば、その後のレスポンスは次の日のフォルダに入ります。

### 10.1 raw JSONの保護

本文・一覧・メタデータの`response.json`は、HTTPレスポンスのJSON本文を受け取ったバイト列で保存します。HTTPのgzip等が使用された場合は、解凍後のJSONエンティティです。HTTPヘッダーや通信の圧縮形式を保存するものではありません。

解析には`System.Text.Json.JsonDocument`を使います。**APIレスポンスは`ConvertFrom-Json`→`ConvertTo-Json`で保存し直しません。** 深い構造、文字列、数値表記、未知のフィールドをPowerShell型へ変換して失うことを避けています。`ConvertTo-Json`はスクリプト自身が作る管理情報にだけ使用します。

監査は`data`内の各Activityオブジェクトをそのまま取り出し、文字列の外の空白だけを除去して1行にします。数値トークン、エスケープ、追加フィールド、未知の`type`・`actor.type`は保持します。監査のページレスポンス全体を別にraw保存して重複イベントを二重保存することはせず、ページ情報はmanifestへ記録します。

JSONの検証深度は2048です。これを超えるものや不正JSONは、切り詰めて保存せずエラーで止めます。極端に大きな1レスポンスはメモリに収まらないことがあり、その場合も内容を省略して成功扱いにはしません。

manifestには対象組織、親ID・リソースID、取得UTC日時、日本時間の日付、リクエスト識別子、API request-id、取得結果、件数、ページ情報、品質上の問題を保存します。元のAPI JSONへ管理項目を混ぜたり、元の項目を削ったりしません。署名付きURL等を含む参照情報も削らず、保護されたrawに残します。通常ログにはそれらを出しません。

### 10.2 保存順序とcheckpoint

保存順序は固定です。

1. API取得とJSONの検証を行い、未確定のstagingフォルダへpayloadとmanifestを書きます。ファイルをFlushして閉じます。
2. 同じNTFSボリューム内のディレクトリ名変更で、payloadとmanifestを一緒に日付フォルダへ確定します。既存の確定データは上書きしません。
3. 確定したデータだけを監査IDのメモリ内集合へ登録します。
4. checkpointを一時ファイルから置き換えます。対象範囲全体・本文走査全体の完了フラグは、さらに**全ページと関連取得を終えた後**に更新します。

監査IDの独立した永続インデックスは持ちません。起動時に保存済みJSONLから再構築するため、「重複判定の状態だけ先に保存され、データはない」という状態を作りません。日付をまたいでも全保存済みActivityの`id`で重複を判断します。

ディレクトリ確定後、checkpoint置換前に停止した場合、次回は連続した通し番号・ハッシュ・対象組織・実行中走査IDを検証し、**最大1つの確定済み保存単位**をcheckpointへ取り込みます。任意の不明なファイルを成功扱いにする復旧ではありません。

### 10.3 ページ単位の再開

checkpointの実行中走査IDと、確定済みmanifestの「リクエスト条件・カーソル・次ページ」を組み合わせて、ページ進捗を保持します。再開時はコード上のループを先頭からたどりますが、**同じ未完了走査の保存済みリクエストはローカルの結果を読み、APIを再呼び出ししません**。そこから初めて未保存のページ／本文取得へ進みます。

この方式により、本文取得の途中位置を表す複雑な入れ子のキューを持たずに、チャット→メッセージ→メタデータ、プロジェクト→添付→文書の途中から再開できます。新しい走査は別IDなので、前日と同じチャットIDでも改めて取得し、過去の本文は残します。同じ日の再走査も別の保存単位になり、既存本文を上書きしません。

### 10.4 起動時の不整合チェック

全保存単位のpayload長、SHA-256、JSONの妥当性、manifestのチェックサム、通し番号の連続、前manifestとのハッシュ連鎖、組織・収集ID、checkpointとの整合性を検証します。JSONLの最終改行がない場合や不正行、保存済みActivity IDの重複も停止対象です。末尾を勝手に切り落としません。

有効なcheckpointがあり、確定していないstagingやcheckpointの一時ファイルだけが残っている場合、それらは`state\recovery`へ移して保持し、未保存リクエストを再取得します。既存の確定rawを自動修正・削除する機能はありません。

保存データがあるのにcheckpointだけがない場合、checkpoint破損、組織不一致、不明なrawファイル、データ不足等では停止します。ログしかない初回設定失敗は、新規収集データがある場合とは区別します。

この保護は、一般的なプロセス停止や不完全書込みを検出・再開するためのものです。ディスク装置の故障、OSやストレージがFlushを正しく実行しない障害、あらゆる電源断での永続性、悪意ある改ざんまで完全に保証するものではありません。バックアップは別途必要です。

## 11. レート制限とエラー処理

公式のCompliance API制限は、**親組織全体で600リクエスト／分**です。キー単位や対象組織単位の独立枠ではなく、関連する組織、他のキー、Activity Feed・本文等のComplianceエンドポイント間で共有します。本版が呼ばないセッション系の追加制限を、本版の独立した600枠と混同しないでください。[A14]

| 項目 | 本版の設定 |
|---|---|
| 通常の呼出し間隔 | 全エンドポイント・全再試行を合わせ、開始間隔250ms以上（単独時おおむね最大240回／分） |
| 1試行のタイムアウト | ヘッダー受信と本文読み取りを合わせて120秒 |
| 再試行上限 | 最初の試行＋追加6回、最大7試行 |
| 通信・タイムアウト・500/502/503/504/529 | 同じリクエスト・カーソルで再試行。基本待機1、2、4、8、16、32秒、一般上限60秒 |
| 429 | 有効な`retry-after`を優先。公式の秒数表記に加え、解釈できるHTTP日時も扱う |
| retry-after欠落／不正 | 同じ指数バックオフを使用 |
| サーバー待機指示が1時間超 | 指示を切り詰めて早く再試行せず、未完了で停止する |
| rate-limit残数が1以下 | 解釈できる`anthropic-ratelimit-requests-reset`の時刻＋1秒まで次回呼出しを遅らせる |
| x-should-retry | `false`では再試行しない。`true`は再試行を許可。ただし401/403の停止を優先 |

250ms、120秒、追加6回、1時間の安全上限、残数1の扱いは設計上の設定で、公式にその値が指定されているわけではありません。公式資料で確認した再試行ヘッダー・エラー分類に従って制御します。他の収集者が同じ枠を消費する場合は、本版だけで600以下を保証できないため、管理者が全体の利用量を調整してください。429では未保存位置のまま待機・再試行します。[A14]

401/403は認証・権限エラーとして即停止します。403の呼出しも共有枠を消費し得るため、繰り返し起動する前に権限を直してください。[A14]

個別の本文・メタデータ取得の404は、汎用の未認証／パス不正を示す公式の`Not found`と一致するケースを除き、「取得不能・理由不明」のmanifestを保存して後続へ進みます。**404だけで削除と断定しません。** 組織全体の一覧の404、その他の再試行しないエラーは停止します。明示的な`deleted_at`がある場合は、APIが削除時刻を報告した事実と、本文の可用性が別であることを記録します。[A14]

公式のエラー本文は内容を含む可能性があるため保存・表示しません。記録するのはHTTPステータス、既知の`error.type`、安全に制限したrequest-id、対象ID、固定の理由コード、ローカル例外型・HResult・スクリプト行番号です。任意の`error.message`、例外メッセージ全体、スタックダンプ、認証ヘッダーはログへ出しません。理由を確定できない場合は「不明」のままにします。

## 12. 切り詰め・取得不能・対象外の扱い

メッセージのツール入力・結果は既定では各10,000文字の制限があるため、両方のmax_charsを-1にします。`tool_use.input`はJSONを符号化した文字列ですが、さらに解釈・再シリアライズせずraw内にそのまま保存します。[A6]

`truncated=true`が返れば対象チャットID・メッセージID・ブロック位置をmanifestに残します。`false`なら、返されたそのフラグがfalseだったことを記録します。**フラグがない場合にfalseと推測しません。** project_doc等で切り詰めフラグが提供されていないものは「不明」です。サーバー側で別の上限が適用される可能性まで、-1で解消すると断定しません。[A6][A10]

プロジェクト詳細の説明・指示が想定外にnullだった場合も、空文字の正常本文と決め付けず、対象IDと取得可否不明を記録してブロック対象の問題に数えます。

ツール結果のAPIはテキスト項目を返し、画像・リンク等の非テキスト項目を省略することが公式に記載されています。省略された項目がその呼出しに実際にあったかを返された情報だけで分からない場合は「存在不明」と記録します。`thinking_redacted=true`はAPI側で内部推論に関するテキスト等が除かれた表示で、通常の文字数切り詰めと区別します。省略された内部推論を復元する処理はありません。[A6]

| 対象 | 保存範囲と制約 |
|---|---|
| チャットのユーザー入力／Claude回答 | メッセージAPIが返す全ページのJSON。回答の内部推論やAPI非提供部分の復元はしない |
| ツール入出力 | APIが返す範囲を無加工保存。非テキスト結果の省略・明示的切り詰め等は別記録 |
| プロジェクト | 説明・カスタム指示を含む詳細JSON。名前等の追加項目も落とさない |
| project_doc | 添付除外ではない。文書取得APIで本文を取得。Word等がテキスト文書へ変換されてproject_docとして列挙される場合も対象 |
| アップロード・生成ファイル | 参照と専用メタデータのみ。ダウンロードしない |
| Artifacts | 利用可能な各メッセージの`artifacts[].version_id`ごとにメタデータ取得。`/content`は呼ばない |
| 不明な将来の添付型 | 一覧のrawは保存。対応APIを推測して呼ばず、対象IDと未対応の記録を残す |
| Claude Code／Cowork等のセッションAPI | 今回のチャット・プロジェクト収集とは別のAPI群で、本版では呼ばない。全Claude利用面の本文収集と説明しない |
| Claude APIの推論リクエスト本文 | Activity Feedの記録を推論プロンプト・回答本文の収集とみなさない |

Artifact・ファイルには、組織全体の全ID・全バージョンを独立列挙するAPIを確認できませんでした。本版のメタデータ取得の起点は、組織のチャット・メッセージ、プロジェクト添付一覧が返す参照です。**そこに参照がない古いバージョン、孤立したファイル、履歴にしか残らないIDまで網羅する保証はありません。** Activity Feedを完全な本文目録として使ったり、未知のイベント項目からIDを推測して追加探索したりはしません。専用の全件目録が必要な場合はAnthropicに可用性・提供方法を確認する必要があります。[A4][A13][A15]

## 13. 保持期間・有効化前・削除・退職者・シークレットチャット

| 項目 | 公式資料で確認できた範囲／本版への影響 |
|---|---|
| 監査の保持 | 6年。Compliance API有効化時からの記録で、過去に遡って生成されない。[A2] |
| API無効化中 | 記録が止まる。再有効化後に停止中の記録を復元することはできない。既存記録の扱いは組織設定も確認。[A1] |
| 本文の保持 | 組織の保持設定、削除、対象の可用性に依存。Enterpriseのカスタム保持は最短30日、既定は無期限という案内があるが、ユーザー削除等とは別。[A15][A16] |
| プロジェクトの保持 | プロジェクトの最終利用・更新に基づく組織ポリシーが関係する。保持方針の説明を、APIの`updated_at`がすべての文書変更を検出する保証へ読み替えない。[A16] |
| 有効化前の本文 | 日付で除外せず、現在の一覧に現れ取得できる本文を収集する。監査の非遡及性と混同しない。全レガシーデータ・全フィールドの遡及可用性保証は確認できず「不明」。[A4][A15] |
| 削除済みチャット | 削除情報が残るものは、名前が空・メッセージ本文がない等の状態になる。完全削除や保持期限超過で一覧・取得から消えるものを復元できない。[A4] |
| 退職・組織から除去したユーザー | 在籍者一覧で対象を絞らない。組織単位のキーでは、元の作成者が非在籍だとchat.userがnullになることが明記されている。nullでも処理する。[A5][A17] |
| アカウント削除済みユーザー | プロジェクトのuserはアカウント削除等でもnullになり得る。リソースがAPIに残っていれば対象。組織からの除去とアカウント／リソースの完全削除を同一視しない。[A7] |
| シークレット／Incognito | EnterpriseのCompliance APIで利用可能と案内され、通常30日、組織のカスタム保持が長ければそれに従う。現時点で列挙・取得できるものを対象とし、過去の全シークレット本文を保証しない。[A18] |
| organization_uuidがnullの監査 | サインイン／サインアウト／Compliance API呼出しなど、組織に直接結び付かないイベントではnullとなる。対象UUIDで絞った結果における網羅性や特定組織への帰属は「不明」。親組織全体の監査を無条件に対象組織へ混ぜない。[A2] |

保持期間を短縮すると削除が進む可能性があるため、収集開始前に組織の設定を記録し、変更手続きを管理してください。長い初回収集中にもAPI側で削除・保持期限到達が進み得ます。削除されてからの再取得は保証されません。これは本版が履歴復元を提供しない理由であり、取得済みrawを後から自動削除する理由ではありません。

## 14. 終了コードと障害時の対処

| コード | 意味 | 対処 |
|---|---|---|
| 0 | 制約も含めた完全性を検証済みの場合に予約。本版は返さない | 0でないことだけでスクリプト未起動とは判断しない |
| 1 | 通信・API再試行枯渇・JSON処理・保存・ローカル処理等の失敗 | エラーログの固定コード、HTTPステータス、対象ID、request-idを確認。原因解消後に同じコマンド |
| 2 | 処理を最後まで実施したが、既知／未確認の制約がある。取得不能が含まれる場合もある | statusの本文結果・問題数を必ず確認。単なる「全部成功」ではない |
| 3 | 認証・権限、公式の汎用Not foundによる未認証／パス問題 | キーの有効性、実行アカウントの環境変数、スコープ、組織、APIパスを確認 |
| 4 | checkpoint・rawの不整合／破損／紛失など、復旧が必要 | 自動初期化しない。下記の復旧手順 |
| 5 | UUID、キー種別、インライン本文方針、実行環境等の設定不備 | configと準備手順を修正。方針未承認を単にtrueへ変えて回避しない |
| 6 | 同じ保存先で別プロセスが実行中 | 実行中タスクを確認。ロックファイルは削除しない |

タスクスケジューラでは2が`0x2`等の表記になることがあります。このスクリプト自身が返した値の場合、ここで定義した「制約あり」です。ただし、スケジューラがpwshを起動できずに返したエラーと区別するため、対応するrunログの開始時刻・runIdがあることも確認してください。

認証エラーでは本番キーをログへ貼り付けず、同じ実行アカウントで環境変数の有無だけを確認します。キーの失効・期限・対象組織・読み取りスコープは管理者に確認してください。APIの仕様不一致が疑われる場合は、固定のAPIパス、HTTPステータス、request-id、公式参照先をAnthropicへ伝えます。raw本文や認証情報を通常の問い合わせログへ添付しないでください。

ディスク不足・書込み拒否では、保存先と一時書込み用の空き容量、NTFS権限、セキュリティ製品のブロックを確認します。空きを確保した後、同じコマンドを実行します。確定前の保存を成功扱いにする進捗更新は行いません。エラーログ自身を書けない場合もあり、コンソールの固定メッセージ・終了コード・タスク結果も確認してください。

### checkpointの破損・紛失

タスクを無効化し、実行中プロセスがないことを確認したうえで、`data`、`state`、`logs`を保護された場所へ一式退避して調査してください。復元する場合は、**同じ時点のdataとstateの整合したバックアップ**をセットで復元します。checkpointだけ古いものに戻すと、多数の確定保存単位との不整合として停止します。

バックアップがなければ自動初期化せず、保存済みmanifestの連続性と実行中範囲を担当者が調査して復旧方法を決めます。この版は任意の壊れたstateを推測して再生成する機能を提供しません。保存済みデータを残したままcheckpointを削除して「初回」に戻す操作は禁止です。監査の途中カーソルと日次開始点を失い、本文取得完了の誤判定にもつながるためです。

## 15. 起動しなかった場合も検知する

収集スクリプトが自分の起動時に調べるだけでは、**そのスクリプトが起動しなかったことは検知できません**。既存の監視機能で、少なくとも次を監視してください。

- タスクの最終起動・終了結果と、`status.json`の更新時刻・runIdが予定どおり変わること。
- checkpointの監査・本文の`lastSuccessUtc`が古くなっていないこと。本文は`lastCompletedScanUtc`と取得不能数も併せて判断すること。
- 保存先の空き容量とWindowsホスト自体の稼働。

既存の監視基盤がない場合は、収集タスクと別に毎日09:00等の確認タスクを置けます。次はその確認処理の例です。新しい補助ファイルを配布する必要はなく、タスクのpwsh `-Command`に設定できます。**36時間は運用例で、公式推奨値ではありません。** 初回が長時間かかる場合や既知の削除対象がある場合は、未完了警告と停止を人が区別してください。

```powershell
$ErrorActionPreference = 'Stop'
try {
    $p = 'C:\ClaudeComplianceCollector\state\checkpoint.json'
    $c = (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json).payload
    $now = [datetimeoffset]::UtcNow
    foreach ($value in @($c.activities.lastSuccessUtc, $c.content.lastSuccessUtc)) {
        if ($null -eq $value) { exit 1 }
        $time = [datetimeoffset]$value
        if (($now - $time).TotalHours -gt 36 -or ($time - $now).TotalMinutes -gt 5) { exit 1 }
    }
    exit 0
}
catch { exit 1 }
```

タスクの引数に入れる場合は、上記をセミコロンで1行につなぎ、全体を`-NoProfile -NonInteractive -Command "..."`の引用符内に入れます。チェック対象パスはコード例のように単一引用符を使用します。この確認タスクには環境変数のキーやAPI権限は不要で、checkpointの読み取り権限だけで足ります。

確認タスクが1を返したことを、既存のタスク監視に接続するか、担当者が毎日確認してください。**確認タスクを作るだけでメール等の通知が届くわけではありません。** 同じPC自体が停止すると確認タスクも動きません。既存の外部ホスト監視、または別端末からの定期的な確認も必要です。新しい常駐監視基盤をこの一式で作る設計にはしていません。

## 16. 容量・実行時間・バックアップ

本文は毎回保存するので、変化がなくても容量が増えます。同じ日に再実行して新規走査が行われた分も増えます。保持・自動削除・世代間の本文ハッシュ重複排除は実装していません。payloadのハッシュは**整合性検証用**であり、前日と同じ本文を省略するためのものではありません。

本文APIの概算呼出し数は、チャット一覧ページ数＋各チャットのメッセージページ数＋プロジェクト一覧ページ数＋各プロジェクトの詳細1件と添付一覧ページ数＋project_doc数＋参照されたユニークなファイル／生成ファイル／Artifactバージョン数です。空の一覧やメッセージでも確認のために1リクエスト必要です。例えば10,000チャットが各1ページなら、メッセージ取得だけで10,000リクエストです。待機間隔250msだけで2,500秒相当になり、ネットワーク、データ量、JSON検証、ファイルI/O、リトライ等がさらに加わります。実データ量で、1日1回の全件走査が現実的な時間に終わるか測定してください。

起動時は全rawのハッシュ等を読むため、累積データ量に比例してディスク読み取りが増えます。監査ID集合は全ユニークイベント数に比例してメモリを使います。大量の保存単位の一覧もメモリを使います。**無制限の組織規模へそのまま拡張できる設計ではありません。** ストレージ・RAM・1回あたりの処理時間を測り、この単純構成の上限を運用で確認してください。DB等を先回りして追加する代わりに、この制約を明示しています。

dataだけでなくstate、logs、一時データ、recovery、バックアップにも容量が必要です。空き容量は既存監視または定期運用で確認し、正常データを手で消して空きを作らないでください。コード・configの更新は実行停止中に管理者が行い、保存形式が異なる版を安易に混在させないでください。

バックアップは、収集プロセスが終了しロックが解放された時点で、dataとstateを一緒に取る方法が単純です。ログと設定・コードも一緒に残すと調査に役立ちます。環境変数の本番キーをrawバックアップへ書き出す必要はありません。

## 17. 本番開始前に実環境で確認する事項

公式仕様で確認したものは、表に示したエンドポイント・パラメータ、ページング、ツール文字数制限解除、スコープ、共有レート制限、エラー用ヘッダー、保持・ユーザー可視性の記載です。対して、以下は実環境での確認が必要です。

| 確認 | 期待する結果 |
|---|---|
| タスクアカウントの準備 | User環境変数が読める。コードは編集不可。保存フォルダは書ける。不要アカウントは読めない |
| 組織とキー | 実際の対象組織のデータである。2つの読み取りスコープだけで全対象APIに到達できる |
| チャット本文 | 管理者が確認できる既存チャットの入力・回答と突合する。ツール入出力と長文のフラグも確認する |
| 退職者・削除アカウント・Incognito | 保持期間内の許可された対象が組織一覧・本文に現れるかを確認する。現れない理由を推測しない |
| project_doc | プロジェクト説明・指示、添付のテキスト文書を確認する。プロジェクト更新日時によらず次走査で再取得される |
| 各メタデータ | upload、generated file、複数Artifactバージョンの参照IDと専用メタデータを突合する。専用本文APIを呼ばない |
| 大きな一覧 | 複数ページを実際に確認し、最後のhas_more=falseまでの保存を確認する |
| 中断・再開 | 検証用の保護された保存先・実行環境で停止を試し、同じコマンドで再開する。確定済み監査IDを二重保存しない |
| 同時起動 | 2つ目の起動が6で終わる。異常終了後の残存ロックファイルで再開が妨げられない |
| 保存失敗・不整合 | 複製した検証用データで権限・容量・不整合を試す。本番の正常データを壊して試さない |
| 監視 | 収集タスクを起動しない場合も、別の確認で古い成功時刻を検知できる |

保存先は固定なので、破損・中断の試験は本番とは別のWindows検証環境で同じパスを用いて行ってください。

本一式にはテスト用コード・サンプルデータ・補助スクリプトは含めていません。ローカルの静的点検は、上記のAPI連携試験やWindows上の動作試験の代わりではありません。

## 18. 参照した公式資料

以下は**2026年9月16日**に確認した公式資料です。API仕様はその後変更される可能性があります。実運用開始・更新時に再確認してください。リンク先の例示値を実データやキーとして使っていません。

### Anthropic / Claude公式

| ID | 資料 | URL |
|---|---|---|
| A1 | Set up the Compliance API | https://platform.claude.com/docs/en/manage-claude/compliance-api-access |
| A2 | Query the Activity Feed | https://platform.claude.com/docs/en/manage-claude/compliance-activity-feed |
| A3 | Design your compliance integration | https://platform.claude.com/docs/en/manage-claude/compliance-integration-patterns |
| A4 | Retrieve and delete chats, files, and projects（読み取り部分だけ使用） | https://platform.claude.com/docs/en/manage-claude/compliance-content-data |
| A5 | List chats | https://platform.claude.com/docs/en/api/compliance/apps/chats/list |
| A6 | Get chat messages | https://platform.claude.com/docs/en/api/compliance/apps/chats/messages/list |
| A7 | List projects | https://platform.claude.com/docs/en/api/compliance/apps/projects/list |
| A8 | List project attachments | https://platform.claude.com/docs/en/api/compliance/apps/projects/attachments/list |
| A9 | Get project | https://platform.claude.com/docs/en/api/compliance/apps/projects/retrieve |
| A10 | Get project document | https://platform.claude.com/docs/en/api/compliance/apps/projects/documents/retrieve |
| A11 | Get file metadata | https://platform.claude.com/docs/en/api/compliance/apps/chats/files/retrieve |
| A12 | Get generated file metadata | https://platform.claude.com/docs/en/api/compliance/apps/chats/generated_files/retrieve |
| A13 | Get artifact metadata | https://platform.claude.com/docs/en/api/compliance/apps/artifacts/retrieve |
| A14 | Handle Compliance API errors | https://platform.claude.com/docs/en/manage-claude/compliance-errors |
| A15 | Compliance API FAQ | https://platform.claude.com/docs/en/manage-claude/compliance-faq |
| A16 | Configure custom data retention controls for Enterprise plans | https://support.claude.com/en/articles/10440198-configure-custom-data-retention-controls-for-enterprise-plans |
| A17 | Removed users' data | https://support.claude.com/en/articles/12053672-what-happens-to-a-user-s-data-when-they-are-removed-from-a-team-or-enterprise-organization |
| A18 | Use incognito chats | https://support.claude.com/en/articles/12260368-use-incognito-chats |
| A19 | Activity list API reference（organization_idsはorg_形式とUUIDを許容する旨を確認） | https://platform.claude.com/docs/de/api/http/compliance/activities/list |

A19の大きな全スキーマを完全に精査したという意味ではありません。実装で使う時間条件・順序・ページング・ページサイズはA2/A3、UUIDの受理は公式リファレンスの当該パラメータ記載で確認しています。未知のActivity種別を一覧から列挙して固定する実装にはしていません。

### Microsoft公式

| ID | 資料 | URL |
|---|---|---|
| M1 | PowerShell support lifecycle | https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6 |
| M2 | WindowsへのPowerShellのインストール | https://learn.microsoft.com/ja-jp/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6 |
| M3 | about_Environment_Variables | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.6 |
| M4 | icacls | https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/icacls |
| M5 | New-ScheduledTaskSettingsSet | https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset?view=windowsserver2025-ps |
