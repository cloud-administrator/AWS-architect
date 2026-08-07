はい。確認できた範囲では、**「Claude.msix をSKYSEAに直接インストーラーとして登録する」のではなく、`Claude.msix` と PowerShell スクリプトをセットで配布し、SKYSEAからシステム権限で PowerShell を実行する**構成が適切です。

ただし、最初に重要な注意点があります。**SKYSEA Client View Ver.19 の公式制限事項には「Windows ストアアプリは配布できません」「配布 / インストールできるアプリケーションは、Sky社が『ソフトウェア情報』を提供しているアプリケーションに限る」と記載されています。** 一方、Sky公式はソフトウェア配布機能について、スクリプトやインストーラーを端末へ配布・実行する仕組みとも説明しています。Claude Desktop のMSIXをPowerShell経由で導入する方法が、Ver.19で**正式サポートされるかどうかまでは公開情報から確認できません**。したがって、本番展開前に検証端末での確認と、必要ならSkyサポートへの確認を推奨します。 ([SkySea Client View][1])

## 推奨する構成

Anthropic公式では、Windows端末の全ユーザー向けClaude Desktop配布に、まさにご提示のコマンドを案内しています。

```powershell
Add-AppxProvisionedPackage -Online -PackagePath "Claude.msix" -SkipLicense -Regions "all"
```

`Add-AppxProvisionedPackage` は、Claudeをマシン全体にプロビジョニングするための方法としてAnthropicが案内しており、標準ユーザーを含む端末上のユーザーが利用できる構成になります。Anthropic自身も、エンタープライズ管理ツールからPowerShellスクリプトラッパーを使ってこのコマンドを配信する方法を案内しています。 ([Claudeヘルプセンター][2])

したがって、SKYSEAでは次の2ファイルを**同じフォルダーとして配布**する構成を推奨します。

```text
ClaudeDeploy
├─ Claude.msix
└─ Install-Claude.ps1
```

`Install-Claude.ps1` は次のようにしてください。

```powershell
# PowerShellスクリプト内でエラーが発生した場合に、
# 処理を継続せず、即座にスクリプトを停止するように設定します。
$ErrorActionPreference = "Stop"

# このPowerShellスクリプト（.ps1）が置かれているフォルダーのパスを取得し、
# 同じフォルダー内にある「Claude.msix」のフルパスを作成します。
#
# 例：
# スクリプトの配置先が C:\Temp\ClaudeDeploy の場合
# $MsixPath は C:\Temp\ClaudeDeploy\Claude.msix になります。
$MsixPath = Join-Path $PSScriptRoot "Claude.msix"

# Claude.msix が指定した場所に存在するか確認します。
# ファイルが存在しない場合は、エラーメッセージを出力して
# スクリプトを停止します。
if (-not (Test-Path $MsixPath)) {
    throw "Claude.msix が見つかりません: $MsixPath"
}

# WindowsにClaude DesktopのMSIXパッケージを
# プロビジョニング（端末全体への登録）します。
#
# -Online
#   現在起動しているWindows OSを対象にします。
#
# -PackagePath
#   インストール対象となるClaude.msixのパスを指定します。
#
# -SkipLicense
#   Microsoft Storeのライセンスファイルを使用せずに
#   パッケージを登録します。
#
# -Regions "all"
#   すべての地域（リージョン）を対象として
#   パッケージをプロビジョニングします。
#
# -ErrorAction Stop
#   このコマンドでエラーが発生した場合、
#   エラーを無視せず処理を停止します。
Add-AppxProvisionedPackage `
    -Online `
    -PackagePath $MsixPath `
    -SkipLicense `
    -Regions "all" `
    -ErrorAction Stop

# すべての処理が正常に完了したことを示す終了コード「0」を返して
# PowerShellスクリプトを終了します。
# SKYSEAなどの管理ツールでは、一般的に終了コード0を
# 「正常終了」として判定します。
exit 0
```

`$PSScriptRoot` を使うのがポイントです。SKYSEAが実際にファイルを展開するフォルダーを固定値で指定する必要がなく、**PowerShellスクリプトと同じ場所にある `Claude.msix` を参照できます。**

---

# SKYSEA Client Viewでの設定手順

以下では、**画面ごとに何をするか**を明確にします。

なお、公開情報で確認できた最近のSKYSEA画面では、「資産管理 → アプリケーション一覧 → ソフトウェア配布」「インストール → 追加」「実行（オプション設定に移動）」「システム権限で実行する」という流れが確認できます。ただし、これはCloud Editionの公開手順であり、**Ver.19オンプレミスで項目名・配置が完全に同一かどうかまでは確認できません**。 ([Josys サポートセンター][3])

### ① 事前準備

Anthropic公式ページから、対象PCのCPUアーキテクチャに合ったClaude MSIXを取得します。公式では **x64版** と **arm64版** が別々に提供されています。一般的なIntel / AMD搭載Windows PCであれば通常はx64ですが、ARM端末が混在する場合は配布を分ける必要があります。 ([Claudeヘルプセンター][2])

作業用フォルダーを次のように準備します。

```text
C:\Work\ClaudeDeploy\
    Claude.msix
    Install-Claude.ps1
