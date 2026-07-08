# Snowflake MCP Server 構築手順書（Azure PrivateLink + APIM + Codex GUI）

作成日: 2026-07-08  
対象OS: Windows  
対象者: Snowflake / Azure / Codex / MCP の初心者を含む構築担当者  
前提: この資料は実装先PCで作業するための手順です。このPCの環境は無視します。

---

## 0. 先に結論

今回の要件では、第一候補は **Snowflake-managed MCP server をSnowflake上に作成し、Azure API Management（APIM）で「既存MCPサーバー」として公開し、Codex GUIからAPIMのMCP URLへ接続する構成** です。

理由は次のとおりです。

- Snowflakeが公式にMCPサーバー機能を提供しているため、MCPサーバー用の独自アプリケーションをAzure VMやContainer Appsに実装しなくてよい。
- Snowflake側のRBAC、OAuth、監査、ウェアハウス制御を使える。
- APIMを挟むことで、社内向けの入口URL、Private Endpoint、アクセス制御、レート制限、監視を一元管理できる。
- Codex側にはAPIMのURLだけを見せ、Snowflakeの直接URLや内部ネットワーク構成を隠せる。

ただし、**Codex GUIだけでSnowflake OAuthログインを完結させる部分は、Codex側のGUI機能・社内プラグイン配布方式に依存します**。公開されているCodex MCP資料では、MCP OAuthログインの例としてCLI操作も記載されています。CLIを完全に使わない運用にする場合は、次のどちらかを選びます。

| OAuth方式 | 推奨度 | 説明 |
|---|---:|---|
| A. Codexプラグイン方式 | 高 | Codex GUIの「Plugins」から社内プラグインを追加し、初回利用時またはインストール時に認証させる。GUI運用に最も合う。 |
| B. APIMでSnowflake OAuthを代理処理 | 中 | CodexはAPIMに接続し、APIMがSnowflake向けOAuthトークンを付けてバックエンドへ転送する。GUIだけで済ませやすいが、Snowflake上では原則APIM側のサービス利用者として見える。 |
| C. Codex手動config + Codex OAuthログイン | 条件付き | `config.toml`の編集だけならGUI/メモ帳で可能。ただしOAuthログイン開始操作がGUIで完結するかはCodex環境の機能確認が必要。CLI禁止の場合はAまたはBを優先する。 |

この資料では、**推奨構成Aを基本**として、APIM代理方式Bも代替案として記載します。

---

## 1. 全体構成

### 1.1 推奨構成図

```text
[Windows PC]
  Codex GUI
     |
     | HTTPS / MCP Streamable HTTP
     | OAuth Bearer token または APIM認証ヘッダー
     v
[Azure API Management]
  MCP server として公開
  Private Endpoint / APIM policy / 監視 / レート制限
     |
     | HTTPS / Private DNS / PrivateLink経由
     v
[Snowflake on Azure]
  Snowflake-managed MCP server
  Snowflake OAuth security integration
  Snowflake RBAC / Warehouse / Query History
     |
     v
[Snowflake Database / Schema / Tables / Cortex Tools]
```

### 1.2 通信の流れ

1. 利用者がWindows上のCodex GUIを起動します。
2. Codex GUIがAPIMのMCP URLへ接続します。
3. APIMがMCPサーバーの入口として振る舞い、アクセス制御、ログ、レート制限を適用します。
4. APIMがSnowflake PrivateLink経由でSnowflake-managed MCP serverへ通信します。
5. SnowflakeがOAuthトークンとRBACを確認します。
6. 許可されたMCPツールだけがCodexから呼び出せます。
7. SQL実行ツールを使う場合は、読み取り専用に制限してSnowflake上でクエリを実行します。

### 1.3 この構成で作るもの

| 作るもの | 作る場所 | 役割 |
|---|---|---|
| Snowflakeロール | Snowflake | Codex/MCP用の最小権限ロール |
| Snowflake Warehouse | Snowflake | MCP経由SQLの実行リソース |
| Snowflake-managed MCP server | Snowflake | MCPツールを公開する本体 |
| Snowflake OAuth security integration | Snowflake | OAuth認証の設定 |
| APIM MCP server | Azure Portal | Snowflake MCP serverを社内向けに公開する入口 |
| APIM policy | Azure Portal | 認証ヘッダー転送、レート制限、監視制御 |
| Codex MCP設定 | Codex GUI / Windowsメモ帳 | CodexからAPIMのMCP URLへ接続 |

---

## 2. 初心者向けの用語整理

### 2.1 MCPとは

MCPは **Model Context Protocol** の略です。AIエージェントやLLMが、外部システムのデータや機能を安全に呼び出すための共通プロトコルです。

今回の文脈では、Codexが「Snowflakeにあるデータを読みに行くための安全な窓口」がMCPです。

### 2.2 MCPの登場人物

| 用語 | 今回の構成での該当物 | 説明 |
|---|---|---|
| MCP Host | Codex GUI | MCPクライアントを持つアプリケーション本体 |
| MCP Client | Codex内のMCP接続機能 | MCPサーバーと通信する部品 |
| MCP Server | Snowflake-managed MCP server | SnowflakeのツールをMCP形式で公開するサーバー |
| Tool | `sql_readonly`など | Codexが呼び出せる個別機能 |

### 2.3 APIMとは

APIMは **Azure API Management** です。APIやMCPサーバーの入口を一元管理するAzureサービスです。

今回APIMを置く目的は次のとおりです。

- Codexから接続するURLをAPIMに統一する。
- Private Endpointで社内ネットワークからだけ接続できるようにする。
- 認証、認可、レート制限、ログ、監視をAPIMで管理する。
- SnowflakeのPrivateLink接続や内部URLをCodex利用者から隠す。

### 2.4 OAuthとは

OAuthは、利用者のパスワードをCodexやAPIMに渡さず、Snowflakeが発行した **短時間だけ有効な通行証（アクセストークン）** でアクセスする仕組みです。

OAuthの登場人物は次のように考えると分かりやすいです。

