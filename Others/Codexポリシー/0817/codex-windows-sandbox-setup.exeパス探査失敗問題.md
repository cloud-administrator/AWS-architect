# 調査結果

## 結論

今回のエラーの**直接原因は、かなり高い確度で特定できます**。

> Codexが `rg` を実行する前に、Windowsのelevatedサンドボックスを更新するための
> `codex-windows-sandbox-setup.exe`
> を起動しようとしましたが、現在動作している `codex.exe` が、対応するヘルパーEXEの場所を解決できていません。

その結果、Codexは最終的に絶対パスではなく、

```text
codex-windows-sandbox-setup.exe
```

という**ファイル名だけ**で起動を試みます。しかし、そのEXEがカレントディレクトリや `PATH` 上にないため、Windowsから `program not found` が返されています。

現行のOpenAI公式ソースでも、サンドボックス・セットアップEXEを現在の `codex.exe` 周辺から探し、見つからなければファイル名だけにフォールバックする処理になっています。また、ヘルパーの起動に失敗した場所で `OrchestratorHelperLaunchFailed` が生成されます。今回のエラー文字列と一致しています。

したがって、現時点の判定は次のとおりです。

| 判定対象                                             | 判定                                                                   |
| ------------------------------------------------ | -------------------------------------------------------------------- |
| `rg` コマンドの問題                                     | **原因ではありません**。`rg` はまだ起動されていません                                      |
| `requirements.toml` のTOML構文                      | **直接原因ではありません**                                                      |
| `allowed_sandbox_implementations = ["elevated"]` | ヘルパー探索失敗の原因ではありません。ただし、弱い `unelevated` への切り替えを禁止するため、失敗がそのまま致命的になります |
| UACの拒否                                           | **今回の直接原因ではありません**。今回はUAC処理より前にヘルパーの起動自体に失敗しています                     |
| ドメインユーザー名                                        | **今回の直接原因ではありません**。ヘルパーが起動していないため、ユーザー情報を使う処理まで進んでいません               |
| サンドボックスの事前プロビジョニング                               | 実施内容自体が誤っているとは断定できません。ただし、事前プロビジョニング後もランタイム用ヘルパーは必要です                |
| 実行中の `codex.exe` とヘルパーの配置不整合                     | **最有力原因**です                                                          |
| EDR、ウイルス対策製品による削除・隔離                             | 可能性はありますが、現時点では不明です                                                  |

---

## エラーが発生する流れ

今回の処理は、おおむね次の順番です。

```text
ユーザーが rg の実行を要求
        ↓
Codexが現在のワークスペースに合わせて
elevatedサンドボックスを「setup refresh」
        ↓
codex-windows-sandbox-setup.exe を検索
        ↓
対応する場所に見つからない
        ↓
ファイル名だけで起動を試す
  codex-windows-sandbox-setup.exe
        ↓
PATH上にも存在しない
        ↓
program not found
        ↓
rgは起動されない
```

エラーに表示されている、

```text
helper=codex-windows-sandbox-setup.exe
```

にドライブ名やディレクトリ名が付いていないことが重要です。

正常に解決できていれば、ログには通常、次のような絶対パスが現れます。

```text
C:\Users\...\ .codex\packages\standalone\releases\...\codex-resources\
codex-windows-sandbox-setup.exe
```

ファイル名だけになっているため、Codex内部の相対パス探索が失敗し、フォールバック処理に入ったと判断できます。

---

# なぜ事前プロビジョニング後もヘルパーが必要なのか

ご利用になったPR #24831のコマンドは、管理者またはIT部門が事前に次の処理を行うためのものです。

```powershell
codex sandbox setup --elevated `
  --user "testdomain\tanaka-tarou" `
  --codex-home "C:\Users\tanaka-tarou\.codex"
```

PRでは、主に次の処理が追加されています。

* サンドボックス用ローカルユーザーの作成・更新
* ファイアウォール／WFP設定
* サンドボックス関連ディレクトリのACL設定
* 対象 `CODEX_HOME` への `windows.sandbox = "elevated"` の保存
* 初回利用時にユーザーへUACを出さないための事前準備

一方、このPRの説明には、IT管理環境におけるその後の更新調整までは解決しないことが明記されています。PR自体も「alpha provisioning path」として導入されています。([GitHub][1])

ここでは、次の2つを分けて考える必要があります。

### 事前プロビジョニング

端末に永続的なサンドボックス基盤を作る処理です。

