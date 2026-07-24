# Snowflake-managed MCP サーバーを Claude.ai から利用するための構築・設定手順

**調査時点：2026年7月24日**

## 1. 最初に結論

### Claude.ai は OAuth に対応しています

Claude.ai の「カスタムコネクタ」は、OAuth で保護されたリモートMCPサーバーへの接続をサポートしています。また、Snowflake-managed MCP サーバーは Snowflake OAuth に対応しています。

Snowflake-managed MCP サーバーは動的クライアント登録、いわゆるDCRには対応していませんが、Claude.aiでは「OAuth Client ID」と「OAuth Client Secret」を手動入力できるため、両者は接続可能です。 ([Snowflake Docs][1])

### ただし、Claude.aiからMCPをPrivateLinkだけで利用することはできません

ここが最重要です。

Claude.aiに設定したリモートMCPコネクタからの通信は、利用者のWindows PCではなく、**Anthropicのクラウド環境**から発信されます。そのため、Anthropicから到達できないSnowflake PrivateLink URLをClaude.aiに登録しても接続できません。 ([Claudeヘルプセンター][2])

Snowflake公式が案内している構成は、次の「ハイブリッド構成」です。

* Claude.aiには、**Snowflakeの公開MCP URL**を登録する
* SnowflakeのOAuth認証画面だけをPrivateLink側へリダイレクトする
* OAuthトークン交換とMCPツール呼び出しは、AnthropicクラウドからSnowflakeの公開URLへ行う
* Snowflakeのネットワークポリシーで、Anthropicの送信元IPだけを許可する
* OAuth、専用ロール、Snowflakeの権限制御で保護する

Snowflakeは、Claude.aiのようなSaaS MCPクライアントでは、PrivateLink URLではなく公開MCP URLを使用し、OAuthセキュリティ統合に `USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE` を設定するよう明記しています。 ([Snowflake Docs][1])

したがって、会社の要件が次のどちらかで結論が変わります。

| 会社のセキュリティ要件                                               | Claude.aiでの実現可否     |
| --------------------------------------------------------- | ------------------- |
| ユーザーがSnowflakeにログインする画面はPrivateLinkを使用したい                 | **実現可能**            |
| MCPの処理は公開URLを使用してよいが、AnthropicのIP、OAuth、専用ロールで制限したい       | **実現可能**            |
| Snowflakeとの通信は、認証・トークン・MCP・検索結果を含めてすべてPrivateLinkだけに限定したい | **Claude.aiでは実現不可** |
| Snowflakeの公開エンドポイントを一切許可できない                              | **Claude.aiでは実現不可** |

---

# 2. 完成後の構成

```text
┌─────────────────────────────────────────────────────┐
│ Windows PC                                          │
│ ・Edge / Chrome                                     │
│ ・会社ネットワークまたはVPN                         │
│ ・PrivateLink用DNSを利用可能                        │
└──────────────┬──────────────────────┬───────────────┘
               │                      │
               │ ① Claude.aiを操作    │ ③ Snowflakeの認証・同意
               │    公開HTTPS         │    PrivateLink経由
               ▼                      ▼
┌─────────────────────────┐   ┌─────────────────────────┐
│ Anthropicクラウド       │   │ Snowflake Azure環境     │
│                         │   │                         │
│ ・Claude.ai             │   │ PrivateLinkエンドポイント│
│ ・リモートMCPクライアント│   │ ・ユーザー認証          │
│ ・OAuthトークン保持     │   │ ・OAuth同意画面          │
└──────────────┬──────────┘   └─────────────────────────┘
               │
               │ ② OAuth開始
               │ ④ トークン交換
               │ ⑤ MCP tools/list、tools/call
               │ ⑥ 検索結果・SQL結果
               │
               │ 公開HTTPS
               │ 送信元IPをSnowflakeで制限
               ▼
┌─────────────────────────────────────────────────────┐
│ Snowflake公開エンドポイント                        │
│ ・OAuth Token Endpoint                              │
│ ・Snowflake-managed MCP Endpoint                    │
│ ・OAuthアクセストークン検証                         │
│ ・DEFAULT_ROLE、RBAC、Warehouseによる権限制御       │
└─────────────────────────────────────────────────────┘
```

重要なのは、次の2点です。

1. **Windows PCからMCPサーバーへ直接接続するわけではありません。**
2. Snowflakeの検索結果やSQL結果は、公開HTTPS上で暗号化されてSnowflakeからAnthropicクラウドへ渡り、その後Claude.aiの会話で利用されます。

