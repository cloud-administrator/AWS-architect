# Company Codex ポリシー解説書

対象ファイル: `requirements.company-codex-policy.elevated.txt`  
想定配置先: ChatGPT Codex > Cloud managed requirements / または管理端末の `requirements.toml`  
作成日: 2026-06-29

---

## 1. このファイルの目的

この解説書は、会社PCで Codex を安全に使うための `requirements.toml` ポリシーについて、初心者にも分かるように説明するための資料です。

対象のポリシーは、主に次のことを目的にしています。

| 目的 | 何を防ぎたいか |
|---|---|
| Workspace 内だけ編集させる | Codex が会社PC上の関係ないフォルダを書き換えることを防ぐ |
| Windows 共有フォルダ・マウントポイントを拒否する | 共有サーバー、ネットワークドライブ、外部ディスク、WSL の `/mnt` などへ書き込ませない |
| 承認なし実行を禁止する | Codex が危険な操作をユーザー確認なしで進めることを防ぐ |
| Web 検索を cached のみにする | live Web 取得による情報送受信面を減らす |
| MCP / Hooks / Plugin を管理者管理に寄せる | ユーザーが勝手に外部連携や拡張機能を追加することを防ぐ |
| 権限昇格・mount・共有操作を禁止する | `sudo`、`runas`、`net use`、`New-SmbMapping` などで制限を回避されることを防ぐ |
| 旧クライアントにも最低限対応する | Codex 0.138.0 未満など、permission profile を使えない環境でも full access を防ぐ |

---

## 2. 初心者向けの基本用語

### Codex

OpenAI の開発支援エージェントです。コードの修正、コマンド実行、ファイル編集などを手伝います。

### Workspace

Codex が作業対象にするフォルダです。たとえば `C:\Users\taro\projects\app` を Workspace として開くと、Codex はそのプロジェクトを中心に作業します。

このポリシーでは、原則として **Workspace の中だけ書き込み可能** にしています。

### requirements.toml

管理者が Codex に強制する制約を書くファイルです。

通常の `config.toml` はユーザー設定に近いものですが、`requirements.toml` は **ユーザーが弱められない会社ルール** として使います。

### permission profile

Codex に「どこまで読み書きさせるか」をまとめた権限セットです。

今回のポリシーでは、`company_workspace_only` という会社専用 profile を作り、それだけを使わせます。

### sandbox

Codex が実行するコマンドを隔離する仕組みです。

イメージとしては、Codex を「自由にPC全体を触れる状態」ではなく、「決められた柵の中だけで動く状態」にするものです。

### approval gate

危険な操作をする前に、ユーザーの承認を求める仕組みです。

このポリシーでは、`never`、つまり「確認なしで進めるモード」を禁止しています。

### MCP

Model Context Protocol の略です。Codex が外部ツールや社内ドキュメントサーバーなどと連携するための仕組みです。

便利ですが、外部接続や情報取得の入口にもなるため、このポリシーでは管理者が許可した MCP だけ使える設計にしています。

### Hooks

Codex の操作前後に、管理者が用意したチェック処理を差し込む仕組みです。

たとえば「危険なコマンドを検査する」「社内ポリシーに反する操作を止める」といった用途に使えます。

### UNC / Windows 共有フォルダ

Windows の共有フォルダの表記です。

例:

```text
\\server\share\project
```

このポリシーでは、このような共有フォルダへのアクセスを拒否対象にしています。

### マウントポイント

別のディスクやネットワーク上の場所を、PC上の普通のフォルダのように見せる仕組みです。

例:

```text
/mnt/c
/Volumes/Share
/media/usb
```

このポリシーでは、macOS / Linux / WSL の代表的なマウントポイントを拒否します。

### allowlist / denylist

- allowlist: 許可リスト。ここに書いたものだけ許可する。
- denylist: 拒否リスト。ここに書いたものを禁止する。

セキュリティでは、基本的に **allowlist のほうが安全** です。

### glob / ワイルドカード

複数のファイルやフォルダをまとめて指定する書き方です。

例:

| 書き方 | 意味 |
|---|---|
| `*.env` | `.env` で終わるファイル |
| `**/*.env` | サブフォルダも含めたすべての `.env` ファイル |
| `/mnt/**` | `/mnt` の下すべて |
| `~/OneDrive*` | ユーザーのホーム配下の `OneDrive` で始まるフォルダ |

---

## 3. 全体構造

対象ポリシーは、概ね次の10ブロックで構成されています。

| 番号 | セクション | 主な役割 |
|---:|---|---|
| 1 | 承認ポリシー | `never` を禁止し、ユーザー承認を必須化する |
| 2 | 旧クライアント互換 | 古い sandbox mode で full access を禁止する |
| 3 | Web 検索 | live Web 検索を禁止し cached のみにする |
| 4 | 既定 permission profile | `company_workspace_only` を既定にする |
| 5 | Hooks / MCP / Plugin / App | 外部連携・拡張機能・画面操作系を制限する |
| 6 | shell / subprocess ネットワーク | コマンド実行からのネットワーク通信を抑える |
| 7 | permission profile 本体 | Workspace 内だけ書き込み可にし、共有・マウントを拒否する |
| 8 | 管理者強制 deny-read | Workspace 誤登録時も読み取りを二重に拒否する |
| 9 | Windows sandbox | `elevated` sandbox のみ許可する |
| 10 | Command rules | 権限昇格、mount、共有操作、危険操作を禁止または承認必須にする |

---

## 4. 重要な前提と注意点

