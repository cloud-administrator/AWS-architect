# SKYSEAによるChatGPT／Codex Elevated Sandbox 実行手順書

- 文書版: 1.1
- 作成日: 2026年8月5日
- 対象: Windows、Active Directoryドメインアカウント
- 実施方式: SKYSEAのリモート操作で、1台・1ユーザーずつ実施

---

## 1. 実施内容

対象PCで次を行います。

1. SKYSEAで対象PCを端末名から1台に特定する。
2. 対象ADユーザーへChatGPTデスクトップアプリを導入または確認する。
3. ADユーザーのSIDから、実際のWindowsプロファイルを特定する。
4. 管理者用Codex CLIを端末へ配置する。
5. 管理者PowerShellでElevated Sandboxを事前構成する。
6. 対象ユーザーでCodexを起動し、UACが表示されないことを確認する。

> UACを無効化する手順ではありません。管理者が初回構成を先に完了させることで、利用者側の初回UACを回避します。

---

## 2. 作業前に準備する値

対象者ごとに次の2項目を用意します。

| 項目 | 例 |
|---|---|
| 端末名 | `PC-TANAKA-001` |
| ADログオン名 | `testdomain\tanaka-tarou` |

前提条件は次のとおりです。

- 対象PCがSKYSEA管理下でオンラインである。
- 対象ADユーザーのWindowsプロファイルがすでに存在する。
- 対象PCで使用できる管理者資格情報がある。
- `winget`が利用できる。
- Codexのクラウドポリシーは設定済みである。

---

# 3. 実行手順

## 手順1. SKYSEAで対象PCへ接続する

### 画面

```text
SKYSEA Client View管理コンソール
  → [資産管理]
  → [ハードウェア一覧] または [端末機一覧]
```

### 操作

1. 「端末名」に対象PC名を完全一致で入力します。
2. 検索結果が**1台だけ**であることを確認します。
3. 対象PCがオンラインで、ログオンユーザーが対象者であることを確認します。
4. 対象PCを選択し、`[リモート操作]`を開始します。

**解説:** 端末名はSKYSEAで実行先を決めるために使用します。0台または複数台の場合は中止します。

---

## 手順2. 対象ユーザーと端末を確認する

対象ユーザーのデスクトップで、PowerShellを**通常起動**します。

```text
[スタート] →「PowerShell」と入力 → 通常起動
```

先頭2行を対象者の値へ変更して実行します。

```powershell
$ExpectedHost = 'PC-TANAKA-001'
$TargetUser   = 'testdomain\tanaka-tarou'

if ($env:COMPUTERNAME -ine $ExpectedHost) {
    throw "対象端末が違います。現在=$env:COMPUTERNAME / 予定=$ExpectedHost"
}
if ((whoami).Trim() -ine $TargetUser) {
    throw "対象ユーザーが違います。現在=$((whoami).Trim()) / 予定=$TargetUser"
}

"端末確認OK: $env:COMPUTERNAME"
"ユーザー確認OK: $((whoami).Trim())"
```

次のように表示されれば合格です。

```text
端末確認OK: PC-TANAKA-001
ユーザー確認OK: testdomain\tanaka-tarou
```

**解説:** SKYSEAで選んだPCと、実際に操作しているユーザーを二重確認します。エラー時は続行しません。

---

## 手順3. ChatGPTデスクトップアプリを導入または確認する

手順2の通常PowerShellで実行します。

### 未導入の場合

```powershell
winget show --id 9PLM9XGG6VKS --source msstore --exact --accept-source-agreements
winget install --id 9PLM9XGG6VKS --source msstore --exact --accept-package-agreements --accept-source-agreements
```

### SKYSEAで配布済みの場合を含む確認

```powershell
winget list --id 9PLM9XGG6VKS --exact
```

スタートメニューにもChatGPTが表示されることを確認します。確認後、ChatGPTはまだ起動しません。

**解説:** アプリは対象ADユーザーの通常セッションへ登録します。管理者アカウント側へ誤って導入しないでください。

---

## 手順4. 管理者PowerShellを起動する

対象ユーザーのデスクトップで次を行います。

```text
[スタート] →「PowerShell」と入力
  → 右クリック
  → [管理者として実行]
```

会社で承認された管理者資格情報を使用します。起動後、次を実行します。

