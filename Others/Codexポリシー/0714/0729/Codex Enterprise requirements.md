# =============================================================================
# Codex Enterprise requirements.toml
# =============================================================================
#
# 目的:
# - 現在のユーザーの ~/codex_work だけをCodexの作業領域として許可する。
# - ~/codex_work 以外は、原則として読み取り・書き込みを禁止する。
# - Never実行、自動承認、ライブWeb検索、未管理Hooks、未管理MCPを禁止する。
# - Windowsでは elevated サンドボックス実装だけを許可する。
#
# 前提:
# - Permission Profileの管理者強制にはCodex 0.138.0以降が必要。
# - ~/codex_work は事前に作成し、ローカルディスク上の通常フォルダとする。
# - このファイルは、Codexの画面で別フォルダをWorkspaceとして選択する操作自体を
#   禁止できない。ただし、選択した別フォルダにはアクセス権を付与しない。
# - requirements.tomlだけでは、CodexアプリをWindowsの管理者として起動することを
#   禁止できない。権限昇格コマンドの禁止はベストエフォートである。
#
# クラウド管理画面:
# https://chatgpt.com/codex/cloud/settings/policies
#
# Windowsのローカル配置先:
# %ProgramData%\OpenAI\Codex\requirements.toml
# =============================================================================


# -----------------------------------------------------------------------------
# 承認ポリシー
# -----------------------------------------------------------------------------

# Neverを禁止し、untrustedだけを許可する。
# untrustedでは、既知の安全な読み取り操作以外は原則として承認を要求する。
# ただし、すべての操作を例外なく承認対象にする設定ではない。
allowed_approval_policies = ["untrusted"]

# 自動レビューによる承認を禁止し、人間のユーザーだけが承認できるようにする。
allowed_approvals_reviewers = ["user"]


# -----------------------------------------------------------------------------
# Web検索
# -----------------------------------------------------------------------------

# indexedとliveを禁止し、Web検索を使用する場合はcachedだけを許可する。
# 仕様上disabledは常に暗黙的に許可される。
allowed_web_search_modes = ["cached"]


# -----------------------------------------------------------------------------
# Hooks・その他の管理対象機能
# -----------------------------------------------------------------------------

# ユーザー、プロジェクト、セッション、プラグインのHooksを読み込まない。
# requirements.tomlなどの管理レイヤーで定義したHooksだけを許可する。
# このファイルには[hooks]を定義していないため、現状はHookを実行しない。
allow_managed_hooks_only = true

# 画面・アプリ状態を取得する別経路を減らすためAppshotsを無効化する。
allow_appshots = false

# デバイスのリモートコントロールを無効化する。
# SSHなど、Codex外のリモート接続を無効にする設定ではない。
allow_remote_control = false


# -----------------------------------------------------------------------------
# Permission Profile
# -----------------------------------------------------------------------------

# 管理者定義プロファイルを既定値として強制する。
default_permissions = "corp_codex_work"

# Codex 0.137.0以前に対するフェイルセーフ。
# 古いクライアントはPermission Profileの管理強制を無視するため、
# 旧サンドボックスではread-onlyだけを許可する。
allowed_sandbox_modes = ["read-only"]

[allowed_permission_profiles]

# このプロファイルだけを許可する。
# :read-only、:workspace、:danger-full-access、および将来追加される
# 未指定プロファイルは許可しない。
corp_codex_work = true


[permissions.corp_codex_work]

description = "現在のユーザーの~/codex_workだけを読み書き可能にする企業管理プロファイル"

# :workspaceを継承しない。
# :workspace_rootsも使用しないため、ユーザーが別フォルダをWorkspaceとして
# 選択しても、その選択先に権限は付与されない。

[permissions.corp_codex_work.filesystem]

# ファイルシステム全体を既定拒否する。
# Windowsのローカルドライブ、UNC共有、割り当て済みネットワークドライブ、
# macOS/Linux/WSLのマウント先も、個別に再許可しない限り拒否される。
":root" = "deny"

# Codexがシェル、Git、言語ランタイム等を起動するために必要な
# 最小限のシステム／ランタイムファイルだけ読み取り可能にする。
":minimal" = "read"

