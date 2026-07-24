# Snowflake Managed MCP Server × ChatGPT.com Developer Mode

## クライアント構築・設定ガイド

**調査日：2026年7月24日**

---

## 1. 調査結果の結論

### 1-1. ChatGPT.comのDeveloper ModeはOAuthをサポートしています

ChatGPTは、MCPサーバーとの認証にOAuthを使用できます。OAuthの固定クライアント、PKCE、Dynamic Client Registrationなどに対応しています。

一方、Snowflake Managed MCP ServerはOAuthに対応していますが、**Dynamic Client Registrationには対応していません**。したがって、今回の構成では、Snowflake側で発行した固定の`client_id`と`client_secret`をChatGPTに登録する方式を使用します。

Snowflakeの公式ドキュメントにも、ChatGPTからSnowflake Managed MCP ServerへOAuth接続する手順が明記されています。([OpenAI Developers][1])

採用するOAuth方式は、次のとおりです。

| 設定項目         | 採用する値                                  |
| ------------ | -------------------------------------- |
| OAuth発行元     | Snowflake OAuth                        |
| OAuthクライアント  | ChatGPTワークスペースのSnowflakeアプリ            |
| クライアント登録方式   | 固定クライアント                               |
| Snowflake側設定 | `OAUTH_CLIENT = CUSTOM`                |
| クライアント種別     | `CONFIDENTIAL`                         |
| 認可フロー        | Authorization Code                     |
| PKCE         | S256、必須化を推奨                            |
| ユーザー認証       | ユーザーごとにSnowflakeへログイン                  |
| トークン送信       | `Authorization: Bearer <access_token>` |

---

### 1-2. 通常構成では、WindowsにMCPクライアントプログラムをインストールしません

通常構成では、ChatGPT.com自体がMCPクライアントです。

Windows PCに以下を用意する必要はありません。

* Node.js
* Python
* SnowSQL
* `mcp.json`
* 独自のMCPクライアントプログラム
* ローカルMCPプロセス

Windows PCで行う作業は、基本的に次の3つです。

1. ブラウザーでChatGPT.comの会社ワークスペースを開く
2. Developer ModeでSnowflakeアプリを登録する
3. SnowflakeのOAuthログインを完了する

実際のMCP要求は、Windows PCからではなく、**OpenAIのサーバー基盤からSnowflakeへ送信されます**。([OpenAI Help Center][2])

---

### 1-3. PrivateLinkについて、非常に重要な制約があります

Snowflakeの公式なSaaSクライアント向け構成では、ChatGPTに登録するのはPrivateLink URLではなく、**Snowflakeの公開MCP URL**です。

そのうえで、OAuth Security Integrationに以下を設定します。

```sql
USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE
```

この設定により、利用者がSnowflakeへログインするブラウザー部分はPrivateLink側へリダイレクトされます。

しかし、以下の通信は公開Snowflake URLを使用します。

* OpenAIバックエンドからSnowflake OAuthトークンエンドポイントへの通信
* OpenAIバックエンドからSnowflake Managed MCP Serverへの通信

Snowflakeは、SaaSベンダーのバックエンドはPrivateLinkホスト名を解決できないため、公開URLを使用する必要があると明記しています。([Snowflake Docs][3])

> **したがって、SnowflakeをPrivateLinkで構築済みであっても、ChatGPTの標準構成は「すべての通信がPrivateLinkを通る構成」ではありません。**

会社のセキュリティ要件が「Snowflakeの公開エンドポイントを一切利用してはいけない」である場合、標準構成をそのまま採用できません。

---

## 2. 推奨構成

### 2-1. Snowflakeが公式に案内している標準構成

```text
【利用者側】

Windows PC
  └─ Edge / Chrome
       │
       │ HTTPS
       ▼
  ChatGPT.com
       │
       │ OAuth認可開始
       ▼
  Snowflakeの公開認可入口
       │
       │ PrivateLink認可URLへリダイレクト
       ▼
  Snowflake PrivateLink認可エンドポイント
       │
       │ ユーザーログイン・同意
       ▼
  ChatGPT OAuth Callback


【サーバー間通信】

OpenAIのChatGPTバックエンド
       │
       ├─ 公開HTTPS
       │    └─ Snowflake OAuthトークンエンドポイント
       │
       └─ 公開HTTPS + Bearer Token
            └─ Snowflake Managed MCP Serverの公開URL
```

通信経路を整理すると、次のようになります。

| 通信                                  | 経路                               |
| ----------------------------------- | -------------------------------- |
| Windows PC → ChatGPT.com            | インターネットHTTPS                     |
| Windowsブラウザー → Snowflakeログイン画面      | PrivateLink側へリダイレクト              |
| OpenAIバックエンド → Snowflakeトークンエンドポイント | 公開HTTPS                          |
| OpenAIバックエンド → Snowflake MCPエンドポイント | 公開HTTPS                          |
| Snowflakeでの権限制御                     | ユーザー、ロール、MCP Server、各ツール対象オブジェクト |

この標準構成は、SnowflakeおよびOpenAIの公式文書で直接案内されている構成です。([Snowflake Docs][3])

---

## 3. 最初に会社として決めること

実装開始前に、ネットワーク担当者、Snowflake担当者、セキュリティ担当者の間で、次のどれを採用するか決めてください。

| 方針 | 構成                                           | 判定                                             |
| -- | -------------------------------------------- | ---------------------------------------------- |
| A  | Snowflakeの公開MCP／トークンURLを、OpenAI送信元IPに限定して許可  | **最も公式情報が揃っているため推奨**                           |
| B  | MCP通信だけは完全にプライベート化し、OAuthトークンエンドポイントの公開利用は許可 | Secure MCP Tunnelを使った検証が必要                     |
| C  | MCP、認可、トークンのすべてを公開インターネットに出さない               | 現時点で公式に完成形が文書化されていないため、OpenAI・Snowflakeへの確認が必要 |

通常は、まず方針Aで読み取り専用の小規模PoCを行います。

---

## 4. 各担当者の作業分担

