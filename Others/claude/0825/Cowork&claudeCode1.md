# 結論

Claude Desktopを企業管理する際は、**「CoworkはGPO、Claude Codeはsettings.json」だけで二分するのではなく、次の3層で統制する**のが最適です。

```text
1. 組織・IDレイヤー
   ├─ Cowork／Claude Codeの利用資格
   ├─ クラウド実行、承認モード、コネクタ
   └─ カスタムロール、組織固定

2. Windows端末レイヤー
   ├─ HKLM\SOFTWARE\Policies\Claude
   │    └─ Claude Desktop／Cowork／機能表示
   └─ HKLM\SOFTWARE\Policies\ClaudeCode
        └─ Claude Codeランタイムのポリシー

3. 通信・監査レイヤー
   ├─ Tenant Restrictions
   ├─ ネットワーク送信先制御
   └─ OpenTelemetry／Compliance API
```

重要なのは、**同じClaude Desktopの中に存在していても、CoworkとClaude Codeは別々のポリシー名前空間と設定評価機構を使う**ことです。したがって、1つのGPOや1つのJSONだけですべてを管理しようとしてはいけません。 ([Anthropic Help Center][1])

また、前提を正確に補足すると、次のようになります。

* CoworkはGPOだけでなく、組織設定、カスタムロール、クラウド実行設定、承認設定でも制御する。
* Claude Codeは組織の管理された設定だけでなく、WindowsのHKLMレジストリを使った端末管理もできる。
* Claude Codeの組織管理設定と端末管理設定は、原則としてマージされない。
* ユーザーの通常の`settings.json`は、企業の強制設定には使用しない。

---

# 1. 制御対象と最適な管理ポイント

| 制御対象                           | 主となる制御                       | Windows側の制御                     | 推奨               |
| ------------------------------ | ---------------------------- | ------------------------------- | ---------------- |
| Coworkを利用できるユーザー               | 組織設定、カスタムロール                 | `secureVmFeaturesEnabled`       | 組織と端末の両方で許可      |
| Coworkで開けるフォルダ                 | ―                            | `allowedWorkspaceFolders`       | 専用作業フォルダだけ許可     |
| CoworkのローカルMCP                 | ―                            | `isLocalDevMcpEnabled`          | 原則無効             |
| Desktop Extension              | 組織側カタログ／許可リスト                | `isDesktopExtensionEnabled`等    | 未承認拡張は無効         |
| Coworkのクラウド実行                  | Cowork組織設定                   | ―                               | 初期導入では無効を推奨      |
| Coworkの自動承認                    | Cowork組織設定                   | ―                               | 原則無効             |
| Claude Codeの表示・利用              | 組織ロール                        | `isClaudeCodeForDesktopEnabled` | 組織と端末の両方で許可      |
| Claude Codeのコマンド、ファイル、MCP、Hook | Claude Code管理された設定           | `HKLM\...\ClaudeCode\Settings`  | 後述のいずれかを主ポリシーにする |
| 個人アカウント利用の防止                   | Tenant Restrictions          | `forceLoginOrgUUID`             | 両方を併用            |
| 操作監査                           | OpenTelemetry、Compliance API | EDR、Windowsログ                   | OTelを中心に設計       |

Coworkの組織設定では、Cowork自体の有効・無効、クラウド実行、自動承認、コネクタツールの永続的な許可、プラグインカタログなどを管理できます。Enterpriseではグループやカスタムロールによる利用者の限定も可能です。したがって、**CoworkをGPOだけで統制するのは不十分**です。 ([Anthropic Help Center][2])

---

# 2. 2つのWindowsポリシーは別物

## 2.1 Claude Desktop／Cowork用

```text
HKLM\SOFTWARE\Policies\Claude
```

ここでは、Claude Desktopアプリ全体とCoworkの端末機能を制御します。

主な値は次のとおりです。

