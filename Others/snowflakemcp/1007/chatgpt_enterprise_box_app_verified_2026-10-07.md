# ChatGPT Enterprise「Boxアプリ（旧Boxコネクタ）」調査報告
## 2資料の統合・公式情報再検証版

**最終確認日：2026年10月7日（JST）**  
**対象：ChatGPT Enterpriseの標準Boxアプリ／Boxホスト型MCP／セルフホストMCP**  
**目的：参照方式、仕様変更、実装基盤、Box側の費用・制限、監査方法を整理し、比較判断に使える資料にする。**

### 調査範囲と読み方

次の添付資料を比較し、その主要な仕様・日付・料金条件・監査上の説明を、OpenAIおよびBoxの公式公開情報で再確認した。

- **資料1：** `chatgpt_enterprise_box_app_investigation_2026-10(1).md`
- **資料2：** `chatgpt_enterprise_box_app_research_2026-10(1).md`

本文の出典番号 `[Sxx]` は、第9章の公式出典に対応する。第三者記事は検証根拠として採用していない。公開日、ページ更新日、機能の適用日は別物として扱う。相対表示の更新日は閲覧時の表示を記録し、正確な日付に換算しない。

| 表記 | 意味 |
|---|---|
| **確認済み** | 記載した範囲の主張が、公式公開資料で明示されている。個別の契約・環境への適用まで確認した意味ではない。 |
| **判断** | 複数の公式説明から行った比較・解釈。ベンダーによる実装保証ではない。 |
| **不明** | 今回確認した公式公開資料では、答えを確定できない。 |
| **実環境未検証** | 契約、管理画面、実ログ、個別サポート回答を確認していない。 |

**本報告では、利用者のワークスペース、Box契約、実ログにはアクセスしておらず、再現試験・サポートへの問い合わせ送信も実施していない。** 公開情報で確定できない事項は、推測で補完せず第5章に残した。

---

## 1. 結論

### 1.1 2資料間の矛盾・相違の判定

**主要結論を覆すような致命的な矛盾は見つからなかった。** 両資料は、「現行Boxアプリは個人同期を使用しない」「標準BoxアプリもMCPを利用する」「EnterpriseにおけるBox固有の同期終了日は不明」という点で一致している。差分は主に説明の精度と補足の有無である。元資料の対応箇所は、両資料の第1章および第2章。詳しい補正内容は第3章に示す。

ただし、そのままでは判断材料が不足する箇所があるため、今回、**2026年4月のMCP統合発表、Box AIの現行計量規則、ツール無効化の管理機能、データ保持の一般ルール、現行Compliance Logsの注意点**を追加した。[S06] [S07] [S22] [S23] [S24] [S25]

### 1.2 採用する最終的な整理

**現行の標準Boxアプリは、ライブ／オンデマンド型として扱うのが妥当である。ただし、確定しているのは個人同期を使用しないことなど、公開された範囲に限られる。** 初回走査、無操作時通信、内部索引・キャッシュが一切存在しないという保証は確認できない。[S01] [S11]

**A案とB案を「同期対MCP」で比較してはならない。** 標準Boxアプリ自体がBox MCP Serverを利用する。比較対象は、A＝標準公開連携、B1＝Boxホスト型MCPへの独自接続、B2＝セルフホスト実装に分ける。[S10] [S12] [S13] [S29]

**Box API課金の免除条件と、Box AI Unitsの消費は別である。** 標準公開連携の本人OAuth利用にはAPIコールの無料条件がある。一方、現行のBox公式説明では、Box MCP経由で実行されるBox AIのQ&A・文章生成・情報抽出はAI Unitsの消費対象である。ChatGPTの質問すべてがBox AIを呼ぶ、とまでは確認できない。[S14] [S23]

**Box固有の同期終了日・移行完了日は、再調査後も不明である。** 2026年3月27日のアプリ更新、4月のMCP統合発表、8月の個人同期廃止、9月のLibrary拡張は、同じ変更の実施日としてまとめない。[S04] [S05] [S06] [S07] [S09]

---

## 2. 確認したいこと1〜5への回答

### 2.1 参照方式

本報告の「同期型」は、**OpenAI側がBoxの内容を事前・継続的に収集して検索索引を保持する方式**を指す。Box自身の検索索引、取得内容の一時キャッシュ、会話内に残った引用とは区別する。

| 確認事項 | 再検証結果 | 判定・出典 |
|---|---|---|
| （a）同期型／（b）ライブ・オンデマンド型／（c）併用型のどれか | **（b）として扱うのが妥当。** OpenAIのBox専用FAQは個人同期を使用しないと明記し、旧同期手順や同期ステータス待ちに従わないよう案内している。Box側もMCPによるリアルタイムの問い合わせを説明している。ただし内部処理全体を確定した分類ではない。 | 個人同期不使用＝**確認済み**。全体分類＝**判断**。[S01] [S11] |
| 管理者管理のApps with SyncにBoxは含まれるか | 現行の管理者同期記事、セットアップ案内、地域別表にはGoogle Drive、SharePoint、Microsoft Teamsが掲載され、Boxは掲載されていない。ただし記事の列挙は、あらゆる限定提供・旧接続を排除する保証ではない。 | 公開対象への掲載なし＝**確認済み**。個別例外＝**不明**。[S02] |
| 「質問されたときだけアクセスする」と言い切れるか | **言い切れない。** Libraryの検索・フォルダ閲覧・ファイル選択・プレビューでも利用される。認証更新や接続維持など、無操作時の通信の有無・内容は不明。 | Library利用＝**確認済み**。無操作時通信＝**不明**。[S05] [S08] [S09] |
| 同期がなければOpenAI側に保存されないか | **その結論にはならない。** アプリから会話やリサーチに取り込まれた内容は、該当機能・会話・ワークスペースの保持設定に従うという一般ルールがある。Box固有の内部索引、埋め込み、一時キャッシュの有無・保存先・保持期間は別途不明。 | 一般的な保持の扱い＝**確認済み**。Box固有の内部保存＝**不明**。[S24] |
| Boxのアクセス権は確認されるか | Box MCPはリクエストごとに本人性、スコープ、対象コンテンツへの権限を確認すると説明している。ただし権限変更が何秒以内に反映されるか、会話に既に取り込まれた内容がどう扱われるかは別問題。 | 権限確認の仕組み＝**確認済み**。Boxアプリ固有の反映SLA＝**不明**。[S26] [S24] |

