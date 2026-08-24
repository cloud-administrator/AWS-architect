Cowork&claudeCode1.md# 精査結果

## 結論

**Claude Codeのサンドボックス利用を必須要件とするなら、Windowsネイティブ版Claude Codeは使用不可と判断するのが適切です。**

2026年8月24日時点で、Claude Codeの内蔵BashサンドボックスはmacOS、Linux、WSL2には対応していますが、Windowsネイティブには対応していません。さらに、`sandbox.failIfUnavailable: true`を設定すると、Windowsネイティブや依存パッケージ不足など、サンドボックスを初期化できない環境ではClaude Code自体を起動失敗にできます。([Claude][1])

ただし、**「WSL2だけにすれば厳格に制御できる」とは限りません。** Claude Code内蔵サンドボックスが直接隔離するのはBashコマンドとその子プロセスだけです。Claude CodeのRead、Edit、Write等の組み込みツール、MCPサーバー、Hooksは同じ隔離境界には入りません。全体を隔離するには、Claude Codeプロセス全体をコンテナまたは専用VMの中で動作させる必要があります。([Claude][2])

したがって、推奨構成は次のようになります。

```text
Windowsホスト
│
├─ Claude Desktop
│   ├─ Cowork：有効
│   └─ Claude Code for Desktop：無効
│
├─ Windows App Control／Intune
│   ├─ Windowsネイティブ版Claude Codeを実行禁止
│   ├─ 未承認インストーラー／実行ファイルを禁止
│   └─ ローカル管理者権限を付与しない
│
└─ Claude Code実行環境
    ├─ 標準的な厳格統制：管理されたWSL2
    │   └─ Claude Code CLIまたはVS Code Remote-WSL
    │
    └─ 高保証・非回避性が必要：専用Linux VM／管理コンテナ
```

**CoworkをWindows上で有効にしながら、Claude Desktop内のClaude Codeだけを無効化することは可能です。** `secureVmFeaturesEnabled`と`isClaudeCodeForDesktopEnabled`は独立した端末ポリシーだからです。([Anthropic Help Center][3])

---

# 1. 実行環境ごとの評価

| 実行形態                       | サンドボックス                           | 厳格統制への評価                  |
| -------------------------- | --------------------------------- | ------------------------- |
| Claude Code・Windowsネイティブ   | 内蔵Bashサンドボックス非対応                  | **不可**                    |
| Claude Code・WSL2           | 内蔵Bashサンドボックス対応                   | 条件付きで可                    |
| Claude Code・WSL2＋プロセス全体の隔離 | 全ツールを隔離可能                         | より強いが、sandbox runtimeはベータ |
| Claude Code・専用Linux VM     | OS全体を分離                           | **高保証用途の推奨**              |
| Cowork・Windowsローカル         | コード実行は専用Linux VM、ファイル操作等はWindows側 | Cowork固有の制御が必要            |

## Coworkは「完全なWindowsネイティブ」ではない

ローカルCoworkは、実際には次のハイブリッド構成です。

* エージェントループ、接続フォルダの読み書き、Web Fetch、ローカルPlugin MCPはWindows側で動作する。
* シェルコマンドとClaudeが生成したコードは、WindowsではHyper-V上の専用Linux VM内で実行される。

したがってCoworkには、コード実行に関しては独立したVM境界があります。ただし、接続フォルダのファイル操作はWindows側のアプリケーションレベル権限制御であり、すべての操作がVM内に閉じ込められているわけではありません。また、CoworkのVMを起動できない場合でもファイルツールとWebツールは動作し続け、シェルとコード実行だけが停止します。([Anthropic Help Center][4])

このため、Coworkについては「VMがあるから安全」と判断せず、接続フォルダ、MCP、Extensions、承認モード、監査を別途制御する必要があります。

---

# 2. 最も推奨する構成

## WindowsではCoworkだけを有効にする

Claude Desktop用の端末ポリシーは、次のように設定します。

```text
HKLM\SOFTWARE\Policies\Claude
```

