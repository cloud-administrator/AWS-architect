## 結論

**Codex CLI、IDE拡張、app-server であれば、`C:\Users\Public\.codex` へ変更できます。**
公式に用意されている環境変数 `CODEX_HOME` を使います。

ただし、`%USERPROFILE%\.codex` は厳密には「Codex本体のインストール先」ではありません。設定、認証情報、セッション、ログ、スキル、キャッシュ、SQLiteデータ、スタンドアロン版のパッケージ情報などを格納する**Codexのユーザーデータ領域**です。実行コマンド自体は、公式Windowsインストーラーの場合、既定では `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin` に配置されます。([OpenAI Developers][1])

一方、**Windowsデスクトップアプリについては、2026年7月24日時点で事情が異なります。** 公式ドキュメントはWindowsアプリの保存先を `%USERPROFILE%\.codex` としており、`CODEX_HOME` の対応対象にもデスクトップアプリは明記されていません。さらに、2026年7月18日に「Windowsアプリが `CODEX_HOME` を無視する」という未解決のIssueが登録されています。そのため、Windowsアプリについては環境変数だけで移動できるとは考えない方が安全です。([OpenAI Developers][2])

## 利用形態ごとの判断

| 利用形態                         | `C:\Users\Public\.codex` への移動                      |
| ---------------------------- | -------------------------------------------------- |
| Codex CLI                    | 公式の `CODEX_HOME` で可能                               |
| VS Code等のCodex IDE拡張         | 公式の `CODEX_HOME` で可能                               |
| app-server                   | 公式の `CODEX_HOME` で可能                               |
| 公式 `install.ps1` のパッケージキャッシュ | `CODEX_HOME` に追従                                   |
| Windowsデスクトップアプリ             | 現状、公式な変更方法は確認できず。ジャンクションが回避策                       |
| 実際の `codex.exe` 配置先          | `CODEX_INSTALL_DIR` で別途変更可能。ただし公式スタンドアロンインストーラーに限る |

---

## CLI・IDE拡張で移動する方法

### 1. Codex関連プロセスを完全に終了する

次を終了してください。

* Codex CLI
* VS Code、Cursor等のIDE
* Codex Windowsアプリ
* バックグラウンドで動いているapp-server

セッション情報にはSQLiteデータも含まれるため、実行中のままコピー・移動するのは避けるべきです。`CODEX_SQLITE_HOME` も用意されていることから、CodexがSQLiteベースの状態を管理していることが公式に示されています。([OpenAI Developers][1])

### 2. 移動先を作成してデータをコピーする

PowerShellの例です。

```powershell
$oldHome = Join-Path $env:USERPROFILE '.codex'
$newHome = 'C:\Users\Public\.codex'

New-Item -ItemType Directory -Path $newHome -Force | Out-Null

if (Test-Path $oldHome) {
    robocopy $oldHome $newHome /E /COPY:DAT /DCOPY:DAT /R:2 /W:1

    if ($LASTEXITCODE -ge 8) {
        throw "Codexデータのコピーに失敗しました。Robocopy終了コード: $LASTEXITCODE"
    }
}
```

この段階では、元の `.codex` は削除しないでください。

### 3. ユーザー環境変数を設定する

ログオンユーザーが固定であれば、システム環境変数ではなく、**ユーザー環境変数**で十分です。

```powershell
$newHome = 'C:\Users\Public\.codex'

[Environment]::SetEnvironmentVariable(
    'CODEX_HOME',
    $newHome,
    'User'
)

# 今開いているPowerShellにも即時反映
$env:CODEX_HOME = $newHome
```

公式仕様では、`CODEX_HOME` に指定するディレクトリは事前に存在している必要があります。([OpenAI Developers][1])

設定確認は次のとおりです。

```powershell
[Environment]::GetEnvironmentVariable('CODEX_HOME', 'User')
$env:CODEX_HOME
```

どちらも次を返せば正常です。

```text
C:\Users\Public\.codex
```

### 4. IDEやターミナルを再起動して確認する

環境変数は起動済みプロセスには自動反映されないため、PowerShell、コマンドプロンプト、VS Code等をすべて再起動します。

