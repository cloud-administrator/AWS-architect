# `settings.wsl2.enterprise.json` 設定内容説明

- 対象：Windows上のWSL2内で動作するClaude Code
- 配布方法：組織設定 ＞ Claude Code ＞ 管理された設定（Managed settings）
- 調査基準日：2026年8月21日
- 説明方針：設定の「意図」だけでなく、複数設定を組み合わせたときの実効動作と残存制約を記載

> **重要**
>
> このJSONは強い制御を意図していますが、`settings.json`だけでClaude Codeの初期Current Working Directoryを固定する設定は含まれていません。必ずWSL2上で `~/claude_work` に移動してからClaude Codeを起動する運用が前提です。
>
> また、`forceLoginOrgUUID` はダミー値、Claude Codeのバージョンは `2.1.237` に完全固定されています。実投入前に必ず確認・変更してください。

---

## 1. 全体像

| 分野 | このJSONによる実効動作 | 評価 |
|---|---|---|
| ログイン | claude.aiログインに限定し、指定Organization UUIDへの所属を要求 | **UUIDの置換が必須** |
| Managed Policy | 取得済みPolicyがある環境では、起動時に最新Policyを取得できなければ終了 | **初回起動は完全保証不可** |
| Claude Codeバージョン | `2.1.237`より古くても新しくても起動拒否 | **完全固定。更新時に設定変更が必要** |
| Workspace | `~/claude_work`のReadを自動許可し、Editを承認制にする。`/cd`も同配下だけ許可 | **初期CWD自体は固定しない** |
| Bash | すべてユーザー承認を要求し、承認後もSandbox内で実行 | **強い制御** |
| Sandbox回避 | `dangerouslyDisableSandbox`を無効化 | **強制。ただし`excludedCommands`の追加リスクあり** |
| Windowsドライブ | `/mnt`配下のRead／WriteをPermissionとSandboxの両方で拒否 | **標準Drive Mountには有効** |
| Windows実行ファイル | `.exe`を含むBashコマンドを拒否 | **文字列ルールのため完全なInterop遮断ではない** |
| Web | 組み込み`WebFetch`と`WebSearch`は全面禁止。Sandbox内コマンドは2ドメインだけ許可 | **組み込みWeb Toolは使用不可** |
| MCP | MCP Serverの許可リストが空のため、実質すべて禁止 | **ロックダウン** |
| Hooks | すべてのHookを禁止 | **Managed Hookも動作しない** |
| Plugin／Skill | Marketplace追加をロックし、サイドロードやSkill内Shell実行等を制限 | **強い制御。ただし既存Plugin全種のロード停止とは限らない** |
| Remote機能 | Remote Control、Channel、Artifact、バックグラウンドAgent View等を無効化 | **強制** |

---

## 2. 認証・Managed Policy・バージョン

公式根拠：Claude Code Settings、Server-managed settings、Claude Code Changelog

| 設定項目 | 設定値 | わかりやすい説明 | 実際の利用者動作 | 注意点・制約 |
|---|---|---|---|---|
| `forceLoginMethod` | `"claudeai"` | Claude Codeのログイン方法をclaude.aiアカウントに限定します。 | Claude Console専用ログインやGatewayログインではなく、claude.aiログインが要求されます。 | Server-managed settingsはログイン後に取得されるため、初回ログイン前からこの値が必ず効くとは限りません。 |
| `forceLoginOrgUUID` | `"00000000-0000-4000-8000-000000000000"` | ログインを許可するAnthropic OrganizationをUUIDで限定します。 | このUUIDに所属しないアカウントはログインできません。 | **現在値はダミーです。実Organization UUIDへの置換必須です。** このままでは通常、実在Organizationに一致せずログイン不能になります。 |
| `forceRemoteSettingsRefresh` | `true` | 起動時に最新のServer-managed settingsを取得できるまで待ち、取得失敗時は終了します。 | 取得済みPolicyがキャッシュされている端末では、Policyサーバーへ到達できない場合にClaude Codeが起動しません。 | 初回起動では、まだこのキー自体が端末へ届いていないため、Server-managed settingsだけで初回からFail-closedを保証できません。認証関連の一部コマンドは例外です。 |
| `requiredMinimumVersion` | `"2.1.237"` | 起動を許可するClaude Codeの最低バージョンです。 | `2.1.236`以下は起動拒否されます。 | このキーを認識しない古いClaude Codeは無視する可能性があります。 |
| `requiredMaximumVersion` | `"2.1.237"` | 起動を許可するClaude Codeの最高バージョンです。 | `2.1.238`以上は起動拒否されます。 | 最低値と最高値が同一なので、**2.1.237への完全固定**です。公式変更履歴には2.1.238も掲載されているため、現状では新しい版も拒否します。 |
| `parentSettingsBehavior` | `"first-wins"` | Agent SDKやIDEなどの埋め込み元が追加で渡すManaged settingsを、管理者Policyがある場合に採用しない設定です。 | 管理者が配布したManaged settingsが優先され、親プロセス由来の設定は破棄されます。 | 一般的なUser／Project設定の優先順位を変更するキーではありません。埋め込みホスト由来のManaged settingsだけが対象です。 |

