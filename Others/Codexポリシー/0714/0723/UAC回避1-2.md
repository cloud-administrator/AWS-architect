# IT管理者がCodexのWindowsサンドボックスを事前プロビジョニングする手順

## 1. 事前プロビジョニングとは

通常、利用者が初めて`elevated`サンドボックスを使うとき、Windowsは管理者権限を要求します。これは、Codexが次のようなWindowsのシステム設定を行うためです。

* Codex専用の低権限ユーザーを作成する
* ファイルやフォルダーのアクセス権を設定する
* ファイアウォールルールを設定する
* サンドボックス用のローカルポリシーを設定する

OpenAIは、専用の低権限ユーザー、ファイルシステム境界、ファイアウォールルールを使う`elevated`方式を、Windowsの推奨サンドボックスとして案内しています。([OpenAI Developers][1])

**事前プロビジョニング**では、この初期設定を利用者にさせず、IT管理者が先に実施します。

```text
通常の方法
利用者がCodexを起動
  ↓
UACが表示される
  ↓
管理者ID・パスワードが必要

事前プロビジョニング
IT管理者が先にセットアップ
  ↓
利用者がCodexを起動
  ↓
UACは表示されない
```

管理者が使用する基本コマンドは、次の形式です。

```powershell
codex sandbox setup --elevated `
  --user "ドメイン名\利用者名" `
  --codex-home "利用者のプロファイル\.codex"
```

このコマンドは、標準ユーザーが管理者操作をできない企業環境向けの事前セットアップとしてOpenAIのCodexに実装されています。

---

# 2. 全体の作業手順

作業の流れは次のとおりです。

1. 利用者に対象PCへ一度サインインしてもらう
2. IT管理者が「管理者としてPowerShell」を開く
3. 利用者のアカウントを指定してサンドボックスをセットアップする
4. セットアップ結果を確認する
5. 利用者が通常権限でCodexを起動する
6. 問題がなければクラウドポリシーで`elevated`を強制する

最初は、全社展開ではなく**1台のテスト端末と1人のテスト利用者**で実施してください。

---

# 3. 事前に用意するもの

## 対象PC

Windows 11を推奨します。OpenAIも企業標準化ではWindows 11を推奨しており、Windows 10はベストエフォート扱いです。([OpenAI Developers][1])

## IT管理者のアカウント

次のいずれかが必要です。

* 対象PCのローカル管理者
* 端末管理専用のActive Directoryアカウント
* IntuneなどのSYSTEM権限
* Windows LAPSで管理しているローカル管理者

利用者に管理者のIDやパスワードを渡す必要はありません。

## 利用者のWindowsアカウント

例として、次の利用者に設定するものとします。

```text
ドメイン名：CONTOSO
利用者名：alice
Windowsアカウント：CONTOSO\alice
```

## Codex CLI

管理者用PowerShellで、次のコマンドが実行できる必要があります。

```powershell
codex --version
```

バージョン番号が表示されれば準備できています。

---

# 4. 手順1：利用者に一度サインインしてもらう

事前プロビジョニングの前に、対象利用者にそのPCへ一度サインインしてもらいます。

例えば、対象利用者が`CONTOSO\alice`の場合、次のようなプロファイルフォルダーが作成されます。

```text
C:\Users\alice
```

利用者は次の操作を行います。

1. Windowsへ通常どおりサインインする
2. デスクトップが表示されるまで待つ
3. Windowsからサインアウトする

Codexはまだ起動しなくても構いません。

### なぜ一度サインインするのか

Windowsは、利用者が最初にサインインしたときに、利用者専用のプロファイルフォルダーを作成します。

事前プロビジョニングでは、次のフォルダーを使用します。

```text
C:\Users\alice\.codex
```

一度もサインインしていない場合、利用者のプロファイルフォルダーがまだ存在しないことがあります。

---

# 5. 手順2：管理者としてPowerShellを開く

