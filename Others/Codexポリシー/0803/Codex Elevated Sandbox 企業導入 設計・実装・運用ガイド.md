# ChatGPT Windows デスクトップアプリ / Codex Elevated Sandbox

## 企業導入 設計・実装・運用ガイド（最終決定版）

> **Markdown版について**  図版は相対パス `assets/media/` を参照します。図版・DOCX・PDF・実装スクリプトを含む完全版は、併記のZIPを展開して参照してください。

> **[決定] 最終結論**
>
> 配布は既存ソフトウェア配布製品/SKYSEA、特権セットアップはコンピューターGPOのSYSTEMタスク、対象ユーザーはAD computer.managedBy + SID完全一致で決定します。C:\Users全列挙と現在ログオン中ユーザー推測は採用しません。

![図0-1 最終決定アーキテクチャ](assets/media/image1.png)

*図0-1 最終決定アーキテクチャ*

| **項目** | **内容**                                                              |
|----------|-----------------------------------------------------------------------|
| 対象     | Active Directoryドメイン参加済みWindows端末 / 100名以上               |
| 主対象   | 情報システム / セキュリティ / AD管理 / 端末管理 / ヘルプデスク        |
| 適用原則 | 原則1台1名。共有PC・VDIプールは本方式の対象外                         |
| 検証状態 | 公式仕様・ソースを再確認。付属PowerShellはWindows実機未試験の参考実装 |

# 文書管理・承認事項

| **項目**          | **最終方針 / 承認事項**                                                                                        |
|-------------------|----------------------------------------------------------------------------------------------------------------|
| 特権実行          | GPOスケジュールタスクを NT AUTHORITY\SYSTEM で実行。SKYSEAからDomain Adminとして直接実行しない。               |
| 端末-利用者の正本 | 貸与台帳/CMDB/SKYSEA資産情報等で確定し、AD computer.managedByへ一括同期。managedBy使用済みなら専用正本へ置換。 |
| 対象プロファイル  | 1台につき1名。ADユーザーSIDとWin32_UserProfile.SIDが一致する既存通常プロファイルのみ。                         |
| ポリシー          | elevatedのみ、private desktop有効、workspace既定、read-only/workspace許可、danger-full-access拒否。            |
| パッケージ        | ChatGPTはStore署名アプリ/MSIX。Codexは公式パッケージ構造を固定し、アーカイブ検証と展開後SHA-256固定。          |
| 本番移行          | 3台 -> 10台 -> 25～30台 -> 残り。UAC 0件、対象誤選定0件、Critical失敗0件を必須ゲートとする。                |

> **[必須] 本番承認の条件**
>
> 本書中のプレースホルダーを実値へ置換し、PS1/PSD1を社内コード署名し、実際のWindows/AD/GPO/EDR/Proxy環境でパイロットを合格させてください。

## 本書の読み方

| **担当**          | **読む章**       |
|-------------------|------------------|
| 意思決定者        | 第1～4章、第11章 |
| ChatGPT管理者     | 第5章            |
| AD管理者          | 第6章            |
| 端末/配布管理者   | 第7～10章        |
| 運用/ヘルプデスク | 第12～14章       |

## 用語と判断ラベル

| **用語**    | **初心者向け説明**                                                                                  |
|-------------|-----------------------------------------------------------------------------------------------------|
| UAC         | 管理者権限が必要な操作の前に表示されるWindowsの確認画面。                                           |
| SYSTEM      | Windows自身の高権限アカウント。パスワードを配布せず端末内の管理処理を実行できる。                   |
| GPO/GPP     | Active DirectoryからWindows設定を配布する仕組み。ここではコンピューター側の基本設定でタスクを作る。 |
| SID         | ユーザーを一意に識別するWindowsの番号。フォルダー名より信頼できる。                                 |
| managedBy   | ADコンピューターオブジェクトが保持する単一値のDN属性。本設計では正式利用者を指す。                  |
| CODEX_HOME  | ユーザーごとのCodex設定/状態フォルダー。通常は実プロファイルの .codex。                             |
| Fail Closed | 割当や検証が不明なら何も変更せず停止する設計。                                                      |

## 本書で使う判断ラベル

| **ラベル**           | **意味**                                                                           |
|----------------------|------------------------------------------------------------------------------------|
| 公式仕様             | OpenAI/Microsoft/SKYSEAの公式文書またはOpenAI公式ソースで確認できた事実。          |
| 設計判断             | 御社の条件に対して、本書が安全性と運用性から選定した方式。                         |
| 現行コードからの推論 | 公開ソースの挙動から導く保守的な運用規則。ベンダーの明示的なサポート宣言ではない。 |
| 御社確認             | 契約版、EDR、Proxy、Windowsビルド等に依存し、Pilotで確認する項目。                 |

# 目次

| **章** | **内容**                                       |
|--------|------------------------------------------------|
| 1      | エグゼクティブサマリー                         |
| 2      | 添付2資料の相違と最終判定                      |
| 3      | 再調査で確認した公式仕様と設計上の推論         |
| 4      | 最終アーキテクチャと役割分担                   |
| 5      | ChatGPT/Codexクラウドポリシーの設定            |
| 6      | ADで端末と利用者を正式に対応付ける             |
| 7      | ChatGPTアプリとCodexパッケージの配布準備       |
| 8      | GPOによるSYSTEMタスクの作成                    |
| 9      | SKYSEA/既存配布製品の安全な使い方              |
| 10     | 段階展開                                       |
| 11     | 動作確認・受入判定                             |
| 12     | 障害対応                                       |
| 13     | 利用者変更・退職・共有PC・更新                 |
| 14     | ロールバックと未検証事項                       |
| 付録   | コマンド、終了コード、チェックリスト、参考資料 |

> **[注意] 画面表示について**
>
> 本書の画面図は操作場所を明確にするための画面イメージです。ChatGPT、Windows Server、SKYSEAの版によってラベルは変わるため、同じ機能名/設定キーを確認してください。

# 1. エグゼクティブサマリー

## 1.1 最終結論