PrivateLinkが使われるのは、主として利用者ブラウザーとSnowflakeのOAuth認可画面の間です。OAuth開始時のクライアント通信、トークン交換、実際のMCP呼び出しまでPrivateLinkになるわけではありません。 ([Snowflake Docs][3])

---

# 3. 今回の「クライアント構築」で実際に行うこと

Claude.aiを利用する場合、Windows PCにPython、Node.js、MCP SDKなどをインストールしてクライアントプログラムを作る必要はありません。

主な作業は次の3つです。

| 作業                           | 担当                     | 操作する画面                            |
| ---------------------------- | ---------------------- | --------------------------------- |
| Snowflake-managed MCPサーバーの作成 | MCPサーバー担当者             | Snowflake SnowsightのSQL Worksheet |
| OAuth、ネットワークポリシー、ロール設定       | Snowflake管理者・ネットワーク管理者 | Snowflake SnowsightのSQL Worksheet |
| Claude.aiへのカスタムコネクタ登録        | あなた、またはClaude組織のOwner  | Claude.aiのWeb画面                   |
| 各利用者のOAuthログイン               | 各利用者                   | Claude.aiとSnowflakeのWeb画面         |
| PrivateLink DNS、443番ポート確認    | あなた、またはネットワーク担当者       | Windows PowerShell、ブラウザー          |

したがって、あなたの主作業では、**CMDを使ったクライアントプログラムの構築はありません**。

また、Claude Desktop用の `claude_desktop_config.json` は、Claude.aiサイトの設定には使用しません。Claude.aiのリモートコネクタはAnthropicクラウド経由であり、Claude DesktopのローカルMCPとは別機能です。 ([Claudeヘルプセンター][2])

---

# 4. Snowflake管理者・MCPサーバー担当者から受け取る情報

Claude.aiを設定する前に、次の情報を受け取ってください。

| 必要な情報               | 内容                                              |
| ------------------- | ----------------------------------------------- |
| コネクタ表示名             | 例：`Snowflake MCP - PROD - ReadOnly`             |
| **公開MCP URL**       | PrivateLink URLではなく、Snowflakeの公開アカウントURLを使用したもの |
| OAuth Client ID     | Snowflake OAuthセキュリティ統合から取得                     |
| OAuth Client Secret | Snowflake OAuthセキュリティ統合から取得                     |
| OAuthリダイレクトURI      | Claude画面に表示された値とSnowflake設定が一致していること            |
| Snowflakeユーザー名      | 各利用者が個別に認証するためのユーザー                             |
| MCP用DEFAULT_ROLE    | MCPサーバーと各ツールに必要な権限を持つ専用ロール                      |
| DEFAULT_WAREHOUSE   | ユーザーの既定Warehouse                                |
| テスト用ツール名            | 最初に呼び出す読み取り専用ツール                                |
| ネットワーク設定完了の確認       | Anthropicの送信元IPがSnowflake側で許可されていること            |
| PrivateLink認証用ホスト名  | WindowsからDNS、HTTPS確認を行うためのホスト名                  |

MCP URLの形式は次のとおりです。

```text
https://<PUBLIC_ACCOUNT_URL>/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>
```

各部分の意味は次のとおりです。

| 部分                     | 意味                                         |
| ---------------------- | ------------------------------------------ |
| `<PUBLIC_ACCOUNT_URL>` | Snowflakeの公開アカウントURL。PrivateLink URLは使用しない |
| `<DATABASE>`           | MCPサーバーが作成されているデータベース                      |
| `<SCHEMA>`             | MCPサーバーが作成されているスキーマ                        |
| `<MCP_SERVER_NAME>`    | Snowflake-managed MCPサーバー名                 |

このURLは自分で推測して作らず、**MCPサーバー担当者から完成したURLを受け取る**のが安全です。Snowflakeの公式URL形式とClaude.aiへの登録方法は公式ドキュメントで示されています。 ([Snowflake Docs][1])

---

# 5. Snowflake側で必要な設定

ここからのSQLは、基本的にあなたのWindows PCのCMDでは実行しません。

**実行画面：**

1. WebブラウザーでSnowflake Snowsightを開く
2. `Projects` または「プロジェクト」を開く
3. `Worksheets` を開く
4. `SQL Worksheet` を新規作成する
5. Snowflake管理者がSQLを実行する

以下は、Snowflake管理者へ渡すためのテンプレートです。

## 5-1. Anthropicの送信元IPを許可する

2026年7月24日時点で、AnthropicがMCPなどの外向きリクエストに使用すると公表しているIPv4範囲は次のとおりです。

```text
160.79.104.0/21
```

Anthropicはこの範囲を固定IPとして公開していますが、実装時には必ず公式ページで再確認してください。 ([Claude Platform][4])

### 管理者用ネットワークルール作成例

