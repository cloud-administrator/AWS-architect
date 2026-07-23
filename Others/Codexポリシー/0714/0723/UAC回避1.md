## 結論

**利用者にUACを通過させるのではなく、IT管理者がCodexのWindowsサンドボックスを事前プロビジョニングする**のが正しい解決策です。

`windows.allowed_sandbox_implementations = ["elevated"]` は、利用者が`unelevated`へ切り替えることを禁止するポリシーであり、Windows側の管理者設定を自動展開するものではありません。`elevated`では、専用の低権限ローカルユーザー、ACL、ファイアウォール、ローカルポリシーなどを作成するため、最初の一度だけ管理者権限が必要です。Codex自体を管理者権限で常用させる設定ではありません。([OpenAI Developers][1])

OpenAIは、この問題に対応する管理者向けコマンドをCodex CLI 0.136.0で追加しています。

```powershell
codex sandbox setup --elevated `
  --user "CONTOSO\alice" `
  --codex-home "C:\Users\alice\.codex"
```

これは、管理者またはIT配布スクリプトが、標準ユーザーの代わりに事前実行することを想定した公式実装です。([GitHub][2])

---

## UACが出ない仕組み

通常のCodex起動時にセットアップが未完了だと、CodexはWindowsの`runas`を使って`codex-windows-sandbox-setup.exe`を起動するため、UACが表示されます。

一方、次の事前プロビジョニングコマンドは、

1. 呼び出し元が既に管理者権限を持っていることを確認する
2. 対象ユーザーを明示してサンドボックスを構成する
3. セットアップ用EXEを追加の昇格要求なしで実行する
4. 対象ユーザーの設定に`windows.sandbox = "elevated"`を保存する

という処理になっています。

つまり、**UACを無効化したり突破したりするのではなく、最初からSYSTEMまたは昇格済み管理者コンテキストで処理する**という設計です。

---

## 少数端末での実行方法

対象ユーザーのWindowsプロファイルが既に存在することを確認し、管理者用PowerShellから、管理対象のCodex実行ファイルを絶対パスで指定して実行します。

```powershell
$CodexExe = "C:\Program Files\OpenAI\Codex\codex.exe"

& $CodexExe sandbox setup --elevated `
  --user "CONTOSO\alice" `
  --codex-home "C:\Users\alice\.codex"

if ($LASTEXITCODE -ne 0) {
    throw "Codex sandbox provisioning failed. ExitCode=$LASTEXITCODE"
}
```

ADユーザーは、原則として`DOMAIN\samAccountName`形式で指定します。公式ソースでも`DOMAIN\alice`形式が想定されています。

### `--current-user`は管理展開では避ける

次のコマンドも存在します。

```powershell
codex sandbox setup --elevated --current-user
```

しかし、標準ユーザーのUAC画面で別の管理者資格情報を入力した場合、昇格後の「現在のユーザー」が管理者アカウントになる可能性があります。管理展開では必ず次を明示してください。

```text
--user "DOMAIN\対象ユーザー"
--codex-home "対象ユーザーの実際のプロファイル\.codex"
```

---

## Intuneでの推奨展開

最も適した方法は、IntuneのWin32アプリまたはPowerShellスクリプトを**Systemコンテキスト**で実行する方法です。

IntuneではWin32アプリのInstall behaviorを`System`にでき、PowerShellインストーラースクリプトも同じSystemコンテキストで実行されます。また、Intuneのインストールは対話型UIを前提にしていないため、UACを利用者に操作させる構成は避ける必要があります。([Microsoft Learn][3])

### 事前プロビジョニング用PowerShell例

以下は、対象ADユーザーのSIDから実際のWindowsプロファイルパスを取得し、SYSTEMまたは管理者権限でセットアップを実行する例です。

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CodexExe,

    [Parameter(Mandatory = $true)]
    [string]$TargetUser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# SYSTEMまたは昇格済み管理者であることを確認
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [System.Security.Principal.WindowsPrincipal]::new($identity)

