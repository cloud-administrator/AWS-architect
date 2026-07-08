## 調査結果の結論

2026年7月8日時点で、**Anthropic / Claude公式ドキュメントのみ**を参照した結果です。

| 論点                                               | 判定                                                                                   |
| ------------------------------------------------ | ------------------------------------------------------------------------------------ |
| Windows端末でClaude Code CLIを使えるか                   | **可能**                                                                               |
| Windows版VS Code拡張として使えるか                         | **可能**                                                                               |
| 企業で一括・最上位レベルのポリシーを適用できるか                         | **可能**                                                                               |
| 「共有フォルダをClaude Codeの作業フォルダにすること」を専用ポリシーで一括禁止できるか | **公式資料上、専用機能は確認できず。不明**                                                              |
| 共有フォルダ利用を実質的に抑止・制限する方法                           | **Managed settings、permission rules、hooks、OS/MDM配布で近い制御は可能。ただし完全な“起動前ブロック”とは言い切れない** |

---

## 1. Windows端末でClaude Code CLIは使用可能

Claude Codeは、WindowsでCLIとして利用できます。公式ドキュメントでは、Windows 10 1809以降、またはWindows Server 2019以降が要件として記載されています。シェルはPowerShell、CMD、Bash、Zshがサポート対象です。([Claude Platform Docs][1])

Windowsでのインストール方法として、公式には以下が案内されています。

```powershell
irm https://claude.ai/install.ps1 | iex
```

または、WinGetを使う場合は以下です。

```powershell
winget install Anthropic.ClaudeCode
```

公式ドキュメントでは、Windowsネイティブ環境ではGit for Windowsの利用が推奨されています。Git for Windowsがある場合はBashツールが使われ、ない場合はPowerShellツールにフォールバックします。WSL環境ではGit for Windowsは不要です。([Claude Platform Docs][2])

初心者向けに言うと、**CLI利用**とは、PowerShellやコマンドプロンプト、VS Codeのターミナルで次のように実行する使い方です。

```powershell
claude
```

Claude Codeは、コマンドを実行したフォルダを作業対象として扱います。公式ドキュメントでも、プロジェクトディレクトリでターミナルを開き、`claude`を実行する使い方が案内されています。([Claude Platform Docs][2])

---

## 2. Windows版VS Code拡張としてClaude Codeは使用可能

Claude CodeはVS Code拡張として利用できます。公式ドキュメントでは、VS Code拡張はClaude CodeをVS Code内で使うための推奨方法と説明されています。([Claude Platform Docs][3])

VS Code拡張の前提条件は、公式上は次のとおりです。

| 項目           | 内容                                                             |
| ------------ | -------------------------------------------------------------- |
| VS Codeバージョン | VS Code 1.98.0以上                                               |
| アカウント        | Claude Pro / Max / Team / Enterprise、またはAnthropic Consoleアカウント |
| APIキー        | VS Code拡張のチャットパネル利用では不要                                        |
| CLI          | VS Code内の統合ターミナルで`claude`コマンドを使う場合は、別途スタンドアロンCLIが必要            |

VS Code拡張はそれ自体にCLIをバンドルしており、チャットパネル利用は拡張だけで可能です。ただし、VS Codeのターミナルで`claude`と打って使いたい場合は、WindowsにCLIを別途インストールする必要があります。([Claude Platform Docs][3])

つまり、企業導入時の整理としては次の理解でよいです。

| 利用形態                         | 可能か | 補足                 |
| ---------------------------- | --: | ------------------ |
| VS Code拡張のGUIから使う            |  可能 | 拡張機能をインストール        |
| VS Codeのターミナルで`claude`を実行    |  可能 | CLIのインストールが必要      |
| PowerShell / CMDで`claude`を実行 |  可能 | Windows CLIとして利用   |
| WSL2内でClaude Codeを使う         |  可能 | サンドボックス利用時はWSL2が重要 |

---

## 3. 企業で一括・最上位レベルのポリシー適用は可能

Claude Codeには**Managed settings**という仕組みがあります。これは、ユーザー個人やプロジェクト設定より上位にある管理者向け設定です。公式ドキュメントでは、Managed settingsは最も高い優先順位を持ち、ユーザー設定・プロジェクト設定・コマンドライン引数では上書きできないと説明されています。([Claude Platform Docs][4])

企業で一括適用する方法は、大きく分けて次の2系統です。

### A. Claude管理コンソールから配布する方法

Claude Team / Enterpriseでは、管理者がClaude管理コンソールからClaude CodeのManaged settingsを設定できます。公式ドキュメントでは、組織OwnerまたはPrimary Ownerが、管理画面からJSON形式の設定を配布できるとされています。([Claude][5])

この方式は、管理対象外端末やクラウド利用も含めて、組織全体に設定を配布しやすい点が利点です。ただし、公式ドキュメント上の制限として、サーバー管理設定は全ユーザーに一律適用され、ユーザーグループ単位のポリシー分けは未対応とされています。([Claude][5])

### B. Windows端末側にMDM / GPO / ファイルで配布する方法

Windows端末では、以下のような方法でManaged settingsを配布できます。

| 方法                 | 配布先                                                 |
| ------------------ | --------------------------------------------------- |
| WindowsレジストリHKLM   | `SOFTWARE\Policies\ClaudeCode`                      |
| ファイルベース            | `C:\Program Files\ClaudeCode\managed-settings.json` |
| MDM / GPO / Intune | 上記レジストリやファイルを配布                                     |

公式ドキュメントでは、HKLMやProgram Files配下の設定は管理者権限が必要で、ユーザーによる改変に強い方式として説明されています。一方、HKCUはユーザー書き込み可能なので、強制力のある企業統制には向きません。([Claude Platform Docs][4])

また、同じManaged settingsはCLI、VS Code拡張、JetBrains IDE連携に対して同じ優先順位で適用されると説明されています。([Claude Platform Docs][4])

---

## 4. 共有フォルダを「作業フォルダ」にすることを禁止できるか

ここが最も重要な点です。

公式ドキュメント上、**「Claude Codeを共有フォルダで起動できないようにする」専用のManaged settingは確認できませんでした。**
たとえば、`disallowWorkingDirectory`、`blockedWorkingDirectories`、`denyCwd`のような、作業フォルダそのものを一括禁止する明示的な設定項目は、確認した公式資料には見当たりませんでした。

したがって、厳密な回答は以下です。

> **共有フォルダをClaude Codeの作業フォルダとして使うことを、Claude Codeの公式設定だけで完全に一括禁止できるかは不明です。公式ドキュメント上は、専用機能としては確認できません。**

ただし、近い制御は複数あります。

---

## 5. 共有フォルダ利用を抑止するために使える公式機能

### 5.1 Permission rulesで共有フォルダへのRead / Editを禁止する

Claude Codeには、読み取り・編集・コマンド実行などを制御するpermission rulesがあります。公式ドキュメントでは、`allow`、`ask`、`deny`のルールを設定でき、`deny`が最優先で評価されると説明されています。([Claude][6])

たとえば、共有ドライブをZドライブに割り当てている場合、管理設定で以下のような考え方ができます。