```sql
USE ROLE ACCOUNTADMIN;  -- ネットワークルールとポリシーを設定できる管理ロールへ切り替えます。本番では委任された専用管理ロールでも構いません。

CREATE NETWORK RULE <SECURITY_DATABASE>.<NETWORK_RULE_SCHEMA>.ANTHROPIC_CLAUDE_MCP  -- AnthropicからのMCP通信を識別するネットワークルールを作成します。
  MODE = INGRESS  -- Snowflake側から見て、外部から入ってくる通信を対象にします。
  TYPE = IPV4  -- 接続元をIPv4アドレスで判定します。
  VALUE_LIST = ('160.79.104.0/21')  -- Anthropicが公開している外向きMCP通信のIPv4範囲を指定します。
  COMMENT = 'Allow Anthropic outbound MCP traffic'  -- このルールの用途を記録します。
;  -- CREATE NETWORK RULE文を終了します。

CREATE NETWORK POLICY CLAUDE_MCP_OAUTH_NP  -- OAuthトークン交換とリソースアクセス用の専用ネットワークポリシーを作成します。
  ALLOWED_NETWORK_RULE_LIST = ('<SECURITY_DATABASE>.<NETWORK_RULE_SCHEMA>.ANTHROPIC_CLAUDE_MCP')  -- Anthropicのネットワークルールだけを許可します。
  COMMENT = 'Network policy for Claude.ai OAuth and MCP access'  -- ポリシーの用途を記録します。
;  -- CREATE NETWORK POLICY文を終了します。

ALTER NETWORK POLICY <ACTIVE_ACCOUNT_NETWORK_POLICY>  -- 現在Snowflakeアカウントで利用しているネットワークポリシーを変更します。
  ADD ALLOWED_NETWORK_RULE_LIST = ('<SECURITY_DATABASE>.<NETWORK_RULE_SCHEMA>.ANTHROPIC_CLAUDE_MCP')  -- 既存の許可ルールを維持したまま、Anthropicのルールを追加します。
;  -- ALTER NETWORK POLICY文を終了します。
```

Snowflakeのmanaged MCP公式手順では、リモートMCPクライアントの送信元IPをアカウントのネットワークポリシーに追加するよう案内されています。 `ADD` を使用すると既存の許可リストを置き換えずに追加できます。 ([Snowflake Docs][1])

### 既存環境が「公開アクセスを全面拒否」の場合

既存のネットワークポリシーに、全公開IPv4を対象とした `BLOCKED_NETWORK_RULE_LIST` がある場合、単純にAnthropicのCIDRを許可リストへ追加しても接続できません。

Snowflakeでは、同じアドレスが許可リストと拒否リストの両方に一致した場合、**拒否リストが優先されます**。その場合は、ネットワーク管理者が次のような再設計を行う必要があります。

* PrivateLinkの `AZURELINKID` を許可する
* AnthropicのIPv4 CIDRを許可する
* それ以外のIPv4が許可されないポリシー構成にする
* 全IPv4を覆う拒否ルールとの競合を解消する

これは既存のSnowflake接続全体に影響する可能性があるため、初心者が単独で変更してはいけません。 ([Snowflake Docs][5])

---

## 5-2. Snowflake OAuthセキュリティ統合を作成する

今回使用するのは、標準の公式構成では**Snowflake OAuth**です。

Azure／Microsoft Entra IDで新しいOAuthアプリを登録するのではありません。既存のSnowflakeログインがEntra IDのSSOを使用している場合は、Snowflakeの認証画面から通常どおりEntra IDへリダイレクトされますが、Claude用OAuth Client IDとSecretはSnowflake側で生成します。

### 管理者用OAuth設定例

