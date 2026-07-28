## 結論

`https://chatgpt.com/codex/cloud/settings/policies` の設定は、ChatGPT Workに**限定的に適用されます**。ただし、**ChatGPT Work全体を一括して管理する設定画面ではありません**。

整理すると、次のようになります。

* **ChatGPT Workを誰が利用できるか**
  → ChatGPT Enterpriseの「Workspace settings → Permissions & roles → Work」で管理します。
* **デスクトップ版WorkがローカルPC上でどのように動作できるか**
  → CodexのManaged Configuration／Policies & Configurationsで、対応しているローカル実行機能を制限できます。
* **Web版・モバイル版Workのブラウザー利用、ネットワーク利用、接続アプリ、操作権限**
  → Work権限、Browser use、Network access、Apps、Pluginsなど、それぞれ別の管理設定を使用します。

OpenAIは、これらを「1つの統一されたChatGPT Workポリシー面ではない」と明記しています。([ChatGPT Learn][1])

---

# 1. ChatGPT Workとは

ChatGPT Workは、契約プラン名ではなく、**ChatGPTの中で利用する長時間・複数ステップの業務向けエージェント**です。

通常のChatが「質問への回答、検索、ブレインストーミング、短いやり取り」に向いているのに対し、Workは、ユーザーから最終的な目的を受け取り、情報収集、分析、計画、ツール操作、成果物作成までを継続して実行します。OpenAIは2026年7月9日にChatGPT Workを公開しました。([OpenAI Help Center][2])

具体的には、次のような作業を想定しています。

* 複数の資料や接続アプリから情報を集める
* 調査、比較、データ分析を行う
* ドキュメント、スプレッドシート、プレゼンテーション、レポート、Webサイトを作成する
* 作業途中でユーザーに質問する
* ユーザーが途中で方針を変更する
* 外部システムへの重要な操作について承認を求める
* 定期実行、トリガー実行、変更監視を行う

作業中は進捗を確認でき、ユーザーが割り込み、方向修正、追加指示、重要操作の承認を行えます。([OpenAI Help Center][3])

例えば、次のような依頼がWork向きです。

> Slack、Google Drive、会議メモからプロジェクトの進捗、課題、リスクを整理し、経営会議用の報告書とプレゼンテーションを作成してください。

この場合、単に質問に回答するだけではなく、複数の情報源を調べ、内容を整理し、成果物を作り、必要に応じてファイルや接続アプリに変更を加えるところまでがWorkの役割です。

---

# 2. Workを利用できる場所

現在の公式資料では、Workは次の環境で利用できます。

| 環境      | Workの動作                                   |
| ------- | ----------------------------------------- |
| Web版    | クラウド上で実行                                  |
| モバイル版   | クラウド上で実行                                  |
| デスクトップ版 | クラウド実行に加え、許可された場合はローカルファイルやデスクトップアプリも利用可能 |

クラウド版Workの会話は、Web、モバイル、デスクトップ間で同期されます。一方、ローカルチャットとして開始したものは、そのPC上に保持されます。([OpenAI Help Center][2])

対象となるChatGPT Enterpriseワークスペースでは、Workは原則として有効ですが、Workspace OwnerまたはAdminが無効化できます。Enterprise Key Managementが有効な対象ワークスペースでも利用可能です。実際に利用できるかは、ワークスペース設定とRBACによって決まります。([OpenAI Help Center][2])

---

# 3. ChatGPT WorkとCodexの違い

最も簡単に説明すると、次の違いです。

> **Workは、一般的な企業業務を完成させるエージェントです。**
> **Codexは、ソフトウェア開発を完成させるエージェントです。**

