# Codex側の設定手順

## 0. 最初に確認すべき重要事項

OpenAIの現在の公式仕様では、`https://chatgpt.com/codex/cloud/settings/policies`から配布されるクラウド管理ポリシーは、基本的に**`requirements.toml`互換の制約設定**です。

`requirements.toml`は、次の目的で使用します。

* 利用を許可するMCPサーバーを制限する
* MCPサーバー名とURLが一致する場合だけ有効にする
* ユーザーが別のMCPサーバーへ接続することを防ぐ

一方、MCPのURL、HTTPヘッダー、PATなどの実際の接続情報は、**`config.toml`または管理対象の`managed_config.toml`に設定する項目**です。OpenAIの公式ドキュメントには、「クラウド管理のrequirementsはrequirementsレイヤーだけに適用され、managed defaultsには適用されない」と明記されています。([OpenAI Developers][1])

したがって、以下の手順は、貴社のPolicies画面に次の両方が存在する場合を前提とします。

1. `Requirements TOML`または`requirements.toml`の入力欄
2. `Config TOML`、`Managed config`、`Managed defaults`などの入力欄

**2番目の入力欄が存在せず、`requirements.toml`しか入力できない場合は、PATを含むMCP接続設定をPolicies画面だけで配布する方法は、現在の公開公式仕様では確認できません。**

---

# 1. 事前に準備する値

Codex側で、次の2つの値を準備します。

```text
Snowflake-managed MCPのPrivateLink URL
```

例：

```text
https://myorg-myaccount.privatelink.snowflakecomputing.com/api/v2/databases/MCP_CONTROL_DB/schemas/MCP_CONTROL_SCHEMA/mcp-servers/CHATGPT_MCP_SERVER
```

```text
Snowflakeで発行したPAT
```

例：

```text
ver:1-hint:1234567890-secret:xxxxxxxxxxxxxxxxxxxxxxxx
```

以下では、MCPサーバーのCodex上の名前を次の値に統一します。

```text
snowflake_company
```

この名前は、`requirements.toml`と`config.toml`で**完全に同じ名前**にする必要があります。Codexは、MCPサーバー名とURLの両方がrequirementsの許可リストに一致した場合だけ、そのMCPサーバーを有効にします。([OpenAI Developers][1])

---

# 2. CodexのPolicies画面を開く

## 操作する画面

Webブラウザを使用します。CMDやPowerShellは使用しません。

1. ChromeまたはEdgeを開きます。
2. 次の画面を開きます。

```text
https://chatgpt.com/codex/cloud/settings/policies
```

3. ChatGPT Enterpriseまたは対象Workspaceの管理者アカウントでサインインします。
4. すでに組織全体へ割り当てているポリシーを開きます。
5. `Edit`、`編集`、または同等のボタンを押します。

画面上の名称は、Workspaceやリリース時期によって多少異なる可能性があります。OpenAIの公式ドキュメントも、現在の管理画面からポリシーを作成・割り当てるよう案内しており、割り当て動作は管理サービス側で変更される可能性があると説明しています。([OpenAI Developers][1])

---

# 3. requirements.tomlにSnowflake MCPの許可設定を追加する

## 入力する画面

Policies画面内の、次のいずれかの名称の入力欄です。

```text
Requirements TOML
```

または

```text
requirements.toml
```

既存の`requirements.toml`を削除せず、末尾などに次の設定を追加します。

```toml
# snowflake_companyという名前のMCPサーバーを許可リストへ登録します。
[mcp_servers.snowflake_company]

# このMCPサーバーで使用を許可するURLを完全一致で指定します。
identity = { url = "https://myorg-myaccount.privatelink.snowflakecomputing.com/api/v2/databases/MCP_CONTROL_DB/schemas/MCP_CONTROL_SCHEMA/mcp-servers/CHATGPT_MCP_SERVER" }
```

## 変更する場所

次の部分を、実際のSnowflake-managed MCP URLへ置き換えます。

```text
https://myorg-myaccount.privatelink.snowflakecomputing.com/api/v2/databases/MCP_CONTROL_DB/schemas/MCP_CONTROL_SCHEMA/mcp-servers/CHATGPT_MCP_SERVER
```

`requirements.toml`と後述の`config.toml`では、URLを完全に同じ文字列にしてください。

次の違いがあると、不一致になる可能性があります。

* 末尾の`/`の有無
* 大文字と小文字
* データベース名
* スキーマ名
* MCPサーバー名
* PrivateLink用URLと公開URLの違い
* URL内の余分な空白

