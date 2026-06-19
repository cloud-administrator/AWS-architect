# Codex GUI から Snowflake MCP へ PrivateLink で直接接続する手順

作成日: 2026-06-19

## この資料の目的

この資料は、Windows の Codex GUI から、Azure Private Link 経由で Snowflake-managed MCP server に直接接続するための構成と手順を、初心者向けにまとめたものです。

ここでの「直接接続」とは、Azure API Management を経由せず、Codex GUI が Snowflake の MCP エンドポイントを直接呼び出す構成です。

## 結論

推奨構成は、Snowflake が提供する Snowflake-managed MCP server を使う構成です。自前で MCP サーバーアプリをホストしなくても、Snowflake 内で MCP server object を作成し、Cortex Search、Cortex Analyst、Cortex Agent、UDF、ストアドプロシージャ、または SQL 実行を MCP tool として公開できます。

ただし、Codex GUI で Snowflake OAuth の Client ID と Client Secret を入力できるかを必ず確認してください。Snowflake-managed MCP server は OAuth を推奨していますが、Snowflake は Dynamic Client Registration をサポートしていません。そのため、Codex GUI 側が Client ID と Client Secret を入力できない場合、直接OAuth接続は失敗する可能性があります。その場合は、`02_codex_apim_private_snowflake_mcp.md` の APIM 経由構成を優先してください。

## 全体構成

```mermaid
flowchart LR
    user["利用者"]
    codex["Windows PC\nCodex GUI"]
    vpn["社内ネットワーク / VPN / VDI\nPrivateLink 到達経路"]
    snowflake["Snowflake account\nPrivateLink URL"]
    mcp["Snowflake-managed MCP server"]
    oauth["Snowflake OAuth\nsecurity integration"]

    user --> codex
    codex --> vpn
    vpn --> snowflake
    snowflake --> mcp
    codex -. OAuth サインイン .-> oauth
    oauth -. access token .-> codex
```

## 事前に決める値

| 項目 | 例 | 説明 |
|---|---|---|
| Snowflake PrivateLink account URL | `https://<account>.privatelink.snowflakecomputing.com` | PrivateLink 経由で名前解決される Snowflake URL |
| Database | `ANALYTICS_DB` | MCP server object を作るデータベース |
| Schema | `MCP` | MCP server object を作るスキーマ |
| MCP server name | `CODEX_PRIVATE_MCP` | Snowflake 内で作る MCP server object 名 |
| Warehouse | `COMPUTE_WH` | MCP tool 実行時に使うウェアハウス |
| Access role | `MCP_CODEX_ROLE` | Codex 接続ユーザーに付与する最小権限ロール |
| OAuth integration | `CODEX_MCP_OAUTH` | Snowflake OAuth 用の security integration 名 |
| OAuth redirect URI | Codex GUI に表示される値 | Codex の OAuth コールバック先。GUIで表示されない場合は後述の固定URL案を使う |

## 重要な前提

- Snowflake 側の Azure Private Link は構築済みである前提です。
- 実装先 Windows PC から Snowflake PrivateLink URL に到達できる必要があります。
- DNS は Snowflake の account URL と OCSP URL を PrivateLink 側に解決できる必要があります。
- Codex は GUI を使用します。CLI は使いません。
- Snowflake の OAuth セッションでは、接続ユーザーの `DEFAULT_ROLE` が使われます。Secondary role は使えません。
- `ACCOUNTADMIN` や `SECURITYADMIN` などの強いロールを OAuth 接続用に使わないでください。

## 1. Snowflake 側のロールと権限を作る

入力する画面: Snowflake Snowsight の `Worksheets`

次の SQL は、管理者が Snowsight の Worksheet に貼り付けて実行します。`<...>` は自社環境の値に置き換えてください。

