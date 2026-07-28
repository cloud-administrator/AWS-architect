# 調査結果：Claude CoworkとClaude Codeの違い

**調査日：2026年7月28日**
Anthropic／Claudeの公式サイト、公式ヘルプ、公式ドキュメントだけを参照しました。

## 結論

**Claude Coworkは、調査、資料作成、ファイル整理、データ分析などの「一般的な業務」を、Claudeにまとめて任せるためのエージェント機能です。**

Claude Codeと同じエージェント型の仕組みを利用していますが、目的と利用画面が異なります。

* **Claude Code**：ソフトウェア開発をするAIエンジニア
* **Claude Cowork**：資料作成や調査、事務作業などを行うAI業務アシスタント

そして、最も重要な `settings.json` についての結論は次のとおりです。

> **Cowork全体を、Claude Codeと同じように `settings.json` で一括制御することはできません。**

ただし、ローカルで動くCoworkについては、特定の管理設定やネットワーク設定が適用されるケースがあります。したがって、正確には次の評価になります。

> **原則として不可。一部の設定項目に限って、ローカルCoworkへ適用される例外がある。**

企業向けのCowork統制では、`settings.json` ではなく、主として以下を使用します。

1. Claude Enterpriseの組織設定
2. グループとカスタムロール
3. Claude Desktopに対するMDM／Group Policy
4. 組織のモデル、コネクタ、プラグイン設定
5. OpenTelemetryによる監視

---

# 1. Claude Coworkとは

## 簡単にいうと「AIに業務を渡す場所」

通常のClaude Chatでは、基本的にClaudeが質問に答えます。

一方、Coworkでは「どうすればよいかを教えて」と相談するのではなく、**「この仕事を完成させて」と仕事そのものを渡します。**

たとえば、次のような依頼です。

* このフォルダ内の契約書を分類し、一覧表を作成する
* 複数の調査資料を読み、経営会議用のレポートを作成する
* CSVデータを分析し、ExcelとPowerPointを作成する
* 領収書を整理し、経費報告書にまとめる
* 議事録から課題とアクションアイテムを抽出する
* 毎週月曜日に定例レポートを作成する

Coworkは、利用者が指定したファイルやツールにアクセスし、作業を複数のステップに分解して、最終的な文書、表計算、プレゼンテーションなどを作成します。([Claude][1])

## Chat・Cowork・Claude Codeのイメージ

初心者向けにたとえると、次のようになります。

| 製品・機能         | 人にたとえると              | 主な役割                |
| ------------- | -------------------- | ------------------- |
| Claude Chat   | 相談に答えるアドバイザー         | 質問への回答、文章作成、アイデア出し  |
| Claude Cowork | 仕事を一式引き受ける業務担当者      | 調査、分析、資料作成、ファイル操作   |
| Claude Code   | 開発環境を操作するソフトウェアエンジニア | コード作成、バグ修正、テスト、開発作業 |

Anthropic自身も、Claude Codeは「ソフトウェアエンジニアリング向け」、Coworkは「調査、分析、文書作成などの非コーディング業務向け」と説明しています。([Claude][1])

---

# 2. Coworkはどのように仕事を進めるのか

ユーザーが成果物を依頼すると、Coworkは概ね次の流れで作業します。

1. 依頼内容を分析する
2. 作業計画を作る
3. 必要に応じて複数のサブタスクに分割する
4. ファイル、コネクタ、ブラウザなどを利用する
5. 必要に応じてコードやシェルコマンドを隔離環境で実行する
6. 複数の作業を並行して進める
7. 完成した文書、表計算、スライドなどを返す

実行中には、Claudeが何をしているかを確認し、途中で追加指示を与えたり、方向を修正したりできます。複雑な仕事では複数のサブエージェントを並行して動かすこともあります。([Claude Help Center][2])

## 「非コーディング向け」でも内部ではコードを実行する

Coworkは非エンジニア向けですが、内部ではデータ処理や文書作成のためにコードやシェルコマンドを実行することがあります。

違いは、ユーザー自身がターミナルを操作する必要がないことです。

つまり、