### 4.1 Cloud managed requirements は便利だが、完全な fail-closed ではない

Cloud managed requirements は、ChatGPT Business / Enterprise の管理画面から Codex に配布できる管理ポリシーです。

ただし、Codex が起動したときに有効なキャッシュがなく、かつクラウドからの取得に失敗した場合、managed requirements layer なしで続行する可能性があります。

そのため、厳格な会社PC運用では次の併用を検討してください。

```text
Cloud managed requirements
+
端末側の system requirements.toml
```

Windows の system requirements の例:

```text
%ProgramData%\OpenAI\Codex\requirements.toml
```

macOS / Linux の system requirements の例:

```text
/etc/codex/requirements.toml
```

ポイントは、`config.toml` ではなく **requirements.toml として配布する** ことです。

### 4.2 requirements.toml だけで「共有フォルダを Workspace として選ばせない」ことは難しい

このポリシーは、共有フォルダやマウントポイントへの読み書きを拒否する設計です。

ただし、ファイル選択画面や Workspace 登録 UI そのものを完全に制御するものではありません。

そのため、会社として本当に「共有フォルダを Workspace に登録させない」ことを保証したい場合は、次も併用してください。

- Windows の endpoint policy
- MDM / Intune / GPO
- ネットワークドライブの利用制御
- リムーバブルメディア制御
- 共有フォルダ上での開発禁止ルール

### 4.3 Windows の `elevated` sandbox は「管理者権限で実行」ではない

名前が紛らわしいですが、Codex の Windows sandbox における `elevated` は、Codex の作業コマンドを管理者権限で自由に実行するという意味ではありません。

`elevated` は、より強い sandbox を構成するために、管理者承認済みのセットアップを使える方式です。

今回のポリシーでは、弱い fallback である `unelevated` を使わせず、`elevated` のみを許可しています。

---

## 5. 各設定項目の解説

## 5.1 承認ポリシー

```toml
allowed_approval_policies = ["untrusted"]
allowed_approvals_reviewers = ["user"]
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `allowed_approval_policies` | `["untrusted"]` | Codex が信頼されていない操作をするとき、承認ゲートを通す |
| `allowed_approvals_reviewers` | `["user"]` | 承認する人をユーザー本人に限定する |

### 何を守るか

`never`、つまり「承認なしで進めるモード」を禁止します。

これにより、Codex が危険なコマンドやファイル変更を勝手に実行するリスクを下げます。

### 注意点

`untrusted` は「すべての操作を毎回必ず手動承認する」という意味ではありません。安全と判断される操作は自動で進む場合があります。

ただし、危険なコマンドについては、後述の `rules.prefix_rules` でも `prompt` や `forbidden` を指定しています。

---

## 5.2 旧クライアント互換: sandbox mode

```toml
allowed_sandbox_modes = ["read-only", "workspace-write"]
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `allowed_sandbox_modes` | `["read-only", "workspace-write"]` | 古い Codex クライアントでは、読み取り専用か Workspace 書き込みのみを許可する |

### 何を守るか

古いクライアントが permission profile を理解できない場合でも、`danger-full-access` を使わせないようにします。

`danger-full-access` は、Codex がPC上の広い範囲へアクセスできる危険なモードです。

### 注意点

Codex 0.138.0 以降では、`allowed_permission_profiles` と `default_permissions` を使う方式が推奨です。この設定は、あくまで古いクライアント向けの保険です。

---

## 5.3 Web 検索

```toml
allowed_web_search_modes = ["cached"]
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `allowed_web_search_modes` | `["cached"]` | live Web 検索を禁止し、OpenAI 側のキャッシュ検索だけ許可する |

### 何を守るか

Codex がその場で外部 Web にアクセスする範囲を抑えます。

### 注意点

`disabled` は常に許可されます。そのため実際には、次のどちらかになります。

```text
cached または disabled
```

つまり「cached のみ」と書いても、ユーザーが Web 検索を無効にすることは可能です。

---

## 5.4 既定 permission profile

```toml
default_permissions = "company_workspace_only"
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `default_permissions` | `company_workspace_only` | Codex の標準権限を、会社が定義した安全な profile に固定する |

### 何を守るか

ユーザーが意図せず広い権限で Codex を起動することを防ぎます。

### TOML 上の重要ポイント

この設定はトップレベル、つまり最初の `[features]` などのテーブルより前に置く必要があります。

TOML では、いったん `[features]` のようなテーブルを書いた後にキーを書くと、そのテーブル配下の設定として扱われるためです。

---

## 5.5 Hooks / Remote Control / Appshots

```toml
allow_managed_hooks_only = true
allow_remote_control = false
allow_appshots = false
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `allow_managed_hooks_only` | `true` | 管理者が配布した hooks だけ使わせる |
| `allow_remote_control` | `false` | デバイスのリモートコントロール機能を無効にする |
| `allow_appshots` | `false` | 画面やアプリ状態の取得面を減らす |

### 何を守るか

ユーザーやプロジェクトが勝手に hooks を追加して、社外連携・情報送信・危険操作を差し込むことを防ぎます。

Appshots や remote control は便利ですが、コードや画面情報に触れる面が増えるため、このポリシーでは無効化しています。

### 注意点

`allow_remote_control = false` は device remote control を止める設定です。SSH remote connections を無効化するものではない点に注意してください。

---

## 5.6 `[features]` セクション

```toml
[features]
hooks = true
apps = false
browser_use = false
browser_use_external = false
browser_use_full_cdp_access = false
in_app_browser = false
computer_use = false
multi_agent = false
plugins = false
plugin_sharing = false
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `hooks` | `true` | 管理者管理 hooks を使えるようにする |
| `apps` | `false` | Apps 連携を無効化する |
| `browser_use` | `false` | Browser Use / Browser Agent を無効化する |
| `browser_use_external` | `false` | 外部ブラウザ連携を無効化する |
| `browser_use_full_cdp_access` | `false` | Chrome DevTools Protocol の広い操作権限を無効化する |
| `in_app_browser` | `false` | アプリ内ブラウザを無効化する |
| `computer_use` | `false` | Computer Use / Record & Replay 関連を無効化する |
| `multi_agent` | `false` | 複数エージェントによる追加実行面を無効化する |
| `plugins` | `false` | ユーザー導入プラグインを無効化する |
| `plugin_sharing` | `false` | ローカルプラグインの共有を無効化する |