| OAuth用語 | 今回の該当物 | 説明 |
|---|---|---|
| Resource Owner | Snowflake利用者 | データへアクセスする本人 |
| Client | Codex、社内Codexプラグイン、またはAPIM | Snowflakeへアクセスしたいアプリ |
| Authorization Server | Snowflake OAuth | ログインとトークン発行を担当 |
| Resource Server | Snowflake MCP endpoint | トークンを受け取り、MCPツールを実行 |

---

## 3. 作業前に決める値

次の値を事前に埋めてから作業してください。

| 項目 | 例 | あなたの環境での値 |
|---|---|---|
| SnowflakeアカウントURL | `xxx-yyy.privatelink.snowflakecomputing.com` |  |
| Snowflake DB | `ANALYTICS_DB` |  |
| Snowflake Schema | `MCP_SCHEMA` |  |
| Snowflake MCPサーバー名 | `CODEX_SNOWFLAKE_MCP` |  |
| MCP用Snowflakeロール | `MCP_CODEX_ROLE` |  |
| MCP用Warehouse | `MCP_CODEX_WH` |  |
| 対象Snowflakeユーザー | `TARO.YAMADA` |  |
| APIMインスタンス名 | `apim-prod-xxx` |  |
| APIM Gatewayホスト名 | `apim-prod-xxx.azure-api.net` または社内カスタムドメイン |  |
| APIM MCP Base path | `snowflake-mcp` |  |
| APIMが表示するMCP Server URL | `https://<APIM Gateway>/<Base path>` |  |
| OAuth Redirect URI | Codexプラグインまたは認証ブローカーが指定するURI |  |
| Codex設定ファイル | `C:\Users\<Windowsユーザー名>\.codex\config.toml` |  |

> 注意: Snowflake MCP接続用ホスト名には、可能な限りアンダースコア `_` ではなくハイフン `-` を使ってください。

---

## 4. 構築ステップ全体

1. Snowflake側にMCP用ロール、Warehouse、権限を用意します。
2. Snowflake-managed MCP serverを作成します。
3. Snowflake OAuth security integrationを作成します。
4. APIMがPrivateLink経由でSnowflakeへ到達できるようにネットワークとDNSを確認します。
5. APIMで「既存MCPサーバー」としてSnowflake MCP endpointを公開します。
6. APIM policyで認証ヘッダー転送、レート制限、ログ設定を行います。
7. Codex GUIで社内プラグインを追加、またはWindows上の`config.toml`を編集します。
8. CodexからMCPツールが見えるか、読み取り専用SQLだけ実行できるか確認します。

---

## 5. Snowflake側の設定

### 5.1 入力画面

この章のSQLは、**Snowflake Snowsight > Worksheets** で実行します。

操作手順:

1. ブラウザでSnowflake Snowsightへサインインします。
2. 左メニューで **Worksheets** を開きます。
3. 新しいWorksheetを作成します。
4. 以下のSQLを環境に合わせて修正して実行します。

### 5.2 MCP用ロールとWarehouseを作成する

`<SNOWFLAKE_USER>` は実際のSnowflakeユーザー名に置き換えてください。

```sql
USE ROLE USERADMIN; -- ロール作成権限を持つ管理ロールに切り替えます。
CREATE ROLE IF NOT EXISTS MCP_CODEX_ROLE; -- Codex/MCP接続に使う最小権限ロールを作成します。
USE ROLE SECURITYADMIN; -- ユーザーへのロール付与を行う管理ロールに切り替えます。
GRANT ROLE MCP_CODEX_ROLE TO USER <SNOWFLAKE_USER>; -- 対象ユーザーにMCP用ロールを付与します。
USE ROLE SYSADMIN; -- WarehouseやDBオブジェクトを作成・管理するロールに切り替えます。
CREATE WAREHOUSE IF NOT EXISTS MCP_CODEX_WH -- MCP経由のSQL実行に使うWarehouseを作成します。
  WAREHOUSE_SIZE = 'XSMALL' -- 最小サイズで開始し、必要に応じて後から拡張します。
  AUTO_SUSPEND = 60 -- 60秒使われなければ自動停止してコストを抑えます。
  AUTO_RESUME = TRUE -- クエリ実行時に自動起動するようにします。
  INITIALLY_SUSPENDED = TRUE; -- 作成直後は停止状態にして不要な課金を避けます。
GRANT USAGE ON WAREHOUSE MCP_CODEX_WH TO ROLE MCP_CODEX_ROLE; -- MCP用ロールがWarehouseを使えるようにします。
```

### 5.3 対象DB/Schema/Tableへの読み取り権限を付与する

`<SNOWFLAKE_DB>` と `<SNOWFLAKE_SCHEMA>` は実際のDB名とSchema名に置き換えてください。

```sql
USE ROLE SECURITYADMIN; -- 権限付与を行う管理ロールに切り替えます。
GRANT USAGE ON DATABASE <SNOWFLAKE_DB> TO ROLE MCP_CODEX_ROLE; -- MCP用ロールが対象DBを参照できるようにします。
GRANT USAGE ON SCHEMA <SNOWFLAKE_DB>.<SNOWFLAKE_SCHEMA> TO ROLE MCP_CODEX_ROLE; -- MCP用ロールが対象Schemaを参照できるようにします。
GRANT SELECT ON ALL TABLES IN SCHEMA <SNOWFLAKE_DB>.<SNOWFLAKE_SCHEMA> TO ROLE MCP_CODEX_ROLE; -- 既存テーブルを読み取れるようにします。
GRANT SELECT ON FUTURE TABLES IN SCHEMA <SNOWFLAKE_DB>.<SNOWFLAKE_SCHEMA> TO ROLE MCP_CODEX_ROLE; -- 今後作成されるテーブルも読み取れるようにします。
GRANT SELECT ON ALL VIEWS IN SCHEMA <SNOWFLAKE_DB>.<SNOWFLAKE_SCHEMA> TO ROLE MCP_CODEX_ROLE; -- 既存Viewを読み取れるようにします。
GRANT SELECT ON FUTURE VIEWS IN SCHEMA <SNOWFLAKE_DB>.<SNOWFLAKE_SCHEMA> TO ROLE MCP_CODEX_ROLE; -- 今後作成されるViewも読み取れるようにします。
```