**区別すべき事項：**「個人同期がない」「管理者同期の公開対象にない」「Box自身に検索索引がある」「取得した内容が会話に残る」「内部キャッシュがあるか不明」は、互いに異なる主張である。

### 2.2 仕様の変化

| 日付・出来事 | 公式情報で確認できたこと | この情報だけでは確定できないこと |
|---|---|---|
| **2025-09-25：過去の事前同期** | OpenAI公式発表はBoxを明示し、データを事前同期して回答を高速化・改善できると説明している。過去のBox事前同期の存在は確認済み。[S03] | 初提供日、全プランでの提供期間、対象環境で実際に同期が動いた期間。 |
| **2026-03-27：Boxなどのアプリ更新** | Enterprise/Edu向けには追加アクション、書き込み対応、権限確認、必要に応じた再接続を案内。一般向けリリースノートには、既存同期は影響を受けないとの記載があり、**Proユーザーのみ**と限定されている。[S04] [S05] | Box同期の全面終了、Enterprise固有の同期停止日、MCPへの一斉切替日。Proの説明をEnterpriseへ読み替えることもできない。 |
| **2026-04-15：MCP AppsのChatGPT対応拡張** | **今回追加確認。** Box英語公式記事は標準BoxアプリへのMCP Apps・Box MCP Serverの統合を説明し、ChatGPTで利用可能と案内している。英語原文の日付は日本語公式記事の翻訳注記で確認。日本語版の公開日は**4月21日**。[S06] [S07] | MCPプロトコルを初めて利用した日、全Enterprise環境の移行完了日、従来同期を停止した日。MCP Appsの画面機能拡張と、初回のMCP採用は同義ではない。 |
| **2026-08-10／08-14：個人同期の廃止** | Enterprise/Edu告知は8月10日に個人認可による新規同期接続を停止し、8月14日に既存同期を無効化して関連同期データの削除を**開始**すると説明。管理者同期は対象外。[S04] | 当該移行表にBoxは明記されていないため、Boxが8月14日まで稼働していたこと、同日に旧Box索引の削除が完了したこと。 |
| **2026-09-10：Library拡張** | OpenAIがBox・Dropbox・SharePointのLibrary対応を告知。Box英語発表も、既に存在するMCP連携を土台としたフォルダ閲覧・ファイル選択・プレビュー等の拡張を説明。Box日本語版は**9月11日公開**で、9月10日の英語原文の翻訳と明記。[S05] [S08] [S09] | 同期終了日、初回MCP導入日、利用者の環境への展開完了日。 |

**社内情報「2026年3月ごろまではバックグラウンド同期が動いていた」の評価：**

「過去にBoxの同期型機能があった」ことは裏付けられる。一方、「そのEnterprise環境で3月ごろまで動いていた」「3月の更新で止まった」ことは、公開資料からは確認できない。対象環境の接続履歴、当時のログ、OpenAIの個別回答が必要である。今回の4月発表はMCP利用の時系列を補強するが、同期終了日の証拠ではない。

### 2.3 実装の土台とA案・B案の関係

| 構成 | 定義と確認結果 | 留意点 |
|---|---|---|
| **A：標準Boxアプリ** | Box公式手順は、Box管理画面で**ChatGPT MCP Server**を有効化し、ChatGPTの標準アプリディレクトリで**Box → Connect**を選ぶ流れを案内している。標準アプリのMCP利用は確認済み。[S10] | これを「カスタムMCP接続のB案」と別建てで数えると、同じ構成を二重に比較することになる。 |
| **B1：Boxホスト型MCPへの独自接続** | BoxがホストするリモートMCPへ、独自クライアント登録や追加Integration Credentials等で接続する構成。登録・認証・公開ツール・管理単位が比較点になる。[S12] [S29] | 標準Aと同じ利用体験、ツール集合、API課金区分になるとは限らない。 |
| **B2：セルフホストMCP** | 自ら管理するMCP実装からBox API／SDKを呼び出す別構成。Boxが紹介する従来のコミュニティ製実装はlegacy／deprecatedで、新規連携にはリモート版を推奨している。[S13] | 独自実装が不可能という意味ではない。保守・認証情報・実行環境の管理が別途必要になる。 |

**MCP経由の範囲：** BoxはMCPリクエスト先として `mcp.box.com` を案内している。ただし、標準Aの検索、本文取得、Library、プレビュー、書き込み、認証まで含め、全通信がこのホストだけを通るという公開保証はない。一般のMCPツール一覧には、ファイル転送用URLに対して直接ネットワークリクエストを行うツールもある。これらをAが実際に使用するかは不明である。[S11] [S15]

**機能一覧の扱い：** Box MCPの全ツール一覧を、そのままAで使える全機能とみなしてはならない。実際の提供はプラン、管理設定、クライアント側の対応等に依存する。[S30]標準Aは「常に読み取り専用」でもなく、内容変更が可能な対応アクションは権限・承認条件に従う。[S01] [S14] [S22]

**画面名の差異：** 再確認時のOpenAI Box専用ヘルプは `Settings > Plugins` を案内し、Box側のセットアップ記事にはApps／App directoryの表記が残る。資料では「標準Boxアプリ」に統一し、実際の表示に応じて読み替える。画面名の差だけで別の連携方式とは判定しない。[S01] [S10]

