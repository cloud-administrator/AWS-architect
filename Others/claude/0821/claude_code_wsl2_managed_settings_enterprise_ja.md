# Claude Enterprise / Claude Code Managed settings — WSL2 強化設定案

> 対象: **Windows上のWSL2内で実行するClaude Code**  
> 配布元: **組織設定 → Claude Code → 管理された設定（server-managed settings）**  
> 作業領域: **WSL2 Linuxファイルシステム上の `~/claude_work`**  
> 調査日: **2026年8月20日（日本時間）**  
> 調査範囲: **Anthropic / Claude Code公式ドキュメントのみ**  
> 検証対象バージョン: **Claude Code 2.1.237**（調査日時点の公式Changelog最新）

---

## 1. 要件実現可否一覧

### 判定基準

| 判定 | 意味 |
|---|---|
| **完全対応** | 現行の対応バージョンでManaged settingsが有効になった後、今回のJSONだけで対象のClaude Code機能を強制できるものです。OS自体を侵害した利用者や改変クライアントまでは含みません。 |
| **部分対応** | 大部分は制御できますが、別スコープから追加可能な例外、初回起動、WSL2の仕組み、OS資源、任意のラッパーなどに残存経路があります。 |
| **settings.jsonのみでは対応不可** | 現行公式仕様に、その保証を行う設定キーまたは安全に成立するルール表現がありません。架空のキーや、実際には機能しないdeny/allowの組合せは使用しません。 |