```powershell
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $IsAdmin) {
    throw 'このPowerShellは管理者として起動されていません。'
}
'管理者権限確認OK'
```

**解説:** `--elevated`は自動昇格オプションではありません。PowerShell自体が管理者として起動されている必要があります。

---

## 手順5. SIDから対象プロファイルを特定する

管理者PowerShellで、先頭2行を対象者の値へ変更して実行します。

```powershell
$ExpectedHost = 'PC-TANAKA-001'
$TargetUser   = 'testdomain\tanaka-tarou'

if ($env:COMPUTERNAME -ine $ExpectedHost) {
    throw "対象端末が違います。現在=$env:COMPUTERNAME / 予定=$ExpectedHost"
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
if (-not (Test-Path -LiteralPath $TargetProfile.LocalPath -PathType Container)) {
    throw "プロファイルが存在しません: $($TargetProfile.LocalPath)"
}
if ($TargetProfile.LocalPath -notlike 'C:\Users\*') {
    throw "想定外のプロファイルパスです: $($TargetProfile.LocalPath)"
}

$CodexHome = Join-Path $TargetProfile.LocalPath '.codex'

"TargetHost = $env:COMPUTERNAME"
"TargetUser = $TargetUser"
"TargetSid  = $TargetSid"
"LocalPath  = $($TargetProfile.LocalPath)"
"CodexHome  = $CodexHome"
```

正常例は次のとおりです。

```text
TargetSid = S-1-5-21-...
LocalPath = C:\Users\tanaka-tarou
CodexHome = C:\Users\tanaka-tarou\.codex
```

**解説:** `C:\Users`のフォルダー名を推測せず、ADユーザーのSIDと`Win32_UserProfile.SID`を完全一致させます。退職者の残存プロファイルがあっても、別SIDであれば対象になりません。

---

## 手順6. 既存設定の競合を確認する

管理者PowerShellで実行します。

```powershell
$ConfigPath = Join-Path $CodexHome 'config.toml'

if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $Conflict = Select-String -LiteralPath $ConfigPath -Pattern '^\s*profile\s*=|sandbox\s*=\s*"unelevated"'
    if ($Conflict) {
        $Conflict
        throw '既存のprofile指定またはunelevated設定があります。設定管理者へ確認してください。'
    }
}
'既存設定の競合なし'
```

**解説:** 既存プロファイル側の設定が`elevated`を上書きする可能性があるため、競合時は削除せず中止します。

---

## 手順7. 管理者用Codex CLIを導入する

管理者PowerShellで実行します。

```powershell
$env:CODEX_HOME = 'C:\ProgramData\OpenAI\CodexProvisioning\home'
$env:CODEX_INSTALL_DIR = 'C:\ProgramData\OpenAI\CodexProvisioning\bin'
$env:CODEX_NON_INTERACTIVE = '1'

irm https://chatgpt.com/codex/install.ps1 | iex
```

続けて、CLIとセットアップヘルパーを確認します。

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

`--help`に`--elevated`、`--user`、`--codex-home`が表示されることを確認します。

**解説:** このCLIは事前構成用です。対象ユーザーごとにインストールせず、端末の`C:\ProgramData`へ1コピーだけ配置します。

> 組織のルールで`irm | iex`が禁止されている場合は、同じ公式URLのファイルを社内確認後に実行してください。

---

## 手順8. Elevated Sandboxを事前構成する

手順5と手順7で設定した変数を使用し、管理者PowerShellで実行します。

```powershell
& $ProvisioningCodex sandbox setup --elevated --user $TargetUser --codex-home $CodexHome

if ($LASTEXITCODE -ne 0) {
    throw "Codex sandbox setupに失敗しました。ExitCode=$LASTEXITCODE"
}
```

正常時は、次の形式で完了メッセージが表示されます。

```text
Windows elevated sandbox setup completed for testdomain\tanaka-tarou at C:\Users\tanaka-tarou\.codex.
```

**解説:** 対象ユーザー用のサンドボックスユーザー、ACL、ファイアウォール／WFP設定、セットアップ情報を管理者が事前構成します。

---

## 手順9. 構成結果を確認する

管理者PowerShellで実行します。

