# Claude Code「管理された設定」で設定できる `settings.json` 全項目一覧

以下は **2026年8月19日時点**で、Anthropic の公式ドキュメントのみを調査し、
**Claude.ai ＞ 組織設定 ＞ Claude Code ＞ 管理された設定（Managed settings）** に投入できる JSON 設定を整理したものです。

Anthropic公式には、サーバー管理設定では原則として **`settings.json` で利用可能なすべての設定を利用でき、OSレベルのポリシー専用設定だけが例外**と明記されています。日本語版公式ページを基礎にしつつ、日本語版への反映がまだ追いついていない新しい設定については、同じ `code.claude.com` の英語最新版で補完しました。第三者サイトは使用していません。 ([Claude][1])

表中の **🔒** は「Managed settings でのみ意味を持つ、特に企業管理向けの設定」、**◇** は後半に子項目の詳細表がある設定、**⚠️** はセキュリティ上、値を慎重に決めるべき設定です。

---

## 0. 最初に知っておきたい `$schema`

これはClaude Codeの動作を変える設定ではなく、JSON編集支援用のメタデータです。

| 設定        | 型      | 説明                                                 | 企業利用でのポイント                                                             |
| --------- | ------ | -------------------------------------------------- | ---------------------------------------------------------------------- |
| `$schema` | string | Claude Code用JSON Schemaを指定し、VS Code等で入力補完・検証を有効にする | 管理画面では必須ではありません。公式Schemaは最新版CLIより更新が遅れる場合があるため、Schema警告＝必ず設定ミス、とは限りません |

公式の例でも `$schema` が使われています。 ([Claude][2])

---

# 1. 全設定一覧 A～C

この表は公式Settingsリファレンスの現在の `Available settings` を基にしています。 ([Claude][2])

| 設定キー                                 | 型・主な値                          | 何を設定するか                                                | 企業導入での意味・注意                                            |
| ------------------------------------ | ------------------------------ | ------------------------------------------------------ | ------------------------------------------------------ |
| `advisorModel`                       | string                         | Advisor機能で使うモデル。`fable` / `opus` / `sonnet` / 完全なモデルID | Advisorを使わせるモデルを統一できる                                  |
| `agent`                              | string                         | メインスレッドを指定したSubagentとして動作させる                           | 組織標準Agentをデフォルトにする用途                                   |
| `agentPushNotifEnabled`              | boolean                        | Remote Control中に、Claudeからスマホへ能動的なPush通知を送る             | 長時間タスク完了通知など。Remote Controlを使わないなら影響小                  |
| 🔒 `allowAllClaudeAiMcps`            | boolean                        | `managed-mcp.json` 利用時にもClaude.ai Connectorを追加で読み込ませる  | 厳格MCP管理時は安易に `true` にしない                               |
| 🔒 `allowedChannelPlugins`           | object[]                       | Channelsとして動作できるPluginをallowlist化                      | `channelsEnabled:true` と組み合わせる。`[]` は全Channel Plugin禁止 |
| `allowedHttpHookUrls`                | string[]                       | HTTP HookがアクセスできるURLをallowlist化                        | **Hookからの外部通信先制御として重要**。`[]` ならHTTP Hook全禁止            |
| ⚠️ `allowedMcpServers`               | object[]                       | 利用を許可するMCPサーバー                                         | `[]` はMCPを原則ロックダウン。詳細は後述                               |
| 🔒 `allowManagedHooksOnly`           | boolean                        | 管理者が許可したHooks中心に限定                                     | ユーザー／Project Hook等を封じる際に重要                             |
| 🔒 `allowManagedMcpServersOnly`      | boolean                        | 管理側 `allowedMcpServers` だけを有効なallowlistとして扱う           | **企業のMCPホワイトリスト化で非常に重要**                               |
| 🔒 `allowManagedPermissionRulesOnly` | boolean                        | 下位設定から `allow` / `ask` / `deny` Permissionルールを追加できなくする | 管理者の権限ポリシーをユーザーに変更させたくない場合に重要                          |
| `alwaysThinkingEnabled`              | boolean                        | Extended Thinkingを標準でONにする                             | 推論品質・コスト・レイテンシのポリシーに関係                                 |
| ⚠️ `apiKeyHelper`                    | string                         | 認証値を生成する外部コマンド                                         | Shellコマンドを実行する設定。Credential設計とセットでレビュー                 |
| `askUserQuestionTimeout`             | `60s` / `5m` / `10m` / `never` | AskUserQuestionが未回答のまま自動継続するまでの時間                      | `never` がデフォルト。無人処理時などに使用                              |
| ◇ `attribution`                      | object                         | Git commit / PRへClaude利用表記を付ける方法                       | `commit`、`pr`、`sessionUrl` を個別制御                       |
| `autoCompactEnabled`                 | boolean                        | Context逼迫時の自動CompactをON/OFF                            | 通常はONが合理的                                              |
| `autoCompactWindow`                  | number                         | 何token程度までContextを使ってからCompactするか                      | 100,000～1,000,000                                      |
| `autoMemoryDirectory`                | string                         | Auto Memoryの保存先を変更                                     | 企業管理下の保存場所に寄せる場合など                                     |
| `autoMemoryEnabled`                  | boolean                        | Auto Memoryの読み書きをON/OFF                                | セッションをまたぐ記憶を許可するかというポリシー                               |
| ◇ `autoMode`                         | object                         | Auto modeのClassifierに、何を許可・禁止させるか                      | AI分類器による権限制御。絶対禁止は `permissions.deny` を優先              |
| `autoScrollEnabled`                  | boolean                        | Fullscreen表示で新しい出力へ自動スクロール                             | UI設定                                                   |
| `autoUpdatesChannel`                 | `latest` / `stable`            | Claude Codeの更新チャネル                                     | **Enterpriseでは `stable` を検討しやすい設定**                    |
| `availableModels`                    | string[]                       | ユーザーが選択できるモデル                                          | モデル／コスト統制に重要                                           |
| `awaySummaryEnabled`                 | boolean                        | 端末に戻ったときセッションの1行要約を表示                                  | UI設定                                                   |
| ⚠️ `awsAuthRefresh`                  | string                         | AWS認証情報を更新するスクリプト                                      | Shell実行を伴う。AWS SSO等との統合用                               |
| ⚠️ `awsCredentialExport`             | string                         | AWS Credential JSONを返すスクリプト                            | Credential管理上、レビュー必須                                   |
| `axScreenReader`                     | boolean                        | Screen Reader向けの平坦なテキスト表示                              | アクセシビリティ                                               |
| 🔒 `blockedMarketplaces`             | object[]                       | 禁止するPlugin Marketplace source                          | Plugin supply-chain対策として重要                             |
| 🔒 `browserExternalPageTools`        | `"disabled"`                   | Desktop Browser上の外部ページにClaudeがツール操作することを禁止             | ユーザー自身のブラウズは残る                                         |
| 🔒 `channelsEnabled`                 | boolean                        | Claude Code Channelsを組織で許可                             | Enterprise/Teamでは明示許可に関係                               |
| 🔒 `claudeMd`                        | string                         | 組織共通のCLAUDE.md相当指示                                     | **全社員に組織ルールやコーディング方針を配る用途**                            |
| `claudeMdExcludes`                   | string[]                       | 読み込まないユーザー／Project CLAUDE.mdを指定                        | Managedの `claudeMd` 自体は除外できない                          |
| `cleanupPeriodDays`                  | integer ≥1                     | セッションファイル等を保持する日数                                      | デフォルト30日。データ保持ポリシーに関係                                  |
| `companyAnnouncements`               | string[]                       | 起動時に会社からのお知らせを表示                                       | 社内ガイドライン・注意事項の告知向け                                     |
| `crossSessionInbound`                | `accept` / `hold` / `refuse`   | 他Claude Codeセッションから届くメッセージをどう扱うか                       | `refuse` が最も厳格。Project側からより厳しくする例外あり                   |