`requirements.toml`の`mcp_servers`は許可リストとして動作します。設定された名前またはURLに一致しないMCPサーバーは無効になります。([OpenAI Developers][2])

## 既存のMCPサーバーがある場合

組織ですでに別のMCPサーバーを許可している場合、その設定を削除しないでください。

たとえば、既存の`github_company`と今回の`snowflake_company`を両方許可する場合は、次のようになります。

```toml
# 既存のGitHub用MCPサーバーを許可します。
[mcp_servers.github_company]

# 既存のGitHub用MCPサーバーURLを許可します。
identity = { url = "https://github.example.com/mcp" }


# 今回追加するSnowflake用MCPサーバーを許可します。
[mcp_servers.snowflake_company]

# Snowflake-managed MCPのPrivateLink URLを許可します。
identity = { url = "https://myorg-myaccount.privatelink.snowflakecomputing.com/api/v2/databases/MCP_CONTROL_DB/schemas/MCP_CONTROL_SCHEMA/mcp-servers/CHATGPT_MCP_SERVER" }
```

`requirements.toml`内に`mcp_servers`許可リストを設定すると、許可リストにないMCPサーバーは無効になるため、既存設定の消去には注意してください。([OpenAI Developers][1])

---

# 4. config.tomlにMCP接続設定とPATを追加する

## 入力する画面

Policies画面に、次のいずれかの名称の入力欄が存在する場合に使用します。

```text
Config TOML
```

```text
config.toml
```

```text
Managed config
```

```text
Managed defaults
```

この入力欄に、次の内容を追加します。

```toml
# snowflake_companyという名前でMCPサーバー設定を開始します。
[mcp_servers.snowflake_company]

# Snowflake-managed MCPへ接続するPrivateLink URLを指定します。
url = "https://myorg-myaccount.privatelink.snowflakecomputing.com/api/v2/databases/MCP_CONTROL_DB/schemas/MCP_CONTROL_SCHEMA/mcp-servers/CHATGPT_MCP_SERVER"

# このMCPサーバーをCodexで有効にします。
enabled = true

# VPN未接続などでMCPへ接続できなくても、ChatGPTデスクトップアプリ自体は起動できるようにします。
required = false

# MCPツールを実行するたびに、利用者へ承認を求めます。
default_tools_approval_mode = "prompt"

# MCPサーバーとの初期接続を最大20秒待ちます。
startup_timeout_sec = 20

# MCPツールの1回の実行を最大60秒待ちます。
tool_timeout_sec = 60


# Snowflake MCPへ送信する固定HTTPヘッダーの設定を開始します。
[mcp_servers.snowflake_company.http_headers]

# Snowflakeで発行したPATをBearerトークンとして送信します。
"Authorization" = "Bearer <SNOWFLAKE_PATをここに入力>"

# AuthorizationヘッダーのトークンがSnowflakeのPATであることを明示します。
"X-Snowflake-Authorization-Token-Type" = "PROGRAMMATIC_ACCESS_TOKEN"
```

CodexのStreamable HTTP形式のMCPサーバーでは、`url`、固定HTTPヘッダーの`http_headers`、有効・無効を制御する`enabled`、起動失敗時の動作を制御する`required`、タイムアウト、ツール承認モードを設定できます。([OpenAI Developers][2])

## 実際のPATを入力した例

以下は形式を理解するための例です。サンプルPATは使用できません。

```toml
# snowflake_companyという名前でSnowflake MCPを登録します。
[mcp_servers.snowflake_company]

# 実際のSnowflake-managed MCP PrivateLink URLを指定します。
url = "https://myorg-myaccount.privatelink.snowflakecomputing.com/api/v2/databases/MCP_CONTROL_DB/schemas/MCP_CONTROL_SCHEMA/mcp-servers/CHATGPT_MCP_SERVER"

# MCPサーバーを有効にします。
enabled = true

# MCP接続に失敗してもデスクトップアプリ全体の起動は継続させます。
required = false

# MCPツールを実行する前に、毎回ユーザーへ確認します。
default_tools_approval_mode = "prompt"

# MCPサーバー初期化の待ち時間を20秒にします。
startup_timeout_sec = 20

# 各ツール実行の待ち時間を60秒にします。
tool_timeout_sec = 60


# 固定HTTPヘッダーを設定します。
[mcp_servers.snowflake_company.http_headers]

# PATの先頭にBearerと半角スペースを付けて設定します。
"Authorization" = "Bearer ver:1-hint:1234567890-secret:xxxxxxxxxxxxxxxxxxxxxxxx"

# Snowflake PAT認証であることを明示します。
"X-Snowflake-Authorization-Token-Type" = "PROGRAMMATIC_ACCESS_TOKEN"
```