```sql
-- 管理者権限で作業するため、ACCOUNTADMIN ロールに切り替えます。
USE ROLE ACCOUNTADMIN;

-- Codex から MCP tool を使うための専用ロールを作成します。
CREATE ROLE IF NOT EXISTS MCP_CODEX_ROLE;

-- MCP tool 実行時に使うウェアハウスの利用権限を付与します。
GRANT USAGE ON WAREHOUSE <WAREHOUSE_NAME> TO ROLE MCP_CODEX_ROLE;

-- MCP server object を置くデータベースの利用権限を付与します。
GRANT USAGE ON DATABASE <DATABASE_NAME> TO ROLE MCP_CODEX_ROLE;

-- MCP server object を置くスキーマの利用権限を付与します。
GRANT USAGE ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE MCP_CODEX_ROLE;

-- MCP server object を作成できる権限をスキーマに付与します。
GRANT CREATE MCP SERVER ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE MCP_CODEX_ROLE;

-- Cortex Search を tool として使う場合だけ、対象サービスの利用権限を付与します。
GRANT USAGE ON CORTEX SEARCH SERVICE <DATABASE_NAME>.<SCHEMA_NAME>.<SEARCH_SERVICE_NAME> TO ROLE MCP_CODEX_ROLE;

-- UDF を custom tool として使う場合だけ、対象関数の利用権限を付与します。
GRANT USAGE ON FUNCTION <DATABASE_NAME>.<SCHEMA_NAME>.<FUNCTION_NAME>(<ARG_TYPES>) TO ROLE MCP_CODEX_ROLE;

-- ストアドプロシージャを custom tool として使う場合だけ、対象プロシージャの利用権限を付与します。
GRANT USAGE ON PROCEDURE <DATABASE_NAME>.<SCHEMA_NAME>.<PROCEDURE_NAME>(<ARG_TYPES>) TO ROLE MCP_CODEX_ROLE;

-- SQL 実行 tool を使う場合だけ、参照させたいテーブルまたはビューに SELECT 権限を付与します。
GRANT SELECT ON TABLE <DATABASE_NAME>.<SCHEMA_NAME>.<TABLE_NAME> TO ROLE MCP_CODEX_ROLE;
```

補足:

- 使わない tool 種別の `GRANT` は実行しないでください。
- 最初は読み取り系 tool だけで始めるのが安全です。
- SQL 実行 tool は便利ですが、広い権限を付けると想定外のデータ参照につながります。

## 2. Snowflake-managed MCP server を作成する

入力する画面: Snowflake Snowsight の `Worksheets`

次の例は Cortex Search Service を MCP tool として公開する最小構成です。実際には、自社で公開したい Cortex Search、Cortex Analyst、Cortex Agent、UDF、ストアドプロシージャに合わせて調整します。

```sql
-- MCP server を作成する専用ロールに切り替えます。
USE ROLE MCP_CODEX_ROLE;

-- MCP server object を作るデータベースを選択します。
USE DATABASE <DATABASE_NAME>;

-- MCP server object を作るスキーマを選択します。
USE SCHEMA <SCHEMA_NAME>;

-- Snowflake 内に MCP server object を作成または上書きします。
CREATE OR REPLACE MCP SERVER CODEX_PRIVATE_MCP
  -- ここから MCP server の tool 定義を YAML で記述します。
  FROM SPECIFICATION $$
    # この MCP server に公開する tool の一覧です。
    tools:
      # Codex に表示される tool の人間向けタイトルです。
      - title: "Search internal documents"
        # Codex が tool を呼ぶときに使う一意な名前です。
        name: "search_internal_documents"
        # この tool が何をするかを Codex に説明します。
        description: "Search approved internal documents through a Snowflake Cortex Search Service."
        # Cortex Search Service を呼び出す tool 種別です。
        type: "CORTEX_SEARCH_SERVICE_QUERY"
        # 実際に呼び出す Cortex Search Service の完全修飾名です。
        identifier: "<DATABASE_NAME>.<SCHEMA_NAME>.<SEARCH_SERVICE_NAME>"
  $$;
```

確認用 SQL です。

```sql
-- 現在のスキーマにある MCP server object の一覧を表示します。
SHOW MCP SERVERS IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME>;

-- 作成した MCP server object の定義を表示します。
DESCRIBE MCP SERVER CODEX_PRIVATE_MCP;
```

## 3. MCP server URL を作る

Codex GUI に登録する URL は、次の形式です。

```text
https://<account_url>/api/v2/databases/<database>/schemas/<schema>/mcp-servers/<mcp_server_name>
```

例:

```text
https://myorg-myaccount.privatelink.snowflakecomputing.com/api/v2/databases/ANALYTICS_DB/schemas/MCP/mcp-servers/CODEX_PRIVATE_MCP
```

注意:

- `<account_url>` は PrivateLink 用の Snowflake account URL を使います。
- クライアントによっては account URL 内の `_` が問題になるため、Snowflake 公式は `_` ではなく `-` を使うことを案内しています。

## 4. OAuth redirect URI を決める

入力する画面: Codex GUI の `Settings` -> `MCP`

まず Codex GUI で次の操作を行い、OAuth redirect URI が表示されるか確認します。

