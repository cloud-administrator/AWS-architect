# 結論

提示された要件は、**Coworkの公開されている管理機能だけでは完全には実現できません**。

次の部分は実現できます。

* Coworkに登録できるローカルWorkspaceを、Windows上の特定フォルダに限定する
* Auto modeを組織設定で無効化する
* Connector／Remote MCPを「毎回承認」または「禁止」にする
* ローカルMCPとDesktop ExtensionをGPOで無効化する
* コード実行環境のネットワーク通信を無効化または限定する
* Web SearchとClaude in Chromeを無効化する

一方、次の要件は現時点の公開仕様では完全に強制できません。

* Workspace外のファイルを、アップロードやProject経由も含めて一切参照できないようにする
* ファイル変更・作成やコマンド実行を、必ず1操作ごとに承認させる
* Windowsローカルセッションで「Skip all approvals」を確実に非表示・使用禁止にする
* CoworkのHooksを、管理者配布のものだけに限定する
* 1つのドメイン許可リストを、コード実行、Web Search、Web Fetch、Chrome、MCPの全経路に共通適用する

したがって、**一般業務用Windows PC上で、提示要件をそのまま満たす構成は不可**です。要件を緩和できない場合は、Cowork専用のWindows VDI／Cloud PCを用意するか、その利用者にはCoworkを提供しない判断が必要です。

---

# 要件別の実現可否

| 要件                             |               判定 | 評価                                                                    |
| ------------------------------ | ---------------: | --------------------------------------------------------------------- |
| `claude_work`だけをWorkspaceとして登録 |           **可能** | `allowedWorkspaceFolders`で登録可能なフォルダを限定できる                             |
| UNCパスやマップドライブをWorkspaceに登録させない |           **可能** | 許可リストをローカルパスだけにすれば、Coworkのフォルダ登録機能からは除外できる                            |
| Workspace外のファイルを参照もできなくする      |           **不可** | ファイルアップロード、Project knowledge、Connector等の別経路が残る                        |
| Workspace内の読み取りだけ承認不要          |         **概ね可能** | フォルダを接続すると、内部のファイル読み取りは通常その権限範囲内で行われる                                 |
| 編集・作成・削除を必ずユーザー承認              |         **一部可能** | Manual modeで承認を求められるが、Claude Codeのようなパス別・操作別ポリシーではない                  |
| ファイル削除を必ず承認                    |           **可能** | 恒久的なファイル削除は、モードにかかわらず明示承認が必要                                          |
| コマンドを必ず1コマンドごとに承認              |           **不可** | Anthropic自身が、個々のコマンドすべてを検証できる前提ではないと説明している                            |
| Auto mode禁止                    |           **可能** | 組織設定でモード自体を非表示にできる                                                    |
| Permission bypass禁止            |          **未保証** | Coworkでは相当機能が`Skip all approvals`。ローカルWindowsセッションでの管理者無効化は公開仕様上明確でない |
| Webを管理者許可ドメインだけに限定             |         **一部可能** | コード実行とChromeは個別に制御可能だが、Web Search／Fetch、MCPは同じ許可リストの対象外               |
| MCPを管理者管理に限定                   |        **可能に近い** | ローカルMCPを停止し、Remote MCPをOwner追加＋RBACのNeeds approvalに限定する               |
| Hooksを管理者管理に限定                 |           **未達** | ユーザーの個人プラグイン経由でHooksを持ち込める経路が公開仕様上残る                                  |
| 権限昇格禁止                         | **Cowork単体では不可** | Windows標準ユーザー、App Control、ACL等のOS制御が必要                                |

---

# 1. `claude_work`だけをWorkspaceにする設定

WindowsのClaude Desktopでは、次のポリシーを使用します。

```text
HKLM\SOFTWARE\Policies\Claude
```

設定例：

```text
Value name: allowedWorkspaceFolders
Type:       REG_SZ
Data:       ["C:\\ClaudeWork"]
```

`allowedWorkspaceFolders`は、CoworkにマウントできるファイルパスのJSON配列です。未設定時は制限なしです。企業管理ではユーザーが変更できる`HKCU`ではなく、優先度の高い`HKLM`を使用します。([Anthropic Help Center][1])