| No. | 要件 | 判定 | 理由と今回の最大限の対応 |
|---:|---|---|---|
| 1 | WSL2でSandboxを必ず有効にする | **完全対応** | `sandbox.enabled: true` と `sandbox.failIfUnavailable: true` をManaged settingsで強制します。bubblewrapやsocatなど必須依存関係がなければClaude Codeは起動を中止します。ただし、Windows Interop遮断に関係するseccomp filterは公式上「任意依存」であり、欠落しても `failIfUnavailable` の必須依存失敗にはなりません。[S4] |
| 2 | Sandbox内Bashを自動承認しない | **完全対応** | `sandbox.autoAllowBashIfSandboxed: false` によりregular permissions modeを使用し、Managedの裸の `Bash` askルールですべてのBashを承認対象にします。[S3][S4] |
| 3 | Sandbox外への自動再実行を禁止する | **部分対応** | `sandbox.allowUnsandboxedCommands: false` により `dangerouslyDisableSandbox` の再試行経路を無効にします。ただし `sandbox.excludedCommands` は全スコープの配列を結合し、Managed-only固定キーがないため、User / Project側から例外を追加できる残存リスクがあります。[S4] |
| 4 | Manual相当を既定にする | **完全対応** | `permissions.defaultMode: "default"` はCLI上のManualです。`acceptEdits` 等へ切り替えても、Managedのask/denyルールは先に評価されます。[S3] |
| 5 | Auto modeを禁止する | **完全対応** | `permissions.disableAutoMode: "disable"` をManaged settingsで設定します。`--permission-mode auto` 等もdefaultへ戻されます。[S2][S3] |
| 6 | `bypassPermissions` を禁止する | **完全対応** | `permissions.disableBypassPermissionsMode: "disable"` を設定します。現行バージョンではCLIフラグやAgent frontmatterからの指定も拒否されます。[S2][S3] |
| 7 | User / ProjectのPermission ruleで企業ポリシーを変更させない | **完全対応**（Permission ruleに限定） | `allowManagedPermissionRulesOnly: true` により、User / Projectの `allow` / `ask` / `deny` は適用されません。ただしSandboxの `allowWrite`、`excludedCommands`、作業ディレクトリ追加は別機構であり、このロックの対象外です。[S2][S3][S4] |
| 8 | `~/claude_work` 内の通常Readを承認不要にする | **部分対応** | `Read(~/claude_work/**)` をManaged allowにします。起動CWDが同フォルダであることが前提です。`/add-dir` や `permissions.additionalDirectories` を全面禁止するManagedキーは公式仕様で確認できず、別ディレクトリが作業範囲へ追加される余地が残ります。[S3] |
| 9 | `~/claude_work` 内のEdit / Write / Createを毎回承認させる | **完全対応**（Claude Codeの直接ツール呼出し） | `Edit(~/claude_work/**)` をManaged askにします。Claude Codeではパス付き `Write(...)` ルールは評価されないため、公式指示どおり `Edit(...)` を使います。Bash経由の作成・変更も裸の `Bash` askで承認対象です。[S3] |
| 10 | `~/claude_work` 内のDeleteを毎回承認させる | **完全対応**（通常のClaude Code操作） | ファイル削除は通常Bashの `rm` / `rmdir` 等で行われ、裸の `Bash` askにより承認が必要です。個別の「Delete」設定キーは作成していません。[S3][S4] |
| 11 | `~/claude_work` 外の組み込みReadを全面禁止する | **部分対応** | Permissionは `deny → ask → allow` の順です。`Read(//**)` をdenyして `Read(~/claude_work/**)` をallowしても、広いdenyが必ず勝つため例外許可になりません。今回、Windows mountの `/mnt` は明示denyし、それ以外はManual promptとSandbox read制限で最大限抑制します。[S3] |
| 12 | `~/claude_work` 外の組み込みEdit / Writeを全面禁止する | **部分対応** | 上記と同じく、Permissionに「すべて拒否、1ディレクトリだけ例外」という否定条件の安全な表現がありません。`/mnt` は明示denyし、それ以外の直接編集はManual promptになります。ユーザーが承認した場合の絶対禁止まではできません。[S3] |
| 13 | `/cd` を `~/claude_work` と配下だけに限定する | **完全対応** | `Cd(~/claude_work/**)` を1件でもallowに入れると `/cd` はallowlist modeになり、解決後の移動先が一致しない場合は拒否されます。symlinkの各hopも評価されます。[S3] |
| 14 | 初期Working Directoryを `~/claude_work` に固定する | **settings.jsonのみでは対応不可** | 現行公式設定表に初期CWDを固定するキーはありません。**Claude Codeを `~/claude_work` をCurrent Working Directoryとして起動することを運用上の前提とします。** 架空の `workingDirectory` 等は使用しません。[S2][S3] |
| 15 | Symlinkを使ったWorkspace外アクセスを全面禁止する | **部分対応** | Read/Edit Permissionはsymlink自体と解決先の両方を評価し、Cd deny/allowも解決経路を確認します。`/mnt` やhome内の拒否領域へのリンクは止まります。ただし、明示denyしていないLinux system pathへの組み込みReadをユーザーが承認する余地は残ります。[S3][S4] |
| 16 | `/mnt/c`、`/mnt/d` 等の標準Windows Drive Mountを読み書き禁止にする | **完全対応**（標準 `/mnt` 配下） | 組み込みツールは `Read(//mnt/**)` / `Edit(//mnt/**)` で拒否し、Sandbox subprocessは具体パス `/mnt` を `denyRead` / `denyWrite` に設定します。WSL2のwrite listでは `/mnt/*` のようなwildcardが無効になるため使用しません。[S3][S4] |
| 17 | UNC / Windows Network Resource / 任意位置の共有mountを全面遮断する | **settings.jsonのみでは対応不可** | `/mnt` 以外へmountされた共有、Windows InteropからのUNC、既存のホスト側仲介プロセス等をOSレベルで列挙・隔離する設定はありません。標準mount、Windows executable、Unix socketを最大限制限しますが、完全なWindows Host Isolationではありません。[S4][S5] |
| 18 | 権限昇格を禁止する | **部分対応** | `sudo`、`su`、`doas`、`pkexec`、`mount`、`nsenter`、`unshare` 等の直接Bash文字列をdenyし、全BashをSandbox化します。しかし任意スクリプト、改名したバイナリ、既承認ラッパーを文字列ルールだけで完全識別することはできません。[S3][S4] |
| 19 | `cmd.exe` / `powershell.exe` 等のWindows executableを禁止する | **部分対応** | `Bash(*.exe*)` と `PowerShell` toolの全面denyを設定します。さらにseccomp filterがあればWSL2のWindows launch用Unix socketをOSレベルでブロックできます。ただしseccompは任意依存で、別名・ラッパー・lower-scope `excludedCommands` を含む全経路の保証はできません。[S3][S4] |
| 20 | Linux native `pwsh` は承認後に使用する | **完全対応**（Bash経由） | 直接の `PowerShell` toolは無効化します。Linux native `pwsh` は `Bash` から実行させ、裸のBash askとSandboxの両方を適用します。 |
| 21 | Sandboxed `curl` / `wget` / package managerを管理Domainだけに限定する | **完全対応**（Sandbox内に限定） | `allowedDomains` に2Domainだけを指定し、`strictAllowlist: true` と `allowManagedDomainsOnly: true` を設定します。未許可Domainはpromptを出さず拒否され、User / ProjectはDomainを追加できません。[S2][S4] |
| 22 | すべてのShell経由networkを管理Domainだけに限定する | **部分対応** | Sandbox内では強制できますが、lower scopeから追加可能な `excludedCommands` はSandbox外で実行され得ます。したがって、settings.json全体としての完全なnetwork boundaryにはなりません。[S4] |
| 23 | 許可Domainの `WebFetch` を承認制、未許可Domainを禁止する | **settings.jsonのみでは対応不可**（今回の案ではWebFetch全面禁止） | `network.strictAllowlist` は公式上Sandboxed commandsだけを対象とし、in-process toolの `WebFetch` はPermission ruleに従います。Permissionでは広いWebFetch denyに狭いask/allow例外を作れないため、厳密な「allowlist + 毎回承認」を宣言的JSONだけで成立させられません。安全側で `WebFetch` を全面denyします。[S3][S4] |
| 24 | `WebSearch` を管理Domainだけに限定する | **settings.jsonのみでは対応不可**（今回の案では全面禁止） | 現行Permission syntaxに `WebSearch(domain:...)` 相当は確認できません。要求どおり `WebSearch` をbare denyします。[S3] |
| 25 | MCPを管理者管理だけに限定する | **完全対応**（今回のゼロMCP基準） | `allowedMcpServers: []`、`allowManagedMcpServersOnly: true`、connector停止、sideload flag停止、plugin-only customizationを併用し、現在はMCP serverを1件も許可しません。[S2][S6] |
| 26 | 将来、管理者許可MCP toolを毎回承認させる | **完全対応**（管理者がMCP allowlistを変更した場合） | `mcp__*` をManaged askにしています。現在はserverが0件なのでMCP toolは現れません。管理者が公式形式でallowlistを追加した場合もtool実行はpromptされます。[S3][S6] |
| 27 | Hooksを管理者管理だけに限定する | **完全対応**（今回のゼロHook基準） | `allowManagedHooksOnly: true` に加え `disableAllHooks: true` を設定するため、User / Project / PluginだけでなくManaged Hookも含めて現在は一切実行しません。[S2][S7] |
| 28 | 管理外Plugin / Skill / Agent / Hook / MCPを禁止する | **部分対応** | 新規sideload、command-source、User / Project customization、marketplace操作を強く制限します。ただし、ポリシー適用前から導入済みの非command pluginを全件wildcardでアンインストールまたは無効化する公式設定は確認できません。[S2] |
| 29 | Skill内Shell executionを禁止する | **完全対応**（User / Project / Plugin / additional-directory由来） | `disableSkillShellExecution: true` を使用します。さらにbundled skillsとworkflowsも停止します。Managed skillのShellはこのキーの対象外ですが、今回のserver-managed JSONではManaged skill自体を配布していません。[S2] |
| 30 | Remote Control、Artifact、Channel、background agent等の追加経路を閉じる | **完全対応**（対象機能） | `disableRemoteControl`、`disableArtifact`、`disableAgentView`、`channelsEnabled: false`、`allowedChannelPlugins: []`、`crossSessionInbound: "refuse"` を設定します。[S2] |
| 31 | Server-managed settings取得失敗時にFail-closedにする | **部分対応** | 一度 `forceRemoteSettingsRefresh: true` が取得・cacheされれば、以後はfresh fetch失敗時に起動終了します。**初回起動にはcacheも当該settingもないため、server-managed settingsだけでは初回からのFail-closedを保証できません。**[S5] |
| 32 | 企業Organization Loginを強制する | **部分対応** | policy取得後は `forceLoginMethod: "claudeai"` と `forceLoginOrgUUID` で制限します。しかしserver-managed settingsは企業Organizationへ認証済みのaccountに配信されるため、最初のloginをserver側JSONだけで誘導・強制できません。[S5][S8] |
| 33 | Claude Code Versionを固定する | **部分対応**（policy適用後は完全） | `requiredMinimumVersion` と `requiredMaximumVersion` を同じ `2.1.237` にしてexact pinします。ただし、これらのキーより古いclientは無視し、初回remote policy未取得期間も残ります。[S2][S5][S10] |
| 34 | settings.json自体をOSレベルのSecurity Boundaryにする | **settings.jsonのみでは対応不可** | Server-managed settingsはClaude Code clientが評価するclient-side controlです。cache改変、改変binary、古いclient、別Organization、third-party provider等の経路をOS権限なしでも回避できると公式が明記しています。[S5] |
| 35 | Claude Code本体の全runtime/config/cache書込みも `~/claude_work` 内だけにする | **settings.jsonのみでは対応不可** | 認証情報、remote settings cache、session data、runtime metadata等はWSL userのClaude Code設定領域へ保存されます。今回のWorkspace制御は主にClaudeのfile toolsとSandbox subprocessが対象です。[S2][S5][S8] |