```powershell
$ConfigPath = Join-Path $CodexHome 'config.toml'
$MarkerPath = Join-Path $CodexHome '.sandbox\setup_marker.json'

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "config.tomlがありません: $ConfigPath"
}
if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
    throw "setup_marker.jsonがありません: $MarkerPath"
}
if (-not (Select-String -LiteralPath $ConfigPath -Pattern 'sandbox\s*=\s*"elevated"' -Quiet)) {
    throw 'config.tomlにsandbox = "elevated"がありません。'
}

$SandboxUsers = @(Get-LocalUser | Where-Object {
    $_.Name -in @('CodexSandboxOffline', 'CodexSandboxOnline')
})
if ($SandboxUsers.Count -ne 2 -or $SandboxUsers.Enabled -contains $false) {
    throw 'Codexのサンドボックスユーザー2件を正常確認できません。'
}

'config.toml       : OK'
'setup_marker.json : OK'
$SandboxUsers | Select-Object Name, Enabled
```

次が確認できれば合格です。

```text
config.toml       : OK
setup_marker.json : OK
CodexSandboxOffline  Enabled=True
CodexSandboxOnline   Enabled=True
```

**解説:** 完了メッセージだけでなく、対象ユーザーの`.codex`に設定とマーカーが作成されたことを確認します。

---

## 手順10. 対象ユーザーで動作確認する

1. 管理者PowerShellを閉じます。
2. 対象ユーザーのスタートメニューからChatGPTを通常起動します。
3. 会社のChatGPTワークスペースへサインインします。
4. Codexを開き、機密情報を含まないテスト用フォルダーを選択します。
5. 次の読み取りテストを実行します。

```text
このフォルダー直下のファイル名だけを一覧表示してください。ファイルは変更しないでください。
```

合格条件は次のとおりです。

- UACが表示されない。
- 初回サンドボックス構成画面が表示されない。
- `unelevated`への切り替えを要求されない。
- 読み取りテストが正常に完了する。

**解説:** 必ず対象ユーザーの通常権限で確認します。ChatGPTを管理者として起動して確認しないでください。

---

## 手順11. 結果を記録して終了する

対象ユーザー一覧へ次を記録します。

- 端末名
- ADログオン名
- AD SID
- 実プロファイルパス
- ChatGPTアプリの導入結果
- Codex CLIバージョン
- Sandbox setup結果
- UACなし確認結果
- 実施日時と実施者

記録後、SKYSEAのリモート操作を終了します。

---

# 4. 中止条件

次の場合は、推測して続行せず中止してください。

- SKYSEAで対象PCを1台に特定できない。
- 端末名または`whoami`が対象情報と一致しない。
- ADユーザーをSIDへ変換できない。
- SIDに一致する通常プロファイルが0件または複数件である。
- 管理者PowerShellとして起動されていない。
- 既存設定に`profile =`または`unelevated`がある。
- セットアップヘルパーが存在しない。
- `sandbox setup`の終了コードが0以外である。
- `config.toml`または`setup_marker.json`を確認できない。
- 利用確認時にUACが表示される。

---

# 5. 最小限のトラブル対応

| 症状 | 対応 |
|---|---|
| `must be run from an elevated process` | PowerShellを閉じ、`[管理者として実行]`で起動し直す。 |
| セットアップヘルパーが見つからない | `$ProvisioningCodex`の実体パスから実行しているか確認する。 |
| Windowsエラー1385 | GPOのログオン権限、ローカルユーザー制限、EDRを管理者へ確認する。 |
| ファイアウォール／WFPで失敗 | ローカルファイアウォール変更を組織ポリシーが許可しているか確認する。 |
| 成功後もUACが出る | `$CodexHome\.sandbox\sandbox.log`を確認し、既存プロファイル設定も再確認する。 |

ログ確認コマンド:

```powershell
Get-Content -LiteralPath (Join-Path $CodexHome '.sandbox\sandbox.log') -Tail 200
```

> `.sandbox-secrets`の内容は表示、コピー、チケット添付、外部送信をしないでください。

---

# 6. 参考資料

- https://learn.chatgpt.com/docs/windows/windows-app
- https://learn.chatgpt.com/docs/enterprise/windows-deployment
- https://learn.chatgpt.com/docs/windows/windows-sandbox
- https://github.com/openai/codex/pull/24831
- https://chatgpt.com/codex/install.ps1