```json
{
  "allowManagedPermissionRulesOnly": true,
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "deny": [
      "Read(//z/**)",
      "Edit(//z/**)"
    ]
  }
}
```

ただし、注意点があります。公式ドキュメントでは、WindowsパスはClaude Code内部ではPOSIX風に正規化されると説明されています。例として、`C:\Users\alice`は`/c/Users/alice`のように扱われ、権限パターンでは`//c/...`のような形式を使うとされています。([Claude][6])

そのため、**UNCパス、たとえば`\\server\share`のようなネットワーク共有がClaude Codeのpermission patternでどう正規化されるかは、公式資料上では確認できませんでした。**
この点は**不明**です。実機検証が必要です。

また、Read / Editのpermission rulesは、Claude Codeの組み込みファイル操作や、Claude Codeが認識できる一部のBashファイル操作に効くものです。公式ドキュメントでは、PythonやNode.jsなどのサブプロセスが間接的にファイルを読み書きするケースには完全には適用されず、OSレベルの強制にはsandboxを使うよう説明されています。([Claude][6])

---

### 5.2 `/cd`で共有フォルダへ移動することは制御できる

Claude Codeには、セッション中に作業ディレクトリを変える`/cd`コマンドがあります。公式ドキュメントでは、`Cd` permission ruleによって、ユーザーが`/cd`で移動できるディレクトリを制御できると説明されています。([Claude][6])

たとえば、セッション中に共有ドライブへ移動することを禁止したい場合は、次のような考え方ができます。

```json
{
  "permissions": {
    "deny": [
      "Cd(//z/**)"
    ]
  }
}
```

ただし、公式ドキュメントでは、`Cd`ルールは**ユーザーが`/cd`を実行したときだけ**適用されると説明されています。つまり、最初から共有フォルダで`claude`を起動した場合に、それだけで起動を止める機能とは説明されていません。([Claude][6])

---

### 5.3 Hooksで現在の作業フォルダを検査してブロックする

Claude Codeにはhooksという仕組みがあります。これは、セッション開始時、ユーザープロンプト送信時、ツール実行前などに、管理者が用意したスクリプトを実行する機能です。公式ドキュメントでは、hooksはClaude Codeのライフサイクルイベントで自動実行され、ルール適用や監査に使えると説明されています。([Claude Platform Docs][7])

hooksの入力には現在の作業ディレクトリ、つまり`cwd`が含まれます。([Claude Platform Docs][7])

このため、企業側で管理されたhookを配布し、`cwd`が共有フォルダに該当する場合は、次のような制御を行う設計が考えられます。

```text
このフォルダではClaude Codeを利用できません。
ローカルの作業用リポジトリに移動してからClaude Codeを起動してください。
```

実装上は、`UserPromptSubmit` hookでユーザーの最初の入力をブロックしたり、`PreToolUse` hookでツール実行前にブロックしたりする構成が考えられます。公式ドキュメントでは、`UserPromptSubmit`や`PreToolUse`はブロック可能なhookとして説明されています。([Claude Platform Docs][7])

ただし、これにも制限があります。公式ドキュメントでは、`SessionStart` hookはセッション開始時に実行されますが、ブロックには使えないとされています。また、`CwdChanged` hookも作業ディレクトリ変更イベントを検知できますが、ブロック制御はできません。([Claude Platform Docs][7])

したがって、hooksによる制御はかなり有効ですが、厳密には次の評価になります。

> **Claude Codeの起動そのものを止めるというより、共有フォルダ上でのプロンプト処理やツール利用を止める実装に近いです。**

---

### 5.4 Native Windowsではsandboxが使えない

Claude Codeにはsandbox機能があります。これは、Bashコマンドやその子プロセスが触れるファイルやネットワークをOSレベルで制限する仕組みです。([Claude][8])

ただし重要な制約として、公式ドキュメントではsandboxはmacOS、Linux、WSL2で利用可能で、**Native Windowsではサポートされない**と明記されています。Windowsでsandboxを使う場合は、WSL2内でClaude Codeを実行する必要があります。([Claude][8])

つまり、Windows端末で次のように整理できます。

| 実行環境           | sandbox利用 | コメント                        |
| -------------- | --------: | --------------------------- |
| Native Windows |        不可 | 公式上サポート外                    |
| WSL1           |        不可 | 公式上sandbox非対応               |
| WSL2           |        可能 | Windowsでsandboxを使うなら現実的な選択肢 |

ただし、sandboxは主にBashコマンドや子プロセスをOSレベルで制限する機能です。共有フォルダを「作業フォルダとして選ばせない」専用機能ではありません。

---

## 6. 企業導入時の推奨構成

公式情報に基づくと、現実的な推奨構成は次のとおりです。

### 推奨1：Managed settingsを必ず使う

Claude Enterprise導入であれば、Claude管理コンソールのserver-managed settingsと、Windows側のHKLM / Program Files配布を併用する設計が有力です。公式ドキュメントでは、server-managed settingsはTeam / Enterpriseで使え、管理者が組織全体に設定を配布できるとされています。([Claude][5])

ただし、初回起動時のserver-managed settings取得には注意が必要です。公式ドキュメントでは、初回起動でキャッシュがない場合、設定取得は非同期で行われ、取得失敗時には管理設定なしで継続する場合があると説明されています。([Claude][5])

厳格な端末統制が必要な場合は、Windows端末側にHKLMレジストリまたは`C:\Program Files\ClaudeCode\managed-settings.json`で設定を配布する方式も検討すべきです。([Claude Platform Docs][4])

---

### 推奨2：ユーザー側で権限ルールを緩められないようにする

共有フォルダを制限したい場合、まずユーザーやプロジェクト設定でpermission rulesを追加・変更できないようにする必要があります。

公式ドキュメントでは、`allowManagedPermissionRulesOnly`というManaged-only設定が用意されており、Managed settings以外のpermission rulesを無視させる用途で説明されています。また、`disableBypassPermissionsMode`により、ユーザーが権限確認を迂回するモードを無効化できます。([Claude][6])

考え方としては、以下のような設定です。

```json
{
  "allowManagedPermissionRulesOnly": true,
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "deny": [
      "Read(//z/**)",
      "Edit(//z/**)",
      "Cd(//z/**)"
    ]
  }
}
```

これはあくまで例です。実際には、企業の共有フォルダがドライブレターなのか、UNCパスなのか、VDI上なのか、OneDrive同期なのかによって、パターン検証が必要です。

---

### 推奨3：Managed hooksで`cwd`を検査する

permission rulesだけでは、「最初から共有フォルダでClaude Codeを起動する」ケースを完全には止められません。

そのため、Managed settingsでhooksを配布し、`cwd`が禁止パスに該当した場合に、`UserPromptSubmit`や`PreToolUse`でブロックする設計が現実的です。公式ドキュメントでは、Managed settingsにhooksを含めることができ、管理されたhooksはユーザーやプロジェクト側の設定では無効化できないと説明されています。([Claude][5])

ただし、前述のとおり、これは「起動そのものの禁止」ではなく、「共有フォルダでの利用処理を止める」設計です。

---

### 推奨4：Native Windowsで厳格制御が必要なら、Claude Code外のOS/端末管理も必要