> **[設計判断] 採用方式: ハイブリッド**
>
> 「ファイルを届けて棚卸しする役割」と「端末内で特権処理を起動する役割」を分離します。配布は既存製品/SKYSEA、特権実行はGPOのSYSTEMタスクです。

| **機能**                 | **採用方式**                      | **理由**                                                                         |
|--------------------------|-----------------------------------|----------------------------------------------------------------------------------|
| ChatGPTアプリ配布        | 既存ソフトウェア配布製品 / SKYSEA | MSIX/Storeアプリの配布、対象端末管理、結果収集に向く。                           |
| Codex公式パッケージ配布  | 既存配布製品 / SKYSEA             | 固定版と複数ファイルをProgram Filesへ配布し、バージョン/ハッシュを棚卸しできる。 |
| Elevated Sandbox事前構成 | コンピューターGPOのSYSTEMタスク   | ユーザー操作なし、パスワード保存なし、UAC非表示、再試行/多重実行防止が明確。     |
| 対象ユーザー決定         | AD computer.managedBy + SID一致   | 旧プロファイルや管理者ログオンを誤選定しない。                                   |

## 1.2 100名以上でも個別コマンドを作らない

100人分のコマンドを手作業で作るのではありません。端末名と正式利用者の2列CSVを正本から一括作成し、managedByへ同期します。端末側は全台共通の署名済みスクリプトを使用し、自分の端末名から自分の割当だけを取得します。

**正本CSVの最小形式**

```csv
ComputerName,SamAccountName
PC-TKY-001,tanaka-tarou
PC-TKY-002,suzuki-hanako
PC-OSK-001,yamada-jiro
```

> **[禁止] 「端末名だけ確認して全プロファイルへ実行」は不採用**
>
> 退職者や旧利用者のプロファイルが残る環境では、全プロファイルへの実行は誤設定を避けられません。安全性を維持しながら工数を下げる方法は、割当データを一括同期して共通スクリプトで自動解決することです。

## 1.3 UACを出さない仕組み

`codex sandbox setup --elevated` は、呼び出し元が実際に昇格済みであることを要求します。GPOタスクをSYSTEMかつ「最上位の特権」で実行すると、利用者の対話セッションへUAC確認を出さずにセットアップできます。

# 2. 添付2資料の相違と最終判定

![図2-1 相違点と最終判定](assets/media/image2.png)

*図2-1 相違点と最終判定*

## 2.1 相違の核心

| **論点**            | **Pro回答(1).md**                                 | **添付DOCX**                                     | **最終決定**                              |
|---------------------|---------------------------------------------------|--------------------------------------------------|-------------------------------------------|
| 現利用者の判定      | 現在ログオン中のADユーザー/ロード済みプロファイル | AD computer.managedByで正式利用者を取得しSID照合 | managedBy + SID                           |
| 端末-ユーザー対応表 | 不要                                              | CSVを一括登録                                    | 正本CSVは必要。ただし手作業コマンドは不要 |
| 共有PC              | 許可ユーザーごとに順次構成                        | 原則1台1対象                                     | 共有PCは除外                              |
| トリガー            | ログオン時 + 定期                                 | 起動時 + 日次                                    | 起動時 + 日次。ログオン時は不使用         |
| 旧プロファイル      | ロードされていなければ除外                        | 正式割当SID以外を除外                            | 正式割当SID以外を無条件で無視             |

## 2.2 なぜログオン中ユーザー方式を捨てるのか

- **正式な貸与関係ではない:** 管理者の保守ログオン、RDP、共有利用、サポート作業を現利用者と誤認します。

- **端末共通の固定アカウント:** 現行ソースではCodexSandboxOffline/Onlineという固定ローカルアカウントのパスワードをsetupごとに再生成し、指定CODEX_HOMEへ保存します。

- **旧CODEX_HOMEとの整合性:** 別プロファイルへ再度setupすると先行プロファイルの保存済み資格情報が古くなる可能性があります。

> **[現行コードからの推論] 1台1対象は「公式の明示的非対応宣言」ではない**
>
> OpenAIの現行コードから導く保守的な運用規則です。固定アカウントとCODEX_HOME別の保存資格情報の組み合わせが変わった場合は再評価してください。

# 3. 再調査で確認した公式仕様と設計上の推論

## 3.1 公式仕様として確認できたこと

| **確認事項**        | **根拠と意味**                                                                                                                                       |
|---------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| Elevated sandbox    | 専用の低権限ユーザー、ACL、ファイアウォール/WFP等を使うWindows向け強化方式。allowed_sandbox_implementationsでelevatedだけを許可できる。              |
| 事前構成コマンド    | PR #24831でIT管理者向けの `codex sandbox setup --elevated --user ... --codex-home ...` が追加された。呼び出し元は実際に昇格済みである必要がある。 |
| 明示ユーザー        | `--user` を使う場合 `--codex-home` が必須。`--current-user` は環境変数から現在ユーザーを解決するためSYSTEMタスクでは使用しない。               |
| 固定sandboxユーザー | CodexSandboxOffline/Onlineという固定名。setup時に新しいランダムパスワードを生成し、DPAPI保護して対象CODEX_HOMEへ保存する。                           |
| 公式パッケージ構造  | codex.exeだけでなくsetup helper、command runner、rg、package manifest等を含む公式構造が必要。                                                        |
| Windowsアプリ配布   | Store署名アプリ、製品ID、x64/Arm64 MSIX、必要に応じてオフラインライセンスが公式に案内される。単独MSI/非Store EXEを前提にしない。                     |

## 3.2 本書の設計判断

| **設計判断**             | **理由**                                                                                         |
|--------------------------|--------------------------------------------------------------------------------------------------|
| 配布 + GPOのハイブリッド | GPOはSYSTEM実行に強く、配布製品はファイル配布/棚卸しに強い。                                     |
| managedByを正本化        | 旧プロファイルを残したまま、端末から現利用者を一意に解決できる。属性が他用途なら専用正本へ置換。 |
| 1台1対象プロファイル     | 固定sandboxユーザーのパスワード再生成とCODEX_HOME別保存から、複数利用者の継続利用を避ける。      |
| 起動時 + 日次            | ログオンした人物を対象判定に使わず、ネットワーク/DC/配布遅延を再試行できる。                     |

