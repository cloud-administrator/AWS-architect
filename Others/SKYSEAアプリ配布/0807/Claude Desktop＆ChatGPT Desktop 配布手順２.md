はい。この構成で進めるのが妥当です。ただし、**SKYSEA Client View Ver.19 の公式仕様上、「Windows ストアアプリは配布できません」**と明記されています。そのため今回の方式は、SKYSEAにMSIXを直接インストールさせるのではなく、**SKYSEAではファイル群とCMDを配布・実行し、Windows側のPowerShell/DISM機能でMSIXをプロビジョニングする方式**として整理するのが正確です。SKYSEA公式がこのClaude/ChatGPTの回避方式そのものを動作保証しているかは、公開資料からは確認できません。([SkySea Client View][1])

## 1. 今回の構成

管理PC側で、以下の5ファイルを同じフォルダーに用意することを推奨します。

```text
AIApps\
├─ Install-AIApps.cmd
├─ Install-AIApps.ps1
├─ Claude.msix
├─ ChatGPT-x64.msix
└─ ChatGPT-License.xml
```

Claudeについては、Anthropic公式が企業向けWindows配布方法として、まさに次のコマンドを案内しています。([Claude ヘルプセンター][2])

```powershell
Add-AppxProvisionedPackage -Online -PackagePath "Claude.msix" -SkipLicense -Regions "all"
```

ChatGPTについては、OpenAI公式が企業配布用として `ChatGPT-x64.msix` とオフラインライセンス `ChatGPT-License.xml` を提供しており、Microsoft Store配布サービスが使えない環境ではMDMやソフトウェア配布ツールへ取り込む方法を案内しています。([OpenAI Developers][3])

ただし、OpenAI公式には現時点で、次の**完全一致のPowerShellコマンドまでは記載されていません**。

```powershell
Add-AppxProvisionedPackage -Online -PackagePath "ChatGPT-x64.msix" -LicensePath "ChatGPT-License.xml" -Regions "all"
```

一方でMicrosoft公式では、`Add-AppxProvisionedPackage` に `PackagePath`、`LicensePath`、`Regions` が正式に存在し、`Regions "all"` も正式な指定値です。したがって、Windowsのコマンド仕様としては整合しています。([learn.microsoft.com][4])

---

# 2. CMDファイル

ファイル名を **`Install-AIApps.cmd`** とします。

```bat
@echo off
setlocal

REM ============================================================
REM Claude / ChatGPT デスクトップアプリ インストール起動用CMD
REM
REM SKYSEA Client View からは、このCMDファイルを実行します。
REM PowerShellスクリプトを ExecutionPolicy Bypass で起動します。
REM
REM %~dp0 は、このCMDファイルが配置されているフォルダーを表します。
REM そのため、SKYSEAの実行時カレントディレクトリに依存しません。
REM ============================================================

echo [INFO] Claude / ChatGPT のインストールを開始します。

REM ------------------------------------------------------------
REM PowerShellスクリプトを実行します。
REM -NoProfile
REM   ユーザー固有のPowerShellプロファイルを読み込みません。
REM
REM -ExecutionPolicy Bypass
REM   このPowerShellプロセスについてスクリプト実行を許可します。
REM
REM -File
REM   実行するPS1ファイルを指定します。
REM ------------------------------------------------------------
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-AIApps.ps1"

REM PowerShellから返された終了コードを保存します。
set RESULT=%ERRORLEVEL%

REM ------------------------------------------------------------
REM PowerShellが正常終了した場合は 0、
REM エラーの場合は 0以外をSKYSEA側へ返します。
REM ------------------------------------------------------------
if "%RESULT%"=="0" (
    echo [INFO] Claude / ChatGPT のインストールが正常終了しました。
) else (
    echo [ERROR] インストール中にエラーが発生しました。終了コード=%RESULT%
)

exit /b %RESULT%
```

---

# 3. PowerShellスクリプト

ファイル名を **`Install-AIApps.ps1`** とします。

このスクリプトでは、**Claudeが完全に終了してからChatGPTを開始**します。`Start-Process`などで非同期実行していないため、Claudeの `Add-AppxProvisionedPackage` が終了するまで次の処理には進みません。

また、Claudeでエラーが発生した場合はChatGPTを実行せず、その時点で異常終了させています。