### 何を守るか

Codex が触れる「外部操作面」を減らします。

初心者向けに言うと、Codex の作業範囲を「コード編集と承認されたコマンド実行」に近づけ、ブラウザ操作、画面操作、プラグイン、複数 agent などの追加機能を閉じています。

---

## 5.7 `[computer_use]` セクション

```toml
[computer_use]
allow_locked_computer_use = false
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `allow_locked_computer_use` | `false` | 管理された macOS 端末がロックされた後の Computer Use 操作を禁止する |

### 何を守るか

万一 Computer Use が有効なクライアントでも、端末ロック後に操作が続くリスクを下げます。

### 注意点

今回の `[features]` では `computer_use = false` にしているため、この設定は二重の保険に近い位置づけです。

---

## 5.8 `[mcp_servers]` セクション

```toml
[mcp_servers]
```

このセクションは空です。

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `[mcp_servers]` | 空 | 管理者が明示していない MCP server をすべて無効化する |

### 何を守るか

ユーザーが勝手に MCP server を追加して、外部サービスや社内データへ接続することを防ぎます。

### 社内 MCP を許可する場合

許可する MCP server がある場合だけ、管理者が identity を追加します。

例:

```toml
[mcp_servers.internal_docs.identity]
url = { match = "exact", value = "https://mcp.example.co.jp/codex" }
```

この例では、`internal_docs` という名前の MCP server が、指定された URL と完全一致する場合だけ許可されます。

---

## 5.9 `[marketplaces]` セクション

```toml
[marketplaces]
restrict_to_allowed_sources = true
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `restrict_to_allowed_sources` | `true` | ユーザーが任意の marketplace source から plugin を入れられないようにする |

### 何を守るか

ユーザーが勝手にプラグイン配布元を追加し、不明な plugin をインストールすることを防ぎます。

### 注意点

このポリシーでは `[features] plugins = false` も指定しているため、plugin 機能自体も止めています。

---

## 5.10 `[experimental_network]` セクション

```toml
[experimental_network]
enabled = true
managed_allowed_domains_only = true
allowed_domains = []
allow_local_binding = false
allow_upstream_proxy = false
dangerously_allow_all_unix_sockets = false
dangerously_allow_non_loopback_proxy = false
denied_domains = [
  "localhost",
  "127.0.0.1",
  "::1",
  "169.254.169.254",
  "*.local",
  "*.lan",
]
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `enabled` | `true` | sandboxed networking の管理要件を有効化する |
| `managed_allowed_domains_only` | `true` | 管理者が許可したドメインだけ有効にする |
| `allowed_domains` | `[]` | 許可ドメインを空にする。つまり追加で許可しない |
| `allow_local_binding` | `false` | ローカル・プライベートネットワークへの広い接続を許可しない |
| `allow_upstream_proxy` | `false` | 環境変数などの上流プロキシを使った抜け道を許可しない |
| `dangerously_allow_all_unix_sockets` | `false` | 任意の Unix socket への接続を許可しない |
| `dangerously_allow_non_loopback_proxy` | `false` | localhost 以外で proxy/listener を開く抜け道を許可しない |
| `denied_domains` | localhost 等 | ローカル・メタデータ・社内名解決系を明示的に拒否する |

### 何を守るか

Codex が shell や subprocess から外部ネットワークへ通信する経路を閉じます。

特に、次のような情報漏えい経路を抑えます。

- `localhost` へのアクセス
- 社内 `.local` / `.lan` へのアクセス
- クラウドメタデータ `169.254.169.254` へのアクセス
- 上流 proxy を使った外部通信
- Unix socket を使ったホスト権限回避

### Web 検索との違い

`allowed_web_search_modes = ["cached"]` は、Codex の Web 検索機能の制御です。

`[experimental_network]` は、Codex が実行するコマンド、たとえば `curl`、`npm`、`pip`、`python` などのネットワーク通信に関係する制御です。

別物として考えてください。

### 重要な注意点

`[experimental_network]` は名前の通り experimental です。Windows 環境で使う場合は、会社で利用する Codex バージョンとOSで必ず検証してください。

また、このセクションは「command network access を付与する設定」ではありません。active sandbox 側でネットワークが閉じている場合、この設定だけでネットワークが開くわけではありません。

---

## 5.11 `[allowed_permission_profiles]` セクション

```toml
[allowed_permission_profiles]
company_workspace_only = true
":read-only" = false
":workspace" = false
":danger-full-access" = false
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `company_workspace_only` | `true` | 会社が定義した profile だけ許可する |
| `:read-only` | `false` | 組み込み read-only profile を選ばせない |
| `:workspace` | `false` | 組み込み workspace profile を選ばせない |
| `:danger-full-access` | `false` | 制限なし profile を選ばせない |

