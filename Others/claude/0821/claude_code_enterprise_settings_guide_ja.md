# Claude Code Enterprise 管理設定 `settings.json` 完全ガイド

> 対象: Claude Enterprise / Team の「組織設定 → Claude Code → 管理された設定」から配布するJSON、およびWindows／WSL2端末での動作差分  
> 調査日: **2026年8月20日（日本時間）**  
> 参照範囲: **Anthropic / Claude Codeの公式ドキュメントのみ**

---

## 1. この資料の結論

組織の管理画面から配布するJSONは、Claude Codeの一般的な `settings.json` と同じ形式です。現行の公式英語版の設定表に掲載された**トップレベル設定キー138件（互換用の旧キー `voiceEnabled` を含む）**を、本資料の「全設定項目一覧」に収録しています。さらに、`permissions`、`sandbox`、`hooks`、プラグイン、MCPなどの入れ子項目も別表で展開しています。

ただし、企業導入では次の点を最初に押さえる必要があります。

1. **サーバー管理設定は、原則として `settings.json` の全キーを受け付けます。** 例外は、OSポリシーからだけ有効になる `policyHelper` と `wslInheritsWindowsSettings` です。この2項目を組織管理画面のJSONへ書いても無視されます。[SM]
2. **管理画面の設定は組織内の全ユーザーへ一律適用され、グループ別配布はできません。** Windows用／WSL2用に管理画面上で分けることもできません。[SM]
3. **サーバー管理設定と端末管理設定は、通常はマージされません。** `policyHelper` があればその出力が優先され、なければ非空のサーバー管理設定が端末側のレジストリ／`managed-settings.json` より先に採用されます。一部のロック項目と、Claude Code v2.1.223以降の `env` のキー単位マージだけが例外です。[SM]
4. **ネイティブWindowsではClaude Codeのサンドボックスは利用できません。** WSL2ではLinux版として利用できます。WSL1でもClaude Code自体は実行できますが、サンドボックスは非対応です。[SETUP][SB]
5. **`processWrapper` はネイティブWindowsでは無視されます。** WSL2ではLinuxのexecランチャーとして利用できます。[PW]
6. **`managed-mcp.json` は管理画面から配布できません。** MCPを中央制御する場合、管理画面では `allowedMcpServers`、`deniedMcpServers`、`allowManagedMcpServersOnly` を使い、固定の `managed-mcp.json` は端末管理で別途配布します。[SM][MCP]
7. **管理設定はクライアント側制御であり、単独では強固なセキュリティ境界ではありません。** EDR、DLP、プロキシ、ファイルACL、秘密管理、端末管理と組み合わせてください。[SM]

### 日本語版と英語版の差

指定された日本語ページ `[SET-JA]` を基準に確認し、翻訳反映前の新項目については現行英語版 `[SET-EN]` で補完しました。日本語版と英語版で記述が異なる場合、本資料では**調査日時点の英語版を最新仕様として優先**しています。バージョン条件が公式に明記されている項目は補足欄へ記載し、公式資料だけでは断定できない点は「不明」としています。

---

## 2. 用語と記号

| 表記 | 意味 |
|---|---|
| **ネイティブWindows** | WSLの外側で、Windows版Claude CodeをPowerShell、Windows Terminal、cmd、Git Bashなどから実行する形態。 |
| **WSL2** | Windows上のWSL2 Linuxディストリビューション内へClaude Codeをインストールし、Linux版として実行する形態。Windows版と設定・PATH・ホームディレクトリが別です。 |
| **○** | 公式仕様上、その環境で利用可能。 |
| **△** | 利用可能だが、追加ツール、アカウント、パス、シェル、WSLg、Git、端末機能などの条件がある、またはOS差を考慮した実装が必要。 |
| **×** | 非対応、無視される、またはその実行形態には適用されない。 |
| **不明** | 公式ドキュメントだけでは明確に判断できない。 |
| **組織の管理設定: ○** | 組織管理画面のサーバー管理JSONで受け付けられる。推奨という意味ではありません。 |
| **組織の管理設定: ○（管理専用）** | 管理設定でだけ意味を持つ、または管理者による強制を目的とした項目。 |
| **組織の管理設定: ×** | 管理画面のサーバー配信では無視される。端末側のOSポリシー／システムファイルが必要。 |

OS列は、**JSONを配布できるかではなく、配布後にその機能が実際に動くか**を示します。たとえば `sandbox` は組織管理画面で配布できますが、ネイティブWindowsでは機能しません。

---

## 3. 組織管理画面から配布したときの仕組み

### 3.1 対象者、更新、権限

- 管理できるのは、公式仕様上 **Primary Owner / Owner** です。
- 設定は組織の全ユーザーに同じ内容で適用されます。ユーザー、部署、グループ、OSごとの割り当ては現時点でありません。
- クライアントは次回起動時に取得し、アクティブなセッションでは概ね1時間ごとに更新を確認します。
- `hooks`、`env`、管理専用キーもサーバー管理設定へ含められます。ただし `policyHelper` と `wslInheritsWindowsSettings` は除外されます。
- Hook、外部コマンド、特定の環境変数、`claudeMd` などは、内容によって利用者へセキュリティ承認ダイアログが表示されます。非対話実行では適用されても承認記録は残りません。

出典: [SM]

### 3.2 管理設定の優先順位

通常のユーザー／プロジェクト設定より、管理設定が最優先です。ただし、複数の管理方式を併用するときは、単純な『クラウド設定に端末設定を足す』動作ではありません。

1. `policyHelper` が有効なら、その出力がその実行の唯一の管理設定になります。
2. それ以外では、サーバー管理設定を先に確認します。
3. サーバー管理設定が非空なら、通常は端末管理のMDM、レジストリ、`managed-settings.json` を読み足しません。
4. サーバー管理設定が空なら、端末管理設定へフォールバックします。
5. 例外として、一部の『どこかの管理ソースでロックされていれば有効』となるキーと、v2.1.223以降の `env` のキー単位マージがあります。

> **企業設計上の重要事項:** 管理画面へ共通項目を1件でも入れたうえで、Windows端末側へWindows固有Hook、WSL2側へサンドボックス設定を置いて『追加分だけ端末側から継ぎ足す』設計は、原則として成立しません。

出典: [SET-EN][SM]

### 3.3 配信の成立条件とキャッシュ

- Anthropicのサーバー管理設定は、原則として `api.anthropic.com` への直接接続と、組織OAuthログインまたは直接設定されたAPIキーが必要です。
- `apiKeyHelper` が返すキーだけでは、サーバー管理設定の取得は開始されません。
- Amazon Bedrock、Google Cloud Agent Platform、Microsoft Foundry、第三者ゲートウェイ、カスタム `ANTHROPIC_BASE_URL` などでは、サーバー管理設定を利用できない場合があります。自社ホストのClaude apps gatewayは別扱いです。
- 初回取得に失敗した場合、既定では管理設定なしで進む短い時間帯が生じ得ます。`forceRemoteSettingsRefresh: true` は、起動時に最新設定を確認できない場合に起動を失敗させるフェイルクローズ用です。
- 取得済み設定はキャッシュされ、ネットワーク障害時にも使われます。ただしプロキシ、TLS、認証、APIルーティング等の一部 `env` 値は、サーバー確認前にキャッシュから適用されない保護があります。

出典: [SM]

### 3.4 端末管理方式と配置場所

| 方式 | Windows | WSL2 |
|---|---|---|
| サーバー管理 | 組織管理画面から取得 | 同じ組織ユーザーなら取得。ただしWSL内の認証・ネットワーク条件を満たす必要あり |
| OSポリシー | `HKLM\SOFTWARE\Policies\ClaudeCode` の `Settings`。ユーザー単位は `HKCU` だが優先度が低い | Windows側ポリシーを読むには `wslInheritsWindowsSettings` をWindows管理ソースに設定 |
| システムファイル | `C:\Program Files\ClaudeCode\managed-settings.json` | `/etc/claude-code/managed-settings.json` |
| 断片ファイル | 同ディレクトリの `managed-settings.d/*.json` | 同左。ファイル名順にマージ |

`C:\ProgramData\ClaudeCode\managed-settings.json` はv2.1.75以降サポートされません。端末側の断片ファイルは、基底ファイルの後にファイル名順で統合されます。この『端末内の断片同士のマージ』と、『サーバー管理設定と端末管理設定の非マージ』は別の規則です。[SET-EN]

### 3.5 検証方法

1. JSONはコメントと末尾カンマを許しません。UTF-8の正しいJSONとして保存します。
2. Claude Code内で `/status` を開き、`Setting sources` に `Enterprise managed settings (remote)`、`(HKLM)`、`(file)` など期待する配信元が出るか確認します。
3. `/permissions` で有効な権限ルールを確認します。
4. `/hooks` で登録されたHookを確認します。
5. `claude doctor` または `/doctor` で、無効な値や取り除かれた管理設定エントリを確認します。
6. 管理設定の1項目がスキーマ違反でも、v2.1.169以降は原則としてその項目だけが除去され、残りの有効なポリシーは適用されます。セキュリティ項目にはフェイルクローズ動作があります。

出典: [SET-EN]

---

## 4. WindowsネイティブとWSL2の重要差分

| 機能 | ネイティブWindows | WSL2 | 企業導入時の意味 |
|---|---|---|---|
| 通常のモデル、権限、表示設定 | ○ | ○ | JSON構造は同じ。ただしパス、環境変数、実行ファイル名はOS側に合わせる。 |
| シェルツール | Git BashがあればBash、なければPowerShellツール | LinuxのBash | HookのmatcherはWindowsで `Bash&#124;PowerShell` を検討。 |
| `defaultShell: "powershell"` | ○ | △ | Windowsでは対話 `!` コマンドをPowerShellへ。WSL2ではPowerShell 7 `pwsh` と環境変数が必要。 |
| サンドボックス | **×** | **○（WSL2のみ）** | 混在共通ポリシーで `failIfUnavailable: true` を設定しない。 |
| `processWrapper` | **×（無視）** | ○ | 監査ラッパーを必須にするならネイティブWindowsでは別の端末統制が必要。 |
| Hookのシェル形式 | △ Git BashまたはPowerShell | ○ `sh -c` | `.cmd` / `.bat` はexec形式ではなくシェル形式を使う。パス区切りにも注意。 |
| Hookのexec形式 (`args`) | △ 実体のある `.exe` 等が必要 | ○ | Windowsのnpm等の `.cmd` シムは直接spawnできないことがある。 |
| `statusLine` / `fileSuggestion` | △ Windows用コマンドが必要 | △ Linux用コマンドが必要 | 同じ管理JSONで1つのコマンドしか配れないため、OS共通ランチャーか端末別ポリシーが必要。 |
| `spellcheck` | △ `.cmd` シム対応。辞書ツールをPATHへ | △ 辞書ツールをPATHへ | v2.1.235以降。aspell/hunspell/ispellの配布が必要。 |
| Git worktree | △ GitとWindowsのsymlink権限等を確認 | △ Gitが必要 | 大規模展開前に実機検証。 |
| Windows実行ファイル連携 | ○ | △ Windows interop | サンドボックス内から `powershell.exe` 等を呼ぶとUnix socket許可等が必要で隔離を弱める。 |
| 音声入力 | △ マイク権限とClaude.aiアカウント | △ WSLg等のマイク連携条件 | HIPAA対応組織では無効。 |
| `wslInheritsWindowsSettings` | ×（ネイティブWindowsには効果なし） | △ Windowsの管理設定をWSLへ継承 | サーバー管理画面では無視。Windows管理ソースに置く。 |

出典: [SETUP][SET-EN][HOOK][PS][VOICE][PW][SB]

---

## 5. `settings.json` 全トップレベル設定項目一覧

以下は調査日時点の現行公式英語版の設定表に掲載された**トップレベルキー138件**です。互換用の旧キー `voiceEnabled` も、公式表に独立して掲載されるため含めています。その他の別名、廃止済み項目、`~/.claude.json` 専用項目は後段で分けています。型や既定値が公式ページで明示されない場合は、推測せず「未明記」「不明」としています。

出典: [SET-JA][SET-EN]

### 1. 組織管理・セキュリティ・配布制御

