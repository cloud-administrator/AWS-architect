添付の「`requirements.toml` 設定項目一覧」をベースに、会社PCでセキュリティ管理する際に特に重要な項目へ集約すると、以下のようになります。添付資料は公開 `requirements.toml` リファレンスに掲載された管理者強制項目を対象としており、`config.toml` の全設定項目とは区別されています。

| 分類                  | 主要な設定キー                                                            | 説明                                                                                                                                                  |
| ------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **承認ポリシー**          | `allowed_approval_policies`                                        | Codexが操作を実行する際の承認方式を制限する。`untrusted`、`on-request`、`never`、`granular` から、ユーザーが選択できる方式を許可リスト化する。会社PCでは一般に `on-request` などを許可し、確認なしで進む `never` は慎重に扱う。 |
| **承認者**             | `allowed_approvals_reviewers`                                      | 危険性のある操作の承認を「利用者自身（`user`）」または「自動レビュー（`auto_review`）」のどちらに任せられるかを制限する。                                                                              |
| **自動レビュー方針**        | `guardian_policy_config`                                           | `auto_review` が承認判断するときに使用する会社独自のルールをMarkdownで指定する。「資格情報を読み取らない」「外部送信を禁止する」などを定義できる。                                                                |
| **権限プロファイルの許可**     | `allowed_permission_profiles`                                      | ユーザーが選択できる権限プロファイルを限定する。代表的には `:read-only`、`:workspace`、`:danger-full-access` があり、通常の会社PCでは `:danger-full-access` を禁止するのが安全側。Codex 0.138.0以降が必要。    |
| **既定権限**            | `default_permissions`                                              | 新しい作業を開始したときに標準で使用する権限プロファイルを指定する。一般的な開発端末なら `:workspace`、レビュー専用なら `:read-only` などを指定する。                                                            |
| **ファイルアクセス制御**      | `permissions.<name>.filesystem`                                    | カスタム権限プロファイル内で、パスごとに `read`、`write`、`deny` を設定する。ワークスペース内は書込み可にしつつ、`.env` や資格情報ファイルだけ拒否するといった制御が可能。                                                 |
| **機密ファイルの強制読取禁止**   | `permissions.filesystem.deny_read`                                 | SSH鍵、AWS/Azure/GCP資格情報など、Codexに絶対に読み取らせたくないパスを管理者が強制的に拒否する。ユーザー設定では弱められない。                                                                          |
| **ローカルコマンドのネットワーク** | `permissions.<name>.network`                                       | シェルやスクリプトなど、Codexが起動したローカルコマンドからネットワークへ接続できるかを制御する。`network.enabled = true` は通信を許可する設定であり、接続先制限には別途プロキシが必要。                                         |
| **ネットワーク宛先制限**      | `experimental_network`                                             | ローカルコマンドの通信を管理プロキシ経由にし、許可／拒否ドメインを強制する。`enabled`、`domains`、`managed_allowed_domains_only`、ローカル通信、上流プロキシ等を管理できる。実験的機能のため導入前試験が重要。                     |
| **Web検索**           | `allowed_web_search_modes`                                         | CodexのWeb検索を `disabled`、`cached`、`indexed`、`live` のどこまで許可するか制御する。外部Webへの直接アクセスを抑える場合は `cached` 以下に限定する。                                             |
| **機能の有効／無効**        | `[features]`                                                       | Apps、ブラウザー操作、Computer Use、Memories、Plugins、Multi-agent、Shell、Hooksなど、Codexの各機能を `true` / `false` で固定する。使わない機能を明示的に無効化するための重要な制御。                    |
| **Apps／コネクタ**       | `apps.<id>.enabled` / `apps.<id>.tools.<tool>.approval_mode`       | 外部アプリ／コネクタをアプリ単位で無効化したり、ツールごとに `auto`、`prompt`、`writes`、`approve` の承認方式を設定する。                                                                       |
| **MCPサーバー**         | `mcp_servers`                                                      | Codexへ接続できるMCPサーバーを完全許可リスト化する。サーバー名だけでなく実行ファイル、引数、URLまで照合でき、未承認MCPへの差し替えを防止できる。空テーブルの場合は全MCPを無効化できる。                                                |
| **プラグイン**           | `plugins` / `features.plugins`                                     | プラグイン機能そのものの有効／無効や、プラグインに同梱されるMCPサーバーを制限する。未承認コードや外部ツールが追加される経路を制御する。                                                                               |
| **プラグイン取得元**        | `marketplaces`                                                     | プラグインを取得できるGitリポジトリ、Gitホスト、ローカルディレクトリを会社承認済みの供給元だけに限定する。サプライチェーン対策として重要。                                                                            |
| **コマンドルール**         | `rules.prefix_rules`                                               | `rm -rf`、`git push` など特定のローカルコマンドをパターン照合し、`prompt`（承認要求）または `forbidden`（実行禁止）にする。サンドボックスに加える追加防御として利用する。                                            |
| **管理フック**           | `hooks` / `allow_managed_hooks_only`                               | ツール実行前後などに会社管理の検査スクリプトを実行できる。DLP確認、危険コマンド検査、監査などに利用できる。`allow_managed_hooks_only = true` でユーザー独自フックを排除できる。                                          |
| **ログインシェル**         | `allow_login_shell`                                                | シェル実行時にユーザーのログインシェル設定を読み込ませるかを制御する。資格情報や環境変数、起動スクリプトからの影響を減らすため、通常の会社PCでは `false` が安全側。                                                             |
| **Appshots／リモート操作** | `allow_appshots` / `allow_remote_control`                          | 画面・アプリ状態を画像として扱うAppshotsや、端末のリモートコントロール機能を許可するか制御する。不要なら明示的に `false` にする。                                                                           |
| **Computer Use**    | `features.computer_use` / `computer_use.allow_locked_computer_use` | Codexによる画面・アプリ操作を許可するか、端末ロック後も操作を継続できるかを制御する。通常の会社PCで不要なら機能全体を無効化する。                                                                                |
| **Windowsサンドボックス**  | `windows.allowed_sandbox_implementations`                          | native Windowsで `elevated` / `unelevated` のどのサンドボックス実装を許可するか限定する。企業標準では、前提条件を満たせる場合は強い分離を行う `elevated` が安全側。                                        |
| **更新管理**            | `check_for_update_on_startup` / `features.in_app_updates`          | Codexやデスクトップアプリの更新確認・アプリ内更新を管理する。MDMで中央更新する場合を除き、セキュリティ更新が止まらないように設計する。                                                                             |
| **フィードバック送信**       | `feedback.enabled`                                                 | CodexからOpenAIへフィードバックを送信できるかを制御する。コードや会話等が送信経路に含まれる可能性を避ける場合は `false` にする。                                                                          |
| **ログ・状態保存先**        | `log_dir` / `sqlite_home`                                          | Codexのローカルログや実行状態を保存する場所を管理者指定のディレクトリへ固定する。ACL、暗号化、保持期間、SIEM転送などと合わせて管理する。                                                                          |
| **データレジデンシー**       | `enforce_residency`                                                | Codexサービスの対応通信について、指定されたデータレジデンシーを要求する。現行資料では `us` が公開されている。契約・法務要件との確認が必要。                                                                         |
| **モデルの既定値**         | `models.new_thread`                                                | 新しいスレッドで使用するモデルや推論強度の「初期値」を設定する。ただし**セキュリティ上の強制設定ではなく、CLI等から上書き可能**なので、禁止モデルを制御する目的には使用しない。                                                         |

