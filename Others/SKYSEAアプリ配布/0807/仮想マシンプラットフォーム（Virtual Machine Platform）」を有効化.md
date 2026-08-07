はい。今回の用途なら、**PowerShellスクリプトをSKYSEAの「ソフトウェア配布」でSYSTEM権限実行し、その後Windowsを再起動する**方法が適切です。

Anthropicの公式手順でも、Windows版Claude DesktopでCoworkを利用するために「仮想マシンプラットフォーム（Virtual Machine Platform）」を有効化する必要があり、次のPowerShellコマンドが案内されています。([Claudeヘルプセンター][1])

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
```

`-NoRestart` は自動再起動を抑止する指定です。**有効化を完了させるには、その後Windowsの再起動が必要**です。([Claudeヘルプセンター][1])

## まず結論：実施する流れ

推奨する順序は次のとおりです。

1. `Enable-VirtualMachinePlatform.ps1` を作成
2. SKYSEA Client View
   **［資産管理］→［アプリケーション一覧］→［ソフトウェア配布］**
3. スクリプトをソフトウェアとして登録
4. 対象PCを選択
5. **「システム権限で実行する」**を有効にして配布・実行
6. Windowsを再起動
7. 「仮想マシンプラットフォーム」が `Enabled` になっていることを確認
8. Claude Desktop / Coworkを確認

SKYSEAの公開情報でも「ソフトウェア配布」で複数PCへの設定変更をスクリプトで一括実行できることは確認できます。([SkySea Client View][2])

---

# 1. 配布するPowerShellスクリプトを作成

以下をメモ帳などに貼り付けて、

**`Enable-VirtualMachinePlatform.ps1`**

という名前で保存してください。

```powershell
$ErrorActionPreference = "Stop"

$LogPath = "$env:ProgramData\SKYSEA_Enable_VirtualMachinePlatform.log"