```powershell
#Requires -Version 5.1

# ==============================================================
# Claude / ChatGPT デスクトップアプリ
# SKYSEA Client View 配布用インストールスクリプト
#
# 処理順序
#   1. 必要ファイルの存在確認
#   2. Claude のプロビジョニング
#   3. Claude の処理完了を待つ
#   4. ChatGPT のプロビジョニング
#   5. 終了コードを返す
#
# SKYSEAからは、Install-AIApps.cmd 経由で実行してください。
# ==============================================================

# エラー発生時に処理を継続せず、catchへ移動させます。
$ErrorActionPreference = "Stop"


# --------------------------------------------------------------
# このPS1ファイルが置かれているフォルダーを取得します。
#
# SKYSEAから実行した場合、カレントディレクトリが
# 配布ファイルのフォルダーとは限らないため、
# $PSScriptRoot を基準にファイルを参照します。
# --------------------------------------------------------------
$BaseDir = $PSScriptRoot


# --------------------------------------------------------------
# インストールに使用するファイル
# --------------------------------------------------------------
$ClaudeMsix     = Join-Path $BaseDir "Claude.msix"
$ChatGPTMsix    = Join-Path $BaseDir "ChatGPT-x64.msix"
$ChatGPTLicense = Join-Path $BaseDir "ChatGPT-License.xml"


# --------------------------------------------------------------
# ログ保存先
#
# SKYSEAが配布時に使用した一時フォルダーは、
# 後から削除される可能性があるため、
# ProgramData配下へログを保存します。
# --------------------------------------------------------------
$LogDir = Join-Path $env:ProgramData "AIAppDeployment\Logs"

New-Item `
    -Path $LogDir `
    -ItemType Directory `
    -Force | Out-Null


$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"

$LogFile = Join-Path `
    $LogDir `
    "Install-AIApps_$TimeStamp.log"

$ClaudeDismLog = Join-Path `
    $LogDir `
    "Claude_DISM_$TimeStamp.log"

$ChatGPTDismLog = Join-Path `
    $LogDir `
    "ChatGPT_DISM_$TimeStamp.log"