## 3.3 現時点で御社確認が必要なこと

- 御社契約版SKYSEAで任意コマンドを実行する際の正確なセキュリティコンテキスト。公開情報だけでは確定できません。

- Windows 10/11ビルド、EDR、Proxy、WDAC/AppLocker、ファイアウォールベースラインとの組合せ。

- managedByを既存の権限委任/資産管理/ワークフローで使用していないこと。

- 実際に採用するCodex固定版とChatGPTアプリ版の組合せ。更新ごとにパイロットが必要です。

# 4. 最終アーキテクチャと役割分担

![図4-1 配布・特権実行・対象判定の責任分界](assets/media/image1.png)

*図4-1 配布・特権実行・対象判定の責任分界*

| **構成要素**        | **責任**                                                               | **書込み先 / 資格情報**                     |
|---------------------|------------------------------------------------------------------------|---------------------------------------------|
| ChatGPT管理ポリシー | Codex権限、Windows sandbox実装、機能可否を強制                         | クラウド。ワークスペース管理者              |
| Active Directory    | 端末 -> 正式利用者、許可ユーザー、Pilot/Prod PC                       | managedBy/グループ。委任AD管理者            |
| 配布基盤/SKYSEA     | MSIX、Codex公式パッケージ、署名済みPS1/PSD1、requirementsを配布/棚卸し | Program Files/ProgramData。配布サービス権限 |
| GPOタスク           | 特権setupの起動、再試行、PCグループ絞込み                              | タスクスケジューラ。LocalSystem             |
| 端末スクリプト      | 署名/ハッシュ/AD/SID/プロファイル検証、setup、ログ                     | 対象 .codex とProgramData。LocalSystem      |

## 4.1 セキュリティ原則

- Domain Adminの資格情報を端末ジョブへ保存しない。LocalSystemで必要な端末内処理を完結させる。

- 対象が不明、AD照会不能、署名/ハッシュ不一致、プロファイル不正では変更せず終了する。

- 一般ユーザーが書き換え可能な場所からSYSTEMスクリプトやCodexバイナリを実行しない。

- 秘密情報をログへ出さない。.sandbox-secretsの内容をチケット、共有フォルダー、資産収集へ載せない。

- AllSignedだけに依存せず、署名者Thumbprint固定、SHA-256、ACL、可能ならWDAC/AppLockerを組み合わせる。

# 5. ChatGPT / Codexクラウドポリシーの設定

![図5-1 ポリシー作成画面イメージ](assets/media/image3.png)

*図5-1 ポリシー作成画面イメージ*

## 5.1 画面で行う操作

1. **ポリシーページを開く**
   ChatGPTワークスペース管理者で `https://chatgpt.com/codex/cloud/settings/policies` を開きます。

2. **パイロット用ポリシーを作る**
   Create policy / New policy / Create requirements に相当するボタンを選択し、名称を `Codex-Windows-Elevated-Pilot` とします。

3. **Requirements/TOMLを登録する**
   下記の設定を貼り付けます。UI表記が変わってもキーと値を優先します。

4. **少人数グループへ割り当てる**
   ADグループではなく、ChatGPTワークスペース側のパイロットグループへ割り当てます。

5. **端末setup成功後に拡大する**
   最初から全社へ割り当てません。3台/10台の端末側成功を確認して本番グループへ拡大します。

**推奨requirements.toml**

```toml
# ChatGPT/Codex cloud requirementsと同じ制約を、Windows端末側にも配置する例です。
# 本番ではクラウドポリシーと内容を一致させてください。
allowed_approval_policies = ["on-request"]
default_permissions = ":workspace"
allow_remote_control = false
allow_appshots = false
[allowed_permission_profiles]
":read-only" = true
":workspace" = true
# ":danger-full-access" は記載しない（許可リスト外として拒否）
[windows]
allowed_sandbox_implementations = ["elevated"]
sandbox_private_desktop = true
```

## 5.2 設定値の意味

| **キー**                              | **推奨値**                | **意味**                                          |
|---------------------------------------|---------------------------|---------------------------------------------------|
| allowed_approval_policies             | `["on-request"]`          | 必要時に利用者承認を要求。                        |
| default_permissions                   | :workspace                | 作業領域中心の標準権限。                          |
| allowed_permission_profiles           | read-only / workspaceのみ | 許可リスト。danger-full-accessは記載せず拒否。    |
| allowed_sandbox_implementations       | `["elevated"]`            | 弱いWindows sandboxへ自動フォールバックさせない。 |
| sandbox_private_desktop               | true                      | サンドボックスを専用デスクトップへ分離。          |
| allow_remote_control / allow_appshots | false                     | 要件とリスク受容が決まるまで無効。                |

> **[初心者注意] ADグループとChatGPTグループは別物**
>
> ADグループは端末スクリプトの認可とGPO対象に使います。クラウドポリシーはChatGPTワークスペースのユーザー/グループへ割り当てます。両方のメンバーを同じ対象者台帳から同期してください。

# 6. ADで端末と利用者を正式に対応付ける

## 6.1 作成するADグループ

| **グループ**             | **種類**                  | **用途**                  |
|--------------------------|---------------------------|---------------------------|
| GG-Codex-Users           | グローバル / セキュリティ | Codexを許可するユーザー。 |
| GG-Codex-Computers-Pilot | グローバル / セキュリティ | パイロットGPOの対象PC。   |
| GG-Codex-Computers-Prod  | グローバル / セキュリティ | 本番GPOの対象PC。         |

1. **Active Directory ユーザーとコンピューターを開く**
   管理端末で `dsa.msc` を実行します。

2. **グループ用OUを右クリック**
   `新規作成` -> `グループ` を選択します。

3. **種類を設定**
   スコープはグローバル、種類はセキュリティとします。

4. **対象を追加**
   利用者はGG-Codex-Users、端末はPilot/Prodのいずれかへ追加します。

## 6.2 managedByを手動で確認する画面

![図6-1 ADUCのManaged By設定画面イメージ](assets/media/image4.png)

*図6-1 ADUCのManaged By設定画面イメージ*

