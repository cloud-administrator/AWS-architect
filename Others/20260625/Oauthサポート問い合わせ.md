下記は、OpenAIサポートへそのまま送れる形の問い合わせ文です。OpenAI向けには英語の方が伝わりやすいので、英語版を主文として作成しています。Codex公式ドキュメントでは、MCP OAuthのcallback URL挙動、`bearer_token_env_var`、`--oauth-client-id`、`--oauth-resource` などは確認できますが、`client_secret` の渡し方は明確に確認しづらいため、その点を中心に質問する構成にしています。([OpenAI Developers][1])

Dear OpenAI Support Team,

We are evaluating a connection from Codex to a Snowflake-managed MCP server over Streamable HTTP.

Our target environment is as follows:

* MCP server: Snowflake-managed MCP server
* MCP client: Codex, ideally from Codex GUI / IDE extension and/or Codex CLI
* Network: PrivateLink-based Snowflake environment
* Authentication: Snowflake OAuth
* OAuth client type: Confidential client, where Snowflake issues a client_id and client_secret in advance
* Important constraint: Snowflake-managed MCP server does not support Dynamic Client Registration, so the MCP client must use a pre-registered OAuth client_id and client_secret

Based on the public Codex documentation we found, Codex appears to support Streamable HTTP MCP servers and OAuth login via commands such as `codex mcp login <name>`. We also found configuration and CLI options such as `url`, `bearer_token_env_var`, `http_headers`, `env_http_headers`, `--oauth-client-id`, and `--oauth-resource`.

However, we could not identify a clear, supported way to provide an OAuth `client_secret` for a confidential OAuth client.

Could you please clarify the following points?

1. Does Codex currently support OAuth authentication to a Streamable HTTP MCP server when the OAuth provider does not support Dynamic Client Registration and requires a pre-registered `client_id` and `client_secret`?

2. If yes, what is the officially supported way to provide the `client_secret` to Codex?

   * Is there a `config.toml` field for this?
   * Is there an environment variable mechanism?
   * Is it stored in the Codex credentials store or keyring?
   * Or is this flow currently unsupported?

3. Is `--oauth-client-id` intended only for public OAuth clients, or can it also be used with confidential clients that require a `client_secret`?

4. For MCP OAuth callback handling, Codex documentation says that `mcp_oauth_callback_url` is used as a base URL and that Codex appends a server-specific callback ID to produce the final `redirect_uri`.

   * How can we determine the exact final redirect URI that must be registered with the OAuth provider?
   * Is there a way to make the callback URI fully deterministic before the first login attempt?
   * Is a localhost HTTP callback supported for enterprise environments, or should HTTPS be used?

5. For a short PoC, is `bearer_token_env_var` an officially supported approach for connecting to a remote HTTP MCP server by sending an `Authorization: Bearer <token>` header?

   * If yes, does this bypass the Codex-managed OAuth login flow entirely?
   * Are there any limitations or security recommendations for this approach?

6. Are there any differences between Codex CLI and Codex GUI / IDE extension regarding MCP OAuth support, especially around confidential OAuth clients and client secrets?

7. If confidential-client OAuth is not currently supported directly, what is the recommended architecture?

   * Use a public OAuth client if allowed by our security policy?
   * Use `bearer_token_env_var` for PoC only?
   * Place an API gateway / internal proxy in front of the Snowflake MCP server and handle OAuth or token injection there?

Our current understanding is that the Snowflake-managed MCP server URL and PrivateLink routing are feasible, but the main uncertainty is whether Codex can complete Snowflake OAuth directly when the provider requires a pre-issued `client_secret` and does not support Dynamic Client Registration.

Could you please confirm whether this understanding is correct and advise the supported configuration pattern?

Best regards,
[Your Name]

日本語で社内確認用に残すなら、下記の版が使いやすいです。

OpenAIサポートご担当者様

現在、Codex から Snowflake-managed MCP server へ Streamable HTTP 経由で接続する構成を検証しています。

前提は以下のとおりです。

* MCP server：Snowflake-managed MCP server
* MCP client：Codex。可能であれば Codex GUI / IDE extension、および Codex CLI
* ネットワーク：PrivateLink 環境
* 認証方式：Snowflake OAuth
* OAuth client：Snowflake 側で事前発行した client_id / client_secret を使う confidential client
* 制約：Snowflake-managed MCP server は Dynamic Client Registration に対応していないため、MCP client 側で事前発行済みの client_id / client_secret を扱う必要があります

Codex の公開ドキュメント上では、Streamable HTTP MCP server や `codex mcp login <name>` による OAuth login、また `url`、`bearer_token_env_var`、`http_headers`、`env_http_headers`、`--oauth-client-id`、`--oauth-resource` などの設定項目は確認できました。

一方で、confidential OAuth client で必要となる `client_secret` を Codex に渡す標準的な方法が確認できませんでした。

以下についてご確認いただけますでしょうか。

1. Codex は、Dynamic Client Registration に対応していない OAuth provider に対して、事前発行済みの `client_id` と `client_secret` を使った MCP OAuth 認証をサポートしていますか。

2. サポートしている場合、`client_secret` はどのように Codex へ安全に渡す想定でしょうか。

   * `config.toml` に該当項目がありますか。
   * 環境変数で渡す方式がありますか。
   * Codex の credentials store / keyring に保存されますか。
   * それとも現時点では非対応でしょうか。

3. `--oauth-client-id` は public client 向けの機能でしょうか。それとも `client_secret` を必要とする confidential client でも利用できますか。

4. MCP OAuth の callback URL について、Codex では `mcp_oauth_callback_url` をベースURLとして使い、実際の `redirect_uri` にはサーバー固有の callback ID が付与されると理解しています。

   * OAuth provider 側に登録すべき完全な redirect URI は、どのように事前確認できますか。
   * 初回ログイン前に redirect URI を固定・確定する方法はありますか。
   * enterprise環境で localhost の HTTP callback を使うことは想定されていますか。それとも HTTPS callback が推奨でしょうか。

5. 短期PoCとして、`bearer_token_env_var` に Snowflake の有効な access token または PAT を入れ、`Authorization: Bearer <token>` として送る方式は、Codex の正式な利用方法として問題ないでしょうか。

   * この場合、Codex側のOAuth login flowは使わず、単純にBearer tokenを送る理解で合っていますか。
   * この方式を使う際の制約やセキュリティ上の推奨事項はありますか。

6. Codex CLI と Codex GUI / IDE extension で、MCP OAuth の対応範囲に違いはありますか。特に confidential client と client_secret の扱いに差異があるかを確認したいです。

7. もし Codex 直結で confidential-client OAuth がサポートされていない場合、推奨される構成はどれでしょうか。

   * 会社のセキュリティ方針上許可できる場合に public OAuth client を使う
   * PoCでは `bearer_token_env_var` を使う
   * APIM や社内プロキシを前段に置き、そこでOAuth処理またはBearer token付与を行う

現時点の理解では、Snowflake-managed MCP server のURL作成やPrivateLink経由の疎通自体は実現可能ですが、Codex が Snowflake OAuth を直結で完了できるかどうか、特に `client_secret` の扱いが最大の確認ポイントです。

この理解が正しいか、またOpenAIとして推奨される設定・構成があるかをご教示いただけますでしょうか。

よろしくお願いいたします。

[氏名]

[1]: https://developers.openai.com/codex/config-reference "Configuration Reference – Codex | OpenAI Developers"