```sql
USE ROLE ACCOUNTADMIN;  -- SECURITY INTEGRATIONを作成できる管理ロールへ切り替えます。

CREATE SECURITY INTEGRATION CLAUDE_AI_MCP_OAUTH  -- Claude.ai用のSnowflake OAuthセキュリティ統合を新規作成します。
  TYPE = OAUTH  -- このセキュリティ統合がOAuth用であることを指定します。
  OAUTH_CLIENT = CUSTOM  -- Claude.aiをSnowflakeのカスタムOAuthクライアントとして登録します。
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'  -- AnthropicクラウドがClient Secretを保持するため、Confidential Clientとして設定します。
  ENABLED = TRUE  -- このOAuthセキュリティ統合を有効にします。
  OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback'  -- 現在のClaude.ai OAuthコールバックURIを登録します。
  OAUTH_ALTERNATE_REDIRECT_URIS = ('https://claude.com/api/mcp/auth_callback')  -- 将来のclaude.comコールバックへの変更に備えて代替URIを登録します。
  OAUTH_USE_SECONDARY_ROLES = NONE  -- OAuthセッションでセカンダリロールを有効にしないようにします。
  ALLOWED_ROLES_LIST = ('<MCP_ROLE>')  -- OAuthで利用可能なロールをMCP専用ロールのみに制限します。
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE  -- アクセストークン失効後も再接続できるよう、リフレッシュトークンを発行します。
  OAUTH_REFRESH_TOKEN_VALIDITY = 2592000  -- リフレッシュトークンの有効期間を30日、2,592,000秒にする例です。
  NETWORK_POLICY = 'CLAUDE_MCP_OAUTH_NP'  -- トークン交換とSnowflakeリソースアクセスをAnthropicの送信元IPに制限します。
  USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE  -- ユーザーの認証・同意画面をPrivateLink側へリダイレクトします。
  COMMENT = 'OAuth integration for Claude.ai and Snowflake managed MCP'  -- この統合の用途を記録します。
;  -- CREATE SECURITY INTEGRATION文を終了します。
```

この例の `OAUTH_REFRESH_TOKEN_VALIDITY = 2592000` は30日の例であり、会社のセキュリティ基準に合わせて変更してください。SnowflakeのカスタムOAuthクライアントでは、通常1日から90日まで設定できます。

`CREATE OR REPLACE` は使用していません。既存のセキュリティ統合を置き換えると、クライアント資格情報や既存接続に影響するためです。既存オブジェクトを変更する場合は `ALTER SECURITY INTEGRATION` を使用します。OAuthパラメーターとPrivateLink認証用パラメーターはSnowflake公式で定義されています。 ([Snowflake Docs][3])

現在のAnthropic公式資料では、Claudeのコールバックは次のURIです。

```text
https://claude.ai/api/mcp/auth_callback
```

将来、次のURIへ変更される可能性があるため、Snowflakeの代替リダイレクトURIとして登録することがAnthropicから案内されています。

```text
https://claude.com/api/mcp/auth_callback
```

ただし、**Claude.aiの設定画面に実際に表示されたURIが最優先**です。表示されたURIが上記と異なる場合は、Snowflake管理者へその値を渡して設定を更新してください。 ([Snowflake Docs][1])

---

## 5-3. Client IDとClient Secretを取得する

**実行画面：Snowflake SnowsightのSQL Worksheet**

```sql
DESC SECURITY INTEGRATION CLAUDE_AI_MCP_OAUTH;  -- 作成したOAuthセキュリティ統合の設定内容を確認します。

SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('CLAUDE_AI_MCP_OAUTH');  -- Claude.aiへ入力するClient IDとClient Secretを取得します。
```

セキュリティ統合名は、大文字・小文字を含めてSnowflake上の名称と一致させてください。Snowflake-managed MCPの公式手順でも、このシステム関数を利用してClient IDとSecretを取得します。 ([Snowflake Docs][1])

取得したSecretは、次のように取り扱います。

* メール本文や一般チャットへ貼らない
* チケットへ平文で記載しない
* 会社のパスワードマネージャーやシークレット管理サービスで渡す
* Claude Team／EnterpriseのOwnerだけがClaude.aiに入力する
* 一般利用者へClient Secretを配布しない

1つのOAuthセキュリティ統合のClient IDとSecretを複数ユーザーで共有できますが、ユーザーのSnowflake認証とアクセストークンはユーザーごとに分かれます。 ([Snowflake Docs][1])

---

## 5-4. 利用者のDEFAULT_ROLEとDEFAULT_WAREHOUSEを設定する

Snowflake-managed MCPでは、OAuthセッションに利用者の `DEFAULT_ROLE` が使われます。Claudeから任意のSnowflakeロールを選択することはできず、セカンダリロールも使用できません。

また、`DEFAULT_WAREHOUSE` が未設定の場合、セッション初期化が失敗します。 ([Snowflake Docs][1])

**実行画面：Snowflake SnowsightのSQL Worksheet**

```sql
ALTER USER <SNOWFLAKE_USER>  -- Claude.aiから接続するSnowflakeユーザーを指定します。
  SET DEFAULT_ROLE = '<MCP_ROLE>'  -- OAuthセッションで使用するMCP専用の最小権限ロールを既定ロールにします。
      DEFAULT_WAREHOUSE = '<MCP_WAREHOUSE>'  -- MCPツールが利用する既定Warehouseを設定します。
;  -- ALTER USER文を終了します。
```

### 注意点

`DEFAULT_ROLE` の変更は、Claudeだけでなく、そのユーザーが通常Snowflakeへログインするときの既定ロールにも影響します。