`Authorization`の値は、必ず次の形式にします。

```text
Bearer 半角スペース PAT本体
```

正しい例：

```text
Bearer ver:1-hint:1234567890-secret:xxxxxxxxxxxxxxxxxxxxxxxx
```

誤った例：

```text
Bearerver:1-hint:1234567890-secret:xxxxxxxxxxxxxxxxxxxxxxxx
```

誤った例：

```text
ver:1-hint:1234567890-secret:xxxxxxxxxxxxxxxxxxxxxxxx
```

---

# 5. URLがrequirements.tomlとconfig.tomlで一致していることを確認する

次の2つのURLは、文字列として完全に一致させます。

## requirements.toml側

```toml
identity = { url = "https://myorg-myaccount.privatelink.snowflakecomputing.com/api/v2/databases/MCP_CONTROL_DB/schemas/MCP_CONTROL_SCHEMA/mcp-servers/CHATGPT_MCP_SERVER" }
```

## config.toml側

```toml
url = "https://myorg-myaccount.privatelink.snowflakecomputing.com/api/v2/databases/MCP_CONTROL_DB/schemas/MCP_CONTROL_SCHEMA/mcp-servers/CHATGPT_MCP_SERVER"
```

また、セクション名も一致させます。

## requirements.toml側

```toml
[mcp_servers.snowflake_company]
```

## config.toml側

```toml
[mcp_servers.snowflake_company]
```

名前またはURLのどちらかが一致しない場合、CodexはそのMCPサーバーを無効にします。([OpenAI Developers][2])

---

# 6. ポリシーを保存して組織全体へ割り当てる

## 操作する画面

引き続き、WebブラウザのPolicies画面です。

1. TOMLの入力エラーが表示されていないことを確認します。
2. `Save`、`保存`、`Publish`、または同等のボタンを押します。
3. ポリシーの割り当て対象を開きます。
4. `All members`、`Entire workspace`、`組織内のすべてのメンバー`などを選択します。
5. 割り当てを保存します。

本番で全員へ公開する前に、可能であれば少人数のテストグループへ適用してください。OpenAIも、利用するすべてのクライアントバージョンが設定キーをサポートしていることを確認し、小規模グループでテストしてから組織全体へ展開することを推奨しています。([OpenAI Developers][1])

---

# 7. 利用者側でポリシーを反映する

## 操作する画面

各利用者のChatGPTデスクトップアプリです。

1. ChatGPTデスクトップアプリを完全に終了します。
2. Windowsの場合は、タスクトレイにChatGPTアイコンが残っていないことを確認します。
3. ChatGPTデスクトップアプリを再起動します。
4. 会社のChatGPT Workspaceへサインインしていることを確認します。
5. 新しいチャットを開始します。

対応するローカルクライアントは、ChatGPTでサインインした利用者に割り当てられたクラウド管理requirementsを取得し、署名済みキャッシュとして保存します。取得に失敗し、有効なキャッシュもない場合は、ポリシーなしで黙って起動するのではなく、設定読み込みエラーになります。([OpenAI Developers][1])

---

# 8. ChatGPTデスクトップアプリでMCPを確認する

## 方法1：設定画面で確認する

1. ChatGPTデスクトップアプリを開きます。
2. `Settings`を開きます。
3. `MCP servers`を開きます。
4. 次の名前が表示されることを確認します。

```text
snowflake_company
```

5. 状態が有効または接続済みであることを確認します。
6. `Restart`ボタンが表示される場合は押します。

## 方法2：チャット画面で確認する

新しいチャットの入力欄に、次を入力します。

```text
/mcp
```

接続中のMCPサーバー一覧に、次の名前が表示されることを確認します。

```text
snowflake_company
```

ChatGPTデスクトップアプリ、Codex CLI、IDE拡張機能は、同じCodexホスト上のMCP設定を共有します。チャット入力欄の`/mcp`から接続済みサーバーを確認できます。([OpenAI Developers][3])

---

# 9. Snowflake MCPの動作確認

新しいチャットで、次のように入力します。