| 比較項目          | ChatGPT Work                          | Codex                                                 |
| ------------- | ------------------------------------- | ----------------------------------------------------- |
| 主な目的          | 調査、分析、資料作成、業務遂行                       | ソフトウェア開発、技術作業                                         |
| 主な成果物         | Word相当の文書、スプレッドシート、プレゼン、レポート、分析、Site  | ソースコード、テスト、修正差分、レビュー結果、PR関連作業                         |
| 主な情報源         | Chat、Projects、アップロードファイル、社内リソース、接続アプリ | リポジトリ、ローカルフォルダー、ターミナル、開発ツール、クラウド開発環境                  |
| 主な操作          | 情報収集、文書作成、表計算、外部アプリ操作                 | コード編集、コマンド実行、テスト、デバッグ、コードレビュー                         |
| ChatGPT上の位置づけ | ChatGPT内のChatと並ぶ業務モード                 | デスクトップアプリではChatGPTとは別の専用ビュー                           |
| Web・モバイル      | Workとして利用可能                           | ChatGPTの通常画面ではCodexモードとして選択不可。専用のCodexサーフェスやRemoteを利用 |
| 履歴            | Chatの履歴と一緒にRecentsに表示                 | ChatGPTの履歴とは別に管理                                      |

OpenAI自身も、Workを「長めの複数ステップの作業や完成した成果物向け」、Codexを「ソフトウェア開発と技術的な作業向け」と説明しています。([OpenAI Help Center][2])

## 共通点

WorkとCodexは完全に無関係な製品ではありません。OpenAIは、Workについて「Codexの背後にある技術をChatGPTへ持ち込んだもの」と説明しています。([ChatGPT Learn][1])

また、次の点を共有しています。

* エージェント型の複数ステップ実行
* ツールやプラグインの利用
* 途中での承認、方向修正
* WorkとCodexで共有される利用量・クレジット体系
* 一部のデスクトップ実行基盤とManaged Configuration

WorkとCodexは、料金、クレジット、利用上限を共有します。通常のChat利用量とは別のエージェント型利用量として扱われます。([OpenAI Help Center][2])

## 使い分けの例

**Workに依頼する例**

> 営業会議の資料、CRMデータ、顧客メールを分析し、失注理由をまとめたレポートと役員向けスライドを作成してください。

**Codexに依頼する例**

> このリポジトリの認証処理の不具合を特定し、修正を実装し、テストを追加して、変更差分をレビューしてください。

---

# 4. `Policies & Configurations`はWorkを制御するのか

## 判定：一部は制御対象です

OpenAIのManaged Configurationは、次のローカルクライアントの「対応しているローカル実行動作」を管理する仕組みです。

* ChatGPTデスクトップアプリ
* Codex CLI
* Codex IDE拡張機能

このManaged Configurationでは、管理者がユーザー側で上書きできないRequirementsを配布できます。例として、承認ポリシー、サンドボックス、ファイルシステム、ネットワーク、MCP、コマンドルール、フック、機能フラグなどを制約できます。([ChatGPT Learn][4])

そのため、**ChatGPTデスクトップアプリ内のWorkが、ローカルファイル、ブラウザー、Computer Use、プラグインなどの対応機能を使う場合、そのローカル実行部分はManaged Configurationの制約を受けます**。

OpenAIの資料では、プラグインのマーケットプレイスソース制限について、明示的に「デスクトップアプリのChatGPT WorkとCodex、およびCodex CLI」に適用されると記載されています。([ChatGPT Learn][4])

## ただし、Work全体を管理する設定ではありません

OpenAIは、Workのガバナンスを次の異なるレイヤーに分けています。

1. ChatGPT Workのアクセス制御
2. Workspace Agentの制御
3. Codex Managed Configurationによるローカルランタイム制御

そして、これらは「1つの統一されたChatGPT Workポリシー面ではない」と説明しています。Managed Configurationはランタイム動作を制約するもので、Workへのアクセス権を付与したり、RBACを置き換えたり、ユーザーのワークスペースアクセスを取り消したりするものではありません。([ChatGPT Learn][1])

---

# 5. 管理対象ごとの正しい設定場所