```text
サンドボックスユーザー
ファイアウォール
ACL
設定マーカー
認証情報
```

### 実行時のsetup refresh

その時点の実行内容に合わせ、次のような情報を更新する処理です。

```text
今回のワークスペース
読み取り可能なディレクトリ
書き込み可能なディレクトリ
読み取り禁止／書き込み禁止パス
ネットワーク・プロキシ関連設定
```

現行ソースでは、この実行時更新にも `codex-windows-sandbox-setup.exe` を使用しています。したがって、事前プロビジョニングが成功していても、各クライアントが実行時に対応するヘルパーを見つけられなければ失敗します。

また、

```text
--codex-home C:\Users\tanaka-tarou\.codex
```

は、主として設定、サンドボックスマーカー、ログなどの保存先を指定します。各製品に同梱されている `codex-windows-sandbox-setup.exe` を、そのディレクトリへ一括インストールする指定ではありません。

---

# 3製品別の見立て

## 1. Codex CLI

### 判定

**原因の確度：高い**

CLIでは、次のような配置になっている可能性があります。

```text
実際に起動される公開ランチャー
C:\Users\<user>\AppData\Local\Programs\OpenAI\Codex\bin\codex.exe

完全なバージョン別パッケージ
C:\Users\<user>\.codex\packages\standalone\releases\<version>\bin\codex.exe

ヘルパー
C:\Users\<user>\.codex\packages\standalone\releases\<version>\
codex-resources\codex-windows-sandbox-setup.exe
```

公開ランチャー側から見た相対位置には `codex-resources` がなく、実際のヘルパーはバージョン別パッケージ側にあるため、探索に失敗する構成です。

OpenAI公式リポジトリのIssue #28457では、CLI 0.140.0について、今回と同一の、

```text
helper=codex-windows-sandbox-setup.exe
error=program not found
```

が報告されています。Issueでは、Codex自身の診断がバージョン別リリースとその `codex-resources` を認識していても、通常の公開ランチャーからの実行時にはファイル名だけにフォールバックしていることが示されています。このIssueは2026年8月13日時点でも未クローズです。

さらに、CLI 0.147.0への自動更新後、公開ランチャーのディレクトリには `codex.exe` が存在するものの、対応する `codex-resources` がなく、すべてのサンドボックスコマンドが同じ `program not found` になるIssue #38039も未クローズです。直接バージョン別の `bin\codex.exe` を起動すると成功したと報告されています。

2026年8月17日時点で公式GitHubの最新CLIリリースは0.147.0ですが、このバージョンでの同一エラー報告が残っているため、**単に最新版へ更新すれば必ず直るとは言えません**。([GitHub][2])

---

## 2. ChatGPTデスクトップアプリ

### 判定

**原因の確度：高い**

デスクトップアプリでは、ヘルパーがMSIXパッケージ内の次の場所に存在する一方、

```text
...\OpenAI.Codex_<version>\app\resources\
codex-windows-sandbox-setup.exe
```

実行側が、

```text
...\OpenAI.Codex_<version>\app
```

または、

```text
...\OpenAI.Codex_<version>
```

またはユーザー側に展開された別の `codex.exe` の周辺を探し、`app\resources` を見つけられない問題が報告されています。

Issue #30732では、今回と同じ `program not found` が発生し、実際にはヘルパーが `app\resources` に存在していたことが報告されています。さらに、セットアップ用ヘルパーだけを手動コピーすると、次に `codex-command-runner.exe` が見つからない問題が発生しています。Issueは未クローズです。

Issue #31708でも、デスクトップアプリがパッケージルート直下の誤った場所を参照し、実際の `app\resources` を参照できない問題が報告されています。こちらも未クローズです。

したがって、デスクトップアプリについては、**ヘルパーがパッケージに同梱されていても、起動中のCodexランタイムからその場所が見えていない**可能性が高いです。

---

## 3. VS Code拡張機能

### 判定

**原因の確度：中程度。正確な原因は現時点では不明です**

VS Code拡張機能には、過去にヘルパーEXE自体が拡張機能へ同梱されていなかった問題があります。

Issue #9744では、VS Code拡張機能0.4.62に `codex-windows-sandbox-setup.exe` が含まれず、同じ `program not found` が発生していました。Issue内では0.4.69でセットアップヘルパーとコマンドランナーが同梱されたことが確認され、その後Issueは完了扱いでクローズされています。

そのため、現在インストールされている拡張機能が十分に新しい場合、古い「同梱漏れ」とまったく同じ問題とは限りません。

