# SKYSEAを使用したChatGPTデスクトップアプリ／Codex Elevated Sandbox導入方式 解説資料

- 文書版: 1.0
- 調査・作成日: 2026年8月5日（JST）
- 対象: Windows、Active Directoryドメインアカウント、既存ユーザープロファイル

---

## 1. 結論

今回のテストに最も適するのは、**SKYSEA Client Viewで対象端末を端末名完全一致で選択し、リモート操作を使って1人ずつ導入する方式**です。

実行コンテキストを明確に分けます。

| 処理 | 実行するユーザー／権限 | 理由 |
|---|---|---|
| ChatGPTデスクトップアプリ導入 | 対象ADユーザーの通常権限 | Store／MSIXアプリは実行ユーザーへ登録されるため |
| 対象プロファイル特定 | 管理者PowerShell | 全プロファイルのCIM情報を安全に照合するため |
| Codex CLI導入 | 管理者PowerShell | 管理者用プロビジョニングツールとして固定配置するため |
| `codex sandbox setup` | 実際に昇格済みの管理者PowerShell | ローカルユーザー、WFP／ファイアウォール、ACL構成が必要なため |
| 利用テスト | 対象ADユーザーの通常権限 | 実運用と同じ条件でUACが出ないことを確認するため |

この分離により、対象ユーザーだけにアプリを登録しつつ、Elevated Sandboxの管理者作業を初回導入時に前倒しできます。

---

## 2. なぜSKYSEAの「リモート操作」を採用するのか

### 2.1 今回は一括配布ではなく、1人ずつのテスト

ユーザー要件では、今回はテストであり、量産スクリプトや自動化は不要です。したがって、配布ジョブ、変数展開、ユーザーコンテキスト切替、結果回収を自動化するよりも、SKYSEAで1台を選び、画面を確認しながら実行する方が単純です。

### 2.2 Windows Storeアプリの配布制約

SKYSEA Client View Ver.21系の公開制限事項では、Windowsストアアプリは通常のソフトウェア配布対象外とされています。一方、OpenAIの現在のCodex対応WindowsアプリはMicrosoft Store IDまたはStore署名済みMSIXで提供されています。

そのため、今回の主経路は次とします。

```text
SKYSEAでPCを特定 → リモート操作 → 対象ユーザーの通常PowerShell → WinGet Store導入
```

これなら、SKYSEAによる対象端末の統制、リモート操作ログ、ユーザー画面の確認を維持しながら、Storeアプリを正しいユーザーへ登録できます。

### 2.3 SKYSEAの画面名に版差がある理由

SKYSEAの詳細な操作マニュアルは保守契約者向けサイトで提供され、公開サイトでは機能名や概要が中心です。また、エディション、オプション、バージョンによりメニュー名や配置が変わる可能性があります。

したがって、実行手順書では、公開資料で確認できる代表的な名称である`[資産管理]`、`[ハードウェア一覧]`／`[端末機一覧]`、`[リモート操作]`を使用し、実環境で同等画面を選ぶよう明記しています。存在しない画面名を断定して操作させるより、安全です。

---

## 3. 端末名とユーザー名をどう使い分けるか

### 3.1 端末名はSKYSEA側の実行先指定

各PCのホスト名は、SKYSEAで接続対象を一意に選ぶために使用します。さらにPowerShell内で`$env:COMPUTERNAME`と予定端末名を比較し、誤端末での実行を止めます。

### 3.2 `--user`にはADアカウントを指定

Codexのコマンドでは、次の形式を使用します。

```text
--user "testdomain\tanaka-tarou"
```

ホスト名を`--user`へ含めません。`PC名\ユーザー名`はローカルアカウントを表す形式であり、今回の対象はADドメインアカウントだからです。

### 3.3 プロファイルパスはSIDで決める

Windowsのユーザープロファイルは、見た目のフォルダー名とログオン名が必ずしも一致しません。

例:

```text
ADアカウント: testdomain\tanaka-tarou
候補フォルダー:
  C:\Users\tanaka-tarou
  C:\Users\tanaka-tarou.TESTDOMAIN
  C:\Users\tanaka-tarou.001
```

