以下の2ファイルを作成しました。

* [ClaudeComplianceCollector.ps1](sandbox:/mnt/data/ClaudeComplianceCollector.ps1)
* [Register-ClaudeComplianceCollectorTask.ps1](sandbox:/mnt/data/Register-ClaudeComplianceCollectorTask.ps1)

実テナントのAPIキーを使った疎通試験はこの環境では実行していません。そのため、導入前に検証用Claude Enterprise環境または限定スコープの本番キーで、後述の「初回検証手順」を必ず実施してください。スクリプト自体は、確認できたAnthropic公式ドキュメントの仕様に合わせて作成しています。

## 最重要の前提

**Activity Feedだけを取得する場合**は、Compliance Access Keyのスコープは `read:compliance_activities` のみで足ります。一方で、今回の要件にある **chat / project content を含むeDiscovery取得** を行う場合、公式仕様上 `read:compliance_user_data` が必要です。`delete:compliance_user_data` は不要なので付与しない設計にしています。Anthropic公式ドキュメントでも、Activity Feedは `read:compliance_activities`、chats / files / projects などのコンテンツ系エンドポイントは `read:compliance_user_data` が必要とされています。([Claude Platform][1])

したがって、最小権限は次のどちらかです。

| 目的                                                | 必要スコープ                                                     |
| ------------------------------------------------- | ---------------------------------------------------------- |
| Activity Feed監査ログのみ                               | `read:compliance_activities`                               |
| Activity Feed + chat / project content eDiscovery | `read:compliance_activities` + `read:compliance_user_data` |
| 削除操作                                              | 今回不要。`delete:compliance_user_data` は付与しない                  |

## 取得対象と除外対象

このスクリプトは、Activity Feedをraw JSONLで保存し、必要に応じてchat message、project metadata、project document、artifact textを取得します。Activity Feedは公式仕様で逆時系列、`first_id` / `last_id` / `has_more` を使うカーソルページング、最大 `limit=5000`、6年保持、親組織あたり600 requests/minuteという前提で実装しています。([Claude Platform][2])

添付ファイルのバイナリは保存しません。公式仕様では、chat message内の `files` や `generated_files`、project attachmentの `project_file` はファイルIDを使って別エンドポイントからバイナリ取得できますが、本スクリプトでは容量圧迫を避けるため、ファイルIDやメタデータは保存し、`/content` バイナリ取得エンドポイントは呼びません。一方、`project_doc` や artifact text はテキストコンテンツとして取得対象にしています。([Claude Platform][3])

## 保存先

既定の保存先は以下です。

```powershell
C:\ProgramData\ClaudeComplianceCollector\
```

主な出力先は次のとおりです。

```text
C:\ProgramData\ClaudeComplianceCollector\
  ClaudeComplianceCollector.ps1
  state\
    checkpoint.json
    latest_status.json
    latest_success.json
  logs\
    run_YYYYMMDD.txt
    error_YYYYMMDD.txt
    requests_YYYYMMDD.jsonl
    summary_<RunId>.json
  data\
    raw\
      activities\YYYY\MM\DD\activities_YYYYMMDD.jsonl
      chats\YYYY\MM\DD\chats_YYYYMMDD.jsonl
      chat_messages\YYYY\MM\DD\chat_messages_YYYYMMDD.jsonl
      artifacts\YYYY\MM\DD\artifacts_YYYYMMDD.jsonl
      projects\YYYY\MM\DD\projects_YYYYMMDD.jsonl
      project_details\YYYY\MM\DD\project_details_YYYYMMDD.jsonl
      project_attachments\YYYY\MM\DD\project_attachments_YYYYMMDD.jsonl
      project_documents\YYYY\MM\DD\project_documents_YYYYMMDD.jsonl
      content_missing\YYYY\MM\DD\content_missing_YYYYMMDD.jsonl
    index\
      ...
```

Activity Feedの保存例は要件に合わせ、日付単位のJSONLです。

```text
C:\ProgramData\ClaudeComplianceCollector\data\raw\activities\2026\07\07\activities_20260707.jsonl
```

## 実装済みの重要要件

スクリプトには以下を実装しています。