公式Claude Codeドキュメントだけを見る限り、Native Windowsで「共有フォルダを作業フォルダにして起動すること」を完全に禁止する専用機能は確認できませんでした。

したがって、厳格に以下を満たしたい場合：

```text
共有フォルダ上ではClaude Codeプロセス自体を起動させない
```

Claude CodeのManaged settingsだけではなく、Windows側の端末管理、MDM、GPO、アプリ制御、ファイルサーバー側ACLなど、Claude Code外の統制も検討する必要があります。
ただし、この部分はClaude公式ドキュメントの範囲外なので、今回の公式Claude調査としては**不明**とします。

---

## 最終判断

### Claude CodeをWindows端末のVS Code拡張またはCLIで使えるか

**使えます。**
CLIもVS Code拡張も、公式ドキュメント上サポートされています。

### 会社ポリシーとして、共有フォルダをClaude Codeの作業フォルダにされたくない場合、一括で最上位レベルのポリシーを適用できるか

**一括で最上位レベルのポリシーを適用すること自体は可能です。**
Managed settingsを使えば、CLI・VS Code拡張に対して、ユーザーが上書きできない設定を配布できます。

ただし、**「共有フォルダを作業フォルダとして起動すること」を直接禁止する専用設定は、公式ドキュメント上確認できませんでした。**
現実的には、次の組み合わせで実装するのが妥当です。

1. Managed settingsをHKLM / Program Files / Claude管理コンソールから配布する
2. `allowManagedPermissionRulesOnly`でユーザー側の権限追加を禁止する
3. `Read` / `Edit` / `Cd`のdeny ruleで共有フォルダへのアクセスや移動を制限する
4. Managed hooksで`cwd`を検査し、共有フォルダ上でのプロンプト送信やツール実行をブロックする
5. Native Windowsで厳格な起動禁止が必要なら、Claude Code外のWindows端末管理も別途検討する

結論として、**企業導入は可能ですが、「共有フォルダを作業フォルダにさせない」要件は、Claude Code単体の公式機能だけで完全に満たせるとは断定できません。**

[1]: https://docs.anthropic.com/en/docs/claude-code/setup "Advanced setup - Claude Code Docs"
[2]: https://docs.anthropic.com/en/docs/claude-code/quickstart "Quickstart - Claude Code Docs"
[3]: https://docs.anthropic.com/en/docs/claude-code/ide-integrations "Use Claude Code in VS Code - Claude Code Docs"
[4]: https://docs.anthropic.com/en/docs/claude-code/settings "Claude Code settings - Claude Code Docs"
[5]: https://code.claude.com/docs/en/server-managed-settings "Configure server-managed settings - Claude Code Docs"
[6]: https://code.claude.com/docs/en/permissions "Configure permissions - Claude Code Docs"
[7]: https://docs.anthropic.com/en/docs/claude-code/hooks "Hooks reference - Claude Code Docs"
[8]: https://code.claude.com/docs/en/sandboxing "Configure the sandboxed Bash tool - Claude Code Docs"





◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆




以下は**Claude / Anthropic公式ドキュメントのみ**を根拠に、2026年7月8日時点で整理したものです。
結論から言うと、Managed settingsではかなり広範囲の統制ができますが、**Claude Codeクライアント側の設定機構であり、OSレベルの完全なセキュリティ境界ではありません**。

---

# 1. Managed settingsとは

Managed settingsは、Claude Codeの設定階層の中で最上位にある**管理者向けポリシー設定**です。ユーザー設定、プロジェクト設定、ローカル設定、CLI引数より優先され、通常のユーザー操作では上書きできません。公式ドキュメントでは、Managed settingsはユーザー設定と同じJSON形式を使い、中央管理・配布できる設定として説明されています。([Claude Platform Docs][1])

配布方法は大きく2種類あります。

| 種類                        | 概要                                        | 主な用途                                                   |
| ------------------------- | ----------------------------------------- | ------------------------------------------------------ |
| Server-managed settings   | Claude管理コンソールから組織全体に配布                    | Claude Team / Enterpriseで、未管理端末やクラウドセッションも含めて一律適用したい場合 |
| Endpoint-managed settings | MDM、GPO、レジストリ、Program Files配下ファイルなどで端末に配布 | 会社管理PCで強制力を高めたい場合                                      |

Server-managed settingsはClaude Team / Enterpriseで利用でき、OwnerまたはPrimary Ownerが管理できます。ただし、全ユーザーに一律適用され、公式上はグループ別ポリシーには未対応です。([Claude][2])

---

# 2. Managed settingsで設定できる項目の全体像

公式ドキュメント上、Managed settingsでは大きく次の領域を制御できます。

| 領域                     | できること                                                            |
| ---------------------- | ---------------------------------------------------------------- |
| 権限・ツール制御               | Read、Edit、Bash、WebFetch、MCPなどの許可・確認・拒否                           |
| モデル制御                  | 利用可能モデル、既定モデル、fallbackモデル、モデル制限                                  |
| 認証・ログイン制御              | Claude.aiログイン、Console/APIキー、Bedrock、Vertex AI、組織UUID、ゲートウェイURLなど |
| MCP制御                  | 利用可能MCPサーバー、禁止MCPサーバー、管理MCPのみ許可など                                |
| Hooks制御                | 管理者が定義したhookのみ許可、HTTP hook URL制限、環境変数制限                          |
| Sandbox制御              | Bashとその子プロセスのファイル・ネットワーク制限。ただしNative Windowsは対象外                 |
| Plugin / Marketplace制御 | 許可マーケットプレイス、禁止マーケットプレイス、サイドロード禁止、カスタマイズ制限                        |
| バージョン制御                | 最小・最大バージョン要求、更新チャネル                                              |
| UI / UX制御              | テーマ、言語、通知、表示モード、スクリーンリーダー、進捗表示など                                 |
| 組織向けカスタマイズ             | 管理CLAUDE.md、会社アナウンス、フッターリンク、ステータスラインなど                           |
| IDE / Remote Control関連 | Agent View、Remote Control、VS Code / IDE連携関連の一部設定                 |

---

# 3. Managed settingsで指定できる主なトップレベル項目

以下は、公式のClaude Code settingsリファレンスに出ている設定項目を、用途別に網羅整理したものです。Server-managed settingsでは、`settings.json`で利用可能な設定は基本的にサポートされますが、OSレベル配布に依存する一部設定は対象外です。([Claude][2])

## 3.1 モデル・推論・エージェント関連

| 設定キー                      | 何を制御するか                 | 備考                                              |
| ------------------------- | ----------------------- | ----------------------------------------------- |
| `model`                   | 既定モデル                   | Managedで指定すればユーザー側の既定値を統制可能                     |
| `fallbackModel`           | fallbackモデル             | 一部の配列・モデル系設定は通常のマージ規則と例外的に扱われる                  |
| `availableModels`         | 利用可能モデル一覧               | `enforceAvailableModels`と組み合わせると制限として機能         |
| `enforceAvailableModels`  | `availableModels`を強制するか | モデル制限の実効性に関わる                                   |
| `modelOverrides`          | モデルごとの上書き設定             | 特定用途のモデル指定に使う                                   |
| `advisorModel`            | アドバイザー用途のモデル            | モデル選択の一部                                        |
| `effortLevel`             | 推論努力量                   | Thinking / effort系の制御                           |
| `alwaysThinkingEnabled`   | 常時thinkingを有効化          | 推論挙動の既定値                                        |
| `showThinkingSummaries`   | thinking summaries表示    | UI表示制御                                          |
| `fastModePerSessionOptIn` | fast modeのセッション単位opt-in | セッション挙動                                         |
| `agent`                   | agent関連設定               | Agent利用挙動                                       |
| `teammateMode`            | teammate mode           | チーム・協調関連機能                                      |
| `ultracode`               | ultracode effort        | 公式上、通常のsettings.jsonから読む設定ではなく、セッション指定系として説明される |

