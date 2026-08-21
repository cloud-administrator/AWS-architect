# Codex `requirements.toml` 設定項目一覧（会社PC向け）

**調査日:** 2026-08-21  
**対象:** ChatGPT Business / Enterprise のクラウド管理ポリシー、および対応するCodexローカルクライアント  
**基準:** OpenAIが公開している `requirements.toml` リファレンスを正とし、同リファレンスから明示的に参照される Permissions、Hooks、承認・サンドボックスの公式資料で下位スキーマを補完。

> **重要:** この資料は `config.toml` の全項目一覧ではない。`requirements.toml` で管理者が強制できる公開項目と、その項目から参照される下位設定だけを扱う。公開 `requirements.toml` リファレンスにないキーは、実装上存在して見える場合でもクラウドポリシーでの正式サポートが **不明** であるため、本番ポリシーには使用しない。

## 最初に理解すべき適用ルール

| 論点 | 内容 | 会社導入時の意味 |
| --- | --- | --- |
| 強制設定と既定値の違い | `requirements.toml` は管理者強制の制約で、ユーザーは回避できない。`managed_config.toml` の管理既定値は起動時の初期値であり、実行中に変更できる。 | セキュリティ境界は `requirements.toml` に置く。単なる推奨値を強制設定と取り違えない。 |
| 省略したキー | 省略したキーは「禁止」ではなく「制約なし」。通常の製品可用性、ユーザー設定、プロジェクト設定などに従う。 | 禁止したい機能は明示的に `false` または許可リストで閉じる。 |
| 対象クライアント | ChatGPTデスクトップアプリ、Codex CLI、IDE拡張などの対応ローカルクライアント。キーの対応状況はクライアントとバージョンで異なる。 | 組織全体配布前に、利用OS・クライアント・バージョンの組合せで試験する。 |
| 権限プロファイルの最低バージョン | `allowed_permission_profiles` と管理された `default_permissions` は Codex 0.138.0 以降。0.137.0以前は無視する。 | 全端末を0.138.0以上に更新してから権限プロファイルを主制御にする。混在期間は `allowed_sandbox_modes` を暫定互換制約として併用できる。 |
| 推奨する権限制御 | 0.138.0以降は `allowed_permission_profiles` と `default_permissions` を優先する。`allowed_sandbox_modes` は旧 `sandbox_mode` 利用環境向け。 | 新規導入では権限プロファイルを基準にし、旧方式との混在を長期化させない。 |
| クラウドポリシーの位置付け | クラウド管理ポリシーは `requirements.toml` 互換ポリシーの配布経路。ChatGPTワークスペースへのアクセス付与、座席割当、RBACの代替ではない。 | ワークスペース権限と端末ランタイム権限を別々に設計する。 |
| クラウド取得失敗時 | 有効な署名済みキャッシュがなく、クラウド要件取得にも失敗した場合、クライアントは要件を無視して起動せずエラーを返す。バックグラウンド更新は次回起動用で、現在プロセスの要件を差し替えない。 | 管理ポリシーなしで黙って起動するフェイルオープンではない。ネットワーク遮断時の起動試験も行う。 |
| 要件の優先順位 | 低→高: ①システム `requirements.toml`、②クラウド管理要件、③旧 `managed_config.toml` の要件互換フィールド、④macOS MDM `requirements_toml_base64`。 | 同じキーが複数層にある場合、上位層が強い。意図しない上書きを防ぐため配布元を棚卸しする。 |
| マージ方法 | 通常のスカラー値・配列は上位層が置換し、テーブルはキー単位でマージする。Rules、Hooks、ファイルシステム制約などは項目固有の合成規則を持つ。 | 「全部同じ方法でマージされる」と仮定しない。複数ポリシー割当時に実効値を検証する。 |
| `models.new_thread` | 新規スレッドの管理既定値であり、強制ではない。明示的なCLIフラグや `--config` 選択で上書きできる。 | モデルを絶対固定するためのセキュリティ制御としては使わない。 |

## 表記

| 表記 | 意味 |
| --- | --- |
| `<id>` | アプリIDまたはMCPサーバーID。実際の設定名に置き換える。 |
| `<name>` | 管理者が付けるルール名、またはカスタム権限プロファイル名。 |
| `<tool>` | アプリ／MCPのツール名。`/` 等を含む場合はTOMLの引用符付きキーを使う。 |
| `<Event>` | フックイベント名。イベント一覧は後述。 |
| `[]` | 配列の1要素を示す。例: `remote_sandbox_config[]`。 |
| `table` | TOMLのテーブル。親テーブルだけでは通常効果がなく、下位キーを設定する。 |
| 「完全許可リスト」 | 記載された `true` の項目だけを許可し、省略または `false` は拒否する方式。将来追加される項目も自動的に拒否される。 |
| 「設定例」 | 各セルは `requirements.toml` に記述するTOML断片。`<id>`、`<name>`、`<tool>`、`<plugin>`、`<server>`、モデルID、ドメイン、URL、パスは組織の実値へ置き換える。複数行は `<br>` で区切って表示する。 |

## 基本・承認・検索・更新・保存先