| 担当者                | 主な作業                                                                               |
| ------------------ | ---------------------------------------------------------------------------------- |
| あなた                | ChatGPT Developer Modeの有効化、Snowflakeアプリ登録、Callback URIの取得、client ID／secretの入力、接続試験 |
| ChatGPTワークスペース管理者  | Developer Modeの権限付与、アプリ公開、利用者・アクション・承認設定                                           |
| Snowflake／MCP担当者   | Managed MCP Serverの作成、ツール定義、MCP URLの払い出し                                           |
| Snowflakeセキュリティ管理者 | OAuth Security Integration、専用ロール、権限、client ID／secretの発行                            |
| Azure／ネットワーク担当者    | Private DNS、VPN、PrivateLink到達性、Snowflakeネットワークポリシー、OpenAI送信元IP許可                   |
| セキュリティ担当者          | 公開URL利用可否、読み取り／書き込み範囲、ログ、秘密情報管理の承認                                                 |

---

# 5. 構築前に他担当者から受け取る情報

次の情報を先に揃えてください。

## 5-1. ChatGPT側の情報

* 会社のChatGPTワークスペース名
* ChatGPTのプラン

  * Business
  * Enterprise
  * Edu
* あなたがワークスペース管理者か
* Developer Modeを利用できる権限があるか
* アプリを最終的にPublishできる管理者が誰か

Full MCPとDeveloper Modeは、主にChatGPT Business、Enterprise、EduのWeb版で提供されています。Enterprise／EduではRBACで特定利用者に開発権限を付与できますが、最終公開は管理者またはOwnerが行います。([OpenAI Help Center][2])

---

## 5-2. Snowflake／MCP担当者から受け取る情報

最低限、次の情報が必要です。

| 項目                  | 例                                        |
| ------------------- | ---------------------------------------- |
| 公開Snowflakeアカウントホスト | `xxxx-yyyy.azure.snowflakecomputing.com` |
| 公開Managed MCP URL   | 後述の完全なURL                                |
| PrivateLinkホスト名     | OAuthブラウザーテスト用                           |
| Database名           | `MCP_DB`                                 |
| Schema名             | `MCP_SCHEMA`                             |
| MCP Server名         | `CHATGPT_MCP`                            |
| Snowflake専用ロール      | `CHATGPT_MCP_ROLE`                       |
| Snowflake Warehouse | `CHATGPT_MCP_WH`                         |
| 公開されるツール一覧          | Search、Analyst、Read-only SQLなど           |
| 書き込みツールの有無          | 初期構築では「なし」を推奨                            |
| テスト対象ユーザー           | あなたのSnowflakeユーザー                        |
| テスト対象データ            | 機密性の低い検証データ                              |

Managed MCP ServerのURLは、次の完全な形式で受け取ってください。

```text
https://<公開Snowflakeアカウントホスト>/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER>
```

例：

```text
https://example-org-example-account.azure.snowflakecomputing.com/api/v2/databases/MCP_DB/schemas/MCP_SCHEMA/mcp-servers/CHATGPT_MCP
```

SnowsightのURL、SnowflakeのルートURLだけ、途中までのURLは使用できません。Database、Schema、MCP Serverまで含む完全なURLが必要です。ホスト名では、クライアントによってアンダースコアではなくハイフンが必要になる場合があります。([OpenAI Help Center][4])

---

# 6. Windows PCの事前確認

## 6-1. PowerShellを開く

操作場所は、実装先のWindows PCです。

1. Windowsの「スタート」を開きます。
2. `PowerShell`と入力します。
3. 「Windows PowerShell」または「ターミナル」を開きます。
4. 以下の確認は、通常、管理者権限なしで実行できます。
5. 社外から作業する場合は、会社のVPNに接続してから実行します。

---

## 6-2. PrivateLink用DNSとHTTPS接続を確認する

以下を**PowerShell**で実行します。

```powershell
$PrivateHost = "<Snowflake管理者から受け取ったPrivateLinkホスト名>" # PrivateLink用Snowflakeホスト名を変数に保存します。

Resolve-DnsName $PrivateHost # PrivateLinkホスト名が会社のDNSで正しく名前解決されるか確認します。

Test-NetConnection $PrivateHost -Port 443 # Windows PCからSnowflake PrivateLinkのHTTPSポート443へ接続できるか確認します。

Test-NetConnection "chatgpt.com" -Port 443 # Windows PCからChatGPT.comのHTTPSポート443へ接続できるか確認します。
```

正常時は、`Test-NetConnection`の結果に以下が表示されます。

```text
TcpTestSucceeded : True
```

ここで確認できるのは、あくまで次の通信です。

```text
Windows PC → Snowflake PrivateLink
Windows PC → ChatGPT.com
```

実際のMCP通信である次の経路は、このテストでは確認できません。

```text
OpenAIバックエンド → Snowflake Managed MCP Server
```

MCP要求の送信元はエンドユーザーのブラウザーではなく、OpenAIのインフラストラクチャです。([Snowflake Docs][5])

---

# 7. ChatGPT Developer Modeを有効化する

## 7-1. 画面名について

2026年7月9日以降、OpenAIはApp DirectoryをPlugin Directoryへ移行しています。

そのため、ワークスペースや段階的リリース状況によって、次の名称が混在する可能性があります。

| 新しい名称              | 以前の名称                |
| ------------------ | -------------------- |
| Plugins            | Apps Directory       |
| Apps               | Connectors           |
| Create app         | Create connector     |
| Developer-mode app | Custom MCP connector |

現在は、概ね次のように考えてください。

* アプリやテンプレートを探す場所：`Plugins`
* 作成済みアプリを管理する場所：`Workspace settings > Apps`
* Snowflakeの古い手順にある名称：`Settings > Connectors`

基盤となるMCPアプリ自体は引き続き`Apps`として管理されます。([OpenAI Help Center][6])

---

## 7-2. Businessの場合

操作場所：**EdgeまたはChromeで開いたChatGPT.com**

1. ChatGPT.comへログインします。
2. 会社のChatGPTワークスペースへ切り替えます。
3. `Workspace settings`を開きます。
4. `Apps`を開きます。
5. `Create`を選択します。
6. Developer Modeの有効化を求められた場合は有効にします。

Businessでは、原則としてAdminまたはOwnerがDeveloper Modeを利用し、アプリを作成・公開します。管理者ごとにDeveloper Modeの有効化が必要な場合があります。([OpenAI Help Center][2])

---

## 7-3. Enterprise／Eduの場合

