はい。その可能性を考慮して、**`Claude` / `ChatGPT` / `Codex` の3名称を対象**にするのがよいです。

OpenAIの現在の公式資料でも、新しいWindows版ChatGPTデスクトップアプリは Chat / Work / Codex を統合した構成になっています。ただし、MSIX内部の固定 `Name` / `PackageFamilyName` は公式資料では確認できないため、削除スクリプトでは `ChatGPT` と `Codex` の両方を検索対象にします。 ([OpenAI Help Center][1])

以下を **管理者権限のPowerShell** で実行してください。

```powershell
# ==============================================================
# Claude / ChatGPT / Codex
# アンインストール・削除スクリプト
#
# 管理者権限の PowerShell で実行してください。
#
# 処理内容
#   1. Claude / ChatGPT / Codex のプロセスを終了
#   2. インストール済みMSIXパッケージを取得
#   3. 全ユーザーからMSIXパッケージを削除
#   4. Windowsのプロビジョニングから削除
#   5. 残存しているMSIXユーザーデータを削除
# ==============================================================

$ErrorActionPreference = "Continue"

# --------------------------------------------------------------
# 削除対象として検索する名称
#
# ChatGPTのWindowsパッケージ内部名が公開情報から
# 確定できないため、ChatGPT と Codex の両方を対象にします。
# --------------------------------------------------------------
$TargetPattern = "(?i)Claude|ChatGPT|Codex"


# --------------------------------------------------------------
# 管理者権限チェック
# --------------------------------------------------------------
$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object `
    Security.Principal.WindowsPrincipal($CurrentIdentity)

$IsAdministrator = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdministrator) {

    Write-Host ""
    Write-Host "ERROR: 管理者権限でPowerShellを実行してください。" `
        -ForegroundColor Red

    exit 1
}


Write-Host ""
Write-Host "=============================================="
Write-Host " Claude / ChatGPT / Codex の削除を開始します"
Write-Host "=============================================="
Write-Host ""


# ==============================================================
# 1. アプリのプロセスを終了
# ==============================================================

Write-Host "[1/5] アプリを終了しています..."

$ProcessNames = @(
    "Claude",
    "ChatGPT",
    "Codex"
)

foreach ($ProcessName in $ProcessNames) {

    $Processes = Get-Process `
        -Name $ProcessName `
        -ErrorAction SilentlyContinue

    if ($Processes) {

        Write-Host "プロセス終了: $ProcessName"

        $Processes |
            Stop-Process `
                -Force `
                -ErrorAction SilentlyContinue
    }
}

# ファイルロック解除のため少し待機します。
Start-Sleep -Seconds 3


# ==============================================================
# 2. インストール済みMSIXパッケージを取得
# ==============================================================

Write-Host ""
Write-Host "[2/5] インストール済みパッケージを検索しています..."

$TargetPackages = @(
    Get-AppxPackage -AllUsers |
        Where-Object {

            $_.Name -match $TargetPattern -or
            $_.PackageFullName -match $TargetPattern -or
            $_.PackageFamilyName -match $TargetPattern
        }
)


# --------------------------------------------------------------
# 後で AppData\Local\Packages の残骸を削除するため、
# アンインストール前に PackageFamilyName を保存します。
# --------------------------------------------------------------

$PackageFamilyNames = @(
    $TargetPackages |
        Select-Object -ExpandProperty PackageFamilyName
) |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    } |
    Sort-Object -Unique


if ($TargetPackages.Count -gt 0) {

    Write-Host ""
    Write-Host "以下のパッケージが見つかりました。"

    $TargetPackages |
        Select-Object `
            Name,
            PackageFullName,
            PackageFamilyName |
        Format-Table -AutoSize

}
else {

    Write-Host "インストール済み対象パッケージは見つかりませんでした。"
}


# ==============================================================
# 3. 全ユーザーからMSIXパッケージを削除
# ==============================================================

Write-Host ""
Write-Host "[3/5] 全ユーザーからアプリを削除しています..."