> 最小権限にする場合は、`ALL TABLES`ではなく、必要なテーブルだけに`GRANT SELECT ON TABLE ...`を付与してください。

### 5.4 Snowflake-managed MCP serverを作成する

まずは安全のため、**読み取り専用SQLツールだけ** を公開します。

入力画面: **Snowflake Snowsight > Worksheets**

```sql
USE ROLE SYSADMIN; -- MCPサーバーオブジェクトを作成するロールに切り替えます。
USE DATABASE <SNOWFLAKE_DB>; -- MCPサーバーを作成するDBを選択します。
USE SCHEMA <SNOWFLAKE_SCHEMA>; -- MCPサーバーを作成するSchemaを選択します。
CREATE OR REPLACE MCP SERVER CODEX_SNOWFLAKE_MCP -- Snowflake管理のMCPサーバーを作成または更新します。
  FROM SPECIFICATION $$ -- ここからMCPツール定義のYAMLを開始します。
tools: # Codexへ公開するツールの一覧です。
  - title: "Read Only SQL" # Codexに表示されるツール名です。
    name: "sql_readonly" # Codex設定の許可リストで使うツールIDです。
    type: "SYSTEM_EXECUTE_SQL" # Snowflake上でSQLを実行する公式ツール種別です。
    description: "Read-only SQL execution for approved Snowflake data." # Codexがツール選択時に参照する説明です。
    config: # SQL実行ツールの設定を開始します。
      read_only: true # SELECTなどの読み取り操作だけを許可します。
      query_timeout: 60 # 1回のSQL実行を60秒でタイムアウトさせます。
      warehouse: "MCP_CODEX_WH" # SQL実行に使うWarehouseを指定します。
$$; -- MCPツール定義を閉じて、MCPサーバー作成を実行します。
```

### 5.5 MCP serverへの接続権限を付与する

入力画面: **Snowflake Snowsight > Worksheets**

```sql
USE ROLE SECURITYADMIN; -- MCPサーバー利用権限を付与する管理ロールに切り替えます。
GRANT USAGE ON MCP SERVER <SNOWFLAKE_DB>.<SNOWFLAKE_SCHEMA>.CODEX_SNOWFLAKE_MCP TO ROLE MCP_CODEX_ROLE; -- MCP用ロールがMCPサーバーへ接続してツール一覧を取得できるようにします。
GRANT USAGE ON WAREHOUSE MCP_CODEX_WH TO ROLE MCP_CODEX_ROLE; -- SQL実行時に使うWarehouseの利用権限を再確認します。
```

### 5.6 ユーザーのデフォルトロールとWarehouseを設定する

Snowflake-managed MCP serverのOAuthセッションでは、接続ユーザーの `DEFAULT_ROLE` と `DEFAULT_WAREHOUSE` が重要です。セカンダリロールに依存しないでください。

入力画面: **Snowflake Snowsight > Worksheets**

```sql
USE ROLE SECURITYADMIN; -- ユーザー設定を変更できる管理ロールに切り替えます。
ALTER USER <SNOWFLAKE_USER> SET DEFAULT_ROLE = 'MCP_CODEX_ROLE' DEFAULT_WAREHOUSE = 'MCP_CODEX_WH'; -- MCP接続時に最小権限ロールと専用Warehouseが使われるようにします。
```

### 5.7 MCP server URLを確認する

Snowflake-managed MCP serverのURL形式は次の形です。

| 部品 | 値 |
|---|---|
| Snowflake URL | `https://<SnowflakeアカウントURL>` |
| 固定パス | `/api/v2/databases/<DB>/schemas/<Schema>/mcp-servers/<MCP server name>` |

例:

`https://<SNOWFLAKE_ACCOUNT_URL>/api/v2/databases/<SNOWFLAKE_DB>/schemas/<SNOWFLAKE_SCHEMA>/mcp-servers/CODEX_SNOWFLAKE_MCP`

このURLはAPIMの「Backend MCP server base URL」に設定します。

---

## 6. OAuth設定

### 6.1 OAuth設定の基本方針

今回のOAuthでは、次の2パターンがあります。

| パターン | CodexからAPIM | APIMからSnowflake | Snowflake上の利用者識別 | 向いているケース |
|---|---|---|---|---|
| A. ユーザー委任方式 | CodexがOAuth Bearer tokenを送る | APIMがAuthorizationヘッダーをSnowflakeへ転送 | 各Snowflakeユーザー | 監査・RBACをユーザー単位にしたい |
| B. APIM代理方式 | CodexはAPIMへ接続 | APIMがSnowflake OAuth tokenを取得して付与 | APIM用サービスユーザー | Codex GUIだけで完結させたい、読み取り専用の共通用途 |

推奨は **A. ユーザー委任方式** です。各ユーザーのSnowflakeロールと監査を保ちやすいからです。  
ただし、Codex GUIだけでOAuthログインを完結させるためには、社内Codexプラグイン方式またはCodex GUIのOAuth対応状況を確認してください。

### 6.2 Snowflake OAuth security integrationを作成する

`<CODEX_OR_AUTH_BROKER_CALLBACK_URL>` は、Codexプラグインまたは社内認証ブローカーが指定するOAuth Redirect URIに置き換えてください。

入力画面: **Snowflake Snowsight > Worksheets**

