# Codex `requirements.toml` 設定項目一覧（会社PC向け）

**調査日:** 2026-08-25  
**再調査範囲:** 実験的ネットワーク、権限プロファイルのネットワーク制御、native Windowsサンドボックス、管理フック、および制御が実効化するための主要な前提条件  
**対象:** ChatGPT Business / Enterprise のクラウド管理ポリシー、および対応するCodexローカルクライアント  
**基準:** OpenAIが公開している `requirements.toml` リファレンスを正とし、同リファレンスから明示的に参照される Permissions、Hooks、承認・サンドボックスの公式資料で下位スキーマを補完。

> **重要:** この資料は `config.toml` の全項目一覧ではない。`requirements.toml` で管理者が強制できる公開項目と、その項目から参照される下位設定だけを扱う。公開 `requirements.toml` リファレンスにないキーは、実装上存在して見える場合でもクラウドポリシーでの正式サポートが **不明** であるため、本番ポリシーには使用しない。

> **読み方:** 「説明」は公開仕様の効果を初心者向けに言い換えたものである。「セキュリティ／運用上の注意」には、公開仕様に明記された制約に加え、設定の性質から必要となる一般的な運用確認を含む。公開資料で確認できない製品動作は **不明** と記載する。

## 最初に理解すべき適用ルール

この表は、`requirements.toml` がどの端末・クライアントに適用され、複数の設定源がある場合にどの値が優先されるかを理解するためのものである。設定を省略した場合の挙動、クライアントの最低バージョン、取得失敗時の動作も含め、会社で安全に配布する前提を整理する。

| 項番 | 論点 | 内容 | 会社導入時の意味 |
| --- | --- | --- | --- |
| 1 | 強制設定と既定値の違い | `requirements.toml` は管理者が変更不可の上限・禁止条件を強制する設定である。`managed_config.toml` は起動時の初期値を配る設定であり、ユーザーが実行中に変更できる。 | 禁止事項や必須条件は `requirements.toml` に置き、操作性のための推奨初期値は `managed_config.toml` に分ける。両者を同じ強制設定として扱わない。 |
| 2 | 省略したキー | キーを省略しても機能は自動的に禁止されず、「管理者による制約なし」となる。実際の動作は製品の可用性、ユーザー設定、プロジェクト設定などで決まる。 | 禁止したい機能は、該当キーを `false` にするか、許可リストを明示して閉じる。省略を禁止の代わりに使わない。 |
| 3 | 対象クライアント | 対象はChatGPTデスクトップアプリ、Codex CLI、IDE拡張などの対応ローカルクライアントである。利用できるキーはクライアント種別とバージョンにより異なる。 | 全社配布前に、利用OS、クライアント種別、バージョンの組合せごとに設定が実際に効くかを試験する。 |
| 4 | 権限プロファイルの最低バージョン | `allowed_permission_profiles` と管理された `default_permissions` は Codex 0.138.0 以降で有効である。0.137.0以前のクライアントはこれらを無視する。 | 全端末を0.138.0以上へ更新してから権限プロファイルを主制御にする。旧版が残る期間だけ `allowed_sandbox_modes` を互換制約として併用する。 |
| 5 | 推奨する権限制御 | 0.138.0以降では、ファイルとネットワークの権限をまとめて扱える `allowed_permission_profiles` と `default_permissions` を優先する。`allowed_sandbox_modes` は旧 `sandbox_mode` 利用環境向けである。 | 新規導入は権限プロファイルを基準に設計し、旧方式との二重管理を長期化させない。 |
| 6 | クラウドポリシーの位置付け | クラウド管理ポリシーは、`requirements.toml` と同等の制約を端末へ配布する仕組みである。ChatGPTワークスペースへのアクセス付与、座席割当、ロール管理を行う仕組みではない。 | ワークスペース側の利用権限と、端末上でCodexが実行できる操作権限を別々に設計・監査する。 |
| 7 | クラウド取得失敗時 | 有効な署名済みキャッシュがなく、クラウド要件の取得にも失敗した場合、クライアントは要件なしで起動せずエラーとなる。バックグラウンド更新は次回起動用であり、現在のプロセスには反映されない。 | ポリシー取得失敗時に無制約で起動するフェイルオープンではない。ネットワーク遮断時、キャッシュ失効時、再起動時の挙動を事前に試験する。 |
| 8 | 要件の優先順位 | 要件の優先順位は低い順に、①システム `requirements.toml`、②クラウド管理要件、③旧 `managed_config.toml` の要件互換フィールド、④macOS MDM `requirements_toml_base64` である。 | 同じキーが複数の配布元にある場合は上位層が優先される。意図しない上書きを防ぐため、すべての配布元と設定値を台帳化する。 |
| 9 | マージ方法 | 通常の単一値と配列は上位層が置き換え、テーブルはキー単位で結合される。Rules、Hooks、ファイルシステム制約などは、それぞれ固有の合成規則を持つ。 | すべての設定が同じ方法で上書きされると考えない。複数ポリシーを割り当てた状態で、最終的に有効になる値を実機で確認する。 |
| 10 | `models.new_thread` | `models.new_thread` は新規スレッドの管理既定値であり、絶対に変更できない強制設定ではない。明示的なCLIフラグや `--config` 選択で上書きできる。 | モデルや推論努力の標準化には使えるが、特定モデル以外を禁止するセキュリティ制御としては使わない。 |

## 重要な制御の前提条件・依存関係

この表は、個別のキーを記述するだけでは制御が実効化しない設定について、同時に必要となる設定、クライアントやOSの条件、満たさない場合の影響をまとめるものである。初心者が「設定したので安全になった」と誤認しやすい組合せを優先している。

| 項番 | 制御 | 実効化の前提条件 | 前提を満たさない場合 | 導入時の確認 |
| --- | --- | --- | --- | --- |
| 1 | `requirements.toml` による強制 | 対象クライアントがそのキーと配布経路に対応し、有効な要件を取得・読込みできることが必要である。 | 未対応キーは期待どおり強制されない可能性がある。省略したキーは原則として「禁止」ではなく「未制約」となる。 | OS、クライアント種別、バージョン、配布元、最終的な実効値を台帳化し、許可・拒否の両方を実機試験する。 |
| 2 | 権限プロファイル | Codex 0.138.0以上が必要である。権限プロファイル方式と旧 `sandbox_mode` / `sandbox_workspace_write` は同一セッションで合成されないため、旧設定を除去する必要がある。管理された `allowed_permission_profiles` は権限プロファイル方式を選ばせる例外である。 | 0.137.0以前では管理された権限プロファイルが無視される。旧設定が残ると、想定した `default_permissions` ではなく旧サンドボックス設定が使われる可能性がある。 | 全端末の更新完了後に主方式を切り替える。混在期間だけ `allowed_sandbox_modes` を互換制約として残し、恒久的な二重管理にしない。 |
| 3 | `default_permissions` | 指定する組込み／カスタムプロファイルが読み込まれ、`allowed_permission_profiles` で許可されている必要がある。 | 許可されていない名前や未定義名を指定すると、期待した既定権限を適用できない。省略時の既定値も許可リストの内容に依存する。 | `default_permissions` を明示し、同じ名前を `allowed_permission_profiles` と `[permissions.<name>]` で整合させる。 |
| 4 | 承認ポリシー | 承認はサンドボックスや権限プロファイルを越える操作を人または自動レビューへ確認する仕組みであり、権限境界そのものではない。 | `never` を許可したり、`:danger-full-access` と組み合わせたりすると、人が止める機会または境界が弱くなる。 | 承認、権限プロファイル、コマンドルール、秘密情報の読取拒否を組み合わせて試験する。承認だけを安全境界にしない。 |
| 5 | ローカルコマンドのネットワーク制御 | ①選択中の権限プロファイルで `network.enabled = true` とし、②ネットワークプロキシを有効にして宛先ルールを強制する、という二段階が必要である。管理要件では `experimental_network.enabled = true` がプロキシを起動できる。 | 通信許可がOFFならプロキシを有効にしても通信できない。通信許可がONでもプロキシがOFFなら、ドメインルールは効かず直接の無制限通信となる。 | 「通信OFF／ON」と「プロキシOFF／ON」の4通りを試験し、許可ホスト、拒否ホスト、IP直指定、ローカル宛先を確認する。 |
| 6 | `[experimental_network]` | `experimental_network.enabled = true`、管理者のallow規則、対象OS・クライアントでの動作確認が必要である。`managed_allowed_domains_only = true` は管理allow規則と同時に使う。 | allowリストだけを書いてもプロキシは起動しない。管理allow規則なしで管理者許可のみを強制すると、ユーザー追加allowも有効にならず必要通信が失敗する。 | 実験的機能であり、特にWindows対応は限定的である。全社一括配布せず、OS・クライアント・サンドボックス実装ごとにパイロットする。 |
| 7 | ネットワーク面の分離 | `experimental_network` と権限プロファイルのドメイン規則が対象にするのは、サンドボックス内のローカルコマンド通信だけである。 | Web検索、Apps／コネクタ、MCP、ブラウザー、Computer Use、Codexサービス通信、Codex cloudの通信を同時に制限したと誤認する。 | `allowed_web_search_modes`、`features.apps`、`mcp_servers`、ブラウザー／Computer Useの各機能フラグ、クラウド環境設定を別々に設計する。 |
| 8 | native Windows `elevated` | Windows 11が推奨であり、`winget`、管理者承認付きセットアップ、ローカルユーザー／グループ作成、ファイアウォール規則変更、サンドボックスユーザーのログオン権限が必要である。 | セットアップが失敗し、`allowed_sandbox_implementations = ["elevated"]` では許可されたフォールバックが残らない。正確な画面表示や失敗範囲はクライアントにより異なり、公開資料では一律に示されていない。 | UAC、GPO／OU、EDR、ローカルセキュリティポリシーを確認する。エラー1385、Everyone書込可能フォルダー、サンドボックスログを確認する。 |
| 9 | native Windows `unelevated` | 現在のユーザーから作る制限付きトークンとACLで境界を構成できることが前提である。`elevated` 特有の管理者承認セットアップを使えない場合のフォールバックである。 | 専用の低権限ユーザー境界と専用ファイアウォール規則を使わず、ネットワーク分離が弱い。すべてのread/write分割を強制できず、未対応ポリシーは拒否される。 | 一時的な例外として期限と対象端末を管理する。`experimental_network` の機能別・プロトコル別の同等性は公開されておらず **不明** であるため、負の試験を行う。 |
| 10 | 管理フック | `[features].hooks = true`、`[hooks]`、管理スクリプトの別配布、一般ユーザーが変更できない絶対パスが必要である。管理フックだけに絞る場合は `allow_managed_hooks_only = true` も必要である。 | フック定義だけではスクリプト本体が存在せず動作しない。非管理フックを残すと、ユーザーやプロジェクトが独自処理を差し込める。 | 所有権／ACL、署名・ハッシュ、タイムアウト、障害時の許可／拒否、並行実行、出力保存を確認する。 |
| 11 | MCPツールフック | 既に接続済みのMCPサーバーと利用可能なツールが必要である。MCPツールフック自身はサーバーを起動・再接続しない。 | サーバー未接続、ツール未提供、呼出しエラーでも、公開仕様上は元の操作を自動的にはブロックしない。 | セキュリティ上必ず止める検査には、MCPツールフック単独で依存しない。MCP許可リスト、接続監視、同期commandフック等を組み合わせる。 |
| 12 | `permissions.filesystem.deny_read` | OSと実行経路が管理読取拒否を強制できることが必要である。 | native Windowsでは直接ファイルツールには適用されるが、シェル子プロセスの読取りには同じ制約が適用されない。 | NTFS ACL、資格情報保管方式、EDR／DLPで補完し、PowerShell・cmd・各種ランタイムからの読取試験を行う。 |
| 13 | 更新制御 | クライアント自身の更新またはMDM等の中央更新のどちらかが、担当者・期限・失敗検知を含めて運用されている必要がある。 | `check_for_update_on_startup = false` とアプリ内更新無効を同時に設定し、中央更新もなければ脆弱性修正が遅延する。 | `check_for_update_on_startup` と `features.in_app_updates` を更新方式と整合させ、更新SLAとロールバック手順を定める。 |
| 14 | `log_dir` | 保存先のACL、ディスク暗号化、保持・削除、転送先を設計する必要がある。 | `log_dir` の明示設定により平文TUIログも有効になり、会話、パス、コマンド等が想定外に保持される可能性がある。 | 保存内容を実機で確認し、最小権限、保持期間、SIEM転送、個人情報・機密情報の取扱いを定める。 |

## 表記

この表は、後続の設定表で使う置換記号、TOML構造、主要な技術用語の読み方を示すものである。`<id>` などはそのまま記述する文字ではなく、組織で実際に使用する値へ置き換えるためのプレースホルダーである。

| 項番 | 表記 | 意味 |
| --- | --- | --- |
| 1 | `<id>` | アプリIDまたはMCPサーバーIDを表す置換記号である。`<id>` の文字列をそのまま書かず、実際の設定名へ置き換える。 |
| 2 | `<name>` | 管理者が付けるルール名またはカスタム権限プロファイル名を表す置換記号である。用途が分かる一意な名前へ置き換える。 |
| 3 | `<tool>` | アプリ／MCPが提供するツール名を表す置換記号である。ツール名に `/` などが含まれる場合は、TOMLの引用符付きキーを使う。 |
| 4 | `<plugin>` | プラグインIDを表す置換記号である。プラグイン同梱MCPの設定では、実際のプラグインIDへ置き換える。 |
| 5 | `<server>` | プラグインに同梱されるMCPサーバーIDを表す置換記号である。実際のサーバーIDへ置き換える。 |
| 6 | `<Event>` | フックを実行するイベント名を表す置換記号である。`PreToolUse` など、後述のイベント名へ置き換える。 |
| 7 | `[]` | 配列内の1要素を表す記号である。例として `remote_sandbox_config[]` は、`remote_sandbox_config` 配列の各設定行を意味する。 |
| 8 | `table` | TOMLの親テーブルまたは設定グループを表す。親テーブル名だけでは通常動作せず、その配下に具体的なキーを設定する。 |
| 9 | 「完全許可リスト」 | 表に `true` と記載した項目だけを許可し、省略または `false` の項目を拒否する方式である。将来追加される未記載項目も自動的に拒否される。 |
| 10 | 「設定例」 | 各セルに、`requirements.toml` へ記述するTOML断片を示す。`<id>`、`<name>`、`<tool>`、`<plugin>`、`<server>`、モデルID、ドメイン、URL、パスなどは組織の実値へ置き換え、複数行は `<br>` で区切る。 |
| 11 | MDM | Mobile Device Managementの略である。会社PCへ設定、アプリ、証明書などを一括配布・管理する仕組みを指す。 |
| 12 | RBAC | Role-Based Access Controlの略である。利用者の役割に応じて、利用できる機能やデータを制限する方式である。 |
| 13 | MCP | Model Context Protocolの略である。Codexへ外部ツールやデータ接続を追加するための仕組みである。 |
| 14 | EDR | Endpoint Detection and Responseの略である。会社PC上の不審な挙動を検知し、調査・対応するセキュリティ製品を指す。 |
| 15 | DLP | Data Loss Preventionの略である。機密情報や個人情報の持ち出し・誤送信を検知または防止する仕組みである。 |
| 16 | ACL | Access Control Listの略である。ファイルやディレクトリを、誰が読み書きできるかを定めるアクセス権の一覧である。 |
| 17 | FQDN | Fully Qualified Domain Nameの略である。例として `host.example.com` のように、ホスト名とドメイン名を省略せず表す名前である。 |
| 18 | SIEM | Security Information and Event Managementの略である。複数の端末やサービスのログを集約し、監視・分析する仕組みである。 |

## 基本・承認・検索・更新・保存先

この表は、会社PCでCodexを利用する際の基本的な安全設定を決めるものである。操作時に承認を求めるか、Web検索や画面・端末操作を使えるか、ログインシェル、更新、フィードバック、モデルの既定値、ログやローカル状態の保存先などをどう扱うかを設定する。