| レジストリ値                               |        種類 |    推奨値 | 目的                      |
| ------------------------------------ | --------: | -----: | ----------------------- |
| `secureVmFeaturesEnabled`            | REG_DWORD |    `1` | Coworkを有効化              |
| `isClaudeCodeForDesktopEnabled`      | REG_DWORD |    `0` | Desktop内Claude Codeを無効化 |
| `isLocalDevMcpEnabled`               | REG_DWORD |    `0` | ローカルMCPを無効化             |
| `isDesktopExtensionEnabled`          | REG_DWORD |    `0` | Desktop Extensionを無効化   |
| `isDesktopExtensionDirectoryEnabled` | REG_DWORD |    `0` | Extensionディレクトリを無効化     |
| `allowedWorkspaceFolders`            |    REG_SZ | JSON配列 | Cowork接続フォルダを限定         |
| `forceLoginOrgUUID`                  |    REG_SZ | 組織UUID | 企業組織へのログインを強制           |

例：

```json
[
  "C:\\Company\\ClaudeCowork"
]
```

Claude Desktopの公開ポリシーでは、Cowork用の`secureVmFeaturesEnabled`と、Desktop内Claude Code用の`isClaudeCodeForDesktopEnabled`が別々に定義されています。したがって、**Coworkは使えるがDesktopのClaude Codeは使えない状態**を端末単位で構成できます。([Anthropic Help Center][3])

この構成では、Claude DesktopはCowork専用クライアントとして扱い、Claude Codeは別の管理された実行経路に限定します。

---

# 3. Windowsネイティブ版Claude Codeの回避経路も閉じる

`isClaudeCodeForDesktopEnabled=0`が無効化するのは、Claude Desktop内のClaude Codeです。

ユーザーが次の経路でWindowsネイティブ版Claude Codeを起動する可能性は別途排除する必要があります。

* スタンドアロン版Claude Code
* npm等でインストールしたClaude Code
* 未承認のIDE拡張
* ユーザー領域に配置した実行ファイル
* PowerShellやNode.jsからの起動
* Claude Code以外のAPIクライアント

Claude Codeのmanaged settingsはClaude Codeにだけ適用され、別のツールからClaude APIを呼び出した場合には適用されません。また、端末のローカル管理者はHKLMの管理設定自体を変更できます。([Claude][5])

したがって、次を併用します。

1. ユーザーをWindows標準ユーザーにする。
2. IntuneまたはApp Control for Businessで承認済みアプリだけを実行可能にする。
3. Windowsネイティブ版Claude Codeのバイナリ、インストーラー、未管理のパッケージ導入経路を禁止する。
4. Anthropic APIへの直接通信を制限し、企業プロキシまたは承認済みGateway経由に限定する。
5. Claude Desktopのログイン先を`forceLoginOrgUUID`で固定する。

App Control for Businessは、許可されたコードだけが実行できる許可リスト方式を実現し、実行ファイルだけでなくスクリプトやMSI等も制御対象にできます。([Microsoft Learn][6])

ただし、AppLockerはWSL内で実行されるLinuxコードを制御できません。Windows側のアプリケーション制御と、WSL内部のLinux側制御は別々に設計する必要があります。([Microsoft Learn][7])

---

# 4. Claude CodeをWSL2だけで使用する場合

## 推奨する利用インターフェース

厳格統制では、Claude Codeを次のいずれかに限定します。

* WSL2内のClaude Code CLI
* VS Code Remote-WSLから起動するClaude Code
* 管理されたLinux VMへのRemote-SSH
* 管理されたDev Container

**Claude DesktopのCode画面は無効のままにすることを推奨します。**

この方式なら、Windows側ではCoworkだけを提供し、Claude CodeはWSL2またはVMのLinux側に限定できます。

## WSL2へWindows側のmanaged settingsを継承させる

Claude CodeのWindows管理設定を次に配布します。

```text
HKLM\SOFTWARE\Policies\ClaudeCode
  Value name: Settings
  Type: REG_SZ
```

このJSON内に次を含めます。

```json
{
  "wslInheritsWindowsSettings": true
}
```

通常、WSL内のClaude CodeはLinux側の`/etc/claude-code`を参照します。`wslInheritsWindowsSettings: true`をHKLMまたは`C:\Program Files\ClaudeCode`の管理者専用ソースに設定すると、WSLセッションにもWindows側の管理ポリシーを継承できます。WSL内で`/status`を実行し、`Enterprise managed settings (HKLM)`または`(file)`が表示されることを確認します。([Claude][8])