| 設定キー | 型・許可値 | 設定例（TOML） | 制御の性質 | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- | --- |
| `allow_appshots` | `boolean` | `allow_appshots = false` | 正確値強制 | Appshotsの利用可否を固定する。`false` で管理対象ユーザーのAppshotsを無効化する。 | 省略は許可ではなく「未制約」。画面・アプリ文脈を組織ポリシー上扱えない場合は `false`。 |
| `allow_login_shell` | `boolean` | `allow_login_shell = false` | 正確値強制 | シェル系ツールがログインシェルを起動できるかを固定する。ログインシェルはプロファイルや起動スクリプトを読み込む可能性がある。 | 通常は `false` を推奨。ユーザーのシェル初期化ファイルから資格情報・追加コマンドが持ち込まれる面を減らす。 |
| `allow_managed_hooks_only` | `boolean` | `allow_managed_hooks_only = true` | 正確値強制 | `true` のとき、ユーザー、プロジェクト、セッション、プラグイン由来のフックを無視し、管理者管理フックだけを許可する。 | フックを利用する会社環境では `true` が安全。管理フックを動かすには `[features].hooks = true` と `[hooks]` も必要。 |
| `allow_remote_control` | `boolean` | `allow_remote_control = false` | 正確値強制 | 端末のデバイス・リモートコントロール機能を許可または禁止する。`false` で無効化する。 | リモート操作を導入しない組織は `false`。SSHリモート接続を無効化する設定ではない。 |
| `allowed_approval_policies` | `array<string>`: `untrusted`, `on-request`, `never`, `granular` | `allowed_approval_policies = ["on-request"]` | 許可リスト | ユーザーが選択できる承認ポリシーを限定する。許可外の指定は互換値へフォールバックし、ユーザーに通知される。 | `never` を許可すると承認プロンプトが出ない。特にフルアクセスとの組合せは避ける。一般的な会社端末は `on-request` のみ、または `untrusted` と `on-request`。 |
| `allowed_approvals_reviewers` | `array<string>`: `user`, `auto_review` | `allowed_approvals_reviewers = ["user"]` | 許可リスト | 承認要求を人が確認するか、自動レビュー用エージェントに確認させるかを限定する。 | `["auto_review"]` は自動レビューを必須化。追加モデル呼出しが発生する。レビュー処理・解析失敗は閉じた側に失敗し、対象アクションは実行されない。 |
| `allowed_permission_profiles` | `table<boolean>` | `[allowed_permission_profiles]`<br>`":read-only" = true`<br>`":workspace" = true`<br>`":danger-full-access" = false` | 完全許可リスト | 選択可能な組込み／カスタム権限プロファイルの全一覧を定義する。 | テーブルを置いた時点で、省略・`false` のプロファイルは将来追加分を含め拒否。Codex 0.138.0以上が必要。 |
| `allowed_permission_profiles.<name>` | `boolean` | `[allowed_permission_profiles]`<br>`":workspace" = true` | 完全許可リストの要素 | 指定プロファイルを許可 (`true`) または禁止 (`false`) する。例: `":workspace" = true`。 | 組込み `:danger-full-access` は通常省略または `false`。上位要件層の `false` は下位層の許可を無効化できる。 |
| `allowed_sandbox_modes` | `array<string>`: `read-only`, `workspace-write`, `danger-full-access` | `allowed_sandbox_modes = ["read-only", "workspace-write"]` | 許可リスト（旧方式） | 旧 `sandbox_mode` 方式でユーザーが選べるサンドボックスモードを限定する。 | 新規は権限プロファイルを優先。混在バージョンの暫定互換以外では長期利用しない。`danger-full-access` は通常除外。 |
| `allowed_web_search_modes` | `array<string>`: `disabled`, `cached`, `indexed`, `live` | `allowed_web_search_modes = ["cached"]` | 許可リスト | CodexのWeb検索モードを限定する。`disabled` は常に暗黙許可され、空配列は実質的にWeb検索を無効化する。 | 機密コード環境では `cached` のみ、または空配列を検討。検索結果はモードにかかわらず信頼済み入力として扱わない。 |
| `check_for_update_on_startup` | `boolean` | `check_for_update_on_startup = true` | 正確値強制 | 起動時にCodex更新確認を行うか固定する。 | クライアント自身で更新するなら `true`。MDM等で中央更新する場合のみ、更新SLAを整備した上で `false`。 |
| `computer_use` | `table` | `[computer_use]`<br>`allow_locked_computer_use = false` | 構造 | Computer Useに関する管理要件の親テーブル。 | 単独では通常効果なし。下位キーおよび `[features].computer_use` と役割が異なる。 |
| `computer_use.allow_locked_computer_use` | `boolean` | `[computer_use]`<br>`allow_locked_computer_use = false` | 正確値強制 | 管理対象macOS端末がロックされた後もComputer Useを継続できるかを固定する。 | 通常は `false`。このキーはComputer Useを有効化せず、ロック後利用だけを制限する。 |
| `default_permissions` | `string`（許可済みプロファイル名） | `default_permissions = ":workspace"` | 管理既定値／選択 | Codexが標準で適用する権限プロファイルを指定する。組込みまたは `[permissions.<name>]` で定義した名前を使う。 | `allowed_permission_profiles` で許可されている必要がある。予測可能性のため明示する。省略時に `:workspace` となるのは `:workspace` と `:read-only` の両方を明示許可した場合だけ。 |
| `enforce_residency` | `string`; 現在は `us` | `enforce_residency = "us"` | 正確値強制 | Codexサービス通信に対応データレジデンシーを要求する。 | 公開リファレンスで確認できる値は現在 `us` のみ。その他地域は **不明**。組織契約・対象通信範囲も別途確認する。 |
| `feedback` | `table` | `[feedback]`<br>`enabled = false` | 構造 | フィードバック送信に関する管理設定の親テーブル。 | 下位の `enabled` を設定する。 |
| `feedback.enabled` | `boolean` | `[feedback]`<br>`enabled = false` | 正確値強制 | Codexクライアントからフィードバックを送信できるか固定する。 | ソースコードや会話が外部送信される運用を禁止する場合は `false`。社内サポート導線を別途用意する。 |
| `guardian_policy_config` | `string`（Markdown、複数行可） | `guardian_policy_config = "資格情報の読取りと外部送信を禁止する。"` | 正確値強制 | 自動レビューの組織固有ポリシー指示を定義する。ローカル `[auto_review].policy` より優先される。 | 空文字は無視される。秘密情報を書かず、許可宛先、持出し、資格情報探索、破壊操作などを明確化する。 |
| `log_dir` | `string`（パス） | `log_dir = "/var/log/codex"` | 正確値強制 | ローカルログの保存先を固定する。 | `log_dir` の明示設定は平文TUIログ `codex-tui.log` も有効化するため、アクセス権、暗号化、保持期間、収集範囲を設計する。 |
| `model_catalog_json` | `string`（パス） | `model_catalog_json = "/etc/codex/models.json"` | 正確値強制 | 起動時に使用するJSONモデルカタログのパスを固定する。 | 管理者配布・改ざん防止・更新整合性が必要。ファイル形式や利用可能モデルの詳細はモデルカタログ側仕様に従う。 |
| `models` | `table` | `[models.new_thread]`<br>`model = "<承認済みモデルID>"`<br>`model_reasoning_effort = "high"` | 構造 | 新規ローカルスレッドの管理既定値をまとめる親テーブル。 | 強制ではない。下位の明示選択で上書き可能。 |
| `models.new_thread` | `table` | `[models.new_thread]`<br>`model = "<承認済みモデルID>"`<br>`model_reasoning_effort = "high"` | 管理既定値 | 新規スレッド開始時に適用するモデル関連既定値をまとめる。 | セキュリティ強制には使わず、操作性・コスト・標準化目的で使う。 |
| `models.new_thread.model` | `string` | `[models.new_thread]`<br>`model = "<承認済みモデルID>"` | 管理既定値 | 新規スレッドの既定モデルを指定する。 | 明示的な `--model` またはモデル／推論努力の `--config` 指定が優先。利用可能モデル名は時点・契約で変わる。 |
| `models.new_thread.model_reasoning_effort` | `string` | `[models.new_thread]`<br>`model_reasoning_effort = "high"` | 管理既定値 | 新規スレッドの既定推論努力を指定する。 | 許可値はモデルに依存。明示的なモデルまたは推論努力指定があると、管理されたmodelとeffortの両方をスキップする。 |
| `models.new_thread.service_tier` | `string` | 不明（公式リファレンスに列挙値がないため、値の例示は省略） | 管理既定値 | 新規スレッドの既定サービス階層を指定する。 | モデル関連の上書きとは独立して、明示的なサービス階層指定が優先。許可値は時点・契約で変わるためここでは **不明**。 |
| `sqlite_home` | `string`（パス） | `sqlite_home = "/var/lib/codex"` | 正確値強制 | SQLiteベースのローカル実行状態を保存するディレクトリを固定する。 | 端末バックアップ、アクセス権、暗号化、保持・削除ポリシーの対象にする。共有ディレクトリは避ける。 |

## 主要な列挙値の意味

| 対象 | 値 | 初心者向けの意味 | 推奨・注意 |
| --- | --- | --- | --- |
| 承認ポリシー | `untrusted` | 既知の安全な読み取り操作だけを自動実行し、状態変更や外部実行経路になり得るコマンドでは承認を求める。 | 操作ごとの確認を多めにしたい場合。安全判定を過信せずサンドボックスと併用する。 |
| 承認ポリシー | `on-request` | サンドボックス内の操作は自動実行し、ワークスペース外書込み、ネットワーク等の境界を越えるときに承認を求める。 | 会社PCの一般的な初期値として扱いやすい。 |
| 承認ポリシー | `never` | 承認プロンプトを出さず、許可された境界内でベストエフォート実行する。 | 対話端末では通常許可しない。`danger-full-access` と組み合わせると特に危険。 |
| 承認ポリシー | `granular` | サンドボックス昇格、コマンドルール、MCP、権限要求、スキルスクリプト等の承認カテゴリを個別に扱うポリシー。 | `requirements.toml` の配列は「granularを選べるか」だけを制約する。各カテゴリの詳細値はユーザー側設定であり、要件側の公開スキーマにはない。 |
| 承認レビュー担当 | `user` | 対象承認を人間ユーザーに提示する。 | 人の判断を必須にしたい場合。承認疲れを避けるため権限境界とルールを狭く設計する。 |
| 承認レビュー担当 | `auto_review` | 承認対象だけを自動レビュー用エージェントに評価させる。 | 自動化に有効だが追加利用量が発生。組織固有ルールは `guardian_policy_config` で定義する。 |
| 旧サンドボックス | `read-only` | ローカルコマンドはファイルを読み取れるが、原則として変更できない。 | 調査・レビュー用途。承認ポリシーにより編集等の昇格要求が出る場合がある。 |
| 旧サンドボックス | `workspace-write` | アクティブなワークスペースと一部一時領域への書込みを許可する。 | 一般的なコーディング用途。`.git`、`.codex` 等の保護パスは読み取り専用。 |
| 旧サンドボックス | `danger-full-access` | ローカルサンドボックス制限を外す。 | 通常の会社PCでは許可しない。名称どおり高リスク。 |
| 組込み権限プロファイル | `:read-only` | ローカルコマンド実行を読み取り専用に保つ。 | コードレビュー、調査、初回導入の安全側。 |
| 組込み権限プロファイル | `:workspace` | ワークスペースルートとシステム一時ディレクトリ内の書込みを許可する。 | 通常の開発作業向け。必要に応じて `.env` 等を追加 `deny` する。 |
| 組込み権限プロファイル | `:danger-full-access` | ローカルサンドボックス制限を外す。 | 完全許可リストから省略または `false` にする。 |
| Web検索 | `disabled` | Web検索ツールを取り除く。 | 空の `allowed_web_search_modes = []` でも実質この状態だけが許可される。 |
| Web検索 | `cached` | OpenAI管理の検索インデックスから事前取得結果を返し、任意ページへの外部ライブアクセスを行わない。 | ライブWebのプロンプトインジェクション露出を減らすが、結果自体は非信頼として扱う。 |
| Web検索 | `indexed` | 検索インデックスによるゲートを通る場合だけ外部アクセスを許可する。 | `cached` より新鮮さを得やすいが外部アクセス面が増える。 |
| Web検索 | `live` | 最新ページをライブ取得する。 | 最も広いWeb露出。機密コードを扱う会社端末では原則禁止または限定グループのみ。 |