IT管理者が対象PCで操作します。

1. Windowsのスタートボタンを押す
2. `PowerShell`または`ターミナル`と入力する
3. 「Windows PowerShell」または「ターミナル」を右クリックする
4. 「管理者として実行」を選択する
5. UAC画面にIT管理者のIDとパスワードを入力する

このUAC操作を行うのは**IT管理者だけ**です。

PowerShellのタイトル部分に次のように表示されていれば、管理者権限で開かれています。

```text
管理者: Windows PowerShell
```

事前プロビジョニングコマンドは、実際に管理者権限で起動されているか確認します。既に管理者権限で起動されている場合、内部セットアップ処理は追加のUACを出さずに実行されます。

---

# 6. 手順3：Codexコマンドを確認する

管理者PowerShellで、次のコマンドを実行します。

```powershell
codex --version
```

正常な例は次のような表示です。

```text
codex-cli 0.xxx.x
```

続いて、事前プロビジョニングコマンドが使用できるか確認します。

```powershell
codex sandbox setup --help
```

ヘルプが表示されれば、そのCodexバージョンで事前プロビジョニングを実行できます。

## エラーになる場合

次のようなエラーが出た場合は、Codex CLIが古い可能性があります。

```text
unrecognized subcommand
```

または、

```text
unknown command
```

この場合は、会社で管理しているCodex CLIを更新してから、もう一度確認します。

一般のCLIリファレンスに表示されないクライアントバージョンもあるため、実際の端末で`--help`を確認してから展開してください。

---

# 7. 手順4：簡単なコマンドでセットアップする

対象利用者が次の場合を例にします。

```text
Windowsアカウント：CONTOSO\alice
プロファイル：C:\Users\alice
```

管理者PowerShellで、次のコマンドを実行します。

```powershell
codex sandbox setup --elevated `
  --user "CONTOSO\alice" `
  --codex-home "C:\Users\alice\.codex"
```

PowerShellの行末にあるバッククォート記号 `` ` `` は、「次の行にコマンドが続く」という意味です。

1行で実行しても構いません。

```powershell
codex sandbox setup --elevated --user "CONTOSO\alice" --codex-home "C:\Users\alice\.codex"
```

## 各項目の意味

| 項目                    | 意味                        |
| --------------------- | ------------------------- |
| `codex sandbox setup` | Codexのサンドボックスを事前セットアップする  |
| `--elevated`          | 強いWindowsサンドボックスをセットアップする |
| `--user`              | Codexを利用する対象社員を指定する       |
| `--codex-home`        | 対象社員のCodex設定フォルダーを指定する    |

## ローカルユーザーの場合

対象PCだけに存在するローカルユーザーの場合は、次のように指定します。

```powershell
codex sandbox setup --elevated `
  --user "PC名\alice" `
  --codex-home "C:\Users\alice\.codex"
```

PC名が`PC001`なら、次のようになります。

```powershell
codex sandbox setup --elevated `
  --user "PC001\alice" `
  --codex-home "C:\Users\alice\.codex"