1. Codex GUI を開きます。
2. 左下または右上の `Settings` を開きます。
3. `MCP` を開きます。
4. `Add server` または `Add new server` を選びます。
5. 種類として `Remote`、`HTTP`、または `Streamable HTTP` を選びます。
6. Snowflake の MCP server URL を入力します。
7. 認証方式で `OAuth` を選びます。
8. 画面に表示される `Redirect URI` または `Callback URL` を控えます。

Codex GUI が redirect URI を表示しない場合は、固定の localhost callback URL を使う案があります。この場合、Codex の設定ファイルを GUI から開いて、次のように固定します。

入力する画面: Codex GUI の `Settings` -> `Config` または `Open config.toml`

```toml
# MCP OAuth のコールバック受信ポートを 4321 に固定します。
mcp_oauth_callback_port = 4321

# MCP OAuth の redirect_uri を固定します。
mcp_oauth_callback_url = "http://localhost:4321/callback"
```

この固定案を使う場合、Snowflake の OAuth integration には `http://localhost:4321/callback` を登録します。localhost の HTTP redirect を使うため、Snowflake 側で `OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE` が必要です。

## 5. Snowflake OAuth security integration を作成する

入力する画面: Snowflake Snowsight の `Worksheets`

次の例は、Codex GUI の redirect URI を `http://localhost:4321/callback` に固定した場合です。Codex GUI が HTTPS の redirect URI を表示する場合は、その値に置き換え、`OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE` は削除してください。

```sql
-- OAuth integration を作成するため、ACCOUNTADMIN ロールに切り替えます。
USE ROLE ACCOUNTADMIN;

-- Codex GUI 用の Snowflake OAuth security integration を作成または上書きします。
CREATE OR REPLACE SECURITY INTEGRATION CODEX_MCP_OAUTH
  -- Snowflake OAuth を使うことを指定します。
  TYPE = OAUTH
  -- Snowflake 公式クライアントではなく、自社で登録する custom client として扱います。
  OAUTH_CLIENT = CUSTOM
  -- この OAuth integration を有効化します。
  ENABLED = TRUE
  -- Client Secret を保持できるクライアントとして登録します。
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  -- Codex GUI が OAuth 完了後に戻ってくる URL です。
  OAUTH_REDIRECT_URI = 'http://localhost:4321/callback'
  -- localhost の HTTP redirect を許可します。HTTPS callback の場合はこの行を削除します。
  OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE
  -- 認可コード横取り対策として PKCE を必須にします。
  OAUTH_ENFORCE_PKCE = TRUE
  -- OAuth セッションで secondary roles を使わないようにします。
  OAUTH_USE_SECONDARY_ROLES = NONE
  -- access token 更新用の refresh token を発行します。
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  -- refresh token の有効期間を 1 日にします。必要に応じて社内ルールで調整します。
  OAUTH_REFRESH_TOKEN_VALIDITY = 86400
  -- 強い管理者ロールを OAuth 利用から明示的に除外します。
  BLOCKED_ROLES_LIST = ('ACCOUNTADMIN', 'SECURITYADMIN', 'ORGADMIN', 'GLOBALORGADMIN')
  -- ユーザーが認証画面へ行く経路にも PrivateLink を使う設定です。
  USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE;
```

Client ID と Client Secret を確認します。

```sql
-- OAuth client ID と client secret を表示します。
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('CODEX_MCP_OAUTH');
```

表示された値は、Codex GUI の MCP server 設定で使います。社内の秘密情報管理ルールに従って保管してください。

## 6. 利用者ユーザーにロールとデフォルトウェアハウスを設定する

入力する画面: Snowflake Snowsight の `Worksheets`

```sql
-- 管理者権限でユーザー設定を変更するため、ACCOUNTADMIN ロールに切り替えます。
USE ROLE ACCOUNTADMIN;

-- Codex を使う Snowflake ユーザーに MCP 用ロールを付与します。
GRANT ROLE MCP_CODEX_ROLE TO USER <SNOWFLAKE_USER_NAME>;

-- OAuth セッションで使われる default role と default warehouse を設定します。
ALTER USER <SNOWFLAKE_USER_NAME> SET DEFAULT_ROLE = 'MCP_CODEX_ROLE' DEFAULT_WAREHOUSE = '<WAREHOUSE_NAME>';
```

## 7. Codex GUI に MCP server を登録する

入力する画面: Codex GUI の `Settings` -> `MCP`