| No. | 設定キー | 型・既定値 | 何を制御するか（初心者向け） | 組織の管理設定 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|---|---|
| 1 | `$schema` | string（任意） | JSONエディターに入力補完と形式チェックをさせるためのスキーマURLです。Claude Codeの動作方針そのものは変えません。 | ○（通常は不要） | ○ | ○ | 公式ドキュメントの例は `https://json.schemastore.org/claude-code-settings.json`。公開スキーマが最新CLIより遅れる場合があります。 |
| 2 | `allowAllClaudeAiMcps` | boolean（既定: false相当） | 管理者が配布した `managed-mcp.json` がある場合でも、Claude.aiから取得するコネクターを追加で読み込ませます。 | ○（管理専用） | ○ | ○ | `managed-mcp.json` 自体は組織設定画面から配布できません。端末側で別途配布します。 |
| 3 | `allowedChannelPlugins` | object[]（未設定 / [] / 許可リスト） | 外部からClaude Codeへメッセージを送れる「チャネルプラグイン」を、マーケットプレイス名とプラグイン名で許可します。 | ○（管理専用） | △ | △ | `channelsEnabled: true` が必要。未設定はAnthropic既定、空配列はすべて禁止です。 |
| 4 | `allowedHttpHookUrls` | string[]（既定: 未制限） | HTTP Hookが送信してよいURLを制限します。社内Webhookなど、決めた送信先だけを許可したいときに使います。 | ○ | ○ | ○ | `*` ワイルドカード対応。空配列はHTTP Hookをすべて禁止。配列は設定ソース間で結合されます。 |
| 5 | `allowedMcpServers` | MCP照合条件[]（既定: 未制限） | 利用を許可するMCPサーバーを、URL・起動コマンド・名前で指定します。 | ○ | ○ | ○ | 空配列はMCPを全面禁止。`deniedMcpServers` が優先します。確実な統制には `allowManagedMcpServersOnly: true` も併用します。 |
| 6 | `allowManagedHooksOnly` | boolean（既定: false） | 管理者が配布したHookと、管理設定で強制有効化した信頼済みプラグインのHookだけを実行させます。 | ○（管理専用） | ○ | ○ | ユーザー・プロジェクト・ローカルHook等を遮断し、`statusLine`、`fileSuggestion`、`subagentStatusLine` の実行元も管理設定へ絞ります。v2.1.229以降は、`disableCommandPluginSources: false` を明示しない限りcommand由来プラグインも無効になります。 |
| 7 | `allowManagedMcpServersOnly` | boolean（既定: false） | MCPの許可リストについて、管理設定に書かれた `allowedMcpServers` だけを有効にします。 | ○（管理専用） | ○ | ○ | ユーザーはMCPを登録できても、管理者の許可条件に一致しなければ接続できません。拒否リストは全ソースから結合されます。 |
| 8 | `allowManagedPermissionRulesOnly` | boolean（既定: false） | ユーザーやリポジトリが `permissions.allow` / `ask` / `deny` を追加することを禁止し、管理者の権限ルールだけを適用します。 | ○（管理専用） | ○ | ○ | 企業ポリシーをユーザー設定で緩和・変更させたくない場合の中心設定です。 |
| 9 | `blockedMarketplaces` | marketplace照合条件[]（既定: なし） | 禁止するプラグイン・マーケットプレイスの取得元を指定します。 | ○（管理専用） | ○ | ○ | 追加・インストール・更新・自動更新の前に拒否します。GitHubの `owner/*` はv2.1.223以降。 |
| 10 | `browserExternalPageTools` | string（値: "disabled"） | Claude DesktopのBrowserペインで、Claudeが外部Webページを読み取り・操作するツールを止めます。ユーザー自身の手動閲覧は残ります。 | ○（管理専用） | △（Desktopのみ） | × | WindowsネイティブCLIではなくClaude Desktopの機能です。ローカル開発サーバーのプレビューは対象外です。 |
| 11 | `channelsEnabled` | boolean（既定: プラン・認証方式依存） | 組織でClaude Codeのチャネル機能を使用できるようにします。 | ○（管理専用） | △ | △ | Team/Enterpriseのclaude.ai認証では、未設定またはfalseならブロックされます。 |
| 12 | `claudeMd` | string（既定: 未設定） | 全社員に共通で読ませる `CLAUDE.md` 相当の組織指示を直接埋め込みます。例: コーディング規約や禁止事項。 | ○（管理専用） | ○ | ○ | ユーザー・プロジェクト・ローカル設定に書いても無視されます。内容によっては初回にセキュリティ承認が表示されます。 |
| 13 | `companyAnnouncements` | string[]（既定: なし） | Claude Code起動時に社員へ表示するお知らせを設定します。 | ○ | ○ | ○ | 複数ある場合はランダムに切り替えて表示されます。機密情報は書かないでください。 |
| 14 | `deniedMcpServers` | MCP照合条件[]（既定: なし） | 明示的に禁止するMCPサーバーを指定します。 | ○ | ○ | ○ | 許可リストより優先され、管理配布MCPも拒否できます。`serverName` は表示名ベースなので強いセキュリティ識別子ではありません。 |
| 15 | `disableAllHooks` | boolean（既定: false） | すべてのHookに加え、カスタム `statusLine` とカスタム `fileSuggestion` を停止します。 | ○ | ○ | ○ | 監査Hookも停止するため、管理設定で不用意にtrueにしないでください。 |
| 16 | `disableBrowserExternalNavigation` | boolean（値はJSONの true） | Claude DesktopのBrowserペインで外部サイトへの移動そのものを禁止します。ユーザーとClaudeの両方が対象です。 | ○（管理専用） | △（Desktopのみ） | × | 文字列の `"true"` は無効。localhostの開発プレビューは影響を受けません。 |
| 17 | `disableClaudeAiConnectors` | boolean（既定: false） | Claude.aiのMCPコネクターを自動取得・接続しないようにします。 | ○ | ○ | ○ | どの設定ソースでもtrueが優先。`--mcp-config` で明示したサーバーは別です。v2.1.182以降。 |
| 18 | `disableCommandPluginSources` | boolean（既定: allowManagedHooksOnlyに連動） | マーケットプレイスが端末上で任意コマンドを実行してプラグインを取得する `command` ソースを禁止します。 | ○（管理専用） | ○ | ○ | trueでは既存のcommand由来プラグインも読み込まれません。v2.1.229以降。 |
| 19 | `disableDeepLinkRegistration` | string（値: "disable"） | `claude-cli://` プロトコルハンドラーをOSへ登録しないようにします。外部アプリからプロンプト付きセッションを開く機能を止めます。 | ○ | ○ | 不明 | WSL2からWindows側のプロトコル登録をどう扱うかは、公式設定ページでは明記されていません。 |
| 20 | `disableMobileSimulatorTools` | boolean（値はJSONの true） | Claude DesktopのiOS Simulatorペインに対するClaudeの操作ツールを禁止します。 | ○（管理専用） | × | × | Windows/WSL2ではiOS Simulator機能が対象外です。ユーザーの手動操作まで禁止する設定ではありません。 |
| 21 | `disableRemoteControl` | boolean（既定: false） | Remote Controlを全面的に無効化します。コマンド、起動フラグ、自動開始、セッション内切替をすべて止めます。 | ○ | ○ | ○ | 端末単位のMDM強制にも向く設定です。 |
| 22 | `disableSideloadFlags` | boolean（既定: false） | `--plugin-dir`、`--plugin-url`、`--agents`、`--mcp-config` など、1回限りの持ち込み用CLIフラグを拒否します。 | ○（管理専用） | ○ | ○ | MCPの恒久登録やSDK経由まで全て止める設定ではありません。`allowedMcpServers` 等と組み合わせます。v2.1.193以降。 |
| 23 | `forceLoginMethod` | string（"claudeai" / "console" / "gateway"） | 社員が使用できるログイン方式を1種類に制限します。 | ○ | ○ | ○ | v2.1.212以降はCLIだけでなくVS Code拡張やAgent SDK等のファーストパーティ経路にも適用されます。 |
| 24 | `forceLoginGatewayUrl` | string（URL） | Cloud gatewayのURLをログイン画面に固定します。 | ○（管理ポリシー専用） | ○ | ○ | `forceLoginMethod: "gateway"` と併用します。ユーザー・プロジェクト設定では無視されます。 |
| 25 | `forceLoginOrgUUID` | string または string[] | Claude.aiでログインできるAnthropic組織UUIDを限定します。 | ○ | ○ | ○ | 空配列はログインを全面ブロックします。UUID誤りは全社員を締め出すため、段階展開が必須です。 |
| 26 | `forceRemoteSettingsRefresh` | boolean（既定: false） | 起動時にサーバー上の管理設定を必ず最新取得し、取得できなければClaude Codeを起動させません。 | ○（管理専用） | ○ | ○ | 可用性よりフェイルクローズを優先する設定。プロキシ障害や `api.anthropic.com` 到達不可でも起動失敗します。 |
| 27 | `parentSettingsBehavior` | string（既定: "first-wins"; "merge" 可） | Agent SDKやIDE拡張など親プロセスが渡す管理設定を、端末・サーバー管理設定とどう扱うか決めます。 | ○（管理専用） | ○ | ○ | `first-wins` は親設定を捨て、`merge` は制限を強める方向だけで下位に結合します。 |
| 28 | `pluginSuggestionMarketplaces` | string[]（既定: なし） | 状況に応じたプラグイン導入候補を表示してよいマーケットプレイス名を限定します。 | ○（管理専用） | ○ | ○ | そのマーケットプレイスの登録元も管理設定で一致させる必要があります。 |
| 29 | `pluginTrustMessage` | string（既定: なし） | プラグイン導入前の信頼警告に、社内向け注意文や審査済みである旨を追記します。 | ○（管理専用） | ○ | ○ | 信頼メッセージは技術的な許可制御ではありません。許可リストも併用します。 |
| 30 | `policyHelper` | object | 端末上の管理者配布プログラムを起動し、その端末・ユーザーに応じた管理設定JSONを動的に生成します。 | ×（サーバー配信では無視） | △（端末管理のみ） | △（端末管理のみ） | MDM/レジストリまたはシステム `managed-settings.json` からのみ有効。使うと他の管理設定ソースを置き換えます。 |
| 31 | `strictKnownMarketplaces` | marketplace照合条件[]（既定: 未制限） | 利用可能なプラグイン・マーケットプレイスの取得元を許可リスト方式で固定します。 | ○（管理専用） | ○ | ○ | 空配列は全マーケットプレイスをロックダウン。`allowedMarketplaces` はv2.1.232以降の別名です。 |
| 32 | `strictPluginOnlyCustomization` | boolean または string[] | スキル、エージェント、Hook、MCPを、プラグインまたは管理設定からだけ供給するよう制限します。 | ○（管理専用） | ○ | ○ | trueは4種類すべて。配列なら `skills` / `agents` / `hooks` / `mcp` の一部だけをロックします。 |
| 33 | `wslInheritsWindowsSettings` | boolean（既定: false） | WSL内のClaude Codeに、Windows側レジストリ/管理ファイルのポリシーも読ませます。 | ×（サーバー配信では無視） | ×（ネイティブには無効） | ○（端末管理のみ） | HKLMまたは `C:\Program Files\ClaudeCode\managed-settings.json` で設定。Windows側がWSL内 `/etc/claude-code` より優先します。 |

### 2. 認証・クラウドプロバイダー・モデル選択

| No. | 設定キー | 型・既定値 | 何を制御するか（初心者向け） | 組織の管理設定 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|---|---|
| 34 | `advisorModel` | string（"fable" / "opus" / "sonnet" / モデルID） | サーバー側Advisorツールが使うモデルを選びます。未設定ならAdvisorを無効にします。 | ○ | ○ | ○ | Fableは対象アクセス権が必要です。 |
| 35 | `alwaysThinkingEnabled` | boolean（既定: false相当） | 拡張思考を各セッションで最初から有効にします。 | ○ | ○ | ○ | 費用・応答時間に影響します。`env.MAX_THINKING_TOKENS=0` との関係やモデル例外を確認してください。 |
| 36 | `apiKeyHelper` | string（コマンド） | 短期APIキー等を生成する社内コマンドを呼び出し、その値を認証ヘッダーとして使います。 | ○ | △（cmd経由） | △（/bin/sh経由） | 管理画面へ設定すること自体は可能ですが、このヘルパーだけで得たキーではサーバー管理設定の取得が開始されません。コマンド出力・ログへの秘密漏えいに注意。 |
| 37 | `availableModels` | string[]（既定: 未制限） | メインセッション、サブエージェント、スキル、Advisorで選べるモデルを限定します。 | ○ | ○ | ○ | 空または不正な管理値は、バージョンによってDefault以外を使えなくするフェイルクローズ動作があります。 |
| 38 | `awsAuthRefresh` | string（コマンド） | AWS認証が必要になったとき、`.aws` ディレクトリを更新するログイン・更新スクリプトを実行します。 | ○ | △ | △ | WindowsとWSLでコマンド名・資格情報保存場所が異なります。 |
| 39 | `awsCredentialExport` | string（コマンド） | AWS資格情報をJSONで出力する社内スクリプトを呼び出します。 | ○ | △ | △ | 標準出力形式を公式仕様に合わせ、秘密を標準エラーやログに出さないでください。 |
| 40 | `effortLevel` | string（"low" / "medium" / "high" / "xhigh"） | モデルが問題解決にかける努力量をセッション間で保存します。 | ○ | ○ | ○ | 対応モデルのみ。`--effort` や環境変数がそのセッションでは優先されます。 |
| 41 | `enforceAvailableModels` | boolean（既定: false） | `availableModels` の制限を「Default」モデルにも適用します。 | ○ | ○ | ○ | 管理設定でtrueかつ許可リストが非空の場合、Defaultが許可外なら最初の利用可能な許可モデルへフォールバック。v2.1.175以降。 |
| 42 | `fallbackModel` | string または string[]（最大3モデル） | 主モデルが過負荷・利用不能のときに順番に試す代替モデルを指定します。 | ○ | ○ | ○ | この配列は通常の配列設定と違い、最上位の設定ソースが全体を置き換えます。 |
| 43 | `fastMode` | boolean（既定: false相当） | 利用可能なセッションでFast modeを有効にします。 | ○ | ○ | ○ | 機能・アカウント・モデル側の提供条件があります。 |
| 44 | `fastModePerSessionOptIn` | boolean（既定: false） | Fast modeの前回選択を次回へ自動継承せず、毎セッション `/fast` で明示的に有効化させます。 | ○ | ○ | ○ | ユーザーの保存済み好み自体は保持されます。 |
| 45 | `gcpAuthRefresh` | string（コマンド） | GCP Application Default Credentialsが期限切れ・未読込のとき、更新コマンドを実行します。 | ○ | △ | △ | WindowsとWSLで `gcloud` のインストール先・認証ファイルが別になることがあります。 |
| 46 | `model` | string（モデル別名またはID） | Claude Codeの既定モデルを指定します。 | ○ | ○ | ○ | `--model` と `ANTHROPIC_MODEL` が1セッションでは優先します。 |
| 47 | `modelOverrides` | object（モデルID → プロバイダー固有ID） | AnthropicのモデルIDを、Bedrock推論プロファイルARN等のプロバイダー固有IDへ置き換えます。 | ○ | ○ | ○ | 利用プロバイダーとリージョンごとのIDを厳密に確認してください。 |
| 48 | `otelHeadersHelper` | string（コマンド） | OpenTelemetry送信に付ける動的HTTPヘッダーを生成します。 | ○ | △ | △ | 起動時および定期的に実行。秘密値を持つ場合は、スクリプト・ACL・ログを保護してください。 |
| 49 | `outputStyle` | string（出力スタイル名） | システムプロンプトに出力スタイルを追加し、説明の仕方や回答形式を変えます。 | ○ | ○ | ○ | 変更は `/clear` または再起動で反映される項目です。 |
| 50 | `skipWebFetchPreflight` | boolean（既定: false） | WebFetch前にホスト名をAnthropicへ照会する安全確認を省略します。 | ○ | ○ | ○ | Anthropicへの通信を遮断するBedrock/Google Cloud/Microsoft Foundry等で必要になる場合がありますが、ブロックリスト照会を失うため慎重に使用します。 |
| 51 | `switchModelsOnFlag` | boolean（既定: true） | 安全分類器がリクエストをフラグしたとき、代替モデルへ自動切替するか、ユーザーに確認するかを決めます。 | ○ | ○ | ○ | falseでは一時停止し、モデル切替またはプロンプト編集を選ばせます。v2.1.170以降。 |