```sql
USE ROLE ACCOUNTADMIN; -- OAuth security integrationを作成できる管理ロールに切り替えます。
CREATE OR REPLACE SECURITY INTEGRATION CODEX_MCP_OAUTH -- Codex/APIMから使うSnowflake OAuth設定を作成または更新します。
  TYPE = OAUTH -- このSecurity IntegrationがOAuth用であることを指定します。
  OAUTH_CLIENT = CUSTOM -- Codex/APIMはSnowflakeの事前定義パートナーではないためCUSTOMを指定します。
  ENABLED = TRUE -- このOAuth設定を有効化します。
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL' -- クライアントシークレットを安全に保持できるサーバー側クライアントとして扱います。
  OAUTH_REDIRECT_URI = '<CODEX_OR_AUTH_BROKER_CALLBACK_URL>' -- 認証後にSnowflakeが戻す先のURLを指定します。
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE -- アクセストークン期限切れ後に再認証を減らすためRefresh Tokenを発行します。
  OAUTH_REFRESH_TOKEN_VALIDITY = 86400 -- Refresh Tokenの有効期間を86400秒、つまり1日に設定します。
  OAUTH_USE_SECONDARY_ROLES = NONE -- セカンダリロールを使わず、デフォルトロールだけに制限します。
  ALLOWED_ROLES_LIST = ('MCP_CODEX_ROLE') -- OAuthで利用可能なSnowflakeロールをMCP用ロールに限定します。
  USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE -- Snowflake認証画面とのやり取りにPrivate connectivityを使う設定を有効化します。
  COMMENT = 'OAuth integration for Codex MCP via APIM'; -- 後から目的が分かるようにコメントを付けます。
```

複数のRedirect URIが必要な場合は、次のようにします。

入力画面: **Snowflake Snowsight > Worksheets**

```sql
USE ROLE ACCOUNTADMIN; -- OAuth security integrationを更新できる管理ロールに切り替えます。
CREATE OR REPLACE SECURITY INTEGRATION CODEX_MCP_OAUTH -- 既存のOAuth設定を複数Redirect URI対応で再作成します。
  TYPE = OAUTH -- OAuth用のSecurity Integrationとして作成します。
  OAUTH_CLIENT = CUSTOM -- カスタムクライアントとして登録します。
  ENABLED = TRUE -- OAuth設定を有効にします。
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL' -- クライアントシークレットをサーバー側で安全に保持する前提にします。
  OAUTH_REDIRECT_URI = '<PRIMARY_CALLBACK_URL>' -- メインのRedirect URIを指定します。
  OAUTH_ALTERNATE_REDIRECT_URIS = ('<ALTERNATE_CALLBACK_URL_1>', '<ALTERNATE_CALLBACK_URL_2>') -- 追加で許可するRedirect URIを指定します。
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE -- Refresh Tokenの発行を許可します。
  OAUTH_REFRESH_TOKEN_VALIDITY = 86400 -- Refresh Tokenの有効期間を1日に設定します。
  OAUTH_USE_SECONDARY_ROLES = NONE -- セカンダリロールを無効化します。
  ALLOWED_ROLES_LIST = ('MCP_CODEX_ROLE') -- OAuthで使えるロールをMCP用ロールに限定します。
  USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE -- 認証時のPrivateLink利用を有効にします。
  COMMENT = 'OAuth integration for Codex MCP via APIM'; -- 設定の用途をコメントとして残します。
```

### 6.3 OAuth Client ID / Secretを取得する

入力画面: **Snowflake Snowsight > Worksheets**

```sql
USE ROLE ACCOUNTADMIN; -- OAuth Client Secretを参照できる管理ロールに切り替えます。
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('CODEX_MCP_OAUTH'); -- OAuth Client IDとClient Secretを取得します。
```

取得した値の扱い:

- Client IDはCodexプラグイン、認証ブローカー、またはAPIM Credential managerに登録します。
- Client Secretは利用者PCの平文ファイルに保存しないでください。
- Client SecretはAzure Key Vault、APIM Credential manager、または社内の秘密情報管理システムに保存してください。
- Codexの`config.toml`へSnowflake Client Secretを直接書かないでください。

### 6.4 OAuth方式A: ユーザー委任方式の流れ

1. Codex GUIで社内Snowflake MCPプラグインを追加します。
2. 初回利用時にSnowflakeサインイン画面が表示されます。
3. 利用者がSnowflakeにサインインします。
4. SnowflakeがCodexプラグインまたは認証ブローカーへ認可コードを返します。
5. Codex側がアクセストークンを取得します。
6. CodexがAPIMへ `Authorization: Bearer <access_token>` を付けてMCP通信します。
7. APIMはAuthorizationヘッダーをSnowflakeへ転送します。
8. Snowflakeはトークンを検証し、利用者の`DEFAULT_ROLE`でMCPツールを実行します。

この方式では、SnowflakeのQuery HistoryやAccess Historyでユーザー単位の追跡がしやすくなります。

### 6.5 OAuth方式B: APIM代理方式の流れ

1. Codex GUIはAPIMのMCP URLに接続します。
2. APIMはCredential managerからSnowflake用アクセストークンを取得します。
3. APIMがSnowflake MCP endpointへ `Authorization: Bearer <access_token>` を付けて転送します。
4. Snowflake上では、原則APIM側のサービスユーザーまたは接続設定に紐づくユーザーとして実行されます。

この方式はGUI運用しやすい反面、ユーザー単位のSnowflake RBACや監査が弱くなります。利用する場合は、必ず読み取り専用ロールに限定してください。

---

## 7. Azure / APIMネットワーク設定

### 7.1 入力画面

この章の作業は、基本的に **Azure Portal** で行います。CLIは使いません。

操作開始場所:

1. ブラウザでAzure Portalを開きます。
2. 検索ボックスで **API Management services** を検索します。
3. 対象のAPIMインスタンスを開きます。

### 7.2 APIMのMCPサポートを確認する

Azure Portalで確認する場所:

1. **API Management services** を開きます。
2. 対象APIMを選択します。
3. 左メニューで **Overview** を開きます。
4. **Pricing tier** を確認します。
5. 左メニューの **APIs** 配下に **MCP servers** が表示されるか確認します。

表示されない場合は、APIMのリージョン、価格レベル、機能提供状況をAzure管理者に確認してください。

### 7.3 APIMの入口をPrivate Endpoint化する

Codex GUIが動くWindows PCからAPIMへプライベート接続したい場合、APIMのInbound Private Endpointを使います。

Azure Portalでの操作:

1. 対象APIMを開きます。
2. 左メニューで **Network** または **Networking** を開きます。
3. **Private endpoint connections** を開きます。
4. **+ Private endpoint** を選択します。
5. 対象VNetとSubnetを選択します。
6. Private DNS zoneとの統合を有効にします。
7. 作成後、接続状態が **Approved** になっていることを確認します。
8. 疎通確認が完了してから、必要に応じてPublic network accessを無効化します。