## `~/claude_work`ではなく`C:\ClaudeWork`を推奨

Windowsでは、次のような表記は使用しない方が安全です。

```text
~/claude_work
%USERPROFILE%\claude_work
C:\Users\*\claude_work
C:\Users\**\claude_work
```

公開仕様では、ワイルドカード、`~`、環境変数展開への対応が記載されていません。したがって、これは公開仕様からの判断ですが、**固定された絶対パスを指定する**べきです。

```text
C:\ClaudeWork
```

端末ごとに利用者固有のパスが必要な場合は、Intuneの端末割当スクリプト等で実際のパスを解決したうえで、展開済みの絶対パスをレジストリへ書き込みます。ただし、複数ユーザーが同じ端末を利用する構成では管理が複雑になるため、Cowork用端末は1ユーザー1端末または専用VDIが適しています。

## 推奨GPO

```powershell
$policyPath = 'HKLM:\SOFTWARE\Policies\Claude'

New-Item -Path $policyPath -Force | Out-Null

New-ItemProperty `
    -Path $policyPath `
    -Name 'allowedWorkspaceFolders' `
    -PropertyType String `
    -Value '["C:\\ClaudeWork"]' `
    -Force | Out-Null

New-ItemProperty `
    -Path $policyPath `
    -Name 'secureVmFeaturesEnabled' `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

New-ItemProperty `
    -Path $policyPath `
    -Name 'isLocalDevMcpEnabled' `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

New-ItemProperty `
    -Path $policyPath `
    -Name 'isDesktopExtensionEnabled' `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

New-ItemProperty `
    -Path $policyPath `
    -Name 'isDesktopExtensionDirectoryEnabled' `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

# Coworkだけを使用し、Desktop内Claude Codeを停止する場合
New-ItemProperty `
    -Path $policyPath `
    -Name 'isClaudeCodeForDesktopEnabled' `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

# 企業Organizationにログイン先を固定
New-ItemProperty `
    -Path $policyPath `
    -Name 'forceLoginOrgUUID' `
    -PropertyType String `
    -Value '<ORGANIZATION_UUID>' `
    -Force | Out-Null
```

Cowork、Desktop内Claude Code、ローカルMCP、Desktop Extensionはそれぞれ別のポリシーで制御できます。([Anthropic Help Center][1])

---

# 2. Windows共有フォルダへのアクセス禁止

## Coworkのファイルツールに限れば制限できる

`allowedWorkspaceFolders`を次の1パスだけにすれば、Coworkの通常のフォルダ接続画面からは、次の場所をWorkspaceとして登録できない構成にできます。

```text
\\fileserver\share
Z:\
C:\Users\<user>\Downloads
C:\Users\<user>\OneDrive
C:\
```

Coworkの通常のファイル読み書きは、ユーザーが接続したフォルダに限定されます。ローカルセッションでは、ファイル読み書きはWindows上のClaude Desktop側で実行され、接続フォルダのルールはアプリケーション層で評価されます。一方、シェルコマンドとClaudeが生成したコードはHyper-V上の専用Linux VMで実行されます。([Anthropic Help Center][2])

## ただし「Workspace外を一切参照できない」保証にはならない

`allowedWorkspaceFolders`が制限するのは、あくまで**Coworkへ接続できるフォルダ**です。Claudeには一般のファイルアップロード機能があり、ユーザーは端末上のファイルを選択、ドラッグ＆ドロップ、クリップボード貼り付けで追加できます。また、CoworkのProjectsは独自のファイル、リンク、指示、メモリを保持でき、Project作成自体を管理者が禁止する設定も公開されていません。([Anthropic Help Center][3])

例えば、次の操作を防げない可能性があります。

```text
1. ユーザーが \\fileserver\share\confidential.xlsx を選択
2. Claudeへファイルとしてアップロード
3. Coworkがそのファイルを参照
```

したがって、要件が次のレベルであれば、`allowedWorkspaceFolders`だけでは不足します。

> `C:\ClaudeWork`以外のファイルは、フォルダ接続だけでなく、手動アップロードやProjectへの追加も禁止する。

公開されているCowork管理設定には、任意のファイルアップロードをWorkspace配下だけに制限する設定がありません。

## 厳格にする場合のWindows側構成

Cowork専用のWindows VDI／Cloud PCを用意し、OSレベルで次の状態にします。

```text
C:\ClaudeWork              利用可能
Windows共有フォルダ         利用不可
マップドライブ              なし
OneDrive同期フォルダ         なし
業務ファイル                 端末内に配置しない
ローカル管理者権限           なし
```

さらに、専用端末で業務上問題がなければ、Windows Firewallまたは上位FirewallでSMB通信を遮断します。

```text
Outbound TCP 445：Block
```

Windows FirewallはGPOでアウトバウンドポートルールやプログラムルールを配布できます。Microsoftも、インターネット向けのSMB 445を遮断することを推奨しています。ただし、TCP 445を社内宛ても含めて全面遮断すると、通常のファイル共有、Azure Files、一部のWindows管理機能に影響するため、一般業務端末ではなくCowork専用VDIでの適用が適しています。([Microsoft Learn][4])

### Windows ACL

`C:\ClaudeWork`はローカルNTFSフォルダにし、次の主体だけに権限を付与します。

```text
SYSTEM
Administrators
対象利用者
```

他のユーザーにはアクセスを付与しません。Windowsのアクセス制御では、ファイルやフォルダに対してユーザーまたはグループ単位のNTFS権限を設定できます。([Microsoft Learn][5])

また、次のような迂回経路を受入試験で確認する必要があります。

```text
C:\ClaudeWork\link → C:\Users\<user>\Documents
C:\ClaudeWork\share → \\fileserver\share
```

つまり、Workspace内にジャンクション、シンボリックリンク、その他のreparse pointを作り、外部へ到達できないことを確認します。

---

# 3. ファイル操作とコマンドの承認

## Auto modeは禁止できる

組織設定で次を無効化します。

```text
Organization settings
  > Cowork
  > Permissions
  > Allow "Automatically approve" mode
    = OFF