### 3. 権限・シェル・環境変数・サンドボックス

| No. | 設定キー | 型・既定値 | 何を制御するか（初心者向け） | 組織の管理設定 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|---|---|
| 52 | `autoMode` | object | Auto modeの分類器に、環境説明・許可・注意・禁止の自然言語ルールを与えます。 | ○ | ○ | ○ | 分類器への指示であり、技術的な強制境界ではありません。確実な禁止は `permissions.deny` やサンドボックスで行います。 |
| 53 | `defaultShell` | string（"bash" / "powershell"） | 入力欄で `!` を付けて実行する対話シェルの既定を決めます。 | ○ | ○ | △ | WindowsはGit BashがなければPowerShellが既定。WSLでPowerShellを使うには `pwsh` と `CLAUDE_CODE_USE_POWERSHELL_TOOL=1` が必要です。 |
| 54 | `disableAutoMode` | string（値: "disable"） | Auto modeを選択・起動できないようにします。 | ○ | ○ | ○ | `permissions.disableAutoMode` にも同じ値を書けます。管理設定で利用するとユーザーが再有効化できません。 |
| 55 | `disableSkillShellExecution` | boolean（既定: false） | ユーザー・プロジェクト・プラグイン等のスキル内に埋め込まれた `!` シェル実行を無効化します。 | ○ | ○ | ○ | 組み込みスキルと管理スキルは対象外です。 |
| 56 | `env` | object（環境変数名 → string） | Claude Code本体と、そこから起動するコマンド・Hookへ共通の環境変数を渡します。 | ○ | ○ | ○ | OSごとにPATH区切り・パス表記が違います。サーバー管理と端末管理が例外的にキー単位で結合されるのはv2.1.223以降です。秘密値の直書きは避けます。 |
| 57 | `permissions` | object | どのツール・コマンド・ファイル・ドメインを許可、確認、拒否するかを定義します。 | ○ | ○ | ○ | 評価順は `deny` → `ask` → `allow`、各配列内は最初に一致したルールです。詳細は専用表を参照。 |
| 58 | `processWrapper` | string または string[]（v2.1.210以降） | Claude Codeが起動するバックグラウンドプロセスの前に、EDR・監査用の社内ランチャーを付けます。 | ○ | ×（明示的に無視） | △ | Windowsでは `exec` ランチャー方式が未対応のため無効。WSL/Linuxでは実行ファイルと引数をシェル文字列ではなくargvとして設計します。 |
| 59 | `respondToBashCommands` | boolean（既定: true） | 入力欄の `!` コマンド終了後にClaudeが回答するかを決めます。 | ○ | ○ | ○ | falseではコマンド出力だけを会話コンテキストへ追加します。名称はBashですがPowerShell入力にも関係します。v2.1.186以降。 |
| 60 | `sandbox` | object（既定: disabled） | シェルコマンドをOSレベルで隔離し、読み書き可能なファイルと外向き通信先を制限します。 | ○ | × | △（WSL2のみ） | ネイティブWindowsはサンドボックス非対応。WSL2はbubblewrap/socat等が必要。`failIfUnavailable: true` を混在配信するとWindows起動を失敗させます。 |
| 61 | `useAutoModeDuringPlan` | boolean（既定: true） | Plan mode中にAuto modeの判定ルールも使うかを決めます。 | ○ | ○ | ○ | 共有プロジェクト設定からは読みません。 |

### 4. Hook・自動化・外部連携スクリプト

| No. | 設定キー | 型・既定値 | 何を制御するか（初心者向け） | 組織の管理設定 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|---|---|
| 62 | `fileSuggestion` | object（type, command） | `@` ファイル補完を、内蔵検索ではなく社内インデックス等のカスタムコマンドで実装します。 | ○ | △ | △ | stdinで検索語JSONを受け、改行区切りパスをstdoutへ返します。Hook制限・ワークスペース信頼の対象です。 |
| 63 | `footerLinksRegexes` | object[]（最大5バッジ表示） | 会話出力にチケット番号等が現れたら、フッターにクリック可能な社内リンクを表示します。 | ○ | ○ | ○ | 正規表現の名前付きキャプチャをURLへ差し込みます。重い正規表現はUIを停止させるため禁止します。v2.1.176以降。 |
| 64 | `hooks` | object | セッション開始、ツール実行前後、終了などのイベントで、コマンド・HTTP・MCP・LLM判定を実行します。 | ○ | △ | △ | Windowsの既定シェル、`.cmd/.bat`、PowerShell指定に注意。管理Hookでも内容によってユーザー承認が表示されます。 |
| 65 | `httpHookAllowedEnvVars` | string[]（既定: 未制限） | HTTP Hookのヘッダーへ展開してよい環境変数名を管理側で限定します。 | ○ | ○ | ○ | 各Hookの `allowedEnvVars` との積集合が実際の許可範囲。配列は設定ソース間で結合されます。 |
| 66 | `prUrlTemplate` | string（URLテンプレート） | GitHub PRバッジのリンク先を、社内レビューシステム等のURLへ置換します。 | ○ | ○ | ○ | `{host}`、`{owner}`、`{repo}`、`{number}`、`{url}` を使用。`gh` が取得したPR URLが前提です。 |
| 67 | `statusLine` | object（type, commandほか） | 入力欄付近に、モデル名、コスト、Gitブランチ等を表示する社内カスタム1行ステータスを作ります。 | ○ | △ | △ | 外部コマンド実行のため、OS別スクリプトが必要。`allowManagedHooksOnly` と `disableAllHooks` の制約対象です。 |
| 68 | `subagentStatusLine` | object（type, command） | サブエージェント一覧の各行を、外部コマンドで社内向け表示に書き換えます。 | ○ | △ | △ | stdinのJSONを読み、行ごとのJSONをstdoutへ返します。追加フィールドは公式記載がないため不明です。 |

### 5. コンテキスト・メモリ・Git・作業ディレクトリ

| No. | 設定キー | 型・既定値 | 何を制御するか（初心者向け） | 組織の管理設定 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|---|---|
| 69 | `askUserQuestionTimeout` | string（既定: "never"; "60s"/"5m"/"10m"） | AskUserQuestion画面を放置したとき、選択済み内容で自動継続するまでの時間を決めます。 | ○ | ○ | ○ | プロジェクト・ローカル設定からは読みません。v2.1.200以降。 |
| 70 | `attribution` | object（commit, pr, sessionUrl） | Claudeが作成したGitコミットとPR説明へ付ける帰属表示を変更・削除します。 | ○ | ○ | ○ | 監査・社内規程に合わせます。空文字で本文を消し、`sessionUrl: false` でセッションリンクを省略できます。 |
| 71 | `autoCompactEnabled` | boolean（既定: true） | コンテキスト上限が近いとき、古い会話を自動要約して継続できるようにします。 | ○ | ○ | ○ | falseでは長時間セッションが上限に達しやすくなります。 |
| 72 | `autoCompactWindow` | integer（100000～1000000 tokens） | 自動コンパクトを始めるコンテキスト使用量のしきい値を指定します。 | ○ | ○ | ○ | 未設定時はモデルに合わせて調整。大きくすると履歴保持は増えますが余裕が減ります。 |
| 73 | `autoMemoryDirectory` | string（絶対パスまたは ~/） | Auto memoryの保存先を標準場所から変更します。 | ○ | ○ | ○ | WindowsネイティブとWSLではホーム・パスが別です。共有場所にすると権限・機密・同時書込みを検討します。 |
| 74 | `autoMemoryEnabled` | boolean（既定: true） | Claudeが継続的な作業上の知識をAuto memoryへ読み書きする機能を有効・無効にします。 | ○ | ○ | ○ | 機密保持・保存期間の要件がある組織では保存先と併せて評価します。 |
| 75 | `claudeMdExcludes` | string[]（globまたは絶対パス） | ユーザー・プロジェクト・ローカルの `CLAUDE.md` のうち、読み込ませないものを除外します。 | ○ | ○ | ○ | 管理ポリシーの `claudeMd` は除外できません。パターンは絶対パスに対して照合されます。 |
| 76 | `cleanupPeriodDays` | integer（既定: 30、最小: 1） | 起動時に、指定日数より古いセッションファイル等のアプリデータを削除します。 | ○ | ○ | ○ | 法務・監査・データ保持方針と整合させます。平文トランスクリプト書込み自体を止める設定とは別です。 |
| 77 | `dialogExpiry` | string（既定: "5m"; "60s"/"5m"/"10m"/"never"） | Remote Control等へ転送したダイアログや保留メッセージ承認が期限切れになる時間を指定します。 | ○ | △ | △ | 通常の権限プロンプトとAskUserQuestionは別の仕組み。v2.1.224以降。 |
| 78 | `fileCheckpointingEnabled` | boolean（既定: true） | ファイル編集前にスナップショットを取り、`/rewind` で戻せるようにします。 | ○ | ○ | ○ | 無効化するとディスク使用量は減りますが、Claude Code内の巻き戻し能力を失います。 |
| 79 | `includeGitInstructions` | boolean（既定: true） | Claudeのシステムプロンプトに、組み込みのコミット/PR手順とGit状態スナップショットを含めます。 | ○ | ○ | ○ | 独自Gitワークフロースキルへ全面置換する場合にfalseを検討します。 |
| 80 | `plansDirectory` | string（既定: ~/.claude/plans） | Plan modeが作成する計画ファイルの保存先を変更します。 | ○ | ○ | ○ | 相対パスはプロジェクトルート基準。WindowsとWSLでパス表記・実体が異なります。 |
| 81 | `respectGitignore` | boolean（既定: true） | `@` ファイルピッカーで `.gitignore` 対象ファイルを候補から除外するか決めます。 | ○ | ○ | ○ | falseにするとビルド成果物や秘密ファイルが候補に出る可能性があります。 |
| 82 | `worktree` | object | `--worktree` やサブエージェント分離で作るGit worktreeの基点、シンボリックリンク、sparse-checkout、バックグラウンド分離を設定します。 | ○ | △ | △ | Gitが必要。Windowsのシンボリックリンク権限・挙動は公式Claude Code文書では詳細不明です。 |

### 6. エージェント・スキル・ワークフロー・プラグイン・MCP

| No. | 設定キー | 型・既定値 | 何を制御するか（初心者向け） | 組織の管理設定 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|---|---|
| 83 | `agent` | string（エージェント名） | メイン会話を指定したサブエージェント定義として実行し、`claude agents` から起動するセッションの既定エージェントにもします。 | ○ | ○ | ○ | そのエージェントのシステムプロンプト、ツール制限、モデルが適用されます。 |
| 84 | `disableAgentView` | boolean（既定: false） | バックグラウンドエージェントとAgent viewを停止します。 | ○ | ○ | ○ | `claude agents`、`--bg`、`/background`、オンデマンドsupervisorが対象です。 |
| 85 | `disableBundledSkills` | boolean（既定: false） | Claude Code同梱のスキルとワークフローを削除します。 | ○ | ○ | ○ | プラグインや `.claude/skills/`、`.claude/commands/` は残ります。組み込みコマンドの一部は入力可能なままです。 |
| 86 | `disableWorkflows` | boolean（既定: false） | 動的ワークフローと同梱ワークフローコマンドを無効化します。 | ○ | ○ | ○ | エージェント数や自動並列化を統制したい場合に使います。 |
| 87 | `disabledMcpjsonServers` | string[]（MCPサーバー名） | プロジェクトの `.mcp.json` に定義された特定MCPサーバーを拒否します。 | ○ | ○ | ○ | 組織全体の厳格なMCP統制には、管理専用の許可/拒否設定も併用します。 |
| 88 | `enableAllProjectMcpServers` | boolean（既定: false） | プロジェクト `.mcp.json` にあるすべてのMCPサーバーを自動承認します。 | ○ | ○ | ○ | 企業環境ではリポジトリを信頼できる場合だけ使用。未信頼フォルダでの扱いはv2.1.196以降強化されています。 |
| 89 | `enabledMcpjsonServers` | string[]（MCPサーバー名） | プロジェクト `.mcp.json` のうち、自動承認するサーバーを個別指定します。 | ○ | ○ | ○ | `enableAllProjectMcpServers` より限定的な運用に向きます。 |
| 90 | `enabledPlugins` | object（plugin@marketplace → boolean） | 特定プラグインを有効または無効にします。管理設定でtrueにするとユーザーが無効化できません。 | ○ | ○ | ○ | 外部ソースのプラグインは、各端末にインストールされていなければ有効化だけでは導入されません。 |
| 91 | `extraKnownMarketplaces` | object（名前 → source定義） | 社内Git、URL、npm、ローカルファイル等の追加マーケットプレイスを登録します。 | ○ | △ | △ | Windows/WSLでローカルパスとSSH資格情報が別。`additionalMarketplaces` はv2.1.232以降の別名です。 |
| 92 | `pluginConfigs` | object（plugin ID → options） | プラグインが公開する非機密オプションを、プラグインID単位で設定します。 | ○ | ○ | ○ | 秘密値は置かないでください。ユーザー、`--settings`、管理設定からのみ読みます。 |
| 93 | `skillListingBudgetFraction` | number（既定: 0.01） | 各ターンでモデルに見せるスキル一覧へ、コンテキストの何割を使うか決めます。 | ○ | ○ | ○ | 上げると説明を多く見せられますが、会話・コードに使えるコンテキストが減ります。 |
| 94 | `skillListingMaxDescChars` | integer（既定: 1536） | 1スキルあたり、モデルへ見せる説明文の最大文字数を決めます。 | ○ | ○ | ○ | 長くすると理解しやすい一方、スキル一覧のコンテキスト消費が増えます。 |
| 95 | `skillOverrides` | object（skill名 → "on"/"name-only"/"user-invocable-only"/"off"） | SKILL.mdを変更せず、個々のスキルを表示・名前だけ表示・手動専用・無効に切り替えます。 | ○ | ○ | ○ | プラグイン由来スキルには適用されません。 |
| 96 | `teammateMode` | string（既定: "in-process"） | Agent teamのメンバーを同一画面内に表示するか、tmux/iTerm2の分割ペインへ出すか決めます。 | ○ | △ | △ | Windowsネイティブは `in-process` が確実。WSL2でtmux表示するにはtmuxが必要。iTerm2モードはWindows/WSL対象外です。 |
| 97 | `workflowKeywordTriggerEnabled` | boolean（既定: true） | 入力プロンプト中の `ultracode` キーワードで動的ワークフローを起動するか決めます。 | ○ | ○ | ○ | falseでも `/workflows` や保存済みワークフロー等は無効になりません。 |
| 98 | `workflowSizeGuideline` | string（既定: "medium"; unrestricted/small/medium/large） | 動的ワークフローでClaudeが目安とするエージェント数を指定します。 | ○ | ○ | ○ | 強制上限ではなく助言です。v2.1.219以降。日本語ページの古い記載と配置が異なるため、現行英語公式ページを優先しました。 |