| 項番 | 設定キー | 対象 | 値 | 型・許可値 | 設定例（TOML） | 制御の性質 | 説明 | 初心者向けの意味 | 推奨・注意 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `allow_appshots` | Appshots | `true` / `false` | `boolean` | `allow_appshots = false` | 正確値強制 | 画面やアプリの状態を画像として扱うAppshots機能を、管理対象ユーザーが利用できるか固定する。`false` で機能を無効化する。 | Codexに画面・アプリの画像情報を取り込ませるかを決める設定である。 | 業務上の利用目的と画面情報の取扱規程が明確でない場合は `false`。 | 画面上の機密情報や個人情報が文脈に含まれる可能性がある。省略は許可ではなく未制約であるため、組織方針上使わせない場合は明示的に `false` とする。 |
| 2 | `allow_login_shell` | ログインシェル | `true` / `false` | `boolean` | `allow_login_shell = false` | 正確値強制 | シェル系ツールがログインシェルを起動できるか固定する。ログインシェルは、ユーザーのプロファイルやシェル起動スクリプトを読み込む可能性がある。 | 通常のコマンド実行時に、ユーザー固有のシェル設定まで読み込ませるかを決める設定である。 | 一般的な会社PCでは `false`。業務ツールがログインシェルを前提とする場合だけ例外検証する。 | シェル初期化ファイルから資格情報、環境変数、別コマンドが持ち込まれる面を減らすため、通常は `false` とする。無効化によるPATHや開発環境への影響は実機で確認する。 |
| 3 | `allow_managed_hooks_only` | 管理フック | `true` / `false` | `boolean` | `allow_managed_hooks_only = true` | 正確値強制 | `true` のとき、ユーザー、プロジェクト、セッション、プラグイン由来のフックを無視し、管理者が配布したフックだけを実行対象にする。フックは、ツール実行前後などに自動実行するスクリプトである。 | 利用者が独自の自動スクリプトを追加できないようにし、会社管理の検査スクリプトだけを動かす設定である。 | 会社でフックを使用する場合は `true`。フック自体を使わない場合は `[features].hooks = false`。 | このキーだけでは管理フックは動作しない。`[features].hooks = true`、`[hooks]` の設定、管理スクリプトの安全な配布と書込権限管理が必要である。 |
| 4 | `allow_remote_control` | デバイス／リモートコントロール | `true` / `false` | `boolean` | `allow_remote_control = false` | 正確値強制 | 端末のデバイス・リモートコントロール機能を利用できるか固定する。`false` で当該機能を無効化する。 | Codexから端末を遠隔操作するための機能を使わせるかを決める設定である。 | リモート操作を業務利用しない組織では `false`。 | 有効化すると端末操作の範囲と監査対象が広がる。なお、これはSSHによるリモート接続を無効化する設定ではないため、SSHは別の端末・ネットワーク統制で管理する。 |
| 5 | `allowed_approval_policies` | 承認ポリシー | `untrusted` | `array<string>`: `untrusted`, `on-request`, `never`, `granular` | `allowed_approval_policies = ["untrusted"]` | 許可リスト | 承認ポリシーとして `untrusted` を選択できるようにする。既知の安全な読み取り操作は自動実行し、それ以外のコマンドや状態変更につながる操作では承認を求める。 | 安全と判断できる閲覧だけを自動化し、判断が難しい操作は利用者へ確認するモードである。 | 確認を多めにしたい環境向け。安全判定だけに依存せず、権限プロファイルやサンドボックスと併用する。 | 許可外のポリシー指定は互換値へフォールバックし、ユーザーへ通知される。`never` を同時に許可すると確認なしの選択肢が残るため、一般端末では `untrusted` と `on-request` だけに絞る。 |
| 6 | `allowed_approval_policies` | 承認ポリシー | `on-request` | `array<string>`: `untrusted`, `on-request`, `never`, `granular` | `allowed_approval_policies = ["on-request"]` | 許可リスト | 承認ポリシーとして `on-request` を選択できるようにする。サンドボックス内の操作は自動実行し、ワークスペース外への書き込みやネットワーク利用など、権限境界を越える場合に承認を求める。 | 通常の作業は自動で進め、会社PCの保護範囲を越えようとしたときだけ確認するモードである。 | 会社PCの一般的な初期値として扱いやすい。権限境界を狭く設計した上で使う。 | 承認が必要になる範囲はサンドボックスや権限プロファイルの設計に依存する。`danger-full-access` を許可すると確認対象となる境界自体が弱くなるため、通常は組み合わせない。 |
| 7 | `allowed_approval_policies` | 承認ポリシー | `never` | `array<string>`: `untrusted`, `on-request`, `never`, `granular` | `allowed_approval_policies = ["never"]` | 許可リスト | 承認ポリシーとして `never` を選択できるようにする。承認プロンプトを表示せず、あらかじめ許可された権限境界内で実行を試みる。 | 操作のたびに人へ確認せず、自動実行を優先するモードである。 | 対話型の会社PCでは通常許可しない。無人処理で使う場合も、読み取り専用など極めて狭い権限に限定する。 | 承認が一切表示されないため、誤操作や悪意ある入力を人が止める機会がなくなる。特に `danger-full-access` との組合せは避ける。 |
| 8 | `allowed_approval_policies` | 承認ポリシー | `granular` | `array<string>`: `untrusted`, `on-request`, `never`, `granular` | `allowed_approval_policies = ["granular"]` | 許可リスト | 承認ポリシーとして `granular` を選択できるようにする。サンドボックス昇格、コマンドルール、MCP、権限要求、スキルスクリプトなどの承認カテゴリを個別に扱う。 | 操作の種類ごとに、確認するか自動実行するかを細かく分けるモードである。 | `requirements.toml` では `granular` を選べるかだけを制御する。カテゴリ別の具体値はユーザー側設定であり、公開要件スキーマにはない。 | カテゴリ別設定が利用者側に残るため、組織として期待する承認動作を固定できるとは限らない。対象クライアントで実効設定を確認する。 |
| 9 | `allowed_approvals_reviewers` | 承認レビュー担当 | `user` | `array<string>`: `user`, `auto_review` | `allowed_approvals_reviewers = ["user"]` | 許可リスト | 承認要求のレビュー担当として `user` を許可する。対象操作を人間の利用者へ提示し、承認または拒否を判断させる。 | 危険性のある操作を実行する前に、人が画面で確認する方式である。 | 人の判断を必須にしたい場合に使用する。承認疲れを避けるため、不要な要求が出ないよう権限境界とルールを調整する。 | 利用者が内容を理解せず承認する運用にならないよう、承認画面の理由、教育、拒否時の手順を整備する。自動レビューも許可する場合は、どちらが選択されるかを実機で確認する。 |
| 10 | `allowed_approvals_reviewers` | 承認レビュー担当 | `auto_review` | `array<string>`: `user`, `auto_review` | `allowed_approvals_reviewers = ["auto_review"]` | 許可リスト | 承認要求のレビュー担当として `auto_review` を許可する。承認対象の操作を自動レビュー用エージェントへ渡し、組織ポリシーに照らして実行可否を評価させる。 | 人の代わりに別のAIレビューが操作内容を確認する方式である。 | 自動化に有効だが追加のモデル利用量が発生する。組織固有の判断基準は `guardian_policy_config` に記述する。 | `["auto_review"]` のみを許可すると自動レビューが必須になる。レビュー処理または解析に失敗した場合は閉じた側に失敗し、対象操作は実行されない。誤判定時の調査手順も用意する。 |
| 11 | `allowed_permission_profiles` | 権限プロファイル | プロファイル名ごとの `true` / `false` | `table<boolean>` | `[allowed_permission_profiles]`<br>`":read-only" = true`<br>`":workspace" = true`<br>`":danger-full-access" = false` | 完全許可リスト | ユーザーが選択できる組込み／カスタム権限プロファイルを、完全許可リストとして定義する。権限プロファイルは、ファイルの読み書き範囲とネットワーク利用範囲をまとめた権限セットである。 | 利用者が選べる「読み取り専用」「作業フォルダーへ書き込み可」などの権限パッケージを限定する設定である。 | 通常は `:read-only` と `:workspace` だけを許可し、`:danger-full-access` は `false` または省略する。 | テーブルを置いた時点で、省略または `false` のプロファイルは将来追加分も含め拒否される。Codex 0.138.0以上が必要であり、旧版では無視される。 |
| 12 | `allowed_permission_profiles.<name>` | 組込み権限プロファイル | `:read-only` | `boolean` | `[allowed_permission_profiles]`<br>`":read-only" = true` | 完全許可リストの要素 | 組込み権限プロファイル `:read-only` を許可または禁止する。許可すると、ローカルコマンドによるファイル変更を原則禁止した状態を選択できる。 | コードやファイルを見せるだけで、書き換えさせない作業モードである。 | コードレビュー、調査、初回導入の安全側プロファイルとして許可する。 | 読み取り専用でも、読み取った内容がモデルや外部連携へ渡る可能性は別途管理が必要である。上位要件層の `false` は下位層の許可を無効化できる。 |
| 13 | `allowed_permission_profiles.<name>` | 組込み権限プロファイル | `:workspace` | `boolean` | `[allowed_permission_profiles]`<br>`":workspace" = true` | 完全許可リストの要素 | 組込み権限プロファイル `:workspace` を許可または禁止する。許可すると、現在のワークスペースルートとシステム一時ディレクトリ内への書き込みを認める。 | 開いているプロジェクト内で、コードの編集やファイル作成を行える通常開発モードである。 | 一般的な開発作業向け。必要に応じて `.env`、資格情報、管理ファイルを追加の `deny` で保護する。 | ワークスペース内に秘密情報を置いている場合は、そのファイルも書込み・読取り対象になり得る。カスタムプロファイルまたは `permissions.filesystem.deny_read` で機密パスを除外する。 |
| 14 | `allowed_permission_profiles.<name>` | 組込み権限プロファイル | `:danger-full-access` | `boolean` | `[allowed_permission_profiles]`<br>`":danger-full-access" = true` | 完全許可リストの要素 | 組込み権限プロファイル `:danger-full-access` を許可または禁止する。許可すると、ローカルサンドボックスによるファイル・コマンド実行の制限を外す。 | Codexへ端末上の広い操作権限を与える、最も危険なモードである。 | 通常の会社PCでは完全許可リストから省略するか `false` とする。 | 誤操作、悪意あるプロンプト、外部コンテンツの指示が端末全体へ影響し得る。承認ポリシーがあっても安全境界が弱くなるため、例外利用は隔離端末と期限付き運用に限定する。 |
| 15 | `allowed_sandbox_modes` | 旧サンドボックス | `read-only` | `array<string>`: `read-only`, `workspace-write`, `danger-full-access` | `allowed_sandbox_modes = ["read-only"]` | 許可リスト（旧方式） | 旧 `sandbox_mode` 方式で、`read-only` を選択可能にする。ローカルコマンドはファイルを読み取れるが、原則として変更できない。 | 旧版Codexで使う、閲覧中心の安全側モードである。 | 旧版との混在期間の調査・レビュー用途に限定する。編集が必要な場合は承認による昇格要求が出ることがある。 | 新規導入では権限プロファイルを優先する。旧方式を長期運用すると、ファイルとネットワークの制御が分散しやすい。 |
| 16 | `allowed_sandbox_modes` | 旧サンドボックス | `workspace-write` | `array<string>`: `read-only`, `workspace-write`, `danger-full-access` | `allowed_sandbox_modes = ["workspace-write"]` | 許可リスト（旧方式） | 旧 `sandbox_mode` 方式で、`workspace-write` を選択可能にする。アクティブなワークスペースと一部一時領域への書き込みを許可する。 | 旧版Codexで、開いているプロジェクト内の編集を認める開発モードである。 | 旧版との混在期間の一般的なコーディング用途。`.git`、`.codex` など一部保護パスは読み取り専用となる。 | 新規は権限プロファイルを優先する。ワークスペース内の秘密情報を別途保護し、`danger-full-access` は通常除外する。 |
| 17 | `allowed_sandbox_modes` | 旧サンドボックス | `danger-full-access` | `array<string>`: `read-only`, `workspace-write`, `danger-full-access` | `allowed_sandbox_modes = ["danger-full-access"]` | 許可リスト（旧方式） | 旧 `sandbox_mode` 方式で、`danger-full-access` を選択可能にする。ローカルサンドボックス制限を外す。 | 旧版Codexで端末上の広い操作を許す、最も危険なモードである。 | 通常の会社PCでは許可しない。 | 新規は権限プロファイルを優先する。名称どおり高リスクであり、承認なしの `never` と組み合わせない。例外は隔離環境に限定する。 |
| 18 | `allowed_web_search_modes` | Web検索 | `disabled` | `array<string>`: `disabled`, `cached`, `indexed`, `live` | `allowed_web_search_modes = ["disabled"]` | 許可リスト | Web検索モードとして `disabled` のみを使う状態にする。`disabled` は常に暗黙許可され、空の許可リストでも実質的にWeb検索が無効になる。 | CodexからWeb検索を行えないようにする設定である。 | 外部検索が不要な機密環境では、空の `allowed_web_search_modes = []` または `disabled` 相当を使用する。 | Web検索を止めても、Apps、MCP、ブラウザー、シェルのネットワーク通信は別設定である。外部接続面を個別に無効化する。 |
| 19 | `allowed_web_search_modes` | Web検索 | `cached` | `array<string>`: `disabled`, `cached`, `indexed`, `live` | `allowed_web_search_modes = ["cached"]` | 許可リスト | Web検索モードとして `cached` を許可する。OpenAI管理の検索インデックスから事前取得済みの結果を返し、任意ページへのライブアクセスを行わない。 | 最新ページへ直接アクセスせず、あらかじめ用意された検索結果だけを使うモードである。 | 機密コードを扱う会社PCで検索が必要な場合の安全側候補である。 | ライブWebへの露出は減るが、検索結果自体は誤情報や悪意ある指示を含み得るため、信頼済み入力として扱わない。 |
| 20 | `allowed_web_search_modes` | Web検索 | `indexed` | `array<string>`: `disabled`, `cached`, `indexed`, `live` | `allowed_web_search_modes = ["indexed"]` | 許可リスト | Web検索モードとして `indexed` を許可する。検索インデックスによるゲートを通る場合だけ、外部ページへのアクセスを行う。 | 検索結果を確認した上で必要な外部ページへアクセスし、`cached` より新しい情報を得やすくするモードである。 | 業務上の新鮮さが必要な場合に限定し、対象データと利用者を絞る。 | `cached` より外部アクセス面が増える。取得内容を非信頼入力として扱い、機密情報を検索語や外部ページへ送らない運用を徹底する。 |
| 21 | `allowed_web_search_modes` | Web検索 | `live` | `array<string>`: `disabled`, `cached`, `indexed`, `live` | `allowed_web_search_modes = ["live"]` | 許可リスト | Web検索モードとして `live` を許可する。最新の外部ページをその場で取得する。 | 通常のブラウザー検索に近く、現在のWebページを直接読み込むモードである。 | 最も広いWeb露出となるため、機密コードを扱う会社PCでは原則禁止または限定グループのみとする。 | 外部ページのプロンプトインジェクション、追跡、誤情報、意図しないデータ送信の面が増える。検索結果とページ内容を信頼済み入力として扱わない。 |
| 22 | `check_for_update_on_startup` | 起動時の更新確認 | `true` / `false` | `boolean` | `check_for_update_on_startup = true` | 正確値強制 | Codex起動時に、新しいクライアント更新があるか確認する動作を固定する。 | Codexを開いたときに最新版の有無を自動確認させるかを決める設定である。 | クライアント自身で更新する場合は `true`。MDMなどで中央更新する場合だけ `false` を検討する。 | `false` にする場合は、脆弱性修正を遅らせない更新SLA、配布担当、失敗端末の検知手順が必要である。`features.in_app_updates` との役割差も確認する。 |
| 23 | `computer_use` | Computer Useの管理要件 | 下位キー | `table` | `[computer_use]`<br>`allow_locked_computer_use = false` | 構造 | Computer Useに関する管理要件をまとめる親テーブルである。親テーブルだけでは通常効果がなく、配下の `allow_locked_computer_use` を設定する。 | 画面操作機能に関する細かな制約をまとめる入れ物である。 | 機能全体の有効／無効は `[features].computer_use` で別途設定する。 | `[computer_use]` を書いただけではComputer Useは有効にも無効にもならない。下位キーと機能フラグを組み合わせ、端末ロック時の挙動を実機確認する。 |
| 24 | `computer_use.allow_locked_computer_use` | ロック後のComputer Use | `true` / `false` | `boolean` | `[computer_use]`<br>`allow_locked_computer_use = false` | 正確値強制 | 管理対象macOS端末がロックされた後も、実行中のComputer Useを継続できるか固定する。 | 利用者が画面をロックした後も、自動操作を続けさせるかを決める設定である。 | 通常は `false`。無人実行が必要な限定端末だけ例外検討する。 | このキーはComputer Use自体を有効化しない。`true` にすると利用者が不在でも操作が続くため、物理セキュリティ、画面ロック、監査ログ、停止手順を整備する。 |
| 25 | `default_permissions` | 既定の権限プロファイル | 許可済みプロファイル名 | `string`（許可済みプロファイル名） | `default_permissions = ":workspace"` | 管理既定値／選択 | Codexが新しい作業で標準選択する権限プロファイルを指定する。組込み名または `[permissions.<name>]` で定義したカスタム名を使う。 | 利用開始時に最初から選ばれる「読み取り専用」「プロジェクト内書き込み可」などの権限モードを決める設定である。 | 通常開発は `:workspace`、レビュー専用端末は `:read-only` を候補とする。 | 指定名は `allowed_permission_profiles` で許可されている必要がある。これは既定選択であり、許可された別プロファイルへの変更可否は許可リスト側で管理する。省略時の挙動に依存せず明示する。 |
| 26 | `enforce_residency` | データレジデンシー | 現在は `us` | `string`; 現在は `us` | `enforce_residency = "us"` | 正確値強制 | Codexサービスとの対応通信について、指定したデータレジデンシー要件を適用する。 | 対応するサービスデータを、契約上指定された地域で取り扱うよう要求する設定である。 | 利用地域、契約、法務要件が一致する場合だけ設定する。 | 公開リファレンスで確認できる値は現在 `us` のみであり、その他地域は不明である。対象となる通信や保存データの範囲を、このキーだけで判断せず契約資料で確認する。 |
| 27 | `feedback` | フィードバック送信 | 下位キー | `table` | `[feedback]`<br>`enabled = false` | 構造 | Codexクライアントからのフィードバック送信可否をまとめる親テーブルである。実際の可否は配下の `enabled` で設定する。 | 製品への意見や不具合報告をクライアントから送れるかをまとめる入れ物である。 | 親テーブルだけでなく `feedback.enabled` を明示する。 | フィードバック本文や添付内容に会話、コード、画面情報が含まれ得る運用を想定し、送信可否と社内問い合わせ窓口を決める。 |
| 28 | `feedback.enabled` | フィードバック送信 | `true` / `false` | `boolean` | `[feedback]`<br>`enabled = false` | 正確値強制 | CodexクライアントからOpenAIへフィードバックを送信できるか固定する。 | 利用者が製品画面から意見や不具合情報を外部送信できるかを決める設定である。 | ソースコードや会話を外部送信する経路を認めない組織では `false`。 | `false` にする場合は、利用者が不具合を報告できる社内サポート窓口と、必要情報を安全に収集する手順を別途用意する。 |
| 29 | `guardian_policy_config` | 自動レビューの組織ポリシー | Markdown文字列 | `string`（Markdown、複数行可） | `guardian_policy_config = "資格情報の読取りと外部送信を禁止する。"` | 正確値強制 | 自動レビュー用エージェントが承認判断に使う、組織固有のルールをMarkdownで定義する。ローカルの `[auto_review].policy` より優先される。 | AIによる自動承認に対し、「資格情報の読み取り禁止」「外部送信先の制限」など会社独自の判断基準を与える設定である。 | 禁止対象、許可宛先、破壊操作、資格情報探索、持ち出し条件を短く明確に記述する。 | 空文字は無視される。ポリシー本文へ秘密情報そのものを書かず、曖昧な表現や相反する指示を避ける。変更時は代表的な承認ケースで再試験する。 |
| 30 | `log_dir` | ローカルログ保存先 | ディレクトリパス | `string`（パス） | `log_dir = "/var/log/codex"` | 正確値強制 | Codexが端末上へ出力するローカルログの保存先ディレクトリを固定する。 | Codexの動作記録を端末のどのフォルダーへ保存するかを決める設定である。 | 管理者がアクセス権、暗号化、収集、保持、削除を管理できる専用ディレクトリを指定する。 | `log_dir` を明示すると平文TUIログ `codex-tui.log` も有効になる。会話、パス、コマンドなどが記録され得る前提で、一般ユーザーの閲覧権限、バックアップ、SIEM転送、保持期間を設計する。 |
| 31 | `model_catalog_json` | モデルカタログ | JSONファイルのパス | `string`（パス） | `model_catalog_json = "/etc/codex/models.json"` | 正確値強制 | Codexが起動時に読み込むJSON形式のモデルカタログについて、使用するファイルのパスを固定する。 | 利用候補として表示するモデル情報を、会社管理の一覧ファイルから読み込ませる設定である。 | 管理者だけが更新できる場所へ配布し、更新手順と整合性確認を設ける。 | ファイルの改ざん、配布遅延、クライアントとの形式不一致に注意する。モデルの実際の利用可否は契約やサービス側設定にも依存し、このパス指定だけでは強制できない。 |
| 32 | `models` | 新規スレッドのモデル既定値 | 下位キー | `table` | `[models.new_thread]`<br>`model = "<承認済みモデルID>"`<br>`model_reasoning_effort = "high"` | 構造 | 新規ローカルスレッドに適用するモデル、推論努力、サービス階層の管理既定値をまとめる親テーブルである。 | 新しい会話を始めたときに最初から選ばれるモデル関連設定をまとめる入れ物である。 | 操作性、コスト、社内標準化のために使い、強制設定として扱わない。 | 親テーブルだけでは効果がなく、`models.new_thread` 配下を設定する。明示的なCLIフラグや `--config` で上書きできるため、禁止モデルの統制には使わない。 |
| 33 | `models.new_thread` | 新規スレッドのモデル既定値 | 下位キー | `table` | `[models.new_thread]`<br>`model = "<承認済みモデルID>"`<br>`model_reasoning_effort = "high"` | 管理既定値 | 新規スレッド開始時に適用するモデル関連の既定値をまとめる。モデル、推論努力、サービス階層を配下で指定する。 | 新しい作業を始めたときの標準モデル設定を決めるグループである。 | 利用者の初期選択をそろえる目的で使用する。 | 管理既定値であり強制ではない。利用者や起動オプションによる上書きを前提に、利用量・コスト統制は別の管理策でも確認する。 |
| 34 | `models.new_thread.model` | 新規スレッドのモデル | モデルID | `string` | `[models.new_thread]`<br>`model = "<承認済みモデルID>"` | 管理既定値 | 新規スレッドで最初に選択する既定モデルを指定する。 | 新しい会話を開始したときに、標準で使うAIモデルを決める設定である。 | 契約上利用可能で、組織が評価済みのモデルIDを指定する。 | 明示的な `--model` またはモデル／推論努力の `--config` 指定が優先される。モデル名と可用性は時点・契約で変わるため、配布前に確認する。 |
| 35 | `models.new_thread.model_reasoning_effort` | 新規スレッドの推論努力 | モデル依存の文字列 | `string` | `[models.new_thread]`<br>`model_reasoning_effort = "high"` | 管理既定値 | 新規スレッドで標準使用する推論努力の水準を指定する。値が高いほど、対応モデルではより多くの推論資源を使う場合がある。 | 回答の検討量と、応答時間・利用量のバランスを決める初期値である。 | 業務の難易度、応答時間、利用量の基準に合わせ、対応モデルで有効な値を選ぶ。 | 許可値はモデルに依存する。明示的なモデルまたは推論努力指定がある場合、管理されたmodelとeffortの両方が適用されないため、強制的なコスト上限には使わない。 |
| 36 | `models.new_thread.service_tier` | 新規スレッドのサービス階層 | 契約依存の文字列 | `string` | 不明（公式リファレンスに列挙値がないため、値の例示は省略） | 管理既定値 | 新規スレッドで標準使用するサービス階層を指定する。具体的な許可値は公開リファレンスに列挙されていない。 | 利用可能な場合に、処理速度や提供条件に関係するサービス区分の初期値を決める設定である。 | 契約と対象クライアントで利用可能な値を確認できる場合だけ設定する。 | モデル関連の上書きとは独立して、明示的なサービス階層指定が優先される。許可値は時点・契約で変わるため、本資料では不明として扱う。 |
| 37 | `sqlite_home` | ローカル実行状態の保存先 | ディレクトリパス | `string`（パス） | `sqlite_home = "/var/lib/codex"` | 正確値強制 | SQLiteベースのローカル実行状態を保存するディレクトリを固定する。 | Codexが端末内で保持する作業状態データを、どのフォルダーへ保存するかを決める設定である。 | ユーザーごとに分離され、管理者が保護できるローカルディレクトリを指定する。共有ディレクトリは避ける。 | 端末バックアップ、アクセス権、ディスク暗号化、保持・削除、障害復旧の対象にする。複数利用者で同じ保存先を共有すると、状態の混在や情報漏えいにつながり得る。 |