既存ユーザーのDEFAULT_ROLEを変更できない場合は、次のいずれかをSnowflake管理者と検討してください。

* 既存のDEFAULT_ROLEへMCP利用権限を最小限追加する
* Claude利用専用のSnowflakeユーザーを個人ごとに作成する
* 利用レベルごとにMCPサーバーやCortex Agentを分ける

専用の共有Snowflakeユーザーを全員で使う方法は、監査上「誰が実行したか」が分かりにくくなるため推奨しません。

---

## 5-5. MCPサーバーとツールへの権限

MCPサーバー自体への `USAGE` 権限だけでは、内部の各ツールを呼び出せません。ツールが参照するCortex Search、Semantic View、Cortex Agent、UDF、ストアドプロシージャ、テーブルなどへの権限も必要です。 ([Snowflake Docs][1])

基本的な管理者用例は次のとおりです。

```sql
GRANT USAGE ON WAREHOUSE <MCP_WAREHOUSE> TO ROLE <MCP_ROLE>;  -- MCP処理に使用するWarehouseを利用可能にします。

GRANT USAGE ON DATABASE <MCP_DATABASE> TO ROLE <MCP_ROLE>;  -- MCPサーバーが存在するデータベースへの参照権限を付与します。

GRANT USAGE ON SCHEMA <MCP_DATABASE>.<MCP_SCHEMA> TO ROLE <MCP_ROLE>;  -- MCPサーバーが存在するスキーマへの参照権限を付与します。

GRANT USAGE ON MCP SERVER <MCP_DATABASE>.<MCP_SCHEMA>.<MCP_SERVER_NAME> TO ROLE <MCP_ROLE>;  -- MCPサーバーの検出と接続を許可します。
```

このほかに、MCPサーバー担当者がツールの種類ごとに必要な権限を追加します。

特に `SYSTEM_EXECUTE_SQL` ツールを含める場合は、最初の導入では `read_only: true` にし、MCP専用ロールにも更新・削除権限を与えない構成が安全です。

---

# 6. Windows PCでのClaude.aiクライアント設定

## 6-1. 事前準備

あなたのWindows PCで、次を確認します。

1. EdgeまたはChromeを利用できる
2. 会社のClaude Team／Enterprise組織へログインできる
3. 会社ネットワークまたはVPNに接続している
4. Snowflake PrivateLink用DNSが利用できる
5. Snowflakeの通常のSSO・MFAログインができる
6. Snowflake管理者から公開MCP URL、Client ID、Client Secretを受け取っている

この主作業では、CMDやPowerShellは使用しません。

---

## 6-2. Claude Team／Enterpriseでコネクタを組織へ追加する

Team／Enterpriseでは、カスタムコネクタを組織へ追加できるのは `Owner` または `Primary Owner` です。一般メンバーは追加できませんが、Ownerが追加したコネクタへ個別に接続できます。 ([Claudeヘルプセンター][2])

**操作画面：EdgeまたはChromeのClaude.aiサイト**

1. Claude.aiへ会社アカウントでログインします。
2. 個人領域ではなく、会社のTeam／Enterprise組織を選択します。
3. `Organization settings`、日本語表示では「組織設定」を開きます。
4. `Connectors`、「コネクタ」を開きます。
5. `Add` を押します。
6. `Custom` にマウスを合わせます。
7. `Web` を選択します。
8. コネクタ名を入力します。

例：

```text
Snowflake MCP - PROD - ReadOnly
```

9. `Remote MCP Server URL` または同様の欄に、Snowflake担当者から受け取った**公開MCP URL**を貼り付けます。
10. `Advanced settings`、「詳細設定」を開きます。
11. `OAuth Client ID` にSnowflakeから取得したClient IDを貼り付けます。
12. `OAuth Client Secret` にSnowflakeから取得したClient Secretを貼り付けます。
13. URL、Client ID、Client Secretに前後の空白が入っていないことを確認します。
14. `Add` を押します。

Claudeの画面ではClient IDとSecretが「任意」と表示される場合がありますが、Snowflake-managed MCPはDCRに対応していないため、**今回の構成では入力が必要**です。 ([Snowflake Docs][1])

### 絶対に入力してはいけないURL

次のようなPrivateLink専用URLをClaude.aiのMCP URL欄へ入力してはいけません。

```text
https://<PRIVATE_OR_PRIVATELINK_HOST>/api/v2/databases/...
```

Claude.aiからの接続元はAnthropicクラウドなので、PrivateLink専用ホスト名を解決・到達できません。

---

## 6-3. 各利用者がOAuth接続する

Ownerがコネクタを追加した後、利用者ごとに次を行います。