| 要件                       | 実装内容                                                            |
| ------------------------ | --------------------------------------------------------------- |
| PowerShell実装             | 外部モジュール不要のWindows PowerShell想定                                  |
| APIキー直書き禁止               | `ANTHROPIC_COMPLIANCE_ACCESS_KEY` 環境変数から読込                      |
| APIキーをログ出力しない            | request log / error logにもキーは出力しない                               |
| 初回取得と継続取得の分離             | `ActivityBackfill` / `ActivityTail` / `AllBackfill` / `AllTail` |
| Activity Feed checkpoint | `first_id` / `last_id` を `checkpoint.json` に保存                  |
| 継続取得                     | 保存済み `activity_first_id` を `before_id` に使用                      |
| 過去方向backfill             | 保存済み `activity_last_id` を `after_id` に使用                        |
| 保存成功後のみcheckpoint更新      | data保存 → index保存 → checkpoint更新の順序                              |
| 重複排除                     | `activity.id` を日次indexでdedupe                                   |
| 未知イベント対応                 | `activity.type` / `actor.type` を解釈せずraw保存                       |
| 通信失敗retry                | network / timeout / 5xx / 529 を同一checkpointでretry               |
| 429対応                    | `retry-after` を尊重                                               |
| 401 / 403                | APIキー不正または権限不足として即時停止                                           |
| 同時実行防止                   | Windows Mutex + lockファイル。タスクスケジューラ側も多重起動抑止                      |
| ログ出力                     | 通常ログ、エラーログ、request-idログ、summary JSON                            |
| 監視項目                     | 最終成功時刻、取得件数、重複件数、エラー件数、retry数、429数                              |
| 添付ファイル除外                 | `claude_file_*` / `claude_gen_file_*` のバイナリcontentは取得しない        |
| 削除API未使用                 | delete系エンドポイントは一切呼ばない                                           |

Anthropic公式ドキュメントでは、Activity Feedはat-least-once前提で重複の可能性があるため `activity.id` でdedupeすること、cursorは保存後に進めること、request-idや取得件数などを証跡として残すことが推奨されています。([Claude Platform][2])

## 導入手順

### 1. スクリプト配置

管理者権限のPowerShellで実行します。

```powershell
New-Item -ItemType Directory -Force "C:\ProgramData\ClaudeComplianceCollector"

Copy-Item ".\ClaudeComplianceCollector.ps1" `
  "C:\ProgramData\ClaudeComplianceCollector\ClaudeComplianceCollector.ps1" `
  -Force

Copy-Item ".\Register-ClaudeComplianceCollectorTask.ps1" `
  "C:\ProgramData\ClaudeComplianceCollector\Register-ClaudeComplianceCollectorTask.ps1" `
  -Force
```

### 2. Compliance Access Keyを作成

Claude Enterprise管理画面でCompliance Access Keyを作成します。公式ドキュメントでは、Compliance Access KeyはActivity Feed、chats、files、projects、users、metadata/settingsに利用でき、作成時にスコープを選択します。キー値は作成時に一度だけ表示されるため、秘密情報として厳重に保管してください。([Claude Platform][4])

Activity Feedのみなら以下です。

```text
read:compliance_activities
```

今回のようにchat / project contentを含むeDiscoveryまで行うなら以下です。

```text
read:compliance_activities
read:compliance_user_data
```

以下は付与しません。

```text
delete:compliance_user_data
```

### 3. APIキーをWindows環境変数に登録

スクリプトにAPIキーは書きません。タスクスケジューラで実行するアカウントから参照できるよう、Machine環境変数に保存します。

```powershell
$secret = Read-Host "Compliance Access Key" -AsSecureString

$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [Environment]::SetEnvironmentVariable(
        "ANTHROPIC_COMPLIANCE_ACCESS_KEY",
        $plain,
        "Machine"
    )
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
```

登録後、新しいPowerShellを開き、以下で存在だけ確認します。値そのものは表示しないでください。

```powershell
if ([Environment]::GetEnvironmentVariable("ANTHROPIC_COMPLIANCE_ACCESS_KEY", "Machine")) {
    "API key environment variable is set."
} else {
    "API key environment variable is NOT set."
}
```

## 初回検証手順