### ワークスペース管理者が行う作業

操作場所：**ChatGPT.comのWorkspace settings**

1. `Workspace settings`を開きます。
2. `Permissions & roles`を開きます。
3. `Connected data`を開きます。
4. `Developer mode`または`Create custom MCP connectors`を許可します。
5. 必要に応じて、あなたが所属するロールまたはグループだけに許可します。

### あなたが行う作業

操作場所：**ChatGPT.comの個人Settings**

1. `Settings`を開きます。
2. `Apps`を開きます。
3. `Advanced Settings`を開きます。
4. `Developer mode`を有効にします。

Enterprise／Eduでは、開発権限を特定メンバーへ委任できます。ただし、完成したアプリのPublishはAdminまたはOwnerが行います。([OpenAI Help Center][2])

---

# 8. SnowflakeアプリをChatGPTへ登録する

## 8-1. 推奨：Snowflake公式テンプレートを使用する

OpenAIは、Snowflake Managed MCP Server用のSnowflakeアプリテンプレートを提供しています。テンプレートが表示される場合は、手動のCustom MCPアプリより、まずテンプレートを使用してください。([OpenAI Help Center][4])

操作場所：**ChatGPT.com**

1. 会社のワークスペースに切り替えます。
2. `Plugins`を開きます。
3. `Snowflake`を検索します。
4. SnowflakeのPluginまたはApp Templateを開きます。
5. `Setup`、`Enable`または類似のボタンを選択します。

画面によっては、公式手順どおり次の経路になっています。

```text
Workspace settings
  → Apps
    → Directory
      → Snowflake
```

6. アプリ名を入力します。

例：

```text
Snowflake - Read Only Analytics
```

7. 説明を入力します。

例：

```text
社内Snowflakeの承認済みデータを読み取り専用で検索するためのMCPアプリ
```

8. Snowflake担当者から受け取った**公開Managed MCP URL**を入力します。

```text
https://<公開Snowflakeホスト>/api/v2/databases/<DB>/schemas/<SCHEMA>/mcp-servers/<SERVER>
```

PrivateLink URLではありません。標準のSaaS構成では、必ず公開URLを使用します。([Snowflake Docs][5])

---

## 8-2. OAuthを選択する

認証方式を選ぶ画面では、以下を選びます。

```text
Authentication：OAuth
```

クライアント登録方式を選択できる場合は、次を選びます。

```text
Predefined OAuth client
Static OAuth client
Client ID and secret
```

表示名は画面によって異なります。

次は選択しません。

```text
Dynamic Client Registration
DCR
```

Snowflake Managed MCP ServerはDynamic Client Registrationをサポートしていないためです。([Snowflake Docs][5])

---

## 8-3. ChatGPTのCallback URIをコピーする

OAuth設定画面に、ChatGPTが使用するCallback URIが表示されます。

現在の形式は、次のようなものです。

```text
https://chatgpt.com/connector/oauth/<callback_id>
```

`<callback_id>`はアプリごとに異なります。

### 必ず守ること

* 画面に表示された値をそのままコピーする
* 手入力しない
* 末尾を変更しない
* 大文字・小文字を変更しない
* 古いCallback URIを流用しない
* Callback URIをSnowflake管理者へ渡す

ChatGPTは、このCallback URIにOAuthの認可コードを戻します。Snowflake側の`OAUTH_REDIRECT_URI`と一字一句一致している必要があります。([OpenAI Developers][1])

---

## 8-4. Snowflake管理者へ依頼する内容

次のように依頼します。

```text
ChatGPT Developer ModeからSnowflake Managed MCP Serverを利用します。

以下のCallback URIを使用して、Snowflake OAuthのCUSTOM／CONFIDENTIALクライアントを作成または更新してください。

Callback URI:
https://chatgpt.com/connector/oauth/<実際のcallback_id>

以下を設定してください。
・OAUTH_ENFORCE_PKCE = TRUE
・OAUTH_ISSUE_REFRESH_TOKENS = TRUE
・OAUTH_USE_SECONDARY_ROLES = NONE
・ALLOWED_ROLES_LIST = ('CHATGPT_MCP_ROLE')
・USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE

設定後、client IDとclient secretを安全な方法で共有してください。
```

client IDはアプリの識別子です。

client secretは、登録されたChatGPTアプリであることをSnowflakeへ証明する秘密情報です。メール、チャット本文、チケット、スクリーンショットには記載せず、会社の秘密情報共有手段を使用してください。

---

## 8-5. client IDとclient secretをChatGPTへ入力する

Snowflake管理者から受け取った値を、ChatGPTのOAuth設定画面に入力します。

```text
Client ID：Snowflakeから発行されたclient_id
Client Secret：Snowflakeから発行されたclient_secret
```

client secretを、次の場所へ入力しないでください。

* ChatGPTの会話欄
* PowerShell
* CMD
* メモ帳
* メール
* チケット
* 設計書の平文欄

入力場所は、ChatGPTのアプリ作成画面にあるClient Secret専用フィールドだけです。

---

## 8-6. ツールをスキャンする

Custom App作成画面の場合は、次を実行します。

1. `Scan Tools`を選択します。
2. OAuthログイン画面が表示されたらSnowflakeへログインします。
3. ツールスキャンの完了を待ちます。
4. 表示されたツール名を確認します。
5. `Create`を選択します。

公式テンプレートの場合は、設定を保存するとDraft Appが作成されます。

ChatGPTは、Snowflake Managed MCP Serverに定義されたツールだけを検出します。Snowflake Managed MCP Serverへの`USAGE`権限だけでなく、各ツールが使用するSearch Service、Semantic View、Agent、UDF、Procedure、Warehouseなどにも権限が必要です。([OpenAI Help Center][4])

---

## 8-7. Draft Appを公開する

操作場所：**ChatGPT.comのWorkspace settings**

1. `Workspace settings`を開きます。
2. `Apps`を開きます。
3. `Drafts`を開きます。
4. 作成したSnowflakeアプリを開きます。
5. MCP URL、認証方式、ツール一覧を確認します。
6. `Publish`を選択します。
7. `Enabled`に表示されることを確認します。

アプリをPublishできるのは、原則としてAdminまたはOwnerです。([OpenAI Help Center][2])

---

