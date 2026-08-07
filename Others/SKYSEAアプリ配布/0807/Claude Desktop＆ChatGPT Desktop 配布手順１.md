以下を、**ChatGPTも `-SkipLicense` でプロビジョニングする構成**にした改訂版手順として使えます。
重要な注意点として、OpenAIはChatGPTのStore署名済みMSIXを企業配布向けに提供していますが、**ChatGPTに対して `-SkipLicense` を使うこのコマンド自体をOpenAI公式手順として掲載しているわけではありません**。Microsoftは `-SkipLicense` を「ライセンスを必要としないアプリ」にのみ使用するよう注意しています。したがって、まず検証端末で確認してから本番展開してください。([OpenAI Developers][1])

# SKYSEA Client View Ver.19

## Claude Desktop / ChatGPT Desktop 配布手順

### 1. 目的

SKYSEA Client View Ver.19 のソフトウェア配布機能を使用して、Windows端末へ以下の2アプリケーションを配布します。

1. Claude Desktop
2. ChatGPT Desktop

インストールは以下の順番で実行します。

```text
Claude Desktop
    ↓
Claudeのインストール完了
    ↓
ChatGPT Desktop
    ↓
ChatGPTのインストール完了
```

両方とも `Add-AppxProvisionedPackage` を使用するため、SKYSEAからSYSTEM／管理者権限で実行する構成とします。

---

# 2. 使用するインストールコマンド

## Claude Desktop

Anthropic公式が全ユーザー向け展開用として案内しているコマンドです。([Claudeヘルプセンター][2])

```powershell
Add-AppxProvisionedPackage -Online -PackagePath "Claude.msix" -SkipLicense -Regions "all"
```

## ChatGPT Desktop

今回使用するコマンドです。

```powershell
Add-AppxProvisionedPackage -Online -PackagePath "ChatGPT-x64.msix" -SkipLicense -Regions "all"
```

OpenAIは企業配布用としてStore署名済みの `ChatGPT-x64.msix` を公式に提供しています。Microsoftの配布サービスを利用できない環境では、このMSIXをMDMやソフトウェア配布プラットフォームへ取り込む方法が案内されています。([OpenAI Developers][1])

ただし、OpenAI公式資料では上記の `Add-AppxProvisionedPackage ... -SkipLicense` コマンド自体は案内されていません。

Microsoftによると `-SkipLicense` は、ライセンスを必要としないアプリに対して使用するパラメーターであり、それ以外のケースではWindowsイメージに問題を生じさせる可能性があります。([Microsoft Learn][3])

そのため、ChatGPTについては**検証端末で正常にプロビジョニング・起動できることを確認してから本番展開すること**を前提とします。

---

# 3. 配布ファイルの準備

以下の4ファイルを同じフォルダーに準備します。

```text
AIApps
│
├─ Install-AIApps.cmd
├─ Install-AIApps.ps1
├─ Claude.msix
└─ ChatGPT-x64.msix
```

`Claude.msix` と `ChatGPT-x64.msix` は、それぞれ公式配布元から取得したファイルを使用します。

この手順では、

```text
ChatGPT-License.xml
```

は使用しません。

ChatGPTを次のコマンドで処理するためです。

```powershell
Add-AppxProvisionedPackage -Online -PackagePath "ChatGPT-x64.msix" -SkipLicense -Regions "all"
```

---

# 4. Install-AIApps.cmd の作成

`Install-AIApps.cmd` を作成します。

内容は以下です。

```cmd
@echo off
setlocal

REM ============================================================
REM Claude Desktop / ChatGPT Desktop 配布用
REM
REM SKYSEA Client View から本CMDを実行します。
REM PowerShellスクリプトを ExecutionPolicy Bypass で起動します。
REM ============================================================


REM ============================================================
REM 使用するWindows PowerShellを指定します。
REM ============================================================

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"


REM ============================================================
REM SKYSEA側プロセスが32bitで動作している場合でも、
REM 64bit版Windows PowerShellを使用できるようにします。
REM ============================================================

if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" (
    set "POWERSHELL_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)


REM ============================================================
REM PowerShellスクリプトを実行します。
REM
REM -NoProfile
REM   ユーザー固有のPowerShellプロファイルを読み込みません。
REM
REM -NonInteractive
REM   ユーザー入力を要求しないモードで実行します。
REM
REM -ExecutionPolicy Bypass
REM   このPowerShellプロセスについてExecutionPolicyをBypassします。
REM
REM %~dp0
REM   このCMDファイルが存在するフォルダーです。
REM ============================================================

"%POWERSHELL_EXE%" ^
    -NoLogo ^
    -NoProfile ^
    -NonInteractive ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0Install-AIApps.ps1"


REM ============================================================
REM PowerShellの終了コードをSKYSEA側へ返します。
REM 0 = 正常終了
REM 0以外 = エラー
REM ============================================================

set "RC=%ERRORLEVEL%"

exit /b %RC%
```

