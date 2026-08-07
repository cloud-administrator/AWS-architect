はい。今回の条件なら、**PowerShellの実行ポリシーを恒久変更せず、SKYSEAから起動されるPowerShellプロセスだけ `Bypass` にする**のが適切です。

Microsoftの仕様でも、`powershell.exe -ExecutionPolicy ...` で指定したポリシーはそのPowerShellセッションだけに適用され、レジストリの実行ポリシーは変更しません。セッション終了後も残りません。([Microsoft Learn][1])

## 結論：SKYSEAでは `.ps1` を直接実行しない

現在はおそらく、

```text
SKYSEA
  ↓
Enable-VirtualMachinePlatform.ps1
  ↓
PowerShell
  ↓
「このシステムではスクリプトの実行が無効…」
```

となっています。

これを、

```text
SKYSEA
  ↓
Run-Enable-VMP.cmd
  ↓
powershell.exe -ExecutionPolicy Bypass
  ↓
Enable-VirtualMachinePlatform.ps1
```

に変更します。

**`Set-ExecutionPolicy` は使用しません。**

---

# 1. PowerShellスクリプトはそのままでOK

添付いただいたスクリプトは、`VirtualMachinePlatform` の状態を確認してから、有効でなければ `Enable-WindowsOptionalFeature` を実行し、ログを残す構成です。

ファイル名はそのまま、

```text
Enable-VirtualMachinePlatform.ps1
```

とします。

---

# 2. 起動用のCMDファイルを作成する

メモ帳を開き、以下を貼り付けてください。

```bat
@echo off
setlocal

REM 64bit PowerShellを指定
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

REM 32bitプロセスから実行されている場合は64bit PowerShellを使用
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" (
    set "POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

REM このPowerShellプロセスだけExecutionPolicyをBypassしてPS1を実行
"%POWERSHELL%" ^
    -NoLogo ^
    -NoProfile ^
    -NonInteractive ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0Enable-VirtualMachinePlatform.ps1"

REM PowerShellの終了コードをSKYSEAへ返す
exit /b %ERRORLEVEL%
```

次の名前で保存します。

```text
Run-Enable-VMP.cmd
```

ポイントはこの部分です。

```bat
-ExecutionPolicy Bypass
```

これは**このとき起動したPowerShellだけ**に適用されます。`LocalMachine` や `CurrentUser` の設定を書き換えません。Microsoftも、`powershell.exe -ExecutionPolicy` で指定した値は現在のセッションにのみ影響し、レジストリには保存されないと説明しています。([Microsoft Learn][1])

---

# 3. 2ファイルを同じフォルダに置く

配布元では、次のようにしてください。

```text
VMP_Enable
│
├─ Run-Enable-VMP.cmd
│
└─ Enable-VirtualMachinePlatform.ps1
```

**この2ファイルは同じフォルダに置くことが重要です。**

CMD内の

```bat
%~dp0Enable-VirtualMachinePlatform.ps1
```

は、

> 「このCMDファイルが置かれているフォルダにある `Enable-VirtualMachinePlatform.ps1`」

という意味です。

Microsoftも、バッチファイルから同じディレクトリのPowerShellスクリプトを指定する場合に `%~dp0` を使用する方法を案内しています。([Microsoft Learn][2])

---

# 4. まず手動でテストする

SKYSEA配布前に、テストPCで

```text
Run-Enable-VMP.cmd
```

を**管理者として実行**してください。

正常ならPowerShellの

> このシステムではスクリプトの実行が無効になっているため～

というエラーは出ず、`.ps1` が実行されます。

実行後は、添付スクリプトの仕様どおり、

```text
C:\ProgramData\SKYSEA_Enable_VirtualMachinePlatform.log
```

に結果が記録されます。

---

# 5. SKYSEAではCMDを実行対象にする

ここが重要です。

今まで、

```text
Enable-VirtualMachinePlatform.ps1
```

をSKYSEAから直接実行していたところを、

```text
Run-Enable-VMP.cmd
```

を実行するように変更します。

イメージは次のとおりです。

| ファイル                                | 用途                  |
| ----------------------------------- | ------------------- |
| `Run-Enable-VMP.cmd`                | **SKYSEAが実行するファイル** |
| `Enable-VirtualMachinePlatform.ps1` | CMDから呼び出される本体       |

SKYSEAは「ソフトウェア配布」機能で複数PCへのソフトウェアインストールや設定変更を一括実行する仕組みを提供しています。([SkySea Client View][3])

添付手順で使用していた、