考えられるのは、次のいずれかです。

* 古い拡張機能が残っている
* 拡張機能内の `codex.exe` とヘルパーのバージョンが一致していない
* `chatgpt.cliExecutable` で公開CLIランチャーを指定している
* 拡張機能がCLIの不完全なAppDataランチャーを利用している
* EDRなどにより拡張機能内のヘルパーだけが削除された
* ヘルパーは存在するが、依存モジュールの読み込みに失敗している

比較的新しいVS Code拡張機能26.616.71553でも、ヘルパーは実在するのに「指定されたモジュールが見つからない」という別形式の未解決Issueがあります。ただし、これは今回の「ファイル名だけで起動して `program not found`」とは少し異なるエラーです。

---

# 3製品を同じ端末へ入れた影響

今回の端末には、

* Codex CLI
* VS Code拡張機能
* ChatGPTデスクトップアプリ

の3つが入っています。

公式リポジトリのIssue #28278にも、この3製品が同じWindows端末にインストールされた環境で、複数の `codex.exe` エントリーポイントが存在し、親プロセスが対応する `codex-resources` を持たない別の `codex.exe` を選択する問題が報告されています。

例えば、同じ端末に次のような複数の実体が存在できます。

```text
C:\Users\<user>\AppData\Local\Programs\OpenAI\Codex\bin\codex.exe

C:\Users\<user>\.codex\packages\standalone\releases\<version>\
bin\codex.exe

C:\Users\<user>\.vscode\extensions\openai.chatgpt-<version>\
bin\windows-x86_64\codex.exe

C:\Program Files\WindowsApps\OpenAI.Codex_<version>\
app\resources\codex.exe

C:\Users\<user>\AppData\Local\OpenAI\Codex\bin\<hash>\codex.exe
```

重要なのは、**すべての `codex.exe` に対して、同じバージョンの2つのヘルパーが対応する位置に必要**という点です。

```text
codex-windows-sandbox-setup.exe
codex-command-runner.exe
```

別バージョンの `codex.exe` とヘルパーを混在させると、一時的にセットアップが通っても、その後のコマンド実行で別の問題になる可能性があります。

---

# 端末で確認すべき内容

以下は読み取り中心の確認です。まずすべてのCodex関連アプリを終了し、CLI、VS Code、デスクトップアプリを**1つずつ起動して再現**してください。

## 1. 実際に動いている `codex.exe` を確認する

エラーを再現した直後に、PowerShellで実行します。

```powershell
Get-CimInstance Win32_Process -Filter "Name='codex.exe'" |
    Select-Object ProcessId,
                  ParentProcessId,
                  ExecutablePath,
                  CommandLine |
    Format-List
```

確認するポイントは `ExecutablePath` です。

CLI、VS Code、デスクトップアプリをそれぞれ単独で起動し、このコマンドの結果を保存してください。

同じ `codex.exe` が3製品から使われているのか、各製品が別々の `codex.exe` を使っているのかを判断できます。

---

## 2. CLIの公開ランチャーを確認する

```powershell
codex --version

where.exe codex

Get-Command codex -All -ErrorAction SilentlyContinue |
    Select-Object CommandType, Name, Source, Path |
    Format-Table -AutoSize
```

次のパスが先頭に出る場合は、公式Issueと一致する可能性が高くなります。

```text
C:\Users\<user>\AppData\Local\Programs\OpenAI\Codex\bin\codex.exe
```

ランチャーの `bin` がジャンクションかどうかも確認します。

```powershell
$codexExe = (Get-Command codex.exe -ErrorAction SilentlyContinue).Source

if ($codexExe) {
    $codexDir = Split-Path $codexExe

    Get-Item $codexDir -Force |
        Format-List FullName, LinkType, Target, Attributes
}
```

---

## 3. CLIのバージョン別パッケージにヘルパーがあるか確認する