---

## 3. Managed設定によるカスタマイズ経路の制限

公式根拠：Claude Code Settings、Managed MCP、Plugins、Hooks

| 設定項目 | 設定値 | わかりやすい説明 | 実際の利用者動作 | 注意点・制約 |
|---|---|---|---|---|
| `allowManagedPermissionRulesOnly` | `true` | Permissionの`allow`・`ask`・`deny`をManaged settingsだけから受け付けます。 | User／Project／Local設定にPermission ruleを書いても適用されません。 | 画面に表示された個別の承認をユーザーが行うことまで禁止する設定ではありません。Permission以外の全設定をManaged限定にするキーでもありません。 |
| `allowManagedHooksOnly` | `true` | Hookの供給元をManaged settingsに限定します。 | User／Project／Local設定のHookは実行されません。 | このJSONではさらに`disableAllHooks: true`なので、Managed Hookを含め**すべてのHookが停止**します。 |
| `allowManagedMcpServersOnly` | `true` | MCP許可リストをManaged settingsの値だけに限定します。 | User／Project側が許可対象を追加しても認められません。 | MCP Serverの登録操作自体が残る場合でも、管理者allowlistに合致しなければ利用できません。 |
| `allowedMcpServers` | `[]` | 利用を許可するMCP Serverの一覧です。空配列はロックダウンを意味します。 | 現在はMCP Serverを1台も利用できません。 | 後日MCPを利用する場合は、公式スキーマに従ったServer定義を管理者が追加する必要があります。 |
| `disableClaudeAiConnectors` | `true` | claude.aiから取得されるMCP Connectorの自動取得・接続を止めます。 | Gmail等のclaude.ai Connectorが自動接続されません。 | このキー単独では明示的な`--mcp-config`を止めませんが、同時設定の`disableSideloadFlags`と空の`allowedMcpServers`で追加経路を制限しています。 |
| `disableSideloadFlags` | `true` | `--plugin-dir`、`--plugin-url`、`--agents`、`--mcp-config`による一時的な持ち込みを拒否します。 | 利用者が起動オプションで管理外Plugin・Agent・MCPを差し込めません。 | すべてがin-process `type: "sdk"`の`--mcp-config`は公式仕様上の例外です。`claude mcp add`や`.mcp.json`を単独では止めないため、MCP allowlistとの併用が重要です。 |
| `strictPluginOnlyCustomization` | `true` | User／Project由来のSkill、Agent、Hook、MCPを禁止し、PluginまたはManaged由来に限定します。 | `.claude/skills`、`.claude/agents`、Project Hook、Project MCP等による独自拡張が使えません。 | Plugin由来とManaged由来は候補として残ります。後続の設定でさらにPlugin経路を狭めています。 |
| `strictKnownMarketplaces` | `[]` | 利用可能なPlugin Marketplaceのallowlistです。空配列はロックダウンです。 | Marketplaceの追加、Pluginのインストール、更新、refresh、auto-updateが拒否されます。 | 公式説明はこれらの取得・更新経路を明確に禁止しますが、すでに導入済みの全種類のPluginを必ずロード停止する、とまではこのキー単独の説明に明記されていません。 |
| `disableCommandPluginSources` | `true` | OS上でコマンドを実行してPluginを導入する`command` sourceを禁止します。 | command sourceのPluginは新規導入・更新されず、既存のものもロードされません。 | `command` source以外の既存Pluginについては、このキーだけでは全面停止になりません。 |
| `disableSkillShellExecution` | `true` | SkillやCustom Command内のインラインShell実行を無効化します。 | User／Project／Plugin／追加ディレクトリ由来のSkillに書かれたShell部分は実行されず、無効化メッセージへ置換されます。 | **Bundled SkillとManaged Skillはこのキーの対象外**です。Bundled Skillは次の設定で別途無効化しています。Managed SkillのShellはこのキーでは止まりません。 |
| `disableBundledSkills` | `true` | Claude Codeに同梱されているSkillとWorkflowを無効化します。 | Bundled Skill／Workflowはモデルから利用できなくなります。 | `/init`等の一部Built-in Commandは入力可能なままです。PluginやUser／Project Skillを単独で止める設定ではありませんが、他のロック設定と併用されています。 |
| `disableWorkflows` | `true` | Dynamic WorkflowとBundled Workflow Commandを無効化します。 | 複数Agentを使うWorkflow機能等が使えません。 | `disableBundledSkills`と一部役割が重複しますが、防御を明示しています。 |
| `disableAllHooks` | `true` | 全Hook、Custom Status Line、Custom File Suggestion Commandを無効化します。 | 管理者Hookも含め、Hookは一切実行されません。 | 将来Managed Hookを使う場合、この値を削除または`false`へ変更し、`allowManagedHooksOnly: true`を残す必要があります。 |
| `channelsEnabled` | `false` | Claude Code Channels機能を無効化します。 | Channel PluginからClaude Codeへメッセージを送れません。 | Team／Enterpriseでは未設定または`false`でブロックされます。 |
| `allowedChannelPlugins` | `[]` | Channelとして許可するPluginのallowlistです。 | 許可Channel Pluginは0件です。 | `channelsEnabled: false`のため実質的には重複する防御です。 |
| `disableRemoteControl` | `true` | Claude Code Remote Controlを無効化します。 | `claude remote-control`、`--remote-control`、自動開始、セッション内の切替が使えません。 | Claude Codeの他の通常通信まで遮断する設定ではありません。 |
| `disableArtifact` | `true` | Artifact Toolを無効化します。 | セッション出力をclaude.ai上のPrivate Web Pageとして公開する機能が使えません。 | 通常の会話やファイル出力を禁止する設定ではありません。 |
| `disableAgentView` | `true` | Background AgentとAgent Viewを無効化します。 | `claude agents`、`--bg`、`/background`、オンデマンドSupervisorが使えません。 | すべての通常Subagent／Agent Toolを全面禁止する設定ではありません。 |
| `crossSessionInbound` | `"refuse"` | 他のClaude Codeセッションから届くメッセージを拒否します。 | 別セッションからのInbound Messageは通知保留ではなく破棄されます。 | `accept < hold < refuse`の最も厳しい値です。 |
| `env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` | `"1"` | Bash、Hook、stdio MCP子プロセスからAnthropicやCloud Providerの認証情報を取り除きます。 | ShellからClaude本体のAPI Credentialを環境変数経由で読み出しにくくなります。WSL2/LinuxではPID Namespaceも分離されます。 | すべての任意環境変数や企業秘密を自動的に削除する機能ではありません。HooksとMCPは本JSONでは別設定により停止しています。 |

