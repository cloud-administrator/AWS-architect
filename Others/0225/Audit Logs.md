2026年3月10日時点で、OpenAI公式サイトのみを突き合わせて確認した結論です。

前提として、公開ドキュメント上では `General Audit Logs` という名称の定義ページは見当たりませんでした。なので以下は、OpenAIが2025年12月11日に公開した `Admin Audit / ChatGPT Audit & Authentication Logs` を、質問中の「Audit Logs (General Audit Logs)」として整理しています。これは公開情報からの読み替えです。

**結論**
ざっくり言うと、

- `Audit Logs (General/Admin Audit Logs)` は「誰が、いつ、ワークスペース設定や認証まわりで何を変えたか」を追うための監査ログ
- `Compliance API Logs` は「ユーザーがChatGPTで何をやり取りし、どんなファイル・GPT・Memory・Canvas等が関わったか」を追うためのコンプライアンス/証跡ログ

です。

OpenAIの最新整理では、両方とも別製品というより、同じ `OpenAI Compliance Platform` 配下の別用途データとして扱うのが正確です。公開ヘルプではこの基盤に
- `Compliance Logs Platform` = 変更不可・追記専用の監査イベント
- `Stateful Compliance API` = 取得時点の状態を問い合わせるAPI  
の2系統がある、と説明されています。

| 観点 | Audit Logs (General/Admin Audit Logs) | Compliance API Logs |
|---|---|---|
| 主目的 | 管理・認証・設定変更の監査 | eDiscovery、DLP、法務・セキュリティ証跡 |
| 何が見えるか | ワークスペース変更、認証アクティビティ、Codex利用など | 会話、入出力、ファイル、GPT設定/メタデータ、Memory、Canvas、Automation、ユーザー等 |
| 粒度 | 管理イベント中心 | コンテンツ/オブジェクト中心 |
| 典型用途 | 「誰が設定を変えたか」「認証で何が起きたか」 | 「誰が何を送信/生成したか」「保持・削除・調査」 |
| データ形式 | OpenAIは immutable な time-windowed JSONL と説明 | 生JSON。現在は Logs Platform と Stateful API の両方で扱う構成 |
| 向いていないこと | 会話内容の精査 | 利用分析ダッシュボード用途 |

**それぞれでできること**
`Audit Logs`
- ワークスペース変更の監査
- 認証アクティビティの追跡
- Codex利用の把握

`Compliance API Logs`
- 会話やGPT関連データの取得
- eDiscovery / DLP / SIEM 連携
- 単一アイテム単位の削除対応
- 削除後最大30日の不変ログによる証跡確保
- Apps利用会話、app calls、skills作成/共有/更新/インストール、record modeのtranscript/canvas などの追跡

補足で、OpenAIは `Compliance API は分析機能ではない` と明記しています。導入率やアクティブユーザー数を見るなら、`Workspace settings -> Usage` の集計ダッシュボードを使う想定です。

**どこで設定できるか**
ログそのものは「別々の管理画面でON/OFFする」というより、同じEnterprise管理配下で扱います。

- ワークスペース全体設定: `Workspace settings`
- アクセス制御: `Workspace settings -> Identity & access -> Access Restrictions`
- Apps: `Workspace settings -> Apps`
- 権限/RBAC: `Workspace settings -> Permissions & roles`
- Record mode: `Workspace Settings -> Record`
- 詳細API/エンドポイント: `chatgpt.com/admin/api-reference`  
  これはOpenAI公式ヘルプでも「Enterprise workspaceにログインしていないと見られない」とされています。

重要なのは、`Compliance API` への通信は `IP allowlisting` の対象で、Compliance API keys には常にIP allowlistingが適用される点です。

**導入時の実務ポイント**
- 監査目的なら、まず `Audit/Admin/Auth logs`
- 会話内容の保持・調査・DLPなら、`Compliance API Logs`
- 実装上は両方を `OpenAI Compliance Platform` としてまとめて設計するのが自然
- 2026年3月5日に新しい conversation logs system が出ており、旧 stateful route は 2026年6月5日に削除予定です。新規導入なら旧ルート前提にしない方が安全です