## アプリ／コネクタ

| 設定キー | 型・許可値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `apps` | `table` | `[apps."<id>"]`<br>`enabled = false` | アプリIDごとの管理要件をまとめる。アプリを無効化したり、個々のツール承認方式を固定できる。 | アプリ可用性全体は `[features].apps` でも制御する。ワークスペースのコネクタ権限、外部サービス側権限、ローカルランタイム権限は別レイヤー。 |
| `apps.<id>.enabled` | `boolean` | `[apps."<id>"]`<br>`enabled = false` | `false` で指定アプリを無効化する。複数要件ソースのどこかで無効化されると、制約側に保たれる。 | 許可するアプリIDを管理台帳と一致させる。省略は未制約。 |
| `apps.<id>.tools.<tool>.approval_mode` | `auto \| prompt \| writes \| approve` | `[apps."<id>".tools."<tool>"]`<br>`approval_mode = "prompt"` | 指定アプリの1ツールについて承認方式を固定する。 | `prompt` が最も保守的、`approve` が最も自動的。`auto` と `writes` の具体的なツール分類基準は公開 `requirements.toml` リファレンスでは **不明**。副作用ツールは実機試験する。 |

## アプリ／MCPツールの `approval_mode`

| 値 | 意味 | 公開情報の精度 |
| --- | --- | --- |
| `auto` | Codexの標準自動判定に従う。 | 読み取り・書込み・危険度をどのメタデータで判定するかの完全な仕様は公開リファレンスでは **不明**。 |
| `prompt` | ツール実行を承認対象として扱う最も保守的なモード。 | 実際の表示・自動レビュー経路は承認ポリシーとレビュアー設定にも依存する。 |
| `writes` | 書込み／副作用を伴うと判定されたツールを承認対象にする。 | ツール側メタデータの品質に依存し得る。具体的分類基準は公開リファレンスでは **不明**。 |
| `approve` | そのツールを承認済みとして扱い、承認要求を減らす。 | 信頼済み・読み取り専用と検証できるツール以外には使わない。 |

## 実験的ネットワーク要件

| 設定キー | 型・許可値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `experimental_network` | `table` | `[experimental_network]`<br>`enabled = true`<br>`managed_allowed_domains_only = true` | 管理者がサンドボックス化されたローカルコマンド通信のネットワーク制約を定義する親テーブル。 | 実験的。Windows対応は限定的。Web検索、Apps、MCP、ブラウザー、Computer Use、Codex cloudの通信を一括制御する設定ではない。 |
| `experimental_network.enabled` | `boolean` | `[experimental_network]`<br>`enabled = true` | 管理ネットワーク要件を有効化する。 | `true` でも、アクティブなサンドボックスがコマンド通信を禁止している場合は通信を付与しない。 |
| `experimental_network.allowed_domains` | `array<string>` | `[experimental_network]`<br>`allowed_domains = ["api.example.com", "*.example.com"]` | 旧リスト形式の管理許可ドメインを指定する。 | `experimental_network.domains` と併用しない。可能ならdenyも明示できるmap形式を優先。 |
| `experimental_network.denied_domains` | `array<string>` | `[experimental_network]`<br>`denied_domains = ["tracking.example.com"]` | 旧リスト形式の管理拒否ドメインを指定する。 | `experimental_network.domains` と併用しない。 |
| `experimental_network.domains` | `map<string, allow \| deny>` | `[experimental_network.domains]`<br>`"api.example.com" = "allow"`<br>`"tracking.example.com" = "deny"` | ドメインパターンごとに許可／拒否を設定する。完全ホスト、`*.example.com`（サブドメインのみ）、`**.example.com`（頂点＋サブドメイン）、許可用の全体 `*` を扱う。競合時はdenyが優先。 | グローバル `* = "allow"` は広範な外向き通信を開く。`allowed_domains` / `denied_domains` と混ぜない。 |
| `experimental_network.managed_allowed_domains_only` | `boolean` | `[experimental_network]`<br>`managed_allowed_domains_only = true` | `true` のとき管理者許可ルールだけを有効にし、ユーザー追加の許可リストを無視する。 | 管理許可ルールを同時に定義する。許可ルールなしで `true` にすると、ユーザー許可も残らない。 |
| `experimental_network.allow_local_binding` | `boolean` | `[experimental_network]`<br>`allow_local_binding = false` | ローカル／プライベートネットワークへの広いアクセスを許可する。`false` のままでも、正確なローカルIPリテラルや `localhost` を個別許可できる。 | DNSリバインディング・社内サービス到達面が増えるため通常は `false`。 |
| `experimental_network.allow_upstream_proxy` | `boolean` | `[experimental_network]`<br>`allow_upstream_proxy = false` | 環境の上流HTTP(S)/ALL_PROXY等を経由することを許可する。 | 会社プロキシが必須なら有効化を検討。ユーザー環境変数による想定外プロキシ経由を許す可能性を試験する。 |
| `experimental_network.http_port` | `integer` | `[experimental_network]`<br>`http_port = 3128` | サンドボックスネットワーク用のループバックHTTPリスナーポートを指定する。 | ポート競合、EDR、ローカルファイアウォールを確認。非ループバック公開には使わない。 |
| `experimental_network.socks_port` | `integer` | `[experimental_network]`<br>`socks_port = 8081` | サンドボックスネットワーク用のループバックSOCKS5リスナーポートを指定する。 | ポート競合と、SOCKS経由通信の監視・制限を確認。 |
| `experimental_network.unix_sockets` | `map<string, allow \| deny>` | `[experimental_network.unix_sockets]`<br>`"/var/run/docker.sock" = "deny"` | Unixソケットパスごとの管理許可／拒否を設定する。 | Dockerソケット等はホスト制御に直結する高権限口になり得る。必要最小限の正確なパスだけ許可。 |
| `experimental_network.dangerously_allow_all_unix_sockets` | `boolean` | `[experimental_network]`<br>`dangerously_allow_all_unix_sockets = false` | Unixソケットの許可リスト制約を外し、任意ソケット宛先を許可する。 | 通常は `false`。名前どおり広いローカル脱出経路になり得る。 |
| `experimental_network.dangerously_allow_non_loopback_proxy` | `boolean` | `[experimental_network]`<br>`dangerously_allow_non_loopback_proxy = false` | ネットワークプロキシのリスナーを非ループバックアドレスにバインドできるようにする。 | 端末外からリスナーへ到達可能になる恐れがある。通常は `false`。 |

## 機能フラグ `[features]`