```

無効にすると、Auto modeは利用者のモード選択画面に表示されなくなります。([Anthropic Help Center][6])

## Connectorの永続承認も禁止する

次も無効にします。

```text
Organization settings
  > Cowork
  > Permissions
  > Allow "Always allow" for connector tools
    = OFF
```

これにより、書き込み可能なConnectorツールについて「すべてのタスクで許可」が使用できなくなり、保存済みのAlways allow設定も無視されます。読み取り専用と正しく注釈されたConnectorツールだけは例外です。([Anthropic Help Center][6])

さらに、Enterpriseカスタムロールで各Connectorまたは各ツールを次のどちらかにします。

```text
Needs approval
Blocked
```

`Needs approval`では、Connectorの各呼び出しについて利用者が確認し、`Always allow`は選択できません。複数ロールに所属すると最も許可的な権限が適用されるため、対象ユーザーに不要な追加ロールを付与しないことが重要です。([Anthropic Help Center][7])

## ファイル操作はClaude Codeのように定義できない

Coworkには、Claude Codeの次のような管理ルールはありません。

```json
{
  "permissions": {
    "allow": [
      "Read(C:\\ClaudeWork\\**)"
    ],
    "ask": [
      "Write(C:\\ClaudeWork\\**)",
      "Edit(C:\\ClaudeWork\\**)"
    ],
    "deny": [
      "Read(C:\\**)"
    ]
  }
}
```

つまり、次のポリシーを管理者が明示的に定義する仕組みではありません。

```text
Read(C:\ClaudeWork\**)  = 自動許可
Write(C:\ClaudeWork\**) = 毎回確認
Read(それ以外)          = 拒否
```

CoworkのManual modeは、実行するアクションについてClaudeが一時停止して承認を求めるモードですが、Claude Codeのパス別・ツール別の許可ルールとは異なります。ファイルの恒久削除は、どのモードでも明示承認が必要です。([Anthropic Help Center][8])

## 1コマンドごとの承認は保証できない

Anthropicの安全ガイドは、Coworkが実行するコードやコマンドについて、利用者が個々のコマンドをすべて検証できることを期待すべきではないと明記しています。したがって、次の要件はCoworkでは満たせません。

> PowerShellやシェルコマンドを、必ず1コマンドごとに表示し、利用者が承認した場合だけ実行する。

([Anthropic Help Center][9])

また、WindowsローカルCoworkの標準シェルは、Windowsホスト上のPowerShellではなく、Hyper-V上のLinux VM内で実行されます。Windowsホスト上でのPowerShell実行を防止する必要がある場合は、Cowork設定ではなく、App Control for Business、PowerShellポリシー、標準ユーザー化で制御します。App Controlはアプリケーションだけでなく、スクリプト、MSI、バッチファイル、PowerShellにも適用できます。([Anthropic Help Center][2])

**1コマンドごとの承認が絶対要件なら、コマンド実行自体を無効化するか、Coworkを使用対象外にする必要があります。**

---

# 4. Permission bypass／Skip all approvals

Coworkでは、Claude Codeの`Permission bypass`に相当するものが`Skip all approvals`です。

```text
Manual
Auto
Skip
```

SkipではClaudeは承認を求めず、安全性の自動チェックも実行されません。Autoとは別のモードです。([Anthropic Help Center][8])

公開されているTeam／Enterprise管理手順では、次の設定は明示されています。

* Auto modeを無効化する設定
* ConnectorのAlways allowを無効化する設定

一方、**WindowsのローカルCoworkセッションについて、Skip modeを組織管理者が確実に非表示・禁止する設定は、公開管理手順では確認できません**。最新のアーキテクチャ文書には、クラウドセッションについて「利用者がper-call approvalなしでセッションを実行できるか制御する」との記述がありますが、その設定名やローカルセッションへの適用は明確ではありません。([Anthropic Help Center][6])

したがって、次の扱いが適切です。

```text
クラウドCowork：
  実テナントでSkip禁止設定を確認