1. Codex GUI を開きます。
2. `Settings` を開きます。
3. `MCP` を開きます。
4. `Add server` または `Add new server` を押します。
5. 種類は `Remote`、`HTTP`、または `Streamable HTTP` を選びます。
6. `Name` に `snowflake-private` など分かりやすい名前を入力します。
7. `URL` に Snowflake MCP server URL を入力します。
8. `Authentication` で `OAuth` を選びます。
9. `Client ID` に Snowflake の `SYSTEM$SHOW_OAUTH_CLIENT_SECRETS` で出た client ID を入力します。
10. `Client Secret` に Snowflake の client secret を入力します。
11. `Save` または `Add` を押します。
12. `Sign in`、`Authorize`、または `Connect` が表示されたら押します。
13. ブラウザーで Snowflake のログイン画面が開いたら、対象ユーザーでログインします。
14. 同意画面が表示されたら、ロールが `MCP_CODEX_ROLE` になっていることを確認して承認します。
15. Codex GUI に戻り、Snowflake の tool が表示されることを確認します。

Codex GUI に `Client ID` と `Client Secret` の入力欄がない場合:

- Snowflake-managed MCP server との直接 OAuth 接続は、その GUI バージョンでは難しい可能性があります。
- その場合は、APIM 経由で認証と制御を分離する構成を検討してください。
- 詳細は `02_codex_apim_private_snowflake_mcp.md` を参照してください。

## 8. 動作確認

入力する画面: Codex GUI のチャット画面

次のように、最初は読み取りだけの依頼で確認します。

```text
Snowflake の search_internal_documents tool を使って、社内文書から「月次レポート」の関連情報を検索してください。SQLの実行や更新はしないでください。
```

確認すること:

- Codex が Snowflake の MCP tool を選択できること。
- Snowflake 側でエラーにならないこと。
- 返ってくる情報が、`MCP_CODEX_ROLE` で許可した範囲だけであること。
- 不要な tool が Codex に見えていないこと。

## OAuth の動き

OAuth は、Codex に Snowflake のパスワードを渡さずに接続するための仕組みです。

1. Codex GUI が Snowflake の OAuth 認可画面を開きます。
2. 利用者が Snowflake にログインします。
3. Snowflake が「このクライアントに、このロールでアクセスを許可しますか」と確認します。
4. 利用者が承認すると、Snowflake が Codex GUI に access token を返します。
5. Codex GUI は access token を使って MCP server を呼び出します。
6. Snowflake は token と `DEFAULT_ROLE` を確認し、許可された tool だけを実行します。

## トラブルシューティング

| 症状 | 原因候補 | 確認場所 |
|---|---|---|
| Codex から接続できない | 実装先 PC が PrivateLink URL を名前解決できていない | Windows のブラウザー、社内DNS、ネットワーク担当 |
| OAuth callback が失敗する | Snowflake の `OAUTH_REDIRECT_URI` と Codex の callback URL が一致していない | Snowflake `DESCRIBE INTEGRATION CODEX_MCP_OAUTH` |
| tool が見えない | MCP server object の `USAGE` 権限がない | Snowflake grants |
| tool 実行で権限エラー | tool の裏側の Cortex Search、UDF、テーブルなどに権限がない | Snowflake grants |
| OAuth 後に想定外ロールになる | ユーザーの `DEFAULT_ROLE` が違う | `SHOW USERS LIKE '<user>'`、`ALTER USER` |
| Client ID/Secret を入力できない | Codex GUI 側の MCP OAuth UI が Snowflake の方式に未対応 | APIM 経由構成を検討 |

## 運用上の推奨

- 最初は検索系や参照系 tool だけを公開します。
- tool 名と description は、何ができて何ができないかを明確に書きます。
- MCP server ごとに最大 tool 数を増やしすぎないようにします。
- OAuth integration の refresh token 有効期間は、社内セキュリティ方針に合わせて短めに始めます。
- 利用者ごとに権限差が大きい場合は、MCP server またはロールを分けます。

## 参考資料

- Snowflake: [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- Snowflake: [CREATE MCP SERVER](https://docs.snowflake.com/en/sql-reference/sql/create-mcp-server)
- Snowflake: [CREATE SECURITY INTEGRATION (Snowflake OAuth)](https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-snowflake)
- Snowflake: [Azure Private Link and Snowflake](https://docs.snowflake.com/en/user-guide/privatelink-azure)
- OpenAI: [Codex MCP](https://developers.openai.com/codex/mcp)
- OpenAI: [Codex app features](https://developers.openai.com/codex/app/features)
- MCP: [Authorization specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)

