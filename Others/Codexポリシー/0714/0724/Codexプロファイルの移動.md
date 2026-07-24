# 調査結果

**2026年7月24日時点では、`CODEX_HOME=C:\Users\Public` をCLI・IDE拡張・Windowsデスクトップアプリの共通ホームとして全社展開する方針は推奨できません。**

推奨構成は次のとおりです。

```text
Codexの実行ファイル・セットアップ用CLI：
  管理者のみ書き込み可能な領域
  例：C:\Program Files\OpenAI\Codex
      C:\ProgramData\OpenAI\Codex\PackageCache

各ユーザーのCodex状態：
  C:\Users\<ユーザー>\.codex

管理ポリシー：
  %ProgramData%\OpenAI\Codex\requirements.toml
  ＋
  Codexクラウド管理ポリシー

elevated sandboxの事前セットアップ：
  SKYSEAのSYSTEM権限から、
  対象ユーザーの C:\Users\<ユーザー>\.codex を明示して1回実行
```

重要なのは、**管理者用のCodex CLIと、ユーザーの `CODEX_HOME` を分離すること**です。

---

## 1. 各クライアントで `C:\Users\Public` が使えるか

| クライアント           | `CODEX_HOME` 対応 |   `C:\Users\Public` 共通化 | 判定   |
| ---------------- | --------------: | ----------------------: | ---- |
| Codex CLI        |            公式対応 |                 技術的には可能 | 条件付き |
| Codex IDE拡張      |            公式対応 | ネイティブWindows実行なら技術的には可能 | 条件付き |
| Windowsデスクトップアプリ | 公式な対応対象に含まれていない |             安定して共通化できない | 非推奨  |
| 3クライアントすべて       |           一貫しない |         同じホームを確実に参照できない | 不採用  |

公式の環境変数一覧では、`CODEX_HOME` の利用主体は「CLI、IDE拡張、app-server、インストーラー」とされており、Windowsデスクトップアプリは含まれていません。また、Windowsアプリの公式説明は保存先を `%USERPROFILE%\.codex` としています。 ([OpenAI Developers][1])

さらに、2026年7月18日に登録された未解決Issueでは、Windowsアプリが `CODEX_HOME` を無視して `%USERPROFILE%\.codex` を使うことが報告されています。これは正式な製品仕様ではなくユーザー報告ですが、公式ドキュメントの記載とも整合しています。ジャンクションは回避策として挙げられているものの、アプリでサポートされた構成ではありません。 ([GitHub][2])

したがって、次の構成になる可能性があります。

```text
CLI／IDE拡張：
C:\Users\Public

Windowsデスクトップアプリ：
C:\Users\alice\.codex
```

このホーム分裂は、単に設定や履歴が分かれるだけでなく、**elevated sandboxの資格情報を壊す可能性があります。**

---

# 2. `codex sandbox setup` はUACを「突破」するものではない

使用予定のコマンドは、企業配布を想定した正しい方向性です。

```powershell
codex sandbox setup `
  --elevated `
  --user 'CONTOSO\alice' `
  --codex-home 'C:\Users\alice\.codex'
```

ただし、これはUACを回避するコマンドではありません。

このコマンドは、**呼び出し元プロセスがすでに管理者権限またはSYSTEM権限を持っていることを前提**としています。一般ユーザーの非昇格プロセスから実行すると、明示的にエラーになります。SKYSEAの管理エージェントがSYSTEM権限で起動することで、対話的UACを出さずに管理者承認済みのセットアップを行う構成です。

また、`--user` は対象ユーザーのIDとパスワードでログインするオプションではありません。対象Windowsアカウントを特定し、そのSIDをサンドボックス関連ファイルのACLに設定するために使われます。したがって、対象ユーザーのパスワードやドメイン管理者パスワードをスクリプトに埋め込む必要はありません。

`elevated` という名称も、Codexが管理者としてコマンドを実行するという意味ではありません。管理者権限が必要なのは初期セットアップであり、実際のコマンドは専用の低権限サンドボックスユーザーとして実行されます。公式ドキュメントでは、専用低権限ユーザー、ACL、ファイアウォール、ローカルポリシーを使用する、より強いWindowsサンドボックスとして説明されています。 ([OpenAI Developers][3])

---

# 3. 異なる `CODEX_HOME` に対して複数回セットアップすると問題が起きる

これは今回の構成で最も重要な問題です。

## elevated sandboxが作成するアカウント

現行の公開実装では、次の固定名のローカルアカウントが作成されます。

```text
CodexSandboxOffline
CodexSandboxOnline
```

セットアッププロトコルの現行ソース上のバージョンは `5` です。

セットアップを実行するたびに、2アカウント用の新しいランダムパスワードが生成されます。アカウントが既に存在する場合、`NetUserSetInfo` によってそのパスワードが更新されます。生成されたパスワードは、指定された `CODEX_HOME` の次のファイルへ暗号化して保存されます。

```text
<CODEX_HOME>\.sandbox-secrets\sandbox_users.json
```

## 異なるホームへセットアップした場合

例えば次の順序でセットアップしたとします。

```text
1回目：
C:\Users\Public

保存されたパスワード：
Password-A
```

```text
2回目：
C:\Users\alice\.codex

