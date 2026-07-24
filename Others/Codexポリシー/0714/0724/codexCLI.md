はい、可能です。現在の `install.ps1` は、環境変数 **`CODEX_RELEASE`** またはスクリプト引数 **`-Release`** でバージョンを受け取る実装になっています。未指定時は `latest` が使用されます。([ChatGPT][1])

### 現在のコマンド形式を維持する場合

例えば `0.131.0` をインストールするなら、PowerShellで次のように実行します。

```powershell
$env:CODEX_RELEASE = "0.131.0"
irm https://chatgpt.com/codex/install.ps1 | iex
```

実行後、環境変数を残したくない場合は削除します。

```powershell
Remove-Item Env:CODEX_RELEASE
```

1行にまとめることもできます。

```powershell
$env:CODEX_RELEASE="0.131.0"; irm https://chatgpt.com/codex/install.ps1 | iex; Remove-Item Env:CODEX_RELEASE
```

### `-Release` 引数を明示する場合

スクリプトをいったん保存して実行します。

```powershell
irm https://chatgpt.com/codex/install.ps1 -OutFile install-codex.ps1
.\install-codex.ps1 -Release "0.131.0"
Remove-Item .\install-codex.ps1
```

インストーラーは、指定されたバージョンをGitHub Releaseの `rust-v<バージョン>` タグとして解決します。`0.131.0`、`v0.131.0`、`rust-v0.131.0` の形式は正規化されます。対象リリースとWindows用アセットが存在しない場合はエラーになります。([ChatGPT][1])

インストール後の確認は次のコマンドです。

```powershell
codex --version
```

なお、公式ドキュメントで安定した公開インストーラー変数として掲載されているのは、現時点では主に `CODEX_NON_INTERACTIVE` と `CODEX_INSTALL_DIR` です。`CODEX_RELEASE` は現在のインストーラースクリプトには実装されていますが、公開ドキュメントには掲載されていないため、CIなどで長期利用する場合はスクリプト仕様の変更に注意してください。([developers.openai.com][2])

[1]: https://chatgpt.com/codex/install.ps1 "releases.openai.com"
[2]: https://developers.openai.com/codex/config-file/environment-variables "
  Environment variables | ChatGPT Learn
"