### 何を守るか

ユーザーが広すぎる権限 profile を選ぶことを防ぎます。

特に重要なのは `:danger-full-access = false` です。これにより、Codex が sandbox 制限なしで動く経路を防ぎます。

### なぜ `:workspace` も false にするのか

組み込み `:workspace` は便利ですが、会社独自の「共有フォルダ拒否」「秘密情報拒否」「D:〜Z: 拒否」などの細かい制御が入っていません。

そのため、会社専用の `company_workspace_only` だけを許可しています。

---

## 5.12 `[permissions.company_workspace_only]` セクション

```toml
[permissions.company_workspace_only]
description = "Company policy: edit only active Workspace roots; deny shared or mounted folders."
extends = ":workspace"
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `description` | 説明文 | この profile の目的を書いた説明 |
| `extends` | `:workspace` | 既存の workspace profile を土台にして、追加制限を足す |

### 何を守るか

`company_workspace_only` は、既存の `:workspace` の安全機能をベースにしつつ、会社ルールを上乗せする profile です。

`extends = ":workspace"` により、Workspace 内だけ書き込み可能という基本動作を引き継ぎます。

---

## 5.13 `[permissions.company_workspace_only.filesystem]` セクション

このセクションは、Workspace の外側や危険な場所へのファイルアクセスを制御する中心部分です。

### 5.13.1 glob 展開深度

```toml
glob_scan_max_depth = 5
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `glob_scan_max_depth` | `5` | `**` のような glob をどの深さまで事前確認するかを決める |

### 注意点

値を深くしすぎると、起動前スキャンが重くなる可能性があります。

通常は 3〜5 程度で検証します。

---

### 5.13.2 ファイルシステム全体の基本方針

```toml
":root" = "deny"
":minimal" = "read"
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `:root` | `deny` | 原則としてPC全体へのアクセスを拒否する |
| `:minimal` | `read` | 実行に最低限必要な runtime/tool パスだけ読むことを許可する |

### 何を守るか

「まず全部拒否し、必要なものだけ読む」という安全側の考え方です。

### 注意点

`:minimal = "read"` があるため、完全に Workspace 以外を一切読まないわけではありません。ツール実行に必要な最小限の読み取りは許可されます。

---

### 5.13.3 一時ディレクトリの拒否

```toml
":tmpdir" = "deny"
":slash_tmp" = "deny"
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `:tmpdir` | `deny` | OS の一時ディレクトリを拒否する |
| `:slash_tmp` | `deny` | Unix 系の `/tmp` を拒否する |

### 何を守るか

Codex が Workspace 外の一時フォルダに成果物や中間ファイルを退避することを防ぎます。

### 注意点

一部のビルドツールやテストツールは一時ディレクトリを使います。そのため、社内標準プロジェクトで動作確認が必要です。

---

### 5.13.4 macOS の外部ディスク・ネットワーク・クラウド同期フォルダ拒否

対象例:

```toml
"/Volumes" = "deny"
"/Volumes/**" = "deny"
"/Network" = "deny"
"/Network/**" = "deny"
"~/Library/CloudStorage" = "deny"
"~/Library/CloudStorage/**" = "deny"
"~/OneDrive*" = "deny"
"~/Dropbox*" = "deny"
"~/Google Drive*" = "deny"
"~/Box*" = "deny"
"~/SharePoint*" = "deny"
```

| パス | 初心者向けの意味 |
|---|---|
| `/Volumes` | macOS の外部ディスクやネットワークボリュームが現れやすい場所 |
| `/Network` | macOS のネットワーク領域 |
| `~/Library/CloudStorage` | iCloud Drive、OneDrive、Dropbox などのクラウド同期領域 |
| `~/OneDrive*` など | ホームフォルダ直下のクラウド同期フォルダ |

### 何を守るか

Codex が外部ディスク、ネットワークボリューム、クラウド同期フォルダを読み書きすることを防ぎます。

---

### 5.13.5 Linux / WSL のマウントポイント拒否

対象例:

```toml
"/mnt" = "deny"
"/mnt/**" = "deny"
"/media" = "deny"
"/media/**" = "deny"
"/run/media" = "deny"
"/run/media/**" = "deny"
"/net" = "deny"
"/net/**" = "deny"
```

| パス | 初心者向けの意味 |
|---|---|
| `/mnt` | WSL の Windows ドライブや手動マウント先として使われやすい |
| `/media` | USB メモリや外部メディアが現れやすい |
| `/run/media` | 一部 Linux デスクトップで外部メディアが現れる |
| `/net` | ネットワークファイルシステムの入口として使われる場合がある |

### 何を守るか

WSL から `/mnt/c` や `/mnt/z` 経由で Windows 側のドライブへアクセスする経路を閉じます。

---

### 5.13.6 Windows native の共有フォルダ拒否

対象例:

```toml
'\\*' = "deny"
'\\**' = "deny"
'\\*\**' = "deny"
'//*' = "deny"
'//**' = "deny"
'//*/**' = "deny"
'C:\Users\Public' = "deny"
'C:\Users\Public\**' = "deny"
'C:/Users/Public' = "deny"
'C:/Users/Public/**' = "deny"
```

| パターン | 初心者向けの意味 |
|---|---|
| `\\server\share` 系 | Windows の UNC 共有フォルダ |
| `//server/share` 系 | UNC をスラッシュで表した形式 |
| `C:\Users\Public` | Windows の共有用途に使われやすい Public フォルダ |

### 何を守るか

