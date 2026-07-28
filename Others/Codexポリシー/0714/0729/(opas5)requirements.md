公式ドキュメント（Managed configuration / requirements.toml リファレンス / Permissions / Sandboxing）を確認したうえで、ご要望をすべて `requirements.toml` だけで表現したポリシーを作成しました。

## 前提（重要な仕様確認）

Codex 0.138.0 以降は `sandbox_mode` 系ではなく **Permission Profiles（`default_permissions` + `[permissions.<name>]`）** が推奨で、`allowed_permission_profiles` を requirements に置くと強制的にプロファイル方式に切り替わります。ご要望の「ワークスペース外は参照も禁止」は、公式の "File access limited to workspace" の例（`":root" = "deny"` + `":minimal" = "read"`）で実現できます。

`~` は Windows では `%USERPROFILE%` に解決されるため、`~/codex_work` と書けばログイン中のアカウント名が自動で入ります（ハードコード不要）。

## requirements.toml

```toml
###############################################################################
# 全社共通 Codex ポリシー（requirements.toml）
#   配布先: ChatGPT 管理画面 > Codex > Managed configuration
#           (https://chatgpt.com/codex/settings/managed-configs)
#   ※ requirements は「管理者強制」レイヤーで、ユーザーの config.toml /
#     プロファイル / CLI の --config / --sandbox 等では上書きできません。
#   ※ 本ポリシーは requirements.toml のみで制御します（managed_config.toml
#     や MDM の config_toml_base64 は使用しません）。
###############################################################################

# =============================================================================
# 1) 承認ゲート（Never 実行の禁止）
# =============================================================================
# approval_policy に指定できる値をこの2つだけに限定する。
#   untrusted  : 既知の安全なコマンド以外はすべて承認を要求（最も厳格）
#   on-request : サンドボックス外に出る操作・昇格時に必ず承認を要求
# "never"（--ask-for-approval never）と "granular" は列挙していないので拒否され、
# 併せて --yolo / --dangerously-bypass-* 相当も成立しなくなる。
allowed_approval_policies = ["untrusted", "on-request"]

# 承認する主体を「人間（user）」に固定する。
# auto_review（レビュア―サブエージェントによる自動承認）を許可しない＝
# 必ず人の目を通す承認ゲートになる。
allowed_approvals_reviewers = ["user"]

# =============================================================================
# 2) Web 検索はキャッシュのみ
# =============================================================================
# "cached" = OpenAI 側の索引のみ参照し、外部サイトへ実アクセスしない。
# "live" / "indexed" を許可しないため、full-access 相当のセッションでも
# ライブ検索に昇格できない。なお "disabled" は常に暗黙的に許可される。
allowed_web_search_modes = ["cached"]

# =============================================================================
# 3) Windows ネイティブサンドボックス実装の固定
# =============================================================================
[windows]
# elevated のみ許可。elevated は専用の低権限サンドボックスユーザー、
# ファイルシステム権限境界、ファイアウォール規則を使えるため最も強い。
# unelevated はネットワーク分離が弱く read/write の分割も強制できないので不許可。
allowed_sandbox_implementations = ["elevated"]

# 旧クライアント（0.137.0 以前）が混在する移行期の互換用ガード。
# danger-full-access を列挙しないことで「権限昇格＝フルアクセス」を封じる。
# 全端末が 0.138.0 以降になったら削除してよい。
allowed_sandbox_modes = ["read-only", "workspace-write"]

# =============================================================================
# 4) 選択可能な権限プロファイルの限定
# =============================================================================
# 既定で適用するプロファイル（下で定義する管理者製プロファイル）
default_permissions = "corp_codex_work_only"

[allowed_permission_profiles]
# ここに true で列挙したものだけが選択可能。省略＝拒否。
# 将来 Codex に追加される新しい組み込みプロファイルも自動的に拒否される。
corp_codex_work_only = true
# ":read-only"          は省略 → 拒否（必要なら true にして読み取り専用運用も可）
# ":workspace"          は省略 → 拒否（ユーザーが任意フォルダを書込可能にできてしまうため）
# ":danger-full-access" は省略 → 拒否（権限昇格の禁止）

# =============================================================================
# 5) 管理者定義プロファイル本体
#    「~/codex_work のみ作業可能。それ以外は参照も禁止」
# =============================================================================
[permissions.corp_codex_work_only]
description = "作業は %USERPROFILE%\\codex_work 配下のみ。共有フォルダ・外部マウントは読取も禁止。"
# :workspace を継承することで、ワークスペース内の .git/ や .codex/ を
# 読み取り専用に保つ Codex 標準の保護がそのまま効く。
# （:danger-full-access は extends 不可＝この時点で昇格経路が存在しない）
extends = ":workspace"

# -----------------------------------------------------------------------------
# 5-1) 唯一のワークスペースルート
# -----------------------------------------------------------------------------
[permissions.corp_codex_work_only.workspace_roots]
# "~" はログイン中のユーザーのホーム（Windows は %USERPROFILE%）に解決される。
# → C:\Users\<ログインユーザー>\codex_work
# 事前に作成しておくこと（存在しないと起動時に警告になる）。
"~/codex_work" = true

# -----------------------------------------------------------------------------
# 5-2) ファイルシステム全体の基本方針
# -----------------------------------------------------------------------------
[permissions.corp_codex_work_only.filesystem]
# 既定ですべてのドライブ・パスを「読み取りすら不可」にする。
# 「~/codex_work 以外はファイルの参照であっても禁止」の実体はこの1行。
":root" = "deny"

# ただし実務上、コンパイラ・git・Node/Python ランタイム等を起動できないと
# 作業にならないため、Codex が定義する最小限のシステムパスだけ読取を許可する。
":minimal" = "read"

# 一時領域も塞ぐ（:workspace 継承時は既定 write のため明示的に deny する）。
# 共有フォルダへのデータ持ち出しの中継地点をなくす意図。
":tmpdir" = "deny"
":slash_tmp" = "deny"

# 無制限の "**" deny グロブを Linux / WSL / ネイティブ Windows で
# 事前展開する際の探索深さ。1 以上必須。深くすると起動が遅くなる。
glob_scan_max_depth = 4

# --- Windows 共有フォルダ（UNC）の遮断 --------------------------------------
# ワイルドカードで汎用的に遮断する。TOML のリテラル文字列（'）を使うため
# バックスラッシュのエスケープは不要。
'\\**'                  = "deny"   # \\server\share\... すべての UNC パス
'\\?\UNC\**'            = "deny"   # Win32 デバイス名前空間経由の UNC 迂回
'\\wsl$\**'             = "deny"   # Windows から WSL ファイルシステムへの侵入
'\\wsl.localhost\**'    = "deny"   # 同上（新形式）
'//**'                  = "deny"   # スラッシュ表記の UNC / POSIX 風ツール対策

# --- ネットワークドライブ（マップされたドライブレター）の遮断 ----------------
# ドライブレターにはワイルドカードが使えないため列挙する。
# C: 以外を明示的に塞ぐことで「Z: に共有をマップして書く」経路を潰す。
'D:\' = "deny"
'E:\' = "deny"
'F:\' = "deny"
'G:\' = "deny"
'H:\' = "deny"
'I:\' = "deny"
'J:\' = "deny"
'K:\' = "deny"
'L:\' = "deny"
'M:\' = "deny"
'N:\' = "deny"
'O:\' = "deny"
'P:\' = "deny"
'Q:\' = "deny"
'R:\' = "deny"
'S:\' = "deny"
'T:\' = "deny"
'U:\' = "deny"
'V:\' = "deny"
'W:\' = "deny"
'X:\' = "deny"
'Y:\' = "deny"
'Z:\' = "deny"

# --- mac / Linux / WSL のマウントポイント遮断（保険） -----------------------
# 主用途は Windows だが、CLI を WSL や Mac/Linux で使う要員がいても
# 同じポリシーで外部・共有ストレージに触れないようにする。
"/mnt"                  = "deny"   # WSL の /mnt/c, /mnt/z（Windows ドライブ＆共有）
"/media"                = "deny"   # Linux のリムーバブル / 自動マウント
"/run/media"            = "deny"   # systemd 系の自動マウント
"/net"                  = "deny"   # autofs 経由の NFS
"/srv"                  = "deny"   # 共有サービス領域
"/Volumes"              = "deny"   # macOS の外部ボリューム / SMB マウント
"/System/Volumes/Data/mnt" = "deny" # macOS のデータボリューム経由の迂回
"/private/var/folders"  = "deny"   # macOS の一時領域
"/cygdrive"             = "deny"   # Cygwin/MSYS 経由のドライブ迂回
"~/.local/share/gvfs"   = "deny"   # GNOME のリモートマウント
"~/Library/CloudStorage" = "deny"  # OneDrive/Box 等のクラウド同期（macOS）

# --- 資格情報・鍵の明示的遮断（:root=deny の多層防御） ----------------------
"~/.ssh"                = "deny"
"~/.aws"                = "deny"
"~/.azure"              = "deny"
"~/.kube"               = "deny"
"~/.gnupg"              = "deny"
"~/.docker"             = "deny"
"~/.codex/auth.json"    = "deny"
'~/AppData/Roaming/Microsoft/Credentials' = "deny"
'~/AppData/Local/Microsoft/Credentials'   = "deny"

# -----------------------------------------------------------------------------
# 5-3) ワークスペースルート内のルール
# -----------------------------------------------------------------------------
[permissions.corp_codex_work_only.filesystem.":workspace_roots"]
# ルート直下＝~/codex_work を読み書き可能にする。編集はここだけ。
"." = "write"
# 機密が入りやすいファイルはワークスペース内でも読ませない
# （より限定的なルールが広いルールに優先し、deny が write に勝つ）。
"**/*.env"        = "deny"
"**/*.pem"        = "deny"
"**/*.key"        = "deny"
"**/*.pfx"        = "deny"
"**/id_rsa*"      = "deny"
"**/.npmrc"       = "deny"
"**/.git-credentials" = "deny"

# -----------------------------------------------------------------------------
# 5-4) ネットワーク（サンドボックス内コマンドの通信）
# -----------------------------------------------------------------------------
[permissions.corp_codex_work_only.network]
# サンドボックス内で実行されるコマンドの外向き通信を無効化。
# ローカル / プライベート宛先も既定でブロックされる（DNS リバインド対策）。
# 社内 Git 等が必要になった場合のみ domains に allow を追加する運用にする。
enabled = false

# =============================================================================
# 6) 管理者強制の読み取り拒否（プロファイルとは別の強制レイヤー）
# =============================================================================
# ユーザーはローカル設定でこれを弱められない。
# また deny_read が存在する時点で、ランタイムはフルアクセス権限を拒否し、
# read-only / workspace サンドボックスを維持する（＝権限昇格の追加ブレーキ）。
# 注意: ネイティブ Windows では deny_read は直接ファイルツールに適用され、
#       シェル子プロセスの読み取りは上の 5-2 のサンドボックス規則側で守られる。
[permissions.filesystem]
deny_read = [
  '\\**',                 # Windows 共有フォルダ（UNC）
  '\\?\UNC\**',
  '\\wsl$\**',
  '\\wsl.localhost\**',
  "/mnt/**",              # WSL 経由の Windows ドライブ / 共有
  "/media/**",
  "/Volumes/**",          # macOS の SMB / 外部ボリューム
  "/net/**",
  "/**/*.env",
  "~/.ssh",
  "~/.aws",
  "~/.gnupg",
  "~/.codex/auth.json",
]

# =============================================================================
# 7) コマンドレベルのガード（.rules とマージされ、最も厳しい判定が勝つ）
#    requirements の rules は decision に "prompt" か "forbidden" のみ指定可。
# =============================================================================
[rules]
prefix_rules = [
  # --- 共有フォルダのマウント / 転送を禁止 ---------------------------------
  { pattern = [{ token = "net" },     { any_of = ["use"] }], decision = "forbidden", justification = "共有フォルダのマウントは禁止です。" },
  { pattern = [{ token = "net.exe" }, { any_of = ["use"] }], decision = "forbidden", justification = "共有フォルダのマウントは禁止です。" },
  { pattern = [{ token = "subst" }],    decision = "forbidden", justification = "ドライブ割り当てによるサンドボックス回避は禁止です。" },
  { pattern = [{ token = "mount" }],    decision = "forbidden", justification = "マウント操作は禁止です。" },
  { pattern = [{ token = "robocopy" }], decision = "forbidden", justification = "ワークスペース外への一括コピーは禁止です。" },
  { pattern = [{ token = "xcopy" }],    decision = "forbidden", justification = "ワークスペース外への一括コピーは禁止です。" },

  # --- 権限昇格の禁止 -------------------------------------------------------
  { pattern = [{ token = "runas" }],  decision = "forbidden", justification = "権限昇格は禁止です。" },
  { pattern = [{ token = "sudo" }],   decision = "forbidden", justification = "権限昇格は禁止です。" },
  { pattern = [{ token = "su" }],     decision = "forbidden", justification = "権限昇格は禁止です。" },
  { pattern = [{ token = "psexec" }], decision = "forbidden", justification = "権限昇格は禁止です。" },
  { pattern = [{ token = "takeown" }],decision = "forbidden", justification = "所有権変更は禁止です。" },
  { pattern = [{ token = "icacls" }], decision = "forbidden", justification = "ACL 変更は禁止です。" },
  { pattern = [{ token = "reg" }, { any_of = ["add", "delete", "import"] }], decision = "forbidden", justification = "レジストリ変更は禁止です。" },

  # --- シェル入口は必ず承認を通す ------------------------------------------
  { pattern = [{ any_of = ["powershell", "powershell.exe", "pwsh", "pwsh.exe", "cmd", "cmd.exe", "wsl", "wsl.exe", "bash", "sh", "zsh"] }], decision = "prompt", justification = "シェル実行は承認が必要です。" },

  # --- 外部への push / 破壊的操作 ------------------------------------------
  { pattern = [{ token = "git" }, { any_of = ["push", "remote", "clean"] }], decision = "prompt", justification = "リポジトリの変更・外部送信は承認が必要です。" },
  { pattern = [{ token = "curl" }],  decision = "prompt", justification = "外部通信は承認が必要です。" },
  { pattern = [{ token = "wget" }],  decision = "prompt", justification = "外部通信は承認が必要です。" },
]

# =============================================================================
# 8) Hooks は管理者管理のみ
# =============================================================================
# ユーザー / プロジェクト / セッション / プラグイン由来の hooks をすべて無視し、
# requirements.toml と管理レイヤー由来の hooks だけを読み込む。
allow_managed_hooks_only = true

[features]
# 管理 hooks を確実に動かすため hooks 機能自体は有効に固定する。
# （社内で hooks を一切使わない方針なら false に変更してよい）
hooks = true

# --- 攻撃面の削減 -----------------------------------------------------------
plugins                    = false  # プラグイン全体を無効化（API キー利用時も適用）
remote_plugin              = false  # リモートプラグインカタログを無効化
plugin_sharing             = false  # ローカル作成プラグインの社内共有を無効化
memories                   = false  # 会話内容の永続記憶を無効化
in_app_browser             = false  # 内蔵ブラウザペインを無効化
browser_use                = false  # ブラウザ操作 / Browser Agent を無効化
browser_use_external       = false  # 外部ブラウザ操作を無効化
browser_use_full_cdp_access = false # CDP フルアクセス / 開発者モードを無効化
computer_use               = false  # 画面操作・記録再生を無効化
network_proxy              = false  # サンドボックス内ネットワークプロキシを無効化

# 管理 hooks スクリプトを配布する場合のみ以下を有効化する。
# ディレクトリは MDM / Intune 等で事前に配置し、絶対パスかつ存在必須。
# [hooks]
# windows_managed_dir = 'C:\ProgramData\OpenAI\Codex\hooks'
# managed_dir         = "/etc/codex/hooks"

# =============================================================================
# 9) MCP は管理者が承認したものだけ
# =============================================================================
# [mcp_servers] を「存在するが空」の状態にすると、すべての MCP サーバーが
# 無効化される。承認する場合はここに name と identity の両方を追記し、
# 名前と identity が両方一致したサーバーだけが有効になる。
[mcp_servers]
# 例）社内 MCP を許可する場合:
# [mcp_servers.corp_docs.identity]
# url = "https://mcp.example.co.jp/mcp"
#
# [mcp_servers.corp_tool.identity]
# command = { executable = 'C:\Program Files\Corp\corp-mcp.exe', args = [
#   { match = "exact",  value = "serve" },
#   { match = "prefix", value = "--workspace=" },
# ] }

# =============================================================================
# 10) プラグインマーケットプレイスの遮断
# =============================================================================
[marketplaces]
# allowed_sources を一つも定義しないことで、ユーザー追加のマーケットプレイス、
# プラグインインストール、Git マーケットプレイス更新をすべて拒否する。
restrict_to_allowed_sources = true

# =============================================================================
# 11) その他の統制
# =============================================================================
allow_appshots      = false   # Appshots（画面キャプチャ共有）を無効化
allow_remote_control = false  # 別デバイスからの遠隔操作を無効化
enforce_residency   = "us"    # データレジデンシー（不要なら削除）
```