---

# 5. Claude Codeのサンドボックスをフェイルクローズにする

最低限、次の設定が必要です。

```json
{
  "wslInheritsWindowsSettings": true,
  "forceLoginOrgUUID": "<ORGANIZATION_UUID>",

  "allowManagedPermissionRulesOnly": true,

  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "disableAutoMode": "disable"
  },

  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,

    "filesystem": {
      "allowManagedReadPathsOnly": true
    },

    "network": {
      "allowedDomains": [
        "<ANTHROPIC_AUTH_AND_API_ENDPOINTS>",
        "<APPROVED_SOURCE_CONTROL>",
        "<APPROVED_PACKAGE_MIRROR>",
        "<OTEL_COLLECTOR>"
      ],
      "allowManagedDomainsOnly": true,
      "strictAllowlist": true
    },

    "credentials": {
      "files": [
        {
          "path": "~/.ssh",
          "mode": "deny"
        },
        {
          "path": "~/.aws",
          "mode": "deny"
        },
        {
          "path": "~/.azure",
          "mode": "deny"
        },
        {
          "path": "~/.kube",
          "mode": "deny"
        }
      ]
    }
  },

  "allowManagedMcpServersOnly": true,
  "allowedMcpServers": []
}
```

このJSONは構成の骨格であり、実際の認証方式、ソース管理、パッケージミラー、OTel構成に合わせて許可ドメインと権限ルールを検証する必要があります。

重要な設定は次の3つです。

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false
  }
}
```

* `enabled: true`：サンドボックスを有効化する。
* `failIfUnavailable: true`：サンドボックスを初期化できなければClaude Codeを起動しない。
* `allowUnsandboxedCommands: false`：サンドボックス外での再実行を禁止する。

これにより、同じポリシーをWindowsネイティブ版Claude Codeが読み込んだ場合、Windowsネイティブはサンドボックス非対応なので起動失敗になります。([Claude][1])

## 管理設定の優先順位に注意する

Claude Codeは、複数の管理ソースを原則として合算しません。

```text
1. 組織のserver-managed settings
2. HKLMレジストリ
3. managed-settings.json
4. HKCU
```

最初にポリシーキーが見つかった管理ソースが選択され、大部分の下位設定は無視されます。したがって、組織側の管理された設定に別のキーが1つでも入っている状態で、HKLMだけに`sandbox.enabled`や`failIfUnavailable`を設定すると、HKLM側のサンドボックスポリシーが適用されない可能性があります。([Claude][5])

適切な構成は次のいずれかです。

### HKLMを主ポリシーにする場合

```text
組織のserver-managed settings：空
HKLM：完全なClaude Codeポリシー
```

### 組織設定を主ポリシーにする場合

```text
組織のserver-managed settings：完全なClaude Codeポリシー
HKLM：同内容の端末フォールバック＋wslInheritsWindowsSettings
```

組織設定とHKLMに役割を分割してはいけません。

---

# 6. WSL2自体の硬化

## 必須パッケージ

WSL2内に次をインストールします。

```bash
sudo apt-get install bubblewrap socat
```

さらに、WSL2から`cmd.exe`、`powershell.exe`、`/mnt/c`配下のWindows実行ファイルを呼び出す経路をサンドボックスから遮断するため、Anthropicのseccompフィルターを導入します。

```bash
npm install -g @anthropic-ai/sandbox-runtime
```

WSL2ではWindows実行ファイルの起動がUnixソケット経由でホストに引き渡されるため、サンドボックスからこの経路を遮断するにはseccompフィルターが重要です。([Claude][1])

## WindowsドライブとWindows実行ファイル連携を無効化する

承認済みWSLディストリビューションの`/etc/wsl.conf`を次のように構成します。

```ini
[automount]
enabled=false
mountFsTab=false

[interop]
enabled=false
appendWindowsPath=false