# 9. 公開時の推奨セキュリティ設定

初回は、全社公開せず少人数の試験グループだけに公開してください。

## 9-1. User access

```text
Workspace settings
  → Apps
    → 対象Snowflakeアプリ
      → User access
```

推奨設定：

```text
PoC利用者グループのみ
```

---

## 9-2. Action control

推奨設定：

```text
Allow only read actions
```

または、Customを選択して、承認済みの読み取りツールだけを有効化します。

新しく追加されたツールに対して選択肢がある場合は、次を選びます。

```text
Disable new actions
```

MCP Server側でツールが追加されても、自動的に有効化しないためです。OpenAIでは、管理者がツール変更をRefreshし、差分を確認して有効化する方式になっています。([OpenAI Help Center][2])

---

## 9-3. App permissions

初回検証では、次のいずれかを推奨します。

```text
Always ask
```

または

```text
Any changes
```

書き込み操作がない場合でも、最初のPoCでは`Always ask`にして、どのタイミングでアプリが呼び出されるかを確認すると安全です。

RBACは「誰が使えるか」、Action controlは「何ができるか」、App permissionsは「実行前に利用者へ確認するか」を制御します。([OpenAI Help Center][7])

---

# 10. 利用者が初回OAuthログインを行う

操作場所：**Windows PCのEdgeまたはChrome**

1. 会社のLANまたはVPNへ接続します。
2. ChatGPT.comを開きます。
3. 新しいチャットを開きます。
4. ツールまたはPluginメニューからSnowflakeアプリを選択します。
5. `Connect`を選択するか、Snowflakeツールを使用するプロンプトを入力します。
6. Snowflakeのログイン画面が表示されます。
7. PrivateLink設定が正しければ、ブラウザーはPrivateLink側の認可画面へリダイレクトされます。
8. Snowflakeへログインします。
9. OAuthの同意内容とロールを確認します。
10. 承認します。
11. ChatGPTのCallback URIへ戻ります。
12. Snowflakeツールが利用可能になることを確認します。

OAuth Security Integrationのclient IDとsecretはアプリで共通ですが、**Snowflakeへのログインとアクセストークンは利用者ごとに発行されます**。([Snowflake Docs][5])

---

# 11. OAuthの動きを初心者向けに説明

OAuthでは、SnowflakeのパスワードをChatGPTへ直接渡しません。

## 11-1. 登場するもの

| 用語                   | 今回の構成                        |
| -------------------- | ---------------------------- |
| OAuth Client         | ChatGPTのSnowflakeアプリ         |
| Authorization Server | Snowflake OAuth              |
| Resource Server      | Snowflake Managed MCP Server |
| User                 | Snowflakeへログインする社員           |
| Callback URI         | 認証後に戻るChatGPTのURL            |
| Access Token         | Snowflakeツールを使うための一時的な通行証    |
| Refresh Token        | Access Tokenを更新するための情報       |
| PKCE                 | 認可コードが盗まれても悪用されにくくする仕組み      |

---

## 11-2. 実際の処理

```text
1. ChatGPTがSnowflake MCPの認証情報を調べる
         ↓
2. ChatGPTがブラウザーをSnowflakeのログイン画面へ送る
         ↓
3. 利用者がSnowflakeへログインする
         ↓
4. Snowflakeが認可コードをChatGPT Callback URIへ返す
         ↓
5. OpenAIバックエンドが認可コードをAccess Tokenへ交換する
         ↓
6. OpenAIバックエンドがAccess Tokenを付けてMCPを呼び出す
         ↓
7. Snowflakeがユーザー、ロール、期限、権限を確認する
         ↓
8. 許可されている場合だけMCPツールを実行する
```

ChatGPTはAuthorization CodeフローとPKCE S256を使用し、その後のMCP要求にBearer Tokenを付けます。([OpenAI Developers][1])

---

## 11-3. Azure上のSnowflakeとMicrosoft Entra IDは別の話です

SnowflakeがAzure上に存在していても、OAuth発行元が自動的にMicrosoft Entra IDになるわけではありません。

この手順では次を使用します。

```text
Snowflake OAuth
OAUTH_CLIENT = CUSTOM
```

既存のSnowflakeログインがMicrosoft Entra IDによるSSOの場合、利用者のログイン処理ではEntra IDの画面を経由することがあります。しかし、ChatGPT用OAuthクライアントとアクセストークンの管理主体はSnowflakeです。

今回の組み合わせについて、Microsoft Entra External OAuthを直接使用する公式な完全手順は確認できませんでした。そのため、まずはSnowflakeが公式に案内しているSnowflake OAuth方式を採用するのが安全です。

---

# 12. Snowflake管理者向けOAuth設定例

以下は、あなたがWindowsのCMDやPowerShellで実行するものではありません。

**実行場所：Snowflake Snowsight → Projects → Worksheets**

**実行者：Snowflakeセキュリティ管理者**

既存環境に合わせた変更が必要なので、そのまま無条件で実行しないでください。

```sql
CREATE SECURITY INTEGRATION CHATGPT_MCP_OAUTH                       -- ChatGPT用のSnowflake OAuth Security Integrationを作成します。
  TYPE = OAUTH                                                      -- このSecurity IntegrationがOAuth認証用であることを指定します。
  OAUTH_CLIENT = CUSTOM                                             -- ChatGPTをカスタムOAuthクライアントとして登録します。
  ENABLED = TRUE                                                    -- 作成したOAuth連携を有効にします。
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'                                -- ChatGPTのサーバー側でclient secretを安全に保持する方式を使用します。
  OAUTH_REDIRECT_URI = 'https://chatgpt.com/connector/oauth/<callback_id>' -- ChatGPT画面に表示されたCallback URIを一字一句そのまま設定します。
  OAUTH_ENFORCE_PKCE = TRUE                                         -- ChatGPTが使用するPKCEを必須にして認可コードを保護します。
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE                                 -- Access Tokenの期限切れ後に更新できるようRefresh Tokenを発行します。
  OAUTH_USE_SECONDARY_ROLES = NONE                                  -- MCP OAuthセッションでセカンダリロールを使用しないようにします。
  ALLOWED_ROLES_LIST = ('CHATGPT_MCP_ROLE')                         -- このOAuth連携で使用できるロールを専用ロールだけに限定します。
  USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE                 -- 利用者のブラウザーログインをPrivateLink側の認可画面へリダイレクトします。
  COMMENT = 'ChatGPT Snowflake Managed MCP OAuth';                  -- 管理者が用途を識別できるコメントを設定します。
```