## 適用手順

管理画面の Managed configuration（`https://chatgpt.com/codex/settings/managed-configs`）で新規ポリシーを作成し、上記の内容を貼り付けて対象グループに割り当てます。ご提示の `/codex/cloud/settings/policies` は Codex cloud 側のポリシー画面で、ローカルクライアント（Windows PC の CLI / IDE 拡張 / デスクトップアプリ）に効かせる requirements は Managed configuration 側が配布経路になります。割り当て前に、`C:\Users\<ユーザー>\codex_work` を配布スクリプトや Intune で作成しておいてください。存在しないワークスペースルートは起動時警告になります。

クライアントはサインイン時にクラウドから requirements バンドルを取得してキャッシュします。取得も有効キャッシュも無い場合はエラーになり「ポリシー無しで静かに起動する」ことはないので、ポリシー未適用のまま使われる事故は起きません。

## 正直にお伝えしておく制約

「共有フォルダを Workspace として登録させない」という**登録操作そのものを禁止するキーは requirements.toml に存在しません**。上記ポリシーは、登録されてしまった場合でも UNC・ネットワークドライブ・各種マウントポイントを `deny` で潰し、`:root = "deny"` を土台に置くことで、実際には読み取りも書き込みもできない状態にする設計です。ただし `:workspace_roots` の `"." = "write"` と個別パスの `deny` が競合したときの優先順位はドキュメント上で明示されていないため、共有フォルダをワークスペースに追加された場合の挙動は**必ず検証環境で実測してください**。確実に登録経路を断つなら、GPO でネットワークドライブのマップ禁止や共有への書き込み ACL を併用するのが堅実です。

もう一点、ネイティブ Windows では管理者強制の `deny_read` は直接のファイルツールに適用され、シェル子プロセスの読み取りには適用されません。シェル経由の読み取りは `elevated` サンドボックスとプロファイルの `filesystem` 規則が守る形になるため、`windows.allowed_sandbox_implementations = ["elevated"]` は必須です（ご指定どおりの設定になっています）。

また `[experimental_network]` は Windows サポートが限定的と明記されているため、あえて使わず、プロファイル側の `network.enabled = false` で通信を止めています。

まずは 5〜10 台程度の小グループに割り当てて、ビルドや git 操作が `:minimal` の範囲で完走するかを確認し、足りないパス（社内ツールのインストール先など）が出たら `filesystem` に `"read"` を個別追加していく進め方をおすすめします。