重要:

- Codex GUIを使うWindows PCは、社内VPN、ExpressRoute、AVD、踏み台VMなどを通じて、APIM Private Endpointへ到達できる必要があります。
- Private DNSでAPIMのホスト名がプライベートIPへ解決される必要があります。

### 7.4 APIMからSnowflake PrivateLinkへ到達できるようにする

APIMからSnowflakeへは、Snowflake PrivateLinkのプライベートURLへ到達できる必要があります。

確認項目:

| 確認項目 | 内容 |
|---|---|
| APIMのネットワーク配置 | APIMがSnowflake PrivateLinkに到達可能なVNetに接続されているか |
| DNS | Snowflake PrivateLinkホスト名がプライベートIPに解決されるか |
| NSG/Firewall | APIMからSnowflake PrivateLink宛てTCP 443が許可されているか |
| ルート | APIMサブネットからSnowflake PrivateLinkへの経路があるか |
| 証明書 | 社内プロキシやTLS inspectionがMCP streamingを壊していないか |

### 7.5 WindowsからDNS確認する場合

入力画面: **Windows > スタートメニュー > `cmd` と入力 > コマンドプロンプト**

以下は確認用コマンドです。`REM`の行は説明コメントなので、そのまま貼り付けても実害はありません。

```cmd
REM APIMのGatewayホスト名がプライベートIPに解決されるか確認します。
nslookup <APIM_GATEWAY_HOST>
REM Snowflake PrivateLinkホスト名がプライベートIPに解決されるか確認します。
nslookup <SNOWFLAKE_ACCOUNT_URL>
```

期待する結果:

- APIM Gatewayホスト名が社内/Azure VNetのプライベートIPに解決される。
- Snowflake PrivateLinkホスト名がAzure PrivateLinkのプライベートIPに解決される。
- Public IPに解決される場合は、Private DNSの設定を見直します。

---

## 8. APIMでSnowflake MCP serverを公開する

### 8.1 入力画面

この章の作業は **Azure Portal > API Management > APIs > MCP servers** で行います。

### 8.2 既存MCPサーバーとして登録する

Azure Portalでの操作:

1. Azure Portalで対象APIMを開きます。
2. 左メニューで **APIs** を開きます。
3. **MCP servers** を選択します。
4. **+ Create MCP server** を選択します。
5. **Expose an existing MCP server** を選択します。
6. **Backend MCP server base URL** にSnowflake MCP server URLを入力します。
7. **Transport type** は **Streamable HTTP** を選択します。
8. **Name** に `company-snowflake-mcp` など分かりやすい名前を入力します。
9. **Base path** に `snowflake-mcp` などCodexへ公開するパスを入力します。
10. 必要に応じて **Products** を選択します。
11. **Create** を選択します。

Backend MCP server base URLの例:

`https://<SNOWFLAKE_ACCOUNT_URL>/api/v2/databases/<SNOWFLAKE_DB>/schemas/<SNOWFLAKE_SCHEMA>/mcp-servers/CODEX_SNOWFLAKE_MCP`

Codexに設定するURLは、APIM作成後に表示される **Server URL** を使います。

Codexに設定するAPIM URLの例:

`https://<APIM_GATEWAY_HOST>/snowflake-mcp`

### 8.3 APIMで公開するツールを絞る

Azure Portalでの操作:

1. APIMの対象MCP serverを開きます。
2. 左メニューで **Tools** を開きます。
3. 初期段階では `sql_readonly` だけを有効にします。
4. 書き込み系や用途不明なツールは無効化します。
5. ツール説明が正しいか確認します。

---

## 9. APIM policy設定

### 9.1 重要な注意

MCPはstreaming通信を使うため、APIM policyでレスポンス本文を読み取ったりバッファリングしたりしないでください。  
特に `context.Response.Body` を参照するポリシーは避けてください。

### 9.2 入力画面

Azure Portalでの操作:

1. Azure Portalで対象APIMを開きます。
2. 左メニューで **APIs > MCP servers** を開きます。
3. 作成したMCP serverを選択します。
4. 左メニューで **Policies** を開きます。
5. XML policyを編集します。
6. 保存します。

### 9.3 OAuth方式A: Authorizationヘッダー転送 + レート制限

この方式では、CodexからAPIMに届いた `Authorization: Bearer ...` をSnowflakeへ転送します。

入力画面: **Azure Portal > APIM > MCP servers > 対象MCP server > Policies**

```xml
<policies> <!-- APIM policy全体のルート要素です。 -->
  <inbound> <!-- CodexからAPIMへ入ってきたリクエストに対する処理です。 -->
    <base /> <!-- APIMの上位スコープに設定済みの共通policyを維持します。 -->
    <set-header name="Authorization" exists-action="override"> <!-- Authorizationヘッダーをバックエンド向けに明示的に設定します。 -->
      <value>@(context.Request.Headers.GetValueOrDefault("Authorization", ""))</value> <!-- Codexから届いたBearer tokenをそのまま取得します。 -->
    </set-header> <!-- Authorizationヘッダー設定を終了します。 -->
    <rate-limit-by-key calls="30" renewal-period="60" counter-key="@(context.Subscription?.Key ?? context.Request.IpAddress)" /> <!-- 同じ購読キーまたはIPからの呼び出しを60秒あたり30回に制限します。 -->
  </inbound> <!-- inbound処理を終了します。 -->
  <backend> <!-- APIMからSnowflakeへ転送する直前の処理です。 -->
    <base /> <!-- 標準のバックエンド転送処理を維持します。 -->
  </backend> <!-- backend処理を終了します。 -->
  <outbound> <!-- SnowflakeからAPIMへ戻るレスポンスに対する処理です。 -->
    <base /> <!-- 標準のレスポンス処理を維持します。 -->
  </outbound> <!-- outbound処理を終了します。 -->
  <on-error> <!-- policy実行中にエラーが起きた場合の処理です。 -->
    <base /> <!-- 標準のエラー処理を維持します。 -->
  </on-error> <!-- エラー処理を終了します。 -->
</policies> <!-- APIM policy全体を終了します。 -->
```