### 7. 画面表示・入力・アクセシビリティ・通知

| No. | 設定キー | 型・既定値 | 何を制御するか（初心者向け） | 組織の管理設定 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|---|---|
| 99 | `autoScrollEnabled` | boolean（既定: true） | フルスクリーン表示で、新しい出力に合わせて自動的に最下部へスクロールします。 | ○ | ○ | ○ | falseでも権限プロンプトは見える位置へ移動します。 |
| 100 | `awaySummaryEnabled` | boolean（既定: true相当） | 数分間ターミナルから離れて戻ったとき、セッションの1行要約を表示します。 | ○ | ○ | ○ | 共有画面で情報露出を避けたい場合はfalseを検討します。 |
| 101 | `axScreenReader` | boolean（既定: false） | 装飾枠やアニメーションを減らした、スクリーンリーダー向けの平坦なテキスト表示にします。 | ○ | ○ | ○ | 有効時はクラシックレンダラーを使うため `tui` は無効。v2.1.181以降。 |
| 102 | `editorMode` | string（既定: "normal"; "normal"/"vim"） | 入力欄のキーバインドを通常操作またはVim操作に切り替えます。 | ○ | ○ | ○ | Vim操作を全社員へ強制すると初心者の入力障害になり得るため、通常はユーザー選択向きです。 |
| 103 | `emojiCompletionEnabled` | boolean（既定: true） | `:heart:` のようなショートコード入力時に絵文字候補を出し、確定時に絵文字へ置換します。 | ○ | ○ | ○ | v2.1.217以降。 |
| 104 | `feedbackSurveyRate` | number（0～1） | 条件を満たしたセッション終了時に品質アンケートを表示する確率を指定します。 | ○ | ○ | ○ | 0で完全に抑止。既定サンプル率は認証プロバイダー等で異なるため、公式文書に単一値の記載はありません。 |
| 105 | `language` | string（例: japanese） | Claudeの既定回答言語、音声入力言語、自動生成セッションタイトルの言語を指定します。 | ○ | ○ | ○ | 技術用語まで必ず翻訳する強制仕様ではなく、応答言語の希望です。 |
| 106 | `preferredNotifChannel` | string（既定: "auto"） | 完了・権限確認の通知方法を、端末ベルや対応ターミナル通知などから選びます。 | ○ | △ | △ | `terminal_bell` は広く利用可能。iTerm2/Ghostty/Kitty固有値はWindows/WSLの使用ターミナルに依存します。 |
| 107 | `prefersReducedMotion` | boolean（既定: false相当） | スピナー、シマー、点滅などのUIアニメーションを減らします。 | ○ | ○ | ○ | アクセシビリティや画面共有時の視認性向上に使います。 |
| 108 | `promptSuggestionEnabled` | boolean（既定: true） | 入力欄に薄い文字で表示される次のプロンプト候補を有効・無効にします。 | ○ | ○ | ○ | 環境変数 `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION` が優先します。 |
| 109 | `showClearContextOnPlanAccept` | boolean（既定: false） | Plan承認画面に「コンテキストをクリアする」選択肢を表示します。 | ○ | ○ | ○ | trueにすると以前のUI選択肢を復元します。 |
| 110 | `showThinkingSummaries` | boolean（既定: false） | 対話セッションで拡張思考の要約を表示します。 | ○ | ○ | ○ | 表示だけを変え、モデルが生成する思考量や料金は減りません。`-p`、Agent SDK、IDE拡張では無効です。 |
| 111 | `showTurnDuration` | boolean（既定: true） | 各回答後に、そのターンにかかった時間を表示します。 | ○ | ○ | ○ | ユーザー体験のみを変えます。 |
| 112 | `spellcheck` | object（enabled, checker, language, color） | 入力中のスペルミスに下線を付けます。 | ○ | △ | △ | v2.1.235以降。aspell/hunspell/ispellのいずれかをPATHへ導入する必要があります。Windowsの `.cmd` シムも公式対応です。 |
| 113 | `spinnerTipsEnabled` | boolean（既定: true） | Claudeが処理中にスピナー横へヒントを表示します。 | ○ | ○ | ○ | 社内標準手順だけを見せたい場合は `spinnerTipsOverride` と組み合わせます。 |
| 114 | `spinnerTipsOverride` | object（excludeDefault, tips） | 処理中のヒントを社内独自文へ追加または置換します。 | ○ | ○ | ○ | `excludeDefault: true` なら組み込みヒントを除外します。機密URLや認証情報は書かないでください。 |
| 115 | `spinnerVerbs` | object（mode: "replace"/"append", verbs） | 処理中に表示される動詞を、独自語へ置換または追加します。 | ○ | ○ | ○ | 動作や性能は変わらず、表示だけです。 |
| 116 | `syntaxHighlightingDisabled` | boolean（既定: false） | diff、コードブロック、ファイルプレビューの構文色分けを無効化します。 | ○ | ○ | ○ | アクセシビリティや低機能端末向け。 |
| 117 | `terminalProgressBarEnabled` | boolean（既定: true） | 対応ターミナルのタブ・ウィンドウに進行状況を表示します。 | ○ | △ | △ | 公式対応例はConEmu、Ghostty 1.2.0+、iTerm2 3.6.6+。使用ターミナル依存です。 |
| 118 | `theme` | string（既定: dark） | 画面テーマを自動、明るい、暗い、色覚対応、ANSI、カスタムテーマから選びます。 | ○ | ○ | ○ | カスタムテーマは配布済みテーマ/プラグインが必要です。 |
| 119 | `tui` | string（"fullscreen" / "default"） | ターミナル描画方式を、フリッカーを抑えた全画面方式または従来方式へ切り替えます。 | ○ | ○ | ○ | スクリーンリーダーモード中は無効。端末互換性問題時は `default` を試します。 |
| 120 | `verbose` | boolean（既定: false） | ツール出力を省略要約せず、より完全に表示します。 | ○ | ○ | ○ | ログ量・画面情報量が増えます。`--verbose` がセッション単位で優先。 |
| 121 | `viewMode` | string（既定: "default"; default/verbose/focus） | 起動時の会話表示を通常、詳細、集中表示から選びます。 | ○ | ○ | ○ | `--verbose` が優先します。 |
| 122 | `vimInsertModeRemaps` | object（2文字 → "<Esc>"） | Vim INSERTモードで、`jj` のような2文字連続入力をEscapeへ割り当てます。 | ○ | ○ | ○ | `editorMode: "vim"` のときだけ有効。キーは印字可能な2文字、値は `<Esc>` のみ。v2.1.208以降。 |
| 123 | `wheelScrollAccelerationEnabled` | boolean（既定: true） | フルスクリーン表示でマウスホイールを速く回したとき、スクロール量を加速します。 | ○ | ○ | ○ | 一定量で動かしたい場合はfalse。v2.1.174以降。 |

### 8. Remote Control・Desktop・セッション間通信・音声

| No. | 設定キー | 型・既定値 | 何を制御するか（初心者向け） | 組織の管理設定 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|---|---|
| 124 | `agentPushNotifEnabled` | boolean（既定: false） | Remote Control接続中、長時間タスク完了などをClaudeの判断でスマートフォンへプッシュ通知します。 | ○ | △ | △ | Remote Control、対応アカウント、通知許可が必要です。 |
| 125 | `crossSessionInbound` | string（"accept" / "hold" / "refuse"） | 同じユーザーの別Claude Codeセッションから届くメッセージを、自動受信・保留・破棄のどれにするか決めます。 | ○ | △ | △ | v2.1.224以降。通常は管理→`--settings`→ユーザーの順ですが、プロジェクト／ローカルの値が `accept < hold < refuse` でより厳しい場合は、管理設定より優先されます。 |
| 126 | `disableArtifact` | boolean（既定: false） | セッション出力をclaude.ai上の非公開Webページとして公開するArtifactツールを禁止します。 | ○ | △ | △ | 組織で外部Web公開機能を使わせない場合に有効。 |
| 127 | `enableArtifact` | boolean（既定: アカウント提供状況に従う） | ユーザー単位でArtifactツールを有効または無効にします。 | ○ | △ | △ | 管理 `disableArtifact` と組織管理画面の設定が優先。プロジェクト/ローカル設定では無視されます。v2.1.196以降。 |
| 128 | `inputNeededNotifEnabled` | boolean（既定: false） | Remote Control接続中、権限確認や質問への回答が必要になったときスマートフォンへ通知します。 | ○ | △ | △ | Remote Controlと通知許可が必要です。 |
| 129 | `isolatePeerMachines` | boolean（既定: false） | Claudeが別マシン上の自分のセッションへメッセージを送る前に、必ず明示承認を求めます。 | ○ | △ | △ | どの設定ソースのtrueも有効。`bypassPermissions` 中でも承認が必要。v2.1.224以降。 |
| 130 | `remote` | object | クラウドセッション関連の設定をまとめます。現行の公式設定項目は `remote.defaultEnvironmentId` です。 | ○ | △ | △ | クラウド環境機能を使えるアカウント・組織が必要です。 |
| 131 | `remoteControlAtStartup` | boolean または未設定 | 対話セッション開始時にRemote Controlへ自動接続します。 | ○ | △ | △ | 未設定なら組織既定または製品既定。プロジェクト／ローカルの `true` は無視されますが、そこで指定した `false` は管理設定の `true` より厳しい例外として優先されます。 |
| 132 | `sshConfigs` | object[] | Claude Desktopの環境選択欄に、管理済みSSH接続先を表示します。 | ○ | △（Desktopのみ） | × | 管理設定ではユーザーに対して読み取り専用。Windows Desktopでの認証方式詳細は公式設定ページだけでは不明です。 |
| 133 | `voice` | object（enabled, mode, autoSubmit） | 音声入力を有効にし、押している間だけ録音するか、タップで開始/停止するかを設定します。 | ○ | △ | △ | Claude.aiアカウントとマイク権限が必要。WSL2ではマイク連携にWSLg等の条件があります。HIPAA対応組織では利用不可。 |
| 134 | `voiceEnabled` | boolean（旧別名） | `voice.enabled` の旧式の別名です。 | ○ | △ | △ | 新規設定では `voice` オブジェクトを使用してください。 |

### 9. 更新チャネル・バージョン統制

| No. | 設定キー | 型・既定値 | 何を制御するか（初心者向け） | 組織の管理設定 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|---|---|
| 135 | `autoUpdatesChannel` | string（既定: "latest"; "latest"/"stable"） | 自動更新で追従するリリースチャネルを選びます。 | ○ | ○ | ○ | `stable` は通常約1週間遅れ、重大な回帰を避けるチャネル。自動更新自体の無効化は `env.DISABLE_AUTOUPDATER` を使います。 |
| 136 | `minimumVersion` | string（バージョン） | 自動更新や `claude update` が、この値より古い版へ下げないようにします。 | ○ | ○ | ○ | 起動は止めません。起動時に古い版を拒否するには `requiredMinimumVersion` を使います。 |
| 137 | `requiredMaximumVersion` | string（バージョン） | 指定版より新しいClaude Codeの通常起動を禁止します。 | ○（管理専用） | ○ | ○ | 回復用の `claude update`、`claude install`、`claude doctor` は実行可能。古すぎてこの設定を知らない版には効きません。 |
| 138 | `requiredMinimumVersion` | string（バージョン） | 指定版より古いClaude Codeの通常起動を禁止します。 | ○（管理専用） | ○ | ○ | 古すぎてこの設定を実装していない版には効かないため、配布基盤側の更新統制も必要です。 |

---

## 6. 入れ子設定の完全リファレンス

トップレベル表だけではJSONを組み立てにくい項目を、設定パス単位で展開します。

### 6.1 `permissions`

`permissions` はツール利用の許可・確認・拒否を定義する中核ポリシーです。評価は `deny` → `ask` → `allow` の順です。管理者が完全に統制したい場合は `allowManagedPermissionRulesOnly: true` も設定します。