# ~ は現在ログインしているユーザーのホームディレクトリに展開される。
# Windows例: C:\Users\<ユーザー>\codex_work
# macOS例:   /Users/<ユーザー>/codex_work
# Linux例:   /home/<ユーザー>/codex_work
#
# このフォルダと配下だけ、読み取り・作成・変更・名前変更・削除を許可する。
"~/codex_work" = "write"

# Git管理情報をエージェント自身が直接書き換えないようにする。
"~/codex_work/.git" = "read"

# プロジェクト内のCodex設定をエージェント自身が書き換えないようにする。
"~/codex_work/.codex" = "read"

# OSの一時フォルダをWorkspace外の書き込み先として使用させない。
# 一部のビルドツールは一時フォルダを必要とするため、事前検証が必要。
":tmpdir" = "deny"
":slash_tmp" = "deny"


[permissions.corp_codex_work.network]

# Codexが起動したローカルコマンドからのネットワーク接続を禁止する。
# Web検索ツールのcachedモードとは別の制御である。
enabled = false


# -----------------------------------------------------------------------------
# macOS / Linux / WSLの代表的マウントポイントを明示的にdeny-read
# -----------------------------------------------------------------------------

[permissions.filesystem]

# :root = "deny"でも拒否されるが、管理者要件として防御を重ねる。
deny_read = [
  "/mnt",
  "/mnt/**",
  "/media",
  "/media/**",
  "/run/media",
  "/run/media/**",
  "/Volumes",
  "/Volumes/**",
]


# -----------------------------------------------------------------------------
# MCP
# -----------------------------------------------------------------------------

# 空のmcp_serversテーブルを定義すると、すべてのMCPサーバーを無効化する。
# 管理者が承認したMCPだけ、名前とidentityをこの配下へ追加する。
[mcp_servers]

# 管理者がstdio MCPを許可する例:
#
# [mcp_servers.company_docs]
# identity = { command = "company-docs-mcp.exe" }
#
# 実行ファイルと引数を厳密に照合する例:
#
# [mcp_servers.company_docs.identity]
# command = { executable = 'C:\Program Files\Company\MCP\company-docs-mcp.exe', args = [
#   { match = "exact", value = "serve" },
#   { match = "exact", value = "--read-only" },
# ] }
#
# 管理者がHTTP MCPを許可する例:
#
# [mcp_servers.company_remote]
# identity = { url = "https://mcp.example.co.jp/v1" }


# -----------------------------------------------------------------------------
# コマンドルール
# -----------------------------------------------------------------------------

[rules]

# requirements.tomlのコマンドルールでは、decisionとして
# promptまたはforbiddenを指定する。
#
# 下記ルールは主要コマンドを対象にしたベストエフォートであり、
# あらゆる実行ファイル、ラッパー、エイリアスを完全には網羅しない。


# 主要な権限昇格コマンドを禁止する。
[[rules.prefix_rules]]
pattern = [
  { any_of = [
    "sudo",
    "su",
    "doas",
    "pkexec",
    "runas",
    "runas.exe",
    "gsudo",
    "gsudo.exe",
  ] },
]
decision = "forbidden"
justification = "OS権限の昇格は禁止されています。管理者権限が必要な処理は端末管理者が別途実施してください。"


# ローカルコマンドとしてのWSL起動を禁止する。
# CodexアプリのUIでWSLエージェントを選択する操作自体を禁止する設定ではない。
[[rules.prefix_rules]]
pattern = [
  { any_of = [
    "wsl",
    "wsl.exe",
  ] },
]
decision = "forbidden"
justification = "WSL経由でWindowsドライブや共有フォルダへ迂回することを防ぐため、WSLの起動は禁止されています。"


# マウント、共有接続、ドライブ割り当て、OSアクセス権の変更を禁止する。
[[rules.prefix_rules]]
pattern = [
  { any_of = [
    "mount",
    "umount",
    "diskutil",
    "subst",
    "subst.exe",
    "New-PSDrive",
    "new-psdrive",
    "New-SmbMapping",
    "new-smbmapping",
    "Remove-SmbMapping",
    "remove-smbmapping",
    "icacls",
    "icacls.exe",
    "cacls",
    "cacls.exe",
    "takeown",
    "takeown.exe",
  ] },
]
decision = "forbidden"
justification = "マウント、共有接続、ドライブ割り当て、またはOSアクセス権の変更は禁止されています。"