### 9.4 OAuth方式B: APIM Credential managerでSnowflake tokenを付ける

この方式では、CodexからSnowflake tokenを渡さず、APIMがSnowflake向けトークンを付与します。

事前にAzure Portalで行うこと:

1. APIMの **Credential manager** を開きます。
2. Snowflake OAuth用のCredential providerを作成します。
3. Snowflake OAuthのClient ID / Secretを登録します。
4. Token endpoint、Authorization endpoint、Scopeを設定します。
5. 接続を作成し、APIMからトークン取得できることを確認します。

入力画面: **Azure Portal > APIM > MCP servers > 対象MCP server > Policies**

```xml
<policies> <!-- APIM policy全体のルート要素です。 -->
  <inbound> <!-- CodexからAPIMへ入ってきたリクエストに対する処理です。 -->
    <base /> <!-- APIMの上位スコープに設定済みの共通policyを維持します。 -->
    <get-authorization-context provider-id="<CREDENTIAL_PROVIDER_ID>" authorization-id="<AUTHORIZATION_ID>" context-variable-name="auth-context" identity-type="managed" ignore-error="false" /> <!-- APIM Credential managerからSnowflake用OAuthトークンを取得します。 -->
    <set-header name="Authorization" exists-action="override"> <!-- Snowflakeへ送るAuthorizationヘッダーを設定します。 -->
      <value>@("Bearer " + ((Authorization)context.Variables.GetValueOrDefault("auth-context"))?.AccessToken)</value> <!-- 取得したアクセストークンをBearer形式で設定します。 -->
    </set-header> <!-- Authorizationヘッダー設定を終了します。 -->
    <rate-limit-by-key calls="30" renewal-period="60" counter-key="@(context.Subscription?.Key ?? context.Request.IpAddress)" /> <!-- 同じ購読キーまたはIPからの呼び出しを60秒あたり30回に制限します。 -->
  </inbound> <!-- inbound処理を終了します。 -->
  <backend> <!-- APIMからSnowflakeへ転送する直前の処理です。 -->
    <base /> <!-- 標準のバックエンド転送処理を維持します。 -->
  </backend> <!-- backend処理を終了します。 -->
  <outbound> <!-- SnowflakeからAPIMへ戻るレスポンスに対する処理です。 -->
    <base /> <!-- 標準のレスポンス処理を維持します。 -->
  </outbound> <!-- outbound処理を終了します。 -->
  <on-error> <!-- policy実行中にエラーが起きた場合の処理です。 -->
    <base /> <!-- 標準のエラー処理を維持します。 -->
  </on-error> <!-- エラー処理を終了します。 -->
</policies> <!-- APIM policy全体を終了します。 -->
```

> 注意: 方式BではSnowflake上の監査がAPIM用ユーザーに寄りやすくなります。利用者別の監査が必要な場合は方式Aを選んでください。

---

## 10. Codex GUI側の設定

### 10.1 Codex appのインストール

入力画面: **Windowsのブラウザ**

1. OpenAIのCodex app配布ページを開きます。
2. Windows版Codex appをダウンロードします。
3. インストーラーを実行します。
4. Codex appを起動します。
5. ChatGPTアカウントでサインインします。

### 10.2 推奨: Codex GUIのPluginsから追加する

この方法が、CLIを使わない前提に最も合います。

入力画面: **Codex GUI**

1. Codex appを開きます。
2. 左側または上部メニューから **Plugins** を開きます。
3. **Shared with you** または社内マーケットプレイスにあるSnowflake MCPプラグインを探します。
4. プラグイン詳細を開きます。
5. **Add to Codex** または `+` ボタンを選択します。
6. 認証を求められた場合は、Snowflakeまたは社内認証画面でサインインします。
7. 新しいCodex threadを開始します。
8. `@` を入力してSnowflake MCPプラグインまたはツールが表示されるか確認します。

社内プラグインに含めるべき設定:

- APIMのMCP Server URL
- 利用可能ツールの許可リスト
- OAuthの認証方式
- 利用者に表示する説明文
- 書き込みSQLを禁止する運用ルール

### 10.3 代替: `config.toml`をメモ帳で編集する

この方法ではCLIを使いません。Windowsのエクスプローラーとメモ帳で設定します。

入力画面: **Windows エクスプローラー / メモ帳**

操作手順:

1. Codex appを終了します。
2. エクスプローラーを開きます。
3. アドレスバーに `%USERPROFILE%\.codex` と入力します。
4. フォルダーが無い場合は `.codex` フォルダーを作成します。
5. `config.toml` ファイルを作成します。
6. `config.toml` をメモ帳で開きます。
7. 以下の内容を貼り付け、環境に合わせて修正します。
8. 保存します。
9. Codex appを再起動します。

#### 10.3.1 OAuthを使う場合のCodex設定例

入力画面: **メモ帳で開いた `C:\Users\<Windowsユーザー名>\.codex\config.toml`**

```toml
mcp_oauth_callback_port = 5555 # OAuthで固定callbackポートが必要な場合に、Codexのローカルcallbackポートを5555に固定します。
mcp_oauth_credentials_store = "auto" # OAuth資格情報をOSの安全な保存先に保管できる場合は自動選択させます。
[mcp_servers.company_snowflake] # company_snowflakeという名前でMCPサーバー設定を開始します。
url = "https://<APIM_GATEWAY_HOST>/<APIM_MCP_BASE_PATH>" # Codexが接続するAPIM上のMCP Server URLを指定します。
enabled = true # このMCPサーバー設定を有効にします。
required = true # このMCPサーバーに接続できない場合は起動時に失敗として扱います。
startup_timeout_sec = 20 # MCPサーバー接続開始を20秒まで待ちます。
tool_timeout_sec = 120 # MCPツールの1回の実行を120秒まで待ちます。
default_tools_approval_mode = "prompt" # ツール実行前にCodexで承認確認を表示させます。
enabled_tools = ["sql_readonly"] # Codexから使えるツールを読み取り専用SQLツールだけに限定します。
```