| 設定キー | 型 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 | 公開上の位置付け |
| --- | --- | --- | --- | --- | --- |
| `features` | `table` | `[features]`<br>`apps = false` | 機能フラグの親テーブル。管理対象ユーザーに認識済み機能を有効／無効のまま固定する。 | 省略した機能は未制約。機能フラグはクライアントやバージョンにより認識状況が異なる。 | 明示 |
| `features.<name>` | `boolean` | `[features]`<br>`shell_tool = true` | 公開されたランタイム機能またはアプリ専用機能をピン留めする汎用形。 | 認識されない名前の挙動を期待しない。組織配布前に対象バージョンで確認。 | 明示 |
| `features.apps` | `boolean` | `[features]`<br>`apps = false` | Apps／コネクタ統合全体を有効／無効化する。 | 外部データ・副作用を使わない環境は `false`。個別アプリ制約は `[apps]` とワークスペース側設定も必要。 | 明示 |
| `features.browser_use` | `boolean` | `[features]`<br>`browser_use = false` | `false` でブラウザー内Computer UseとBrowser Agentの可用性を無効化する。 | ブラウザー操作を導入しない会社端末は `false`。 | 明示・アプリ専用 |
| `features.browser_use_external` | `boolean` | `[features]`<br>`browser_use_external = false` | `false` で外部ブラウザーを使うBrowser Useを無効化する。 | 外部ブラウザーの既存セッションやデータへの接触を避ける場合は `false`。 | 明示・アプリ専用 |
| `features.browser_use_full_cdp_access` | `boolean` | `[features]`<br>`browser_use_full_cdp_access = false` | `false` でローカルランタイムの完全Chrome DevTools ProtocolアクセスとBrowser Developer modeを無効化し、デスクトップアプリからの有効化も防ぐ。 | CDPはブラウザー全体へ広い制御を与え得るため、通常は `false`。 | 明示・アプリ専用 |
| `features.computer_use` | `boolean` | `[features]`<br>`computer_use = false` | `false` でComputer Use、Record & Replay、および関連インストール／有効化フローを無効化する。 | 画面操作が不要なら `false`。`computer_use.allow_locked_computer_use` だけでは機能全体を止めない。 | 明示・アプリ専用 |
| `features.fast_mode` | `boolean` | `[features]`<br>`fast_mode = false` | Fastモード／サービス階層選択機能を有効／無効化する。 | 主に性能・利用量・コスト統制。モデル可用性と組織の利用枠に合わせる。 | 明示・canonical |
| `features.guardian_approval` | `boolean` | `[features]`<br>`guardian_approval = true` | Guardian承認機能の可用性を固定する。 | これは自動レビューの具体ポリシーではない。レビュアーは `allowed_approvals_reviewers`、組織指示は `guardian_policy_config`。 | 明示・アプリ専用 |
| `features.in_app_browser` | `boolean` | `[features]`<br>`in_app_browser = false` | `false` で組込みブラウザーペインを無効化する。 | ブラウザー面を許可しない端末は `false`。Web検索とは別機能。 | 明示・アプリ専用 |
| `features.in_app_updates` | `boolean` | `[features]`<br>`in_app_updates = true` | `false` でChatGPTデスクトップアプリ自身のアプリ内更新を無効化する。 | 中央配布を行わずに `false` にするとパッチ遅延を招く。外部パッケージ配布には影響しない。 | 明示・アプリ専用 |
| `features.memories` | `boolean` | `[features]`<br>`memories = false` | 会話からのMemories生成・利用機能の可用性を固定する。 | 長期保持や外部文脈の社内ルールに合わない場合は `false`。 | 明示・canonical |
| `features.multi_agent` | `boolean` | `[features]`<br>`multi_agent = false` | サブエージェント協調ツールを有効／無効化する。 | 並列ツール活動、利用量、監査対象が増える。初期導入では `false` から評価してもよい。 | 明示・canonical |
| `features.plugin_sharing` | `boolean` | `[features]`<br>`plugin_sharing = false` | `false` でローカル作成プラグインのワークスペース共有を無効化する。 | クラウド管理 `requirements.toml` 専用。ローカルプラグインの社内配布を認めない場合は `false`。 | 明示・クラウド専用 |
| `features.plugins` | `boolean` | `[features]`<br>`plugins = false` | サポート対象ローカルクライアントのプラグイン機能全体を固定する。 | 不要なら `false`。APIキーでCodexへサインインする場合にも適用される。 | 明示・アプリ専用 |
| `features.remote_plugin` | `boolean` | `[features]`<br>`remote_plugin = false` | リモートプラグインカタログの可用性を固定する。 | 会社承認済みローカル配布だけに絞る場合は `false`。 | 明示・canonical |
| `features.workspace_dependencies` | `boolean` | `[features]`<br>`workspace_dependencies = false` | バンドルされたワークスペース依存関係ランタイムの可用性を固定する。 | 公開リファレンスは利用者影響の詳細を展開していないため、具体的な対象依存関係は **不明**。試験環境で確認。 | 明示・アプリ専用 |
| `features.enable_request_compression` | `boolean` | `[features]`<br>`enable_request_compression = true` | 対応時にストリーミング要求本文をzstd圧縮する。 | ネットワークプロキシ／監視製品との互換性を試験。セキュリティ境界そのものではない。 | canonical汎用規則 |
| `features.goals` | `boolean` | `[features]`<br>`goals = false` | 永続化されたGoalsと自動継続を有効／無効化する。 | 長時間・自動継続作業の実行範囲と監査方針に合わせる。 | canonical汎用規則 |
| `features.hooks` | `boolean` | `[features]`<br>`hooks = true` | ライフサイクルフックのロード／実行を有効／無効化する。 | 管理フックを強制するなら `true` と `[hooks]`、非管理フックを排除するなら `allow_managed_hooks_only = true`。フック不要なら `false`。 | canonical汎用規則 |
| `features.network_proxy` | `boolean` のピン留め | `[features]`<br>`network_proxy = true` | サンドボックスネットワーク機能フラグを有効／無効化する。 | `config.toml` ではtable形式もあるが、公開 `requirements.toml` の `[features]` はboolean pinとして説明される。下位tableを要件に書けるかは **不明**。管理制約は `[experimental_network]` を使う。 | canonical汎用規則・実験的 |
| `features.personality` | `boolean` | `[features]`<br>`personality = false` | コミュニケーションスタイル選択コントロールを有効／無効化する。 | 通常はセキュリティ境界ではない。標準UI統制が必要な場合のみ固定。 | canonical汎用規則 |
| `features.prevent_idle_sleep` | `boolean` | `[features]`<br>`prevent_idle_sleep = false` | ターン実行中に端末のスリープを防止する。 | 端末ロック・省電力・物理セキュリティポリシーと競合し得るため、会社PCでは慎重に。 | canonical汎用規則・実験的 |
| `features.shell_snapshot` | `boolean` | `[features]`<br>`shell_snapshot = false` | 繰り返しコマンド高速化のためシェル環境スナップショットを有効／無効化する。 | 環境変数・起動設定の取扱いをシェル環境ポリシーと合わせる。保存内容の完全な詳細はこの要件リファレンスでは **不明**。 | canonical汎用規則 |
| `features.shell_tool` | `boolean` | `[features]`<br>`shell_tool = true` | 標準 `shell` ツールを有効／無効化する。 | `false` は攻撃面を減らすが、Codexの一般的な開発作業能力を大きく制限する。他の実行ツールが残る可能性にも注意。 | canonical汎用規則 |
| `features.skill_mcp_dependency_install` | `boolean` | `[features]`<br>`skill_mcp_dependency_install = false` | Skillsに不足するMCP依存関係のプロンプト／インストールを許可する。 | サプライチェーン面が増える。中央管理した依存関係だけを使うなら `false`。 | canonical汎用規則 |
| `features.unified_exec` | `boolean` | `[features]`<br>`unified_exec = true` | PTYベースの統合実行ツールを利用する。 | Windowsでは既定が異なる。EDR、シェル、フック、入出力ログとの互換性を試験。 | canonical汎用規則 |
| `features.web_search` | `boolean` | `[features]`<br>`web_search = false` | 旧Web検索トグル。 | 非推奨。トップレベル `allowed_web_search_modes` と `web_search` のモード制約を使う。 | canonical・非推奨 |
| `features.web_search_cached` | `boolean` | `[features]`<br>`web_search_cached = false` | 旧トグル。トップレベル `web_search` 未設定時にcachedへ対応付ける。 | 非推奨。新規ポリシーでは使わない。 | canonical・非推奨 |
| `features.web_search_request` | `boolean` | `[features]`<br>`web_search_request = false` | 旧トグル。トップレベル `web_search` 未設定時にliveへ対応付ける。 | 非推奨。意図せずlive検索を許さないよう新規ポリシーでは使わない。 | canonical・非推奨 |

### `[features]` の下位テーブルに関する不明点

`config.toml` の公開リファレンスには `features.code_mode.*`、`features.network_proxy.*`、`features.rollout_budget.*` のような下位テーブル設定もある。一方、公開 `requirements.toml` リファレンスは `[features]` を **booleanのピン留め** として定義し、これらの下位テーブルを要件として使えるとは明記していない。したがって、上表に個別掲載した単純booleanキー以外の下位テーブルをクラウドポリシーに書けるかは **不明**。ネットワーク制約は `[experimental_network]` または権限プロファイルのnetwork設定を使用する。

## 権限プロファイルとファイルシステム制約