```text
Snowflake MCPに接続できることを確認してください。

最初に使用可能なSnowflake MCPツールを確認してください。
その後、読み取り専用の簡単なSQLを実行してください。

実行するSQLを事前に表示し、
SELECT以外のSQLは実行しないでください。
```

`default_tools_approval_mode = "prompt"`を設定しているため、ツール実行前に承認画面が表示されます。

表示内容を確認してから承認します。

---

# 10. エラー別の確認方法

## `snowflake_company`が表示されない

確認項目：

* `requirements.toml`と`config.toml`のサーバー名が同じか
* 両方が`mcp_servers.snowflake_company`になっているか
* requirements側とconfig側のURLが完全に一致しているか
* ポリシーが組織または対象グループへ割り当てられているか
* 利用者が正しい会社Workspaceへサインインしているか
* アプリを完全に終了して再起動したか
* 利用者のChatGPTデスクトップアプリが新しいバージョンか

---

## MCPサーバーが「Disabled」と表示される

最も多い原因は、`requirements.toml`の許可リストとの不一致です。

次の4か所を比較します。

```toml
# requirements.toml
[mcp_servers.snowflake_company]
identity = { url = "https://..." }
```

```toml
# config.toml
[mcp_servers.snowflake_company]
url = "https://..."
```

確認内容：

* `snowflake_company`が一致している
* URL全体が一致している
* 末尾の`/`が一致している
* PrivateLink用URLを使用している

---

## HTTP 401または認証エラー

確認項目：

```toml
"Authorization" = "Bearer <実際のPAT>"
```

* `Bearer`のスペルが正しい
* `Bearer`とPATの間に半角スペースが1つある
* PATの前後に不要な空白がない
* PAT全体がコピーされている
* PATが期限切れになっていない
* Policies画面で古いPATが残っていない
* 設定変更後にアプリを再起動した

---

## 接続タイムアウトになる

今回のURLはPrivateLink用なので、利用者のPCがPrivateLinkへ到達できる状態である必要があります。

確認項目：

* 社内ネットワークへ接続している
* 必要な場合は会社VPNへ接続している
* 利用者PCがPrivateLink用DNSを参照できる
* HTTPSのTCP 443通信が許可されている
* 公開URLではなくPrivateLink URLを設定している

`required = false`の場合、PrivateLinkに接続できなくてもアプリ自体は起動しますが、Snowflake MCPだけが接続失敗になります。

---

# 11. PATをconfig.tomlへ直接記載する場合の注意点

次の設定は、Codexの構文としては有効です。

```toml
[mcp_servers.snowflake_company.http_headers]

"Authorization" = "Bearer <Snowflake PAT>"
```

Codexは`http_headers`に設定された固定HTTPヘッダーを各MCP HTTPリクエストへ追加します。([OpenAI Developers][2])

ただし、PATをクラウド管理configへ直接記載した場合、同じPATを利用するために、その値が割り当て対象のローカルクライアントへ配布される必要があります。

そのため、設計上は次の前提で管理してください。

* Policies画面を秘密情報保管庫と同等には扱わない
* ポリシーを閲覧・編集できる管理者を限定する
* 同じPATが全メンバーで共有される
* 1人の端末からPATが漏えいすると、共有PAT全体の交換が必要になる
* PATの有効期限を短くする
* PATのローテーション手順を用意する
* ポリシーの変更履歴を監査する
* 退職者や異動者をポリシー割り当てから除外する
* 可能であれば将来的にユーザー単位のOAuthへ移行する

---

# 12. Policies画面にConfig TOML欄が存在しない場合

Policies画面に`requirements.toml`の入力欄しか存在しない場合は、次の構成になります。

```text
Policies画面のrequirements.toml
    ↓
許可するMCPサーバー名とURLだけを設定

各PCのmanaged_config.toml
    ↓
MCP URL、PAT、HTTPヘッダーを設定
```

OpenAIの現在の公開公式ドキュメントでは、クラウド管理requirementsはmanaged defaultsには適用されません。管理対象の接続設定を配布する正式な別経路として、`managed_config.toml`またはmacOS MDMの`config_toml_base64`が説明されています。Windowsの管理対象設定ファイルは、通常、各ユーザーの`~/.codex/managed_config.toml`です。([OpenAI Developers][1])

したがって、**Policies画面にConfig TOML相当の別入力欄がない場合、PATをPolicies画面だけで組織全体へ配布する手順は、現在の公開公式仕様では確認できません。**