### 特に会社PCで優先したい制御

この中でもセキュリティ設計上の中核は、**①権限プロファイル、②承認、③ファイル読取制限、④ネットワーク制限、⑤Web・Apps・MCP・Plugins等の外部接続面、⑥コマンドルール、⑦Windowsサンドボックス**です。OpenAIの現行ガイドでも、新規導入では旧 `sandbox_mode` より `allowed_permission_profiles` と `default_permissions` を中心に設計することが案内されています。([ChatGPT Learn][1])

また、`requirements.toml` では**設定を省略しただけでは禁止になりません**。使わせたくない機能については、`false`、空の許可リスト、完全許可リストなど、その項目に応じた方法で明示的に閉じる必要があります。 ([ChatGPT Learn][2])

会社向けの説明資料としてさらに絞るなら、上表を **「設定項目／説明／推奨設定例／セキュリティ上の理由」の4列、10～15項目程度**にすると、情シス・セキュリティ部門にも読みやすい形になります。

[1]: https://learn.chatgpt.com/ja-JP/docs/permissions "https://learn.chatgpt.com/ja-JP/docs/permissions"
[2]: https://learn.chatgpt.com/ja-JP/docs/config-file/config-reference "https://learn.chatgpt.com/ja-JP/docs/config-file/config-reference"