| 管理したい内容                                   | 主な設定場所                                          | `codex/cloud/settings/policies`の対象か     |
| ----------------------------------------- | ----------------------------------------------- | --------------------------------------- |
| Workを利用できるユーザー・グループ                       | Workspace settings → Permissions & roles → Work | **対象外**。Work権限で管理                       |
| WorkのWeb・モバイル・デスクトップ利用可否                  | Workアクセス権                                       | **対象外**                                 |
| Codex Localの利用可否                          | Permissions & roles → Codex Local               | **別権限**。WorkのON/OFFとは独立                 |
| デスクトップ版Workのローカル実行制約                      | Managed Configuration／Requirements              | **対応機能について対象**                          |
| ファイルシステム、ネットワーク、承認、サンドボックス                | Managed Configuration／Requirements              | **対応機能について対象**                          |
| WorkのWeb・モバイルでのBrowser use／Network access | Work向けのBrowser use・Network access設定             | **原則として対象外**                            |
| Google Drive、Slackなどの接続アプリ                | Workspace settings → Apps                       | **対象外**                                 |
| 接続アプリの読み取り・書き込み・承認                        | AppsのAction controls／App permissions            | **対象外**                                 |
| プラグインの利用・インストール                           | Workspace settings → Plugins                    | 主設定は別。ローカルの一部制限はManaged Configuration対象 |
| WorkとCodexの開始モデル・推論レベル                    | Workspace settings → Models                     | **対象外**                                 |
| WorkとCodexの利用上限・クレジット                     | Usage limits／Global Admin Console               | **対象外**                                 |

Workのアクセスについて、現在の公式Help Centerでは、1つのWorkアクセス設定がWeb、モバイル、デスクトップアプリに適用されると説明されています。また、Codex Localは別制御であり、Workの有効化・無効化によってCodex Localの設定は変わりません。([OpenAI Help Center][2])

---

# 6. Enterprise導入時に設定すべき項目

## ① Workのアクセス権

最初に、次の画面でWorkを許可するロールまたはグループを決めます。

> Workspace settings → Permissions & roles → Work

全社一斉ではなく、部門やパイロットグループ単位で有効化できます。Workの利用権限とCodex Localの利用権限は別々に確認する必要があります。([OpenAI Help Center][2])

## ② デスクトップ版のローカル実行ポリシー

デスクトップ版Workにローカルファイルやアプリを扱わせる場合は、Managed Configurationを設計します。

検討対象には、例えば次があります。

* 許可するPermission Profile
* ファイルの読み取り・書き込み範囲
* ネットワークアクセス
* コマンド実行時の承認
* Computer Use
* Browser Use
* Appshots
* Remote Control
* MCPサーバー
* プラグインソース
* コマンドルール
* フック

ただし、OpenAIは、対応するRequirementsがクライアントやバージョンによって異なると説明しており、小規模グループでのテストを推奨しています。([ChatGPT Learn][4])

## ③ Apps／Pluginsの設定

WorkがGoogle Drive、Slack、SharePoint、各種業務システムを利用する場合、Managed Configurationだけでは管理できません。

次の設定を別途確認します。

* アプリ自体を利用可能にするか
* 利用できるロール
* 読み取りのみか、書き込みも許可するか
* どの操作でユーザー承認を要求するか
* 新しいアクションを自動許可するか
* 接続先システムのユーザー権限
* 共有接続やサービスアカウントのスコープ

Workは、接続先システムの権限を迂回しません。ユーザーまたは承認された共有接続がアクセスできるファイル、チャンネル、レコード、操作だけを利用します。([ChatGPT Learn][1])

## ④ 利用量とコスト

WorkとCodexは同じクレジット・利用上限の枠を共有します。

特に次の処理は利用量が増えやすいと説明されています。

* 大量ファイルの処理
* 複数の接続アプリの呼び出し
* 定期実行やトリガー実行
* 広範囲な社内検索
* 長時間のエージェント処理
* 大きな成果物の生成
* エラー時の再試行