---

## 4. Permissionの基本動作

公式根拠：Claude Code Permissions、Claude Code Settings

Permission ruleは、**`deny` → `ask` → `allow`**の順で評価されます。先に一致した種類が採用され、狭い`allow`で広い`deny`を上書きすることはできません。

| 設定項目 | 設定値 | わかりやすい説明 | 実際の利用者動作 | 注意点・制約 |
|---|---|---|---|---|
| `permissions.defaultMode` | `"default"` | Manual相当のPermission Modeです。 | ファイル変更やShell実行など、標準で承認対象となる操作に確認画面が表示されます。 | 読み取り専用操作は、Working DirectoryやAdditional Directory内では通常、承認不要です。 |
| `permissions.disableAutoMode` | `"disable"` | Auto modeを利用できなくします。 | `Shift+Tab`や起動オプションからAuto modeを選べません。Autoで始めようとしても`default`になります。 | JSON Booleanではなく文字列`"disable"`が正式値です。 |
| `permissions.disableBypassPermissionsMode` | `"disable"` | Permission bypassを利用できなくします。 | `--dangerously-skip-permissions`やAgent定義の`bypassPermissions`が無効になります。 | Claude Code自身のPermission bypassを止める設定であり、OS管理者権限そのものを剥奪する設定ではありません。 |