---

# 2. 全設定一覧 D～F

この範囲には、企業セキュリティ上かなり重要な「禁止系」設定が集中しています。 ([Claude][2])

| 設定キー                                  | 型・主な値                               | 何を設定するか                                                             | 企業導入での意味・注意                                         |
| ------------------------------------- | ----------------------------------- | ------------------------------------------------------------------- | --------------------------------------------------- |
| `defaultShell`                        | `bash` / `powershell`               | 入力欄の `!` コマンドで使用するShell                                             | Windows中心環境ではPowerShellを指定可能                        |
| ⚠️ `deniedMcpServers`                 | object[]                            | 明示的に禁止するMCP                                                         | `allowedMcpServers` よりdenyが優先                       |
| `dialogExpiry`                        | `60s` / `5m` / `10m` / `never`      | Remote Client等に転送したDialogの期限                                        | Permission prompt本体とは別                              |
| `disableAgentView`                    | boolean                             | Background Agent、`claude agents`、`--bg` 等を無効化                       | Agentによる並行処理を禁止したい場合                                |
| `disableAllHooks`                     | boolean                             | Hooks、custom status line、custom file suggestion等を無効化                | 管理側Hooksとの優先関係には注意                                  |
| `disableArtifact`                     | boolean                             | Artifact公開機能を禁止                                                     | セッション内容をClaude.ai上のArtifactとして出したくない場合              |
| `disableAutoMode`                     | `"disable"`                         | Auto modeを完全に選択不可にする                                                | EnterpriseでManual中心にしたい場合                           |
| 🔒 `disableBrowserExternalNavigation` | boolean `true`                      | Desktop Browserから外部WebへのNavigationそのものを禁止                           | ユーザーもClaudeも外部サイトへ移動できなくなる                          |
| `disableBundledSkills`                | boolean                             | Claude Code同梱Skills/Workflowsを無効化                                   | Project/Plugin Skillは別制御                            |
| `disableClaudeAiConnectors`           | boolean                             | Claude.ai提供MCP Connectorsを無効化                                       | `true` は**どの設定スコープからでも制限側が優先**                      |
| 🔒 `disableCommandPluginSources`      | boolean                             | Marketplaceが任意コマンドでPluginをインストールする `command` sourceを禁止              | Supply-chain上重要。通常は厳格環境で `true` を検討                 |
| `disableDeepLinkRegistration`         | `"disable"`                         | `claude-cli://` OS protocol handlerの登録を禁止                           | 外部アプリからClaude Codeを起動するDeep Linkを抑止                 |
| `disabledMcpjsonServers`              | string[]                            | `.mcp.json` 内の特定サーバーを拒否                                             | Project MCPの個別拒否                                    |
| 🔒 `disableMobileSimulatorTools`      | boolean `true`                      | DesktopのiOS SimulatorをClaude自身が操作する機能を禁止                            | ユーザーによる手動Simulator利用は残る                             |
| `disableRemoteControl`                | boolean                             | Remote Control全体を禁止                                                 | `claude remote-control`、起動フラグ、自動接続等も抑止              |
| 🔒 `disableSideloadFlags`             | boolean                             | `--plugin-dir`、`--plugin-url`、`--agents`、`--mcp-config` 等による持ち込みを抑止 | **Plugin/MCP統制の抜け道対策**。MCPは `allowedMcpServers` も併用 |
| `disableSkillShellExecution`          | boolean                             | Skill内のinline shell commandを禁止                                      | User/Project/Plugin SkillのShell実行リスク低減              |
| `disableWorkflows`                    | boolean                             | Dynamic Workflowsおよびbundled workflowを禁止                             | AgenticなWorkflow利用を統制                               |
| `editorMode`                          | `normal` / `vim`                    | 入力欄のキー操作モード                                                         | UI                                                  |
| `effortLevel`                         | `low` / `medium` / `high` / `xhigh` | モデルのEffort設定                                                        | 品質・処理量の標準化に利用可能                                     |
| `emojiCompletionEnabled`              | boolean                             | `:heart:` 等の絵文字補完                                                   | UI                                                  |
| `enableAllProjectMcpServers`          | boolean                             | Project `.mcp.json` の全MCPを自動承認                                      | **企業管理では安易な `true` は注意**                            |
| `enableArtifact`                      | boolean                             | ユーザー側Artifact機能をON/OFF                                              | 管理側 `disableArtifact` が優先                           |
| `enabledMcpjsonServers`               | string[]                            | Project `.mcp.json` の特定MCPだけ承認                                      | Project MCPの選択的承認                                   |
| `enabledPlugins`                      | object                              | `plugin@marketplace: true/false` でPluginを強制ON/OFF                   | Managedで `true` にしたPluginは下位設定で無効化できない              |
| `enforceAvailableModels`              | boolean                             | `availableModels` をDefault modelにも強制                                | **モデルallowlistを実質的に強制したい場合重要**                      |
| `env`                                 | object<string,string>               | 全セッションと子プロセスへ環境変数を設定                                                | Proxy、Telemetry等に便利。秘密値の直書きは慎重に                     |
| ◇ `extraKnownMarketplaces`            | object                              | Marketplaceを事前登録                                                    | `strictKnownMarketplaces` は登録しないため、両方必要になることが多い     |
| `fallbackModel`                       | string[] 最大3                        | Primary model障害時のFallback順                                          | 配列は通常と違い、上位設定の**配列全体**が採用される                        |
| `fastMode`                            | boolean                             | Fast modeをON                                                        | 利用可能な環境のみ                                           |
| `fastModePerSessionOptIn`             | boolean                             | Fast modeをセッションごとに再度ONにさせる                                          | Fast modeの永続化を防ぐ                                    |
| `feedbackSurveyRate`                  | 0～1                                 | Session survey表示確率                                                  | `0` でSurveyを抑止                                      |
| `fileCheckpointingEnabled`            | boolean                             | 編集前にFile snapshotを取り `/rewind` を可能にする                               | デフォルトtrue                                           |
| ◇ `fileSuggestion`                    | object                              | `@` ファイル補完を独自コマンドに置換                                                | 外部コマンド実行になるので企業環境ではレビュー対象                           |
| ◇ `footerLinksRegexes`                | object[]                            | 出力中のIssue ID等をクリック可能Badge化                                          | 社内Issue Tracker連携に便利                                |
| `forceLoginMethod`                    | `claudeai` / `console` / `gateway`  | 許可するログイン方式を限定                                                       | 認証統制の中心設定                                           |
| 🔒 `forceLoginGatewayUrl`             | string                              | Cloud Gateway URLを固定                                                | Enterprise Gateway利用時                               |
| `forceLoginOrgUUID`                   | string または string[]                 | ログインを指定Anthropic Organizationに限定                                    | **個人Orgへのログイン防止に重要**。`[]` はログインをfail-closed         |
| 🔒 `forceRemoteSettingsRefresh`       | boolean                             | 最新Managed settingsを取得できなければCLIを起動させない                               | **fail-closed運用**に重要                                |

