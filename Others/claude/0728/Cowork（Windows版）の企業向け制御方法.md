# Claude Cowork（Windows版）の企業向け制御方法：調査結果

**調査基準日：2026年7月28日**
AnthropicおよびMicrosoftの公式情報のみを参照しました。

なお、Team／Enterprise向けのWeb・モバイル版Coworkとクラウドセッションは、公式情報上、**2026年8月3日からベータ提供開始**とされています。本回答では、現在利用可能なWindowsデスクトップ上のローカルセッションを中心に整理し、クラウドセッションについては今後の制御として記載します。([Claude Help Center][1])

---

## 1. 結論

### 特定フォルダだけをCoworkにアクセスさせる

これは、**Windows端末側のClaude Desktopシステムポリシー**で直接制御できます。

`allowedWorkspaceFolders`というポリシーに、Coworkへの接続を許可するフォルダを指定します。WindowsではグループポリシーまたはIntuneを使用して、`HKLM\SOFTWARE\Policies\Claude`配下に設定します。端末全体に適用するHKLM設定が推奨され、HKCUのユーザー設定より優先されます。初期状態は「制限なし」であるため、企業利用時には明示的な設定が重要です。([Claude Help Center][2])

ただし、このポリシーが制限するのは、正確には**ユーザーがCoworkにマウントできるフォルダ**です。次の経路は別途制御する必要があります。

* ローカルMCPサーバー
* デスクトップ拡張機能
* コネクター
* Claude in Chrome
* Computer useによる画面操作
* Windowsユーザー自身が持つファイルアクセス権

したがって、機密性の高い環境では、`allowedWorkspaceFolders`だけではなく、ローカルMCP・拡張機能の無効化、NTFSアクセス権などを組み合わせるのが適切です。

---

### 危険なコマンドの実行を禁止する

**Coworkについて、`rm`、`curl`、`sudo`など特定のコマンドを管理者がdenyリストで禁止する機能は、公式資料では確認できませんでした。**

Windows版のローカルCoworkでは、シェルコマンドとClaudeが生成したコードは、Windowsホスト上ではなく、Hyper-Vで分離された専用Linux VM内で実行されます。VMにはネットワーク送信制限、システムコール制限、セッションごとのユーザー分離があります。([Claude Help Center][3])

一方、Claude Codeには、たとえば次のようなコマンド単位の制御が公式に存在します。

* `Bash(rm *)`
* `Bash(curl *)`
* `Bash(sudo *)`
* `Read(./secrets/**)`

Claude CodeではAllow／Ask／Denyルールを管理設定として強制できますが、これは明確に**Claude Codeの機能**です。公式資料には、このClaude Code用ポリシーがCoworkにも適用されるという記載がないため、Coworkの制御として流用できるとは判断できません。([Claude Platform Docs][4])

そのため、Coworkで危険な実行を抑える場合は、コマンド単位の禁止ではなく、以下の多層制御が必要です。

1. アクセス可能なフォルダを最小化する
2. コード実行環境のネットワーク送信を無効化する
3. ローカルMCPとデスクトップ拡張機能を無効化する
4. コネクターの書き込み／削除ツールをBlockedまたはNeeds approvalにする
5. 高リスク作業ではユーザーにManualモードを使用させる
6. OpenTelemetryでコマンド、ファイルアクセス、承認結果を監視する
7. リスクを許容できない端末ではCowork自体を無効化する

---

# 2. 制御を実施する場所

企業として利用する場合、制御面は次の4種類に分かれます。

| 制御面                     | 管理対象                            | 主な管理者                   |
| ----------------------- | ------------------------------- | ----------------------- |
| **Anthropic組織設定**       | 組織全体、グループ、ユーザー、コネクター、ネットワーク     | Claude Enterprise Owner |
| **Windows上のClaudeポリシー** | 管理対象Windows端末のClaude Desktop    | Intune／GPO管理者           |
| **Windows OSセキュリティ**    | OS上のファイル、アプリ、スクリプト              | Windows／セキュリティ管理者       |
| **外部システム側の制御**          | Microsoft 365、Google、Slackなどの権限 | IdP／各サービス管理者            |

重要なのは、**WindowsポリシーだけではWeb・モバイル版Coworkを停止できず、Anthropic組織設定だけではWindows端末上のローカルMCPなどを完全に抑止できない**ことです。両方の管理面を使用する必要があります。