| 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `permissions` | `table` | `[permissions.corp_workspace]`<br>`description = "社内開発用"`<br>`extends = ":workspace"` | 管理者定義の権限プロファイル、および全プロファイルへ追加される読取拒否要件の親テーブル。 | カスタムプロファイル名は `:` で始められず、予約名 `filesystem` も使えない。ロード済み設定の同名プロファイルとの衝突にも注意。 |
| `permissions.<name>` | `table` | `[permissions.corp_workspace]`<br>`description = "社内開発用"`<br>`extends = ":workspace"` | 管理者定義の1つの権限プロファイル。ファイルシステムとネットワークの最小権限を一体で定義する。 | 0.138.0以降を前提に、`allowed_permission_profiles.<name> = true` と `default_permissions` を整合させる。 |
| `permissions.<name>.description` | `string` | `[permissions.corp_workspace]`<br>`description = "社内開発用"` | プロファイルの人間向け説明。 | `extends` で親のdescriptionは継承されない。用途・所有者・例外条件を明記する。 |
| `permissions.<name>.extends` | `string`: `:read-only`, `:workspace`, または他のカスタム名 | `[permissions.corp_workspace]`<br>`extends = ":workspace"` | 親プロファイルを基礎にして差分だけを追加する。 | 組込みの基礎防御を継承するため `:read-only` / `:workspace` から始める。`:danger-full-access`、未知の親、循環継承は拒否。 |
| `permissions.<name>.workspace_roots` | `table` | `[permissions.corp_workspace.workspace_roots]`<br>`"/srv/repos/product-a" = true` | プロファイル固有の追加ワークスペースルートを定義する。実行時ワークスペースルートと併せて `:workspace_roots` ルールの対象になる。 | 必要なリポジトリだけ追加。ホーム全体や共有ドライブ全体をルート化しない。 |
| `permissions.<name>.workspace_roots."<path>"` | `boolean` | `[permissions.corp_workspace.workspace_roots]`<br>`"/srv/repos/product-a" = true` | `true` のパスを追加ワークスペースルートとして有効化する。`false` は非アクティブ。 | 絶対パスまたはホーム相対を明確にし、端末間差異を検証。Windowsはドライブパス・UNCも対応。 |
| `permissions.<name>.filesystem` | `table` | `[permissions.corp_workspace.filesystem.":workspace_roots"]`<br>`"." = "write"`<br>`"**/*.env" = "deny"` | ファイル／ディレクトリパスを `read`, `write`, `deny` または下位サブパスマップへ対応付ける。 | 空または欠落ではアクセスを制限し起動警告。広い許可の後に機密サブパスを `deny` する。 |
| `permissions.<name>.filesystem.glob_scan_max_depth` | `number`（1以上） | `[permissions.corp_workspace.filesystem]`<br>`glob_scan_max_depth = 8` | Linux、WSL、native Windowsで無制限 `**` denyグロブを事前展開するときの最大深さを制限する。 | 大きい値は起動時走査コストを増やす。`**/*.env` 等を使う場合だけ必要深さを設定。 |
| `permissions.<name>.filesystem."<path>"` | `read \| write \| deny` またはtable | `[permissions.corp_workspace.filesystem]`<br>`"~/.ssh" = "deny"` | 正確なパス／特殊パスに直接アクセス権を与える。 | 同じ具体度では `deny > write > read`。より具体的なルールが広いルールを上書きする。ランタイムで強制不能な直接writeは拒否。 |
| `permissions.<name>.filesystem."<path>"."<subpath>"` | `read \| write \| deny` | `[permissions.corp_workspace.filesystem."/srv/repos"]`<br>`"product-a" = "write"` | 基準パス配下の相対サブパスごとに権限を分ける。`.` は基準パス自身。 | サブパスに `.` / `..` 成分や親ディレクトリ移動は使えない。 |
| `permissions.<name>.filesystem.":workspace_roots"."<subpath-or-glob>"` | `read \| write \| deny` | `[permissions.corp_workspace.filesystem.":workspace_roots"]`<br>`"." = "write"`<br>`"**/*.env" = "deny"` | 各実効ワークスペースルートに同じ相対ルールを適用する。例: `"." = "write"`, `"**/*.env" = "deny"`。 | 資格情報ファイルをdenyで切り抜く主要パターン。read/writeグロブはLinux/WSL/Windowsで可搬性が低いため、可能なら正確なパス／サブツリーを使う。 |
| `permissions.<name>.network` | `table` | `[permissions.corp_workspace.network]`<br>`enabled = true` | プロファイルのサンドボックスネットワークプロキシと宛先ポリシーを定義する。 | 権限プロファイルはローカルのサンドボックス化コマンド通信を制御し、Apps/MCP/ブラウザー/Computer Use/Cloudは別制御。 |
| `permissions.<name>.network.enabled` | `boolean`; 既定 `false` | `[permissions.corp_workspace.network]`<br>`enabled = true` | プロファイル内のサンドボックス化コマンドにネットワークアクセスを許可する。 | 有効化時はドメイン許可を併記する。これだけではプロキシを自動起動するという意味ではない。 |
| `permissions.<name>.network.domains` | `table` | `[permissions.corp_workspace.network.domains]`<br>`"api.example.com" = "allow"`<br>`"tracking.example.com" = "deny"` | ホストパターンを `allow` / `deny` に対応付ける。allowが1件もなければドメイン要求はブロックされる。 | denyがallowより優先。広いワイルドカードを避ける。 |
| `permissions.<name>.network.domains."<pattern>"` | `allow \| deny` | `[permissions.corp_workspace.network.domains]`<br>`"api.example.com" = "allow"` | 完全ホスト、`*.example.com`、`**.example.com`、許可用 `*` を設定する。 | 末尾ドット、単純ポート、括弧などは正規化される。`* = "allow"` は公開ネットワーク全体を開く。 |
| `permissions.<name>.network.unix_sockets` | `table` | `[permissions.corp_workspace.network.unix_sockets]`<br>`"/var/run/docker.sock" = "deny"` | Unixソケットの許可／拒否マップ。 | Dockerなどローカル統合用。ホスト制御面に直結する可能性があるため最小限。 |
| `permissions.<name>.network.unix_sockets."<path>"` | `allow \| deny` | `[permissions.corp_workspace.network.unix_sockets]`<br>`"/var/run/docker.sock" = "deny"` | 絶対Unixソケットパスを許可または拒否する。 | 継承したallowもdenyで除外可能。リスナーはループバックに保つ。 |
| `permissions.<name>.network.proxy_url` | `URL string`; 既定 `http://127.0.0.1:3128` | `[permissions.corp_workspace.network]`<br>`proxy_url = "http://127.0.0.1:3128"` | HTTP/HTTPS/WebSocket等のプロキシ環境変数に使うHTTPリスナーURL。 | 通常は既定値のまま。非ループバックへ向けない。 |
| `permissions.<name>.network.enable_socks5` | `boolean`; 既定 `true` | `[permissions.corp_workspace.network]`<br>`enable_socks5 = false` | ALL_PROXYやFTPプロキシ変数向けSOCKS5リスナーを有効化する。 | 不要なプロトコルを減らす場合は `false` を試験。 |
| `permissions.<name>.network.socks_url` | `URL string`; 既定 `http://127.0.0.1:8081` | `[permissions.corp_workspace.network]`<br>`socks_url = "http://127.0.0.1:8081"` | SOCKS5リスナーアドレス。 | 通常は既定値のまま。ポート競合と監視製品を確認。 |
| `permissions.<name>.network.enable_socks5_udp` | `boolean`; 既定 `true` | `[permissions.corp_workspace.network]`<br>`enable_socks5_udp = false` | SOCKS5有効時にUDPを許可する。 | UDPが不要な組織では `false` を検討し、名前解決・開発ツール影響を試験。 |
| `permissions.<name>.network.allow_upstream_proxy` | `boolean`; 既定 `true` | `[permissions.corp_workspace.network]`<br>`allow_upstream_proxy = true` | 環境の `HTTP(S)_PROXY` / `ALL_PROXY` 等の上流プロキシを尊重する。 | 会社プロキシ必須環境では必要になり得る。ユーザー設定の上流プロキシへ迂回しないか検証。 |
| `permissions.<name>.network.allow_local_binding` | `boolean`; 既定 `false` | `[permissions.corp_workspace.network]`<br>`allow_local_binding = false` | `true` でローカル／プライベートネットワークガードを外す。`false` では `localhost` やIPリテラルを明示allowする必要があり、プライベートIPへ解決するホスト名はブロックされる。 | DNSリバインディング・内部サービス接触面が増えるため通常 `false`。 |
| `permissions.<name>.network.dangerously_allow_non_loopback_proxy` | `boolean`; 既定 `false` | `[permissions.corp_workspace.network]`<br>`dangerously_allow_non_loopback_proxy = false` | プロキシリスナーの非ループバックバインドを許可する。 | 通常 `false`。端末外へプロキシを公開する恐れ。 |
| `permissions.<name>.network.dangerously_allow_all_unix_sockets` | `boolean`; 既定 `false` | `[permissions.corp_workspace.network]`<br>`dangerously_allow_all_unix_sockets = false` | Unixソケット許可リストを迂回する。 | 通常 `false`。広いローカル脱出経路。 |
| `permissions.filesystem.deny_read` | `array<string>`（絶対パス、`~`、glob） | `[permissions.filesystem]`<br>`deny_read = ["~/.ssh", "~/.aws"]` | すべてのローカル設定より強い管理者読取拒否を追加する。ユーザーは弱められない。 | `./` で始まる相対パスは不可。これがあるとフルアクセス権限は拒否される。native Windowsでは直接ファイルツールには効くが、シェル子プロセスの読取りにはこのルールが適用されない。 |

## 権限プロファイルで使える特殊パス