[user]
default=claudedev
```

この設定により、次を抑制します。

* `C:`や`D:`ドライブの`/mnt/c`、`/mnt/d`への自動マウント
* WSLからの`cmd.exe`や`powershell.exe`起動
* WindowsのPATHのWSLへの自動追加
* `/etc/fstab`からの追加マウント

MicrosoftのWSL仕様では、`[interop] enabled=false`によりWindowsプロセスの起動を無効化し、`appendWindowsPath=false`によりWindows PATHの追加を無効化できます。([Microsoft Learn][9])

プロジェクトはWindowsファイルシステムではなく、WSLのLinuxファイルシステム内に配置します。

```text
/work/project-a
/work/project-b
```

避けるべき構成は次です。

```text
/mnt/c/Users/<user>/source
C:\Users\<user>\source
\\wsl$\...
```

Cowork用のWindowsフォルダとClaude Code用のWSLリポジトリも分離する方が安全です。

```text
Cowork：
C:\Company\ClaudeCowork

Claude Code：
WSL内 /work
```

## IntuneのWSL設定

Intuneでは、少なくとも次を設定します。

| WSLポリシー                                        |      推奨値 |
| ---------------------------------------------- | -------: |
| Allow Windows Subsystem for Linux              |  Enabled |
| Allow Inbox WSL                                | Disabled |
| Allow WSL1                                     | Disabled |
| Allow debug shell                              | Disabled |
| Allow passthrough disk mount                   | Disabled |
| Allow custom kernel configuration              | Disabled |
| Allow kernel command line configuration        | Disabled |
| Allow custom system distribution configuration | Disabled |
| Allow custom networking configuration          | Disabled |
| Allow user firewall configuration              | Disabled |
| Allow nested virtualization                    | Disabled |
| Allow kernel debugging                         | Disabled |

これにより、Store版WSL2だけを許可し、カスタムカーネル、デバッグシェル、ディスクマウント、ネットワークモード変更等を抑制できます。([Microsoft Learn][10])

---

# 7. WSL2だけでは非回避性を保証できない理由

ここはセキュリティ判断上、最も重要です。

Microsoftの公開仕様では、現在WSLについて次の統制はサポートされていません。

* 企業ユーザーが利用できるディストリビューションの完全な制御
* ユーザーのWSL内rootアクセスの制御

また、WSL内のLinuxプロセスがWindowsファイルへアクセスする場合、そのWindowsユーザーと同じ権限でアクセスします。WSL内でrootになってもWindows管理者にはなりませんが、Windowsユーザー本人がアクセスできるファイルと実行ファイルには到達できます。([Microsoft Learn][11])

したがって、`wsl.conf`で自動マウントやinteropを無効にしても、WSL内のroot権限を持つ意図的なユーザーが設定を書き換えることまで、WSL標準機能だけで完全には防止できません。

さらに、Claude Code内蔵サンドボックスには、`excludedCommands`に対するmanaged-onlyロックがありません。ユーザーまたはプロジェクト設定から、サンドボックス外で実行するコマンドを追加できることが公式文書に明記されています。([Claude][1])

このため、脅威モデルを次のように分ける必要があります。

| 想定する脅威                        | WSL2＋内蔵サンドボックス           |
| ----------------------------- | ------------------------ |
| Claudeの誤操作                    | 有効                       |
| Prompt Injection              | 有効な防御層                   |
| 依存パッケージ不足によるサンドボックス未適用        | `failIfUnavailable`で防止可能 |
| 利用者の偶発的な設定変更                  | managed settingsで概ね防止可能  |
| 利用者が意図的にサンドボックスを回避            | **十分ではない**               |
| WSL rootを使った設定改変              | **十分ではない**               |
| Read/Edit/MCP/Hooksを含む全プロセス隔離 | **内蔵Bashサンドボックスだけでは不可**  |
| カーネルレベルのホスト分離                 | **専用VMが必要**              |

---

# 8. 高保証が必要な場合は専用VMを使う

次の要件がある場合、WSL2ではなく専用Linux VMを推奨します。

* 利用者による意図的な回避も防止する。
* Read、Edit、MCP、Hooksを含むClaude Codeプロセス全体を隔離する。
* 未信頼リポジトリを扱う。
* 規制上、ホストと別のカーネル境界が必要。
* サンドボックス外コマンドを絶対に許可しない。
* ホスト上の認証情報や業務データへの到達を防ぐ。

Anthropicも、専用VMを最も強い分離方式として位置付け、未信頼コードやカーネルレベル分離が必要な場合に推奨しています。内蔵BashサンドボックスはBashだけを隔離し、全自動実行に対する単独の境界としては不十分とされています。([Claude][2])

推奨構成は次です。

```text
Windowsホスト
├─ Claude Desktop
│   └─ Coworkのみ有効
│
└─ 専用Linux VM
    ├─ Claude Code
    ├─ プロジェクトリポジトリ
    ├─ 承認済み開発ツール
    ├─ Linux EDR
    ├─ 外部通信プロキシ
    └─ OTel