| 値                                    | 用途                                     |
| ------------------------------------ | -------------------------------------- |
| `forceLoginOrgUUID`                  | 指定組織のアカウントだけでログインさせる                   |
| `secureVmFeaturesEnabled`            | Cowork機能を端末上で有効・無効にする                  |
| `allowedWorkspaceFolders`            | Coworkにマウントできるフォルダを制限する                |
| `isClaudeCodeForDesktopEnabled`      | Desktop内のClaude Codeを有効・無効にする          |
| `isLocalDevMcpEnabled`               | ローカル開発MCPを有効・無効にする                     |
| `isDesktopExtensionEnabled`          | Desktop Extension自体を有効・無効にする           |
| `isDesktopExtensionDirectoryEnabled` | 拡張機能ディレクトリを有効・無効にする                    |
| `disableAutoUpdates`                 | アプリの自動更新を無効にする                         |
| `autoUpdaterEnforcementHours`        | 更新適用までの猶予時間を制御する                       |
| `effortLevel`                        | Desktop内Claude Codeセッションの既定effortを設定する |

`HKLM`と`HKCU`の両方に設定がある場合は、`HKLM`が優先されます。企業統制では必ず`HKLM`を使用し、`HKCU`を強制ポリシーとして扱わないでください。 ([Anthropic Help Center][1])

なお、`effortLevel`はClaude Codeセッションの既定値を指定する機能であり、ファイルアクセスやコマンド実行を制限するセキュリティポリシーではありません。

## 2.2 Claude Codeランタイム用

```text
HKLM\SOFTWARE\Policies\ClaudeCode
```

このキーの下に、`Settings`という`REG_SZ`または`REG_EXPAND_SZ`値を作り、JSONを格納します。

```text
HKLM\SOFTWARE\Policies\ClaudeCode
  └─ Settings = "{ ...Claude Code managed settings JSON... }"
```

このポリシーは、Claude Codeの次のような挙動を管理します。

* ファイルの読み書き
* Bash／PowerShell等のツール利用
* 権限ルール
* 権限バイパスモード
* MCPサーバー
* Hooks
* プラグイン／マーケットプレイス
* Sandbox
* 利用可能なモデル
* WSL設定

Claude CodeのWindows端末ポリシーは、CLIだけでなく、Claude Desktop内のClaude Code、VS Code、JetBrains等から実行されるClaude Codeにも適用されます。 ([Claude][3])

---

# 3. Claude Codeの設定優先順位に最も注意する

Claude Codeの管理設定は、概ね次の順序で評価されます。

```text
優先度 高

1. 組織設定の「管理された設定」
   Server-managed settings

2. HKLM\SOFTWARE\Policies\ClaudeCode\Settings
   Windows端末のGPO／MDMポリシー

3. C:\Program Files\ClaudeCode\managed-settings.json

4. HKCU\SOFTWARE\Policies\ClaudeCode\Settings

優先度 低
```

ここで最も重要なのは、**これらが通常は加算・マージされない**ことです。

例えば、組織の管理された設定に1つでも有効なポリシーキーが配信されている場合、Claude Codeは原則として組織側を選択し、下位のHKLMポリシーを追加適用しません。

したがって、次のような設計は誤りです。

```text
組織設定：
  権限バイパスを禁止

HKLM：
  MCPを禁止
  Secretsフォルダを禁止
  プラグインを禁止

期待：
  すべてが合算される

実際：
  組織設定だけが選択され、
  HKLM側の大部分が適用されない可能性がある
```

Claude Codeでは、**選択された1つの管理ソースに必要なポリシーをすべて記述する**必要があります。一部の機械固有設定やクロスソース例外はありますが、それを前提にポリシーを分割しない方が安全です。 ([Claude][4])

---

# 4. この案件で推奨するClaude Codeの管理方式

## パターンA：ローカルの管理Windows端末だけで使う場合

今回のように、主として管理されたWindows PC上のClaude DesktopからClaude Codeを使用し、ユーザーや端末グループごとに設定を変えたい場合は、次の構成が適します。

```text
主ポリシー：
HKLM\SOFTWARE\Policies\ClaudeCode\Settings

配布：
Active Directory GPO、Intune、その他MDM

組織のClaude Code管理された設定：
空にする、または配信しない
```

この方式の利点は、次のとおりです。