同じローカルアカウントのパスワードをPassword-Bへ変更
保存されたパスワード：
Password-B
```

この時点で、

```text
C:\Users\Public\.sandbox-secrets\sandbox_users.json
```

には古い `Password-A` が残ります。しかしWindows上の実際のアカウントは `Password-B` です。

その結果、先に設定したホームを参照するCLIまたはIDE拡張では、以下が発生し得ます。

* サンドボックスユーザーでのログオン失敗
* `CreateProcessWithLogonW` 関連エラー
* サンドボックスセットアップの再要求
* UACの再表示
* CLIでは動くがデスクトップアプリでは動かない、またはその逆
* クライアント起動順によって動作が変わる

この問題は、PCへログインする人が1人だけでも発生します。競合するのは人間のユーザーではなく、**CLI用ホームとデスクトップアプリ用ホーム**だからです。

したがって、企業構成としては、

> 1台のPCでは、すべてのネイティブWindowsクライアントが同じ `CODEX_HOME` を使用し、elevatedセットアップもその同じホームに対してのみ実行する

という設計が必要です。

現状では、3クライアントすべてが確実に参照するホームは、既定の次のパスです。

```text
%USERPROFILE%\.codex
```

---

# 4. `C:\Users\Public` を使うセキュリティ上の問題

固定ユーザー1人であることは同時利用上の競合を減らしますが、Public配下を安全にするものではありません。

## 4.1 認証・ログ・セッションもPublic配下になる

`CODEX_HOME` には、サンドボックス関連ファイルだけでなく、以下が格納されます。

* `config.toml`
* 認証情報
* セッション
* ログ
* 履歴
* スキル
* SQLite状態
* キャッシュ
* プラグイン関連データ
* スタンドアロンCLIのパッケージメタデータ

これは公式の `CODEX_HOME` 定義に含まれています。 ([OpenAI Developers][1])

特に `CODEX_HOME=C:\Users\Public` と指定すると、`.codex` サブディレクトリではなく、PublicフォルダそのものがCodexホームになります。

```text
C:\Users\Public\config.toml
C:\Users\Public\auth.json
C:\Users\Public\sessions
C:\Users\Public\logs
C:\Users\Public\packages
C:\Users\Public\.sandbox-secrets
```

企業PCでは避けるべき構成です。

## 4.2 CLIパッケージと昇格用EXEもPublic配下に置かれ得る

公式スタンドアロンインストーラーでは、`CODEX_INSTALL_DIR` を変更しても、実際のパッケージキャッシュは次に残ります。

```text
CODEX_HOME\packages\standalone
```

つまり、`CODEX_HOME=C:\Users\Public` でインストールすると、CLI本体や `codex-windows-sandbox-setup.exe` を含むパッケージがPublic配下に格納される可能性があります。 ([OpenAI Developers][1])

スタンドアロンパッケージの構成では、`codex-windows-sandbox-setup.exe` が必須ファイルとして含まれています。

現在の公開実装では、実行中の `codex.exe` を基準として、同じディレクトリまたは隣接する `codex-resources` ディレクトリからセットアップEXEを検索します。

そのため、Public配下が一般ユーザーまたは別プロセスから書き換え可能な状態で、そこにあるCLIをSYSTEM権限でSKYSEAから実行すると、**ユーザー書き込み可能な実行ファイルをSYSTEM権限で起動する設計**になり得ます。これは現在ログインする人が1人かどうかとは関係なく、ローカル権限昇格につながり得る危険な信頼境界です。

公開実装上、この起動経路は相対位置からEXEを見つけて実行しており、起動直前に毎回SHA-256や署名を検証する処理は確認できません。したがって、昇格セットアップに使用するCLIとヘルパーは、必ず管理者またはSYSTEMのみが書き込み可能な領域に置くべきです。

## 4.3 セットアップが保護するのは一部のサブディレクトリだけ

セットアップ処理は、次のディレクトリについて専用ACLを設定します。

```text
<CODEX_HOME>\.sandbox
<CODEX_HOME>\.sandbox-bin
<CODEX_HOME>\.sandbox-secrets
```

しかし、`CODEX_HOME` 直下全体や、認証、セッション、ログ、パッケージ全体を同じ方法で保護するわけではありません。

そのため、Publicフォルダの親ACLが広ければ、サンドボックス秘密情報以外のCodexデータはその広い権限を継承する可能性があります。

公式ドキュメントも、`Everyone` が書き込み可能なフォルダがある場合、サンドボックスの保護が十分に機能しない可能性があると警告しています。 ([OpenAI Developers][3])

## 4.4 DPAPIがマシンスコープ

サンドボックスユーザーのパスワードはDPAPIで暗号化されますが、実装では `CRYPTPROTECT_LOCAL_MACHINE`、つまりマシンスコープが使われています。SYSTEMで生成し、一般ユーザーのCodexプロセスで復号できるのはこのためです。

この方式では、暗号化ファイルのアクセス制御にACLが特に重要です。`.sandbox-secrets` をSKYSEAで収集したり、ログ収集サーバーへコピーしたりしないでください。公式ドキュメントも `.sandbox-secrets` の内容を診断情報として送信しないよう明記しています。 ([OpenAI Developers][3])

---

# 5. 各クライアントは同じ `codex-windows-sandbox-setup.exe` を使うのか

## 結論

**同じファイル名ではありますが、PC全体で1つの共通EXEを使う設計ではありません。**

各クライアントは、原則として自分自身に同梱されている `codex-windows-sandbox-setup.exe` を使います。

```text
CLI
  └─ CLIに同梱されたsetup.exe

IDE拡張
  └─ IDE拡張に同梱されたsetup.exe

Windowsデスクトップアプリ
  └─ デスクトップアプリまたはキャッシュされたランタイムに同梱されたsetup.exe