---

## 3.2 権限・ツール利用関連

| 設定キー                              | 何を制御するか                               | 備考              |
| --------------------------------- | ------------------------------------- | --------------- |
| `permissions`                     | Claude Codeのツール権限全般                   | 最重要項目           |
| `allowManagedPermissionRulesOnly` | Managed settingsのpermission rulesのみ許可 | Managed専用       |
| `disableBypassPermissionsMode`    | 権限確認を迂回するモードの無効化                      | 通常はManagedで使うべき |
| `respondToBashCommands`           | Bashコマンドへの応答挙動                        | Bash利用時の挙動制御    |
| `skipWebFetchPreflight`           | WebFetchの事前確認挙動                       | Web取得時の確認制御     |
| `respectGitignore`                | `.gitignore`を尊重するか                    | ファイル探索・参照挙動に関係  |
| `includeGitInstructions`          | Git関連指示を含めるか                          | Claudeへの標準指示に影響 |
| `fileCheckpointingEnabled`        | ファイル変更チェックポイント                        | 変更管理            |
| `fileSuggestion`                  | ファイル候補提示                              | UI / 補助機能       |
| `claudeMd`                        | 管理者指定のCLAUDE.md                       | Managed専用       |
| `claudeMdExcludes`                | CLAUDE.mdの除外設定                        | 組織指示の読み込み範囲制御   |

Claude Codeのpermission rulesは、`allow`、`ask`、`deny`で構成され、評価順は`deny`が最優先です。公式ドキュメントでは、権限はモデルではなくClaude Code本体によって強制され、`CLAUDE.md`などのプロンプト指示だけでは許可範囲は変わらないと説明されています。([Claude][3])

---

## 3.3 認証・ログイン・API・クラウド連携関連

| 設定キー                   | 何を制御するか               | 備考                      |
| ---------------------- | --------------------- | ----------------------- |
| `forceLoginMethod`     | ログイン方式を強制             | Claude.ai / Console等の統制 |
| `forceLoginOrgUUID`    | ログイン先組織UUIDを強制        | 組織外利用の抑止に使う             |
| `forceLoginGatewayUrl` | ログインゲートウェイURLを強制      | Managed policyでのみ有効とされる |
| `apiKeyHelper`         | APIキー取得ヘルパー           | 端末側での認証統制               |
| `awsAuthRefresh`       | AWS認証更新               | Bedrock利用時              |
| `awsCredentialExport`  | AWS credential export | Bedrock利用時              |
| `gcpAuthRefresh`       | GCP認証更新               | Vertex AI利用時            |
| `otelHeadersHelper`    | OpenTelemetryヘッダー補助   | 監査・観測性連携                |
| `env`                  | Claude Code実行時の環境変数   | 認証・プロキシ・組織設定に使える        |

---

## 3.4 MCP関連

| 設定キー                         | 何を制御するか                   | 備考                                   |
| ---------------------------- | ------------------------- | ------------------------------------ |
| `allowedMcpServers`          | 許可するMCPサーバー               | 管理下のMCPだけ許可する用途                      |
| `deniedMcpServers`           | 禁止するMCPサーバー               | deny側の制御                             |
| `allowManagedMcpServersOnly` | Managedで許可されたMCPのみ利用可能にする | Managed専用                            |
| `allowAllClaudeAiMcps`       | Claude.ai側のMCPをすべて許可      | Managed専用                            |
| `disableClaudeAiConnectors`  | Claude.ai connectorsを無効化  | コネクタ制御                               |
| `enabledMcpjsonServers`      | `.mcp.json`内の有効サーバー       | プロジェクトMCP制御                          |
| `disabledMcpjsonServers`     | `.mcp.json`内の無効サーバー       | プロジェクトMCP制御                          |
| `enableAllProjectMcpServers` | すべてのプロジェクトMCPを有効化         | 一括有効化                                |
| `managed-mcp.json`           | MCPサーバーを管理者定義のみに限定        | これはManaged settingsのJSONキーではなく、別ファイル |

重要点として、`managed-mcp.json`を配布すると、そのファイルで定義されたMCPサーバーのみがロードされ、ユーザーは他のMCPサーバーを追加・変更・利用できなくなります。ただし、公式ドキュメント上、`managed-mcp.json`はServer-managed settingsでは配布できず、端末側のシステムパスに配布する必要があります。([Claude][4])

---

## 3.5 Hooks関連

| 設定キー                     | 何を制御するか                     | 備考                         |
| ------------------------ | --------------------------- | -------------------------- |
| `hooks`                  | Claude Code lifecycle hooks | セッション開始、ツール実行前後、プロンプト送信時など |
| `allowManagedHooksOnly`  | Managed hooksのみ許可           | Managed専用                  |
| `allowedHttpHookUrls`    | HTTP hookの送信先URLを制限         | 外部送信先の統制                   |
| `httpHookAllowedEnvVars` | HTTP hookに渡せる環境変数を制限        | 秘密情報流出抑止                   |
| `disableAllHooks`        | すべてのhooksを無効化               | 利用禁止ポリシー                   |

`allowManagedHooksOnly`を有効にすると、Managed settingsで定義されたhooks、SDK hook、管理者が強制有効化したplugin由来のhook以外はブロックされます。([Claude Platform Docs][1])

Hooksは強力ですが、すべてのhookイベントでブロックできるわけではありません。`UserPromptSubmit`や`PreToolUse`はブロック用途に使えますが、`SessionStart`、`Setup`、`SubagentStart`などはブロック用途には使えないと説明されています。([Claude][5])

---

## 3.6 Sandbox関連