### 2.4 Box側への影響：API課金・AI Units・上限

#### 2.4.1 API料金と計量

| 項目 | 公開ルールに基づく回答 |
|---|---|
| 標準的なAのAPI無料条件 | **①Box Integrations Centerで公開されたアプリ、②本人のBoxアカウントによるOAuthログイン、の両条件。** ChatGPTは標準利用例として明記されている。ChatGPT側のディレクトリ掲載だけ、またはOAuthであることだけでは説明が足りない。[S14] |
| B1の独自接続 | 上記以外は課金対象として、非公開アプリ、独自連携・自動化、追加Integration Credentials、サービスアカウント等が例示される。単にMCPだから有料、本人OAuthだから必ず無料、という判定ではない。[S14] |
| 課金対象のBoxホストMCPの計数 | ツール実行は1回につき1 API call。セッション初期化とツール一覧取得はそれぞれ1回／セッション。AIツールは、このAPI計量に加えてAI Unitsが適用される。セルフホストB2へ同じ計数をそのまま適用する根拠はない。[S14] [S13] |
| AI以外の追加利用 | DocGenやSignにも、それぞれプラン・利用量に応じた扱いがある。「API無料」を、すべてのMCP機能の総費用ゼロと解釈しない。[S14] |
| 月間API契約枠・超過請求 | 非課金MCPが月間API枠にどう算入されるか、契約上の例外、実際の超過請求額は**不明／実環境未検証**。公開のChargeable分類だけで請求額を確定しない。確認先はBox。 |

費用の比較表では、**通信の発生、課金対象APIとしての計量、契約枠消費、超過請求、AI Units等の別料金**を分ける。この区別は分析上の整理であり、通信回数から請求額を一対一で推定するものではない。

#### 2.4.2 Box AI Units：今回明確になったこと

Boxの現行AI利用説明は、MCP経由の処理を次のように区別している。[S23]

| 実際に行われる処理 | 現行公開ルール |
|---|---|
| 通常のファイル取得、フォルダ閲覧、構造的なメタデータ取得 | それ自体ではAI Unitsを消費しない。 |
| Box MCP経由のBox AIによるQ&A・文章生成 | **AI Unitsを消費する。** BoxのネイティブWeb画面での対象プラン内利用と同じ扱いではない。 |
| MCPで実行されるBox AIの情報抽出 | **AI Unitsを消費する。** 通常のメタデータ取得とは区別する。 |

したがって元資料の「Box AIツールでは消費し得る」は、**対象のBox AI処理を実行した場合の現行規則については、より明確に記載できる。** ただし、「ChatGPTで要約を依頼した」という操作名だけでは、取得本文をChatGPTが処理したのか、Box AIを呼び出したのかを区別できない。Aにおける質問とツール選択の対応は引き続き不明である。

同じ公式ページに、将来は公開MCPアプリと独自MCPアプリで計量を区別する方針が記載されているが、**将来方針を現在の免除条件として採用しない。** また、AI Units Reportの0 Units記録は、現在のMCPによるBox AI Q&Aが一律無料という証拠ではない。[S23] [S19]

#### 2.4.3 AIや書き込みを制限する方法

**ツールの無効化機能自体は公開仕様で確認できた。** Boxでは全社既定と連携別に、カテゴリ／個別ツールを有効・無効化できる。**連携別のCustom設定は全社Global設定より優先される**ため、全社設定だけで実効設定を判断しない。無効化はツール一覧への非表示に加え、実行時にも強制される。[S22]

**検証用の設定案：** 対象のChatGPT MCP Server連携を特定し、必要な通常の検索・取得を残したうえで、Box AI系ツールと不要な変更系ツールを無効化する。契約・画面に表示される対象ツールを確認し、同じ連携の他利用者への影響を確認してから変更する。これでAの全AI経路を排除できるか、必要な取得機能が残るかは実機で確かめる。

ChatGPTの読み取りアクションに関する**承認省略の設定**と、Box側での**ツール無効化**は別である。承認を求める／求めないという設定だけを、AI Unitsの使用禁止設定として扱わない。[S21]

#### 2.4.4 公開されている数値と、適用してはいけない範囲

| 対象 | 確認できた数値・性質 | 誤って一般化してはいけないこと |
|---|---|---|
| Box一般APIのレート制限 | 通常1,000回／分／ユーザー。検索は6回／秒／ユーザー、60回／分／ユーザー、12回／秒／企業。制限時は429とRetry-Afterを使用する。[S16] | そのままChatGPTの質問回数・MCPツール回数へ換算しない。MCP固有の制限枠、A/B間の共有単位は不明。 |
| `ai_qa_single_file` | 公開ツール説明は、処理対象の**テキスト表現が最大1 MB**で、超える場合は先頭1 MBを処理すると記載。[S15] | A全体のファイルサイズ上限、全ツール共通上限、元ファイルのバイナリサイズ上限とはいえない。 |
| Box自身の検索索引 | Business以上のアカウントについて、文書あたり最大10,000 bytes程度の本文を索引化し、文書種別・言語等で変動すると説明。更新は通常秒単位という案内だが、負荷によって長くなる。[S27] | 日本語10,000文字、本文全体の取得上限、OpenAI側の索引上限ではない。「必ず数秒以内」というSLAでもない。 |
| 現行Boxアプリ固有の総上限・旧同期の仕様 | 最大ファイル件数、総容量、取得総量、旧同期の巡回頻度、旧同期・現行Aの更新／削除／権限変更の反映SLAは、今回の公式資料では**確定できない**。 | Google Drive等の別アプリや、個別Box AIツールの制限を転用しない。 |

**鮮度の解釈：** OpenAI側の個人同期がなくても、検索がBox自身の索引に依存する経路では、その索引の更新や検索対象範囲が影響し得る。これは一般のBox検索仕様からの判断であり、Aの全検索経路が同じAPIを使うと確認したものではない。[S27]