### 4.1 自動許可ルール

| Permission rule | 分類 | わかりやすい説明 | 実効動作 | 注意点・制約 |
|---|---|---|---|---|
| `Read(~/claude_work/**)` | `allow` | `~/claude_work`とその配下の組み込みFile Readを承認不要にします。 | Read、Grep、Glob等の組み込み読み取り系Toolは同範囲を自動利用できます。 | **他のLinuxパスをdenyするルールではありません。** 初期Working DirectoryやAdditional Directoryが別パスなら、別領域もアクセス対象になり得ます。Symlinkはリンク元と解決先の両方がallowに一致しない場合、allow扱いにならず承認へフォールバックします。 |
| `Cd(~/claude_work/**)` | `allow` | 利用者が実行する`/cd`の移動先を`~/claude_work`配下へ限定します。 | `~/claude_work`自身と子ディレクトリだけへ`/cd`できます。その他は拒否されます。 | Claude Code起動時のCWDは固定しません。また、これはユーザー操作の`/cd`用で、Bashコマンド内部の`cd`を直接制御するルールではありません。Symlinkの解決経路も評価されます。 |

### 4.2 毎回承認を要求するルール

| Permission rule | 分類 | わかりやすい説明 | 実効動作 | 注意点・制約 |
|---|---|---|---|---|
| `Edit(~/claude_work/**)` | `ask` | Workspace内のEdit／Write／新規作成等をユーザー承認制にします。 | Claudeが`~/claude_work`内のファイルを変更しようとすると確認画面が表示されます。 | `Edit` path ruleは組み込みの編集Tool群に使われます。Workspace外全体をdenyするルールではありません。 |
| `Bash` | `ask` | すべてのBashコマンドを承認制にします。 | 読み取り専用コマンドを含め、Sandbox内で実行可能なBashでも毎回Permission Flowを通ります。 | `sandbox.autoAllowBashIfSandboxed: false`との組合せが重要です。ユーザーが承認するとコマンドはSandbox内で実行されます。 |
| `mcp__*` | `ask` | すべてのMCP Toolを承認制にします。 | MCP Toolが存在すれば、実行ごとに確認が必要です。 | 現在は`allowedMcpServers: []`のためMCP Server自体が認められず、通常このルールが発動する機会はありません。将来allowlistへ追加した場合の安全策です。 |

### 4.3 禁止ルール