* Claude Code：ユーザーが開発環境の中でClaudeと一緒に作業する
* Cowork：ユーザーは成果物を指示し、Claudeが裏側の実行方法を決める

という違いです。CoworkはClaude Codeと同じエージェント・アーキテクチャを利用しますが、ターミナルを必要としません。([Claude Help Center][2])

---

# 3. Claude CoworkとClaude Codeの違い

| 比較項目    | Claude Cowork                      | Claude Code                                    |
| ------- | ---------------------------------- | ---------------------------------------------- |
| 主目的     | 一般業務、知識業務の実行                       | ソフトウェア開発                                       |
| 主な利用者   | 営業、企画、法務、経理、人事、調査担当者など             | 開発者、エンジニア、SREなど                                |
| 典型的な依頼  | 調査、分析、文書・Excel・PowerPoint作成、ファイル整理 | コード作成、バグ修正、テスト、依存関係更新                          |
| 操作方法    | 成果物やゴールを自然言語で指示                    | コードベースを開き、開発作業を自然言語で指示                         |
| 主な画面    | Coworkタブ、Web、モバイル、Desktop          | CLI、IDE、DesktopのCodeタブなど                       |
| ファイルの扱い | 指定した業務フォルダのファイルを読み書き               | リポジトリやプロジェクトのソースコードを読み書き                       |
| ターミナル   | 利用者が直接操作する必要はない                    | ターミナル操作が中心となる利用形態がある                           |
| 主な成果物   | Word、Excel、PowerPoint、PDF、レポートなど   | ソースコード、テスト、コミット、PRなど                           |
| カスタマイズ  | Customize、グローバル指示、フォルダ指示、プラグイン     | `settings.json`、`CLAUDE.md`、Skills、Hooks、MCPなど |
| 企業統制    | 組織設定、カスタムロール、Desktop MDM、OTel      | 組織設定に加え、managed settings、リポジトリ設定など             |

CoworkはWord、Excel、PowerPoint、PDF、CSV、画像、コードファイルなど、幅広いファイル形式を扱えます。Claude Codeと共通の技術を利用しますが、「同じエージェント技術を使っている」ことと「設定方式がすべて共通である」ことは別です。([Claude][1])

---

# 4. Coworkは `settings.json` でコントロールできるのか

## 4-1. まず、Claude Codeの設定ファイルを整理する

公式表記は、先頭が小文字の **`settings.json`** です。

Claude Codeには、主に次の設定ファイルがあります。

| 種類         | ファイル                          | 用途                |
| ---------- | ----------------------------- | ----------------- |
| ユーザー設定     | `~/.claude/settings.json`     | そのユーザーの全プロジェクトに適用 |
| プロジェクト共通設定 | `.claude/settings.json`       | リポジトリ内でチーム共有      |
| ローカル設定     | `.claude/settings.local.json` | 個人・端末固有の設定        |
| 管理者設定      | `managed-settings.json`       | 組織管理者が強制する設定      |

Claude Codeの公式ドキュメントでは、`settings.json` はClaude Codeを階層的に設定する公式の仕組みと明記されています。([Claude Platform Docs][3])

ここで重要なのは、次の二つを区別することです。

* **`settings.json`**：通常のユーザー設定やプロジェクト設定
* **`managed-settings.json`**：企業の管理者が配布する強制設定

ユーザーが変更できる `settings.json` と、管理者が変更不能な形で配布する `managed-settings.json` は、同じものではありません。

---

## 4-2. Coworkに対する公式の回答

Claude Codeのモデル設定ドキュメントには、次の趣旨が明記されています。

* CoworkはClaude Codeの「サーフェス」ではない
* CoworkにはClaude Codeのサーバー管理設定が設計上配信されない
* 管理設定ファイルは、そのファイルがCoworkの実行場所に存在する場合のみ適用される
* リモートCoworkはAnthropic管理のVMで動くため、利用者端末に配布した設定ファイルは存在しない

ここでいう「サーフェス」とは、CLI、IDE、DesktopのCodeタブ、Coworkタブなどの製品画面・実行環境を意味します。([Claude Platform Docs][4])