# Windowsのnet useによる共有フォルダ接続を禁止する。
[[rules.prefix_rules]]
pattern = [
  { any_of = ["net", "net.exe"] },
  { any_of = ["use", "USE"] },
]
decision = "forbidden"
justification = "Windows共有フォルダの接続またはネットワークドライブ割り当ては禁止されています。"


# 主要なシェル、インタープリター、開発ツールは人間の承認を要求する。
[[rules.prefix_rules]]
pattern = [
  { any_of = [
    "powershell",
    "powershell.exe",
    "pwsh",
    "pwsh.exe",
    "cmd",
    "cmd.exe",
    "bash",
    "bash.exe",
    "sh",
    "zsh",
    "python",
    "python.exe",
    "python3",
    "py",
    "node",
    "node.exe",
    "npm",
    "npm.cmd",
    "npx",
    "npx.cmd",
    "perl",
    "ruby",
    "dotnet",
    "dotnet.exe",
    "java",
    "java.exe",
    "javac",
    "javac.exe",
    "go",
    "go.exe",
    "cargo",
    "cargo.exe",
    "rustc",
    "rustc.exe",
  ] },
]
decision = "prompt"
justification = "シェル、スクリプト、インタープリター、またはビルドツールの実行には人間の承認が必要です。"


# 主要なファイル検索、転送、リポジトリ操作も人間の承認を要求する。
[[rules.prefix_rules]]
pattern = [
  { any_of = [
    "git",
    "git.exe",
    "rg",
    "rg.exe",
    "fd",
    "fd.exe",
    "find",
    "find.exe",
    "findstr",
    "findstr.exe",
    "where",
    "where.exe",
    "grep",
    "sed",
    "awk",
    "ls",
    "cat",
    "head",
    "tail",
    "curl",
    "curl.exe",
    "wget",
    "wget.exe",
    "ssh",
    "ssh.exe",
    "scp",
    "scp.exe",
    "sftp",
    "sftp.exe",
    "robocopy",
    "robocopy.exe",
    "xcopy",
    "xcopy.exe",
    "tar",
    "tar.exe",
    "7z",
    "7z.exe",
    "zip",
    "unzip",
  ] },
]
decision = "prompt"
justification = "ファイル参照、転送、検索、アーカイブ、またはリポジトリ操作には人間の承認が必要です。"


# -----------------------------------------------------------------------------
# 別経路となる機能を無効化
# -----------------------------------------------------------------------------

[features]

# Apps／コネクター経由の別データアクセス経路を無効化する。
apps = false

# プラグインおよびプラグイン同梱MCPの経路を無効化する。
plugins = false
remote_plugin = false
plugin_sharing = false

# ブラウザー操作を無効化する。
# Web検索ツールのcachedモードは別機能として利用できる。
in_app_browser = false
browser_use = false
browser_use_external = false
browser_use_full_cdp_access = false

# Computer Use、Record & Replay、関連する有効化フローを無効化する。
computer_use = false

# 自動承認機能を無効化する。
guardian_approval = false


# -----------------------------------------------------------------------------
# Windowsサンドボックス
# -----------------------------------------------------------------------------

[windows]

# elevatedだけを許可し、弱いフォールバックのunelevatedを禁止する。
#
# elevatedはCodexへ管理者権限を与える設定ではない。
# 専用の低権限サンドボックスユーザー、ファイル境界、
# ファイアウォールルールを利用できる、より強い実装である。
allowed_sandbox_implementations = ["elevated"]










===================================================================================================



以下は、修正版 `requirements.toml` で**何ができるか／何ができないか**を整理した表です。

### 判定

| 判定      | 意味                            |
| ------- | ----------------------------- |
| **○**   | 要件をおおむね技術的に強制できる              |
| **△**   | 一定範囲では制御できるが、例外や別経路が残る        |
| **×**   | `requirements.toml`だけでは制御できない |
| **要検証** | クライアントのバージョンや実環境で動作確認が必要      |

## 制御可否一覧