WindowsローカルCowork：
  公開仕様上は要件未達として扱う
```

導入判断前に、Anthropicのアカウントチームから次の点を書面で確認する必要があります。

```text
1. Skip all approvalsを組織単位で無効化できるか
2. その設定はWindowsローカルセッションにも適用されるか
3. 管理設定を利用者が変更できないか
4. Manual modeを組織既定ではなく強制できるか
```

受入試験では、Autoだけでなく、**Skipもモード選択画面から消えていること**を合格条件にしてください。

---

# 5. インターネットアクセス制御

Coworkには複数の外部通信経路があります。

```text
1. コード実行環境からのネットワーク通信
2. Web Search
3. Web Fetch
4. Claude in Chrome
5. Remote MCP／Connectors
6. ローカルMCP／Desktop Extension
```

これらは1つの許可リストでは管理できません。

## コード実行環境

`Organization settings > Capabilities > Code execution`では、次の選択肢があります。

```text
ネットワーク通信なし
パッケージマネージャーのみ
パッケージマネージャー＋指定ドメイン
全ドメイン
```

最も厳格な設定は次です。

```text
Allow network egress = OFF
```

指定ドメインを許可するモードは「指定ドメインだけ」ではなく、npm、PyPI、GitHub等の承認済みパッケージマネージャーへのアクセスも含みます。そのため、会社が明示した数個のドメイン以外を完全に禁止したい要件には適合しない可能性があります。([Anthropic Help Center][10])

## Web Search／Web Fetch

コード実行環境のネットワーク許可リストは、Web Search、Web Fetch、MCP、Claude in Chromeには適用されません。Web Searchを有効にすると、提示されたURLを取得するWeb Fetchも利用可能になります。([Anthropic Help Center][6])

したがって、厳格構成では次のようにします。

```text
Organization settings
  > Capabilities
  > Web Search
    = OFF
```

これにより、組み込みのWeb Search／Web Fetch経路を停止します。

## Claude in Chrome

Claude in Chromeには、別の組織単位の許可リストと拒否リストがあります。

```text
Organization settings
  > Claude in Chrome