```

公開実装では、現在実行中の `codex.exe` の場所から、次の順序で関連EXEを探索します。

1. `codex.exe` と同じディレクトリ
2. `codex.exe` が `bin` 配下なら、親パッケージの `codex-resources`
3. `codex.exe` の隣の `codex-resources`

したがって、どのクライアントから実行したかによって、使われるセットアップEXEも変わります。

## 一般的な格納場所

| クライアント        | 代表的な格納場所                                                                                                                    |
| ------------- | --------------------------------------------------------------------------------------------------------------------------- |
| スタンドアロンCLI    | `%CODEX_HOME%\packages\standalone\current\codex-resources\codex-windows-sandbox-setup.exe`                                  |
| IDE拡張         | `%USERPROFILE%\.vscode\extensions\openai.chatgpt-<version>-win32-x64\bin\windows-x86_64\codex-windows-sandbox-setup.exe` など |
| Cursor        | `%USERPROFILE%\.cursor\extensions\openai.chatgpt-<version>-universal\bin\windows-x86_64\codex-windows-sandbox-setup.exe` など |
| Windowsデスクトップ | `C:\Program Files\WindowsApps\OpenAI.Codex_<version>...\` 配下、または `%LOCALAPPDATA%\OpenAI\Codex\bin\<hash>\` 配下               |

IDE拡張が独自にバンドルしたCodex CLIとセットアップEXEを利用することは、過去に拡張パッケージへセットアップEXEが含まれていなかったことでWindows sandboxが失敗したIssueからも確認できます。 ([GitHub][4])

Windowsデスクトップアプリでは、WindowsApps内のパッケージに加え、`%LOCALAPPDATA%\OpenAI\Codex\bin\<hash>` に展開されたコピーが使われた事例も報告されています。 ([GitHub][5])

したがって、パスベースのAppLocker／WDACルールを作る場合、バージョン番号やコンテンツハッシュによってパスが変わる点に注意が必要です。利用可能な場合は、承認済み発行元、署名、パッケージID、または社内で管理したハッシュを基準にする方が安定します。

---

# 6. バージョンは同じか

バージョンも、**同じである保証はありません。**

次の3種類を区別する必要があります。

## 6.1 クライアントの製品バージョン

```text
CLIバージョン
IDE拡張バージョン
Windowsデスクトップアプリバージョン
```

これらは別々です。

## 6.2 セットアップEXEのビルド

各クライアントへ同梱されたCodexランタイムのビルドに対応します。

CLIとIDE拡張が同時期に同じCodexコアを採用していれば、バイナリが同じ可能性はあります。しかし、それは保証された共有関係ではありません。

WindowsデスクトップアプリのIssueでは、WindowsApps側のセットアップEXEとAppDataキャッシュ側のセットアップEXEが同一SHA-256だった事例がありますが、これはその特定バージョンで同じだったという観測にすぎません。 ([GitHub][6])

## 6.3 セットアッププロトコルバージョン

現行公開ソースでは、

```rust
SETUP_VERSION = 5
```

です。セットアップEXEは、受け取ったペイロードのバージョンが一致しない場合にエラーにします。

ただし、

```text
setup_marker.json の version が同じ
```

ことは、

```text
EXEがバイト単位で同一
```

であることを意味しません。

正確に同一ファイルか判定するにはSHA-256を比較してください。

## 6.4 手動でEXEを統一しない

次の対応は推奨できません。

* CLIのセットアップEXEをIDE拡張へコピーする
* 最新版のセットアップEXEをWindowsAppsのものと置換する
* 1つのセットアップEXEを共有フォルダに置いて全クライアントから直接実行する
* `codex-windows-sandbox-setup.exe --version` を直接実行する

セットアップEXEはペイロードを受け取る内部ヘルパーで、直接利用する公開CLIではありません。必ず対応する `codex.exe` から呼び出してください。

---

# 7. 事前セットアップ後も各クライアントのEXEは使用される

SKYSEAで事前セットアップを行えば、以後 `codex-windows-sandbox-setup.exe` が一切使われなくなるわけではありません。

処理には大きく2種類あります。

```text
管理者による初期プロビジョニング
  ・ローカルサンドボックスユーザー作成
  ・パスワード設定
  ・ファイアウォール設定
  ・基本ACL設定
  ・セットアップマーカー作成
```

```text
通常実行時のsetup refresh
  ・現在のワークスペースに対するACL更新
  ・読み取り／書き込みルート調整
  ・ランタイムパスの読み取り権限調整
```

通常実行時のrefreshは、UACを要求せず、各クライアントに同梱されたセットアップEXEを使って実行されます。

したがって、初期セットアップをCLIから行っても、

* IDE拡張はIDE拡張側のヘルパー
* Windowsデスクトップアプリはアプリ側のヘルパー

を引き続き必要とします。

企業環境では、次の双方を確認する必要があります。

1. 管理者プロビジョニングに使うCLIとヘルパーが保護されていること
2. 各クライアントの実行時ヘルパーがEDR、AppLocker、WDAC、UAC互換性検出によってブロックされないこと

Windowsデスクトップでは、非昇格refresh時にOSエラー740やWindowsAppsのACL更新失敗が発生したという最近のIssueもあるため、全社展開前の実機パイロットは必須です。 ([GitHub][5])

---

# 8. 推奨する企業向け構成

## 8.1 ランタイムの `CODEX_HOME`

マシン環境変数として `CODEX_HOME` を設定しません。

全クライアントで既定値を使用します。

```text
C:\Users\alice\.codex
```

これにより、ネイティブWindowsのCLI、IDE拡張、Windowsデスクトップアプリが同じホームを参照できます。 ([OpenAI Developers][1])

IDEがWSL、Remote SSH、Dev Containerで動いている場合は別環境です。その環境にはWindows elevated sandboxの設定は適用されません。

## 8.2 管理用CLIの配置

管理用CLIは、一般ユーザーが書き換えられない場所へ配置します。

```text
C:\Program Files\OpenAI\Codex\bin
```

パッケージキャッシュも保護された場所へ配置します。

```text
C:\ProgramData\OpenAI\Codex\PackageCache
```

公式スタンドアロンインストーラーをSYSTEMから実行する際は、プロセス内だけ次のように設定します。

```powershell
$packageCache = 'C:\ProgramData\OpenAI\Codex\PackageCache'
$installDir   = 'C:\Program Files\OpenAI\Codex\bin'