出典: [PERM][SET-EN]

| 設定パス | 型・既定値 | 初心者向け説明 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|
| permissions.allow | string[] | 自動許可するツール利用ルール。例: `Bash(git diff *)`。 | ○ | ○ | MCPツール名のglobには制約があります。 |
| permissions.ask | string[] | 一致した操作を実行前に必ず確認するルール。 | ○ | ○ | 高リスクだが業務上必要な操作に向きます。 |
| permissions.deny | string[] | 一致した操作を拒否するルール。機密ファイルや危険コマンドの遮断に使います。 | ○ | ○ | `deny` が最優先。`Read` の拒否は同じパスのEdit/Writeも止めます。 |
| permissions.additionalDirectories | string[] | 通常のプロジェクト以外に、Claudeが作業対象として読めるディレクトリを追加します。 | ○ | ○ | 追加先の `.claude/` 設定の多くは自動発見されません。 |
| permissions.defaultMode | string | 新規セッションが開始する権限モードを指定します。 | ○ | ○ | 値は下表。CLI `--permission-mode` が優先。 |
| permissions.disableAutoMode | string: "disable" | Auto modeを選べないようにします。 | ○ | ○ | トップレベル `disableAutoMode` と同じです。 |
| permissions.disableBypassPermissionsMode | string: "disable" | `bypassPermissions` と `--dangerously-skip-permissions` を無効にします。 | ○ | ○ | 企業環境で強く推奨される防御設定の一つです。 |
| permissions.skipDangerousModePermissionPrompt | boolean | 危険なbypassモードへ入る前の確認画面を省略します。 | ○ | ○ | 安全性を下げます。プロジェクト設定では無視されます。管理設定でtrueにすることは通常推奨しません。 |

### 6.2 `permissions.defaultMode` の値

既定モードは、個別ルールに一致しなかった操作の扱いを決めます。`manual` は `default` の別名です。

| 値 | 意味 | 初心者向け注意 |
|---|---|---|
| default / manual | 必要な操作だけ確認します。`manual` はv2.1.200以降の別名です。 | 一般的な企業既定。 |
| acceptEdits | ファイル編集を自動承認し、それ以外は通常どおり判断します。 | 開発速度は上がりますが、編集範囲のdenyルールを整備します。 |
| plan | 計画・調査中心で、実変更を抑えます。 | 設計レビューや初回調査向け。 |
| auto | 分類器が操作の安全性を判定します。 | 自然言語ルールは技術的な境界ではありません。プロジェクト/ローカルからは有効化不可。 |
| dontAsk | 事前許可済み操作だけ実行し、未許可操作は質問せず拒否します。 | 無人実行・CIで予測可能性を高める用途。 |
| bypassPermissions | 権限確認を省略します。 | 危険。企業端末では通常 `disableBypassPermissionsMode` で禁止します。 |

### 6.3 `autoMode`

Auto modeの分類器へ自然言語ルールを渡します。これはLLM分類器へのガイダンスであり、ファイルACLやネットワーク境界のような強制機構ではありません。

| 設定パス | 型 | 説明 | 注意 |
|---|---|---|---|
| autoMode.environment | string または string[]（公式例・詳細は自然言語） | 分類器へ『どのような端末・環境か』を説明します。 | 秘密や認証情報は書かず、信頼境界を明確にします。 |
| autoMode.allow | string[] | 分類器が通常許可してよい操作を自然言語で記述します。 | `$defaults` を入れると組み込みルールをその位置で継承します。 |
| autoMode.soft_deny | string[] | 原則避けるが、より強い文脈で許可され得る操作を記述します。 | 管理側soft_denyをユーザーallowが上書きし得るため、強制禁止には不適切です。 |
| autoMode.hard_deny | string[] | 分類器が強く禁止する操作を記述します。 | 分類器指示でありOSレベルの強制ではありません。 |
| autoMode.classifyAllShell | boolean（既定: false） | Auto mode中、Bash/PowerShellの全コマンドを分類器へ通します。 | v2.1.193以降。既存allowルールによる分類器迂回を減らします。 |

### 6.4 `attribution`

コミット本文、PR本文、セッションURLの帰属表記を制御します。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| attribution.commit | string | Gitコミットへ追加する帰属文・trailers。空文字で非表示。 |
| attribution.pr | string | PR説明へ追加する帰属文。空文字で非表示。 |
| attribution.sessionUrl | boolean（既定: true） | Cloud/Remote ControlセッションのURLをコミットtrailersやPRへ付けるか。 |

### 6.5 `worktree`

Git worktreeを使う並列作業やサブエージェント分離の設定です。

出典: [SET-EN]

| 設定パス | 型・既定値 | 初心者向け説明 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|
| worktree.baseRef | "fresh"（既定） / "head" | `fresh` はリモート既定ブランチから、`head` は現在のローカルHEADから分岐します。 | ○ | ○ | 未pushコミットを含める必要があるかで選択。 |
| worktree.symlinkDirectories | string[] | `node_modules` 等をメイン作業ツリーから各worktreeへシンボリックリンクし、重複を減らします。 | △ | ○ | Windowsのシンボリックリンク権限・開発者モード等はClaude Code公式文書では不明。 |
| worktree.sparsePaths | string[] | 巨大monorepoで必要なディレクトリだけをsparse-checkoutします。 | ○ | ○ | ルート直下ファイルは含まれます。共有Git設定へ影響します。 |
| worktree.bgIsolation | "worktree"（既定） / "none" | バックグラウンドセッションがメインcheckoutを直接編集できるか制御します。 | ○ | ○ | `none` は分離を弱めます。`worktree` はv2.1.143以降、詳細動作の一部はv2.1.203以降。 |

### 6.6 `sandbox`

OSレベルの隔離です。**ネイティブWindowsでは全項目が非対応**です。WSL2ではLinux版として利用できますが、必要パッケージ、カーネル、AppArmor、プロキシ等の条件があります。資格情報マスキングは、秘密値を子プロセスへ渡さない／必要部分だけ渡すための高度な機能です。

出典: [SET-EN][SB]

| 設定パス | 型・既定値 | 初心者向け説明 | Windows | WSL2 | 補足・注意 |
|---|---|---|---|---|---|
| sandbox.enabled | boolean（既定: false） | シェルコマンドをサンドボックス内で実行します。 | × | △ | サンドボックスはWSL2のみ。WSL1／ネイティブWindowsでは非対応。 |
| sandbox.failIfUnavailable | boolean（既定: false） | 隔離を開始できなければ起動時にエラー終了します。 | × | △ | 混在組織へ一括配信するとネイティブWindowsが起動不能になります。 |
| sandbox.autoAllowBashIfSandboxed | boolean（既定: true） | 隔離済みのBashコマンドを自動承認します。 | × | ○ | サンドボックス外のツール権限とは別です。 |
| sandbox.excludedCommands | string[] | 指定コマンドをサンドボックス外で実行します。 | × | ○ | 例: `docker *`。例外を増やすほど隔離が弱くなります。 |
| sandbox.allowUnsandboxedCommands | boolean（既定: true） | `dangerouslyDisableSandbox` によるサンドボックス外実行を許可します。 | × | ○ | 厳格運用ではfalse。`excludedCommands` は別扱いです。 |
| sandbox.filesystem.allowWrite | string[] | サンドボックスから追加で書き込めるパス。 | × | ○ | WSL/Linuxでは `* ? [` を含むwriteパターンは無視されます。具体パスを列挙します。 |
| sandbox.filesystem.denyWrite | string[] | サンドボックスから書き込めないパス。 | × | ○ | WSL/Linuxではwriteワイルドカード無効。`Edit(...)` denyとも結合。 |
| sandbox.filesystem.denyRead | string[] | サンドボックスから読めないパス。 | × | ○ | WSL2ではreadワイルドカードを具体パスへ展開できます。 |
| sandbox.filesystem.allowRead | string[] | 広いdenyRead領域の一部を再び読めるようにします。 | × | ○ | 完全一致denyは広いallowより優先。 |
| sandbox.filesystem.allowManagedReadPathsOnly | boolean（既定: false） | allowReadについて管理設定の値だけを採用します。 | × | ○ | 管理専用。denyReadは全ソースから結合。 |
| sandbox.filesystem.disabled | boolean（既定: false） | ファイル隔離だけを無効にし、ネットワーク隔離は残します。 | × | ○ | v2.1.216以降。ホスト全ファイルへアクセス可能になるため高リスク。 |
| sandbox.credentials.files | object[] | 資格情報ファイルを `deny` または `mask` で保護します。 | × | ○ | `deny` v2.1.187+。`mask` はWSL2/Linuxでv2.1.221+かつTLS終端が必要。 |
| sandbox.credentials.files[].path | string | 保護するファイルまたはディレクトリのパス。 | × | ○ | sandbox標準の `/`、`~/`、`./` 接頭辞規則を使用。 |
| sandbox.credentials.files[].mode | "deny" / "mask" | 読取禁止、または偽値を見せて許可ホストへの通信時だけ実値へ差し替えます。 | × | ○ | 不正なmask設定は管理設定ではdenyへ劣化する場合があります。 |
| sandbox.credentials.files[].extract | regex | ファイル中のキャプチャグループ1だけをマスクします。 | × | ○ | v2.1.221+。最低1つのキャプチャグループ必須。 |
| sandbox.credentials.files[].onExtractNoMatch | "warn"（既定） / "deny" / "error" | マスク対象が見つからない場合の動作を指定します。 | × | ○ | `warn` は未マスクで読めるため、本番ではリスク評価が必要。 |
| sandbox.credentials.files[].decode | "jwt" | JWT構造を保った偽トークンへ置換します。 | × | ○ | v2.1.224+。 |
| sandbox.credentials.files[].maskClaims | string[] | JWT全体ではなく指定payload claimだけをマスクします。 | × | ○ | `decode` 必須。v2.1.224+。 |
| sandbox.credentials.files[].maskDuplicates | boolean（既定: false） | 抽出した秘密値と同じ文字列がファイルの別位置にあれば追加でマスクします。 | × | ○ | 長く高エントロピーな値に限定。短い値では誤置換リスク。 |
| sandbox.credentials.files[].injectHosts | string[] | 実資格情報を復元して送信してよいホストを限定します。 | × | ○ | 未設定ではallowedDomains内の全ホスト。最小限に限定します。 |
| sandbox.credentials.envVars | object[] | 環境変数の資格情報を `deny` または `mask` で保護します。 | × | ○ | `deny` v2.1.187+、`mask` v2.1.199+。同一変数ではdeny優先。 |
| sandbox.credentials.envVars[].name | string | 保護対象の環境変数名。 | × | ○ | 先頭は英字/underscore、以後は英数字/underscore。 |
| sandbox.credentials.envVars[].mode | "deny" / "mask" | 変数を削除するか、偽値へ置換して許可通信時だけ実値を注入します。 | × | ○ | maskはuser/managed/CLI設定からのみ有効。 |
| sandbox.credentials.envVars[].extract | regex | 接続文字列等の一部だけをキャプチャしてマスクします。 | × | ○ | v2.1.224+。`decode` と併用不可。 |
| sandbox.credentials.envVars[].onExtractNoMatch | "warn" / "deny" / "error" | 抽出失敗時に未マスク通過、変数削除、セットアップ停止を選びます。 | × | ○ | decode使用時はwarnのみ受理。 |
| sandbox.credentials.envVars[].decode | "jwt" | 環境変数全体のJWTを構造維持した偽値へ置換します。 | × | ○ | v2.1.224+。検証失敗時は警告して未マスク通過。 |
| sandbox.credentials.envVars[].maskClaims | string[] | JWTの指定claimだけをマスクします。 | × | ○ | 対象claimがなければ警告して未マスク通過。 |
| sandbox.credentials.envVars[].injectHosts | string[] | 実変数値を復元して送信してよいホスト。 | × | ○ | そのホストは `network.allowedDomains` にも必要。 |
| sandbox.credentials.allowPlaintextInject | boolean（既定: false） | HTTP平文通信でも実資格情報への差替えを許可します。 | × | ○ | 資格情報が平文送信されるため、信頼済みテスト網以外ではtrueにしないでください。 |
| sandbox.credentials.awsPairs | object[] | 非標準名のAWSアクセスキー/秘密鍵/セッショントークンを1組として関連付けます。 | × | ○ | v2.1.224+。全値mask、extract/decodeなしが条件。 |
| sandbox.credentials.awsPairs[].accessKeyIdVar | string | アクセスキーIDを保持するenvVarsエントリ名。 | × | ○ | 必須。 |
| sandbox.credentials.awsPairs[].secretAccessKeyVar | string | 秘密アクセスキーを保持するenvVarsエントリ名。 | × | ○ | 必須。 |
| sandbox.credentials.awsPairs[].sessionTokenVar | string | 一時セッショントークンのenvVarsエントリ名。 | × | ○ | 任意。 |
| sandbox.credentials.sigv4.streaming | "deny"（既定） / "passthrough" | 再署名できないaws-chunked streamingを拒否するか、そのまま転送するか。 | × | ○ | passthroughでも偽値署名のためAWS側で通常拒否されます。 |
| sandbox.credentials.sigv4.presigned | "deny" / "passthrough" | Presigned URLの扱い。 | × | ○ | v2.1.224+。 |
| sandbox.credentials.sigv4.sigv4a | "deny" / "passthrough" | SigV4A署名の扱い。 | × | ○ | v2.1.224+。 |
| sandbox.network.allowUnixSockets | string[] | macOSで許可するUnix socketパス。 | × | × | Linux/WSL2では無視されます。 |
| sandbox.network.allowAllUnixSockets | boolean（既定: false） | WSL2/LinuxでUnix socketを全面許可します。 | × | △ | WSL2ではWindows実行ファイルを起動するinterop socketも再開し、隔離を弱めます。 |
| sandbox.network.allowLocalBinding | boolean（既定: false） | localhostポートへのbindを許可します。 | × | × | macOS専用。 |
| sandbox.network.allowMachLookup | string[] | macOSのXPC/Machサービス参照を許可します。 | × | × | macOS専用。 |
| sandbox.network.allowedDomains | string[] | 外向き通信を許可するドメイン。`*.example.com` 等を使用できます。 | × | ○ | IPv6表記は対応バージョン注意。必要最小限にします。 |
| sandbox.network.deniedDomains | string[] | 外向き通信を禁止するドメイン。 | × | ○ | allowedDomainsより優先し、全設定ソースから結合。 |
| sandbox.network.strictAllowlist | boolean（既定: false） | 許可リスト外ホストをユーザー確認せず自動拒否します。 | × | ○ | v2.1.219+。サンドボックス内コマンドだけが対象で、in-process WebFetchは別。 |
| sandbox.network.allowManagedDomainsOnly | boolean（既定: false） | allowedDomainsとWebFetch許可について管理設定だけを採用します。 | × | ○ | 管理専用。許可外は自動拒否。deniedDomainsは全ソースから結合。 |
| sandbox.network.httpProxyPort | integer | 管理者が用意したHTTPプロキシのポートを使います。 | × | ○ | 未設定ならClaude Codeがプロキシを起動。 |
| sandbox.network.socksProxyPort | integer | 管理者が用意したSOCKS5プロキシのポートを使います。 | × | ○ | 未設定ならClaude Code側の仕組みを使用。 |
| sandbox.network.tlsTerminate | object（{} またはCAパス） | サンドボックスプロキシでTLSを終端し、HTTPS内容の確認・資格情報差替えを可能にします。 | × | △ | 実験的。v2.1.199+。端末にCA信頼を与える設計と秘密鍵保護が必要。 |
| sandbox.network.tlsTerminate.caCertPath | string | 独自CA証明書のパス。 | × | △ | `caKeyPath` と組で使用。 |
| sandbox.network.tlsTerminate.caKeyPath | string | 独自CA秘密鍵のパス。 | × | △ | 最重要秘密。ACL、配布、ローテーションを厳格化。 |
| sandbox.enableWeakerNestedSandbox | boolean（既定: false） | 非特権Docker等の入れ子環境で弱い方式のサンドボックスを許可します。 | × | △ | Linux/WSL2のみ。防御強度が下がります。 |
| sandbox.enableWeakerNetworkIsolation | boolean（既定: false） | macOSでTLS信頼サービスへの経路を開きます。 | × | × | macOS専用。 |
| sandbox.allowAppleEvents | boolean（既定: false） | macOSでApple Eventsを許可します。 | × | × | macOS専用。隔離外アプリ起動が可能になり大幅に弱化。 |
| sandbox.ripgrep.command | string | サンドボックスが使用する `rg` 実行ファイルを指定します。 | × | ○ | user/managed/CLI設定からのみ。 |
| sandbox.ripgrep.args | string[] | カスタムripgrepへ渡す固定引数。 | × | ○ | 任意。 |
| sandbox.bwrapPath | string（絶対パス） | bubblewrapの場所を明示します。 | × | ○ | 管理専用、Linux/WSL2のみ。 |
| sandbox.socatPath | string（絶対パス） | ネットワークプロキシ用socatの場所を明示します。 | × | ○ | 管理専用、Linux/WSL2のみ。 |