## 6.3 100台以上を一括登録する

CSVは「100個の個別コマンド」ではなく、端末と利用者の正式な貸与関係を一度だけ機械処理するための入力です。資産台帳やCMDBから出力し、情報システムと資産管理責任者が承認します。

**最初は必ず変更なしで検証**

```powershell
.\Set-CodexDeviceUserMapping.ps1 `
-CsvPath .\CodexDeviceUserMap.csv `
-AuthorizedUserGroupSamAccountName 'GG-Codex-Users' `
-ReportPath .\Mapping-Report.csv `
-WhatIf
```

**承認後に反映**

```powershell
.\Set-CodexDeviceUserMapping.ps1 `
-CsvPath .\CodexDeviceUserMap.csv `
-AuthorizedUserGroupSamAccountName 'GG-Codex-Users' `
-ReportPath .\Mapping-Report.csv
```

> **[Fail Closed] 既存managedByは自動上書きしない**
>
> 別オブジェクトが設定済みならスクリプトはRejectedにします。資産管理責任者が新旧割当を確認した場合だけ `-OverwriteExisting` を使用します。

## 6.4 端末側の自動判定

![図6-2 全端末共通スクリプトによる対象決定](assets/media/image5.png)

*図6-2 全端末共通スクリプトによる対象決定*

## 6.5 正しいコマンドの生成

| **値**       | **取得元**                                             | **例**                                  |
|--------------|--------------------------------------------------------|-----------------------------------------|
| 端末名       | `$env:COMPUTERNAME`。ADコンピューター検索だけに使用 | PC-TKY-001                              |
| ADアカウント | managedByユーザーSIDをNTAccountへ変換                  | TESTDOMAIN\tanaka-tarou                 |
| SID          | AD user.objectSid                                      | S-1-5-21-...                            |
| プロファイル | Win32_UserProfile.LocalPath                            | C:\Users\tanaka-tarou.TESTDOMAIN        |
| CODEX_HOME   | LocalPath + .codex                                     | C:\Users\tanaka-tarou.TESTDOMAIN\.codex |

**実行例（SYSTEMタスクでは --current-user を使用禁止。--user と --codex-home を明示）**

```powershell
"C:\Program Files\OpenAI\CodexCLI\bin\codex.exe" sandbox setup --elevated `
--user "TESTDOMAIN\tanaka-tarou" `
--codex-home "C:\Users\tanaka-tarou.TESTDOMAIN\.codex"
```

# 7. ChatGPTアプリとCodexパッケージの配布準備

## 7.1 ChatGPT Windowsアプリ

| **方式**            | **画面/入力値**                                           | **使いどころ**                             |
|---------------------|-----------------------------------------------------------|--------------------------------------------|
| Microsoft Store連携 | 製品ID: 9PLM9XGG6VKS                                      | Store利用と自動更新を許容する標準端末。    |
| 企業向けMSIX        | OpenAI公式x64/Arm64 MSIX + 必要に応じオフラインライセンス | 更新リングと配布時期を厳密に管理する端末。 |

> **[禁止] ユーザープロファイルへ手作業コピーしない**
>
> ChatGPTアプリはStore署名アプリ/MSIXとして配布します。公式の単独MSIや非Store EXEを前提にした配布設計は採用しません。

## 7.2 Codex CLIは必要か

ChatGPTデスクトップアプリの一般利用に、利用者向けCodex CLIを別途PATHへ登録することが常に必須という意味ではありません。ただし今回の管理用コマンド `codex sandbox setup` を実行するため、IT管理用のCodex Windows公式パッケージ一式を端末へ配置します。

## 7.3 公式パッケージ構造を崩さない

**保持する構造**

```text
C:\Program Files\OpenAI\CodexCLI\
├─ codex-package.json
├─ bin\
│ ├─ codex.exe
│ └─ codex-code-mode-host.exe
├─ codex-path\
│ └─ rg.exe
└─ codex-resources\
   ├─ codex-command-runner.exe
   └─ codex-windows-sandbox-setup.exe