### 結論

今回のJSONは、**現行公式仕様で安全に成立する範囲を最大化した「ゼロMCP・ゼロHook・ゼロPlugin追加・Web tool停止」の強化基準**です。  
管理者が許可した `example.com` / `api.example.com` への通信は、**ユーザーがBash実行を承認した後、Sandbox内のsubprocessからだけ**利用できます。`WebFetch` と `WebSearch` は使用しません。

---

## 2. 本番投入前に必ず置換・確認する値

1. `forceLoginOrgUUID` の `00000000-0000-4000-8000-000000000000` は、形式上有効なダミーUUIDです。**実際の企業Organization UUIDへ置換しない限り、正しいOrganizationへloginできません。**
2. `requiredMinimumVersion` / `requiredMaximumVersion` は、調査日時点の公式最新 **2.1.237** にexact pinしています。組織の検証済みversionを採用する場合は、2項目を同じ有効なSemVerへ同時に変更してください。
3. `example.com` と `api.example.com` は例です。実環境の承認済みDomainへ置換してください。ワイルドカードを使わないため、`example.com` は任意subdomainを許可しません。
4. Claude Codeは、**WSL2内で `cd ~/claude_work` を実行した状態から起動**してください。Managed settingsだけで初期CWDは固定できません。
5. このJSONはWSL2専用です。Native WindowsではSandboxが非対応であり、`failIfUnavailable: true` により起動できません。
6. WSL2ではbubblewrapとsocatが必須です。Windows InteropのUnix socket遮断には任意のseccomp filterも必要ですが、settings.jsonはその導入有無を必須化できません。[S4]

---

## 3. 本番投入用の有効なJSON

以下はコメント、末尾カンマ、JSON5記法を含まない有効なJSONです。同じ内容を別ファイル `settings.wsl2.enterprise.json` として添付しています。

```json
{
  "forceLoginMethod": "claudeai",
  "forceLoginOrgUUID": "00000000-0000-4000-8000-000000000000",
  "forceRemoteSettingsRefresh": true,
  "requiredMinimumVersion": "2.1.237",
  "requiredMaximumVersion": "2.1.237",
  "parentSettingsBehavior": "first-wins",
  "allowManagedPermissionRulesOnly": true,
  "allowManagedHooksOnly": true,
  "allowManagedMcpServersOnly": true,
  "allowedMcpServers": [],
  "disableClaudeAiConnectors": true,
  "disableSideloadFlags": true,
  "strictPluginOnlyCustomization": true,
  "strictKnownMarketplaces": [],
  "disableCommandPluginSources": true,
  "disableSkillShellExecution": true,
  "disableBundledSkills": true,
  "disableWorkflows": true,
  "disableAllHooks": true,
  "channelsEnabled": false,
  "allowedChannelPlugins": [],
  "disableRemoteControl": true,
  "disableArtifact": true,
  "disableAgentView": true,
  "crossSessionInbound": "refuse",
  "env": {
    "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB": "1"
  },
  "permissions": {
    "defaultMode": "default",
    "disableAutoMode": "disable",
    "disableBypassPermissionsMode": "disable",
    "allow": [
      "Read(~/claude_work/**)",
      "Cd(~/claude_work/**)"
    ],
    "ask": [
      "Edit(~/claude_work/**)",
      "Bash",
      "mcp__*"
    ],
    "deny": [
      "Read(//mnt/**)",
      "Edit(//mnt/**)",
      "PowerShell",
      "WebFetch",
      "WebSearch",
      "Bash(dangerouslyDisableSandbox:true)",
      "Bash(*.exe*)",
      "Bash(*sudo *)",
      "Bash(*su *)",
      "Bash(*doas *)",
      "Bash(*pkexec *)",
      "Bash(*mount *)",
      "Bash(*umount *)",
      "Bash(*nsenter *)",
      "Bash(*unshare *)"
    ]
  },
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "autoAllowBashIfSandboxed": false,
    "allowUnsandboxedCommands": false,
    "excludedCommands": [],
    "filesystem": {
      "disabled": false,
      "allowWrite": [
        "~/claude_work"
      ],
      "denyWrite": [
        "/mnt"
      ],
      "denyRead": [
        "~/",
        "/mnt"
      ],
      "allowRead": [
        "~/claude_work"
      ],
      "allowManagedReadPathsOnly": true
    },
    "network": {
      "allowedDomains": [
        "example.com",
        "api.example.com"
      ],
      "strictAllowlist": true,
      "allowManagedDomainsOnly": true,
      "allowAllUnixSockets": false
    },
    "enableWeakerNestedSandbox": false
  }
}
```

### このJSONが採用する安全側の方針

- 組み込み `WebFetch` / `WebSearch` は全面禁止。
- Web通信は、承認後のSandboxed Bashから管理Domainだけへ許可。
- MCPとHooksは、実環境の承認対象が提示されていないため0件許可。
- Plugin marketplaceは0件許可。
- Linux native `pwsh` はPowerShell toolではなく、Sandboxed Bashから起動。
- Windows executableは `.exe` を含むBash commandをdeny。
- Permissionの全体deny＋狭いallowという、評価順上成立しない構成は使用しない。
- WSL2のwrite pathに無効な `/mnt/*` 等のwildcardは使用しない。

---

## 4. 設定説明表