### 6.7 `fileSuggestion`

入力時の `@` ファイル候補を外部コマンドで生成します。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| fileSuggestion.type | "command" | 外部コマンド方式を指定。 |
| fileSuggestion.command | string | 検索語JSONをstdinで受け、候補パスを改行区切りでstdoutへ返すコマンド。 |

### 6.8 `footerLinksRegexes`

Claudeの出力中の文字列を、ターミナルでクリック可能なリンクへ変換します。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| footerLinksRegexes[].type | "regex" | 正規表現リンク方式。 |
| footerLinksRegexes[].pattern | string（regex） | ツール結果・Claude回答へ照合する正規表現。名前付きキャプチャを使用。 |
| footerLinksRegexes[].url | string（URL template） | `{name}` を名前付きキャプチャで置換。URL originはテンプレートの固定originから変えられません。 |
| footerLinksRegexes[].label | string（任意） | バッジ表示名。省略時は一致文字列。28表示列に切り詰め。 |

### 6.9 `statusLine`

メイン画面のカスタムステータス行です。コマンドはOSごとに用意する必要があります。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| statusLine.type | "command" | 外部コマンドを実行する方式。 |
| statusLine.command | string | stdinのセッションJSONを読み、表示文字列をstdoutへ出すコマンド。 |
| statusLine.padding | integer（既定: 0） | 左側の追加余白。 |
| statusLine.refreshInterval | integer秒（最小: 1） | イベント更新に加え、一定間隔で再実行。時計等に使用。 |
| statusLine.hideVimModeIndicator | boolean | 組み込み `-- INSERT --` 表示を隠す。スクリプト側で表示する場合に使用。 |

### 6.10 `subagentStatusLine`

サブエージェント表示用のステータス行です。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| subagentStatusLine.type | "command" | 外部コマンド方式。 |
| subagentStatusLine.command | string | タスク一覧JSONをstdinで読み、`{"id":"...","content":"..."}` を1行ずつ返します。 |

### 6.11 `spellcheck`

v2.1.235以降の入力スペルチェックです。外部辞書ツールをPATHへ導入します。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| spellcheck.enabled | boolean | 入力中スペルチェックの有効化。 |
| spellcheck.checker | "auto" / "aspell" / "hunspell" / "ispell" | 使用する外部チェッカー。autoはPATH上を順番に検出。 |
| spellcheck.language | string | チェッカーの辞書名。例: `en_GB`。 |
| spellcheck.color | string | 下線色。名前、hex、rgb、ANSI指定を使用。 |

### 6.12 `voice`

音声入力の有効化、操作方式、自動送信を設定します。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| voice.enabled | boolean | 音声入力を有効化。 |
| voice.mode | "hold" / "tap" | 押している間録音、またはタップで開始/停止。 |
| voice.autoSubmit | boolean | holdモードでキーを離したとき自動送信。 |

### 6.13 `sshConfigs`

Claude Desktopに表示する管理済みSSH接続先です。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| sshConfigs[].id | string（必須） | 接続設定を一意に識別するID。 |
| sshConfigs[].name | string（必須） | Desktop UIに表示する名前。 |
| sshConfigs[].sshHost | string（必須） | `user@host` 等のSSH接続先。 |
| sshConfigs[].sshPort | integer（任意） | SSHポート。 |
| sshConfigs[].sshIdentityFile | string（任意） | 秘密鍵ファイル。 |
| sshConfigs[].startDirectory | string（任意） | 接続後に開始するリモートディレクトリ。 |

### 6.14 `spinnerVerbs` / `spinnerTipsOverride`

処理中表示の文言を組織向けに追加または置き換えます。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| spinnerTipsOverride.excludeDefault | boolean | trueなら組み込みヒントを除外。 |
| spinnerTipsOverride.tips | string[] | 追加・置換する社内ヒント。 |
| spinnerVerbs.mode | "replace" / "append" | 組み込み動詞を置換または追加。 |
| spinnerVerbs.verbs | string[] | 表示する動詞。 |

### 6.15 `policyHelper`

端末ごとに管理ポリシーを動的生成する高度な仕組みです。**サーバー管理画面では無視されます。** MDMまたはシステム `managed-settings.json` からだけ有効です。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| policyHelper.path | string（絶対パス） | 管理設定JSONを生成する管理者配布実行ファイル。 |
| policyHelper.timeoutMs | integer | ヘルパーを待つ最大時間。既定値は公式ページの該当節を確認してください。 |
| policyHelper.refreshIntervalMs | 0 または 60000以上 | 0は起動時のみ、正数は再評価間隔。 |

### 6.16 `remote`

クラウド環境関連の入れ子設定です。

| 設定パス／値 | 型 | 初心者向け説明・注意 |
|---|---|---|
| remote.defaultEnvironmentId | string（`env_...` または `ccpool_...`） | CLIから作るクラウドセッションの既定環境。自己ホストIDは管理/user/CLI設定だけで有効。 |

### 6.17 `skillOverrides` の値

スキル名ごとに有効／無効／ユーザー選択可を指定します。

| 値／項目 | 意味 |
|---|---|
| on | 名前と説明を通常どおりモデルへ見せ、利用可能。 |
| name-only | 名前だけモデルへ見せ、説明文のコンテキスト消費を減らす。 |
| user-invocable-only | モデルの自動選択対象から外し、ユーザーが明示実行するときだけ使用。 |
| off | 無効化。 |


### 6.18 `env` に入れられる環境変数

`env` は固定スキーマのオブジェクトではなく、**環境変数名 → 文字列値**のマップです。Claude Code固有変数だけでなく、Hook、MCP、Bash／PowerShell、社内ツールが読む独自変数も渡せるため、入れ子キーの有限な「全一覧」は存在しません。本資料の138件は固定のトップレベル設定キーの全数です。Claude Codeが公式に読む環境変数の完全な最新一覧は `[ENV]` を参照してください。

```json
{
  "env": {
    "API_TIMEOUT_MS": "1200000",
    "CLAUDE_CODE_USE_POWERSHELL_TOOL": "1",
    "DISABLE_AUTOUPDATER": "1"
  }
}
```

**重要な規則**

- `env` の値はJSON文字列です。`true` ではなく、多くの場合は `"1"`、`"true"`、`"0"` 等を使います。各変数で値の解釈が異なります。
- 同じ変数がシェルと `settings.json` の `env` にある場合、`env` の値が適用されます。
- 専用設定キーと環境変数が両方ある機能では、通常は環境変数が優先します。例外やCLI／対話コマンドとの順序は各変数の公式説明を確認してください。
- 実行中に値を追加・変更すると多くは再適用されますが、起動時だけ読む機能は再起動が必要です。削除した変数は実行中にはunsetされず、次回起動で反映されます。
- サーバー管理設定のキャッシュでは、認証、プロキシ、TLS、APIルーティング、設定ディレクトリ等の高リスク変数が、当該セッションでサーバー確認されるまで保留される場合があります。
- `CLAUDE_CODE_REMOTE`、`CLAUDE_CODE_ACCOUNT_UUID`、メッセージングsocket/token等、ホストが所有する識別変数は `env` から設定しても無視されます。`CLAUDE_CODE_PROJECT_DIR_NAME` も起動環境専用で、`env` ブロックからは読まれません。
- 秘密値を組織管理画面のJSONへ平文保存しないでください。資格情報ヘルパー、OS資格情報ストア、短期資格情報、秘密管理製品を優先します。

#### 企業導入・Windows／WSL2で特に影響が大きい環境変数

| 環境変数 | 用途・初心者向け注意 | Windows | WSL2 |
|---|---|---|---|
| `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` | モデルAPI認証。サブスクリプションよりAPIキーが使われる場合があります。平文の管理JSONへ秘密を直接置く運用は避け、資格情報管理を使います。 | ○ | ○ |
| `ANTHROPIC_BASE_URL` | API送信先をプロキシ／LLMゲートウェイへ変更します。非AnthropicホストではRemote Controlやサーバー管理設定などに制約が生じます。 | ○ | ○ |
| `ANTHROPIC_MODEL` | `model` 設定より優先して主モデルを指定します。ただし `--model` や `/model` との優先関係も確認します。 | ○ | ○ |
| `CLAUDE_CODE_USE_BEDROCK` | Amazon Bedrockをモデルプロバイダーとして使います。サーバー管理設定のAnthropic配信は通常利用できません。 | ○ | ○ |
| `CLAUDE_CODE_USE_VERTEX` | Google Cloud Agent Platformを使います。空文字を設定すると、シェルに残る古い値をプロバイダー選択上は未設定扱いにできます。 | ○ | ○ |
| `CLAUDE_CODE_USE_FOUNDRY` | Microsoft Foundryを使います。認証、リージョン、エンドポイント変数も別途必要になる場合があります。 | ○ | ○ |
| `CLAUDE_CODE_USE_ANTHROPIC_AWS` | Claude Platform on AWSを使います。Bedrockとは別のプロバイダー選択です。 | ○ | ○ |
| `CLAUDE_CODE_GIT_BASH_PATH` | Git BashがPATHにないWindowsで、`bash.exe` の場所を指定します。Windows専用です。 | ○ | × |
| `CLAUDE_CODE_USE_POWERSHELL_TOOL` | PowerShellツールを制御します。WindowsはGit Bash有無で既定が異なり、WSL2で `1` にする場合は `pwsh` がPATHに必要です。 | ○ | △ |
| `CLAUDE_CODE_TOOL_MEMORY_LIMIT` | Bash／PowerShellツールのメモリを `4G` 等で制限します。v2.1.233以降、Linux／WSL専用です。 | × | ○ |
| `CLAUDE_CODE_PROCESS_WRAPPER` | `processWrapper` と同じ企業ランチャーを環境変数で指定し、こちらが優先します。Windowsでは無視されます。 | × | ○ |
| `CLAUDE_CONFIG_DIR` | 設定、履歴、プラグイン、Windows／Linux資格情報の保存ディレクトリを変更します。WindowsとWSL2で別パスを指定します。 | ○ | ○ |
| `API_TIMEOUT_MS` | API要求のタイムアウトをミリ秒で調整します。長くしすぎると障害検知が遅れます。 | ○ | ○ |
| `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS` | シェルコマンドの既定タイムアウトと、モデルが指定できる最大タイムアウトを調整します。 | △ | ○ |
| `HTTP_PROXY` / `HTTPS_PROXY` | 外部通信に使うHTTP／HTTPSプロキシを指定します。サーバー管理設定取得、モデルAPI、MCP、Webアクセスを実機で確認します。 | ○ | ○ |
| `CLAUDE_CODE_CERT_STORE` | TLSで使うCA証明書源を `bundled`、`system` の組み合わせで指定します。企業CA利用時は公式TLS資料も確認します。 | ○ | ○ |
| `DISABLE_AUTOUPDATER` | 自動バックグラウンド更新を止めます。手動 `claude update` は残ります。 | ○ | ○ |
| `DISABLE_UPDATES` | 自動更新だけでなく `claude update` と `claude install` も止めます。社内配布だけに限定するときの強い設定です。 | ○ | ○ |
| `DISABLE_TELEMETRY` / `DO_NOT_TRACK` | テレメトリを無効化します。値の解釈が異なり、`DISABLE_TELEMETRY=0` でも無効化になる点に注意します。機能フラグ取得も止まり、Remote Control等が使えなくなります。 | ○ | ○ |
| `CLAUDE_CODE_ENABLE_TELEMETRY` | OpenTelemetryのメトリクス／ログ収集を有効にします。Exporter関連変数とセットで設計します。 | ○ | ○ |
| `MAX_THINKING_TOKENS` | 拡張思考の固定トークン予算。Anthropic APIでは `0` で無効化できますが、モデル／プロバイダー例外があります。 | ○ | ○ |
| `CLAUDE_CODE_EFFORT_LEVEL` | 対応モデルのeffortを設定し、`effortLevel` と `/effort` より優先します。値はモデル対応状況を確認します。 | ○ | ○ |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | 自動compactを開始するコンテキスト量を指定し、設定キーとCLIより優先します。100000～1000000の整数です。 | ○ | ○ |
| `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION` | 入力候補を有効／無効化し、`promptSuggestionEnabled` より優先します。 | ○ | ○ |
| `CLAUDE_CODE_ENABLE_AWAY_SUMMARY` | 離席後のセッション要約を強制的に有効／無効化し、`awaySummaryEnabled` より優先します。 | ○ | ○ |
| `CLAUDE_CODE_USER_DIALOG_TIMEOUT_MS` | Remote Control／SDKダイアログと保留メッセージ承認の期限をミリ秒で指定し、`dialogExpiry` より優先します。 | ○ | ○ |
| `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` | `apiKeyHelper` が返す資格情報の再取得間隔をミリ秒で指定します。 | ○ | ○ |
| `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` | Stop／SubagentStop Hookが終了を連続ブロックできる回数。既定8、`0` は上限なしです。 | ○ | ○ |
| `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` | Bash、PowerShell、Hook、stdio MCPの子プロセスからAnthropic／クラウド資格情報を除去します。Linux／WSLではPID名前空間も使います。 | ○ | ○（追加隔離あり） |
| `CLAUDE_CODE_SKIP_PROMPT_HISTORY` | プロンプト履歴とセッショントランスクリプトのディスク保存を止めます。再開／履歴機能も使えなくなります。 | ○ | ○ |
| `CLAUDE_CODE_TMPDIR` | Claude Codeの一時ファイル基点を変更します。WindowsとWSL2でパス表記を分けます。 | ○ | ○ |