```powershell
$CodexHome = $env:CODEX_HOME

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = Join-Path $env:USERPROFILE ".codex"
}

$releaseRoot = Join-Path $CodexHome "packages\standalone\releases"

Get-ChildItem $releaseRoot -Directory -ErrorAction SilentlyContinue |
    ForEach-Object {
        [pscustomobject]@{
            ReleaseRoot   = $_.FullName
            CodexExe      = Test-Path (
                Join-Path $_.FullName "bin\codex.exe"
            )
            SetupHelper   = Test-Path (
                Join-Path $_.FullName `
                    "codex-resources\codex-windows-sandbox-setup.exe"
            )
            CommandRunner = Test-Path (
                Join-Path $_.FullName `
                    "codex-resources\codex-command-runner.exe"
            )
        }
    } |
    Format-Table -AutoSize
```

正常なバージョン別パッケージなら、原則として次の3列がすべて `True` になります。

```text
CodexExe       True
SetupHelper    True
CommandRunner  True
```

---

## 4. VS Code拡張機能を確認する

拡張機能のバージョンを確認します。

```powershell
code --list-extensions --show-versions |
    Select-String "openai\.chatgpt"
```

拡張機能フォルダー内のヘルパーを確認します。

```powershell
$vsExtRoot = Join-Path $env:USERPROFILE ".vscode\extensions"

Get-ChildItem $vsExtRoot -Directory `
    -Filter "openai.chatgpt*" `
    -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host "`nExtension: $($_.FullName)"

        Get-ChildItem $_.FullName -Recurse -File `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -in @(
                    "codex.exe",
                    "codex-windows-sandbox-setup.exe",
                    "codex-command-runner.exe",
                    "rg.exe"
                )
            } |
            Select-Object Name, FullName, Length, LastWriteTime
    }
```

外部CLIが指定されていないかも確認します。

```powershell
$settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"

Select-String -Path $settingsPath `
    -Pattern "chatgpt\.cliExecutable" `
    -Context 0, 2 `
    -ErrorAction SilentlyContinue
```

ここで、

```json
"chatgpt.cliExecutable":
  "C:\\Users\\...\\AppData\\Local\\Programs\\OpenAI\\Codex\\bin\\codex.exe"
```

のようになっていれば、VS Code拡張機能がCLI側の不完全な公開ランチャー問題を引き継いでいる可能性があります。

---

## 5. デスクトップアプリのパッケージを確認する

```powershell
$app = Get-AppxPackage -Name OpenAI.Codex `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

$app |
    Select-Object Name, Version, InstallLocation |
    Format-List
```

アプリが見つかった場合、ヘルパーを確認します。

```powershell
if ($app) {
    $resources = Join-Path $app.InstallLocation "app\resources"

    Write-Host "Resources directory: $resources"

    Get-ChildItem $resources -File `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -in @(
                "codex.exe",
                "codex-windows-sandbox-setup.exe",
                "codex-command-runner.exe"
            )
        } |
        Select-Object Name, FullName, Length, LastWriteTime
}
```

`WindowsApps` のアクセス制御により一覧取得が拒否されることがあります。その場合、一覧取得できなかったことだけではファイルが存在しないとは判断できません。

---

## 6. すべての既知の場所からヘルパーを検索する

```powershell
$CodexHome = $env:CODEX_HOME

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = Join-Path $env:USERPROFILE ".codex"
}

$roots = @(
    (Join-Path $CodexHome "packages\standalone\releases"),
    (Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex"),
    (Join-Path $env:LOCALAPPDATA "OpenAI\Codex"),
    (Join-Path $env:USERPROFILE ".vscode\extensions")
)

$app = Get-AppxPackage -Name OpenAI.Codex `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if ($app) {
    $roots += Join-Path $app.InstallLocation "app\resources"
}

$roots = $roots |
    Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -Unique

$helperFiles = foreach ($root in $roots) {
    Get-ChildItem $root -Recurse -File `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -in @(
                "codex-windows-sandbox-setup.exe",
                "codex-command-runner.exe"
            )
        }
}

$helperFiles |
    Select-Object Name, FullName, Length, LastWriteTime |
    Sort-Object Name, FullName |
    Format-Table -AutoSize
```

さらに、ファイル名だけで起動できる状態か確認します。

```powershell
Get-Command codex-windows-sandbox-setup.exe `
    -ErrorAction SilentlyContinue

Get-Command codex-command-runner.exe `
    -ErrorAction SilentlyContinue
```

何も表示されなければ、Codexがファイル名だけにフォールバックした場合は起動できません。

---

## 7. サンドボックスログを確認する

OpenAI公式ドキュメントでも、Windowsサンドボックス問題では `CODEX_HOME/.sandbox/sandbox.log` の収集が案内されています。また、`.sandbox-secrets` の内容は送付しないよう明記されています。([OpenAI Developers][3])

```powershell
$CodexHome = $env:CODEX_HOME

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = Join-Path $env:USERPROFILE ".codex"
}