| 設定キー                                           | 何を制御するか                | 備考                       |
| ---------------------------------------------- | ---------------------- | ------------------------ |
| `sandbox.enabled`                              | sandboxを有効化            | Bashと子プロセスが主対象           |
| `sandbox.failIfUnavailable`                    | sandbox不可なら失敗させる       | 厳格運用向け                   |
| `sandbox.autoAllowBashIfSandboxed`             | sandbox内Bashを自動許可      | 運用効率とのバランス               |
| `sandbox.excludedCommands`                     | sandbox対象外コマンド         | 管理上注意が必要                 |
| `sandbox.allowUnsandboxedCommands`             | sandbox外コマンドを許可するか     | 厳格運用ではfalse候補            |
| `sandbox.filesystem.allowWrite`                | sandbox内で書込可能なパス       | ファイルアクセス制御               |
| `sandbox.filesystem.denyWrite`                 | sandbox内で書込禁止のパス       | ファイルアクセス制御               |
| `sandbox.filesystem.allowRead`                 | sandbox内で読取可能なパス       | ファイルアクセス制御               |
| `sandbox.filesystem.denyRead`                  | sandbox内で読取禁止のパス       | ファイルアクセス制御               |
| `sandbox.filesystem.allowManagedReadPathsOnly` | Managedのread pathのみ許可  | Managed専用                |
| `sandbox.credentials.files`                    | sandboxへ注入する認証ファイル     | 認証情報管理                   |
| `sandbox.credentials.envVars`                  | sandboxへ注入する環境変数       | 認証情報管理                   |
| `sandbox.credentials.envVars[].injectHosts`    | env var注入対象host        | 細かい注入制御                  |
| `sandbox.credentials.allowPlaintextInject`     | 平文注入の許可                | セキュリティ注意                 |
| `sandbox.network.allowedDomains`               | 許可ドメイン                 | ネットワーク制御                 |
| `sandbox.network.deniedDomains`                | 禁止ドメイン                 | ネットワーク制御                 |
| `sandbox.network.allowManagedDomainsOnly`      | Managedの許可ドメインのみ許可     | Managed専用                |
| `sandbox.network.allowUnixSockets`             | 許可Unix socket          | ローカル連携制御                 |
| `sandbox.network.allowAllUnixSockets`          | すべてのUnix socketを許可     | 緩い設定                     |
| `sandbox.network.httpProxyPort`                | HTTP proxy port        | ネットワーク制御                 |
| `sandbox.network.socksProxyPort`               | SOCKS proxy port       | ネットワーク制御                 |
| `sandbox.network.tlsTerminate`                 | TLS終端                  | ネットワーク制御                 |
| `sandbox.enableWeakerNestedSandbox`            | 弱いnested sandboxを許可    | 互換性用途                    |
| `sandbox.enableWeakerNetworkIsolation`         | 弱いnetwork isolationを許可 | 互換性用途                    |
| `sandbox.allowAppleEvents`                     | macOS Apple Events許可   | macOS向け                  |
| `sandbox.bwrapPath`                            | bubblewrap path        | Managed専用、Linux / WSL2向け |
| `sandbox.socatPath`                            | socat path             | Managed専用、Linux / WSL2向け |

Sandboxは、主にBashコマンドとその子プロセスに対してOSレベルの制限をかける機能です。公式ドキュメントでは、macOS、Linux、WSL2で利用可能で、Native Windowsはサポート対象外とされています。Windowsでsandboxを使う場合はWSL2内でClaude Codeを実行する必要があります。([Claude][6])

---

## 3.7 Plugin / Marketplace関連

| 設定キー                            | 何を制御するか              | 備考          |
| ------------------------------- | -------------------- | ----------- |
| `enabledPlugins`                | 有効化するplugin          | plugin利用制御  |
| `extraKnownMarketplaces`        | 追加の既知マーケットプレイス       | plugin配布元管理 |
| `strictKnownMarketplaces`       | 既知マーケットプレイスのみ許可      | Managed専用   |
| `blockedMarketplaces`           | 禁止マーケットプレイス          | Managed専用   |
| `pluginSuggestionMarketplaces`  | plugin提案元マーケットプレイス   | Managed専用   |
| `pluginTrustMessage`            | plugin信頼メッセージ        | Managed専用   |
| `strictPluginOnlyCustomization` | plugin以外のカスタマイズ制限    | Managed専用   |
| `disableSideloadFlags`          | pluginサイドロード系フラグを無効化 | Managed専用   |
| `allowedChannelPlugins`         | channel plugin許可     | Managed専用   |
| `channelsEnabled`               | channels有効化          | Managed専用   |
| `disableBundledSkills`          | バンドルskill無効化         | skill利用制御   |
| `skillOverrides`                | skillごとの上書き          | skill制御     |
| `skillListingBudgetFraction`    | skill listingの予算比率   | skill検索・表示  |
| `skillListingMaxDescChars`      | skill説明の最大文字数        | skill表示     |
| `disableSkillShellExecution`    | skillによるshell実行を無効化  | セキュリティ寄り設定  |

---

## 3.8 UI / UX / 表示 / 通知関連

| 設定キー                             | 何を制御するか                  |
| -------------------------------- | ------------------------ |
| `theme`                          | テーマ                      |
| `language`                       | 表示言語                     |
| `verbose`                        | verbose表示                |
| `viewMode`                       | 表示モード                    |
| `editorMode`                     | エディタモード                  |
| `autoScrollEnabled`              | 自動スクロール                  |
| `autoCompactEnabled`             | 自動compact                |
| `awaySummaryEnabled`             | 離席時summary               |
| `showTurnDuration`               | ターン所要時間表示                |
| `showClearContextOnPlanAccept`   | plan承認時のclear context表示  |
| `spinnerTipsEnabled`             | spinner tips表示           |
| `spinnerTipsOverride`            | spinner tips上書き          |
| `spinnerVerbs`                   | spinner文言                |
| `terminalProgressBarEnabled`     | ターミナル進捗バー                |
| `prefersReducedMotion`           | motion低減                 |
| `wheelScrollAccelerationEnabled` | ホイールスクロール加速              |
| `syntaxHighlightingDisabled`     | syntax highlighting無効化   |
| `axScreenReader`                 | スクリーンリーダー対応              |
| `voiceEnabled`                   | voice有効化                 |
| `voice`                          | voice設定                  |
| `preferredNotifChannel`          | 通知チャネル                   |
| `agentPushNotifEnabled`          | agent push通知             |
| `inputNeededNotifEnabled`        | 入力待ち通知                   |
| `disableArtifact`                | artifact無効化              |
| `enableArtifact`                 | artifact有効化              |
| `disableWorkflows`               | workflows無効化             |
| `workflowKeywordTriggerEnabled`  | workflow keyword trigger |
| `autoMode`                       | auto mode                |
| `autoMode.classifyAllShell`      | shell分類のauto mode        |
| `disableAutoMode`                | auto mode無効化             |
| `useAutoModeDuringPlan`          | plan中auto mode使用         |

---

## 3.9 IDE / Remote Control / Agent View関連

| 設定キー                          | 何を制御するか            | 備考                                   |
| ----------------------------- | ------------------ | ------------------------------------ |
| `disableAgentView`            | Agent Viewを無効化     | 管理者統制向け                              |
| `disableRemoteControl`        | Remote Controlを無効化 | リモート操作抑止                             |
| `remoteControlAtStartup`      | 起動時Remote Control  | 既定挙動                                 |
| `disableDeepLinkRegistration` | deep link登録を無効化    | IDE / OS連携制御                         |
| `defaultShell`                | 既定shell            | WindowsではPowerShell / CMD / Bash等に関係 |
| `sshConfigs`                  | SSH config         | Managedとuserから読まれ、Managedでは読み取り専用扱い  |

---

## 3.10 バージョン・更新・メンテナンス関連