---

# 3. Anthropicの組織設定で制御できるもの

## 3.1 Cowork自体の有効／無効

**管理面：Anthropic組織設定**

Organization settingsのCowork設定で、組織全体のCoworkを有効または無効にできます。Coworkは組織でデフォルト有効になっているため、導入前に状態を確認する必要があります。([Claude Help Center][1])

Enterpriseでは、グループとカスタムロールを使用して、特定の部署やパイロットユーザーだけにCoworkを許可できます。

カスタムロールを利用する場合、対象ユーザーの組織ロールを「Custom」にする必要があります。User、Admin、Ownerの組み込みロールにはカスタムロールの制限が適用されません。([Claude Help Center][5])

**推奨：**

* 最初は組織全体に開放しない
* パイロット用グループを作成する
* Coworkを許可するカスタムロールをそのグループだけに割り当てる

---

## 3.2 クラウドセッションの有効／無効

**管理面：Anthropic組織設定**

Cowork自体の有効化とは別に、クラウド上でCoworkを実行する機能を制御できます。

Enterpriseではクラウドセッションはデフォルトで無効です。Ownerが組織設定で有効化し、さらにカスタムロールで「Cowork in the cloud」をグループに許可します。([Claude Help Center][1])

クラウドセッションを有効にすると、端末が停止していても処理やスケジュール済みタスクが継続します。そのため、Windows端末管理の範囲外で処理が続く可能性があります。

---

## 3.3 コード実行とネットワーク送信

**管理面：Anthropic組織設定**

Organization settingsのCapabilitiesにある「Code execution and file creation」で、コード実行・ファイル作成機能を組織レベルで無効化できます。

Enterpriseでは、コード実行は新規組織でデフォルト有効ですが、外部ネットワークへの送信はデフォルト無効です。([Claude Help Center][6])

ネットワーク送信は、次の段階で制御できます。

* ネットワークアクセスなし
* パッケージマネージャーのみ
* パッケージマネージャーと指定ドメインのみ
* すべてのドメイン

Anthropicは、最初はネットワークアクセスを無効にし、必要に応じてパッケージマネージャー、指定ドメインの順に広げる方法を推奨しています。([Claude Help Center][6])

ただし、以下はこのネットワーク送信ポリシーの対象外です。

* Web search
* Web fetch
* MCPコネクター
* Claude in Chrome

これらはそれぞれ別の管理設定で無効化または制限する必要があります。([Claude Help Center][1])

また、「Code execution and file creation」設定がCoworkのローカルシェルだけを個別に無効化するものかは、公式資料では明確ではありません。**Coworkは許可したまま、シェル機能だけを停止する専用設定は確認できませんでした。**

---

## 3.4 コネクターの操作権限

**管理面：Anthropic組織設定**

組織管理者は、各コネクターまたは各ツールについて、以下を指定できます。

* **Always allow**：承認なし
* **Needs approval**：操作ごとに承認
* **Blocked**：使用禁止

たとえば次のような制御が可能です。

* Outlookメールは検索・読み取りのみ許可し、送信は禁止
* Google Driveは読み取りのみ許可し、作成・編集は禁止
* チケットシステムは参照のみ許可し、ステータス変更は禁止

この制限は組織全体に適用され、ユーザーは解除できません。また、Claude側で許可しても、元のMicrosoft 365やGoogle Workspaceなどでユーザーが持っていない権限が追加されることはありません。([Claude Help Center][7])

Enterpriseのカスタムロールでも、グループ単位でコネクターおよびツールをAlways allow／Needs approval／Blockedにできます。([Claude Help Center][5])

---

## 3.5 Coworkでの「常に許可」を禁止する

**管理面：Anthropic組織設定**

Organization settingsのCowork Permissionsで、書き込み可能なコネクターツールについて、ユーザーが「すべてのタスクで常に許可」を選択できるかを制御できます。

この設定はデフォルトで無効です。無効時は、書き込み可能なコネクターツールについてタスクごとの承認が必要になります。カスタムロールよりも厳しい設定が優先されます。([Claude Help Center][1])

ただし、これは主に**コネクターツール**の承認制御です。ローカルファイル操作やシェルコマンドを含むすべてのCoworkアクションを、組織管理者が常にManualモードへ固定するものではありません。

---

## 3.6 Web検索とClaude in Chrome

**管理面：Anthropic組織設定＋Chrome管理**