## アプリ／コネクタ

この表は、Codexから利用できる外部アプリ／コネクタを管理し、アプリ単位で無効化するか、各ツールの実行前に承認を求めるかを決めるものである。外部サービスの読み取りや書き込みを伴うため、アプリの許可範囲と承認方式を組み合わせて制御する。

| 項番 | 設定キー | 値 | 型・許可値 | 設定例（TOML） | 説明 | 意味 | 公開情報の精度 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `apps` | 下位キー | `table` | `[apps."<id>"]`<br>`enabled = false` | アプリIDごとの管理要件をまとめる親テーブルである。アプリ全体を無効化し、アプリが提供する各ツールの承認方式を固定できる。 | Codexから接続する外部サービスを、アプリ単位・操作単位で管理するための入れ物である。 | 親テーブルと下位キーの役割は明示されている。利用できるアプリIDとツール名は環境・契約に依存する。 | アプリ可用性全体は `[features].apps` でも制御する。ワークスペースのコネクタ権限、外部サービス側のアカウント権限、ローカルランタイム権限は別レイヤーであり、すべてを確認する。 |
| 2 | `apps.<id>.enabled` | `true` / `false` | `boolean` | `[apps."<id>"]`<br>`enabled = false` | 指定したアプリを有効または無効に固定する。`false` にすると、そのアプリをCodexから利用できなくする。複数要件ソースのいずれかで無効化されると、制限側が維持される。 | 未承認の外部サービスを、アプリIDを指定して利用不可にする設定である。 | `false` による無効化と複数要件ソースでの制限側優先は明示されている。 | 省略は未制約である。許可するアプリIDを管理台帳と一致させ、不要なアプリは明示的に `false` とする。アプリ停止後も外部サービス側に残る認可やデータは別途棚卸しする。 |
| 3 | `apps.<id>.tools.<tool>.approval_mode` | `auto` | `auto \| prompt \| writes \| approve` | `[apps."<id>".tools."<tool>"]`<br>`approval_mode = "auto"` | 指定アプリの1ツールについて、承認方式を `auto` に固定する。Codexの標準判定に従い、操作内容に応じて自動実行または承認要求を決める。 | そのツールを実行するたびに、Codexが危険度を判断して確認の要否を決める方式である。 | モードの存在は明示されているが、読み取り・書き込み・危険度を判定する完全な基準は公開リファレンスでは不明である。 | 副作用のあるツールを `auto` にする場合は、実際にどの操作で承認が出るかを実機試験する。分類の誤りを前提に、外部サービス側の最小権限も併用する。 |
| 4 | `apps.<id>.tools.<tool>.approval_mode` | `prompt` | `auto \| prompt \| writes \| approve` | `[apps."<id>".tools."<tool>"]`<br>`approval_mode = "prompt"` | 指定アプリの1ツールについて、承認方式を `prompt` に固定する。ツール実行を承認対象として扱う、最も保守的なモードである。 | そのツールを使う前に、原則として人または自動レビューへ確認を求める方式である。 | 承認対象として扱うことは明示されている。実際の表示先と自動レビュー経路は、承認ポリシーとレビュアー設定にも依存する。 | 書き込み、送信、削除、購入、権限変更などの副作用があるツールは `prompt` を基本とする。承認疲れを避けるため、ツール名と用途を利用者へ明示する。 |
| 5 | `apps.<id>.tools.<tool>.approval_mode` | `writes` | `auto \| prompt \| writes \| approve` | `[apps."<id>".tools."<tool>"]`<br>`approval_mode = "writes"` | 指定アプリの1ツールについて、承認方式を `writes` に固定する。書き込みまたは副作用を伴うと判定された操作を承認対象にする。 | 閲覧だけの操作は自動化し、外部サービスのデータを変更する操作だけ確認する方式である。 | 書き込み／副作用を承認対象にする趣旨は明示されているが、具体的な分類基準は公開リファレンスでは不明であり、ツール側メタデータに依存し得る。 | 書き込みに見えない送信、起動、公開、共有なども副作用になり得る。重要ツールでは分類結果を実機試験し、判定に不安がある場合は `prompt` を使う。 |
| 6 | `apps.<id>.tools.<tool>.approval_mode` | `approve` | `auto \| prompt \| writes \| approve` | `[apps."<id>".tools."<tool>"]`<br>`approval_mode = "approve"` | 指定アプリの1ツールについて、承認方式を `approve` に固定する。そのツールを事前承認済みとして扱い、承認要求を減らす。 | そのツールを原則自動実行し、利用者への確認を省く方式である。 | 事前承認済みとして扱う効果は明示されている。承認ポリシーとの最終的な組合せは対象クライアントで確認が必要である。 | 信頼済みで読み取り専用と検証できるツール以外には使用しない。外部サービス側で書き込み権限を持つツールへ設定すると、誤操作を人が止める機会が減る。 |

## 実験的ネットワーク要件

`[experimental_network]` は「インターネット通信を許可するスイッチ」ではない。サンドボックス内で動くローカルコマンドについて、管理者定義のネットワークプロキシを起動し、接続先ルールを強制する設定である。実効化には、**コマンド側の通信許可** と **プロキシによる宛先制限** の両方が必要である。

対象はローカルコマンド、スクリプト、その子プロセスの通信である。Web検索、Apps／コネクタ、MCP、ブラウザー、Computer Use、Codexサービス通信、Codex cloudの通信は別経路であり、この設定では一括制御できない。機能自体が実験的であり、Windows対応は公式資料上「限定的」であるため、全社一括適用ではなくOS・クライアント・サンドボックス実装別のパイロットが前提となる。

### 利用前提

この表は、`[experimental_network]` が実際に通信を制限するために、同時に満たす必要がある条件を示すものである。

| 項番 | 前提条件 | 必要な設定・環境 | 満たさない場合 |
| --- | --- | --- | --- |
| 1 | コマンド通信の許可 | 権限プロファイル方式では、選択中のプロファイルに `permissions.<name>.network.enabled = true` が必要である。旧サンドボックス方式では、その方式側でコマンド通信が許可されている必要がある。 | `experimental_network.enabled = true` でも通信権限は追加されず、コマンドは外部通信できない。 |
| 2 | 権限制御方式の統一 | 権限プロファイルを使う場合はCodex 0.138.0以上とし、旧 `sandbox_mode` / `sandbox_workspace_write` を除去する。管理された `allowed_permission_profiles` で使用プロファイルを限定する。 | 権限プロファイルと旧方式は合成されない。旧設定が選択され、想定した `network.enabled` やファイル制約が使われない可能性がある。 |
| 3 | 管理プロキシの起動 | `experimental_network.enabled = true` が必要である。管理要件から起動する場合、ユーザー側の `features.network_proxy` は前提ではない。 | allow／deny規則を書いてもプロキシが起動せず、宛先制限として機能しない。 |
| 4 | 管理allow規則 | `allowed_domains` または `domains` のどちらかで、必要な接続先を具体的に許可する。`managed_allowed_domains_only = true` は管理allow規則と同時に使う。 | 管理者許可のみを強制しているのに管理allow規則がなければ、ユーザー追加allowも残らず必要通信が失敗する。 |
| 5 | プロキシ待受 | HTTP／SOCKSのループバックポートが他アプリと競合せず、EDR・ローカルファイアウォールが必要なローカル通信を妨げないことが必要である。 | プロキシが起動できない、または一部のツールだけ通信に失敗する可能性がある。 |
| 6 | OS側サンドボックス | macOS、Linux／WSL、native Windowsで強制方式と制約が異なる。native Windowsでは `elevated` が最も強く、`unelevated` はネットワーク分離が弱い。 | 同じTOMLでもOSや実装により強制可能な境界が異なる。未対応ポリシーは拒否される場合がある。 |
| 7 | 外部接続面の個別制御 | Web検索、Apps、MCP、ブラウザー、Computer Use、Codex cloudを個別に無効化または制限する。 | コマンド通信だけを閉じても、別機能から外部サービスへ接続できる状態が残る。 |
| 8 | 負の試験 | allowしたFQDNだけでなく、denyしたFQDN、IP直指定、`localhost`、プライベートIP、上流プロキシ、Unixソケットを試験する。 | 「必要通信が通る」だけを確認し、禁止通信の迂回経路を見落とす。 |

### 通信許可とプロキシの組合せ

この表は、権限プロファイルの `network.enabled` と、`experimental_network.enabled` 等で有効になるネットワークプロキシの組合せを示すものである。ドメインルールはプロキシが動作している場合だけ強制される。

| 項番 | コマンド通信 | プロキシ | 実効動作 | 初心者向けの意味 |
| --- | --- | --- | --- | --- |
| 1 | OFF | OFF | コマンドはネットワークへ接続できない。 | 最も閉じた状態であり、ドメインルール以前に通信自体が禁止される。 |
| 2 | OFF | ON | コマンドはネットワークへ接続できない。プロキシは通信権限を追加しない。 | `experimental_network` は通信を許可する設定ではないことを示す組合せである。 |
| 3 | ON | OFF | コマンドは直接ネットワークへ接続でき、権限プロファイルのドメインルールは強制されない。 | allowリストを書いていても、プロキシが動かなければ接続先を絞れない危険な状態である。 |
| 4 | ON | ON | コマンドはプロキシ経由となり、allow／deny規則が強制される。実効allowがない場合、外部宛先はブロックされる。 | 通信を必要な宛先だけに限定するための完成形である。 |

### Windowsサンドボックス実装との関係

この表は、`windows.allowed_sandbox_implementations` の指定によって、native Windowsで使えるサンドボックス方式と前提条件がどのように変わるかを示すものである。`elevated` という名称は、Codexのコマンドを管理者権限で実行する意味ではない。管理者承認付きセットアップを使い、実際のコマンドは専用の低権限サンドボックスユーザーで動かす方式である。

