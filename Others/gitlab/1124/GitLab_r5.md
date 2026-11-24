GitLab 機能要件定義書

AI エージェント基盤・市民開発環境向け

| 文書の位置づけ | PowerPoint「GitLabCE\_論点整理」スライド 12 の機能一覧を起点に、AI エージェントのプロ開発と市民開発で必要となる機能要件へ具体化したもの。構築方式、非機能要件、運用設計の詳細は別文書で定義する。 |
| :---: | :---: |

 

| 文書版数 | 1.0.12（表内配置統一版） |
| ----- | :---- |
| **作成日** | 2026 年 10 月 19 日 |
| **対象製品** | GitLab Self-Managed / Free を採用（~~GitLab CE、または~~ GitLab EE を有償ライセンス未適用の Free 状態で利用） |
| **主対象** | AI エージェント基盤、市民開発環境 |
| **参照資料** | GitLabCE\_論点整理.pptx（スライド 12・13）、AWS 環境構築検討.xlsx、GitLab 公式ドキュメント |

# **1\. 文書目的**

本書は、社内 GitLab 導入における機能要件を定義する。主用途は、外部ベンダー等による AI エージェントのプロ開発と、社内利用者による市民開発であり、ソースコード、設定ファイル、プロンプト、エージェント定義、IaC、レビュー記録および作業管理情報を一元的に管理する。

## **1.1 背景**

·         AI エージェント実行環境は AWS 上での構築を想定し、GitLab は Azure 側に構築する方針とする。  
·         GitLab は AI エージェント基盤だけに閉じず、市民開発環境を含む複数の開発用途で共用する。  
·         ~~初期スコープ~~本書で機能要件を定義する主な機能群はソース管理、レビュー、作業管理、文書・リリース、アクセス制御、API・自動化とする。このうち初期リリースで提供する範囲は 1.4 に示す。CI/CD 等の追加構築を要する機能は 14 章に示す。

## **1.2 要件の表記**

| 区分 | 意味 |
| :---: | ----- |
| 初期実装 | 初期導入時に実現する要件 |
| 条件付き実装 | 対象ユースケースまたは連携を採用する場合に実現する要件 |
| ~~将来~~後日拡張 | 初期対象外だが拡張時に再評価する要件 |
| 対象外 | 本書の初期スコープに含めない要件 |

 

## **1.3 前提・制約**

·         Public Project および利用者の自己登録は許可しない。  
·         インターネットへの直接公開は行わず、社内ネットワークから内部 DNS および TLS で利用する。  
·         Runner、Container Registry、Package Registry、Git LFS、Pages、Object Storage は初期実装とはせず、利用要件および追加構築条件の確定後に追加する。  
·         有償ライセンス専用機能は本書の要件に含めない。無償版で実現できない高度な承認、監査、SCIM、SAML Group Sync 等は対象外または代替運用とする。  
·         AI エージェントおよび自動化処理から GitLab API へアクセスする場合は、GitLab OAuth による短寿命 Access Token を採用し、長期固定の Access Token を実行環境へ保存しない。

## **1.4 初期リリース範囲（短納期構築）**

初期リリースでは、Repository と IAM を中核とし、安全に利用開始するために直接必要となる機能だけを提供する。Issue、Board、Release、API（承認済みの自動連携による利用を除く）、Webhook、Runner、Registry 等は後日拡張とする。README および Project Wiki は初期実装に含める。

·         **初期実装：Private Project／会社管理 Group、Clone・Pull・Push、Branch・Tag、既定 Branch 保護、Merge Request（Draft・Squash を含む）、最小権限 Role、自己登録禁止、Entra ID SAML SSO、Project または最下位 Subgroup 単位の権限付与、README、Project Wiki、Web IDE（軽微な修正に限定）、AI エージェント等の自動連携（GitLab OAuth による API 利用）**  
·         条件付き実装：~~自動連携を初期導入する場合の GitLab OAuth。~~SSH を採用する場合の SSH Key 管理。外部委託者を初期受入れする場合の期限付きアクセス  
·         **運用上のリリース前提：**内部 DNS・TLS、緊急管理者、バックアップ取得と復元確認、ログ・容量・死活の最低限監視、パッチ適用方法。これらは非機能・運用設計で定義する  
·         後日拡張：Issue／Board／Milestone、Release／Snippet、REST／GraphQL API（承認済みの自動連携による REST API 利用を除く）、Webhook、CI/CD・Runner、Container／Package Registry、Git LFS、Pages、Object Storage  
·         後日拡張機能の初期の扱い：GitLab の既定で利用可能となる機能（Issue、Snippet、Release、Webhook、REST API、Git LFS、Package Registry 等）は、初期リリースでは設定で無効化する。設定で無効化できない機能は利用ルールで禁止する（承認済みの自動連携による API 利用を除く）

初期リリースで Merge Requestと既定 Branch保護を含める理由は、Repositoryを提供しながらmain への直接 Push・Force Push・誤削除を抑止するためである。高度な複数承認は無償版前提のため要求しない。

# **2\. 利用者・ユースケース**

| 利用者区分 | 主な利用内容 | 標準ロール案 |
| :---: | ----- | :---: |
| AI エージェント開発者 | エージェントコード、プロンプト、ツール定義、IaC の登録・変更・レビュー依頼 | Developer |
| 開発リーダー／レビュー担当 | Merge Request レビュー、マージ、ブランチ・リリース管理 | Maintainer |
| 市民開発者 | テンプレートからの成果物管理、Issue 起票、レビュー依頼、文書更新 | Developer ~~または Planner~~（Issue 起票・Wiki 更新のみの利用者は Planner） |
| 閲覧者／運用担当 | 成果物参照、Issue 確認、リリース情報確認 | Reporter |
| GitLab 管理者 | ユーザー、認証、グループ、全体設定、バックアップ等の管理 | Administrator |
| GitLab 運用管理者 | Project の作成・初期設定、メンバー・権限の付与、棚卸、廃止処理 | 担当 Group の Owner |

 

| 設計上の注意 | 市民開発者へ一律に Maintainer を付与しない。プロジェクト設定変更やメンバー管理が不要な利用者は Developer 以下とし、権限の過大付与を避ける。 |
| :---: | :---: |

 

# **3\. 機能要件一覧**

本章は機能要件の索引である。構成方針は 4 章、機能群ごとの詳細は 5～10 章、用途固有要件は 11～12 章、利用・運用フローは 13 章、追加構築機能は 14 章、受入条件は 15 章、未決事項は 16 章に示す。