New-Item -ItemType Directory -Path $packageCache -Force | Out-Null
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

# インストーラー実行プロセスだけに設定する
$env:CODEX_HOME = $packageCache
$env:CODEX_INSTALL_DIR = $installDir
$env:CODEX_NON_INTERACTIVE = '1'

# この後、社内承認済みの公式インストーラーを実行
```

重要なのは、これを**マシン環境変数として永続化しないこと**です。

```text
インストール時CODEX_HOME：
C:\ProgramData\OpenAI\Codex\PackageCache

実行時CODEX_HOME：
未設定 → C:\Users\<ユーザー>\.codex
```

`CODEX_INSTALL_DIR` を指定しても、パッケージキャッシュはインストール時の `CODEX_HOME\packages\standalone` に残るため、両方のACLを保護してください。 ([OpenAI Developers][1])

---

# 9. SKYSEAでの推奨セットアップ処理

`C:\Users\alice` を文字列で固定するのではなく、対象ADユーザーのSIDから実際のプロファイルパスを取得する方が安全です。環境によっては、プロファイル名が次のようになるためです。

```text
C:\Users\alice.CONTOSO
C:\Users\alice.000
```

次はSYSTEM権限で実行する想定の構成例です。

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetUser,

    [string]$CodexExe = 'C:\Program Files\OpenAI\Codex\bin\codex.exe'
)

$ErrorActionPreference = 'Stop'

# 管理者またはSYSTEMであることを確認
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw 'この処理は管理者またはSYSTEM権限で実行する必要があります。'
}

if (-not (Test-Path -LiteralPath $CodexExe -PathType Leaf)) {
    throw "承認済みCodex CLIが見つかりません: $CodexExe"
}

# ここで社内承認済みSHA-256またはデジタル署名を照合すること
# Get-FileHash -LiteralPath $CodexExe -Algorithm SHA256
# Get-AuthenticodeSignature -LiteralPath $CodexExe

# ADアカウント名からSIDを取得
$account = [Security.Principal.NTAccount]::new($TargetUser)
$sid = $account.Translate(
    [Security.Principal.SecurityIdentifier]
).Value

# 実際のWindowsプロファイルパスを取得
$profileKey =
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"

if (-not (Test-Path -LiteralPath $profileKey)) {
    throw "対象ユーザーのWindowsプロファイルが未作成です: $TargetUser"
}

$profilePath = Get-ItemPropertyValue `
    -LiteralPath $profileKey `
    -Name 'ProfileImagePath'

$profilePath =
    [Environment]::ExpandEnvironmentVariables($profilePath)

$codexHome = Join-Path $profilePath '.codex'

New-Item -ItemType Directory -Path $codexHome -Force | Out-Null

# elevated sandboxを対象ホームへプロビジョニング
& $CodexExe `
    sandbox setup `
    --elevated `
    --user $TargetUser `
    --codex-home $codexHome

if ($LASTEXITCODE -ne 0) {
    throw "Codex sandbox setupに失敗しました。終了コード: $LASTEXITCODE"
}

$markerPath =
    Join-Path $codexHome '.sandbox\setup_marker.json'

$secretsPath =
    Join-Path $codexHome '.sandbox-secrets\sandbox_users.json'

if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    throw "セットアップマーカーがありません: $markerPath"
}

if (-not (Test-Path -LiteralPath $secretsPath -PathType Leaf)) {
    throw "サンドボックス資格情報ファイルがありません: $secretsPath"
}

Write-Output "Codex elevated sandbox setup completed."
Write-Output "Target user : $TargetUser"
Write-Output "CODEX_HOME : $codexHome"
Write-Output "Marker      : $markerPath"
```

### 実行条件

この処理は次の条件を満たしてから実行してください。

* 対象ユーザーのWindowsプロファイルが既に作成されている
* PCがドメインアカウントを解決できる
* 管理用CLIが一般ユーザーから書き換えられない
* `CodexSandboxOffline` と `CodexSandboxOnline` の作成をGPOが許可している
* ローカルグループ作成が許可されている
* ファイアウォールルール変更が許可されている
* サンドボックスユーザーに必要なログオン権限をGPOが拒否していない
* EDRがヘルパー起動やACL変更をブロックしていない

Windows 11が企業導入の推奨ベースラインです。公式ドキュメントでも、ローカルユーザー／グループ作成、ファイアウォール変更、ログオン権限が企業ポリシーでブロックされるとelevated setupが失敗するとされています。 ([OpenAI Developers][3])

---

# 10. 推奨する管理ポリシー

クラウド管理ポリシーだけでなく、次のシステムポリシーも配布することを推奨します。