| No. | 制御したい内容                              |    判定    | 修正版でできること                                                                            | できないこと・残るリスク                                                       |
| --: | ------------------------------------ | :------: | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
|   1 | `Never`での実行を禁止する                     |   **○**  | `allowed_approval_policies = ["untrusted"]`により、承認ポリシーとして`never`を選択できないようにする          | `untrusted`でも、安全と判定された一部の読み取り処理は承認なしで実行される可能性がある                   |
|   2 | すべての実行を必ず承認させる                       |   **×**  | シェル、Git、検索、転送など主要コマンドを`prompt`に設定して承認対象にできる                                          | 任意の全コマンドへ一致する包括的なワイルドカードがないため、全操作を例外なく承認対象にはできない                   |
|   3 | 人間だけが承認する                            |   **○**  | `allowed_approvals_reviewers = ["user"]`により、自動レビューによる承認を禁止する                         | ユーザー自身が危険な操作を承認することまでは防げない                                         |
|   4 | Web検索をキャッシュのみにする                     |   **○**  | `allowed_web_search_modes = ["cached"]`により、ライブ検索とインデックス検索を禁止する                       | Web検索を無効にする`disabled`は仕様上選択可能。必ずキャッシュ検索を実行させる設定ではない                |
|   5 | ローカルコマンドからインターネットへ接続させない             |   **○**  | Permission Profileの`network.enabled = false`で、サンドボックス内コマンドの外部通信を禁止する                 | Web検索、MCP、外部コネクターなどは別経路。今回の設定ではそれらも可能な範囲で無効化している                   |
|   6 | Hooksを管理者管理に限定する                     |   **○**  | `allow_managed_hooks_only = true`により、ユーザー、プロジェクト、セッション、プラグインのHooksを読み込まない            | 管理者が`requirements.toml`へ追加したHookは実行される。今回の修正版では管理Hook自体は定義していない    |
|   7 | MCPを管理者管理に限定する                       |   **○**  | 空の`[mcp_servers]`により、現状はすべてのMCPを無効化する                                                | MCPを利用する場合は、管理者がサーバー名、実行ファイル、引数、URLなどを個別に登録する必要がある                 |
|   8 | 未承認MCPを禁止する                          |   **○**  | 管理者が明示したidentityと一致するMCPだけを許可する方式を採用できる                                              | 将来MCPを追加する際に、実行ファイルだけを緩く指定すると差し替えリスクが残る                            |
|   9 | `~/codex_work`だけを書き込み可能にする           |   **○**  | `":root" = "deny"`の後に`"~/codex_work" = "write"`を設定し、このフォルダだけを再許可する                   | システムコマンド実行に必要な最小限のファイルは、`:minimal = "read"`で読み取られる                 |
|  10 | `user`部分をログインユーザーに置き換える              |   **○**  | `~`を使用することで、現在ログインしているユーザーのホームディレクトリへ展開される                                           | `~`が企業で想定したローカルパスを指すかは端末構成に依存する                                    |
|  11 | `~/codex_work`外への書き込みを禁止する           |   **○**  | 通常のPermission Profile内では、`~/codex_work`外への書き込みは拒否される                                 | ユーザーがサンドボックス外実行を承認できる経路が残る場合、絶対的な禁止とは言えない                          |
|  12 | `~/codex_work`外のファイル読み取りを禁止する        |   **△**  | ファイルシステム全体を既定拒否するため、通常の業務ファイルは読み取れない                                                 | Codexが動作するための実行ファイル、DLL、ランタイムなどは`:minimal`により読み取り可能                |
|  13 | Windows共有フォルダへの書き込みを禁止する             |   **○**  | UNC共有や割り当て済みネットワークドライブも、`~/codex_work`以外であれば既定拒否になる                                  | `~/codex_work`自体が共有フォルダやリダイレクト先だった場合は意図に反する。TOMLだけでは物理配置を検証できない    |
|  14 | Windows共有フォルダの読み取りも禁止する              |   **○**  | ファイルシステム全体の既定拒否により、共有フォルダも通常は読み取れない                                                  | 別ツール、MCP、外部プロセス、承認されたサンドボックス外実行など、CodexのPermission Profile外の経路は別問題 |
|  15 | 共有フォルダをWorkspaceとして登録させない            |   **×**  | 共有フォルダをWorkspaceとして選択されても、そこへ読み書き権限を付与しないようにできる                                      | Codexアプリの画面上でフォルダを選択・登録する操作自体を禁止する設定はない                            |
|  16 | `~/codex_work`だけをWorkspaceとして登録可能にする |   **×**  | 実効的なファイルアクセス先を`~/codex_work`だけに限定できる                                                 | Workspace選択ダイアログの表示範囲や登録可能パスは`requirements.toml`では制御できない           |
|  17 | Workspaceとして選択されたフォルダを自動的に信頼しない      |   **○**  | `:workspace`や`:workspace_roots`を継承しないため、ユーザーが選択したパスへ自動的に権限を付与しない                     | 画面上では選択できるため、ユーザーにはアクセスエラーとして見える可能性がある                             |
|  18 | `.git`フォルダの直接変更を防ぐ                   |   **○**  | `~/codex_work/.git = "read"`により、Git管理情報を読み取り専用にする                                    | `git`コマンドによる通常操作との互換性に影響する可能性があるため、実機検証が必要                         |
|  19 | `.codex`設定をCodex自身に変更させない            |   **○**  | `~/codex_work/.codex = "read"`により、プロジェクト内のCodex設定を読み取り専用にする                          | 利用する機能が`.codex`への書き込みを必要とする場合、処理が失敗する可能性がある                        |
|  20 | OSの一時フォルダへの書き込みを禁止する                 |   **○**  | `:tmpdir = "deny"`および`:slash_tmp = "deny"`で一時領域を拒否する                                 | コンパイラー、パッケージ管理、圧縮・展開など、多くのツールが一時フォルダを必要とするため互換性リスクが高い              |
|  21 | macOSの外部ディスクを遮断する                    |   **○**  | `/Volumes`以下を`deny_read`へ登録している                                                      | 別の非標準マウント先が使われた場合は、個別パス指定が必要                                       |
|  22 | Linuxの外部メディアを遮断する                    |   **○**  | `/mnt`、`/media`、`/run/media`以下を`deny_read`へ登録している                                    | 非標準のマウントポイントやbind mountをすべて列挙できるわけではない                             |
|  23 | WSLのWindowsドライブを遮断する                 |   **△**  | `/mnt`以下を拒否し、さらに`wsl.exe`のローカル実行を禁止する                                                | CodexアプリのUIでWSLエージェントを選択する操作自体はTOMLで禁止できない                         |
|  24 | WSLを起動できないようにする                      |   **△**  | Codexがコマンドとして`wsl`または`wsl.exe`を実行することを禁止する                                           | OS側でユーザーが直接WSLを起動することや、Codexの実行環境をWSLへ切り替える操作は防げない                 |
|  25 | 権限昇格コマンドを禁止する                        |   **△**  | `sudo`、`su`、`doas`、`pkexec`、`runas`、`gsudo`など主要コマンドを`forbidden`にする                   | 別名のツール、スクリプト、API、既に管理者権限で動作しているプロセスなど、すべての昇格経路は網羅できない              |
|  26 | CodexをWindowsの管理者として起動させない           |   **×**  | 直接制御できない                                                                             | Windows側のアプリケーション制御、ユーザー権限、UAC、Intuneなどが必要                         |
|  27 | ネットワークドライブ割り当てを禁止する                  |   **△**  | `net use`、`New-PSDrive`、`New-SmbMapping`、`subst`など主要コマンドを禁止する                        | PowerShell API、独自ツール、別プロセスなど、すべての割り当て方法を網羅できない                     |
|  28 | NTFSアクセス権を変更させない                     |   **△**  | `icacls`、`cacls`、`takeown`などの主要コマンドを禁止する                                             | PowerShell/.NET API、独自プログラム、管理者プロセスを利用する別経路は残る                     |
|  29 | シェル実行を承認対象にする                        |   **○**  | PowerShell、cmd、bash、Python、Node.jsなど主要なシェル・ランタイムを`prompt`へ設定する                       | 未列挙の実行ファイルや、別名・ラッパーを使用した実行はルールに一致しない可能性がある                         |
|  30 | Git操作を承認対象にする                        |   **○**  | `git`と`git.exe`を`prompt`へ設定する                                                        | IDEやライブラリがGitをプロセス外APIとして操作する経路は別                                  |
|  31 | ファイル検索・参照を承認対象にする                    |   **△**  | `rg`、`find`、`grep`、`cat`、`where`など主要コマンドを承認対象にする                                     | Codexの組み込みファイルツールや未列挙コマンドまで、すべてを必ず承認対象にするわけではない                    |
|  32 | ファイル転送を承認対象にする                       |   **△**  | `curl`、`wget`、`scp`、`sftp`、`robocopy`、`xcopy`などを承認対象にする                              | ネットワーク自体はPermission Profileで無効だが、未列挙の転送ツールや外部MCPなどは別制御             |
|  33 | Apps／コネクターを無効化する                     |  **○相当** | `features.apps = false`により、別のデータアクセス経路を無効化する意図                                       | クライアントバージョンが該当キーを認識することを実機で確認する必要がある                               |
|  34 | プラグインを無効化する                          |  **○相当** | plugins、remote plugin、plugin sharingを無効化する意図                                         | クライアントバージョンによるキー対応状況の確認が必要                                         |
|  35 | ブラウザー操作を無効化する                        |  **○相当** | in-app browserやbrowser use関連機能を無効化する意図                                               | Web検索のcached機能は別機能なので、必要に応じて使用可能                                   |
|  36 | Computer Useを無効化する                   |  **○相当** | `computer_use = false`により、画面操作経路を閉じる意図                                               | 対応クライアントで設定が強制されるか実機確認が必要                                          |
|  37 | より強いWindowsサンドボックスだけを使う              |   **○**  | `windows.allowed_sandbox_implementations = ["elevated"]`により、unelevatedへのフォールバックを禁止する | 端末がelevatedサンドボックスの前提条件を満たさない場合、Codexが動作しない可能性がある                  |
|  38 | Codexへ管理者権限を与える                      | **該当なし** | `elevated`は管理者権限を与える値ではない                                                            | 名称が紛らわしいが、より強い分離方式を意味する                                            |
|  39 | 古いCodexクライアントを安全側に倒す                 |   **△**  | `allowed_sandbox_modes = ["read-only"]`により、旧方式では書き込み禁止を意図する                          | 古いクライアントではPermission Profile管理が無視されるため、想定どおりの完全制御にはならない            |
|  40 | `requirements.toml`だけで全要件を満たす        |   **×**  | Codexランタイム内の多くの制御は可能                                                                 | Workspace登録禁止、管理者起動禁止、OSユーザー権限、フォルダの物理配置、古いクライアント排除などは別手段が必要       |