したがって、以下の理解が正確です。

### ユーザー／プロジェクトの `settings.json`

**Cowork全体を制御する汎用的な設定方法としては利用できません。**

たとえば、Claude Code用の `.claude/settings.json` をリポジトリに置いたからといって、Cowork全体の動作、利用可否、クラウド実行、コネクタ権限などが同じように統制されるわけではありません。

### Claude Codeのサーバー管理設定

**Coworkには配信されません。**

公式ドキュメントは、CoworkはClaude Codeのサーフェスではなく、サーバー管理設定を受け取らないと明記しています。([Claude Platform Docs][4])

### 端末に置かれた `managed-settings.json`

**ローカルCoworkでは、公式に対応が記載された一部の設定に限って適用される可能性があります。**

ただし、すべてのClaude Code設定項目がCoworkに適用されるとは、公式には記載されていません。

---

# 5. `settings.json` がCoworkに関係する、確認済みの限定例

## 例1：モデルの許可リスト

Claude Codeの `availableModels` に関する公式表では、MDMまたは管理設定ファイルについて、Coworkでは「配布されている場所で適用」とされています。

一方、リモートCoworkはAnthropic管理VMで実行されるため、端末に置いた管理設定ファイルは届きません。([Claude Platform Docs][4])

ただし、モデル制御については、Claude Enterpriseの**組織のモデルアクセス設定**がCoworkにも正式に適用されます。そのため、企業全体のモデル制御にはこちらを使用する方が適切です。([Claude Help Center][5])

## 例2：プロキシ・証明書・mTLS関連

Claude Desktopが接続を管理するCoworkセッションでは、プロキシや一部のTLS関連環境変数を、次の場所から読み取ることが公式に記載されています。

* 管理設定
* `~/.claude/settings.json`

ただし、リポジトリ内の `.claude/settings.json` は、この用途では無視されます。これはリポジトリが通信経路を不正に変更できないようにするためです。([Claude][6])

これは、Coworkが `settings.json` 全体に対応しているという意味ではありません。**ネットワーク接続に関する限定的な例外**です。

## 例3：サイドロード用フラグの禁止

管理設定の `disableSideloadFlags` は、Claude CodeのCLIフラグだけでなく、DesktopアプリのローカルCoworkセッションにも適用されると明記されています。([Claude Platform Docs][3])

これも、特定の設定キーについて公式にCowork対応が明記されている例です。

## 例4：Skills、Plugins、Connectors

Coworkは、CLI側の `~/.claude` ディレクトリからSkills、Plugins、Connectorsを読み込むのではありません。

Coworkでは、Claudeアカウントの **Customize** で有効化されたものがセッション開始時に同期されます。`~/.claude` にしか存在しないSkillやPluginをCoworkで利用するには、Customize側へ追加する必要があります。([Claude][7])

---

# 6. `settings.json` に関する判定表

| 制御したい内容                  | `settings.json` でのCowork制御 | 公式に推奨される制御方法                                |
| ------------------------ | -------------------------: | ------------------------------------------- |
| Coworkそのものを利用可能／不可能にする   |                     **不可** | Organization settings ＞ Cowork              |
| 部署ごとにCoworkを許可する         |                     **不可** | グループ＋カスタムロール                                |
| クラウドCoworkを許可する          |                     **不可** | Organization settings ＞ Cowork＋カスタムロール      |
| Desktop上のCoworkを無効化する    |                     **不可** | MDM／Group Policyの `secureVmFeaturesEnabled` |
| Coworkがマウントできるフォルダを制限する  |                     **不可** | MDM／Group Policyの `allowedWorkspaceFolders` |
| 利用可能モデルを制限する             |                   **一部のみ** | Organization settings ＞ Models              |
| Skills／Pluginsを配布する      |                   **原則不可** | Customize、組織のSkills／Plugins設定               |
| コネクタ権限を制御する              |                   **原則不可** | 組織設定、カスタムロール、コネクタポリシー                       |
| 書き込み系コネクタの常時許可を禁止する      |                     **不可** | Coworkの組織設定                                 |
| プロキシ／mTLSを設定する           |                 **限定的に可能** | 管理設定または `~/.claude/settings.json`           |
| ローカルCoworkの一部サイドロードを禁止する |                **管理設定で可能** | `disableSideloadFlags`                      |
| 利用状況やツール実行を監視する          |                     **不可** | OpenTelemetry                               |
| その他のClaude Code設定キー      |                     **不明** | 公式にCowork対応が明記されたキーだけを使用                    |