| Permission rule | 禁止対象 | 実効動作 | 注意点・制約 |
|---|---|---|---|
| `Read(//mnt/**)` | WSLの`/mnt`配下に対する組み込みRead | `/mnt/c`、`/mnt/d`等をRead／Grep／Glob等で参照できません。 | Permission ruleの`//`はFilesystem Rootからの絶対パスを示します。`/mnt`以外にマウントされたWindows／Network Resourceは対象外です。 |
| `Edit(//mnt/**)` | WSLの`/mnt`配下に対する組み込みEdit／Write | `/mnt/c`等で編集・作成・削除できません。 | `Read` denyもEdit／Writeを一部ブロックしますが、`Edit` denyを併記して編集系Toolを明示的に塞いでいます。 |
| `PowerShell` | Claude CodeのPowerShell Tool全体 | PowerShell Toolがモデルから利用できません。 | WSL2のBashからLinux Native `pwsh`を起動する経路は別物で、`Bash`承認とSandboxの対象です。Windowsの`powershell.exe`は`.exe`ルールでも制限します。 |
| `WebFetch` | 組み込みWebFetch Tool全体 | 許可ドメインを含め、WebFetchは一切利用できません。 | Sandboxの`allowedDomains`は、Sandbox内コマンド用です。組み込みWebFetchを再許可するものではありません。 |
| `WebSearch` | 組み込みWebSearch Tool全体 | WebSearchは一切利用できません。 | Domain単位で厳密に限定できないため、全面禁止の構成です。 |
| `Bash(dangerouslyDisableSandbox:true)` | Sandbox外実行を要求するBash Tool Call | 該当Tool CallをPermission段階で拒否します。 | `sandbox.allowUnsandboxedCommands: false`でも同じEscape Hatchを無効化しており、防御を重ねています。 |
| `Bash(*.exe*)` | コマンド文字列に`.exe`を含むBash | `cmd.exe`、`powershell.exe`、`notepad.exe`等の典型的Windows Binary実行を拒否します。 | Bash Permission patternはコマンド文字列ベースです。別名、Wrapper、変数展開、特殊な呼出経路等を含む完全なWindows Interop遮断ではありません。 |
| `Bash(*sudo *)` | `sudo`を含むコマンド | 一般的なsudo権限昇格を拒否します。 | 文字列パターンであり、OSレベルの権限昇格防止境界ではありません。 |
| `Bash(*su *)` | `su`を含むコマンド | 別ユーザー／rootへの切替を狙う一般的な`su`を拒否します。 | 同上。文字列に一致しない別経路までは保証しません。 |
| `Bash(*doas *)` | `doas`を含むコマンド | `doas`による権限昇格を拒否します。 | 同上。 |
| `Bash(*pkexec *)` | `pkexec`を含むコマンド | PolicyKit経由の権限昇格を拒否します。 | 同上。 |
| `Bash(*mount *)` | `mount`を含むコマンド | 新しいFilesystem Mountの作成を拒否します。 | 単純な文字列一致のため、すべてのMount関連経路をOSレベルで完全遮断するものではありません。 |
| `Bash(*umount *)` | `umount`を含むコマンド | Mount解除を拒否します。 | 同上。 |
| `Bash(*nsenter *)` | `nsenter`を含むコマンド | 他Namespaceへ入る典型的なコマンドを拒否します。 | 別のBinaryやWrapperを介する経路まで完全保証しません。 |
| `Bash(*unshare *)` | `unshare`を含むコマンド | 新しいNamespaceを作る典型的なコマンドを拒否します。 | 別経路まで完全保証しません。 |

---

## 5. Sandbox基本設定

公式根拠：Claude Code Sandboxing、Claude Code Settings

| 設定項目 | 設定値 | わかりやすい説明 | 実際の利用者動作 | 注意点・制約 |
|---|---|---|---|---|
| `sandbox.enabled` | `true` | Bashとその子プロセスをSandbox内で実行します。 | WSL2上でFilesystemとNetworkの分離が適用されます。 | Native Windowsでは非対応です。WSL2で`bubblewrap`と`socat`が必要です。 |
| `sandbox.failIfUnavailable` | `true` | Sandboxを開始できない場合にClaude Codeを終了します。 | 依存関係不足、WSL1、非対応環境等では、Unsandboxedへ自動Fallbackせず起動失敗します。 | Optional seccomp filterがないだけの場合まで必ず起動失敗する、という意味ではありません。seccompはUnix Socket遮断用の追加機能です。 |
| `sandbox.autoAllowBashIfSandboxed` | `false` | Sandbox内で実行できるという理由だけでBashを自動承認しません。 | Sandbox内Bashも通常のPermission Flowへ進み、`Bash` ask ruleによりユーザー承認が必要です。 | 要件どおりの「Sandbox内でも毎回承認」を実現する中心設定です。 |
| `sandbox.allowUnsandboxedCommands` | `false` | Sandbox失敗時に`dangerouslyDisableSandbox`で外へ逃がす仕組みを無効化します。 | Sandbox内で実行できないコマンドは、通常のUnsandboxed再実行へ切り替えられません。 | `excludedCommands`に該当するコマンドは例外としてSandbox外実行になります。 |
| `sandbox.excludedCommands` | `[]` | 管理者が明示的にSandbox外で実行させるCommand一覧です。 | Managed設定には例外Commandが1件もありません。 | **重大な制約：配列はScope間でマージされ、`excludedCommands`にはManaged-only lockがありません。User／Project側から追加される余地が公式に残っています。** |
| `sandbox.enableWeakerNestedSandbox` | `false` | Securityを弱めたNested Sandboxを使用しません。 | 通常の強いSandboxを要求します。 | Container内等で通常Sandboxが作れなければ、`failIfUnavailable: true`により起動失敗する可能性があります。 |

---

## 6. SandboxのFilesystem制限

公式根拠：Claude Code Sandboxing、Sandbox path prefixes

