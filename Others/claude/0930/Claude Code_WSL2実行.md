はい。**Windows上のClaudeデスクトップアプリはそのまま使用し、Codeタブの実行環境に「WSL2のディストリビューション」を選び、その中でClaude Codeのサンドボックスを有効にする**構成です。現行の公式仕様では、この使い方がサポートされています。:chatgpt-content-reference{index="0"}

ただし、**「WSL2がインストール済み」「クラウドにsettings.jsonを登録済み」だけでは、WSL2内でサンドボックス実行されていることにはなりません。** 実行環境の選択、WSL内の依存パッケージ、管理設定の適用を、それぞれ確認します。:chatgpt-content-reference{index="1"}

以下は、**2026年9月30日に確認した公式仕様と、添付設定ファイルに基づく手順**です。ディストリビューションはUbuntuを例にします。

## 1．最初に理解しておく構成

ここでいう「クラウドのsettings.json」は、**Claudeの管理コンソールに登録するManaged settings／サーバー管理設定**として説明します。設定をクラウドから配信することと、コードをクラウド環境で実行することは別です。:chatgpt-content-reference{index="2"}

```text
Claudeの管理コンソール
  └─ Managed settings：組織の設定を配信
               ↓
WindowsのClaudeデスクトップアプリ
  └─ Codeタブ
       └─ 実行環境として「WSL → Ubuntu」を選択
               ↓
WSL2／Ubuntu内のClaude Code
  └─ Bashコマンドをサンドボックス内で実行
       ├─ ファイルアクセス制限
       └─ ネットワークアクセス制限
```

**Windowsネイティブの実行と、WSL2内の実行を混同しないことが重要です。** Claude Code組み込みのサンドボックスはWSL2に対応していますが、Windowsネイティブには対応していません。:chatgpt-content-reference{index="3"}

なお、以下のセットアップ用コマンドは、**IT担当者や利用者が通常のPowerShell／Ubuntuターミナルで実行するもの**です。Claudeに`sudo`などを実行させる手順ではありません。

---

## 2．添付の設定で、導入前に確認する項目

添付設定には、サンドボックスを必須にする主要な指定が入っています。

```json
"sandbox": {
  "enabled": true,
  "failIfUnavailable": true,
  "autoAllowBashIfSandboxed": false,
  "allowUnsandboxedCommands": false,
  "excludedCommands": []
}
```

これは添付ファイルの抜粋です。**既存設定全体を、この抜粋だけで置き換えないでください。**:chatgpt-content-reference{index="4"}

この指定では、サンドボックスが初期化できない場合の起動を止め、Claudeが失敗したコマンドをサンドボックス外で再実行する経路を禁止します。:chatgpt-content-reference{index="5"}

一方、次の値は導入環境に合わせた確認が必要です。

| 添付設定の項目 | 導入前の確認 |
|---|---|
| `forceLoginOrgUUID` | `00000000-0000-4000-8000-000000000000`は、実際の企業組織UUIDに置き換えます。添付時にマスキングした値なら、実設定を確認します。 |
| `requiredMinimumVersion`／`requiredMaximumVersion` | 両方とも`2.1.237`です。これは**2.1.237だけを起動可能にする指定**です。 |
| `sandbox.network.allowedDomains` | `example.com`と`api.example.com`です。本番で必要な、企業が承認した接続先に変更します。 |

上記の値は、添付ファイルに記載されています。:chatgpt-content-reference{index="6"} :chatgpt-content-reference{index="7"}

**特にバージョン固定に注意してください。** 許可範囲外のClaude Codeは起動を拒否されるため、Desktopから実際に起動されるエンジンの版と設定を整合させる必要があります。デスクトップアプリを更新するだけ、または利用者が上限設定だけを外す、といった対応にはしないでください。:chatgpt-content-reference{index="8"}

---

## 3．Windows側でWSL2と利用許可を確認する

### 3-1．ディストリビューションがWSL2であることを確認

**WindowsのPowerShell**で実行します。

```powershell
wsl --list --verbose
```

表示例：

```text
  NAME       STATE       VERSION
* Ubuntu     Stopped     2
```

使用するディストリビューションの`VERSION`が**2**であることを確認してください。その後、次のように起動します。`Ubuntu`の部分は実際に表示された名前に置き換えます。:chatgpt-content-reference{index="9"}

```powershell
wsl --distribution Ubuntu --cd ~
```

### 3-2．企業管理端末では、DesktopのWSLセッション許可を確認