| 設定項目 | 設定値 | 目的 | なぜ必要か | 対応する要件 | 注意点・制約 |
|---|---|---|---|---|---|
| `forceLoginMethod` | `"claudeai"` | login方法をClaude.ai accountに限定します。 | Consoleや別のfirst-party login経路を既定にしないためです。 | 企業Organization Login | Server-managed settingsは最初のlogin後に届くため、初回loginの完全強制にはなりません。[S8] |
| `forceLoginOrgUUID` | ダミーUUID | 許可するClaude.ai Organizationを1つに固定します。 | 別OrganizationのClaude.ai credentialでの起動を拒否するためです。 | 企業Organization Login | 必ず実UUIDへ置換してください。Console credential、cloud provider、初回loginには公式上の例外があります。[S8] |
| `forceRemoteSettingsRefresh` | `true` | 起動時にremote policyのfresh fetchを必須にします。 | 古いcacheまたはpolicyなしで起動することを、2回目以降の起動で防ぐためです。 | Managed policy fail-closed | 最初のremote payloadを受け取る前には自己適用できません。[S5] |
| `requiredMinimumVersion` | `"2.1.237"` | 許可versionの下限です。 | 古いclientが新しいsecurity settingを理解しない状態を減らします。 | Version管理 | このsetting自体より古いclientは無視します。[S2] |
| `requiredMaximumVersion` | `"2.1.237"` | 許可versionの上限です。 | 未検証の自動update後versionを起動させないためです。 | Version管理 | 下限と同値のためexact pinです。Version更新時は2項目を同時変更します。[S2][S10] |
| `parentSettingsBehavior` | `"first-wins"` | SDK / IDE等の親processが渡すManaged設定を捨て、管理者tierだけを採用します。 | embedding hostからの追加policyで挙動が変わる範囲を減らすためです。 | Managed Policy保護 | CLI単体では通常影響しません。現行既定値でもあります。[S2] |
| `allowManagedPermissionRulesOnly` | `true` | User / ProjectのPermission ruleを無視します。 | `.claude/settings.json` 等から企業のallow/ask/denyを変更できなくする中心設定です。 | Permission policy固定 | `sandbox.allowWrite`、`excludedCommands`、`/add-dir` は別であり、このキーでは固定されません。[S3][S4] |
| `permissions.defaultMode` | `"default"` | CLI表示上のManual modeで開始します。 | 変更・command・外部toolを人が確認する運用の基礎です。 | Manual相当 | `default` は公式値です。`"manual"` aliasではなく正式な保存値を使用しています。[S3] |
| `permissions.disableAutoMode` | `"disable"` | Auto modeを選択・起動できなくします。 | classifierによる自動承認を企業policyで禁止するためです。 | Auto mode禁止 | booleanではなく文字列 `"disable"` が正式値です。[S2][S3] |
| `permissions.disableBypassPermissionsMode` | `"disable"` | bypass modeを利用不可にします。 | `--dangerously-skip-permissions` 等でpromptを飛ばす経路を閉じるためです。 | Permission bypass禁止 | 旧clientや改変clientは別問題です。[S2][S3] |
| `permissions.allow[Read]` | `Read(~/claude_work/**)` | Workspace内の通常Readを自動許可します。 | 日常のsource参照まで毎回promptすると実用性が大きく落ちるためです。 | Workspace内Read自動許可 | symlinkではlinkとtargetの両方が一致しなければallowにならず、promptへfallbackします。[S3] |
| `permissions.allow[Cd]` | `Cd(~/claude_work/**)` | `/cd` の行先をWorkspace内に限定します。 | session中に別Workspaceへ移動する誤操作を防ぐためです。 | `/cd`制限 | 1件のCd allowでallowlist modeになり、root自体と配下を許可します。[S3] |
| `permissions.ask[Edit]` | `Edit(~/claude_work/**)` | Workspace内のEdit / Write / Createを承認制にします。 | ファイル変更を自動実行させないためです。 | 変更・作成承認 | `Write(path)` は公式上評価されないため、`Edit(path)` を使います。[S3] |
| `permissions.ask[Bash]` | `Bash` | すべてのBash commandを承認制にします。 | read-only扱いのcommandも含め、企業環境では実行前に利用者へ見せるためです。 | Shell承認 | `autoAllowBashIfSandboxed: false` と必ず組み合わせます。[S3][S4] |
| `permissions.ask[mcp]` | `mcp__*` | すべてのMCP toolを承認制にします。 | 将来管理者がMCPを許可した場合にも自動実行させないためです。 | MCP Tool承認 | 現在の `allowedMcpServers: []` ではMCP tool自体が存在しません。[S3][S6] |
| `permissions.deny[Read/Edit /mnt]` | `Read(//mnt/**)` / `Edit(//mnt/**)` | Claude Code組み込みfile toolsから標準Windows mountを拒否します。 | Sandboxはbuilt-in Read/Editには直接適用されないため、Permission側にも必要です。 | Windows共有folder禁止 | Permission wildcardは有効です。Sandbox write側では別途具体パス `/mnt` を使用します。[S3][S4] |
| `permissions.deny[PowerShell]` | `PowerShell` | PowerShell toolをmodel contextから外します。 | Bash sandboxを通らない別Shell surfaceを作らないためです。 | PowerShell制御 | Linux native `pwsh` はBashから実行し、承認とSandboxを適用します。[S3][S4] |
| `permissions.deny[WebFetch/WebSearch]` | bare tool名 | 組み込みWeb toolを全面停止します。 | settings-onlyで厳密なallowlistと毎回承認を同時成立させられないため、安全側へ倒します。 | Web allowlist / WebSearch | 許可Domain通信はSandboxed Bashを使用します。[S3][S4] |
| `Bash(dangerouslyDisableSandbox:true)` | deny | Sandbox無効parameter付きBash callを拒否します。 | `allowUnsandboxedCommands: false` の防御をPermission側でも補強します。 | Sandbox bypass禁止 | parameter省略・別経路はsandbox setting側で処理します。[S3][S4] |
| `Bash(*.exe*)` | deny | command文字列に `.exe` を含む実行を拒否します。 | WSL2からWindows executableを直接起動する典型経路を塞ぐためです。 | `cmd.exe` / `powershell.exe`禁止 | 文字列matchのため、改名、wrapper、script、大小文字の変形等を完全識別できません。[S3][S4] |
| privilege / namespace系Bash deny | `sudo`、`su`、`doas`、`pkexec`、`mount`、`umount`、`nsenter`、`unshare` | 代表的な権限昇格・namespace操作を直接拒否します。 | Sandbox境界を変えようとする典型commandを早期拒否するためです。 | 権限昇格禁止 | 任意scriptの内部動作まではcommand文字列ルールで完全判別できません。[S3] |
| `allowManagedHooksOnly` | `true` | Hook sourceをManaged / SDK / Managedで強制enableされたpluginに限定します。 | User / Project Hookを読み込ませないためです。 | Hook管理 | 今回は `disableAllHooks: true` がさらに優先し、全Hookを止めます。[S2][S7] |
| `disableAllHooks` | `true` | Hook、custom status line、custom file suggestionを停止します。 | 実行内容が提示されていないHookをゼロにする安全な初期基準です。 | Hook管理 | Managed Hookも実行されません。承認済みHookを使う組織は別途policy変更が必要です。[S2][S7] |
| `allowManagedMcpServersOnly` | `true` | MCP allowlistをManaged sourceだけに限定します。 | User側allowlistでMCPを追加できなくするためです。 | MCP管理 | Userは定義を置けても、管理者allowlistに一致しなければ利用できません。[S2][S6] |
| `allowedMcpServers` | `[]` | MCP serverを0件許可します。 | 実際の承認済みserver情報がない状態で架空のserverを許可しないためです。 | MCP管理 | Server-managed settingsから `managed-mcp.json` 自体は配布できません。[S5][S6] |
| `disableClaudeAiConnectors` | `true` | Claude.ai connectorを自動取得・接続しません。 | local MCPを閉じてもcloud connectorが追加される経路を防ぐためです。 | MCP / 外部access | `--mcp-config` は別のため、sideloadとallowlistも併用します。[S2] |
| `disableSideloadFlags` | `true` | `--plugin-dir`、`--plugin-url`、`--agents`、`--mcp-config` を拒否します。 | 1sessionだけ管理policyを迂回するCLI flagを止めるためです。 | Plugin / Agent / MCP sideload禁止 | `type: "sdk"` のin-process MCPは公式例外です。空MCP allowlist等と併用します。[S2] |
| `strictPluginOnlyCustomization` | `true` | User / Project由来のskills、agents、hooks、MCPを無視します。 | repositoryへ置かれたcustomizationを管理外code実行源にしないためです。 | 管理外customization禁止 | plugin、bundled、Managed sourceは別です。下記設定でさらに縮小します。[S2] |
| `strictKnownMarketplaces` | `[]` | Marketplaceを0件許可します。 | 未審査pluginの追加・install・update・refreshを止めるためです。 | 管理外Plugin禁止 | 既導入pluginを全種類自動uninstallする設定ではありません。[S2] |
| `disableCommandPluginSources` | `true` | marketplaceのcommand source pluginを拒否し、既導入分もload停止します。 | install時に利用者端末上でcommandを実行するsourceを禁止するためです。 | Command Plugin Source制限 | Claude Code 2.1.229以降が必要です。Exact pinはこれを満たします。[S2] |
| `disableSkillShellExecution` | `true` | skill/custom command内のinline Shellを無効化します。 | prompt資産に埋め込まれた `!` commandを実行させないためです。 | Skill Shell禁止 | bundled / managed skillは対象外ですが、今回bundledも停止しManaged skillは未配布です。[S2] |
| `disableBundledSkills` | `true` | Claude Code同梱skill/workflowを除去します。 | 管理者が把握していない補助surfaceを最小化するためです。 | Plugin / Skill制御 | `/init` 等のbuilt-in commandそのものとは別です。[S2] |
| `disableWorkflows` | `true` | dynamic workflowとbundled workflow commandを停止します。 | 自動化surfaceを縮小するためです。 | Workflow禁止 | `disableBundledSkills` と一部重複しますが、明示的に停止します。[S2] |
| `channelsEnabled` / `allowedChannelPlugins` | `false` / `[]` | Channelとmessage push pluginを停止します。 | 外部からsessionへmessageを注入する経路を閉じるためです。 | 外部access / Plugin | `channelsEnabled: false` が主制御で、空配列は追加防御です。[S2] |
| `disableRemoteControl` | `true` | Remote Controlを停止します。 | remote clientからsessionを操作する経路を閉じるためです。 | 外部access | CLI flag、auto-start、session内toggleが対象です。[S2] |
| `disableArtifact` | `true` | session outputをclaude.ai private web pageへpublishするArtifact toolを停止します。 | 意図しない外部publishを防ぐためです。 | Web / 外部access | local file生成とは別機能です。[S2] |
| `disableAgentView` | `true` | background agent、`--bg`、`/background`、agent viewを停止します。 | 人の承認待ちが見えにくいunattended execution surfaceを減らすためです。 | 自動実行防止 | foreground subagent toolを全面禁止する設定ではありません。[S2] |
| `crossSessionInbound` | `"refuse"` | 他sessionからのinbound messageを破棄します。 | cross-sessionで作業内容・指示が混入する経路を閉じるためです。 | 外部access | 現行設定の最も厳しい値です。[S2] |
| `env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` | `"1"` | Anthropic / cloud provider credentialをsubprocess環境から除去します。 | commandやchild processへmodel/API credentialが渡る範囲を減らすためです。 | credential保護 | 任意の企業独自secretをすべて自動検出する設定ではありません。[S9] |
| `sandbox.enabled` | `true` | Bashとchild processをOS機構で隔離します。 | Permissionの文字列評価だけでなく、実際のprocessへfilesystem/network境界をかけるためです。 | Sandbox必須 | Native Windows / WSL1は非対応です。[S4] |
| `sandbox.failIfUnavailable` | `true` | 必須Sandbox初期化失敗時に起動を止めます。 | 警告だけ出してunsandboxed実行へfall backする既定動作を禁止するためです。 | Fail-closed Sandbox | 任意seccomp filterの欠落は必須依存失敗ではありません。[S4] |
| `sandbox.autoAllowBashIfSandboxed` | `false` | Sandboxed commandでもregular permission flowへ通します。 | Sandbox内だから安全として自動承認されないようにするためです。 | Sandbox内Bash承認 | 裸のBash askと併用します。[S4] |
| `sandbox.allowUnsandboxedCommands` | `false` | Sandbox違反後のunsandboxed retryを無効にします。 | `dangerouslyDisableSandbox` escape hatchを閉じるためです。 | Sandbox bypass禁止 | `excludedCommands` は別例外です。[S4] |
| `sandbox.excludedCommands` | `[]` | Managed policy自身はSandbox除外を0件にします。 | 管理者が意図的に例外を作っていないことを明確にするためです。 | Sandbox bypass禁止 | 配列は全scopeで結合され、Managed-only lockがないため完全固定できません。[S4] |
| `filesystem.disabled` | `false` | Filesystem isolationを有効のままにします。 | networkだけのSandboxへ弱体化させないためです。 | Filesystem制限 | Managedがfilesystemを構成している場合、lower scopeからのdisableは抑止されます。[S2][S4] |
| `filesystem.allowWrite` | `["~/claude_work"]` | Sandboxed processのWorkspace書込みを明示許可します。 | Workspaceでbuild/test/file変更を可能にするためです。 | Workspace write | WSL2 write listはwildcard不可のため具体directoryです。全scope配列結合のため、lower scopeは他pathを追加できます。[S2][S4] |
| `filesystem.denyWrite` | `["/mnt"]` | Sandboxed processによる標準Windows mount書込みを拒否します。 | `/mnt/c`、`/mnt/d` 等への変更を止めるためです。 | Windows共有folder write禁止 | `/mnt/*` は無効になるため、再帰prefixとして具体 `/mnt` を使います。[S2][S4] |
| `filesystem.denyRead` | `["~/", "/mnt"]` | Home全体とWindows mountをSandbox read拒否領域にします。 | credential/configやWindows host fileをchild processから隠すためです。 | Workspace外read / Windows共有folder | Linux system directoriesはcommand runtimeのため読取可能なままです。[S4] |
| `filesystem.allowRead` | `["~/claude_work"]` | 広いhome deny内でWorkspaceだけを再許可します。 | `denyRead: ["~/"]` と矛盾させず作業fileを読めるようにするためです。 | Workspace read | Readではより具体的なallowが広いdeny内を再開できます。[S2][S4] |
| `filesystem.allowManagedReadPathsOnly` | `true` | `allowRead` をManaged値だけに固定します。 | User / ProjectがSandbox read範囲を追加するのを止めるためです。 | Filesystem read policy固定 | `allowWrite` や `excludedCommands` 用の同等lockは公式にありません。[S2][S4] |
| `network.allowedDomains` | 2Domain | Sandboxed processのoutbound先を管理者Domainへ限定します。 | `curl`、`wget`、package manager等をallowlist化するためです。 | Network allowlist | exact hostnameです。その他のsubdomainは許可されません。[S4] |
| `network.strictAllowlist` | `true` | 未許可hostをpromptではなく直ちに拒否します。 | 利用者がその場でDomainを追加承認してpolicyを広げないためです。 | Network allowlist | **Sandboxed commandsだけ**が対象で、WebFetchは対象外です。[S2][S4] |
| `network.allowManagedDomainsOnly` | `true` | Domain sourceをManaged settingsだけに固定します。 | User / Project設定のDomain追加を無視するためです。 | Domain policy固定 | `deniedDomains` は全scopeから結合され、さらに狭めることはできます。[S2][S4] |
| `network.allowAllUnixSockets` | `false` | Sandbox内の任意Unix domain socket接続を許可しません。 | WSL2 Windows Interopやlocal daemonへのescape経路を減らすためです。 | Windows Interop / socket | WSL2では任意seccomp filterが実際のsocket blockに必要です。[S4] |
| `enableWeakerNestedSandbox` | `false` | 弱いnested sandboxを使いません。 | compatibilityのためにisolationを弱める設定を拒否するためです。 | Sandbox強度 | unprivileged container内などでは起動できない場合があります。[S2][S4] |