Web searchはOrganization settingsのCapabilitiesで無効化できます。

Claude in ChromeはCoworkとは別機能として管理され、以下を制御できます。

* 組織全体で有効／無効
* カスタムロールによるグループ別アクセス
* Webサイトの許可リスト
* Webサイトのブロックリスト

EnterpriseではClaude in Chromeはデフォルト無効です。Anthropicは最初に厳しいサイト許可リストを使用し、必要に応じて拡張する方法を推奨しています。([Claude Help Center][8])

Chrome拡張機能自体のインストール対象は、Google WorkspaceのChrome管理やMDMを使用して、特定ユーザーまたはグループに限定できます。

---

## 3.7 プラグイン

**管理面：Anthropic組織設定**

組織管理者は、プラグインマーケットプレイスを作成し、各プラグインを以下の状態にできます。

* Installed by default
* Available
* Required
* Not available

Enterpriseではグループ単位の上書きも可能です。([Claude Help Center][1])

ただし、Coworkのプラグイン機能全体を単独で有効／無効にする専用スイッチはなく、プラグインはCoworkのメイン設定に含まれます。端末上でプラグインに含まれるローカルMCPを動作させたくない場合は、Windowsポリシーの`isLocalDevMcpEnabled`を使用します。

---

## 3.8 監視

**管理面：Anthropic組織設定＋SIEM**

CoworkではOpenTelemetryを使用して、次の情報をSIEMやログ基盤へ送信できます。

* ユーザーのプロンプト全文
* すべてのツール／MCP呼び出し
* ツール名、引数、成功／失敗、処理時間
* 読み書きしたファイルのパス
* 使用したスキル、プラグイン
* ユーザーの承認／拒否
* 使用モデル、トークン、推定コスト

Organization settingsのCoworkで、OTLPエンドポイントと認証情報を指定します。([Claude Help Center][9])

ログにはプロンプト全文、ファイルパス、コマンド引数、メールアドレスなどが含まれる可能性があります。ログ側でのマスキング、アクセス制限、保持期間設定が必要です。([Claude Help Center][9])

---

# 4. Windows上のClaude Desktopポリシー

**管理面：Windowsグループポリシー／Intune**

Windowsでは、Claude Desktopのポリシーを以下に配置します。

`HKLM\SOFTWARE\Policies\Claude`

HKLMは端末全体、HKCUはユーザー単位です。両方に設定された場合はHKLMが優先されます。([Claude Help Center][2])

| ポリシー                                 | 制御内容                        | 主な用途                  |
| ------------------------------------ | --------------------------- | --------------------- |
| `allowedWorkspaceFolders`            | Coworkにマウントできるフォルダを限定       | 機密フォルダへのアクセス防止        |
| `secureVmFeaturesEnabled`            | Windowsデスクトップ上のCoworkを有効／無効 | Coworkを使用させない端末       |
| `forceLoginOrgUUID`                  | 指定したClaude組織のアカウントだけログイン可能  | 個人アカウントや別組織の利用防止      |
| `isLocalDevMcpEnabled`               | ローカルMCPサーバーを有効／無効           | 未管理MCPの実行防止           |
| `isDesktopExtensionEnabled`          | デスクトップ拡張機能の実行を有効／無効         | 拡張機能を全面禁止             |
| `isDesktopExtensionDirectoryEnabled` | 拡張機能ディレクトリへのアクセスを有効／無効      | ユーザーによる拡張機能探索を防止      |
| `isClaudeCodeForDesktopEnabled`      | デスクトップ版Claude Codeを有効／無効    | CoworkとClaude Codeを分離 |
| `disableAutoUpdates`                 | 自動更新を停止                     | MDMによるバージョン管理         |
| `autoUpdaterEnforcementHours`        | 更新適用までの猶予時間                 | 更新強制の管理               |

これらの正式なポリシー一覧と初期値はAnthropicのEnterprise configurationに記載されています。([Claude Help Center][2])

## 重要な使い分け

### 拡張機能を完全に禁止する場合

Windowsポリシーで以下を無効化します。

* `isDesktopExtensionEnabled`
* `isDesktopExtensionDirectoryEnabled`
* `isLocalDevMcpEnabled`

### 承認済み拡張機能だけを使わせる場合

Windowsポリシーでは拡張機能を有効のままにして、Anthropic組織設定のデスクトップ拡張機能Allowlistを有効化します。