```

VMとWindowsホスト間では、次を禁止または最小化します。

* Windowsドライブ全体の共有
* ユーザープロファイルの共有
* クリップボード共有
* ホストのSSHキーやクラウド認証情報の持ち込み
* Dockerソケット等の強力なソケット共有
* 無制限のインターネット接続

必要なソースコードだけを、承認されたGitサーバーまたは管理された同期経路からVMへ取得します。

---

# 9. 同じClaude DesktopからWSL2版Claude Codeを使う場合

同一アプリ内でCoworkとWSL2版Claude Codeの両方を使うことが必須の場合は、次の構成が可能です。

```text
secureVmFeaturesEnabled = 1
isClaudeCodeForDesktopEnabled = 1
```

Claude Codeのmanaged settingsには次を強制します。

```json
{
  "wslInheritsWindowsSettings": true,
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false
  }
}
```

その結果、原則として次の挙動になります。

```text
DesktopからWindowsネイティブ環境を選択
  → サンドボックスを初期化できない
  → Claude Code起動失敗

Desktopから管理対象WSL2を選択
  → bubblewrap / socat等を確認
  → サンドボックス起動
  → Claude Code利用可能
```

ただし、管理設定が存在するWindows端末では、Claude Code DesktopのWSLセッションは初期状態で利用不可となっており、組織で有効化するにはAnthropicのアカウントチームへの依頼が必要です。([Claude][8])

また、公開されているClaude Desktopポリシーには、次のような環境別スイッチはありません。

```text
Windows native Code = OFF
WSL2 Code = ON
```

公開ポリシーにあるのは、Desktop内Claude Code全体を制御する`isClaudeCodeForDesktopEnabled`です。したがって、**同一Desktop内でのWSL2限定は、UIからネイティブ選択肢を完全に消す制御ではなく、ネイティブセッションを`failIfUnavailable`で起動失敗にする実装**になります。これは公開ポリシー一覧とWSLセッション仕様からの判断です。([Anthropic Help Center][3])

この方式は次の理由から、最も厳格な構成としては推奨しません。

* ネイティブ選択肢が表示される可能性がある。
* managed settingsが未配信の場合、フェイルクローズ設定も存在しない。
* 同じDesktop実行ファイルをCoworkで必要とするため、App ControlでDesktop全体を禁止できない。
* WSL2内蔵Bashサンドボックス自体に残余リスクがある。

したがって、**「DesktopはCowork専用、Claude CodeはWSL CLI／Remote-WSL専用」**と分離する方が明確です。

---

# 10. Cowork側に必要な厳格制御

Claude CodeをWSL2またはVMへ分離しても、Coworkは次のように制御する必要があります。

## 端末側

```text
secureVmFeaturesEnabled = 1
allowedWorkspaceFolders = ["C:\\Company\\ClaudeCowork"]
isLocalDevMcpEnabled = 0
isDesktopExtensionEnabled = 0
isDesktopExtensionDirectoryEnabled = 0
```

Coworkには、ユーザープロファイル全体や次の場所を許可しないことを推奨します。

```text
C:\
C:\Users
C:\Users\<user>
OneDrive全体
ファイルサーバーのルート
WSLファイルシステム
開発リポジトリ全体
```

## 組織側

* Coworkの利用者をカスタムロールまたはグループで限定する。
* ローカル利用だけなら「Run Cowork in the cloud」を無効化する。
* 「Automatically approve」を無効化する。
* Connector toolの「Always allow」を無効のままにする。
* Claude in ChromeやComputer Useが不要なら無効化する。
* Plugins／Skillsを承認済みのものに限定する。
* OpenTelemetryを有効化する。

Coworkの自動承認モードは組織設定上、既定で利用可能になっているため、厳格運用では明示的に無効化する必要があります。書き込み可能なConnectorの「Always allow」は既定で無効ですので、その状態を維持します。([Anthropic Help Center][12])

CoworkのOTelでは、ユーザープロンプト、ツールとMCPの呼び出し、ファイルアクセス、Skills、Plugins、人間の承認・拒否等を監視できます。([Anthropic Help Center][13])

なお、Windowsホスト上のEDRはCoworkの専用VM内部を直接観測できません。Coworkの監査についてはEDRだけに依存せず、OTelとCompliance APIを利用します。([Anthropic Help Center][4])

---

# 11. WSL2の監視

WSL2内のプロセスは、通常のWindows側EDRセンサーからは直接見えません。Anthropicも、DesktopのWSLセッションではWindows側のEDRからWSLプロセスが不可視になることを明記しています。([Claude][8])

そのため、次を実施します。

* Microsoft Defender for EndpointのWSL Plugin、または対応するLinux用EDRを導入する。
* Claude Code OpenTelemetryをSIEMへ送信する。
* WSLディストリビューション一覧を定期的に収集する。
* `wsl.conf`、`/etc/claude-code`、インストール済みClaude Codeバージョンを定期検査する。
* App ControlイベントとWSL側のプロセスイベントを関連付ける。
* 許可されていない外部通信をプロキシまたはFirewallで遮断する。

Microsoftも企業環境で、Intune、Defender for EndpointのWSL統合、およびネットワーク制御を組み合わせることを推奨しています。([Microsoft Learn][11])

---

# 12. ネットワーク制御

Claude Codeサンドボックスのドメイン許可リストだけを、機密データ持ち出し防止の最終境界にしてはいけません。

内蔵プロキシはホスト名を使って許可判定しますが、既定ではTLSを終端・検査しません。Anthropicも、`github.com`等の広いドメインを許可するとデータ持ち出し経路になり得ることや、より強い保証が必要な場合はTLSを終端・検査する企業プロキシを使用するよう案内しています。([Claude][1])

推奨構成は次です。

```text
Claude Code sandbox
  ↓
