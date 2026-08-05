# SKYSEAによるChatGPTデスクトップアプリ／Codex elevated sandbox 導入手順書【完成版】

- 文書版: 2.0
- 精査日: 2026-08-04
- 対象: Windows端末、Active Directoryドメインアカウント、20名以上
- 推奨OS: Windows 11
- ChatGPT新アプリのMicrosoft Store製品ID: `9PLM9XGG6VKS`
- 本パッケージで承認済みのCodex CLI: `0.146.0`
- 前提: Codexクラウドポリシーは作成・適用済み

> [!IMPORTANT]
> 本手順は、利用者にUAC承認を求めず、IT管理者がSKYSEAのLocalSystemジョブで`elevated` sandboxを正規に事前構成する方法です。UACを無効化・迂回する手順ではありません。

> [!IMPORTANT]
> SKYSEAの画面名はバージョン、Edition、管理機の構成によって多少異なります。公開資料で確認できる基本経路と設定値を記載しています。自社版で同義の項目名が異なる場合は、保守契約者向けマニュアルで照合してください。実行主体だけは変更せず、SYSTEMジョブはLocalSystem、USERジョブは対象ユーザー本人とします。

---

## 1. 採用する方式

対象者ごとにコマンドや配布パックを作りません。次の3点だけで運用します。

```text
1つの targets.csv
    ├─ SKYSEAジョブ1: LocalSystem
    │    対象PCの1行だけを選択
    │    Domain\SamAccountName → SID
    │    SID → ProfileList → 正式な既存プロファイル
    │    codex sandbox setup --elevated
    │    保護されたAuthorizedTarget.jsonを作成
    │
    └─ SKYSEAジョブ2: 対象ユーザー本人
         AuthorizedTarget.jsonのSIDと現在のSIDを照合
         一致時のみ製品ID 9PLM9XGG6VKSをwingetで導入
```

| 項目 | 確定方式 |
|---|---|
| 対象者台帳 | `ComputerName,Domain,SamAccountName,Enabled`の1つのCSV |
| 1台当たりの対象 | `Enabled=1`は1名だけ |
| プロファイル特定 | AD SIDと`ProfileList\<SID>\ProfileImagePath`から取得 |
| `C:\Users` | 列挙しない |
| Codex setup | SKYSEAのLocalSystemジョブ |
| ChatGPTアプリ | SKYSEAのログオンユーザージョブ |
| Codex CLI | 管理用フルパッケージを`C:\ProgramData`へACL保護して1コピー配置 |
| ChatGPT製品 | 新アプリ`9PLM9XGG6VKS` |
| 配布波 | 2台 → 5～10台 → 残り |

---

## 2. 本パッケージの構成

```text
Codex_SKYSEA_完成版_20260804\
├─ 00_README_FIRST.md
├─ Codex_SKYSEA_完成版_導入手順書.md
├─ Codex_SKYSEA_完成版_方式設計・解説.md
├─ APPROVED_CODEX_VERSION.txt
├─ APPROVED_CODEX_PACKAGE_HASHES.csv
├─ STATIC_VALIDATION.txt
├─ SHA256SUMS.csv
├─ targets.csv                         ← 通常編集するのはこれだけ
├─ targets.example.csv
├─ 00_Prepare\
│  ├─ Run-Prepare-And-Build.cmd
│  └─ Prepare-And-Build.ps1
├─ 01_SYSTEM_TEMPLATE\
│  ├─ RUN_AS_SYSTEM.cmd
│  └─ Deploy-CodexSandbox.ps1
└─ 02_USER_TEMPLATE\
   ├─ RUN_AS_TARGET_USER.cmd
   └─ Install-ChatGPTForAuthorizedUser.ps1
```

準備スクリプトを実行すると、`Output`に次が作成されます。

```text
SKYSEA_CodexSandbox_SYSTEM_0.146.0_x64.zip
SKYSEA_ChatGPT_USER.zip
SKYSEA_MEDIA_SHA256.csv
```

Arm64端末用のSYSTEM媒体は、Arm64 Windows準備端末で`-Architecture arm64`を指定して作成します。

---

## 3. 事前条件

### 3.1 対象端末・ユーザー

- 対象ユーザーのWindowsプロファイルが既に存在する。
- プロファイルが`C:\Users`配下にある。
- 対象端末がドメインコントローラーへ到達でき、`Domain\SamAccountName`をSIDへ変換できる。
- SYSTEMジョブ実行時は対象ユーザーを**サインアウト**させる。画面ロックだけでは不可。
- USERジョブ実行時は対象ユーザー本人がログオンしている。
- 端末は64ビットWindowsである。
- Windows 11を標準とする。Windows 10は更新済み端末でもベストエフォート扱いとする。