ここは企業導入で重要な点です。

Claude Desktopは、組織管理端末と判定したWindows端末では、WSLセッションを既定で無効にする場合があります。管理者が許可するには、**Claude Desktop v1.19367.0以降**で、次のWindowsポリシーを設定します。:chatgpt-content-reference{index="10"}

```text
キー：HKLM\SOFTWARE\Policies\Claude
名前：disableWslSessions
種類：REG_DWORD
値　：0
```

IT管理者が、**管理者として起動したPowerShell**で設定する例です。

```powershell
New-Item -Path 'HKLM:\SOFTWARE\Policies\Claude' -Force | Out-Null

New-ItemProperty `
  -Path 'HKLM:\SOFTWARE\Policies\Claude' `
  -Name 'disableWslSessions' `
  -PropertyType DWord `
  -Value 0 `
  -Force | Out-Null
```

**設定先は`Claude`キーです。Claude Codeの管理設定を入れる`ClaudeCode`キーとは別です。** また、HKCUに設定してもWSLセッションの許可にはなりません。:chatgpt-content-reference{index="11"}

### 3-3．Windows側の管理設定をWSLにも継承する場合

Windows側にも管理設定を配布している場合、WSLがそれを自動的に読むとは限りません。継承させるには、Windowsの管理者管理下の設定に次を追加します。:chatgpt-content-reference{index="12"}

```json
"wslInheritsWindowsSettings": true
```

配布先は、WindowsのHKLM管理設定、または次のファイルです。

```text
C:\Program Files\ClaudeCode\managed-settings.json
```

**このキーはクラウドのManaged settingsに追加しても有効になりません。** OS側の管理設定として配布する必要があります。なお、これは「Windows側ポリシーの継承」の設定であり、WSL内のClaude Codeがクラウド設定を受信するための必須条件とは別です。:chatgpt-content-reference{index="13"}

---

## 4．Ubuntu内にサンドボックスの依存パッケージを入れる

ここからは、**WSLのUbuntuターミナル**で実行します。

### 4-1．必要なパッケージをインストール

```bash
sudo apt-get update
sudo apt-get install -y git bubblewrap socat curl ca-certificates
```

今回の構成で重要なのは、WSLセッションに必要な`git`と、サンドボックスのファイル隔離・通信制御に使う`bubblewrap`、`socat`です。`curl`は後述の疎通試験にも使用します。:chatgpt-content-reference{index="14"}

インストール後、次で確認します。

```bash
git --version
command -v bwrap
command -v socat
```

`bwrap`と`socat`について、実行ファイルのパスが表示されることを確認します。

### 4-2．Unixソケット制限用のseccompフィルターも確認

添付設定には、次の指定があります。:chatgpt-content-reference{index="15"}

```json
"allowAllUnixSockets": false
```

ただし、**Linux／WSL2でUnixソケットを実際に遮断するには、seccompフィルターが利用可能である必要があります。** 利用できない場合、警告が出てソケット制限が効かない構成になり得ます。:chatgpt-content-reference{index="16"}

不足している場合、公式手順では次のパッケージを使用します。企業で承認したNode.js／npmを準備したうえで、IT管理者の配布方法に従って導入してください。:chatgpt-content-reference{index="17"}

```bash
npm install -g @anthropic-ai/sandbox-runtime
```

ここでは、Claude Code全体を別の` srt `コマンドで起動する構成に変更するのではなく、**組み込みサンドボックスで使う依存機能を整える**ための導入です。

WSLからWindowsプログラムを起動する連携もUnixソケットを使用するため、Windows側への実行経路を制限するうえで、この確認は重要です。:chatgpt-content-reference{index="18"}

### 4-3．Ubuntuで`Operation not permitted`が出る場合

Ubuntu 24.04以降では、AppArmorによるユーザー名前空間の制限が関係する場合があります。確認コマンドは次です。:chatgpt-content-reference{index="19"}

```bash
sysctl kernel.apparmor_restrict_unprivileged_userns
```

`1`の場合は、IT管理者が公式手順に沿って`bwrap`用のAppArmor許可を設定します。**動かすためだけにサンドボックスを無効化したり、添付の`enableWeakerNestedSandbox`を`true`に変更したりしないでください。** 後者は隔離を弱める設定です。:chatgpt-content-reference{index="20"}

---

## 5．WSL内に専用の作業フォルダーを用意する

添付設定では、作業用の読み書き許可先が`~/claude_work`になっています。まずは、この下に検証用フォルダーを作ります。:chatgpt-content-reference{index="21"}

**Ubuntuターミナルで、普段使用する一般ユーザーとして**実行してください。

```bash
mkdir -p "$HOME/claude_work/sandbox-demo"
cd "$HOME/claude_work/sandbox-demo"