```

> **[重要] codex.exeだけを抜き出さない**
>
> setup helperとcommand runnerは同じ公式パッケージ構造で必要です。付属設定例は6ファイルすべてのSHA-256を固定します。

## 7.4 ステージング手順

1. **公式安定版を固定する**
   本番端末でlatestを直接取得せず、管理用ステージング端末で採用版を決めます。

2. **公式アーカイブを検証する**
   リリースメタデータ/チェックサムでダウンロード資産を確認します。

3. **公式構造のまま展開する**
   `C:\Program Files\OpenAI\CodexCLI` 用の社内配布パッケージを作ります。

4. **展開後SHA-256を記録する**
   `CodexDeploymentConfig.psd1` のRequiredFilesへ記録します。

5. **スクリプトと設定を署名する**
   社内コード署名証明書でPS1/PSD1を署名し、GPO引数へThumbprintを固定します。

6. **ACLを固定する**
   Program Files配下はSYSTEM/Administratorsのみ変更可、Usersは読み取り/実行だけにします。

**展開後ハッシュの取得**

```powershell
Get-ChildItem 'C:\Program Files\OpenAI\CodexCLI' -Recurse -File |
Get-FileHash -Algorithm SHA256 |
Format-Table Path,Hash -AutoSize
```

> **[運用] 本番端末でオンラインインストールしない**
>
> `irm <URL> | iex` のような実行時ダウンロードは、取得タイミングによる版差、外部通信失敗、内容変更のリスクがあるため採用しません。

# 8. GPOによるSYSTEMタスクの作成

## 8.1 GPOを作成し対象PCのOUへリンク

1. **グループ ポリシーの管理を開く**
   管理端末で `gpmc.msc` を実行します。

2. **GPOを新規作成**
   `グループ ポリシー オブジェクト` -> `新規`。名前は `GPO-Codex-WindowsSandbox-Provision`。

3. **コンピューターOUへリンク**
   ユーザーOUではなく、対象PCのコンピューターオブジェクトが入るOUへリンクします。

4. **セキュリティフィルター**
   PilotではGG-Codex-Computers-PilotにRead/Applyを許可します。Authenticated UsersまたはDomain ComputersのReadは残し、Applyだけを対象PCグループで絞ります。明示Denyは使いません。

5. **PCを再起動**
   コンピューターグループへ追加した後は再起動し、コンピュータートークンを更新します。

## 8.2 タスク画面までの経路

![図8-1 GPOタスク設定の全体像](assets/media/image6.png)

*図8-1 GPOタスク設定の全体像*

## 8.3 「全般」タブ

| **画面項目**     | **設定値**                                                                        |
|------------------|-----------------------------------------------------------------------------------|
| アクション       | 更新                                                                              |
| 名前             | OpenAI Codex Elevated Sandbox Provisioning                                        |
| 実行するユーザー | NT AUTHORITY\SYSTEM（`ユーザーまたはグループの変更` -> SYSTEM -> 名前の確認） |
| ログオン条件     | ユーザーがログオンしているかどうかにかかわらず実行                                |
| 権限             | 最上位の特権で実行                                                                |
| 構成対象         | 御社標準のWindows 10/11対応値                                                     |

> **[禁止] Domain Adminを指定しない**
>
> SYSTEMは端末内の必要な高権限を持ち、パスワードをタスクへ保存しません。ネットワーク上はコンピューターアカウントとして動作します。

## 8.4 「トリガー」タブ

| **トリガー**     | **設定**                                                     |
|------------------|--------------------------------------------------------------|
| スタートアップ時 | 有効。3分遅延。ネットワーク/DC初期化を待つ。                 |
| 毎日             | 例: 03:00。配布遅延、AD一時障害、版/ポリシー更新時の再試行。 |
| ログオン時       | 使用しない。ログオンした人物を対象決定に使わない。           |

## 8.5 「操作」タブ

| **項目**   | **設定値**                                                |
|------------|-----------------------------------------------------------|
| プログラム | C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe |
| 引数       | 下記を1行で入力                                           |
| 開始       | C:\Program Files\Company\CodexProvisioning                |

**追加する引数**

```powershell
-NoLogo -NoProfile -NonInteractive -ExecutionPolicy AllSigned -File "C:\Program Files\Company\CodexProvisioning\Provision-CodexSandbox.ps1" -ConfigPath "C:\Program Files\Company\CodexProvisioning\CodexDeploymentConfig.psd1" -ApprovedSignerThumbprint "<40_HEX_THUMBPRINT>"
```

## 8.6 「条件」「設定」タブ

| **項目**             | **推奨値**                                       |
|----------------------|--------------------------------------------------|
| ネットワーク         | 指定ネットワーク接続が使用可能な場合のみ開始     |
| AC電源               | ノートPCでも実行できるよう「AC電源時のみ」を無効 |
| 予定時刻を逃した場合 | すぐに実行                                       |
| 再試行               | 15分間隔で3回                                    |
| タイムアウト         | 15分で停止                                       |
| 多重実行             | 新しいインスタンスを開始しない                   |
| 一度だけ適用         | 選択しない。GPO更新/再適用を可能にする           |

## 8.7 GPO適用後の確認

**対象PCの管理者PowerShell**

```powershell
gpupdate /force
gpresult /h C:\ProgramData\Company\CodexProvisioning\gpresult.html
```

`gpresult.html` のコンピューター設定で `GPO-Codex-WindowsSandbox-Provision` が「適用されたGPO」にあることを確認します。グループへ追加直後はPC再起動が必要です。

**パイロット端末で即時実行**

```powershell
schtasks.exe /Run /TN "OpenAI Codex Elevated Sandbox Provisioning"
```

## 8.8 UACが表示されない理由

管理用setupコマンドは、呼び出し元が昇格済みかを確認します。SYSTEM/Highestのタスクは既に昇格済みであり、UACの対話セッションを必要としません。利用者がChatGPTを起動する前に事前構成を完了させます。

# 9. SKYSEA / 既存配布製品の安全な使い方

## 9.1 SKYSEAに任せる役割

- ChatGPTアプリ/MSIXとライセンスの配布。

- Codex公式パッケージ一式のProgram Filesへの配布。

- 署名済みPS1/PSD1とrequirements.tomlの配布。

- ファイルパス、版、SHA-256、タスク状態、state.json/validation-reportの有無の棚卸し。

- Pilot/Prodの端末グループ、配布スケジュール、失敗端末の再配布。

## 9.2 SKYSEAに任せない役割

> **[最重要] Domain Adminでsetupを直接実行しない**
>
> LocalSystemで十分な端末内権限があります。Domain Admin資格情報を配布ジョブへ持ち込むと、漏えい・誤設定時の影響がドメイン全体へ拡大します。

## 9.3 SKYSEA単独実行を代替候補にできる条件

御社契約版の公式マニュアルまたはメーカー回答で、次のすべてが確認できた場合だけ代替候補です。本書の標準方式はGPOのままとします。

- LocalSystemまたは製品サービスコンテキストで、Domain Admin資格情報を保存せず実行できる。

- 非対話実行、終了コード取得、タイムアウト、再試行、多重実行防止ができる。

- 署名/ハッシュ検証後に固定パスから実行できる。

- ログオンユーザーのセキュリティコンテキストへ切り替わらない。

| **評価軸**  | **GPO SYSTEMタスク**  | **SKYSEAをDomain Adminで実行**    |
|-------------|-----------------------|-----------------------------------|
| 資格情報    | パスワード不要        | 広い資格情報を保存/利用する可能性 |
| 影響範囲    | 端末内                | 侵害時にドメインへ拡大し得る      |
| UAC/非対話  | Windows仕様として明確 | 契約版/機能の確認が必要           |
| 配布/棚卸し | 不得手                | 得意                              |

# 10. 段階展開

![図10-1 展開リングと判定ゲート](assets/media/image7.png)

*図10-1 展開リングと判定ゲート*

## 10.1 推奨順序

| **段階**   | **対象** | **実施内容**                                            | **次へ進む条件**              |
|------------|----------|---------------------------------------------------------|-------------------------------|
| 準備       | 管理環境 | ポリシー、固定版、署名、AD対応表、GPO、テスト手順を完成 | レビュー承認                  |
| 技術検証   | 3台      | 異なるWindowsビルド/EDR。全ログ採取                     | UAC 0、誤選定0、Critical pass |
| パイロット | 10台     | 異なるOU、Proxy、VPN、部門を含める                      | 5営業日安定、ヘルプデスク承認 |
| Wave 1     | 25～30台 | 一括配布と監視/復旧負荷を確認                           | 失敗率基準内、復旧手順確認    |
| 本番       | 残り     | setup成功確認後にアプリ/ポリシーを拡大                  | 全対象の状態回収              |

## 10.2 配布順序

1. **ADグループとmanagedByを準備**
   正本CSVのRejectedをゼロにします。

2. **Codex公式パッケージと署名済みファイルを配布**
   存在、ACL、ハッシュ、版を棚卸しします。

3. **requirements.tomlを配布**
   クラウド要件と同じ内容/ハッシュにします。

4. **GPOをPilot PCへ適用**
   PC再起動後、タスクを即時実行します。

5. **事前構成成功を確認**
   state.jsonとTest-CodexDeployment.ps1のレポートを回収します。

6. **ChatGPTアプリを配布/有効化**
   失敗端末へはアプリを配布しない、またはポリシー割当を保留します。

7. **クラウドポリシーをPilotへ割り当て**
   端末側成功後にelevated強制を有効化します。

8. **標準ユーザーで業務試験**
   UAC、権限プロファイル、ネットワーク、旧プロファイル無変更を確認します。

# 11. 動作確認・受入判定

![図11-1 端末側の確認順序](assets/media/image8.png)

*図11-1 端末側の確認順序*

## 11.1 タスク スケジューラ

1. **タスク スケジューラを開く**
   `taskschd.msc` を実行します。

2. **対象タスクを選ぶ**
   タスク スケジューラ ライブラリの `OpenAI Codex Elevated Sandbox Provisioning`。

3. **全般を確認**
   実行ユーザーSYSTEM、最上位の特権が有効。

4. **履歴/結果を確認**
   前回の実行結果 `0x0` が成功。その他は終了コード表と照合します。

## 11.2 成果物

**確認するパス**

```text
C:\ProgramData\Company\CodexProvisioning\
├─ provisioning.jsonl
├─ state.json
└─ validation-report.json