企業プロキシ
  ↓
承認済み宛先のみ
```

許可先は可能な限り次に限定します。

* Anthropicの認証・API接続先
* 社内Gitまたは承認済みGitサービス
* 社内パッケージミラー
* 社内Artifact Registry
* OTel Collector
* 必要な社内MCP

直接のnpm、PyPI、任意GitHubリポジトリ等を許可するのではなく、社内ミラー経由に限定する方が厳格です。

---

# 13. MCPを完全に停止する場合

Claude CodeのMCPを完全に禁止する場合は、WSL内に次を配置します。

```text
/etc/claude-code/managed-mcp.json
```

内容：

```json
{
  "mcpServers": {}
}
```

この構成では、VS Code拡張自身のインプロセスサーバーを除き、すべてのMCPサーバーを停止できます。ユーザーによる`claude mcp add`も拒否されます。([Claude][14])

WSLユーザーがrootを持つ場合、このファイルを変更できる点は残ります。そのため、MCP設定ファイルを含めて非改ざん性を求める場合も、専用VMまたは管理コンテナの方が適しています。

---

# 14. 受入試験

## Windowsホスト

* Claude DesktopでCoworkが表示される。
* Claude DesktopでCodeが表示されない。
* Windows版`claude.exe`がApp Controlで拒否される。
* ユーザー領域から未承認バイナリを実行できない。
* ローカル管理者権限がない。
* 指定組織以外でClaude Desktopへログインできない。

## WSL2

* `wsl -l -v`で承認済みディストリビューションがWSL2として動作している。
* `/status`に`Enterprise managed settings (HKLM)`または承認した管理ソースが表示される。
* `/sandbox`で`bubblewrap`、`socat`、seccompが正常と表示される。
* `sandbox.failIfUnavailable`が有効である。
* `cmd.exe`と`powershell.exe`を起動できない。
* `/mnt/c`が自動マウントされていない。
* 未承認ドメインへ接続できない。
* 未承認MCPを追加できない。
* `--dangerously-skip-permissions`を使用できない。
* Auto modeを使用できない。
* OTelイベントがSIEMへ到達する。

## Cowork

* `C:\Company\ClaudeCowork`以外を接続できない。
* ローカルMCPを起動できない。
* Desktop Extensionを追加できない。
* Automatically approveを選択できない。
* 書き込みConnectorでタスクごとの承認が必要になる。
* クラウド実行が無効になっている。
* ファイルアクセスと承認判断がOTelへ記録される。

## 高保証要件の判定試験

次の試験で回避できる場合、WSL2構成は高保証要件を満たしません。

* ユーザー設定またはプロジェクト設定から`excludedCommands`を追加する。
* WSL rootで`/etc/wsl.conf`を変更する。
* 別のWSLディストリビューションを導入する。
* `/etc/claude-code`の管理ファイルを変更する。
* 別のClaudeクライアントやAPIクライアントを実行する。

これらの回避も防止要件に含まれるなら、Claude Codeは専用VM／管理コンテナへ移す必要があります。

---

# 最終判断

本案件では、次の構成が最も適切です。

## 推奨構成

```text
Claude Desktop
├─ Cowork：ON
└─ Claude Code for Desktop：OFF