```

管理者は機能全体を無効化するか、アクセス可能なWebサイトをallowlistで限定できます。([Anthropic Help Center][11])

厳格な初期構成では次を推奨します。

```text
Claude in Chrome = OFF
```

Webブラウザー操作が業務上必要になった場合だけ、別途限定グループに対して有効化し、サイトallowlistを設定します。

## MCP

Remote MCPは端末から接続するのではなく、Anthropicのクラウド基盤から接続します。そのため、Windows端末上のFirewallやProxyだけでは制御できません。Team／Enterpriseでは、Remote MCPのカスタムConnectorを組織へ追加できるのはOwnerです。([Anthropic Help Center][12])

厳格構成は次です。

```text
ローカルMCP              OFF
Desktop Extension       OFF
全Remote MCP            Blocked
承認済みRemote MCPだけ   Needs approval
```

## 許可ドメインだけWebアクセスさせる最適構成

管理者が許可したドメインだけにアクセスさせ、かつ毎回承認させる必要がある場合、次の構成が最も明確です。

```text
組み込みWeb Search／Fetch   OFF
Claude in Chrome            OFF
コード実行ネットワーク       OFF
一般のMCP                   Blocked

管理者運営Web Gateway MCP   Needs approval
```

Web Gateway MCP側で、次をサーバー側実装します。

```text
許可ドメインリスト
DNS再解決チェック
リダイレクト先の再検査
private / loopback / link-local IP拒否
HTTPメソッド制限
レスポンスサイズ制限
監査ログ
```

この方式なら、CoworkからのWebアクセスを1つの管理されたRemote MCPへ集約し、Custom Roleの`Needs approval`によって呼び出しごとの承認を要求できます。

---

# 6. MCPを管理者管理に限定する方法

MCPについては、次の組み合わせでかなり厳格に制御できます。

## Windows GPO

```text
isLocalDevMcpEnabled = 0
isDesktopExtensionEnabled = 0
isDesktopExtensionDirectoryEnabled = 0
```

`isLocalDevMcpEnabled=false`は、ローカル設定およびプラグインに含まれるローカルMCPサーバーを無効化します。`isDesktopExtensionEnabled=false`はMCPB／DXT形式のDesktop Extensionサーバーを停止します。([Anthropic Help Center][2])

## 組織設定

Remote MCPについては、Ownerが組織へ追加したConnectorだけを対象にし、カスタムロールで次を設定します。

```text
All connectors = Blocked

Approved-Web-Gateway
  fetch = Needs approval

Approved-Internal-System
  read  = Needs approval
  write = Blocked
```

Remote MCPは端末のローカルネットワークではなくAnthropicクラウドから接続されるため、MCPサーバー側でもAnthropic接続元、認証、ユーザー権限、監査を構成します。([Anthropic Help Center][12])

---

# 7. Hooksを管理者管理に限定できるか

## 結論：公開仕様だけでは保証できない

CoworkのプラグインにはHooksとSub-agentsを含めることができ、HooksはCoworkで実行されます。([Anthropic Help Center][13])

組織管理者は、組織Marketplace上のプラグインについて次を設定できます。

```text
Required
Installed by default
Available
Not available
```

しかし、ユーザー向けドキュメントでは、利用者自身が次の操作を行えるとされています。

* カスタムプラグインファイルのアップロード
* 個人プラグインMarketplaceの追加
* Git／GitHub URLからのMarketplace追加

([Anthropic Help Center][13])

また、EnterpriseのSkill／Plugin scanningは、HooksとMCPサーバー自体をスキャンしません。([Anthropic Help Center][14])

したがって、組織Marketplaceだけを管理しても、次の保証にはなりません。

> 実行されるHooksは、管理者が配布したHooksだけである。

## Hooksが不要な場合

最も安全なのは、Hooksを含むプラグイン機能を利用させないことです。

```text
Organization settings
  > Skills
  > User-created skills
    = OFF

個人向けSkill共有
    = OFF

組織Plugin Marketplace
    = すべて削除またはNot available

ローカルMCP
    = OFF

Desktop Extension
    = OFF