* HKLMなので一般ユーザーによる変更が困難
* ADグループや端末OU単位で異なる設定を配布できる
* ネットワーク切断中でもポリシーを適用できる
* 初回起動時から端末ポリシーを適用できる
* GPO／Intuneの変更管理プロセスに組み込める

ただし、ローカル管理者権限を持つユーザーはHKLMを変更できるため、必要に応じてローカル管理者権限の制限やWDAC／AppLocker等も併用します。

## パターンB：クラウドセッション、CLI、IDEを含めて同一ポリシーにする場合

Claude Codeのクラウドセッションを使用する、またはDesktop、CLI、IDE等をまたいで同一の組織ポリシーを適用する場合は、次の構成を推奨します。

```text
主ポリシー：
組織設定
  ＞ Claude Code
  ＞ 管理された設定

端末側：
同じ内容の完全なポリシーを
HKLM\SOFTWARE\Policies\ClaudeCode\Settings
にもフォールバックとして配布
```

組織側設定は起動時に取得され、その後定期的に更新されます。クラウドセッションには端末のHKLMポリシーが届かないため、クラウドを使用するならサーバー管理設定が必要です。 ([Claude][4])

この場合も、サーバー設定とHKLMを別々の役割に分けてはいけません。**両方に同じ完全な基本ポリシーを配置し、通常時はサーバー設定、取得不能時は端末設定という形**にします。

## 可用性重視か、フェイルクローズか

Claude Codeには`forceRemoteSettingsRefresh`があります。

### 可用性重視

* サーバー設定をキャッシュして使用する
* 通信障害時にもClaude Codeを起動できる
* HKLMポリシーをフォールバックにする
* `forceRemoteSettingsRefresh`は使わない

### コンプライアンス重視

* HKLM側で`forceRemoteSettingsRefresh: true`を設定
* 起動時に最新のリモートポリシーを取得できなければClaude Codeを起動させない
* ポリシー取得障害時は開発作業も停止する

金融、重要インフラ、規制対象データなど、古いポリシーでの動作を許容できない場合はフェイルクローズが候補になります。ただし、Anthropic側または社内ネットワークの障害が業務停止につながるため、リスク判断が必要です。 ([Claude][4])

---

# 5. 推奨するCoworkの組織設定

初期導入時は、次の設定を推奨します。

## 利用者

Coworkは全社一括有効化ではなく、Enterpriseのカスタムロールまたはグループを使い、パイロットユーザーだけに付与します。

```text
例：
Claude-Cowork-Users
Claude-Code-Users
Claude-Cowork-Cloud-Users
Claude-Extension-Users
```

組織側の権限とWindows GPOのセキュリティフィルターを同じグループ体系にすると、運用が分かりやすくなります。Coworkの組織全体スイッチが上位のマスタースイッチになり、その下でカスタムロールによる利用資格を管理できます。 ([Anthropic Help Center][2])

## クラウド実行

初期段階では「Run Cowork in cloud」を無効にし、ローカルセッションで監査・リスク評価を行ってから限定的に解放することを推奨します。

クラウド実行を有効にする場合は、次を別途決定します。

* 外部ネットワークへの送信先
* Web Search／Web Fetchの利用可否
* コネクタの利用可否
* MCPの利用可否
* Claude in Chromeの利用可否
* クラウドセッションで扱ってよいデータ区分

Coworkの組織ネットワークポリシーは重要ですが、Web Search、Web Fetch、MCP、Claude in Chrome等のすべてを同じ設定だけで制御できるわけではないため、各機能を個別に管理する必要があります。 ([Anthropic Help Center][5])

## 承認モード

推奨初期値は次のとおりです。

| 設定                               | 推奨        |
| -------------------------------- | --------- |
| Auto approval mode               | 無効        |
| Always allow for connector tools | 無効        |
| Skip approval相当の高権限動作            | 使用させない    |
| 書き込み系コネクタ                        | 毎タスク承認    |
| ファイル削除・上書き                       | ユーザー承認を要求 |

Coworkはマウントされたフォルダ内のファイルを読み取り、書き込み、削除できるため、専用作業フォルダ、バックアップ、承認モードを組み合わせる必要があります。 ([Anthropic Help Center][6])