`CONFIDENTIAL`は、クラウド上の保護されたサービスがclient secretを保持する場合に使用します。SnowflakeはPKCEの必須化を推奨しており、ChatGPTはPKCE S256を使用します。([Snowflake Docs][8])

---

## 12-1. 既存IntegrationのCallback URIだけ変更する場合

```sql
ALTER SECURITY INTEGRATION CHATGPT_MCP_OAUTH                        -- 既存のChatGPT用OAuth Security Integrationを変更します。
  SET OAUTH_REDIRECT_URI = 'https://chatgpt.com/connector/oauth/<callback_id>'; -- 新しいChatGPTアプリに表示されたCallback URIへ更新します。
```

ChatGPTアプリを作り直すと、Callback URIが変わる可能性があります。その場合はSnowflake側も更新する必要があります。

---

## 12-2. client IDとclient secretを取得する

```sql
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('CHATGPT_MCP_OAUTH'); -- ChatGPTへ登録するclient IDとclient secretを取得します。
```

Integration名は大文字・小文字の扱いに注意が必要です。Snowflake Managed MCPの公式手順では、Integration名を大文字で指定するよう案内されています。([Snowflake Docs][5])

---

## 12-3. 専用ロールとWarehouseをユーザーへ設定する

```sql
GRANT ROLE CHATGPT_MCP_ROLE TO USER <SNOWFLAKE_USER_NAME>; -- 対象ユーザーへChatGPT MCP専用ロールを付与します。

ALTER USER <SNOWFLAKE_USER_NAME>                           -- 対象ユーザーの既定セッション設定を変更します。
  SET DEFAULT_ROLE = 'CHATGPT_MCP_ROLE'                    -- MCP OAuthセッションが使用する既定ロールを専用ロールへ設定します。
      DEFAULT_WAREHOUSE = 'CHATGPT_MCP_WH';                -- MCPセッションとSQLツールが使用する既定Warehouseを設定します。
```

Snowflake Managed MCPのOAuthセッションでは、接続ユーザーの`DEFAULT_ROLE`が使用され、セカンダリロールはサポートされません。また、`DEFAULT_WAREHOUSE`がNULLの場合はセッション初期化に失敗します。([Snowflake Docs][5])

> `DEFAULT_ROLE`の変更は、利用者が通常のSnowsightやSQLクライアントを使う際の初期ロールにも影響します。既存ユーザーのDEFAULT_ROLEを変更してよいか、必ずSnowflakeのIAM担当者と確認してください。

共通のSnowflakeユーザーを複数人で使う方式は避け、原則としてユーザーごとにOAuth認証してください。

---

## 12-4. MCP Serverへの最小権限

```sql
GRANT USAGE ON DATABASE <DATABASE_NAME> TO ROLE CHATGPT_MCP_ROLE; -- MCP Serverが存在するDatabaseへアクセスする権限を付与します。

GRANT USAGE ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE CHATGPT_MCP_ROLE; -- MCP Serverが存在するSchemaへアクセスする権限を付与します。

GRANT USAGE ON MCP SERVER <DATABASE_NAME>.<SCHEMA_NAME>.<MCP_SERVER_NAME> TO ROLE CHATGPT_MCP_ROLE; -- MCP Serverの発見とツール呼び出しを許可します。

GRANT USAGE ON WAREHOUSE CHATGPT_MCP_WH TO ROLE CHATGPT_MCP_ROLE; -- SQL系ツールがWarehouseを利用できるようにします。
```

これだけでは、ツールの実行権限がすべて揃うとは限りません。

例えば次の追加権限が必要です。

* Cortex Search Serviceへの`USAGE`
* Semantic Viewへの`SELECT`
* Cortex Agentへの`USAGE`
* Stored Procedureへの`USAGE`
* UDFへの`USAGE`
* SQLツールが参照するテーブルやビューへの`SELECT`

MCP Serverへの`USAGE`権限を付与しても、内部ツールが参照するオブジェクトへの権限は自動的に付与されません。([Snowflake Docs][5])

---

## 12-5. 設定確認

```sql
DESCRIBE SECURITY INTEGRATION CHATGPT_MCP_OAUTH; -- OAuth Security Integrationの設定値を確認します。

SHOW GRANTS TO ROLE CHATGPT_MCP_ROLE; -- MCP専用ロールへ付与されている権限を一覧表示します。

SHOW MCP SERVERS IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME>; -- 対象Schemaに存在するMCP Serverを一覧表示します。

DESCRIBE MCP SERVER <DATABASE_NAME>.<SCHEMA_NAME>.<MCP_SERVER_NAME>; -- 対象MCP Serverのツール定義を確認します。
```

---

# 13. OpenAI送信元IPアドレスの許可

Snowflakeにネットワークポリシーを設定している場合、ChatGPTのMCP要求は利用者PCではなく、OpenAIの送信元IPアドレスから到着します。

OpenAIはChatGPT連携用の送信元IP一覧を公開しています。ただし、そのIP一覧は変更される可能性があるため、固定値を設計書へ転記するのではなく、公開JSONから定期取得してください。IP許可はOpenAIのネットワークからの通信であることを示すだけで、特定のワークスペースや利用者を識別するものではありません。OAuthとSnowflakeの権限制御は別途必須です。([OpenAI Developers][9])

## 13-1. 最新IP一覧を取得する

操作場所：**Windows PowerShell**

```powershell
$OpenAIRanges = Invoke-RestMethod -Uri "https://openai.com/chatgpt-connectors.json" # OpenAIが現在公開しているChatGPT連携用の送信元IP情報を取得します。

$OpenAIRanges.creationTime # IP一覧が作成された日時を表示します。

$Prefixes = $OpenAIRanges.prefixes | ForEach-Object { # 公開JSONのprefixes配列を1件ずつ処理します。
    if ($_ -is [string]) { $_ } # プレフィックスが文字列形式なら、その値をそのまま返します。
    elseif ($_.ipv4Prefix) { $_.ipv4Prefix } # IPv4のオブジェクト形式ならipv4Prefixの値を返します。
    elseif ($_.ipv6Prefix) { $_.ipv6Prefix } # IPv6のオブジェクト形式ならipv6Prefixの値を返します。
}

$Prefixes # 取得したCIDR一覧をPowerShell画面へ表示します。

$Prefixes | Set-Content -Encoding utf8 ".\chatgpt-connectors-cidrs.txt" # CIDR一覧を現在のフォルダーへUTF-8のテキストファイルとして保存します。
```