```

---

# 8. より安全な自動確認付きPowerShell

利用者のプロファイルフォルダー名は、必ずしもWindowsのユーザー名と同じとは限りません。

例えば、同じ名前のユーザーが過去に存在した場合、次のようになることがあります。

```text
C:\Users\alice.CONTOSO
C:\Users\alice.001
```

パスの間違いを防ぐには、次のスクリプトを使います。

管理者PowerShellへ貼り付け、最初の`$TargetUser`だけ変更してください。

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==================================================
# ここだけ対象利用者に合わせて変更してください
# ==================================================
$TargetUser = "CONTOSO\alice"
# ==================================================

# 1. PowerShellが管理者権限か確認
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [System.Security.Principal.WindowsPrincipal]::new($identity)

$isAdministrator = $principal.IsInRole(
    [System.Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdministrator) {
    throw "PowerShellを「管理者として実行」で開き直してください。"
}

# 2. codexコマンドを探す
$CodexCommand = Get-Command codex `
    -CommandType Application `
    -ErrorAction Stop |
    Select-Object -First 1

$CodexExe = $CodexCommand.Source

# 3. 対象利用者のSIDを取得
try {
    $account = [System.Security.Principal.NTAccount]::new($TargetUser)

    $sid = $account.Translate(
        [System.Security.Principal.SecurityIdentifier]
    ).Value
}
catch {
    throw "対象利用者 '$TargetUser' を確認できません。ドメイン名とユーザー名を確認してください。"
}

# 4. Windowsに登録されている本当のプロファイルパスを取得
$profileKey =
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"

if (-not (Test-Path -LiteralPath $profileKey)) {
    throw @"
対象利用者のWindowsプロファイルがありません。

対象利用者にこのPCへ一度サインインしてもらい、
デスクトップ表示後にサインアウトしてから、再実行してください。
"@
}

$profilePath = (
    Get-ItemProperty `
        -LiteralPath $profileKey `
        -Name ProfileImagePath
).ProfileImagePath

$profilePath =
    [Environment]::ExpandEnvironmentVariables($profilePath)

$codexHome = Join-Path $profilePath ".codex"

# 5. 実行内容を表示
Write-Host ""
Write-Host "次の内容でCodexサンドボックスをセットアップします。"
Write-Host "--------------------------------------------------"
Write-Host "Codexコマンド : $CodexExe"
Write-Host "対象利用者    : $TargetUser"
Write-Host "プロファイル  : $profilePath"
Write-Host "CODEX_HOME    : $codexHome"
Write-Host "--------------------------------------------------"
Write-Host ""

$confirmation = Read-Host "内容が正しければ YES と入力してください"

if ($confirmation -ne "YES") {
    Write-Host "処理を中止しました。"
    return
}

# 6. 事前プロビジョニングを実行
& $CodexExe sandbox setup `
    --elevated `
    --user $TargetUser `
    --codex-home $codexHome

$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "Codexサンドボックスのセットアップに失敗しました。終了コード: $exitCode"
}

# 7. セットアップ結果を確認
$markerPath =
    Join-Path $codexHome ".sandbox\setup_marker.json"

$credentialsPath =
    Join-Path $codexHome ".sandbox-secrets\sandbox_users.json"

if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    throw "セットアップ確認ファイルが作成されていません: $markerPath"
}

if (-not (Test-Path -LiteralPath $credentialsPath -PathType Leaf)) {
    throw "サンドボックス用の資格情報ファイルが作成されていません。"
}