---

## 5. 最終的な動作確認表

> 「禁止」と記載していても、Server-managed settings自体がclient-side controlであるという全体制約は第6章に残ります。  
> 「条件付き」は、Managed policyが取得済みで、WSL2 Sandboxの必須依存があり、Claude Codeを `~/claude_work` から起動した場合です。

| 操作 | 最終動作 | 根拠・補足 |
|---|---|---|
| `~/claude_work` 内の通常Read | **自動許可（条件付き）** | Managed `Read` allow。symlink targetもWorkspace内である必要があります。 |
| `~/claude_work` 内のEdit | **ユーザー承認** | `Edit(~/claude_work/**)` ask。 |
| `~/claude_work` 内のWrite / 新規作成 | **ユーザー承認** | Write toolはEdit path ruleで評価され、Bash作成もBash ask。 |
| `~/claude_work` 内のDelete | **ユーザー承認** | 通常はBash `rm` 等としてBash ask。 |
| `~/claude_work` 外のRead | **settings.jsonだけでは完全保証不可** | `/mnt` とSandboxのhome denyは禁止。それ以外の組み込みReadはManual promptになり得ます。 |
| `~/claude_work` 外のEdit | **settings.jsonだけでは完全保証不可** | `/mnt` は禁止。その他は広いdeny＋狭いallowが成立しないため、直接toolではpromptが残ります。 |
| `~/claude_work` 外のWrite | **settings.jsonだけでは完全保証不可** | Sandbox subprocessは原則CWD/temporary/work allowだけですが、lower `allowWrite` と誤った初期CWDが残存します。 |
| `~/claude_work` 外への `/cd` | **禁止** | Cd allowlist mode。resolved targetがWorkspace外なら拒否。 |
| Bash / Linux Shell command | **ユーザー承認** | 裸のBash ask。 |
| Sandbox内Bash | **ユーザー承認** | `autoAllowBashIfSandboxed: false`。 |
| Windows `cmd.exe` | **禁止を優先／完全保証不可** | `.exe` Bash deny、`/mnt` deny、Unix socket deny。seccomp欠落やindirect wrapperは残存。 |
| Windows `powershell.exe` | **禁止を優先／完全保証不可** | 同上。PowerShell tool自体もbare deny。 |
| その他Windows `.exe` | **禁止を優先／完全保証不可** | `Bash(*.exe*)`。文字列に現れない間接実行までは保証不可。 |
| Linux native `pwsh` | **ユーザー承認** | `Bash(pwsh ...)` として実行しSandbox内へ。直接PowerShell toolは使用不可。 |
| 許可Domainへの `curl` / `wget` / package manager | **ユーザー承認** | Bash prompt後、Sandbox proxyが2Domainだけ許可。 |
| 未許可DomainへのSandboxed network | **禁止** | strict allowlistによりpromptなしで拒否。 |
| `WebFetch`：許可Domain | **禁止** | 厳密なdomain allowlist＋毎回承認をsettings-onlyで保証できないためfallbackとして全面deny。 |
| `WebFetch`：未許可Domain | **禁止** | Bare WebFetch deny。 |
| `WebSearch` | **禁止** | Domain specifierがないためbare deny。 |
| MCP Tool | **禁止（現在）** | MCP server allowlistが空。将来Managed serverを追加した場合は `mcp__*` ask。 |
| 管理外MCP | **禁止（対応client上）** | Empty allowlist、Managed-only、connector/sideload停止。 |
| 管理外Hook | **禁止** | `disableAllHooks: true`。 |
| Managed Hook | **禁止（現在）** | ゼロHook基準のためManaged Hookも止めています。 |
| 管理外Plugin / Skill | **禁止を優先／完全保証不可** | 新規追加とuser/project sourceは遮断。既導入の非command plugin全件停止は保証不可。 |
| Skill inline Shell | **禁止** | User / Project / Plugin / additional-directory skillが対象。 |
| Permission bypass | **禁止** | disableBypassPermissionsMode。 |
| Auto mode | **禁止** | disableAutoMode。 |
| Sandbox bypass parameter | **禁止** | allowUnsandboxedCommands false＋parameter deny。 |
| lower-scope `excludedCommands` | **settings.jsonだけでは完全保証不可** | 追加を禁止するManaged-only lockがありません。 |
| Remote Control / Artifact / Channel / background agent | **禁止** | 各disable/false/refuse setting。 |