**重要：Claude Codeの設定キーについて、Coworkへの適用可否を網羅した公式の互換性一覧は確認できませんでした。**

したがって、`permissions`、Hooks、MCP関連設定などを含め、公式にCowork対応が明記されていない設定については、今回の調査結果としては**不明**です。

企業導入では、動作したという実機結果だけで対応仕様と判断せず、公式に記載されたキーだけをサポート対象として扱うのが安全です。

---

# 7. Coworkで利用する公式のカスタマイズ方法

Coworkには、Claude Codeの `settings.json` や `CLAUDE.md` とは異なる、Cowork用の設定方法があります。

## グローバル指示

`設定 ＞ Cowork` で、すべてのCoworkセッションに適用する常設指示を設定できます。

たとえば次のような内容です。

* 出力は日本語にする
* 結論を最初に書く
* 社内文書は所定の形式にする
* 数値の根拠を必ず記載する
* 特定の業界用語を使用する

## フォルダ指示

Desktopでローカルフォルダを選択した場合、そのフォルダ固有の指示を与えられます。

例：

* このフォルダは営業企画部の資料である
* 金額はすべて税抜きで扱う
* 元ファイルは変更せず、`output` フォルダに結果を保存する

## Plugins、Skills、Connectors

Coworkでは、Customizeを中心に機能を追加します。

* **Skill**：特定業務の手順や知識
* **Connector**：Google Drive、Slackなど外部サービスとの接続
* **Plugin**：Skill、Connector、サブエージェントなどをまとめたパッケージ

Coworkのグローバル指示、フォルダ指示、Pluginについては公式ヘルプで案内されています。([Claude Help Center][2])

---

# 8. Claude Enterpriseでの主なCowork統制

## 組織全体の有効化・無効化

組織所有者は、`Organization settings ＞ Cowork` からCoworkを組織全体で無効化できます。

この組織設定が主電源であり、組織側で無効にされている場合、カスタムロールから利用を許可することはできません。([Claude Help Center][8])

## 部署・グループごとの制御

Enterpriseでは、カスタムロールを使用して、次の機能を部署やグループ単位で制御できます。

* Claude Cowork
* Claude Code
* Web検索
* Claude in Chrome
* Connectors
* モデルアクセス

カスタムロールは、メンバーのロールが「Custom」に設定されている場合に適用されます。通常のUser、Admin、Ownerにはカスタムロールが直接適用されないため、パイロット設計時に注意が必要です。([Claude Help Center][9])

## クラウドCoworkの制御

公式のEnterprise向けページでは、Team／Enterprise向けWeb・モバイル版Coworkのベータ開始予定日は**2026年8月3日**とされています。

Enterpriseでは、クラウドCoworkはデフォルトで無効です。利用するには、次の両方が必要です。

1. 組織設定で「Run Cowork in the cloud」を有効にする
2. カスタムロールで対象グループにクラウドCowork権限を付与する

本日2026年7月28日時点では開始予定日前であり、さらに段階的なロールアウトが案内されているため、各Enterpriseテナントで実際に利用可能になる正確な日時は**不明**です。([Claude Help Center][8])

## Desktop端末のMDM／Group Policy制御

Claude Desktopは、macOSではMDM、WindowsではGroup PolicyまたはIntuneで制御できます。

主な設定は次のとおりです。