| 項番 | 許可値 | 前提条件 | 分離方式と保証 | 実験的ネットワーク利用時の注意 |
| --- | --- | --- | --- | --- |
| 1 | `["elevated"]` | Windows 11を推奨。`winget`、管理者承認付きセットアップ、ローカルユーザー／グループ作成、ファイアウォール規則変更、必要なログオン権限が必要である。 | 専用の低権限サンドボックスユーザー、ファイル権限境界、ファイアウォール規則、ローカルポリシーを使う最も強いnative Windows実装である。`unelevated` へのフォールバックを禁止する。 | OS側のネットワーク分離は強い側であるが、Windows上の `[experimental_network]` 自体は限定的サポートである。HTTP／SOCKS、DNS、IP直指定、上流プロキシを実機試験する。セットアップ失敗時に許可された代替実装は残らない。 |
| 2 | `["unelevated"]` | `elevated` 特有の管理者承認セットアップを使えない環境でも利用できる。現在ユーザー由来の制限付きトークンとNTFS ACLで境界を構成する。 | 専用サンドボックスユーザーを使わず、ACL境界と環境レベルのオフライン制御を使う。ネットワーク分離が弱く、すべてのread/write分割を強制できない。 | `[experimental_network]` の各機能が `elevated` と同等に強制されるかを示す公式の対応表はなく **不明** である。許可・拒否・迂回の負の試験を行い、恒久的な標準構成にしない。 |
| 3 | `["elevated", "unelevated"]` | 両実装を端末で利用できるようにする。未選択時は `elevated` が優先される。 | 利用可能性は上がるが、端末またはセッションにより保証強度が混在し得る。自動切替の条件・UI・記録方法は公開資料で一律に説明されておらず **不明** である。 | 会社が `elevated` を最低保証とする場合は使用しない。許可する場合は実際に選択された実装、理由、解消期限を監査できる運用が必要である。 |
| 4 | WSL2 | Linux側でbubblewrap、seccomp、ユーザー名前空間、カーネル機能等の条件を満たす必要がある。 | native WindowsサンドボックスではなくLinuxサンドボックスを使う。`[windows].allowed_sandbox_implementations` の対象外である。 | Linux／WSL側のプロキシ、名前解決、カーネル制約を別途試験する。native Windowsの結果を流用しない。 |

### 設定キー一覧

この表は、管理プロキシの起動、allow／deny規則、ローカルネットワーク、上流プロキシ、待受ポート、Unixソケットを設定する各キーを示すものである。

| 項番 | 設定キー | 型・許可値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| 1 | `experimental_network` | `table` | `[experimental_network]`<br>`enabled = true`<br>`managed_allowed_domains_only = true` | サンドボックス化されたローカルコマンドの通信へ適用する、管理プロキシ要件をまとめる親テーブルである。 | このテーブル自体は通信権限を付与しない。選択中の権限プロファイル等で通信を許可し、`enabled = true` でプロキシを起動し、管理allow規則を定義する必要がある。Windowsは限定的サポートである。 |
| 2 | `experimental_network.enabled` | `boolean` | `[experimental_network]`<br>`enabled = true` | 管理者定義のサンドボックスネットワークプロキシを有効にする。ユーザー側の `features.network_proxy` がなくても、管理要件からプロキシを起動できる。 | `true` は通信権限を付与しない。通信許可、プロキシ起動、管理allow規則の三点を別々に確認する。 |
| 3 | `experimental_network.allowed_domains` | `array<string>` | `[experimental_network]`<br>`allowed_domains = ["api.example.com", "*.example.com"]` | リスト形式で、管理プロキシを通るコマンド通信の許可ドメインを列挙する。 | `experimental_network.domains` と併用しない。許可だけを配列で管理する場合に使う。公開資料はmap形式より劣る、または非推奨であるとは明記していない。 |
| 4 | `experimental_network.denied_domains` | `array<string>` | `[experimental_network]`<br>`denied_domains = ["tracking.example.com"]` | リスト形式で、管理プロキシを通るコマンド通信の拒否ドメインを列挙する。 | `experimental_network.domains` と併用しない。denyはallowより優先するが、deny規則だけで通信権限や管理allowリストが完成するわけではない。 |
| 5 | `experimental_network.domains` | `map<string, allow \| deny>` | `[experimental_network.domains]`<br>`"api.example.com" = "allow"`<br>`"tracking.example.com" = "deny"` | map形式で、ドメインパターンごとに `allow` または `deny` を設定する。完全ホスト、`*.example.com`、`**.example.com`、allow専用の全体 `*` を扱い、競合時は `deny` が優先される。 | allowとdenyを同じ表で管理する場合に使う。`* = "allow"` は公開ネットワーク全体を広く開く。必要なAPI、認証、CDN、パッケージ配布ホストを具体的に列挙し、`allowed_domains` / `denied_domains` と混在させない。 |
| 6 | `experimental_network.managed_allowed_domains_only` | `boolean` | `[experimental_network]`<br>`managed_allowed_domains_only = true` | `true` のとき、管理者が定義したallow規則だけを実効許可リストとし、ユーザーが追加したallow規則を無視する。 | 管理allow規則と同時に使う。管理allowなしで `true` にすると、ユーザー追加allowも有効にならず必要通信が失敗する。 |
| 7 | `experimental_network.allow_local_binding` | `boolean` | `[experimental_network]`<br>`allow_local_binding = false` | ローカルホスト、リンクローカル、プライベートネットワークへの広い到達を許可するかを決める。`false` のままでも、正確な `localhost` またはローカルIPリテラルを個別allowできる。 | 通常は `false` とする。allowされたホスト名がプライベートIPへ解決される場合は、広いローカル接続を許可しない限り拒否される。DNSリバインディング対策をこの設定だけに依存しない。 |
| 8 | `experimental_network.allow_upstream_proxy` | `boolean` | `[experimental_network]`<br>`allow_upstream_proxy = false` | 端末環境の `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY` 等を使い、管理プロキシからさらに上流プロキシへ接続できるかを制約する。 | 会社プロキシが必須なら有効化を検討する。ユーザーが環境変数を変更できる場合に未承認プロキシへ迂回しないかを試験する。 |
| 9 | `experimental_network.http_port` | `integer` | `[experimental_network]`<br>`http_port = 3128` | 管理プロキシが端末内のループバックで待ち受けるHTTPポートを指定する。 | ポート競合、EDR、ローカルファイアウォール、他のプロキシ製品との互換性を確認する。公開資料は全OSでの推奨ポートや自動競合回避を明記していないため、実機で確認する。 |
| 10 | `experimental_network.socks_port` | `integer` | `[experimental_network]`<br>`socks_port = 8081` | 管理プロキシが端末内のループバックで待ち受けるSOCKS5ポートを指定する。 | SOCKS5を使うツール、UDP、名前解決、監視製品との互換性を確認する。不要なプロトコルまで許可しない。 |
| 11 | `experimental_network.unix_sockets` | `map<string, allow \| deny>` | `[experimental_network.unix_sockets]`<br>`"/var/run/docker.sock" = "deny"` | Unixソケットの絶対パスごとに `allow` または `deny` を設定する。 | Dockerソケット等はホスト制御に直結し得るため原則拒否する。native WindowsでのUnixソケット対応範囲は公開資料から十分に確認できず **不明** である。 |
| 12 | `experimental_network.dangerously_allow_all_unix_sockets` | `boolean` | `[experimental_network]`<br>`dangerously_allow_all_unix_sockets = false` | Unixソケットの許可リストを迂回し、任意のUnixソケット宛先を許可する。 | 通常は `false` とする。コンテナ管理やシステムサービスを経由する広いローカル脱出経路になり得る。 |
| 13 | `experimental_network.dangerously_allow_non_loopback_proxy` | `boolean` | `[experimental_network]`<br>`dangerously_allow_non_loopback_proxy = false` | 管理プロキシの待受をループバック以外のアドレスへ公開できるようにする。 | 通常は `false` とする。有効化すると別端末から到達できる中継点になる可能性がある。 |

### パイロット用の最小構成例

以下は、Codex 0.138.0以上の権限プロファイルでコマンド通信を許可し、`[experimental_network]` で管理allowリストを強制する例である。組織の実ドメイン、ポート、プロキシ、OSへ置き換え、全社配布前に負の試験を行う必要がある。

```toml
default_permissions = "corp_workspace_net"

[allowed_permission_profiles]
"corp_workspace_net" = true
":read-only" = true
":workspace" = false
":danger-full-access" = false

[permissions.corp_workspace_net]
description = "社内開発用。ワークスペース書込みと承認済みAPI通信だけを許可する。"
extends = ":workspace"

[permissions.corp_workspace_net.network]
enabled = true

[experimental_network]
enabled = true
managed_allowed_domains_only = true
allow_local_binding = false
allow_upstream_proxy = false
http_port = 3128
socks_port = 8081

[experimental_network.domains]
"api.example.com" = "allow"
"auth.example.com" = "allow"
"tracking.example.com" = "deny"
```

この例はWeb検索、Apps、MCP、ブラウザー、Computer Useを制限しない。それらを禁止する場合は、それぞれの管理要件を別途設定する。native Windowsへ配布する場合は、後述の `allowed_sandbox_implementations` とセットアップ前提を先に確認する。

## 機能フラグ `[features]`

この表は、Codexおよび対応デスクトップアプリに備わる各機能を、会社方針に合わせて有効または無効に固定するものである。ブラウザー操作、Computer Use、プラグイン、Memories、複数エージェント、シェル実行、更新など、機能ごとの利用可否を設定する。

| 項番 | 設定キー | 型 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 | 公開上の位置付け |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `features` | `table` | `[features]`<br>`apps = false` | Codexおよび対応アプリの機能スイッチをまとめる親テーブルである。認識済みの各機能を `true` または `false` に固定する。 | 省略した機能は未制約である。認識されるキーはクライアントとバージョンで異なるため、全社配布前に対象環境で有効／無効が反映されるかを確認する。 | 明示 |
| 2 | `features.<name>` | `boolean` | `[features]`<br>`shell_tool = true` | 公開されたランタイム機能またはアプリ専用機能を、名前ごとに有効／無効へ固定する汎用形である。 | 存在が確認できない名前を設定しても期待どおり制御できるとは限らない。公式リファレンスに掲載されたキーだけを使用し、対象バージョンで試験する。 | 明示 |
| 3 | `features.apps` | `boolean` | `[features]`<br>`apps = false` | Apps／コネクタ統合全体を有効または無効にする。`false` にすると、Codexから外部アプリのツールを利用する入口を閉じる。 | 外部データの取得や外部サービスへの書き込みを使わない環境は `false` とする。個別アプリは `[apps]`、ワークスペース側のコネクタ設定、外部サービス側権限も別途管理する。 | 明示 |
| 4 | `features.browser_use` | `boolean` | `[features]`<br>`browser_use = false` | ブラウザー内Computer UseとBrowser Agentの利用可否を固定する。`false` にすると、ブラウザー画面を自動操作する機能を無効化する。 | ブラウザー操作を導入しない会社端末は `false` とする。有効化する場合は、ログイン済みサイト、個人情報、ダウンロード、外部送信、操作記録の範囲を定める。 | 明示・アプリ専用 |
| 5 | `features.browser_use_external` | `boolean` | `[features]`<br>`browser_use_external = false` | 外部ブラウザーを使うBrowser Useの利用可否を固定する。`false` にすると、既存の外部ブラウザーセッションを操作する機能を無効化する。 | 外部ブラウザーには既存ログイン、Cookie、履歴、保存パスワードなどがあるため、接触を避ける場合は `false` とする。 | 明示・アプリ専用 |
| 6 | `features.browser_use_full_cdp_access` | `boolean` | `[features]`<br>`browser_use_full_cdp_access = false` | ローカルランタイムによる完全なChrome DevTools Protocol（CDP）アクセスとBrowser Developer modeの利用可否を固定する。`false` にするとデスクトップアプリからの有効化も防ぐ。 | CDPはブラウザーのタブ、Cookie、ネットワーク、実行コンテキストなどへ広い制御を与え得るため、通常は `false` とする。例外利用は専用ブラウザープロファイルで検証する。 | 明示・アプリ専用 |
| 7 | `features.computer_use` | `boolean` | `[features]`<br>`computer_use = false` | Computer Use、Record & Replay、および関連するインストール／有効化フローをまとめて有効または無効にする。 | 画面や入力操作が不要なら `false` とする。`computer_use.allow_locked_computer_use` はロック後の継続だけを制御し、機能全体を停止する設定ではない。 | 明示・アプリ専用 |
| 8 | `features.fast_mode` | `boolean` | `[features]`<br>`fast_mode = false` | Fastモードまたはサービス階層を選択する機能を有効／無効にする。主に処理速度、利用量、コストに関係する機能である。 | 組織の利用枠、コスト予算、応答時間の基準、利用可能モデルに合わせて設定する。セキュリティ境界そのものとして扱わない。 | 明示・canonical |
| 9 | `features.guardian_approval` | `boolean` | `[features]`<br>`guardian_approval = true` | Guardian承認機能の利用可否を固定する。自動レビューによる承認判断を利用するための機能スイッチである。 | このキーだけでは承認担当や判断基準は決まらない。レビュアーは `allowed_approvals_reviewers`、組織固有ポリシーは `guardian_policy_config` で設定する。 | 明示・アプリ専用 |
| 10 | `features.in_app_browser` | `boolean` | `[features]`<br>`in_app_browser = false` | ChatGPTデスクトップアプリ内の組込みブラウザーペインを有効または無効にする。 | ブラウザー面を許可しない端末は `false` とする。これはWeb検索ツールとは別機能であり、Web検索の可否は `allowed_web_search_modes` で管理する。 | 明示・アプリ専用 |
| 11 | `features.in_app_updates` | `boolean` | `[features]`<br>`in_app_updates = true` | ChatGPTデスクトップアプリ自身がアプリ内で更新を行う機能を有効または無効にする。`false` にしても外部のパッケージ配布は止めない。 | MDMなどの中央配布を行わずに `false` とすると、脆弱性修正や不具合修正が遅れる。`check_for_update_on_startup` と矛盾しない更新方式を設計する。 | 明示・アプリ専用 |
| 12 | `features.memories` | `boolean` | `[features]`<br>`memories = false` | 会話から情報を長期的に記憶し、後の会話で利用するMemories機能を有効または無効にする。 | 長期保持や別会話への文脈再利用が社内ルールに合わない場合は `false` とする。有効化時は保持対象、削除、利用者への説明を確認する。 | 明示・canonical |
| 13 | `features.multi_agent` | `boolean` | `[features]`<br>`multi_agent = false` | 複数のサブエージェントが分担・並列実行するmulti-agent機能を有効または無効にする。 | 並列のツール実行、モデル利用量、ログ、承認要求が増える。初期導入では `false` から評価し、監査で各サブエージェントの操作を追えるか確認する。 | 明示・canonical |
| 14 | `features.plugin_sharing` | `boolean` | `[features]`<br>`plugin_sharing = false` | ローカルで作成したプラグインをChatGPTワークスペースへ共有する機能を有効または無効にする。 | クラウド管理 `requirements.toml` 専用である。未審査のコードや設定を社内共有させない場合は `false` とし、正式な配布経路を別途用意する。 | 明示・クラウド専用 |
| 15 | `features.plugins` | `boolean` | `[features]`<br>`plugins = false` | 対応するローカルクライアントで、プラグイン機能全体を有効または無効にする。 | 不要なら `false` とする。APIキーでCodexへサインインする場合にも適用される。許可する場合はマーケットプレイス、同梱MCP、更新元、署名・レビューを管理する。 | 明示・アプリ専用 |
| 16 | `features.remote_plugin` | `boolean` | `[features]`<br>`remote_plugin = false` | リモートのプラグインカタログを参照・利用する機能を有効または無効にする。 | 会社承認済みのローカル配布だけに限定する場合は `false` とする。有効化時は供給元と更新内容を継続監査する。 | 明示・canonical |
| 17 | `features.workspace_dependencies` | `boolean` | `[features]`<br>`workspace_dependencies = false` | ワークスペースに同梱された依存関係ランタイムを利用する機能を有効または無効にする。 | 公開リファレンスは、対象となる依存関係や利用者影響の詳細を示していないため不明である。有効化前に試験環境で、実行物、ダウンロード、更新、権限を確認する。 | 明示・アプリ専用 |
| 18 | `features.enable_request_compression` | `boolean` | `[features]`<br>`enable_request_compression = true` | 対応する場合に、ストリーミング要求本文をzstdで圧縮して送信する。通信量を減らすための互換・性能設定である。 | ネットワークプロキシ、DLP、監視製品が圧縮通信を正しく扱えるかを試験する。暗号化やアクセス制御を代替するセキュリティ境界ではない。 | canonical汎用規則 |
| 19 | `features.goals` | `boolean` | `[features]`<br>`goals = false` | 永続化されたGoalsと自動継続を有効または無効にする。長時間の目標を保持し、処理を継続する機能である。 | 長時間・自動継続作業の実行範囲、停止条件、利用量、夜間実行、監査方針に合わせる。明確な停止手段を用意する。 | canonical汎用規則 |
| 20 | `features.hooks` | `boolean` | `[features]`<br>`hooks = true` | ツール実行前後やセッション開始・終了などで、ライフサイクルフックを読み込み・実行する機能を有効または無効にする。 | 管理フックを強制する場合は `true`、`[hooks]`、`allow_managed_hooks_only = true` を組み合わせる。フック不要なら `false` とし、任意スクリプト実行面を閉じる。 | canonical汎用規則 |
| 21 | `features.network_proxy` | `boolean` のピン留め | `[features]`<br>`network_proxy = true` | サンドボックス化されたローカルコマンド向けネットワークプロキシ機能を有効または無効に固定する。通信権限を付与する設定ではない。 | 権限プロファイルのドメインルールは、プロキシが有効な場合だけ強制される。ただし管理者が `experimental_network.enabled = true` を使う場合、この機能フラグはプロキシ起動の前提ではない。`network.enabled = true` でプロキシが無効な状態は、直接通信が許可されてドメインルールが強制されないため避ける。 | canonical汎用規則・実験的 |
| 22 | `features.personality` | `boolean` | `[features]`<br>`personality = false` | コミュニケーションスタイルを選ぶUIまたは機能を有効または無効にする。 | 通常はセキュリティ境界ではない。社内マニュアルや標準UIを統一する必要がある場合だけ固定し、回答内容の正確性制御とは分けて考える。 | canonical汎用規則 |
| 23 | `features.prevent_idle_sleep` | `boolean` | `[features]`<br>`prevent_idle_sleep = false` | Codexがターンを実行している間、端末がアイドルスリープへ入らないようにする。 | 会社PCの画面ロック、省電力、物理セキュリティ方針と競合し得る。長時間実行が必要な専用端末以外では慎重に扱う。 | canonical汎用規則・実験的 |
| 24 | `features.shell_snapshot` | `boolean` | `[features]`<br>`shell_snapshot = false` | 繰り返しコマンドの起動を速くするため、シェル環境のスナップショットを利用する機能を有効または無効にする。 | 環境変数や起動設定の扱いをシェルポリシーと合わせる。保存内容の完全な詳細は要件リファレンスでは不明であるため、資格情報が環境変数に入る運用では慎重に試験する。 | canonical汎用規則 |
| 25 | `features.shell_tool` | `boolean` | `[features]`<br>`shell_tool = true` | 標準の `shell` ツールを有効または無効にする。`false` にすると、Codexが一般的なローカルコマンドを実行する能力を大きく制限する。 | `false` は攻撃面を減らすが、開発作業の多くが行えなくなる。他の実行ツールやMCPが残る可能性があるため、シェルだけを止めて端末操作が完全に止まるとは考えない。 | canonical汎用規則 |
| 26 | `features.skill_mcp_dependency_install` | `boolean` | `[features]`<br>`skill_mcp_dependency_install = false` | Skillsで必要なMCP依存関係が不足している場合に、利用者へ案内し、インストールする機能を許可する。 | 新しい依存関係を取得・実行するサプライチェーン面が増える。中央管理した依存関係だけを使う場合は `false` とする。 | canonical汎用規則 |
| 27 | `features.unified_exec` | `boolean` | `[features]`<br>`unified_exec = true` | PTYベースの統合実行ツールを使用する。PTYは対話型ターミナルに近い入出力を提供する仕組みである。 | Windowsでは既定が異なる。EDR、シェル、フック、標準入出力ログ、対話型コマンドとの互換性をOS別に試験する。 | canonical汎用規則 |
| 28 | `features.web_search` | `boolean` | `[features]`<br>`web_search = false` | Web検索機能全体を切り替える旧トグルである。 | 非推奨である。新規ポリシーではトップレベルの `allowed_web_search_modes` とWeb検索モード制約を使い、旧キーとの競合を避ける。 | canonical・非推奨 |
| 29 | `features.web_search_cached` | `boolean` | `[features]`<br>`web_search_cached = false` | トップレベルのWeb検索モードが未設定の場合に、`cached` 検索へ対応付ける旧トグルである。 | 非推奨である。新規ポリシーでは使わず、`allowed_web_search_modes` へ移行して実効モードを明確にする。 | canonical・非推奨 |
| 30 | `features.web_search_request` | `boolean` | `[features]`<br>`web_search_request = false` | トップレベルのWeb検索モードが未設定の場合に、`live` 検索へ対応付ける旧トグルである。 | 非推奨である。意図せずライブ検索を許可する恐れがあるため新規ポリシーでは使わず、`allowed_web_search_modes` で明示的に制限する。 | canonical・非推奨 |