| 設定項目 | 設定値 | わかりやすい説明 | 実効動作 | 注意点・制約 |
|---|---|---|---|---|
| `sandbox.filesystem.disabled` | `false` | Filesystem isolationを有効のままにします。 | Sandboxed Bashと子プロセスにはRead／Write制限が適用されます。 | `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`もFilesystem isolationを維持する方向に働きます。 |
| `sandbox.filesystem.allowWrite` | `["~/claude_work"]` | Sandbox内プロセスへ`~/claude_work`の書込み権限を追加します。 | 承認済みBashは`~/claude_work`にファイルを作成・変更できます。 | **これは排他的allowlistではなく追加許可です。** SandboxではCurrent Working DirectoryとSession Temp Directoryも標準で書込み可能です。別ディレクトリから起動すると、その起動CWDも書込み可能になり得ます。WSL2のWrite listはWildcard非対応ですが、この値はConcrete Pathなので有効です。 |
| `sandbox.filesystem.denyWrite` | `["/mnt"]` | `/mnt`とその配下へのSandbox内Writeを拒否します。 | `/mnt/c`、`/mnt/d`等へ、Bashやその子プロセスから書き込めません。 | WSL2で無効になる`/mnt/*`ではなく、Concrete Path `/mnt`を使用しているため有効です。別のMount Pointは対象外です。 |
| `sandbox.filesystem.denyRead` | `["~/", "/mnt"]` | Home Directory全体と`/mnt`全体をSandbox内Read禁止にします。 | 原則としてHome配下とWindows Drive MountをShellから読めません。 | 後続の`allowRead`で`~/claude_work`だけをHome deny内から再許可しています。他のLinuxパス、例：`/etc`、`/usr`、`/var`全体を禁止する設定ではありません。 |
| `sandbox.filesystem.allowRead` | `["~/claude_work"]` | 広いHome denyの内側から、Workspaceだけを読み取り可能に戻します。 | Sandboxed Bashは`~/claude_work`を読めますが、他のHome配下は読めません。 | SandboxのReadルールでは、より狭い`allowRead`で広い`denyRead`の一部を再度開く正式仕様があります。 |
| `sandbox.filesystem.allowManagedReadPathsOnly` | `true` | `allowRead`の追加をManaged settingsだけに限定します。 | User／Project／Local設定から別のRead例外を追加できません。 | `denyRead`は各Scopeからマージされるため、利用者側がより厳しくすることは可能です。Write側には同等の`allowManagedWritePathsOnly`設定はありません。 |

### Filesystem制限の実効範囲

| 対象 | 組み込みRead／Edit Tool | Sandboxed Bash／子プロセス |
|---|---|---|
| `~/claude_work` | Readは自動許可、Edit／Writeは承認 | Read／Write可能。ただしBash起動自体に承認必要 |
| Home内の`~/claude_work`以外 | 本JSONでは一律denyしていない | `denyRead: "~/"`によりRead禁止。Writeは標準Sandbox境界によるが、排他的Workspace固定ではない |
| `/mnt/c`、`/mnt/d`等 | Read／Edit deny | Read／Write deny |
| `/etc`、`/usr`、`/var`等 | 本JSONでは一律denyしていない | 原則Read可能。WriteはSandbox標準境界で制限 |
| Session Temp Directory | Permission Toolとは別 | Sandbox仕様によりWrite可能 |
| Claude Code起動CWD | 読み取り専用操作は通常承認不要 | Sandbox仕様によりWrite可能 |

---

## 7. SandboxのNetwork制限

公式根拠：Claude Code Sandboxing、Network isolation