<対象LocalPath>\.codex\
├─ config.toml
├─ .sandbox\setup_marker.json
└─ .sandbox-secrets\sandbox_users.json
```

> **[機密] secretsの内容を見ない/集めない**
>
> `.sandbox-secrets` は資格情報を含む制御情報です。存在とACLだけを確認し、内容を表示、コピー、資産収集、チケット添付しません。

## 11.3 付属受入テスト

**読み取り専用テスト**

```powershell
powershell.exe -NoProfile -ExecutionPolicy AllSigned `
-File "C:\Program Files\Company\CodexProvisioning\Test-CodexDeployment.ps1"
```

## 11.4 必須受入基準

| **分類**     | **基準**                                                                                |
|--------------|-----------------------------------------------------------------------------------------|
| 対象性       | managedByのユーザーとstate.jsonのSID/アカウントが一致。旧プロファイルに.codex変更なし。 |
| セキュリティ | UAC 0件、Domain Admin資格情報未使用、署名/ハッシュ検証有効。                            |
| 機能         | read-only/workspace利用可、danger-full-access不可、Windows sandbox=elevated。           |
| 運用         | 終了コード、JSONLログ、validation-reportを管理基盤から回収可能。                        |
| 障害         | AD停止、割当不在、ハッシュ不一致で変更せず停止する。                                    |

# 12. 障害対応

## 12.1 終了コード

| **コード** | **意味**                       | **一次対応**                                        |
|------------|--------------------------------|-----------------------------------------------------|
| 0          | 成功または既に適合             | 対応不要                                            |
| 10         | SYSTEM以外                     | GPOタスクの実行ユーザーを修正                       |
| 11         | 別インスタンス実行中           | タスク多重実行設定/残存プロセス確認                 |
| 12         | 署名/Thumbprint不一致          | 証明書チェーン、署名、GPO引数確認                   |
| 13         | 設定/パス/ACL/ハッシュ不一致   | 配布パッケージと権限を再確認                        |
| 14         | CLIバージョン不一致            | 承認版を再配布、PSD1を更新/再署名                   |
| 20         | managedBy不在/不正             | AD割当とコンピューターオブジェクト確認              |
| 21         | ユーザー無効/ドメイン外/認可外 | 人事/AD/GG-Codex-Users確認                          |
| 22         | 一致する通常プロファイルなし   | SID、Win32_UserProfile Status/LocalPath確認         |
| 23         | 対象ユーザー変更未承認         | 再割当手順を実施後、AllowTargetChangeを一時承認     |
| 30         | AD照会失敗                     | DNS、DC、時刻、信頼関係、PCアカウント読取確認       |
| 50         | Codex setup失敗                | Codex sandboxログ、EDR、Firewall/WFP、権利確認      |
| 51         | 成功応答後の成果物/設定不足    | helper遮断、ACL、ディスク、active profile上書き確認 |
| 99         | 想定外                         | JSONL/イベントを採取しリング停止                    |

## 12.2 よくある症状

| **症状**           | **確認ポイント**                                      | **対処**                                                  |
|--------------------|-------------------------------------------------------|-----------------------------------------------------------|
| UACが出る          | 利用者セッションからsetupを直接起動していないか       | GPO SYSTEM/Highestの事前構成を先に成功させる              |
| Windows error 1385 | ローカルログオン権、拒否権、セキュリティベースライン  | 正常OUとgpresult比較。Everyoneへ広い権利を付与しない      |
| 終了20             | managedBy空、グループ指定、DN不正                     | 正本CSVからユーザーDNを1件設定                            |
| 終了22             | プロファイル未作成、Temp/Mandatory/Corrupt、SID不一致 | 対象者に通常ログオンさせる。破損は別途修復                |
| 終了13             | EDR隔離、パッケージ差替え、Users書込み可              | 固定パッケージ再配布、許可ルール/ACL是正                  |
| 終了51             | active profileがunelevatedを上書き                    | config.tomlのprofileと `[profiles.<name>.windows]` を確認 |