### 2.5 実際の確認方法

#### 2.5.1 使うレポートと限界

| 目的 | レポート／ログ | 確認できることと注意点 |
|---|---|---|
| 連携・利用者の識別 | **Box MCP Server Activity Report** | Integration ID、Integration Name、Integration Client ID、利用者等を確認できる。公開の列説明に個別ツール名はなく、全HTTPリクエストの詳細ログとは扱わない。日付はPT。[S17] |
| API利用量・課金区分 | **Box Platform Activity Report** | アプリ別API Calls、App ID、App Name、Chargeable等。認可リクエスト・エラーを含むが、**直近3日間とBox AI APIは対象外**。日付はPT。非課金を含む抽出条件はある一方、Valueの説明にはChargeable=Yesの場合という限定があり、非課金MCPの数量が完全に得られるとは断定しない。[S18] |
| ファイル操作 | **Box User Activity Report** | Download、Preview、Content Access等を利用者・ファイルで照合できる。CSV反映は最大1日の遅れがあり得る。1つのプレビューから複数イベントが発生する場合もあり、イベント数を課金API数に置き換えない。[S20] |
| Box AIの実利用 | **Box AI Units Report** | AI Capability、Product、モデル区分、AI Units等を確認。ProductはMCPやAPI等の入口を示し、0 UnitsのAI利用も記録される。A/Bを一意に特定する連携IDまで常に得られるかは実確認が必要。[S19] |
| ChatGPT側の呼び出し | **OpenAI Compliance Logs／Compliance Platform** | アプリ呼び出しが記録されるという公式説明がある。ただし、認証更新等を含む全バックエンドHTTP通信の網羅性までは確認できない。権限のある管理者による取得が必要。[S21] [S25] |

**OpenAI側の更新点：** 専用のCompliance文書は、会話ログの旧statefulルートが2026年6月5日に削除されたと説明している。新しい会話ログの取得方法に従う必要があり、「Compliance API」の名称だけで古い取得例を流用しない。Stateful APIのすべてが廃止されたという意味ではない。**Compliance Logs Platformの保持は30日**とされるため、検証に必要なログは期限内に取得する。[S25]

**時刻：** MCP／PlatformのPTと、試験記録のJSTを混同しない。その他のレポートも、ファイル名のローカル時刻とイベント列の時刻が同じとは限らない。実際の列に付くタイムゾーンやオフセットを確認して照合する。[S17] [S18] [S20] [S28]

#### 2.5.2 最小限の検証手順案

以下は本報告で提案する試験であり、実施済みの結果やベンダーの保証ではない。最初から独自サーバーや監視基盤を構築する必要はなく、**専用ユーザー1名、小さなダミー文書2件、手動の実施記録**から始める。

| 段階 | 実施内容 | 記録・判断 |
|---|---|---|
| 1. 接続を特定 | 標準Aの連携名、Integration ID／Client ID、App ID、ChatGPT側設定、認証ユーザー、有効ツールを記録。B1は比較が必要な場合だけ別期間で試す。 | 表示名が同じ「ChatGPT」でも、同じ登録とは決めつけない。取得できないIDは不明として残す。 |
| 2. 背景通信を観察 | 「接続前」「接続直後」「接続を維持して無操作」を分ける。無操作期間は例として24時間。Library・プレビュー・自動処理・別端末の利用を混在させない。 | 初回認可やセッション維持と思われる通信と、継続的な本文取得を分ける。少数の呼び出しだけで同期と判定しない。 |
| 3. 操作を分離 | 検索、指定ファイル取得、Libraryプレビュー、単一文書要約、複数文書比較を順に行う。必要ならAI系ツールを無効化した条件でも試す。 | 開始・終了時刻、対象ファイルID、質問、表示されたツールを記録。日次集計で区別できなければ試験日を分ける。 |
| 4. 更新・権限を確認 | 小さなテキスト文書の先頭付近に一意の検証文字列を追加し、新規会話で「ファイル指定取得」と「キーワード検索」を別々に試す。権限取り消し後も新規取得を試す。 | 大きな文書の末尾だけに文字列を置くと、検索索引の範囲制限と混同し得る。過去の会話の再表示は新規取得の成功に数えない。 |
| 5. 反映後に照合 | 表示遅延・対象外期間を考慮して各レポートを取得し、アプリ・ユーザー・日時・対象ファイルを照合する。 | Platformの直近3日除外を過ぎてから評価する。非課金の数量欄がない場合はゼロに置き換えない。OpenAIログは保持期限内に確保する。 |
| 6. 不一致だけ照会 | 判別できない通信、課金分類、AI利用、権限反映について、IDと時刻を添えてOpenAI／Boxに照会する。 | 第6〜8章の質問文から必要な項目だけ使う。 |

上記の試験設計は、第2.4.4節の検索仕様と、第2.5.1節のレポート仕様を踏まえた提案である。**ログに記録がないことだけで、アクセス・キャッシュ・背景処理の不存在は証明できない。** 逆に、記録があっても、それだけで継続的な本文同期や追加請求があったとは断定できない。

---

## 3. 2資料の差分と、再調査による補正