if (-not $principal.IsInRole(
    [System.Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "This script must run as SYSTEM or from an elevated administrator process."
}

# ユーザー書き込み可能なPATH上のcodex.exeを使わない
if (-not (Test-Path -LiteralPath $CodexExe -PathType Leaf)) {
    throw "Codex executable not found: $CodexExe"
}

# ADアカウントをSIDへ変換
$account = [System.Security.Principal.NTAccount]::new($TargetUser)
$sid = $account.Translate(
    [System.Security.Principal.SecurityIdentifier]
).Value

# 実際のユーザープロファイルパスを取得
$profileKey =
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"

if (-not (Test-Path -LiteralPath $profileKey)) {
    throw "The Windows profile for $TargetUser has not been created yet. Run this after the user's first sign-in."
}

$profilePath = (
    Get-ItemProperty `
        -LiteralPath $profileKey `
        -Name ProfileImagePath
).ProfileImagePath

$profilePath = [Environment]::ExpandEnvironmentVariables($profilePath)

if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) {
    throw "Profile directory not found: $profilePath"
}

$codexHome = Join-Path $profilePath ".codex"

# バージョンを記録
$codexVersion = (& $CodexExe --version 2>&1 | Out-String).Trim()

# 公式の事前プロビジョニングコマンド
& $CodexExe sandbox setup `
    --elevated `
    --user $TargetUser `
    --codex-home $codexHome

if ($LASTEXITCODE -ne 0) {
    throw "Codex sandbox setup failed. ExitCode=$LASTEXITCODE"
}

# セットアップ成果物を確認
$markerPath =
    Join-Path $codexHome ".sandbox\setup_marker.json"

$secretsPath =
    Join-Path $codexHome ".sandbox-secrets\sandbox_users.json"

if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    throw "Setup marker was not created: $markerPath"
}

if (-not (Test-Path -LiteralPath $secretsPath -PathType Leaf)) {
    throw "Sandbox credentials file was not created."
}

# Intune検出用の管理者側スタンプ
$stampDirectory =
    Join-Path $env:ProgramData "OpenAI\Codex\SandboxProvisioning"

New-Item `
    -ItemType Directory `
    -Path $stampDirectory `
    -Force | Out-Null

$marker = Get-Content `
    -LiteralPath $markerPath `
    -Raw | ConvertFrom-Json

$stampPath = Join-Path $stampDirectory "$sid.json"

[pscustomobject]@{
    TargetUser       = $TargetUser
    UserSid          = $sid
    CodexHome        = $codexHome
    CodexVersion     = $codexVersion
    SetupVersion     = $marker.version
    CompletedUtc     = [DateTime]::UtcNow.ToString("o")
} |
    ConvertTo-Json |
    Set-Content -LiteralPath $stampPath -Encoding UTF8

Write-Output "Codex elevated sandbox provisioning completed for $TargetUser."
```

Intuneでは次のような構成にします。

| 項目               | 推奨値                                                          |
| ---------------- | ------------------------------------------------------------ |
| Install behavior | `System`                                                     |
| 実行ホスト            | 64ビットPowerShell                                              |
| ユーザー操作           | 不要                                                           |
| Codex実行ファイル      | 管理者だけが書き換えられる固定パス                                            |
| 対象ユーザー           | IntuneのPrimary Userなどから明示的に渡す                                |
| 実行時期             | 対象ユーザーの初回ログオン後                                               |
| 検出               | `C:\ProgramData\OpenAI\Codex\SandboxProvisioning\<SID>.json` |
| 再実行              | Codexクライアント更新時                                               |

Codex／ChatGPT Windowsアプリ自体も、OpenAIはIntuneなどのMDMによる集中展開を案内しています。([ChatGPT Learn][4])

### 重要なセキュリティ条件

`codex.exe`をSYSTEMで起動するため、次を徹底してください。

* ユーザーの`PATH`から`codex.exe`を検索しない
* `%LOCALAPPDATA%`やユーザー書き込み可能なnpmディレクトリのEXEをSYSTEMで実行しない
* 管理者所有の`Program Files`配下などに固定する
* 配布パッケージの署名またはSHA-256を検証する
* スクリプトも署名し、管理者だけが変更可能な状態で配布する

---

## Active DirectoryのGPOだけで展開する場合

コンピューターのスタートアップスクリプトはLocal Systemアカウントで実行されるため、UAC資格情報を利用者に渡さずにセットアップできます。([Microsoft Learn][5])

ただし、スタートアップ時には対象ユーザーのプロファイルがまだ存在しない場合があります。そのため実際には、次の構成が安定します。

1. コンピュータースタートアップスクリプトで、管理者保護されたセットアップスクリプトを配置する
2. 「ユーザーログオン時」をトリガーとするタスクスケジューラタスクを作成する
3. タスクの実行アカウントを`SYSTEM`、最上位の特権で実行にする
4. ログオンしたADユーザーを特定して、前述のコマンドを一度だけ実行する
5. 成功スタンプがあれば以後スキップする

**通常のユーザーログオンスクリプトとして実行するだけでは、標準ユーザー権限なので解決しません。**

MECM／Configuration Managerがある場合も、Install for systemで同じ方式を採れます。([Microsoft Learn][6])

---

## Policies画面に設定する推奨ポリシー

以下は、比較的厳格な企業向けベースラインです。

```toml
# 承認なしのフルオート実行を禁止
allowed_approval_policies = ["untrusted", "on-request"]

# 旧形式・混在バージョン向けの安全策
allowed_sandbox_modes = ["read-only", "workspace-write"]

# live / indexed検索を禁止。disabledは常に選択可能
allowed_web_search_modes = ["cached"]

# 必要な場合だけ有効化する機能
allow_appshots = false
allow_remote_control = false

# ユーザー、プロジェクト、プラグイン由来のhooksを禁止し、
# 管理者配布のhooksだけを許可
allow_managed_hooks_only = true

# Codex 0.138.0以降
default_permissions = ":workspace"

[allowed_permission_profiles]
":read-only" = true
":workspace" = true
":danger-full-access" = false

[windows]
allowed_sandbox_implementations = ["elevated"]
```

このポリシーでは、

* `danger-full-access`を禁止
* `--yolo`相当の使用を禁止
* `elevated`から`unelevated`へのフォールバックを禁止
* live Web検索を禁止
* リモート操作を禁止
* ユーザーやリポジトリが独自に持ち込むhooksを禁止

します。

OpenAIの管理設定は`requirements.toml`互換で、クラウドからサインイン済みクライアントへ配信されます。OpenAIも、全社展開前に小規模グループで検証するよう案内しています。([OpenAI Developers][7])

`allowed_permission_profiles`と`default_permissions`はCodex 0.138.0以降が必要です。それ以前のクライアントはこの制限を無視するため、混在期間中は`allowed_sandbox_modes`も残すのが安全です。([OpenAI Developers][7])

Web検索を完全禁止する場合は、次のようにします。

```toml
allowed_web_search_modes = []
```

空配列では`disabled`だけが許可されます。([OpenAI Developers][8])

### Windowsの管理コマンドに承認を要求する例

```toml
[rules]
prefix_rules = [
  {
    pattern = [
      {
        any_of = [
          "reg", "reg.exe",
          "sc", "sc.exe",
          "netsh", "netsh.exe",
          "schtasks", "schtasks.exe",
          "bcdedit", "bcdedit.exe",
          "diskpart", "diskpart.exe"
        ]
      }
    ],
    decision = "prompt",
    justification = "Windowsのシステム、サービス、ネットワーク、タスク設定の変更には明示承認が必要です"
  }
]
```

ただし、コマンドルールはフルパス、別名、ラッパー経由などをすべて捕捉するものではありません。主たるセキュリティ境界はサンドボックスとPermission Profileであり、ルールは補助的な統制として扱うべきです。

---

## 端末側にも同じポリシーを配る

クラウドポリシーに加えて、重要な制約を次のファイルにも配布すると、端末単位の防御になります。

```text
%ProgramData%\OpenAI\Codex\requirements.toml
```

Windowsのシステム`requirements.toml`とクラウド管理要件は、Codexクライアント上で管理者強制レイヤーとして合成されます。([OpenAI Developers][7])

ただし、展開順序は次にしてください。

1. Codexアプリ／CLIを展開
2. `elevated`サンドボックスを事前プロビジョニング
3. 標準ユーザーで動作確認
4. ローカル`requirements.toml`を配布
5. クラウドPoliciesを割り当て

先に`elevated`強制ポリシーだけを配ると、未プロビジョニング端末でUACが表示されます。

---

## バージョン管理が重要

事前プロビジョニングコマンドはCodex CLI 0.136.0で追加されました。Permission Profileの強制には0.138.0以降が必要です。2026年7月22日時点の最新CLIは0.145.0で、Windowsサンドボックスの信頼性改善も含まれています。([GitHub][2])

ただし、企業展開では単純に最新へ即日更新するのではなく、

* パイロットリング
* 検証リング
* 本番リング

に分けてください。

Codexは、現在の実行ファイルが期待するセットアップバージョンと、ユーザーの`.codex`内にあるセットアップマーカーのバージョンが一致するかを確認しています。一致しない場合、再び管理者セットアップを要求します。

したがって、

> **Codexクライアントを更新したら、同じバージョンの`codex.exe sandbox setup --elevated`をSYSTEMで再実行する**

という更新処理をパッケージに含めてください。

なお、この事前プロビジョニング機能はリリース上「alpha」とされており、OpenAIの実装説明でも、将来の管理者権限付き更新を自動調整する仕組みまでは対象外とされています。

---

## 共有PC・複数ユーザー端末の重要な注意

現行実装では、サンドボックス用ローカルアカウント名は端末全体で固定されています。

```text
CodexSandboxOffline
CodexSandboxOnline
CodexSandboxUsers
```

さらに、事前プロビジョニングのたびにランダムパスワードを生成し、その対象ユーザーの`CODEX_HOME`に暗号化して保存します。

この実装から判断すると、**同じPCでユーザーAをプロビジョニングした後にユーザーBをプロビジョニングすると、共通のサンドボックスアカウントのパスワードが更新され、ユーザーA側の保存済み資格情報が古くなる可能性があります。** ログオン失敗時には資格情報ファイルを削除して再セットアップへ進む実装です。

これは現行ソースからの推定ですが、共有端末では次の扱いが安全です。

* 原則として1端末1プライマリユーザー
* 共用PCへの全社展開は、OpenAIに複数ユーザー対応を確認してから
* ユーザー交代時には新ユーザー向けに再プロビジョニング
* 旧ユーザーが引き続き利用する前提にしない

---

## 管理者資格情報について

Domain Adminアカウントを各ユーザーPCのUAC画面に入力する運用は避けてください。Microsoftの管理階層モデルでも、Domain AdminなどのTier 0アカウントは標準ユーザーのワークステーションへログオンさせない構成が推奨されています。([Microsoft Learn][9])

推奨順は次のとおりです。

1. Intune／MECM／GPOからSYSTEM実行
2. 専用の端末管理者アカウント
3. Windows LAPSで管理された端末固有のローカル管理者
4. Domain Adminは使用しない

Windows LAPSは、端末ごとのローカル管理者パスワードを自動管理・バックアップする仕組みです。([Microsoft Learn][10])

---

## 実施してはいけない方法

以下は避けてください。

* UACを無効化する
* 管理者ID・パスワードを利用者に渡す
* スクリプトや構成ファイルに管理者パスワードを平文保存する
* `runas /savecred`を使う
* Domain Admin資格情報をユーザーPC上で入力する
* `powershell.exe`や`cmd.exe`全体を自動昇格対象にする
* ユーザー書き込み可能な場所の`codex.exe`をSYSTEM実行する
* `codex-windows-sandbox-setup.exe`を直接実行する

特に最後の点について、このセットアップEXEは内部生成されたBase64ペイロードを1個だけ受け取り、Codex本体とセットアップバージョンが一致することを確認する内部ヘルパーです。直接実行する一般向けインストーラーではありません。

必ず次の公式CLI入口を使用してください。

```text
codex sandbox setup --elevated ...
```

---

## エラー別の確認箇所

| 症状           | 主な原因                      | 対処                        |
| ------------ | ------------------------- | ------------------------- |
| 初回起動でUACが出る  | 事前プロビジョニング未実施             | SYSTEMでセットアップコマンドを実行      |
| 更新後にUACが再発   | CLIとセットアップマーカーのバージョン不一致   | 更新後に再プロビジョニング             |
| エラー1385      | サンドボックスユーザーのログオン種別がGPOで拒否 | User Rights Assignmentを確認 |
| ローカルユーザー作成失敗 | GPO、EDR、端末管理製品が作成を禁止      | Codex用アカウント／グループの例外を検討    |
| ファイアウォール設定失敗 | Firewall、WFP、EDRによる制限     | OpenAI署名済みヘルパーと必要な変更を許可   |
| 何度もセットアップを要求 | 対象ユーザーまたはCODEX_HOMEが誤っている | SIDとProfileImagePathから再取得 |
| 別ユーザー導入後に失敗  | 共通サンドボックスアカウントの資格情報更新     | 共有PC運用を再検討                |

OpenAIの公式資料でも、UAC拒否、ローカルユーザー／グループ作成禁止、ファイアウォール変更禁止、ログオン権限、その他の企業ポリシーが主な失敗原因として挙げられています。([OpenAI Developers][1])

エラー1385は、サンドボックスユーザーに必要なログオン種別をWindowsポリシーが拒否している状態です。([OpenAI Developers][1])

ログは次で確認できます。

```text
%USERPROFILE%\.codex\.sandbox\sandbox.log
```

一方、次のディレクトリの内容は収集・送信しないでください。

```text
%USERPROFILE%\.codex\.sandbox-secrets\
```

OpenAIも、診断時に`.sandbox-secrets`を送らないよう明記しています。([OpenAI Developers][1])

---

## 最終的な推奨構成

企業管理PCでは、次の構成が最も安全です。

1. Windows 11の管理端末を標準とする
2. Codex／ChatGPTアプリとCLIをIntuneで配布する
3. CLIを管理者保護された固定パスに置く
4. 対象ユーザーの初回ログオン後、SYSTEMで事前プロビジョニングする
5. 成功後にクラウドPoliciesで`elevated`のみを許可する
6. `danger-full-access`を禁止する
7. 必要に応じてWeb、Appshots、リモート操作、hooksを制限する
8. Codex更新時にプロビジョニングを再実行する
9. Domain Admin資格情報をユーザーPCに入力しない
10. まず少数端末で、UAC非表示、ネットワーク制御、ファイルACL、エラー1385の有無を確認する

OpenAIは企業標準化ではWindows 11を推奨し、`unelevated`は別サンドボックスユーザー境界を持たず、ネットワーク分離も弱い一時的なフォールバックとして位置付けています。([OpenAI Developers][1])

[1]: https://developers.openai.com/codex/windows/windows-sandbox "https://developers.openai.com/codex/windows/windows-sandbox"
[2]: https://github.com/openai/codex/releases/tag/rust-v0.136.0 "https://github.com/openai/codex/releases/tag/rust-v0.136.0"
[3]: https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32 "https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32"
[4]: https://learn.chatgpt.com/codex/enterprise/windows-deployment "https://learn.chatgpt.com/codex/enterprise/windows-deployment"
[5]: https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn789190%28v%3Dws.11%29 "https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn789190%28v%3Dws.11%29"
[6]: https://learn.microsoft.com/bs-latn-ba/intune/configmgr/apps/deploy-use/create-applications "https://learn.microsoft.com/bs-latn-ba/intune/configmgr/apps/deploy-use/create-applications"
[7]: https://developers.openai.com/codex/enterprise/managed-configuration "https://developers.openai.com/codex/enterprise/managed-configuration"
[8]: https://developers.openai.com/codex/config-reference "https://developers.openai.com/codex/config-reference"
[9]: https://learn.microsoft.com/hi-in/microsoft-identity-manager/pam/tier-model-for-partitioning-administrative-privileges "https://learn.microsoft.com/hi-in/microsoft-identity-manager/pam/tier-model-for-partitioning-administrative-privileges"
[10]: https://learn.microsoft.com/en-us/windows-server/identity/laps/laps-overview "https://learn.microsoft.com/en-us/windows-server/identity/laps/laps-overview"
