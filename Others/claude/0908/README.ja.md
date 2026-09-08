# Claude Enterprise Compliance Collector — 導入・運用手順

資料確認日: **2026年9月8日（日本時間）**

## 0. 最初に確認すること

`Collect-ClaudeCompliance.ps1` が省略なしの収集スクリプトです。Windows / **PowerShell 7.6 LTS** / ローカルNTFSのCドライブを対象とします。Windows PowerShell 5.1 (`powershell.exe`) では実行しません。PowerShellの追加モジュール、Anthropic SDK、Python、データベースは不要です。[M1][M2]

本実装には再試行、排他、保存後checkpoint、更新版保存、取得制約の記録を組み込んでいます。ただし、作成環境にはPowerShell実行環境と本番テナントへの接続がなく、**Windows上の実行試験・実API接続試験は未実施**です。コードの静的点検と公式仕様の確認を行った実装であり、稼働保証・監査適合認証済み製品ではありません。まず同梱のオフライン試験、次に承認された検証組織での受入試験を実施してください。

本番キーの提示は不要です。キーをチャット、スクリプト、設定JSON、タスク引数に記載しないでください。収集対象は「各取得時点にAPIが返せる内容」です。収集前に消えた本文、APIが返さない過去の状態、全リソースを同一瞬間に凍結したスナップショットは対象・保証に含みません。

**実行完了とデータの完全性は別です。** 終了コード、監査と本文の別々の進捗、リソース別レポート、取得範囲の時刻を一緒に確認します。0件・HTTP 200・終了コード0だけでは、組織指定やAPI有効化の正しさも証明できません。

## 1. 取得範囲と使用API

すべて `https://api.anthropic.com` に対するGETです。認証は `x-api-key`、APIバージョンは `anthropic-version: 2023-06-01`。リダイレクトは許可せず、レスポンス内のURL・MCPサーバー・ファイルリンクをアクセス先として使いません。[A1][A2]

| データ | 呼び出すパス（`/v1/compliance` に続く部分） | 保存内容 |
|---|---|---|
| Activity Feed | `/activities` | Activityオブジェクト全体をJSONL |
| チャット列挙 | `/apps/chats` | 一覧のraw JSON、全ページ |
| チャット本文 | `/apps/chats/{id}/messages` | 入力、回答、返されたツール入出力、ファイル参照等を含むraw JSON、全ページ |
| プロジェクト列挙 | `/apps/projects` | 一覧のraw JSON、全ページ |
| プロジェクト詳細 | `/apps/projects/{id}` | description、instructions等を含むraw JSON |
| プロジェクト添付一覧 | `/apps/projects/{id}/attachments` | raw JSON、全ページ |
| project_doc | `/apps/projects/documents/{document_id}` | **contentを含むraw JSON** |
| アップロードファイル | `/apps/chats/files/{file_id}` | メタデータのみ |
| 生成ファイル | `/apps/chats/generated-files/{generated_file_id}` | メタデータのみ |
| Artifactの各参照版 | `/apps/artifacts/{artifact_version_id}` | メタデータのみ |

APIの根拠は[A2]〜[A14]です。`project_doc` は通常のファイル添付と区別して本文を保存します。Artifactは安定したartifact IDと版のIDが異なるため、**メッセージに現れるversion_idごと**にメタデータを要求します。アップロードファイル・生成ファイル・Artifactの `/content` は呼びません。[A7][A11][A12][A13][A14]

メタデータの列挙起点は、取得可能なチャットメッセージとプロジェクト添付一覧です。監査イベントに含まれる参照もそのままraw保存します。これらに現れないファイルや版を独立した全件一覧から発見する仕様は、この実装では確認できていません。過去に存在した全ファイル・全Artifact版の復元は保証しません。

「ファイル本体を取得しない」は別のダウンロードAPIを呼ばないという意味です。ユーザー入力、ツール引数、ツール結果などの本文に、ファイル内容やArtifact生成コードが直接含まれて返る場合、その本文は要求に従って保存します。そこで内容を削ると、raw保存およびツール入出力の保存要件と両立しません。

### 組織、退職者、シークレットチャット

`OrganizationUuids` に**収集対象の実際のワークロード組織UUID**を指定します。親組織のUUIDを一つ指定すれば配下が自動展開される、という動作にはしません。複数組織は複数UUIDを明示します。表示名やユーザーID、`org_...` とUUIDの推測変換はしません。管理者から正しいUUIDを受け取り、不明な場合はAnthropicサポートで確認してください。

キーには、対象組織をカバーする `read:compliance_activities` と `read:compliance_user_data` だけを付与します。`delete:compliance_user_data` と `read:compliance_org_data` は使いません。組織の一覧・設定APIを呼ばないため追加スコープは不要です。可能なら収集対象組織に限定されたキーを使用してください。[A1]

現役ユーザー一覧は一切使わず、組織全体のチャットとプロジェクトから列挙します。userがnullでも除外せず、非公開プロジェクトやシークレットチャットを除外する条件も付けません。公式にはEnterpriseのシークレットチャットはCompliance APIに含まれ、プロジェクトの作成者情報は退職・アカウント削除等でnullになり得ます。ただし、退職・削除という属性だけから個々の本文の残存を保証することはできません。[A6][A8][A15]