| 論点 | 元資料の状態 | 統合版の処理・重要度 |
|---|---|---|
| 現行の個人同期・MCP利用 | 両資料の主要結論は一致。 | **維持。致命的矛盾なし。** 内部キャッシュまで否定しない限定も維持。第2.1・2.3節。 |
| 3月27日と同期終了の関係 | 資料2のみ、一般向け告知のPro限定・同期影響なしの記載を補足。 | **資料2の精度を採用。** 記載の欠落であり、相反する主張ではない。第2.2節。 |
| MCP統合の確認可能な時期 | 両資料とも主に9月資料を利用。 | **4月の公式発表を追加。** 同期終了日とは結び付けない。第2.2節。 |
| 9月10日／11日の違い | 資料1は英語発表、資料2は日本語発表を中心に記載。 | **矛盾ではない。** 日本語公式の翻訳注記で原文日付を確認し、両方を併記。第2.2節。 |
| API無料とAI Units | 両資料とも区別しているが、AIは「消費するケース」「消費し得る」が中心。 | **重要補強。** 現行のMCP経由Box AI処理の消費ルールと、未確認の質問→ツール選択を切り分けた。第2.4.2節。 |
| AIツールを止める設定 | 両資料ともサポートへの質問に残していた。 | **一部解決。** Boxの公開管理機能は確認済み。対象環境の実効設定・Aの全経路への効き方は未検証。第2.4.3節。 |
| データ保持 | 両資料とも「同期なし＝保持なし」を否定しているが、未確認事項が広い。 | **一部解決。** 会話に取り込まれた内容の一般的な保持ルールを追加。内部索引・キャッシュは不明のまま。第2.1節。 |
| 数値上限・鮮度 | 旧同期の件数・容量・周期等は不明。 | **範囲を分けて補足。** 個別AIツールとBox検索の公開制限を追加したが、A全体や旧同期の上限には転用しない。第2.4.4節。 |
| OpenAI側監査 | 資料1に説明があり、資料2では省略。 | **統合・更新。** 現行ログ取得、旧会話ルート廃止、30日保持を追記。第2.5.1節。 |
| 非課金MCPをログで数え切れるか | 両資料に注意はあるが、Platformの説明が完全な数量確認を期待させ得る。 | **判定を厳密化。** 全非課金通信の数量網羅性は不明。空欄・ゼロ・未反映を区別。第2.5節。 |
| A／Bの区分 | 資料1はA／B1／B2を明確化。資料2は別章に説明が分散。 | **資料1の三分法を採用。** 同じ標準連携を別案に数えない。第2.3・4章。 |
| 第三者記事 | Carly、Jotform等の説明との比較がある。 | **現行仕様の根拠から除外。** 今回は第三者記事へ再アクセスせず、原文・更新日の正否も再判定しない。 |

### 第三者情報をどう扱うか

元資料にある第三者記事の紹介は、今回の公式限定調査の根拠には使用していない。したがって「第三者記事は当時から誤りだった」とは認定しない。

公式の2025年発表に同期の説明が残り、現行FAQが個人同期を否定していることは、**説明対象の時点が異なる**ものとして扱う。現行の設計には現行仕様、履歴の確認には当時の発表を使用する。過去記事の見出しや古いリンク名だけで、現在も同期型と判断しない。[S01] [S03]

---

## 4. A案とB案の比較への影響

以下は、確認した仕様を踏まえた**本報告の比較判断**である。費用、性能、機能差を実測した結論ではない。

| 評価軸 | A：標準公開連携 | B1：独自リモートMCP | B2：セルフホスト |
|---|---|---|---|
| 同期・API負荷 | 個人同期による全件クロールを当然の前提にしない。接続時・操作時・無操作時を測定。 | 同じく実測が必要。「直接MCPなら背景通信ゼロ」とは仮定しない。 | 自分の実装に依存。同期するかどうかも設計次第。 |
| Box側API費用 | 公開連携＋本人OAuthの無料条件に対応する標準利用として検討可能。適用はID・契約で確認。 | 独自登録・追加認証情報等により課金対象となる公開条件に注意。 | 実際のBox API利用と契約で評価。リモートMCPの計数を転用しない。 |
| AI等の費用 | 呼ばれたBox AI等の機能で評価。 | 同左。MCPという名称より有効ツールが重要。 | 実装から呼ぶBox AI等の機能で評価。 |
| 検索品質・鮮度 | 「Aは古い事前索引、Bは最新」という前提は採用しない。 | Aと同じ文書・権限・質問で、検索成功率・更新後取得・時間を比較。 | 取得方式、検索方式、エラー処理を自ら評価。 |
| 機能・統制 | 標準Library等の体験と、Box／OpenAI双方の管理設定を確認。 | 同じ画面機能・ツール集合になるとは限らない。必要な差分を明確にする。 | 自由度の代わりに実装・保守の責任が増える。 |
| 運用負担 | まず標準構成で小規模検証。 | Aで満たせない要件があるときに検討。 | 従来紹介実装は非推奨。明確な独自要件がある場合に限って別途評価。 |

根拠となる仕様は第2.1〜2.5節を参照。

**推奨する進め方：** まずAを、必要な読み取りと最小限のツールで検証する。その結果、満たせない機能・統制・運用要件が残る場合だけB1を比較する。B2はさらに独自実装が必要な理由がある場合の選択肢とする。「同期負荷を避けたい」という理由だけでは、現行AよりBが優位とは説明できない。

---

## 5. 再調査後も残る不明点

公開管理機能や一般ルールが分かった項目まで、すべてを「不明」としては扱わない。一方、一般仕様から対象環境の動作を断定しない。