---

# 6. Windows GPOの推奨値

## 全端末に適用するベースラインGPO

```text
GPO名：
GPO-Claude-Desktop-Baseline

適用対象：
Claude Desktopがインストールされた全社端末
```

推奨値：

| レジストリ値                               |        種類 |                推奨データ |
| ------------------------------------ | --------: | -------------------: |
| `forceLoginOrgUUID`                  |    REG_SZ | 企業のOrganization UUID |
| `isLocalDevMcpEnabled`               | REG_DWORD |                  `0` |
| `isDesktopExtensionEnabled`          | REG_DWORD |                  `0` |
| `isDesktopExtensionDirectoryEnabled` | REG_DWORD |                  `0` |
| `secureVmFeaturesEnabled`            | REG_DWORD |                  `0` |
| `isClaudeCodeForDesktopEnabled`      | REG_DWORD |                  `0` |

このベースラインでは、Cowork、Claude Code、ローカルMCP、未承認Extensionを一旦無効化します。

## Cowork許可端末向けGPO

```text
GPO名：
GPO-Claude-Cowork-Enable
```

上書きする値：

| レジストリ値                    |        種類 |  推奨データ |
| ------------------------- | --------: | -----: |
| `secureVmFeaturesEnabled` | REG_DWORD |    `1` |
| `allowedWorkspaceFolders` |    REG_SZ | JSON配列 |

例：

```json
[
  "C:\\Company\\ClaudeWork",
  "D:\\ApprovedProjects"
]
```

次のような広すぎるパスは避けます。

```text
C:\
C:\Users
C:\Users\<user>
ユーザープロファイル全体
社内ファイルサーバーのルート
```

Coworkには、専用の作業ルートを用意するのが安全です。

```text
C:\Company\ClaudeWork
```

そのフォルダに対して、NTFSアクセス権、DLP、バックアップ、ランサムウェア対策等を適用します。

## Claude Code許可端末向けGPO

```text
GPO名：
GPO-Claude-Code-Enable
```

上書きする値：

| レジストリ値                          |        種類 | データ |
| ------------------------------- | --------: | --: |
| `isClaudeCodeForDesktopEnabled` | REG_DWORD | `1` |

ただし、これはDesktop内にClaude Codeを表示・利用可能にする機能ゲートです。Claude Codeの細かい実行制御は、`HKLM\SOFTWARE\Policies\ClaudeCode\Settings`または組織の管理された設定で行います。 ([Anthropic Help Center][1])

### Extensionを許可する場合の注意

会社が承認したExtensionを許可リスト方式で利用する場合、次の値を`0`にしてはいけません。

```text
isDesktopExtensionEnabled
isDesktopExtensionDirectoryEnabled
```

端末ポリシーでExtension自体を無効化すると、アプリ側のExtension許可リストよりも端末ポリシーが優先されます。

その場合は次の構成にします。

```text
Extension機能：有効
組織カタログ：承認済みExtensionだけ登録
サイドロード：禁止
ローカル開発MCP：無効
```

([Anthropic Help Center][1])

---

# 7. GPO相当のPowerShell設定例

次はパイロット端末での検証用例です。本番ではGPO Registry PreferencesまたはIntuneで同じ値を配布する方が管理しやすくなります。

```powershell
$desktopPolicy = 'HKLM:\SOFTWARE\Policies\Claude'

New-Item -Path $desktopPolicy -Force | Out-Null

# 指定した企業組織にログイン先を固定
New-ItemProperty `
    -Path $desktopPolicy `
    -Name 'forceLoginOrgUUID' `
    -PropertyType String `
    -Value '<ORGANIZATION_UUID>' `
    -Force | Out-Null

# Coworkで利用可能な作業フォルダ
$allowedFolders = ConvertTo-Json -InputObject @(
    'C:\Company\ClaudeWork',
    'D:\ApprovedProjects'
) -Compress

New-ItemProperty `
    -Path $desktopPolicy `
    -Name 'allowedWorkspaceFolders' `
    -PropertyType String `
    -Value $allowedFolders `
    -Force | Out-Null

# Coworkを有効化
New-ItemProperty `
    -Path $desktopPolicy `
    -Name 'secureVmFeaturesEnabled' `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