**確認に使ったOpenAI公式ソース**
- [OpenAI Compliance Platform for Enterprise Customers](https://help.openai.com/en/articles/9261474-compliance-apis-for-enterprise-customers)
- [ChatGPT Enterprise & Edu Release Notes](https://help.openai.com/en/articles/10128477-chatgpt-enterprise-edu-release-notes)
- [New compliance and administrative tools for ChatGPT Enterprise](https://openai.com/index/new-tools-for-chatgpt-enterprise/)
- [Compliance API vs User Analytics in ChatGPT Enterprise/Edu](https://help.openai.com/en/articles/11327494)
- [What workspace settings can I control for my workspace?](https://help.openai.com/en/articles/8411955)
- [IP allowlisting for ChatGPT](https://help.openai.com/en/articles/12111596-ip-allowlisting-for-chatgpt)
- [Apps in ChatGPT](https://help.openai.com/en/articles/11487775-apps-in-chatgpt)
- [Skills in ChatGPT](https://help.openai.com/en/articles/20001066-skills-in-chatgpt)
- [Enterprise compliance information for ChatGPT record mode](https://help.openai.com/en/articles/11664471)
- [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540)

必要なら次に、導入提案資料向けに
`1枚でわかる比較表`
または
`情シス/法務/セキュリティ向けの説明文`
の形に整えて出します。




◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆

2026年3月10日時点のOpenAI公式情報で整理すると、まず名称に注意が必要です。最新の公開情報では、`Audit Logs` も `Compliance API Logs` も、いまは `OpenAI Compliance Logs Platform` 配下で扱われています。なお、正確なイベント名・フィールド定義・全エンドポイント一覧は、Enterpriseログインが必要な [API reference](https://chatgpt.com/admin/api-reference) 側にあり、公開ページでは完全には見えません。以下は「公開情報で確認できた範囲」の要約です。

**取得できる内容**
`Audit Logs`
- `Admin Audit`。ワークスペースに加えられた変更の監査に使うログです。
- `User Authentication`。認証アクティビティ追跡に使うログです。
- `Codex Usage Logs`。Codex利用状況の把握に使うログです。
- 取得方式は、OpenAIの公開説明では「immutable / append-only / time-windowed JSONL log files」です。
- 公開Quickstartで確認できる取得口は、`GET /v1/compliance/{workspaces|organizations}/{id}/logs` と `GET /v1/compliance/{workspaces|organizations}/{id}/logs/{log_id}` です。`event_type` で種別指定する形で、公開例では `AUTH_LOG` が示されています。Audit/Codexの具体的な enum 名までは公開ページで確認できませんでした。

`Compliance API Logs`
- 会話/メッセージ全体。ユーザー入力、モデル出力に加え、system/generated/injected message や python tool calls も含まれます。
- アップロードファイル。
- ワークスペースGPTの設定とメタデータ。
- Memory。
- Canvas。
- Automation。
- Workspace users。
- Apps利用時の会話。
- Appsの呼び出し内容。公式には `app calls`、`tool calls`、`files accessed`、`relevant conversation context` が監査対象として明記されています。
- Skillsの監査メタデータ。作成、共有、更新、インストール。
- Record mode の transcript と canvas。
- Slack app を使う場合、Slack由来でChatGPTに同期された会話。
- Codex利用ログ。ただしOpenAI公式では、`web` と `cloud delegated` の利用だけが Compliance API で取得可能で、`local environments` は取得対象外です。

**企業として保持推奨のログ**
以下は、OpenAI公式が示す用途から見た実務上の推奨です。

`最低限保持を強く推奨`
- `Admin Audit logs`
- `User Authentication logs`
- `全会話ログ`。入力・出力だけでなく、system/generated/injected message を含む完全ログ
- `ファイル関連ログ`
- `workspace users / role context`。誰の操作か結び付けるため

`機能を使っているなら追加で保持推奨`
- `GPT設定・メタデータ`
- `Memory`
- `Canvas`
- `Record mode transcripts`
- `Automation`
- `Apps logs`。特に tool calls / files accessed / app calls
- `Skills lifecycle logs`
- `Codex Usage Logs`。ただしOpenAI公式上、local Codex は取れない
- `Slack app conversations`。Slack連携を使う場合

**運用上の重要ポイント**
- OpenAI公式では `Compliance Logs Platform retains data for 30 days` とされており、長期保管したい場合は継続的にダウンロードして自社SIEM / data lake に保存する必要があります。
- 会話に添付したファイルは、Chat retention とは別に失効し、Enterpriseでは失効後 `Compliance API` から即時見えなくなります。公開ヘルプでは `48 hours` の注意が出ています。ファイル証跡は早めの取得前提で設計した方が安全です。
- `User Analytics` は代替になりません。集計ダッシュボードであり、メッセージ本文や完全証跡は出ません。
- `Compliance API keys` には常に `IP allowlisting` が適用されます。
- 2026年3月5日に新しい conversation logs system が出ており、旧 stateful route は 2026年6月5日に削除予定です。今から導入するなら新しい logs system 前提で設計するのが安全です。

**公式ソース**
- [OpenAI Compliance Platform for Enterprise Customers](https://help.openai.com/en/articles/9261474-compliance-apis-for-enterprise-customers)
- [Compliance API vs User Analytics in ChatGPT Enterprise/Edu](https://help.openai.com/en/articles/11327494)
- [New compliance and administrative tools for ChatGPT Enterprise](https://openai.com/index/new-tools-for-chatgpt-enterprise/)
- [ChatGPT Enterprise & Edu Release Notes](https://help.openai.com/en/articles/10128477-chatgpt-enterprise-edu-release-notes)
- [OpenAI Compliance Logs Platform quickstart](https://developers.openai.com/cookbook/examples/chatgpt/compliance_api/logs_platform)
- [Admin Controls, Security, and Compliance in apps](https://help.openai.com/en/articles/11509118)
- [Apps in ChatGPT](https://chatgpt.com/features/apps/)
- [Skills in ChatGPT](https://help.openai.com/en/articles/20001066-skills-in-chatgpt)
- [Enterprise compliance information for ChatGPT record mode](https://help.openai.com/en/articles/11664471)
- [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-codex-in-chatgpt)
- [Chat and File Retention Policies in ChatGPT](https://help.openai.com/en/articles/8983778-how-are-files-vs-chats-retained)
- [IP allowlisting for ChatGPT](https://help.openai.com/en/articles/12111596-ip-allowlisting-for-chatgpt)

必要なら次に、これをそのまま提案書に貼れる形で `監査ログ一覧表` と `保持方針の推奨案` に整えます。

◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆

以下は、OpenAI公式情報をもとに、そのまま提案資料に貼りやすい形へ整えたものです。  
なお、`保持年限` は OpenAI の必須要件ではなく、公開仕様を踏まえた実務上の推奨案です。

**監査ログ一覧表**
| 区分 | ログ/API | OpenAI公式で確認できる主な内容 | 企業での保持優先度 |
|---|---|---|---|
| Audit Logs | `Admin Audit` | ワークスペースに加えられた変更の監査 | 必須 |
| Audit Logs | `User Authentication` | 認証アクティビティの追跡 | 必須 |
| Audit Logs | `Codex Usage` | Codex利用状況。`web` と `cloud delegated` は取得対象、`local environments` は対象外 | 条件付き |
| Compliance API Logs | `Conversation logs` | 全メッセージ。ユーザー入力、モデル出力、system-generated / injected message、python tool calls | 必須 |
| Compliance API Logs | `Files` | 会話にアップロードされたファイル。Enterpriseでは失効後は Compliance API から利用不可 | 必須 |
| Compliance API Logs | `Memory` | Memory の保持・調査向けデータ | 機能利用時は推奨 |
| Compliance API Logs | `Canvas` | Canvas データ | 機能利用時は推奨 |
| Compliance API Logs | `Automation` | Automation データ | 機能利用時は推奨 |
| Compliance API Logs | `Apps` | app を使った会話、app calls。公式 feature page では tool calls / files accessed / relevant conversation context を明記 | Apps利用時は必須 |
| Compliance API Logs | `Skills` | skills の作成・共有・更新・インストールのメタデータ/監査ログ | Skills利用時は推奨 |
| Compliance API Logs | `Record mode` | transcript と canvas | Record mode利用時は推奨 |

補足です。公開Quickstartで確認できる取得口は `GET /v1/compliance/{workspaces|organizations}/{id}/logs` と `GET /v1/compliance/{workspaces|organizations}/{id}/logs/{log_id}` です。`event_type` 指定の公開例としては `AUTH_LOG` が確認できます。完全な event type 一覧は Enterprise ログインが必要な [API reference](https://chatgpt.com/admin/api-reference) 側で確認する前提です。

**保持方針の推奨案**
| 方針項目 | 推奨案 |
|---|---|
| 最低限保持するログ | `Admin Audit`、`User Authentication`、`Conversation logs`、`Files`、`Apps logs`（Apps利用時） |
| 追加で保持するログ | `Codex Usage`、`Skills`、`Memory`、`Canvas`、`Automation`、`Record mode` は利用機能に応じて追加 |
| 収集頻度 | `Compliance Logs Platform` は OpenAI側で30日保持なので、常時エクスポートが前提。実務上は `少なくとも1時間ごと` を推奨 |
| ファイル取得方針 | 会話内ファイルは Enterprise で `48時間後に失効` しうるため、必要なファイル証跡は `24時間以内` に取得する運用を推奨 |
| 標準保持年限の例 | `Admin/Auth/App/Skill/Codex` は `13か月`、`Conversation/Memory/Canvas/Automation/Record transcripts` は `12か月` |
| 規制業種・訴訟対応が重い場合 | 上記を `24か月以上` に延長し、法務の legal hold 方針に合わせる |
| 保管先 | `変更不可の保管領域` と `検索用SIEM/データレイク` の二層保管を推奨 |
| アクセス制御 | 閲覧権限は `SecOps / 法務 / コンプライアンス` に限定。一般管理者と分離 |
| 削除対応 | OpenAI側の削除後復元には依存しない。法的保全が必要なら、自社保管側で legal hold をかける |
| 連携前提 | Compliance API keys は `IP allowlisting` 前提で設計する |

**実務上の推奨結論**
- まず必須で残すべきなのは、`Admin Audit`、`User Authentication`、`Conversation logs`、`Files` です。
- `Apps` を使う企業は、`app calls` も必須扱いにした方が安全です。OpenAI公式でも監査対象として強く位置づけられています。
- `Skills`、`Record mode`、`Codex` は、機能を有効化した時点で保持対象に追加する設計がよいです。
- OpenAI側の保持だけでは足りないため、`自社SIEM / data lake への継続取り込み` を前提に設計するのが基本です。

**公式根拠**
- [OpenAI Compliance Platform for Enterprise Customers](https://help.openai.com/en/articles/9261474-compliance-apis-for-enterprise-customers)
- [Compliance API vs User Analytics in ChatGPT Enterprise/Edu](https://help.openai.com/en/articles/11327494)
- [New compliance and administrative tools for ChatGPT Enterprise](https://openai.com/index/new-tools-for-chatgpt-enterprise/)
- [OpenAI Compliance Logs Platform quickstart](https://developers.openai.com/cookbook/examples/chatgpt/compliance_api/logs_platform)
- [Admin Controls, Security, and Compliance in apps](https://help.openai.com/en/articles/11509118-admin-controls-security-and-compliance-in-apps-enterprise-edu-and-business)
- [Apps in ChatGPT](https://chatgpt.com/features/apps/)
- [Skills in ChatGPT](https://help.openai.com/en/articles/20001066-skills-in-chatgpt)
- [Enterprise compliance information for ChatGPT record mode](https://help.openai.com/en/articles/11664471)
- [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-codex-in-chatgpt)
- [Chat and File Retention Policies in ChatGPT](https://help.openai.com/en/articles/8983778-how-are-files-vs-chats-retained)
- [IP allowlisting for ChatGPT](https://help.openai.com/en/articles/12111596-ip-allowlisting-for-chatgpt)

必要なら次に、これを `社内説明用の1ページ資料` か `提案書向けの箇条書き版` に圧縮します。

◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆

`Audit Logs` と `Compliance API Logs` は、2026年3月10日時点ではどちらも `OpenAI Compliance Logs Platform` から取得する形です。つまり、取得の仕組みは基本的に共通で、違うのは `event_type` と保存対象です。以下は、OpenAI公式情報で確認できる範囲だけで組んだ、ファイルサーバー保存の実施手順です。

**前提**
- OpenAI公式では、`Compliance Logs Platform` の保持期間は `30日` です。長期保管したい場合は、自社で継続的にダウンロードして保存する必要があります。
- 2026年3月5日に新しい conversation logs system が公開され、旧 stateful route は `2026年6月5日` に削除予定です。新規構築は `Logs Platform` 前提で進めます。
- `Compliance API` の詳細ドキュメントは `Enterprise workspace にログインした状態` でないと見られません。正確な `event_type` 一覧やキー発行画面は、その Enterprise 専用ドキュメントで最終確認が必要です。

**手順**
1. `Workspace settings` で管理画面に入る  
   `Workspace settings` では、workspace / organization ID を確認できます。公開ヘルプでは、`General` と `Permissions & roles` で ID を確認できると案内されています。

2. 取得対象を決める  
   最低限、以下を対象にします。  
   - `Audit Logs`: `Admin Audit`, `User Authentication`  
   - `Compliance API Logs`: 会話ログ、ファイル、必要に応じて Memory / Canvas / Automation / Apps / Skills / Codex  
   もし Apps や Codex を使うなら、それらも対象に含めます。

3. `Compliance API` 用の送信元IPを allowlist に登録する  
   `Workspace settings -> Identity & access -> Access Restrictions` で、`Compliance API` 用のIP allowlistを設定します。  
   OpenAI公式では、`Compliance API traffic` には IP allowlisting が常に適用されるとされています。取得サーバーや中継サーバーの固定IPを必ず登録してください。

4. `Compliance API key` を発行する  
   公開ヘルプでは、Compliance API は `dedicated API-key scopes` を使うと案内されています。  
   ただし、キー発行の具体的な画面手順は公開ページでは確認できず、Enterprise 専用の [API reference](https://chatgpt.com/admin/api-reference) 側で確認する必要があります。  
   実務上は、`ログ取得専用キー` を1本用意し、OS の secret store や vault に保管します。

5. `workspace_id` か `organization_id` を決める  
   OpenAI公式 quickstart では両方使えます。  
   - 1つの workspace だけ取るなら `workspaces/{workspace_id}`  
   - 複数 workspace をまとめて取りたいなら `organizations/{organization_id}`

6. ログ一覧を取得する  
   公式 quickstart にある入口は次の2つです。  
   - `GET /v1/compliance/{workspaces|organizations}/{id}/logs`
   - `GET /v1/compliance/{workspaces|organizations}/{id}/logs/{log_id}`  
   まず一覧APIに対して、`event_type`、`limit`、`after` を付けて呼びます。  
   公開サンプルでは `AUTH_LOG` が例示されています。`Admin Audit` や会話ログなどの正確な `event_type` 値は Enterprise 専用APIドキュメントで確認してください。

7. 返ってきた `log_id` ごとに実体をダウンロードする  
   一覧APIのレスポンスに含まれる `data[].id` を使って、`/logs/{log_id}` を順に取得します。  
   OpenAI公式の quickstart でも、この2段階で JSONL を落とす流れになっています。

8. `has_more` と `last_end_time` でページングする  
   公式 quickstart では、レスポンスの `has_more` が `true` の間は続け、次回の `after` に `last_end_time` を使う構成です。  
   これをそのまま実装すると、取りこぼしを減らせます。

9. ファイルサーバーに `raw のまま` 保存する  
   保存先は、まず `OpenAIから返ってきた原本(JSON/JSONL)` をそのまま保管します。  
   推奨構成は次のような形です。  
   - `\\fileserver\openai-logs\audit\YYYY\MM\DD\...`
   - `\\fileserver\openai-logs\auth\YYYY\MM\DD\...`
   - `\\fileserver\openai-logs\compliance\conversations\YYYY\MM\DD\...`
   - `\\fileserver\openai-logs\codex\YYYY\MM\DD\...`
   ファイル名は `取得日時 + log_id` にしておくと追跡しやすいです。

10. チェックポイントを別ファイルで管理する  
   取得した JSONL と別に、各 `event_type` ごとの `last_end_time` を保存します。  
   例: `\\fileserver\openai-logs\checkpoints\AUTH_LOG.json`  
   次回実行時はこの時刻を `after` に使います。

11. 定期実行する  
   OpenAI公式は `継続的にダウンロード` するよう案内しています。  
   実務上は `1時間ごと` を推奨します。最低でも `1日1回` ではなく、もっと短い間隔にした方が安全です。

12. 会話内ファイルを使う場合は別途すぐ回収する  
   OpenAI公式では、Enterprise の会話添付ファイルは `48時間で失効` しうるとされています。  
   そのため、会話ログだけでなく実ファイルも保管対象なら、`24時間以内` に関連ファイルを回収するジョブを別で走らせるのが安全です。  
   ここも正確なファイル取得エンドポイントは Enterprise 専用APIドキュメントで確認してください。

**保存運用の推奨**
- `raw` と `加工済み` を分ける  
  まず原本をそのまま保存し、検索用の整形データは別フォルダや別ストレージに置きます。
- `変更不可領域` に置く  
  監査証跡なので、書き換え禁止または追記専用の共有領域に置くのが安全です。
- `取得失敗アラート` を付ける  
  1回でも失敗したらメールや監視に上げる運用にします。
- `event_type ごと` に分ける  
  後から調査しやすくなります。
- `Apps / Skills / Codex` を使うなら対象追加  
  これらは導入後に抜けやすいので、機能有効化時に必ず収集対象へ追加します。

**実装イメージ**
1. `after` を読み込む  
2. `logs` 一覧APIを呼ぶ  
3. `data[].id` を順に `logs/{log_id}` で取得する  
4. ファイルサーバーへ保存する  
5. `has_more` が `false` になるまで繰り返す  
6. 最後の `last_end_time` を checkpoint に保存する  
7. 次の `event_type` に進む

**注意点**
- `User Analytics` は集計画面であり、監査ログ保存の代わりにはなりません。
- OpenAI側の30日保持を過ぎると、自社未取得分は戻せません。
- 旧 stateful route 前提で作ると、`2026年6月5日` 以降に使えなくなるため避けてください。
- 正確な `event_type` 一覧、ファイル取得API、キー発行画面は Enterprise 専用ドキュメントで最終確認してください。公開ページだけではそこまで開示されていません。

**公式ソース**
- [OpenAI Compliance Platform for Enterprise Customers](https://help.openai.com/en/articles/9261474-compliance-apis-for-enterprise-customers)
- [OpenAI Compliance Logs Platform quickstart](https://developers.openai.com/cookbook/examples/chatgpt/compliance_api/logs_platform)
- [IP allowlisting for ChatGPT](https://help.openai.com/en/articles/12111596-ip-allowlisting-for-chatgpt)
- [What workspace settings can I control for my workspace?](https://help.openai.com/en/articles/8411955)
- [Compliance API vs User Analytics in ChatGPT Enterprise/Edu](https://help.openai.com/en/articles/11327494)
- [Chat and File Retention Policies in ChatGPT](https://help.openai.com/en/articles/8983778-how-are-files-vs-chats-retained)
- [ChatGPT Enterprise & Edu - Release Notes](https://help.openai.com/en/articles/10128477-chatgpt-enterprise-edu-release-notes)

必要なら次に、`Windows のファイルサーバーに保存する前提の PowerShell 手順書` として、コマンド例つきでそのまま手順書形式に整えます。

◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