| 設定キー                         | 何を制御するか                          | 備考         |
| ---------------------------- | -------------------------------- | ---------- |
| `minimumVersion`             | 最小バージョン                          | 古いクライアント抑止 |
| `requiredMinimumVersion`     | 必須最小バージョン                        | Managed専用  |
| `requiredMaximumVersion`     | 必須最大バージョン                        | Managed専用  |
| `autoUpdatesChannel`         | 自動更新チャネル                         | 更新制御       |
| `cleanupPeriodDays`          | クリーンアップ期間                        | ローカル管理     |
| `forceRemoteSettingsRefresh` | remote settings取得失敗時にfail closed | Managed専用  |

Server-managed settingsは初回起動時にキャッシュがない場合、非同期で取得され、取得失敗時には設定なしで継続する短い未適用時間があり得ると説明されています。厳格運用では`forceRemoteSettingsRefresh: true`を使うことで、remote settings取得に失敗した場合にCLIをfail closedにできます。([Claude][2])

---

## 3.11 組織カスタマイズ・運用補助関連

| 設定キー                         | 何を制御するか                                 |                        |
| ---------------------------- | --------------------------------------- | ---------------------- |
| `companyAnnouncements`       | 会社アナウンス                                 |                        |
| `footerLinksRegexes`         | フッターリンクの正規表現                            |                        |
| `outputStyle`                | 出力スタイル                                  |                        |
| `statusLine`                 | ステータスライン                                |                        |
| `plansDirectory`             | plan保存ディレクトリ                            |                        |
| `autoMemoryEnabled`          | 自動メモリ                                   |                        |
| `autoMemoryDirectory`        | 自動メモリ保存場所                               |                        |
| `askUserQuestionTimeout`     | ユーザー質問タイムアウト                            |                        |
| `attribution`                | commit / PR / session URLなどのattribution |                        |
| `prUrlTemplate`              | PR URLテンプレート                            |                        |
| `feedbackSurveyRate`         | feedback survey表示率                      |                        |
| `tui`                        | TUI関連設定                                 |                        |
| `parentSettingsBehavior`     | 親プロセス・埋め込み時の設定継承                        | Managed専用              |
| `policyHelper`               | ポリシーヘルパー                                | MDM / system managed専用 |
| `wslInheritsWindowsSettings` | WSLがWindows側設定を継承するか                    | Windows managed専用      |

`policyHelper`と`wslInheritsWindowsSettings`は、Server-managed settingsでは尊重されないOSレベル寄りの設定として公式ドキュメントに記載されています。([Claude][2])

---

# 4. ネストされた主要設定

## 4.1 `permissions`配下

| 設定キー                                            | 意味                          |
| ----------------------------------------------- | --------------------------- |
| `permissions.allow`                             | 明示的に許可するツール・パターン            |
| `permissions.ask`                               | 実行前にユーザー確認するツール・パターン        |
| `permissions.deny`                              | 明示的に拒否するツール・パターン            |
| `permissions.additionalDirectories`             | 追加でアクセス可能にするディレクトリ          |
| `permissions.defaultMode`                       | 既定の権限モード                    |
| `permissions.disableBypassPermissionsMode`      | bypass permissions modeを無効化 |
| `permissions.skipDangerousModePermissionPrompt` | dangerous mode確認の扱い         |

Claude Codeは、起動したディレクトリには既定でアクセスできます。追加ディレクトリは`--add-dir`、`/add-dir`、または`permissions.additionalDirectories`で追加できます。([Claude][3])

注意点として、`Cd` permission ruleはユーザーが`/cd`を実行した場合に適用されます。つまり、**Claude Codeを最初から特定フォルダで起動すること自体を、`Cd` ruleだけで禁止する機能ではありません**。([Claude][3])

---

## 4.2 `worktree`配下

| 設定キー                          | 意味                   |
| ----------------------------- | -------------------- |
| `worktree.baseRef`            | worktreeの基準ref       |
| `worktree.symlinkDirectories` | symlink対象ディレクトリ      |
| `worktree.sparsePaths`        | sparse checkout対象    |
| `worktree.bgIsolation`        | background isolation |

---

## 4.3 `attribution`配下

| 設定キー                     | 意味                      |
| ------------------------ | ----------------------- |
| `attribution.commit`     | commit attribution      |
| `attribution.pr`         | PR attribution          |
| `attribution.sessionUrl` | session URL attribution |

---

# 5. Managed専用、または管理者配布で特に意味がある項目

以下は、公式ドキュメント上でManaged-only、または実質的に管理者ポリシー向けとして扱われる項目です。

| 設定キー                                           | 用途                                                  |
| ---------------------------------------------- | --------------------------------------------------- |
| `allowManagedPermissionRulesOnly`              | ユーザー・プロジェクト側のpermission rulesを無視し、Managed rulesのみ適用 |
| `allowManagedHooksOnly`                        | Managed hooksのみ許可                                   |
| `allowManagedMcpServersOnly`                   | Managedで許可したMCPサーバーのみ許可                             |
| `allowAllClaudeAiMcps`                         | Claude.ai MCPをすべて許可                                 |
| `allowedChannelPlugins`                        | 許可channel plugin                                    |
| `channelsEnabled`                              | channels有効化                                         |
| `blockedMarketplaces`                          | 禁止plugin marketplace                                |
| `strictKnownMarketplaces`                      | 既知marketplaceのみ許可                                   |
| `disableSideloadFlags`                         | plugin sideloadを禁止                                  |
| `pluginSuggestionMarketplaces`                 | plugin提案元marketplace                                |
| `pluginTrustMessage`                           | plugin信頼メッセージ                                       |
| `strictPluginOnlyCustomization`                | plugin以外のカスタマイズを制限                                  |
| `claudeMd`                                     | 管理者指定CLAUDE.md                                      |
| `parentSettingsBehavior`                       | 親設定とのマージ挙動                                          |
| `requiredMinimumVersion`                       | 必須最小バージョン                                           |
| `requiredMaximumVersion`                       | 必須最大バージョン                                           |
| `forceRemoteSettingsRefresh`                   | Server-managed取得失敗時にfail closed                     |
| `sandbox.filesystem.allowManagedReadPathsOnly` | Managedで定義したread pathのみ許可                           |
| `sandbox.network.allowManagedDomainsOnly`      | Managedで定義したnetwork domainのみ許可                      |
| `sandbox.bwrapPath`                            | Linux / WSL2向けsandbox補助                             |
| `sandbox.socatPath`                            | Linux / WSL2向けsandbox補助                             |
| `wslInheritsWindowsSettings`                   | WSLがWindows側Managed settingsを継承                     |
| `policyHelper`                                 | MDM / system managed専用                              |

公式ドキュメントでは、Managed-only項目の一覧として、権限、hooks、MCP、plugin、sandbox、WSL関連の強制設定が列挙されています。また、`disableBypassPermissionsMode`はManaged専用ではないものの、通常はManagedで設定すべき項目として説明されています。([Claude][3])

---

# 6. settings.jsonには置けないグローバル設定

公式ドキュメントには、`settings.json`ではなく`~/.claude.json`に保存されるglobal config settingsもあります。これらを`settings.json`に追加するとschema validation errorになると説明されています。Managed settingsは基本的に`settings.json`と同じ形式を使うため、以下は通常のManaged settings項目として扱うべきではありません。([Claude Platform Docs][1])

