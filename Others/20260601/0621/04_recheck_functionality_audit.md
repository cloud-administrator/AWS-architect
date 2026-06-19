# 3資料の再調査結果と機能判定

作成日: 2026-06-19

## 結論

3つの資料は、Snowflake-managed MCP server、Codex の `config.toml`、Azure API Management、Copilot Cowork の基本方針としては公式ドキュメントと整合しています。

ただし、この3資料をそのまま設定すれば無条件に必ず動く、とは言い切れません。特に注意が必要なのは次の2点です。

1. Codex から Snowflake へ直接 OAuth 接続する構成は、Codex GUI が Snowflake の事前登録 OAuth client を扱えるか実機確認が必要です。
2. APIM 経由構成では、Codex から APIM へ subscription key を送るだけでは不十分です。APIM から Snowflake へ送る Snowflake 用 `Authorization: Bearer ...` が必須です。

## 総合判定

| 資料 | 判定 | そのまま機能するための必須条件 |
|---|---|---|
| `01_codex_private_snowflake_mcp.md` | 条件付き | PrivateLink DNS/TLS が通り、Codex GUI が Snowflake OAuth client を扱えること。または `bearer_token_env_var` で有効な Snowflake token を渡せること |
| `02_codex_apim_private_snowflake_mcp.md` | 機能させやすい | Codex -> APIM の入口認証に加えて、APIM -> Snowflake の bearer token 付与または pass-through ができること |
| `03_copilot_cowork_public_snowflake_mcp.md` | 構成として妥当 | Teams Developer Portal の OAuth registration、manifest、Snowflake network policy、公開経路の許可が正しいこと |

初心者向けに言うと、Snowflake のMCPサーバー作成部分は大きく問題ありません。失敗しやすいのは、MCPそのものではなく「誰が、どのtokenで、どのURLへ接続するか」の認証とネットワーク部分です。

## 01 Codex PrivateLink 直結の判定

### 動くと判断できる部分

- Snowflake-managed MCP server の URL 形式は公式形式と一致しています。
- `CREATE MCP SERVER ... FROM SPECIFICATION` の考え方は Snowflake 公式構文と一致しています。
- Codex の `config.toml` で `url`、`scopes`、`mcp_oauth_callback_port`、`mcp_oauth_callback_url`、`bearer_token_env_var` を使う方針は Codex 公式設定と整合しています。
- PrivateLink URL を使うこと自体は、実装先PCのDNSとネットワークが正しければ問題ありません。

### 動かない可能性がある部分

Codex直結OAuthは要注意です。Snowflake-managed MCP server は OAuth をサポートしますが、Dynamic Client Registration はサポートしていません。さらに、公開されている Codex `config.toml` のMCP設定項目には、Snowflake OAuth の `client_id` と `client_secret` を直接書く項目が確認できません。

そのため、Codex GUI の初回接続時に OAuth ログインが開始されない、または Snowflake の client 情報を渡せない場合、直結OAuthは失敗します。

### 実装前の合格条件

- Codex GUI の MCP 設定で、Snowflake OAuth のログイン画面が開くこと。
- Snowflake の同意画面で、想定した `MCP_CODEX_ROLE` またはユーザーの `DEFAULT_ROLE` が使われること。
- OAuth が難しい場合、短時間 token を `SNOWFLAKE_MCP_ACCESS_TOKEN` 環境変数に入れ、`bearer_token_env_var` 方式で疎通できること。

## 02 Codex APIM経由 PrivateLink の判定

### 動くと判断できる部分

- APIM は既存の remote MCP server を公開し、Streamable HTTP の MCP endpoint として管理できます。
- APIM policy で rate limit、quota、認証、監査をかける設計は妥当です。
- Codex の `config.toml` から APIM URL へ接続し、`env_http_headers` で subscription key を送る方針は Codex 公式設定と整合しています。

### 動かない可能性がある部分

APIM subscription key は、Codex から APIM へ入るための鍵です。Snowflake に対する認証ではありません。

つまり、次の状態では失敗します。

```text
Codex -> APIM: Ocp-Apim-Subscription-Key は送っている
APIM -> Snowflake: Authorization ヘッダーがない
結果: Snowflake 側で 401 Unauthorized
```

### 実装前の合格条件

- APIM から Snowflake PrivateLink URL に到達できること。
- APIM の backend 呼び出しに `Authorization: Bearer <Snowflake用token>` が付いていること。
- APIM policy が MCP のストリーミング応答本文を読み取っていないこと。
- APIM のメトリックまたはトレースで、Codex からの呼び出しと Snowflake への backend 呼び出しを分けて確認できること。

## 03 Copilot Cowork パブリック接続の判定

### 動くと判断できる部分

- Copilot Cowork の `agentConnectors` に `remoteMcpServer` を書く方針は Microsoft の公式例と一致しています。
- OAuth は `OAuthPluginVault` と Teams Developer Portal の OAuth client registration を使うため、Snowflake の Client ID / Client Secret を Microsoft 側の token store に保管できます。
- Snowflake OAuth の redirect URI に `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect` を登録する方針は Microsoft の plugin OAuth 説明と整合しています。