組織に結びつかず `organization_uuid` 等がnullになるサインイン／サインアウト等のイベントもあります。指定組織のフィルターに入らないイベントを、この実装が勝手に指定組織のものと推定して収集することはありません。親組織全体の無所属イベントまで必要な場合は、収集境界を別途決める必要があります。[A2]

## 2. Backfill / Tail の動作

### 監査イベント

Backfillは上限時刻を固定し、最初のページの `first_id` を新しい側の基点として保持します。一方、過去方向は各ページの `last_id` を `after_id` に渡し、`has_more=false` まで継続します。過去方向の途中カーソルをTailの開始位置に流用しません。[A2][A3]

Tailは保存した `tail_first_id` を `before_id` に指定します。次ページも返された `first_id` を `before_id` に渡して全ページを読み、最後のページまで保存して初めてTailの確定位置を更新します。進行中のカーソルは `activity.work` に別保存します。[A3]

反映遅延対策として、既定では上限を現在時刻の120秒前にし、さらに前回上限の10分前から今回上限までを `after_id` で再照合します。公式の「1分以上前の上限」「数分の重複窓または過去窓の再照合」「activity.idによる重複排除」に沿ったものです。**10分を超える例外的な遅延まで無条件に保証するものではありません。** 疑わしい遅延があった場合は、次回に `OverlapMinutes` を必要な期間以上へ拡大して再照合し、結果を確認してください。[A3]

途中の古い取得窓を再開した場合は、その窓の完了後に今回の目標時刻まで追い付きます。取得窓は固定するため、収集中に新しく生まれるイベントを無限に追いかけません。

### 本文

**本文のTailは「全件再照合＋同一レスポンスのハッシュ重複排除」です。変更分だけをAPIで取得する方式ではありません。** 毎回、対象組織のチャットとプロジェクトを全ページ列挙して、各本文を取り直します。変更のあったIDも取り直し、過去の保存版は残します。

理由は、本文の変更やproject_docの変更が、すべて親のupdated_atや監査イベントへ確実に伝播するかについて、完全な保証を確認できないためです。updated_atを使う差分取得自体は公式にありますが、それだけで子本文のすべての変更を検出できると推定しません。[A4][A6]

チャット一覧・メッセージは `last_id → after_id`、プロジェクト一覧・添付一覧は `next_page → page` で、各 `has_more=false` まで読みます。本文の処理キューはcheckpointに保存し、一つのチャット／プロジェクトの必要なページと参照メタデータを処理した後に、そのリソースの結果レポートを作ります。[A6][A7][A8][A10]

列挙開始時点の作成日時上限を固定し、処理途中で生まれるリソースは次の照合で拾います。再開した古い照合が終わった場合は、今回の目標時刻で新しい照合を一巡させます。ただし本文はページごとの取得時点の内容であり、一括スナップショットではありません。

この方式は呼び出し回数が多くなります。おおよその呼び出し数は「一覧ページ＋全チャットのメッセージページ＋全プロジェクト詳細／添付ページ＋全project_doc＋参照ファイル／版のメタデータ＋監査ページ」です。同じ参照が別ページに現れる場合など、メタデータを再取得することもあります。日次で一巡できる規模か受入試験で測定してください。

## 3. 保存と再開の仕組み

```text
C:\ClaudeComplianceCollector\
  bin\                         スクリプト
  config\collector.config.json
  collector.lock
  data\raw\YYYY\MM\DD\<連番_GUID>\activities_YYYYMMDD.jsonl
  data\content\YYYY\MM\DD\<連番_GUID>\response.json
  data\reports\YYYY\MM\DD\<連番_GUID>\report.json
  state\checkpoint.json
  state\status.json
  logs\run_YYYYMMDD.txt
  logs\error_YYYYMMDD.txt
  logs\runs\<run_id>.json
  staging\
```

日付は**取得時の日本時間**です。イベント発生日ではありません。各保存単位のフォルダーには `receipt.json` も保存されます。

ユーザー指定の例とは異なり、日付フォルダー直下に一つのJSONLを追記するのではなく、日付の下に保存単位ごとの小さなJSONLを置きます。追記途中の破損行を保存済みと誤認しないための設計です。一日の監査を読むときは、その日付配下を再帰的に列挙します。重複しかなかったページや0件のページは、データファイルを追加せずreceiptに取得結果を記録します。

本文レスポンスは受信したUTF-8のJSONバイト列をそのまま保存します。Activityは各オブジェクトのrawテキストを使用し、JSONLのため文字列外の改行だけを除きます。APIデータを `ConvertTo-Json` へ通しません。未知のtypeや追加フィールドも残ります。`System.Text.Json` の読取り深さ上限は2048で、超過や解析失敗時は切り詰めずエラー終了します。非常に大きなレスポンスを保持できるメモリがなければ、その位置を未完了のまま停止します。

保存は「stagingに本文とreceiptを書き、Flushする → 同じCドライブの保存先へフォルダーを公開 → checkpointを置換」の順です。receiptには取得時刻、要求パス・パラメーター、request-id、ページ情報、制約、保存ファイルのSHA-256を持たせます。receiptも連番と前receiptのハッシュで連結しています。

起動時に全receiptと実ファイルの存在・ハッシュを検証し、監査IDの集合と本文レスポンスの索引を再構築します。保存は済んだがcheckpoint更新前に停止した場合、古い位置を読み直して重複排除します。未完成のstagingは保存済みと数えません。checkpointが保存済みデータより先にある、履歴が途中で欠けている、ファイルが改変されている場合は止まります。

