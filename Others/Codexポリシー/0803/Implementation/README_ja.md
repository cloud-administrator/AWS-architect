# Codex Windows Elevated Sandbox 企業展開用実装ファイル

このフォルダーは、同梱の `手順書.md` で使用する実装ファイル一式です。作業は必ず `手順書.md` の順序で実施してください。

## 採用方式

- ChatGPT Windows アプリ、Codex 公式パッケージ、署名済みファイル、`requirements.toml` の配布と棚卸しは、既存のソフトウェア配布製品または SKYSEA で行います。
- `codex sandbox setup --elevated` は、コンピューター GPO で作成したスケジュールタスクから `NT AUTHORITY\SYSTEM`／最上位の特権で実行します。
- 対象ユーザーは、AD コンピューターオブジェクトの `managedBy` を正本とし、AD ユーザー SID と `Win32_UserProfile.SID` が一致する既存プロファイルだけに限定します。
- `C:\Users` 配下の全プロファイル、現在ログオン中のユーザー、最終ログオン履歴から対象者を推測しません。
- 現行実装に基づく保守的な運用規則として、1 台につき Codex 対象プロファイルは 1 名です。

## ファイルと実行順序

| 順序 | ファイル | 実行場所／用途 |
|---:|---|---|
| 1 | `Set-CodexDeviceUserMapping.ps1` | AD 管理端末。CSV を検証し、コンピューターの `managedBy` へ正式利用者を登録します。最初は必ず `-WhatIf` で実行します。 |
| 2 | `Get-CodexOfficialPackage.ps1` | 管理端末。承認済み固定版を OpenAI 公式配布元から取得し、`release.json`、`codex-package_SHA256SUMS`、アーカイブ SHA-256、公式パッケージ構造、`codex.exe --version` を検証します。 |
| 3 | `New-CodexDeploymentPayload.ps1` | AD 管理端末。検証済みパッケージ、端末スクリプト、要件ファイルをまとめ、ドメイン、認可グループ DN、固定版、6 必須ファイルの SHA-256 を設定した配布ペイロードを生成します。 |
| 4 | `Install-CodexProvisioningPayload.ps1` | 対象 Windows PC。ソフトウェア配布製品から LocalSystem で実行し、署名、Thumbprint、ハッシュ、バージョンを検証して Program Files／ProgramData へ配置し、ACL を固定します。 |
| 5 | `Provision-CodexSandbox.ps1` | 対象 Windows PC。GPO の SYSTEM タスクから実行し、署名、ACL、ハッシュ、AD `managedBy`、認可グループ、SID、既存プロファイルを検証して Elevated Sandbox を事前構成します。 |
| 6 | `Test-CodexDeployment.ps1` | 対象 Windows PC。現在の AD 割当、認可、SID 一致プロファイル、GPO タスクの操作、署名者、ハッシュ、`requirements.toml`、`state.json`、Codex 成果物、ローカル sandbox アカウント／グループを読み取り専用で検証します。 |

## 補助ファイル

- `CodexDeploymentConfig.psd1.example`: 設定構造の参考例。通常は `New-CodexDeploymentPayload.ps1` が実値入りの `CodexDeploymentConfig.psd1` を生成します。
- `requirements.toml`: クラウドポリシーと一致させる Windows ローカル要件。UTF-8 BOM なしで保持します。
- `CodexDeviceUserMap.csv`: 端末名と正式利用者の対応表の例。
- `GPO-Task-Action.txt`: GPO のスケジュールタスク画面へ入力する値のクイックリファレンス。
- `SHA256SUMS.txt`: この Implementation フォルダーの配布時点の SHA-256。PS1 へコード署名を付けた後は署名対象ファイルの SHA-256 が変わります。

## 署名対象

管理端末で使用する次のスクリプトを署名します。

```text
Set-CodexDeviceUserMapping.ps1
Get-CodexOfficialPackage.ps1
New-CodexDeploymentPayload.ps1
```

生成したペイロード内で次を署名します。

```text
Install-CodexProvisioningPayload.ps1
CodexProvisioning\Provision-CodexSandbox.ps1
CodexProvisioning\Test-CodexDeployment.ps1
CodexProvisioning\CodexDeploymentConfig.psd1
```

すべて同じ承認済みコード署名証明書とタイムスタンプを使用し、端末側では署名者 Thumbprint を固定します。

## 本番前の必須条件

1. `managedBy` を別用途で使用していないことを確認します。
2. 1 台 1 対象プロファイルを端末標準として承認します。
3. Codex CLI は公式安定版を固定し、`latest` やプレリリースを本番へ自動配布しません。
4. 配布製品の実行主体が LocalSystem／SYSTEM 相当であることを公式マニュアルまたはメーカー回答で確認します。Domain Admin とログオンユーザーは使用しません。
5. Windows PowerShell 5.1、実際の AD、GPO、EDR、Proxy、ChatGPT アプリとの組合せで、3 台 → 10 台 → 25～30 台 → 残りの順に検証します。
6. 各ゲートで UAC 0 件、対象誤選定 0 件、Critical 検証失敗 0 件を満たします。

## 検証上の注意

この実装は Linux 上で生成し、PowerShell の静的検査、ファイル整合性検査、Markdown 構造検査を行っています。Windows／AD／GPO／SKYSEA／EDR／Proxy への接続を伴う実行試験は行っていません。実運用版の承認は、御社 Windows 環境での段階パイロット合格を条件にしてください。