## まとめ

### 実現できる主な制御

* `Never`ポリシーの禁止
* 自動承認の禁止
* ライブWeb検索の禁止
* 未管理Hooksの禁止
* MCPの全面禁止または管理者Allowlist化
* 通常のファイルアクセスを`~/codex_work`へ限定
* Windows共有フォルダや他のローカルフォルダの通常読み書き禁止
* ローカルコマンドからのネットワーク接続禁止
* 主要な権限昇格、WSL、共有接続コマンドの禁止
* `elevated` Windowsサンドボックスの強制
* プラグイン、ブラウザー操作、Computer Useなどの無効化

### 完全には実現できない制御

* 全コマンドを例外なく人間の承認対象にする
* `~/codex_work`以外をWorkspaceとして選択・登録する操作自体を禁止する
* ユーザーが承認したサンドボックス外アクセスを絶対に禁止する
* あらゆる権限昇格方法を漏れなく禁止する
* CodexアプリをWindowsの管理者として起動することを禁止する
* `~/codex_work`が共有フォルダ、ジャンクション、リダイレクト先でないことを検証する
* 古いCodexクライアントの利用を`requirements.toml`だけで防ぐ
* Codex CloudやOS側の操作を、このローカルポリシーだけで制御する

## 総合評価

| 評価対象                             |     判定     |
| -------------------------------- | :--------: |
| 通常のローカル作業を`~/codex_work`へ限定      | **おおむね可能** |
| 共有フォルダの通常読み書き禁止                  | **おおむね可能** |
| ライブ通信、MCP、Hooksなどの制限             |   **可能**   |
| 全実行の完全な人間承認                      |   **不可**   |
| Workspace登録操作そのものの制限             |   **不可**   |
| OS権限昇格の完全禁止                      |   **不可**   |
| `requirements.toml`だけによる全要件の完全達成 |   **不可**   |

この修正版は、**通常のCodex作業を狭いサンドボックスへ閉じ込めるポリシーとしては有効**です。ただし、OS管理やWorkspace選択UIまで含む完全な端末統制ではありません。






