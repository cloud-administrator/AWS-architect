# はじめに読むファイル

本パッケージは、Windows端末上の指定したActive Directoryドメインユーザーだけを対象に、次の2段階をSKYSEA Client Viewで実行するための完成版テンプレートです。

1. **SYSTEMジョブ**: Codexの`elevated` Windows sandboxを対象ユーザーの既存プロファイルへ事前構成する。
2. **ログオンユーザージョブ**: SYSTEMジョブで承認されたSIDと一致するユーザーだけに、新しいChatGPT Windowsアプリをインストールする。

## 最短の実行順序

1. ルートの`targets.csv`を編集する。
2. 管理された64ビットWindows準備端末で`00_Prepare\Run-Prepare-And-Build.cmd`を実行する。
3. `Output`に作られたSYSTEM媒体とUSER媒体をSKYSEAへ登録する。
4. まずパイロット2台で、SYSTEMジョブ、USERジョブの順に実行する。
5. 受入試験に合格した後、5～10台、残りの順で展開する。

詳細は次を上から順に実行してください。

- `Codex_SKYSEA_完成版_導入手順書.md`
- `Codex_SKYSEA_完成版_方式設計・解説.md`
- `STATIC_VALIDATION.txt`
- `SHA256SUMS.csv`

## 管理者が通常編集するファイル

```text
targets.csv
```

それ以外のスクリプト、承認済みCodex版、ハッシュ表は、変更管理を通さず編集しないでください。

## 重要な実行コンテキスト

| ジョブ | 必須実行主体 |
|---|---|
| Codex sandbox事前構成 | `NT AUTHORITY\SYSTEM`（SID `S-1-5-18`） |
| ChatGPTアプリ導入 | 対象ADユーザー本人のログオンセッション |

`winget`はLocalSystemコンテキストで実行しません。

## 検証範囲

付属スクリプトは構造・固定値・ファイル参照について静的検査しています。検査内容は`STATIC_VALIDATION.txt`、配布元一式のハッシュは`SHA256SUMS.csv`を確認してください。実際のWindows、Active Directory、SKYSEA、GPO、EDR、Microsoft Store環境では実行していません。必ずパイロット2台から開始してください。