監査は全保存日を通じて `activity.id` を一意キーにします。本文は「取得パス＋rawバイト列のSHA-256」で同一保存物を再利用します。同じリソースIDでも内容が異なれば新規保存です。同じ内容の再取得でも新しいreceiptを残し、過去payloadへの参照を保持します。日付を指定して本文を取り出す際も、その日のreceiptの `payload_ref` をたどってください。参照先は前日のフォルダーの場合があります。

これはデータベースを追加しない代わりに、毎回過去ファイルを検証する方式です。履歴が巨大になると起動時I/O・ファイル数・監査ID集合のメモリが負荷になります。古いフォルダーだけを移動・削除して負荷を下げると、検証や参照が壊れます。アーカイブ保持方法を変更する場合は実装変更・移行が必要です。ハッシュ連鎖は破損検知用であり、管理者による書換えに対する電子署名、WORM、法的な証拠能力の保証ではありません。

## 4. 実行環境と保存先を準備する

### 4.1 PowerShellとアカウント

Microsoft公式手順からPowerShell 7.6 LTSのサポートされる最新パッチをインストールします。[M1][M2]

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command '$PSVersionTable.PSVersion'
```

以後、通常運用は専用のWindowsアカウントで行います。例は `CONTOSO\svc_claude_collect` です。自社の実在するアカウントに置き換えてください。管理者権限は初期配置／権限設定時だけに使い、収集タスクに常時管理者権限を与える必要はありません。タスクアカウントについて、組織ポリシーの「バッチジョブとしてログオン」、パスワード期限、プロキシ・外向きHTTPSを管理者が確認してください。

### 4.2 保存先とACL（管理者として実行）

**まだ存在しない保存先**を作る例です。既存環境のACLを無条件に置き換えないよう、既存なら停止します。SYSTEM・Administratorsはフル、実行アカウントはbin/configに読取り、data/state/logs/stagingに変更権限を持たせます。`icacls`の継承・付与オプションはMicrosoft公式資料を参照しています。[M4]

```powershell
$ErrorActionPreference = 'Stop'
$Root = 'C:\ClaudeComplianceCollector'
$Account = 'CONTOSO\svc_claude_collect'   # 実在する実行アカウント
if (Test-Path -LiteralPath $Root) {
    throw '保存先が既に存在します。既存データとACLを確認してから管理者が判断してください。'
}
New-Item -ItemType Directory -Path $Root | Out-Null
& icacls.exe $Root /inheritance:r /grant:r `
    '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' "${Account}:(OI)(CI)(RX)"
if ($LASTEXITCODE -ne 0) { throw 'Root ACL設定失敗' }

foreach ($Name in @('bin','config','data','state','logs','staging')) {
    New-Item -ItemType Directory -Path (Join-Path $Root $Name) | Out-Null
}
foreach ($Name in @('data','state','logs','staging')) {
    & icacls.exe (Join-Path $Root $Name) /grant:r "${Account}:(OI)(CI)(M)"
    if ($LASTEXITCODE -ne 0) { throw "ACL設定失敗: $Name" }
}
[IO.File]::WriteAllBytes((Join-Path $Root 'collector.lock'), [byte[]]::new(0))
& icacls.exe (Join-Path $Root 'collector.lock') /grant:r "${Account}:(M)"
if ($LASTEXITCODE -ne 0) { throw 'ロックファイルACL設定失敗' }
```

一般利用者がdataを読めず、実行アカウントがdataへ作成・読取り・リネーム・削除でき、bin/configは変更できないことを確認してください。例のSIDはローカライズされたグループ名への依存を避けるためです。ACL設定失敗のまま進めないでください。

アーカイブは平文のJSONです。チャット本文、個人情報、認証情報がユーザー入力に含まれていた場合も保存され得ます。端末保護、ディスク暗号化、バックアップ暗号化、監査担当者の限定は組織の方針で実施してください。同期フォルダー、共有フォルダーへの置換、ジャンクションは使わないでください。

### 4.3 ファイル配置

管理者が同梱の3つの `.ps1` を `bin`、設定JSONを `config` にコピーします。

```powershell
# カレントディレクトリが配布ZIPを展開したフォルダーである例
Copy-Item .\Collect-ClaudeCompliance.ps1 C:\ClaudeComplianceCollector\bin\
Copy-Item .\Check-ClaudeComplianceHealth.ps1 C:\ClaudeComplianceCollector\bin\
Copy-Item .\Test-CollectorOffline.ps1 C:\ClaudeComplianceCollector\bin\
Copy-Item .\collector.config.json C:\ClaudeComplianceCollector\config\
```

配布物をレビューし、社内の署名・実行ポリシーに従ってください。無条件な `ExecutionPolicy Bypass` やマシン全体の制限解除は行いません。ダウンロードのブロック解除が必要な環境では、確認済みの該当ファイルだけを対象に管理者が `Unblock-File` を実行します。

## 5. 環境変数の設定

**タスクスケジューラで指定するのと同じ実行アカウント**でPowerShell 7.6を起動して実行します。別の管理者アカウントでUser環境変数を設定しても、実行アカウントには設定されません。[M3][M6]