printf 'sandbox test\n' > allowed.txt
pwd
```

表示例：

```text
/home/tanaka/claude_work/sandbox-demo
```

この`~`は、**WSL内のLinuxユーザーのホームディレクトリ**です。Windows側の`C:\Users\...`ではありません。サンドボックス設定の`~/`はホームディレクトリ基準で解決されます。:chatgpt-content-reference{index="22"}

**今回の設定では、`/mnt/c/...`を作業フォルダーに選ばないでください。** 添付ファイルは、`/mnt`以下の読み書きを拒否する指定になっています。:chatgpt-content-reference{index="23"} :chatgpt-content-reference{index="24"}

最初の検証は、この空の検証用フォルダーで行い、本番リポジトリや秘密情報を入れるのは動作確認後にすることを勧めます。

---

## 6．クラウドの管理設定を配信し、CodeタブからWSLを選択する

### 6-1．管理コンソール側

組織のOwner／Primary Ownerが、次の画面で添付設定を基にしたJSONを保存します。

```text
Admin Settings
  → Claude Code
    → Managed settings
```

通常のローカル`~/.claude/settings.json`に保存するだけでは、企業のManaged settingsとしての配布にはなりません。サーバー管理設定は起動時に取得され、実行中も定期的に更新されます。:chatgpt-content-reference{index="25"}

また、**この配信は組織内の利用者へ一律に適用されます。** Windowsネイティブで使用している既存ユーザーがいる場合、サンドボックス必須化で起動できなくなる影響も含め、展開前に確認してください。:chatgpt-content-reference{index="26"}

### 6-2．デスクトップアプリ側

WindowsのClaudeデスクトップアプリで、次の操作を行います。

1. **企業のClaudeアカウントでログインし、Codeタブを開く。**
2. **新しいセッションを作り、実行環境の選択メニューを開く。**
3. **「WSL」セクションから、準備したUbuntuを選択する。**
4. **フォルダー選択で、`/home/ユーザー名/claude_work/sandbox-demo`を選ぶ。**
5. **初回のフォルダー信頼確認で、対象フォルダーが正しいことを確認して開始する。**

公式のWSL接続手順は、この流れです。初回はDesktop側がディストリビューション内のセットアップを行います。:chatgpt-content-reference{index="27"}

**実行環境は「Local」や「Cloud」ではなく、「WSL内のUbuntu」を選びます。** また、初回検証の権限モードは`Manual`にしてください。Desktopではフォルダーごとに以前選んだモードが記憶されるため、`defaultMode`の設定だけに頼らず画面で確認します。:chatgpt-content-reference{index="28"}

---

## 7．実際にWSL2＋サンドボックスで動いているか確認する

### 7-1．まず実行場所を確認

**Codeタブの会話欄**から、次のように依頼します。

```text
Bashツールで、次のコマンドを一つずつ実行してください。
ファイルの変更はしないでください。