---

# 3. 全設定一覧 G～P

この範囲にはHooks、認証、モデル、Remote環境、Plugin設定などがあります。 ([Claude][2])

| 設定キー                              | 型・主な値                  | 何を設定するか                                               | 企業導入での意味・注意                                                                       |
| --------------------------------- | ---------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------- |
| ⚠️ `gcpAuthRefresh`               | string                 | GCP Application Default Credentials更新スクリプト            | Shell実行を伴う                                                                        |
| ◇ `hooks`                         | object                 | Claude Code Lifecycle Event発生時に処理を実行                  | **非常に強力。監査・強制チェックにも、任意コード実行にもなり得る**                                               |
| `httpHookAllowedEnvVars`          | string[]               | HTTP HookのHeaderに展開してよい環境変数名を限定                       | Credential漏えい対策                                                                   |
| `includeGitInstructions`          | boolean                | Claude標準のCommit/PR workflow指示とGit状態をSystem Promptに入れる | 独自Git Skillを使う場合にOFF可能                                                            |
| `inputNeededNotifEnabled`         | boolean                | Remote Control中、入力が必要になったらスマホへ通知                      | Remote利用時                                                                         |
| `isolatePeerMachines`             | boolean                | 別マシン上の自分のClaude sessionへSendMessageする際に明示承認           | `true` はどのスコープからでも制限側が優先                                                          |
| `language`                        | string                 | Claudeの標準応答言語                                         | `japanese` 等。音声入力やSession titleにも関連                                               |
| `minimumVersion`                  | version string         | Auto Updateがこれより古い版へ下がらないようにする                        | **起動自体は止めない**。起動を止めるなら `requiredMinimumVersion`                                   |
| `model`                           | string                 | デフォルト利用モデル                                            | 組織標準モデルを指定可能                                                                      |
| `modelOverrides`                  | object                 | Anthropic model IDをBedrock等のProvider固有IDにマッピング        | Third-party provider構成向け                                                          |
| `otelHeadersHelper`               | string                 | OpenTelemetry Headerを生成するScript                       | Observability統合                                                                   |
| `outputStyle`                     | string                 | System Promptへ適用するOutput Style                        | 全社的な回答スタイル統一にも使用可能                                                                |
| 🔒 `parentSettingsBehavior`       | `first-wins` / `merge` | SDK/IDEなど埋め込みHostから渡されたmanaged settingsとの合成方法         | 通常 `first-wins`。`merge` はHost policyも制限的に適用                                       |
| ◇ `permissions`                   | object                 | ClaudeのTool利用許可・確認・拒否                                 | **Enterprise設計で最重要項目の一つ**                                                         |
| `plansDirectory`                  | string                 | Plan modeのPlanファイル保存先                                 | 例 `./plans`                                                                       |
| `pluginConfigs`                   | object                 | Pluginの非機密オプション値                                      | Managed/User/`--settings` から利用。機密値向きではない                                          |
| 🔒 `pluginSuggestionMarketplaces` | string[]               | Contextual Plugin提案に出してよいMarketplace                  | 社内承認MarketplaceのみSuggestionに表示可能                                                  |
| 🔒 `pluginTrustMessage`           | string                 | Plugin install時のTrust Warningへ会社固有メッセージを追加            | 「IT承認済み」等の表示用                                                                     |
| `preferredNotifChannel`           | enum                   | Terminal/Desktop notification方式                       | `auto`, `terminal_bell`, `iterm2`, `kitty`, `ghostty`, `notifications_disabled` 等 |
| `prefersReducedMotion`            | boolean                | Animationを減らす                                         | アクセシビリティ                                                                          |
| ⚠️ `processWrapper`               | string                 | Claude Codeが生成するbackground processの前に企業Launcherを挿入    | EDR・監査・Container wrapper等と統合可能                                                    |
| `promptSuggestionEnabled`         | boolean                | 入力欄のPrompt suggestionをON/OFF                          | UI                                                                                |
| `prUrlTemplate`                   | string                 | PR URL Badgeを社内Code Review URLへ変換                     | GitHub URLを社内Review Toolへ転送する用途                                                   |

---

# 4. 全設定一覧 R～W

最新の公式Settingsでは、Remote Control、Skill、Voice、Agent Team、Worktreeなども `settings.json` 管理対象です。 ([Claude][2])