# 13. 利用者変更・退職・共有PC・更新

## 13.1 同一端末の利用者変更

1. **貸与台帳で新利用者を承認**
   旧利用者の業務データ移行と端末利用停止を完了します。

2. **旧利用者のCodex許可を終了**
   GG-Codex-Usersから除外するか、アカウント/端末利用権を終了します。

3. **managedByを新利用者へ更新**
   CSVの変更を -WhatIf -> 承認 -> 反映します。

4. **新利用者が通常ログオン**
   Win32_UserProfileを作成します。

5. **旧CODEX_HOMEの扱いを決定**
   情報管理ルールに従い保全/削除。スクリプトで自動削除しません。

6. **AllowTargetChangeを一時承認**
   PSD1を変更/再署名し、対象PCだけ再実行。state.jsonが新SIDへ変わったらfalseへ戻します。

> **[重要] 旧利用者と新利用者を同時に使わせない**
>
> 再プロビジョニングは端末共通sandboxアカウントのパスワードを更新します。旧プロファイルでCodexを継続利用しないことを確認してください。

## 13.2 退職者対応

- 退職日までにmanagedByを空にするか後任者へ変更し、GG-Codex-Usersから除外します。

- タスクはmanagedBy不在/無効ユーザーでFail Closedし、残存プロファイルを選択しません。

- Windowsプロファイル削除は既存の人事/情報管理手順で行い、Codexスクリプトへ削除機能を持たせません。

- .sandbox-secretsをバックアップ、移送、チケット添付しません。

## 13.3 共有PC / VDI

> **[対象外] 本番対象グループへ入れない**
>
> 本設計は1台1対象プロファイルです。共有PC、シフト端末、VDIプールで複数ユーザーを構成しません。managedByへグループを設定したり、ログオンユーザーごとに実行したりしません。

## 13.4 Codex/ChatGPTアプリ更新

| **手順**         | **管理内容**                                                         |
|------------------|----------------------------------------------------------------------|
| 1\. 検証版取得   | 公式安定版をx64/Arm64別に取得。                                      |
| 2\. チェックサム | 公式アーカイブを検証し、展開後6ファイルのSHA-256を記録。             |
| 3\. 組合せ試験   | ChatGPTアプリ、CLI、cloud requirements、Proxy/EDRを同じPilotで確認。 |
| 4\. PSD1更新     | ApprovedCodexVersion、ハッシュ、PolicyVersionを更新し再署名。        |
| 5\. 再構成       | 3台 -> 10台 -> Wave 1の順にタスクを再実行。                        |
| 6\. アプリ更新   | sandbox setup成功後にChatGPTアプリ更新リングを進める。               |

PR #24831は事前構成の入口を提供しますが、将来のElevated Sandbox更新を企業ITが完全自動調整する仕組みまでは対象外です。固定版、ハッシュ、PolicyVersionを更新単位で管理します。

# 14. ロールバックと未検証事項

## 14.1 安全な停止手順

1. **クラウドポリシー割当を停止**
   本番グループへのelevated強制を外し、新規利用を止めます。

2. **GPO対象PCグループから外す**
   GPOリンク全体を削除せず、PCグループを段階的に外します。

3. **配布を停止**
   ChatGPTアプリ/Codexパッケージの新規配布と自動更新を止めます。

4. **状態を保全**
   state.json、JSONL、gpresult、validation-reportを採取します。secrets本体は採取しません。

5. **正式なアンインストール/再イメージ**
   アプリ/パッケージは配布製品の手順で削除。sandboxアカウント、WFP、ACLを未検証の手作業で一括削除しません。

## 14.2 制約と未検証事項

| **項目**           | **状態 / 必須対応**                                                                     |
|--------------------|-----------------------------------------------------------------------------------------|
| Windows実機試験    | 本書作成環境はWindows/AD/GPO/SKYSEAへ接続していない。付属PowerShellは静的レビューまで。 |
| 御社SKYSEA版       | 公開情報では任意コマンドの実行主体を確定できない。契約版マニュアル/メーカー回答で確認。 |
| 複数プロファイル   | 現行ソースから保守的に1台1対象を採用。Codex更新時に再評価。                             |
| Proxy/EDR/WDAC     | 御社固有ルールは3台/10台Pilotで確認。                                                   |
| 完全クリーンアップ | 公式/検証済みcleanupがない状態でローカルユーザー/WFP/ACLを手作業削除しない。            |

> **[承認条件] 本番投入前の必須作業**
>
> Windows PowerShell 5.1でPS1/PSD1を署名し、実際のADドメイン、managedBy、GPO、EDR、Proxy、ChatGPTアプリ版、Codex固定版の組合せをPilot端末で検証してください。

# 付録A. 実装チェックリスト

| **区分** | **確認事項**                                        | **完了** |
|----------|-----------------------------------------------------|----------|
| 設計     | managedByを他用途で使用していない/代替正本を承認    | □        |
| 設計     | 1台1対象プロファイルを端末標準として承認            | □        |
| AD       | GG-Codex-Users/Pilot/Prodを作成                     | □        |
| AD       | CSVの端末名/利用者を資産責任者が承認                | □        |
| AD       | -WhatIfレポートにRejectedがない                     | □        |
| ポリシー | elevatedのみ、workspace既定、danger-full-access拒否 | □        |
| 配布     | ChatGPT MSIX/Store方式を決定                        | □        |
| 配布     | Codex安定版を固定し公式チェックサムを検証           | □        |
| 配布     | 展開後6ファイルのSHA-256をPSD1へ記録                | □        |
| 署名     | PS1/PSD1を社内コード署名しStatus=Valid              | □        |
| GPO      | 対象PC OUへリンク、Read/Applyを正しく設定           | □        |
| GPO      | SYSTEM/Highest、起動遅延、日次、再試行を設定        | □        |
| Pilot    | 3台でUAC 0、誤選定0、Critical failure 0             | □        |
| Pilot    | 10台でOU/EDR/Proxy差を検証                          | □        |
| 本番     | setup成功後にアプリ/ポリシーを拡大                  | □        |
| 運用     | 再割当、退職、更新、障害エスカレーションを承認      | □        |