| 設定項目 | 設定値 | わかりやすい説明 | 実効動作 | 注意点・制約 |
|---|---|---|---|---|
| `sandbox.network.allowedDomains` | `["example.com", "api.example.com"]` | Sandboxed Commandが通信できるDomainの管理者allowlistです。 | `curl`、`wget`、package manager等は、この2Domainだけへ接続できます。 | 実環境の承認Domainへ置換してください。必要なCDN、認証先、redirect先等も個別に許可しないとToolが失敗します。 |
| `sandbox.network.strictAllowlist` | `true` | allowlist外Domainを承認画面へ回さず即時拒否します。 | 未許可DomainへのSandbox通信はユーザーがその場で許可できません。 | Sandboxed Commandだけが対象です。In-process Toolの`WebFetch`には適用されませんが、このJSONではWebFetch自体をdenyしています。 |
| `sandbox.network.allowManagedDomainsOnly` | `true` | Network allowlistをManaged settings由来だけに限定します。 | User／Project／Local設定から許可Domainを追加できません。 | deniedDomainsは他Scopeからも追加でき、より厳しくすることは可能です。 |
| `sandbox.network.allowAllUnixSockets` | `false` | Unix Domain Socketを全面許可しません。 | Optional seccomp filterが導入済みなら、Sandbox内のUnix Socket作成・接続がブロックされます。 | **seccomp filterが未導入の場合、Linux／WSL2 SandboxはUnix Socket Callをブロックしません。** WSL2のWindows Binary起動はInterop Socketを使うため、Windows Hostへの完全遮断はこのJSONだけでは保証できません。 |

### Web機能の最終動作

| 操作 | 最終動作 | 理由 |
|---|---|---|
| 組み込み`WebFetch`で`example.com`へアクセス | **禁止** | Permissionの裸の`WebFetch` denyが先に適用されるため |
| 組み込み`WebFetch`で未許可Domainへアクセス | **禁止** | `WebFetch`全面deny |
| 組み込み`WebSearch` | **禁止** | `WebSearch`全面deny |
| Bashの`curl https://example.com/...` | **ユーザー承認後、Sandbox内で許可** | `Bash` ask + Domain allowlist |
| Bashの`curl https://api.example.com/...` | **ユーザー承認後、Sandbox内で許可** | 同上 |
| Bashの`curl https://other.example/...` | **ユーザー承認の前後に関係なくNetwork拒否** | strict allowlist外 |

---

## 8. 主要操作ごとの最終動作

| 操作 | 最終動作 | 説明 |
|---|---|---|
| `~/claude_work`内の通常Read | **自動許可** | `Read(~/claude_work/**)` allow |
| `~/claude_work`内のEdit | **ユーザー承認** | `Edit(~/claude_work/**)` ask |
| `~/claude_work`内のWrite／新規作成 | **ユーザー承認** | 組み込みFile ModificationはEdit path ruleで評価 |
| `~/claude_work`内のDelete | **ユーザー承認** | Bash経由なら裸の`Bash` ask。組み込み編集操作でも承認対象 |
| `/mnt`配下のRead | **禁止** | PermissionとSandboxの両方でdeny |
| `/mnt`配下のEdit／Write | **禁止** | PermissionとSandboxの両方でdeny |
| Home内のWorkspace外をSandboxed BashでRead | **禁止** | `denyRead: "~/"` + Workspaceだけ`allowRead` |
| 他のLinux Directoryを組み込みRead | **完全禁止ではない** | `/mnt`以外を一律denyするPermission ruleはない |
| `/cd`でWorkspace外へ移動 | **禁止** | `Cd` allow ruleによりallowlist mode |
| 起動時CWDをWorkspaceへ固定 | **settings.jsonだけでは未実現** | 初期CWDを指定する設定が本JSONにない |
| Bash／Linux Shell Command | **ユーザー承認** | 裸の`Bash` ask |
| Sandbox内Bash | **ユーザー承認** | `autoAllowBashIfSandboxed: false` |
| Linux Native `pwsh`をBashから実行 | **ユーザー承認後にSandbox内実行** | PowerShell ToolではなくBash経由 |
| Windows `cmd.exe`／`powershell.exe` | **典型的呼出は拒否、完全保証不可** | `.exe`文字列deny。ただしInterop自体のOSレベル遮断ではない |
| WebFetch | **禁止** | 裸の`WebFetch` deny |
| WebSearch | **禁止** | 裸の`WebSearch` deny |
| MCP Tool | **現状は利用不可** | MCP allowlistが空。将来許可時は`mcp__*` ask |
| 管理外MCP | **禁止** | Managed-only allowlist + 空配列 + sideload制限 |
| Hook | **すべて禁止** | `disableAllHooks: true` |
| Channel | **禁止** | `channelsEnabled: false` |
| Remote Control | **禁止** | `disableRemoteControl: true` |
| Artifact | **禁止** | `disableArtifact: true` |
| Auto mode | **禁止** | `disableAutoMode: "disable"` |
| Permission bypass | **禁止** | `disableBypassPermissionsMode: "disable"` |
| `dangerouslyDisableSandbox` | **禁止** | Permission deny + `allowUnsandboxedCommands: false` |
| `excludedCommands` | **Managed値は空。ただし完全固定不可** | 他Scopeから配列へ追加できる公式上の残存リスク |