# --------------------------------------------------------------
# ログ出力用関数
# --------------------------------------------------------------
function Write-Log {

    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Line = "[$Now][$Level] $Message"

    Add-Content `
        -Path $LogFile `
        -Value $Line `
        -Encoding UTF8

    # SKYSEA側の実行結果にも表示させるため、
    # 標準出力にも同じ内容を出します。
    Write-Output $Line
}


# --------------------------------------------------------------
# 必要ファイルが存在するか確認する関数
# --------------------------------------------------------------
function Test-RequiredFile {

    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {

        throw "必要なファイルが見つかりません: $Path"
    }

    Write-Log "ファイル確認OK: $Path"
}


try {

    Write-Log "=================================================="
    Write-Log "Claude / ChatGPT インストール処理を開始します。"
    Write-Log "実行ユーザー: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Log "配布元フォルダー: $BaseDir"
    Write-Log "=================================================="


    # ----------------------------------------------------------
    # 管理者権限の確認
    #
    # Add-AppxProvisionedPackage は端末全体への
    # プロビジョニングを行うため、昇格された権限が必要です。
    # ----------------------------------------------------------
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $Principal = New-Object `
        Security.Principal.WindowsPrincipal($Identity)

    $IsAdministrator = $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $IsAdministrator) {

        throw "管理者権限で実行されていません。"
    }

    Write-Log "管理者権限の確認OK"


    # ----------------------------------------------------------
    # 必要な4ファイルを確認します。
    # ----------------------------------------------------------
    Write-Log "インストールファイルを確認します。"

    Test-RequiredFile $ClaudeMsix
    Test-RequiredFile $ChatGPTMsix
    Test-RequiredFile $ChatGPTLicense


    # ==========================================================
    # 1. Claude
    # ==========================================================

    Write-Log "--------------------------------------------------"
    Write-Log "Claude のインストールを開始します。"
    Write-Log "PackagePath = $ClaudeMsix"
    Write-Log "--------------------------------------------------"

    # Claude公式の全ユーザー向けプロビジョニングコマンドです。
    #
    # このコマンドが終了するまでPowerShellは次の処理へ進まないため、
    # Claudeの処理完了後にChatGPTが開始されます。
    Add-AppxProvisionedPackage `
        -Online `
        -PackagePath $ClaudeMsix `
        -SkipLicense `
        -Regions "all" `
        -LogPath $ClaudeDismLog `
        -ErrorAction Stop | Out-Null

    Write-Log "Claude のインストールが正常終了しました。"


    # ==========================================================
    # 2. ChatGPT
    # ==========================================================

    Write-Log "--------------------------------------------------"
    Write-Log "ChatGPT のインストールを開始します。"
    Write-Log "PackagePath = $ChatGPTMsix"
    Write-Log "LicensePath = $ChatGPTLicense"
    Write-Log "--------------------------------------------------"

    # ChatGPTのMSIXとオフラインライセンスを使用して、
    # Windowsへプロビジョニングします。
    Add-AppxProvisionedPackage `
        -Online `
        -PackagePath $ChatGPTMsix `
        -LicensePath $ChatGPTLicense `
        -Regions "all" `
        -LogPath $ChatGPTDismLog `
        -ErrorAction Stop | Out-Null

    Write-Log "ChatGPT のインストールが正常終了しました。"


    # ----------------------------------------------------------
    # すべて正常終了
    # ----------------------------------------------------------
    Write-Log "=================================================="
    Write-Log "Claude / ChatGPT のインストールがすべて完了しました。"
    Write-Log "=================================================="

    exit 0
}
catch {

    # ----------------------------------------------------------
    # エラー内容をログへ記録します。
    #
    # Claudeでエラーになった場合はChatGPTへ進みません。
    # ChatGPTでエラーになった場合も終了コード1を返します。
    # ----------------------------------------------------------

    Write-Log "==================================================" "ERROR"
    Write-Log "インストール処理でエラーが発生しました。" "ERROR"
    Write-Log $_.Exception.Message "ERROR"
    Write-Log ($_ | Out-String) "ERROR"
    Write-Log "==================================================" "ERROR"

    exit 1
}
```

Microsoft公式では `Add-AppxProvisionedPackage` の `-LogPath` も正式なパラメータです。指定しなければ通常はDISMログがWindows側に記録されますが、上記ではトラブルシュートしやすいよう独自ログ保存先を指定しています。([Microsoft Learn][4])

---

# 4. SKYSEA Client View Ver.19 での設定

ここは重要な点があります。**「アプリケーション一覧 ＞ ソフトウェア配布」までは公式公開情報で確認できますが、その先のVer.19の各ダイアログの正確なボタン名・項目名は、一般公開ページから確認できません。** SkyはVer.19向けに「ソフトウェア配布のためのソフトウェア情報作成ガイド」を用意していますが、詳細資料の一部は保守契約ユーザー向けです。したがって、存在を確認できないボタン名を断定はしません。([SkySea Client View][5])

実際の登録内容は、次のようにしてください。

| SKYSEA上の作業      | 設定内容                                           |
| --------------- | ---------------------------------------------- |
| 画面              | **アプリケーション一覧 ＞ ソフトウェア配布**                      |
| 配布設定            | 新しいソフトウェア配布設定を作成                               |
| 配布ファイル          | `Install-AIApps.cmd`                           |
|                 | `Install-AIApps.ps1`                           |
|                 | `Claude.msix`                                  |
|                 | `ChatGPT-x64.msix`                             |
|                 | `ChatGPT-License.xml`                          |
| 実行するファイル        | **`Install-AIApps.cmd` のみ**                    |
| CMDの引数          | なし                                             |
| PowerShellを直接指定 | **しない**                                        |
| 実行権限            | **管理者権限で実行できる設定**                              |
| 配布対象            | 最初はテストPC数台                                     |
| 実行日時            | PC利用の少ない時間帯を推奨                                 |
| 実行順序            | SKYSEAにはCMDだけを実行させ、CMD→PS1→Claude→ChatGPTの順で制御 |

SKYSEAのソフトウェア配布は、通常ユーザーが管理者権限を持っていないPCに対しても、管理者権限が必要なソフトウェアを配布・インストールする用途で利用されています。また、実行日時のスケジュール設定も公式に案内されています。([SkySea Client View][6])

特に今回のMSIXは処理に時間がかかる可能性があるため、**SKYSEA側に「配信～実行完了までの時間」「タイムアウト」等に相当する設定がある場合は短くしないでください**。Ver.19での正確な項目名は公開資料から確認できませんが、Sky公式の導入事例でも、スクリプト配布では「配信～実行完了までの時間は余裕を持って指定する」運用が紹介されています。([SkySea Client View][7])

---

# 5. 処理の流れ

今回の構成では以下の順番になります。

```text
SKYSEA Client View
      │
      │ ソフトウェア配布
      ▼
Install-AIApps.cmd
      │
      │ powershell.exe
      │ -ExecutionPolicy Bypass
      ▼