| 設定キー                               | 型・主な値                                         | 何を設定するか                                                     | 企業導入での意味・注意                                           |
| ---------------------------------- | --------------------------------------------- | ----------------------------------------------------------- | ----------------------------------------------------- |
| `remote.defaultEnvironmentId`      | string                                        | `claude --cloud` 等で使うデフォルトCloud/Self-hosted Environment     | `env_...` または `ccpool_...`                            |
| `remoteControlAtStartup`           | boolean                                       | Interactive session起動時にRemote Controlへ自動接続                  | Project/Local側の `false` はManagedの `true` より厳しいため尊重される |
| 🔒 `requiredMaximumVersion`        | version string                                | **これより新しいClaude Codeを起動禁止**                                 | 未検証新版へのアップデート防止                                       |
| 🔒 `requiredMinimumVersion`        | version string                                | **これより古いClaude Codeを起動禁止**                                  | 脆弱版／古い版を排除                                            |
| `respectGitignore`                 | boolean                                       | `@` file pickerで `.gitignore` を尊重                           | デフォルトtrue                                             |
| `respondToBashCommands`            | boolean                                       | 入力欄の `!command` 実行後にClaudeが応答するか                            | falseなら出力だけContextへ追加                                 |
| `showClearContextOnPlanAccept`     | boolean                                       | Plan承認画面に「contextをclear」を表示                                 | UI                                                    |
| `showThinkingSummaries`            | boolean                                       | Extended ThinkingのSummary表示                                 | 表示の問題であり、Thinking自体の生成量削減ではない                         |
| `showTurnDuration`                 | boolean                                       | 各Turnの所要時間を表示                                               | UI                                                    |
| `skillListingBudgetFraction`       | number                                        | Context WindowのうちSkill一覧に割り当てる割合                            | デフォルト0.01＝1%                                          |
| `skillListingMaxDescChars`         | integer                                       | Skill descriptionの最大文字数                                     | デフォルト1536                                             |
| `skillOverrides`                   | object                                        | Skillごとに `on` / `name-only` / `user-invocable-only` / `off` | Plugin Skillは別管理                                      |
| ⚠️ `skipWebFetchPreflight`         | boolean                                       | WebFetch前のAnthropic domain safety checkを省略                  | **安全機構を弱める設定**。閉域環境など必要時のみ                            |
| ◇ `spellcheck`                     | object                                        | Prompt入力のスペルチェック                                            | 例 `{enabled:true, language:"en_GB"}`                  |
| `spinnerTipsEnabled`               | boolean                                       | 処理中Tips表示                                                   | UI                                                    |
| ◇ `spinnerTipsOverride`            | object                                        | 独自Tipsを追加／標準Tipsを置換                                         | 社内ルールTipsにも利用可能                                       |
| ◇ `spinnerVerbs`                   | object                                        | 処理中の動詞をカスタマイズ                                               | UI                                                    |
| ◇ `sshConfigs`                     | object[]                                      | Claude DesktopのEnvironment dropdownにSSH接続先を定義               | Managed指定ならユーザー側ではread-only                           |
| ◇ `statusLine`                     | object                                        | CLI下部に独自Status lineを表示                                      | Script実行を伴う                                           |
| 🔒 `strictKnownMarketplaces`       | object[]                                      | 利用可能Plugin Marketplaceを厳格allowlist化                         | **Plugin supply-chain統制で重要**。`[]` は全面禁止               |
| 🔒 `strictPluginOnlyCustomization` | boolean / string[]                            | Skill、Agent、Hook、MCPを「PluginまたはManaged経由のみ」に限定              | `true` で4領域全部。部分指定も可能                                 |
| ◇ `subagentStatusLine`             | object                                        | Subagent Task表示行を独自コマンドで生成                                  | Script実行を伴う                                           |
| `switchModelsOnFlag`               | boolean                                       | Safety classifierでFlagされた際、自動でFallback modelへ切替             | falseならユーザーに確認                                        |
| `syntaxHighlightingDisabled`       | boolean                                       | Syntax Highlightを無効化                                        | UI                                                    |
| `teammateMode`                     | `in-process` / `auto` / `tmux` / `iterm2`     | Agent Teamの表示方法                                             | Agent Team利用時                                         |
| `terminalProgressBarEnabled`       | boolean                                       | 対応TerminalでProgress bar表示                                   | UI                                                    |
| `theme`                            | string                                        | CLI Theme                                                   | dark/light/ansi/daltonized/custom等                    |
| `tui`                              | `fullscreen` / `default`                      | Terminal renderer                                           | UI                                                    |
| `useAutoModeDuringPlan`            | boolean                                       | Plan modeでもAuto mode semanticsを使うか                          | Auto modeを許可する組織で検討                                   |
| `verbose`                          | boolean                                       | Tool outputを省略せず表示                                          | ログ／デバッグ向け                                             |
| `viewMode`                         | `default` / `verbose` / `focus`               | 起動時Transcript表示モード                                          | UI                                                    |
| `vimInsertModeRemaps`              | object                                        | Vim Insert modeの2キーEscape mapping                           | 例 `"jj":"<Esc>"`                                      |
| ◇ `voice`                          | object                                        | Voice Dictation設定                                           | `enabled`, `mode`, `autoSubmit`                       |
| `voiceEnabled`                     | boolean                                       | `voice.enabled` の旧Alias                                     | 新規設定では `voice` を推奨                                    |
| `wheelScrollAccelerationEnabled`   | boolean                                       | Fullscreen表示のWheel加速                                        | UI                                                    |
| `workflowKeywordTriggerEnabled`    | boolean                                       | Prompt中の `ultracode` キーワードでDynamic Workflowを発動するか           | falseなら単なる文字列として扱う                                    |
| `workflowSizeGuideline`            | `unrestricted` / `small` / `medium` / `large` | Dynamic Workflowが目標とするAgent数規模                              | **Hard limitではなくモデルへの指針**                             |
| ◇ `worktree`                       | object                                        | Git Worktree動作                                              | 詳細は後述                                                 |
| ◇ `sandbox`                        | object                                        | Bash等をFilesystem/Networkから隔離                                | **Enterprise設計で最重要項目の一つ**                             |

---

# 5. `permissions` の全子項目

`permissions` はClaude Code自身のTool実行判断を制御します。

Permission ruleは **`deny` → `ask` → `allow` の順**に評価され、最初に一致したルールが採用されます。したがって、企業管理では `deny` が最も強力です。 ([Claude][2])

| JSONキー                                             | 型           | 意味                                | 企業向けの使い方                                                                           |
| -------------------------------------------------- | ----------- | --------------------------------- | ---------------------------------------------------------------------------------- |
| `permissions.allow`                                | string[]    | 自動許可するTool/操作                     | `Bash(git diff *)` 等                                                               |
| `permissions.ask`                                  | string[]    | 実行前にユーザー確認                        | `Bash(git push *)` 等                                                               |
| `permissions.deny`                                 | string[]    | 完全に拒否                             | `.env`、secret、危険Command、MCP Tool等の禁止                                               |
| `permissions.additionalDirectories`                | string[]    | Claudeがアクセスできる追加Working Directory | Repo外のドキュメント参照等                                                                    |
| `permissions.defaultMode`                          | enum        | Session開始時のPermission mode        | `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`, `manual` |
| `permissions.disableAutoMode`                      | `"disable"` | Auto modeを禁止                      | Top-level `disableAutoMode` と同等                                                    |
| `permissions.disableBypassPermissionsMode`         | `"disable"` | `bypassPermissions` を禁止           | **`--dangerously-skip-permissions` も無効化。企業では重要**                                   |
| ⚠️ `permissions.skipDangerousModePermissionPrompt` | boolean     | bypass mode開始前の警告を省略              | Managedでこれを有効にするのは通常セキュリティ上慎重にすべき                                                  |

例えば、

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run test *)"
    ],
    "ask": [
      "Bash(git push *)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./secrets/**)",
      "Bash(curl *)"
    ],
    "disableBypassPermissionsMode": "disable"
  },
  "allowManagedPermissionRulesOnly": true
}
```

とすれば、概念的には

**テスト → 自動許可
Git push → 確認
秘密情報／curl → 禁止
権限バイパス → 禁止
ユーザーによるPermission rule追加 → 禁止**

という企業ポリシーにできます。 ([Claude][2])

---

# 6. `autoMode` の子項目

Auto modeの設定は公式に `environment`、`allow`、`soft_deny`、`hard_deny` と `classifyAllShell` が定義されています。Auto modeの判断はClassifierベースなので、**絶対に禁止したい操作は `permissions.deny` で実装する**ことをAnthropicも案内しています。 ([Claude][2])

| キー                          | 型        | 意味                                     |
| --------------------------- | -------- | -------------------------------------- |
| `autoMode.environment`      | string[] | 組織環境・信頼対象についてClassifierへ説明             |
| `autoMode.allow`            | string[] | Auto modeで許可したい操作ルール                   |
| `autoMode.soft_deny`        | string[] | 通常は止める方向でClassifierに判断させるルール           |
| `autoMode.hard_deny`        | string[] | より強く拒否させるClassifierルール                 |
| `autoMode.classifyAllShell` | boolean  | Bash/PowerShellの全CommandをClassifierへ通す |
| `"$defaults"`               | 特殊文字列    | 組み込みAuto mode ruleをその位置に継承             |

---

# 7. `sandbox` で設定できる全項目

Sandboxは `permissions` とは別物です。

**permissions = Claude CodeがToolを実行してよいか判断する論理制御**
**sandbox = 実行したProcessそのものをOSレベルでFilesystem/Networkから隔離する制御**

です。企業環境では両方を組み合わせます。 ([Claude][2])

## 7-1. Sandbox基本設定

| キー                                 | 型 / Default       | 意味                                           |
| ---------------------------------- | ----------------- | -------------------------------------------- |
| `sandbox.enabled`                  | boolean / `false` | Sandboxを有効化                                  |
| `sandbox.failIfUnavailable`        | boolean / `false` | Sandboxを起動できなければClaude CodeをError終了          |
| `sandbox.autoAllowBashIfSandboxed` | boolean / `true`  | Sandbox内Bashを自動承認                            |
| `sandbox.excludedCommands`         | string[]          | Sandbox外で実行するCommand                         |
| `sandbox.allowUnsandboxedCommands` | boolean / `true`  | `dangerouslyDisableSandbox` によるSandbox外実行を許可 |

厳格な企業環境なら、特に

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false
  }
}
```