Windows の共有フォルダ、ローカル共有フォルダに Codex がアクセスすることを防ぎます。

### 注意点

Windows native では、filesystem deny が direct file tools には効いても、shell subprocess の読み取りには直接効かない場合があります。

そのため、このポリシーでは後述の `rules.prefix_rules` で `net use`、`New-SmbMapping`、`mountvol` なども禁止しています。

---

### 5.13.7 Windows の D:〜Z: ドライブ拒否

対象例:

```toml
'D:\' = "deny"
'D:\**' = "deny"
'D:/' = "deny"
'D:/**' = "deny"
...
'Z:\' = "deny"
'Z:\**' = "deny"
'Z:/' = "deny"
'Z:/**' = "deny"
```

| 対象 | 初心者向けの意味 |
|---|---|
| `D:`〜`Z:` | C: 以外の Windows ドライブを原則拒否する |

### 何を守るか

Windows のマップされたネットワークドライブやリムーバブルドライブに Codex がアクセスすることを防ぎます。

例:

```text
Z:\project
```

がネットワーク共有に割り当てられている場合、Codex がそこへアクセスできないようにします。

### 注意点

`requirements.toml` だけでは、`D:` がローカル固定ディスクなのか、ネットワークドライブなのか、USB なのかを静的に判別できません。

そのため、このポリシーでは安全側に倒して **C: 以外を原則拒否** しています。

会社標準で `D:` をローカル開発ドライブとして使っている場合は、次のどちらかが必要です。

1. `D:` の deny を削除する
2. 端末管理側で `D:` が network/removable drive ではないことを保証する

---

### 5.13.8 ユーザー秘密情報の拒否

```toml
"~/.ssh" = "deny"
"~/.gnupg" = "deny"
"~/.aws" = "deny"
"~/.azure" = "deny"
"~/.gcloud" = "deny"
"~/.kube" = "deny"
"~/.docker" = "deny"
```

| パス | 含まれやすいもの |
|---|---|
| `~/.ssh` | SSH 秘密鍵、known_hosts |
| `~/.gnupg` | GPG 鍵 |
| `~/.aws` | AWS 認証情報 |
| `~/.azure` | Azure 認証情報 |
| `~/.gcloud` | Google Cloud 認証情報 |
| `~/.kube` | Kubernetes 接続情報 |
| `~/.docker` | Docker 認証情報 |

### 何を守るか

Codex がクラウド認証情報、秘密鍵、クラスタ認証情報などを読めないようにします。

---

## 5.14 `[permissions.company_workspace_only.filesystem.":workspace_roots"]` セクション

```toml
[permissions.company_workspace_only.filesystem.":workspace_roots"]
"." = "write"
".git" = "read"
".codex" = "read"
".agents" = "read"
".devcontainer" = "read"
"**/*.env" = "deny"
"**/.env" = "deny"
"**/.env.*" = "deny"
"**/*.pem" = "deny"
"**/*.key" = "deny"
"**/*secret*" = "deny"
"**/*credential*" = "deny"
"**/*token*" = "deny"
"**/id_rsa" = "deny"
"**/id_ed25519" = "deny"
```

このセクションは、Workspace の中で何を許可するかを決めます。

### 5.14.1 Workspace root の書き込み許可

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `.` | `write` | Active Workspace root の中だけ書き込みを許可する |

### 何を守るか

Codex はプロジェクトの中ではコード修正ができますが、Workspace 外には原則書き込めません。

---

### 5.14.2 重要設定ディレクトリを読み取り専用にする

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `.git` | `read` | Git の管理情報を直接書き換えにくくする |
| `.codex` | `read` | Codex 設定を勝手に変更しにくくする |
| `.agents` | `read` | agent 関連設定を勝手に変更しにくくする |
| `.devcontainer` | `read` | devcontainer 設定を勝手に変更しにくくする |

### 何を守るか

プロジェクトの動作や開発環境を大きく変える設定ファイルを、Codex が勝手に書き換えるリスクを下げます。

---

### 5.14.3 Workspace 内の秘密情報を拒否する

| パターン | 拒否したいもの |
|---|---|
| `**/*.env` | 環境変数ファイル |
| `**/.env` | `.env` ファイル |
| `**/.env.*` | `.env.local` など |
| `**/*.pem` | 証明書・秘密鍵ファイル |
| `**/*.key` | 鍵ファイル |
| `**/*secret*` | `secret` を含むファイル |
| `**/*credential*` | `credential` を含むファイル |
| `**/*token*` | `token` を含むファイル |
| `**/id_rsa` | SSH 秘密鍵 |
| `**/id_ed25519` | SSH 秘密鍵 |

### 何を守るか

Workspace の中に秘密情報が誤って置かれていても、Codex が読めないようにします。

### 注意点

一部のプロジェクトでは `.env.example` や `.env.test` を Codex に読ませたい場合があります。今回のポリシーでは安全を優先して拒否しています。

---

## 5.15 `[permissions.company_workspace_only.network]` セクション