また、退職者や再作成されたアカウントのプロファイルが残っている場合、同じようなフォルダー名でもSIDが異なります。

本方式は次の順に照合します。

```text
testdomain\tanaka-tarou
        ↓ Windowsのアカウント解決
S-1-5-21-...（対象ADアカウントのSID）
        ↓ Win32_UserProfile.SIDと完全一致
Win32_UserProfile.LocalPath
        ↓
<LocalPath>\.codex
```

これにより、端末名、ADアカウント、SID、プロファイルパスの4点を結び付けられます。

### 3.4 「ユーザー名と端末名で指定すべきか」への回答

**はい。ただし役割を分けます。**

- SKYSEAで`端末名`を指定する。
- Codexで`ドメイン\ユーザー名`を指定する。
- Windows内部では`SID`でプロファイルを特定する。
- `--codex-home`にはSID照合後の実際の`LocalPath\.codex`を指定する。

Codexコマンドへ端末名を追加する必要はありません。端末名はコマンド実行前のターゲットガードとして使用します。

---

## 4. ChatGPTデスクトップアプリとCodex CLIの関係

### 4.1 デスクトップアプリのためにユーザー用CLIを別途入れる必要はない

現在のCodex対応Windowsアプリは、デスクトップアプリとしてローカルCodex機能を提供します。通常のアプリ利用のために、対象ユーザーへ別の`codex`コマンドを常設することが必須という意味ではありません。

### 4.2 今回CLIが必要な理由

今回必要なのは、PR #24831で追加された管理展開用コマンドを実行するためです。

```powershell
codex sandbox setup --elevated --user "DOMAIN\user" --codex-home "C:\Users\...\.codex"
```

このコマンドは、ユーザーが初めてCodexを使う前に、管理者がElevated Sandboxを事前構成するためのものです。

### 4.3 管理者専用の固定パスへ置く理由

対象ユーザーごとにCLIをインストールすると、次の問題が増えます。

- 各ユーザーの`PATH`管理が必要になる。
- `%LOCALAPPDATA%`配下へ複数コピーが作られる。
- どのバージョンのCLIで構成したか追跡しにくい。
- 管理者と対象ユーザーの実行コンテキストが混在する。

そこで、本方式では次の1コピーを使用します。

```text
C:\ProgramData\OpenAI\CodexProvisioning
```

これは利用者向けCLIではなく、端末管理者がプロビジョニングと再構成に使う管理ツールです。

---

## 5. `codex sandbox setup`がUACを回避する仕組み

### 5.1 UACを無効化するのではない

通常、Elevated Sandboxの初回セットアップでは、管理者権限が必要なためUACが表示されます。管理展開用コマンドは、管理者が事前に昇格済みプロセスからセットアップを済ませることで、エンドユーザー初回利用時のUACをなくします。

つまり、次の違いです。

```text
不適切: UAC機能を弱める／無効化する
適切  : 導入担当者が承認済み管理者権限で初回構成を先に完了する
```

### 5.2 `--elevated`は昇格操作ではない

PR #24831および現在の実装では、プロビジョニングコマンドは、呼び出し元プロセスが実際に管理者として昇格済みであることを確認します。

したがって、通常PowerShellで次を実行しても不十分です。

```powershell
codex sandbox setup --elevated ...
```

`--elevated`は構成するサンドボックス方式を表し、UACを自動承認するオプションではありません。実行者はWindowsの正規手順でPowerShellを管理者として起動する必要があります。

### 5.3 ProvisionOnlyモード

管理展開用コマンドは、通常のCodex作業を行わず、セットアップに必要な処理だけを実施する`ProvisionOnly`経路を使用します。現在の実装では、対象`CODEX_HOME`と実ユーザーを明示し、サンドボックスユーザー、資格情報、ネットワーク制御、設定マーカー等を作成します。

---

## 6. Elevated Sandboxで作成・変更されるもの

OpenAIの設計解説と実装から、主な構成要素は次のとおりです。

### 6.1 ローカルサンドボックスユーザー

- `CodexSandboxOffline`
- `CodexSandboxOnline`