Write-Host ""
Write-Host "事前プロビジョニングが正常に完了しました。"
Write-Host "対象利用者: $TargetUser"
Write-Host "CODEX_HOME: $codexHome"
Write-Host ""
Write-Host "利用者は通常権限でCodexを起動できます。"
```

## スクリプト実行時の注意

スクリプトには次のように表示されます。

```text
Codexコマンド : C:\...\codex.exe
```

または、

```text
Codexコマンド : C:\...\codex.cmd
```

本番展開では、会社が管理している場所のCodexを使用してください。

例えば、管理者だけが変更できる`Program Files`配下などです。

次のような**対象利用者が書き換えられる場所**のCodexを、SYSTEMや管理者権限で実行しないでください。

```text
C:\Users\対象利用者\AppData\...
C:\Users\対象利用者\Downloads\...
C:\Users\対象利用者\Desktop\...
```

---

# 9. `--current-user`を使用しない

次のコマンドは、企業の事前プロビジョニングでは避けてください。

```powershell
codex sandbox setup --elevated --current-user
```

管理者PowerShellでこれを実行すると、「現在のユーザー」は利用者ではなく、PowerShellを起動した管理者になる可能性があります。

その結果、管理者自身の`.codex`がセットアップされ、目的の利用者には設定されません。

企業環境では、必ず次の2つを明示します。

```text
--user "ドメイン名\対象利用者"
--codex-home "対象利用者のプロファイル\.codex"
```

Codexの管理者向けコマンドは、`--user`と`--codex-home`を使って対象ユーザーを明示できるよう設計されています。

---

# 10. `codex-windows-sandbox-setup.exe`を直接実行しない

次のファイルを、エクスプローラーやスクリプトから直接実行してはいけません。

```text
codex-windows-sandbox-setup.exe
```

これは一般的なインストーラーではなく、Codex本体から内部データを受け取って動作するセットアップ用ヘルパーです。

必ず次の公式コマンドから実行します。

```powershell
codex sandbox setup --elevated ...
```

セットアップ用EXEは、Codexが生成した1つのペイロードを受け取り、セットアップバージョンが一致することを確認する内部プログラムです。

---

# 11. 手順5：正常終了を確認する

正常に完了すると、次のような意味のメッセージが表示されます。

```text
Windows elevated sandbox setup completed
```

Codexは、対象利用者の設定に`elevated`サンドボックスを保存します。

## PowerShellで確認する

対象利用者が`alice`の場合は、次を実行します。

```powershell
Test-Path "C:\Users\alice\.codex\.sandbox\setup_marker.json"
```

正常なら、次のように表示されます。

```text
True
```

次も確認します。

```powershell
Test-Path "C:\Users\alice\.codex\.sandbox-secrets\sandbox_users.json"
```

正常なら、同じく次のように表示されます。

```text
True
```

### 重要

次のファイルは、中身を表示したり、メールやチャットで送信したりしないでください。

```text
C:\Users\alice\.codex\.sandbox-secrets\sandbox_users.json
```

OpenAIも、診断時に`.sandbox-secrets`の内容を送信しないよう案内しています。([OpenAI Developers][1])

存在確認だけにしてください。

```powershell
Test-Path "ファイルパス"
```

---

# 12. 手順6：利用者が通常権限で動作確認する

事前プロビジョニングが完了したら、管理者PowerShellを閉じます。

その後、対象利用者が通常どおりWindowsへサインインします。

## 利用者が行うこと

1. Windowsへ通常サインインする
2. CodexまたはChatGPTデスクトップアプリを通常起動する
3. 「管理者として実行」は選ばない
4. プロジェクトフォルダーを開く
5. 簡単な読み取り処理を試す

Codex CLIの場合は、次を実行します。

```powershell
codex
```

Codexが開いたら、次を入力します。

```text
/status
```

続いて、例えば次のように依頼します。

```text
このフォルダー内のファイル一覧を確認してください。
ファイルは変更しないでください。
```

## 正常な状態

次の状態なら成功です。

* 利用者にUACが表示されない
* 管理者ID・パスワードを求められない
* Codexが通常権限で起動する
* ファイルの読み取りができる
* 作業フォルダー外への書き込みが制限される

---

# 13. 手順7：クラウドポリシーで`elevated`を強制する

事前プロビジョニングのテストが成功した後、Codexの管理画面でポリシーを設定します。

設定する内容は次のとおりです。

```toml
[windows]
allowed_sandbox_implementations = ["elevated"]
```

この設定により、利用者は弱い`unelevated`サンドボックスへ切り替えられなくなります。OpenAIの公式資料でも、この設定は`elevated`を必須にし、`unelevated`へのフォールバックを禁止するものと説明されています。([OpenAI Developers][1])

## 設定順序が重要

次の順番で実施してください。

```text
1. Codexを端末へ配布する
2. IT管理者が事前プロビジョニングする
3. 利用者で動作確認する
4. テストグループへポリシーを割り当てる
5. 全社へ段階的に展開する
```

先に`elevated`強制ポリシーだけを配布すると、まだ事前プロビジョニングされていないPCで、Codexがセットアップできず利用できなくなる可能性があります。

クラウド管理ポリシーは対応クライアントへ管理者強制要件として配信されます。OpenAIも、全社割り当ての前に小規模グループでポリシーを検証するよう案内しています。([OpenAI Developers][2])

---

# 14. 複数台へ展開する場合

1台での動作確認が完了したら、同じ処理をIntune、MECM、GPO、その他の端末管理ツールから配布します。

OpenAIは、Windowsアプリの集中管理にはIntuneなどのMDM・ソフトウェア配布基盤を使用するよう案内しています。([ChatGPT Learn][3])

## 基本的な考え方

端末管理ツールから、次の条件でPowerShellスクリプトを実行します。

| 項目        | 設定                                  |
| --------- | ----------------------------------- |
| 実行権限      | SYSTEM                              |
| 利用者の管理者権限 | 不要                                  |
| UAC操作     | 不要                                  |
| 実行時期      | 対象利用者の初回サインイン後                      |
| 対象        | 対象利用者のWindowsアカウント                  |
| 成功確認      | `.sandbox\setup_marker.json`が存在すること |

SYSTEM権限で動作するため、利用者の画面にはUACが表示されません。

## 一括展開の流れ

```text
IntuneなどでCodexを配布
  ↓
