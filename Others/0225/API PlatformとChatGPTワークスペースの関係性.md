API PlatformとChatGPTワークスペースの関係性とEnterprise契約直後のデフォルト状態
エグゼクティブサマリ
本レポートは、OpenAI公式サイト（help.openai.com / developers.openai.com / cookbook.openai.com / openai.com）に限定して確認できた情報のみを根拠に、**API Platform（platform.openai.com）とChatGPTワークスペース（chatgpt.com の管理コンソール）**の関係を、Enterprise契約直後（初期状態）を含めて整理したものです。各主張は本文中の参照で裏付けています。

結論として、実務で混同しやすいポイントは次の4点です。

**API Platformの最上位単位は「Organization（組織）」**で、監査ログ（Audit Logs）や管理者向けキー（Admin API Key）を扱うのは原則こちらです。Audit Logsは https://api.openai.com/v1/organization/audit_logs をAdminキーで取得します。
**ChatGPTの最上位単位は「Workspace（ワークスペース）」**で、コンプライアンス目的のログ（Compliance Logs）は原則こちら（または“org-”系ID）をスコープにして https://api.chatgpt.com/v1/compliance/... から取得します。
「Tenant（テナント）」はID/SSO/ドメイン管理を横断する新しい階層で、1つのTenantに複数のChatGPTワークスペースと複数のAPI Platform Organizationを束ねられます（Global Admin Console）。
Enterprise契約直後の既定状態は、“何が有効になっているか”が機能ごとに異なり、明示されていない既定値も多いです。本レポートでは、公式に明示된既定（例：ドメイン初回検証時は「未マッピング」）は断定し、**明示されていないものは「未設定/要確認」**として整理します。
全体像と用語
API Platform／ChatGPT／Tenant（Global Admin Console）の位置づけ
OpenAIの管理対象は大きく分けて以下の3レイヤーで理解すると整理しやすいです。

ChatGPTワークスペース：エンドユーザーが利用するChatGPTの“組織空間”。管理者はワークスペース設定（例：権限・ロール・IP allowlist など）を操作します。
API Platform Organization：開発者/API運用の“組織空間”。プロジェクト、APIキー、サービスアカウント、Admin API、監査ログなどの管理が中心です。
Tenant（Global Admin Console）：複数のワークスペース／組織を束ね、ドメイン検証とSSOを横断管理するための階層。Tenantには複数のChatGPTワークスペース、複数のAPI Platform Organization、複数の検証済みドメイン、単一のSSO接続などを含められます。
関係図（mermaid）
API Platform（platform.openai.com）

ChatGPT（chatgpt.com）

Tenant（Global Admin Console: admin.openai.com）

検証済みドメイン\n（初回検証時は未マッピング既定）

SSO接続（Tenant共通）

Global Admins / Tenant Admins

Workspace A（workspace_id: UUID等）

Workspace B（workspace_id: UUID等）

管理コンソール（chatgpt.com/admin 等）

Organization（org-...）

Projects / API keys / service accounts

Audit Logs / Admin API Keys



コードを表示する
Tenantにワークスペースや組織を追加・削除したい場合はサポート連絡が必要とされています。

役割の違い
役割分担の比較表
観点	API Platform（platform.openai.com）	ChatGPTワークスペース（chatgpt.com + 管理コンソール）
主用途	API利用・開発運用（プロジェクト/キー/サービスアカウント等）
組織ユーザーのChatGPT利用・ワークスペース管理（権限・機能トグル等）
監査ログの主対象	API Platform組織内の操作（APIキー作成/更新/削除、招待、ロール変更、ログイン失敗、組織設定更新、プロジェクト操作 等）
ChatGPTワークスペースのコンプライアンス用途ログ（生ログの入出力・メタデータをeDiscovery/DLP/SIEMへ）
ログ取得のAPIホスト	api.openai.com（例：/v1/organization/audit_logs）
api.chatgpt.com（例：/v1/compliance/workspaces/{workspace_id}/logs）
SSO適用の単位	ドメインベース（現時点ではAPI Platform側はカスタマイズ不可と説明）
ワークスペース×ドメイン（ドメインマッピングが必要）
IP allowlisting	適用されない（ChatGPT固有で、API Platformには適用されないと明記）
適用される（Compliance APIキー含む）。Compliance API通信は常に強制されオフにできない。