**操作画面：Claude.aiサイト**

1. Claude.aiで会社の組織を選択します。
2. `Customize`、「カスタマイズ」を開きます。
3. `Connectors`、「コネクタ」を開きます。
4. Ownerが追加した `Snowflake MCP - PROD - ReadOnly` を探します。
5. コネクタに `Custom` の表示があることを確認します。
6. `Connect` を押します。
7. Snowflakeの認証画面が開きます。
8. 会社のSnowflakeユーザーまたはSSOでログインします。
9. 必要に応じてMFAを完了します。
10. OAuth同意画面で、使用されるロールと要求内容を確認します。
11. 問題がなければ承認します。
12. Claude.aiへ戻り、コネクタが `Connected` になっていることを確認します。

この認証処理はユーザーごとに行います。Ownerがコネクタを登録しただけで、全利用者が同じSnowflakeユーザーとして接続されるわけではありません。 ([Claudeヘルプセンター][2])

### OAuth画面で「secondary roles = ALL」と表示された場合

Claudeは `session:role:all` を要求する場合があり、Snowflakeの同意画面に「secondary roles = ALL」のような表示が出ることがあります。

ただし、セキュリティ統合が次の設定であれば、

```sql
OAUTH_USE_SECONDARY_ROLES = NONE
```

Snowflakeは実際には利用者の `DEFAULT_ROLE` だけを使用します。Snowflake公式では、この「ALL」という表示は画面上の表示にすぎず、追加ロールは付与されないと説明されています。 ([Snowflake Docs][1])

---

## 6-4. 会話ごとにコネクタを有効化する

コネクタへ接続しただけでは、すべての会話で自動的に使用されるとは限りません。

**操作画面：Claude.aiのチャット画面**

1. 新しいチャットを開きます。
2. 画面左下の `+` を押します。
3. `Connectors` を選択します。
4. `Snowflake MCP - PROD - ReadOnly` を有効にします。
5. コネクタ名が会話に表示されていることを確認します。

Claudeの公式手順でも、会話ごとに `+` → `Connectors` からコネクタを有効化する方式が案内されています。 ([Claudeヘルプセンター][2])

---

# 7. 最初の接続テスト

最初は、書き込みを伴わないツールで確認してください。

Claude.aiのチャット欄へ、例えば次のように入力します。

```text
Snowflakeコネクタで利用可能なツールの名前と説明を確認してください。
この時点では、データの更新、追加、削除を行うツールは実行しないでください。
```

次に、MCPサーバー担当者から指定された読み取り専用ツールで試します。

```text
Snowflakeの読み取り専用ツールを使用して、承認済みのテストデータから10件以内で結果を取得してください。
データの追加、更新、削除は行わないでください。
```

確認項目は次のとおりです。

| 確認項目         | 正常な状態                    |
| ------------ | ------------------------ |
| コネクタ         | Connected                |
| OAuth        | Snowflakeログインと同意が完了      |
| ツール一覧        | 想定したツールだけが表示される          |
| Snowflakeロール | MCP専用DEFAULT_ROLE        |
| Warehouse    | MCP用Warehouse            |
| ツール実行        | 読み取り専用テストが成功             |
| 結果件数         | 指定した少量の結果だけが返る           |
| Snowflake監査  | 利用者本人のOAuthセッションとして記録される |

---

# 8. Windows側でPrivateLink認証経路を確認する方法

これは任意の診断作業です。

## 8-1. PowerShellを開く

1. Windowsのスタートメニューを開きます。
2. `PowerShell` と入力します。
3. `Windows PowerShell` または `PowerShell` を開きます。
4. 通常は「管理者として実行」する必要はありません。

## 8-2. PrivateLink用DNSを確認する

```powershell
Resolve-DnsName "<PRIVATE_LINK_SNOWFLAKE_HOSTNAME>"  # Snowflake PrivateLink用ホスト名がDNSで解決できるか確認します。https://やパスは付けません。
```

結果に会社ネットワークで想定しているPrivate EndpointのIPアドレスが表示されることを確認します。

## 8-3. HTTPSの443番ポートを確認する

```powershell
Test-NetConnection "<PRIVATE_LINK_SNOWFLAKE_HOSTNAME>" -Port 443  # Windows PCからSnowflake PrivateLinkのHTTPSポートへ到達できるか確認します。
```

次の表示であれば、TCP接続は成功しています。

```text
TcpTestSucceeded : True
```

ただし、この確認で分かるのは、**Windows PCからPrivateLink認証画面へ到達できるかどうかだけ**です。