> 注意: この設定だけでOAuthログイン画面がGUIに表示されない場合は、Codex GUIの機能だけでは手動MCP OAuthログインを完結できない可能性があります。その場合は、社内プラグイン方式またはAPIM代理方式に切り替えてください。

#### 10.3.2 APIM Subscription Keyを使う場合のCodex設定例

APIMのProduct/Subscriptionで購読キーを必須にする場合は、Codexの設定にヘッダーを追加します。  
平文のキーを`config.toml`へ直接書くより、Windowsユーザー環境変数に保存する方が安全です。

Windows GUIで環境変数を登録する手順:

1. Windowsのスタートメニューを開きます。
2. `環境変数` と検索します。
3. **システム環境変数の編集** を開きます。
4. **環境変数** ボタンを選択します。
5. **ユーザー環境変数** の **新規** を選択します。
6. 変数名に `APIM_SUBSCRIPTION_KEY` を入力します。
7. 変数値にAPIMのSubscription Keyを入力します。
8. OKで保存します。
9. Codex appを再起動します。

入力画面: **メモ帳で開いた `C:\Users\<Windowsユーザー名>\.codex\config.toml`**

```toml
[mcp_servers.company_snowflake] # company_snowflakeという名前でMCPサーバー設定を開始します。
url = "https://<APIM_GATEWAY_HOST>/<APIM_MCP_BASE_PATH>" # Codexが接続するAPIM上のMCP Server URLを指定します。
enabled = true # このMCPサーバー設定を有効にします。
startup_timeout_sec = 20 # MCPサーバー接続開始を20秒まで待ちます。
tool_timeout_sec = 120 # MCPツールの1回の実行を120秒まで待ちます。
default_tools_approval_mode = "prompt" # ツール実行前にCodexで承認確認を表示させます。
enabled_tools = ["sql_readonly"] # Codexから使えるツールを読み取り専用SQLツールだけに限定します。
[mcp_servers.company_snowflake.env_http_headers] # HTTPヘッダー値をWindows環境変数から取得する設定を開始します。
Ocp-Apim-Subscription-Key = "APIM_SUBSCRIPTION_KEY" # APIM Subscription KeyをAPIM_SUBSCRIPTION_KEY環境変数から読み取って送信します。
```

> 注意: Subscription KeyだけではSnowflake OAuthの代わりにはなりません。Snowflake側にはOAuth tokenが必要です。Subscription KeyはAPIM入口の追加保護として使います。

---

## 11. 動作確認

### 11.1 確認順序

| 順序 | 確認内容 | 成功条件 |
|---:|---|---|
| 1 | Windows PCからAPIMホスト名のDNS解決 | プライベートIPに解決される |
| 2 | APIMからSnowflake PrivateLinkへの到達 | APIMのバックエンド接続で失敗しない |
| 3 | Snowflake OAuth | サインイン後にアクセストークンが取得される |
| 4 | APIM MCP server | APIMのServer URLが作成される |
| 5 | Codex MCP接続 | Codexに`sql_readonly`ツールが表示される |
| 6 | SQL実行 | SELECT系クエリのみ成功する |
| 7 | 書き込みSQLの拒否 | INSERT/UPDATE/DELETE/DDLが実行できない |

### 11.2 Codexでの確認プロンプト例

入力画面: **Codex GUIの新規thread**

```text
Snowflake MCPのsql_readonlyツールだけを使って、接続確認用に現在のユーザー名と現在のロールを確認してください。破壊的なSQLは実行しないでください。
```

期待する動き:

- CodexがMCPツール実行の承認を求める。
- 承認するとSnowflakeに読み取り系SQLが実行される。
- 現在ユーザー、現在ロール、現在Warehouseが返る。
- `CURRENT_ROLE()` が `MCP_CODEX_ROLE` になっている。

### 11.3 読み取り専用の確認プロンプト例

入力画面: **Codex GUIの新規thread**

```text
Snowflake MCPのsql_readonlyツールだけを使って、許可されたスキーマ内のテーブル一覧を確認してください。SELECT以外のSQLは実行しないでください。
```

期待する動き:

- テーブル一覧を取得できる。
- 対象外DBや対象外Schemaは権限不足で見えない。

---

## 12. トラブルシューティング

| 症状 | 主な原因 | 確認場所 | 対処 |
|---|---|---|---|
| CodexからAPIMに接続できない | VPN未接続、Private DNS不備、APIM Public access無効化後の経路不足 | Windows CMD / Azure DNS / APIM Networking | VPN接続、Private DNS、Private Endpoint承認状態を確認する |
| APIMからSnowflakeに接続できない | APIMがSnowflake PrivateLinkへ到達できない | APIM Networking / VNet / DNS / NSG | APIMのVNet接続、DNS、TCP 443許可を確認する |
| Snowflakeで401 | OAuth tokenが無い、期限切れ、APIMがAuthorizationを転送していない | APIM policy / Snowflake OAuth | Authorizationヘッダー転送、Credential manager、token有効期限を確認する |
| Snowflakeで403 | `USAGE ON MCP SERVER`やテーブル権限が無い | Snowflake Grants | MCP server、Warehouse、DB、Schema、Table権限を確認する |
| OAuth後のロールが違う | ユーザーの`DEFAULT_ROLE`がMCP用ロールではない | Snowflake User設定 | `ALTER USER ... DEFAULT_ROLE`を設定する |
| OAuthのRedirect URI mismatch | Snowflake登録URIとCodex/認証ブローカーのcallback URIが一致しない | Snowflake OAuth integration / Codex plugin | 完全一致するRedirect URIを登録する |
| MCPの応答が途中で止まる | APIM policyがresponse bodyを読み取りstreamingを壊している | APIM Policies / Diagnostics | `context.Response.Body`参照やFrontend Response body loggingを無効化する |
| Codexに不要なツールが表示される | Snowflake MCP serverまたはAPIM Toolsでツールを絞っていない | Snowflake MCP spec / APIM Tools / config.toml | `enabled_tools = ["sql_readonly"]` とAPIM Tools制御を設定する |
| 書き込みSQLが実行できてしまう | `read_only: true`が設定されていない、別ツールが有効 | Snowflake MCP server spec | SQL toolを読み取り専用にし、不要ツールを無効化する |
| ホスト名接続エラー | ホスト名にアンダースコアが含まれる | DNS / URL設定 | ハイフンを使うホスト名に変更する |