| パス | 意味 | 注意 |
| --- | --- | --- |
| `:root` | ファイルシステムのルート。 | 広いreadを意図する場合だけ。サブパスは `.` のみ。 |
| `:minimal` | 一般的な開発ツールの実行に必要な最小限のプラットフォーム／ランタイムパス。 | 具体的な展開内容はプラットフォーム・ランタイム依存。サブパスは `.` のみ。 |
| `:workspace_roots` | 現在の実行ワークスペースルート＋プロファイルで有効化した追加ルート。 | 相対サブパスルールを設定できる。 |
| `:tmpdir` | `$TMPDIR` の場所。 | 既定継承でwriteになり得るため、不要ならdenyを検討。サブパスは `.` のみ。 |
| `:slash_tmp` | 存在する場合の `/tmp`。 | 共有一時領域のリスクを評価。サブパスは `.` のみ。 |
| `/absolute/path` / `C:\path` | OSの絶対パス。 | native WindowsではドライブパスとUNCパスをサポート。 |
| `~/path` / `~\path` | 現在ユーザーのホーム配下。 | ユーザーごとに展開される。資格情報ディレクトリはdeny候補。 |

## 管理フック

| 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `hooks` | `table` | `[hooks]`<br>`managed_dir = "/enterprise/hooks"` | 管理者強制のライフサイクルフックを定義する。inline hooksと同じイベントスキーマを使う。 | スクリプト本体は配布されない。MDM/端末管理で別途配布し、絶対パスを使う。 |
| `hooks.managed_dir` | `string`（存在する絶対パス） | `[hooks]`<br>`managed_dir = "/enterprise/hooks"` | macOS/Linuxの管理フックスクリプトディレクトリ。 | 絶対パスかつ存在確認される。一般ユーザーが書き換えられない所有権・ACLにする。 |
| `hooks.windows_managed_dir` | `string`（存在する絶対パス） | `[hooks]`<br>`windows_managed_dir = "C:\\enterprise\\hooks"` | Windowsの管理フックスクリプトディレクトリ。 | 一般ユーザーが書き換えられないACLにする。 |
| `hooks.<Event>` | `array<table>` | `[[hooks.PreToolUse]]`<br>`matcher = "^Bash$"` | 指定イベントで評価するmatcherグループの配列。 | 同じイベントで一致した複数のcommandフックは並行して起動される。1つのフックが、別の一致フックの起動を先回りして止めることはできないため、実行順序や前段フックの副作用に依存させない。 |
| `hooks.<Event>[].matcher` | `string`（正規表現） | `[[hooks.PreToolUse]]`<br>`matcher = "^Bash$"` | イベント発火対象を絞る。`*`、空文字、または省略で全一致。イベントによりツール名、開始理由、圧縮理由等へ適用される。 | `UserPromptSubmit` と `Stop` は現在matcherをサポートせず、指定しても無視される。正規表現をアンカーして意図しない一致を避ける。 |
| `hooks.<Event>[].hooks` | `array<table>` | `[[hooks.PreToolUse]]`<br>`matcher = "^Bash$"`<br><br>`[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"` | matcherグループ内で実行するハンドラー配列。 | 現在実行されるのはcommandハンドラー。 |
| `hooks.<Event>[].hooks[].type` | `command`; `prompt`/`agent` は解析されるが現在スキップ | `[[hooks.PreToolUse]]`<br><br>`[[hooks.PreToolUse.hooks]]`<br>`type = "command"` | ハンドラー種別。 | 本番は `command` のみを使用。解析できることと実行サポートは別。 |
| `hooks.<Event>[].hooks[].command` | `string` | `[[hooks.PreToolUse]]`<br><br>`[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"` | macOS/Linux等で実行するコマンド。セッションの `cwd` で起動する。 | 管理ディレクトリ配下の絶対スクリプトパスを参照し、引数インジェクションを避ける。 |
| `hooks.<Event>[].hooks[].command_windows` | `string` | `[[hooks.PreToolUse]]`<br><br>`[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command_windows = "C:\\enterprise\\hooks\\check.cmd"` | Windows専用コマンド上書き。 | `commandWindows` という別名も受理される。パス引用符とPowerShell/cmdの差を試験。 |
| `hooks.<Event>[].hooks[].commandWindows` | `string` | `[[hooks.PreToolUse]]`<br><br>`[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`commandWindows = "C:\\enterprise\\hooks\\check.cmd"` | `command_windows` のTOML別名。 | 組織内で表記を統一する。公式管理例は `command_windows`。 |
| `hooks.<Event>[].hooks[].timeout` | `number`（秒） | `[[hooks.PreToolUse]]`<br><br>`[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"`<br>`timeout = 30` | フックのタイムアウト。省略時は多くのフックで600秒。`SessionEnd` は既定1秒、最大3秒。 | 長すぎる値はユーザー操作を停止させる。セキュリティ検査は短時間・フェイルクローズ方針を明確化。 |
| `hooks.<Event>[].hooks[].statusMessage` | `string` | `[[hooks.PreToolUse]]`<br><br>`[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"`<br>`statusMessage = "管理ポリシーを確認中"` | フック実行中に表示する任意の状態メッセージ。 | 機密情報、内部パス、検知ロジックの詳細を表示しない。 |
| `hooks.<Event>[].hooks[].additionalContextLimit` | `integer`; 既定2500、`0` は全量 | `[[hooks.PreToolUse]]`<br><br>`[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"`<br>`additionalContextLimit = 2000` | フックが返す `additionalContext` の概算トークン閾値。超過時は全文をディスクへ保存し、モデルへ短いプレビューを渡す。 | `0` はコンテキスト枯渇や機密情報の大量投入を招き得る。出力上限を厳密に保証できる場合以外は避ける。 |
| `hooks.<Event>[].hooks[].async` | `boolean`; 既定 `false` | `[[hooks.PreToolUse]]`<br><br>`[[hooks.PreToolUse.hooks]]`<br>`type = "command"`<br>`command = "/enterprise/hooks/check.sh"`<br>`async = false` | 非同期フック指定として解析される。 | 公式Hooks資料では非同期commandフックは現在未サポート。設定しても期待どおり動くとは限らないため **使用非推奨**。`SessionEnd` は常に同期。 |

## フックイベント

| イベント | 発火タイミング／matcher対象 | 主な用途と注意 |
| --- | --- | --- |
| `PreToolUse` | ツール使用前。matcherはツール名。 | ツール呼出しのブロック／書換え、DLP検査。`Bash`, `apply_patch`, MCPツール名等を対象にできる。 |
| `PermissionRequest` | 承認要求時。matcherはツール名。 | 承認要求の追加検査。承認ポリシーそのものの代替ではない。 |
| `PostToolUse` | ツール使用後。matcherはツール名。 | 出力監査、検証、記録。ツール出力は非信頼として扱う。 |
| `PreCompact` | コンテキスト圧縮前。matcherは `manual` / `auto`。 | 圧縮前の記録・検査。 |
| `PostCompact` | コンテキスト圧縮後。matcherは `manual` / `auto`。 | 圧縮結果後処理。 |
| `SessionStart` | セッション開始。matcherは `startup`, `resume`, `clear`, `compact`。 | 管理コンテキストの読込み。起動遅延を短く保つ。 |
| `SessionEnd` | メインスレッド終了。matcherは現在 `other`。サブエージェントでは実行されない。 | 監査・終了処理。既定1秒、最大3秒。 |
| `SubagentStart` | サブエージェント開始。matcherはagent type。 | サブエージェント監査。タイプ値は起動するサブエージェント依存。 |
| `SubagentStop` | サブエージェント停止。matcherはagent type。 | 結果検査・監査。 |
| `UserPromptSubmit` | ユーザープロンプト送信時。matcherは現在未サポート。 | 秘密情報・APIキー等の検査。誤検知時のユーザー導線を用意。 |
| `Stop` | ターン停止時。matcherは現在未サポート。 | 完了条件検査、継続要求。無限継続を防ぐ。 |

## プラグインマーケットプレイス

| 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `marketplaces` | `table` | `[marketplaces]`<br>`restrict_to_allowed_sources = true` | プラグインマーケットプレイスの管理要件。 | `restrict_to_allowed_sources = true` の場合に許可ソース規則が実効化する。 |
| `marketplaces.restrict_to_allowed_sources` | `boolean` | `[marketplaces]`<br>`restrict_to_allowed_sources = true` | `true` でユーザー設定マーケットプレイスの追加、プラグインインストール、設定済みGitマーケットプレイス更新を許可ソースへ限定する。 | 既に設定済みのユーザーマーケットプレイスやプラグインを実行時に自動除外するものではない。既存棚卸しが別途必要。 |
| `marketplaces.allowed_sources` | `table` | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"` | 管理者が付けた規則名ごとの許可ソース一覧。 | 異なる規則名は要件層間で蓄積。同名配下は通常の優先順位で解決。 |
| `marketplaces.allowed_sources.<name>` | `table` | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"` | 1つの許可ソース規則。最終的な `source` 値で解釈する兄弟フィールドが決まる。 | 規則名は用途と所有者が分かる名前にする。 |
| `marketplaces.allowed_sources.<name>.source` | `git \| host_pattern \| local` | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"` | Gitリポジトリ完全一致、Gitホスト正規表現、ローカルディレクトリのどれで照合するかを指定する。 | 最も具体的な `git` または `local` を優先し、host全体許可は慎重に。 |
| `marketplaces.allowed_sources.<name>.url` | `string` | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"` | `source = "git"` の必須GitリポジトリURL。正規化後にリポジトリ完全一致を要求する。 | 組織管理リポジトリだけを指定。似た名前の別リポジトリを許可しない。 |
| `marketplaces.allowed_sources.<name>.ref` | `string`（任意） | `[marketplaces.allowed_sources."<name>"]`<br>`source = "git"`<br>`url = "https://github.com/example-org/codex-plugins.git"`<br>`ref = "0123456789abcdef0123456789abcdef01234567"` | `git` 規則で正確なGit refを要求する。省略すると一致リポジトリの任意refを許可する。 | 供給網リスクを下げるには、不変のコミットSHA等を検討。ブランチ名は同じref文字列でも内容が変わり得る。 |
| `marketplaces.allowed_sources.<name>.host_pattern` | `string`（正規表現） | `[marketplaces.allowed_sources."<name>"]`<br>`source = "host_pattern"`<br>`host_pattern = '^git\.example\.com$'` | `source = "host_pattern"` の必須パターン。HTTPS/SSH/SCP形式Gitソースから抽出した小文字ホスト名へ照合する。 | `^` と `$` で全体一致にする。例: `^git\.example\.com$`。 |
| `marketplaces.allowed_sources.<name>.path` | `string`（絶対パス） | `[marketplaces.allowed_sources."<name>"]`<br>`source = "local"`<br>`path = "/opt/company/codex-marketplace"` | `source = "local"` の必須ローカルマーケットプレイスディレクトリ。正規化後に比較する。 | 管理者のみ書込可能なディレクトリを使う。相対パス不可。 |

## MCPサーバー許可リスト

| 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `mcp_servers` | `table` | `[mcp_servers."<id>".identity]`<br>`url = "https://mcp.example.com/v1"` | ローカルクライアントが有効化できるMCPサーバーの許可リスト。サーバー名とidentityの両方が一致する必要がある。 | テーブルが存在して空の場合、すべてのMCPサーバーを無効化する。許可リスト外またはidentity不一致は無効化。 |
| `mcp_servers.<id>.identity` | `table` | `[mcp_servers."<id>".identity]`<br>`url = "https://mcp.example.com/v1"` | 1つのMCPサーバーの同一性規則。stdioは `command`、streamable HTTPは `url` のどちらかを設定する。 | 名前だけでなく実行ファイル／URLも固定する。 |
| `mcp_servers.<id>.identity.command` | `string \| table` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"` | stringは設定されたcommand文字列だけを完全一致。tableは実行ファイルと順序付き引数を厳密照合する。 | string形式は `args`, `cwd`, `env`, `env_vars` を検査しないため弱い。会社許可サーバーは構造化tableを推奨。 |
| `mcp_servers.<id>.identity.command.executable` | `string` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"` | stdio MCPの設定commandが一致すべき実行ファイルを完全一致で指定する。 | 可能なら絶対パスを使い、PATHハイジャックを避ける。 |
| `mcp_servers.<id>.identity.command.args` | `array<table>` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[mcp_servers."<id>".identity.command.args]]`<br>`match = "exact"`<br>`value = "--stdio"` | 位置ごとの引数matcher。設定引数は同じ個数・同じ順序で全位置一致する必要がある。 | 不要な可変引数を許可しない。なお `cwd`, `env`, `env_vars` は検査しない。 |
| `mcp_servers.<id>.identity.command.args[].match` | `exact \| prefix \| regex` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[mcp_servers."<id>".identity.command.args]]`<br>`match = "exact"`<br>`value = "--stdio"` | その位置の引数照合方式。 | 可能なら `exact`。`prefix` / `regex` は許可範囲をレビュー。 |
| `mcp_servers.<id>.identity.command.args[].value` | `string` | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[mcp_servers."<id>".identity.command.args]]`<br>`match = "prefix"`<br>`value = "--workspace="` | `exact` または `prefix` で使う値。 | シェルメタ文字やパス境界を意識して最小範囲にする。 |
| `mcp_servers.<id>.identity.command.args[].expression` | `string`（正規表現） | `[mcp_servers."<id>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[mcp_servers."<id>".identity.command.args]]`<br>`match = "regex"`<br>`expression = '^--tenant=[a-z0-9-]+$'` | `regex` で使う式。引数値全体に一致する必要がある。 | 全値一致でも、過度に広い `.*` は避ける。 |
| `mcp_servers.<id>.identity.url` | `string \| table` | `[mcp_servers."<id>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | stringは正確なURL、tableは `exact` / `prefix` / `regex` matcherでHTTP MCP URLを許可する。 | HTTPSと正確な組織管理ホストを優先。prefixで別パス・クエリまで広げない。 |
| `mcp_servers.<id>.identity.url.match` | `exact \| prefix \| regex` | `[mcp_servers."<id>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | 設定MCP URLの照合方式。 | 原則 `exact`。 |
| `mcp_servers.<id>.identity.url.value` | `string` | `[mcp_servers."<id>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | `exact` または `prefix` URL matcherの値。 | スキーム、ホスト、ポート、パス境界を含める。 |
| `mcp_servers.<id>.identity.url.expression` | `string`（正規表現） | `[mcp_servers."<id>".identity.url]`<br>`match = "regex"`<br>`expression = '^https://mcp\.example\.com/v[0-9]+$'` | `regex` URL matcherの式。URL全体に一致する必要がある。 | ホスト部分のエスケープとアンカーを確認。 |

## プラグイン同梱MCPサーバー

| 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `plugins` | `table` | `[plugins."<plugin>".mcp_servers."<server>".identity]`<br>`url = "https://mcp.example.com/v1"` | プラグインIDごとの、同梱MCPサーバー許可リスト。 | このテーブルが存在する場合、一致するプラグイン＋サーバー項目がない同梱MCPは無効化。プラグイン全体停止は `features.plugins = false`。 |
| `plugins.<plugin>.mcp_servers` | `table` | `[plugins."<plugin>".mcp_servers."<server>".identity]`<br>`url = "https://mcp.example.com/v1"` | 1プラグインに同梱されるMCPサーバーの許可リスト。 | トップレベルMCPと同じidentity形式を使う。 |
| `plugins.<plugin>.mcp_servers.<server>.identity` | `table` | `[plugins."<plugin>".mcp_servers."<server>".identity]`<br>`url = "https://mcp.example.com/v1"` | 1つのプラグイン同梱MCPの同一性規則。 | `command` または `url` のどちらかを設定。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.command` | `string \| table` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"` | stdioサーバーをcommand文字列または構造化matcherで照合する。 | string形式は引数等を検査しない。構造化形式を推奨。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.command.executable` | `string` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"` | 実行ファイル完全一致。 | 可能なら絶対パス。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.command.args` | `array<table>` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[plugins."<plugin>".mcp_servers."<server>".identity.command.args]]`<br>`match = "exact"`<br>`value = "--stdio"` | 順序・個数が完全一致する位置引数matcher。 | `cwd`, `env`, `env_vars` は照合対象外。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.command.args[].match` | `exact \| prefix \| regex` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[plugins."<plugin>".mcp_servers."<server>".identity.command.args]]`<br>`match = "exact"`<br>`value = "--stdio"` | 引数照合方式。 | 原則 `exact`。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.command.args[].value` | `string` | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[plugins."<plugin>".mcp_servers."<server>".identity.command.args]]`<br>`match = "prefix"`<br>`value = "--workspace="` | `exact` / `prefix` の値。 | 最小範囲。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.command.args[].expression` | `string`（正規表現） | `[plugins."<plugin>".mcp_servers."<server>".identity.command]`<br>`executable = "/usr/local/bin/company-mcp"`<br><br>`[[plugins."<plugin>".mcp_servers."<server>".identity.command.args]]`<br>`match = "regex"`<br>`expression = '^--tenant=[a-z0-9-]+$'` | `regex` の完全値一致式。 | 広すぎる式を避ける。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.url` | `string \| table` | `[plugins."<plugin>".mcp_servers."<server>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | streamable HTTP MCP URLの完全一致またはmatcher。 | 原則HTTPS＋exact。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.url.match` | `exact \| prefix \| regex` | `[plugins."<plugin>".mcp_servers."<server>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | URL照合方式。 | 原則 `exact`。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.url.value` | `string` | `[plugins."<plugin>".mcp_servers."<server>".identity.url]`<br>`match = "exact"`<br>`value = "https://mcp.example.com/v1"` | `exact` / `prefix` のURL値。 | スキーム・ホスト・ポート・パスを明確化。 |
| `plugins.<plugin>.mcp_servers.<server>.identity.url.expression` | `string`（正規表現） | `[plugins."<plugin>".mcp_servers."<server>".identity.url]`<br>`match = "regex"`<br>`expression = '^https://mcp\.example\.com/v[0-9]+$'` | `regex` のURL全体一致式。 | ホスト名のドット等を正しくエスケープ。 |

## ホスト別旧サンドボックス制約

| 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `remote_sandbox_config` | `array<table>` | `[[remote_sandbox_config]]`<br>`hostname_patterns = ["build-*.corp.example"]`<br>`allowed_sandbox_modes = ["read-only", "workspace-write"]` | ホスト名に応じて旧サンドボックス許可モードを変える規則配列。 | 現在上書きできるのは `allowed_sandbox_modes` だけ。権限プロファイルのホスト別切替ではない。 |
| `remote_sandbox_config[].hostname_patterns` | `array<string>` | `[[remote_sandbox_config]]`<br>`hostname_patterns = ["build-*.corp.example"]`<br>`allowed_sandbox_modes = ["read-only"]` | 大文字小文字を区別しないホスト名パターン。`*` は任意長、`?` は1文字。 | 取得ホスト名はベストエフォートで、FQDN優先・ローカル名へフォールバック。認証済み端末証明として使わない。 |
| `remote_sandbox_config[].allowed_sandbox_modes` | `array<string>` | `[[remote_sandbox_config]]`<br>`hostname_patterns = ["build-*.corp.example"]`<br>`allowed_sandbox_modes = ["read-only", "workspace-write"]` | パターン一致ホストに適用する旧サンドボックス許可モード。 | 同一要件ソース内では最初の一致規則が勝つ。規則順序をセキュリティ順にレビュー。 |

## 管理コマンドルール

| 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `rules` | `table` | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`justification = "会社PCでは再帰削除を禁止しています。"`<br>`pattern = [{ token = "rm" }, { any_of = ["-rf", "-fr"] }]` | `.rules` ファイルと合成される管理者強制コマンドルール。最も制限的な決定が優先される。 | 要件ルールは緩和に使えず、`allow` を指定できない。 |
| `rules.prefix_rules` | `array<table>` | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`pattern = [{ token = "rm" }, { any_of = ["-rf", "-fr"] }]` | コマンド先頭トークンのパターン規則一覧。各規則に `pattern` と `decision` が必須。 | シェル文字列ではなくトークン列として考える。ラッパーコマンドや別名による迂回もテスト。 |
| `rules.prefix_rules[].decision` | `prompt \| forbidden` | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`pattern = [{ token = "rm" }, { any_of = ["-rf", "-fr"] }]` | `prompt` は承認を要求し、`forbidden` は実行を拒否する。 | `allow` は要件では禁止。不可逆・管理者権限・資格情報抽出系は `forbidden` を検討。 |
| `rules.prefix_rules[].justification` | `string`（任意、非空） | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`justification = "会社PCでは再帰削除を禁止しています。"`<br>`pattern = [{ token = "rm" }, { token = "-rf" }]` | 承認画面または拒否メッセージに表示する理由。 | ユーザーが判断できる具体的理由と代替手段を書く。機密な検知条件は書かない。 |
| `rules.prefix_rules[].pattern` | `array<table>` | `[[rules.prefix_rules]]`<br>`decision = "prompt"`<br>`pattern = [{ token = "git" }, { any_of = ["push", "commit"] }]` | コマンドprefixをトークン位置ごとに表す。各位置は `token` または `any_of` のどちらか。 | すべての危険な変形を網羅できるとは限らない。サンドボックスと併用。 |
| `rules.prefix_rules[].pattern[].token` | `string` | `[[rules.prefix_rules]]`<br>`decision = "forbidden"`<br>`pattern = [{ token = "rm" }, { token = "-rf" }]` | その位置で一致させる1つのリテラルトークン。 | 大小文字・絶対パス・別バイナリ名など実環境で確認。 |
| `rules.prefix_rules[].pattern[].any_of` | `array<string>` | `[[rules.prefix_rules]]`<br>`decision = "prompt"`<br>`pattern = [{ token = "git" }, { any_of = ["push", "commit"] }]` | その位置で許容する複数候補トークン。 | 候補を広げすぎない。例: `git` の後の `push` / `commit`。 |

## native Windows要件

| 設定キー | 型・値 | 設定例（TOML） | 説明 | セキュリティ／運用上の注意 |
| --- | --- | --- | --- | --- |
| `windows` | `table` | `[windows]`<br>`allowed_sandbox_implementations = ["elevated"]`<br>`sandbox_private_desktop = true` | native Windowsサンドボックスに関する管理要件。 | WSL利用時とは強制機構が異なる。対象クライアントで確認。 |
| `windows.allowed_sandbox_implementations` | `array<string>`: `elevated`, `unelevated`（空不可） | `[windows]`<br>`allowed_sandbox_implementations = ["elevated"]` | `windows.sandbox` で選択できるnative Windows実装を限定する。両方許可かつ未選択なら `elevated` を優先する。 | `elevated` がより強い。`unelevated` はフォールバックでネットワーク分離が弱く、全split read/writeを強制できない。管理者権限・セットアップを検証。 |
| `windows.sandbox_private_desktop` | `boolean` | `[windows]`<br>`sandbox_private_desktop = true` | 最終サンドボックス子プロセスを専用プライベートデスクトップで動かすか固定する。 | 通常 `true`。互換性理由で旧 `Winsta0\Default` が必要な場合だけ `false` を試験。 |

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

## 配布前チェックリスト

| 確認項目 | 合格条件 |
| --- | --- |
| クライアント台帳 | 対象のChatGPTデスクトップアプリ、CLI、IDE拡張、OS、バージョンを把握し、使用キーの対応版を満たす。権限プロファイルは0.138.0以上。 |
| 権限制御方式 | `allowed_permission_profiles` / `default_permissions` を主方式とし、旧 `sandbox_mode` 設定を各 `config.toml` から除去する。混在期間だけ `allowed_sandbox_modes` を互換制約として残す。 |
| 許可リストの閉じ方 | `allowed_permission_profiles`、MCP、plugin MCP、marketplaceの省略／空テーブルの意味を実機で確認。特に空 `mcp_servers` は全MCP無効。 |
| Web・外部連携 | Web検索、Apps、MCP、Plugins、Browser、Computer Useを別々に評価し、使わない面を明示的に無効化する。 |
| 秘密情報 | `permissions.filesystem.deny_read` とカスタムプロファイルのdenyを設定し、`.env`、SSH、クラウド資格情報をテスト。native Windowsのシェル読取制限を別対策で補う。 |
| ネットワーク | `experimental_network` を使う場合はOS別パイロット、DNS、プロキシ、ローカルIP、Unix socket、EDRを検証。Web検索等には効かないことを確認。 |
| フック | 管理スクリプトをMDMで配布し、管理者のみ書込可能な絶対パス、署名／ハッシュ、タイムアウト、障害時挙動を確認。 |
| 更新 | アプリ内更新か中央更新のどちらかを必ず運用し、`check_for_update_on_startup` と `features.in_app_updates` を矛盾させない。 |
| 監査ログ | `log_dir` を設定する場合、平文TUIログを含む保存内容、ACL、暗号化、転送、保持、削除、個人情報を確認。 |
| パイロット | 小規模グループへ割り当て、許可操作、拒否操作、オフライン起動、ポリシー更新、複数要件層マージを確認してから全社配布。 |
| RBAC | クラウド要件とは別にChatGPTワークスペースの座席、ロール、コネクタAction control、外部サービス権限を設定。 |

## 公開リファレンス外のキーの扱い

OpenAI公式Codexリポジトリの実装には、公開 `requirements.toml` リファレンスより先行する、または特定配布経路向けと見られるフィールドが含まれることがある。しかし、`https://chatgpt.com/codex/cloud/settings/policies` での正式サポート範囲、クライアント対応版、安定性が公開リファレンスから確認できないキーは **不明** とする。本番では、上記の公開キー一覧と、明示的に参照されたPermissions／Hooks下位スキーマだけを使用する。

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

> 公式ドキュメントは更新される。ポリシー変更時は、上記Configuration Referenceの `requirements.toml` 節を再確認し、未掲載キーは「不明」として扱う。