ID（org_id / workspace_id / principal_id）の関係と使い分け
IDが出てくる場所と、公式に確認できる“関係”
Global Admin Consoleのトラブルシューティング説明では、サポートへ送るべきIDの参照先として platform.openai.com/settings/organization/general（API Platform側）と chatgpt.com/admin（ChatGPT側）が挙げられています。ここから、少なくとも API PlatformとChatGPTは別々の管理面（＝別々のID系）を持ち、Tenantで束ねうることが読み取れます。

ID一覧（実務の“使い分け”で重要なもの）
ID/概念	何を指すか	どこで使うか（具体例）	公式根拠
org_id（例：org-...）	API PlatformのOrganization識別子	- Tenantに含める対象のAPI組織の識別<br>- （一部のCompliance Logs Platform）で“org-”として扱われる場合、パスが/organizations/{id}になる	TenantにAPI Platform組織を含められる
／Compliance Logs Platformがorg-判定してorganizationsへ切替
workspace_id（例：UUID）	ChatGPTワークスペース識別子	- Compliance API/Logs Platformで/workspaces/{workspace_id}/...<br>- ChatGPT管理コンソール（Workspace details）で参照してAPI呼び出しに埋め込む	workspace_idはChatGPT Admin consoleのWorkspace detailsで確認
principal_id（Cookbookスクリプト内の引数名）	**“workspace_idまたはorg_idのどちらか”**を渡す抽象入力	- Compliance Logs Platform quickstartが、引数1つで workspaces / organizations を自動切替して呼ぶ	org-ならorganizations、そうでなければworkspacesへ切替し、https://api.chatgpt.com/v1/compliance/{scope}/{principal}/logsを叩く実装例
audit_log-... 等	Audit LogsのイベントID（カーソルにもなる）	- afterパラメータでページネーション	afterはオブジェクトIDカーソルと説明

具体例で理解する（“何をどのIDで取るか”）
例 A：ChatGPTワークスペースのCompliance Logs（SIEM連携）を取りたい
ChatGPT管理コンソールで workspace_id を特定します。
https://api.chatgpt.com/v1/compliance/workspaces/{workspace_id}/logs を呼び、event_type と after（ISO8601）でログファイル一覧を取得し、/logs/{log_file_id} をダウンロードします。
例 B：API Platform組織の監査ログ（APIキー作成・権限変更など）を取りたい
API Platformで監査ログをEnableします（Organization setting → Data controls → Data retention → Audit logging → Enable）。
Organization OwnerがAdmin API Keyを作成（Admin keys → Create new admin key）。
https://api.openai.com/v1/organization/audit_logs をAdminキーで呼び出します。
例 C：“principal_id”という1つの引数で、ワークスペース／組織のどちらにも対応したい
Compliance Logs Platform quickstartの例では、引数が org-... で始まるかどうかで、/organizations/{id} と /workspaces/{id} を自動切替しています。SIEM取り込みロジックを共通化する際のヒントになります。

Enterprise契約直後のデフォルト状態（公式に明記されている範囲）
ここでは、ユーザー指定の観点（アクセス権／SSO・ドメイン検証／IP allowlist／ログ有効化）に絞り、公式に断定できるものと断定できないため要確認のものを分けて記載します。