| 残る不明点 | 分かっている範囲との境界 | 主な確認先 |
|---|---|---|
| **Box固有の同期提供期間・終了日・移行完了日・旧索引削除完了時期** | 過去同期、各発表日、一般的な個人同期廃止は確認済み。対象Enterpriseの適用履歴は不明。 | OpenAI |
| **初回接続・無操作時の本文／メタデータ取得、ポーリング、先読み、イベント購読、キャッシュ・内部索引** | 個人同期不使用、会話内コンテンツの一般的な保持方針は確認済み。内部処理と保持期間は不明。 | OpenAI。通信の実態はBoxとも照合 |
| **対象環境の管理者同期・旧接続・限定提供の例外** | 現行の公開対象にBoxはない。例外が実在するとも、絶対にないとも確認できない。 | OpenAI |
| **Aの全通信経路・実公開ツール・B1との差・操作ごとのBox AI選択** | 標準AのMCP利用、一般ツール・管理機能は確認済み。完全な経路図と質問→ツール対応は不明。 | OpenAI／Box、実機検証 |
| **非課金MCPの月間API枠算入、制限共有単位、契約への実適用** | 公開API料金条件と一般API制限は確認済み。契約上の計上とMCP固有の制限適用は不明。 | Box |
| **非課金通信・背景通信・AI呼び出しのログ網羅性と関連付け** | レポートの公開列・除外期間等は確認済み。全通信を共通IDで一対一に照合できる保証はない。 | Box／OpenAI |
| **A全体の件数・容量・反映SLA、旧同期の周期・上限** | 個別ツール・一般検索の一部制限は確認済み。A全体と旧方式の数値は不明。 | OpenAI／Box |

**現時点で上記に数値や実施日を入れて断定することはできない。** サポート回答を得た場合は、一般仕様と対象ワークスペースへの適用を分けて、本表を更新する。

---

## 6. OpenAIサポートへの問い合わせ文案（日本語）

**未送信の文案。確認済みの一般仕様の再説明ではなく、残ったBox固有・環境固有の点を確認するために使用する。**

**件名：ChatGPT Enterprise標準BoxアプリのBox固有仕様・移行履歴・通信と保持の確認（2026年10月7日時点）**

OpenAIサポートご担当者様

ChatGPT Enterpriseの標準Boxアプリと、Boxホスト型MCPへの独自接続を比較しています。公開資料で、標準Boxアプリの個人同期不使用、Box MCP Server利用、アプリ由来コンテンツの一般的な保持ルールを確認しています。そのうえで、次の未確認事項について、当社環境に適用される仕様をご回答ください。

対象情報：  
ワークスペースID：［記入］  
データレジデンシー設定：［記入］  
Box Enterprise ID・契約プラン：［記入］  
ChatGPT側のBoxアプリ／プラグイン識別子：［確認できる場合に記入］  
Box連携名・Integration ID・Client ID・App ID：［確認できるものを記入］  
初回接続日・最終再接続日：［記入］  
接続方式：［標準Box／独自MCP］

### 1. 初回接続・無操作時のアクセス

個人同期を使用しない現行接続でも、初回走査、差分取得、定期ポーリング、変更イベント購読、先読み等は行われますか。会話、Library、プレビュー、自動処理を利用していない状態で発生するBoxアクセスを、認証・セッション維持と、本文・メタデータ・アクセス権情報の取得に分けてご説明ください。

### 2. 内部索引・キャッシュと保持

会話に取り込まれた内容の保持とは別に、Box本文、メタデータ、ACL情報、検索索引、埋め込み、キャッシュをOpenAI側に保持しますか。保持する場合は保存場所、対象範囲、保持期間、更新条件、権限取り消し・切断時の削除条件をご提示ください。

### 3. Box固有の移行履歴

EnterpriseにおけるBox同期の提供期間、現行方式への移行開始日・完了日、旧同期データの削除開始・完了条件を教えてください。2026年3月27日のアプリ更新、4月のMCP Apps拡張、8月の個人同期廃止、9月のLibrary拡張との関係、および当社の接続に適用された変更日を確認したいです。

### 4. 管理者同期・旧接続の例外

現行公開資料ではBoxの管理者同期手順を確認できませんでした。当社でBoxの管理者管理Indexed search／Apps with Syncを利用できる構成、旧接続、限定提供、地域差による例外はありますか。存在する場合は対象範囲と制限をご提示ください。

### 5. 全通信経路と公開ツール

標準Boxアプリの検索、本文取得、Library閲覧、プレビュー、書き込みについて、MCP以外の直接API・ファイル転送経路も含めた構成をご説明ください。当社接続のBox側識別子、標準アプリに実際に公開されるツール、独自リモートMCPと異なる点も教えてください。

### 6. Box AIの選択と管理設定

標準アプリの検索、要約、比較、抽出が、どの条件でBox AIを呼びますか。Box側の連携別ツール無効化で、通常の検索・取得を維持しつつ、当該連携のBox AI呼び出しを遮断できますか。MCP以外の経路や別ツールによる同等処理があれば、その制御方法をご提示ください。

### 7. 上限・鮮度とBoxへの確認用情報

標準Boxアプリ固有の件数、ファイルサイズ、総取得量、頻度、内容変更・削除・権限変更の反映目標を教えてください。個別Box AIツールの上限や一般Box検索の制限が、どの経路で適用されるかも確認したいです。API料金・契約枠をBoxへ照会するために必要な連携識別子もご提示ください。

### 8. 監査・再現試験

現行Compliance LogsでBoxアプリの呼び出しを確認する方法と、Box側レポートと照合できる識別子をご提示ください。無操作時アクセス、認証更新、非課金呼び出しについて、記録対象外・記録遅延・粒度の限界を教えてください。現行の会話ログ取得方式を前提にご回答ください。

各項目について、一般仕様と当社ワークスペースへの適用を分け、公式資料または適用日付きの技術説明をご提示ください。Boxによる回答が必要な点は、確認先と必要情報をご案内ください。

---

## 7. OpenAI Support inquiry draft（English）

**Unsent draft. This requests Box-specific and workspace-specific details that remain unresolved after reviewing the public documentation.**

**Subject: Box-specific architecture, migration history, traffic, and retention for the standard ChatGPT Enterprise Box app — as of October 7, 2026**

Hello OpenAI Support,

We are comparing the standard Box app in ChatGPT Enterprise with a custom connection to Box’s hosted MCP server. We have reviewed the public statements that the standard Box app does not use individual-user sync, uses Box MCP Server, and is subject to general retention rules for content incorporated into conversations. Please clarify the following unresolved points for our workspace.