### 3.2 GPO・EDR・Windows制御

Codexの`elevated` sandboxは、専用の低権限sandboxユーザー、ACL、ファイアウォール、ローカルポリシーを使用します。次をGPO、EDR、アプリケーション制御が妨げていないことをパイロットで確認します。

- ローカルユーザー／グループの作成
- Windows Firewall／WFP関連設定
- sandboxユーザーに必要なログオン権利
- `codex.exe`と同梱helperの実行
- `C:\ProgramData\OpenAI\CodexDeployment\Tools`からの実行

例外が必要な場合は、製品・パス・署名・ハッシュを限定し、包括的な除外を作らないでください。

### 3.3 ネットワーク

| フェーズ | 必要な接続 |
|---|---|
| 管理用媒体の作成 | `releases.openai.com`へのHTTPS |
| SYSTEMジョブ | Codexフルパッケージを媒体に同梱するため、通常は外部ダウンロード不要 |
| USERジョブ | Microsoft Storeの`msstore`ソース、Windows Package Manager関連サービス |
| アプリ更新 | OpenAI公式展開資料に記載された更新配布先を組織ポリシーに従って許可 |

対象端末でMicrosoft配布サービスを使えない場合は、第18章のMSIX代替方式を使用します。

### 3.4 SKYSEA

- ソフトウェア配布機能が利用可能。
- SYSTEM権限実行が利用可能。
- ログオンユーザー権限でスクリプトを実行できる。
- 配布パックを作成・変更できる管理者を必要最小限に限定している。
- 終了コードを取得・確認できる。

---

## 4. STEP 1: 対象者CSVを作る

### 4.1 編集するファイル

```text
targets.csv
```

ヘッダーは変更しません。

```csv
ComputerName,Domain,SamAccountName,Enabled
```

### 4.2 対象者を1人1行で入力する

```csv
ComputerName,Domain,SamAccountName,Enabled
PC-TANAKA-001,testdomain,tanaka-tarou,1
PC-SUZUKI-002,testdomain,suzuki-hanako,1
PC-OLD-003,testdomain,old-user,0
```

| 列 | 入力内容 | 例 |
|---|---|---|
| `ComputerName` | 対象PCで`hostname`を実行した結果。FQDNではない | `PC-TANAKA-001` |
| `Domain` | 対象ユーザーで`whoami`を実行したときの`\`左側。ADのNetBIOSドメイン名 | `testdomain` |
| `SamAccountName` | `whoami`の`\`右側 | `tanaka-tarou` |
| `Enabled` | 導入対象は`1`、台帳に残す対象外行は`0` | `1` |

上表の`\`は表示上の区切り記号です。実際の`whoami`出力は次の形です。

```text
testdomain\tanaka-tarou
```

> [!IMPORTANT]
> 同じ`ComputerName`に`Enabled=1`の行を2件以上作らないでください。SYSTEMスクリプトは安全側で停止します。

### 4.3 `ProfilePath`をCSVに書かない理由

完成版では、添付資料にあった任意の`ProfilePath`列を廃止しました。フォルダー名を人が転記せず、次の正式な対応関係から自動取得します。

```text
Domain\SamAccountName
  → AD SID
  → HKLM\...\ProfileList\<SID>\ProfileImagePath
  → Win32_UserProfile.SID／LocalPathと再照合
  → 実フォルダーとNTUSER.DATを確認