uname -s
pwd
id -u
```

確認する結果は、OSが`Linux`、作業場所が`/home/.../claude_work/...`、ユーザーIDが`0`以外であることです。

これは、今回の構成に対する確認用のテストです。**Claudeの文章による「WSLで動いています」という説明だけでなく、実際のツール実行結果を確認してください。**

### 7-2．許可と拒否を別々に試験

次は、添付設定に対する受入試験例です。ファイルはすべてダミーを使ってください。

| 試験 | 期待する結果 |
|---|---|
| 作業フォルダー内の`allowed.txt`を読む | 読める |
| 作業フォルダー内のファイルを編集する | 承認を求められ、承認後に編集できる |
| **Bashで**`~/claude_work`外のホーム内ダミーファイルを読む | サンドボックスで拒否される |
| `/mnt/c`配下のWindows側ダミーファイルを読む | 拒否される |
| Bashの`curl`で許可済みの検証ホストへ接続する | 接続できる |
| Bashの`curl`で許可リストにない検証ホストへ接続する | 拒否される |

この期待値は、添付ファイルの編集確認、`/mnt`拒否、ホーム配下の読み取り制限、およびネットワーク許可リストから整理したものです。:chatgpt-content-reference{index="29"} :chatgpt-content-reference{index="30"}

ホーム外ではなく、**ホーム内の作業フォルダー外**を試すため、事前に通常のUbuntuターミナルで、専用のダミーファイルを作っておくと確認しやすくなります。

```bash
printf 'dummy data only\n' > "$HOME/claude-sandbox-deny-probe.txt"
```

その後、Codeタブから、**Bashツールで**次を実行するよう依頼します。

```bash
cat "$HOME/claude-sandbox-deny-probe.txt"
```

この試験では、利用者が承認画面で「拒否」を押したことを合格にしないでください。無害な試験内容を承認した後でも、**設定によってアクセスが阻止されるか**を確認します。通信試験も、単なるDNSエラーやタイムアウトではなく、許可リストによる拒否であることを確認します。

### 7-3．管理設定・依存関係の診断はCLIと区別する

診断用のスタンドアロンCLIを併用する場合は、**同じWSLディストリビューション内で、同じ企業組織にログインしたCLI**を使用します。

```bash
claude --version
claude doctor
```

対話セッションでは、次を確認します。

```text
/status
/sandbox
/permissions
```

`/status`では管理設定の適用元、`/sandbox`では有効な設定と依存関係を確認します。クラウド設定が選択されている場合、設定元は`Enterprise managed settings (remote)`として表示されます。:chatgpt-content-reference{index="31"}

ただし、**Desktopでは`/permissions`などの端末ダイアログ型コマンドが利用できません。** Desktopの会話欄で、CLIと同じ診断画面が必ず開くとは考えないでください。CLIでの確認は補助とし、Desktop側でも前述の試験を実施します。:chatgpt-content-reference{index="32"}

また、`claude doctor`の`Managed settings (remote)`診断行は**v2.1.248以降**の機能です。添付どおり`2.1.237`を使用する場合、その診断行が表示されないことだけで配信失敗と判断してはいけません。:chatgpt-content-reference{index="33"}

---

## 8．企業導入で、添付設定に加えて押さえるべき限界

### 「作業フォルダー以外は、すべてのツールで読み取り禁止」ではありません

組み込みサンドボックスによるOSレベルの制限は、主にBashなどのシェルコマンドとその子プロセスに適用されます。**Read／Edit／Writeなどの組み込みファイルツールは、別の権限システムで制御されます。**:chatgpt-content-reference{index="34"}

添付設定の`Read(~/claude_work/**)`は、その範囲の読み取りを許可するルールです。それだけで、ほかの場所すべての読み取りが禁止になるわけではありません。添付のRead拒否ルールは`/mnt`向けなので、秘密情報へのアクセス制御は別途確認が必要です。:chatgpt-content-reference{index="35"} :chatgpt-content-reference{index="36"}

### `excludedCommands: []`だけで、利用者による例外追加まで完全には防げません

現行の公式仕様では、`excludedCommands`は複数の設定スコープから追加され得て、専用の「管理者設定だけを認める」ロックがありません。**添付設定だけで、利用者が一切変更できない強制隔離環境になったとは評価しないでください。**:chatgpt-content-reference{index="37"}

### 初回起動も「クラウド設定が取得できなければ停止」にする場合

添付には`forceRemoteSettingsRefresh: true`がありますが、**初回にまだクラウド設定を受信していない端末にも強制するには、端末側の管理設定への事前配布が必要です。** WSL側の管理ファイルは、次の場所です。:chatgpt-content-reference{index="38"} :chatgpt-content-reference{index="39"}

```text
/etc/claude-code/managed-settings.json
```

Windows側から継承させる設計にする場合は、前述の`wslInheritsWindowsSettings`と合わせて管理します。

### ローカル実行でも、AI処理は端末内だけでは完結しません

WSL内で動くのはClaude Codeの実行プロセスやツールです。ローカルセッションでも、会話や必要なコードコンテキストは、構成したモデル提供先へ送信されます。**「WSLサンドボックス＝コードが一切クラウドへ送信されない」ではありません。**:chatgpt-content-reference{index="40"}

---

今回の案件では、まず**「承認済みバージョンの整合 → 企業端末でのWSL許可 → Ubuntu内の依存関係整備 → `~/claude_work`作成 → CodeタブでWSL選択 → 許可・拒否の実測」**の順で進めるのがよいです。

**導入完了の判断は、画面にWSLと表示されることではなく、Desktopの実際のセッションで管理設定が効き、禁止したファイルアクセスと通信が拒否されることを確認してから行ってください。**