が重要な設計候補です。 ([Claude][2])

---

## 7-2. Filesystem

公式Settingsでは以下が定義されています。 ([Claude][2])

| キー                                                | 型        | 意味                                                |
| ------------------------------------------------- | -------- | ------------------------------------------------- |
| `sandbox.filesystem.allowWrite`                   | string[] | Sandbox processが追加で書き込めるPath                      |
| `sandbox.filesystem.denyWrite`                    | string[] | 書込み禁止Path                                         |
| `sandbox.filesystem.denyRead`                     | string[] | 読取り禁止Path                                         |
| `sandbox.filesystem.allowRead`                    | string[] | `denyRead` 内で例外的に再許可するPath                        |
| 🔒 `sandbox.filesystem.allowManagedReadPathsOnly` | boolean  | `allowRead` をManaged settings側だけに限定               |
| ⚠️ `sandbox.filesystem.disabled`                  | boolean  | Filesystem isolationだけを完全OFF。Network isolationは残る |

`sandbox.filesystem.disabled:true` はFilesystem隔離を外すため、厳格なManaged policyでは通常慎重に扱うべき値です。 ([Claude][2])

Sandbox pathでは、

`/path` = Filesystem rootからの絶対Path、
`~/path` = Home directory、
`./path` = Project/User scopeに応じた相対Path

という規則があります。ただし、**サーバー管理設定で相対PathがどのDirectory基準になるかについて、今回確認した公式のPath表には明示がありませんでした。したがってその点は不明です。** Managed settingsでは誤解を避けるため、重要なPathは絶対Pathまたは `~/` を優先するのが安全です。 ([Claude][2])

---

# 8. Sandbox Credential保護

Claude Codeには、単にCredentialファイルを読めなくするだけでなく、Sandbox内では偽の値に置換し、許可した通信先へ出るときだけProxyが実Credentialへ差し替える仕組みまであります。 ([Claude][2])

## Credential file

| キー                          | 意味                                           |
| --------------------------- | -------------------------------------------- |
| `sandbox.credentials.files` | 保護対象File/Directory。各Entryに `path` と `mode`   |
| `files[].path`              | Credential Path                              |
| `files[].mode`              | `deny` または `mask`                            |
| `files[].extract`           | Credentialの一部分だけをmaskするRegex。capture group必須 |
| `files[].onExtractNoMatch`  | `warn` / `deny` / `error`                    |
| `files[].decode`            | 現在は `"jwt"`                                  |
| `files[].maskClaims`        | JWTの特定Claimだけmask                            |
| `files[].maskDuplicates`    | 同一Credential値の別出現箇所もmask                     |
| `files[].injectHosts`       | 実Credentialを復元してよい送信先Host                    |

## Environment Variable Credential

| キー                                            | 意味                                           |
| --------------------------------------------- | -------------------------------------------- |
| `sandbox.credentials.envVars`                 | 保護する環境変数                                     |
| `envVars[].name`                              | 環境変数名                                        |
| `envVars[].mode`                              | `deny` または `mask`                            |
| `envVars[].extract`                           | 値の一部をmaskするRegex                             |
| `envVars[].onExtractNoMatch`                  | `warn` / `deny` / `error`                    |
| `envVars[].decode`                            | 現在 `"jwt"`                                   |
| `envVars[].maskClaims`                        | JWT Claim単位のmask                             |
| `envVars[].injectHosts`                       | 実値を復元してよいHost                                |
| ⚠️ `sandbox.credentials.allowPlaintextInject` | HTTP平文通信でも実Credential挿入を許可。Default false     |
| `sandbox.credentials.awsPairs`                | AWS Access Key / Secret / Session Tokenの組を定義 |
| `sandbox.credentials.sigv4.streaming`         | `deny` / `passthrough`                       |
| `sandbox.credentials.sigv4.presigned`         | `deny` / `passthrough`                       |
| `sandbox.credentials.sigv4.sigv4a`            | `deny` / `passthrough`                       |

特に `allowPlaintextInject:true` は、平文HTTP経由でCredentialを扱えるようにするため、公式もTrusted test network以外ではOFFを推奨する内容になっています。 ([Claude][2])

---

# 9. Sandbox Networkの全設定

Network isolationもかなり細かく制御できます。 ([Claude][2])

| キー                                           | 型        | 意味・注意                                                           |
| -------------------------------------------- | -------- | --------------------------------------------------------------- |
| `sandbox.network.allowUnixSockets`           | string[] | macOSで許可するUnix Socket                                           |
| `sandbox.network.allowAllUnixSockets`        | boolean  | 全Unix Socketを許可                                                 |
| `sandbox.network.allowLocalBinding`          | boolean  | macOSでlocalhost port bindを許可                                    |
| `sandbox.network.allowMachLookup`            | string[] | macOSで追加許可するMach/XPC Service                                    |
| `sandbox.network.allowedDomains`             | string[] | Sandboxから通信できるDomain                                            |
| `sandbox.network.deniedDomains`              | string[] | 通信禁止Domain。Allowより優先                                            |
| `sandbox.network.strictAllowlist`            | boolean  | Allowlist外は確認せず拒否                                               |
| 🔒 `sandbox.network.allowManagedDomainsOnly` | boolean  | 下位設定からDomain allowを追加できなくする                                     |
| `sandbox.network.httpProxyPort`              | integer  | 独自HTTP ProxyのPort                                               |
| `sandbox.network.socksProxyPort`             | integer  | 独自SOCKS5 ProxyのPort                                             |
| ⚠️ `sandbox.network.tlsTerminate`            | object   | Sandbox proxyでTLS terminate。Credential maskingに必要               |
| ⚠️ `sandbox.enableWeakerNestedSandbox`       | boolean  | Linux/WSL2の弱いSandbox mode。**Security低下**                        |
| ⚠️ `sandbox.enableWeakerNetworkIsolation`    | boolean  | macOSのNetwork isolationを一部弱める。**Security低下**                    |
| ⚠️ `sandbox.allowAppleEvents`                | boolean  | macOS SandboxからApple Eventsを許可。**Code execution isolationを弱める** |
| `sandbox.ripgrep`                            | object   | Sandbox用custom `rg`。`command`, `args`                           |
| 🔒 `sandbox.bwrapPath`                       | string   | Linux/WSL2の `bwrap` binary絶対Path                                |
| 🔒 `sandbox.socatPath`                       | string   | Linux/WSL2の `socat` binary絶対Path                                |