上表は企業導入上の高影響項目を抜粋したものです。Claude Codeが公式に読む環境変数の**完全な一覧**と各変数の厳密な値・バージョン条件は `[ENV]` が正本です。

出典: [ENV][SET-EN][SM][SETUP]
### 6.19 `hooks` の構造

`hooks` はイベントごとにmatcher groupを置き、その中へ1つ以上のハンドラーを置きます。WindowsとWSL2では実行シェル、パス、実行ファイルが異なります。管理Hookは強力ですが、利用者が端末自体を管理できる環境では、Hookだけを改ざん不能な監査境界とみなさないでください。

| 設定パス | 型 | 説明 |
|---|---|---|
| hooks.<Event>[] | object[] | イベントごとのmatcher group配列。 |
| hooks.<Event>[].matcher | string（任意） | `*`、空、未指定は全一致。単純な名前列挙または正規表現として評価されます。 |
| hooks.<Event>[].hooks | handler[]（必須） | 一致時に並列実行する1つ以上のハンドラー。 |
| handler.type | "command" / "http" / "mcp_tool" / "prompt" / "agent" | 実行方式。agentは実験的。イベントにより利用可能な型が異なります。 |
| handler.if | permission rule（任意） | ツールイベントでさらに条件を絞ります。対象外イベントで指定すると実行されません。1フィールドに1ルールだけです。 |
| handler.timeout | number（秒） | タイムアウト。既定はcommand/http/mcp_tool 600秒、prompt 30秒、agent 60秒。イベント別短縮あり。 |
| handler.statusMessage | string（任意） | Hook実行中に表示するスピナーメッセージ。 |
| handler.once | boolean | settings.jsonでは無視されます。スキルfrontmatterでのみ1セッション1回として有効。 |
| command.command | string（必須） | シェル形式ではコマンド文字列、exec形式では実行ファイル名。 |
| command.args | string[]（任意） | 指定するとシェルを介さないexec形式になり、各要素が1引数になります。 |
| command.async | boolean（任意） | バックグラウンドで実行し、会話を待たせません。 |
| command.asyncRewake | boolean（任意） | 非同期実行し、終了コード2ならアイドル中でもClaudeを起こして失敗情報を渡します。`async` を含意。 |
| command.shell | "bash" / "powershell"（任意） | シェル形式で使うシェル。`args` があるexec形式では無視。WindowsはGit Bash不在時PowerShellが既定。 |
| http.url | string（必須） | イベントJSONをPOSTするURL。`allowedHttpHookUrls` の制約対象。 |
| http.headers | object（任意） | HTTPヘッダー。環境変数展開は許可リストで制限します。 |
| http.allowedEnvVars | string[]（任意） | このHookでヘッダー展開に使ってよい環境変数。全体設定との積集合。 |
| mcp_tool.server | string（必須） | 既に接続済みのMCPサーバー名。 |
| mcp_tool.tool | string（必須） | 呼び出すMCPツール名。 |
| mcp_tool.input | object（任意） | MCPツールへ渡す入力。Hook入力のplaceholderを使用できます。 |
| prompt.prompt | string（必須） | 単発のClaude判定へ渡すプロンプト。 |
| prompt.model | string（任意） | 判定に使うモデル。未指定時の既定は公式Hookページを参照。 |
| agent.prompt | string（必須） | 検証用サブエージェントへの指示。 |
| agent.model | string（任意） | 検証用サブエージェントのモデル。 |

出典: [HOOK][HOOK-GUIDE]

#### Hookイベント全31種

| イベント | 発火タイミング／用途 |
|---|---|
| SessionStart | セッション開始または再開時。環境変数の永続化や初期コンテキスト追加に使います。 |
| Setup | `--init-only`、または `-p` と `--init` / `--maintenance` で起動した準備処理時。CIの一回限り準備向け。 |
| InstructionsLoaded | `CLAUDE.md` または `.claude/rules/*.md` がコンテキストへ読み込まれたとき。 |
| UserPromptSubmit | ユーザーがプロンプトを送信した直後、Claudeが処理する前。 |
| UserPromptExpansion | ユーザー入力コマンドがプロンプトへ展開され、Claudeへ渡る前。展開を止められます。 |
| MessageDisplay | Claudeのメッセージ文字列が画面へ表示されている間。 |
| PreToolUse | ツール呼び出しの実行前。拒否・変更・延期などの判断に使える主要ゲート。 |
| PermissionRequest | ツールが権限判断を必要としたとき。 |
| PermissionDenied | Auto modeがツールを拒否したとき。条件により再試行を促せます。 |
| PostToolUse | ツール呼び出し成功後。整形、監査、テスト等に使用。 |
| PostToolUseFailure | ツール呼び出し失敗後。エラー収集や追加説明に使用。 |
| PostToolBatch | 並列ツール呼び出し1バッチが全て完了し、次のモデル呼び出しへ進む前。 |
| Notification | Claude Codeが通知を送るとき。 |
| SubagentStart | サブエージェント生成時。 |
| SubagentStop | サブエージェント終了時。 |
| TaskCreated | `TaskCreate` でタスクを作成しようとするとき。 |
| TaskCompleted | タスクを完了扱いにしようとするとき。 |
| Stop | Claudeが通常どおり回答を終えたとき。 |
| StopFailure | APIエラーでターンが終了したとき。 |
| TeammateIdle | Agent teamのメンバーがアイドル状態へ入る直前。 |
| ConfigChange | セッション中に設定ファイルが変更されたとき。 |
| CwdChanged | `cd` 等で作業ディレクトリが変わったとき。 |
| DirectoryAdded | `/add-dir` またはSDKで作業ディレクトリが追加されたとき。 |
| FileChanged | 監視対象ファイルがディスク上で変更されたとき。matcherでファイル名を指定。 |
| WorktreeCreate | `--worktree`、worktree分離、バックグラウンドセッションでworktreeを作成するとき。既定Git動作を置換できます。 |
| WorktreeRemove | 終了・サブエージェント完了・バックグラウンド削除等でworktreeを削除するとき。 |
| PreCompact | コンテキストをcompactする直前。 |
| PostCompact | compact完了後。 |
| Elicitation | MCPサーバーがツール実行中にユーザー入力を要求したとき。 |
| ElicitationResult | ユーザー回答後、MCPサーバーへ返す前。 |
| SessionEnd | セッション終了時。短い終了予算があるため軽量処理にします。 |

**Windows固有のHook注意点**

- シェル形式（`args` なし）は、Windowsでは既定でGit Bash、Git BashがなければPowerShellを使います。
- PowerShellを確実に使う場合は `shell: "powershell"` またはPowerShell実行ファイルを明示します。
- `args` を置くexec形式はシェルを介しません。`.cmd` / `.bat` やnpmのshimではなく、実体のある実行ファイルを指定します。
- Hook入力のWindowsパスは `C:\\...` のようなバックスラッシュです。Git Bash内で比較する前に `/` へ正規化してください。
- シェルコマンドを検査するHookは、WindowsのPowerShellツールも対象にするためmatcherを `Bash|PowerShell` とすることを検討します。

### 6.20 MCPサーバー許可／拒否リストの1エントリ

`allowedMcpServers` と `deniedMcpServers` の各要素は、次のいずれか**1種類だけ**を指定します。拒否リストが優先です。`allowedMcpServers` 未設定は制限なし、空配列 `[]` は全面禁止です。

| 指定方法 | 型 | 用途 | 注意 |
|---|---|---|---|
| allowedMcpServers[] / deniedMcpServers[].serverUrl | string | HTTP/SSE等のサーバーURLを完全一致または対応ワイルドカードで照合します。 | URL方式のMCPに使用。 |
| allowedMcpServers[] / deniedMcpServers[].serverCommand | string[] | stdioサーバーの実行ファイルと引数を配列で厳密に照合します。 | WindowsとWSLで実行パスが異なります。 |
| allowedMcpServers[] / deniedMcpServers[].serverName | string | 設定上のサーバー名で照合します。 | ユーザーが付ける名前なので、単独では強いセキュリティ制御にしないでください。 |

Windowsの環境変数展開は `${USERPROFILE}` を使い、WSL2では `${HOME}` を使うのが基本です。`serverName` は名前の一致だけなので、改ざん不能なサーバー識別子ではありません。厳格に管理する場合は `allowManagedMcpServersOnly: true` を併用します。[MCP]

### 6.21 `allowedChannelPlugins`

| 設定パス | 型 | 説明 |
|---|---|---|
| allowedChannelPlugins[].marketplace | string | 許可するプラグインのマーケットプレイス名。 |
| allowedChannelPlugins[].plugin | string | 許可するチャネルプラグイン名。 |

`channelsEnabled: true` が前提です。未設定はAnthropicの既定許可リスト、空配列はすべて禁止、配列を指定するとそのリストへ置き換わります。[SET-EN]

### 6.22 プラグイン設定

| 設定パス | 型 | 説明 |
|---|---|---|
| enabledPlugins.<plugin@marketplace> | boolean | プラグインを有効/無効化。管理trueはユーザーが無効化不可。 |
| pluginConfigs.<plugin@marketplace>.options | object | プラグインの非機密オプション。秘密値は保存しない。 |
| extraKnownMarketplaces.<name>.source | object | マーケットプレイス取得元。下表のsource種別を使用。 |
| extraKnownMarketplaces.<name>.autoUpdate | boolean（任意） | 起動後にそのマーケットプレイスと導入済みプラグインをバックグラウンド更新。非公式marketplaceの既定はfalse。 |
| extraKnownMarketplaces.<name>.source.skipLfs | boolean（任意） | github/git取得時にGit LFSオブジェクトをダウンロードしない。v2.1.153以降。 |

#### `extraKnownMarketplaces.<name>.source` のsource種別

| source値 | 必須／任意フィールド | 用途・注意 |
|---|---|---|
| github | `repo` 必須、`ref` / `path` / `skipLfs` 任意 | GitHubリポジトリ。`extraKnownMarketplaces` では単一repoのみで、`owner/*` は不可。 |
| git | `url` 必須、`ref` / `path` / `skipLfs` 任意 | GitHub以外を含むGit URL。端末のgit credential helper/SSHキーを使用。 |
| url | `url` 必須、`headers` 任意 | marketplace.jsonの直接URL。相対パスのプラグイン本体は配れません。 |
| file | `path` 必須 | ローカルのmarketplace.json絶対パス。Windows/WSLで別パス。 |
| directory | `path` 必須 | ローカルディレクトリ。公式文書では開発用途。 |
| hostPattern | `hostPattern` 必須 | マーケットプレイスホストを正規表現で照合。 |
| settings | `name` と `plugins` 必須 | settings.json内に小規模なマーケットプレイスをインライン宣言。各pluginは外部sourceを参照。 |

#### `strictKnownMarketplaces` / `blockedMarketplaces` のsource matcher