### `[features]` の下位テーブルに関する不明点

`config.toml` の公開リファレンスには `features.code_mode.*`、`features.network_proxy.*`、`features.rollout_budget.*` のような下位テーブル設定もある。一方、公開 `requirements.toml` リファレンスは `[features]` を **booleanのピン留め** として定義し、これらの下位テーブルを要件として使えるとは明記していない。したがって、上表に個別掲載した単純booleanキー以外の下位テーブルをクラウドポリシーに書けるかは **不明**。ネットワーク制約は `[experimental_network]` または権限プロファイルのnetwork設定を使用する。

## 権限プロファイルとファイルシステム制約

この表は、Codexがローカル端末上で読み書きできるファイル範囲と、サンドボックス化されたコマンドが接続できるネットワーク範囲を、再利用可能な権限プロファイルとして定義するものである。通常業務に必要な範囲だけを許可し、資格情報や管理用ソケットなどを明示的に拒否するために使う。

| 項番 | 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| 1 | `permissions` | `table` | `[permissions.corp_workspace]`<br>`description = "社内開発用"`<br>`extends = ":workspace"` | 管理者が作成する権限プロファイルと、すべてのプロファイルへ追加する強制的な読取拒否をまとめる親テーブルである。権限プロファイルは、許可するファイル操作とネットワーク通信を用途別にひとまとめにした設定である。 | カスタムプロファイル名は `:` で開始できず、予約名 `filesystem` も使えない。既存設定の同名プロファイルとの衝突を避け、名称、所有者、用途を台帳化する。 |
| 2 | `permissions.<name>` | `table` | `[permissions.corp_workspace]`<br>`description = "社内開発用"`<br>`extends = ":workspace"` | 管理者が定義する1つの権限プロファイルである。ファイルの読み取り・書き込み・拒否と、ローカルコマンドのネットワーク宛先を一体で定義する。 | Codex 0.138.0以降を前提とする。`allowed_permission_profiles.<name> = true` で選択を許可し、`default_permissions` の指定名と整合させる。 |
| 3 | `permissions.<name>.description` | `string` | `[permissions.corp_workspace]`<br>`description = "社内開発用"` | 権限プロファイルの目的を人が読める文章で記録する。設定の動作には直接影響しないが、利用者と管理者が用途を判断するための説明となる。 | `extends` で親プロファイルの説明は継承されない。対象業務、許可範囲、所有者、例外条件、連絡先を簡潔に明記する。 |
| 4 | `permissions.<name>.extends` | `string`: `:read-only`, `:workspace`, または他のカスタム名 | `[permissions.corp_workspace]`<br>`extends = ":workspace"` | 既存の組込みまたはカスタム権限プロファイルを親として継承し、必要な差分だけを追加する。 | 組込みの基礎防御を引き継ぐため、通常は `:read-only` または `:workspace` から始める。`:danger-full-access`、未知の親、循環継承は拒否される。 |
| 5 | `permissions.<name>.workspace_roots` | `table` | `[permissions.corp_workspace.workspace_roots]`<br>`"/srv/repos/product-a" = true` | 現在開いているワークスペース以外に、プロファイルで作業対象として扱う追加ディレクトリをまとめる。追加した場所は `:workspace_roots` ルールの対象になる。 | 必要なリポジトリだけを追加する。ホームディレクトリ全体、共有ドライブ全体、資格情報ディレクトリをワークスペースルートにしない。 |
| 6 | `permissions.<name>.workspace_roots."<path>"` | `boolean` | `[permissions.corp_workspace.workspace_roots]`<br>`"/srv/repos/product-a" = true` | 指定パスを追加ワークスペースルートとして有効化する。`true` で有効、`false` で非アクティブとなる。 | 絶対パスまたはホーム相対パスの展開結果を端末ごとに確認する。WindowsのドライブパスやUNCパスは、端末間で同じ意味になるかを検証する。 |
| 7 | `permissions.<name>.filesystem` | `table` | `[permissions.corp_workspace.filesystem.":workspace_roots"]`<br>`"." = "write"`<br>`"**/*.env" = "deny"` | ファイルまたはディレクトリのパスごとに、`read`（読み取り可）、`write`（読み書き可）、`deny`（アクセス禁止）を割り当てる。配下をさらに細かく分けるサブパスマップも定義できる。 | 空または欠落したルールはアクセスを制限し、起動警告の対象となる。広い許可を先に定義し、`.env`、資格情報、鍵、管理ファイルなどをより具体的な `deny` で除外する。 |
| 8 | `permissions.<name>.filesystem.glob_scan_max_depth` | `number`（1以上） | `[permissions.corp_workspace.filesystem]`<br>`glob_scan_max_depth = 8` | `**` を使う無制限階層のdenyグロブについて、起動時に事前走査する最大ディレクトリ深さを指定する。Linux、WSL、native Windowsで使用される。 | 大きい値は起動時のファイル走査コストを増やす。`**/*.env` などの再帰denyを使う場合だけ、実際のディレクトリ深さに合わせて設定する。 |
| 9 | `permissions.<name>.filesystem."<path>"` | `read \| write \| deny` またはtable | `[permissions.corp_workspace.filesystem]`<br>`"~/.ssh" = "deny"` | 正確なOSパスまたは特殊パスに対して、読み取り、書き込み、拒否の権限を直接設定する。 | 同じ具体度では `deny > write > read` の順に強く、より具体的なルールが広いルールを上書きする。OSで安全に強制できない直接writeは拒否されるため、実機で確認する。 |
| 10 | `permissions.<name>.filesystem."<path>"."<subpath>"` | `read \| write \| deny` | `[permissions.corp_workspace.filesystem."/srv/repos"]`<br>`"product-a" = "write"` | 基準パスの配下を相対サブパスごとに分け、異なる権限を設定する。`.` は基準パスそのものを表す。 | サブパスに `.` / `..` の移動成分や親ディレクトリへ抜ける指定は使えない。許可範囲が意図したサブツリーだけになるかを確認する。 |
| 11 | `permissions.<name>.filesystem.":workspace_roots"."<subpath-or-glob>"` | `read \| write \| deny` | `[permissions.corp_workspace.filesystem.":workspace_roots"]`<br>`"." = "write"`<br>`"**/*.env" = "deny"` | すべての実効ワークスペースルートに対し、同じ相対パスまたはグロブの権限ルールを適用する。例として、ルート全体を書き込み可にし、`**/*.env` だけを拒否できる。 | 資格情報ファイルを一括denyする主要な方法である。read/writeグロブはOS間の可搬性が低いため、可能なら正確なパスまたはサブツリーを使い、denyの一致をOS別に試験する。 |
| 12 | `permissions.<name>.network` | `table` | `[permissions.corp_workspace.network]`<br>`enabled = true` | その権限プロファイルで、サンドボックス化コマンドの通信許可と、プロキシが有効な場合に強制する宛先ルールをまとめる親テーブルである。 | `enabled = true` は通信を許可するが、プロキシを起動しない。ドメイン制限には `features.network_proxy = true` または `experimental_network.enabled = true` が別途必要である。Apps、MCP、ブラウザー等は別制御である。 |
| 13 | `permissions.<name>.network.enabled` | `boolean`; 既定 `false` | `[permissions.corp_workspace.network]`<br>`enabled = true` | 選択中のプロファイルで、サンドボックス化されたコマンド、スクリプト、子プロセスへネットワークアクセスを許可する。 | `true` は通信権限を付与するだけである。プロキシが無効ならドメインルールは強制されず、コマンドは直接・無制限に接続できる。通信を絞る場合はプロキシの有効化とallow規則を同時に確認する。 |
| 14 | `permissions.<name>.network.mode` | `limited \| full`; 既定値は公開資料で不明 | `[permissions.corp_workspace.network]`<br>`enabled = true`<br>`mode = "full"` | 子プロセス通信で使用するネットワークプロキシのモードを `limited` または `full` から指定する。 | 公開Configuration Referenceは値名と「子プロセス通信のプロキシモード」であることだけを示し、両者の具体的な通信差、既定値、全OSでの互換性を説明していないため、本資料では詳細を **不明** とする。制御目的で採用する前に対象版で試験する。 |
| 15 | `permissions.<name>.network.domains` | `table` | `[permissions.corp_workspace.network.domains]`<br>`"api.example.com" = "allow"`<br>`"tracking.example.com" = "deny"` | 接続先ホストのパターンを `allow` または `deny` に対応付ける。ルールはネットワークプロキシが有効な場合だけ強制される。 | プロキシが有効でallowが1件もなければ外部宛先はブロックされる。プロキシが無効なら、この表を書いていても直接通信を制限できない。`deny` は `allow` より優先する。 |
| 16 | `permissions.<name>.network.domains."<pattern>"` | `allow \| deny` | `[permissions.corp_workspace.network.domains]`<br>`"api.example.com" = "allow"` | 完全ホスト、`*.example.com`、`**.example.com`、allow専用の全体 `*` を指定する。 | `* = "allow"` は公開ネットワーク全体を開く。必要なホストだけを列挙し、CDN、認証、パッケージ配布等の補助ホストも通信ログから確認する。 |
| 17 | `permissions.<name>.network.unix_sockets` | `table` | `[permissions.corp_workspace.network.unix_sockets]`<br>`"/var/run/docker.sock" = "deny"` | そのプロファイルから接続できるUnixソケットを、パスごとに許可または拒否する。 | Dockerや管理エージェントのソケットはホスト制御面に直結し得る。必要な統合だけを正確なパスで許可し、通常は拒否する。 |
| 18 | `permissions.<name>.network.unix_sockets."<path>"` | `allow \| deny` | `[permissions.corp_workspace.network.unix_sockets]`<br>`"/var/run/docker.sock" = "deny"` | 指定した絶対Unixソケットパスへの接続を `allow` または `deny` にする。 | 親プロファイルから継承したallowも、より具体的なdenyで除外できる。ソケット自体の所有権と書込権限も確認する。 |
| 19 | `permissions.<name>.network.proxy_url` | `URL string`; 既定 `http://127.0.0.1:3128` | `[permissions.corp_workspace.network]`<br>`proxy_url = "http://127.0.0.1:3128"` | HTTP、HTTPS、WebSocket等のプロキシ環境変数で使うローカルHTTPリスナーURLを指定する。 | 通常はループバックの既定値を使う。ポート競合を確認し、非ループバックへ向けない。 |
| 20 | `permissions.<name>.network.enable_socks5` | `boolean`; 既定 `true` | `[permissions.corp_workspace.network]`<br>`enable_socks5 = false` | `ALL_PROXY` やFTP系プロキシ変数で使うSOCKS5リスナーを有効または無効にする。 | SOCKS5が不要なら `false` を検討する。ただし開発ツール、名前解決、パッケージ取得への影響を試験する。 |
| 21 | `permissions.<name>.network.socks_url` | `URL string`; 既定 `http://127.0.0.1:8081` | `[permissions.corp_workspace.network]`<br>`socks_url = "http://127.0.0.1:8081"` | SOCKS5リスナーのURLを指定する。 | 通常はループバックの既定値を使う。ポート競合、監視製品、ローカルファイアウォールとの互換性を確認する。 |
| 22 | `permissions.<name>.network.enable_socks5_udp` | `boolean`; 既定 `true` | `[permissions.corp_workspace.network]`<br>`enable_socks5_udp = false` | SOCKS5を有効にした場合にUDP通信も許可するかを決める。 | UDPが不要なら `false` を検討する。DNSや開発ツールへの影響をOS別に試験する。 |
| 23 | `permissions.<name>.network.allow_upstream_proxy` | `boolean`; 既定 `true` | `[permissions.corp_workspace.network]`<br>`allow_upstream_proxy = true` | 端末環境の `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY` 等の上流プロキシを尊重する。 | 会社プロキシ必須環境では必要になり得る。ユーザー設定の未承認プロキシへ迂回しないか、環境変数の管理と実通信で確認する。 |
| 24 | `permissions.<name>.network.allow_local_binding` | `boolean`; 既定 `false` | `[permissions.corp_workspace.network]`<br>`allow_local_binding = false` | `true` にするとローカル／プライベートネットワークガードを外す。`false` の場合も、正確な `localhost` やIPリテラルを個別allowできる。 | DNSリバインディングや社内管理サービスへの到達面が増えるため通常は `false` とする。allowしたホスト名がプライベートIPへ解決される場合の挙動も試験する。 |
| 25 | `permissions.<name>.network.dangerously_allow_non_loopback_proxy` | `boolean`; 既定 `false` | `[permissions.corp_workspace.network]`<br>`dangerously_allow_non_loopback_proxy = false` | プロキシリスナーをループバック以外のアドレスへバインドできるようにする。 | 通常は `false` とする。有効化すると端末外へプロキシが公開され、意図しない中継点になる恐れがある。 |
| 26 | `permissions.<name>.network.dangerously_allow_all_unix_sockets` | `boolean`; 既定 `false` | `[permissions.corp_workspace.network]`<br>`dangerously_allow_all_unix_sockets = false` | Unixソケットの許可リストを迂回し、任意のUnixソケットへ接続できるようにする。 | 通常は `false` とする。Dockerソケット等を通じた広いローカル脱出経路になり得る。 |
| 27 | `permissions.filesystem.deny_read` | `array<string>`（絶対パス、`~`、glob） | `[permissions.filesystem]`<br>`deny_read = ["~/.ssh", "~/.aws"]` | すべてのローカル設定より強い、管理者強制の読取拒否パスを追加する。ユーザーやプロジェクト設定では弱められない。 | `./` で始まる相対パスは使えない。この設定があるとフルアクセス権限は拒否される。native Windowsでは直接ファイルツールには効くが、シェル子プロセスの読み取りには適用されないため、OS側ACLやEDRで補完する。 |