```

これにより、退職者の残存フォルダー、同名再作成アカウント、`user.000`等の特殊なプロファイル名をフォルダー名だけで誤判定しません。

### 4.4 情報確認コマンド

対象ユーザーがログオン中の確認作業時に、通常権限のPowerShellまたはコマンドプロンプトで実行します。

```powershell
hostname
whoami
whoami /user
$env:USERPROFILE
```

CSVは`CSV UTF-8（コンマ区切り）`で保存します。

---

## 5. STEP 2: SKYSEA登録用媒体を作る

この処理は対象端末ごとには実行しません。管理された準備端末で1回実行します。

### 5.1 準備端末

- 対象PCと同じCPUアーキテクチャの64ビットWindows端末
- OpenAI公式リリース配布先へHTTPS接続可能
- PowerShellスクリプトの実行とZIP作成が可能
- ダウンロード物を一時保存できる

### 5.2 実行

1. 本パッケージを管理用フォルダーへ展開します。
2. `targets.csv`を完成させます。
3. エクスプローラーで`00_Prepare`を開きます。
4. `Run-Prepare-And-Build.cmd`をダブルクリックするか、コマンドプロンプトから実行します。

x64端末では通常、引数なしで実行します。

```bat
00_Prepare\Run-Prepare-And-Build.cmd
```

明示する場合:

```bat
00_Prepare\Run-Prepare-And-Build.cmd -Architecture x64
```

Arm64用:

```bat
00_Prepare\Run-Prepare-And-Build.cmd -Architecture arm64
```

準備スクリプトは次を自動実行します。

1. `targets.csv`の列、値、端末重複を検査
2. `APPROVED_CODEX_VERSION.txt`の承認版を読み取り
3. OpenAI公式の**フルパッケージアーカイブ**を取得
4. 固定SHA-256とOpenAI公開`codex-package_SHA256SUMS`の両方で照合
5. フルパッケージに`codex-windows-sandbox-setup.exe`等が揃っていることを確認
6. `codex --version`と`codex sandbox setup --help`を実行
7. SYSTEM媒体へフルパッケージと対象CSVを格納
8. USER媒体を作成
9. 2媒体のSHA-256を`SKYSEA_MEDIA_SHA256.csv`へ記録

### 5.3 成功確認

```text
Output\
├─ SKYSEA_CodexSandbox_SYSTEM_0.146.0_x64.zip
├─ SKYSEA_ChatGPT_USER.zip
└─ SKYSEA_MEDIA_SHA256.csv
```

PowerShellで再確認します。

```powershell
Import-Csv .\Output\SKYSEA_MEDIA_SHA256.csv | Format-Table
Get-FileHash .\Output\SKYSEA_CodexSandbox_SYSTEM_0.146.0_x64.zip -Algorithm SHA256
Get-FileHash .\Output\SKYSEA_ChatGPT_USER.zip -Algorithm SHA256
```

結果を変更管理票へ記録します。あわせて、配布元一式の`STATIC_VALIDATION.txt`と`SHA256SUMS.csv`を保管します。`SHA256SUMS.csv`は`targets.csv`編集前の配布元ハッシュです。対象CSV確定後は別途`Get-FileHash targets.csv`を記録してください。

### 5.4 コード署名を使う組織

社内のPowerShellコード署名基盤がある場合は、媒体作成**前**に3つの`.ps1`へ署名します。署名後に媒体を作り直し、そのZIPハッシュを記録します。署名を必須にする場合は、CMD内の`-ExecutionPolicy Bypass`を組織標準へ変更してください。

`Bypass`は付属CMDが起動する1プロセスだけに適用され、端末の永続的な実行ポリシーを変更しません。ただし、配布パックの編集権限とハッシュ管理は必須です。

---

## 6. STEP 3: SKYSEAで対象端末グループを作る

20台以上を毎回手作業で選ばず、今回専用グループを作成します。

例:

```text
ChatGPT-Codex-Target-202608
```

1. SKYSEAの資産台帳から`targets.csv`の`ComputerName`を検索します。
2. 対象端末を専用グループへ登録します。
3. CSVの`Enabled=1`端末数とグループの端末数を照合します。
4. 端末名一覧を二者確認します。
5. パイロット2台を別の小グループにします。

SKYSEA側の端末グループと、端末上スクリプトのCSV照合を二重に使用します。

---

## 7. SKYSEAの基本画面

公開資料で確認できる基本経路:

```text
［資産管理］
  →［アプリケーション一覧］
    →［ソフトウェア配布］
      →［追加］または［配布パック作成］
        →［実行ファイルやWindows更新プログラム］
          →［実行設定］
```

自社版に同じ名称がない場合、次の役割で対応する画面を選びます。

| 目的 | 探す項目 |
|---|---|
| 実行ファイル登録 | バッチ、実行ファイル、スクリプト、配布パック |
| 依存ファイル | 同時配布ファイル、フォルダー、関連ファイル |
| 実行主体 | システム権限、SYSTEM、ログオンユーザー |
| 対象指定 | クライアントPC、グループ、端末一覧 |
| 結果 | 実行結果、終了コード、配布結果 |

---

## 8. STEP 4: SYSTEMジョブを登録する

### 8.1 使用媒体

`Output`のSYSTEM ZIPを管理機で展開します。

```text
SKYSEA_CodexSandbox_SYSTEM_0.146.0_x64\
├─ RUN_AS_SYSTEM.cmd
├─ Deploy-CodexSandbox.ps1
├─ targets.csv
└─ CodexTool\
   ├─ bin\codex.exe
   ├─ codex-resources\codex-windows-sandbox-setup.exe
   └─ その他の公式フルパッケージファイル
