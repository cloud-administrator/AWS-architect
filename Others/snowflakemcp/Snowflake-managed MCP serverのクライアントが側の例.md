## 結論

**2026年7月23日時点で、Snowflake-managed MCP serverをOAuthで利用するコーディングエージェントとしては、次の順で検討するのが妥当です。**

1. **Cursor Agent／Cursor Desktop** — 最有力。SnowflakeとCursorの双方が、固定のClient ID／Client Secretを使う設定を明示しています。
2. **Claude Code** — 有力。DCR非対応サーバー向けに、事前登録済みClient ID／Secretと固定callback portを公式サポートしています。
3. **VS Code＋GitHub CopilotのローカルAgent** — 有力。VS Code 1.123以降で、Client IDとOS保管のClient Secretに対応しています。
4. **Gemini CLI** — 技術的な候補。ただしSnowflakeとの公式なエンドツーエンド接続例がなく、事前検証が必要です。

会話型のAIクライアントであれば、**Claude.ai／Claude Desktop**と**ChatGPT Developer Mode**はSnowflake公式に接続例があります。対して、**CodexのネイティブMCP OAuth接続は、現時点ではSnowflakeの認証方式と適合しません**。

重要なのは、利用するAIモデルよりも、**そのAIエージェントがMCPホストとしてどのOAuthクライアント機能を実装しているか**です。同じOpenAI製品でも、ChatGPT Developer Modeでは接続でき、Codexでは接続できないという差があります。

---

## Snowflake側のOAuth要件

Snowflake-managed MCP serverには、次の制約があります。

* Dynamic Client Registration、つまりDCRをサポートしていない
* Snowflakeで事前登録した固定のClient IDとClient Secretが必要
* OAuth Security Integrationは`OAUTH_CLIENT = CUSTOM`かつ`OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'`
* Redirect URIを事前登録する必要がある
* Token endpointにおけるクライアント認証は、現在`Basic Base64(client_id:client_secret)`、すなわち`client_secret_basic`のみ対応

したがって、クライアント側に単に「MCP OAuth対応」と書かれているだけでは不十分です。**Static OAuth client credentials、Client Secret、固定Redirect URI、client_secret_basicによるトークン交換**が必要です。 ([スノーフレークドキュメント][1])

---

## 対応状況の比較

| クライアント／エージェント                   |     固定ID＋Secret | 固定Redirect URI |   Snowflake公式例 | 判定            |
| ------------------------------- | --------------: | -------------: | -------------: | ------------- |
| **Cursor Agent／Desktop**        |              対応 |             対応 |             あり | **◎ 第一候補**    |
| **Claude Code**                 |              対応 |             対応 | Snowflake専用例なし | **○ 有力**      |
| **VS Code＋Copilot Agent（ローカル）** |      対応、1.123以降 |             対応 | Snowflake専用例なし | **○ 有力**      |
| **Claude.ai／Claude Desktop**    |              対応 |             対応 |             あり | **◎ 会話型AI向け** |
| **ChatGPT Developer Mode**      |              対応 |        接続画面に表示 |             あり | **◎ 会話型AI向け** |
| **Gemini CLI**                  |              対応 |         任意指定可能 |             なし | **△ PoC推奨**   |
| **CodexネイティブMCP**               | 固定ID／Secret設定なし | callbackのみ指定可能 |             なし | **× OAuth不可** |
| **GitHub Copilot cloud agent**  | Remote OAuth非対応 |              ― |             なし | **× 不可**      |

### 1. Cursor Agent／Cursor Desktop

今回の条件に最も明確に適合しています。

Snowflake公式ドキュメントには、`mcp.json`の`auth`に`CLIENT_ID`と`CLIENT_SECRET`を設定する例が掲載されています。Cursor側も、DCR非対応プロバイダー向けの「Static OAuth」を明示的にサポートしています。Cursor Desktopのcallbackは`http://localhost:8787/callback`、Web／Cursor Agentsのcallbackは`https://www.cursor.com/agents/mcp/oauth/callback`です。 ([スノーフレークドキュメント][1])

したがって、**Codexからの移行先としてはCursorが最も確実**です。

### 2. Claude Code

Claude Codeは、DCR非対応のMCPサーバーを明示的に想定しています。`--client-id`、`--client-secret`、`--callback-port`を指定でき、redirect URIを`http://localhost:PORT/callback`に固定できます。Client Secretは設定ファイルの平文ではなく、OSキーチェーンまたは資格情報ファイルに保存されます。 ([Claude Platform Docs][2])

Snowflake公式にはClaude.ai／Desktopの例はありますが、Claude Code専用の接続例はありません。そのため評価は「公式機能上は適合しているが、Snowflakeとのステージング検証を推奨」です。

### 3. VS Code＋GitHub CopilotのローカルAgent