利用者が一度Windowsへサインイン
  ↓
SYSTEM権限で事前プロビジョニングスクリプトを実行
  ↓
成功確認ファイルを検出
  ↓
Codexポリシーを利用者へ割り当て
```

## Codex更新時

Codexの更新によってWindowsサンドボックスのセットアップバージョンが変わった場合、再セットアップが必要になることがあります。

Codexは、保存されたセットアップマーカーと現在のセットアップバージョンが一致するか確認し、不足または不一致の場合は再セットアップを要求します。

したがって、企業のCodex更新パッケージには次を含めるのが安全です。

```text
1. Codex本体を更新
2. SYSTEM権限で事前プロビジョニングを再実行
3. 動作確認
```

---

# 15. エラーが出た場合の確認方法

## エラー1：`codex`が見つからない

表示例：

```text
The term 'codex' is not recognized
```

原因は、Codex CLIがインストールされていないか、PATHへ登録されていないことです。

確認します。

```powershell
Get-Command codex -ErrorAction SilentlyContinue
```

何も表示されない場合は、会社で管理しているCodex CLIを先に配布してください。

---

## エラー2：`sandbox setup`が認識されない

表示例：

```text
unrecognized subcommand 'setup'
```

Codex CLIが古い可能性があります。

次を確認します。

```powershell
codex --version
codex sandbox setup --help
```

会社で配布しているCodex CLIを更新し、再度確認します。

---

## エラー3：利用者のプロファイルが見つからない

表示例：

```text
対象利用者のWindowsプロファイルがありません
```

対象利用者が、そのPCへ一度もサインインしていない可能性があります。

対象利用者に次を実施してもらいます。

```text
Windowsへサインイン
  ↓
デスクトップが表示されるまで待つ
  ↓