```powershell
# 現在のWindows実行アカウント名だけを確認。キーは表示しない。
[Security.Principal.WindowsIdentity]::GetCurrent().Name

$SecureKey = Read-Host 'Compliance Access Keyを入力' -AsSecureString
$Pointer = [IntPtr]::Zero
try {
    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
    [Environment]::SetEnvironmentVariable(
        'ANTHROPIC_COMPLIANCE_ACCESS_KEY',
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer),
        [EnvironmentVariableTarget]::User
    )
}
finally {
    if ($Pointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
    }
    $SecureKey.Dispose()
}
# True/Falseだけを確認する。
-not [string]::IsNullOrWhiteSpace(
    [Environment]::GetEnvironmentVariable(
        'ANTHROPIC_COMPLIANCE_ACCESS_KEY', [EnvironmentVariableTarget]::User
    )
)
```

スクリプトの既定値は `KeyEnvironmentScope: "User"` です。起動ごとにUserスコープを明示して読み取るため、古い親プロセスから継承された環境変数だけには依存しません。[M6]

User環境変数はWindowsレジストリに永続化されますが、秘密保管庫ではありません。実行アカウントや管理者から読めます。Machineスコープに広く公開する構成は使っていません。Anthropic自体はCompliance Access Keyの秘密管理サービスでの保管を推奨しています。本要件では環境変数方式なので、その制約を認識して専用アカウントを保護してください。[A1][M3]

`Process`も指定できますが、そのプロセスへ安全にキーを供給する仕組みが別途必要です。初心者向けの日次タスクではUserのままにします。キー更新時は同じ実行アカウントでこの手順をやり直し、次の収集が成功した後に旧キーを失効させます。カーソルはキー更新をまたいで使える公式仕様です。[A1]

## 6. 設定ファイル

`C:\ClaudeComplianceCollector\config\collector.config.json` の `REPLACE_WITH_ORGANIZATION_UUID` を実際のUUIDへ置き換えます。未変更ならエラー停止します。キーそのものは書きません。

```json
{
  "OrganizationUuids": ["REPLACE_WITH_ORGANIZATION_UUID"],
  "KeyEnvironmentVariable": "ANTHROPIC_COMPLIANCE_ACCESS_KEY",
  "KeyEnvironmentScope": "User",
  "RequestsPerMinute": 120,
  "ActivityPageSize": 1000,
  "ChatPageSize": 100,
  "MessagePageSize": 20,
  "ProjectPageSize": 100,
  "LagSeconds": 120,
  "OverlapMinutes": 10,
  "MaxRetries": 6,
  "TimeoutSeconds": 120,
  "MaxRunMinutes": 1200
}
```

120 requests/min、リトライ6回、タイムアウト120秒、実行上限20時間は**この実装の既定値**で、公式の推奨値や全組織での適正値ではありません。

公式レート制限は、ここで使うCompliance APIについて**親組織あたり600 requests/min、キー・リンク組織・エンドポイント間で共有**です。本実装は全GETを直列にし、設定した間隔と応答のrate-limitヘッダーに従います。ほかの収集ツールも使う場合は、合計が公式枠を超えないよう各運用者で予算を割り当ててください。このスクリプトは他プロセスの送信を止められません。上限近くまで上げる前に他の利用を確認します。[A3][A5]

ページサイズの公式上限は監査5000、チャット1000、メッセージ1000、プロジェクト／添付100です。MessagePageSizeを小さめにして、切り詰めを解除したツール入出力による大きな応答に備えています。[A2][A6][A7][A8][A10]

進行中のページの要求条件はcheckpointに保持します。設定値を変更しても、すでに保存されているキューのページサイズ等は即座には変わりません。新しい照合で新設定が使われます。処理停止の原因が特定の巨大な保留レスポンスなら、メモリ確保や承認されたコード修正を検討し、checkpointを無造作に書き換えないでください。

対象組織の組合せを変えるとcheckpoint整合性チェックで止まります。同じアーカイブの途中で対象を黙って切り替えないためです。対象変更には、既存収集の保全と承認された移行手順が必要です。

## 7. 実行と日次タスク

### 7.1 最初にオフライン試験

実行アカウントで、別プロセスのPowerShellから実行します。実キーは使用せず、実APIにも本番保存先にも書き込みません。テスト用ファイルは `%TEMP%\ClaudeCollectorTest_<GUID>` に作成します。疑似HTTPはメモリ内ハンドラーで処理します。

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive `
  -File 'C:\ClaudeComplianceCollector\bin\Test-CollectorOffline.ps1'
$LASTEXITCODE
```

テストは実スクリプトの構文解析、深いJSON／長文の保存、同一本文と更新本文、checkpoint未更新状態からの索引再構築、監査の複数ページ前後方向と重複排除、各本文ページ方式、project_doc／版ID、429／401／403／529／再試行上限、破損検知を確認します。**同梱されていることは試験済みという意味ではありません。作成環境では実行できていません。** 結果0と各PASSを確認し、不合格なら本番収集へ進めないでください。

### 7.2 Backfill

実行アカウントのPowerShellから次を実行します。

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive `
  -File 'C:\ClaudeComplianceCollector\bin\Collect-ClaudeCompliance.ps1' `
  -Mode Backfill `
  -ConfigPath 'C:\ClaudeComplianceCollector\config\collector.config.json'
$LASTEXITCODE
```