[1]: https://developers.openai.com/codex/enterprise/managed-configuration "Managed configuration | ChatGPT Learn"
[2]: https://developers.openai.com/codex/config-reference "Configuration Reference | ChatGPT Learn"
[3]: https://developers.openai.com/codex/mcp "Model Context Protocol | ChatGPT Learn"




＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝


## 実施する画面と作業内容

### 1. Webブラウザ：Codexのポリシー画面

ブラウザで次を開きます。

```text
https://chatgpt.com/codex/cloud/settings/policies
```

組織に適用しているポリシーを開き、`Edit`または`編集`を押します。

---

### 2. 「Requirements TOML」欄

この欄には、Snowflake MCPの**利用許可設定**を入力します。

```toml
# snowflake_companyという名前のMCPサーバーを許可します。
[mcp_servers.snowflake_company]

# 実際に使用を許可するSnowflake MCPのURLを指定します。
identity = { url = "https://＜PrivateLinkホスト名＞/api/v2/databases/＜DB名＞/schemas/＜スキーマ名＞/mcp-servers/＜MCPサーバー名＞" }
```

`requirements.toml`では、MCPサーバーの名前とURLが許可内容に一致しない場合、そのMCPサーバーは無効になります。([OpenAI Developers][1])

---

### 3. 「Config TOML」または「Managed defaults」欄

この欄には、Snowflake MCPへの**接続情報とPAT**を入力します。

```toml
# snowflake_companyという名前でMCP接続を登録します。
[mcp_servers.snowflake_company]

# Snowflake-managed MCPのPrivateLink URLを指定します。
url = "https://＜PrivateLinkホスト名＞/api/v2/databases/＜DB名＞/schemas/＜スキーマ名＞/mcp-servers/＜MCPサーバー名＞"

# このMCPサーバーを有効にします。
enabled = true

# 接続できなくてもCodexアプリ全体の起動は継続します。
required = false

# MCPツールを実行する前に利用者へ確認します。
default_tools_approval_mode = "prompt"

# 接続開始を最大20秒待ちます。
startup_timeout_sec = 20

# ツール実行を最大60秒待ちます。
tool_timeout_sec = 60


# Snowflakeへ送信する固定HTTPヘッダーを設定します。
[mcp_servers.snowflake_company.http_headers]

# ＜SnowflakeのPAT＞を実際のPATに置き換えます。
"Authorization" = "Bearer ＜SnowflakeのPAT＞"

# BearerトークンがSnowflake PATであることを明示します。
"X-Snowflake-Authorization-Token-Type" = "PROGRAMMATIC_ACCESS_TOKEN"
```

CodexはStreamable HTTP形式のMCPサーバーに接続でき、`http_headers`に設定した固定ヘッダーを各リクエストへ送信できます。([OpenAI Developers][2])

**Requirements TOMLとConfig TOMLでは、次を完全に一致させてください。**

```text
mcp_servers.snowflake_company
```

```text
Snowflake MCPのURL全体
```

---

### 4. 同じポリシー画面：保存と割り当て

設定入力後、次を実施します。

1. `Save`または`Publish`を押します。
2. ポリシーの割り当て対象を開きます。
3. `All members`または組織全体を選択します。
4. 割り当てを保存します。

---

### 5. 各利用者のChatGPTデスクトップアプリ

各利用者は次を実施します。

1. 会社のネットワークまたはVPNへ接続します。
2. ChatGPTデスクトップアプリを完全に終了します。
3. アプリを再起動します。
4. `Settings`を開きます。
5. `MCP servers`を開きます。
6. `snowflake_company`が表示されていることを確認します。
7. 必要に応じて`Restart`を押します。

チャット入力欄に次を入力しても確認できます。

```text
/mcp
```

デスクトップアプリでは、`Settings → MCP servers`からMCPを確認し、`/mcp`で接続中のサーバーを確認できます。([OpenAI Developers][2])

## 注意

ポリシー画面に**Requirements TOML欄しかない場合**、そこへPATや接続設定は入力できません。Requirementsは許可制御用であり、PATを含む接続設定にはConfig TOMLまたはManaged defaults相当の入力欄が必要です。([OpenAI Developers][1])

[1]: https://developers.openai.com/codex/enterprise/managed-configuration "Managed configuration | ChatGPT Learn"
[2]: https://developers.openai.com/codex/mcp "Model Context Protocol | ChatGPT Learn"