Allowlistはデフォルト無効で、無効のままではレジストリ内の全拡張機能にアクセスできます。Allowlistを有効化すると、既存の未承認拡張機能は削除され、許可リスト外の拡張機能をインストールできなくなります。([Claude Help Center][10])

ただし、Allowlistはインストール後にローカルMCPファイルが改変されることまでは防止しません。強い制御が必要な場合は、拡張機能を全面無効化するか、Windowsのアプリケーション制御を併用する必要があります。([Claude Help Center][10])

---

# 5. Windows OS側で実施する補完制御

## 5.1 NTFSアクセス権

**管理面：Windowsファイルシステム**

NTFSのDACLを使用して、対象Windowsユーザーが読み取り／書き込みできるフォルダを限定できます。Microsoftの`icacls`などで設定・変更できます。([Microsoft Learn][11])

ただし、これはClaude専用のアクセス制御ではありません。そのWindowsユーザー本人と、そのユーザー権限で動く他のアプリにも同じ制限がかかります。

**役割の違い：**

* `allowedWorkspaceFolders`：Coworkが接続できるフォルダを限定
* NTFS ACL：Windowsユーザーが実際にアクセスできるフォルダを限定

両方を設定することで、設定ミスや別経路によるアクセスのリスクを低減できます。

---

## 5.2 Controlled Folder Access

**管理面：Microsoft Defender／Intune／GPO**

Controlled Folder Accessは、信頼されていないアプリが保護対象フォルダ内のファイルを変更することを防止します。Intune、Configuration Manager、グループポリシーで管理できます。([Microsoft Learn][12])

ただし、これは主にランサムウェア対策であり、**読み取りを禁止する機能ではありません**。Coworkのフォルダアクセス制限の代わりにはならず、重要フォルダへの書き込みを防ぐ追加防御として扱います。

---

## 5.3 App Control for Business／AppLocker

**管理面：Windowsアプリケーション制御**

Windows上で実行を許可するアプリ、ドライバー、スクリプト、MSIXなどを制御できます。

Microsoftは、可能であればAppLockerよりApp Control for Businessを優先することを推奨しています。App Controlは端末全体、AppLockerはユーザーまたはグループ単位の制御に向いています。([Microsoft Learn][13])

適用対象としては次のようなものがあります。

* Claude Desktop自体
* ユーザーが追加した未承認アプリ
* ホストWindows上で動くローカルMCP実装
* 未承認スクリプトやインストーラー

ただし、Coworkのシェルコマンドは分離Linux VM内で実行されます。そのため、AppLocker、App Control、EDRを使っても、VM内部の個別コマンドを直接監視・禁止することはできません。

Anthropicも、ホスト側EDRはCowork VM内を検査できず、クラウドセッションも端末外で動作するためEDRから観測できないと明記しています。([Claude Help Center][3])

---

## 5.4 アプリ配布と管理者権限

**管理面：Intune／SCCM／GPO／PowerShell**

Windows版CoworkにはVirtual Machine Platformが必要です。企業配布ではMSIXを端末全体にプロビジョニングし、標準ユーザーでも利用できる状態にします。([Claude Help Center][14])

MSIXを単純にIntuneのユーザーコンテキストで配布すると、Cowork用仮想化サービスが登録されず、ClaudeはインストールされていてもCoworkが起動できない場合があります。端末全体へのプロビジョニングが必要です。([Claude Help Center][14])

更新管理は次のどちらか一方に統一します。

* Claude Desktopの自動更新に任せる
* `disableAutoUpdates`を設定し、MDMから更新版MSIXを配布する

アプリとMDMの両方で更新すると競合する可能性があります。([Claude Help Center][14])

---

# 6. ユーザーが選択する承認モード

**管理面：原則としてユーザー操作**

Coworkには以下の3モードがあります。

| モード    | 動作                          |
| ------ | --------------------------- |
| Manual | 操作前にユーザーへ承認を要求              |
| Auto   | 各操作を安全性チェックし、危険と判断した操作をブロック |
| Skip   | 承認を求めず、安全性の自動チェックも行わない      |

Autoモードには安全性チェックがありますが、完全な防御ではありません。Skipモードでは自動チェックが行われません。ファイルの完全削除については、どのモードでも明示的な承認が必要です。([Claude Help Center][15])

### 管理者による強制について