Workspace ID: [insert]  
Configured data residency region: [insert]  
Box Enterprise ID and subscription: [insert]  
ChatGPT Box app/plugin identifier: [if available]  
Box integration name, Integration ID, Client ID, and App ID: [available identifiers]  
Initial connection and most recent reconnection dates: [insert]  
Connection method: [standard Box app / custom MCP]

### 1. Initial and idle-period access

Despite not using individual-user sync, does this connection perform initial crawling, incremental retrieval, polling, change-event subscriptions, or pre-fetching? Identify requests made when conversations, Library, previews, and automations are inactive. Distinguish authentication/session maintenance from retrieval of content, metadata, and access-control information.

### 2. Internal storage and retention

Separately from conversation content, does OpenAI retain Box content, metadata, ACLs, search indexes, embeddings, or caches? Specify location, scope, retention, refresh conditions, and deletion behavior following permission revocation or disconnection.

### 3. Box-specific migration history

Provide the Enterprise availability period for Box sync, migration start and completion dates, and the start and completion criteria for deletion of legacy synced data. Explain the relationship to the March 27 app update, April MCP Apps expansion, August individual-sync retirement, and September Library expansion, including the dates applied to our connection.

### 4. Administrator-managed sync and exceptions

We did not find Box setup instructions in the current administrator-managed sync documentation. Does our workspace support any Box administrator-managed indexed source, legacy connection, limited release, or regional exception? Where applicable, specify its scope and limits.

### 5. Request routing and exposed tools

Describe the routes used for search, content retrieval, Library browsing, previews, and writes, including any direct API or file-transfer paths outside MCP. Provide our Box-side integration identifiers, the tools actually exposed to the standard app, and differences from a custom remote MCP connection.

### 6. Box AI selection and controls

Under what conditions do searches, summaries, comparisons, and extraction requests invoke Box AI? Can Box’s per-integration tool controls block these calls while retaining ordinary search and retrieval? Identify any equivalent processing through other tools or non-MCP paths and explain how it is controlled.

### 7. Limits, freshness, and information for Box

Provide standard-app-specific limits on file count, file size, total retrieval, and frequency, together with freshness targets for updates, deletions, and permission changes. Explain where individual Box AI tool limits and general Box search restrictions apply. Supply the integration identifiers needed for Box to confirm billing and contractual allowance accounting.

### 8. Audit coverage and testing

Explain how to identify Box app calls using the current Compliance Logs interface and correlate them with Box reports. Describe exclusions, delays, and granularity limitations for idle-period activity, authentication refreshes, and non-chargeable calls. Please use the current conversation-log access method.

Please distinguish general product specifications from the configuration applied to our workspace. Include official references or dated technical explanations and identify questions that require confirmation from Box.

Thank you.

---

## 8. Boxサポートへの追加問い合わせ文案（日本語）

**未送信の文案。課金・契約枠・Box側管理機能はBoxへ直接確認する。**

**件名：ChatGPT標準Box連携のAPI計量・AI Units・実効ツール設定・レポート網羅性の確認**

Boxサポートご担当者様

当社のChatGPT標準Box連携について、公開料金規則およびMCP管理機能を確認したうえで、以下の実適用をご確認ください。

対象：Box Enterprise ID［記入］／プラン［記入］／連携名・Integration ID・Client ID・App ID［記入］／認証方式・ユーザー［記入］／検証期間とタイムゾーン［記入］

1. 当該接続は「Box Integrations Centerの公開アプリ＋本人OAuth」のAPI非課金条件に該当しますか。非課金コールは月間API契約枠へ算入されますか。追加Integration Credentialsや独自接続ではどう変わりますか。
2. 当該MCP接続に適用されるレート制限の単位・上限を教えてください。同一ユーザー、別のMCP連携、一般Box APIとの制限枠共有はありますか。
3. 当該連携で有効なBox AI系ツールと、実行時のAI Units計量を確認してください。公開資料にある将来の公開MCPアプリ向け計量変更が、当社へ適用済みの例外として存在する場合は、適用日と根拠をご提示ください。
4. 当該連携のGlobal／Customの実効設定と、通常の検索・取得を残してAI系ツールを無効化する方法を確認してください。他カテゴリや別経路のAI処理がある場合も教えてください。
5. 非課金MCP、認証更新、ツール実行、AI利用のそれぞれについて、どのレポートに何が記録されますか。Platform Activityの非課金レコードの数量、Box AI APIの除外、反映遅延、共通識別子、取得可能なログの限界をご説明ください。

公開一般仕様と当社契約への適用結果を分けてご回答ください。

---

## 9. 公式出典一覧

**全出典の閲覧・再確認日：2026-10-07。** 「更新」はページの最終更新表示、「公開／項目日」は記事またはリリースノートの該当発表日を指す。英語ブログの公開日を日本語公式の翻訳注記で確認した場合は、その確認方法を明記した。