初期状態サマリ表
項目	契約直後の既定状態（公式に明記の範囲）	根拠
Global Admin Consoleへのアクセス	ChatGPT Business/Enterpriseのワークスペース所有者に制限（新規顧客で利用可能と説明）	
Tenant内のドメイン検証	未設定/要確認（“契約直後に既に検証済みか”は明記なし。通常は自組織で追加・検証が必要）	“ドメインを追加/検証できる”の説明のみで既定値は明記なし
ドメインマッピング	ドメインを初めて検証する際の既定は「未マッピング」（ロックアウト防止のため）	
SSO（ChatGPT/API Platform）	未設定/要確認（Required/Optional/Offの選択肢は説明されるが、契約直後既定がどれかは明記なし）	選択肢と適用条件は説明
IP allowlisting（ChatGPT側）	未設定/要確認（“enableできる”ことと、enable時の挙動は明記）	enable時の挙動と管理場所（Workspace SettingsのIP allowlistタブ）は明記
IP allowlistingの適用範囲	ChatGPTの主要エンドポイントに適用（認証済みファイルDL含む）。Compliance APIキー通信は常に強制・無効化不可。API Platformには適用されない。	
API PlatformのAudit logging	有効化（Enable）操作が必要（＝少なくとも“自動で受け取れる前提ではない”）	“監査ログデータを受け取るには有効にする必要”およびEnable手順が明記
Compliance API/Logs Platformの利用開始	API Platformでキー作成→supportへメール→OpenAIの有効化確認を待つフローが明記（契約直後の利用可否は要確認）	手順としてサポート連絡と“確認を待つ”が明記
参考：Apps/Connectors（Enterprise/Edu）	Enterprise/Eduでは“Apps and connectors are disabled by default”と明記（ログ・SSOとは別だが「既定がOFF」の例）	

Audit Logs（API Platform）とCompliance Logs（ChatGPT）の関係
まず結論：ログの“対象”が違う
**Audit Logs（API Platform）**は、API Platform組織内の管理・運用イベント（APIキー、招待、ユーザー/サービスアカウント、ログイン失敗、組織設定、プロジェクト等）を追跡するための監査可能イベントログです。
**Compliance Logs（ChatGPT）**は、ChatGPTワークスペースのログ/メタデータをeDiscovery/DLP/SIEMへ接続する目的で提供され、User Analyticsのような集計ではなく、**生の入力/出力（システム注入メッセージ含む）**を返すと説明されています。
両者は競合ではなく、監査対象の面が違うため“両方必要”になるケースが多い（例：ChatGPTの利用監査＋APIキー運用監査）という位置づけです。

“ログ取得にAPI Platformを使う必要があるか”を分解して答える
観点	Audit Logs（API Platform）	Compliance Logs（ChatGPT）
ログ取得APIのホスト	api.openai.com（例：/v1/organization/audit_logs）
api.chatgpt.com（例：/v1/compliance/workspaces/{workspace_id}/logs）
キーの発行場所	API Platform（Admin keys）
**API Platform（API keys page）**でシークレットキーを作成し、サポートへメールしてアクセス有効化確認を待つ手順が明記（＝取得自体はChatGPT側APIだが、オンボーディングはAPI Platform起点）
追加の有効化操作	Audit loggingをEnableする必要
OpenAIがキーにCompliance APIアクセスを付与する前提の手順が明記