# Desktop内Claude Codeを有効化
New-ItemProperty `
    -Path $desktopPolicy `
    -Name 'isClaudeCodeForDesktopEnabled' `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

# ローカル開発MCPを禁止
New-ItemProperty `
    -Path $desktopPolicy `
    -Name 'isLocalDevMcpEnabled' `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

# Desktop Extensionを禁止
New-ItemProperty `
    -Path $desktopPolicy `
    -Name 'isDesktopExtensionEnabled' `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

New-ItemProperty `
    -Path $desktopPolicy `
    -Name 'isDesktopExtensionDirectoryEnabled' `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null
```

これらは`HKLM\SOFTWARE\Policies\Claude`に格納されるClaude Desktop用のポリシーです。 ([Anthropic Help Center][1])

---

# 8. Claude Codeの推奨ポリシー例

最初は、権限バイパスの禁止と、管理者が定義した権限ルールだけを利用させる構成から開始するのが安全です。

```json
{
  "forceLoginOrgUUID": "<ORGANIZATION_UUID>",
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)"
    ],
    "disableBypassPermissionsMode": "disable"
  },
  "allowManagedPermissionRulesOnly": true
}
```

このJSONは、次のいずれか一方を主な配布先にします。

### 組織から配布

```text
組織設定
  ＞ Claude Code
  ＞ 管理された設定
```

### Windows GPO／Intuneから配布

```text
HKLM\SOFTWARE\Policies\ClaudeCode
  Value name: Settings
  Type: REG_SZ
  Data: 上記JSON
```

端末レジストリへ書き込むPowerShell例：

```powershell
$codePolicyPath = 'HKLM:\SOFTWARE\Policies\ClaudeCode'

$codePolicy = @{
    forceLoginOrgUUID = '<ORGANIZATION_UUID>'

    permissions = @{
        deny = @(
            'Read(./.env)',
            'Read(./.env.*)',
            'Read(./secrets/**)'
        )

        disableBypassPermissionsMode = 'disable'
    }

    allowManagedPermissionRulesOnly = $true
}

$codePolicyJson = $codePolicy |
    ConvertTo-Json -Depth 20 -Compress

New-Item -Path $codePolicyPath -Force | Out-Null

New-ItemProperty `
    -Path $codePolicyPath `
    -Name 'Settings' `
    -PropertyType String `
    -Value $codePolicyJson `
    -Force | Out-Null
```

本番では、次の設定もリスク評価後に追加します。

* `allowManagedMcpServersOnly`
* `allowedMcpServers`
* `allowManagedHooksOnly`
* `strictKnownMarketplaces`
* `strictPluginOnlyCustomization`
* `disableSideloadFlags`
* Sandbox関連ロック
* 利用可能モデルの制限
* 環境変数の制限
* Web Fetch／Web Searchの権限制御

これらは強力な設定なので、空のMCP許可リストやマーケットプレイス許可リストを配布すると、既存開発環境を一括で停止させる可能性があります。パイロット環境での動作確認が必要です。 ([Claude][3])

---

# 9. `settings.json`という言葉の整理

Claude Codeには、似た名前の設定が複数あります。

| 種類           | 例                                                   | 企業の強制力       |
| ------------ | --------------------------------------------------- | ------------ |
| ユーザー設定       | `~/.claude/settings.json`                           | 弱い。ユーザーが変更可能 |
| プロジェクト設定     | `.claude/settings.json`                             | 弱い。リポジトリ管理   |
| ローカルプロジェクト設定 | `.claude/settings.local.json`                       | 弱い           |
| 端末管理ファイル     | `C:\Program Files\ClaudeCode\managed-settings.json` | 管理設定         |
| Windowsポリシー  | `HKLM\...\ClaudeCode\Settings`                      | 強い           |
| 組織の管理された設定   | 管理コンソール上のJSON                                       | 最優先の管理設定     |

組織設定の画面に入力するJSONは、`settings.json`互換のスキーマを使用しますが、ローカルにある通常の`settings.json`ファイルを配るものではありません。