* コネクターの書き込みツールについては、組織管理者がタスクごとの承認を強制できます。
* 今後のクラウドセッションについては、組織管理者が永続的なAlways allowを禁止し、操作ごとの承認なしで実行できるかを制御できると記載されています。([Claude Help Center][3])
* **WindowsローカルCoworkについて、管理者がManualモードに固定したり、Skipモードを禁止したりする専用ポリシーは、公式資料では確認できませんでした。**

企業ポリシーとしてManualを使用させるだけでは技術的強制にならない可能性があるため、この点は導入判断上の制約になります。

---

# 7. ID・アカウントの制御

## Anthropic組織設定

Enterpriseでは以下を利用できます。

* SSO
* ドメイン検証
* JIT／SCIMプロビジョニング
* グループ管理
* カスタムロール

SSO設定はOwnerまたはPrimary Ownerが行い、企業ドメインとIdPを関連付けます。([Claude ヘルプセンター][16])

## Windows端末設定

Claude Desktopの`forceLoginOrgUUID`を設定すると、指定したEnterprise組織に所属するアカウント以外ではログインできなくなります。([Claude Help Center][2])

したがって、推奨される組み合わせは次のとおりです。

* SSO／SCIM：企業アカウントのライフサイクル管理
* `forceLoginOrgUUID`：管理Windows端末で個人Claudeアカウントを使用させない
* カスタムロール：部署ごとの機能制御

---

# 8. データ保持・監査上の重要な制約

## ローカルCowork履歴

Windows上のローカルセッションでは、会話履歴がユーザー端末に保存されます。

このデータは以下の対象外です。

* Anthropicの標準保持ポリシー
* Enterpriseの中央保持期間管理
* 管理者による一括エクスポート

公式資料でも、ローカル履歴は管理者が集中管理またはエクスポートできないと明記されています。([Claude Help Center][1])

通常のEnterprise会話・プロジェクトには30日以上のカスタム保持期間を設定できますが、この管理をローカルCowork履歴にも適用できるとは記載されていません。([Claude ヘルプセンター][17])

## Compliance APIと監査ログ

2026年7月28日時点では、ローカルCoworkの活動は以下に記録されません。

* Audit logs
* Compliance API
* データエクスポート

監視にはOpenTelemetryを使用する必要があります。([Claude Help Center][3])

2026年8月3日から予定されているWeb・モバイルのクラウドセッションについては、Enterprise向けページでCompliance APIの対象になると記載されています。実際の提供開始後に、契約テナントで対象イベントを再確認する必要があります。([Claude Help Center][1])

---

# 9. 現時点で制御できない、または不明な項目

| 項目                                         | 調査結果               |
| ------------------------------------------ | ------------------ |
| Coworkで特定のシェルコマンドをdenyする                   | **公式な設定を確認できず**    |
| Coworkは許可し、シェル機能だけを無効化する                   | **専用設定を確認できず**     |
| ローカルCoworkを常にManualモードへ固定                  | **公式な管理者設定を確認できず** |
| ローカルCoworkでSkipモードを禁止                      | **公式な管理者設定を確認できず** |
| スケジュール済みタスクの作成だけを組織で禁止                     | **専用設定を確認できず**     |
| Cowork Projectsの作成を禁止                      | **現在は不可と明記**       |
| ローカル履歴にEnterprise保持期間を適用                   | **不可または未対応**       |
| ローカルCowork履歴を管理者がエクスポート                    | **不可**             |
| EDRでVM内部のコマンドを監視                           | **不可**             |
| Extension Allowlistでローカルファイル改変まで防止         | **不可**             |
| Computer useのEnterprise向け提供状況と組織単位のアプリブロック | **公式資料間で時期差があり不明** |

Cowork Projectsについては、組織管理者がプロジェクト作成を禁止する機能は現在ないと公式に明記されています。([Claude Help Center][1])

Computer useについては、2026年4月の専用ページではPro／Max限定の研究プレビューとされていますが、7月の一般Cowork資料ではCowork機能として説明されています。Enterprise向けの提供状態と管理者制御は、契約テナントでの確認が必要です。([Claude Help Center][18])

---

# 10. 推奨する企業向け初期構成

以下は、公式機能を組み合わせた**厳格なパイロット構成案**です。

## Anthropic組織設定