具体的なエンドポイントとキー発行フロー（公式に書かれている形）
Audit Logs（API Platform）
監査ログ有効化（UI）：Organization setting → Data controls → Data retention → Audit logging → Enable
Admin API Key作成（UI）：API Platformダッシュボード左メニュー Admin keys → Create new admin key
Admin API Key作成（API）：POST https://api.openai.com/v1/organization/admin_api_keys（Body: name）
監査ログ取得（API）：GET https://api.openai.com/v1/organization/audit_logs（Bearer: OPENAI_ADMIN_KEY）
Compliance Logs Platform / Compliance API（ChatGPT）
キー作成（UI）：API Platform Portalでシークレットキーを作成し、権限は“All permissions”を選ぶ、と記載
有効化（運用フロー）：support@openai.comにメールし、必要スコープ等を伝え、OpenAIの確認を待つ、と記載
ログ一覧（API）：GET https://api.chatgpt.com/v1/compliance/workspaces/{workspace_id}/logs（例：event_type=CODEX_LOG&after=...）
ログファイルDL（API）：GET .../logs/{log_file_id}（ダウンロード例で -L が使われる）
“org-”/workspace切替（Cookbook例）：https://api.chatgpt.com/v1/compliance をベースに、org-なら/organizations/{id}、それ以外は/workspaces/{id}へ切替する実装が例示
実務運用上の注意点
権限設計（誰がどこを触るか）
ChatGPTの管理ダッシュボード（例：User Analytics）はOwners/Adminsのみがアクセス可能で、Memberは組織レベル指標を見られないとされています。これ自体が“契約直後のアクセス権設計”の前提になります。
API PlatformのAdmin API Keyは組織オーナーのみ作成・使用可能と明記されています。監査ログ運用はセキュリティ部門主導に寄せるのが自然です。
IP allowlistingの落とし穴（ChatGPTとAPI Platformで非対称）
IP allowlistingはChatGPT側機能で、API Platformには適用されません。そのため「APIは広く到達できるがChatGPT/Complianceは閉じている」という非対称が起こり得ます。
さらに、Compliance APIキーの通信はIP allowlistingが常に強制で、オフにできません。ログ取り込み基盤（SIEM取り込みサーバ、ETLジョブ等）の送信元IP固定とallowlist登録は必須級です。
保持期間と移行スケジュール（Compliance側は特に重要）
Compliance Logs Platformは30日保持で、長期保持したい場合は継続ダウンロードして自社ポリシーに従って保管する必要がある、と明記されています。
2026-03-05に会話ログ新システムがリリースされ旧stateful routeが非推奨となり、2026-06-05に削除予定と明記されています。既存連携がstateful route依存の場合、期日までに新ソースへ移行が必要です。
キー管理（共通の基本）
APIキーは秘密情報であり、クライアントサイド露出を避け、環境変数やキー管理サービスから安全にロードすべき、とAPI Referenceで説明されています。
Admin API Keyは紛失しても復旧できないため削除して再発行が推奨されます。運用上は「定期ローテーション＋失効手順＋棚卸し」を標準化すると説明しやすくなります。
Compliance API側も、キー作成後に安全に保管することが前提として手順に含まれています（“一度しか見られない”旨の記載）。
参照したOpenAI公式URL一覧
text
コピーする
https://help.openai.com/ja-jp/articles/12289294-global-admin-console
https://help.openai.com/ja-jp/articles/9687866-admin-and-audit-logs-api-for-the-api-platform
https://developers.openai.com/api/reference/resources/organization/subresources/audit_logs/
https://developers.openai.com/api/reference/resources/organization/subresources/audit_logs/methods/list/
https://developers.openai.com/api/reference/resources/organization/subresources/audit_logs/subresources/admin_api_keys/methods/create/
https://help.openai.com/en/articles/9261474-compliance-apis-for-enterprise-customers
https://developers.openai.com/cookbook/examples/chatgpt/compliance_api/logs_platform/
https://developers.openai.com/codex/enterprise/admin-setup/





==========================================================================================





結論からいうと、`完全には合っていません`。  
より正確には、`ChatGPT Enterprise のログ取得に、推論やアプリ開発のための API Platform 利用は不要`ですが、`APIで取得する以上、APIキーなし・Platform完全非利用で済むわけではない`、が公式情報ベースの整理です。

ChatGPT Enterprise の使用履歴や操作履歴を取る主な入口は、`API Platform Audit Logs` ではなく、`ChatGPT 側の Compliance Platform / Compliance Logs Platform` です。OpenAI はこれを「ChatGPT workspace の logs and metadata」にアクセスする機能として説明しており、2025年12月3日には `ChatGPT Audit & Authentication Logs` も Compliance Logs Platform で扱えるようになったと案内しています。つまり、`workspaceの利用履歴・監査/認証ログを取りたい`なら、見るべき先は基本的にこちらです。  
一方で `API Platform Audit Logs` は、API key、invite、project、user/service account、organization config など `API Platform organization 側の操作`を追うためのものです。

ただし、ここが重要で、OpenAI の公式 quickstart は Compliance Logs Platform の前提条件として `Enterprise Compliance API key` を要求しています。また、OpenAI の公式ヘルプでは API key の作成場所を `Developer Platform (platform.openai.com) の API Keys ページ` としています。さらに OpenAI は `every ChatGPT workspace has a corresponding Platform organization` と明記しています。  
そのため、`モデル推論のために API Platform を使う必要はない`は正しいですが、`API keyを一切発行せず、API Platformにも触れずにAPI取得できる`は、公式情報と一致しません。