企業のallowlist型Network設計なら、

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "network": {
      "allowedDomains": [
        "github.com",
        "*.npmjs.org"
      ],
      "strictAllowlist": true,
      "allowManagedDomainsOnly": true
    }
  }
}
```

のように、

**通信先を管理者が列挙
＋ 下位設定から追加不可
＋ Allowlist外は自動拒否**

という構造を作れます。 ([Claude][2])

---

# 10. MCP関連設定の詳細

MCP制御には、

`allowedMcpServers`
`deniedMcpServers`
`allowManagedMcpServersOnly`

の組み合わせが基本になります。Anthropic公式でも「Approved catalog」方式として `allowedMcpServers + allowManagedMcpServersOnly:true` が案内されています。 ([Claude][3])

`allowedMcpServers` / `deniedMcpServers` のEntryには主に次の識別方法があります。

| MCP識別方法         | 意味                      | Security上の扱い                     |
| --------------- | ----------------------- | -------------------------------- |
| `serverUrl`     | HTTP/SSE MCPのURLで識別     | **推奨**。実際の接続先に基づいて制御             |
| `serverCommand` | stdio MCPのCommand＋引数で識別 | **推奨**。実行されるProgramで制御           |
| `serverName`    | MCPにつけられた名前             | **Security boundaryとして使わない方がよい** |

公式は、`serverName` はユーザーが自由に付けられるLabelであり、**Security controlではない**と明示しています。厳格な制御には `serverUrl` または `serverCommand` を使います。 ([Claude][4])

企業で完全allowlistに近づけるなら、

```json
{
  "allowedMcpServers": [
    {
      "serverUrl": "https://approved-mcp.example.com/*"
    }
  ],
  "allowManagedMcpServersOnly": true
}
```

の考え方になります。

また、`managed-mcp.json` は別ファイルであり、**このClaude.aiの「管理された設定」画面から配布することはできません。** Endpoint/MDM等から配布します。 ([Claude][3])

---

# 11. Hooksで設定できる内容

`hooks` は概ね、

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/check.sh"
          }
        ]
      }
    ]
  }
}
```

という3階層です。

**Event → Matcher → Handler**

という構造です。 ([Claude][5])

## 利用可能なHook Event

現在の公式Referenceには次が掲載されています。 ([Claude][5])

| Event                 | 発生タイミング                      |
| --------------------- | ---------------------------- |
| `SessionStart`        | Session開始・再開                 |
| `Setup`               | init-only等のSetup             |
| `UserPromptSubmit`    | Prompt送信直後、Claude処理前         |
| `UserPromptExpansion` | Slash command等のPrompt展開時     |
| `PreToolUse`          | Tool実行直前                     |
| `PermissionRequest`   | Permission判断が必要なとき           |
| `PermissionDenied`    | Auto mode等でToolが拒否されたとき      |
| `PostToolUse`         | Tool成功後                      |
| `PostToolUseFailure`  | Tool失敗後                      |
| `PostToolBatch`       | 並列Tool batch完了後              |
| `Notification`        | Notification発生               |
| `MessageDisplay`      | Assistant message表示中         |
| `SubagentStart`       | Subagent開始                   |
| `SubagentStop`        | Subagent終了                   |
| `TaskCreated`         | Task作成                       |
| `TaskCompleted`       | Task完了                       |
| `Stop`                | Claudeの応答終了                  |
| `StopFailure`         | API Error等でTurn失敗            |
| `TeammateIdle`        | Agent TeamのTeammateがIdleになる前 |
| `InstructionsLoaded`  | CLAUDE.md / rules読込み         |
| `ConfigChange`        | 設定変更                         |
| `CwdChanged`          | Current directory変更          |
| `DirectoryAdded`      | `/add-dir` 等                 |
| `FileChanged`         | Watch対象File変更                |
| `WorktreeCreate`      | Worktree作成                   |
| `WorktreeRemove`      | Worktree削除                   |
| `PreCompact`          | Context Compact直前            |
| `PostCompact`         | Compact完了                    |
| `Elicitation`         | MCP Serverがユーザー入力を要求         |
| `ElicitationResult`   | MCP入力結果送信前                   |
| `SessionEnd`          | Session終了                    |

---

## Hook Handlerは5種類

公式には現在5種類あります。 ([Claude][5])

| `type`     | 実行内容              |
| ---------- | ----------------- |
| `command`  | Shell command     |
| `http`     | HTTP POST         |
| `mcp_tool` | 既に接続済みMCP Toolを呼ぶ |
| `prompt`   | Claudeモデルへ単発判定を依頼 |
| `agent`    | Agentによる判定        |

共通Fieldsは、

| Field           | 内容                                           |
| --------------- | -------------------------------------------- |
| `type`          | Handler type                                 |
| `if`            | Permission rule形式の追加Condition                |
| `timeout`       | Timeout秒数                                    |
| `statusMessage` | 実行中表示                                        |
| `once`          | Settings fileでは**無視される**。Skill frontmatter専用 |

Command Hookではさらに、

`command`、`args`、`async`、`asyncRewake`、`shell`

を指定できます。

HTTP Hookでは、

`url`、`headers`、`allowedEnvVars`

を指定できます。

MCP Tool Hookでは、

`server`、`tool`、`input`

を指定できます。

Prompt / Agent Hookでは、

`prompt`、`model`

を指定できます。 ([Claude][5])

---

# 12. Plugin / Marketplace の全設定

Plugin関連は、通常のAvailable settings表以外にも、公式Settingsページ内の専用Plugin sectionで定義されています。 ([Claude][2])

| キー                                 | 構造                              | 意味                                       |
| ---------------------------------- | ------------------------------- | ---------------------------------------- |
| `enabledPlugins`                   | `"plugin@marketplace": boolean` | PluginをON/OFF                            |
| `pluginConfigs`                    | `plugin ID -> options`          | Pluginの非機密設定値                            |
| `extraKnownMarketplaces`           | Marketplace名 → source           | Marketplaceを事前登録                         |
| 🔒 `strictKnownMarketplaces`       | source[]                        | どのMarketplaceからPluginを取得してよいか強制          |
| 🔒 `blockedMarketplaces`           | source[]                        | 明示的Marketplace blocklist                 |
| 🔒 `pluginSuggestionMarketplaces`  | string[]                        | Suggestion表示を許可するMarketplace             |
| 🔒 `pluginTrustMessage`            | string                          | Trust dialogへ組織メッセージ                     |
| 🔒 `strictPluginOnlyCustomization` | true / string[]                 | Customization sourceをPlugin/Managedだけに限定 |
| 🔒 `disableCommandPluginSources`   | boolean                         | Command source Pluginを禁止                 |
| 🔒 `disableSideloadFlags`          | boolean                         | CLI Flag経由のPlugin持込み等を禁止                 |

## `strictKnownMarketplaces` / `blockedMarketplaces` のSource type

公式の最新仕様では以下があります。 ([Claude][2])

| Source        | 主なField                        |
| ------------- | ------------------------------ |
| `github`      | `repo`, optional `ref`, `path` |
| `git`         | `url`, optional `ref`, `path`  |
| `url`         | `url`, optional `headers`      |
| `npm`         | `package`                      |
| `file`        | `path`                         |
| `directory`   | `path`                         |
| `hostPattern` | `hostPattern` regex            |
| `pathPattern` | `pathPattern` regex            |

`strictKnownMarketplaces: []` とすると、**Anthropic公式Marketplaceを含むすべてのMarketplace追加を禁止**します。 ([Claude][2])

また、

```text
strictKnownMarketplaces
```

は「許可するMarketplaceを登録する機能」ではなく、

**Marketplaceを追加してよいか判定するGate**

です。

したがって、

```text
strictKnownMarketplaces
+
extraKnownMarketplaces
```