Claude Code
├─ Windowsネイティブ：禁止
├─ 管理されたWSL2：条件付きで許可
└─ 高保証対象：専用Linux VMで実行
```

### Cowork

* Windows上で有効化する。
* コード実行はCowork固有のHyper-V VMを利用する。
* 接続フォルダを専用ステージング領域だけに限定する。
* ローカルMCPとExtensionsを無効化する。
* Auto approvalとConnectorの永続承認を無効化する。
* OTelとCompliance APIで監視する。

### Claude Code

* Windowsネイティブでは使用させない。
* Claude Desktop内のCode機能は`isClaudeCodeForDesktopEnabled=0`で無効化する。
* 通常の厳格運用では、管理対象WSL2のCLIまたはRemote-WSLだけを許可する。
* `sandbox.enabled`、`failIfUnavailable`、`allowUnsandboxedCommands:false`を強制する。
* WSLのWindowsドライブ自動マウントとinteropを無効化する。
* Windows側はApp Control、WSL側はLinux EDRとOTelで監視する。
* 非回避性、全プロセス隔離、カーネル分離が必要なら専用Linux VMへ移す。

したがって、**「CoworkはWindowsのClaude Desktopで利用し、Claude CodeはDesktopから切り離して管理対象WSL2または専用VMだけで利用する」構成が、制御の明確性と厳格性の両面で最適です。** 同一Claude Desktop内でWSL2版Claude Codeを使う方式は実現可能ですが、Windowsネイティブ選択肢をポリシーで明示的に隠す公開機能がないため、厳格な本番構成では第二選択とすべきです。

[1]: https://code.claude.com/docs/en/sandboxing "https://code.claude.com/docs/en/sandboxing"
[2]: https://code.claude.com/docs/en/sandbox-environments "https://code.claude.com/docs/en/sandbox-environments"
[3]: https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop "https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop"
[4]: https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview "https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview"
[5]: https://code.claude.com/docs/en/managed-settings "https://code.claude.com/docs/en/managed-settings"
[6]: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol"
[7]: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/security-considerations-for-applocker "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/security-considerations-for-applocker"
[8]: https://code.claude.com/docs/en/admin-setup "https://code.claude.com/docs/en/admin-setup"
[9]: https://learn.microsoft.com/en-us/windows/wsl/wsl-config "https://learn.microsoft.com/en-us/windows/wsl/wsl-config"
[10]: https://learn.microsoft.com/en-us/windows/wsl/intune "https://learn.microsoft.com/en-us/windows/wsl/intune"
[11]: https://learn.microsoft.com/en-us/windows/wsl/enterprise "https://learn.microsoft.com/en-us/windows/wsl/enterprise"
[12]: https://support.claude.com/en/articles/13455879-use-claude-cowork-on-team-and-enterprise-plans "https://support.claude.com/en/articles/13455879-use-claude-cowork-on-team-and-enterprise-plans"
[13]: https://support.claude.com/en/articles/14477985-monitor-claude-cowork-activity-with-opentelemetry "https://support.claude.com/en/articles/14477985-monitor-claude-cowork-activity-with-opentelemetry"
[14]: https://code.claude.com/docs/en/managed-mcp "https://code.claude.com/docs/en/managed-mcp"
