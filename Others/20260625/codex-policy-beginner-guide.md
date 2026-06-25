# Codex ポリシー初心者向けガイド

## このファイルの目的

この資料は、会社の PC で Codex を安全に使うためのポリシーを、初心者にもわかるように説明するものです。

実際に管理画面へ登録する設定ファイルは、同じフォルダにある `requirements.company-codex-policy.toml` です。

このガイドでは、次の内容を説明します。

- 何を禁止しているのか
- なぜ禁止する必要があるのか
- Codex の設定だけでできること
- Codex の設定だけではできないこと
- 導入後に確認すべきこと

## まず結論

今回のポリシーの目的は、Codex が会社 PC 上で勝手に危険な操作をしないようにすることです。

特に、次のことを防ぎます。

- 共有フォルダへ勝手に書き込む
- Workspace 外のファイルを書き換える
- ユーザーが承認なしでコマンドを実行させる
- Web から最新情報を自由に検索する
- ユーザーが自由に MCP や Hooks を追加する
- フルアクセス権限で Codex を動かす
- 古い Codex クライアントで安全設定をすり抜ける

## Codex の Workspace とは

Workspace とは、Codex に作業させるフォルダのことです。

たとえば、ユーザーが次のフォルダを Workspace として選ぶと、Codex はそのフォルダ内のファイルを読んだり編集したりできます。

```text
D:\projects\my-app
```

今回のポリシーでは、基本的に Codex が編集できる場所を Workspace 内だけに制限します。

つまり、Codex が作業してよい場所を決めて、それ以外の場所には手を出させない、という考え方です。

## requirements.toml とは

`requirements.toml` は、管理者が Codex に対して強制するルールを書くための設定です。

ユーザー個人の設定とは違い、管理者が設定したルールとして扱われます。

今回作成したファイルでは、次のようなルールを書いています。

- 使ってよい承認モード
- 使ってよい権限プロファイル
- 使ってよい Web 検索モード
- 使ってよい MCP
- Hooks の扱い
- ファイルアクセスの範囲
- ネットワークアクセスの扱い
- 旧クライアント向けの制限

## 実際の設定内容

以下が、実際に管理画面へ登録する設定内容です。

登録先は次の画面です。

```text
https://chatgpt.com/codex/cloud/settings/policies
```

この内容は、同じフォルダにある `requirements.company-codex-policy.toml` と同じものです。

注意点として、UNC 形式の共有フォルダはワイルドカードで防御的に拒否しています。

UNC 形式とは、次のようなパスです。

```text
\\fileserver\share
\\nas01\dept
```

今回の設定では、これらを個別に列挙するのではなく、次のような汎用パターンで拒否します。

```toml
"\\\\*\\*" = "deny"
"\\\\*\\*\\**" = "deny"
```

ただし、`S:\` や `Z:\` のような mapped drive は、TOML の静的設定だけでは「ネットワーク共有なのか、ローカルディスクなのか」を判定できません。

そのため、この設定では会社で共有ドライブに使われやすい `H:\` から `Z:\` までをまとめて拒否しています。

自社でローカルディスクとして使っているドライブ文字がある場合は、その文字を除外してください。

この設定は Codex 側の防御策です。共有フォルダへの書き込みを物理的に禁止するには、Windows やファイルサーバー側の権限設定も必要です。

実際の設定内容:

```toml
# Codex managed requirements for company-managed PCs.
# Paste this payload into:
# https://chatgpt.com/codex/cloud/settings/policies
#
# Review the mapped-drive letters below before deployment. UNC shares are
# denied generically with wildcard patterns.

# Block approval-free mode. "on-request" still lets Codex work inside the
# sandbox automatically; prefix rules below prompt for shell entrypoints.
allowed_approval_policies = ["on-request"]
allowed_approvals_reviewers = ["user"]

# Web search may use only OpenAI's cached index. "disabled" is always allowed.
allowed_web_search_modes = ["cached"]

# Disable device remote control and user/project/plugin hooks.
allow_remote_control = false
allow_managed_hooks_only = true