---

## 6. settings.jsonだけでは完全に保証できない事項

### 6.1 初期Working Directory

Managed `settings.json` に、Claude Code起動時のCWDを `~/claude_work` へ固定する公式キーはありません。Sandboxは**実際のCWDを既定のwrite領域**として扱うため、別directoryから起動すると、そのdirectoryもSandboxのwrite対象になります。

したがって、次の前提が必要です。

> **Claude Codeを `~/claude_work` をCurrent Working Directoryとして起動することを運用上の前提とする。**

`Cd(~/claude_work/**)` は起動後の `/cd` を制限しますが、起動前のCWDを修正しません。また、`/add-dir`、`--add-dir`、`permissions.additionalDirectories` を全面禁止するManaged keyは現行公式仕様で確認できません。[S3]

### 6.2 Workspace外の組み込みRead/Edit/Write

Permission ruleは **deny → ask → allow** の順です。広い `Read(//**)` denyと狭いWorkspace allowを同時に置くと、Workspaceもdenyされます。Rule specificityでは覆せません。[S3]

このため、今回のJSONは次の多層構成です。

- Workspace内Readをallow。
- Workspace内Editをask。
- `/mnt` をRead/Edit deny。
- Sandboxed subprocessのhomeと`/mnt` readをdenyし、Workspaceを再allow。
- Workspace外の直接built-in toolはManual permission flowへ残す。