途中停止・上限到達後も同じBackfillコマンドを再実行します。完了した監査の初回過去取得をゼロからやり直さず、監査の追い付きと本文の保留キューを再開します。最初の監査取得が長時間なら、その間本文取得に入らないことにも注意し、保持期限との関係を受入時に確認してください。

### 7.3 Tail

監査の `backfill_done=true` と本文の `initial_done=true` が揃った後、Tailへ切り替えます。初回未完了ならTailはエラー停止し、Backfill継続を求めます。

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive `
  -File 'C:\ClaudeComplianceCollector\bin\Collect-ClaudeCompliance.ps1' `
  -Mode Tail `
  -ConfigPath 'C:\ClaudeComplianceCollector\config\collector.config.json'
$LASTEXITCODE
```

### 7.4 タスクスケジューラ（例: 毎日02:00 JST）

「基本タスク」ではなく「タスクの作成」で設定します。実行PCのタイムゾーンを確認し、JST以外なら02:00 JSTに対応する時刻を設定してください。保存日のJST判定はPCのタイムゾーンに依存しません。

| 設定箇所 | 値 |
|---|---|
| 名前 | `ClaudeComplianceCollector-Tail` |
| 実行ユーザー | 環境変数を設定した専用アカウント |
| ログオン条件 | ユーザーがログオンしているかどうかにかかわらず実行する。必要な資格情報を登録 |
| 権限 | 「最上位の特権で実行する」は通常不要 |
| トリガー | 毎日、02:00 JST相当 |
| プログラム | `C:\Program Files\PowerShell\7\pwsh.exe` |
| 引数 | `-NoLogo -NoProfile -NonInteractive -File "C:\ClaudeComplianceCollector\bin\Collect-ClaudeCompliance.ps1" -Mode Tail -ConfigPath "C:\ClaudeComplianceCollector\config\collector.config.json"` |
| 開始（オプション） | `C:\ClaudeComplianceCollector\bin` |
| スケジュールを逃した場合 | 実行可能になったらすぐに実行する |
| 既に実行中の場合 | **新しいインスタンスを開始しない（IgnoreNew）** |
| 強制停止上限 | 例: 23時間。内部の20時間上限より長くする |

IgnoreNewはMicrosoft公式の設定です。[M5] さらにスクリプトが保存先の `collector.lock` を排他的に開くため、別タスクや手動のBackfill/Tailも同じ保存先へ同時収集できません。ロックファイルが存在するだけではロック中ではありません。プロセス終了でハンドルが解放されるので、残ったファイルを削除しないでください。

初回はタスクの「実行」を使い、**ログオフ状態でも**環境変数・ネットワーク・ACL・終了コードを確認します。電源・スリープ・アイドル条件でタスクが実行されない設定になっていないかも確認します。タスクの起動失敗時にはスクリプト側のログは作れないため、後述の独立監視が必要です。

## 8. 終了コード、エラー、再実行

| 収集スクリプトの終了コード | 意味と対応 |
|---|---|
| 0 | 今回目標の監査窓と本文照合が完了し、検出した本文gapは0。APIが返さないデータの不存在や履歴全体の完全性を証明しない |
| 1 | 認証・権限、非再試行APIエラー、リトライ上限、JSON、I/O、整合性等で停止。ログ確認後に同じモードで再実行 |
| 2 | 照合は完了したが取得不能・切り詰め等のgapあり。レポートを確認。削除済み本文など要件上許容する除外もここに含まれ得る |
| 3 | 内部実行時間上限等による未完了終了。同じモードで再開 |
| 4 | 他の処理が同じ保存先を使用中のため未実行。既存処理を確認 |

通信エラー、タイムアウト、408、通常の再試行可能な500／502／503／504／529は、同じ要求位置から上限付きで再試行します。指数バックオフに小さな揺らぎを加えます。429は秒数の `retry-after` を優先し、欠落・不正ならバックオフします。待機期限はcheckpointへ保存し、上限終了しても次回はその期限まで要求しません。待機だけを記録するときに本文や監査のカーソルは進めません。[A5]

`x-should-retry` がtrue/falseなら、その指示を優先します。ただし401/403は認証・権限エラーとして再試行せず停止します。404は個別本文・メタデータについて取得不能レコードを残しますが、一覧／監査APIの404は取得範囲そのものを列挙できないため停止します。404だけから「削除」「別組織」「存在しない」のいずれかを断定できない場合、理由は `http_404_cause_not_distinguishable` です。[A5]

エラーにはHTTPステータス、エラーtype、対象ID、request-id、試行回数、例外型／HResult／スクリプト行番号等を記録します。APIのerror.message全文やPowerShellの例外全文は、秘密や本文を反映する危険を避けて出力しません。詳細なサーバー側理由が必要な場合はrequest-idでAnthropicへ照会してください。ログには認証ヘッダー、キー、チャット本文を出しません。

I/O・JSON失敗時は対象の進捗を確定しません。最後のログ保存まで失敗するディスク不足では、標準エラーと終了コード以外に記録できない可能性があります。そこで、タスクの最終結果と独立監視も確認します。

401/403ならキーの失効・スコープ・組織範囲を管理画面で確認します。スコープは作成後に変更できないため、不足なら必要な二つのreadスコープを持つキーを新規発行し、環境変数だけを更新します。[A1][A5]