エージェントが起動する子プロセスは、実ユーザー本人ではなく、用途に応じた制限付きローカルユーザーを基礎に実行されます。

### 6.2 ネットワーク制御

`CodexSandboxOffline`には、Windows Filtering Platform／ファイアウォールを使用したアウトバウンド制御が適用されます。これにより、単なる環境変数によるベストエフォート遮断より強いOSレベルの境界を作ります。

### 6.3 ファイルシステムACL

サンドボックスユーザーが対象ユーザーと同じ必要範囲を読み取れるようにしつつ、書き込み可能な領域を制限するため、ACL構成が行われます。

### 6.4 対象`CODEX_HOME`内の管理データ

主なパスは次のとおりです。

```text
<CODEX_HOME>\.sandbox
<CODEX_HOME>\.sandbox-bin
<CODEX_HOME>\.sandbox-secrets
<CODEX_HOME>\.sandbox\setup_marker.json
```

`.sandbox-secrets`には保護対象情報が含まれるため、内容を表示、コピー、チケット添付、外部送信しないでください。

### 6.5 ローカル設定

管理展開コマンドは、対象`CODEX_HOME`の`config.toml`へWindowsサンドボックスの`elevated`設定を保存します。

---

## 7. なぜ既存`config.toml`を確認するのか

PR #24831のレビューでは、ベース設定を`elevated`へ更新しても、アクティブなプロファイル側に古い設定があると実効値を上書きする可能性が指摘されています。

例:

```toml
profile = "legacy"

[windows]
sandbox = "elevated"

[profiles.legacy.windows]
sandbox = "unelevated"
```

この場合、ベース設定だけを見ると成功に見えても、`legacy`プロファイルが選択されているため、実利用時に期待どおりにならない可能性があります。

そのため本方式では、実行前に`config.toml`をバックアップして表示し、次を確認します。

- アクティブプロファイルの有無
- プロファイル固有のWindows設定
- `unelevated`の残存
- 過去の実験設定

ユーザーごとの設定に問題がなければ、プロビジョニングコマンドへ進みます。

---

## 8. CLIの起動パスを固定する理由

### 8.1 Windows版インストーラーの構成

OpenAI公式Windowsインストーラーは、概ね次の構成を作成します。

```text
<CODEX_HOME>\packages\standalone\releases\<version-platform>\
  bin\codex.exe
  codex-resources\codex-windows-sandbox-setup.exe
  codex-resources\codex-command-runner.exe

<CODEX_HOME>\packages\standalone\current  → 現在リリースへのジャンクション
<CODEX_INSTALL_DIR>                       → current\binへの見かけのbin
```

### 8.2 既知のヘルパー探索問題

2026年7月時点のOpenAI Codexリポジトリには、見かけの`bin`ジャンクションから`codex.exe`を起動すると、隣接する`codex-resources\codex-windows-sandbox-setup.exe`を見つけられない報告があります。

そのため本方式では、次を使いません。

```text
C:\ProgramData\OpenAI\CodexProvisioning\bin\codex.exe
```

代わりに、パッケージルートが保たれる次を使用します。

```text
C:\ProgramData\OpenAI\CodexProvisioning\home\packages\standalone\current\bin\codex.exe
```

そして実行前に、対応するセットアップヘルパーの存在を確認します。

```text
C:\ProgramData\OpenAI\CodexProvisioning\home\packages\standalone\current\codex-resources\codex-windows-sandbox-setup.exe
```

これは回避策を複雑にするのではなく、単に誤った入口を使わないための固定パス指定です。

---

## 9. セキュリティ上の設計判断

### 9.1 最小権限

- ChatGPTアプリは対象ユーザーの通常権限で導入・利用する。
- 管理者権限はサンドボックスの事前構成時だけ使用する。
- Domain Adminを常用せず、端末単位の管理者またはJIT資格情報を推奨する。
- UACを無効化しない。

### 9.2 対象の一意性

- SKYSEA: 端末名完全一致、1台だけ。
- Windows: `whoami`と端末名の再確認。
- AD: `DOMAIN\user`をSIDへ変換。
- プロファイル: SID完全一致、1件だけ。