Enterpriseでは、ワークスペース、グループ、個人単位の利用上限やオーバーライドを設定できます。([ChatGPT Learn][1])

## ⑤ 監査ログの範囲

導入時に特に注意すべき点です。

OpenAIの現在の説明では、Compliance APIはChat、Work、Codexのユーザーメッセージと応答を対象とします。一方、Compliance Logs Platformは、**ファイル、実行アクション、ツール呼び出しまでは記録しません**。([ChatGPT Learn][1])

したがって、次のような説明は避けるべきです。

> 「Workが実行したすべての外部操作をCompliance APIで完全に監査できる」

現時点の公式資料では、この説明は正しくありません。外部システム側の監査ログ、アプリ側ログ、ChatGPTのCompliance APIを組み合わせて設計する必要があります。

---

# 7. 今回確認できなかった点

## URLが現在のManaged Configuration画面と完全に同一か

OpenAIの現行公開ドキュメントは、Managed Configurationの管理画面として、現在は別のパスである`/codex/settings/managed-configs`へのリンクを掲載しています。一方、OpenAIのリリースノートでは、Codex cloud settingsの「Policies & Configurations」という名称も引き続き使われています。([ChatGPT Learn][4])

ご提示の

```text
https://chatgpt.com/codex/cloud/settings/policies
```

と、現在の公開ドキュメントが案内するManaged Configuration画面が、内部的に同一画面なのか、旧URLからのエイリアスなのか、別画面なのかについては、**公開情報だけでは断定できません**。未認証状態ではChatGPTのトップ画面へリダイレクトされるため、Enterprise管理者向け画面の実体を確認できないためです。

ただし、機能の適用範囲については公式資料から確認できており、次の結論は変わりません。

> **CodexのPolicies & Configurations／Managed Configurationは、デスクトップ版ChatGPT Workの対応するローカルランタイム機能に適用される。**
> **しかし、Workの利用可否やWeb・モバイル、Apps、RBAC、モデル、利用量を一括制御するものではない。**

## 個々の設定キーがWorkに適用されるか

すべての設定キーについて、「Workにも適用」「Codexだけに適用」という完全な一覧は、現在の公式資料では確認できません。

OpenAI自身が、次の点を明記しています。

* 対応する設定はクライアントによって異なる
* クライアントバージョンによって異なる
* 選択したキーを各クライアントがサポートしているか確認する必要がある
* 全社適用前に小規模グループでテストする

したがって、`browser_use`、`computer_use`、`plugins`、Permission Profileなど、実際に採用する各キーについては、利用予定のChatGPTデスクトップアプリのバージョンで動作確認する必要があります。([ChatGPT Learn][4])

---

## 最終整理

社内説明用には、次の表現が最も正確です。

> ChatGPT Workは、調査、分析、資料作成、接続アプリ操作などの一般的な業務を、複数ステップで最後まで進めるエージェントです。
> Codexは同じエージェント技術を基盤としながら、コード、リポジトリ、ターミナル、テストなどのソフトウェア開発に特化しています。
> Workの利用可否はChatGPT EnterpriseのWork権限とRBACで管理します。CodexのPolicies & Configurationsは、デスクトップ版Workの対応するローカル実行機能には適用されますが、Work全体を一括管理する設定ではありません。Web・モバイル、接続アプリ、モデル、利用量などは、それぞれ別の管理設定が必要です。

[1]: https://learn.chatgpt.com/codex/enterprise/work-admin-faq "ChatGPT Work admin FAQ | ChatGPT Learn"
[2]: https://help.openai.com/en/articles/20001275-chatgpt-work-and-codex "ChatGPT Work and Codex | OpenAI Help Center"
[3]: https://help.openai.com/en/articles/6825453-chatgpt-release-notes "ChatGPT — Release Notes | OpenAI Help Center"
[4]: https://learn.chatgpt.com/codex/enterprise/managed-configuration "Managed configuration | ChatGPT Learn"