---

## 13. セキュリティチェックリスト

本番化前に必ず確認してください。

| チェック | 推奨設定 |
|---|---|
| MCP SQL tool | `read_only: true` を設定する |
| Codex tool approval | `default_tools_approval_mode = "prompt"` にする |
| Codex allowed tools | `enabled_tools = ["sql_readonly"]` にする |
| Snowflake Role | `MCP_CODEX_ROLE` を最小権限にする |
| Snowflake Warehouse | MCP専用Warehouseを使う |
| Snowflake OAuth | `ALLOWED_ROLES_LIST` でMCP用ロールだけ許可する |
| Snowflake OAuth | `OAUTH_USE_SECONDARY_ROLES = NONE` にする |
| Secret保管 | Client SecretをPCの平文ファイルに保存しない |
| APIM logging | MCP response bodyをログに出さない |
| APIM rate limit | 1ユーザーまたは1購読キーあたりの呼び出し数を制限する |
| APIM Private Endpoint | 疎通確認後にPublic access無効化を検討する |
| DNS | APIMとSnowflakeがプライベートIPに解決される |
| 監査 | Snowflake Query History、Access History、APIM logsを確認する |
| ツール説明 | ツール名と説明が誤解を招かない内容になっている |
| 再帰呼び出し | Cortex Agentから別MCPを呼ぶような循環構成を避ける |

---

## 14. 本番化の推奨進め方

### Phase 1: 最小構成で接続確認

- Snowflake MCP serverは`sql_readonly`だけにする。
- APIMはPrivate Endpoint化する前に、検証用ネットワークで疎通確認する。
- OAuthは開発用Redirect URIで検証する。
- Codexはツール実行時に必ず承認を出す。

### Phase 2: PrivateLink / DNS / APIM policyを固める

- APIM inbound Private Endpointを構成する。
- APIM outboundからSnowflake PrivateLinkへ到達できることを確認する。
- Public accessを無効化する前に、必ず社内Windows PCからの疎通を確認する。
- APIM policyでAuthorizationヘッダー転送、レート制限、監視を設定する。

### Phase 3: OAuth方式を確定する

- ユーザー単位の監査が必要なら、Codexプラグイン方式でSnowflake OAuthを利用する。
- GUIのみでの認証完結が必須で、かつCodexプラグイン方式が使えない場合は、APIM代理方式を検討する。
- APIM代理方式を使う場合は、読み取り専用ロールと専用Warehouseに強く制限する。

### Phase 4: 利用者展開

- 対象ユーザーに`MCP_CODEX_ROLE`を付与する。
- Codexプラグインを社内共有する。
- 利用者向けに「実行前承認」「SELECT以外禁止」「機密データ取り扱い」のルールを明文化する。
- APIM logsとSnowflake Query Historyを定期確認する。

---

## 15. Azure上に自作MCPサーバーをホストする代替構成

会社方針として「MCPサーバー本体をAzure上に置く」ことが必須の場合は、次の代替構成になります。

```text
[Codex GUI]
   |
   v
[APIM]
   |
   v
[Azure Container Apps / App Service]
  自作MCP Server
  Snowflake Connector
  OAuth token取得処理
   |
   v
[Snowflake PrivateLink]
```

この場合に追加で必要になるもの:

| 追加要素 | 説明 |
|---|---|
| MCP serverアプリ | PythonまたはTypeScriptでMCP serverを実装する |
| Azure実行基盤 | Container Apps、App Service、Functionsなど |
| Secrets管理 | Azure Key VaultにSnowflake OAuth Client Secretを保存する |
| Snowflake接続処理 | Snowflake connectorでOAuth tokenを使って接続する |
| 運用監視 | App Insights、ログ、アプリの脆弱性対応が必要 |

ただし、この方式は実装・保守・セキュリティレビューの負担が増えます。Snowflake-managed MCP serverで要件を満たせる場合は、Snowflake-managed MCP serverを優先してください。

---

## 16. 最終構成の要点

- Codex GUIはAPIMのMCP Server URLに接続する。
- APIMはAzure上の社内向けMCP Gatewayとして機能する。
- APIMのバックエンドはSnowflake PrivateLink経由のSnowflake-managed MCP serverにする。
- Snowflake MCP serverには最初は`sql_readonly`だけを公開する。
- Snowflake OAuthはMCP用ロールだけを許可する。
- Snowflake OAuthセッションはユーザーの`DEFAULT_ROLE`に依存するため、対象ユーザーの`DEFAULT_ROLE`を`MCP_CODEX_ROLE`にする。
- Codex側ではツール承認を`prompt`にし、`enabled_tools`で利用可能ツールを絞る。
- APIM policyではMCP streamingを壊さないよう、response bodyを読み取らない。
- 本番ではSnowflake Client SecretをPCに置かず、Key VaultやAPIM Credential managerで管理する。

---

## 17. 公式資料リンク

- OpenAI Codex app: https://developers.openai.com/codex/app
- OpenAI Codex Plugins: https://developers.openai.com/codex/plugins
- OpenAI Codex MCP: https://developers.openai.com/codex/mcp
- OpenAI Codex Configuration Reference: https://developers.openai.com/codex/config-reference
- Snowflake-managed MCP server: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp
- Snowflake OAuth Security Integration: https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-snowflake
- Azure API Management MCP overview: https://learn.microsoft.com/en-us/azure/api-management/mcp-server-overview
- Azure API Management - Expose existing MCP server: https://learn.microsoft.com/en-us/azure/api-management/expose-existing-mcp-server
- Azure API Management - Secure MCP servers: https://learn.microsoft.com/en-us/azure/api-management/secure-mcp-servers
- Azure API Management inbound private endpoint: https://learn.microsoft.com/en-us/azure/api-management/private-endpoint
- Azure API Management internal VNet mode: https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet
