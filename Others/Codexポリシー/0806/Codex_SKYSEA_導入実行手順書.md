# SKYSEAを使用したChatGPTデスクトップアプリ／Codex Elevated Sandbox導入 実行手順書

- 文書版: 1.0
- 調査・作成日: 2026年8月5日（JST）
- 対象OS: Windows 11推奨、または最新更新済みの64-bit Windows 10
- 対象アカウント: Active Directoryドメインアカウント
- 実施方式: SKYSEA Client Viewの「リモート操作」を使用し、1台・1ユーザーずつ実施
- 対象外: Codexクラウドポリシーの作成・変更、量産用スクリプト化、全社一括配布

---

## 0. この手順で採用する方式

今回のテストでは、次の二段階で導入します。

```text
SKYSEAで端末名を完全一致させて対象PCを選択
          │
          ├─ 対象ユーザーの通常セッション
          │    └─ WinGetで公式ChatGPTデスクトップアプリを導入
          │
          └─ 管理者として起動したPowerShell
               ├─ ADアカウントをSIDへ変換
               ├─ SIDから既存Windowsプロファイルを一意に特定
               ├─ 管理者用のCodex CLIを固定パスへ導入
               └─ 対象プロファイルの .codex にElevated Sandboxを事前構成
```

### 画面と実行権限の早見表

| 順番 | 画面 | 実行権限 | 実施内容 |
|---|---|---|---|
| 1 | SKYSEAのハードウェア一覧／端末機一覧 | SKYSEA管理者 | 端末名を完全一致で検索し、1台だけ選択 |
| 2 | SKYSEAのリモート操作画面 | SKYSEA管理者＋対象ユーザー | 対象ユーザーのデスクトップへ接続 |
| 3 | 対象ユーザーの通常PowerShell | 対象ADユーザー | 本人・端末確認、ChatGPTアプリ導入 |
| 4 | 管理者PowerShell | 承認済み端末管理者 | SID照合、CLI導入、Sandbox事前構成 |
| 5 | ChatGPTデスクトップアプリ | 対象ADユーザー | UACなしでCodexが起動することを確認 |

本書のPowerShellブロックは、`.ps1`として保存・自動配布せず、SKYSEAのリモート操作中に上から手動でコピー＆ペーストします。

### 本方式の重要ポイント

1. **端末名**は、SKYSEAで実行先PCを一意に選ぶために使います。
2. **ADユーザー名**は、`--user "ドメイン\ユーザー名"`へ指定します。
3. **Windowsプロファイルのフォルダー名は推測しません。** ADアカウントのSIDと`Win32_UserProfile.SID`を照合し、`LocalPath`を取得します。
4. 退職者のプロファイルが`C:\Users`に残っていても、SID完全一致で選ぶため誤対象化を防げます。
5. ChatGPTアプリのインストールは**対象ユーザーの通常権限セッション**で実施します。
6. `codex sandbox setup`は**実際に昇格した管理者PowerShell**で実施します。`--elevated`を付けるだけでは昇格されません。
7. UACは無効化しません。初回構成時だけ、正規の管理者昇格を使用します。
8. Codex CLIは、対象ユーザー用ではなく、今回の事前構成コマンドを実行するための**管理者用プロビジョニングツール**として`C:\ProgramData`配下へ1コピーだけ導入します。

---

## 1. 実施前の前提条件

実施前に、以下をすべて満たしてください。

### 1.1 SKYSEA側

- SKYSEA Client Viewの管理機へログインできること。
- 対象PCがSKYSEA管理下にあり、オンラインであること。
- 利用中のエディション／オプションで「リモート操作」が使用できること。
- 対象PCの端末名を把握していること。
- 操作ログが取得される設定であること。

> SKYSEAの公開仕様では、Windowsストアアプリは通常の「ソフトウェア配布」の対象外です。そのため本テストでは、SKYSEAで対象端末を選択し、リモート操作先の対象ユーザーセッションで公式WinGetコマンドを実行します。

### 1.2 Windows／アカウント側

- 対象ユーザーのWindowsプロファイルがすでに作成済みであること。
- 対象ユーザーが対象PCへサインインできること。
- ADドメインコントローラーへ接続でき、`ドメイン\ユーザー名`をSIDへ解決できること。
- 実施者が対象PCで使用可能な、承認済みのローカル管理者またはJIT管理者資格情報を持つこと。
- 対象PCでローカルユーザー作成、Windows Filtering Platform／ファイアウォール設定、必要なACL設定が組織ポリシーで禁止されていないこと。
- Microsoft StoreソースまたはOpenAI公式配布先へ通信できること。
- `winget`が利用できること。利用できない場合は「9. WinGetが利用できない場合」を参照してください。

### 1.3 OpenAI側

- Codexを利用する対象ユーザーが、会社のChatGPTワークスペースで利用権限を付与されていること。
- Codexクラウドポリシーは作成済みで、`windows.allowed_sandbox_implementations`が`["elevated"]`になっていること。
- 本手順ではクラウドポリシーを変更しません。

---

## 2. 対象ユーザー一覧を準備する

同梱の`Codex_SKYSEA_対象ユーザー一覧.csv`を使用します。最低限、実施前に次の4項目を入力してください。

| 項目 | 記入例 | 用途 |
|---|---|---|
| 管理番号 | 001 | 実施記録の一意識別 |
| 氏名 | 田中 太郎 | 人による照合 |
| 端末名 | PC-TANAKA-001 | SKYSEAで対象端末を特定 |
| ADログオン名 | `testdomain\tanaka-tarou` | SID解決および`--user`指定 |

SID、実際のプロファイルパス、実施結果は作業中に記録します。

### 今回の入力例

```text
端末名       : 実際の対象PC名を記入する
ADログオン名 : testdomain\tanaka-tarou
```

> `C:\Users\tanaka-tarou`を事前に決め打ちしないでください。実際には`tanaka-tarou.DOMAIN`や別名になっている場合があります。

---

## 3. 1ユーザー分の実行手順

以下を上から順番に実施してください。

---

### 手順1. SKYSEAで対象端末を1台だけ選択する

#### 使用する画面

- SKYSEA Client View 管理コンソール
- `[資産管理]` → `[ハードウェア一覧]`または`[端末機一覧]`

> SKYSEAの版やエディションにより表示名が若干異なる場合があります。公開資料で確認できる機能名に基づく表記です。実環境では「端末名を検索し、1台を選択できる一覧画面」を使用してください。

#### 操作

1. SKYSEA Client Viewの管理コンソールを開きます。
2. `[資産管理]`を開きます。
3. `[ハードウェア一覧]`または`[端末機一覧]`を開きます。
4. 検索条件の「端末名」に、対象ユーザー一覧の端末名を**完全一致**で入力します。
5. 検索結果が**1台だけ**であることを確認します。
6. 次を照合します。
   - 端末名が対象ユーザー一覧と一致する。
   - OSがWindowsである。
   - 端末がオンラインである。
   - 一覧の「ログオンユーザー名」列、または端末詳細のユーザー情報で、現在ログオン中のユーザーが対象の`ドメイン\ユーザー名`である。
7. 0台または2台以上の場合は実行せず、対象情報を修正します。

#### 実行中止条件

- 端末名が一致しない。
- 現在のログオンユーザーが対象ユーザーではない。
- 端末がオフラインである。
- 検索結果が一意でない。

---

### 手順2. SKYSEAのリモート操作で対象ユーザー画面へ接続する

#### 使用する画面

- 手順1の端末一覧画面
- `[リモート操作]`または同等のリモート接続メニュー

#### 操作

1. 手順1で確認した1台を選択します。
2. 右クリックメニューまたは上部メニューから`[リモート操作]`を選択します。
3. `[接続]`を実行します。
4. 利用者確認画面を表示する設定の場合、対象ユーザーに接続を承認してもらいます。
5. 接続後、Windowsデスクトップに表示されているユーザーが対象者であることを確認します。

> UACのセキュアデスクトップがリモート画面に表示されない環境では、UACを無効化しないでください。承認済み管理者が現地で操作するか、組織で承認されたSKYSEAの管理者実行方式を使用してください。

---

### 手順3. 対象ユーザーの通常PowerShellで本人・端末を再確認する

#### 使用する画面

- Windowsの`[スタート]`
- `PowerShell`または`Windows PowerShell`

#### 操作

1. 対象ユーザーのデスクトップで`[スタート]`を開きます。
2. `PowerShell`と入力します。
3. **「管理者として実行」は選ばず**、通常起動します。
4. 次の2箇所だけ、対象ユーザー一覧の値へ置き換えて実行します。

```powershell
$ExpectedHost = 'PC-TANAKA-001'
$TargetUser  = 'testdomain\tanaka-tarou'

$CurrentHost = $env:COMPUTERNAME
$CurrentUser = (whoami).Trim()

if ($CurrentHost -ine $ExpectedHost) {
    throw "対象端末が違います。現在=$CurrentHost / 予定=$ExpectedHost"
}
if ($CurrentUser -ine $TargetUser) {
    throw "対象ユーザーが違います。現在=$CurrentUser / 予定=$TargetUser"
}

"端末確認OK: $CurrentHost"
"ユーザー確認OK: $CurrentUser"
```

#### 正常結果

```text
端末確認OK: PC-TANAKA-001
ユーザー確認OK: testdomain\tanaka-tarou
```

エラーになった場合は、その端末では作業を続行しません。

---

### 手順4. 対象ユーザーへ公式ChatGPTデスクトップアプリを導入する

#### 実行コンテキスト

- 対象ユーザーの通常PowerShell
- 管理者権限では実行しない

#### 4-1. WinGetと製品情報を確認する

```powershell
winget --version
winget show --id 9PLM9XGG6VKS --source msstore --exact --accept-source-agreements
```

表示内容で、次を確認します。

- IDが`9PLM9XGG6VKS`である。
- 製品がChatGPT／OpenAIの公式Windowsアプリである。
- 発行元がOpenAIである。

一致しない場合はインストールせず中止します。

#### 4-2. インストールする

```powershell
winget install --id 9PLM9XGG6VKS --source msstore --exact --accept-package-agreements --accept-source-agreements
```

#### 4-3. インストール結果を確認する

```powershell
winget list --id 9PLM9XGG6VKS --exact
```

対象ユーザー一覧の「ChatGPTアプリ」に、`成功`またはエラー内容を記録します。

> OpenAIの現在のCodex対応Windowsアプリ資料で案内されているStore IDは`9PLM9XGG6VKS`です。古いChatGPT Windowsアプリの別IDを本手順へ混在させないでください。

#### 4-4. アプリを終了する

スタートメニューにChatGPTが表示されることだけ確認し、この時点ではアプリを起動しないか、起動した場合は完全に終了します。サンドボックス事前構成中はChatGPTを閉じてください。

---

### 手順5. 管理者PowerShellを起動する

#### 使用する画面

- Windowsの`[スタート]`
- `PowerShell`または`Windows PowerShell`
- UAC資格情報画面

#### 操作

1. 対象ユーザーのデスクトップで`[スタート]`を開きます。
2. `PowerShell`と入力します。
3. 検索結果を右クリックし、`[管理者として実行]`を選択します。
4. UAC画面で、組織が承認した端末管理者またはJIT管理者の資格情報を使用します。
5. 管理者PowerShellで次を実行します。

```powershell
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $IsAdmin) {
    throw 'このPowerShellは管理者として起動されていません。'
}
'管理者権限確認OK'
```

`管理者権限確認OK`が表示されない場合は続行しません。

---

### 手順6. ADユーザーのSIDから対象プロファイルを一意に特定する

#### 目的

`C:\Users`配下のフォルダー名を目視で選ばず、ADアカウントのSIDとWindowsプロファイルのSIDを照合します。これにより、退職者の残存プロファイルや似たユーザー名を誤って対象にすることを防ぎます。

#### 実行コマンド

次の2箇所だけ、対象ユーザー一覧の値へ置き換えて実行します。

```powershell
$ExpectedHost = 'PC-TANAKA-001'
$TargetUser  = 'testdomain\tanaka-tarou'

if ($env:COMPUTERNAME -ine $ExpectedHost) {
    throw "対象端末が違います。現在=$env:COMPUTERNAME / 予定=$ExpectedHost"
}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $IsAdmin) {
    throw '管理者として起動されていません。'
}

$TargetSid = ([System.Security.Principal.NTAccount]$TargetUser).Translate(
    [System.Security.Principal.SecurityIdentifier]
).Value

$Profiles = @(
    Get-CimInstance Win32_UserProfile |
        Where-Object { $_.SID -eq $TargetSid -and -not $_.Special }
)

if ($Profiles.Count -ne 1) {
    throw "対象SIDに一致する通常プロファイルが $($Profiles.Count) 件です。推測せず中止してください。SID=$TargetSid"
}

$TargetProfile = $Profiles[0]
$TargetProfile | Format-List SID, LocalPath, Loaded, Special, Status, LastUseTime

if (-not (Test-Path -LiteralPath $TargetProfile.LocalPath -PathType Container)) {
    throw "プロファイルフォルダーが存在しません: $($TargetProfile.LocalPath)"
}
if ($TargetProfile.LocalPath -notlike 'C:\Users\*') {
    throw "想定外のプロファイルパスです: $($TargetProfile.LocalPath)"
}
if (-not (Test-Path -LiteralPath (Join-Path $TargetProfile.LocalPath 'NTUSER.DAT') -PathType Leaf)) {
    throw "NTUSER.DATが見つかりません。正常な既存プロファイルとして確認できません。"
}
if (($TargetProfile.Status -band 1) -ne 0 -or
    ($TargetProfile.Status -band 4) -ne 0 -or
    ($TargetProfile.Status -band 8) -ne 0) {
    throw "一時・必須・破損プロファイルの可能性があります。Status=$($TargetProfile.Status)"
}

$CodexHome = Join-Path $TargetProfile.LocalPath '.codex'

"TargetHost = $env:COMPUTERNAME"
"TargetUser = $TargetUser"
"TargetSid  = $TargetSid"
"LocalPath  = $($TargetProfile.LocalPath)"
"CodexHome  = $CodexHome"
```

#### 正常結果の例

```text
TargetHost = PC-TANAKA-001
TargetUser = testdomain\tanaka-tarou
TargetSid  = S-1-5-21-...
LocalPath  = C:\Users\tanaka-tarou
CodexHome  = C:\Users\tanaka-tarou\.codex
```

#### 記録

対象ユーザー一覧へ次を転記します。

- AD SID
- `Win32_UserProfile.LocalPath`

> SID変換エラー、0件、複数件のいずれかになった場合は、フォルダー名を手入力して回避しないでください。AD接続、アカウント名、プロファイル登録状態を修正してから再実施します。

---

### 手順7. 既存のCodexローカル設定を確認し、必要ならバックアップする

この手順は、過去のテスト設定やアクティブプロファイルが`elevated`設定を上書きする事故を防ぐために行います。

#### 7-1. 既存設定をバックアップする

```powershell
$ConfigPath = Join-Path $CodexHome 'config.toml'

if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $BackupPath = Join-Path $CodexHome (
        'config.toml.before-sandbox-setup-{0}.bak' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    )
    Copy-Item -LiteralPath $ConfigPath -Destination $BackupPath
    "設定バックアップ: $BackupPath"
} else {
    '既存config.tomlなし'
}
```

#### 7-2. 内容を表示する

```powershell
if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    Get-Content -LiteralPath $ConfigPath
}
```

次がある場合はその場で中止し、設定管理者へ確認します。

- `profile = "..."`でアクティブプロファイルが指定されている。
- `[profiles.<名前>.windows]`配下に別のサンドボックス設定がある。
- `sandbox = "unelevated"`がある。
- 旧Windowsサンドボックス用の設定が残っている。

> `codex sandbox setup`はベース設定へ`elevated`を書き込んでも、アクティブプロファイル側が上書きすると利用時の実効設定が変わる可能性があります。

---

### 手順8. 管理者用Codex CLIを固定パスへ導入する

#### 方針

- 対象ユーザーの`AppData`や`PATH`へCLIを導入しません。
- 管理者用のプロビジョニングコピーを次へ導入します。

```text
C:\ProgramData\OpenAI\CodexProvisioning
```

- ChatGPTデスクトップアプリ自体の通常利用に、別途ユーザー用CLIを常設する必要はありません。
- 今回CLIが必要なのは、`codex sandbox setup`を実行するためです。

#### 8-1. 公式インストーラーを実行する

管理者PowerShellで実行します。

```powershell
$env:CODEX_HOME = 'C:\ProgramData\OpenAI\CodexProvisioning\home'
$env:CODEX_INSTALL_DIR = 'C:\ProgramData\OpenAI\CodexProvisioning\bin'
$env:CODEX_NON_INTERACTIVE = '1'

irm https://chatgpt.com/codex/install.ps1 | iex
```

公式インストーラーはWindowsのx64／ARM64を判定し、Codexパッケージを取得してSHA-256検証を行います。

> 組織ルールで`irm | iex`が禁止されている場合は、同じ公式URLをファイルへ保存し、社内レビュー済みファイルとして実行してください。非公式ミラーや第三者配布物へ置き換えないでください。

#### 8-2. 実行するCLIとセットアップヘルパーを確認する

```powershell
$ProvisioningCodex = 'C:\ProgramData\OpenAI\CodexProvisioning\home\packages\standalone\current\bin\codex.exe'
$SetupHelper = 'C:\ProgramData\OpenAI\CodexProvisioning\home\packages\standalone\current\codex-resources\codex-windows-sandbox-setup.exe'

if (-not (Test-Path -LiteralPath $ProvisioningCodex -PathType Leaf)) {
    throw "codex.exeが見つかりません: $ProvisioningCodex"
}
if (-not (Test-Path -LiteralPath $SetupHelper -PathType Leaf)) {
    throw "セットアップヘルパーが見つかりません: $SetupHelper"
}

& $ProvisioningCodex --version
& $ProvisioningCodex sandbox setup --help
```

`--help`に次が表示されることを確認します。

- `--elevated`
- `--user`
- `--codex-home`

> `codex`だけを実行したり、`C:\ProgramData\OpenAI\CodexProvisioning\bin\codex.exe`を使用したりせず、上記の`...\current\bin\codex.exe`を使用してください。Windows版Codexには、見かけ上の`bin`ジャンクションから起動した場合にセットアップヘルパーを見つけられない既知の報告があるためです。

---

### 手順9. 対象ユーザーのElevated Sandboxを事前構成する

#### 実行コマンド

手順6で設定済みの`$TargetUser`、`$CodexHome`、手順8の`$ProvisioningCodex`をそのまま使用します。

```powershell
& $ProvisioningCodex sandbox setup --elevated --user $TargetUser --codex-home $CodexHome

if ($LASTEXITCODE -ne 0) {
    throw "Codex sandbox setupに失敗しました。ExitCode=$LASTEXITCODE"
}
```

#### 期待する表示例

```text
Windows elevated sandbox setup completed for testdomain\tanaka-tarou at C:\Users\tanaka-tarou\.codex.
```

この処理は、概ね次を行います。

- `CodexSandboxOffline`と`CodexSandboxOnline`のローカルサンドボックスユーザーを作成または更新する。
- サンドボックス用の資格情報をDPAPIで保護して対象`CODEX_HOME`配下へ保存する。
- ファイアウォール／WFP設定を構成する。
- 対象の実ユーザーを使用して必要なACLを構成する。
- 対象`config.toml`へWindowsサンドボックスの`elevated`設定を保存する。

> 成功メッセージが出るまでは、ChatGPTアプリを起動しないでください。

---

### 手順10. 事前構成の結果を確認する

管理者PowerShellで実行します。

```powershell
$ConfigPath = Join-Path $CodexHome 'config.toml'
$MarkerPath = Join-Path $CodexHome '.sandbox\setup_marker.json'
$LogPath    = Join-Path $CodexHome '.sandbox\sandbox.log'

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "config.tomlが見つかりません: $ConfigPath"
}
if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
    throw "setup_marker.jsonが見つかりません: $MarkerPath"
}
if (-not (Select-String -LiteralPath $ConfigPath -Pattern 'sandbox\s*=\s*"elevated"' -Quiet)) {
    throw 'config.tomlにsandbox = "elevated"が見つかりません。'
}

$SandboxUsers = @(
    Get-LocalUser |
        Where-Object { $_.Name -in @('CodexSandboxOffline', 'CodexSandboxOnline') }
)
if ($SandboxUsers.Count -ne 2 -or $SandboxUsers.Enabled -contains $false) {
    throw '2つのCodexサンドボックスユーザーが存在し、有効であることを確認できません。'
}

'config.toml       : OK'
'setup_marker.json : OK'
Get-Content -LiteralPath $MarkerPath
$SandboxUsers | Select-Object Name, Enabled
```

#### 合格条件

すべて満たすことを確認します。

- `config.toml : OK`
- `setup_marker.json : OK`
- `config.toml`に`sandbox = "elevated"`がある。
- `setup_marker.json`が読み取れる。
- `CodexSandboxOffline`が存在し、`Enabled=True`である。
- `CodexSandboxOnline`が存在し、`Enabled=True`である。

`Get-LocalUser`が使用できない場合だけ、次で確認します。

```powershell
Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" |
    Where-Object { $_.Name -in @('CodexSandboxOffline', 'CodexSandboxOnline') } |
    Select-Object Name, Disabled, SID
```

対象ユーザー一覧の次を記録します。

- Codex CLIバージョン
- Sandbox setup結果
- 実施日時
- 実施者

---

### 手順11. 対象ユーザーでChatGPT／Codexの動作確認をする

#### 使用する画面

- 管理者PowerShellを閉じる。
- 対象ユーザーのWindowsスタートメニュー。
- ChatGPTデスクトップアプリ。

#### 操作

1. 管理者PowerShellを閉じます。
2. 対象ユーザーのスタートメニューから`ChatGPT`を起動します。
3. 会社のChatGPTワークスペースへサインインします。
4. Codexを開きます。
5. テスト用の機密情報を含まないローカルフォルダーを選択します。
6. 最初のテストとして、ファイル変更を伴わない安全な指示を実行します。

例:

```text
このフォルダー直下のファイル名だけを一覧表示してください。ファイルは変更しないでください。
```

#### 合格条件

- Codex起動時に初回サンドボックス構成を要求されない。
- UAC画面が出ない。
- `unelevated`への切り替えを要求されない。
- 管理ポリシーどおりElevated Sandboxが使用される。
- 安全な読み取りテストが正常終了する。

対象ユーザー一覧の「UACなし動作確認」を`合格`にします。

---

### 手順12. SKYSEAリモート操作を終了し、記録を確定する

1. ChatGPTアプリを終了します。
2. 対象ユーザー一覧の未記入欄を埋めます。
3. SKYSEAのリモート操作を終了します。
4. SKYSEA側で、操作対象端末、操作者、操作日時のログが残っていることを確認します。
5. 次のユーザーを実施する場合は、手順1へ戻ります。

---

## 4. 実施完了の判定表

| 確認項目 | 合格条件 |
|---|---|
| SKYSEA対象端末 | 端末名完全一致で1台のみ |
| 対象Windowsユーザー | `whoami`が対象ADログオン名と一致 |
| プロファイル | AD SIDと`Win32_UserProfile.SID`が1件だけ一致 |
| ChatGPTアプリ | Store ID `9PLM9XGG6VKS`が対象ユーザーに導入済み |
| 管理者権限 | 管理者トークン確認済み |
| Codex CLI | 固定パスのCLIで`--version`および`setup --help`成功 |
| セットアップヘルパー | `codex-windows-sandbox-setup.exe`存在 |
| Sandbox setup | 成功メッセージ、終了コード0 |
| ローカル設定 | `config.toml`に`elevated` |
| セットアップマーカー | `.sandbox\setup_marker.json`存在 |
| ローカルユーザー | Offline／Onlineの2ユーザーが有効 |
| 利用確認 | ChatGPTからCodexを起動してUACなし |
| 記録 | 対象ユーザー一覧とSKYSEA操作ログを保存 |

すべて合格した時点で、そのユーザーの作業を完了とします。

---

## 5. 必ず中止する条件

次のいずれかが発生した場合、推測や手入力で回避せず中止します。

- SKYSEAで対象端末が一意に特定できない。
- 端末名が予定と異なる。
- `whoami`が対象ADユーザーと異なる。
- ADアカウントをSIDへ変換できない。
- SIDに一致する通常プロファイルが0件または複数件である。
- プロファイルが一時、必須、破損状態である。
- `winget show`の製品ID／発行元が期待値と異なる。
- PowerShellが実際には管理者へ昇格されていない。
- 既存のアクティブプロファイルや`unelevated`設定が見つかった。
- `codex sandbox setup --help`に必要な引数がない。
- セットアップヘルパーが見つからない。
- `codex sandbox setup`の終了コードが0以外である。
- セットアップマーカーまたはローカルサンドボックスユーザーが確認できない。
- 動作確認時にUACまたは初回セットアップ画面が再度出る。

---

## 6. 主なトラブルと対処

### 6.1 `sandbox provisioning setup must be run from an elevated process`

**原因:** PowerShellが実際には昇格されていません。

**対処:** PowerShellを閉じ、`[管理者として実行]`で起動し直します。`--elevated`引数だけでUAC昇格は行われません。

---

### 6.2 `codex-windows-sandbox-setup.exe`が見つからない

**原因:** `PATH`上の見かけの`bin`ジャンクションから`codex.exe`を起動した可能性があります。

**対処:** 次の固定パスを使用します。

```powershell
$ProvisioningCodex = 'C:\ProgramData\OpenAI\CodexProvisioning\home\packages\standalone\current\bin\codex.exe'
$SetupHelper = 'C:\ProgramData\OpenAI\CodexProvisioning\home\packages\standalone\current\codex-resources\codex-windows-sandbox-setup.exe'
```

両方が存在することを確認してから再実行します。

---

### 6.3 エラー1385、ログオン権限、ローカルユーザー作成エラー

**原因候補:** GPOやEDRにより、ローカルサンドボックスユーザーの作成／ログオン権限が拒否されています。

**対処:** 対象端末のGPO結果、ユーザー権利の割り当て、EDRイベントを確認します。UACやセキュリティ製品を無効化して回避しないでください。

---

### 6.4 ファイアウォール／WFP設定で失敗する

**原因候補:** 組織ポリシーがローカルファイアウォール設定を禁止している、またはEDRが変更を遮断しています。

**対処:** セキュリティ管理者に、Codex Elevated Sandboxが`CodexSandboxOffline`用のアウトバウンド制御を構成することを伝え、許可方針を確認します。

---

### 6.5 成功メッセージ後もUACや初回セットアップが出る

1. アクティブプロファイルが`elevated`を上書きしていないか確認します。
2. 次のログを確認します。

```powershell
$LogPath = Join-Path $CodexHome '.sandbox\sandbox.log'
Get-Content -LiteralPath $LogPath -Tail 200
```

3. ChatGPTアプリとプロビジョニングCLIの更新時期を確認し、必要なら最新CLIで手順9を再実行します。
4. プロキシ環境変数を利用している場合、実利用時と同じ`HTTP_PROXY`／`HTTPS_PROXY`等を管理者PowerShellへ設定した状態で再構成します。

> `.sandbox-secrets`の内容は表示、収集、チケット添付、外部送信をしないでください。

---

### 6.6 ChatGPTアプリが管理者アカウント側へ入ってしまった

**原因:** アプリ導入を管理者PowerShellで実施しました。MSIX／Storeアプリは原則として実行中ユーザーへ登録されます。

**対処:** 管理者側の誤導入を削除し、対象ユーザーの通常PowerShellへ戻って手順4を実行します。

---

### 6.7 AD SIDへ変換できない

**原因候補:** ドメイン名／ユーザー名の誤り、VPN未接続、ドメインコントローラー到達不可、アカウント無効化。

**対処:** `testdomain\tanaka-tarou`の表記、ネットワーク接続、AD上のアカウント状態を確認します。フォルダー名からSIDを推測して続行しません。

---

## 7. 再実行について

`codex sandbox setup`は管理展開時の事前構成用として再実行できます。次の場合に再実行を検討します。

- OpenAIのリリースノートまたは管理展開手順で、Windows Sandboxのプロビジョニング更新が案内された。
- セットアップマーカーのバージョン不一致がログに記録された。
- 会社のプロキシ／ローカルバインド設定を変更した。
- ローカルサンドボックスユーザーまたは関連ファイアウォール設定が削除・無効化された。
- 動作確認で初回セットアップまたはUACが再発した。

再実行時も、必ず対象PC名、ADユーザー、SID、プロファイルパスを再照合します。

---

## 8. ロールバック／テスト後の扱い

### 8.1 ChatGPTアプリだけを削除する

対象ユーザーの通常PowerShellで実行します。

```powershell
winget uninstall --id 9PLM9XGG6VKS --source msstore
```

または、対象ユーザーの`[設定]` → `[アプリ]` → `[インストールされているアプリ]` → `ChatGPT` → `[アンインストール]`を使用します。

### 8.2 Elevated Sandboxの構成

ローカルユーザー、ファイアウォール／WFP、ACL、DPAPI保護済み情報が関係するため、次を手作業で削除しないでください。

- `CodexSandboxOffline`
- `CodexSandboxOnline`
- `.sandbox-secrets`
- 関連ファイアウォール／WFP設定
- Codexが設定したACL

現時点で本手順が参照する公式資料には、これらを一括して安全に戻す管理者用アンインストールコマンドが明記されていません。テスト端末を完全に元へ戻す必要がある場合は、事前スナップショットからの復元、再イメージ、またはOpenAIサポートの正式手順を使用します。

### 8.3 管理者用Codex CLI

`C:\ProgramData\OpenAI\CodexProvisioning`は、再プロビジョニングや障害調査に使用できるため、本テスト後も残すことを推奨します。削除する場合は、社内変更管理に従って実施してください。

---

## 9. WinGetが利用できない場合

WinGetが使用できない場合だけ、OpenAIの企業向けWindows配布ページから、端末アーキテクチャに合う公式Store署名済みMSIXを取得します。

### 実施条件

- x64端末にはx64版、ARM64端末にはARM64版を使用する。
- 必ずOpenAI公式配布ページから取得する。
- 対象ユーザーの通常PowerShellで`Add-AppxPackage`を実行する。
- 管理者PowerShellで対象ユーザーの代わりに実行しない。

### 対象ユーザーの通常PowerShellでの例

```powershell
$env:PROCESSOR_ARCHITECTURE
Add-AppxPackage -Path 'C:\Path\To\OpenAI-ChatGPT.msix'
```

MSIXファイル名とURLは更新される可能性があるため、本手順へ固定URLを埋め込まず、実施時点のOpenAI公式企業配布ページから取得してください。依存関係、ライセンス、署名に関するエラーが発生した場合は、その場で中止します。別サイトから依存パッケージを取得したり、署名検証を回避したりせず、OpenAI公式の企業向け配布手順または組織のMicrosoft Store／MDM管理手順へ切り替えてください。

---

## 10. 参照資料

### OpenAI公式

- ChatGPT desktop app for Windows / Codex Windows app  
  https://learn.chatgpt.com/docs/windows/windows-app
- Enterprise deployment of the Codex-enabled Windows app  
  https://learn.chatgpt.com/docs/enterprise/windows-deployment
- Windows sandbox  
  https://learn.chatgpt.com/docs/windows/windows-sandbox
- Codex公式Windowsインストーラー  
  https://chatgpt.com/codex/install.ps1
- Windows Elevated Sandboxの設計解説  
  https://openai.com/index/building-codex-windows-sandbox/

### OpenAI Codexリポジトリ

- Managed deployment用`codex sandbox setup`追加PR #24831  
  https://github.com/openai/codex/pull/24831
- Windowsのセットアップヘルパー探索に関するIssue #30829  
  https://github.com/openai/codex/issues/30829
- 同種のIssue #32359  
  https://github.com/openai/codex/issues/32359

### SKYSEA

- SKYSEA Client View 機能一覧  
  https://www.skyseaclientview.net/product-info/feature/
- SKYSEA Client View リモート操作  
  https://www.skyseaclientview.net/product-info/option/
- SKYSEA Client View 制限事項  
  https://www.skyseaclientview.net/product-info/limit/ver21/

### Microsoft

- Win32_UserProfile class  
  https://learn.microsoft.com/windows/win32/cimwin32prov/win32-userprofile
- WinGet install command  
  https://learn.microsoft.com/windows/package-manager/winget/install
- Add-AppxPackage  
  https://learn.microsoft.com/powershell/module/appx/add-appxpackage

---

## 11. 実施者用の最終チェック

```text
□ SKYSEAで端末名を完全一致させ、1台だけ選択した
□ 対象ユーザーの通常セッションでwhoamiとhostnameを確認した
□ Store ID 9PLM9XGG6VKSの公式アプリを対象ユーザーへ導入した
□ 管理者PowerShellが実際に昇格されていることを確認した
□ ADアカウントをSIDへ変換した
□ SID一致のWin32_UserProfileが1件だけであることを確認した
□ 実際のLocalPathからCodexHomeを決定した
□ 既存config.tomlを確認・バックアップした
□ 固定パスの管理者用Codex CLIとセットアップヘルパーを確認した
□ codex sandbox setupが終了コード0で完了した
□ config.toml、setup_marker.json、2つのローカルユーザーを確認した
□ 対象ユーザーでChatGPT/Codexを起動し、UACが出ないことを確認した
□ 対象ユーザー一覧とSKYSEA操作ログを保存した
```