---

# 5. Install-AIApps.ps1 の作成

続いて `Install-AIApps.ps1` を作成します。

このスクリプトでは、

```text
Claude
 ↓
完了待ち
 ↓
ChatGPT
```

の順番で処理します。

`Add-AppxProvisionedPackage` は同期的に処理されるため、Claudeのコマンドが終了する前にChatGPTのコマンドへ進むことはありません。

```powershell
#requires -version 5.1

# ============================================================
# Claude Desktop / ChatGPT Desktop
# SKYSEA Client View 配布用スクリプト
#
# 実行順序
#
#   1. Claude Desktop
#   2. Claude完了後
#   3. ChatGPT Desktop
#
# SKYSEAから管理者またはSYSTEM権限で実行することを想定しています。
# ============================================================


# ============================================================
# PowerShellでエラーが発生した場合、
# 処理を停止してCatchへ移動します。
# ============================================================

$ErrorActionPreference = "Stop"


# ============================================================
# インストールファイルのパスを設定します。
#
# $PSScriptRoot は、このPS1自身が存在するフォルダーです。
# SKYSEAの実行時カレントディレクトリに依存しないようにします。
# ============================================================

$ClaudePackage = Join-Path $PSScriptRoot "Claude.msix"
$ChatGPTPackage = Join-Path $PSScriptRoot "ChatGPT-x64.msix"


# ============================================================
# ログ保存先
# ============================================================

$LogDirectory = Join-Path $env:ProgramData "AIAppDeployment"

$LogFile = Join-Path `
    $LogDirectory `
    ("AIApps_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))


$ExitCode = 0
$TranscriptStarted = $false


try {

    # ========================================================
    # ログ保存フォルダーを作成します。
    # ========================================================

    New-Item `
        -ItemType Directory `
        -Path $LogDirectory `
        -Force |
        Out-Null


    # ========================================================
    # PowerShellの処理内容をログへ記録します。
    # ========================================================

    Start-Transcript `
        -Path $LogFile `
        -Append |
        Out-Null

    $TranscriptStarted = $true


    Write-Output "=================================================="
    Write-Output "AI Desktop Apps deployment started."
    Write-Output "=================================================="

    Write-Output ("Date       : {0}" -f (Get-Date))
    Write-Output ("Computer   : {0}" -f $env:COMPUTERNAME)
    Write-Output (
        "RunAs      : {0}" -f
        [Security.Principal.WindowsIdentity]::GetCurrent().Name
    )



    # ========================================================
    # 管理者権限の確認
    #
    # Add-AppxProvisionedPackage -Online を使用するため、
    # 管理者またはSYSTEM権限で実行されていることを確認します。
    # ========================================================

    $Identity = `
        [Security.Principal.WindowsIdentity]::GetCurrent()

    $Principal = `
        New-Object `
        Security.Principal.WindowsPrincipal($Identity)

    $IsAdministrator = `
        $Principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )


    if (-not ($Identity.IsSystem -or $IsAdministrator)) {

        throw `
            "管理者またはSYSTEM権限で実行されていません。SKYSEAの実行権限を確認してください。"
    }



    # ========================================================
    # Claude.msix の存在確認
    # ========================================================

    if (-not (
        Test-Path `
            -LiteralPath $ClaudePackage `
            -PathType Leaf
    )) {

        throw "Claude.msix が見つかりません: $ClaudePackage"
    }



    # ========================================================
    # ChatGPT-x64.msix の存在確認
    # ========================================================

    if (-not (
        Test-Path `
            -LiteralPath $ChatGPTPackage `
            -PathType Leaf
    )) {

        throw "ChatGPT-x64.msix が見つかりません: $ChatGPTPackage"
    }



    # ========================================================
    #
    # 1. Claude Desktop
    #
    # ========================================================

    Write-Output ""
    Write-Output "=================================================="
    Write-Output "STEP 1 : Claude Desktop"
    Write-Output "=================================================="

    Write-Output "Claude Desktop のプロビジョニングを開始します。"

    Write-Output (
        "Package : {0}" -f $ClaudePackage
    )


    # --------------------------------------------------------
    # Claude DesktopをWindowsへプロビジョニングします。
    #
    # このコマンドの処理が終了するまで、
    # PowerShellは次のChatGPT処理へ進みません。
    # --------------------------------------------------------

    Add-AppxProvisionedPackage `
        -Online `
        -PackagePath $ClaudePackage `
        -SkipLicense `
        -Regions "all" `
        -ErrorAction Stop


    Write-Output ""
    Write-Output "Claude Desktop の処理が正常終了しました。"



    # ========================================================
    #
    # 2. ChatGPT Desktop
    #
    # Claudeの処理が正常終了した場合のみ、
    # この処理へ進みます。
    #
    # ========================================================

    Write-Output ""
    Write-Output "=================================================="
    Write-Output "STEP 2 : ChatGPT Desktop"
    Write-Output "=================================================="

    Write-Output "ChatGPT Desktop のプロビジョニングを開始します。"

    Write-Output (
        "Package : {0}" -f $ChatGPTPackage
    )


    # --------------------------------------------------------
    # ChatGPT DesktopをWindowsへプロビジョニングします。
    #
    # 今回はChatGPT-License.xmlを使用せず、
    # -SkipLicense を指定します。
    #
    # 本番展開前に検証端末で正常動作を確認してください。
    # --------------------------------------------------------

    Add-AppxProvisionedPackage `
        -Online `
        -PackagePath $ChatGPTPackage `
        -SkipLicense `
        -Regions "all" `
        -ErrorAction Stop


    Write-Output ""
    Write-Output "ChatGPT Desktop の処理が正常終了しました。"



    # ========================================================
    # すべて正常終了
    # ========================================================

    Write-Output ""
    Write-Output "=================================================="
    Write-Output "SUCCESS"
    Write-Output "=================================================="

    Write-Output "Claude Desktop"
    Write-Output "ChatGPT Desktop"

    Write-Output "すべてのプロビジョニング処理が正常終了しました。"

}
catch {

    # ========================================================
    # ClaudeまたはChatGPTのどちらかでエラーになった場合
    # ========================================================

    $ExitCode = 1

    Write-Error (
        "インストール処理に失敗しました: {0}" -f
        $_.Exception.Message
    )

}
finally {

    # ========================================================
    # Transcriptログを終了します。
    # ========================================================

    if ($TranscriptStarted) {

        try {

            Stop-Transcript |
                Out-Null

        }
        catch {

            # Transcript終了処理のエラーでは、
            # インストール結果を変更しません。

        }

    }

}


# ============================================================
# SKYSEAへ終了コードを返します。
#
# 0 = 正常終了
# 1 = エラー
# ============================================================

exit $ExitCode
```

---

# 6. SKYSEAへ登録するファイル

配布対象は以下の4ファイルです。

```text
Install-AIApps.cmd
Install-AIApps.ps1
Claude.msix
ChatGPT-x64.msix
```

実行するファイルは、

```text
Install-AIApps.cmd
```

です。

PS1を直接実行するのではなく、

```text
SKYSEA
 ↓
Install-AIApps.cmd
 ↓
powershell.exe -ExecutionPolicy Bypass
 ↓
Install-AIApps.ps1
```

という構成にします。

---

# 7. SKYSEA Client Viewでの設定

## 画面

SKYSEA Client View管理機で、

```text
資産管理
 ↓
アプリケーション一覧
 ↓
ソフトウェア配布
```

へ移動します。

SKYSEAではソフトウェア配布機能により、管理機から指定したPCへソフトウェアを配布・インストールできます。([SkySea Client View][4])

---

## 配布設定

ClaudeとChatGPTを1つの処理にしているため、ソフトウェア配布の登録も1つにします。

登録内容の考え方は以下です。

```text
名称：
Claude・ChatGPT Desktop インストール

実行ファイル：
Install-AIApps.cmd

関連ファイル：
Install-AIApps.ps1
Claude.msix
ChatGPT-x64.msix

実行権限：
SYSTEM権限または管理者権限
```

ただし、**SKYSEA Client View Ver.19の公開資料から、ソフトウェア配布登録画面における各ボタン・項目の正確な名称や、上記4ファイルを1つの配布単位として登録する具体的な画面操作までは確認できません。**

その部分については、Ver.19のオンラインマニュアルまたは保守契約ユーザー用Webサイトの「ソフトウェア配布」手順に従ってください。

Sky社は保守契約ユーザー向けに、ソフトウェア配布用スクリプトやオンラインマニュアルを提供しています。([SkySea Client View][5])

---

# 8. SKYSEA Ver.19の重要な制限事項

SKYSEA Client View Ver.19について、Sky社公式の制限事項には、

```text
Windows ストアアプリは配布できません。
```

と記載されています。

また、

```text
配布 / インストールできるアプリケーションは、
Sky社が「ソフトウェア情報」を提供している
アプリケーションに限る
```

という制限もあります。([SkySea Client View][6])

したがって、

```text
SKYSEAから直接ChatGPT MSIXを
Windowsストアアプリとして配布する
```

方法については、Ver.19の公式サポート範囲外と考える必要があります。

今回想定しているのは、

```text
SKYSEA
 ↓
CMD / PS1 / MSIXファイルを展開
 ↓
SYSTEM権限でCMDを実行
 ↓
PowerShell
 ↓
Add-AppxProvisionedPackage
```

という**スクリプト経由の間接的なインストール方式**です。

この方式がSKYSEA Client View Ver.19の正式サポート対象になるかについては、公開資料から確認できません。

そのため、本番展開前にSky社サポートへ、

```text
SKYSEA Client View Ver.19のソフトウェア配布機能で
CMD・PS1・MSIXをクライアントPCへ配布し、

CMDからPowerShellを起動して、
Add-AppxProvisionedPackageによって
MSIXをプロビジョニングする運用は
正式サポート対象でしょうか。
```

と確認してください。

---

# 9. インストール実行

まず1台の検証用PCを配布対象にします。

SKYSEAから

```text
Install-AIApps.cmd
```

をSYSTEM／管理者権限で実行します。

処理順序は以下です。

```text
SKYSEA

 ↓

Install-AIApps.cmd

 ↓

powershell.exe
-ExecutionPolicy Bypass

 ↓

Install-AIApps.ps1

 ↓

Claude.msix
Add-AppxProvisionedPackage

 ↓
処理完了まで待機

 ↓

ChatGPT-x64.msix
Add-AppxProvisionedPackage

 ↓
処理完了まで待機

 ↓

正常終了
```

Claudeの処理でエラーになった場合、ChatGPTの処理は実行されません。

---

# 10. ログ確認

実行ログは、

```text
C:\ProgramData\AIAppDeployment
```

へ保存します。

ファイル名は例えば、

```text
AIApps_20260807_150000.log
```

です。

エラーになった場合は、このログを最初に確認してください。

Windows側のDISMログについても、

```text
C:\Windows\Logs\DISM\dism.log
```

がトラブルシューティングに利用できます。

---

# 11. プロビジョニング結果の確認

管理者PowerShellを起動して、

```powershell
Get-AppxProvisionedPackage -Online
```

を実行します。

ClaudeとChatGPTに該当するパッケージが表示されることを確認します。

`Add-AppxProvisionedPackage` により追加されたアプリは、Windowsイメージへプロビジョニングされ、既存ユーザー・新規ユーザーとも次回ログオン時に登録されます。オンラインイメージに追加した場合、現在ログオン中のユーザーには、その場では登録されず次回ログオン時に登録されるというMicrosoftの説明があります。([Microsoft Learn][7])

したがって、配布後は対象ユーザーで一度、

```text
サインアウト
 ↓
サインイン
```

を行って確認することを推奨します。

---

# 12. ユーザー側での確認

ユーザーがWindowsへ再ログオンした後、

```text
スタート
```

から、

```text
Claude
ChatGPT
```

が起動できることを確認します。

さらに対象ユーザーのPowerShellで、

```powershell
Get-AppxPackage
```

を実行して、ユーザーへパッケージが登録されていることを確認できます。

---

# 13. ChatGPTの `-SkipLicense` について

今回の手順ではユーザー指定に従い、

```powershell
Add-AppxProvisionedPackage `
    -Online `
    -PackagePath "ChatGPT-x64.msix" `
    -SkipLicense `
    -Regions "all"
```

を使用します。

ただし、この点だけは本番展開前の検証が必須です。

OpenAI公式は現在、Microsoftの配布サービスを利用しない企業配布向けとしてStore署名済みの、

```text
ChatGPT-x64.msix
ChatGPT-arm64.msix
```

を提供しています。

さらに、ライセンスファイルが必要なオフライン展開では、

```text
ChatGPT-License.xml
```

も取得するよう案内しています。([OpenAI Developers][1])

一方Microsoftは、

```text
-SkipLicense
```

について、ライセンスを必要としないアプリにのみ使用するよう説明しています。([Microsoft Learn][3])

したがって、ChatGPTについて、

```text
-SkipLicense
```

がOpenAIから明示的に保証されているとは確認できません。

検証端末で次のすべてを確認してください。

1. `Add-AppxProvisionedPackage` がエラー0で完了する
2. `Get-AppxProvisionedPackage -Online` にChatGPTが表示される
3. ユーザーが再ログオンするとChatGPTが登録される
4. ChatGPTが正常起動する
5. サインインできる
6. Windows再起動後も正常起動する
7. 標準ユーザーでも正常利用できる

これらを確認できない場合は、`ChatGPT-License.xml` を取得し、

```powershell
Add-AppxProvisionedPackage `
    -Online `
    -PackagePath "ChatGPT-x64.msix" `
    -LicensePath "ChatGPT-License.xml" `
    -Regions "all"
```

へ変更して再検証します。

---

# 14. 最終的な構成

```text
SKYSEA Client View Ver.19
│
│
├─ 資産管理
│    ↓
│  アプリケーション一覧
│    ↓
│  ソフトウェア配布
│
│
└─ Install-AIApps.cmd
       │
       └─ SYSTEM / 管理者権限
             │
             ↓
       Install-AIApps.ps1
             │
             ├─ ① Claude.msix
             │
             │   Add-AppxProvisionedPackage
             │   -Online
             │   -SkipLicense
             │   -Regions all
             │
             │        ↓ 完了
             │
             └─ ② ChatGPT-x64.msix

                 Add-AppxProvisionedPackage
                 -Online
                 -SkipLicense
                 -Regions all

                      ↓ 完了

                 正常終了
```

## 採用するChatGPTコマンド

```powershell
Add-AppxProvisionedPackage -Online -PackagePath "ChatGPT-x64.msix" -SkipLicense -Regions "all"
```

ただし、ChatGPTについてこの `-SkipLicense` 方式はOpenAI公式の明示されたインストールコマンドではないため、**検証環境で正常性を確認した上で本番展開する**ものとします。

この版では、**ClaudeとChatGPTを1つのCMD＋PS1に統合し、両方をSYSTEM権限で順番に処理する**構成にしています。特にChatGPTの `-SkipLicense` だけは、Microsoftの注意事項との関係から「検証必須」として扱うのが安全です。

[1]: https://developers.openai.com/codex/enterprise/windows-deployment "Deploy the Windows app | ChatGPT Learn"
[2]: https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows?utm_source=chatgpt.com "Deploy Claude Desktop for Windows"
[3]: https://learn.microsoft.com/en-us/powershell/module/dism/add-appxprovisionedpackage?view=windowsserver2025-ps "Add-AppxProvisionedPackage (Dism) | Microsoft Learn"
[4]: https://www.skyseaclientview.net/function/res/?utm_source=chatgpt.com "資産管理｜機能｜SKYSEA Client View"
[5]: https://www.skyseaclientview.net/support/guide/ "最新版ご提供・情報発信｜SKYSEA Client View"
[6]: https://www.skyseaclientview.net/product-info/limit/ver19/?utm_source=chatgpt.com "制限事項Ver.19｜機能｜SKYSEA Client View"
[7]: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options?view=windows-11&utm_source=chatgpt.com "DISM App Package (.appx or .appxbundle) Servicing ..."