要件 ID は後続の基本設計・受入試験でトレーサビリティを確保するため固定する。

| ID | 機能群 | 対象機能 | ~~優先度~~区分 | 機能要件 | 詳細章 |
| :---: | :---: | :---: | :---: | ----- | :---: |
| SCM-01 | ソースコード管理 | Repository | 初期実装 | プロジェクト単位で Git リポジトリを作成し、AI エージェント、市民開発成果物および関連文書を保管できること。 | 4・5 章 |
| SCM-02 | ソースコード管理 | Branch / Tag | 初期実装 | 開発、レビュー、リリースを分離するブランチおよび版を識別するタグを管理できること。 | 4・5 章 |
| SCM-03 | ソースコード管理 | Clone / Pull / Push | 初期実装 | HTTPS または SSH により、許可された利用者・システムが取得および更新できること。 | 4・5 章 |
| SCM-04 | ソースコード管理 | Web IDE | **~~後日拡張~~**初期実装 | ブラウザから軽微な編集を行えること。市民開発での利用可否は対象ファイルと権限を限定して決定すること。 | 4・5 章 |
| REV-01 | コードレビュー | Merge Request / Diff / Comment | 初期実装 | 変更差分を提示し、コメントおよびディスカッションを記録した上でマージできること。 | 6 章 |
| REV-02 | コードレビュー | Draft | **~~後日拡張~~**初期実装 | レビュー準備中の変更を Draft として明示できること。 | 6 章 |
| REV-03 | コードレビュー | Squash | **~~後日拡張~~**初期実装 | マージ時にコミットを整理できること。適用方針をプロジェクトごとに定義できること。 | 6 章 |
| REV-04 | コードレビュー | Protected Branch / Tag | 初期実装 | main 等への直接更新、強制 Push、削除、マージ可能者を制御できること。 | 6 章 |
| WRK-01 | 作業管理 | Issue | **後日拡張** | 機能追加、障害、問い合わせ、審査事項、改善事項を Issue として管理できること。 | 7 章 |
| WRK-02 | 作業管理 | Board / Label | **後日拡張** | Issue をラベルとボードで分類し、未着手・対応中・レビュー中・完了等の状態を可視化できること。 | 7 章 |
| WRK-03 | 作業管理 | Milestone / 担当 / 期限 | **後日拡張** | リリースまたは開発期間ごとに作業をグルーピングし、担当者と期限を設定できること。 | 7 章 |
| DOC-01 | 文書・リリース | README / Project Wiki | 初期実装 | Project ごとに README および Project Wiki を利用できること。README には Project の目的、所有者、対象環境、基本的な利用方法および問い合わせ先を記載し、Wiki には開発標準、接続仕様、プロンプト設計、運用手順、FAQ 等の詳細情報を Markdown 中心で管理できること。正式承認文書の原本は既存文書管理基盤で管理し、GitLab には参照先を記載すること。 | 8 章 |
| DOC-02 | 文書・リリース | Snippet | **後日拡張** | 再利用可能な小規模コード、コマンド例、設定例を権限管理下で共有できること。機密情報は登録しないこと。 | 8 章 |
| DOC-03 | 文書・リリース | Release | **後日拡張** | リリース名、タグ、説明、関連成果物を関連付けて公開できること。 | 8 章 |
| IAM-01 | アクセス制御 | Role | 初期実装 | グループ／プロジェクト単位で最小権限のロールを付与できること。 | 9 章 |
| IAM-02 | アクセス制御 | SSO / 認証方針 | 初期実装 | 一般利用者および GitLab 管理者は Microsoft Entra ID による SSO を必須とする。MFA は GitLab 固有要件とせず、Entra ID 側の全社認証ポリシーに従う。ローカル緊急管理者は通常利用せず、別途資格情報の保管・利用手順を定める。ローカル緊急管理者は Entra ID の MFA を経由しないため、GitLab の 2FA を必須とする。 | 9 章 |
| IAM-03 | アクセス制御 | Token | 初期実装 | AI エージェントおよび自動化処理から GitLab API へアクセスするため、GitLab OAuth による短寿命 Access Token を必須とする。長期固定の Access Token を実行環境へ保存せず、OAuth Application、Scope、Token の取得・更新・失効および認証情報の保管方法を管理すること。 | 9 章 |
| IAM-04 | アクセス制御 | 自己登録・公開制御 | 初期実装 | 自己登録を禁止し、プロジェクト可視性を Private または承認済み Internal に限定できること。 | 9 章 |
| API-01 | API・自動化 | REST API | **~~後日拡張~~**初期実装（承認済みの自動連携に限定） | プロジェクト、Issue、Merge Request 等を外部システムから操作・参照できること（Issue は導入後）。 | 10 章 |
| API-02 | API・自動化 | GraphQL API | **後日拡張** | 必要なデータを選択して参照する連携で利用できること。 | 10 章 |
| API-03 | API・自動化 | Webhook | **後日拡張** | Push、Issue、Merge Request 等のイベントを、許可された社内送信先へ通知できること。 | 10 章 |
| **CICD-01** | CI/CD | Pipeline | 後日拡張 | Repository の変更を契機に、承認済みの検査、ビルド、試験およびデプロイ処理を Pipeline として実行できること。 | 14 章 |
| **CICD-02** | CI/CD | Runner | ~~条件付き実装~~後日拡張 | CI/CD を利用する場合、Runner を GitLab 本体と分離して配置し、Executor、同時実行数、到達先、実行権限および Artifact 保持を管理できること。 | 14 章 |
| **REG-01** | 成果物管理 | Container Registry | 後日拡張 | 承認されたコンテナイメージを Project 単位で保管し、FQDN、TLS、容量、保持・削除およびアクセス権を管理できること。 | 14 章 |
| **REG-02** | 成果物管理 | Package Registry | 後日拡張 | 承認された Package を Project 単位で保管し、形式、容量、保持・削除およびアクセス権を管理できること。 | 14 章 |
| **LFS-01** | 大容量ファイル | Git LFS | 後日拡張 | Git での直接管理に適さない承認済み大容量ファイルを Git LFS で管理し、対象拡張子、容量、バックアップおよび取得性能を管理できること。 | 14 章 |
| **PAGE-01** | 静的コンテンツ | GitLab Pages | 後日拡張 | 承認された内部向け静的コンテンツを公開でき、公開範囲、内部 DNS、TLS、Runner およびコンテンツ審査を管理できること。 | 14 章 |
| **STO-01** | 外部ストレージ | Object Storage | 後日拡張 | 容量増加時に、GitLab が保存する対象データを組織内 Object Storage へ格納でき、接続、認証、暗号化、保持、バックアップおよび復元を管理できること。 | 14 章 |

 