## 権限プロファイルで使える特殊パス

この表は、権限プロファイルのファイルシステムルールで使用できる特殊なパス表記を説明するものである。OSごとに異なる実パスを直接列挙せず、ワークスペース、テンポラリ領域、ホームディレクトリなどを共通表記で指定できる。

| 項番 | パス | 意味 | 注意 |
| --- | --- | --- | --- |
| 1 | `:root` | ファイルシステム全体のルートを表す。Linux/macOSの `/` やWindowsの各ルートに相当する、最も広い指定である。 | 広い読み取りを明確に必要とする場合だけ使用する。サブパスは `.` のみであり、安易なwrite許可は避ける。 |
| 2 | `:minimal` | 一般的な開発ツールを起動するために最低限必要となる、OSやランタイムのパス集合を表す。 | 実際に含まれるパスはプラットフォームとランタイムに依存する。サブパスは `.` のみであり、対象端末で必要十分かを確認する。 |
| 3 | `:workspace_roots` | 現在の実行ワークスペースルートと、プロファイルで追加したワークスペースルートをまとめて表す。 | 相対サブパスやグロブを設定できる。プロジェクト全体を許可した後、`.env` や資格情報を具体的な `deny` で除外する。 |
| 4 | `:tmpdir` | 環境変数 `$TMPDIR` が示す一時ディレクトリを表す。 | 親プロファイルからwrite権限を継承する場合がある。不要ならdenyを検討し、機密情報を一時ファイルへ残さない。サブパスは `.` のみ。 |
| 5 | `:slash_tmp` | OS上に存在する場合の共有一時ディレクトリ `/tmp` を表す。 | 複数ユーザーやプロセスが利用する共有領域であるため、ファイル名衝突、権限、シンボリックリンクなどを評価する。サブパスは `.` のみ。 |
| 6 | `/absolute/path` / `C:\path` | OS上の正確な絶対パスを直接指定する。Linux/macOS形式とnative Windowsのドライブパス・UNCパスを扱える。 | 端末ごとのパス差異、ドライブ割当、UNC共有の可用性と権限を確認する。広い親ディレクトリではなく必要なサブツリーを指定する。 |
| 7 | `~/path` / `~\path` | 現在のユーザーのホームディレクトリ配下を、ユーザーごとに展開して指定する。 | SSH鍵、クラウド資格情報、設定ファイルなどが置かれやすい。`~/.ssh`、`~/.aws` などはdeny候補とし、利用OSごとに実際の展開先を確認する。 |

## 管理フック

この表は、ツール実行前後やセッション開始・終了などの決まったタイミングで、管理者配布のcommandフックまたは接続済みMCPツールを自動実行する設定を示すものである。検査、ブロック、監査、追加コンテキストの提供を実現できるが、ハンドラーの種類により、元の操作を止められる条件が異なる。

管理フックを動かすには、`[features].hooks = true`、`[hooks]`、スクリプトの別配布が必要である。管理フックだけに絞る場合は `allow_managed_hooks_only = true` も設定する。