```toml
[permissions.company_workspace_only.network]
enabled = false
allow_local_binding = false
allow_upstream_proxy = false
dangerously_allow_non_loopback_proxy = false
dangerously_allow_all_unix_sockets = false
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `enabled` | `false` | この permission profile では command network を使わせない |
| `allow_local_binding` | `false` | ローカル・プライベートネットワーク接続を広く許可しない |
| `allow_upstream_proxy` | `false` | proxy 経由の抜け道を許可しない |
| `dangerously_allow_non_loopback_proxy` | `false` | localhost 以外への proxy/listener を許可しない |
| `dangerously_allow_all_unix_sockets` | `false` | 任意の Unix socket 接続を許可しない |

### 何を守るか

Codex がコマンド経由で外部通信することを防ぎます。

例:

```text
curl https://example.com
npm install
pip install
```

のような通信は、原則として許可されない方向になります。

---

## 5.16 `[permissions.company_workspace_only.network.unix_sockets]` セクション

```toml
[permissions.company_workspace_only.network.unix_sockets]
"/var/run/docker.sock" = "deny"
"/run/docker.sock" = "deny"
"/run/podman/podman.sock" = "deny"
```

| パス | 初心者向けの意味 |
|---|---|
| `/var/run/docker.sock` | Docker を操作できる socket |
| `/run/docker.sock` | Docker を操作できる socket |
| `/run/podman/podman.sock` | Podman を操作できる socket |

### 何を守るか

Docker / Podman socket にアクセスできると、コンテナ経由でホストやファイルシステムに強い影響を与えられる場合があります。

この設定は、そのような権限逃げを防ぐためのものです。

---

## 5.17 `[permissions.filesystem]` セクション

```toml
[permissions.filesystem]
deny_read = [ ... ]
```

このセクションは、管理者が強制する読み取り拒否リストです。

### 何を守るか

`company_workspace_only` profile の中でも拒否していますが、ここでも二重に拒否しています。

狙いは、Workspace として共有フォルダやマウントポイントが誤登録された場合でも、読み取りを拒否しやすくすることです。

### 主な拒否対象

| 分類 | 対象 |
|---|---|
| macOS | `/Volumes`, `/Network`, `~/Library/CloudStorage`, `~/OneDrive*`, `~/Dropbox*`, `~/Google Drive*`, `~/Box*`, `~/SharePoint*` |
| Linux / WSL | `/mnt`, `/media`, `/run/media`, `/net` |
| Windows | UNC 共有、`C:\Users\Public`, `D:`〜`Z:` |
| 秘密情報 | `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.azure`, `~/.gcloud`, `~/.kube`, `~/.docker` |

### `deny_read` と `deny` の違い

- `deny`: 対象への読み書きなどを拒否する profile 内のルール
- `deny_read`: 管理者強制の読み取り拒否リスト

このポリシーでは、重要な場所を両方で拒否して、制御を二重化しています。

---

## 5.18 `[windows]` セクション

```toml
[windows]
allowed_sandbox_implementations = ["elevated"]
```

| 設定 | 値 | 初心者向けの意味 |
|---|---|---|
| `allowed_sandbox_implementations` | `["elevated"]` | Windows native では強い elevated sandbox だけ使わせる |

### 何を守るか

Codex が弱い `unelevated` sandbox に fallback することを防ぎます。

### `elevated` と `unelevated` の違い

| 項目 | elevated | unelevated |
|---|---|---|
| 位置づけ | 推奨の強い sandbox | fallback の弱い sandbox |
| 使う仕組み | 専用の低権限 sandbox ユーザー、ファイルシステム境界、firewall rule、ローカルポリシー変更など | 現在ユーザー由来の制限付き token、ACL 境界、環境レベルの offline 制御など |
| 企業PCでの推奨 | 原則こちら | elevated が使えない場合の一時 fallback |

### 注意点

`elevated` は、Codex のコマンドを管理者権限で実行させる意味ではありません。より強い sandbox を準備するための方式です。

---

## 5.19 `[rules]` セクション: command rules 全体

```toml
[rules]
prefix_rules = [ ... ]
```

command rules は、Codex が実行しようとするコマンドの先頭部分を見て、禁止または承認必須にする仕組みです。

| decision | 意味 |
|---|---|
| `forbidden` | 実行禁止 |
| `prompt` | 実行前にユーザー承認を求める |

requirements rules では、原則として `allow` ではなく、`prompt` または `forbidden` のような制限方向の指定を使います。

---

## 5.20 権限昇格コマンド禁止

対象例:

```toml
sudo, su, doas, pkexec, runas, runas.exe, Start-Process
```

| decision | 意味 |
|---|---|
| `forbidden` | 実行禁止 |

### 何を守るか

Codex が OS 権限を上げて、sandbox やファイル制限を回避することを防ぎます。

### Windows で特に重要なもの

| コマンド | 危険性 |
|---|---|
| `runas` | 別ユーザー・管理者権限で実行される可能性 |
| `Start-Process` | PowerShell 経由で昇格実行に使われる可能性 |

---

## 5.21 mount / mapping 操作禁止

対象例:

```toml
mount, umount, sshfs, fusermount, diskutil,
mountvol, diskpart, subst,
New-PSDrive, New-SmbMapping, Remove-SmbMapping
```

| decision | 意味 |
|---|---|
| `forbidden` | 実行禁止 |

### 何を守るか

後から共有フォルダや外部ディスクをマウントし、Codex の作業範囲を広げることを防ぎます。

### Windows で特に重要なもの

| コマンド | 危険性 |
|---|---|
| `New-PSDrive` | PowerShell で新しいドライブ割り当てを作れる |
| `New-SmbMapping` | SMB 共有を割り当てられる |
| `mountvol` | ボリューム操作に関係する |
| `diskpart` | ディスク構成を変更できる |
| `subst` | フォルダをドライブ文字に見せられる |

---

## 5.22 Windows `net` コマンド制限

対象例:

```toml
net use
net share
net user
net localgroup
net group
net session
net file
net start
net stop
```

| decision | 意味 |
|---|---|
| `forbidden` | 実行禁止 |

### 何を守るか

Windows の共有、ユーザー、グループ、サービス操作を Codex から実行させないようにします。

特に `net use` はネットワーク共有の接続に使われるため重要です。

---

## 5.23 WSL 起動禁止

対象例:

```toml
wsl, wsl.exe
```

| decision | 意味 |
|---|---|
| `forbidden` | 実行禁止 |

### 何を守るか

Windows native の Codex から WSL を起動し、`/mnt/c` や `/mnt/z` 経由で Windows ドライブへアクセスする抜け道を防ぎます。

### 注意点

会社として WSL2 上で Codex を正式運用する場合は、別途 WSL2 用のポリシーと端末設計が必要です。

---

## 5.24 コンテナ・クラスタ・IaC ツール禁止

対象例:

```toml
docker, podman, kubectl, helm, terraform, tofu
```

| decision | 意味 |
|---|---|
| `forbidden` | 実行禁止 |

### 何を守るか

Codex がホスト、コンテナ、Kubernetes クラスタ、クラウド環境に影響する操作を実行することを防ぎます。

| コマンド | 危険性 |
|---|---|
| `docker` / `podman` | コンテナ経由でホストファイルや socket に影響する可能性 |
| `kubectl` / `helm` | Kubernetes クラスタに影響する可能性 |
| `terraform` / `tofu` | クラウドやインフラを変更する可能性 |

---

## 5.25 シェル・実行系・パッケージ管理系は承認必須

対象例:

```toml
bash, sh, zsh, fish,
python, python3, py, node, npm, npx, pnpm, yarn, bun,
pip, pip3, uv, make, cmake, cargo, go, mvn, gradle,
cmd, powershell, pwsh, dotnet, msbuild,
winget, choco, scoop, msiexec
```

| decision | 意味 |
|---|---|
| `prompt` | 実行前にユーザー承認が必要 |

### 何を守るか

任意コード実行、ビルド、パッケージインストールなどを、承認なしで進められないようにします。

### なぜ禁止ではなく prompt なのか

開発作業では、テスト実行やビルドに `python`、`npm`、`dotnet` などが必要になることがあります。

完全禁止にすると開発支援として使いにくくなるため、このポリシーでは **承認必須** にしています。

---

## 5.26 Windows 管理系コマンド禁止

対象例:

```toml
reg, sc, schtasks, takeown, icacls, bcdedit
```

| decision | 意味 |
|---|---|
| `forbidden` | 実行禁止 |

### 何を守るか

Windows のレジストリ、サービス、タスクスケジューラ、ACL、ブート設定などを Codex に変更させないようにします。

| コマンド | 危険性 |
|---|---|
| `reg` | レジストリ変更 |
| `sc` | サービス操作 |
| `schtasks` | タスクスケジューラ操作 |
| `takeown` | ファイル所有者変更 |
| `icacls` | ACL / 権限変更 |
| `bcdedit` | ブート設定変更 |

---

## 5.27 Git の危険操作は承認必須

対象例:

```toml
git commit
git push
git tag
git merge
git rebase
git reset
git clean
```

| decision | 意味 |
|---|---|
| `prompt` | 実行前にユーザー承認が必要 |

### 何を守るか

履歴変更、リモート反映、削除など、Git リポジトリに大きく影響する操作を承認なしで実行させないようにします。

| コマンド | リスク |
|---|---|
| `git push` | リモートリポジトリへ変更が反映される |
| `git reset` | 作業内容や履歴が戻る可能性 |
| `git clean` | 未追跡ファイルが削除される可能性 |
| `git rebase` | 履歴が書き換わる可能性 |

---

## 5.28 破壊的ファイル操作は承認必須

対象例:

```toml
rm, rmdir, mv, cp, chmod, chown, ln,
del, erase, copy, move, ren, rename,
Remove-Item, Move-Item, Copy-Item, Rename-Item,
New-Item, Set-Content, Add-Content, Out-File
```

| decision | 意味 |
|---|---|
| `prompt` | 実行前にユーザー承認が必要 |

### 何を守るか

削除、移動、コピー、権限変更、ファイル作成、ファイル上書きなどを承認なしで実行させないようにします。

### 注意点

Workspace 内の普通の編集も一部承認が必要になる可能性があります。

これは利便性より安全性を優先する設定です。

---

## 6. 要件との対応表

| 要件 | 対応する主な設定 | 判定 |
|---|---|---|
| Windows 共有フォルダへの書き込み禁止 | UNC deny、`C:\Users\Public` deny、D:〜Z: deny、`rules` の共有系禁止 | 概ね対応。実機検証必須 |
| Windows 共有フォルダを Workspace に登録させない | UNC deny、`deny_read`、endpoint policy 併用推奨 | TOML 単独では完全保証しにくい |
| 承認なし Never 実行禁止 | `allowed_approval_policies = ["untrusted"]` | 対応 |
| 必ず承認ゲートを通す | `allowed_approvals_reviewers = ["user"]`、`rules.prefix_rules` | 危険操作は対応。全操作手動承認ではない |
| Web 検索は cached のみ | `allowed_web_search_modes = ["cached"]` | 対応。`disabled` は常に可能 |
| Hooks は管理者管理 | `allow_managed_hooks_only = true`、`features.hooks = true` | 対応 |
| MCP は管理者管理 | 空の `[mcp_servers]` allowlist | 対応 |
| Workspace 内だけ編集 | `default_permissions`、`company_workspace_only`、`.` = `write` | 対応 |
| Workspace 外アクセス禁止 | `:root = deny`、各種 deny、`deny_read` | 概ね対応。`:minimal = read` は例外 |
| 権限昇格禁止 | `sudo`、`runas`、`Start-Process` など forbidden | 対応。ネスト実行は検証推奨 |
| 旧クライアント互換 | `allowed_sandbox_modes` | 対応 |
| mac / Linux / WSL mount point 遮断 | `/Volumes`、`/Network`、`/mnt`、`/media` など deny | 対応 |
| requirements.toml のみで制御 | Cloud managed requirements / system requirements として配布 | 対応。ただし fail-closed には system requirements 併用推奨 |

---

## 7. 本番適用前のテスト項目

Windows 管理端末で、最低限次を確認してください。

| テスト | 期待結果 |
|---|---|
| `\\server\share\repo` を Workspace に指定 | 読み書きできない |
| `Z:\repo` を Workspace に指定 | 読み書きできない |
| `D:\repo` がローカル開発ドライブの場合 | ブロックされるため、会社ルールに合うか確認 |
| `wsl.exe` を実行 | forbidden になる |
| `net use` を実行 | forbidden になる |
| `New-SmbMapping` を実行 | forbidden になる |
| `mountvol` / `diskpart` を実行 | forbidden になる |
| `powershell` を実行 | prompt になる |
| `cmd` を実行 | prompt になる |
| `git push` を実行 | prompt になる |
| `rm` / `Remove-Item` を実行 | prompt になる |
| `.env` を読ませる | deny になる |
| `~/.ssh` を読ませる | deny になる |
| `curl` や `npm install` を実行 | ネットワーク通信が許可されない、または承認・制限される |
| Windows sandbox mode | `elevated` のみ許可され、`unelevated` fallback できない |

---

## 8. 運用上の推奨

### 8.1 Cloud managed requirements と system requirements を併用する

厳格な会社PC運用では、Cloud managed requirements だけでなく、端末側にも同じ `requirements.toml` を配布することを推奨します。

理由は、Cloud managed requirements は取得失敗時に managed layer なしで継続する場合があるためです。

### 8.2 Windows 共有フォルダ禁止は endpoint policy でも制御する

`requirements.toml` は Codex のアクセス制御には有効ですが、Windows のファイル選択 UI や共有ドライブ登録そのものを完全に止めるものではありません。

そのため、次も併用してください。

- Intune
- Group Policy
- Defender for Endpoint
- リムーバブルメディア制御
- ネットワークドライブ制御
- 開発フォルダの社内標準化

### 8.3 D: ドライブを使う会社では特に確認する

このポリシーは C: 以外のドライブを安全側で拒否しています。

会社標準で `D:\dev` のようなローカル開発領域を使っている場合、そのままだと開発作業に支障が出ます。

その場合は、D: の扱いを会社ルールとして決めてください。

### 8.4 prefix_rules だけに頼りすぎない

`rules.prefix_rules` はコマンドの先頭トークンを見る制御です。

次のような入れ子実行は、環境や実装によって追加検証が必要です。

```text
cmd /c net use ...
powershell -Command New-SmbMapping ...
python -c "...危険操作..."
```

厳格にする場合は、managed hooks で full command line を検査する設計を検討してください。

---

## 9. このポリシーで特に重要な安全設計

### 9.1 deny by default

まず広い範囲を拒否し、必要な Workspace だけ書き込み可能にしています。

```toml
":root" = "deny"
"." = "write"
```

これは「基本は触らせない。必要な場所だけ許可する」という考え方です。

### 9.2 二重の拒否

共有フォルダや秘密情報は、profile 内の `deny` と、管理者強制の `deny_read` の両方で拒否しています。

これにより、設定漏れや Workspace 誤登録時のリスクを下げています。

### 9.3 強い Windows sandbox の強制

```toml
allowed_sandbox_implementations = ["elevated"]
```

これにより、Windows native では強い sandbox だけを使わせます。

### 9.4 外部連携面の最小化

Browser Use、Computer Use、Apps、Plugins、MCP、Marketplace などを閉じることで、外部接続・画面操作・プラグイン経由のリスクを減らしています。

---

## 10. 参考資料

公式ドキュメントは更新される可能性があるため、本番適用前に最新の内容を確認してください。

- OpenAI Codex Managed configuration  
  https://developers.openai.com/codex/enterprise/managed-configuration
- OpenAI Codex Configuration Reference  
  https://developers.openai.com/codex/config-reference
- OpenAI Codex Permissions  
  https://developers.openai.com/codex/permissions
- OpenAI Codex Windows  
  https://developers.openai.com/codex/windows
- OpenAI Codex Agent approvals & security  
  https://developers.openai.com/codex/agent-approvals-security
- OpenAI Codex MCP  
  https://developers.openai.com/codex/mcp

---

## 11. まとめ

この `requirements.toml` は、会社PCで Codex を使う際に、かなり安全側へ寄せたポリシーです。

特に重要なのは次の点です。

1. `never` 実行を禁止する
2. `company_workspace_only` profile に固定する
3. Workspace 外や共有フォルダ、マウントポイントを拒否する
4. Windows では `elevated` sandbox のみ許可する
5. Web 検索は cached のみにする
6. MCP / Hooks / Plugins を管理者管理に寄せる
7. 危険コマンドは forbidden または prompt にする

ただし、`requirements.toml` だけで会社PC全体の利用ルールを完全に保証できるわけではありません。

特に、共有フォルダの Workspace 登録禁止、ネットワークドライブ制御、リムーバブルメディア制御は、端末管理ポリシーと組み合わせて運用することを推奨します。