```

まずSKYSEAを使わず、**検証用Windows PCの管理者PowerShellから `Install-Claude.ps1` を実行し、正常にインストールできることを確認する**のが安全です。

---

### ② SKYSEA管理機：「アプリケーション一覧」を開く

SKYSEA Client View管理機で、

**［資産管理］
→［アプリケーション一覧］
→［ソフトウェア配布］**

を開きます。

この導線自体は、現在公開されているSKYSEAのソフトウェア配布手順でも確認できます。 ([Josys サポートセンター][3])

---

### ③ 「インストール」から新規登録する

「ソフトウェア配布」画面で、

**［インストール］
→［追加］**

を選択します。 ([Josys サポートセンター][3])

「ソフトウェア登録」画面が開きます。

設定イメージは次のとおりです。

| 項目        | 設定内容                      |
| --------- | ------------------------- |
| 種類        | **実行ファイルやWindows更新プログラム** |
| 表示名       | `Claude Desktop` など       |
| 配布対象      | **フォルダー**                 |
| 配布するフォルダー | `ClaudeDeploy` フォルダー      |
| 実行対象      | `Install-Claude.ps1`      |
| サイレント実行   | 有効にできる場合は有効               |

ここで1点、**「配布対象＝フォルダー」「ps1を実行対象として直接指定する」という組み合わせがVer.19の標準画面でそのまま設定可能かどうかは、公開されているVer.19資料だけでは確認できません。**

現在公開されている別環境のSKYSEA手順では、「実行ファイルやWindows更新プログラム」「配布対象：ファイル」「ps1ファイルを指定」「サイレントで実行する」という設定が確認されています。 ([Josys サポートセンター][3])

したがってVer.19でフォルダー＋ps1を直接指定できない場合は、Skyが保守契約ユーザー向けに提供している**ソフトウェア配布用スクリプト**を使用する方式になります。Sky公式でも、ソフトウェア配布用スクリプトを保守サイトで提供していることを案内しています。 ([SkySea Client View][4])

---

### ④ 配布先PCを選択する

登録が完了したら、「ソフトウェア配布」の一覧から、

**`Claude Desktop`**

として登録した設定を選択します。

次に「配布先端末選択」で、

**Claude DesktopをインストールするWindows PC**

を選択します。

最初は全社PCを選ばず、

```text
検証PC 1台
↓
IT部門 数台
↓
一部部署
↓
全社展開
```

の順番を推奨します。

対象PCを選択後、

**［実行（オプション設定に移動）］**

を選択します。この画面遷移は公開されているSKYSEA手順でも確認できます。 ([Josys サポートセンター][3])

---

### ⑤ 最重要：「システム権限で実行する」

「オプション設定」画面を開いたら、

**［システム権限で実行する］**

にチェックを入れます。

その後、

**［実行］**

をクリックします。公開されているSKYSEA配布手順でも、PowerShell実行時に「システム権限で実行する」を指定する方法が案内されています。 ([Josys サポートセンター][3])

今回のClaude配布ではここが重要です。

実行されるPowerShellは、

```powershell
Add-AppxProvisionedPackage -Online ...
```

によってWindows OSにアプリをプロビジョニングするため、**ユーザー権限での実行ではなく、昇格されたコンテキストで実行する構成**にします。Anthropicもマシン全体への展開にはこの方法を案内しています。 ([Claudeヘルプセンター][2])

---

# 実際の処理フロー

SKYSEAから見ると、処理は次のようになります。

```text
SKYSEA管理機
      │
      │ ソフトウェア配布
      ▼
対象Windows PC
      │
      ├─ Claude.msix
      │
      └─ Install-Claude.ps1
               │
               │ システム権限で実行
               ▼
      PowerShell
               │
               ▼
Add-AppxProvisionedPackage
 -Online
 -PackagePath Claude.msix
 -SkipLicense
 -Regions all
               │
               ▼
       Claude Desktop
      マシン全体にプロビジョニング
```

---

# ⑥ インストール結果を確認する

SKYSEA側の「実行完了」だけでなく、**最初の検証端末ではWindows側でも確認してください**。

管理者PowerShellから例えば、

```powershell
Get-AppxProvisionedPackage -Online |
    Where-Object DisplayName -Match "Claude"