サインアウト
```

その後、管理者が事前プロビジョニングを再実行します。

---

## エラー4：ローカルユーザーまたはグループを作成できない

会社のGPO、EDR、セキュリティ製品が、ローカルユーザーやローカルグループの作成を禁止している可能性があります。

OpenAIは、`elevated`セットアップの主な失敗原因として、次を挙げています。

* UACや管理者要求の拒否
* ローカルユーザー・グループ作成の禁止
* ファイアウォールルール変更の禁止
* サンドボックスユーザーに必要なログオン権限の拒否
* その他の企業ポリシーによるブロック

([OpenAI Developers][1])

---

## エラー5：Windowsエラー1385

表示例：

```text
Logon failure: the user has not been granted the requested logon type
```

またはエラー番号：

```text
1385
```

これは、Codex専用のサンドボックスユーザーに必要なログオン権限が、Active DirectoryのGPOなどで拒否されている状態です。

次を確認します。

* 対象端末のGPO
* User Rights Assignment
* サンドボックス用ユーザーのログオン拒否設定
* 正常な端末と問題端末のOU・GPOの違い

OpenAIも、エラー1385はWindowsがサンドボックスユーザーに必要なログオン種別を拒否している状態と説明しています。([OpenAI Developers][1])

---

## エラー6：利用者に再びUACが表示される

次を確認します。

1. `--user`に正しい利用者を指定したか
2. `--codex-home`が正しい利用者のフォルダーか
3. 管理者自身の`.codex`を誤って設定していないか
4. `setup_marker.json`が存在するか
5. Codex更新後にセットアップバージョンが変わっていないか
6. 利用者が別のWindowsプロファイルでログオンしていないか

確認コマンド：

```powershell
Test-Path "C:\Users\利用者\.codex\.sandbox\setup_marker.json"
```

---

# 16. ログの確認場所

セットアップに失敗した場合は、対象利用者の次のログを確認します。

```text
C:\Users\利用者\.codex\.sandbox\sandbox.log
```

PowerShellで表示する場合：

```powershell
Get-Content "C:\Users\alice\.codex\.sandbox\sandbox.log" -Tail 100
```

OpenAIへ問い合わせる場合も、この`sandbox.log`は診断材料になります。([OpenAI Developers][1])

ただし、次のフォルダーの内容は送信しないでください。

```text
C:\Users\利用者\.codex\.sandbox-secrets
```

---

# 17. 実施してはいけないこと

次の方法は使用しないでください。

* 利用者に管理者IDとパスワードを渡す
* UACを無効にする
* `runas /savecred`で管理者資格情報を保存する
* 管理者パスワードをPowerShellスクリプトへ記載する
* Domain Adminの資格情報を利用者PCで常用する
* 利用者にCodexを「管理者として実行」させる
* `codex-windows-sandbox-setup.exe`を直接実行する
* 利用者が書き換えられる場所の`codex.exe`をSYSTEM権限で実行する
* セットアップ前に全利用者へ`elevated`強制ポリシーを配る
* `.sandbox-secrets`の中身をログ収集・メール送信する

---

# 18. 管理者向け最終チェックリスト

## セットアップ前

* [ ] Windows 11が最新状態である
* [ ] Codex CLIがインストールされている
* [ ] `codex --version`が成功する
* [ ] `codex sandbox setup --help`が成功する
* [ ] 対象利用者がPCへ一度サインインしている
* [ ] 対象利用者のアカウント名を確認した
* [ ] PowerShellを管理者として起動した

## セットアップ時

* [ ] `--current-user`を使っていない
* [ ] `--user "DOMAIN\利用者"`を指定した
* [ ] 対象利用者の正しい`--codex-home`を指定した
* [ ] 会社管理下のCodex実行ファイルを使用した
* [ ] セットアップが終了コード0で完了した

## セットアップ後

* [ ] `setup_marker.json`が存在する
* [ ] `sandbox_users.json`が存在する
* [ ] `.sandbox-secrets`の中身を表示していない
* [ ] 利用者が通常権限でCodexを起動できる
* [ ] 利用者にUACが表示されない
* [ ] 1台のテスト端末で動作確認した
* [ ] テスト後に`elevated`強制ポリシーを割り当てた

最初の検証では、**テスト利用者が一度サインインした後、管理者PowerShellで自動確認付きスクリプトを実行し、利用者が通常権限で再テストする**という順序が最も間違いにくい進め方です。

[1]: https://developers.openai.com/codex/windows/windows-sandbox "
  Windows sandbox | ChatGPT Learn
"
[2]: https://developers.openai.com/codex/enterprise/managed-configuration "
  Managed configuration | ChatGPT Learn
"
[3]: https://learn.chatgpt.com/codex/enterprise/windows-deployment "
  Deploy the Windows app | ChatGPT Learn
"