企業統制では、次を強制ポリシーとして利用しないでください。

```text
%USERPROFILE%\.claude\settings.json
プロジェクト内の .claude\settings.json
```

ユーザーまたはプロジェクトが編集できるためです。 ([Claude][7])

---

# 10. 組織ごとの設定差が必要な場合

Claude Codeのサーバー管理設定は、基本的に組織全体で共通です。現時点では、Coworkのカスタムロールのように、同一組織内でグループごとに異なる管理JSONを簡単に配信する用途には制約があります。 ([Claude][4])

例えば次のような要件です。

```text
一般開発者：
  読み取り中心
  MCP禁止
  本番環境接続禁止

SRE：
  一部運用コマンド許可
  社内MCP許可

セキュリティ担当：
  ログ解析ツール許可
  別のモデルを許可
```

この場合は、次のいずれかが必要です。

1. ローカルセッションだけを対象に、GPO／IntuneのHKLMポリシーをグループ別に配布する。
2. サーバー管理設定を空にし、端末ポリシーを主ポリシーとする。
3. IdPグループ単位の設定配信に対応したClaude Apps Gateway等を利用する。
4. クラウドセッションを使うグループには、共通の最小ポリシーだけを適用する。

非空のサーバー管理設定を置いたまま、下位のHKLMにグループ別追加ルールを配置する方法は、原則として機能しません。

---

# 11. WSLを使用する場合

Windows上のClaude CodeがWSL内で動作する構成では、Windowsの管理設定をWSLへ継承させるため、次の設定を検討します。

```json
{
  "wslInheritsWindowsSettings": true
}
```

ただし、これは通常のサーバー管理設定ではなく、Windows側のHKLMポリシーまたはProgram Files側の管理設定に置くべき機械固有設定です。

WSLを許可しない場合は、次も併せて実施します。

* DesktopでWSL実行を選択させない
* Windows機能、実行ファイル、開発環境側で制限
* WDAC／AppLocker等で未承認ランタイムを制限

Claude Code管理設定だけでは、端末上の別のAIツール、APIクライアント、シェル、スクリプトを一括で制御できません。 ([Claude][8])

---

# 12. ログと監査

Coworkのローカル処理は分離されたVM内で動くため、一般的なEDRだけではVM内部の詳細なファイル操作やツール実行を完全には把握できません。クラウドセッションについても端末EDRの監視外です。 ([Anthropic Help Center][5])

そのため、Enterprise導入ではOpenTelemetryの設定を強く推奨します。

取得対象には、次の情報が含まれ得ます。

* ユーザープロンプト
* ツール呼び出し
* MCP呼び出し
* パラメータと結果
* ファイルアクセスパス
* Skills／Plugins
* 承認または拒否の判断
* モデル、トークン、コスト
* エラー情報

OpenTelemetryにはプロンプト本文が含まれる可能性があるため、SIEMへ無条件に全量転送するのではなく、次を設計します。

* 機密情報のマスキング
* SIEM閲覧者の限定
* 保存期間
* データ所在地
* 個人情報・顧客情報の取り扱い
* インシデント調査時の参照手順

([Anthropic Help Center][9])

---

# 13. 個人アカウント利用を防止する

`forceLoginOrgUUID`はClaude Desktop上のログイン先を制限するために有効ですが、端末上のアプリ設定だけに依存するべきではありません。

企業のプロキシやセキュアWebゲートウェイでTenant Restrictionsを構成すると、Claude Web、Desktop、APIキー、OAuth等について、承認された組織以外の利用をネットワーク側から制限できます。 ([Anthropic Help Center][10])

推奨する多層構成は次です。

```text
第1層：forceLoginOrgUUID
第2層：Tenant Restrictions
第3層：SSO／IdPのユーザー管理
第4層：端末証明書／Managed Device判定
第5層：プロキシ、DNS、Firewall
```

これにより、ユーザーが個人アカウントへ切り替える、古いクライアントを利用する、別のClaude利用経路を使う、といった回避を抑制できます。

---

# 14. インストールと更新管理