VS Code 1.123以降では、`mcp.json`の`oauth.clientId`と、OSのSecret Storageに保管するClient Secretが利用できます。DCR非対応時に固定資格情報へフォールバックする設計です。callbackには`http://127.0.0.1:33418`と`https://vscode.dev/redirect`の両方を登録します。Snowflakeは`OAUTH_ALTERNATE_REDIRECT_URIS`で複数callbackを登録できます。 ([Visual Studio Code][3])

ただし、これは**ローカルのVS Code Chat／Agent**の話です。GitHub上で動作する**Copilot cloud agentとCopilot code reviewは、remote MCPのOAuthを現在サポートしていません**。 ([GitHub Docs][4])

### 4. Gemini CLI

Gemini CLIはremote HTTP／SSE MCPのOAuthに対応し、`clientId`、`clientSecret`、`redirectUri`、`authorizationUrl`、`tokenUrl`を設定できます。固定callback URIも指定可能です。 ([Gemini CLI][5])

ただし、Gemini CLIのドキュメントには、Client SecretをSnowflakeが要求する`client_secret_basic`で送ることや、Snowflakeとの接続実績までは明示されていません。したがって、**検証環境でAuthorization Code交換とRefresh Token更新まで確認してから採用**するのが安全です。

### 5. Claude.ai／Claude Desktop

Snowflake公式の確認済みクライアントです。Snowflake MCP URL、Client ID、Client Secretを設定し、ブラウザでOAuth認証します。Claude.aiでは通常`https://claude.ai/api/mcp/auth_callback`、Desktopでは画面に表示されるlocalhost URIをSnowflakeに登録します。 ([スノーフレークドキュメント][1])

コーディングエージェントではなく、SnowflakeのCortex Analyst、Cortex Search、SQLツールなどを会話から使う用途に向いています。

### 6. ChatGPT Developer Mode

Snowflake公式ドキュメントでは、ChatGPTのDeveloper Modeでremote MCP connectorを作成し、OAuthを選択してClient IDとClient Secretを入力する手順が掲載されています。したがって、**ChatGPT側ではSnowflake OAuthを利用できます**。 ([スノーフレークドキュメント][1])

ただし、これはCodexとは別のMCPホスト実装です。また、現時点でFull MCPはChatGPT Business／Enterprise／Edu向けで、Proはread／fetch権限に制限されています。さらに、通常のChatGPT **Agent modeはcustom MCP appを使用しません**。 ([OpenAI Help Center][6])

---

## Codexで接続できなかった理由

Codexはremote Streamable HTTP MCPについて、一般的なOAuth自体はサポートしています。しかし、公式の`config.toml`設定項目には次のものしかありません。

* `url`
* `auth = "oauth"`
* `bearer_token_env_var`
* `http_headers`
* `env_http_headers`
* OAuth callback port／URL

**Snowflakeが必要とする固定Client IDとClient Secretを、MCPサーバーごとに設定する項目がありません。** ([OpenAI Developers][7])

OpenAIのCodexリポジトリにも、CodexがDCRを試行してしまい、事前登録済みOAuthクライアントを指定できないという未解決issueがあります。そこでは固定callback portだけでは解決しないことも報告されています。 ([GitHub][8])

したがって、今回の現象は概ね次の流れです。

```text
Codex
  └─ Dynamic Client Registrationを試行
       └─ SnowflakeはDCR非対応
            └─ OAuthクライアント登録に失敗

必要な動作:
Codex
  └─ 事前登録したClient ID / Client Secretを使用
       └─ 現在のCodexには設定方法がない
```

`http_headers`にClient Secretを設定しても解決しません。これはMCPサーバーへの通常リクエスト用ヘッダーであり、OAuth token endpointへのクライアント認証設定ではないためです。

---

## 最も確実なCursor構成例

### Snowflake OAuth Security Integration

Cursor DesktopとCursor Agentの両方を使用する場合は、2つのcallbackを登録します。

```sql
CREATE OR REPLACE SECURITY INTEGRATION MCP_CURSOR_OAUTH
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'http://localhost:8787/callback'
  OAUTH_ALTERNATE_REDIRECT_URIS = (
    'https://www.cursor.com/agents/mcp/oauth/callback'
  );

SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('MCP_CURSOR_OAUTH');
```

Snowflakeは、複数callbackが必要なクライアントに対して`OAUTH_ALTERNATE_REDIRECT_URIS`を使用するよう案内しています。 ([スノーフレークドキュメント][1])

### Cursor `mcp.json`

```json
{
  "mcpServers": {
    "snowflake": {
      "url": "https://<account_url>/api/v2/databases/<database>/schemas/<schema>/mcp-servers/<name>",
      "auth": {
        "CLIENT_ID": "${env:MCP_CLIENT_ID}",
        "CLIENT_SECRET": "${env:MCP_CLIENT_SECRET}"
      }
    }
  }
}
```