* Coworkをパイロットグループだけに許可
* クラウドセッションは無効
* Code executionのネットワーク送信は無効
* Web searchは無効
* Claude in Chromeは無効、または限定サイトのみ
* コネクターは原則Blocked
* 必要な読み取りツールだけ許可
* 書き込みツールはNeeds approval
* 「Always allow for connector tools」は無効
* プラグインは承認済みのものだけ公開
* OpenTelemetryをSIEMへ送信

## Windows上のClaudeポリシー

* `allowedWorkspaceFolders`で業務用作業フォルダだけを許可
* `forceLoginOrgUUID`で企業組織に固定
* `isLocalDevMcpEnabled=false`
* `isDesktopExtensionEnabled=false`
* `isDesktopExtensionDirectoryEnabled=false`
* Claude Codeが不要なら`isClaudeCodeForDesktopEnabled=false`
* Coworkを許可しない端末は`secureVmFeaturesEnabled=false`
* 更新管理をMDMまたはClaudeのどちらか一方に統一

## Windows OS

* ユーザーは標準ユーザー
* 重要フォルダはNTFS ACLでアクセスを限定
* 重要フォルダの書き込みはControlled Folder Accessで補完
* App Control for Businessで未承認アプリ／スクリプトを制限
* Claude DesktopはIntune等で端末全体にプロビジョニング

---

## 最終評価

Claude Coworkは、**フォルダ、ネットワーク、コネクター、拡張機能、利用者、監視については企業向けの制御手段が揃いつつあります**。

一方で、特に次の3点は企業導入時の制約です。

1. **Cowork固有のコマンド単位denyポリシーが確認できない**
2. **ローカルCoworkの承認モードを管理者が完全に固定できるか不明**
3. **ローカル履歴・VM内部活動を既存の監査ログやEDRで完全に把握できない**

したがって、導入方式としては、Anthropic組織設定だけに依存せず、**Claude DesktopのWindowsポリシー、Windows OSのアクセス制御、外部サービス側の権限、OpenTelemetry監視を組み合わせることが前提**になります。

[1]: https://support.claude.com/en/articles/13455879-cowork-for-team-and-enterprise-plans "https://support.claude.com/en/articles/13455879-cowork-for-team-and-enterprise-plans"
[2]: https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop "https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop"
[3]: https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview "https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview"
[4]: https://docs.anthropic.com/ja/docs/claude-code/permissions "https://docs.anthropic.com/ja/docs/claude-code/permissions"
[5]: https://support.claude.com/en/articles/13930452-manage-custom-roles-on-enterprise-plans "https://support.claude.com/en/articles/13930452-manage-custom-roles-on-enterprise-plans"
[6]: https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude "https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude"
[7]: https://support.claude.com/en/articles/11176164-use-connectors-to-extend-claude-s-capabilities "https://support.claude.com/en/articles/11176164-use-connectors-to-extend-claude-s-capabilities"
[8]: https://support.claude.com/en/articles/13065128-claude-in-chrome-admin-controls "https://support.claude.com/en/articles/13065128-claude-in-chrome-admin-controls"
[9]: https://support.claude.com/en/articles/14477985-monitor-cowork-activity-with-opentelemetry "https://support.claude.com/en/articles/14477985-monitor-cowork-activity-with-opentelemetry"
[10]: https://support.claude.com/en/articles/12592343-enabling-and-using-the-desktop-extension-allowlist "https://support.claude.com/en/articles/12592343-enabling-and-using-the-desktop-extension-allowlist"
[11]: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/icacls "https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/icacls"
[12]: https://learn.microsoft.com/en-us/defender-endpoint/controlled-folder-access-configure "https://learn.microsoft.com/en-us/defender-endpoint/controlled-folder-access-configure"
[13]: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol-and-applocker-overview "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol-and-applocker-overview"
[14]: https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows "https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows"
[15]: https://support.claude.com/en/articles/13364135-use-claude-cowork-safely "https://support.claude.com/en/articles/13364135-use-claude-cowork-safely"
[16]: https://support.anthropic.com/en/articles/13132885-setting-up-single-sign-on-sso "https://support.anthropic.com/en/articles/13132885-setting-up-single-sign-on-sso"
[17]: https://support.anthropic.com/en/articles/10440198-custom-data-retention-controls-for-claude-enterprise "https://support.anthropic.com/en/articles/10440198-custom-data-retention-controls-for-claude-enterprise"
[18]: https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork "https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork"