WindowsでCoworkを完全に利用するためには、Claude DesktopのMSIX配布に加えて、Virtual Machine Platform等のWindows機能が必要になります。企業配布ではIntune、SCCM、GPO、PowerShell等を使い、端末単位のプロビジョニングを行います。 ([Anthropic Help Center][11])

更新については、管理主体を二重化しないことが重要です。

## Intune等でバージョンを固定する場合

```text
disableAutoUpdates = 1
```

* Intune／SCCMが更新を配布
* 事前検証後にリング展開
* Claude Desktop自身の自動更新は停止

## Claude Desktopの自動更新を利用する場合

```text
disableAutoUpdatesは未設定
```

* Claude Desktop自身が更新
* 必要に応じて`autoUpdaterEnforcementHours`を設定
* Intune側で別バージョンを上書き配布しない

「アプリが自動更新しつつ、Intuneも別タイミングで更新する」構成は避けます。

---

# 15. 動作確認手順

## Windowsポリシー確認

```powershell
reg query "HKLM\SOFTWARE\Policies\Claude"
reg query "HKLM\SOFTWARE\Policies\ClaudeCode"
```

GPOの適用確認：

```powershell
gpresult /h C:\Temp\claude-gpresult.html
```

## Cowork確認

1. 指定組織以外でログインできないこと。
2. 未許可ユーザーにはCoworkが表示されないこと。
3. 許可フォルダ以外をマウントできないこと。
4. ローカルMCPが起動できないこと。
5. 未承認Extensionを追加できないこと。
6. 自動承認モードが表示されないこと。
7. 書き込み系コネクタで毎回承認を求められること。
8. OTelにテストイベントが到達すること。

## Claude Code確認

Claude Codeセッションで次を確認します。

```text
/status
```

選択された管理ソースが、設計どおり次のいずれかになっていることを確認します。

```text
remote
HKLM
managed-settings file
```

さらに、次を確認します。

```text
/permissions
claude doctor
```

* `disableBypassPermissionsMode`が適用されている
* deny対象ファイルを読めない
* 未承認MCPを追加できない
* 未承認Hook／Pluginを追加できない
* クラウドセッションにも同じ制約がある
* ポリシー取得不能時の挙動が設計どおりである

Claude Codeの端末管理設定は定期的に再評価され、サーバー管理設定も定期更新されますが、セッション開始時に評価される設定もあるため、ポリシーテストではClaude DesktopとClaude Codeセッションを再起動します。 ([Claude][3])

---

# 16. 避けるべき設計

特に次の構成は避けてください。

1. **CoworkはGPOだけで管理する**
   クラウド実行、自動承認、コネクタ、利用資格等を管理できません。

2. **Claude Codeのサーバー設定とHKLMを分割して書く**
   原則マージされないため、下位設定が無視されます。

3. **通常の`settings.json`を企業ポリシーとして配布する**
   ユーザーまたはリポジトリが変更できます。

4. **HKCUに強制設定を書く**
   ユーザー自身が変更できます。

5. **Coworkにユーザープロファイル全体を許可する**
   メール添付、認証情報、ブラウザデータ、同期フォルダ等への影響範囲が大きくなります。

6. **Extensionを無効化しながら許可リストを設定する**
   端末側の無効化が優先され、承認済みExtensionも使えません。

7. **クラウドセッションを許可しながらHKLMだけで制御する**
   クラウドセッションには端末ポリシーが届きません。

8. **OTelを有効化せずEDRだけに依存する**
   Cowork VM内部やクラウド実行の可視性が不足します。

9. **自動承認を全社既定で有効にする**
   ファイル書き込み、削除、コネクタ操作のリスクが高くなります。

10. **開発者が任意の旧バージョンや別インストーラーを実行できる**
    ポリシーを解釈しない、または古いクライアントによる回避経路になり得ます。Claude Codeのクライアント側制御は、未管理端末上では絶対的なセキュリティ境界にはなりません。 ([Claude][4])

---

# 最終推奨構成

本案件では、次の構成を推奨します。

## 全社共通