作成された`chatgpt-connectors-cidrs.txt`を、Snowflakeネットワーク担当者へ安全な方法で渡します。

Snowflake側では、以下を区別する必要があります。

| 通信                     | 主に適用されるポリシー                                   |
| ---------------------- | --------------------------------------------- |
| 利用者ブラウザーによるOAuthログイン   | ユーザーまたはアカウントのネットワークポリシー                       |
| OpenAIバックエンドによるトークン交換  | OAuth Security Integrationまたはアカウントのネットワークポリシー |
| OpenAIバックエンドによるMCP呼び出し | OAuth Security Integrationまたはアカウントのネットワークポリシー |

SnowflakeのOAuth Security Integrationに関連付けたネットワークポリシーは、トークン交換およびAccess Tokenを使ったSnowflakeリソースアクセスに適用されます。([Snowflake Docs][3])

---

# 14. 接続試験

## 14-1. ツール一覧確認

ChatGPTでSnowflakeアプリだけを選択し、次のように入力します。

```text
Snowflakeアプリだけを使用してください。
利用可能なツールの名前と説明を一覧表示してください。
データの変更や書き込み操作は実行しないでください。
```

確認する点：

* MCP担当者から聞いているツールだけが表示される
* 不明な書き込みツールがない
* ツール名と説明が分かりやすい
* 同じ用途の重複ツールがない

---

## 14-2. 読み取り試験

```text
Snowflakeの読み取り専用ツールを使用して、
承認済みのテストデータを最大10件だけ取得してください。
書き込み操作は実行しないでください。
```

確認する点：

* 結果が10件以内
* 想定したテーブル、Search Service、Semantic Viewだけを使用
* 正しいWarehouseを使用
* Snowflake Query Historyに想定したユーザーとロールが記録される

---

## 14-3. 権限境界の試験

```text
Snowflakeアプリを使用して、
現在の専用ロールに許可されていないテスト用オブジェクトへアクセスしてください。
```

この試験は、事前にSnowflake管理者と相談して、アクセス拒否確認用の無害なオブジェクトを用意して行います。

期待する結果：

```text
アクセス拒否
権限不足
対象オブジェクトを参照できない
```

アクセスできてしまった場合は、ロールまたはオブジェクト権限が広すぎます。

OpenAIのSnowflakeテンプレート手順でも、最初に低リスクな読み取り操作を実行し、承認範囲外のアクセスがSnowflake権限で防止されることを確認するよう案内されています。([OpenAI Help Center][4])

---

# 15. よくあるエラーと確認箇所

| 現象                              | 主な原因                                         | 確認箇所                                |
| ------------------------------- | -------------------------------------------- | ----------------------------------- |
| Developer Modeが表示されない           | 対象プランではない、会社ワークスペースではない、権限不足                 | ワークスペース、プラン、RBAC                    |
| Snowflakeテンプレートが見つからない          | Plugins移行、管理者に無効化されている、段階的展開                 | Plugins、Apps Directory、管理者設定        |
| `MCP server not found`          | URLが不完全、Snowsight URLを入力、DB／Schema／Server名違い | 完全な公開MCP URL                        |
| OAuth Callbackエラー               | Snowflakeに登録したURIとChatGPT表示値が不一致             | `OAUTH_REDIRECT_URI`                |
| Snowflakeログイン画面が開かない            | VPN未接続、Private DNS不備、PrivateLink認可設定なし       | VPN、DNS、`USE_PRIVATELINK...`        |
| ログイン後に失敗する                      | OpenAI送信元IPがSnowflakeで拒否されている                | Network Policy、OpenAI CIDR          |
| ツールが一つも表示されない                   | MCP Serverにツールがない、ロールにMCP ServerのUSAGEがない    | MCP仕様、`GRANT USAGE ON MCP SERVER`   |
| ツールは見えるが実行できない                  | 内部オブジェクトへの権限不足                               | Search、View、Agent、UDF等の権限           |
| SQLツールが失敗する                     | Warehouse名違い、USAGEなし、DEFAULT_WAREHOUSEがNULL  | ユーザー設定、Warehouse                    |
| 想定外のデータへアクセスできる                 | DEFAULT_ROLEまたはロール権限が広すぎる                    | `DEFAULT_ROLE`、`ALLOWED_ROLES_LIST` |
| 何度も再認証を求められる                    | Refresh Tokenが無効または期限切れ                      | `OAUTH_ISSUE_REFRESH_TOKENS`        |
| PCからはSnowflakeへ接続できるがChatGPTは失敗 | 実際のMCP要求はOpenAIサーバーから送信される                   | OpenAI CIDR、公開MCP URL               |
| MCP側でツールを追加したがChatGPTに出ない       | 公開済みツールは固定スナップショット                           | AppsのAction controlでRefresh         |
| アプリを作り直したらOAuthが失敗              | Callback URIが変更された                           | SnowflakeのRedirect URIを更新           |

---

# 16. Snowflake Managed MCP Serverの主な制限

現時点のSnowflake Managed MCP Serverには、次の制限があります。

* MCPの`tools`機能が中心
* Resources、Prompts、Roots、Samplingなどは未サポート
* 非ストリーミング応答のみ
* 1つのMCP Serverあたり最大50ツール
* SQLツールとGeneric Toolの応答は250KBで切り詰められる
* OAuthセッションではセカンダリロールを使用できない
* 接続ユーザーの`DEFAULT_ROLE`が使用される

そのため、ChatGPTのツールスキャンでResourcesやPromptsが表示されないのは、必ずしも不具合ではありません。([Snowflake Docs][5])

---

# 17. 公開MCP URLを使用できない場合：Secure MCP Tunnel

## 17-1. Secure MCP Tunnelの構成