その後、例えば次を確認します。

```powershell
codex login status
codex --version
Get-ChildItem 'C:\Users\Public\.codex'
```

新しいセッションを1件作成し、設定、ログイン状態、履歴などが維持されていることを確認してから、元のフォルダをバックアップ名に変更します。

```powershell
Rename-Item `
    -LiteralPath "$env:USERPROFILE\.codex" `
    -NewName '.codex.before-move'
```

数日間問題がなければ、バックアップを削除できます。

---

## 最初から `C:\Users\Public\.codex` を使う方法

公式のスタンドアロンインストーラーを実行する前に、次のように設定します。

```powershell
$codexHome = 'C:\Users\Public\.codex'

New-Item -ItemType Directory -Path $codexHome -Force | Out-Null

[Environment]::SetEnvironmentVariable(
    'CODEX_HOME',
    $codexHome,
    'User'
)

$env:CODEX_HOME = $codexHome

powershell -ExecutionPolicy ByPass -c "irm https://chatgpt.com/codex/install.ps1 | iex"
```

これにより、設定、認証、ログ、セッション、スキル、スタンドアロンパッケージキャッシュなどは `C:\Users\Public\.codex` 側に作成されます。([OpenAI Developers][1])

実行コマンド自体もPublic配下にしたい場合は、インストール前に `CODEX_INSTALL_DIR` も設定できます。

```powershell
$codexBin = 'C:\Users\Public\Codex\bin'

New-Item -ItemType Directory -Path $codexBin -Force | Out-Null

[Environment]::SetEnvironmentVariable(
    'CODEX_INSTALL_DIR',
    $codexBin,
    'User'
)

$env:CODEX_INSTALL_DIR = $codexBin
```

ただし、**実行ファイルまでPublic配下に置くことはあまり推奨しません。** 書き込み権限が広い場合、実行ファイルや更新用パッケージを別のローカルユーザーまたはプロセスに改変される危険があるためです。`CODEX_INSTALL_DIR` は公式の `install.ps1`／`install.sh` に対する設定であり、npm版のグローバルインストール先には適用されません。([OpenAI Developers][1])

---

## Windowsデスクトップアプリを使っている場合

現在のWindowsデスクトップアプリは `%USERPROFILE%\.codex` を参照する前提になっているため、`CODEX_HOME` を設定しても、次のように状態が分離する可能性があります。

```text
CLI:
C:\Users\Public\.codex

Windowsアプリ:
C:\Users\<ユーザー名>\.codex
```

この場合、以下の症状が発生します。

* CLIではログイン済みだが、アプリでは再ログインを要求される
* 設定変更が片方にしか反映されない
* セッション履歴が別々になる
* スキルやプラグインの状態が一致しない
* 古い場所に `.codex` が再作成される

現在報告されている回避策は、元のパスに**ディレクトリジャンクション**を作成する方法です。ただし、これは現時点では公式サポートされた移動機能ではありません。([GitHub][3])

概略は次のようになります。

```powershell
$oldHome = Join-Path $env:USERPROFILE '.codex'
$newHome = 'C:\Users\Public\.codex'

# Codexアプリ、CLI、IDEを完全に終了してから実施

# データを移動またはコピーし、元フォルダを退避
Rename-Item -LiteralPath $oldHome -NewName '.codex.before-junction'

# C:\Users\Public\.codex にデータが存在することを確認してから
cmd.exe /c "mklink /J `"$oldHome`" `"$newHome`""
```

`mklink /J` はWindowsのディレクトリジャンクションを作るコマンドです。([Microsoft Learn][4])

WindowsアプリとCLIの両方を使う場合は、次の構成が比較的一貫します。

```text
実データ:
C:\Users\Public\.codex

アプリが見るパス:
C:\Users\<ユーザー名>\.codex
  └─ ジャンクション → C:\Users\Public\.codex