# 付録B. コマンドと設定のクイックリファレンス

**B.1 管理用コマンド**

```powershell
"C:\Program Files\OpenAI\CodexCLI\bin\codex.exe" sandbox setup --elevated `
--user "TESTDOMAIN\tanaka-tarou" `
--codex-home "C:\Users\tanaka-tarou.TESTDOMAIN\.codex"
```

**B.2 GPO「操作」タブ引数**

```powershell
-NoLogo -NoProfile -NonInteractive -ExecutionPolicy AllSigned -File "C:\Program Files\Company\CodexProvisioning\Provision-CodexSandbox.ps1" -ConfigPath "C:\Program Files\Company\CodexProvisioning\CodexDeploymentConfig.psd1" -ApprovedSignerThumbprint "<40_HEX_THUMBPRINT>"
```

**B.3 AD CSV取込**

```powershell
.\Set-CodexDeviceUserMapping.ps1 -CsvPath .\CodexDeviceUserMap.csv -AuthorizedUserGroupSamAccountName 'GG-Codex-Users' -ReportPath .\Mapping-Report.csv -WhatIf
```

**B.4 端末受入テスト**

```powershell
powershell.exe -NoProfile -ExecutionPolicy AllSigned -File "C:\Program Files\Company\CodexProvisioning\Test-CodexDeployment.ps1"
```

## B.5 配布キット

| **ファイル**                       | **SHA-256**                                                      |
|------------------------------------|------------------------------------------------------------------|
| CodexDeploymentConfig.psd1.example | 2ff2e40c3e3b10ce18e3491f1697d2b0190ce6c62ac0995624629ea7555fe662 |
| CodexDeviceUserMap.csv             | b5fa5121ab11fd260a6160f790def842e62145ccdf9faf68eba4b3e0e7a0c7f5 |
| GPO-Task-Action.txt                | a0ca4746f64ff94cca0ccc46ad27c599120d46f9731440892e2b67d2434c4912 |
| Provision-CodexSandbox.ps1         | 0a9526dfe5d7e179a6c0287f8e9ba29a867d8c6b8f89af2869ef6bdcb07ad65d |
| README_ja.md                       | 63a61f4d8fdab132887c1c857bfe3a55657f0e7bc287e62bc0746209dd2dbdb5 |
| SHA256SUMS.txt                     | 0ee0fad50713bc0224cd12296342bab067c9a905b03b2cc45a828c3e3a0afc60 |
| Set-CodexDeviceUserMapping.ps1     | eb50328d930e8ea62436fba5c5f07d8dc90127d6c6891550cdf53fac08d8c855 |
| Test-CodexDeployment.ps1           | a48b39c8818d436d75207561205813fa1700ef353291d7f75bdcffe6e0b89e73 |
| requirements.toml                  | 6630a65ec9a4cd050c3aa7bbcb90bd19dbe088c2fa4bd02be2844b9d1587de08 |

# 付録C. 参考資料

| **ID** | **資料**                                   | **URL**                                                                                                                                     |
|--------|--------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| OAI-1  | OpenAI - Windows sandbox                   | https://developers.openai.com/codex/windows/windows-sandbox                                                                                 |
| OAI-2  | OpenAI - Managed configuration             | https://developers.openai.com/codex/enterprise/managed-configuration                                                                        |
| OAI-3  | OpenAI - Deploy the Windows app            | https://developers.openai.com/codex/enterprise/windows-deployment                                                                           |
| OAI-4  | OpenAI Codex PR #24831                    | https://github.com/openai/codex/pull/24831                                                                                                  |
| OAI-5  | Codex sandbox_setup.rs                     | https://github.com/openai/codex/blob/main/codex-rs/cli/src/sandbox_setup.rs                                                                 |
| OAI-6  | Windows sandbox setup.rs                   | https://github.com/openai/codex/blob/main/codex-rs/windows-sandbox-rs/src/setup.rs                                                          |
| OAI-7  | Windows sandbox sandbox_users.rs           | https://github.com/openai/codex/blob/main/codex-rs/windows-sandbox-rs/src/bin/setup_main/win/sandbox_users.rs                               |
| OAI-8  | Codex Windows install.ps1                  | https://github.com/openai/codex/blob/main/scripts/install/install.ps1                                                                       |
| MS-1   | Microsoft - LocalSystem Account            | https://learn.microsoft.com/windows/win32/services/localsystem-account                                                                      |
| MS-2   | Microsoft - Win32_UserProfile              | https://learn.microsoft.com/previous-versions/windows/desktop/userprofileprov/win32-userprofile                                             |
| MS-3   | Microsoft - managedBy attribute            | https://learn.microsoft.com/openspecs/windows_protocols/ms-adls/f782cdbe-b65d-4a31-b15c-01c9087f83a4                                        |
| MS-4   | Microsoft - Set-ADComputer                 | https://learn.microsoft.com/powershell/module/activedirectory/set-adcomputer                                                                |
| MS-5   | Microsoft - Scheduled Task preference item | https://learn.microsoft.com/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn789200(v=ws.11)                              |
| MS-6   | Microsoft - GPO read/apply permissions     | https://learn.microsoft.com/troubleshoot/windows-server/group-policy/cannot-apply-user-gpo-when-computer-objects-dont-have-read-permissions |
| SKY-1  | SKYSEA Client View - 資産管理              | https://www.skyseaclientview.net/function/res/                                                                                              |
| SKY-2  | SKYSEA Client View - ソフトウェア資産管理  | https://www.skyseaclientview.net/function/sam/                                                                                              |

参照日: 2026-08-03。製品UI、設定キー、実装、パッケージ構造は更新されるため、採用版更新時に再確認してください。

# 付録D. 提出物の位置付け

> **[位置付け] 最終決定版設計 + 本番候補実装**
>
> 本書とZIP内スクリプトは、相違する添付2資料を再調査して統合した最終設計です。ただしベンダー保証済み手順ではなく、御社Windows/AD/GPO/SKYSEA/EDR/Proxy環境でのPilot合格をもって運用版として承認してください。