会社のセキュリティ方針で、Snowflake Managed MCP Serverの公開URLをOpenAIから呼び出すことが認められない場合、OpenAIのSecure MCP Tunnelを検討できます。

```text
OpenAI ChatGPTバックエンド
          │
          ▼
OpenAI Secure MCP Tunnelサービス
          ▲
          │ 外向きHTTPS 443のみ
          │
Azure VNet内のtunnel-client
          │
          │ PrivateLink
          ▼
Snowflake PrivateLink Managed MCP URL
```

`tunnel-client`をSnowflake PrivateLinkへ到達できるAzure VNet内で実行します。

`tunnel-client`側からOpenAIへ外向きHTTPS接続を確立するため、Azure側にインターネットからの受信ポートを開ける必要はありません。([OpenAI Developers][10])

---

## 17-2. 本番では利用者PCではなくAzure VM上で動かす

Windows PC上で検証することは可能ですが、本番では次のような場所が適しています。

```text
Azure VNet内のWindows Server VM
Azure VNet内のLinux VM
AKS
既存の常時稼働コンテナ環境
```

利用者PCで動かすと、次の場合にChatGPTから接続できなくなります。

* PCをシャットダウンした
* PCがスリープした
* VPNを切断した
* PowerShell画面を閉じた
* `tunnel-client`が停止した

OpenAIも、ツール検出とMCP呼び出しの間は`tunnel-client`を継続稼働させる必要があると説明しています。([OpenAI Developers][10])

---

## 17-3. Tunnelの事前準備

OpenAI Platform側で、次が必要です。

* `tunnel_id`
* Tunnel実行用Runtime API Key
* Platform OrganizationでのTunnel権限
* 対象ChatGPTワークスペースとの関連付け

権限は次のように分かれます。

| 作業                   | 必要な権限                 |
| -------------------- | --------------------- |
| Tunnelの作成・変更         | Tunnels Read + Manage |
| tunnel-clientの実行     | Tunnels Read + Use    |
| ChatGPTアプリでTunnelを選択 | Tunnels Read + Use    |
| Developer Mode利用     | ChatGPTワークスペース側の別権限   |

Tunnel権限とChatGPT Developer Mode権限は別物です。([OpenAI Developers][10])

---

## 17-4. WindowsでのTunnel検証コマンド

操作場所：**Azure VNet内のWindows VMのPowerShell**

まず、OpenAI PlatformのTunnel管理画面から、現在サポートされている`tunnel-client`をダウンロードし、例えば次のフォルダーへ展開します。

```text
C:\Tools\OpenAI-Tunnel
```

PowerShellで実行します。

```powershell
Set-Location "C:\Tools\OpenAI-Tunnel" # tunnel-client.exeを展開したフォルダーへ移動します。

.\tunnel-client.exe --version # 実行ファイルが正しく起動し、バージョンを表示できるか確認します。

.\tunnel-client.exe help quickstart # インストールしたバージョンに対応する公式の最短セットアップ手順を表示します。

$env:CONTROL_PLANE_API_KEY = "<OPENAI_RUNTIME_API_KEY>" # OpenAI Tunnelへ接続するためのRuntime API Keyを現在のPowerShellに設定します。

$env:CONTROL_PLANE_TUNNEL_ID = "<tunnel_id>" # OpenAI Platformで作成したTunnel IDを現在のPowerShellに設定します。

$env:MCP_SERVER_URL = "https://<PrivateLinkホスト>/api/v2/databases/<DB>/schemas/<SCHEMA>/mcp-servers/<SERVER>" # Azure VNet内からPrivateLinkで到達できるSnowflake Managed MCP URLを設定します。

.\tunnel-client.exe doctor --explain # OpenAI Tunnel、Snowflake MCP、OAuthメタデータなどの到達性と設定を診断します。

.\tunnel-client.exe run --log.level=info --log.format=struct-text # Tunnelを前景実行し、ChatGPTからのMCP要求をPrivateLink先へ中継します。
```

最後の`run`を実行したPowerShell画面は閉じないでください。

Runtime API KeyをPowerShellへ直接入力した行は、PowerShellの履歴に残る可能性があります。検証では短期間だけ使用するRuntime Keyを使い、本番ではWindowsのSecret Store、Azure Key Vault、環境変数注入、ファイル参照などを使用してください。

---

## 17-5. Tunnelの稼働確認

別のPowerShell画面を開き、次を実行します。

```powershell
Invoke-RestMethod "http://127.0.0.1:8080/healthz" # tunnel-clientプロセスが起動しているか確認します。

Invoke-RestMethod "http://127.0.0.1:8080/readyz" # OpenAI Tunnelへの接続を含め、MCP要求を処理できる状態か確認します。

Start-Process "http://127.0.0.1:8080/ui" # tunnel-clientのローカル管理画面を既定ブラウザーで開きます。
```

---

## 17-6. ChatGPT側でTunnelを選択する

操作場所：**ChatGPT.com**

```text
Settings
  → Plugins
    → ＋
      → Create developer-mode app
        → Connection
          → Tunnel
```

作成済みのTunnelを選択するか、`tunnel_id`を入力します。

Tunnelが表示されない場合は、次を確認します。

* Tunnelが対象ChatGPTワークスペースと関連付けられているか
* Platform Organizationだけに関連付けられていないか
* あなたにTunnels Read + Useがあるか
* `tunnel-client run`が継続稼働しているか

ChatGPTでは、Developer ModeアプリのConnectionとしてTunnelを選択できます。([OpenAI Developers][10])

---

## 17-7. Secure MCP TunnelとOAuthの注意事項

Secure MCP Tunnelは、MCP Serverの通信をプライベートに保つためのトランスポートです。

しかし、OpenAIは次の点を明記しています。

* OAuth discoveryはTunnel経由で取得できる
* OAuthのメタデータは保持される
* OAuth Authorization Server自体は自動的にはTunnel化されない
* Authorization Serverへ必要な場所から到達できない場合、MCPに到達できてもOAuthは失敗する

([OpenAI Developers][10])

また、SnowflakeはSaaSクライアントの場合、トークン要求をSaaSバックエンドから行うため、トークンエンドポイントは公開URLである必要があると説明しています。([Snowflake Docs][3])

したがって、現時点で判断できるのは次のとおりです。