| source値 | 照合フィールド | 用途・注意 |
|---|---|---|
| github | `repo`、任意で `ref` / `path` | 完全一致。`owner/*` はstrict/blockedだけでv2.1.223以降。 |
| git | `url`、任意で `ref` / `path` | Git URLを照合。 |
| url | `url`、任意で `headers` | marketplace.json URLを照合。 |
| npm | `package` | npm packageを照合。 |
| file | `path` | marketplace.jsonの絶対パスを照合。 |
| directory | `path` | marketplaceディレクトリを照合。 |
| hostPattern | `hostPattern` regex | ネットワークsourceのホストを正規表現で照合。 |
| pathPattern | `pathPattern` regex | file/directory sourceのパスを正規表現で照合。 |

`strictKnownMarketplaces: []` は、Anthropic公式マーケットプレイスを含むすべての追加元を禁止します。`github` の `owner/*` ワイルドカードはv2.1.223以降です。`additionalMarketplaces` と `allowedMarketplaces` の別名はv2.1.232以降です。[SET-EN]

### 6.23 `strictPluginOnlyCustomization` の値

| 値 | 意味 |
|---|---|
| true | skills、agents、hooks、mcpの4面すべてをプラグイン/管理設定だけに限定。 |
| ["skills", "hooks"] 等 | 配列に指定した面だけを限定。選べる値は `skills`、`agents`、`hooks`、`mcp`。 |

---

## 7. 別名、廃止済み、`settings.json` ではない項目

### 7.1 現行の別名

| 別名 | 正規キー | 注意 |
|---|---|---|
| `additionalMarketplaces` | `extraKnownMarketplaces` | v2.1.232以降。旧版混在フリートでは正規キーを使用。両方あれば正規キーが優先。 |
| `allowedMarketplaces` | `strictKnownMarketplaces` | v2.1.232以降。管理設定専用。正規キーを推奨。 |
| `voiceEnabled` | `voice.enabled` 相当 | 互換用の旧形式。新規設計では `voice` オブジェクトを優先。 |
| `manual` | `permissions.defaultMode: "default"` の別名 | 意味は通常の確認付きモード。 |

### 7.2 廃止済み／非推奨

| 項目 | 状態 | 代替 |
|---|---|---|
| `includeCoAuthoredBy` | 非推奨 | `attribution`。両方ある場合は `attribution` が優先。 |
| `ignorePatterns` | 非推奨 | `permissions.deny` の `Read(...)` ルール。 |
| `teammateDefaultModel` | v2.1.234で削除 | `model`、`agent`、サブエージェント定義等を用途に応じて使用。 |

### 7.3 `settings.json` に書いても読まれない／別ファイルの項目

| 項目 | 正しい保存先／状態 |
|---|---|
| `ultracode` | 公式設定表に関連記述はあるものの、明示的に `settings.json` からは読まれません。 |
| `autoConnectIde` | `~/.claude.json` のグローバル状態。 |
| `autoInstallIdeExtension` | `~/.claude.json` のグローバル状態。 |
| `diffTool` | `~/.claude.json` のグローバル状態。 |
| `externalEditorContext` | `~/.claude.json` のグローバル状態。 |
| `permissionExplainerEnabled` | `~/.claude.json` のグローバル状態。 |

`~/.claude.json` はOAuthセッション、MCP状態、プロジェクト信頼情報、キャッシュ等も含むため、組織管理画面の `settings.json` と同じものとして配布しないでください。[SET-EN]

---

## 8. 設定例

以下は構造を説明するための例です。組織UUID、許可ドメイン、パス、認証方式、モデル、MCP、Hookスクリプトを実環境に合わせてレビューしてください。

### 8.1 Windows／WSL2共通のサーバー管理ベースライン例

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "forceLoginMethod": "claudeai",
  "forceLoginOrgUUID": [
    "REPLACE-WITH-YOUR-ORG-UUID"
  ],
  "allowManagedPermissionRulesOnly": true,
  "permissions": {
    "defaultMode": "default",
    "disableBypassPermissionsMode": "disable",
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)"
    ]
  },
  "disableAutoMode": "disable",
  "allowManagedHooksOnly": true,
  "allowManagedMcpServersOnly": true,
  "allowedMcpServers": [],
  "disableSideloadFlags": true,
  "strictKnownMarketplaces": [],
  "disableCommandPluginSources": true,
  "disableRemoteControl": true,
  "companyAnnouncements": [
    "Claude Code is centrally managed by your organization."
  ],
  "forceRemoteSettingsRefresh": true
}
```

**この例の意味**

- Claude.ai組織ログインを要求し、指定組織へ限定します。
- 権限ルールを管理設定だけに限定し、`.env` と `secrets` の読み取りを拒否します。
- Auto modeを利用者が有効化できないようにします。
- Hook、MCP、プラグインマーケットプレイス、Remote Controlを厳しく制限します。
- 最新のサーバー設定を確認できない起動を拒否します。

**そのまま本番投入しない理由**

- `forceLoginOrgUUID` の置換が必須です。
- `allowedMcpServers: []` はMCPを全面禁止します。
- `strictKnownMarketplaces: []` はAnthropic公式を含むマーケットプレイス追加を全面禁止します。
- `forceRemoteSettingsRefresh: true` は管理サーバー到達不能時に起動できなくなるため、可用性設計が必要です。
- `$schema` はエディター補助であり、公開スキーマが最新CLIより遅れる場合があります。

### 8.2 ネイティブWindows向け端末管理例

> この例は、サーバー管理ベースラインへの単純な『追加パッチ』ではありません。OS別の完全な端末ポリシーとして設計する場合の抜粋です。

```json
{
  "defaultShell": "powershell",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe",
            "args": [
              "-NoProfile",
              "-ExecutionPolicy",
              "Bypass",
              "-File",
              "C:\\Program Files\\Company\\ClaudeHooks\\audit.ps1"
            ]
          }
        ]
      }
    ]
  }
}
```

- `defaultShell` は対話的な `!` コマンドをPowerShellへ寄せます。
- Hookはexec形式で `powershell.exe` と引数を分離し、クォート事故を減らしています。
- ネイティブWindowsでは `sandbox` と `processWrapper` を入れません。
- 管理コンソールから一律配布する場合、WSL2でも同じWindowsパスは存在しないため、この例は適しません。

### 8.3 WSL2向けサンドボックス例

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": false,
    "filesystem": {
      "denyRead": [
        "~/.ssh",
        "~/.aws",
        "~/.config/gcloud"
      ]
    },
    "credentials": {
      "envVars": [
        {
          "name": "AWS_SECRET_ACCESS_KEY",
          "mode": "deny"
        },
        {
          "name": "GITHUB_TOKEN",
          "mode": "deny"
        }
      ]
    },
    "network": {
      "allowedDomains": [
        "api.anthropic.com",
        "github.com",
        "api.github.com",
        "registry.npmjs.org"
      ],
      "strictAllowlist": true,
      "allowManagedDomainsOnly": true
    }
  }
}
```

- 隔離が利用できなければ起動を失敗させます。
- SSH、AWS、gcloudの設定ディレクトリを読み取り拒否します。
- 代表的な秘密環境変数を子プロセスへ渡しません。
- 外向き通信先を明示し、管理者許可リストだけに限定します。

**注意:** 許可ドメインは例です。パッケージマネージャー、Git、社内レジストリ、証明書失効確認、プロキシ等に必要な接続先を実測してください。WSL2サンドボックスから `powershell.exe`、`cmd.exe`、`/mnt/c` 上のWindows実行ファイルを使う場合、Unix socket許可または除外が必要になり、隔離が弱くなります。[SB]

---

## 9. Windows／WSL2混在企業での推奨設計パターン

### パターンA: 管理画面にはOS共通の最小公倍数だけを置く

WindowsとWSL2の両方で同じ意味になる認証、モデル制限、権限ルール、MCP／プラグイン制限、Remote Control制限、告知などだけをサーバー管理設定へ置きます。`sandbox.enabled`、`processWrapper`、OS固有Hook、OS固有パスは置きません。

**向くケース:** 全社共通のガードレールを優先し、OS固有の強制機能を必須としない場合。  
**弱点:** サーバー設定が非空だと、通常は端末管理側のOS固有設定を追加マージできません。

### パターンB: 管理画面を空にし、端末管理でOS別の完全ポリシーを配る

WindowsはHKLMまたは `C:\Program Files\ClaudeCode\managed-settings.json`、WSL2は `/etc/claude-code/managed-settings.json` へ、それぞれ**共通項目も含む完全な設定**を配布します。

**向くケース:** WSL2でサンドボックスを必須化し、WindowsでPowerShell Hook等を使うなど、OS差が大きい場合。  
**弱点:** Claude Code on the webやAnthropicホストのクラウドセッションには端末ポリシーが届きません。そこも制御する場合は、別途サーバー管理を検討します。

### パターンC: 運用上可能なら、ポリシー単位で組織を分ける

管理画面の設定は組織内一律でグループ割り当てがないため、強く異なるクラウドポリシーが必要なら、契約・ID・運用上許される範囲で組織分離を検討します。

### 避けるべき設計

- 混在組織の一律設定で `sandbox.enabled: true` と `sandbox.failIfUnavailable: true` を同時に配る。
- サーバー管理JSONへ共通設定を置き、端末側にOS固有設定だけ置けば自動で合成されると考える。
- Windows用絶対パスをWSL2へ、LinuxパスをネイティブWindowsへ一律配布する。
- Hookや `autoMode` だけを改ざん不能なセキュリティ境界とみなす。
- `allowManagedMcpServersOnly` なしで、`allowedMcpServers` だけを書いて完全統制できたと判断する。
- `strictKnownMarketplaces: []` や `allowedMcpServers: []` の全面禁止効果を理解せず投入する。

---

## 10. 本番導入チェックリスト

- [ ] 対象Claude Codeの最低バージョンを決め、`requiredMinimumVersion` / `minimumVersion` を検討した。
- [ ] 日本語版だけでなく現行英語版の新項目・変更点を確認した。
- [ ] 管理画面の設定が全ユーザー一律であることを関係者が理解した。
- [ ] サーバー管理と端末管理が通常はマージされないことを設計書へ明記した。
- [ ] Bedrock、Vertex、Foundry、プロキシ、カスタムBase URL利用時にサーバー管理設定を取得できるか実機確認した。
- [ ] `/status` で期待する管理ソースを確認した。
- [ ] `claude doctor` / `/doctor` で無効項目がないことを確認した。
- [ ] `/permissions` でdeny/ask/allowの実効ルールを確認した。
- [ ] Windowsでは `Bash|PowerShell`、バックスラッシュ、`.cmd/.bat`、Git Bash有無を含めHookを試験した。
- [ ] WSL2ではbubblewrap、socat、AppArmor、プロキシ、CA証明書、DNS、Windows interopを試験した。
- [ ] `forceRemoteSettingsRefresh` の可用性影響を障害試験した。
- [ ] MCPとマーケットプレイスの空配列が全面禁止になることを承認者が確認した。
- [ ] 秘密値を平文の `settings.json` や `pluginConfigs` へ保存していない。
- [ ] EDR、DLP、プロキシ、秘密管理、ファイルACL、ソフトウェア配布と整合させた。
- [ ] 変更管理、ロールバック、キャッシュ残存、利用者への承認ダイアログ案内を準備した。

---

## 11. 公式参照資料

本資料では以下の公式サイトだけを参照しました。

- [SET-JA] Claude Code 設定（日本語）: https://code.claude.com/docs/ja/settings
- [SET-EN] Claude Code settings（英語・現行仕様）: https://code.claude.com/docs/en/settings
- [SM] Configure server-managed settings: https://code.claude.com/docs/en/server-managed-settings
- [SETUP] Claude Code setup: https://code.claude.com/docs/en/setup
- [HOOK] Hooks reference: https://code.claude.com/docs/en/hooks
- [HOOK-GUIDE] Automate actions with hooks: https://code.claude.com/docs/en/hooks-guide
- [SB] Sandboxing: https://code.claude.com/docs/en/sandboxing
- [MCP] Managed MCP configuration: https://code.claude.com/docs/en/managed-mcp
- [PERM] Permissions: https://code.claude.com/docs/en/permissions
- [AUTO] Auto mode: https://code.claude.com/docs/en/auto-mode
- [STATUS] Status line: https://code.claude.com/docs/en/statusline
- [PS] PowerShell: https://code.claude.com/docs/en/powershell
- [VOICE] Voice mode: https://code.claude.com/docs/en/voice
- [PW] Corporate launcher / process wrapper: https://code.claude.com/docs/en/corporate-launcher
- [ENV] Environment variables: https://code.claude.com/docs/en/env-vars

---

## 12. 更新時の注意

Claude Codeは更新頻度が高く、設定キー、既定値、最低バージョン、OS対応が変わる可能性があります。本資料の表は**2026年8月20日時点**です。導入時および変更申請時には `[SET-EN]` と `[SM]` を再確認し、ステージング端末で `/status`、`/permissions`、`/hooks`、`claude doctor` を実行してください。

<!-- Markdown reference links -->
[SET-JA]: https://code.claude.com/docs/ja/settings
[SET-EN]: https://code.claude.com/docs/en/settings
[SM]: https://code.claude.com/docs/en/server-managed-settings
[SETUP]: https://code.claude.com/docs/en/setup
[HOOK]: https://code.claude.com/docs/en/hooks
[HOOK-GUIDE]: https://code.claude.com/docs/en/hooks-guide
[SB]: https://code.claude.com/docs/en/sandboxing
[MCP]: https://code.claude.com/docs/en/managed-mcp
[PERM]: https://code.claude.com/docs/en/permissions
[AUTO]: https://code.claude.com/docs/en/auto-mode
[STATUS]: https://code.claude.com/docs/en/statusline
[PS]: https://code.claude.com/docs/en/powershell
[VOICE]: https://code.claude.com/docs/en/voice
[PW]: https://code.claude.com/docs/en/corporate-launcher
[ENV]: https://code.claude.com/docs/en/env-vars