try {
    # 現在の状態を確認
    $Feature = Get-WindowsOptionalFeature `
        -Online `
        -FeatureName VirtualMachinePlatform

    $BeforeState = $Feature.State

    # 未有効の場合のみ有効化
    if ($BeforeState -notin @("Enabled", "EnablePending")) {

        Enable-WindowsOptionalFeature `
            -Online `
            -FeatureName VirtualMachinePlatform `
            -All `
            -NoRestart `
            -ErrorAction Stop | Out-Null
    }

    # 実行後の状態を確認
    $AfterState = (
        Get-WindowsOptionalFeature `
            -Online `
            -FeatureName VirtualMachinePlatform
    ).State

    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Before=$BeforeState After=$AfterState" |
        Out-File -FilePath $LogPath -Encoding UTF8 -Append

    if ($AfterState -in @("Enabled", "EnablePending")) {
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ERROR=$($_.Exception.Message)" |
        Out-File -FilePath $LogPath -Encoding UTF8 -Append

    exit 1
}
```

このスクリプトは、すでに有効になっているPCに再配布しても問題が起こりにくいよう、最初に状態を確認しています。

また、確認用として対象PCの

```text
C:\ProgramData\SKYSEA_Enable_VirtualMachinePlatform.log
```

に結果を残します。

Microsoftも `Enable-WindowsOptionalFeature` をWindowsオプション機能の有効化に使用する正式なコマンドとして案内しており、`-Online` は実行中のWindows、`-All` は必要な親機能も有効化、`-NoRestart` は再起動を抑止する指定です。([Microsoft Learn][3])

---

# 2. SKYSEAを開く

SKYSEA Client Viewの管理コンソールで、

**［資産管理］
→［アプリケーション一覧］
→［ソフトウェア配布］**

へ移動します。

この画面遷移は、公開されているSKYSEAのソフトウェア配布操作例でも確認できます。([Josysヘルプセンター][4])

---

# 3. スクリプトを登録する

［ソフトウェア配布］画面で、

**［インストール］→［追加］**

をクリックします。

「ソフトウェア登録」画面が表示されます。

設定イメージは次のとおりです。

| 項目         | 設定                                    |
| ---------- | ------------------------------------- |
| 種類         | **実行ファイルやWindows更新プログラム**             |
| 表示名        | `Claude Cowork - 仮想マシンプラットフォーム有効化` など |
| 配布対象       | **ファイル**                              |
| ファイル       | `Enable-VirtualMachinePlatform.ps1`   |
| サイレントで実行する | **ONを推奨**                             |

設定後、

**［OK］**

で登録します。

公開されているSKYSEAの操作例では、PowerShellの `.ps1` ファイルについて「配布対象：ファイル」で登録し、「サイレントで実行する」を選択する手順が確認できます。([Josysヘルプセンター][4])

### ここはVer.19について注意

上記の操作名称は、**2025年12月時点のSKYSEA Client Viewクラウド版の公開操作例**で確認できる名称です。

一方、**SKYSEA Client View Ver.19の詳細な操作マニュアルは一般公開されておらず、保守契約ユーザー向けオンラインマニュアル側にあります**。そのため、

* 「実行ファイルやWindows更新プログラム」
* 「配布対象」
* 「サイレントで実行する」

という文言・配置が**Ver.19のオンプレミス環境でも完全に同一であることまでは、公開情報から確認できません**。Sky株式会社自身も詳細マニュアルを保守契約ユーザー用Webサイトで提供しています。([SkySea Client View][2])

---

# 4. 配布対象PCを選択する

登録した

**「Claude Cowork - 仮想マシンプラットフォーム有効化」**

をソフトウェア一覧から選択します。

続いて「配布先端末選択」などの画面で、仮想マシンプラットフォームを有効にするWindows PCを選択します。

最初から全社PCへ配布するのではなく、

```text
IT管理者PC
↓
テスト用PC 2～5台
↓
一部部署
↓
全社
```

という順に展開することを推奨します。

対象PCを選択したら、公開操作例では、

**［実行（オプション設定に移動）］**

をクリックします。([Josysヘルプセンター][4])

---

# 5. 「システム権限で実行する」をONにする

ここが今回の設定で特に重要です。

「オプション設定」画面で、

**☑ システム権限で実行する**

をONにしてください。

その後、

**［実行］**

をクリックします。

公開されているSKYSEAの操作例でも、PowerShellスクリプト配布時にこの設定を使用しています。([Josysヘルプセンター][4])

今回のWindowsオプション機能変更は管理者権限が必要です。AnthropicもCoworkを含む完全なWindows版Claude Desktop環境には管理者権限が必要と案内しています。([Claudeヘルプセンター][1])

したがって、

> **「システム権限で実行する」は必須と考えてください。**

一般ユーザー権限で実行すると、有効化に失敗する可能性があります。

---

# 6. 配布・実行後、Windowsを再起動する

スクリプトには、

```powershell
-NoRestart
```

を付けています。

これは意図的です。

スクリプト配布直後に社員PCが突然再起動すると業務影響が大きいため、**機能の有効化とPC再起動は分けて管理する**方が安全です。

Anthropicも、このコマンドを実行した後にPCを再起動するよう案内しています。([Claudeヘルプセンター][1])

Microsoftも、Windows機能が `Enable Pending` の場合は再起動によって有効化が完了すると説明しています。([Microsoft Learn][5])

つまり、

```text
SKYSEA
  ↓
Enable-WindowsOptionalFeature
  ↓
VirtualMachinePlatform
  ↓
EnablePending
  ↓
Windows再起動
  ↓
Enabled
```

という流れになります。

**SKYSEA Ver.19のソフトウェア配布画面から再起動を直接指定できるか、その具体的な画面項目については、公開資料だけでは確認できません。**

そのため再起動については、

* SKYSEAで利用している既存のPC再起動運用
* 社内メッセージで再起動依頼
* メンテナンス時間帯で再起動

のいずれかを使用してください。

---

# 7. 再起動後に有効化を確認する

テストPCでPowerShellを開き、次を実行します。

```powershell
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
```

正常なら、

```text
FeatureName : VirtualMachinePlatform
State       : Enabled
```

となります。

`State : Enabled`

であればWindows側の「仮想マシンプラットフォーム」は有効です。

さらにCowork関連で問題がある場合は、

```powershell
Get-Service vmcompute,hns
```

も確認します。

Anthropic自身が、CoworkでHCS関連エラーが出る場合は `VirtualMachinePlatform` の状態と `vmcompute` / `hns` サービスを確認するよう案内しています。([Claudeヘルプセンター][1])

---

# 8. WindowsのGUIでも確認できる

テスト端末で、

**［コントロール パネル］
→［プログラム］
→［Windowsの機能の有効化または無効化］**

を開き、

```text
☑ 仮想マシン プラットフォーム
```

となっていれば有効です。

ただし大量展開時はGUI確認ではなく、PowerShellで確認する方が適しています。

---

# SKYSEAでの設定をまとめると

| 順番 | 画面         | 操作                                     |
| -: | ---------- | -------------------------------------- |
|  1 | 資産管理       | **アプリケーション一覧**                         |
|  2 | アプリケーション一覧 | **ソフトウェア配布**                           |
|  3 | ソフトウェア配布   | **インストール → 追加**                        |
|  4 | ソフトウェア登録   | **実行ファイルやWindows更新プログラム**              |
|  5 | ソフトウェア登録   | 表示名を入力                                 |
|  6 | ソフトウェア登録   | **配布対象＝ファイル**                          |
|  7 | ソフトウェア登録   | `Enable-VirtualMachinePlatform.ps1`を指定 |
|  8 | ソフトウェア登録   | **サイレントで実行する＝ON**                      |
|  9 | ソフトウェア配布   | 対象PCを選択                                |
| 10 | ソフトウェア配布   | **実行（オプション設定に移動）**                     |
| 11 | オプション設定    | **システム権限で実行する＝ON**                     |
| 12 | オプション設定    | **実行**                                 |
| 13 | Windows    | **PCを再起動**                             |
| 14 | Windows    | `State : Enabled` を確認                  |

手順1～2の画面経路、3～12の操作名称は公開されているSKYSEAの操作例に基づきますが、前述のとおり**Ver.19固有の画面について完全一致までは公開情報で確認できません**。([Josysヘルプセンター][4])

---

# Claude DesktopもSKYSEA配布する場合の重要な注意

今回の「仮想マシンプラットフォーム」とは別に、**Claude Desktop本体の企業配布方法にもCowork特有の注意点があります。**

Anthropicは現在、Windows企業環境向けにMSIXを提供していますが、単純に

```powershell
Add-AppxPackage
```

でユーザー単位にインストールすると、**Coworkが必要とする仮想化サービスがマシン全体に登録されず、Claudeは起動するのにCoworkだけ動かない場合がある**と明記しています。([Claudeヘルプセンター][1])

マシン全体への企業配布については、Anthropicは次の方式を案内しています。

```powershell
Add-AppxProvisionedPackage `
    -Online `
    -PackagePath "Claude.msix" `
    -SkipLicense `
    -Regions "all"
```

([Claudeヘルプセンター][1])

ただし、**SKYSEA Client View Ver.19でClaudeの現在のMSIXを直接配布する方法・正式対応可否については、公開されているSky株式会社の資料からは確認できません。** Ver.19の公開制限事項にはソフトウェア配布に関する制約もあるため、Claude本体の配布については少数端末での事前検証を強く推奨します。([SkySea Client View][6])

### 推奨する社内展開順序

私なら次の順序にします。

```text
① SKYSEAでVirtualMachinePlatform有効化
             ↓
② Windows再起動
             ↓
③ State=Enabledを確認
             ↓
④ Claude Desktopをマシン全体へ配布
             ↓
⑤ Claude起動
             ↓
⑥ Cowork起動テスト
             ↓
⑦ 問題なければ展開対象を拡大
```

この順序なら、**「Claudeのインストール問題」なのか「Windows仮想化の問題」なのかを切り分けやすくなります。**

なお、`VirtualMachinePlatform = Enabled` でもCoworkが起動しない場合は、BIOS/UEFI側のCPU仮想化設定、Windowsハイパーバイザー、VM/VDI環境におけるNested Virtualizationなどが次の確認ポイントになります。Anthropicは、ネストされた仮想化を利用できないVM/VDIではCoworkはサポートされないとも案内しています。([Claudeヘルプセンター][1])

[1]: https://support.claude.com/ja/articles/12622703-windows%E7%94%A8claude-desktop%E3%81%AE%E3%83%87%E3%83%97%E3%83%AD%E3%82%A4 "Windows用Claude Desktopのデプロイ | Anthropicヘルプセンター"
[2]: https://www.skyseaclientview.net/support/guide/?utm_source=chatgpt.com "最新版ご提供・情報発信｜SKYSEA Client View"
[3]: https://learn.microsoft.com/ja-jp/powershell/module/dism/enable-windowsoptionalfeature?view=windowsserver2022-ps&utm_source=chatgpt.com "Enable-WindowsOptionalFeature (DISM) | Microsoft Learn"
[4]: https://jpsupport.josys.com/hc/ja/articles/5074770196126-SKYSEA-Client-View-%E3%82%AF%E3%83%A9%E3%82%A6%E3%83%89%E7%89%88-%E3%81%A7%E3%81%AE%E3%82%BD%E3%83%95%E3%83%88%E3%82%A6%E3%82%A7%E3%82%A2%E9%85%8D%E5%B8%83%E3%81%AE%E6%96%B9%E6%B3%95 "SKYSEA Client View（クラウド版） でのソフトウェア配布の方法 – ジョーシスヘルプセンター"
[5]: https://learn.microsoft.com/ja-jp/windows-hardware/manufacture/desktop/enable-or-disable-windows-features-using-dism?view=windows-11&utm_source=chatgpt.com "DISM を使用して Windows の機能を有効または無効にする | Microsoft Learn"
[6]: https://www.skyseaclientview.net/product-info/limit/ver19/?utm_source=chatgpt.com "制限事項Ver.19｜機能｜SKYSEA Client View"
