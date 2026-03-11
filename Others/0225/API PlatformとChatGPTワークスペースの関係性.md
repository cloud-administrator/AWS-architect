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