# **4\. GitLab 利用構成**

## **4.1 管理境界**

管理境界は、複数の組織・業務で共用する「全社共通領域」と、特定の部門・業務が所有する「組織・業務所有領域」に分ける。基盤 IaC は全社共通領域の共通基盤直下に配置し、個別成果物とは分離する。

| 会社管理 Top Group |  |  |  |
| ----- | ----- | :---: | :---: |
| ↓ | ↓ | ↓ | ↓ |
| **全社共通領域** |  | **組織・業務所有領域** |  |
| ↓ | ↓ | ↓ | ↓ |
| **共通基盤** | **共通資材** | **部門・業務領域 Subgroup** |  |
| ↓ | ↓ | ↓ | ↓ |
|   |   | **個別 Project** | **個別 Project** |
| 基盤 IaC GitLab 基盤 AI エージェント基盤 市民開発基盤 | 共通部品 標準資材 | AI エージェント 市民開発アプリ | 業務フロー その他の個別成果物 |

図 4-1 管理境界の考え方

組織・業務所有領域では、部門・業務領域 Subgroup の配下に個別 Project を作成し、AI エージェント、市民開発アプリ、業務フロー等を配置する。共通部品は複数 Project が実装の一部として利用する資材、標準資材は開発ルールや雛形として参照する資材とする。

## **4.2 Namespace／Group／Project 構成**

4.1 の管理境界を GitLab の Group／Subgroup／Project へ配置した想定構成を次に示す。共通基盤、共通部品、標準資材を全社共通領域へ集約し、個別成果物は所有する部門・業務領域の配下へ配置する。

| company-development　会社管理 Top Group |  |  |  |  |  |
| ----- | ----- | :---: | :---: | ----- | ----- |
| ↓ | ↓ | ↓ | ↓ | ↓ | ↓ |
| **common　全社共通領域** |  |  |  | **organization　組織・業務所有領域** |  |
| ↓ | ↓ | ↓ | ↓ | ↓ | ↓ |
| **platforms　共通基盤** |  | **shared-resources　共通資材** |  | **＜部門・業務領域＞ Subgroup** |  |
| ↓ | ↓ | ↓ | ↓ | ↓ | ↓ |
| **platform-iac 基盤 IaC** | gitlab-platform ai-agent-platform citizen-dev-platform | **shared-components 共通部品** | **standards 標準資材** | AI エージェント Project | 市民開発アプリ／業務フロー Project |
|   |   | **実装物として利用** | **規約・雛形として参照** |   |   |
| **基盤 IaC は共通基盤直下。個別成果物固有の deploy/ のみ各 Project の Repository に配置する。** |  |  |  |  |  |

図 4-2 Namespace／Group／Project 構成

platform-iac は共通基盤を構成・変更する IaC の格納先とし、AI エージェント基盤の配下には置かない。

## **4.3 Project／Repository 構造と管理対象**

組織・業務所有領域の個別成果物は、1 つの GitLab Project を管理単位とする。Project 内の Repository には、当該成果物のコード、プロンプト、設定、試験、文書、および当該成果物固有のデプロイ定義を配置する。共通基盤の IaC や Terraform 共通 Module は配置しない。