$log = Get-ChildItem (Join-Path $CodexHome ".sandbox") `
    -File `
    -Filter "sandbox*.log" `
    -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$log |
    Select-Object FullName, LastWriteTime |
    Format-List

if ($log) {
    Get-Content $log.FullName -Tail 250 |
        Select-String -Pattern `
            "setup refresh",
            "codex-windows-sandbox-setup",
            "command-runner",
            "program not found",
            "module could not be found"
}
```

### ログの判定方法

次の場合は、パス探索問題がほぼ確定です。

```text
setup refresh: spawning codex-windows-sandbox-setup.exe
```

ヘルパーがバージョン別の `codex-resources` や `app\resources` に存在するのに、ログがファイル名だけなら、**存在するファイルをCodexが発見できていません**。

正常な探索では、次のように絶対パスになります。

```text
setup refresh: spawning
C:\Users\...\releases\<version>\codex-resources\
codex-windows-sandbox-setup.exe
```

---

# CLIで原因を確定する検証

検証端末では、公開ランチャーではなく、バージョン別リリースにある `codex.exe` を直接実行すると切り分けできます。

```powershell
$CodexHome = $env:CODEX_HOME

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = Join-Path $env:USERPROFILE ".codex"
}

$release = Get-ChildItem `
    (Join-Path $CodexHome "packages\standalone\releases") `
    -Directory `
    -ErrorAction Stop |
    Where-Object {
        Test-Path (Join-Path $_.FullName "bin\codex.exe")
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$root = $release.FullName
$codexExe = Join-Path $root "bin\codex.exe"
$setupExe = Join-Path $root `
    "codex-resources\codex-windows-sandbox-setup.exe"
$runnerExe = Join-Path $root `
    "codex-resources\codex-command-runner.exe"

[pscustomobject]@{
    ReleaseRoot   = $root
    CodexExe      = Test-Path $codexExe
    SetupHelper   = Test-Path $setupExe
    CommandRunner = Test-Path $runnerExe
} | Format-List
```

すべて `True` であれば、現在のPowerShellプロセスだけ一時的に対応するパスを先頭へ追加して起動します。

```powershell
$env:Path = (
    (Join-Path $root "bin") + ";" +
    (Join-Path $root "codex-resources") + ";" +
    $env:Path
)

& $codexExe
```

このCodexに `Get-Location` などの単純なコマンドを実行させます。

### 判定

* バージョン別の `codex.exe` では成功
* 通常の `codex` コマンドでは失敗

となった場合、CLIについては、

> AppData側の公開ランチャーと、バージョン別 `codex-resources` の配置不整合

がほぼ確定します。

この方法は公式Issueで確認されている暫定的な切り分け方法ですが、正式な恒久対策とは確認できません。

---

# 推奨する対応

## 1. 本番ポリシーはすぐに弱めない

OpenAI公式ドキュメントでは、`elevated` がより強いWindowsサンドボックスで、`unelevated` は制限された現在ユーザーのトークンを使用する弱いフォールバックです。また、

```toml
[windows]
allowed_sandbox_implementations = ["elevated"]
```

は `unelevated` へのフォールバックを禁止する設定です。([OpenAI Developers][3])

今回の問題はヘルパー探索なので、`unelevated` を許可することは根本修正ではありません。セキュリティ要件上必要であれば、引き続き `elevated` のみとするのが妥当です。

---

## 2. ヘルパーEXEを手作業で恒久コピーしない

次の対応は推奨しません。

```text
ヘルパーをWindowsAppsからAppDataへコピーする
ヘルパーをSystem32へコピーする
ヘルパーのディレクトリをマシン全体のPATHへ追加する
別バージョンのヘルパーを流用する
```

セットアップヘルパーだけをコピーしても、次に `codex-command-runner.exe` が見つからなくなる事例が公式リポジトリにあります。更新後に古いヘルパーが残り、`codex.exe` とヘルパーのバージョンが不一致になるリスクもあります。

---

## 3. CLIは検証用にバージョン別実体を直接使用する

公開ランチャーではなく、

```text
%USERPROFILE%\.codex\packages\standalone\releases\<version>\bin\codex.exe
```

を直接起動し、同じリリースの、

```text
codex-resources\codex-windows-sandbox-setup.exe
codex-resources\codex-command-runner.exe
```

を組として使用してください。

これはセキュリティポリシーを弱めず、ランチャー／リソース不整合だけを回避する検証になります。

ただし、企業向けの恒久運用として正式に保証された回避策であることは確認できていません。

---

## 4. VS Code拡張機能