```text
%ProgramData%\OpenAI\Codex\requirements.toml
```

クラウドポリシーは、ユーザーがChatGPTへサインインして対象ワークスペースとして識別された後に取得されます。システムの `requirements.toml` はそれより低い優先順位ですが、サインイン前や初回起動時の基本ポリシーとして機能します。クラウドポリシーは有効な署名済みキャッシュがなく取得にも失敗した場合、ポリシーなしで起動せずエラーになります。 ([ChatGPT Learn][7])

## Codex 0.138.0以降向けの例

```toml
# approval_policy="never" を許可しない
allowed_approval_policies = ["untrusted", "on-request"]

# 既定はワークスペースアクセス
default_permissions = ":workspace"

# 端末のリモート制御を禁止
allow_remote_control = false

# 画面キャプチャ系機能を利用しない会社ではfalse
allow_appshots = false

# ユーザー、プロジェクト、プラグイン由来のhookを禁止し、
# 管理者配布hookだけを許可
allow_managed_hooks_only = true

# Full accessを許可しない
[allowed_permission_profiles]
":read-only" = true
":workspace" = true

# Windowsでは強いサンドボックスだけを許可
[windows]
allowed_sandbox_implementations = ["elevated"]
```

この構成では、

* `danger-full-access` を許可しない
* `approval_policy = "never"` を許可しない
* `unelevated` へフォールバックさせない
* デバイスのリモート制御を禁止
* Appshotsを禁止
* 非管理hookを禁止

という、比較的厳しい企業向け構成になります。

`allowed_permission_profiles` と `default_permissions` はCodex 0.138.0以降が必要です。0.137.0以前ではこれらが無視されるため、管理対象クライアントを0.138.0以上へ統一してから使用してください。 ([ChatGPT Learn][7])

## 旧バージョン用

0.137.0以前が混在する期間は、プロファイル制御の代わりに次を使用します。

```toml
allowed_approval_policies = ["untrusted", "on-request"]
allowed_sandbox_modes = ["read-only", "workspace-write"]

allow_remote_control = false
allow_appshots = false
allow_managed_hooks_only = true

[windows]
allowed_sandbox_implementations = ["elevated"]
```

ただし、クライアントやバージョンによって対応するrequirementsキーが異なる可能性があるため、公式ドキュメントも小規模グループでのパイロットを求めています。 ([ChatGPT Learn][7])

`allowed_sandbox_implementations = ["elevated"]` は、elevatedセットアップが壊れた場合に `unelevated` へ逃げることを禁止します。これはセキュリティ上はfail-closedですが、セットアップに問題があるPCではCodex自体が利用できなくなるため、事前検証が必要です。 ([OpenAI Developers][8])

---

# 11. EXEのパス・バージョン・同一性を確認する方法

次のPowerShellで、PC内にあるセットアップEXEを列挙できます。

```powershell
$roots = @(
    'C:\ProgramData\OpenAI\Codex',
    'C:\Program Files\OpenAI\Codex',
    'C:\Program Files\WindowsApps',
    "$env:LOCALAPPDATA\OpenAI\Codex",
    "$env:LOCALAPPDATA\Programs\OpenAI\Codex",
    "$env:USERPROFILE\.vscode\extensions",
    "$env:USERPROFILE\.vscode-insiders\extensions",
    "$env:USERPROFILE\.cursor\extensions"
) | Where-Object { Test-Path -LiteralPath $_ }

$results = foreach ($root in $roots) {
    Get-ChildItem `
        -LiteralPath $root `
        -Filter 'codex-windows-sandbox-setup.exe' `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue |
    ForEach-Object {
        $signature = Get-AuthenticodeSignature -LiteralPath $_.FullName
        $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256

        [pscustomobject]@{
            Path           = $_.FullName
            FileVersion    = $_.VersionInfo.FileVersion
            ProductVersion = $_.VersionInfo.ProductVersion
            SHA256         = $hash.Hash
            Signature      = $signature.Status
            Signer         = $signature.SignerCertificate.Subject
        }
    }
}

$results |
    Sort-Object Path -Unique |
    Format-Table -AutoSize
```

判断基準は次のとおりです。

```text
SHA-256が同じ
  → バイト単位で同じEXE

FileVersionだけ同じ
  → 同じEXEとは限らない

setup_marker.jsonのversionが同じ
  → セットアッププロトコル互換
  → 同じEXEとは限らない
```

実際にどのヘルパーが起動されたかは、サンドボックスログから確認できます。

```powershell
$codexHome = "$env:USERPROFILE\.codex"

Select-String `
    -Path "$codexHome\.sandbox\sandbox.log" `
    -Pattern 'setup refresh: spawning|setup orchestrator' `
    -ErrorAction SilentlyContinue
```

ただし、サンドボックスログにはワークスペースパスやコマンド情報が含まれ得るため、SKYSEAで一律収集する場合は情報管理上の取り扱いを定めてください。

---

# 12. 全社展開前に必要なテスト

少なくとも次のテストを、実際のGPO、EDR、AppLocker／WDAC、プロキシ環境を適用したパイロットPCで実施してください。