| グローバル設定キー                 | 注意                 |
| ------------------------- | ------------------ |
| `autoConnectIde`          | `settings.json`対象外 |
| `autoInstallIdeExtension` | `settings.json`対象外 |
| `externalEditorContext`   | `settings.json`対象外 |
| `teammateDefaultModel`    | `settings.json`対象外 |
| `workflowSizeGuideline`   | `settings.json`対象外 |

---

# 7. Managed settingsで「できること」

## 7.1 ユーザーが上書きできない組織ポリシーを配布できる

Managed settingsは最上位の設定であり、CLI引数などでも上書きできません。配列系設定は基本的にマージされますが、`fallbackModel`や`availableModels`など一部は例外的に扱われます。([Claude Platform Docs][1])

---

## 7.2 危険なツール利用を禁止・確認制にできる

`permissions.deny`、`permissions.ask`、`permissions.allow`を使い、Bash、Read、Edit、WebFetch、MCPなどのツール利用を制御できます。`deny`は最優先で評価され、ある階層で拒否された操作を別階層で許可することはできません。([Claude][3])

例として、次のような制御が可能です。

```json id="lkw8h2"
{
  "allowManagedPermissionRulesOnly": true,
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "deny": [
      "Read(./.env)",
      "Read(./secrets/**)",
      "Bash(curl *)",
      "Bash(wget *)"
    ]
  }
}
```

---

## 7.3 ユーザー・プロジェクト側の権限追加を無効化できる

`allowManagedPermissionRulesOnly`を使うと、Managed settingsで定義されたpermission rulesのみを有効にできます。これにより、プロジェクトの`.claude/settings.json`やユーザー設定で勝手に許可ルールを追加することを防げます。([Claude][3])

---

## 7.4 MCPサーバーを制限できる

`allowedMcpServers`、`deniedMcpServers`、`allowManagedMcpServersOnly`により、利用できるMCPサーバーを制御できます。さらに厳格にする場合は、端末側に`managed-mcp.json`を配布することで、そのファイルで定義したMCPサーバーのみをロードさせることができます。([Claude][4])

---

## 7.5 Hooksで独自の検査・監査・ブロック処理を入れられる

`hooks`を使うと、ユーザー入力時、ツール実行前、ツール実行後などに管理者定義の処理を実行できます。`allowManagedHooksOnly`を使えば、ユーザーやプロジェクトが定義したhooksを無効化し、管理者定義のhooksだけを有効にできます。([Claude Platform Docs][1])

たとえば、次のような用途が考えられます。

| 用途             | 実現方法                            |
| -------------- | ------------------------------- |
| 禁止パスでの利用検知     | hook入力の`cwd`を検査                 |
| 特定ツール実行前の監査    | `PreToolUse` hook               |
| ユーザープロンプト内容の検査 | `UserPromptSubmit` hook         |
| 外部送信前のURL検査    | `allowedHttpHookUrls`やhook内ロジック |

---

## 7.6 SandboxでBashと子プロセスのOSレベル制限ができる

Sandboxを有効にすると、Bashコマンドとその子プロセスに対して、ファイル読み書きやネットワークの制限をかけられます。permission rulesだけではPythonやNode.jsなどのサブプロセスによる間接的アクセスを完全には制御できないため、公式ドキュメントではsandboxとの組み合わせが説明されています。([Claude][3])

---

## 7.7 PluginやMarketplaceの供給元を制限できる

`strictKnownMarketplaces`、`blockedMarketplaces`、`disableSideloadFlags`、`strictPluginOnlyCustomization`などにより、pluginの取得元、サイドロード、カスタマイズ範囲を制限できます。これは企業導入時のサプライチェーン管理に有効です。([Claude][7])

---

## 7.8 認証方式や組織を縛れる

`forceLoginMethod`、`forceLoginOrgUUID`、`forceLoginGatewayUrl`などを使い、Claude Codeのログイン方式や組織を統制できます。企業導入時には、個人アカウントや別組織での利用抑止に使えます。([Claude][7])

---

## 7.9 古いクライアントの利用を抑止できる

`minimumVersion`、`requiredMinimumVersion`、`requiredMaximumVersion`、`forceRemoteSettingsRefresh`などにより、古いClaude Codeクライアントやポリシー未取得状態の利用を抑止できます。特にServer-managed settingsを厳格に使う場合、`forceRemoteSettingsRefresh`は重要です。([Claude][2])

---

# 8. Managed settingsで「できないこと」または注意が必要なこと

## 8.1 Server-managed settingsだけでは、完全なセキュリティ境界にはならない

公式ドキュメントでは、Server-managed settingsはクライアント側の制御であり、セキュリティ境界として扱うべきではないと説明されています。改変されたクライアント、古いクライアント、組織外アカウント、第三者プロバイダー経由の利用などでは、server-managed policyを回避される可能性があります。([Claude][2])

したがって、厳格な企業統制では、Server-managed settingsだけでなく、MDM、GPO、アプリ制御、ネットワーク制御、端末管理を併用する必要があります。

---

## 8.2 Server-managed settingsはグループ別ポリシーに未対応

公式ドキュメントでは、Server-managed settingsは全ユーザーに一律適用され、ユーザーグループ別設定はサポートされていないと説明されています。([Claude][2])

つまり、たとえば次のような運用はServer-managed settings単体ではできません。

| やりたいこと            | Server-managed単体で可能か |
| ----------------- | -------------------: |
| 開発部だけBash許可       |                   不可 |
| 管理職だけMCP許可        |                   不可 |
| 部門ごとに異なるモデル制限     |                   不可 |
| 特定ユーザーだけsandbox必須 |                   不可 |

この場合は、端末側の配布ポリシー、別組織分離、ネットワーク制御などで設計する必要があります。

---

## 8.3 Server-managed settingsでは`managed-mcp.json`を配布できない

MCPを最も厳格に制御する`managed-mcp.json`は、Server-managed settingsから配布できません。公式ドキュメントでは、システムパスへの端末側配布が必要とされています。([Claude][4])

---

## 8.4 Native Windowsではsandboxを使えない

Claude Codeのsandboxは、macOS、Linux、WSL2で利用可能ですが、Native Windowsではサポートされません。Windows端末でsandboxを使いたい場合は、WSL2内でClaude Codeを実行する必要があります。([Claude][6])

そのため、WindowsネイティブCLIやWindows版VS Code拡張だけで、Bash子プロセスをOSレベルsandboxに閉じ込めることは、公式上はできません。

---

## 8.5 Permission rulesはOSレベルの完全なアクセス制御ではない

Permission rulesはClaude Codeのツール利用を制御する仕組みです。一方、公式ドキュメントでは、Bashパターンは壊れやすく、WebFetchを制限してもBashで`curl`や`wget`を許可していれば別経路でネットワークアクセスできる可能性があると説明されています。([Claude][3])

つまり、以下は避けるべきです。

```json id="4v0a09"
{
  "permissions": {
    "deny": [
      "WebFetch(domain:example.com)"
    ],
    "allow": [
      "Bash(curl *)"
    ]
  }
}
```

この場合、WebFetchは制限していても、Bash経由で外部アクセスできる可能性があります。厳格運用では、Bash deny、sandbox network policy、proxy、端末・ネットワーク制御を組み合わせる必要があります。

---

## 8.6 共有フォルダを「初期作業フォルダ」にすることを禁止する専用キーは確認できない