AnthropicクラウドからSnowflake公開MCP URLへ到達できるかは、このWindows PCからのテストでは確認できません。Anthropic側の到達性は、Snowflakeネットワークポリシー、Snowflakeログ、Claude.aiからの実接続で確認します。

---

# 9. よくあるエラーと確認箇所

| 症状                                    | 主な原因                                                | 確認する担当・設定                                               |
| ------------------------------------- | --------------------------------------------------- | ------------------------------------------------------- |
| Claudeでコネクタ追加画面がない                    | Team／EnterpriseのOwner権限がない、会社組織を選択していない             | Claude組織管理者                                             |
| URL登録後すぐタイムアウトする                      | PrivateLink URLをClaudeへ登録している                       | 公開MCP URLへ変更                                            |
| WindowsではSnowflakeへ接続できるがClaudeでは失敗する | Claudeの接続はWindowsからではなくAnthropicクラウドから発信される         | Snowflakeのアカウントネットワークポリシー                               |
| OAuth画面がDNSエラーになる                     | Windowsが会社ネットワーク／VPNに未接続、PrivateLink DNSが引けない       | Windows、VPN、Private DNS                                 |
| OAuthエラー `390307`                     | Claudeが送ったredirect URIとSnowflakeの設定が一致しない           | `OAUTH_REDIRECT_URI` と代替URI                             |
| `invalid_client`                      | Client IDまたはSecretが誤っている、Secretがローテーションされた          | Snowflake OAuth統合、Claude詳細設定                            |
| OAuth認証は成功するがツールが表示されない               | `USAGE ON MCP SERVER`、Database、Schema、ツール権限が不足      | Snowflakeロール                                            |
| ツールは表示されるが実行時に失敗する                    | DEFAULT_WAREHOUSE未設定、Warehouse USAGE不足、内部オブジェクト権限不足 | Snowflakeユーザーとロール                                       |
| 同意画面にsecondary roles ALLと表示される        | Claudeの要求スコープによる表示                                  | `OAUTH_USE_SECONDARY_ROLES = NONE` なら実権限はDEFAULT_ROLEのみ |
| Anthropic CIDRをALLOWに追加しても接続できない      | 既存の全IPv4 BLOCKルールが優先されている                           | Snowflakeネットワーク管理者                                      |
| 結果が途中で切れる                             | SQL実行または汎用ツールの結果が250KBを超えている                        | 列数、行数、検索条件を絞る                                           |
| Secret変更後にコネクタを更新できない                 | Claudeのカスタムコネクタは編集ではなく削除・再追加が必要な場合がある               | Claude組織Owner                                           |

Snowflake OAuthの `390307` はredirect URI不一致を表す公式エラーです。 ([Snowflake Docs][6])

---

# 10. セキュリティ上の重要事項

## 10-1. SnowflakeのデータはAnthropicクラウドへ渡ります

この構成では、Snowflakeから取得した検索結果やSQL結果がAnthropicクラウドへ送られ、Claudeの会話処理に使用されます。

したがって、PrivateLinkを使用しているからといって、データがSnowflakeと自社ネットワーク内だけに留まるわけではありません。

会社では、少なくとも次を確認してください。

* Claude Team／Enterpriseなど会社契約の環境を使用する
* 個人のFree／Pro／Maxアカウントへ会社データを接続しない
* Anthropicとの契約、DPA、データ保持期間、データ所在地を確認する
* SnowflakeからClaudeへ出してよいデータ分類を決める
* 個人情報、機密情報、規制対象情報の利用可否を決める
* 必要に応じてSnowflakeのマスキングポリシーや行アクセスポリシーを適用する

Anthropicは、商用製品へ提供されたデータを、明示的なプログラム参加などがない限り、標準ではモデル学習に使用しないと説明しています。ただし、これは「データが一切保存されない」という意味ではないため、会社契約の保持条件を別途確認する必要があります。 ([Claudeヘルプセンター][7])

## 10-2. 最小権限のロールを使用する

MCP用ロールに、次の管理ロールを使用してはいけません。

* `ACCOUNTADMIN`
* `SECURITYADMIN`
* `SYSADMIN`
* `ORGADMIN`

MCP専用の読み取りロールを作成し、対象データ、ツール、Warehouseだけを許可してください。

## 10-3. ツールの内容を確認する

MCPサーバーへ接続できることと、すべてのツールを安全に使えることは別問題です。

特に次を確認します。

* SQL実行ツールが読み取り専用か
* 書き込み系ストアドプロシージャが含まれていないか
* ツール名と説明が誤解を招かないか
* 意図しないデータベースを参照しないか
* Cortex Agentが別のMCPを再帰的に呼び出さないか