# Modern clients: use the centrally managed permission profile below.
default_permissions = "company_workspace"

# Legacy clients that do not support managed permission profiles:
# fail closed to read-only. Remove "read-only" only after the fleet is
# upgraded and tested on Codex 0.138.0 or later.
allowed_sandbox_modes = ["read-only"]

[allowed_permission_profiles]
":read-only" = true
company_workspace = true
# ":workspace" is omitted so users cannot bypass the custom profile.
# ":danger-full-access" is omitted so full local access is denied.

[permissions.company_workspace]
description = "Workspace-only editing, no command network, shared folders denied."
extends = ":workspace"

[permissions.company_workspace.filesystem]
glob_scan_max_depth = 6
":root" = "deny"
":minimal" = "read"
":tmpdir" = "deny"
":slash_tmp" = "deny"

# Shared-folder controls:
# - UNC shares are denied generically as a defense-in-depth rule. These patterns
#   cover paths such as \\server\share and \\server\share\folder.
#   Confirm enforcement on your target Codex client/Windows build; use Windows
#   ACL/GPO/Intune for physical write prevention.
# - Mapped network drives cannot be distinguished from local drives by static
#   TOML alone, so this policy denies common mapped-drive letters H: through Z:.
#   Remove any letters your company uses for local disks.
"\\\\*\\*" = "deny"
"\\\\*\\*\\**" = "deny"
"H:\\" = "deny"
"I:\\" = "deny"
"J:\\" = "deny"
"K:\\" = "deny"
"L:\\" = "deny"
"M:\\" = "deny"
"N:\\" = "deny"
"O:\\" = "deny"
"P:\\" = "deny"
"Q:\\" = "deny"
"R:\\" = "deny"
"S:\\" = "deny"
"T:\\" = "deny"
"U:\\" = "deny"
"V:\\" = "deny"
"W:\\" = "deny"
"X:\\" = "deny"
"Y:\\" = "deny"
"Z:\\" = "deny"

[permissions.company_workspace.filesystem.":workspace_roots"]
"." = "write"
".git" = "read"
".codex" = "read"
".agents" = "read"
"*.env" = "deny"
"*/*.env" = "deny"
"*/*/*.env" = "deny"
"**/*secret*" = "deny"
"**/*credential*" = "deny"

[permissions.company_workspace.network]
enabled = false
allow_upstream_proxy = false
allow_local_binding = false
dangerously_allow_non_loopback_proxy = false
dangerously_allow_all_unix_sockets = false

# Admin-enforced read denials that local user config cannot weaken.
[permissions.filesystem]
deny_read = [
  "\\\\*\\*",
  "\\\\*\\*\\**",
  "H:\\",
  "I:\\",
  "J:\\",
  "K:\\",
  "L:\\",
  "M:\\",
  "N:\\",
  "O:\\",
  "P:\\",
  "Q:\\",
  "R:\\",
  "S:\\",
  "T:\\",
  "U:\\",
  "V:\\",
  "W:\\",
  "X:\\",
  "Y:\\",
  "Z:\\",
]

# MCP: empty allowlist means no user-defined MCP servers are approved.
# Add only admin-approved servers with exact identity.command or identity.url.
[mcp_servers]

[features]
hooks = true
apps = false
browser_use = false
browser_use_external = false
browser_use_full_cdp_access = false
computer_use = false
in_app_browser = false
plugin_sharing = false
plugins = false

# Optional managed hooks can be added after the hook directory, event
# definitions, and scripts are deployed by MDM or another admin channel.
# `allow_managed_hooks_only = true` above blocks user/project/session/plugin
# hooks while still allowing admin-managed hook sources.

# Native Windows sandbox selection. This follows the "no elevation" requirement.
# If your security team permits OpenAI's elevated Windows sandbox implementation,
# allowing "elevated" can provide stronger enforcement on native Windows.
[windows]
allowed_sandbox_implementations = ["unelevated"]