**［資産管理］→［アプリケーション一覧］→［ソフトウェア配布］**

という流れはそのままです。

---

# 6. SKYSEA側では「システム権限で実行」をON

SKYSEAの実行オプションでは、

```text
☑ システム権限で実行する
```

をONにします。

これは元の手順と同じです。

したがって、実際の処理は、

```text
SKYSEA Client View
        ↓
SYSTEM権限
        ↓
Run-Enable-VMP.cmd
        ↓
powershell.exe
  -ExecutionPolicy Bypass
        ↓
Enable-VirtualMachinePlatform.ps1
        ↓
Enable-WindowsOptionalFeature
        ↓
VirtualMachinePlatform 有効化
```

となります。

---

# 7. 「恒久設定」は一切変更されない

今回の方法では、以下は実行しません。

```powershell
Set-ExecutionPolicy Bypass
```

また、

```powershell
Set-ExecutionPolicy RemoteSigned
```

も実行しません。

つまり、

```text
LocalMachine
CurrentUser
```

などのExecutionPolicyは変更しません。

Microsoftによれば、`powershell.exe -ExecutionPolicy Bypass` のような起動時指定は **Process相当**として扱われ、そのセッション終了時に消えます。([Microsoft Learn][1])

たとえば元の端末が、

```text
LocalMachine : Restricted
```

だったとしても、

```text
SKYSEA
 ↓
powershell.exe -ExecutionPolicy Bypass
```

で起動したPowerShellだけが、

```text
Process : Bypass
```

として動作します。

処理終了後は元に戻す操作も不要です。

---

# 8. 配布後に確認する

スクリプト実行後、

```text
C:\ProgramData\SKYSEA_Enable_VirtualMachinePlatform.log
```

を確認します。

たとえば、

```text
2026-08-07 14:00:00 Before=Disabled After=EnablePending
```

のようになっていれば、機能の有効化処理自体は成功しています。

その後PCを再起動します。

添付スクリプトは、

```powershell
-NoRestart
```

を使用しているため、スクリプト実行中には再起動しません。

再起動後、

```powershell
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
```

を実行し、

```text
FeatureName : VirtualMachinePlatform
State       : Enabled
```

になっていれば完了です。

---

## 重要：グループポリシーで強制されている場合

一点だけ例外があります。

実行ポリシーの優先順位は概ね、

```text
MachinePolicy
UserPolicy
Process（-ExecutionPolicy）
LocalMachine / CurrentUser
```

です。Microsoftによれば、**グループポリシーで設定された `MachinePolicy` / `UserPolicy` は `powershell.exe -ExecutionPolicy Bypass` より優先されます**。([Microsoft Learn][1])

ただし今回は、

> `-ExecutionPolicy Bypass` を付けると実行できる

とのことなので、少なくとも現在の環境では今回の方式で解決できる可能性が高いです。

---

## SKYSEA配布用の最終形

今回なら、この構成を推奨します。

```text
【配布ファイル】

Run-Enable-VMP.cmd
Enable-VirtualMachinePlatform.ps1


【SKYSEA】

資産管理
  ↓
アプリケーション一覧
  ↓
ソフトウェア配布
  ↓
2ファイルを対象PCへ配置
  ↓
Run-Enable-VMP.cmd を実行
  ↓
「システム権限で実行する」ON
  ↓
実行


【対象PC】

Run-Enable-VMP.cmd
  ↓
powershell.exe
-ExecutionPolicy Bypass
  ↓
Enable-VirtualMachinePlatform.ps1
  ↓
VirtualMachinePlatform
EnablePending
  ↓
PC再起動
  ↓
Enabled
```

**要するに「SKYSEAから `.ps1` を直接実行しない」のがポイントです。** `.cmd` を入口にして、その中から `powershell.exe -ExecutionPolicy Bypass -File ...` を呼び出せば、端末のExecutionPolicyを恒久変更せずに配布できます。

なお、SKYSEA Ver.19の画面上で「関連する2ファイルをどのように同一フォルダへ配布するか」は、契約形態・画面構成によって操作が異なる可能性があります。公開情報では詳細マニュアルが保守契約ユーザー向けとなっています。([SkySea Client View][3]) 添付資料でもVer.19では画面名称・配置が完全一致するとは限らない旨が整理されています。

[1]: https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1 "about_Execution_Policies - PowerShell | Microsoft Learn"
[2]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1 "about_PowerShell_exe - PowerShell | Microsoft Learn"
[3]: https://www.skyseaclientview.net/support/guide/ "最新版ご提供・情報発信｜SKYSEA Client View"