Install-AIApps.ps1
      │
      ├─ 必要ファイル存在確認
      │
      ├─ Claude.msix
      │    Add-AppxProvisionedPackage
      │
      │    ↓ 完了するまで待機
      │
      ├─ ChatGPT-x64.msix
      │    + ChatGPT-License.xml
      │    Add-AppxProvisionedPackage
      │
      │    ↓ 完了するまで待機
      │
      ▼
     完了
      │
      ├─ 正常 → exit 0
      └─ 異常 → exit 1
```

別途 `timeout` や `Start-Sleep` を入れて待機する必要はありません。`Add-AppxProvisionedPackage` 自体の処理が戻ってくるまでは次のPowerShell命令へ進まないためです。

---

# 6. インストール後の確認

対象PCで**管理者としてPowerShell**を開き、まず端末にプロビジョニングされたMSIXを確認します。

```powershell
Get-AppxProvisionedPackage -Online |
    Where-Object {
        $_.DisplayName -match "Claude|OpenAI|ChatGPT"
    } |
    Select-Object DisplayName, PackageName, Version
```

ユーザーへの登録状況も確認する場合は次を使用できます。

```powershell
Get-AppxPackage -AllUsers |
    Where-Object {
        $_.Name -match "Claude|OpenAI|ChatGPT"
    } |
    Select-Object Name, PackageFullName
```

なお、パッケージの内部IDは将来のリリースで変更される可能性があるため、上記の文字列検索はあくまで確認補助です。

今回のスクリプト自体のログは、

```text
C:\ProgramData\AIAppDeployment\Logs
```

に残ります。例えば、

```text
Install-AIApps_20260807_150000.log
Claude_DISM_20260807_150000.log
ChatGPT_DISM_20260807_150000.log
```

のようになります。

---

# 7. 運用上、特に注意する点

**SKYSEA Ver.19の公式制限事項では「Windows ストアアプリは配布できません」**。したがって今回の設計は「Windows Storeアプリの配布機能」として使うのではなく、**一般的なファイル配布・スクリプト実行をトリガーとしてWindowsのMSIXプロビジョニング機能を呼び出す**ものです。この方式がSKYSEA Ver.19のメーカーサポート対象になるかどうかは、公開情報だけでは判断できません。重要な本番環境であれば、Skyの保守窓口へ「ソフトウェア配布でCMDを実行し、そのCMDからPowerShellの `Add-AppxProvisionedPackage` をSYSTEM/管理者権限で実行する運用がサポート対象か」を確認するのが安全です。([SkySea Client View][1])

また、**アプリの更新管理をSKYSEA側で行いたいか、アプリ自身に任せるかを事前に決める必要があります**。Claude Desktopは既定で自動アップデートを行い、AnthropicはMDMでバージョン管理する場合は自動更新を無効化する運用も案内しています。([Claude ヘルプセンター][2]) ChatGPTも既定ではアプリ自身のアップデーターが有効で、OpenAIは組織側で更新管理する場合に `[features] in_app_updates = false` を設定して無効化する方法を公式に案内しています。([OpenAI Developers][8])

**まず1～3台の検証端末 → 一部部署 → 全社**の順で展開することを推奨します。特に、SKYSEA実行時の権限、既存ユーザープロファイルでのアプリ表示、再ログオン後の状態、プロキシ/AppLocker等の社内セキュリティ設定まで確認してから全台配布に進むのが安全です。AnthropicもMSIXについてAppLockerで制限される可能性を明記しています。([Claude ヘルプセンター][2])

[1]: https://www.skyseaclientview.net/product-info/limit/ver19/?utm_source=chatgpt.com "制限事項Ver.19｜機能｜SKYSEA Client View"
[2]: https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows "Deploy Claude Desktop for Windows | Claude Help Center"
[3]: https://developers.openai.com/codex/enterprise/windows-deployment "Deploy the Windows app | ChatGPT Learn"
[4]: https://learn.microsoft.com/en-us/powershell/module/dism/add-appxprovisionedpackage?view=windowsserver2025-ps "Add-AppxProvisionedPackage (Dism) | Microsoft Learn"
[5]: https://www.skyseaclientview.net/product-info/technicalsheet/ver19/allview.html?utm_source=chatgpt.com "技術資料ダウンロード｜機能｜SKYSEA Client View"
[6]: https://www.skyseaclientview.net/case/report/case159.html?utm_source=chatgpt.com "奈良市 様｜導入事例 - SKYSEA Client View"
[7]: https://www.skyseaclientview.net/case/report/case148.html?utm_source=chatgpt.com "北海道八雲町 様｜導入事例 - SKYSEA Client View"
[8]: https://developers.openai.com/codex/enterprise/manage-app-updates "Manage app updates | ChatGPT Learn"