### 動かない可能性がある部分

公開接続では、OAuth が成功しても Snowflake network policy で拒否される可能性があります。Microsoft 365 側の接続元IPを固定的に許可できない場合は、Snowflake を直接公開するより、公開APIM、Azure Front Door、WAF などを前段に置いて接続元を自社管理する方が安全です。

### 実装前の合格条件

- Teams Developer Portal の OAuth registration ID が manifest の `referenceId` と一致していること。
- manifest が Microsoft 365 管理センターで validation error なくアップロードできること。
- Snowflake network policy が Cowork または自社公開gatewayからの接続を許可していること。
- 初回利用時に Snowflake OAuth ログインが表示され、token endpoint で失敗しないこと。

## 実装前チェックリスト

### Snowflake Snowsight で確認

入力する画面: Snowflake Snowsight の `Worksheets`

```sql
-- MCP server object が作成されているか確認します。
SHOW MCP SERVERS IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME>;

-- MCP server object の tool 定義を確認します。
DESCRIBE MCP SERVER <MCP_SERVER_NAME>;

-- 利用者ユーザーに想定ロールが付いているか確認します。
SHOW GRANTS TO USER <SNOWFLAKE_USER_NAME>;

-- OAuth セッションで使う default role と default warehouse を確認します。
SHOW USERS LIKE '<SNOWFLAKE_USER_NAME>';
```

### Windows PC で確認

入力する画面: 実装先 Windows PC のブラウザー

1. Snowflake PrivateLink URL をブラウザーで開きます。
2. DNSエラーではなく、Snowflake 側の応答または認証エラーになることを確認します。
3. APIM経由の場合は、APIM の private endpoint URL もブラウザーで開きます。
4. ブラウザーで到達できない場合、Codex GUI からも到達できません。

### Codex GUI で確認

入力する画面: Codex GUI

1. `Settings` を開きます。
2. `Configuration` を開きます。
3. `Open config.toml` を押します。
4. 対象資料の `config.toml` 例を貼り付けます。
5. Codex GUI を完全に終了してから再起動します。
6. 最初は読み取り専用の質問だけで動作確認します。

### Azure Portal で確認

入力する画面: Azure Portal -> APIM

- `MCP servers` に Snowflake MCP server が登録されていること。
- APIM の inbound private endpoint が `Approved` であること。
- APIM から Snowflake PrivateLink へ名前解決できるネットワーク設計になっていること。
- APIM policy に rate limit と Snowflake 用 `Authorization` ヘッダー設定が入っていること。
- 診断ログで response body を読み取っていないこと。

## 資料に反映した修正

- `01_codex_private_snowflake_mcp.md` に、Codex直結OAuthは要検証であることを明記しました。
- `02_codex_apim_private_snowflake_mcp.md` に、APIM subscription key だけでは Snowflake 認証にならないことを明記しました。
- `02_codex_apim_private_snowflake_mcp.md` に、APIM から Snowflake へ固定 bearer token を付ける最小PoC例を追加しました。
- `03_copilot_cowork_public_snowflake_mcp.md` に、OAuthPluginVault は妥当だが公開接続の network policy と manifest validation が必須であることを明記しました。

## 最終判断

実装順としては、次を推奨します。

1. まず Snowflake-managed MCP server を作成し、Snowsight で `SHOW MCP SERVERS` と `DESCRIBE MCP SERVER` を確認します。
2. 次に APIM 経由構成で PoC します。Codex -> APIM は subscription key、APIM -> Snowflake は bearer token 付与にすると切り分けが簡単です。
3. 直結Codex OAuthは、Codex GUI が Snowflake OAuth の事前登録 client を扱えることを確認できた場合だけ採用します。
4. Copilot Cowork は、公開経路と network policy が固まってから OAuthPluginVault で実装します。

## 参考資料

- OpenAI: [Codex app settings](https://developers.openai.com/codex/app/settings)
- OpenAI: [Codex configuration reference](https://developers.openai.com/codex/config-reference)
- OpenAI: [Codex MCP](https://developers.openai.com/codex/mcp)
- Snowflake: [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- Snowflake: [CREATE MCP SERVER](https://docs.snowflake.com/en/sql-reference/sql/create-mcp-server)
- Snowflake: [Configure Snowflake OAuth for custom clients](https://docs.snowflake.com/en/user-guide/oauth-custom)
- Snowflake: [CREATE SECURITY INTEGRATION (Snowflake OAuth)](https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-snowflake)
- Microsoft: [Expose and govern an existing MCP server](https://learn.microsoft.com/en-us/azure/api-management/expose-existing-mcp-server)
- Microsoft: [Secure access to MCP servers in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/secure-mcp-servers)
- Microsoft: [llm-token-limit policy](https://learn.microsoft.com/en-us/azure/api-management/llm-token-limit-policy)
- Microsoft: [Build plugins for Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/cowork-plugin-development)
- Microsoft: [Configure authentication for MCP and API plugins in agents](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/plugin-authentication)
