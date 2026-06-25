## Snowflake-managed MCP server と Codex 接続の整理

結論から言うと、上司の認識はかなり妥当です。

今回難しいのは、**Snowflake-managed MCP server のURLをどう作るか**ではありません。
本当に難しいのは、**Snowflake と Codex の OAuth 認証の方式がうまく噛み合うか**です。

---

## まず OAuth を簡単に説明すると

OAuth は、ざっくり言うと、
**「アプリにパスワードを直接渡さず、安全にアクセス許可を与える仕組み」**です。

たとえば今回の場合は、次のような関係です。

* **Snowflake**：データを持っている側
* **Codex**：Snowflake にアクセスしたいアプリ
* **OAuth**：Codex に「Snowflakeへアクセスしてよい」という許可を出す仕組み
* **client_id**：アプリの識別番号
* **client_secret**：アプリ用の秘密鍵のようなもの
* **access token / bearer token**：実際にアクセスするときに使う一時的な通行証
* **redirect URI**：ログイン後に戻ってくるURL

つまり、OAuthでは単にURLを叩けばよいのではなく、
**「どのアプリが、どの権限で、どこに戻ってくるのか」**を事前に正しく設定する必要があります。

---

## 今回の一番大きな問題

Snowflake-managed MCP server は OAuth に対応しています。

ただし、Snowflake側は **Dynamic Client Registration** には対応していません。

Dynamic Client Registration とは、簡単に言うと、
**アプリが自動的にOAuth用の登録を済ませる仕組み**です。

これが使えれば、Codex側が自動的にOAuthクライアントとして登録され、認証が比較的スムーズに進む可能性があります。

しかし Snowflake-managed MCP server ではそれが使えないため、
事前にSnowflake側で発行した **client_id / client_secret** を、MCPクライアント側に設定する必要があります。

---

## ここで Codex 側の制約が出てくる

Claude、ChatGPT Connector、Cursor などは、Snowflake公式手順に近い形で、
**client_id と client_secret を入力するUIや設定**があります。

そのため、Snowflake公式の想定に比較的合っています。

一方で Codex の公開ドキュメントを見る限り、HTTP MCP server の設定としては、主に次のような項目が確認できます。

* url
* bearer_token_env_var
* http_headers
* env_http_headers

また、CLIには `--oauth-client-id` はありますが、
`--oauth-client-secret` に相当する項目は見当たりません。

つまり、Snowflake側は
**「client_id と client_secret をMCPクライアントに設定してほしい」**
という前提なのに、Codex側では
**「client_secret を素直に渡す標準的な設定方法が見えにくい」**
という状態です。

ここが最大のひっかかりポイントです。

---

## つまり何が起きるのか

Snowflake-managed MCP server そのものは使えます。
PrivateLink URL を組み立てることもできます。
Codex の `config.toml` にMCP serverのURLを書くこともできます。

ただし、次の設定だけで、CodexからSnowflake OAuthがきれいに完了するとは限りません。

```toml
[mcp_servers.snowflake-private]
url = "https://<account>.privatelink.snowflakecomputing.com/api/v2/databases/<DATABASE_NAME>/schemas/<SCHEMA_NAME>/mcp-servers/CODEX_PRIVATE_MCP"
scopes = ["session:role:MCP_CODEX_ROLE"]
```

この設定は、MCP server の接続先を指定しているだけです。
OAuthで必要になる **client_id / client_secret / redirect URI** の扱いがまだ残ります。

特に Codex 直結で Snowflake OAuth を完了させる部分は、
そのまま本番手順として確定扱いしない方がよいです。

---

## redirect URI も注意点

OAuthでは、ログイン後に戻ってくるURLである **redirect URI** をSnowflake側に登録する必要があります。

ここも地味に難しい点です。

資料では次のような設定が想定されています。

```toml
mcp_oauth_callback_url = "http://localhost:4321/callback"
```

ただし Codex では、このURLをそのまま使うのではなく、
サーバーごとの callback ID を付けた redirect URI を使う説明になっています。