[rules]
prefix_rules = [
  { pattern = [{ any_of = ["bash", "sh", "zsh", "powershell", "pwsh", "cmd"] }], decision = "prompt", justification = "Company policy requires explicit approval for shell entrypoints." },
  { pattern = [{ any_of = ["sudo", "su", "runas"] }], decision = "forbidden", justification = "Privilege escalation is prohibited on company-managed PCs." },
  { pattern = [{ token = "Start-Process" }, { any_of = ["-Verb", "-verb"] }, { any_of = ["RunAs", "runas"] }], decision = "forbidden", justification = "Privilege escalation is prohibited on company-managed PCs." },
  { pattern = [{ token = "net" }, { token = "use" }], decision = "forbidden", justification = "Mapping network drives is prohibited on company-managed PCs." },
  { pattern = [{ any_of = ["New-PSDrive", "subst"] }], decision = "forbidden", justification = "Creating alternate drive mappings is prohibited on company-managed PCs." },
]
```

## 設定内容の読み方

上の設定は長く見えますが、役割ごとに分けると理解しやすくなります。

### 承認モード

```toml
allowed_approval_policies = ["on-request"]
allowed_approvals_reviewers = ["user"]
```

承認なし実行の `never` を禁止し、承認が必要な操作ではユーザー承認を通す設定です。

`never` が入っていないため、承認なしモードは使えません。

注意点として、`on-request` は「すべての操作を毎回承認する」という意味ではありません。

Codex は sandbox の内側で許可された作業を自動実行する場合があります。今回の設定では、後述の command rules により、`powershell` や `cmd` などの shell entrypoint は承認を求めるようにしています。

### Web 検索

```toml
allowed_web_search_modes = ["cached"]
```

Web 検索をキャッシュ済み検索のみにします。

ライブ検索は許可していません。

### Hooks

```toml
allow_managed_hooks_only = true
```

管理者が用意した Hooks だけを許可します。

ユーザーやプロジェクトが勝手に追加した Hooks は使わせません。

### 既定の権限

```toml
default_permissions = "company_workspace"
```

Codex が標準で使う権限を、会社用に作った `company_workspace` に固定します。

### 古いクライアント向けの制限

```toml
allowed_sandbox_modes = ["read-only"]
```

古い Codex クライアントでは、安全のため読み取り専用にします。

### 許可する権限プロファイル

```toml
[allowed_permission_profiles]
":read-only" = true
company_workspace = true
```

ユーザーが選べる権限を限定します。

`:danger-full-access` を書いていないため、フルアクセスは選べません。

### Workspace 内の編集

```toml
[permissions.company_workspace.filesystem.":workspace_roots"]
"." = "write"
```

Workspace の中だけ書き込み可能にします。

### 共有フォルダの拒否

```toml
"\\\\*\\*" = "deny"
"\\\\*\\*\\**" = "deny"
"H:\\" = "deny"
"Z:\\" = "deny"
```

UNC 形式の共有フォルダをワイルドカードで防御的に拒否します。

`H:\` から `Z:\` までは、mapped drive として使われやすいためまとめて拒否しています。

ただし、会社によっては `D:\` や `E:\` などを共有ドライブとして使う場合や、逆に `H:\` 以降をローカルディスクとして使う場合があります。

その場合は、自社のドライブ割り当てルールに合わせて調整してください。

また、`permissions.filesystem.deny_read` は読み取り拒否の設定です。共有フォルダへの物理的な書き込み禁止は、Windows の ACL、GPO、Intune、ファイルサーバー権限でも実施してください。

### ネットワーク

```toml
[permissions.company_workspace.network]
enabled = false
```

Codex が実行するコマンドからのネットワークアクセスを禁止します。

### MCP

```toml
[mcp_servers]
```

空の MCP allowlist です。

何も登録されていないため、ユーザー定義 MCP は使えません。

### 機能の無効化

```toml
[features]
apps = false
browser_use = false
computer_use = false
plugins = false
```

外部操作につながりやすい機能を無効化します。

### Windows の sandbox

```toml
[windows]
allowed_sandbox_implementations = ["unelevated"]
```

Windows で権限昇格しない sandbox 実装だけを許可します。

### 危険なコマンドの禁止

```toml
[rules]
prefix_rules = [
  { pattern = [{ any_of = ["sudo", "su", "runas"] }], decision = "forbidden", justification = "Privilege escalation is prohibited on company-managed PCs." },
  { pattern = [{ token = "net" }, { token = "use" }], decision = "forbidden", justification = "Mapping network drives is prohibited on company-managed PCs." },
  { pattern = [{ any_of = ["New-PSDrive", "subst"] }], decision = "forbidden", justification = "Creating alternate drive mappings is prohibited on company-managed PCs." },
]
```

管理者権限につながるコマンドや、共有フォルダを後からドライブ文字に割り当てるコマンドを禁止します。

## 承認なし実行を禁止する理由

Codex には、コマンドを自動実行する機能があります。

便利ですが、会社 PC では危険になる場合があります。

たとえば、承認なしで次のような操作が走ると問題になります。

- ファイルを削除する
- 共有フォルダに書き込む
- 外部サイトへ通信する
- 社内情報を読み取る
- スクリプトを実行する

そのため、今回のポリシーでは `never` という承認なしモードを禁止しています。

代わりに、承認が必要な操作ではユーザー確認を求める `on-request` のみを許可しています。

ただし、`on-request` は sandbox 内のすべての処理を毎回止める設定ではありません。通常作業の一部は自動実行されるため、shell 実行や危険コマンドは command rules でも追加制限しています。

## フルアクセスを禁止する理由

Codex には、広い権限でローカル PC を操作できるモードがあります。

代表的なものが `danger-full-access` です。

名前の通り、これは非常に強い権限です。便利な反面、会社 PC では次のようなリスクがあります。

- Workspace 外のファイルへアクセスする
- ユーザーフォルダや設定ファイルへアクセスする
- 共有フォルダへ書き込む
- 本来触るべきでない場所を変更する

今回のポリシーでは、このようなフルアクセス権限を許可していません。

## Workspace 内だけ編集させる考え方

今回の基本方針は、次のとおりです。

```text
Codex が編集してよいのは Workspace 内だけ
```

そのため、管理者定義の `company_workspace` という権限プロファイルを用意しています。

このプロファイルでは、Workspace 内の作業は許可しつつ、Workspace 外や共有フォルダへのアクセスを制限します。

## 共有フォルダを守る考え方

共有フォルダは、多くの社員が使う重要な場所です。

Codex が誤って共有フォルダへ書き込むと、次のような問題が起きる可能性があります。

- 他の人のファイルを変更してしまう
- 業務ファイルを削除してしまう
- 誤った資料を共有してしまう
- 社内の重要データを読み取ってしまう

そのため、今回のポリシーでは、UNC 形式の共有フォルダをワイルドカードで拒否しています。

```toml
"\\\\*\\*" = "deny"
"\\\\*\\*\\**" = "deny"
```

これは、次のような共有フォルダをまとめて拒否するための考え方です。

```text
\\server01\share
\\server02\department
\\nas01\common\folder
```

また、mapped drive として共有フォルダを割り当てている会社向けに、`H:\` から `Z:\` までを拒否対象にしています。

mapped drive は見た目が `Z:\` のようになるため、TOML だけではネットワーク共有かローカルディスクかを自動判定できません。

そのため、会社で共有ドライブとして使う文字を決め、不要なドライブ文字は削除してください。

## 重要: 共有フォルダの物理的な禁止は Windows 側でも必要

ここはとても重要です。

Codex の `requirements.toml` は、Codex が行う操作を制限するための設定です。

しかし、共有フォルダそのものを物理的に読み取り専用にする設定ではありません。

つまり、Codex 側で共有フォルダへのアクセスを禁止しても、Windows やファイルサーバー側の権限が書き込み可能なままだと、他のアプリや手作業では書き込めてしまう場合があります。

そのため、共有フォルダへの書き込みを本当に禁止したい場合は、次のような Windows 側の対策も必要です。

- ファイルサーバーのアクセス権限を read-only にする
- Active Directory のグループ権限を見直す
- GPO で共有フォルダ利用を制限する
- Intune などの MDM で端末制御する
- 共有フォルダを Workspace として使わない運用ルールを決める

Codex のポリシーと Windows 側の権限管理は、両方セットで考えるのが安全です。

## Web 検索を cached のみにする理由

Codex の Web 検索には、ライブ検索とキャッシュ検索があります。

ライブ検索を許可すると、Codex がインターネット上の最新ページを検索できるようになります。

会社 PC では、外部通信や情報持ち出しの観点から慎重に扱う必要があります。

そのため、今回のポリシーでは Web 検索を `cached` のみにしています。

これは、自由なライブ検索を避け、OpenAI 側のキャッシュ済み検索だけに制限する考え方です。

なお、検索を完全に無効化する `disabled` は常に許可されます。これは、ユーザーがより安全な方向に倒す操作なので問題ありません。

## MCP を管理者管理にする理由

MCP は、Codex に外部ツールや外部サービスをつなぐ仕組みです。

便利ですが、接続先によっては次のようなリスクがあります。

- 外部サービスに社内情報が渡る
- ユーザーが未承認のツールを追加する
- 社内規定に合わないサービスへ接続する
- 権限の強いツールを Codex から操作できてしまう

そのため、今回のポリシーでは MCP を空の allowlist にしています。

空の allowlist とは、何も許可しないリストという意味です。

必要な MCP がある場合だけ、管理者が内容を確認してから追加します。

## Hooks を管理者管理にする理由

Hooks は、Codex の動作の前後にスクリプトを実行できる仕組みです。

たとえば、コマンド実行前にチェックしたり、作業終了時に検査を走らせたりできます。

ただし、ユーザーが自由に Hooks を追加できると、危険なスクリプトが動く可能性があります。

そのため、今回のポリシーではユーザー、プロジェクト、セッション、plugin の Hooks を無効にし、管理者が配布した managed hooks だけを許可します。

注意点として、`requirements.toml` は hook の設定を強制できますが、hook 用スクリプトそのものを配布する機能ではありません。

hook スクリプトは、MDM やソフトウェア配布ツールで別途 PC に配布する必要があります。

現在の設定ファイルでは、managed hooks の実行先ディレクトリや `SessionStart` hook はまだ有効定義していません。共有フォルダを Workspace として選択した時点で止めたい場合は、管理者が hook ディレクトリ、hook イベント定義、検査スクリプトを別途配布してください。

## 旧クライアント互換の設定

Codex のバージョンが古い場合、新しい permission profile の設定を正しく理解できない可能性があります。

そのため、今回の設定では旧クライアント向けに `allowed_sandbox_modes` も書いています。

旧クライアントでは、安全側に倒すため `read-only` のみ許可しています。

つまり、古い Codex では編集できず、読むだけの状態にします。

これは不便に感じるかもしれませんが、安全性を優先するための設定です。

## 権限昇格を禁止する理由

権限昇格とは、通常ユーザーより強い権限でコマンドを実行することです。

Windows では `Run as administrator`、Linux や macOS では `sudo` のような操作が代表例です。

権限昇格を許すと、Codex が通常より広い範囲を操作できてしまいます。

今回のポリシーでは、次のような操作を禁止しています。

- `sudo`
- `su`
- `runas`
- PowerShell の `Start-Process -Verb RunAs`
- `net use`
- `New-PSDrive`
- `subst`

会社 PC では、Codex に管理者権限を渡さないことが基本です。

また、共有フォルダを後から `Z:\` のような mapped drive に割り当てて回避する操作も禁止します。

## 導入前に置き換える場所

今回の `requirements.company-codex-policy.toml` では、UNC 形式の共有フォルダはワイルドカードで拒否しています。

そのため、通常は `\\server\share` のような共有フォルダ名を一つずつ列挙する必要はありません。

```toml
"\\\\*\\*" = "deny"
"\\\\*\\*\\**" = "deny"
```

ただし、mapped drive は確認が必要です。

今回の設定では、共有ドライブとして使われやすい `H:\` から `Z:\` までを拒否しています。

```toml
"H:\\" = "deny"
"I:\\" = "deny"
"J:\\" = "deny"
# ...
"X:\\" = "deny"
"Y:\\" = "deny"
"Z:\\" = "deny"
```

導入前に、社内で使っているドライブ文字を確認してください。

- 共有ドライブとして使う文字は、拒否対象に残す。
- ローカルディスクとして使う文字は、拒否対象から外す。
- `C:\` や `D:\` までワイルドカードでまとめて拒否すると、通常の作業フォルダまで使えなくなる可能性がある。

## 導入手順

大まかな導入手順は次のとおりです。

1. `requirements.company-codex-policy.toml` を開く。
2. `H:\` から `Z:\` の拒否対象が、自社のドライブ運用と合っているか確認する。
3. `https://chatgpt.com/codex/cloud/settings/policies` を開く。
4. Codex の policy 設定画面に TOML の内容を登録する。
5. 管理対象 PC で Codex を再起動する。
6. テスト用ユーザーで動作確認する。