| 要件                                | 状況                         |
| --------------------------------- | -------------------------- |
| Snowflake MCP本体だけPrivateLinkにしたい  | Secure MCP TunnelによるPoCが可能 |
| Snowflakeトークンエンドポイントの公開利用は許可できる   | Tunnel構成を検証する余地あり          |
| OAuth認可・トークン・MCPのすべてを完全プライベートにしたい | 公式の完成した手順を確認できていない         |

Snowflake Managed MCP、Snowflake OAuth、Secure MCP Tunnelを組み合わせた完全なPrivateLink-only構成については、OpenAIまたはSnowflakeのサポートへ構成可否を確認してください。

---

# 18. 現時点で明確に分からない点

情報の正確性を優先し、確認できなかった点を明記します。

### 18-1. 画面名称の完全な統一状況

2026年7月9日にApp DirectoryからPlugin Directoryへの移行が行われたため、ワークスペースによって次の表示が残っている可能性があります。

* Plugins
* Apps
* Connectors
* Directory
* Advanced Settings

基盤となる操作は同じですが、画面名称は段階的展開によって異なる可能性があります。

---

### 18-2. Secure MCP TunnelとSnowflake OAuthの完全な組み合わせ

Secure MCP Tunnel自体はChatGPT Developer Modeで公式サポートされています。

ただし、Snowflake Managed MCP Server、Snowflake OAuth CUSTOMクライアント、PrivateLink、Secure MCP Tunnelを一体化した完成手順は、SnowflakeまたはOpenAIから明示的には公開されていません。

---

### 18-3. Microsoft Entra External OAuth

Microsoft Entra IDをSnowflakeのExternal OAuth発行元として使用する一般的な構成は存在しますが、今回のChatGPT Developer ModeからSnowflake Managed MCP Serverへの接続について、公式に確認できた手順はSnowflake OAuth方式です。

---

### 18-4. Single-use Refresh Token

Snowflakeには、次の設定があります。

```sql
OAUTH_SINGLE_USE_REFRESH_TOKENS_REQUIRED = TRUE
```

ただし、ChatGPTとの組み合わせでこの設定を必須化した公式な動作確認情報は確認できませんでした。

初回PoCではデフォルトの`FALSE`で検証し、会社のセキュリティポリシーで必須の場合は別途互換性試験を行うのが安全です。

---

# 19. あなたが実際に行う順番

最終的な作業順序は、次のとおりです。

1. 会社が公開Snowflake MCP URLを許可するか確認する
2. ChatGPTプランと自分のDeveloper Mode権限を確認する
3. Snowflake担当者から完全な公開Managed MCP URLを受け取る
4. Snowflake専用ロール、Warehouse、ツール一覧を確認する
5. Windows PCを会社LANまたはVPNへ接続する
6. PrivateLinkホスト名のDNSと443接続をPowerShellで確認する
7. ChatGPT Developer Modeを有効にする
8. PluginsまたはApps DirectoryからSnowflakeテンプレートを開始する
9. 公開Managed MCP URLを入力する
10. OAuthを選択する
11. ChatGPTに表示されたCallback URIをコピーする
12. Callback URIをSnowflake管理者へ渡す
13. Snowflake管理者にOAuth Security Integrationを作成してもらう
14. client IDとclient secretを安全に受け取る
15. ChatGPTの専用フィールドへ入力する
16. Tool ScanまたはDraft作成を行う
17. ツール一覧が想定どおりか確認する
18. 管理者にDraft AppをPublishしてもらう
19. User accessをPoCグループだけに限定する
20. Action controlを読み取り専用にする
21. App permissionsを`Always ask`にする
22. SnowflakeへユーザーごとにOAuthログインする
23. 読み取り試験を行う
24. 権限外データへのアクセス拒否試験を行う
25. Snowflake Query HistoryとChatGPT側ログを確認する
26. 問題がなければ段階的に利用者を拡大する

---

## 最終的な推奨

今回の条件で、公式情報が最も揃っている構成は以下です。

```text
ChatGPT Snowflake App Template
  ＋
Snowflake Managed MCP Serverの公開URL
  ＋
Snowflake OAuth CUSTOM / CONFIDENTIAL
  ＋
PKCE
  ＋
利用者の認可画面だけPrivateLink
  ＋
OpenAI送信元IPをSnowflake Network Policyで制限
  ＋
Snowflake専用ロール
  ＋
読み取り専用ツールからPoC
```

ただし、この構成は**エンドツーエンドのPrivateLink構成ではありません**。

会社の要件が「OpenAIからSnowflake Managed MCP Serverへの通信も必ずプライベートでなければならない」である場合は、Secure MCP TunnelをAzure VNet内に配置する構成へ切り替え、Snowflake OAuthの公開トークンエンドポイント利用が許可されるかを含めて、事前にOpenAI・Snowflake双方へ確認する必要があります。

[1]: https://developers.openai.com/apps-sdk/build/auth "https://developers.openai.com/apps-sdk/build/auth"
[2]: https://help.openai.com/en/articles/12584461-developer-mode-and-mcp-apps-in-chatgpt "https://help.openai.com/en/articles/12584461-developer-mode-and-mcp-apps-in-chatgpt"
[3]: https://docs.snowflake.com/user-guide/oauth-snowflake-overview "https://docs.snowflake.com/user-guide/oauth-snowflake-overview"
[4]: https://help.openai.com/articles/20001249 "https://help.openai.com/articles/20001249"
[5]: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp "https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp"
[6]: https://help.openai.com/en/articles/20001256-plugins-in-codex "https://help.openai.com/en/articles/20001256-plugins-in-codex"
[7]: https://help.openai.com/ms-my/articles/11509118-admin-controls-security-and-compliance-for-plugins-and-apps "https://help.openai.com/ms-my/articles/11509118-admin-controls-security-and-compliance-for-plugins-and-apps"
[8]: https://docs.snowflake.com/sql-reference/sql/create-security-integration-oauth-snowflake "https://docs.snowflake.com/sql-reference/sql/create-security-integration-oauth-snowflake"
[9]: https://developers.openai.com/api/docs/guides/ip-addresses "https://developers.openai.com/api/docs/guides/ip-addresses"
[10]: https://developers.openai.com/api/docs/guides/secure-mcp-tunnels "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels"