まずActivity Feedだけを少量取得できるか確認します。初回の本格backfill前に、rootを検証用フォルダに変えて実行することを推奨します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\ProgramData\ClaudeComplianceCollector\ClaudeComplianceCollector.ps1" `
  -Mode ActivityBackfill `
  -Root "C:\ProgramData\ClaudeComplianceCollector_Test" `
  -ActivityLimit 100
```

成功したら、以下を確認します。

```powershell
Get-Content "C:\ProgramData\ClaudeComplianceCollector_Test\state\latest_success.json"
Get-Content "C:\ProgramData\ClaudeComplianceCollector_Test\logs\run_$(Get-Date -Format yyyyMMdd).txt"
```

JSONLが作成されていることを確認します。

```powershell
Get-ChildItem "C:\ProgramData\ClaudeComplianceCollector_Test\data\raw\activities" -Recurse
```

chat / project contentまで含める場合は、次に以下を検証します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\ProgramData\ClaudeComplianceCollector\ClaudeComplianceCollector.ps1" `
  -Mode AllBackfill `
  -Root "C:\ProgramData\ClaudeComplianceCollector_Test" `
  -ActivityLimit 100
```

## 本番初回backfill

Activity Feedのみの場合は以下です。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\ProgramData\ClaudeComplianceCollector\ClaudeComplianceCollector.ps1" `
  -Mode ActivityBackfill
```

chat / project contentも含める場合は以下です。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\ProgramData\ClaudeComplianceCollector\ClaudeComplianceCollector.ps1" `
  -Mode AllBackfill
```

初回backfillはログ量によって長時間かかる可能性があります。途中で失敗した場合でも、保存済みcheckpointから同じ位置で再開します。API取得済みでもファイル保存・index保存・checkpoint更新の前に失敗した場合はcheckpointを進めないため、次回同じページを再取得し、`activity.id` で重複排除します。

## 1日1回の定期実行

Activity Feedのみを毎日継続取得する場合は以下です。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\ProgramData\ClaudeComplianceCollector\Register-ClaudeComplianceCollectorTask.ps1" `
  -Mode ActivityTail `
  -At "02:00"
```

chat / project contentも含めて毎日継続取得する場合は以下です。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\ProgramData\ClaudeComplianceCollector\Register-ClaudeComplianceCollectorTask.ps1" `
  -Mode AllTail `
  -At "02:00"
```

登録スクリプトは、Windowsタスクスケジューラに以下の設定でタスクを作成します。

```text
タスク名: ClaudeComplianceCollector
実行頻度: 1日1回
多重起動: IgnoreNew
実行ユーザー: SYSTEM
実行コマンド:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\ClaudeComplianceCollector\ClaudeComplianceCollector.ps1 -Mode <指定モード>
```

PowerShellスクリプト側でもMutexとlockファイルで多重起動を防ぐため、前回実行中に次回タスクが起動しても二重取得しません。

## 実行モード

| モード                | 用途                                                                       |
| ------------------ | ------------------------------------------------------------------------ |
| `ActivityBackfill` | Activity Feedの過去方向初回取得。`last_id` を `after_id` に使って `has_more=false` まで取得 |
| `ActivityTail`     | Activity Feedの継続取得。保存済み `first_id` を `before_id` に使って新しいログを取得            |
| `ContentBackfill`  | chat / project content取得。Activity Feedは取らない                              |
| `ContentTail`      | chat / project contentの継続取得。Activity Feedは取らない                           |
| `AllBackfill`      | `ActivityBackfill` + content取得                                           |
| `AllTail`          | `ActivityTail` + content取得                                               |
| `Status`           | 最新状態の表示のみ                                                                |

## レート制限対策

Anthropic公式ドキュメントでは、Compliance APIは親組織あたり600 requests/minuteで、全キー・全linked org・全Compliance endpointで共有されるとされています。各レスポンスにはrate-limit系ヘッダーが含まれ、429時は `retry-after` に従う必要があります。([Claude Platform][5])

スクリプトの既定値では、各API呼び出し間に最低250msの待機を入れています。

```powershell
-MinDelayMs 250
```

他の連携ツールも同じ親組織でCompliance APIを使う場合は、より保守的にしてください。