---

## 9. 特に重要な制約・誤解しやすい点

| 項目 | このJSONでできていること | このJSONだけでは保証できないこと |
|---|---|---|
| 初期Workspace | `/cd`の移動先を`~/claude_work`配下へ限定 | Claude Codeを必ず`~/claude_work`から起動させること。別CWDから起動すると、そのCWDが標準Workspace／Sandbox書込み領域になり得る |
| 組み込みFile Tool | `~/claude_work`のRead自動許可、Edit承認、`/mnt`拒否 | `/mnt`以外の全Linux Filesystemを一律禁止すること |
| Sandbox Filesystem | Homeと`/mnt`のRead制限、`/mnt`のWrite制限 | `/etc`、`/usr`等を含むLinux Filesystem全体をWorkspace以外すべて不可視にすること |
| Windows Drive Mount | 標準的な`/mnt/c`、`/mnt/d`を拒否 | 別Mount Point、Interop Socket、Wrapper、OS側Network Resourceを含む完全なWindows Host Isolation |
| Windows Binary | `.exe`を含む典型的コマンド文字列を拒否 | 文字列難読化、Wrapper、未想定経路を含む完全なInterop禁止 |
| Unix Socket | seccomp filter導入済みなら`allowAllUnixSockets: false`で遮断 | seccomp filter未導入環境でのUnix Socket遮断 |
| Sandbox例外 | Managedの`excludedCommands`は空 | User／Project側から`excludedCommands`を追加することの完全禁止 |
| Web | Sandbox内CommandのDomainを管理者allowlistに固定 | TLS内容検査、Domain Fronting等を含むネットワーク上の完全なSecurity Boundary |
| Plugin | Marketplace追加・取得・更新、sideload、command source等を強く制限 | すでに導入済みのあらゆるSource種別のPluginが必ずロードされないことを、`strictKnownMarketplaces: []`単独で保証すること |
| Managed Policy | 取得済み端末で起動時のFresh Fetch失敗をFail-closed化 | Server-managed Policyが一度も届いていない初回起動からのFail-closed |
| Organization Login | Policy適用後、claude.aiと指定Orgへ制限 | Server-managed Policy取得前の最初のLoginを同Policyだけで強制 |
| Version | キーを認識するVersionに対し2.1.237へ固定 | このキーが実装される前の古いClientでの強制。今後のVersionを自動で安全に追従 |
| Security Boundary | Claude Code内のTool、Permission、Sandboxを強く制御 | `settings.json`自体をOS／Hypervisor／Network Firewall相当の完全なSecurity Boundaryにすること |

---

## 10. 本番投入前の必須確認

1. `forceLoginOrgUUID`を実企業Organization UUIDへ置換する。
2. `2.1.237`を本当に承認Versionとして固定するか再確認する。公式変更履歴には`2.1.238`も掲載されている。
3. `example.com`と`api.example.com`を実際の許可Domainへ置換する。
4. 各ユーザーが必ずWSL2のLinux Filesystem上の`~/claude_work`へ移動してから`claude`を起動する運用を徹底する。
5. `/sandbox`のDependencies表示で`bubblewrap`、`socat`、必要に応じてoptional seccomp filterを確認する。
6. `/status`でManaged settingsの適用元を確認する。
7. `/permissions`でPermission ruleの実効一覧を確認する。
8. `/sandbox`のConfigで、解決後のFilesystem／Network設定と、WSL2でskipされたWrite pathがないことを確認する。
9. `claude doctor`で無効・未認識・schema errorの設定項目がないことを確認する。

---

## 公式参照先

- Claude Code Settings: https://code.claude.com/docs/en/settings
- Claude Code Permissions: https://code.claude.com/docs/en/permissions
- Claude Code Sandboxing: https://code.claude.com/docs/en/sandboxing
- Server-managed settings: https://code.claude.com/docs/en/server-managed-settings
- Environment variables: https://code.claude.com/docs/en/env-vars
- Claude Code Changelog: https://code.claude.com/docs/en/changelog