| 設定キー                            | 内容                         |
| ------------------------------- | -------------------------- |
| `allowedWorkspaceFolders`       | Coworkへ接続できるフォルダを制限        |
| `forceLoginOrgUUID`             | 指定した企業組織へのログインを強制          |
| `secureVmFeaturesEnabled`       | DesktopのCoworkを有効／無効化      |
| `isLocalDevMcpEnabled`          | ローカルMCPサーバーを有効／無効化         |
| `isDesktopExtensionEnabled`     | Desktop拡張機能を有効／無効化         |
| `isClaudeCodeForDesktopEnabled` | DesktopのClaude Codeを有効／無効化 |

これらはClaude Codeの `settings.json` ではなく、**Claude Desktop用のOSポリシー**です。([Claude Help Center][10])

---

# 9. ローカルCoworkとクラウドCoworkの違い

企業導入では、この違いが非常に重要です。

## ローカルCowork

* エージェントの処理はユーザー端末上で動作
* コード実行は端末内の隔離されたLinux VMで実施
* 接続したフォルダだけを操作
* 端末に配布したMDM設定や、一部の管理設定を利用できる

## クラウドCowork

* Anthropic管理環境の、一時的で隔離されたサンドボックスで実行
* セッションやファイルはClaudeアカウントに保存
* ノートPCを閉じても作業を継続できる
* 端末に置かれた `settings.json` や `managed-settings.json` はクラウドVMへ届かない
* Desktop経由でローカルファイルへアクセスした場合、そのデータはAnthropic側で処理される

Anthropicは、リモートセッションを組織ごと・セッションごとに隔離し、商用契約下のデータをClaudeの学習には使用しないと説明しています。([Claude Help Center][11])

---

# 10. 企業導入時に特に注意する点

## 10-1. ネットワーク制御だけではすべてを止められない

Coworkは組織のネットワーク送信ポリシーに従います。

ただし、公式ドキュメントでは、そのネットワーク送信制御が次には適用されないとされています。

* Web検索
* Web Fetch
* MCP
* Claude in Chrome

これらは、それぞれ組織設定側で別途無効化・制限する必要があります。([Claude Help Center][8])

## 10-2. 書き込み系コネクタの「常に許可」

Enterpriseでは、書き込み可能なコネクタツールに対して「常に許可」を利用者に認めるか、組織設定で制御できます。

この設定はデフォルトで無効です。無効のままなら、利用者は書き込み操作をタスク単位で承認する必要があります。([Claude Help Center][8])

パイロット期間中は、デフォルトのまま無効にしておく方が安全です。

## 10-3. EDRからVM内部が見えない

公式アーキテクチャ資料では、ローカルCoworkの隔離VM内部を、端末上のEDRから検査できないとされています。リモートセッションは端末外で実行されるため、当然ながらEDRからは観測できません。([Claude Help Center][11])

EDRだけに依存した監視設計では不足します。

## 10-4. OpenTelemetryによる監視

Team／Enterpriseでは、CoworkイベントをOpenTelemetryでSIEMや監視基盤に送信できます。

監視対象には次が含まれます。

* ユーザーのプロンプト
* ツール呼び出し
* MCP呼び出し
* ファイルアクセス
* 人による承認
* 実行結果や処理時間

プロンプト全文やツール引数が送られる可能性があるため、SIEM側のアクセス管理、保存期間、機密情報の取り扱いも設計対象です。([Claude Help Center][12])

---

# 11. 公式情報上、不明または記述が一致していない点

## `settings.json` の完全な互換性

Claude Codeの各設定キーがCoworkに適用されるかを網羅した公式一覧は確認できませんでした。

したがって、公式に個別記載のある以下などを除き、その他は**不明**です。

* モデル許可リストの管理設定
* プロキシ／mTLS関連設定
* `disableSideloadFlags`

## Audit Logs／Compliance API

ここは公式情報同士で記述が一致していません。

新しいTeam／Enterprise向けページには、Web・モバイル経由のCoworkがCompliance APIに記録されるとあります。([Claude Help Center][8])

一方、Coworkのアーキテクチャページおよび製品ページには、CoworkアクティビティはAudit Logs、Compliance API、Data Exportにまだ記録されないとあります。([Claude Help Center][11])

ローカルCoworkとリモートCoworkの違い、またはドキュメント更新時期の差である可能性がありますが、公式情報が一致していないため、現時点の正確な対応範囲は**不明**です。