* Enterprise SSO／ユーザー管理
* Tenant Restrictions
* `forceLoginOrgUUID`
* Claude DesktopのMSIX管理配布
* 更新管理主体をIntuneまたはClaude自動更新のどちらかに統一
* OpenTelemetryとCompliance API
* 未承認Extension、ローカルMCPを既定で無効

## Cowork

* 組織設定をマスタースイッチにする
* カスタムロールで利用者を限定
* GPOの`secureVmFeaturesEnabled`で利用端末を限定
* `allowedWorkspaceFolders`で専用作業フォルダだけ許可
* クラウド実行は初期無効
* Auto approvalは無効
* コネクタのAlways allowは無効
* OTelで操作を監査

## Claude Code

* Desktop上の表示は`isClaudeCodeForDesktopEnabled`で制御
* 実行制御はClaude Code専用のmanaged settingsで実施
* ローカルPC限定・グループ別設定が必要ならHKLMを主ポリシーにする
* クラウド／複数クライアントを含むなら組織管理設定を主ポリシーにする
* サーバーとHKLMを併用する場合は、同一の完全な基本ポリシーを配置する
* サーバーとHKLMがマージされる前提で分割しない
* 権限バイパス、未管理MCP、Hook、Plugin、サイドロードを制限する

したがって、今回の最適解は、**「Cowork用GPO」と「Claude Code用settings.json」の二つだけではなく、`組織設定＋HKLM\Policies\Claude＋HKLM\Policies\ClaudeCode＋ネットワーク／監査`を組み合わせる多層統制**です。これにより、同一のClaude Desktopアプリに含まれるCoworkとClaude Codeを、それぞれの制御機構に合わせて一貫して管理できます。

[1]: https://support.claude.com/ja/articles/12622667-claude-desktop%E3%81%AE%E3%82%A8%E3%83%B3%E3%82%BF%E3%83%BC%E3%83%97%E3%83%A9%E3%82%A4%E3%82%BA%E6%A7%8B%E6%88%90 "Claude Desktopのエンタープライズ構成 | Anthropicヘルプセンター"
[2]: https://support.claude.com/ja/articles/13455879-team-%E3%83%97%E3%83%A9%E3%83%B3%E3%81%A8-enterprise-%E3%83%97%E3%83%A9%E3%83%B3%E3%81%A7-claude-cowork-%E3%82%92%E4%BD%BF%E7%94%A8%E3%81%99%E3%82%8B "Team プランと Enterprise プランで Claude Cowork を使用する | Anthropicヘルプセンター"
[3]: https://code.claude.com/docs/en/managed-settings "Deploy managed settings - Claude Code Docs"
[4]: https://code.claude.com/docs/en/server-managed-settings "Configure server-managed settings - Claude Code Docs"
[5]: https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview "Claude Cowork architecture overview | Anthropic Help Center"
[6]: https://support.claude.com/en/articles/13364135-use-claude-cowork-safely "Use Claude Cowork safely | Anthropic Help Center"
[7]: https://code.claude.com/docs/en/settings "Claude Code settings - Claude Code Docs"
[8]: https://code.claude.com/docs/en/admin-setup "Set up Claude Code for your organization - Claude Code Docs"
[9]: https://support.claude.com/en/articles/14477985-monitor-claude-cowork-activity-with-opentelemetry "Monitor Claude Cowork activity with OpenTelemetry | Anthropic Help Center"
[10]: https://support.claude.com/ja/articles/13198485-%E3%83%86%E3%83%8A%E3%83%B3%E3%83%88%E5%88%B6%E9%99%90%E3%81%AB%E3%82%88%E3%82%8B%E3%83%8D%E3%83%83%E3%83%88%E3%83%AF%E3%83%BC%E3%82%AF%E3%83%AC%E3%83%99%E3%83%AB%E3%81%AE%E3%82%A2%E3%82%AF%E3%82%BB%E3%82%B9%E5%88%B6%E5%BE%A1%E3%81%AE%E5%AE%9F%E6%96%BD?utm_source=chatgpt.com "テナント制限によるネットワークレベルのアクセス制御の実施"
[11]: https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows "Deploy Claude Desktop for Windows | Anthropic Help Center"