```powershell
-MinDelayMs 500
```

または大量環境では以下のようにします。

```powershell
-MinDelayMs 1000
```

429が発生した場合、スクリプトはcheckpointを進めず、`retry-after` 秒待機して同じリクエストを再試行します。

## 監視方法

最新の成功状態は以下で確認できます。

```powershell
Get-Content "C:\ProgramData\ClaudeComplianceCollector\state\latest_success.json"
```

最新状態は以下です。

```powershell
Get-Content "C:\ProgramData\ClaudeComplianceCollector\state\latest_status.json"
```

日次ログは以下です。

```powershell
Get-Content "C:\ProgramData\ClaudeComplianceCollector\logs\run_$(Get-Date -Format yyyyMMdd).txt"
```

エラーがある場合は以下です。

```powershell
Get-Content "C:\ProgramData\ClaudeComplianceCollector\logs\error_$(Get-Date -Format yyyyMMdd).txt"
```

API request-idの証跡は以下です。

```powershell
Get-Content "C:\ProgramData\ClaudeComplianceCollector\logs\requests_$(Get-Date -Format yyyyMMdd).jsonl"
```

`latest_success.json` には、次のような監視項目が入ります。

```json
{
  "status": "success",
  "started_at": "...",
  "ended_at": "...",
  "activity_fetched": 12345,
  "activity_saved": 12300,
  "activity_duplicate": 45,
  "error_count": 0,
  "retry_count": 2,
  "rate_limit_429_count": 1,
  "last_request_id": "...",
  "starting_checkpoint": {},
  "ending_checkpoint": {}
}
```

## 障害時の動き

401または403の場合は即時停止します。これはAPIキー不正、キー未設定、またはスコープ不足の可能性が高いためです。公式エラー仕様でも、401はinvalid/missing key、403は権限またはscope不足として説明されています。([Claude Platform][5])

5xx、529、timeout、通信エラーは同じcheckpointでretryします。500で `x-should-retry:false` が返された場合はretryしません。429は `retry-after` に従います。([Claude Platform][5])

chat / project contentの404は、削除済み、保持期間切れ、または存在しないIDの可能性があります。公式ドキュメントでも、hard-deletedまたはretention期限切れのcontentは取得できないとされています。その場合、スクリプトは `content_missing` に証跡を保存し、処理全体は継続します。([Claude Platform][3])

## 注意すべき公式仕様上の限界

Activity Feedは6年間保持されますが、chat / file / project contentの保持期間は組織のClaude.ai retention policyに従います。法的保全や6年超の保存が必要な場合は、取得後に自社ストレージ側で長期保管してください。([Claude Platform][2])

また、Content endpointsはClaude.aiのデータを対象とします。公式ドキュメント上、Activity FeedにはClaude ConsoleやClaude API workloadのprompt text/model responsesは含まれず、hard-deletedまたはretentionで削除済みのcontentも取得できません。([Claude Platform][6])

不明点として、Activity Feedの `limit` は公式に最大5000と確認できましたが、chat / project系のlist/message endpointの最大 `limit` は、今回確認できた公式本文上では明確な最大値を確認できませんでした。スクリプトでは公式例に合わせて保守的な既定値を使い、引数で調整できるようにしています。([Claude Platform][2])

[1]: https://platform.claude.com/docs/en/manage-claude/compliance-api "https://platform.claude.com/docs/en/manage-claude/compliance-api"
[2]: https://platform.claude.com/docs/en/manage-claude/compliance-activity-feed "https://platform.claude.com/docs/en/manage-claude/compliance-activity-feed"
[3]: https://platform.claude.com/docs/en/manage-claude/compliance-content-data "https://platform.claude.com/docs/en/manage-claude/compliance-content-data"
[4]: https://platform.claude.com/docs/en/manage-claude/compliance-api-access "https://platform.claude.com/docs/en/manage-claude/compliance-api-access"
[5]: https://platform.claude.com/docs/en/manage-claude/compliance-errors "https://platform.claude.com/docs/en/manage-claude/compliance-errors"
[6]: https://platform.claude.com/docs/en/manage-claude/compliance-integration-patterns "https://platform.claude.com/docs/en/manage-claude/compliance-integration-patterns"