```

でプロビジョニング状態を確認できます。

また、サインインしたユーザー側については、

```powershell
Get-AppxPackage -Name Claude
```

などで確認できます。Anthropicも企業管理下での検出例として `Get-AppxPackage -Name Claude` を案内しています。 ([Claudeヘルプセンター][2])

最終的には、

**Windowsスタートメニュー → Claude**

から起動し、ログイン画面まで正常に表示されることを確認してください。

---

# ⑦ AppLockerを利用している場合

会社PCでAppLockerを使用している場合は注意が必要です。

Anthropic公式も、MSIX形式のClaude DesktopがAppLockerによってブロックされる可能性があるため、

**Claude Desktopを許可アプリケーションに追加する**

または

**MSIXパッケージを許可するルールにする**

必要があると案内しています。 ([Claudeヘルプセンター][2])

したがって、

```text
SKYSEA上は「実行完了」
↓
しかしClaudeが起動しない
```

となった場合、AppLocker / WDAC等のアプリケーション制御も確認対象です。

---

# ⑧ Claudeの自動アップデートも事前に決める

これは社内展開では重要です。

Claude Desktopは、デフォルトでは**約4時間ごとにアップデートをチェックして自動適用**します。Anthropicは、端末管理ツール側でバージョンを管理する場合と、Claude自身に更新させる場合のどちらかに統一するよう案内しています。 ([Claudeヘルプセンター][2])

つまり会社として、

**A. SKYSEAでClaudeのバージョンを管理する**

または

**B. 初回インストールだけSKYSEAで行い、その後はClaude自身に自動更新させる**

のどちらにするか決めた方がよいです。

初回導入だけが目的なら、まずは **B** の方が運用は単純です。

---

# 現時点で「確認できること／確認できないこと」

| 項目                                                     | 結論                   |
| ------------------------------------------------------ | -------------------- |
| Claude Windows版にMSIXがある                                | **確認済み**             |
| x64 / arm64版がある                                        | **確認済み**             |
| 全ユーザー向けコマンド                                            | **確認済み**             |
| ご提示の `Add-AppxProvisionedPackage ...` が正しい             | **確認済み**             |
| PowerShellラッパーによる企業配布                                  | **Anthropic公式で案内あり** |
| SKYSEAにソフトウェア配布機能がある                                   | **確認済み**             |
| 「アプリケーション一覧 → ソフトウェア配布」の導線                             | **確認済み**             |
| SKYSEAからps1をシステム権限で実行する方式                              | **別環境で実例を確認**        |
| SKYSEA Ver.19でClaude MSIXが正式サポート対象                     | **確認できない**           |
| Ver.19でMSIX＋ps1のフォルダーをそのまま登録可能                         | **公開資料からは確認できない**    |
| SKYSEA Ver.19の「Windows ストアアプリは配布できない」制限とClaude MSIXの扱い | **Skyへの確認が必要**       |

特に最後の点が重要です。SKYSEA Ver.19公式資料には明確に「Windows ストアアプリは配布できません」とあります。 ([SkySea Client View][1])
そのため、**「Claude.msixをSKYSEAのネイティブなアプリ配布対象として登録できる」とは現時点では断言できません。** 今回の方法は、あくまで「SKYSEAでファイルを送り、システム権限のPowerShellからWindowsの `Add-AppxProvisionedPackage` を呼び出す」形にするのがポイントです。

必要であれば次に、**SKYSEA Ver.19の実際の「ソフトウェア登録」画面を想定した設定値を、①画面名 → ②クリックする場所 → ③入力値、という社内手順書形式**にして、そのまま作業者へ渡せる形まで整理できます。

[1]: https://www.skyseaclientview.net/product-info/limit/ver19/ "制限事項Ver.19｜機能｜SKYSEA Client View"
[2]: https://support.claude.com/ja/articles/12622703-windows%E7%94%A8claude-desktop%E3%81%AE%E3%83%87%E3%83%97%E3%83%AD%E3%82%A4 "Windows用Claude Desktopのデプロイ | Anthropicヘルプセンター"
[3]: https://jpsupport.josys.com/hc/ja/articles/5074770196126-SKYSEA-Client-View-%E3%82%AF%E3%83%A9%E3%82%A6%E3%83%89%E7%89%88-%E3%81%A7%E3%81%AE%E3%82%BD%E3%83%95%E3%83%88%E3%82%A6%E3%82%A7%E3%82%A2%E9%85%8D%E5%B8%83%E3%81%AE%E6%96%B9%E6%B3%95 "SKYSEA Client View（クラウド版） でのソフトウェア配布の方法 – ジョーシスヘルプセンター"
[4]: https://www.skyseaclientview.net/function/res/?utm_source=chatgpt.com "資産管理｜機能 - SKYSEA Client View"