環境変数を設定してからCursorを起動します。

```bash
export MCP_CLIENT_ID='<SYSTEM$SHOW_OAUTH_CLIENT_SECRETSで取得したID>'
export MCP_CLIENT_SECRET='<取得したSecret>'
```

保存後、CursorのMCP設定からSnowflakeに対して`Sign in`を実行します。この設定形式はSnowflakeとCursorの双方の公式ドキュメントに掲載されています。 ([スノーフレークドキュメント][1])

---

## Claude Codeを使う場合

Snowflake側には、例えば次のcallbackを登録します。

```text
http://localhost:8080/callback
```

Claude Codeには次のように追加できます。

```bash
MCP_CLIENT_SECRET="$SNOWFLAKE_MCP_CLIENT_SECRET" \
claude mcp add \
  --transport http \
  --client-id "$SNOWFLAKE_MCP_CLIENT_ID" \
  --client-secret \
  --callback-port 8080 \
  snowflake \
  "https://<account_url>/api/v2/databases/<database>/schemas/<schema>/mcp-servers/<name>"
```

その後、Claude Code内の`/mcp`からブラウザ認証を実行します。 ([Claude Platform Docs][2])

---

## Codexを継続利用する場合の回避策

OAuthが必須要件でなければ、**Snowflake PATをBearer TokenとしてCodexに設定する方法**があります。

```toml
[mcp_servers.snowflake]
url = "https://<account_url>/api/v2/databases/<database>/schemas/<schema>/mcp-servers/<name>"
bearer_token_env_var = "SNOWFLAKE_PAT"
```

Codexは環境変数からBearer Tokenを送る機能を持っています。Snowflake-managed MCP serverもPAT利用を想定していますが、SnowflakeはOAuthを推奨しており、PATを使う場合はMCP専用の最小権限ロールに限定するよう案内しています。 ([OpenAI Developers][7])

OAuthによるユーザー単位のログイン、同意画面、アクセストークン更新が必須なら、PATは代替になりません。その場合はCursor、Claude Code、またはVS CodeのローカルAgentへ切り替えるのが妥当です。

---

## Snowflake側で注意する設定

OAuth接続に成功しても、Snowflakeセッションは接続ユーザーの`DEFAULT_ROLE`を使用し、Secondary Roleは利用できません。また`DEFAULT_WAREHOUSE`が未設定だとセッション初期化に失敗します。 ([スノーフレークドキュメント][1])

```sql
ALTER USER <username>
  SET DEFAULT_ROLE = '<mcp_access_role>'
      DEFAULT_WAREHOUSE = '<warehouse_name>';
```

運用上は、Cursor、Claude Code、ChatGPTなど**MCPホストごとにOAuth Security Integrationを分ける**ことを推奨します。Snowflake上は1つのIntegrationを共有できますが、分離することでSecretのローテーション、利用停止、監査、callback URI管理が容易になります。

PrivateLink環境からClaude.aiやChatGPTなどのSaaSクライアントを使う場合は、MCP URLにはpublic URLを指定し、Security Integrationに`USE_PRIVATELINK_FOR_AUTHORIZATION_ENDPOINT = TRUE`を設定する必要があります。 ([スノーフレークドキュメント][1])

**実務上の推奨構成は、コーディングエージェントならCursor、CLI中心ならClaude Code、既存のVS Code環境を維持するならVS Code 1.123以降＋ローカルCopilot Agentです。Codexをそのまま使う場合は、現状ではOAuthではなく最小権限PATが現実的な選択になります。**

[1]: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp "Snowflake-managed MCP server | Snowflake Documentation"
[2]: https://docs.anthropic.com/en/docs/claude-code/mcp "Connect Claude Code to tools via MCP - Claude Code Docs"
[3]: https://code.visualstudio.com/updates/v1_123 "Visual Studio Code 1.123"
[4]: https://docs.github.com/en/copilot/concepts/agents/cloud-agent/mcp-and-cloud-agent "Model Context Protocol (MCP) and GitHub Copilot cloud agent - GitHub Docs"
[5]: https://geminicli.com/docs/tools/mcp-server/ "MCP servers with Gemini CLI | Gemini CLI"
[6]: https://help.openai.com/en/articles/12584461-developer-mode-and-mcp-apps-in-chatgpt "Developer mode and MCP apps in ChatGPT | OpenAI Help Center"
[7]: https://developers.openai.com/codex/mcp "
  Model Context Protocol | ChatGPT Learn
"
[8]: https://github.com/openai/codex/issues/19154 "codex mcp login appears to require dynamic client registration for private OAuth MCP servers; cannot use pre-registered client identity · Issue #19154 · openai/codex · GitHub"