実務上はこう整理するのが安全です。

- `ChatGPT workspace の生ログ・会話ログ・監査/認証ログをAPIで取る`  
  `Compliance Platform / Compliance Logs Platform` を使う
- `API Platform 側のAPIキー作成やProject変更などを監査する`  
  `API Platform Audit Logs` を使う
- `集計された利用状況だけ見たい`  
  `User Analytics` を使う。公開ドキュメント上はダッシュボード + CSV export で、`User Analytics API` は確認できませんでした
- `APIキーを発行しない`  
  `Compliance API / Compliance Logs Platform をAPIで呼ぶことはできない` と考えるのが妥当です

なので、あなたの質問に一文で答えると、  
`「API Platformで推論や開発をする必要はない」が、「API Platformを全く使わず、APIキーも発行せずにChatGPT EnterpriseのログをAPI取得できる」は現時点の公式情報ではNo` です。

参照した OpenAI 公式情報:
- [OpenAI Compliance Platform for Enterprise Customers](https://help.openai.com/en/articles/9261474-compliance-api-for-chatgpt-enterprise-edu-and-chatgpt-for-teachers)
- [OpenAI Compliance Logs Platform quickstart](https://developers.openai.com/cookbook/examples/chatgpt/compliance_api/logs_platform)
- [Assign API Key Permissions](https://help.openai.com/en/articles/8867743-assign-api-key-permissions)
- [SSO Overview](https://help.openai.com/en/articles/10468051-sso-overview)
- [Admin and Audit Logs API for the API Platform](https://help.openai.com/en/articles/9687866-admin-and-audit-logs-api-for-the-api-platform)
- [ChatGPT Enterprise & Edu Release Notes](https://help.openai.com/en/articles/10128477-chatgpt-enterprise-edu-release-notes)
- [User Analytics for ChatGPT Enterprise and Edu](https://help.openai.com/en/articles/10875114)
- [ChatGPT Pricing](https://chatgpt.com/pricing)

必要なら次に、`社内説明用に誤解が出にくい表現` にして、2-3段落の説明文や図解用の文章に整えます。
https://help.openai.com/en/articles/12111596-ip-allowlisting-for-chatgpt
https://help.openai.com/en/articles/10128477-chatgpt-enterprise-edu-release-notes
https://help.openai.com/en/articles/10875114-user-analytics-for-chatgpt-enterprise-and-edu
https://developers.openai.com/api/reference/overview/






◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆

2026年3月11日時点で、OpenAI公式サイトだけを再確認したうえで、`Compliance Platform / Compliance Logs Platform` の取得手順を、実務でそのまま使える順番で整理します。

まず前提です。  
`Compliance Platform` は大きな箱で、その中に

- `Compliance Logs Platform`
- `Stateful Compliance API`

の2系統があります。  
`新しくログ取得を始めるなら、まず Compliance Logs Platform を使う` のが自然です。OpenAI自身もこれを「immutable, append-only」の監査向けログ取得として案内しており、旧来の会話系 stateful route は `2026年3月5日` に非推奨化、`2026年6月5日` に削除予定です。

**全体像**
1. Enterprise契約があることを確認する
2. ChatGPT側のIDを確認する
3. Compliance用のAPIキーを用意する
4. 必要ならCompliance API用のIP allowlistを設定する
5. `logs` 一覧APIで「ログファイル一覧」を取る
6. 返ってきた各 `log_file_id` を個別にダウンロードする
7. `has_more` と `last_end_time` でページングする
8. JSONLを自社のSIEM / data lake に保存する
9. 必要な場合だけ Stateful Compliance API を補助的に使う

**1. Enterprise契約であることを確認する**
OpenAIの公式ヘルプでは、Compliance Platform は `Enterprise customers only` です。  
つまり、Free / Plus / Pro / Business 向けの一般APIではなく、ChatGPT Enterprise 前提の機能です。

**2. ChatGPT側のIDを確認する**
ログ取得には、公式 quickstart 上 `ChatGPT account ID or API Platform Org ID` が必要です。  
一方、ChatGPT 管理画面の公式ヘルプでは `workspace ID / organization ID` を確認できると案内されています。

実務上は、まず ChatGPT 管理画面で ID を確認するのが一番わかりやすいです。

- ChatGPTでプロフィールを開く
- `Workspace settings` に入る
- `General` または `Permissions & Roles` で `workspace ID / organization ID` を確認する

補足です。  
OpenAIの SSO 文書では、各 ChatGPT workspace には対応する Platform organization があり、`org-id` は共通だと説明されています。  
なので、取得対象を ChatGPT 側のUUIDで指定する方法と、`org-...` で指定する方法があります。迷ったら、`ChatGPT workspace 側のID` を使うほうが理解しやすいです。

**3. Compliance用のAPIキーを用意する**
ここは少し誤解しやすいです。

公開されている公式資料で明示されているのは次の2点です。

- quickstart の前提条件は `Enterprise Compliance API key`
- OpenAI の API key は `Developer Platform の API Keys page` で作成・編集する

この2点を突き合わせると、`Developer Platform (platform.openai.com) の API Keys page で Compliance 用のキーを準備する` という理解が最も自然です。  
これは公開資料の突き合わせによる整理です。

実際の準備イメージは次です。

- `platform.openai.com` の `API Keys` に行く
- `Create new secret key` を押す
- 作成したキーを安全に保管する
- 使えるなら `Restricted` を選び、Compliance用 scope を付ける  
  正確な scope 名は、`chatgpt.com/admin/api-reference` のログイン後ドキュメントで確認してください

重要な補足です。  
`2026年3月11日時点で確認できる現在の公開ヘルプ記事` では、昔の案内にあったような「support@openai.com にメールして有効化」という手順は確認できませんでした。  
少なくとも現在の公開情報では、`Enterprise であること` と `Compliance API documentation / quickstart` が案内されています。

**4. 必要なら IP allowlist を設定する**
もしワークスペースで IP allowlisting を使うなら、Compliance API 用の送信元IPも登録が必要です。

設定場所:
- `Workspace Settings`
- `Identity & access`
- `Access Restrictions`

ここで重要なのは次です。

- Workspace用 allowlist と Compliance API用 allowlist は別
- Compliance API traffic は IP allowlisting の対象
- Compliance API keys では IP allowlisting が常に強制され、オフにできない

つまり、SIEM連携サーバやバッチ実行サーバのグローバルIPを許可しないと、キーが正しくてもAPI呼び出しは失敗します。

**5. まずは「ログファイル一覧」を取得する**
Compliance Logs Platform は、1件ずつイベントを返すのではなく、`時間区切りのJSONLログファイル` を配る形です。  
なので最初にやるのは、`イベント本体の取得` ではなく `ファイル一覧の取得` です。

ベースURL:
```text
https://api.chatgpt.com/v1/compliance
```

workspace ID を使う場合:
```text
GET /workspaces/{workspace_id}/logs
```

org-id を使う場合:
```text
GET /organizations/{org_id}/logs
```

主なクエリ:
- `event_type`
- `limit`
- `after`

`after` は `ISO 8601` 形式の日時です。  
公式 quickstart でも、`AUTH_LOG` と `after=<UTC日時>` の形で例示されています。

**6. 返ってきた各ログファイルをダウンロードする**
一覧APIの結果には `data[].id` が入ります。  
この `id` ごとに、次のAPIで実ファイルを落とします。

```text
GET /workspaces/{workspace_id}/logs/{log_file_id}
```

または

```text
GET /organizations/{org_id}/logs/{log_file_id}
```

ダウンロードした中身は `JSONL` です。  
1行1イベントなので、そのまま SIEM や data lake に流し込みやすい形式です。

**7. ページングする**
一覧APIは1回で全部返る前提ではありません。  
公式 quickstart では次の値でページングしています。

- `has_more`
- `last_end_time`

流れはこうです。

1. `after=開始時刻` で一覧取得
2. 返ってきた `data[].id` を全部ダウンロード
3. `has_more=true` なら、次回の `after` に `last_end_time` を入れて再実行
4. `has_more=false` になるまで続ける

**8. 保存先は必ず自社側に持つ**
OpenAI の公式ヘルプでは、`Compliance Logs Platform retains data for 30 days` と明記されています。  
なので、OpenAI上に長期保存される前提ではいけません。

実務ではこう考えるのが安全です。

- OpenAIから定期的に取り込む
- 自社のSIEM / S3 / Data Lake / eDiscovery基盤に保存する
- 長期保持は自社ポリシーで行う

**9. Stateful Compliance API は必要なときだけ使う**
OpenAIの現在の説明では、Stateful Compliance API は

- リクエスト時点の状態を引く
- Logs Platform のイベントから参照されるデータを join する
- legacy data types を扱う

ための補助的な位置づけです。  
新規導入で「監査ログを継続収集したい」だけなら、まずは `Compliance Logs Platform` から始めるのがよいです。

ただし注意点として、会話ログの古い stateful route は `2026年3月5日` に非推奨化され、`2026年6月5日` に削除予定です。  
新規実装で旧 route 前提にしないのが大事です。

**最小の PowerShell 例**
Windows環境なら、まずはこんな形で試せます。

```powershell
$env:COMPLIANCE_API_KEY = "<your_key>"
$workspaceId = "<your_workspace_uuid>"
$eventType = "AUTH_LOG"  # 他の値はログイン後のAPI Referenceで確認
$after = (Get-Date).ToUniversalTime().AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")

$headers = @{ Authorization = "Bearer $env:COMPLIANCE_API_KEY" }
$base = "https://api.chatgpt.com/v1/compliance/workspaces/$workspaceId"

New-Item -ItemType Directory -Force -Path .\compliance-logs | Out-Null

do {
  $listUrl = "$base/logs?event_type=$eventType&limit=100&after=$after"
  $resp = Invoke-RestMethod -Method Get -Headers $headers -Uri $listUrl

  foreach ($file in $resp.data) {
    $out = ".\compliance-logs\$($file.id).jsonl"
    Invoke-WebRequest -Method Get -Headers $headers -Uri "$base/logs/$($file.id)" -OutFile $out
  }

  $after = $resp.last_end_time
} while ($resp.has_more)
```

`org-...` を使う場合は、`workspaces` を `organizations` に変えれば大丈夫です。

**運用上の注意**
- Compliance API は `analytics 用ではありません`。集計用途なら `User Analytics` のほうが向いています。
- Compliance API は raw log なので、system-generated / injected message も含まれます。
- そのため、User Analytics の数字と完全一致しないことがあります。
- 全 authenticated request は OpenAI 側でも security/compliance purposes でログ化されます。

参照した OpenAI 公式ソース:
- [OpenAI Compliance Platform for Enterprise Customers](https://help.openai.com/en/articles/9261474-compliance-api-for-chatgpt-enterprise-edu-and-chatgpt-for-teachers)
- [OpenAI Compliance Logs Platform quickstart](https://developers.openai.com/cookbook/examples/chatgpt/compliance_api/logs_platform)
- [Compliance API documentation](https://chatgpt.com/admin/api-reference)
- [What workspace settings can I control for my workspace?](https://help.openai.com/en/articles/8411955)
- [IP allowlisting for ChatGPT](https://help.openai.com/en/articles/12111596-ip-allowlisting-for-chatgpt/)
- [SSO Overview](https://help.openai.com/en/articles/10468051-sso-overview)
- [Assign API Key Permissions](https://help.openai.com/en/articles/8867743-assign-api-key-permissions)
- [Compliance API vs User Analytics in ChatGPT Enterprise/Edu](https://help.openai.com/en/articles/11327494-compliance-api-vs-user-analytics-in-chatgpt-enterprise-edu)
- [ChatGPT Enterprise & Edu Release Notes](https://help.openai.com/en/articles/10128477-chatgpt-enterprise-edu-release-notes)

必要なら次に、`監査ログ取得だけに絞った最短手順版` か、`社内手順書としてそのまま貼れる文章` に整えます。