| 項番 | 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| 1 | `hooks` | `table` | `[hooks]`<br>`managed_dir = "/enterprise/hooks"` | 管理者が強制するライフサイクルフックを定義する親テーブルである。inline hooksと同じイベントスキーマを使う。 | ポリシーはスクリプト本体を配布しない。MDM等で別途配布し、一般ユーザーが変更できない絶対パス、所有権、署名またはハッシュを管理する。 |
| 2 | `hooks.managed_dir` | `string`（存在する絶対パス） | `[hooks]`<br>`managed_dir = "/enterprise/hooks"` | macOS／Linuxで使用する管理フックスクリプトの格納ディレクトリを指定する。 | 存在する絶対パスが必要である。一般ユーザーが書き換えられない所有者・グループ・ACLにする。 |
| 3 | `hooks.windows_managed_dir` | `string`（存在する絶対パス） | `[hooks]`<br>`windows_managed_dir = "C:\\enterprise\\hooks"` | Windowsで使用する管理フックスクリプトの格納ディレクトリを指定する。 | 存在する絶対パスを使い、一般ユーザーが書き換えられないNTFS ACLにする。PowerShell実行ポリシーや署名要件も確認する。 |
| 4 | `hooks.<Event>` | `array<table>` | `[[hooks.PreToolUse]]`<br>`matcher = "^Bash$"` | 指定イベントで評価するmatcherグループの配列である。 | 同じイベントで一致した複数のcommandフックは並行起動される。実行順序や別フックの副作用へ依存しない。 |
| 5 | `hooks.<Event>[].matcher` | `string`（正規表現） | `[[hooks.PreToolUse]]`<br>`matcher = "^Bash$"` | フックを発火させる対象を正規表現で絞る。イベントに応じてツール名、開始理由、圧縮理由等へ照合される。 | `UserPromptSubmit` と `Stop` は現在matcherをサポートしない。正規表現をアンカーし、意図しない一致を避ける。 |
| 6 | `hooks.<Event>[].hooks` | `array<table>` | `[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"` | matcherに一致した場合に実行するハンドラーの配列である。`command` と `mcp_tool` を指定できる。 | ハンドラー種別ごとに、エラー時、タイムアウト時、元操作を止められるかが異なる。単に配列へ追加しただけでフェイルクローズになるとは限らない。 |
| 7 | `hooks.<Event>[].hooks[].type` | `command \| mcp_tool`; `prompt` / `agent` は解析されるがスキップ | `[[hooks.PreToolUse.hooks]]`<br>`type = "command"` | ハンドラー種別を指定する。`command` はローカルコマンドを実行し、`mcp_tool` は既に接続済みのMCPサーバーのツールを呼び出す。 | `prompt` と `agent` は設定として解析されても現在は実行されない。`mcp_tool` は接続失敗等で元操作を自動的に止めないため、必須防御に単独使用しない。 |
| 8 | `hooks.<Event>[].hooks[].command` | `string` | `[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"` | macOS／Linux等で実行するcommandフックのコマンドを指定する。セッションの `cwd` で起動する。 | 管理ディレクトリ配下の絶対スクリプトパスを参照し、ユーザー入力をそのままシェル引数へ連結しない。 |
| 9 | `hooks.<Event>[].hooks[].command_windows` | `string` | `[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command_windows = "C:\\enterprise\\hooks\\check.cmd"` | Windowsで実行するcommandフックを、共通の `command` から上書きする。 | `commandWindows` という別名も受理される。パス引用符、PowerShellとcmdの解釈差を試験する。 |
| 10 | `hooks.<Event>[].hooks[].commandWindows` | `string` | `[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`commandWindows = "C:\\enterprise\\hooks\\check.cmd"` | `command_windows` と同じWindows用コマンドを指定するTOML別名である。 | 組織内では表記を統一し、公式管理例に合わせて `command_windows` を優先する。 |
| 11 | `hooks.<Event>[].hooks[].server` | `string`（`mcp_tool` で必須） | `[[hooks.PostToolUse.hooks]]`<br>`type = "mcp_tool"`<br>`server = "scanner"` | 呼び出す、既に接続済みのMCPサーバー名を指定する。 | フックはサーバーを起動・再接続しない。サーバー未接続でも元操作は自動的にブロックされない。管理MCP許可リストと接続監視が必要である。 |
| 12 | `hooks.<Event>[].hooks[].tool` | `string`（`mcp_tool` で必須） | `[[hooks.PostToolUse.hooks]]`<br>`type = "mcp_tool"`<br>`server = "scanner"`<br>`tool = "scan_patch"` | MCPサーバーが提供するツール名を指定する。 | ツールが存在しない、利用不能、エラーとなった場合も元操作は自動的にブロックされない。必須検査では別の同期制御を併用する。 |
| 13 | `hooks.<Event>[].hooks[].input` | JSONオブジェクト相当（`mcp_tool`、任意） | `[[hooks.PostToolUse.hooks]]`<br>`type = "mcp_tool"`<br>`server = "scanner"`<br>`tool = "scan_patch"`<br>`input = { patch = "${tool_input.command}" }` | MCPツールへ渡す引数テンプレートを指定する。イベントの値を `${field.nested}` で展開でき、省略時は空オブジェクトとなる。 | イベント入力は非信頼として扱う。テンプレート展開後の値、サイズ、秘密情報、パスをMCPサーバー側でも検証する。 |
| 14 | `hooks.<Event>[].hooks[].timeout` | `number`（秒） | `[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"`<br>`timeout = 30` | フックの最大実行時間を秒で指定する。省略時は多くのフックで600秒、`SessionEnd` は既定1秒・最大3秒である。 | 長すぎる値は操作を停止させる。MCPツールフックではフックとサーバーの短い方のタイムアウトが適用される。 |
| 15 | `hooks.<Event>[].hooks[].statusMessage` | `string` | `[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"`<br>`statusMessage = "管理ポリシーを確認中"` | フック実行中に利用者へ表示する任意の状態メッセージを指定する。 | 機密情報、内部パス、検知ロジック、認証情報を表示しない。 |
| 16 | `hooks.<Event>[].hooks[].additionalContextLimit` | `integer`; 既定2500、`0` は全量 | `[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"`<br>`additionalContextLimit = 2000` | commandフックが返す `additionalContext` をモデルへ渡す概算トークン上限を指定する。超過時は全文をディスクへ保存し、短いプレビューを渡す。 | `0` は全量であり、コンテキスト枯渇や機密情報の大量投入を招き得る。大きな出力はディスクへ保存されるため、秘密情報を返さない。 |
| 17 | `hooks.<Event>[].hooks[].async` | `boolean`; 既定 `false`（commandのみ） | `[[hooks.PostToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/audit.sh"`<br>`async = true` | `true` にするとcommandフックをバックグラウンド実行し、Codexは完了を待たずに処理を続ける。 | 非同期フックは元操作をブロック、承認、書換えできない。1セッション最大8件が同時実行され、終了時に未完了処理と未配信出力は破棄される。`SessionEnd` は常に同期である。 |

## フックイベント

この表は、管理フックを実行できるイベントの種類と、各イベントが発生するタイミングを示すものである。どの処理の前後で検査や監査を行うかを選ぶ際の対応表である。

| 項番 | イベント | 発火タイミング／matcher対象 | 主な用途と注意 |
| --- | --- | --- | --- |
| 1 | `PreToolUse` | ツールを実行する直前に発火する。matcherはツール名へ照合される。 | コマンドやMCP呼出しの検査、ブロック、入力書換え、DLP確認に使う。`Bash`、`apply_patch`、MCPツール名などを対象にできる。実行前に止める必要がある制御はこのイベントで行う。 |
| 2 | `PermissionRequest` | Codexが利用者または自動レビューへ承認要求を出す時点で発火する。matcherはツール名へ照合される。 | 承認対象の操作へ追加検査や説明を行う。承認ポリシーそのものを置き換える設定ではなく、承認が発生する範囲は別設定で決まる。 |
| 3 | `PostToolUse` | ツールの実行が完了した後に発火する。matcherはツール名へ照合される。 | 出力監査、結果検証、記録に使う。すでに実行された副作用を事前に止める用途ではない。ツール出力は非信頼入力として扱う。 |
| 4 | `PreCompact` | 会話コンテキストを圧縮する直前に発火する。matcherは `manual` または `auto` へ照合される。 | 圧縮前の会話状態を記録・検査する。大量データをフック出力へ含めず、機密情報の保存先と保持期間を管理する。 |
| 5 | `PostCompact` | 会話コンテキストを圧縮した直後に発火する。matcherは `manual` または `auto` へ照合される。 | 圧縮結果の検査や後処理に使う。重要な制約や作業条件が失われていないかを確認する用途である。 |
| 6 | `SessionStart` | セッション開始時に発火する。matcherは `startup`、`resume`、`clear`、`compact` へ照合される。 | 管理コンテキスト、注意事項、初期検査の読み込みに使う。毎回実行される可能性があるため、起動遅延と外部依存を小さくする。 |
| 7 | `SessionEnd` | メインスレッド終了時に発火する。matcherは現在 `other` であり、サブエージェントでは実行されない。 | 監査記録や終了処理に使う。既定1秒・最大3秒と短いため、重い処理や外部通信に依存させない。 |
| 8 | `SubagentStart` | サブエージェントを開始するときに発火する。matcherは起動するagent typeへ照合される。 | サブエージェントの開始記録、役割確認、追加制約の付与に使う。agent typeの具体値は起動するサブエージェントに依存する。 |
| 9 | `SubagentStop` | サブエージェントが停止するときに発火する。matcherはagent typeへ照合される。 | サブエージェントの結果検査、監査、後処理に使う。メインスレッドへ戻す内容に秘密情報や未検証出力が含まれないか確認する。 |
| 10 | `UserPromptSubmit` | 利用者がプロンプトを送信した時点で発火する。matcherは現在サポートされない。 | APIキー、パスワード、個人情報などの送信前検査に使う。誤検知で業務が止まる場合の説明、修正、問い合わせ手順を用意する。 |
| 11 | `Stop` | 1ターンの処理が停止するときに発火する。matcherは現在サポートされない。 | 完了条件の確認や、必要に応じた継続要求に使う。継続を自動要求する場合は、回数上限と停止条件を設けて無限継続を防ぐ。 |

## プラグインマーケットプレイス

この表は、ユーザーがプラグインを取得できるマーケットプレイスの供給元を制限するものである。許可するGitリポジトリ、Gitホスト、ローカルディレクトリを定義し、未承認の配布元からの追加・インストール・更新を防ぐ。

| 項番 | 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| 1 | `marketplaces` | `table` | `[marketplaces]`<br>`restrict_to_allowed_sources = true` | プラグインを取得するマーケットプレイスについて、会社が許可する供給元をまとめる親テーブルである。 | `restrict_to_allowed_sources = true` にした場合に、配下の許可ソース規則が実効化する。親テーブルだけでは未承認ソースを自動的に排除しない。 |
| 2 | `marketplaces.restrict_to_allowed_sources` | `boolean` | `[marketplaces]`<br>`restrict_to_allowed_sources = true` | `true` にすると、ユーザーによるマーケットプレイス追加、プラグインインストール、設定済みGitマーケットプレイスの更新を、管理者が許可したソースへ限定する。 | すでに設定済みのユーザーマーケットプレイスや既存プラグインを、実行時に自動除外する設定ではない。導入時に既存ソースとインストール済みプラグインを別途棚卸しする。 |
| 3 | `marketplaces.allowed_sources` | `table` | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"` | 管理者が名前を付けた許可ソース規則の一覧である。Gitリポジトリ、Gitホスト、ローカルディレクトリを個別に登録できる。 | 異なる規則名は複数の要件層で蓄積され、同名配下は通常の優先順位で解決される。重複・意図しない追加を防ぐため、規則名を台帳化する。 |
| 4 | `marketplaces.allowed_sources.<name>` | `table` | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"` | 1つの許可ソース規則を定義するテーブルである。`source` の値により、`url`、`host_pattern`、`path` のどれを使用するかが決まる。 | 規則名は用途、所有者、対象チームが分かる名前にする。不要になった規則の削除と影響確認を行う。 |
| 5 | `marketplaces.allowed_sources.<name>.source` | `git \| host_pattern \| local` | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"` | 許可ソースの照合方法を、Gitリポジトリ完全一致、Gitホストの正規表現、ローカルディレクトリのいずれかから選ぶ。 | 最も具体的な `git` または `local` を優先する。ホスト全体を許可する `host_pattern` は、同一ホスト上の未審査リポジトリまで含み得るため慎重に使う。 |
| 6 | `marketplaces.allowed_sources.<name>.url` | `string` | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"` | `source = "git"` の場合に、許可するGitリポジトリURLを指定する。正規化後のリポジトリが完全一致した場合だけ許可する。 | 組織が管理する正確なリポジトリURLだけを指定する。似た組織名やリポジトリ名、フォーク、別ホストを許可しない。 |
| 7 | `marketplaces.allowed_sources.<name>.ref` | `string`（任意） | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"`<br>`ref = "0123456789abcdef0123456789abcdef01234567"` | `source = "git"` の場合に、許可するGit refを固定する。省略すると、一致するリポジトリ内の任意refを許可する。 | 供給網リスクを下げるには、不変のコミットSHAなどへ固定する。ブランチ名やタグは同じ文字列でも参照先が変更され得るため、更新承認手順を設ける。 |
| 8 | `marketplaces.allowed_sources.<name>.host_pattern` | `string`（正規表現） | `[marketplaces.allowed_sources."<name>"]`<br>`source = "host_pattern"`<br>`host_pattern = '^git\.example\.com$'` | `source = "host_pattern"` の場合に、Git URLから抽出した小文字ホスト名へ照合する正規表現を指定する。 | `^` と `$` でホスト名全体へ一致させる。例として `^git\.example\.com$` のようにドットをエスケープし、サブドメインや似たホストを誤許可しない。 |
| 9 | `marketplaces.allowed_sources.<name>.path` | `string`（絶対パス） | `[marketplaces.allowed_sources."<name>"]`<br>`source = "local"`<br>`path = "/opt/company/codex-marketplace"` | `source = "local"` の場合に、許可するローカルマーケットプレイスの絶対ディレクトリパスを指定する。正規化後のパスで比較する。 | 管理者だけが書き込めるディレクトリを使用し、相対パスは使わない。配下のプラグイン更新、署名、ハッシュ、配布元を管理する。 |

## MCPサーバー許可リスト

この表は、Codexへ追加のツールやデータ接続を提供するMCPサーバーについて、会社が許可したサーバーだけを有効化するためのものである。サーバーIDだけでなく、実行ファイル、引数、または接続URLまで照合し、同名の別サーバーへの差し替えを防ぐ。

| 項番 | 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| 1 | `mcp_servers` | `table` | `[mcp_servers."<id>".identity]`<br>`url = "https://mcp.example.com/v1"` | ローカルクライアントが有効化できるMCPサーバーを、完全許可リストとして定義する。設定名とidentityの両方が一致したサーバーだけを有効化する。 | テーブルが存在して空の場合はすべてのMCPサーバーが無効になる。許可リスト外またはidentity不一致も無効化されるため、必要サーバーのID・実行方法・URLを台帳と一致させる。 |
| 2 | `mcp_servers.<id>.identity` | `table` | `[mcp_servers."<id>".identity]`<br>`url = "https://mcp.example.com/v1"` | 1つのMCPサーバーが会社承認済みの実体かを確認する同一性規則である。stdio方式は `command`、streamable HTTP方式は `url` のどちらかを設定する。 | サーバー名だけでなく、実行ファイルまたは接続URLまで固定する。同じ名前を使う別プログラムや別ホストへの差し替えを防ぐ。 |
| 3 | `mcp_servers.<id>.identity.command` | `string \| table` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"` | stdio方式のMCPサーバーを、コマンド文字列または構造化された実行ファイル・引数で照合する。string形式はcommand文字列だけ、table形式は実行ファイルと順序付き引数を厳密に確認する。 | string形式は `args`、`cwd`、`env`、`env_vars` を検査しないため弱い。会社許可サーバーは構造化tableを使い、環境変数と作業ディレクトリは別統制で確認する。 |
| 4 | `mcp_servers.<id>.identity.command.executable` | `string` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"` | stdio MCPを起動する実行ファイルが一致すべき正確なパスまたは名前を指定する。 | 可能なら管理者配布先の絶対パスを使い、PATH上の同名バイナリへ差し替わるPATHハイジャックを避ける。ファイル所有者と更新元も確認する。 |
| 5 | `mcp_servers.<id>.identity.command.args` | `array<table>` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[mcp_servers."<id>".identity.command.args]]`<br>`match = "exact"`<br>`value = "--stdio"` | stdio MCPへ渡す引数を位置ごとに照合する規則配列である。設定された引数は、同じ個数・同じ順序で全位置が一致する必要がある。 | 不要な可変引数を許可しない。なお、`cwd`、`env`、`env_vars` は照合対象外であるため、引数が一致しても実行環境全体が同一とは限らない。 |
| 6 | `mcp_servers.<id>.identity.command.args[].match` | `exact \| prefix \| regex` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[mcp_servers."<id>".identity.command.args]]`<br>`match = "exact"`<br>`value = "--stdio"` | その位置の引数を、完全一致 `exact`、先頭一致 `prefix`、正規表現 `regex` のどれで照合するかを指定する。 | 可能な限り `exact` を使う。`prefix` と `regex` は意図しない値まで許可しやすいため、許可範囲と境界条件をレビューする。 |
| 7 | `mcp_servers.<id>.identity.command.args[].value` | `string` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[mcp_servers."<id>".identity.command.args]]`<br>`match = "prefix"`<br>`value = "--workspace="` | `exact` または `prefix` で照合する引数値を指定する。 | シェルメタ文字、パス区切り、テナントIDなどの境界を考慮し、必要最小限の文字列にする。`prefix` では後続文字列に危険な値を入れられないか確認する。 |
| 8 | `mcp_servers.<id>.identity.command.args[].expression` | `string`（正規表現） | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[mcp_servers."<id>".identity.command.args]]`<br>`match = "regex"`<br>`expression = '^--tenant=[a-z0-9-]+$'` | `regex` で引数を照合する正規表現を指定する。式は引数値全体へ一致する必要がある。 | 全体一致でも `.*` など過度に広い式は避ける。文字種、長さ、区切り、許可値を具体的に制限し、正例と負例をテストする。 |
| 9 | `mcp_servers.<id>.identity.url` | `string \| table` | `[mcp_servers."<id>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | streamable HTTP方式のMCPサーバーURLを、正確な文字列または `exact` / `prefix` / `regex` のmatcherで照合する。 | HTTPSと組織管理ホストを優先し、原則 `exact` を使う。`prefix` で別パス、別テナント、危険なクエリまで広げない。 |
| 10 | `mcp_servers.<id>.identity.url.match` | `exact \| prefix \| regex` | `[mcp_servers."<id>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | 設定されたMCP URLを、完全一致 `exact`、先頭一致 `prefix`、正規表現 `regex` のどれで照合するかを指定する。 | 原則 `exact` を使う。柔軟な照合が必要な場合も、スキーム、ホスト、ポート、パス境界が変わらないよう制限する。 |
| 11 | `mcp_servers.<id>.identity.url.value` | `string` | `[mcp_servers."<id>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | `exact` または `prefix` で照合するMCP URLの値を指定する。 | スキーム、完全なホスト名、必要なポート、パス境界まで含める。`prefix` の末尾位置により、想定外のサブパスやホスト文字列を許可しないか確認する。 |
| 12 | `mcp_servers.<id>.identity.url.expression` | `string`（正規表現） | `[mcp_servers."<id>".identity.url]`<br>`match = "regex"`<br>`expression = '^https://mcp\.example\.com/v[0-9]+$'` | `regex` でMCP URLを照合する正規表現を指定する。式はURL全体へ一致する必要がある。 | ホスト名のドットをエスケープし、`^` と `$` でアンカーする。スキーム、ポート、パス、バージョン部分を必要以上に広く許可しない。 |

## プラグイン同梱MCPサーバー

この表は、プラグインに同梱されるMCPサーバーを、プラグインIDとサーバーIDの組合せごとに許可するものである。トップレベルのMCP許可リストと同様に、実行ファイル・引数・URLを照合して、未承認の同梱サーバーを無効化する。

| 項番 | 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| 1 | `plugins` | `table` | `[plugins."<plugin>".mcp_servers."<server>".identity]`<br>`url = "https://mcp.example.com/v1"` | プラグインIDごとに、そのプラグインへ同梱されたMCPサーバーの許可リストを定義する親テーブルである。 | このテーブルが存在する場合、一致するプラグインとサーバー項目がない同梱MCPは無効になる。プラグイン機能全体を止める場合は `features.plugins = false` を使う。 |
| 2 | `plugins.<plugin>.mcp_servers` | `table` | `[plugins."<plugin>".mcp_servers."<server>".identity]`<br>`url = "https://mcp.example.com/v1"` | 1つのプラグインに同梱されるMCPサーバーを、サーバーIDごとに許可するテーブルである。 | トップレベルMCPと同じidentity形式を使う。プラグイン更新により同梱サーバーが変わる可能性があるため、バージョン更新時に再照合する。 |
| 3 | `plugins.<plugin>.mcp_servers.<server>.identity` | `table` | `[plugins."<plugin>".mcp_servers."<server>".identity]`<br>`url = "https://mcp.example.com/v1"` | 1つのプラグイン同梱MCPが会社承認済みの実体かを確認する同一性規則である。 | stdio方式は `command`、streamable HTTP方式は `url` のどちらかを設定する。名前だけでなく実行方法または接続先を固定する。 |
| 4 | `plugins.<plugin>.mcp_servers.<server>.identity.command` | `string \| table` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"` | 同梱されたstdio MCPサーバーを、command文字列または構造化された実行ファイル・引数で照合する。 | string形式は引数、作業ディレクトリ、環境変数を検査しない。構造化形式を優先し、プラグイン配下の実行ファイルが管理対象か確認する。 |
| 5 | `plugins.<plugin>.mcp_servers.<server>.identity.command.executable` | `string` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"` | 同梱stdio MCPを起動する実行ファイルを完全一致で指定する。 | 可能なら絶対パスを使い、同名バイナリへの差し替えを防ぐ。プラグイン更新後もパスとファイルの整合性を確認する。 |
| 6 | `plugins.<plugin>.mcp_servers.<server>.identity.command.args` | `array<table>` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[plugins."<plugin>".mcp_servers."<server>".identity.command.args]]`<br>`match = "exact"`<br>`value = "--stdio"` | 同梱stdio MCPへ渡す引数を位置ごとに照合する規則配列である。引数の順序と個数も完全一致する。 | `cwd`、`env`、`env_vars` は照合対象外である。可変引数を最小限にし、実行環境は別の端末管理で統制する。 |
| 7 | `plugins.<plugin>.mcp_servers.<server>.identity.command.args[].match` | `exact \| prefix \| regex` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[plugins."<plugin>".mcp_servers."<server>".identity.command.args]]`<br>`match = "exact"`<br>`value = "--stdio"` | その位置の引数を `exact`、`prefix`、`regex` のどれで照合するか指定する。 | 原則 `exact` を使う。`prefix` と `regex` を使う場合は、許可される全パターンを正例・負例でテストする。 |
| 8 | `plugins.<plugin>.mcp_servers.<server>.identity.command.args[].value` | `string` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[plugins."<plugin>".mcp_servers."<server>".identity.command.args]]`<br>`match = "prefix"`<br>`value = "--workspace="` | `exact` または `prefix` で照合する引数値を指定する。 | 後続文字列へ任意パスやコマンドを入れられないよう、最小の許可範囲と境界を定義する。 |
| 9 | `plugins.<plugin>.mcp_servers.<server>.identity.command.args[].expression` | `string`（正規表現） | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[plugins."<plugin>".mcp_servers."<server>".identity.command.args]]`<br>`match = "regex"`<br>`expression = '^--tenant=[a-z0-9-]+$'` | `regex` で引数を照合する、引数値全体への正規表現を指定する。 | `.*` など広すぎる式を避け、文字種、長さ、区切り、許可値を具体的に制限する。 |
| 10 | `plugins.<plugin>.mcp_servers.<server>.identity.url` | `string \| table` | `[plugins."<plugin>".mcp_servers."<server>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | 同梱されたstreamable HTTP MCPのURLを、完全一致またはmatcherで照合する。 | 原則としてHTTPSと `exact` を使う。プラグイン更新で接続先が変わる場合は、変更理由と所有者を確認してから許可リストを更新する。 |
| 11 | `plugins.<plugin>.mcp_servers.<server>.identity.url.match` | `exact \| prefix \| regex` | `[plugins."<plugin>".mcp_servers."<server>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | 同梱MCP URLを `exact`、`prefix`、`regex` のどれで照合するか指定する。 | 原則 `exact` を使い、柔軟な照合ではスキーム、ホスト、ポート、パス境界を固定する。 |
| 12 | `plugins.<plugin>.mcp_servers.<server>.identity.url.value` | `string` | `[plugins."<plugin>".mcp_servers."<server>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | `exact` または `prefix` で照合する同梱MCPのURL値を指定する。 | スキーム、ホスト、ポート、パスを明確にし、`prefix` で想定外のサブパスや類似ホストを許可しない。 |
| 13 | `plugins.<plugin>.mcp_servers.<server>.identity.url.expression` | `string`（正規表現） | `[plugins."<plugin>".mcp_servers."<server>".identity.url]`<br>`match = "regex"`<br>`expression = '^https://mcp\.example\.com/v[0-9]+$'` | `regex` で同梱MCP URLを照合する、URL全体への正規表現を指定する。 | ホスト名のドットなどを正しくエスケープし、`^` と `$` でアンカーする。許可するバージョンやパスを必要以上に広げない。 |

## ホスト別旧サンドボックス制約

この表は、接続先または実行先のホスト名に応じて、旧方式のサンドボックスモードを切り替えるものである。特定のビルド端末だけ書き込みを許可するなどの互換用途に使うが、新しい権限プロファイルをホスト別に切り替える設定ではない。

| 項番 | 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| 1 | `remote_sandbox_config` | `array<table>` | `[[remote_sandbox_config]]`<br>`hostname_patterns = ["build-*.corp.example"]`<br>`allowed_sandbox_modes = ["read-only", "workspace-write"]` | ホスト名のパターンに応じて、旧 `sandbox_mode` 方式で選択できるサンドボックスモードを変える規則配列である。 | 現在上書きできるのは `allowed_sandbox_modes` だけであり、権限プロファイルをホスト別に切り替える設定ではない。新規導入では権限プロファイルを優先する。 |
| 2 | `remote_sandbox_config[].hostname_patterns` | `array<string>` | `[[remote_sandbox_config]]`<br>`hostname_patterns = ["build-*.corp.example"]`<br>`allowed_sandbox_modes = ["read-only"]` | 規則を適用するホスト名を、大文字小文字を区別しないパターンで指定する。`*` は任意長、`?` は1文字に一致する。 | 取得するホスト名はベストエフォートで、FQDNを優先しローカル名へフォールバックする。認証済み端末の証明にはならないため、高権限付与の唯一の条件にしない。 |
| 3 | `remote_sandbox_config[].allowed_sandbox_modes` | `array<string>` | `[[remote_sandbox_config]]`<br>`hostname_patterns = ["build-*.corp.example"]`<br>`allowed_sandbox_modes = ["read-only", "workspace-write"]` | ホスト名パターンに一致した端末へ適用する、旧サンドボックスモードの許可リストを指定する。 | 同一要件ソース内では最初に一致した規則が優先される。広いパターンが先に一致して例外規則を隠さないよう、規則順序をセキュリティ順にレビューする。 |

## 管理コマンドルール

この表は、ローカルコマンドの先頭部分をパターン照合し、該当するコマンドに承認を要求するか、実行を禁止するかを管理者が強制するものである。削除、外部送信、管理者操作など、会社PCで避けたいコマンドの追加防御として使う。

| 項番 | 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| 1 | `rules` | `table` | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`justification = "会社PCでは再帰削除を禁止する。"`<br>`pattern = [{ token = "rm" }, { any_of = ["-rf", "-fr"] }]` | ローカルの `.rules` ファイルと合成される、管理者強制のコマンドルールをまとめる親テーブルである。複数ルールが一致した場合は最も制限的な決定が優先される。 | 要件ルールは権限を緩める用途には使えず、`allow` を指定できない。コマンドルールだけに依存せず、サンドボックス、ファイル拒否、ネットワーク制約と併用する。 |
| 2 | `rules.prefix_rules` | `array<table>` | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`pattern = [{ token = "rm" }, { any_of = ["-rf", "-fr"] }]` | コマンドの先頭トークン列へ一致させる規則の一覧である。各規則に、照合パターン `pattern` と処置 `decision` が必要である。 | シェル文字列全体ではなく、分割されたトークン列として設計する。絶対パス、ラッパー、別名、オプション順序などによる迂回を実機テストする。 |
| 3 | `rules.prefix_rules[].decision` | `prompt \| forbidden` | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`pattern = [{ token = "rm" }, { any_of = ["-rf", "-fr"] }]` | 規則に一致したコマンドの処置を指定する。`prompt` は実行前に承認を要求し、`forbidden` は実行を拒否する。 | 要件では `allow` を指定できない。不可逆な削除、管理者権限操作、資格情報抽出、外部持ち出しなどは `forbidden` を検討する。 |
| 4 | `rules.prefix_rules[].justification` | `string`（任意、非空） | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`justification = "会社PCでは再帰削除を禁止する。"`<br>`pattern = [{ token = "rm" }, { token = "-rf" }]` | 承認画面または拒否メッセージへ表示する、規則適用の理由を指定する。 | 利用者が判断できる具体的な理由と、安全な代替手段を記載する。内部の検知条件、機密パス、回避方法につながる詳細は書かない。 |
| 5 | `rules.prefix_rules[].pattern` | `array<table>` | `[[rules.prefix_rules]]`<br>`decision = "prompt"`<br>`pattern = [{ token = "git" }, { any_of = ["push", "commit"] }]` | コマンドの先頭部分を、トークン位置ごとの配列として表す。各位置は1つの文字列 `token` または複数候補 `any_of` のどちらかである。 | すべての危険な変形を1つのprefix規則で網羅できるとは限らない。異なる実行ファイル名、シェルラッパー、スクリプト経由も含めて試験し、サンドボックスで補完する。 |
| 6 | `rules.prefix_rules[].pattern[].token` | `string` | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`pattern = [{ token = "rm" }, { token = "-rf" }]` | そのトークン位置で完全一致させる1つのリテラル文字列を指定する。 | 大文字小文字、絶対パス、別バイナリ名、OSごとのコマンド名を確認する。例として `rm` だけでなく `/bin/rm` 経由も検討する。 |
| 7 | `rules.prefix_rules[].pattern[].any_of` | `array<string>` | `[[rules.prefix_rules]]`<br>`decision = "prompt"`<br>`pattern = [{ token = "git" }, { any_of = ["push", "commit"] }]` | そのトークン位置で一致を許す複数の候補文字列を指定する。いずれか1つに一致すれば、その位置は一致となる。 | 候補を広げすぎない。例として `git` の次の `push` と `commit` だけを対象にするなど、危険操作の範囲を明確にする。 |

## native Windows要件

この節は、native Windows上でCodexのローカルコマンドを隔離するサンドボックス実装を管理するものである。`elevated` と `unelevated` は、コマンドへ管理者権限を与えるかどうかの選択ではない。どのOSレベルの分離方式を使うかの選択である。WSL2はLinuxサンドボックスであり、この節の `windows.allowed_sandbox_implementations` では制御しない。

### `elevated` と `unelevated` の違い

この表は、両方式の境界、前提、失敗時の扱いを比較するものである。

| 項番 | 比較項目 | `elevated` | `unelevated` | 運用上の意味 |
| --- | --- | --- | --- | --- |
| 1 | 位置付け | 推奨される、最も強いnative Windowsサンドボックスである。 | 管理者承認付きセットアップを完了できない場合のフォールバックである。 | 会社標準は原則 `elevated` とし、`unelevated` は期限付き例外として扱う。 |
| 2 | 実行ユーザー | 専用の低権限サンドボックスユーザーでコマンドを実行する。 | 現在のログインユーザーから作る制限付きWindowsトークンでコマンドを実行する。 | `elevated` は名称に反して、コマンドを管理者として実行する設定ではない。 |
| 3 | ファイル境界 | 専用ユーザーとファイルシステム権限境界を使う。 | NTFS ACLを中心に境界を作る。すべてのread/write分割を強制できず、未対応ポリシーは拒否される。 | 複雑な読取／書込分離を求めるほど `elevated` が適する。 |
| 4 | ネットワーク境界 | 専用サンドボックスユーザー向けのファイアウォール規則とローカルポリシーを使える。 | 専用オフラインユーザーのファイアウォール規則ではなく、環境レベルのオフライン制御を使う。ネットワーク分離は弱い。 | `[experimental_network]` を使う場合も、`unelevated` を `elevated` と同等とみなさず、別試験が必要である。 |
| 5 | セットアップ権限 | 管理者承認付きセットアップが必要である。 | `elevated` 特有の管理者承認セットアップを前提としない。 | UAC、GPO、EDR等で管理者セットアップが阻害される端末では `elevated` を使えない場合がある。 |
| 6 | 失敗時 | UAC拒否、ユーザー／グループ作成禁止、ファイアウォール変更禁止、ログオン権限不足等で失敗する。 | `elevated` が失敗しても作業を継続するために使えるが、長期推奨構成ではない。 | `allowed_sandbox_implementations = ["elevated"]` はフォールバックを禁止するため、配布前に全端末の前提確認が必要である。 |
| 7 | UI分離 | 既定でプライベートデスクトップを使う。 | 既定でプライベートデスクトップを使う。 | `sandbox_private_desktop = false` は互換性が必要な場合だけ使用する。 |
| 8 | 実験的ネットワークとの同等性 | Windows対応自体が限定的であり、実機試験が必要である。 | 各プロトコル・機能が `elevated` と同等に強制されるかの公式対応表はない。 | 同等性は **不明** である。allow／deny、IP直指定、ローカル宛先、上流プロキシをモード別に試験する。 |

### `elevated` を必須化する前の確認

この表は、`allowed_sandbox_implementations = ["elevated"]` を全社配布する前に確認する前提条件を示すものである。

| 項番 | 確認項目 | 合格条件 | 不合格時の影響 |
| --- | --- | --- | --- |
| 1 | Windows版 | Windows 11を標準とする。Windows 10を使う場合は完全更新済みで、1809以降かつConPTY等の必要機能を確認する。 | Windows 10はbest effortであり、古いビルドはセットアップ・コンソール・サンドボックスの失敗が増える。 |
| 2 | `winget` | Windows Package Managerを利用できる。 | 公式資料が示す環境前提を満たさず、セットアップや依存関係導入に支障が出る可能性がある。 |
| 3 | 管理者承認 | UACまたは管理者承認付きセットアップを完了できる。 | `elevated` の初期セットアップを完了できない。 |
| 4 | ローカルユーザー／グループ | 端末ポリシーが必要なローカルユーザー／グループ作成を許可する。 | 専用の低権限サンドボックスユーザー境界を作成できない。 |
| 5 | ファイアウォール規則 | Windows Firewall規則の作成・変更を端末ポリシーが許可する。 | 専用サンドボックスユーザー向けのネットワーク分離を構成できない。 |
| 6 | ログオン権限 | サンドボックスユーザーに必要なログオン種別をGPO／ローカルポリシーが許可する。 | Windowsエラー1385等で、ユーザー作成後もサンドボックス化コマンドを起動できない。 |
| 7 | フォルダーACL | Codexが警告するフォルダーに、不要な `Everyone` 書込権限がない。 | 広すぎるACLによりサンドボックスが十分に保護できない。 |
| 8 | EDR・GPO・OU | ユーザー作成、ファイアウォール、ログオン、プロセス生成を阻害するルールがない。OUや端末群の差も確認する。 | 一部端末だけセットアップが失敗し、保証強度が不均一になる。 |
| 9 | フォールバック方針 | `elevated` 失敗端末を業務停止、例外申請、または一時的 `unelevated` のどれで扱うかを決める。 | `["elevated"]` では `unelevated` を選択できない。正確なUI・エラー表示はクライアントにより異なり、公開資料では不明である。 |
| 10 | パイロット | 代表端末でファイル読取／書込、ネットワーク、承認、再起動、ポリシー変更、エラー時ログを確認する。 | 設定配布後に初めて端末ポリシーとの競合が判明し、業務が停止する。 |

### 設定キー一覧

この表は、native Windowsで許可するサンドボックス実装と、プライベートデスクトップの利用を設定する各キーを示すものである。

| 項番 | 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| 1 | `windows` | `table` | `[windows]`<br>`allowed_sandbox_implementations = ["elevated"]`<br>`sandbox_private_desktop = true` | native Windowsサンドボックスで許可する実装と、子プロセスを専用デスクトップで動かすかをまとめる親テーブルである。 | PowerShell等のnative実行に適用する。WSL2はLinuxサンドボックスであり、別の前提と試験が必要である。 |
| 2 | `windows.allowed_sandbox_implementations` | `array<string>`: `elevated`, `unelevated`（空不可） | `[windows]`<br>`allowed_sandbox_implementations = ["elevated"]` | ユーザーまたはクライアントが選択できるnative Windowsサンドボックス実装を完全許可リストで限定する。両方を許可し未選択の場合は `elevated` が優先される。 | 値は「強さの設定値」ではなく、利用を許可する実装の集合である。空配列は無効である。 |
| 3 | `windows.allowed_sandbox_implementations` | `["elevated"]` | `[windows]`<br>`allowed_sandbox_implementations = ["elevated"]` | `elevated` だけを許可し、`unelevated` への切替を禁止する。専用低権限ユーザー、ファイル境界、ファイアウォール規則を使う強い実装を必須にする。 | 管理者承認、ユーザー／グループ作成、ファイアウォール変更、ログオン権限が全端末で必要である。前提を満たせない端末には許可されたフォールバックがない。コマンドを管理者権限で動かす設定ではない。 |
| 4 | `windows.allowed_sandbox_implementations` | `["unelevated"]` | `[windows]`<br>`allowed_sandbox_implementations = ["unelevated"]` | `unelevated` だけを許可する。現在ユーザー由来の制限付きトークン、ACL境界、環境レベルのオフライン制御を使う。 | ネットワーク分離が弱く、すべてのread/write分割を強制できない。公式資料は長期の推奨企業構成としていない。期限付き例外として扱う。 |
| 5 | `windows.allowed_sandbox_implementations` | `["elevated", "unelevated"]` | `[windows]`<br>`allowed_sandbox_implementations = ["elevated", "unelevated"]` | 両方を許可する。モードが未選択の場合は `elevated` が優先される。 | 可用性は上がるが、保証強度が混在する。公開資料は自動フォールバックの条件・UI・監査方法を一律に説明していないため、その詳細は **不明** である。 |
| 6 | `windows.sandbox_private_desktop` | `boolean` | `[windows]`<br>`sandbox_private_desktop = true` | 最終サンドボックス子プロセスを、通常のユーザーデスクトップから分離したプライベートデスクトップで実行するか固定する。 | 既定は両モードでプライベートデスクトップである。旧 `Winsta0\Default` との互換性が必要な場合だけ `false` を試験する。 |

## 会社導入向け・保守的な初期テンプレート

以下は **機能を絞って開始する例** であり、組織の業務要件、OS、更新方式、コネクタ利用、EDR、プロキシに合わせて調整する。Codex 0.138.0以上を前提とし、実験的な `[experimental_network]` は初期テンプレートから外している。

```toml
# Codex 0.138.0+ を前提とする、保守的な初期例

allow_appshots = false
allow_login_shell = false
allow_remote_control = false

# サンドボックス境界を越えるときに承認を要求
allowed_approval_policies = ["on-request"]
allowed_approvals_reviewers = ["user"]

# live/indexed検索を禁止。disabled は暗黙に許可される
allowed_web_search_modes = ["cached"]

# 中央更新を行わない場合の例。MDMで更新するなら運用に合わせて変更
check_for_update_on_startup = true

# 権限プロファイル方式（0.138.0+）
default_permissions = ":workspace"

[allowed_permission_profiles]
":read-only" = true
":workspace" = true
":danger-full-access" = false

[computer_use]
allow_locked_computer_use = false

[feedback]
enabled = false

[features]
apps = false
browser_use = false
browser_use_external = false
browser_use_full_cdp_access = false
computer_use = false
hooks = false
in_app_browser = false
memories = false
multi_agent = false
plugin_sharing = false
plugins = false
remote_plugin = false
skill_mcp_dependency_install = false

# 管理者強制の読取拒否。Windowsのシェル子プロセスには制限がある点に注意
[permissions.filesystem]
deny_read = [
  "~/.ssh",
  "~/.aws",
  "~/.azure",
  "~/.config/gcloud",
]
```

### 管理フックを使う場合の差分

`features.hooks = false` を削除または `true` にし、次のように管理フックだけを許可する。スクリプトはポリシーでは配布されない。

```toml
allow_managed_hooks_only = true

[features]
hooks = true

[hooks]
managed_dir = "/enterprise/hooks"
windows_managed_dir = "C:\\enterprise\\hooks"

[[hooks.PreToolUse]]
matcher = "^Bash$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "python3 /enterprise/hooks/pre_tool_use_policy.py"
command_windows = "py -3 C:\\enterprise\\hooks\\pre_tool_use_policy.py"
timeout = 30
statusMessage = "Checking managed command"
```

### native Windowsで `elevated` を必須にする場合の差分

次の設定は、native Windowsで `elevated` だけを許可し、`unelevated` への切替を禁止する。前述の管理者承認、ローカルユーザー／グループ、ファイアウォール、ログオン権限を全端末で確認してから配布する。`elevated` はコマンドを管理者権限で実行する設定ではなく、専用の低権限サンドボックスユーザーを使う強い分離方式である。

```toml
[windows]
allowed_sandbox_implementations = ["elevated"]
sandbox_private_desktop = true
```

前提を満たせない端末では `unelevated` へ切り替えられない。Codex全体がどの画面・範囲で失敗するかはクライアントごとに異なり、公開資料では一律に説明されていないため、代表端末で障害時挙動を確認する。

## 配布前チェックリスト

この表は、`requirements.toml` を会社PCへ配布する前に、設定だけでなく端末、更新、秘密情報、外部連携、監査、運用体制まで確認するためのチェックリストである。各項目の合格条件を満たしたことを確認してから、段階的に全社展開する。

| 項番 | 確認項目 | 合格条件 |
| --- | --- | --- |
| 1 | クライアント台帳 | 対象のChatGPTデスクトップアプリ、Codex CLI、IDE拡張、OS、バージョン、配布方式を台帳化している。使用する各キーの対応版を満たし、権限プロファイルを使う端末はCodex 0.138.0以上である。 |
| 2 | 権限制御方式 | `allowed_permission_profiles` と `default_permissions` を主方式としている。旧 `sandbox_mode` / `sandbox_workspace_write` を各設定から除去し、旧版混在期間だけ `allowed_sandbox_modes` を互換制約として残している。 |
| 3 | 既定プロファイル | `default_permissions` が読み込まれる組込み／カスタムプロファイル名と一致し、`allowed_permission_profiles` で明示的に許可されている。 |
| 4 | 許可リストの閉じ方 | `allowed_permission_profiles`、MCP、プラグイン同梱MCP、marketplaceについて、省略・空テーブル・`false` の意味を実機確認している。特に空の `mcp_servers` が全MCP無効になることを確認している。 |
| 5 | Web・外部連携 | Web検索、Apps、MCP、Plugins、Browser、Computer Use、シェルネットワークを別々の外部接続面として評価している。使わない機能を明示的に無効化し、外部サービス側の権限も最小化している。 |
| 6 | 秘密情報 | `permissions.filesystem.deny_read` とカスタムプロファイルの `deny` を設定し、`.env`、SSH鍵、クラウド資格情報、個人情報を実機テストしている。native Windowsのシェル子プロセス制限はNTFS ACL、資格情報保管、EDR／DLPで補完している。 |
| 7 | ネットワーク二段階 | コマンド通信の許可とプロキシの有効化を別々に確認している。通信ON／プロキシOFFでドメインルールが効かず直接通信になることを理解し、この状態を配布しない。 |
| 8 | 実験的ネットワーク | `experimental_network.enabled = true`、管理allow規則、`managed_allowed_domains_only`、ポート、上流プロキシ、OS対応を確認している。Windowsは `elevated`／`unelevated` 別にパイロットし、同等性を前提にしていない。 |
| 9 | native Windows `elevated` | Windows版、`winget`、UAC、ローカルユーザー／グループ、ファイアウォール、ログオン権限、Everyone書込ACL、EDR／GPOを確認している。`["elevated"]` がフォールバックを禁止することを理解している。 |
| 10 | native Windows例外 | `unelevated` を許可する端末、理由、期限、解消担当を台帳化し、弱いネットワーク分離と未対応read/write分割を負の試験で確認している。 |
| 11 | フック | `[features].hooks = true`、`[hooks]`、スクリプト配布、管理者のみ書込可能な絶対パス、署名／ハッシュ、タイムアウト、並行実行、障害時挙動を確認している。非同期フックとMCPツールフックを必須ブロック制御に単独使用していない。 |
| 12 | 更新 | アプリ内更新または中央更新のどちらかを必ず運用し、担当者、更新期限、失敗端末の検知・復旧手順を定めている。`check_for_update_on_startup` と `features.in_app_updates` が更新方式と矛盾していない。 |
| 13 | 監査ログ | `log_dir` を設定する場合、平文TUIログを含む保存内容、ACL、ディスク暗号化、SIEM等への転送、保持期間、削除、バックアップ、個人情報の取扱いを確認している。 |
| 14 | パイロット | 小規模グループへ先行配布し、許可操作、拒否操作、承認、オフライン起動、ポリシー取得失敗、更新、複数要件層のマージ、ロールバックを確認してから全社配布している。 |
| 15 | RBAC | クラウド要件とは別に、ChatGPTワークスペースの座席、ロール、RBAC、コネクタAction control、外部サービス権限を設定し、退職・異動時の剥奪手順も定めている。 |

## 公開リファレンス外のキーの扱い

公開 `requirements.toml` リファレンスに掲載されていないキーは、クラウドポリシーでの正式サポート範囲、対応クライアント／バージョン、安定性を公開資料から確認できないため **不明** とする。本番では、上記の公開キー一覧と、同リファレンスから明示的に参照されるPermissions／Hooks下位スキーマだけを使用する。

## 公式参照先

- OpenAI Configuration Reference — `requirements.toml`: https://developers.openai.com/codex/config-reference#requirementstoml
- OpenAI Managed configuration: https://developers.openai.com/codex/enterprise/managed-configuration
- OpenAI Config basics: https://developers.openai.com/codex/config-basic
- OpenAI Advanced configuration: https://developers.openai.com/codex/config-advanced
- OpenAI Permissions: https://learn.chatgpt.com/docs/permissions
- OpenAI Hooks: https://learn.chatgpt.com/docs/hooks
- OpenAI Agent approvals & security: https://learn.chatgpt.com/docs/agent-approvals-security
- OpenAI Rules: https://learn.chatgpt.com/docs/agent-configuration/rules
- OpenAI Windows sandbox: https://learn.chatgpt.com/docs/windows/windows-sandbox
- Cloud policy administration: https://chatgpt.com/codex/cloud/settings/policies

> 公式ドキュメントは更新される。本資料は2026-08-25時点の公開資料で再確認したものである。ポリシー変更時は、上記Configuration Referenceの `requirements.toml` 節、Permissions、Windows sandbox、Hooksを再確認し、未掲載キーや説明のない挙動は「不明」として扱う。