```

プラグイン利用にはCoworkとSkillsの両方が必要です。ユーザー作成Skillsは組織設定で禁止できます。([Anthropic Help Center][15])

ただし、Skillsを無効化した際に、既存の個人プラグインやHooksが完全に動作不能になることを公開仕様だけで断定できません。実テナントで次を確認します。

```text
Customize > Plugins が利用できない
Upload custom plugin が表示されない
Personal plugins が表示されない
Add marketplace が表示されない
既存の個人Pluginが実行されない
```

## 管理者配布Hooksを使用したい場合

管理者配布Hooksを使いながら、個人Plugin Hooksだけを禁止する要件については、Anthropicに次を確認する必要があります。

```text
個人プラグインアップロードを組織単位で禁止できるか
個人Marketplace追加を組織単位で禁止できるか
管理者配布プラグインだけを実行可能にできるか
Hooksの実行元をOTel／Compliance APIで識別できるか
```

なお、Enterpriseの「Inference Hooks」は別機能です。これはOwner／Primary Ownerが管理し、プロンプト、ツール応答、アップロードファイル本文をClaudeへ到達する前に検査する中央管理型のコンプライアンス機能ですが、プラグインHooksの管理元制限やWindowsファイルアクセス制御の代替ではありません。([Anthropic Help Center][16])

---

# 8. 推奨する厳格構成

## Claude組織設定

```text
Cowork
  Enable for organization                  ON
  Run Cowork in the cloud                  OFF
  Allow "Automatically approve" mode       OFF
  Allow "Always allow" connector tools     OFF

Capabilities
  Code execution network egress            OFF
  Web Search                               OFF

Claude in Chrome
  Enable for organization                  OFF

Connectors
  Default                                  Blocked
  Approved remote MCP                      Needs approval

Skills
  User-created skills                      OFF
  Skill sharing                            OFF
  Share with organization                  OFF
  Share with groups                        OFF

Plugins
  Default marketplaces                     Remove
  Organization plugins                     Not available
```

現在のCoworkはクラウドセッションが中心ですが、既存Desktop展開ではローカルセッションも利用できます。Windowsでローカルだけを使用する場合は、`Run Cowork in the cloud`を明示的にOFFにし、クラウドで実行されるScheduled tasks等も利用対象外にします。Enterpriseではクラウド実行は既定OFFです。([Anthropic Help Center][6])

## Windows GPO

```text
HKLM\SOFTWARE\Policies\Claude