前回の調査内容にも関係しますが、公式ドキュメント上、`blockedWorkingDirectories`や`denyCwd`のような、**Claude Code起動時の作業フォルダそのものを禁止する専用Managed settingは確認できません**。

関連する制御としては、以下は可能です。

| 制御                                  |    可能か | 補足                                  |
| ----------------------------------- | -----: | ----------------------------------- |
| `/cd`で共有フォルダへ移動することを拒否              |     可能 | `Cd(...)` permission rule           |
| 共有フォルダ内ファイルのRead/Editを拒否            |     可能 | `Read(...)` / `Edit(...)` deny rule |
| hookで`cwd`を検査し、プロンプトやツール実行を止める      |     可能 | `UserPromptSubmit` / `PreToolUse`   |
| Claude Codeを共有フォルダで起動すること自体を専用キーで禁止 | 公式上は不明 | 専用設定は確認できず                          |

`Cd` ruleは`/cd`コマンドに対する制御であり、最初からそのディレクトリで起動することを止める機能とは説明されていません。([Claude][3])

---

## 8.7 Hooksでも起動そのものは必ず止められるとは限らない

Hooksは強力ですが、`SessionStart`はブロック用途には使えません。共有フォルダ上での利用を止めたい場合は、`UserPromptSubmit`で最初のユーザー入力をブロックする、または`PreToolUse`でツール実行をブロックする設計になります。([Claude][5])

つまり、hookでできるのは実質的に次のような制御です。

```text id="ie1c5v"
Claude Codeの起動自体を止めるのではなく、
共有フォルダ上でのプロンプト処理やツール実行を止める。
```

---

## 8.8 `CLAUDE.md`や`claudeMd`はセキュリティ制御ではない

`claudeMd`をManaged settingsで配布すれば、組織共通の指示をClaudeに与えることはできます。ただし、これは**モデルへの指示**であって、厳格なアクセス制御ではありません。公式ドキュメントでも、保証が必要な制御にはpermissionsやhooksを使うべきという位置づけです。([Claude][8])

---

# 9. 企業導入時に重要な設計ポイント

Claude EnterpriseでManaged settingsを使うなら、最低限、次の考え方が安全です。

## 9.1 Server-managedとEndpoint-managedを使い分ける

| 要件                                   | 推奨                                 |
| ------------------------------------ | ---------------------------------- |
| 全社員に一律ポリシーを配る                        | Server-managed settings            |
| 会社管理Windows端末で強制力を高める                | HKLM / Program Files / MDM / GPO   |
| MCPを完全に管理者定義のみにする                    | `managed-mcp.json`を端末配布            |
| Native WindowsでBash子プロセスをsandbox化したい | 不可。WSL2利用を検討                       |
| ポリシー未取得時にfail closedしたい              | `forceRemoteSettingsRefresh: true` |

Endpoint-managed settingsは、WindowsではHKLMレジストリまたは`C:\Program Files\ClaudeCode\managed-settings.json`などで配布できます。これらは管理者権限が必要な場所であり、ユーザーによる上書きに強い方式です。([Claude Platform Docs][1])

---

## 9.2 最小構成の考え方

企業の標準ポリシーとしては、次のような方向性が考えられます。

```json id="zukvrw"
{
  "allowManagedPermissionRulesOnly": true,
  "allowManagedHooksOnly": true,
  "allowManagedMcpServersOnly": true,
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "deny": [
      "Read(./.env)",
      "Read(./secrets/**)",
      "Bash(curl *)",
      "Bash(wget *)"
    ]
  },
  "disableSideloadFlags": true,
  "strictPluginOnlyCustomization": true,
  "forceRemoteSettingsRefresh": true
}
```

これはあくまで考え方の例です。実際には、社内ネットワーク、MCP利用方針、モデル利用方針、Windows / WSL2構成、共有フォルダのパス体系に合わせて検証が必要です。

---

# 10. 最終まとめ

Managed settingsで**できること**は広範囲です。

| できること                 | 実現手段                                                                       |
| --------------------- | -------------------------------------------------------------------------- |
| ユーザーが上書きできない設定配布      | Managed settings                                                           |
| ツール利用の許可・確認・拒否        | `permissions`                                                              |
| ユーザー側permission追加の無効化 | `allowManagedPermissionRulesOnly`                                          |
| MCPサーバー制限             | `allowedMcpServers` / `deniedMcpServers` / `managed-mcp.json`              |
| hooksの強制・ユーザーhook禁止   | `hooks` / `allowManagedHooksOnly`                                          |
| plugin供給元の制限          | `strictKnownMarketplaces` / `blockedMarketplaces` / `disableSideloadFlags` |
| モデル利用制限               | `availableModels` / `enforceAvailableModels`                               |
| ログイン組織・方式の制限          | `forceLoginMethod` / `forceLoginOrgUUID`                                   |
| Bash子プロセスのOSレベル制限     | `sandbox`、ただしNative Windows不可                                              |
| 古いクライアント抑止            | `requiredMinimumVersion` / `minimumVersion`                                |
| ポリシー未取得時のfail closed  | `forceRemoteSettingsRefresh`                                               |

一方で、Managed settingsで**できない、または断定できないこと**もあります。

| できない / 注意が必要                        | 理由                             |
| ----------------------------------- | ------------------------------ |
| Server-managedだけで完全なセキュリティ境界にする     | クライアント側制御であり、改変クライアント等で回避可能    |
| Server-managedでユーザーグループ別ポリシー        | 公式上未対応                         |
| Server-managedで`managed-mcp.json`配布 | 端末側配布が必要                       |
| Native Windowsでsandbox利用            | 公式上、Native Windows非対応          |
| Permission rulesだけでOSレベルに完全隔離       | Bash子プロセスや別経路の考慮が必要            |
| 起動時の作業フォルダを専用キーで禁止                  | 公式上、専用Managed settingは確認できず。不明 |
| `CLAUDE.md`だけでセキュリティ強制              | これはモデルへの指示であり、強制制御ではない         |

実務上の結論は、**Managed settingsはClaude Codeの企業統制の中核機能として使えるが、端末管理・ネットワーク管理・MCP配布管理・WSL2設計と組み合わせて初めて厳格な企業ポリシーになる**、という整理です。

[1]: https://docs.anthropic.com/en/docs/claude-code/settings "Claude Code settings - Claude Code Docs"
[2]: https://code.claude.com/docs/en/server-managed-settings "Configure server-managed settings - Claude Code Docs"
[3]: https://code.claude.com/docs/en/permissions "Configure permissions - Claude Code Docs"
[4]: https://code.claude.com/docs/en/managed-mcp?utm_source=chatgpt.com "Control MCP server access for your organization"
[5]: https://code.claude.com/docs/en/hooks "Hooks reference - Claude Code Docs"
[6]: https://code.claude.com/docs/en/sandboxing?utm_source=chatgpt.com "Configure the sandboxed Bash tool - Claude Code Docs"
[7]: https://code.claude.com/docs/en/admin-setup "Set up Claude Code for your organization - Claude Code Docs"
[8]: https://code.claude.com/docs/en/debug-your-config "Debug your configuration - Claude Code Docs"