1. SKYSEAのSYSTEM権限でセットアップし、UACが表示されないこと
2. 一般ユーザーでCLIを起動し、簡単なサンドボックスコマンドが実行できること
3. IDE拡張から同じ操作ができること
4. Windowsデスクトップアプリから同じ操作ができること
5. 3クライアントを順番に起動しても資格情報が壊れないこと
6. PC再起動後も動作すること
7. CLIだけを更新した場合に動作すること
8. IDE拡張だけを更新した場合に動作すること
9. Windowsデスクトップアプリだけを更新した場合に動作すること
10. サンドボックス内の `whoami` が想定するCodexSandboxユーザーになること
11. ワークスペース外への書き込みが拒否されること
12. ネットワークアクセスが設定した権限プロファイルどおりになること
13. Windowsエラー1385が発生しないこと
14. `.sandbox-secrets` のACLに不要なユーザーが含まれないこと
15. 更新後に新たなUACやsetup refreshエラーが発生しないこと

特にクライアント更新後の確認が重要です。各クライアントが異なるCodexコア／ヘルパーを同梱できるため、1つのクライアント更新だけでセットアッププロトコルや実行時ヘルパーの挙動が変わる可能性があります。

---

# 最終判断

## 採用を推奨する構成

```text
ランタイムCODEX_HOME：
C:\Users\<対象ユーザー>\.codex

管理用CLI：
C:\Program Files\OpenAI\Codex\bin\codex.exe

CLIパッケージキャッシュ：
C:\ProgramData\OpenAI\Codex\PackageCache

ローカル管理ポリシー：
%ProgramData%\OpenAI\Codex\requirements.toml

クラウド管理ポリシー：
同等またはより厳しいrequirements

セットアップ：
SKYSEAのSYSTEM権限から
対象ユーザーの実プロファイルを指定して実行
```

## 採用しない方がよい構成

```text
CODEX_HOME=C:\Users\Public
```

をマシン環境変数として全クライアントに設定する構成です。

理由は以下の4点です。

* Windowsデスクトップアプリが確実に追従しない
* Publicとユーザープロファイルの二重セットアップでサンドボックス資格情報が競合する
* 認証、ログ、セッション、パッケージがPublic配下になる
* 一般ユーザーが書き換え得るCLIまたはヘルパーをSYSTEMで実行する危険がある

**今回の要件では、Publicへ移す必要はありません。** `--codex-home` はコマンド引数で対象ユーザーごとのパスを明示できるため、SKYSEAスクリプト側でユーザーSIDからプロファイルパスを解決すれば、一括配布とセキュリティを両立できます。

[1]: https://developers.openai.com/codex/config-file/environment-variables "https://developers.openai.com/codex/config-file/environment-variables"
[2]: https://github.com/openai/codex/issues/34070 "https://github.com/openai/codex/issues/34070"
[3]: https://developers.openai.com/codex/windows/windows-sandbox "https://developers.openai.com/codex/windows/windows-sandbox"
[4]: https://github.com/openai/codex/issues/9744 "https://github.com/openai/codex/issues/9744"
[5]: https://github.com/openai/codex/issues/25162 "https://github.com/openai/codex/issues/25162"
[6]: https://github.com/openai/codex/issues/25362 "https://github.com/openai/codex/issues/25362"
[7]: https://learn.chatgpt.com/codex/enterprise/managed-configuration "https://learn.chatgpt.com/codex/enterprise/managed-configuration"
[8]: https://developers.openai.com/codex/config-reference "https://developers.openai.com/codex/config-reference"




====================================================



## 結論

**はい。次の条件を満たせば、この事前プロビジョニングは、ネイティブWindows上で動作するCLI、VS Code拡張、Windowsデスクトップアプリの3つすべてに対して有効です。**

```powershell
codex sandbox setup `
  --elevated `
  --user "CONTOSO\alice" `
  --codex-home "C:\Users\alice\.codex"
```

このコマンドは「実行したCLIだけ」を設定するものではありません。正確には、次の組み合わせに対してElevated Windows Sandboxを構築します。

```text
対象Windowsユーザー：
CONTOSO\alice

対象Codexホーム：
C:\Users\alice\.codex
```

WindowsネイティブのCodex sandboxは、CLI、IDE拡張、Windowsデスクトップアプリで使用されます。CLIとIDE拡張の既定のCodexホームは `~/.codex`、Windowsデスクトップアプリは `%USERPROFILE%\.codex` を使用します。そのため、`C:\Users\alice` がAliceの実際のプロファイルであり、別の `CODEX_HOME` が設定されていなければ、3クライアントは同じプロビジョニング状態を参照します。 ([OpenAI Developers][1])

---

## クライアントごとの適用可否

| クライアント                  | 事前プロビジョニング | 条件                                           |
| ----------------------- | ---------: | -------------------------------------------- |
| Codex CLI（Windowsネイティブ） |         有効 | `CODEX_HOME` が `C:\Users\alice\.codex` であること |
| VS Code拡張（ローカルWindows）  |         有効 | 拡張がWindows側で動作し、同じ `CODEX_HOME` を使用すること      |
| Windowsデスクトップアプリ        |         有効 | Aliceでログオンし、実プロファイルが `C:\Users\alice` であること  |
| VS Code Remote-WSL      |        対象外 | WSL側はLinux環境・Linux側ホームとして扱われる                |
| VS Code Remote-SSH      |        対象外 | 接続先ホスト側で別途サンドボックスを管理する                       |
| Dev Container           |        対象外 | コンテナ側の実行環境であり、Windows sandboxとは別             |

特にVS Codeについては、通常のローカルWindowsプロジェクトなら有効ですが、左下に「WSL」「Dev Container」「SSH」などが表示されるリモートセッションでは、このWindows向けプロビジョニングの対象にはなりません。Windowsアプリの公式説明でも、Windows側とWSL側では既定のCodexホームが別であるとされています。 ([OpenAI Developers][2])

---

## 3クライアントで共有される仕組み

プロビジョニング結果は、主に次の場所に保存されます。

```text
C:\Users\alice\.codex\.sandbox\setup_marker.json