foreach ($Package in $TargetPackages) {

    Write-Host ""
    Write-Host "削除対象:"
    Write-Host "  Name = $($Package.Name)"
    Write-Host "  PackageFullName = $($Package.PackageFullName)"

    try {

        Remove-AppxPackage `
            -Package $Package.PackageFullName `
            -AllUsers `
            -ErrorAction Stop

        Write-Host "削除成功: $($Package.Name)"
    }
    catch {

        Write-Warning "削除に失敗しました: $($Package.PackageFullName)"
        Write-Warning $_.Exception.Message
    }
}


# ==============================================================
# 4. プロビジョニングされたパッケージを削除
#
# Add-AppxProvisionedPackage でインストールしているため、
# こちらも削除します。
#
# これを残すと、新規ユーザーにアプリが登録される
# 可能性があります。
# ==============================================================

Write-Host ""
Write-Host "[4/5] プロビジョニングを確認・削除しています..."

$ProvisionedPackages = @(
    Get-AppxProvisionedPackage -Online |
        Where-Object {

            $_.DisplayName -match $TargetPattern -or
            $_.PackageName -match $TargetPattern
        }
)


if ($ProvisionedPackages.Count -gt 0) {

    Write-Host ""
    Write-Host "以下のプロビジョニングパッケージが見つかりました。"

    $ProvisionedPackages |
        Select-Object DisplayName, PackageName |
        Format-Table -AutoSize
}
else {

    Write-Host "対象のプロビジョニングパッケージは見つかりませんでした。"
}


foreach ($Package in $ProvisionedPackages) {

    Write-Host ""
    Write-Host "プロビジョニング削除:"
    Write-Host "  $($Package.PackageName)"

    try {

        Remove-AppxProvisionedPackage `
            -Online `
            -PackageName $Package.PackageName `
            -ErrorAction Stop |
            Out-Null

        Write-Host "プロビジョニング削除成功"
    }
    catch {

        Write-Warning `
            "プロビジョニング削除に失敗しました: $($Package.PackageName)"

        Write-Warning $_.Exception.Message
    }
}


# ==============================================================
# 5. 残存しているMSIXユーザーデータを削除
#
# 対象:
#
# C:\Users\<ユーザー名>\
#     AppData\Local\Packages\<PackageFamilyName>
#
# アンインストール前に実際に取得できた
# PackageFamilyNameだけを使用します。
#
# "Claude" や "Codex" という文字だけでフォルダーを
# 無差別に削除しないため、この方法にしています。
# ==============================================================

Write-Host ""
Write-Host "[5/5] 残存ユーザーデータを確認しています..."

$UserProfiles = @(
    Get-CimInstance Win32_UserProfile |
        Where-Object {

            -not $_.Special -and
            -not [string]::IsNullOrWhiteSpace($_.LocalPath)
        }
)


foreach ($Profile in $UserProfiles) {

    foreach ($PackageFamilyName in $PackageFamilyNames) {

        $PackageDataPath = Join-Path `
            $Profile.LocalPath `
            "AppData\Local\Packages\$PackageFamilyName"

        if (Test-Path -LiteralPath $PackageDataPath) {

            Write-Host ""
            Write-Host "残存データ削除:"
            Write-Host "  $PackageDataPath"

            try {

                Remove-Item `
                    -LiteralPath $PackageDataPath `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop

                Write-Host "削除成功"
            }
            catch {

                Write-Warning "削除に失敗しました:"
                Write-Warning $PackageDataPath
                Write-Warning $_.Exception.Message
            }
        }
    }
}


# ==============================================================
# 削除結果確認
# ==============================================================

Write-Host ""
Write-Host "=============================================="
Write-Host " 削除結果を確認しています"
Write-Host "=============================================="


$RemainingAppx = @(
    Get-AppxPackage -AllUsers |
        Where-Object {

            $_.Name -match $TargetPattern -or
            $_.PackageFullName -match $TargetPattern -or
            $_.PackageFamilyName -match $TargetPattern
        }
)


$RemainingProvisioned = @(
    Get-AppxProvisionedPackage -Online |
        Where-Object {

            $_.DisplayName -match $TargetPattern -or
            $_.PackageName -match $TargetPattern
        }
)


if (
    $RemainingAppx.Count -eq 0 -and
    $RemainingProvisioned.Count -eq 0
) {

    Write-Host ""
    Write-Host "==============================================" `
        -ForegroundColor Green

    Write-Host " Claude / ChatGPT / Codex の" `
        -ForegroundColor Green

    Write-Host " MSIXパッケージ削除が完了しました。" `
        -ForegroundColor Green

    Write-Host "==============================================" `
        -ForegroundColor Green

    exit 0
}


# --------------------------------------------------------------
# 削除できなかったものを表示
# --------------------------------------------------------------

Write-Host ""
Write-Host "==============================================" `
    -ForegroundColor Yellow

Write-Host " 一部のパッケージが残っています。" `
    -ForegroundColor Yellow

Write-Host "==============================================" `
    -ForegroundColor Yellow


if ($RemainingAppx.Count -gt 0) {

    Write-Host ""
    Write-Host "残っているインストール済みパッケージ:"

    $RemainingAppx |
        Select-Object `
            Name,
            PackageFullName,
            PackageFamilyName |
        Format-Table -AutoSize
}


if ($RemainingProvisioned.Count -gt 0) {

    Write-Host ""
    Write-Host "残っているプロビジョニングパッケージ:"

    $RemainingProvisioned |
        Select-Object `
            DisplayName,
            PackageName |
        Format-Table -AutoSize
}


exit 1
```

Microsoft公式でも、`Get-AppxPackage -AllUsers` は全ユーザーのパッケージ取得、`Remove-AppxPackage -AllUsers` は全ユーザーからの削除に使用する仕様です。後者は管理者権限が必要です。 ([Microsoft Learn][2])

また、今回のインストールでは `Add-AppxProvisionedPackage` を使用しているため、**`Remove-AppxPackage` だけでなく `Remove-AppxProvisionedPackage` も実行する**のが重要です。プロビジョニングは、新規ユーザーにアプリを登録するためWindowsイメージに追加された状態だからです。 ([Microsoft Learn][3])

なお、`Codex` という名前の**別会社・別製品のMSIXがPCに存在する場合、このスクリプトも削除対象として拾う可能性があります**。会社PCでその可能性があるなら、実行前に次だけ実行して、実際の `Name` を確認するとより安全です。

```powershell
Get-AppxPackage -AllUsers |
    Where-Object {
        $_.Name -match "(?i)Claude|ChatGPT|Codex" -or
        $_.PackageFamilyName -match "(?i)Claude|ChatGPT|Codex"
    } |
    Select-Object Name, PackageFullName, PackageFamilyName, Publisher |
    Format-List
```

この結果が分かれば、**実際のClaudeとChatGPT/CodexのパッケージIDだけを完全一致で指定する、誤削除リスクの低い版**にできます。

[1]: https://help.openai.com/ja-jp/articles/20001276?utm_source=chatgpt.com "新しい ChatGPT デスクトップアプリへの移行 | OpenAI Help Center"
[2]: https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage?view=windowsserver2025-ps&utm_source=chatgpt.com "Remove-AppxPackage (Appx)"
[3]: https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage?view=windowsserver2025-ps&utm_source=chatgpt.com "Remove-AppxProvisionedPackage (Dism)"