そのため、Snowflake側に登録する redirect URI は、
単純な `http://localhost:4321/callback` だけでは足りない可能性があります。

さらに Snowflake側では、redirect URI は基本的にTLS、つまり `https://` が前提です。
localhost の `http://` を使う場合は、Snowflake側で
`OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE`
のような追加設定が必要になる可能性があります。

---

## PrivateLink 環境での追加の難しさ

会社のSnowflakeが Azure Private Link 前提の場合、OAuth以前にネットワーク面の確認も必要です。

Codexを動かすPCから、Snowflake MCP server のURLが
**PrivateLink用のURLとして正しく解決できること**が必要です。

つまり、DNS設定として、Snowflakeの account URL や OCSP URL が
Private Endpoint の private IP に解決される必要があります。

この部分はOAuthの問題とは別ですが、
PrivateLink環境では接続確認の重要なポイントになります。

---

## 実現性の整理

| 内容                                                  | 実現性        |
| --------------------------------------------------- | ---------- |
| Snowflake-managed MCP server を作る                    | 実現可能       |
| PrivateLink URL で MCP server URL を組み立てる             | 実現可能       |
| Codex の config.toml に Streamable HTTP MCP の url を書く | 実現可能       |
| bearer_token_env_var で token を渡す                    | PoCとして実現可能 |
| Codex直結で Snowflake OAuth を完了する                      | 要検証。ここが難所  |

---

## 現実的な進め方

まずは、OAuthの完全対応を目指す前に、
**bearer_token_env_var 方式でSnowflake MCP serverへの疎通確認をする**のが現実的です。

これは、Snowflakeの有効な access token または PAT を環境変数に入れて、
Codexから `Authorization: Bearer ...` として送る方式です。

PoCとしては分かりやすく、問題の切り分けがしやすいです。

ただし、この方式にも注意点があります。

* tokenの発行方法を決める必要がある
* tokenの有効期限を管理する必要がある
* tokenの保管方法を安全にする必要がある
* tokenのローテーション運用が必要になる

本番運用まで考えるなら、次のような選択肢を検討するのが安全です。

1. **APIM や社内プロキシを前段に置く**
   CodexはAPIMやプロキシに接続し、APIM側でSnowflake用の認証処理を吸収する方式です。構成は増えますが、Codex側の制約を避けやすくなります。

2. **Snowflake OAuth integration を PUBLIC client として作る**
   Codexの `--oauth-client-id` だけで試せる可能性があります。ただし、PUBLIC client を会社のセキュリティ方針上許可できるかは確認が必要です。

3. **短期PoCでは bearer token 方式を使う**
   まずURL、PrivateLink、MCP server の疎通を確認する目的なら、この方式が最も切り分けやすいです。

---

## 結論

この資料の内容が丸ごと実現できない、という意味ではありません。

むしろ、次の内容は有効です。

* Snowflake-managed MCP server を作る考え方
* PrivateLink URL でMCP server URLを組み立てる考え方
* Codex の `config.toml` に Streamable HTTP MCP server のURLを書く考え方
* bearer_token_env_var を使ってPoCする考え方

ただし、注意すべきなのは、
**Codex GUI から Snowflake-managed MCP server に直結し、Snowflake OAuth でログインする部分**です。

ここは、Snowflake側が client_id / client_secret の設定を前提としている一方で、Codex側では client_secret を渡す標準設定が見えにくいため、そのまま動く前提にはしない方がよいです。

要するに、今回難しいのは Snowflake-managed MCP server そのものではありません。

難しいのは、次の要素が同時に重なることです。

**Snowflake-managed MCP server + Codex + OAuth + PrivateLink + 会社のセキュリティ制約**

上司向けに一言で言うなら、次の説明になります。

**Snowflake-managed MCP server はOAuth前提だが、SnowflakeはMCPのDynamic Client Registrationに対応しておらず、Codex側もclient secretを素直に渡す標準設定が見えにくい。そのため、Codex直結OAuthはひと手間かかる可能性が高い。PoCでは bearer token 方式か APIM 経由の方が問題を切り分けやすい。**