```

`CodexTool`を含むフォルダー構造を崩さないでください。`codex.exe`だけを抜き出して配布しません。

### 8.2 画面操作

1. SKYSEA管理機で`［資産管理］→［アプリケーション一覧］→［ソフトウェア配布］`を開きます。
2. `［追加］`または`［配布パック作成］`を選びます。
3. 種別に`［実行ファイルやWindows更新プログラム］`を選びます。
4. パッケージ名を入力します。

```text
01_CodexSandbox_SYSTEM_0.146.0_x64
```

5. 実行ファイルに次を指定します。

```text
RUN_AS_SYSTEM.cmd
```

6. `Deploy-CodexSandbox.ps1`、`targets.csv`、`CodexTool`フォルダー全体が同じ相対構造で配布されるよう登録します。
7. 引数は空欄にします。
8. 作業フォルダー／カレントフォルダー欄がある場合は、`RUN_AS_SYSTEM.cmd`が配置されるフォルダーを指定します。
9. 保存します。

### 8.3 実行設定

| 設定項目 | 設定値 |
|---|---|
| システム権限で実行する | **ON** |
| 実行主体 | `NT AUTHORITY\SYSTEM`／LocalSystem |
| 管理者資格情報 | 入力しない |
| 表示 | サイレント／非表示を推奨 |
| 再起動 | 強制しない |
| 実行時刻 | 対象ユーザーをサインアウトできる保守時間帯 |
| 最初の対象 | パイロット2台だけ |

付属スクリプトはSID`S-1-5-18`以外を拒否します。「管理者として実行」やドメイン管理者の保存資格情報では代用しません。

### 8.4 実行前チェック

- [ ] 対象ユーザーへ通知済み
- [ ] 対象ユーザーが**サインアウト**済み
- [ ] 他の対象ユーザーセッションが残っていない
- [ ] 対象端末がADへ到達可能
- [ ] `targets.csv`に当該端末の`Enabled=1`行が1件だけ
- [ ] 端末アーキテクチャとSYSTEM媒体が一致
- [ ] GPO／EDR例外は最小範囲で審査済み

### 8.5 実行

1. パイロット2台を選択します。
2. `01_CodexSandbox_SYSTEM_0.146.0_x64`を選びます。
3. `［実行］`を選びます。
4. 完了後、SKYSEAの終了コードを確認します。
5. 2台とも`0`になるまでUSERジョブへ進みません。

### 8.6 SYSTEMスクリプトが実行する内容

1. LocalSystem・64ビットPowerShellを確認
2. CSVの端末名完全一致行を1件だけ選択
3. ADアカウントをSIDへ変換
4. SIDの`ProfileList`と`Win32_UserProfile`を照合
5. 実フォルダー、`NTUSER.DAT`、ログオフ状態、再解析ポイントを検査
6. 既存`config.toml`の旧キー・プロファイル上書きを検査
7. Codexフルパッケージを二重にハッシュ検証
8. 次へACL保護して配置

```text
C:\ProgramData\OpenAI\CodexDeployment\Tools\0.146.0-x64
```

9. 次を絶対パスで実行

```powershell
codex.exe sandbox setup --elevated `
  --user "testdomain\tanaka-tarou" `
  --codex-home "C:\Users\tanaka-tarou\.codex"
```

実際のプロファイルパスはフォルダー名から推測せず、SIDのProfileListから取得します。

10. `config.toml`と`setup_marker.json`を事後検証
11. 対象SIDだけが読める承認状態を作成

```text
C:\ProgramData\OpenAI\CodexDeployment\State\AuthorizedTarget.json
```

このJSONは対象指定情報であり、sandboxのパスワードや秘密情報を含みません。

---

## 9. STEP 5: SYSTEMジョブの結果を確認する

### 9.1 成功条件

- SKYSEA終了コードが`0`
- 次が存在する

```text
C:\ProgramData\OpenAI\CodexDeployment\State\AuthorizedTarget.json
C:\ProgramData\OpenAI\CodexDeployment\Logs\<端末名>_sandbox_latest.json
C:\Users\<正式な対象プロファイル>\.codex\config.toml
C:\Users\<正式な対象プロファイル>\.codex\.sandbox\setup_marker.json
```

### 9.2 管理者PowerShellでの確認例

```powershell
Get-Content 'C:\ProgramData\OpenAI\CodexDeployment\State\AuthorizedTarget.json' -Raw |
  ConvertFrom-Json | Format-List

Get-Content 'C:\ProgramData\OpenAI\CodexDeployment\Logs\<端末名>_sandbox_latest.json' -Raw |
  ConvertFrom-Json | Format-List