C:\Users\alice\.codex\.sandbox-secrets\sandbox_users.json
```

加えて、Windows上には次の専用ローカルアカウントなどが作成されます。

```text
CodexSandboxOffline
CodexSandboxOnline
```

つまり、プロビジョニング状態は「CLI」「VS Code」「デスクトップアプリ」といったフロントエンド名に紐付くのではなく、主として次の要素に紐付きます。

```text
・Windowsマシン
・対象Windowsユーザー
・CODEX_HOME
・セットアップ・プロトコルのバージョン
```

現在の実装では、セットアップ済みかどうかを、指定された `CODEX_HOME` 内のマーカーとサンドボックス資格情報によって判定します。今回のコマンドはそのホームへプロビジョニングを行い、同じホームの設定を `elevated` に更新します。 ([GitHub][3])

---

# アップデート後も有効か

## 基本的には有効

CLI、VS Code拡張、デスクトップアプリをアップデートしても、**セットアップ・プロトコルのバージョンが変更されず、同じ `CODEX_HOME` を使い続ける限り、通常は事前プロビジョニングをそのまま利用できます。**

製品バージョンが異なること自体は、直ちに問題になるわけではありません。例えば、次のような状態でも、各クライアントが同じセットアップ形式に対応していれば利用できる可能性があります。

```text
CLI                      0.xxx
VS Code拡張              0.yyy
Windowsデスクトップ      別の製品バージョン
セットアップ形式         すべて互換
```

現在の公開実装ではセットアップ・プロトコルの内部バージョンは `5` で、保存されたマーカーと資格情報のバージョンが、実行中のCodexが期待するバージョンと一致するかを厳密に確認しています。 ([GitHub][4])

---

## アップデートによって再プロビジョニングが必要になる場合

次の場合は、更新後に再度管理者またはSYSTEM権限でプロビジョニングする必要があります。

| 状況                                 | 結果                              |
| ---------------------------------- | ------------------------------- |
| セットアップ・プロトコルのバージョンが変わった            | 既存マーカーが互換性なしと判定される              |
| `.sandbox-secrets` が削除・破損した        | サンドボックス資格情報を読み込めない              |
| ローカルのCodexSandboxアカウントが削除・無効化された   | サンドボックスユーザーでログオンできない            |
| プロキシやローカル通信許可設定が変わった               | ファイアウォール設定の不一致として再設定が必要になる場合がある |
| `CODEX_HOME` を変更した                 | 新しいホームでは未プロビジョニング扱いになる          |
| 別のWindowsユーザーで利用した                 | そのユーザー用のACLや設定が存在しない            |
| GPOやEDRでローカルユーザー、ログオン、ACL変更等が制限された | セットアップまたは実行時更新に失敗する             |

互換性のない状態を検出した場合、CodexはElevated Setupを再実行しようとします。一般ユーザーのプロセスから実行されている場合はUACが表示されるか、「sandbox setup is missing or out of date」として失敗します。 ([GitHub][5])

---

## アップデート後も `codex-windows-sandbox-setup.exe` は使用される

事前プロビジョニングを行っても、各クライアントに同梱された `codex-windows-sandbox-setup.exe` が以後使われなくなるわけではありません。

通常実行時には、プロジェクトやワークスペースごとに、次のようなACLのリフレッシュが行われます。

```text
・読み取り可能なルートの調整
・書き込み可能なワークスペースの調整
・書き込み禁止パスのACL設定
・Codexランタイムの読み取り権限調整
```

このリフレッシュ処理は、現行実装ではUACを要求しない非昇格処理として実行されます。 ([GitHub][5])

また、セットアップEXEは、実行中のCodexランタイムを基準に探索されます。そのため、

```text
CLI
  → CLIに同梱されたセットアップEXE

VS Code拡張
  → VS Code拡張側のCodexランタイムに同梱されたセットアップEXE

デスクトップアプリ
  → デスクトップアプリ側のCodexランタイムに同梱されたセットアップEXE