allowedWorkspaceFolders                  ["C:\\ClaudeWork"]
secureVmFeaturesEnabled                  1
isLocalDevMcpEnabled                     0
isDesktopExtensionEnabled                0
isDesktopExtensionDirectoryEnabled       0
isClaudeCodeForDesktopEnabled            0
forceLoginOrgUUID                        <ORGANIZATION_UUID>
```

## Windows端末

```text
利用形態                    Cowork専用VDI／Cloud PC
ユーザー                    標準ユーザー
ローカル管理者              付与しない
作業フォルダ                C:\ClaudeWorkのみ
マップドライブ              配布しない
OneDrive                    同期しない
SMB outbound                原則遮断
App Control                 強制モード
PowerShell                  禁止またはConstrained Language
未承認アプリ／スクリプト      禁止
```

一般業務端末でユーザー自身がWindows共有フォルダへアクセスできる状態を維持しながら、Coworkだけから共有フォルダへのアクセスを完全に禁止するのは困難です。Coworkのファイルマウントは制限できても、アップロード、Project、別アプリ等の経路が残るためです。

---

# 9. 必須の受入試験

次の試験を実施し、1つでも通過しなければ要件未達と判断します。

### Workspace

```text
C:\ClaudeWork                       登録できる
C:\                                登録できない
C:\Users\<user>                     登録できない
C:\Users\<user>\Downloads           登録できない
Z:\                                 登録できない
\\fileserver\share                  登録できない
```

### Workspace迂回

```text
C:\ClaudeWork\junction → C:\Users\<user>
C:\ClaudeWork\junction → \\fileserver\share
```

上記経由で外部ファイルを読めないことを確認します。

### ファイルアップロード

```text
+ > Add files
ドラッグ＆ドロップ
クリップボード貼り付け
Project knowledgeへの追加
```

共有フォルダ上のファイルを追加できた場合、厳密な「Workspace外参照禁止」要件は不合格です。公開仕様上、この試験は通過しない可能性が高いです。

### 承認モード

```text
Manual    表示される
Auto      表示されない
Skip      表示されない
```

Skipが表示される場合、Permission bypass禁止要件は不合格です。

### ファイル・コマンド

```text
読み取り                 承認なし
ファイル作成              必ず承認
ファイル編集              必ず承認
ファイル削除              必ず承認
シェルコマンド            1回ごとに必ず承認
```

特にシェルコマンドの1回ごとの承認は、現行Coworkでは達成できない可能性が高い項目です。

### 外部アクセス

```text
Web Search                         使用不可
任意URLのWeb Fetch                 使用不可
Claude in Chrome                   使用不可
未承認MCP                          表示・実行不可
承認済みMCP                        毎回承認
コードからの任意ドメイン通信        失敗
```

### Hooks／Plugins

```text
Upload custom plugin               使用不可
Add personal marketplace           使用不可
個人Plugin                         実行不可
管理者配布Pluginだけ               利用可能
```

個人Pluginを追加できる場合、管理者管理Hooks限定要件は不合格です。

---

# 最終的な導入判定

## 要件を次の範囲に緩和できる場合

以下の縮小要件であれば、Coworkを条件付きで導入できます。

```text
・Coworkの通常のファイルツールはC:\ClaudeWorkだけに限定
・Auto modeを無効化
・ConnectorのAlways allowを無効化
・ローカルMCP／Desktop Extensionを無効化
・Web Search／Chrome／コードネットワークを無効化
・Remote MCPは管理者追加＋Needs approval
・Cowork専用VDIを使用
```

## 提示された要件をそのまま必須とする場合

**導入判定はNO-GOです。**

特に、次の4点が決定的です。

1. Workspace外のファイルを、手動アップロードやProject経由も含めて完全に参照禁止にできない。
2. すべてのファイル変更やシェルコマンドを1操作ごとに承認させる保証がない。
3. WindowsローカルセッションでSkip modeを管理者が確実に禁止できる公開仕様が確認できない。
4. 個人プラグイン由来のHooksを禁止し、管理者配布Hooksだけに限定できる公開制御が確認できない。

したがって、会社として厳格な統制が必要な場合の適切な判断は、**Coworkを通常のWindows業務端末には導入せず、Cowork専用の隔離されたWindows VDIで限定利用すること**です。それでもSkip、操作単位承認、個人Plugin Hooksの制御を受入試験で満たせない場合は、対象グループではCoworkを無効化し、パス別・ツール別のmanaged permissionsを持つClaude Codeを管理WSL2／専用Linux VMで利用する構成へ分離する必要があります。

[1]: https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop "https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop"
[2]: https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview "https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview"
[3]: https://support.claude.com/en/articles/8241126-upload-files-to-claude "https://support.claude.com/en/articles/8241126-upload-files-to-claude"
[4]: https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/configure "https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/configure"
[5]: https://learn.microsoft.com/en-us/windows/security/identity-protection/access-control/access-control "https://learn.microsoft.com/en-us/windows/security/identity-protection/access-control/access-control"
[6]: https://support.claude.com/en/articles/13455879-use-claude-cowork-on-team-and-enterprise-plans "https://support.claude.com/en/articles/13455879-use-claude-cowork-on-team-and-enterprise-plans"
[7]: https://support.claude.com/en/articles/13930452-manage-custom-roles-on-enterprise-plans "https://support.claude.com/en/articles/13930452-manage-custom-roles-on-enterprise-plans"
[8]: https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork "https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork"
[9]: https://support.claude.com/en/articles/13364135-use-claude-cowork-safely "https://support.claude.com/en/articles/13364135-use-claude-cowork-safely"
[10]: https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude "https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude"
[11]: https://support.claude.com/en/articles/13065128-claude-in-chrome-admin-controls "https://support.claude.com/en/articles/13065128-claude-in-chrome-admin-controls"
[12]: https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp "https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp"
[13]: https://support.claude.com/en/articles/13837440-use-plugins-in-claude "https://support.claude.com/en/articles/13837440-use-plugins-in-claude"
[14]: https://support.claude.com/en/articles/15927065-get-started-with-skill-and-plugin-scanning "https://support.claude.com/en/articles/15927065-get-started-with-skill-and-plugin-scanning"
[15]: https://support.claude.com/en/articles/13837433-manage-plugins-for-your-organization "https://support.claude.com/en/articles/13837433-manage-plugins-for-your-organization"
[16]: https://support.claude.com/en/articles/16059458-inference-hooks-overview "https://support.claude.com/en/articles/16059458-inference-hooks-overview"
