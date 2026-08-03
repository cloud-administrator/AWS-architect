# ChatGPT Windows／Codex Elevated Sandbox 導入手順書パッケージ

## 最初に開くファイル

`手順書.md` を先頭から順番に実施してください。設計解説ではなく、実際の画面操作、PowerShell、GPO 入力値、配布順序、受入判定、障害対応、更新、停止手順をまとめた作業用手順書です。

## 収録内容

```text
Codex_Windows_Enterprise_Deployment_Procedure_ja\
├─ 手順書.md
├─ README_ja.md
├─ SHA256SUMS.txt
└─ Implementation\
   ├─ Get-CodexOfficialPackage.ps1
   ├─ New-CodexDeploymentPayload.ps1
   ├─ Install-CodexProvisioningPayload.ps1
   ├─ Provision-CodexSandbox.ps1
   ├─ Set-CodexDeviceUserMapping.ps1
   ├─ Test-CodexDeployment.ps1
   ├─ CodexDeploymentConfig.psd1.example
   ├─ CodexDeviceUserMap.csv
   ├─ requirements.toml
   ├─ GPO-Task-Action.txt
   ├─ README_ja.md
   └─ SHA256SUMS.txt
```

## 実行前に確定する値

- AD NetBIOS 名、DNS 名、ドメイン DN
- グループ格納 OU、対象 PC 格納 OU
- `GG-Codex-Users`、`GG-Codex-Computers-Pilot`、`GG-Codex-Computers-Prod`
- 承認済み固定版 Codex CLI
- ポリシー版
- コード署名証明書 Thumbprint とタイムスタンプ URL
- ChatGPT ワークスペース側のパイロット／本番グループ
- SKYSEA／配布製品の LocalSystem 実行方式

## 整合性確認

ZIP 展開後、`手順書.md` 第 1.3 節に従って `Implementation\SHA256SUMS.txt` を検証します。ルートの `SHA256SUMS.txt` は、提出物全体の改変確認用です。

## 重要事項

- `C:\Users` の全プロファイルへ実行しません。
- ログオンユーザーや最終ログオン履歴から対象を推測しません。
- Domain Admin 資格情報を端末ジョブへ登録しません。
- 共有 PC、シフト端末、VDI プールは本手順の対象外です。
- `.sandbox-secrets\sandbox_users.json` の内容を表示、コピー、収集、チケット添付しません。
- `requirements.toml` は UTF-8 BOM なしで保持します。
- 本番投入前に 3 台、10 台、25～30 台の各段階で検証します。

付属 PowerShell は本番候補実装ですが、御社 Windows／AD／GPO／SKYSEA／EDR／Proxy 環境での実行試験を経て運用版として承認してください。