```

という形になります。3クライアントが物理的に同一のEXEを使用する必要はありませんが、同じ `CODEX_HOME` の保存形式に対して互換性を持っている必要があります。 ([GitHub][4])

---

# 異なるバージョンが混在する場合の注意

最も注意すべきなのは、次のような更新途中の状態です。

```text
CLI                     新バージョン
VS Code拡張             旧バージョン
デスクトップアプリ      旧バージョン
```

新バージョンでセットアップ・プロトコルが更新された場合、新しいCLIで再プロビジョニングすると、マーカーも新しい形式になります。その後、旧バージョンのVS Code拡張やデスクトップアプリがそのマーカーを「互換性なし」と判定する可能性があります。

現行実装では、マーカーのバージョンについて前方互換・後方互換ではなく、期待値との完全一致を確認しています。このため、セットアップ・プロトコル変更を伴う更新でクライアントの新旧が混在すると、一方で再プロビジョニングした結果、他方が未設定扱いになる可能性があります。これは公開実装から導かれる運用上のリスクです。 ([GitHub][4])

したがって、会社PCでは、可能な範囲で次のように更新時期を揃えることを推奨します。

```text
CLI
VS Code拡張
Windowsデスクトップアプリ
```

少なくとも、更新前にパイロットPCで3種類を組み合わせて検証する必要があります。

---

# `allowed_sandbox_implementations = ["elevated"]` の影響

クラウドまたはローカルポリシーで次を設定している場合、

```toml
[windows]
allowed_sandbox_implementations = ["elevated"]
```

Codexは `unelevated` sandboxへフォールバックできません。公式の設定仕様上、この値は利用可能なWindows sandbox実装を制限します。 ([OpenAI Developers][6])

そのため、更新後に既存プロビジョニングが互換性なしになった場合は、次のいずれかになります。

```text
・再度UACを要求する
・UACをユーザーが通過できず失敗する
・Elevated Setupが必要というエラーで停止する
```

セキュリティ上は、弱いsandboxへ自動的に切り替わらないため望ましいfail-closedの動作です。一方で、アップデート後にCodexが一斉に利用不能になる可能性があるため、再プロビジョニング手順を運用に含める必要があります。

---

# 推奨するアップデート運用

## 1. 更新前にパイロットPCで検証する

本番展開前に、少数のPCで以下を更新します。

```text
・Codex CLI
・VS Code拡張
・Windowsデスクトップアプリ
```

その後、3種類すべてで以下を確認します。

* UACが表示されない
* サンドボックスでコマンドを実行できる
* ワークスペース内へ書き込める
* ワークスペース外への書き込みが拒否される
* ネットワーク制限がポリシーどおり動作する
* `.sandbox` ログにsetup mismatchがない

## 2. プロビジョニングの状態を確認する

```powershell
$codexHome = 'C:\Users\alice\.codex'

$marker =
    Join-Path $codexHome '.sandbox\setup_marker.json'

$secrets =
    Join-Path $codexHome '.sandbox-secrets\sandbox_users.json'

Test-Path -LiteralPath $marker
Test-Path -LiteralPath $secrets

Get-Content -LiteralPath $marker -Raw |
    ConvertFrom-Json |
    Format-List
```

現在の実装では、マーカーの `version` は次のようになります。

```text
version : 5
```

ただし、マーカーが存在するだけでは、更新後の3クライアントすべてが互換であることまでは証明できません。最終的には各クライアントで実際にサンドボックス実行を確認する必要があります。

## 3. 再プロビジョニングが必要な場合

すべてのCodex、VS Code、デスクトップアプリを終了したうえで、SKYSEAからSYSTEM権限で同じコマンドを再実行します。

```powershell
codex sandbox setup `
  --elevated `
  --user "CONTOSO\alice" `
  --codex-home "C:\Users\alice\.codex"
```

この際、管理用に承認した新しいCodex CLIを使用します。

```text
C:\Program Files\OpenAI\Codex\bin\codex.exe
```

再プロビジョニングを複数の異なる `CODEX_HOME` に対して実行してはいけません。

```text
正：
C:\Users\alice\.codex のみに実行

誤：
C:\Users\alice\.codex
C:\Users\Public
アプリ独自の別ホーム
```

## 4. 新旧バージョン混在中は安易に再実行しない

新しいCLIだけを先に更新した状態で再プロビジョニングすると、旧VS Code拡張や旧デスクトップアプリとの互換性問題が起こる可能性があります。

したがって、次の順序が安全です。

```text
1. パイロットPCで3製品を更新
2. 3製品をすべて終了
3. 同じCODEX_HOMEへ1回だけ再プロビジョニング
4. CLIで動作確認
5. VS Code拡張で動作確認
6. デスクトップアプリで動作確認
7. 問題がなければ本番配布
```

---

# 最終判断

今回のコマンドは、以下の条件なら3クライアントすべてに有効です。

```text
対象ユーザー：
CONTOSO\alice

実際のユーザープロファイル：
C:\Users\alice

全クライアントのCodexホーム：
C:\Users\alice\.codex

実行環境：
ネイティブWindows

事前セットアップの実行権限：
管理者またはSYSTEM
```

**アップデート後も、セットアップ形式が変わらなければ、そのまま利用できます。** 一方、セットアップ・プロトコルの更新、保存ファイルの破損、サンドボックスユーザーの変更、プロキシ設定の変更などがあれば、再プロビジョニングが必要になります。

企業運用としては、次の方針が適切です。

> 同じユーザーの同じ `%USERPROFILE%\.codex` に対して1回だけ事前プロビジョニングし、CLI・VS Code拡張・デスクトップアプリをパイロットで組み合わせて検証する。更新後に互換性エラーが確認された場合は、全クライアントを終了し、SKYSEAのSYSTEM権限から、更新後の承認済みCLIを使って同じホームへ再プロビジョニングする。

[1]: https://developers.openai.com/codex/windows/windows-sandbox "
  Windows sandbox | ChatGPT Learn
"
[2]: https://developers.openai.com/codex/windows/windows-app "
  ChatGPT desktop app for Windows | ChatGPT Learn
"
[3]: https://github.com/openai/codex/blob/main/codex-rs/cli/src/sandbox_setup.rs "codex/codex-rs/cli/src/sandbox_setup.rs at main · openai/codex · GitHub"
[4]: https://github.com/openai/codex/blob/main/codex-rs/windows-sandbox-rs/src/setup.rs "codex/codex-rs/windows-sandbox-rs/src/setup.rs at main · openai/codex · GitHub"
[5]: https://github.com/openai/codex/blob/main/codex-rs/windows-sandbox-rs/src/identity.rs "codex/codex-rs/windows-sandbox-rs/src/identity.rs at main · openai/codex · GitHub"
[6]: https://developers.openai.com/codex/config-reference "
  Configuration Reference | ChatGPT Learn
"