## 導入後の確認項目

導入後は、最低限次の確認を行ってください。

- `never` を選べないこと
- `danger-full-access` を選べないこと
- Web search で live search を選べないこと
- ユーザー定義 MCP が起動しないこと
- ユーザー定義 Hooks が実行されないこと
- Workspace 内の通常ファイルは編集できること
- Workspace 外のファイルは編集できないこと
- 共有フォルダには書き込めないこと
- 古い Codex クライアントでは read-only になること
- 管理者権限でのコマンド実行が拒否されること

## よくある質問

### Q. この設定だけで共有フォルダへの書き込みは完全に防げますか

Codex からの書き込みを制限するための防御策は入れています。

ただし、TOML だけで共有フォルダそのものを物理的に書き込み禁止にすることはできません。Windows やファイルサーバー側の権限設定も必要です。

### Q. ユーザーが共有フォルダを Workspace に選んだらどうなりますか

UNC 形式の共有フォルダであれば、ワイルドカード deny と `deny_read` により Codex からのアクセスを防御的に制限する方針です。

mapped drive の場合は、`H:\` から `Z:\` など拒否対象に含めたドライブ文字であればアクセスを制限します。

ただし、Workspace として選択する UI 操作そのものを完全に禁止する専用キーは、この設定だけでは明確に用意されていません。

つまり、画面上で選択できてしまう可能性はありますが、Codex がその場所へアクセスする段階で制限する設計です。

より確実に「選択した時点で止める」には、Windows 側の権限制御や、管理者配布の managed hook で Workspace パスを検査する運用が必要です。

### Q. MCP をすべて禁止して大丈夫ですか

最初はすべて禁止で始めるのが安全です。

業務上必要な MCP がある場合だけ、管理者が接続先や権限を確認して追加してください。

### Q. Web search を cached のみにすると不便ですか

最新情報を直接調べる作業では不便になる場合があります。

ただし、会社 PC での情報管理を優先するなら、まずは cached のみにするのが安全です。

### Q. なぜ旧クライアントは read-only にするのですか

古い Codex が新しい安全設定を理解できない可能性があるためです。

誤って広い権限で動かないように、古いクライアントでは編集できない状態にしています。

## 最終的な考え方

Codex の安全対策は、次の 3 層で考えるとわかりやすいです。

```text
1. Codex の policy
   Codex が何をしてよいかを制御する

2. Windows / ファイルサーバーの権限
   共有フォルダやローカル PC の物理的な権限を制御する

3. 社内運用ルール
   どのフォルダを Workspace にしてよいか、誰が MCP を追加してよいかを決める
```

今回の `requirements.company-codex-policy.toml` は、1 番目の Codex policy を強化するための設定です。

共有フォルダや管理者権限のような重要な部分は、2 番目と 3 番目も合わせて整備してください。