| GitLab Project（個別成果物の管理単位） |  |  |  |
| :---: | :---: | ----- | ----- |
| **Repository（コード・設定・文書を版管理）** |  | → | **Project Wiki 補足文書・FAQ・運用手順** |
| **README.md** | Project の入口 |   |   |
| **src/** | 実装コード |   |   |
| **prompts/** | プロンプト | → | **Issue／Merge Request 作業・差分・レビュー記録** |
| **tools/** | Tool 定義 |   |   |
| **config/** | 設定雛形 |   |   |
| **tests/・evaluation/** | 試験・評価 | → | **Tag／Release 反映対象の版を識別** |
| **deploy/** | 個別成果物固有のデプロイ定義 |   |   |
| **docs/** | 設計・仕様 |   |   |

図 4-3 個別成果物 Project／Repository の管理構造

基盤 IaC は全社共通領域の platform-iac、Terraform 共通 Module は共通部品、個別成果物固有の deploy/は当該 Project で管理する。

# **5\. ソースコード管理要件**

## **5.1 管理対象**

·         AIエージェント: アプリケーションコード、プロンプト、ツール定義、評価コード、設定テンプレート、当該エージェント固有のデプロイ定義。  
·         市民開発: Power Platform 等のエクスポート可能なソース、設定、手順書、テンプレート、レビュー記録。  
·         共通基盤: 基盤 IaC、CI/CD 定義、共通設定、README、変更履歴。Terraform 共通 Module は共通部品として分離する。ただし秘密情報、実データ、個人情報をリポジトリへ直接格納しない。

## **5.2 リポジトリ・グループ構成**

| 要件 ID | 要件 |
| :---: | ----- |
| SCM-05 | 会社管理トップレベル Group 配下を、用途、共通資材、基盤資材、プロジェクトの管理境界で分割できること。組織図をそのまま Group 階層に固定しないこと。 |
| SCM-06 | ~~AI エージェント基盤、市民開発、全社標準を用途別 Subgroup として分離し~~全社共通領域（共通基盤、共通資材）と組織・業務所有領域を Subgroup として分離し、組織・業務所有領域は部門・業務領域 Subgroup ごとに分け、プロジェクトごとにアクセス境界となる Subgroup または Project を設けること。 |
| SCM-07 | Personal Namespace への業務 Project 作成を禁止し、Project 作成権限を~~管理者または承認された運用担当~~GitLab 管理者または GitLab 運用管理者に限定できること。 |
| SCM-08 | 命名規則、README、Issue／Merge Request テンプレートを標準化できること。 |
| SCM-09 | 大容量バイナリの登録を原則禁止し、必要時のみ Git LFS を別途設計すること。 |

 

## **5.3 ブランチ・タグ**

·         既定ブランチは保護し、Developer の直接 Push を禁止して Merge Request 経由とする。  
·         強制 Push は原則禁止する。例外は管理者承認と記録を必要とする。  
·         リリースタグの作成・削除権限を限定し、ブランチ名と同名のタグによる制御抜けを防ぐ。

## **5.4 標準設定方針**

| 機能 | 本環境での標準設定 | 禁止・統制 |
| :---: | ----- | ----- |
| Repository | Private Project。会社 Group 配下。既定 Branch は main。Project 作成は申請制。 | 個人 Namespace、秘密情報、実データ、大容量バイナリの直接 Commit を禁止。 |
| Branch / Tag | main は Developer 直接 Push・Force Push 禁止。作業 Branch は feature/\<Issue\>-\<要約\>、fix/\<Issue\>-\<要約\>（Issue 導入前は \<Issue\> を申請番号で代替）。Release Tag は vX.Y.Z を基本とする。 | main 変更は MR 経由。Tag 作成・削除は Maintainer。Branch と Tag で同名を使う場合は双方を保護。 |
| Clone / Push | 社内 DNS・TLS 経由。HTTPS を標準候補とし、SSH 採用時は鍵種別・失効を設計。 | 外部ネットワークからの直接接続と共有 ID での Push を禁止。 |
| Web IDE | Markdown・設定の軽微な修正に限定し、作業 Branch へ保存。 | main への直接 Commit、秘密値編集、大量ファイル投入には使用しない。 |

 

# **6\. コードレビュー要件**

| 要件 ID | 要件 | 受入観点 |
| :---: | ----- | ----- |
| REV-05 | Merge Request に変更目的、影響範囲、試験結果、ロールバック方法を記載できること。 | テンプレートを適用し、必須項目が表示される。 |
| REV-06 | 変更差分に対する行単位コメントとスレッドを保持できること。 | 未解決コメントと解決済みコメントを確認できる。 |
| REV-07 | AI が生成したコード・プロンプトも人によるレビュー対象として扱えること。 | AI 生成物を通常の MR フローでレビューできる。 |
| REV-08 | 無償版で利用できる保護ブランチ、Merge Request、コメント等を前提にレビュー統制を設計すること。有償版専用の承認機能を前提にしないこと。 | 無償版で実装・受入可能な統制であることを確認する。 |

 

| 重要 | 無償版では、Merge Request、コメント、保護ブランチ等を組み合わせてレビューを運用する。複数承認など有償版専用機能を必須要件にせず、必要なレビュー証跡はテンプレートと運用で補完する。 |
| :---: | :---: |

 

## **6.1 標準設定方針**

| 機能 | 本環境での標準設定 | 禁止・統制 |
| :---: | ----- | ----- |
| Merge Request | 目的、Issue（導入前は申請番号）、影響、試験、データ／権限影響、切戻しをテンプレート必須項目とする。 | 作成者とマージ担当を原則分離。未解決コメントや試験未完了ではマージしない。 |
| Draft / Squash | 作業中は Draft。main への反映は原則 Squash merge として Issue／MR 単位に履歴を整理。 | 評価結果・切戻し未記載の MR をマージしない。 |

 

# **7\. 作業管理要件**

本章の要件は、Issue、Board、Milestone 等の作業管理機能を導入する時点（後日拡張）で適用する。

| 要件 ID | 要件 |
| :---: | ----- |
| WRK-04 | AI エージェント開発では、要件、プロンプト変更、モデル／ツール変更、評価不備、障害を追跡できる Issue 分類を定義すること。 |
| WRK-05 | 市民開発では、申請、開発、レビュー、公開、改修、廃止を追跡できるラベルまたはボード列を定義すること。 |
| WRK-06 | Issue テンプレートに目的、利用データ、接続先、権限、リスク、受入条件を含められること。 |
| WRK-07 | Issue と Merge Request を関連付け、変更理由から実装・レビュー結果まで追跡できること。 |
| WRK-08 | 無償版で利用できる Issue、Label、Milestone、Board の範囲で作業管理を設計すること。 |

 

## **7.1 標準設定方針**

| 機能 | 本環境での標準設定 | 禁止・統制 |
| :---: | ----- | ----- |
| Issue / Board | AI 用と市民開発用で Label 体系を分離。列は Backlog、Ready、In Progress、Review、Done を標準とする。 | メールや Excel だけで変更要求を管理せず、実装は Issue 起点とする。 |

 

# **8\. 文書・リリース要件**

·         README はプロジェクトの目的、所有者、対象環境、構築・利用方法、問い合わせ先を記載する。  
·         Wiki は共通手順、設計判断、FAQ、利用ルールの管理に用いる。正式な承認済み設計書の~~原本管理先は別途定義する。~~原本は既存文書管理基盤で管理し、GitLab には参照先を記載する。  
·         Release はタグと対応付け、変更内容、既知の制約、移行・切戻し情報を記録する。  
·         Snippet へ資格情報、秘密鍵、接続文字列、個人情報を保存しない。

## **8.1 標準設定方針**

| 機能 | 本環境での標準設定 | 禁止・統制 |
| :---: | ----- | ----- |
| README / Project Wiki | README に目的、所有者、対象環境、基本的な利用方法および問い合わせ先を記載する。Wiki には開発標準、接続仕様、プロンプト設計、運用手順、FAQ 等の詳細情報を記載する。 | 正式承認文書の原本は既存文書管理基盤で管理し、GitLab には参照先を記載する。秘密情報、個人情報および実データを記載しない。 |
| Release | 本番／配布対象を Tag＋Release で固定し、変更、既知制約、移行、切戻し、Commit を記録。 | Branch 名だけで本番版を識別しない。 |

 

# **9\. アクセス制御・認証要件**

認証方針は、一般利用者および GitLab 管理者ともに Microsoft Entra ID SSO を必須とする。MFA は GitLab 固有要件にせず、Entra ID 側の全社認証ポリシーに従う。ローカル緊急管理者は通常利用から分離する。ローカル緊急管理者は Entra ID の MFA を経由しないため、GitLab の 2FA を必須とする。

| 要件 ID | 要件 | 設計判断 |
| :---: | ----- | ----- |
| IAM-05 | 利用者認証は Microsoft Entra ID との SAML SSO を必須とし、自己登録を禁止する。初回 SAML ログイン時の JIT プロビジョニングを基本候補とする。 | SAML の NameID・メール属性、JIT プロビジョニング、既存アカウント連携、緊急管理者を基本設計で確定する。 |
| IAM-06 | 最小権限を原則とし、Guest／Planner／Reporter／Developer／Maintainer／Owner を用途別に割り当てる。 | 市民開発者へ過大な設定権限を付与しない。 |
| IAM-07 | 一般利用者および GitLab 管理者は Entra ID SSO を必須とする。MFA は GitLab 固有要件とせず、Entra ID 側の全社認証ポリシーに従う。ローカル緊急管理者は通常利用せず、資格情報の保管・利用手順を別途定める。ローカル緊急管理者は Entra ID の MFA を経由しないため、GitLab の 2FA を必須とする。 | GitLab 側 2FA は一律要求しない（ローカル緊急管理者を除く）。管理者を含む通常利用者の認証は Entra ID SSO へ統一し、ローカル緊急管理者だけ別管理する。 |
| IAM-08 | GitLab API を利用する AI エージェントおよび自動化処理は、GitLab OAuth による短寿命 Access Token を使用し、OAuth Application、Scope、Token の取得・更新・失効および認証情報の保管方法を定義する。OAuth を認可する GitLab ユーザーは、エージェント専用アカウント（推奨）と開発者本人のどちらにも対応する。 | Entra ID SSO は GitLab への Web ログインに使用する。GitLab API には、GitLab が発行する OAuth Access Token を使用する。エージェントは認可したユーザーの代理として、そのユーザーの権限で動作する。専用アカウントの場合は対象 Project のメンバーに限定し、開発者本人の場合は本人の権限の範囲で動作することを前提とする。 |
| IAM-09 | AI エージェント等のシステム連携では、長期固定の PAT および Project／Group Access Token を実行環境へ保存せず、GitLab OAuth による短寿命 Access Token を採用する。 | OAuth Access Token の Scope は必要最小限とする。Client Secret および Refresh Token を使用する場合は、認証情報管理基盤へ分離して保管し、実行環境へ平文で永続保存しない。 |
| IAM-10 | 退職・異動・委託終了時に、Entra ID 側の GitLab 利用割当て解除と、GitLab 側の Group／Project 権限・トークン失効を実施できること。 | 無償版では SCIM を前提にせず、Entra ID と GitLab の双方を更新する運用を定義する。 |
| IAM-11 | Microsoft Entra ID との SAML SSO を必須とし、GitLab への認証を Entra ID へ統合する。 | Free Tier で利用可能なインスタンス全体 SAML SSO を使用する。 |
| IAM-12 | Entra ID 側で GitLab 利用対象者を制御し、GitLab 側では Project または最下位 Subgroup 単位で Planner／Reporter／Developer／Maintainer を割り当てる。 | 上位 Group からの権限継承で過大権限にならないようにする。 |
| IAM-13 | Entra ID グループによる GitLab 内アクセス権管理を望ましい要件とする。 | 無償版標準の SAML Group Sync は利用できないため、初期は GitLab 側の手動割当てを採用し、GitLab API 等による代替自動化は実現性・保守性・監査性を別途検証する。 |
| IAM-14 | Entra ID と GitLab 間の自動ユーザーライフサイクル同期を前提としない。 | 無償版標準では SCIM を利用できないため、異動・退職・委託終了時は Entra ID と GitLab の双方を更新する。 |

 

## **9.1 標準設定方針**

| 機能 | 本環境での標準設定 | 禁止・統制 |
| :---: | ----- | ----- |
| Role | Developer、限定 Maintainer、Reporter を基本とし、Owner は Group 管理者の少人数のみ。 | トップ Group に一般利用者を直接追加しない。市民開発者へ一律 Maintainer を付与しない。 |
| 認証 / MFA | 一般利用者および GitLab 管理者は Entra ID SAML SSO。ローカル緊急管理者は通常利用から分離する。ローカル緊急管理者は Entra ID の MFA を経由しないため、GitLab の 2FA を必須とする。 | 自己登録とローカルアカウント常用を禁止する。緊急管理者の資格情報は通常運用から分離する。 |
| Token | GitLab API を利用する AI エージェントおよび自動化処理は、GitLab OAuth による短寿命 Access Token を使用する。Git over HTTPS の認証方式は別途基本設計で定める。 | 長期固定の PAT、Project／Group Access Token を AI エージェントの実行環境へ保存しない。OAuth の Client Secret および Refresh Token を使用する場合は、実行環境から分離した認証情報管理基盤で保管し、平文 Commit およびログ出力を禁止する。 |

 

# **10\. API・自動化要件**

| 要件 ID | 要件 |
| :---: | ----- |
| API-04 | REST／GraphQL API は、GitLab OAuth による短寿命 Access Token を使用し、ネットワーク経路、OAuth Application、Scope、Token の取得・更新・失効、レート／負荷および監査方法を定義した上で利用すること。 |
| API-05 | AI エージェントや自動化ツールが GitLab を操作する場合、GitLab OAuth による短寿命 Access Token を使用し、利用 Project と Scope を必要最小限に限定すること。 |
| API-06 | Webhook の送信先を社内の許可済み FQDN／URL へ限定し、受信側で真正性を検証できる構成とすること。 |
| API-07 | 外部サービスへの Webhook、未承認 SaaS 連携、インターネット上のコールバックを初期状態で禁止すること。 |
| API-08 | 連携失敗、権限エラー、トークン期限切れを検知し、運用担当へ通知できること。 |

 

## **10.1 標準設定方針**

| 機能 | 本環境での標準設定 | 禁止・統制 |
| :---: | ----- | ----- |
| REST / GraphQL | 参照、Issue 作成（Issue 導入後）、MR 作成等の承認済みユースケースに限定し、呼出元・Token・対象・操作を台帳化。 | 管理 API や全 Project 対象の資格情報を一般利用者へ開放しない。 |
| Webhook | Project 単位で承認済み社内 HTTPS Endpoint のみに送信し、対象 Event、Secret／署名、失敗監視を記録。 | インターネット上の任意 URL、個人端末、未承認 SaaS への送信を禁止。 |

 

# **11\. AI エージェント基盤固有要件**

| ID | 要件 |
| :---: | ----- |
| AI-01 | エージェントごとにコード、プロンプト、ツール定義、評価資材、デプロイ定義の版を追跡できること。 |
| AI-02 | モデル名・モデルバージョン・接続先等の環境差分は設定として管理し、秘密情報は外部のシークレット管理基盤で管理すること。 |
| AI-03 | プロンプト変更をコード変更と同様に Merge Request でレビューし、変更理由と評価結果を記録できること。 |
| AI-04 | 本番反映対象をタグまたは Release で識別し、どのコミットがどの環境へ反映されたか追跡可能にすること。 |
| AI-05 | AWS 上の実行環境へデプロイする自動化を採用する場合、Runner は GitLab 本体と分離し、到達先と実行権限を限定すること。 |
| AI-06 | AI エージェントによる GitLab 操作を許可する場合、GitLab OAuth による短寿命 Access Token を使用し、読み取り・Issue 作成（Issue 導入後）・MR 作成等の必要最小操作に限定すること。 |

 

# **12\. 市民開発環境固有要件**

| ID | 要件 |
| :---: | ----- |
| CD-01 | 市民開発者が利用するプロジェクトテンプレート、README、Issue テンプレート、ラベル体系を標準化すること。 |
| CD-02 | 開発成果物の所有部署、管理責任者、利用対象、データ区分、接続先、廃止条件を記録できること。 |
| CD-03 | 公開・本番反映前に、レビュー依頼と証跡を Merge Request または Issue で残せること。 |
| CD-04 | 市民開発者が他部門の非公開成果物を閲覧できないよう、グループ／プロジェクト境界を設けること。 |
| CD-05 | バイナリ中心で Git 差分が有効でない製品については、GitLab で管理する対象を設定・スクリプト・文書・エクスポート成果物に限定すること。 |
| CD-06 | ローコード製品側の環境管理・DLP・監査を GitLab だけで代替しないこと。 |

 

# **13\. 利用・運用フロー**

## **13.1 Project の作成から廃止まで**

Issue および Release の導入前は、各欄の括弧内に示す運用台帳、申請番号、Tag 等で代替して記録する。

| 段階 | 担当 | 実施内容 | 証跡 |
| :---: | :---: | ----- | ----- |
| 申請 | 利用部門／開発責任者 | 用途、所有部署、責任者、利用者、データ区分、接続先、外部委託有無を申請。 | 申請番号を Project 説明と初期 Issue へ記録（Issue 導入前は運用台帳で代替）。 |
| 作成 | GitLab 運用管理者 | 所定 Subgroup 配下に Private Project を作成し、命名、main、機能、メンバー、容量方針を設定。 | 作成者、承認者、設定結果を管理 Issue へ記録（Issue 導入前は運用台帳で代替）。 |
| 初期化 | Maintainer | README、Issue／MR テンプレート、Label、保護 Branch、Release 規約を適用（Issue テンプレート、Label、Release 規約は各機能の導入後）。 | 初期化チェック Issue を完了（Issue 導入前はチェックリストで代替）。 |
| 利用 | Developer／Maintainer | Issue 起点（Issue 導入前は申請番号起点）で Branch を作成し、MR レビュー後に main へ反映。 | Issue、MR、Commit、Tag、Release を関連付け（Issue・Release は導入後）。 |
| 棚卸 | Group Owner／GitLab 運用管理者 | 所有者、メンバー、外部利用期限、Token、Webhook、最終更新を確認。 | 棚卸 Issue または運用台帳へ記録。 |
| 廃止 | 所有部署＋GitLab 運用管理者 | 書込み停止、最終 Release（導入前は最終 Tag）、資材保全、Token／Webhook 失効、Archive、保持後削除。 | 廃止承認と保全先を記録。 |

 

## **13.2 初期リリースの共通開発フロー**

初期リリースで提供する Repository、README、Project Wiki、Branch／Tag、Merge Request、保護 Branch、IAM で成立する共通フローとする。Issue、Release、Runner および自動デプロイは前提としない。

| 工程 | 実施者 | GitLab での実施内容 | 完了条件 |
| :---: | :---: | ----- | ----- |
| Project 準備 | GitLab 運用管理者 | 申請内容に基づき会社管理 Group 配下へ Private Project を作成し、利用者へ最小権限 Role を付与する。README の雛形を配置し、Project Wiki を有効化する。 | Project、所有者、利用者、Role、main 保護設定、README および Project Wiki を確認できる。 |
| 変更作業 | Developer | main から作業 Branch を作成し、コード、プロンプト、設定雛形等を Commit／Push する。 | 秘密情報を含まず、変更対象が作業 Branch へ登録されている。 |
| レビュー依頼 | Developer | 作業 Branch から main への Merge Request を作成し、変更目的、影響、試験結果および切戻し方法を記載する。 | 差分とレビューに必要な説明を確認できる。 |
| レビュー／反映 | Maintainer | 差分とコメントを確認し、未解決事項がなければ main へマージする。Developer の main 直接 Push は許可しない。 | Merge Request 経由で main へ反映され、履歴が残る。 |
| 版識別 | Maintainer | 必要な場合のみ Tag を付与し、利用・配布対象の Commit を識別する。 | 対象 Tag と Commit の対応を確認できる。 |

 

## **13.3 将来拡張後の AI エージェント開発フロー**

Issue、評価管理、Release、CI/CD、Runner およびデプロイ記録を追加した後の目標フローとする。AI エージェントが GitLab API を操作する場合は、長期固定の Access Token を実行環境へ保存せず、GitLab OAuth による短寿命 Access Token を使用する。

| 工程 | GitLab で管理するもの | 自動化・連携 | 合格条件 |
| :---: | ----- | ----- | ----- |
| 要件 | Issue に目的、利用者、利用データ、接続先、許可 Tool、リスク、受入条件を記録。 | 申請・審査システムとの連携は別途検討。 | 所有者、受入条件、データ・権限審査要否が明確。 |
| 実装 | コード、プロンプト、Tool Schema、評価コード、設定雛形を作業 Branch へ Commit。 | CI で静的検査や単体試験を実行。 | 秘密値を含まず、変更が Issue に関連付く。 |
| 評価 | 評価条件、結果サマリ、既知失敗を Merge Request へ記録。 | 評価ジョブ／評価基盤との連携。 | モデル、プロンプト、Tool 変更の評価結果を参照可能。 |
| レビュー | Merge Request でコード、プロンプト、権限、外部通信、切戻しを確認。 | 必要に応じて CI 結果をマージ条件に利用。 | 未解決コメントがなく必要なレビュー証跡がある。 |
| リリース／デプロイ | Tag＋Release で反映対象を固定し、Commit、設定版、対象環境、切戻し先を記録。 | Runner から AWS 実行環境へデプロイし、結果を記録。 | GitLab 上の版と実行環境のデプロイ記録が対応する。 |

 

## **13.4 将来拡張後の市民開発フロー**

Issue、Release、テンプレートおよび製品側の ALM 機能を追加した後の目標フローとする。初期リリースでは ~~3.6~~13.2 の共通フローを適用する。

| 工程 | GitLab で管理するもの | 製品側で管理するもの | 完了条件 |
| :---: | ----- | ----- | ----- |
| 申請 | 所有部署、責任者、用途、データ区分、Connector、接続先、廃止条件を Issue へ記録。 | 環境利用申請、DLP、ライセンス。 | 所有者と利用条件が明確。 |
| 開発 | エクスポート可能な Solution、ソース、設定説明、手順を作業 Branch で管理。 | アプリ／フロー、接続参照、環境変数。 | GitLab 管理対象と製品側管理対象が分離されている。 |
| レビュー | Merge Request で差分、試験、接続先変更、権限変更、公開範囲を記録。 | Solution Checker、DLP、共有設定、接続権限。 | レビュー結果と製品側確認結果を参照可能。 |
| 公開 | Tag／Release、公開申請番号、対象環境、切戻し手順を記録。 | 本番環境への Import／Deployment、利用者共有。 | GitLab 上の版と本番反映対象が対応する。 |
| 廃止 | 所有者、最終版、依存先、廃止 Issue、保全情報を記録。 | 共有解除、接続削除、アプリ／フロー停止・削除。 | GitLab と製品側の双方で廃止結果を確認できる。 |

 

# **14\. 初期対象外・追加検討機能**

| 機能 | 初期方針 | 追加時の主な論点 |
| :---: | :---: | ----- |
| CI/CD / Runner | ~~条件付き追加~~後日拡張 | Runner 配置、Executor、同時実行、到達先、資格情報、Artifact 保持、AWS/Azure 双方への配置 |
| Container / Package Registry | 初期無効 | FQDN、TLS、容量、保持・削除、マルウェア／脆弱性対応 |
| Git LFS | 初期無効 | 対象拡張子、容量、バックアップ、クローン性能 |
| GitLab Pages | 初期無効 | 公開範囲、DNS、TLS、Runner、コンテンツ審査 |
| GitLab Duo / AI | ~~初期無効~~対象外（無償版前提） | 有償のアドオン（Premium／Ultimate）または GitLab Credits の購入（Free は GitLab 19.0 以降）が必要なため本書対象外。採用する場合の論点：ライセンス、外部通信、学習利用、プロンプト／コード送信、監査 |
| 高度な承認・監査・セキュリティ | 対象外（無償版前提） | 本書対象外。有償版専用機能を利用しない。 |
| **Object Storage** | 容量増加時に検討 | 格納対象、接続、認証、暗号化、容量、保持、バックアップ、復元、互換性 |

 

## **14.1 追加構築機能の機能要件**

本節は、GitLab ~~CE／~~Free で利用可能だが、Runner、保存領域、FQDN、TLS 等の追加構築を要する機能を定義する。有償ライセンス固有機能は含めない。

| 要件 ID | 機能要件 | 実装条件・統制 |
| :---: | ----- | ----- |
| **CICD-01** | CI/CD Pipeline で検査、ビルド、試験およびデプロイを実行できること。 | 初期状態では無効とし、対象ユースケース、Pipeline 定義、実行権限、実行時間、ログおよび Artifact 保持を決定した後に追加する。 |
| **CICD-02** | Runner を GitLab 本体と分離して配置できること。 | 初期は構築せず、Runner VM、Executor、同時実行数、ネットワーク到達先、資格情報、タグおよび保護 Runner の運用を定義~~する。~~した後に追加する。 |
| **REG-01** | Container Registry を Project 単位で利用できること。 | 初期は無効とし、FQDN、TLS、容量、保持・削除、バックアップ、マルウェア／脆弱性対応およびアクセス権を定義した後に追加する。 |
| **REG-02** | Package Registry を Project 単位で利用できること。 | 初期は無効とし、対象 Package 形式、FQDN、TLS、容量、保持・削除、バックアップおよびアクセス権を定義した後に追加する。 |
| **LFS-01** | 承認された大容量ファイルを Git LFS で管理できること。 | 初期は無効とし、対象拡張子、容量上限、バックアップ、復元および Clone／Fetch 性能を定義した後に追加する。 |
| **PAGE-01** | 承認された内部向け静的コンテンツを GitLab Pages で公開できること。 | 初期は無効とし、Runner、内部 DNS、TLS、公開範囲、アクセス制御およびコンテンツ審査を定義した後に追加する。 |
| **STO-01** | 容量増加時に組織内 Object Storage を利用できること。 | 初期は使用せず、格納対象、接続方式、認証、暗号化、容量、保持、バックアップ、復元および GitLab との互換性を確認した後に追加する。 |

   
**除外：複数承認、Push Rules、高度な監査・Compliance、脆弱性管理、Portfolio、GitLab Duo 等の有償ライセンス固有機能。**

# **15\. 受入条件**

初期リリースの受入は、区分が「初期実装」の観点を対象とする。「条件付き実装」「後日拡張」の観点は、当該機能を導入する時点で受入を行う。

| 観点 | 区分 | 最低受入条件 |
| :---: | :---: | ----- |
| リポジトリ | 初期実装 | 管理者が標準構成の Private プロジェクトを作成し、Developer が Clone／Push、閲覧者が参照できる。 |
| 保護ブランチ | 初期実装 | Developer が既定ブランチへ直接 Push できず、Merge Request 経由で変更できる。 |
| レビュー | 初期実装 | 差分、コメント、Draft、Squash の動作と記録を確認できる。 |
| 作業管理 | 後日拡張 | 標準テンプレートから Issue を作成し、ラベル、担当、期限、Milestone、Board で追跡できる。 |
| 文書・リリース | 初期実装（Release は後日拡張） | README／Wiki を更新し、タグと Release を関連付けできる。 |
| 認証・権限 | 初期実装 | Entra ID の SAML SSO でログインでき、ローカルアカウント常用が禁止され、Project ごとのロール差を確認できる。SSO 利用者はパスワードでログインできず、ローカル緊急管理者は GitLab の 2FA を伴う場合だけログインできる（Entra ID を経由しない緊急ログインの成功を含む）。 |
| API | 初期実装 | GitLab OAuth で短寿命 Access Token を取得・更新・失効でき、許可された Scope の操作のみ成功し、権限外操作が拒否される。 |
| Webhook | 後日拡張 | 許可済み社内送信先へイベント通知でき、未許可送信先を運用上禁止できる。 |
| ~~用途別分離~~領域・部門間の分離 | 初期実装 | ~~AI エージェント基盤と市民開発のグループ間~~全社共通領域と組織・業務所有領域の間、および部門・業務領域 Subgroup 間で、想定外の参照・権限継承が発生しない。 |
| 権限付与 | 初期実装 | 上位 Group に一般利用者を広く付与せず、対象 Project または最下位 Subgroup で Planner／Reporter／Developer／Maintainer を個別に付与できる。 |
| ID ライフサイクル | 初期実装 | 異動・退職・委託終了の試験で、Entra ID 側の利用停止と GitLab 側の権限削除またはブロックを確認できる。 |
| **追加構築機能** | 初期実装（無効の確認） | CI/CD／Runner、Registry、Git LFS、Pages、Object Storage は初期状態で無効または未構築であり、採用時に個別要件と統制を満たして追加できる。 |
| **有償機能の除外** | 初期実装 | 受入条件および初期構成が、Premium／Ultimate または追加 Credits を必要とする機能へ依存していない。 |

 

# **16\. 未決事項**

| No. | 未決事項 | 決定が必要な理由 |
| :---: | ----- | ----- |
| 1 | GitLab CE と GitLab EE 無償状態のどちらを導入するか（決定済み：GitLab EE を有償ライセンス未適用の Free 状態で導入する） | 導入・更新方式、利用許諾、将来の移行手順に影響。機能要件は Free Tier に固定する。 |
| 2 | Entra ID SAML SSO の詳細方式と、Entra ID グループを利用した権限管理の代替可否 | SSO は必須。無償版標準では SAML Group Sync／SCIM を利用できないため、JIT と GitLab 側の手動割当てを基本とし、API 等の代替方式は別途検証する。 |
| 3 | CI/CD と Runner の~~初期導入範囲~~導入時期と範囲 | AI エージェントの AWS デプロイ、市民開発の自動化範囲に影響。 |
| 4 | 標準グループ／プロジェクト構成 | 権限継承、部門分離、運用委任に影響。 |
| 5 | 正式文書と GitLab Wiki／README の役割分担（決定済み：正式承認文書の原本は既存文書管理基盤で管理し、GitLab には参照先を記載する。役割分担は DOC-01 のとおり） | 承認済み設計書の原本性と更新運用に影響。 |
| 6 | 外部ベンダー利用者の認証・接続方式（決定済み：外部ベンダーにも社内の Entra ID アカウントを付与し、社員と同じ方式で認証・接続する） | 委託先アクセス、期限管理、ネットワーク境界に影響。 |
| 7 | Git over HTTPS／SSH で利用者が使用する認証情報（Personal Access Token、OAuth、SSH Key）の方式、有効期限、発行・失効手順 | 初期実装の Clone／Pull／Push に必須。Entra ID SAML SSO は Web ログイン用のため、Git コマンドの認証には別途 Token または SSH Key が必要（9.1 Token では「別途基本設計で定める」としている）。 |
| 8 | AI エージェントの OAuth を認可する GitLab ユーザーを、エージェント専用アカウント（推奨）と開発者本人のどちらにするか（または使い分けの基準） | 要件はどちらにも対応する（IAM-08）。GitLab OAuth のトークンは認可したユーザーの代理として動作するため、選択によって最小権限（API-05、AI-06）と操作記録の分離に影響する。 |

 

# **17\. 公式情報の参照先**

**GitLab roles and permissions:** [https\://docs.gitlab.com/user/permissions/](https://docs.gitlab.com/user/permissions/)

**Repositories and branches:** [https\://docs.gitlab.com/user/project/repository/branches/](https://docs.gitlab.com/user/project/repository/branches/)

**Protected branches:** [https\://docs.gitlab.com/user/project/repository/branches/protected/](https://docs.gitlab.com/user/project/repository/branches/protected/)

**Merge requests API:** [https\://docs.gitlab.com/api/merge\_requests/](https://docs.gitlab.com/api/merge_requests/)

**Issues:** [https\://docs.gitlab.com/user/project/issues/](https://docs.gitlab.com/user/project/issues/)

**Issue boards:** [https\://docs.gitlab.com/user/project/issue\_board/](https://docs.gitlab.com/user/project/issue_board/)

**Milestones:** [https\://docs.gitlab.com/user/project/milestones/](https://docs.gitlab.com/user/project/milestones/)

**Project Wiki API:** [https\://docs.gitlab.com/api/wikis/](https://docs.gitlab.com/api/wikis/)

**GraphQL API:** [https\://docs.gitlab.com/api/graphql/](https://docs.gitlab.com/api/graphql/)

**REST API authentication:** [https\://docs.gitlab.com/api/rest/authentication/](https://docs.gitlab.com/api/rest/authentication/)

**Webhooks:** [https\://docs.gitlab.com/user/project/integrations/webhooks/](https://docs.gitlab.com/user/project/integrations/webhooks/)

**Two-factor authentication enforcement:** [https\://docs.gitlab.com/security/two\_factor\_authentication/](https://docs.gitlab.com/security/two_factor_authentication/)

**GitLab pricing / feature comparison:** [https\://about.gitlab.com/pricing/feature-comparison/](https://about.gitlab.com/pricing/feature-comparison/)

GitLab Self-Managed SAML SSO: [https\://docs.gitlab.com/integration/saml/](https://docs.gitlab.com/integration/saml/)

SAML Group Sync（Premium／Ultimate）：[https\://docs.gitlab.com/user/group/saml\_sso/group\_sync/](https://docs.gitlab.com/user/group/saml_sso/group_sync/)

SCIM for GitLab Self-Managed（Premium／Ultimate）：[https\://docs.gitlab.com/administration/settings/scim\_setup/](https://docs.gitlab.com/administration/settings/scim_setup/)

GitLab EE activation / Free state: [https\://docs.gitlab.com/administration/license/](https://docs.gitlab.com/administration/license/)

GitLab backup and restore: [https\://docs.gitlab.com/administration/backup\_restore/](https://docs.gitlab.com/administration/backup_restore/)

Microsoft Entra Workload ID federation: [https\://learn.microsoft.com/ja-jp/entra/workload-id/workload-identity-federation](https://learn.microsoft.com/ja-jp/entra/workload-id/workload-identity-federation)

GitLab OAuth provider: [https\://docs.gitlab.com/integration/oauth\_provider/](https://docs.gitlab.com/integration/oauth_provider/)

GitLab Token overview: [https\://docs.gitlab.com/security/tokens/](https://docs.gitlab.com/security/tokens/)

GitLab OAuth 2.0 identity provider API: [https\://docs.gitlab.com/api/oauth2/](https://docs.gitlab.com/api/oauth2/)

GitLab groups and subgroup structure: [https\://docs.gitlab.com/user/group/subgroups/](https://docs.gitlab.com/user/group/subgroups/)

注：GitLab の機能提供範囲はバージョンおよびプランで変更される可能性があるため、基本設計開始時と導入直前に英語版公式ドキュメントで再確認する。