まず、古い0.4.62以前ではないことを確認してください。少なくとも過去の同梱漏れは0.4.69で解消されたとIssue上では確認されています。

現在の拡張機能の場合は、

* 拡張機能フォルダーに両方のヘルパーがあるか
* `chatgpt.cliExecutable` が設定されていないか
* 設定されている場合、公開AppDataランチャーを指していないか
* VS Codeから実際にどの `codex.exe` が起動しているか

を確認する必要があります。

診断目的で `chatgpt.cliExecutable` を使用する場合は、公開ランチャーではなく、CLIの正確なバージョン別 `bin\codex.exe` を指定します。ただし、この設定を企業展開の正式な恒久策として利用できるかは、今回確認した公式ドキュメントだけでは不明です。

---

## 5. デスクトップアプリ

デスクトップアプリについては、手動でWindowsAppsパッケージを書き換えないでください。

今回確認した公式リポジトリでは、`app\resources` の探索に関するIssueが未クローズであり、全環境に適用可能な修正版のバージョンは確認できませんでした。

最新版への更新または再インストールでパッケージ欠損が修復される可能性はありますが、探索ロジックの問題であれば再発する可能性があるため、確実な解決策とは断定できません。

---

## 6. クライアント更新後の検証を必須にする

企業展開では、各更新後に最低限次を確認することを推奨します。

```text
codex.exeの実際のパス
codex.exeのバージョン
セットアップヘルパーの存在
コマンドランナーの存在
Get-Locationなどの読み取りコマンド
ワークスペース内の書き込み
ワークスペース外の書き込み拒否
ネットワーク制限
```

特にCLIでは、0.147.0への自動更新後に公開ランチャーだけが壊れたという未解決報告があるため、`codex --version` が成功するだけでは、サンドボックスが正常とは判断できません。

---

# 現時点で不明な点

次の情報が提示されていないため、3製品それぞれの最終的な原因までは確定できません。

1. Codex CLIのバージョン
2. VS Code拡張機能のバージョン
3. ChatGPTデスクトップアプリのパッケージバージョン
4. 各製品から実際に起動されている `codex.exe` の絶対パス
5. ヘルパーが端末上に存在するか
6. ヘルパーがEDRなどに隔離された履歴があるか
7. `.codex\.sandbox\sandbox*.log` に記録された起動パス
8. VS Codeの `chatgpt.cliExecutable` 設定の有無

特にVS Codeについては、過去の単純な同梱漏れは修正済みであるため、現在の拡張機能でも同じ原因なのか、外部CLIの選択問題なのかは不明です。

また、公式GitHub IssueはOpenAI公式リポジトリ内の情報ですが、Issue本文の多くは利用者による報告です。すべてがOpenAIメンテナーによって根本原因確認済みという意味ではありません。ただし、今回については、複数のIssue、現在のソースコード、エラーのファイル名だけへのフォールバックが一致しているため、**ヘルパーのパス解決／パッケージ配置不整合という原因分類の確度は高い**と判断しています。

---

# 最終判定

今回の最も可能性が高い原因は、次のとおりです。

> 事前プロビジョニングは成功している可能性があるが、Codex CLI、VS Code拡張機能、ChatGPTデスクトップアプリの各ランタイムが、実行時のsetup refreshで必要な `codex-windows-sandbox-setup.exe` を、自身の実行ファイルに対応するリソースディレクトリから解決できていない。
> 探索失敗後にヘルパー名だけで起動しようとするため、`program not found` になっている。

製品別には、

```text
CLI
→ 公開AppDataランチャーとバージョン別codex-resourcesの不整合が最有力

デスクトップアプリ
→ app\resourcesと実際の探索パスの不整合が最有力

VS Code
→ 拡張機能のバージョン、外部CLI指定、同梱ファイルの状況が不明
```

という判定です。

OpenAI公式ドキュメント上、CLI、IDE拡張機能、デスクトップアプリはいずれもローカルWindowsサンドボックスの対象で、管理された `requirements.toml` は3クライアントのローカル実行に適用されます。したがって、ポリシーの設計方針は妥当ですが、クライアントごとのバイナリ／ヘルパー配布と更新検証を別途行う必要があります。

[1]: https://github.com/openai/codex/pull/24831 "https://github.com/openai/codex/pull/24831"
[2]: https://github.com/openai/codex/releases/latest "https://github.com/openai/codex/releases/latest"
[3]: https://developers.openai.com/codex/windows/ "https://developers.openai.com/codex/windows/"