「Workspace外をユーザーが承認しても絶対に読めない」という保証はありません。

### 6.3 Sandbox write policyのlower-scope追加

`filesystem.allowWrite` はUser / Project / Managedの配列が結合されます。Read側には `allowManagedReadPathsOnly` がありますが、公式に同等の `allowManagedWritePathsOnly` は確認できません。したがってUser / Projectから別write pathを追加できる残存リスクがあります。[S2][S4]

`denyWrite: ["/mnt"]` は全scopeで結合され、`/mnt`に対する拒否自体は残りますが、別位置へのwrite追加を全面阻止できません。

### 6.4 `excludedCommands` によるSandbox例外

`excludedCommands` は空配列で配布しますが、全scopeから結合されます。公式Sandbox文書は、**Managed-only lockdownの同等設定がなく、developerがentryを追加できる**と明記しています。[S4]

追加されたcommandはSandbox外で実行され得るため、filesystem/network/Unix socket制限を迂回する可能性があります。裸のBash askにより人の承認は残りますが、企業policyとしての絶対拒否にはなりません。

### 6.5 Windows Host / Windows Network Resourceへの完全遮断

今回、標準 `/mnt`、`.exe` command、PowerShell tool、Unix socketを制限します。しかし次は完全保証できません。

- Windows driveやnetwork shareが `/mnt` 以外へmountされている。
- Windows executableが改名・wrapper・script経由で呼ばれる。
- optional seccomp filterがない。
- lower scopeの `excludedCommands` が利用される。
- 既存local service、socket、host bridgeが別経路を提供する。
- ユーザー自身がWSL/Windows側でresourceをmount・操作する。

settings.jsonはWSL設定、Windows Host ACL、Network drive、UNC認証を管理するOS policyではありません。

### 6.6 Windows Interopとoptional seccomp filter

公式文書によると、WSL2はWindows binary起動をUnix socket経由でHostへ渡します。`allowAllUnixSockets: false` だけでは、**optional seccomp filterがインストールされていない場合にsocketを最初からblockできません**。[S4]

`failIfUnavailable: true` はbubblewrapやsocat等の必須依存失敗には有効ですが、optional seccomp filterの未導入を理由に必ず起動失敗させる設定は確認できません。

### 6.7 WebFetchを「許可Domainだけ・毎回承認」にすること

`network.strictAllowlist` はSandboxed commandsだけに適用されます。`WebFetch` はClaude Code process内のtoolで、Sandbox network gateではなくPermission ruleに従います。[S4]

Permissionのdeny優先順位により、次の構成は成立しません。

```text
deny: WebFetch(domain:*)
ask: WebFetch(domain:example.com)
```

広いdenyが `example.com` にも勝つためです。逆に広いdenyを置かなければ、未許可Domainを利用者がpromptで承認できる余地が残ります。したがって本案はWebFetchを全面禁止します。

### 6.8 WebSearchのDomain限定

公式Permission syntaxには `WebFetch(domain:...)` はありますが、`WebSearch(domain:...)` は確認できません。このためWebSearchを特定Domainだけへ限定するJSONは作成していません。Bare `WebSearch` denyを使用します。[S3]

### 6.9 初回起動時のremote policy Fail-closed

初回起動はcacheがなく、server-managed settingsを非同期取得します。取得失敗時はpolicyなしで継続し、取得まで短い未強制windowがあります。`forceRemoteSettingsRefresh` は一度取得・cacheされた後は自己維持しますが、最初のpayload以前には存在しません。[S5]

したがって、**組織設定画面のJSONだけでは初回からFail-closedを保証できません。**

### 6.10 初回Organization Login

Server-managed settingsは、Organization OAuth loginまたは対象credentialで認証された後に取得されます。そのため `forceLoginMethod` / `forceLoginOrgUUID` をserver-managedだけに置いても、最初のlogin画面を企業Organizationへ強制することはできません。[S5][S8]

また、公式認証文書にはConsole login、setup-token、cloud provider、profile/federation credential等の差異・例外が明記されています。

### 6.11 Claude Code Versionの完全固定

現行clientではmin/maxを同値にしてexact pinできます。ただし以下はsettings-onlyの完全保証外です。

- Version settingを知らない古いclientは無視する。
- Server-managed settingsを取得しない古いclientはpolicy全体を適用しない。
- 初回policy取得前のwindow。
- 改変client。
- 別Organization / third-party providerでserver-managed delivery自体を回避。

このJSONでは現行公式最新2.1.237をpinしていますが、展開時には組織の検証済みversionへ更新してください。[S2][S5][S10]

### 6.12 Plugin / Skillの既存導入状態

`strictKnownMarketplaces: []` はmarketplace追加とplugin install/update/refreshをblockし、`disableCommandPluginSources` はcommand-source pluginのloadも停止します。しかし、policy適用前に導入済みの**非command source plugin全件を名前不問でuninstallまたはdisableするglobal wildcard setting**は公式文書で確認できません。[S2]

### 6.13 Claude Code自身のruntime/config/cache

SandboxはBash subprocessを対象とし、built-in file toolsはPermissionを使います。Claude Code本体は認証情報、remote policy cache、session data等を`~/.claude`等へ保存します。これらをすべて `~/claude_work` 内へ固定するManaged keyは確認できません。[S4][S5][S8]

### 6.14 Domain allowlistのSecurity Boundary

Sandbox proxyはhostnameでallowlistを評価し、既定ではTLSをterminate/inspectしません。許可したDomainがredirect/proxy/API relay機能を提供する場合、そのDomain経由の内容までJSONが理解して制限するわけではありません。[S4]

### 6.15 Server-managed settings自体