```

対象ユーザーの正式なプロファイルを承認JSONで確認し、そのパスを使用します。

```powershell
$state = Get-Content 'C:\ProgramData\OpenAI\CodexDeployment\State\AuthorizedTarget.json' -Raw | ConvertFrom-Json
Test-Path $state.SetupMarkerPath
Get-Content $state.ConfigPath | Select-String '^\s*sandbox\s*=\s*["'']elevated["'']'
```

### 9.3 ログ

```text
C:\ProgramData\OpenAI\CodexDeployment\Logs\*_sandbox-setup.log
C:\Users\<対象>\.codex\.sandbox\sandbox.log
```

> [!CAUTION]
> `C:\Users\<対象>\.codex\.sandbox-secrets\`の内容は開かず、SKYSEAで回収せず、チケットやメールへ添付しないでください。

---

## 10. STEP 6: USERジョブを登録する

### 10.1 使用媒体

`SKYSEA_ChatGPT_USER.zip`を管理機で展開します。

```text
SKYSEA_ChatGPT_USER\
├─ RUN_AS_TARGET_USER.cmd
└─ Install-ChatGPTForAuthorizedUser.ps1
```

USER媒体には全対象者のCSVを含めません。端末のSYSTEMジョブが作った、対象SID専用の`AuthorizedTarget.json`だけを参照します。

### 10.2 画面操作

1. `［資産管理］→［アプリケーション一覧］→［ソフトウェア配布］`を開きます。
2. `［追加］`または`［配布パック作成］`を選びます。
3. `［実行ファイルやWindows更新プログラム］`を選びます。
4. パッケージ名を入力します。

```text
02_ChatGPT_USER_9PLM9XGG6VKS
```

5. 実行ファイルに次を指定します。

```text
RUN_AS_TARGET_USER.cmd
```

6. `Install-ChatGPTForAuthorizedUser.ps1`を同じフォルダーへ配布します。
7. 引数は空欄にします。
8. 保存します。

### 10.3 実行設定

| 設定項目 | 設定値 |
|---|---|
| システム権限で実行する | **OFF** |
| 実行主体 | 現在ログオン中のWindowsユーザー |
| 管理者資格情報 | 使用しない |
| 表示 | サイレント／非表示を推奨 |
| 対象 | SYSTEMジョブが終了コード`0`の端末だけ |
| 実行時刻 | 対象ユーザー本人がログオンしている時間帯 |

自社版に`ログオンユーザーとして実行`、`ユーザーセッションで実行`等の明示項目がある場合は、それを選びます。

> [!IMPORTANT]
> `winget`はLocalSystemコンテキストをサポートしません。単にSYSTEMをOFFにした結果が自社版でどの実行主体になるか不明な場合は、SKYSEA保守マニュアルまたはサポートで「現在ログオン中のユーザーとして実行される」ことを確認してください。付属スクリプトはSYSTEM／セッション0を終了コード`10`で拒否します。

### 10.4 実行

1. パイロット端末で対象ユーザー本人をログオンさせます。
2. SYSTEMジョブ成功済みの同じ2台を選択します。
3. `02_ChatGPT_USER_9PLM9XGG6VKS`を実行します。
4. 終了コードを確認します。

USERスクリプトは次を再照合します。

- 現在の端末名
- 現在のユーザーSID
- SYSTEMジョブが承認したSID
- 現在の`USERPROFILE`
- ProfileListのプロファイル
- Codexの`config.toml`
- Codexの`setup_marker.json`

USERジョブは標準ユーザー権限で動作し、特権が必要なCIM/WMI列挙には依存しません。SYSTEMジョブが保護保存したSIDと、現在のSID／ProfileListだけを再照合します。

すべて一致した場合だけ、Store照会結果に製品ID`9PLM9XGG6VKS`と発行元`OpenAI`が含まれることを確認してから次を実行します。

```powershell
winget show --id 9PLM9XGG6VKS --source msstore --exact

winget install --id 9PLM9XGG6VKS --source msstore --exact --silent `
  --accept-package-agreements --accept-source-agreements --disable-interactivity
```

別ユーザーがログオンしている場合は終了コード`20`で何も変更しません。

---

## 11. STEP 7: 対象ユーザーで受入確認する

対象ユーザー本人の通常権限PowerShellで実行します。

```powershell
winget list --id 9PLM9XGG6VKS --exact

Get-Content "$env:LOCALAPPDATA\OpenAI\CodexDeployment\Logs\ChatGPTInstallState.json" -Raw |
  ConvertFrom-Json | Format-List

Test-Path "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"

Get-Content "$env:USERPROFILE\.codex\config.toml" |
  Select-String '^\s*sandbox\s*=\s*["'']elevated["'']'
```

### 11.1 アプリ画面

1. Windowsスタートメニューで`ChatGPT`を検索します。
2. **新しいChatGPTアプリ**を起動します。
3. 組織のChatGPTアカウントでサインインします。
4. Codexを開きます。
5. 組織ポリシーに沿う承認モードを使用し、Full accessは選びません。
6. 検証用の空リポジトリまたはテスト用フォルダーを開きます。
7. 次を依頼します。