企業の監査要件に関わるため、導入判断では次の確認が必要です。

* 対象Enterpriseテナントの実際のCompliance API出力
* ローカルセッションとクラウドセッションの差
* Web、モバイル、Desktopごとの差
* Anthropicの担当者またはサポートからの正式回答

---

# 12. 推奨する導入方針

企業で最初から全社員へ開放するのではなく、以下の順序が安全です。

1. **組織のCowork設定とカスタムロールを先に設計する**
   パイロット利用者だけにCoworkを付与します。通常ロールとCustomロールの違いに注意します。

2. **クラウドCoworkは当初無効のままにする**
   データ処理場所、保持期間、Compliance API、監査要件を確認してから有効化します。

3. **書き込み系コネクタの「常に許可」は無効にする**
   初期段階ではタスクごとの承認を要求します。

4. **MDMでアクセス可能フォルダを限定する**
   `allowedWorkspaceFolders` を利用し、個人フォルダ、機密フォルダ、ソースコード領域などを必要に応じて対象外にします。

5. **ローカルMCPとDesktop拡張機能を制限する**
   承認済みのものだけを利用できるようにします。

6. **モデル、Web検索、Claude in Chrome、ネットワークを別々に設計する**
   ネットワーク許可リストだけではWeb検索やMCPを制御できないことに注意します。

7. **OpenTelemetryを先に接続してからパイロットを開始する**
   ファイルアクセス、ツール呼び出し、承認操作などを確認できる状態にします。

8. **公式にCowork対応が明記されていない `settings.json` キーには依存しない**
   検証環境で偶然動作しても、企業の正式な統制手段としては扱わない方が安全です。

---

## 最終的な回答

**Claude Coworkは、Claude Codeと同じエージェント技術を、一般的な業務に使いやすくした機能です。ただし、Claude Codeとは別の製品サーフェスであり、設定方式は共通ではありません。**

**CoworkをClaude Codeと同じように `settings.json` だけで統制することはできません。**

ローカルCoworkでは、プロキシ設定や一部の管理キーなど限定的な例外がありますが、企業全体の統制は次の組み合わせで行う必要があります。

> **組織設定 ＋ カスタムロール ＋ Claude DesktopのMDM／Group Policy ＋ モデル／コネクタ／プラグイン管理 ＋ OpenTelemetry**

また、公式にCowork対応が明記されていない `settings.json` の各設定キーについては、現時点では**不明**として扱うのが適切です。

[1]: https://claude.com/product/cowork "Claude Cowork | Claude by Anthropic"
[2]: https://support.claude.com/ja/articles/13345190-claude-cowork%E3%82%92%E5%A7%8B%E3%82%81%E3%82%8B "Claude Coworkを始める | Anthropicヘルプセンター"
[3]: https://docs.anthropic.com/en/docs/claude-code/settings "Claude Code settings - Claude Code Docs"
[4]: https://docs.anthropic.com/en/docs/claude-code/model-config "Model configuration - Claude Code Docs"
[5]: https://support.claude.com/en/articles/15694740-manage-model-access-for-your-organization "Manage model access for your organization | Claude Help Center"
[6]: https://code.claude.com/docs/en/network-config "Enterprise network configuration - Claude Code Docs"
[7]: https://claude.com/docs/cowork/overview "Overview - Claude.ai Documentation"
[8]: https://support.claude.com/en/articles/13455879-use-claude-cowork-on-team-and-enterprise-plans "Use Claude Cowork on Team and Enterprise plans | Claude Help Center"
[9]: https://support.claude.com/en/articles/13930452-manage-custom-roles-on-enterprise-plans "Manage custom roles on Enterprise plans | Claude Help Center"
[10]: https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop "Enterprise configuration for Claude Desktop | Claude Help Center"
[11]: https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview "Claude Cowork architecture overview | Claude Help Center"
[12]: https://support.claude.com/en/articles/14477985-monitor-claude-cowork-activity-with-opentelemetry "Monitor Claude Cowork activity with OpenTelemetry | Claude Help Center"