Snowflakeも、ツールポイズニングやツールシャドーイングを避けるため、ツールと説明を確認し、最小権限を使用するよう推奨しています。 ([Snowflake Docs][1])

---

# 11. Snowflake-managed MCPの仕様上の制限

現行のSnowflake-managed MCPには、主に次の制限があります。

* MCPの `tools` 機能のみをサポートする
* `resources`、`prompts`、`roots` などはサポートしない
* ストリーミング応答はサポートしない
* 1つのMCPサーバーにつき最大50ツール
* Genericツールの応答は250KBで切り詰められる
* SQL実行ツールの応答は250KBで切り詰められる
* OAuthセッションではセカンダリロールを使用できない
* 利用者のDEFAULT_ROLEが使用される

大量の表をそのまま返す用途ではなく、列、期間、件数を限定した問い合わせとして設計する必要があります。 ([Snowflake Docs][1])

---

# 12. Entra ID OAuthとの違い

今回の公式構成は次のとおりです。

```text
Claude.ai
    ↓
Snowflake OAuth
    ↓
Snowflakeユーザー認証
    ↓
必要に応じて既存のEntra ID SSO
```

つまり、

* OAuth Client IDとClient SecretはSnowflakeが発行する
* Entra IDのアプリ登録でClient IDを作るのではない
* 利用者認証では、既存のSnowflake SSOとしてEntra IDを利用できる
* Snowflake OAuthアクセストークンをClaudeが取得する

今回確認したSnowflake-managed MCPの公式手順では、Snowflake内蔵OAuthを使用する方法が明記されています。Entra IDがアクセストークンを直接発行する「External OAuth」をClaude.aiとSnowflake-managed MCPで利用する公式手順は確認できませんでした。会社がExternal OAuthを必須としている場合は、SnowflakeおよびAnthropicのサポートへ構成可否を確認する必要があります。 ([Snowflake Docs][1])

---

# 13. 最終チェックリスト

| チェック              | 合格条件                                                |
| ----------------- | --------------------------------------------------- |
| Claude.aiの契約      | 会社のTeam／Enterprise組織を使用                             |
| Claude権限          | OwnerがカスタムWebコネクタを登録できる                             |
| MCP URL           | Snowflakeの**公開URL**を使用                              |
| PrivateLink URL   | Claude.aiのMCP URL欄には入力していない                         |
| OAuth Client      | `CUSTOM`、`CONFIDENTIAL`                             |
| OAuth callback    | Claude画面のURIとSnowflake設定が完全一致                       |
| PrivateLink OAuth | `USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE` |
| Anthropic IP      | 実装時点の公式送信元CIDRを許可                                   |
| 拒否ルール競合           | 全IPv4 BLOCKルールとの競合を解消                               |
| OAuthロール          | `ALLOWED_ROLES_LIST` をMCP専用ロールに限定                   |
| Secondary role    | `OAUTH_USE_SECONDARY_ROLES = NONE`                  |
| Snowflake user    | `DEFAULT_ROLE` と `DEFAULT_WAREHOUSE` が設定済み          |
| MCP権限             | MCPサーバーと内部ツールの両方に権限あり                               |
| 初回テスト             | 読み取り専用・少量データで成功                                     |
| データガバナンス          | SnowflakeデータをAnthropicへ送る社内承認済み                     |
| シークレット管理          | Client SecretをOwner以外へ配布していない                       |

**最も重要な判断点は、「AnthropicクラウドからSnowflakeの公開MCP／OAuth Tokenエンドポイントへの通信を、送信元IP限定・OAuth・専用ロール付きで会社が許可できるか」です。**
これが許可できれば、Snowflake公式が案内するPrivateLink併用構成でClaude.aiを設定できます。公開エンドポイントを一切許可できない場合は、Claude.aiではなく、社内ネットワーク内で実行される別のMCPクライアントまたは別のゲートウェイ構成を選定する必要があります。

[1]: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp "https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp"
[2]: https://support.anthropic.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp "https://support.anthropic.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp"
[3]: https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-snowflake "https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-snowflake"
[4]: https://platform.claude.com/docs/en/api/ip-addresses "https://platform.claude.com/docs/en/api/ip-addresses"
[5]: https://docs.snowflake.com/en/sql-reference/sql/create-network-policy "https://docs.snowflake.com/en/sql-reference/sql/create-network-policy"
[6]: https://docs.snowflake.com/en/user-guide/oauth-snowflake-overview "https://docs.snowflake.com/en/user-guide/oauth-snowflake-overview"
[7]: https://support.claude.com/en/articles/9267385-does-anthropic-act-as-a-data-processor-or-controller "https://support.claude.com/en/articles/9267385-does-anthropic-act-as-a-data-processor-or-controller"