どこか1つでも一意でなければ停止します。

### 9.3 供給元

- ChatGPTアプリ: Microsoft Store上のOpenAI公式ID、またはOpenAI公式Store署名済みMSIX。
- Codex CLI: OpenAI公式インストーラー。
- 非公式ミラーや第三者パッケージを使用しない。

公式インストーラーは、取得したCodexパッケージのSHA-256検証を行います。

### 9.4 監査性

- 対象ユーザー一覧に、端末、ADユーザー、SID、プロファイル、CLIバージョン、結果を記録する。
- SKYSEAのリモート操作ログを残す。
- 実施日時と実施者を記録する。
- エラー時には推測で続行せず、停止理由を記録する。

### 9.5 機密情報

- テスト用フォルダーには機密データを置かない。
- `.sandbox-secrets`を閲覧・収集しない。
- Sandboxログを外部共有する場合は、ユーザー名、パス、プロキシ、内部ホスト名等を社内基準でマスキングする。

---

## 10. なぜ自動化しないのか

量産時には、対象リストから端末・ユーザーごとに処理を展開し、結果を回収する仕組みが必要です。しかし今回の要件はテストであり、1人ずつ実行します。

今回、自動化を行わない利点は次です。

- SKYSEA画面上で対象PCを目視確認できる。
- 対象ユーザーが実際にログオンしていることを確認できる。
- Storeアプリが正しいユーザーへ登録されたことを確認できる。
- UAC、GPO、EDR、プロキシ等の端末差をその場で把握できる。
- 誤端末／誤プロファイルに対する中止判断を人が行える。

一方で、同じ入力箇所を毎回増やすと誤入力が起きます。そのため、手順書では毎回変更する値を原則として次の2つに限定しています。

```powershell
$ExpectedHost = '対象端末名'
$TargetUser  = 'ドメイン\ユーザー名'
```

SID、プロファイルパス、`CODEX_HOME`はコマンドで解決します。

---

## 11. 代替案を採用しなかった理由

### 11.1 `C:\Users\ユーザー名`を直接指定する

採用しません。フォルダー名はADログオン名と一致しない場合があり、退職者・再作成アカウント・重複プロファイルを誤選択するためです。

### 11.2 `--current-user`を使う

採用しません。コマンドは管理者コンテキストで実行するため、`--current-user`は対象ユーザーではなく、昇格に使用した管理者を指す可能性があります。管理展開では`--user`と`--codex-home`を明示するのが適切です。

### 11.3 対象ユーザーごとにCLIをインストールする

採用しません。アプリ利用に不要な重複インストールとPATH管理が増えるためです。

### 11.4 UACを無効化する

採用しません。端末全体の防御を弱め、今回の目的である安全な事前構成と逆行します。

### 11.5 SKYSEAの通常ソフトウェア配布でStoreアプリを配る

採用しません。SKYSEAの公開制限事項と、ユーザー単位のStore／MSIX登録という性質に合わないためです。今回のテストではリモート操作が最短です。

### 11.6 `SYSTEM`でChatGPTアプリを登録する

採用しません。Store／MSIXアプリを対象ユーザーだけへ登録するにはユーザーコンテキストが重要で、SYSTEMや管理者コンテキストでは意図したユーザーへ入らない可能性があるためです。

### 11.7 `codex`をPATH任せで実行する

採用しません。複数のインストールやWindowsジャンクションの問題により、異なるバージョンやヘルパー探索失敗を招くためです。固定パスを使います。

---

## 12. 運用上の注意

### 12.1 プロキシ環境

管理展開コマンドは、対象`CODEX_HOME`の設定と、実行プロセスのネットワーク関連設定を参照します。会社で`HTTP_PROXY`、`HTTPS_PROXY`、ローカルプロキシポート、ローカルバインド許可を使用する場合、実利用時と事前構成時を一致させる必要があります。

プロキシ設定を後から変更した場合、Elevated Sandboxのオフライン側ネットワーク構成を更新するため、再プロビジョニングが必要になる場合があります。

### 12.2 GPO／EDR