```

この場合、CLI側も環境変数を使わず、既定の `%USERPROFILE%\.codex` を経由させれば、すべて同じ実データを参照できます。

---

# `C:\Users\Public` に置いた場合に起き得る問題

## 1. 認証情報や履歴のアクセス権が広くなる可能性

`.codex` には、次のようなデータが格納されます。

* `config.toml`
* `auth.json`
* `history.jsonl`
* セッションデータ
* ログ
* キャッシュ
* スキル
* SQLiteデータ
* スタンドアロン版パッケージ情報

認証方式によっては、ログイン情報が `auth.json` に**平文ファイルとして保存**されます。公式には、資格情報の保存先として `file`、`keyring`、`auto` が用意されており、`file` の場合は `CODEX_HOME\auth.json` に保存されます。([OpenAI Developers][5])

ログオンユーザーが1人だけであれば、ユーザー同士の競合は問題になりません。しかし、重要なのはログオン人数ではなく、対象フォルダのNTFSアクセス制御です。

次で確認できます。

```powershell
icacls 'C:\Users\Public\.codex'
```

`Everyone` や `BUILTIN\Users` に次の権限が付いている場合は注意が必要です。

```text
(F)   フルコントロール
(M)   変更
(W)   書き込み
```

少なくとも、以下が中心になるように設定するのが安全です。

* 現在のログオンユーザー
* `SYSTEM`
* `Administrators`
* Codexのサンドボックス設定によって追加された専用アカウント

`icacls` はWindowsのDACLを確認・変更する公式コマンドです。([Microsoft Learn][6])

## 2. Windowsサンドボックスの保護が弱くなる可能性

CodexのWindowsサンドボックスは、専用の低権限ユーザーやACL境界を使用します。公式ドキュメントでは、`Everyone` が書き込み可能なフォルダが存在すると警告され、サンドボックスが十分に保護できない可能性があると説明されています。([OpenAI Developers][7])

したがって、`C:\Users\Public\.codex` を作っただけで親フォルダの権限をそのまま継承させる構成は避けるべきです。

特に、`CODEX_HOME` にはスタンドアロン版のパッケージキャッシュも置かれます。書き込み権限が広い状態では、キャッシュや実行関連ファイルを改変されるリスクも考えられます。これはログオンユーザーが現在1人でも、将来のユーザー追加、リモート管理、別権限で動くソフトウェアなどを考えると無視できません。([OpenAI Developers][1])

## 3. WindowsアプリとCLIで保存場所が分裂する可能性

これは現時点で最も起きやすい機能上の問題です。

* CLIは `CODEX_HOME` を使用
* Windowsアプリは `%USERPROFILE%\.codex` を使用

という状態になると、履歴、設定、認証、スキル等が分離します。元の `.codex` が勝手に再作成されたように見える場合は、Windowsアプリまたは環境変数を認識していないプロセスが既定パスを使っている可能性があります。([GitHub][3])

## 4. 移動中のSQLite・セッションデータ破損

Codex実行中にフォルダを移動すると、書き込み中のセッションやSQLiteデータを不完全な状態でコピーする可能性があります。

通常の利用でCLIとIDEが同じホームを使うこと自体は想定されていますが、**移行作業中だけは全プロセスを終了する**ことが重要です。

## 5. 絶対パスを記述している設定が壊れる可能性

例えば `config.toml`、フック、MCP設定、独自スクリプトなどに次のような絶対パスがある場合です。

```toml
command = "C:\\Users\\username\\.codex\\scripts\\example.ps1"
```

移動後は次のように修正する必要があります。

```toml
command = "C:\\Users\\Public\\.codex\\scripts\\example.ps1"
```

Codex本体が管理する標準的なファイルは `CODEX_HOME` に追従しますが、ユーザー自身が記述した固定パスまでは自動変換されません。

## 6. ジャンクション特有の運用上の問題

Windowsアプリ向けにジャンクションを使う場合、次の点があります。

* 現在は公式に保証された構成ではない
* バックアップソフトがリンク先を重複保存することがある
* セキュリティソフトやクリーンアップソフトが再解析ポイントを特別扱いすることがある
* トラブル調査時に、表示上のパスと実体のパスが異なる
* アプリ更新後も同じ挙動が維持される保証がない
* 元フォルダを消すつもりでリンク先まで削除しないよう注意が必要

同じCドライブ内なので `/J` のディレクトリジャンクションを使いやすい点は利点です。

## 7. ユーザープロファイルのバックアップ対象から外れる

バックアップや移行ツールが `%USERPROFILE%` のみを対象にしている場合、`C:\Users\Public\.codex` がバックアップされない可能性があります。

逆に、Publicフォルダ全体を共通データとしてバックアップしている場合、認証情報やセッション履歴までバックアップ対象になる可能性があります。

## 8. WSLでは別途設定が必要

WSL内のCodex CLIは、Windows側のユーザー環境変数をそのまま利用しません。WSLから同じデータを利用する場合は、例えば次を設定します。

```bash
export CODEX_HOME=/mnt/c/Users/Public/.codex
```

永続化する場合は `~/.bashrc` または `~/.zshrc` に記載します。WindowsアプリとWSLでCodexホームを共有する方法として、公式にも `CODEX_HOME` の設定例があります。([OpenAI Developers][2])

---

## 認証情報をPublic配下に平文保存しない設定

CLIを使用している場合、`C:\Users\Public\.codex\config.toml` に次を設定すると、認証情報をWindowsの資格情報ストアへ保存できます。

```toml
cli_auth_credentials_store = "keyring"
```

これにより、認証情報そのものは `.codex\auth.json` ではなくOSの資格情報ストア側に保存されます。ただし、セッション履歴、ログ、ソースコード断片、コマンド出力などは引き続き `.codex` 側に残り得ます。([OpenAI Developers][5])

---

## 推奨構成

固定ユーザー1名で、CLIまたはIDE拡張を中心に使うのであれば、次の構成は実用上可能です。

```text
CODEX_HOME=C:\Users\Public\.codex
```

ただし、次の条件を満たすことを推奨します。

1. `C:\Users\Public\.codex` のACLを現在のユーザー中心に制限する
2. `Everyone`／`Users` の読み取り・書き込み権限を不用意に残さない
3. `cli_auth_credentials_store = "keyring"` を使用する
4. 移行時はCodex、IDE、Windowsアプリを完全終了する
5. 元フォルダはすぐに削除せず、動作確認後に削除する
6. Windowsデスクトップアプリを使う場合は、`CODEX_HOME` だけではなくジャンクション方式を検討する

ただ、ユーザー名に依存しない固定パスが目的なら、Publicではなく次のような専用フォルダの方が安全です。

```text
C:\CodexData\.codex
```

または、

```text
C:\ApplicationData\Codex\.codex
```

この方がPublicフォルダ由来の共通アクセス権を継承しにくく、用途も明確です。

**総合すると、CLI／IDE拡張だけならPublicへの移動は正式な方法で可能です。Windowsデスクトップアプリを含む場合は、現状ではジャンクションを使う非公式構成になります。ログオンユーザーが1人である点は競合問題をほぼ解消しますが、ACL、認証情報、Windowsサンドボックス、アプリとCLIの保存先分裂という問題は残ります。**

[1]: https://developers.openai.com/codex/config-file/environment-variables "
  Environment variables | ChatGPT Learn
"
[2]: https://developers.openai.com/codex/windows/windows-app "
  ChatGPT desktop app for Windows | ChatGPT Learn
"
[3]: https://github.com/openai/codex/issues/34070 "Codex Windows App uses hardcoded %USERPROFILE%\\.codex path — ignores CODEX_DIR / CODEX_HOME env vars · Issue #34070 · openai/codex · GitHub"
[4]: https://learn.microsoft.com/ja-jp/windows-server/administration/windows-commands/mklink?utm_source=chatgpt.com "mklink"
[5]: https://developers.openai.com/codex/auth "
  Authentication | ChatGPT Learn
"
[6]: https://learn.microsoft.com/ja-jp/windows-server/administration/windows-commands/icacls "icacls | Microsoft Learn"
[7]: https://developers.openai.com/codex/windows/windows-sandbox "
  Windows sandbox | ChatGPT Learn
"