```text
PowerShellでwhoamiを実行し、結果だけを表示してください。ファイルは変更しないでください。
```

8. コマンド実行時にUAC画面が出ないことを確認します。
9. `whoami`の結果が実ユーザーではなく、Codex用のsandboxユーザーであることを確認します。
10. 組織のネットワーク・承認ポリシーどおりに動作することを確認します。

### 11.2 受入基準

- [ ] SYSTEMジョブ終了コード`0`
- [ ] USERジョブ終了コード`0`
- [ ] `winget list`で`9PLM9XGG6VKS`を確認
- [ ] 新アプリが起動
- [ ] 組織アカウントでサインイン
- [ ] `setup_marker.json`が存在
- [ ] トップレベルWindows sandboxが`elevated`
- [ ] 安全な`whoami`でUACが出ない
- [ ] 実ユーザーではなくsandboxユーザーで実行
- [ ] `sandbox.log`に反復するsetup失敗がない

---

## 12. 20名以上への段階展開

| 波 | 台数 | 条件 |
|---|---:|---|
| パイロット | 2台 | 標準端末1台と、ポリシー／プロファイル条件が異なる端末1台 |
| 第2波 | 5～10台 | パイロットの全受入基準を満たした後 |
| 本番波 | 残り | 第2波で共通障害が再発しないことを確認後 |

各波の順序は同じです。

```text
対象ユーザーをサインアウト
  → SYSTEMジョブ
  → 終了コード0の端末だけ対象ユーザーをログオン
  → USERジョブ
  → 受入確認
```

SYSTEMジョブとUSERジョブを同時に配布しません。

---

## 13. 終了コード

### 13.1 SYSTEMジョブ

| コード | 意味 | 主な確認箇所 |
|---:|---|---|
| `0` | 成功 | 次の波へ進む |
| `10` | 実行主体／ビット数不正 | LocalSystem、64ビットCMD経由 |
| `20` | CSV／対象端末不一致 | 端末名、Enabled、重複、配布媒体のCSV |
| `30` | AD／SID／プロファイル不正 | DC到達、ProfileList、NTUSER.DAT、ログオフ |
| `40` | Codex設定競合 | 旧キー、プロファイル配下のsandbox設定 |
| `50` | Codexパッケージ不正 | アーキテクチャ、フルパッケージ、SHA-256 |
| `60` | `codex sandbox setup`失敗 | GPO、EDR、Firewall、ログオン権利、sandbox.log |
| `70` | 事後検証失敗 | config、marker、承認状態 |
| `99` | 未分類 | 管理ログの例外メッセージ |

### 13.2 USERジョブ

| コード | 意味 | 主な確認箇所 |
|---:|---|---|
| `0` | 成功／既に導入済み | 受入確認へ進む |
| `10` | SYSTEM／セッション0／32ビット | ログオンユーザー実行設定 |
| `20` | 現在ユーザーが対象外 | 対象者本人をログオンさせる |
| `30` | SYSTEM承認状態なし／不正 | SYSTEMジョブを先に成功させる |
| `40` | SID／プロファイル／Codex状態不一致 | ProfileList、config、marker |
| `50` | winget／Store事前確認失敗 | App Installer、msstore、プロキシ |
| `60` | ChatGPTインストール失敗 | wingetログ、Storeサービス |
| `70` | インストール後検出失敗 | `winget list`、アプリ登録 |
| `99` | 未分類 | ユーザーログの例外メッセージ |

---

## 14. 主なトラブルシューティング

### 14.1 SYSTEM `20`: CSVに一致しない

```powershell
hostname
Import-Csv .\targets.csv | Format-Table
```

- `ComputerName`はFQDNでなく`hostname`の結果か
- 空白や全角文字がないか
- `Enabled=1`か
- 同一端末に有効行が2件ないか
- SKYSEAが旧媒体をキャッシュしていないか

### 14.2 SYSTEM `30`: SIDへ変換できない

```powershell
([System.Security.Principal.NTAccount]::new('testdomain\tanaka-tarou')).Translate(
  [System.Security.Principal.SecurityIdentifier]
).Value
```

- `Domain`は原則として`whoami`左側のNetBIOS名
- 社内LANまたはドメイン参照可能VPNへ接続
- ADアカウントの削除、改名、信頼関係を確認

### 14.3 SYSTEM `30`: ユーザーがログオン中

画面ロックではなく、Windowsの`サインアウト`を実行します。Fast User Switchingで残ったセッションも終了します。

```powershell
quser
```

### 14.4 SYSTEM `40`: config競合

対象ユーザーの`config.toml`を管理者が確認します。

停止対象の例:

```toml
[profiles.work.windows]
sandbox = "unelevated"
```

旧キーの例:

