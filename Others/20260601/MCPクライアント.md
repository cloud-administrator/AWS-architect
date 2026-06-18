# MCPクライアント.md

## 目的

Codex側のMCPクライアント設定の見本です。CodexはStreamable HTTP MCP serverへ接続できます。Snowflake-managed MCP serverはHTTP endpointとして公開されるため、Codex側では `codex mcp add --url ...` または `~/.codex/config.toml` に接続先を登録します。

この設定は会社PCで行ってください。自宅PCでは実接続やsecret保存は行いません。

## 1. 会社環境で置き換える値

```text
<ORG>                   Snowflake organization
<ACCOUNT>               Snowflake account
<DATABASE>              MCP serverを作成したdatabase
<SCHEMA>                MCP serverを作成したschema
<MCP_SERVER_NAME>       MCP server名
<OAUTH_CLIENT_ID>       Snowflake OAuth integrationのclient id
<OAUTH_RESOURCE>        必要な場合だけ指定するOAuth resource
```

Private接続用URL:

```text
https://<ORG>-<ACCOUNT>.privatelink.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>
```

Public接続用URL:

```text
https://<ORG>-<ACCOUNT>.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>
```

## 2. CLIで登録する見本

OAuthで接続する基本形です。

```powershell
codex mcp add snowflake-private `
  --url "https://<ORG>-<ACCOUNT>.privatelink.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>" `
  --oauth-client-id "<OAUTH_CLIENT_ID>"

codex mcp login snowflake-private
```

OAuth resourceが必要な場合だけ追加します。

```powershell
codex mcp add snowflake-private `
  --url "https://<ORG>-<ACCOUNT>.privatelink.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>" `
  --oauth-client-id "<OAUTH_CLIENT_ID>" `
  --oauth-resource "<OAUTH_RESOURCE>"

codex mcp login snowflake-private
```

確認:

```powershell
codex mcp list
codex mcp get snowflake-private --json
```

CodexのTUIを使う場合は、起動後に次を入力します。

```text
/mcp
```

## 3. `config.toml`で登録する見本

会社PCの `~/.codex/config.toml` に設定する例です。プロジェクト単位にしたい場合は、信頼済みプロジェクトの `.codex/config.toml` に置きます。

```toml
[mcp_servers.snowflake_private]
enabled = true
required = true
url = "https://<ORG>-<ACCOUNT>.privatelink.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>"
startup_timeout_sec = 20
tool_timeout_sec = 120
default_tools_approval_mode = "prompt"

# 必要な場合だけ指定する。
# oauth_resource = "https://<ORG>-<ACCOUNT>.privatelink.snowflakecomputing.com"
```

OAuth callbackの固定が必要な環境では、top-levelに設定します。

```toml
mcp_oauth_callback_port = 5555
# mcp_oauth_callback_url = "https://<company-approved-callback-url>/callback"
```

## 4. PATで疎通確認する場合

原則はOAuthです。PATはOAuthが会社PCのCodex構成で直ちに通らない場合の短期検証用です。

Snowflake PATを使う場合のCodex設定例:

```toml
[mcp_servers.snowflake_private_pat]
enabled = true
url = "https://<ORG>-<ACCOUNT>.privatelink.snowflakecomputing.com/api/v2/databases/<DATABASE>/schemas/<SCHEMA>/mcp-servers/<MCP_SERVER_NAME>"
bearer_token_env_var = "SNOWFLAKE_MCP_PAT"
http_headers = { "X-Snowflake-Authorization-Token-Type" = "PROGRAMMATIC_ACCESS_TOKEN" }
startup_timeout_sec = 20
tool_timeout_sec = 120
default_tools_approval_mode = "prompt"
```

PowerShellの現在のsessionだけにPATを入れる例:

```powershell
$env:SNOWFLAKE_MCP_PAT = "<TOKEN_SECRET>"
codex
```

PATをファイル、Markdown、Git、チャット、チケットに貼り付けないでください。

## 5. 動作確認の流れ

```powershell
# 1. Private hostnameが引けるか
Resolve-DnsName <ORG>-<ACCOUNT>.privatelink.snowflakecomputing.com

# 2. 443で到達できるか
Test-NetConnection <ORG>-<ACCOUNT>.privatelink.snowflakecomputing.com -Port 443

# 3. Codexに登録されているか
codex mcp list

# 4. OAuthログイン
codex mcp login snowflake-private
```

Codex起動後、`/mcp`でSnowflake MCP serverが表示されることを確認します。その後、Snowflake側のCortex Analyst/Search/Agent toolを呼ぶ質問を試します。

## 6. よく使う削除・再設定

```powershell
codex mcp logout snowflake-private
codex mcp remove snowflake-private
```

再登録:

```powershell
codex mcp add snowflake-private `
  --url "<MCP_ENDPOINT_URL>" `
  --oauth-client-id "<OAUTH_CLIENT_ID>"
```

## 参照元

- [Codex MCP](https://developers.openai.com/codex/mcp)
- [Codex CLI command reference](https://developers.openai.com/codex/cli/reference)
- [Snowflake REST API authentication / PAT](https://docs.snowflake.com/en/developer-guide/snowflake-rest-api/authentication)