ディスク不足なら未完了stagingや一時ファイルを含む現状を保全し、容量・ACLを修復して同じコマンドを実行します。**dataやcheckpointを削除して強制的に正常化しないでください。** 破損・連鎖不一致では整合したバックアップから復元し、原因を調査します。stagingの残骸整理は収集停止と保全後に行い、完成データやreceiptを巻き込まないようにします。

## 9. 実行ログと監視

通常ログは `logs\run_YYYYMMDD.txt`、エラー／制約の詳細は `logs\error_YYYYMMDD.txt` にも書きます。拡張子はtxtですが、一行ごとにJSON形式なので機械集計できます。開始・終了、モード、開始／終了checkpointの要約、request-id、件数、再試行、未完了状態を記録します。preflight失敗と重複起動は、それぞれ固有名のtxtに記録する場合があります。

### 件数の単位

`activity_received/saved/duplicates` はイベント件数です。`body_responses_received/saved/body_response_duplicates` は**APIレスポンス単位**で、一覧・メタデータも含みます。`chat_messages_received` は返されたメッセージ行数、`chat_messages_in_new_responses` は新規保存レスポンス内の行数です。いずれも一意メッセージIDの総数とは限りません。`chats_walked/projects_walked/project_docs_received` も併せて確認します。

`unavailable_responses` は個別404応答数、`gap_findings` は削除・欠落・切り詰め等の指摘数、`warning_findings` は警告数です。異常終了時の保留ジョブも確認してください。`errors` はエラー発生・試行のカウントで、再試行が成功したエラーも含みます。これらは異なる単位なので、足して「未取得リソース数」とは扱いません。

### 成功時刻の意味

| checkpoint項目 | 意味 |
|---|---|
| `activity.last_success_utc` | 監査の前方向＋再照合窓を保存し終えた時刻 |
| `activity.last_window_upper` | 監査の確定した上限時刻 |
| `body.last_sweep_utc` | 本文の列挙と必要取得を一巡し、結果を記録した時刻。gapを含む場合あり |
| `body.last_sweep_cutoff_utc` | その本文照合の列挙作成日時上限。本文の同時点スナップショット時刻ではない |
| `body.last_sweep_gaps` | 直近照合の検出gap数 |
| `body.last_no_gap_utc` | 検出gapなしで本文照合が終わった最後の時刻 |
| `last_no_gap_success_utc` | 監査と本文が今回完了し、本文の検出gapが0だった最後の時刻 |

`state\status.json` は直近終了した実行のまとめです。開始中に前回statusを上書きしないため、statusがあるだけで現在の実行が終わったとは扱いません。途中の状態はcheckpointと開始ログ、タスク状態を参照します。強制停止なら終了ログがない場合があります。

### タスク未起動を含む停止検知

同梱の監視スクリプトはAPIキー不要です。収集タスクとは独立して、たとえば1時間ごとに既存の監視エージェントまたは別の監視サーバーから実行します。

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive `
  -File 'C:\ClaudeComplianceCollector\bin\Check-ClaudeComplianceHealth.ps1' `
  -MaxAgeHours 36