公式文書はServer-managed settingsを**client-side controlでありsecurity boundaryではない**と明記しています。Cache削除・改変、modified binary、old client、別Organization、third-party provider等の回避可能性があります。[S5]

---

## 7. PermissionとSandboxの評価ロジック

### 7.1 Permission ruleの順序

1. `deny`
2. `ask`
3. `allow`

この順に最初に一致した結果が採用されます。詳細度の高いallowでも、広いdenyを上書きしません。[S3]

今回、次のような見た目だけ安全な設定は使用していません。

```text
deny: Read(//**)
allow: Read(~/claude_work/**)
```

### 7.2 Sandboxと組み込みToolの違い

| Layer | 主な対象 | 今回の役割 |
|---|---|---|
| Permission | Bash、Read、Edit、WebFetch、MCP等のtool call前 | 自動許可、prompt、拒否を決定 |
| Sandbox filesystem/network | Bashとそのchild process | 実行中processへOS-level filesystem/network境界を適用 |
| WSL2 / Host OS | mount、Interop、socket、Windows resource | settings.jsonだけでは全面管理不可 |

Sandboxを有効にしても、built-in `Read` / `Edit` / `Write` が自動的にSandbox内へ入るわけではありません。両layerを設定する必要があります。[S3][S4]

### 7.3 Symlink

- Read/Edit allowは、symlink pathとtargetの両方がallowに一致したときだけ自動許可。
- Read/Edit denyは、pathまたはtargetのどちらかがdenyに一致すれば拒否。
- Cdはresolved targetと各symlink hopを評価。
- Sandboxは実際のprocess accessをfilesystem boundaryで拒否。

このため、`~/claude_work/link -> /mnt/c/...` はPermissionとSandboxの双方で拒否される設計です。[S3][S4]

---

## 8. WSL2固有の注意事項

### 8.1 Write pathのWildcard

Linux / WSL2の `sandbox.filesystem.allowWrite` / `denyWrite` では、`*`、`?`、`[` を含むentryはskipされ、効果がありません。Read側 `allowRead` / `denyRead` はwildcardを利用できます。[S2][S4]

今回のSandbox write設定は次のように具体pathだけを使用します。

```json
{
  "allowWrite": ["~/claude_work"],
  "denyWrite": ["/mnt"]
}
```

`/mnt` はdirectory prefixとして子孫を含むため、`/mnt/c`、`/mnt/d` 等を覆います。

### 8.2 必須・任意依存

- 必須: bubblewrap、socat等。欠落時は `failIfUnavailable: true` で起動停止。
- 任意: seccomp filter。Unix socket blockを強化し、WSL2 Windows Interop対策に重要。
- Native Windows: Sandbox非対応。
- WSL1: Sandbox非対応。

### 8.3 Temporary directory

SandboxはCWDに加えてsession temporary directoryを既定でwrite可能にします。これはtoolがtemporary fileを作るための仕様であり、settings.jsonで「Workspaceだけが唯一のwrite先」と厳密にはできません。[S4]

---

## 9. 導入・動作確認チェックリスト

- [ ] `forceLoginOrgUUID` を実Organization UUIDへ置換した。
- [ ] Exact pinする組織承認versionを決め、min/maxを同時に設定した。
- [ ] Domain allowlistを実際の承認済みhostnameへ置換した。
- [ ] WSL distributionがWSL2であり、`~/claude_work` がLinux filesystem上にある。
- [ ] `/mnt/c/Users/.../claude_work` をWorkspaceとして使っていない。
- [ ] `~/claude_work` をCWDとしてClaude Codeを起動した。
- [ ] `/status` で `Enterprise managed settings (remote)` を確認した。
- [ ] `/permissions` でManaged ruleだけが有効であることを確認した。
- [ ] `/sandbox` のDependenciesで必須componentとoptional seccomp filterを確認した。
- [ ] `/sandbox` のConfigでresolved read/write/network pathを確認した。
- [ ] `claude doctor` または `/doctor` でschemaからstripされたfieldがないことを確認した。
- [ ] `~/claude_work` のReadがpromptなしで成功する。
- [ ] `~/claude_work` のEdit/Create/Deleteがpromptされる。
- [ ] `/cd ~`、`/cd /mnt/c` が拒否される。
- [ ] built-in Readで `/mnt/c/...` が拒否される。
- [ ] Sandboxed Bashで `/mnt/c/...` のread/writeが拒否される。
- [ ] Bash commandがSandbox内でもpromptされる。
- [ ] `curl` で許可Domainだけが到達し、未許可Domainがpromptなしで拒否される。
- [ ] `WebFetch` と `WebSearch` がtool contextから除外されている。
- [ ] `cmd.exe` / `powershell.exe` の直接Bash callがdenyされる。
- [ ] optional seccomp filterがない端末を「Windows Interop完全遮断」と判定していない。
- [ ] User / Projectの `sandbox.excludedCommands` と `allowWrite` を残存リスクとして受容・監視している。
- [ ] 初回起動・初回loginにはserver-managed-onlyの未強制windowがあることを導入判定で承認した。

---

## 10. 公式参照資料

すべてAnthropic / Claude Code公式ドキュメントです。日本語版で未反映または説明が少ない新しいsettingについては、同じ公式サイトの現行英語版を優先しました。

- **[S1]** [Claude Codeの設定（日本語）](https://code.claude.com/docs/ja/settings)
- **[S2]** [Claude Code settings（英語・現行詳細）](https://code.claude.com/docs/en/settings)
- **[S3]** [Configure permissions](https://code.claude.com/docs/en/permissions)
- **[S4]** [Configure the sandboxed Bash tool](https://code.claude.com/docs/en/sandboxing)
- **[S5]** [Configure server-managed settings](https://code.claude.com/docs/en/server-managed-settings)
- **[S6]** [Managed MCP configuration](https://code.claude.com/docs/en/mcp)
- **[S7]** [Hooks](https://code.claude.com/docs/en/hooks)
- **[S8]** [Authentication](https://code.claude.com/docs/en/authentication)
- **[S9]** [Environment variables](https://code.claude.com/docs/en/env-vars)
- **[S10]** [Claude Code changelog](https://code.claude.com/docs/en/changelog)

---

## 11. JSON検証結果

- UTF-8 JSONとしてparse成功。
- コメントなし。
- 末尾カンマなし。
- JSON5構文なし。
- WSL2 write listにwildcardなし。
- Permission ruleとSandbox path syntaxを区別。
- `Write(path)` 等、公式が「受理しても評価しない」と明記するpath ruleは不使用。
- 調査日時点の公式settings / permissions / sandboxing referenceに存在するkeyだけを使用。

SHA-256（添付JSON）: `a9cf69d46ed52e8037e9417a72048b776d9807e52734086b2cea3a879e58cab2`