```toml
experimental_windows_sandbox = true
elevated_windows_sandbox = true
enable_experimental_windows_sandbox = true
```

勝手に削除せず、設定管理者が不要性を確認して整理します。完成形はトップレベルに次が存在し、プロファイル配下から矛盾する設定がない状態です。

```toml
[windows]
sandbox = "elevated"
```

### 14.5 SYSTEM `50`: パッケージ検証失敗

- x64媒体をArm64へ配っていないか
- `CodexTool`のフォルダー構造を維持したか
- SKYSEA登録後にファイルを差し替えていないか
- `SKYSEA_MEDIA_SHA256.csv`と元ZIPが一致するか

期待ハッシュをエラー回避のために書き換えません。承認版を更新する場合は第16章の変更手順を実施します。

### 14.6 SYSTEM `60`: sandbox setup失敗

確認対象:

- ローカルユーザー／グループ作成禁止
- Firewall／WFP変更禁止
- sandboxユーザーのログオン権利不足
- EDR／アプリ制御によるhelperブロック
- `C:\ProgramData`からの実行禁止

ログ:

```text
C:\ProgramData\OpenAI\CodexDeployment\Logs\...
C:\Users\<対象>\.codex\.sandbox\sandbox.log
```

### 14.7 USER `10`: ユーザーコンテキストではない

SKYSEAの`システム権限で実行する`をOFFにし、自社版の`ログオンユーザーとして実行`を選びます。ドメイン管理者資格情報で実行しません。

### 14.8 USER `20`: 別ユーザーがログオン

何も変更されていません。対象者本人へログオンし直して同じUSERジョブを再実行します。

### 14.9 USER `50`: wingetがない／Store sourceが使えない

対象ユーザーのPowerShellで確認します。

```powershell
Get-Command winget.exe
winget --version
winget source list
winget show --id 9PLM9XGG6VKS --source msstore --exact
```

Microsoft App Installer、Store source、プロキシ、地域、組織のStore制御を確認します。

### 14.10 UACが再び表示される

1. markerの存在
2. configのトップレベル`elevated`
3. 旧キー／プロファイル上書き
4. `sandbox.log`
5. ChatGPTアプリ更新後のsandbox setup version変化
6. GPO、Firewall、プロキシの変更

を確認します。承認した新しいCodexフルパッケージでSYSTEM媒体を更新し、対象ユーザーをサインアウトしてSYSTEMジョブを再実行します。

---

## 15. 新アプリと旧アプリを取り違えない

完成版が導入する製品IDは次です。

```text
9PLM9XGG6VKS
```

これはChat、Work、Codexを含む新しいChatGPTデスクトップアプリです。

過去のOpenAIヘルプには旧WindowsアプリのID`9NT1R1C2HH7J`が残っています。新旧が併存すると、旧アプリは`ChatGPT Classic`と表示される場合があります。本手順では旧IDを使用しません。

既存の旧アプリを削除するかは、利用者データと移行状況を確認した別の変更作業とし、新アプリ導入ジョブへ自動削除を組み込みません。

---

## 16. 更新運用

`0.146.0`は2026-08-04時点の承認スナップショットであり、永久固定値ではありません。

Codex CLIまたはChatGPTアプリ更新時:

1. OpenAI公式release channelで安定版を確認
2. 対応するWindowsフルパッケージ名とSHA-256を公式`codex-package_SHA256SUMS`で確認
3. `APPROVED_CODEX_VERSION.txt`と`APPROVED_CODEX_PACKAGE_HASHES.csv`を変更管理下で更新
4. コードレビュー／コード署名
5. `Run-Prepare-And-Build.cmd`で新媒体を作成
6. 新しい媒体名・ZIPハッシュを記録
7. 2台で現行ChatGPTアプリとの互換性を試験
8. 5～10台、残りの順でSYSTEMジョブを再実行

アプリが自動更新される環境では、UAC再表示やmarker version不整合を監視し、必要時に承認済みSYSTEM媒体を再実行します。

---

## 17. 導入中止・アンインストール

### 17.1 ChatGPTアプリを対象ユーザーから削除

対象ユーザー本人のログオンセッションで実行します。

```powershell
winget uninstall --id 9PLM9XGG6VKS --exact --silent --disable-interactivity
```

### 17.2 USERジョブの再実行を禁止

LocalSystemまたは管理者として、端末の承認状態を削除します。

```powershell
Remove-Item 'C:\ProgramData\OpenAI\CodexDeployment\State\AuthorizedTarget.json' -Force
```

これはChatGPTアプリやsandbox自体を削除しません。

### 17.3 sandbox構成を手作業で削除しない

公式に確認できる一括クリーンアップコマンドがない状態で、次を個別削除しません。