| ID | 公式資料 | 日付・確認対象 |
|---|---|---|
| [S01] | OpenAI — Box app and setup in ChatGPT | 更新表示：10 days ago。正確な更新日は未確定。 |
| [S02] | OpenAI — Administrator-managed apps with sync in ChatGPT | 更新表示：yesterday。正確な更新日は未確定。 |
| [S03] | OpenAI — More ways to work with your team and tools in ChatGPT | 公開：2025-09-25。Boxの事前同期はRecent updates。 |
| [S04] | OpenAI — ChatGPT Enterprise and Edu release notes | 対象項目：2026-03-27、2026-08-10。停止予定日8月14日も本文で確認。 |
| [S05] | OpenAI — ChatGPT — Release Notes | 対象項目：2026-03-27、2026-09-10。 |
| [S06] | Box — Box expands MCP Apps to ChatGPT, M365 Copilot, and Glean | 原文日付：2026-04-15。S07の公式翻訳注記で確認。 |
| [S07] | Box Japan — Box、MCPアプリのサポート対象をChatGPT、Microsoft 365 Copilot、Gleanに拡大 | 公開：2026-04-21。英語原文は2026-04-15と明記。 |
| [S08] | Box — Box and OpenAI to bring enterprise content directly into ChatGPT | 原文日付：2026-09-10。S09の公式翻訳注記で確認。 |
| [S09] | Box Japan — BoxとOpenAI、企業コンテンツをChatGPTに直接統合 | 公開：2026-09-11。英語原文は2026-09-10と明記。 |
| [S10] | Box — Set up ChatGPT with Box MCP Server | 更新：2026-09-02。 |
| [S11] | Box — About Box MCP server | 更新：2026-08-07。 |
| [S12] | Box Developer — Box MCP server | 更新：2026-09-10。 |
| [S13] | Box Developer — Self-hosted Box MCP server (legacy) | 更新：2026-09-04。 |
| [S14] | Box — Box MCP Server pricing | 更新：2026-08-20。 |
| [S15] | Box Developer — Available tools | 更新：2026-09-02。個別ツールとURL転送の説明を確認。 |
| [S16] | Box Developer — Box API rate limits | 更新：2026-09-14。 |
| [S17] | Box — MCP Server Activity Report | 更新：2026-07-14。 |
| [S18] | Box — Platform Activity Report | 更新：2026-08-07。 |
| [S19] | Box — AI Units Report | 更新：2026-08-11。 |
| [S20] | Box — User Activity Report | 更新：2026-08-28。 |
| [S21] | OpenAI — Connected apps in ChatGPT | 更新表示：yesterday。正確な更新日は未確定。 |
| [S22] | Box — Manage tool access for Box MCP Server | 更新：2026-09-03。 |
| [S23] | Box — Understanding Box AI Usage: Daily Quotas and AI Units | 更新：2026-09-10。MCP Partners IntegrationsのCurrent／Futureを区別。 |
| [S24] | OpenAI — Admin controls, security, and compliance for plugins and apps | 更新表示：4 hours ago。正確な更新日時は未確定。 |
| [S25] | OpenAI — OpenAI Compliance Platform for Enterprise and Edu customers | 更新表示：18 days ago。本文の2026-03-05／06-05と30日保持を確認。 |
| [S26] | Box Developer — Permission-aware access | 更新：2026-09-10。 |
| [S27] | Box Developer — Search indexing | 更新：2026-08-28。Box自身の検索索引についての説明。 |
| [S28] | Box — Dates and times in report data | 更新：2026-07-24。個別レポートの時刻仕様も併せて確認。 |
| [S29] | Box Developer — Set up Box MCP server | 更新：2026-08-28。 |
| [S30] | Box — MCP frequently asked questions | 更新：2026-07-22。契約・ツール利用条件の補助確認。 |

### 更新時の注意

公式ヘルプは更新されるため、本報告は上記確認日時点の公開説明に基づく。将来の再確認では、とくに料金のCurrent／Future、Box専用の同期FAQ、管理者ツール制御、監査ログの仕様を優先して見直す。製品の更新日を、そのまま対象環境の変更日とは扱わない。

[S01]: https://help.openai.com/en/articles/12368225-box-app-and-setup-in-chatgpt
[S02]: https://help.openai.com/en/articles/10847137-administrator-managed-apps-with-sync-in-chatgpt
[S03]: https://openai.com/index/more-ways-to-work-with-your-team/
[S04]: https://help.openai.com/en/articles/10128477-chatgpt-enterprise-and-edu-release-notes
[S05]: https://help.openai.com/en/articles/6825453-chatgpt-release-notes
[S06]: https://blog.box.com/box-expands-mcp-apps-chatgpt-m365-copilot-and-glean
[S07]: https://japan.box.com/blog/box-expands-mcp-apps-chatgpt-m365-copilot-and-glean
[S08]: https://blog.box.com/box-chatgpt-enterprise-content-integration
[S09]: https://japan.box.com/blog/box-chatgpt-enterprise-content-integration
[S10]: https://docs.box.com/en/box-mcp/configuring-box-mcp-server/chatgpt
[S11]: https://docs.box.com/en/box-mcp/about-box-mcp-server
[S12]: https://developer.box.com/guides/box-mcp
[S13]: https://developer.box.com/guides/box-mcp/self-hosted
[S14]: https://docs.box.com/en/box-mcp/pricing
[S15]: https://developer.box.com/guides/box-mcp/tools
[S16]: https://developer.box.com/guides/api-calls/permissions-and-errors/rate-limits
[S17]: https://docs.box.com/en/box-admin-tools/reporting-and-insights/mcp-server-activity-report
[S18]: https://docs.box.com/en/box-admin-tools/reporting-and-insights/platform-activity-report
[S19]: https://docs.box.com/en/box-admin-tools/reporting-and-insights/ai-units-report
[S20]: https://docs.box.com/en/box-admin-tools/reporting-and-insights/user-activity-report
[S21]: https://help.openai.com/en/articles/11487775-connected-apps-in-chatgpt
[S22]: https://docs.box.com/en/box-mcp/admin-controls
[S23]: https://docs.box.com/en/box-ai/understanding-ai-units-in-box
[S24]: https://help.openai.com/en/articles/11509118-admin-controls-security-and-compliance-for-plugins-and-apps
[S25]: https://help.openai.com/en/articles/9261474-openai-compliance-platform-for-enterprise-and-edu-customers
[S26]: https://developer.box.com/guides/box-mcp/permission-aware-access
[S27]: https://developer.box.com/guides/search/indexing
[S28]: https://docs.box.com/en/box-admin-tools/reporting-and-insights/dates-and-times-in-report-data
[S29]: https://developer.box.com/guides/box-mcp/setup
[S30]: https://docs.box.com/en/box-mcp/faq