を組み合わせ、

**許可先を限定し、その許可先を端末へ事前登録する**

設計が実用的です。 ([Claude][2])

---

# 13. Marketplace Alias

Claude Code v2.1.232以降では以下のAliasも認識されます。混在VersionのEnterprise fleetでは公式名を使う方が安全です。 ([Claude][2])

| Alias                    | 正式キー                      | 推奨      |
| ------------------------ | ------------------------- | ------- |
| `additionalMarketplaces` | `extraKnownMarketplaces`  | 正式キーを推奨 |
| `allowedMarketplaces`    | `strictKnownMarketplaces` | 正式キーを推奨 |

両方を同じファイルに書いた場合、正式キー側が優先されます。 ([Claude][2])

---

# 14. その他のObject型設定の詳細

## `attribution`

([Claude][2])

| 子キー                      | 説明                                                           |
| ------------------------ | ------------------------------------------------------------ |
| `attribution.commit`     | Git commitに追加するAttribution。`""` で非表示                         |
| `attribution.pr`         | PR本文へ追加するAttribution。`""` で非表示                               |
| `attribution.sessionUrl` | Cloud/Remote Control session URLをCommit/PRへ付けるか。Default true |

---

## `fileSuggestion`

([Claude][2])

| 子キー                      | 説明                   |
| ------------------------ | -------------------- |
| `fileSuggestion.type`    | 現在 `"command"`       |
| `fileSuggestion.command` | `@` 補完候補を生成するCommand |

Commandはstdinで `{"query":"..."}` を受け取り、改行区切りのPathをstdoutへ返します。現在は最大15件です。 ([Claude][2])

---

## `footerLinksRegexes`

([Claude][2])

| 子キー       | 説明                  |
| --------- | ------------------- |
| `type`    | `"regex"`           |
| `pattern` | 出力を検出する正規表現         |
| `url`     | BadgeのLink template |
| `label`   | optional表示名         |

最大5Badgeで、URL長等にも制約があります。正規表現はUI処理をBlockingするため、重いRegexを使わないことも公式で注意されています。 ([Claude][2])

---

## `spinnerTipsOverride`

| 子キー              | 説明                 |
| ---------------- | ------------------ |
| `excludeDefault` | `true` なら標準Tipsを除外 |
| `tips`           | 独自Tipの配列           |

## `spinnerVerbs`

| 子キー     | 説明                   |
| ------- | -------------------- |
| `mode`  | `replace` / `append` |
| `verbs` | 独自Verb配列             |

([Claude][2])

---

## `sshConfigs`

| 子キー               | 必須  | 説明            |
| ----------------- | --- | ------------- |
| `id`              | Yes | Connection ID |
| `name`            | Yes | 表示名           |
| `sshHost`         | Yes | SSH Host      |
| `sshPort`         | No  | SSH Port      |
| `sshIdentityFile` | No  | Identity file |
| `startDirectory`  | No  | 接続開始Directory |

Managed settingsで定義したSSH connectionはユーザーからread-onlyになります。 ([Claude][2])

---

## `statusLine`

公式Settings表で明示されているFieldsは次です。 ([Claude][2])

| 子キー                    | 説明                    |
| ---------------------- | --------------------- |
| `type`                 | `command`             |
| `command`              | Status line生成Command  |
| `padding`              | Padding               |
| `refreshInterval`      | 定期再実行Interval         |
| `hideVimModeIndicator` | Vim mode indicatorを隠す |

---

## `subagentStatusLine`

公式Settings表で確認できる構造は、

```json
{
  "type": "command",
  "command": "~/.claude/subagent-statusline.sh"
}
```

です。それ以外の子Fieldについては、今回確認したSettingsリファレンスの表では明示されていないため、**本回答では不明とします。** ([Claude][2])

---

## `spellcheck`

現在の公式例で確認できる子Fieldは、

```json
{
  "enabled": true,
  "language": "en_GB"
}
```

です。Claude Code v2.1.235以降で、別途Spell checkerのインストールが必要です。これ以外の子FieldについてはSettings表だけでは明示されていないため、本回答では不明とします。 ([Claude][2])

---

## `voice`

| 子キー                | 値              |
| ------------------ | -------------- |
| `voice.enabled`    | boolean        |
| `voice.mode`       | `hold` / `tap` |
| `voice.autoSubmit` | boolean        |

`voiceEnabled` は `voice.enabled` の旧Aliasです。 ([Claude][2])

---

# 15. `worktree` の全設定

Git Worktreeについては4項目あります。 ([Claude][2])

| キー                            | 値                   | 説明                                                  |
| ----------------------------- | ------------------- | --------------------------------------------------- |
| `worktree.baseRef`            | `fresh` / `head`    | 新WorktreeをどこからBranchするか。Default `fresh`             |
| `worktree.symlinkDirectories` | string[]            | Main RepoからWorktreeへsymlinkするDirectory              |
| `worktree.sparsePaths`        | string[]            | Sparse checkout対象Directory                          |
| `worktree.bgIsolation`        | `worktree` / `none` | Background sessionをWorktree隔離するか。Default `worktree` |

企業環境では `worktree.bgIsolation:"worktree"` の方が、Background AgentがMain Checkoutへ直接Edit/Writeすることを抑制できます。 ([Claude][2])

---

# 16. この「管理された設定」画面では設定できないもの

ここは非常に重要です。

公式Settingsリファレンスに名前が載っていても、今回の

**組織設定 ＞ Claude Code ＞ 管理された設定**

では有効にならないものがあります。 ([Claude][6])

| キー                           | この画面   | 理由                                                         |
| ---------------------------- | ------ | ---------------------------------------------------------- |
| `policyHelper`               | ❌ 不可   | MDMまたはSystem `managed-settings.json` 専用。Server-managedでは無視 |
| `wslInheritsWindowsSettings` | ❌ 不可   | Windows HKLM / System managed settings等のOSポリシー専用           |
| `ultracode`                  | ❌ 不可   | そもそも `settings.json` から読み込まれない                             |
| `managed-mcp.json`           | ❌ 配布不可 | Settings keyではなく別ファイル。Endpoint管理で配布                        |

---

# 17. `~/.claude.json` 用なのでここに書いてはいけないもの

現在の公式Settingsでは、次は **`settings.json` ではなく `~/.claude.json` に保存されるGlobal config** と明示されています。

`settings.json` に書いても起動時に黙って無視されます。 ([Claude][2])

| キー                           | 用途                             |
| ---------------------------- | ------------------------------ |
| `autoConnectIde`             | IDE自動接続                        |
| `autoInstallIdeExtension`    | IDE Extension自動Install         |
| `diffTool`                   | DiffをIDE/Terminalのどちらに出すか      |
| `externalEditorContext`      | External Editorへ前回Responseを入れる |
| `permissionExplainerEnabled` | Permission promptでmodel説明を表示   |
| `teammateDefaultModel`       | **v2.1.234で削除済み。現在は無視**        |

---

# 18. Managed settings特有の重要な挙動

管理画面のJSONは通常のUser settingsとは挙動が少し違います。

Managed settingsは設定階層の最上位で、通常はユーザー・Project・Local・CLIでは上書きできません。ただし、Securityを**より厳しくする方向**についてはいくつか例外があります。 ([Claude][2])