$LASTEXITCODE
```

監視スクリプトは収集とは別の終了コード体系です。0=新しい完了記録あり、2=新しい完了記録はあるが既知gapあり、3=古い／未完了等、1=状態を読めない・壊れている、です。監視基盤で0以外を通知対象にし、2を「内容制約」、1/3を「収集・監視障害」と分けます。36時間は例であり、実行所要時間と要求SLAで決めます。

**監査の成功時刻だけを監視しません。** 本文の完了時刻と対象期間の古さも見ます。古い本文照合が長期間かかり、終了したばかりでも対象上限が古い場合は検知します。タスクを意図的に無効化し、しきい値超過後に警報となることを試験してください。

別ホストからは、stateだけを公開した専用の読取り専用共有や既存エージェントで監視します。監視ユーザーにraw本文やキーへのアクセスを付与する必要はありません。共有の作成・ファイアウォール・資格情報管理は既存の監視運用へ合わせます。収集ホストだけで収集と監視を実行すると、そのPC自体の停止を通知できないため、ホスト死活監視も外部に置いてください。

0件が続く場合はAPIの有効化、対象UUID、テナント範囲も確認します。APIが無効な期間の活動は後から復元できず、単に200の空一覧が返ったことを正しい範囲の証明にはできません。[A1]

## 10. 本番前の受入試験

破壊的な試験は本番のCドライブや本番データで行わず、検証VMと承認された検証組織で実施します。オフラインテストはあくまで内部処理の試験で、API仕様・実際の権限・NTFSの障害時挙動を代替しません。

| 試験 | 手順と合格基準 |
|---|---|
| 実際の組織・キー | 設定UUIDと管理者が確認した組織を照合し、既知の検証チャット／プロジェクトがrawにあることを確認。対象外組織が混ざらない |
| 全ページ | 新規の検証アーカイブで4種類のPageSizeを1にし、2件以上のチャット・プロジェクト、複数メッセージ・複数project_docを作成。各receiptのhas_moreと次要求を追い、最後がfalseになることを確認 |
| Tailの複数ページ | Backfill後、ページ数を超えるイベントと新規／更新本文を作る。保存tail_first_idからbefore_idで複数ページ進むこと、本文も全部読むことを確認 |
| project_docとファイル除外 | プロジェクトの説明・指示・文書に固有の検証文字列を設定。doc contentは保存され、project_fileはメタデータだけで、要求パスに末尾/contentがない |
| Artifactの複数版 | Artifactを更新して二つ以上のversion_idを作る。メッセージの参照を保持し、参照された各version_idのメタデータがあることを確認 |
| 長文・深いJSON | オフライン試験を実行。実APIでも長いツール入出力を含む承認済み検証会話を使い、-1の指定、truncatedフラグ、保存バイト列を確認 |
| 通常の途中停止 | MaxRunMinutesを短くしてコード3で止め、checkpointの保留ジョブと保存結果を記録。同じモードで再開し、完了することを確認 |
| 強制停止 | 検証VMで収集中の対象pwshプロセスだけを停止。再実行時にstagingを完成扱いせず、公開済みファイルを確認して未保存位置から再開する |
| 更新本文・過去版 | 同じチャットに追記し、同じプロジェクトの説明・指示・同一docを変更してTail。新しいSHAのpayloadが増え、古いpayloadとハッシュが変わらない |
| 日またぎ重複 | 翌日にTailまたは重複窓を広げた再取得。全rawを通じてactivity.idの重複が0で、receiptには再取得件数が残る |
| 退職者・シークレット | 検証用アカウントで通常／シークレット会話を作り、承認の上で組織から削除。APIが提供するものが組織列挙から収集され、user=nullでも落ちない。APIが返さない場合は残存を推定しない |
| 取得不能 | 検証会話を削除、または疑似404を使用。対象IDと理由がレポートにあり、監査保存の成功だけで本文保存済みにならない |
| 認証・レート | オフラインの疑似429／401／403／529／500の再試行試験を使う。本番APIへ大量送信して故意に429を起こさない |
| ディスク・ACL | 検証VMでのみ書込み拒否／容量不足／強制停止を試す。保存失敗の対象のcheckpointが進まない。正常な環境に戻して再開する |
| 破損 | 保全した検証アーカイブのpayloadを改変し、ハッシュ検証で停止することを確認。改変後のcheckpointを手編集して通さない |
| 排他 | Backfill実行中に別のBackfill/Tailを起動し、後発が4で終了、既存処理が継続、dataに並行変更がない |
| 日次タスクと停止監視 | ログオフ状態からタスク実行。さらにタスク停止・ホスト到達不能で外部監視が検知する |
| 容量・所要時間 | 実際に一巡した呼び出し数・保存増分・起動検証時間・メモリを測り、日次枠に入ることを確認 |

監査IDの重複チェック例です。本文を標準出力に出しません。大規模履歴ではメモリを使うため、検証用アーカイブまたは十分なメモリの監査端末で実施してください。

```powershell
Add-Type -AssemblyName System.Text.Json
$Ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$Duplicates = 0L
$Options = [Text.Json.JsonDocumentOptions]::new()
$Options.MaxDepth = 2048
Get-ChildItem 'C:\ClaudeComplianceCollector\data\raw' -Recurse -Filter 'activities_*.jsonl' -File |
  ForEach-Object {
    foreach ($Line in [IO.File]::ReadLines($_.FullName)) {
      $Doc = [Text.Json.JsonDocument]::Parse($Line, $Options)
      try {
        if (-not $Ids.Add($Doc.RootElement.GetProperty('id').GetString())) { $Duplicates++ }
      } finally { $Doc.Dispose() }
    }
  }