Elevated Sandboxは安全境界を作るため、ローカルユーザー、ACL、WFP／ファイアウォールを使用します。次の組織制御と競合する可能性があります。

- ローカルアカウント作成禁止
- ローカルログオン／バッチログオン権限の拒否
- ローカルファイアウォールルール変更禁止
- EDRによる新規ローカルユーザーやプロセス起動の遮断
- プロファイル／ACL変更監視

エラー時にこれらを一時無効化するのではなく、イベントログとポリシー結果を確認し、正式な許可方針を作成します。

### 12.3 Windowsバージョン

OpenAIはWindows 11を推奨しています。最新更新済みWindows 10ではベストエフォート対応となるため、セキュリティ境界の一貫性を重視する会社端末ではWindows 11を優先してください。

### 12.4 更新

ChatGPTアプリとCodex CLIは別の更新経路を持ちます。管理者用CLIは、再プロビジョニングが必要になったときに公式インストーラーで更新し、`--version`を記録します。OpenAIがSandbox setup versionの変更や再構成を案内した場合は、対象ユーザーごとに手順を再実行します。

---

## 13. テスト成功後に量産化する場合の考え方

今回は実装しませんが、テストで次を確認してから量産設計へ進むのが妥当です。

1. SKYSEAの対象端末選択とログ取得が運用可能か。
2. WinGet Store導入が会社ネットワークで安定するか。
3. 対象ユーザーのSID解決とプロファイル照合が安定するか。
4. GPO／EDRとElevated Sandboxが競合しないか。
5. プロキシ設定を含めてUACなしで利用開始できるか。
6. アプリ／CLI更新後の再プロビジョニング要否を管理できるか。

量産時も、入力データの基準は次の組み合わせにすべきです。

```text
端末名 + ADログオン名 + AD SID + 実プロファイルLocalPath
```

フォルダー名だけのリストを基準にしないことが重要です。

---

## 14. 参照資料

### OpenAI公式

- ChatGPT desktop app for Windows / Codex Windows app  
  https://learn.chatgpt.com/docs/windows/windows-app
- Enterprise deployment of the Codex-enabled Windows app  
  https://learn.chatgpt.com/docs/enterprise/windows-deployment
- Windows sandbox  
  https://learn.chatgpt.com/docs/windows/windows-sandbox
- Windows Elevated Sandbox設計解説  
  https://openai.com/index/building-codex-windows-sandbox/
- Codex公式Windowsインストーラー  
  https://chatgpt.com/codex/install.ps1

### OpenAI Codexリポジトリ

- PR #24831: Add admin CLI command to pre-provision the Windows elevated sandbox  
  https://github.com/openai/codex/pull/24831
- CLI implementation: `codex-rs/cli/src/sandbox_setup.rs`  
  https://github.com/openai/codex/blob/main/codex-rs/cli/src/sandbox_setup.rs
- Windows sandbox setup implementation  
  https://github.com/openai/codex/blob/main/codex-rs/windows-sandbox-rs/src/setup.rs
- Windows setup helper issue #30829  
  https://github.com/openai/codex/issues/30829
- Related issue #32359  
  https://github.com/openai/codex/issues/32359

### SKYSEA

- SKYSEA Client View 機能一覧  
  https://www.skyseaclientview.net/product-info/feature/
- リモート操作  
  https://www.skyseaclientview.net/product-info/option/
- Ver.21 制限事項  
  https://www.skyseaclientview.net/product-info/limit/ver21/

### Microsoft

- Win32_UserProfile class  
  https://learn.microsoft.com/windows/win32/cimwin32prov/win32-userprofile
- WinGet  
  https://learn.microsoft.com/windows/package-manager/winget/
- Add-AppxPackage  
  https://learn.microsoft.com/powershell/module/appx/add-appxpackage

---

## 15. 要点の再確認

```text
端末はSKYSEAの端末名で狙う。
ユーザーはADのDOMAIN\userで狙う。
プロファイルはSIDで狙う。
アプリは対象ユーザーの通常権限で入れる。
Sandbox setupは昇格済み管理者で行う。
CLIはProgramDataの管理者用1コピーにする。
UACは無効化せず、導入時に一度だけ正規昇格する。
```