| 設定                          | 例外                                              |
| --------------------------- | ----------------------------------------------- |
| `disableClaudeAiConnectors` | 下位設定でも `true` なら禁止が優先                           |
| `isolatePeerMachines`       | 下位設定でも `true` なら隔離が優先                           |
| `remoteControlAtStartup`    | Project/Localの `false` はManaged `true` より優先できる  |
| `crossSessionInbound`       | Project/Local側がより厳しい `hold` / `refuse` ならそちらを採用 |

つまり基本思想は、

> **下位設定から企業ポリシーを緩めることはできないが、さらに厳しくすることは一部許される**

という設計です。 ([Claude][2])

---

# 19. JSONを間違えた場合の挙動も重要

Managed settingsは、通常の `settings.json` より寛容なParserになっています。

不正なEntryがあった場合、原則としてそのEntryだけを除外し、**残りの有効なPolicyは引き続き適用**されます。さらにSecurity enforcement系の一部Fieldは、不正値の場合に安全側へ倒れる特殊処理があります。 ([Claude][2])

特に、

| 設定                                                  | 不正値だった場合                               |
| --------------------------------------------------- | -------------------------------------- |
| `allowedMcpServers`                                 | Empty allowlist相当となり、MCPを許可しない方向       |
| `allowManagedHooksOnly`                             | `true` として扱う                           |
| `allowManagedMcpServersOnly`                        | `true` として扱う                           |
| `disableCommandPluginSources`                       | `true` として扱う                           |
| `availableModels`                                   | Empty allowlist相当                      |
| `enforceAvailableModels`                            | `true` として扱う                           |
| `forceLoginOrgUUID`                                 | Org Loginを許可しない方向                      |
| `sandbox.credentials`                               | 一部の不正mask設定は `deny` に劣化してCredentialを守る |
| `requiredMinimumVersion` / `requiredMaximumVersion` | 不正値は削除される＝**fail-open**                |

という違いがあります。 ([Claude][2])

AnthropicはFleet全体へ配る前に、

```text
claude doctor
```

で検証することを公式に案内しています。 ([Claude][2])

---

# 20. 管理画面そのものの制約

今回の「Managed settings」画面には、設定項目とは別に次の制約があります。

| 制約              | 内容                                               |
| --------------- | ------------------------------------------------ |
| 適用単位            | **組織内ユーザー全体へ一律**                                 |
| Group/部署別       | **現時点では未対応**                                     |
| MCP Server本体の配布 | `managed-mcp.json` は配布不可                         |
| OS専用Policy      | `policyHelper`、`wslInheritsWindowsSettings` 等は不可 |
| 管理できるRole       | Primary Owner / Owner                            |

([Claude][6])

---

# 21. 企業導入で特に重要な設定を優先順位で整理

全設定を検討すると非常に多いですが、セキュリティ設計としてまず見るべき部分は次のように整理できます。

| 優先度   | 領域                        | 最重要設定                                      | 何を決めるか                                |
| ----- | ------------------------- | ------------------------------------------ | ------------------------------------- |
| **S** | Permission                | `permissions.deny/ask/allow`               | Claudeに何をさせるか                         |
| **S** | Permission lock           | `allowManagedPermissionRulesOnly`          | ユーザーが権限ルールを緩められるか                     |
| **S** | Bypass                    | `permissions.disableBypassPermissionsMode` | Permission bypassを禁止するか               |
| **S** | Sandbox                   | `sandbox.enabled`                          | ProcessをOSレベルで隔離するか                   |
| **S** | Sandbox hard gate         | `failIfUnavailable`                        | Sandboxが使えなければ停止するか                   |
| **S** | Sandbox escape            | `allowUnsandboxedCommands`                 | Sandbox外実行を認めるか                       |
| **S** | MCP                       | `allowedMcpServers`                        | 利用可能MCP                               |
| **S** | MCP lock                  | `allowManagedMcpServersOnly`               | ユーザーがMCP allowlistを広げられるか             |
| **S** | Plugin                    | `strictKnownMarketplaces`                  | Plugin入手元                             |
| **S** | Plugin                    | `disableSideloadFlags`                     | CLIからの持込みを抑止するか                       |
| **A** | Hook                      | `allowManagedHooksOnly`                    | 独自Hookを許すか                            |
| **A** | Skill/Agent/MCP           | `strictPluginOnlyCustomization`            | Extension sourceをPlugin/Managedだけにするか |
| **A** | Authentication            | `forceLoginOrgUUID`                        | 会社Orgへのログインを強制するか                     |
| **A** | Authentication            | `forceLoginMethod`                         | Login方式                               |
| **A** | Version                   | `requiredMinimumVersion`                   | 古いClaude Codeを禁止                      |
| **A** | Version                   | `requiredMaximumVersion`                   | 未検証新版を禁止                              |
| **A** | Policy availability       | `forceRemoteSettingsRefresh`               | Policy取得失敗時にfail-closedにするか           |
| **A** | Credential                | `sandbox.credentials.*`                    | AWS/GitHub等Credentialをどう保護するか         |
| **A** | Network                   | `sandbox.network.*`                        | どの外部通信を許可するか                          |
| **B** | Model                     | `availableModels`                          | 利用モデルを絞る                              |
| **B** | Model                     | `enforceAvailableModels`                   | Default modelまでallowlistを強制           |
| **B** | Organization instructions | `claudeMd`                                 | 全社員共通のClaude指示                        |
| **C** | UX                        | `companyAnnouncements` 等                   | 標準UI・利用体験                             |

---

## 最後に

今回の調査範囲では、**Claude.aiの「組織設定 ＞ Claude Code ＞ 管理された設定」には、OSポリシー専用の `policyHelper` / `wslInheritsWindowsSettings` と、`settings.json` 非対応の `ultracode` 等を除いて、現在の `settings.json` 設定をほぼすべて投入できます。** Hooks、Sandbox、Credential masking、MCP、Plugin Marketplace、モデル、Remote Control、Channels、Agent Team、Voice、Worktree、UIまで対象です。 ([Claude][6])

また、Claude Codeは2026年現在も設定項目の追加がかなり速いため、企業向け設計では**Claude CodeのバージョンとManaged settingsのJSONをセットで管理**し、更新前に `claude doctor` でポリシー検証する運用が重要です。公式もFleet配布前の `claude doctor` による検証を案内しています。 ([Claude][2])

次の工程としては、この一覧をそのまま使うより、**「推奨値／セキュリティリスク／採用要否／採用理由／実際のJSON例」を追加した企業導入用の設定設計書形式に落とす**と、案件資料としてかなり扱いやすくなります。

[1]: https://code.claude.com/docs/ja/settings?utm_source=chatgpt.com "Claude Code の設定 - Claude Code Docs"
[2]: https://code.claude.com/docs/en/settings "Claude Code settings - Claude Code Docs"
[3]: https://code.claude.com/docs/en/managed-mcp "Control MCP server access for your organization - Claude Code Docs"
[4]: https://code.claude.com/docs/en/managed-mcp?utm_source=chatgpt.com "Control MCP server access for your organization - Claude Code Docs"
[5]: https://code.claude.com/docs/en/hooks "Hooks reference - Claude Code Docs"
[6]: https://code.claude.com/docs/ja/server-managed-settings?utm_source=chatgpt.com "サーバー管理設定を構成する - Claude Code Docs"