[pscustomobject]@{ UniqueActivityIds = $Ids.Count; DuplicateActivityIds = $Duplicates }
```

## 11. 取得できないもの・未確認事項

| 項目 | 扱い |
|---|---|
| 収集前に削除・保持期限超過・hard-deleteされた本文 | 復元対象外。削除マーカーや404で分かった範囲を記録。既にローカル収集済みの過去版は残す |
| APIが返さないツール結果の非テキスト要素 | 公式に画像・リンク等の一部要素は省略される。生成ファイル参照は保存するがファイル実体は取得しない |
| ツール入出力の切り詰め | 既定の10000文字制限を両方-1にして解除要求。truncated=trueが残れば対象IDをgapとして記録 |
| endpointが課すその他の最大長 | すべての数値上限・例外条件は**不明**。-1だけであらゆる上限が消えると保証しない |
| reasoningの非公開部分 | APIが除去しthinking_redacted=trueとする場合は警告。モデル内部の非公開推論を復元しない |
| サーバーの通知なしの欠落 | クライアント側での網羅的検知は**不明／保証不可**。API応答に総件数・全体checksumはなく、列挙完了をもってAPI外の完全性までは証明しない |
| doc等の更新が親updated_atへ必ず伝わるか | 全更新種類に対する保証は**不明**。その前提を使わず全件再照合 |
| 同時更新・ページ移動中の完全な一点スナップショット | 保証仕様は**不明**。収集時刻とページを残し次回再照合する |
| 対象組織の現在の保持設定・API有効状態 | このキーで設定APIを読まないため**不明**。管理者がUIで確認 |
| 列挙に現れないリソースの存在・権限外データ | **不明**。アクセス範囲外の本文を取得できたとはしない |
| 未知の添付種別 | 一覧rawは保存し、識別子とunknown_attachment_type_saved_reference_onlyをgapとして記録。未確認の本文APIを推測しない |
| Claude Code／Cowork等のセッション専用API | 本件のチャット／プロジェクトの本文取得とは別のため未実装。監査イベント内に含まれる場合は監査rawとして保存 |

根拠は[A3][A4][A5][A7]です。日次の間に作られ、その日の収集前に消える本文は捕捉できません。本件の削除前復元要件からは除外されていますが、将来その捕捉も必要になれば日次収集だけでは満たせません。

## 12. 保持期間、組織設定、バックアップ

Activity Feedは公式に6年間保持されます。ただし記録はCompliance API有効化後からで、過去へ遡って新規記録されません。APIを無効にした間の未記録活動も後から取り戻せません。[A1][A2]

本文は組織の保持方針とユーザー削除等に依存します。Enterpriseのカスタム保持は最低30日、通常は設定しなければ無期限ですが、**シークレットチャットは通常会話と分けて確認**します。シークレットの公式説明は30日またはより長い組織保持方針です。[A15][A16]

通常チャットの保持起点は最後のメッセージ、プロジェクトは最後の更新です。プロジェクトの保持設定が内部チャットに優先し得ます。保持期間を短縮すると保存時点で範囲外データが直ちに削除され、復元できません。管理者はData and Privacyの実設定、API有効化状態、ユーザー削除の扱いを収集前に確認してください。[A16]

**Cドライブ内だけではバックアップになりません。** `data`、`state`、`logs`、`bin`、`config`を、別ディスク・別ホスト・組織管理のバックアップ先へ世代付きで保全してください。キーはアーカイブとは分離した承認済みの秘密管理方法で再発行・復旧できるようにします。

整合性の取れたバックアップを作るには、タスクの新規起動を止めて収集プロセス終了を確認してから一式を保全するか、組織で検証済みの整合したスナップショット／バックアップ製品を使用します。checkpointだけを先の時点で、dataを古い時点で復元すると安全側に停止します。stateだけのバックアップでは本文は戻りません。

復元試験は別の検証ホストで、バックアップからデータとstateの整合性検証が通ること、同じ位置から再開できること、権限が維持されることを確認します。日付フォルダー間のpayload参照があるため、古い日のdataも必要です。無条件のミラー削除、古い版の自動削除は採用していません。追加の保管期限・WORM要否・アクセス監査は組織の情報管理方針で決めてください。

## 13. 参照した公式資料

以下はすべて **2026年9月8日確認**。Anthropic公式ドキュメント／公式Help CenterとMicrosoft公式ドキュメントのみです。資料更新時は、とくにレスポンス形状・ページ送り・切り詰め・レート制限・保持を再確認してください。

### Anthropic

- [A1] Set up the Compliance API — https://platform.claude.com/docs/en/manage-claude/compliance-api-access
- [A2] Query the Activity Feed — https://platform.claude.com/docs/en/manage-claude/compliance-activity-feed
- [A3] Design your compliance integration — https://platform.claude.com/docs/en/manage-claude/compliance-integration-patterns
- [A4] Retrieve and delete chats, files, and projects — https://platform.claude.com/docs/en/manage-claude/compliance-content-data
- [A5] Handle Compliance API errors — https://platform.claude.com/docs/en/manage-claude/compliance-errors
- [A6] List chats — https://platform.claude.com/docs/en/api/compliance/apps/chats/list
- [A7] Get chat messages — https://platform.claude.com/docs/en/api/compliance/apps/chats/messages/list
- [A8] List projects — https://platform.claude.com/docs/en/api/compliance/apps/projects/list
- [A9] Get project details — https://platform.claude.com/docs/en/api/compliance/apps/projects/retrieve
- [A10] List project attachments — https://platform.claude.com/docs/en/api/compliance/apps/projects/attachments/list
- [A11] Get project document — https://platform.claude.com/docs/en/api/compliance/apps/projects/documents/retrieve
- [A12] Get file metadata — https://platform.claude.com/docs/en/api/compliance/apps/chats/files/retrieve
- [A13] Get generated file metadata — https://platform.claude.com/docs/en/api/compliance/apps/chats/generated_files/retrieve
- [A14] Get artifact metadata — https://platform.claude.com/docs/en/api/compliance/apps/artifacts/retrieve
- [A15] Use incognito chats — https://support.claude.com/en/articles/12260368-use-incognito-chats
- [A16] Configure custom data retention controls for Enterprise plans — https://support.claude.com/en/articles/10440198-configure-custom-data-retention-controls-for-enterprise-plans
- [A17] Removed users' data — https://support.claude.com/en/articles/12053672-what-happens-to-a-user-s-data-when-they-are-removed-from-a-team-or-enterprise-organization

### Microsoft

- [M1] PowerShell Support Lifecycle — https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6
- [M2] Install PowerShell on Windows — https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6
- [M3] about_Environment_Variables — https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.6
- [M4] icacls — https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/icacls
- [M5] New-ScheduledTaskSettingsSet — https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset?view=windowsserver2025-ps
- [M6] Environment.GetEnvironmentVariable — https://learn.microsoft.com/en-us/dotnet/api/system.environment.getenvironmentvariable?view=net-10.0
- [M7] Environment.SetEnvironmentVariable — https://learn.microsoft.com/en-us/dotnet/api/system.environment.setenvironmentvariable?view=net-10.0