- `CodexSandbox*`のローカルユーザー／グループ
- CodexのFirewall／WFP設定
- `.sandbox`、`.sandbox-bin`、`.sandbox-secrets`
- Codexが設定したACLやログオン権利

完全撤去は別の変更管理とし、導入時のCodex版、ログ、OpenAI最新手順を確認します。

---

## 18. Microsoft配布サービスを初回導入に使えない場合

標準方式は、対象ユーザーコンテキストの`winget`です。Microsoft配布サービスを利用できない場合、OpenAI公式のエンタープライズ展開ページが提供するStore署名済みMSIXを使用できます。

- x64用MSIX
- Arm64用MSIX
- オフライン展開で必要なライセンスXML

この場合:

1. 公式MSIXと必要なライセンスを管理端末で取得
2. ファイルの署名・ハッシュ・アーキテクチャを確認
3. SKYSEAへ別のUSER配布パックとして登録
4. 対象ユーザー本人のログオンセッションで、自社標準の`Add-AppxPackage`等を使用
5. パイロットから開始

`Add-AppxProvisionedPackage -Online`で全ユーザー・将来ユーザーへ展開する方式は、今回の「対象者だけ」という要件に合わないため採用しません。winget方式とMSIX方式を同じ展開波で混在させません。

---

## 19. 最終チェックリスト

### 媒体作成前

- [ ] `targets.csv`に対象者を登録
- [ ] 1端末につき`Enabled=1`が1件
- [ ] CSVをUTF-8で保存
- [ ] SKYSEA対象グループとCSVを二者確認
- [ ] 承認Codex版とハッシュ表を確認
- [ ] `STATIC_VALIDATION.txt`と`SHA256SUMS.csv`を確認
- [ ] 準備端末のアーキテクチャを確認

### 媒体作成

- [ ] `Run-Prepare-And-Build.cmd`が成功
- [ ] SYSTEM ZIPとUSER ZIPが生成
- [ ] `SKYSEA_MEDIA_SHA256.csv`を変更管理票へ記録
- [ ] 必要な社内コード署名を適用済み

### SYSTEMジョブ

- [ ] フォルダー構造を保って登録
- [ ] `RUN_AS_SYSTEM.cmd`を指定
- [ ] システム権限をON
- [ ] 対象ユーザーをサインアウト
- [ ] 終了コード`0`
- [ ] AuthorizedTarget、config、markerを確認

### USERジョブ

- [ ] `RUN_AS_TARGET_USER.cmd`を指定
- [ ] システム権限をOFF
- [ ] 対象ユーザー本人をログオン
- [ ] 終了コード`0`
- [ ] `winget list --id 9PLM9XGG6VKS --exact`で確認

### 受入

- [ ] 新アプリが起動
- [ ] 組織アカウントでサインイン
- [ ] Codexの安全な`whoami`でUACなし
- [ ] sandboxユーザーで実行
- [ ] パイロット合格後に段階展開

---

## 20. 成果物の静的検証範囲

`STATIC_VALIDATION.txt`には、文字コード、Windows改行、PowerShellの文字列・コメント・区切り記号の整合、必須／禁止トークン、固定製品ID、承認済みCodexハッシュ、CSV列、CMDラッパー、Markdownコードフェンスの検査結果を記載しています。

ただし、作成環境にはWindows PowerShell実行系、Active Directory、SKYSEA、Microsoft Store、WinGet、Codex Windows helperがないため、PowerShell AST／実行時検証と実機統合試験は未実施です。この制約を補うため、2台のパイロットを本番展開の必須ゲートとします。

---

## 21. 参照した一次資料・製品資料

調査日は2026-08-04です。導入直前にも最新版を確認してください。

1. OpenAI, Deploy the Windows app  
   https://learn.chatgpt.com/docs/enterprise/windows-deployment
2. OpenAI, Moving to the new ChatGPT desktop app  
   https://help.openai.com/en/articles/20001276-moving-to-the-new-chatgpt-desktop-app
3. OpenAI, Windows sandbox  
   https://learn.chatgpt.com/docs/windows/windows-sandbox
4. OpenAI Codex PR #24831, Add Windows sandbox provisioning setup command  
   https://github.com/openai/codex/pull/24831
5. OpenAI Codex release channel  
   https://releases.openai.com/codex/channels/latest
6. Microsoft, Debugging and troubleshooting issues with WinGet — System Context  
   https://learn.microsoft.com/windows/package-manager/winget/troubleshooting
7. SKYSEA Client View, 資産管理／ソフトウェア配布  
   https://www.skyseaclientview.net/function/res/
8. SKYSEAの公開画面例を含む技術記事  
   https://www.netattest.com/zero-touch-certificate-distributionsoliton-keymanager-skysea-2024_tec_sol
