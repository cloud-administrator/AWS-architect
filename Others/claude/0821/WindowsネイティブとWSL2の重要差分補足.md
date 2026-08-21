はい。**その理解は概ね正しいですが、「Permission制限そのものを回避できる」というより、「WindowsネイティブではPermissionの外側にOSレベルのFilesystem Sandboxがないため、承認されたShell/PowerShellからWorkspace外へアクセスできる余地が残る」**という表現が正確です。

Anthropic公式は、`Read` / `Edit` のdenyルールについて、Claude Codeの組み込みFile Toolや一部の認識可能なBashコマンドには適用される一方、**PythonやNode.jsなど任意のsubprocessが自分でファイルを開く場合には適用されない**と明記しています。そして「全プロセスに対してOSレベルでPath Accessを禁止したい場合はSandboxを使う」よう案内しています。([Claude][1])

例えばWindowsネイティブで、`C:\Users\user\claude_work`以外をRead禁止に近づけるPermission設定をしていたとしても、Claudeが次のようなPowerShellやPythonコマンドを実行し、**そのShell Command自体をユーザーが承認した場合**を考えます。

```powershell
Get-Content C:\Users\user\Documents\secret.txt
```

あるいは、

```powershell
python -c "print(open(r'C:\Users\user\Documents\secret.txt').read())"
```

Claude CodeはShell CommandそのものについてPermission確認を行えますが、WindowsネイティブではSandboxがないため、承認後に起動したプロセスをOSレベルのFilesystem境界の中へ閉じ込めるClaude Code Sandboxはありません。特に後者のような任意のsubprocessによるファイルアクセスは、Anthropic公式が`Read` / `Edit`ルールだけでは完全には制御できないケースとして説明しています。([Claude][1])

一方WSL2では、さらにSandboxを重ねられます。Anthropic公式によればSandboxはmacOS、Linux、WSL2で利用できますが、**Native Windowsは非対応**です。Sandbox内のFilesystem制限はOSレベルで強制され、その中で動くBash Commandとその子プロセスすべてに適用されます。([Claude][2])

つまり構造としてはこう違います。

| 操作                                     | Windowsネイティブ            | WSL2 + Sandbox     |
| -------------------------------------- | ----------------------- | ------------------ |
| Claude CodeのRead Tool                  | Permissionで制限可能         | Permissionで制限可能    |
| Claude CodeのEdit / Write Tool          | Permissionで制限可能         | Permissionで制限可能    |
| PowerShell / Bashの実行前確認                | Permissionで制限可能         | Permissionで制限可能    |
| Python等の子プロセスによるファイルアクセス               | **SandboxによるOSレベル制限なし** | **Sandboxで制限可能**   |
| Workspace外へのFilesystem AccessをOSレベルで遮断 | **不可**                  | **Sandbox範囲内では可能** |
| Network Accessを子プロセス単位でDomain制限        | **不可**                  | **可能**             |

例えばWSL2では、

```text
Claude Code
   ↓
Bash実行のPermission確認
   ↓
Sandbox
   ↓
Python / curl / npm / git など
```

となるため、仮にユーザーが

```bash
python script.py
```

を承認したとしても、その`python`プロセス自体がSandbox内に入ります。

そのため、

```text
~/claude_work       → 許可
/mnt/c              → 禁止
~/Documents         → 禁止
```

のようなFilesystem BoundaryをSandbox側で設定しておけば、PythonコードがWorkspace外を読もうとしても、**Permission判断ではなくOSレベルのSandboxがアクセスを拒否する**という二段構えにできます。AnthropicもSandboxについて「operating system enforces that boundary for every Bash command and its child processes」と説明しています。([Claude][2])

### 特に注意したい「承認」の意味

Windowsネイティブで、

> 「PowerShellは毎回ユーザー承認にすれば安全なのでは？」

という考え方は、ある程度は有効です。ただしこれは、

> **ユーザーが危険なCommandを見抜いて拒否する**

ことに依存する制御です。

たとえばClaudeが、

```powershell
python process_data.py
```

を提案した場合、ユーザーから見ると安全そうでも、`process_data.py`の内部で、

```python
open(r"C:\Users\user\Documents\secret.txt")
```

としている可能性があります。

Anthropic公式が説明している通り、この種の**任意subprocessによる間接Filesystem AccessはRead/Edit rulesだけでは完全にカバーされません**。([Claude][1])

WSL2 Sandboxなら、このPython processもSandbox Boundary内に入るため、より強い制御になります。

### UNC共有フォルダについても同じ考え方です

WindowsネイティブではClaude CodeはUNC Pathを含むCommandを検出した場合、通常のread-only commandでもPermission promptを出す仕組みがあります。たとえば、

```text
\\server\share\file.txt
```

をCommand引数に含む場合、Windows Credentialが送信される可能性があるためprompt対象になります。([Claude][1])

しかしこれは**「承認を求める」制御**であって、

> `\\server\share`へのNetwork Filesystem AccessをOSレベルで絶対禁止する

仕組みではありません。

そのためWindowsネイティブでは、

```text
Permission
    ↓
ユーザーが承認
    ↓
PowerShell / Python / Node
    ↓
Windowsユーザーがアクセス可能な場所へアクセス可能
```

という構造が残ります。

## 今回の案件での理解

一番重要なのは次の違いです。

> **Windowsネイティブ**
>
> 「Claude Codeにこの操作をさせてよいか」をPermissionで制御する。

対して、

> **WSL2 + Sandbox**
>
> 「Claude Codeにこの操作をさせてよいか」をPermissionで制御し、さらに「承認されたCommandであっても、実際に触れてよいFilesystem / Network」をSandboxで制御する。

したがって今回のように、

* `~/claude_work`だけで作業させたい
* Windows側の`/mnt/c`等を触らせたくない
* Shell内のPython / Node / npm等にも同じFilesystem制限を適用したい
* ユーザーがCommandを誤って承認しても被害範囲を狭めたい

という企業向け要件では、**WindowsネイティブのPermissionだけより、WSL2 + Permission + Sandboxの方が大幅に強い構成**になります。

短くまとめるなら、

> **Windowsネイティブでは、Claude Codeの組み込みToolはPermissionで制限できますが、承認後に実行されたPowerShellや任意subprocessまでFilesystem Sandboxで閉じ込めることはできません。WSL2ではSandboxを併用できるため、承認済みCommandとその子プロセスについてもFilesystem / Network AccessをOSレベルで制限できます。**

という説明が最も適切です。

[1]: https://code.claude.com/docs/en/permissions "Configure permissions - Claude Code Docs"
[2]: https://code.claude.com/docs/en/sandboxing "Configure the sandboxed Bash tool - Claude Code Docs"








＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝＝




これまでの調査内容を整理すると、**Windowsネイティブでは実現できず、WSL2を使うことで実現できる最大のポイントは「Claude Code Sandboxを使ったOSレベルの制御」**です。

## Windowsネイティブでは不可、WSL2なら可能な主な制御

| 項目                                          | Windowsネイティブ |    WSL2 | 要点                                                                                                |
| ------------------------------------------- | -----------: | ------: | ------------------------------------------------------------------------------------------------- |
| **Claude Code Sandboxの利用**                  |        **×** |   **○** | 最大の違いです。WindowsネイティブではClaude Code Sandboxが利用できません。WSL2ではLinux Sandboxを利用できます。                     |
| **Sandboxが使えなければ起動を失敗させる**                  |        **×** |   **○** | `sandbox.failIfUnavailable: true` により、Sandboxなしで安全性を下げて動作することを防げます。                               |
| **Sandbox内Bashの自動承認を禁止**                    |       **×※** |   **○** | `sandbox.autoAllowBashIfSandboxed: false` により、Sandbox内で安全と判断されたBashでも、Permissionによるユーザー承認を要求できます。 |
| **Sandbox外でのCommand再実行を禁止**                 |       **×※** |   **○** | `sandbox.allowUnsandboxedCommands: false` により、Sandboxを回避してCommandを再実行する経路を制限できます。                 |
| **BashプロセスのFilesystem Read制限**              |        **×** |   **○** | `sandbox.filesystem.denyRead` / `allowRead` により、Bash等の子プロセスから読めるDirectoryを制限できます。                 |
| **BashプロセスのFilesystem Write制限**             |        **×** |   **○** | `denyWrite` / `allowWrite` により、子プロセスが書き込めるDirectoryを制限できます。                                       |
| **`/mnt/c`、`/mnt/d`等へのSandboxアクセス禁止**       |            ― |   **○** | WSL2ではWindows Driveが通常`/mnt/c`等に見えるため、`/mnt`をSandboxでRead/Write禁止できます。                            |
| **BashからのNetwork AccessをDomain制限**          |        **×** |   **○** | `curl`、`wget`、package manager等の通信先を管理者指定Domainに限定できます。                                            |
| **未許可Domainを即時拒否するstrict allowlist**        |        **×** |   **○** | Sandbox Networkの`strictAllowlist`により、管理者が許可していないDomainへの通信を拒否できます。                                |
| **User / ProjectからNetwork Domainを追加できなくする** |        **×** |   **○** | `allowManagedDomainsOnly`を使い、SandboxのDomain allowlistをManaged settingsだけから定義できます。                 |
| **Unix SocketをSandboxで制限**                  |        **×** | **△～○** | WSL2/LinuxではSandboxとoptional seccomp filterを使ったUnix Socket制御が可能です。ただしseccompの導入状況に依存します。          |
| **`processWrapper`の利用**                     |        **×** |   **○** | Windowsネイティブでは無視されます。WSL2では会社指定launcher経由でClaude Code内部プロセスを起動できます。                               |

※ WindowsネイティブではSandbox自体がないため、「Sandbox内Bash」や「Sandbox外再実行」という概念自体が実質的に対象外です。

---

## 特に企業セキュリティ上大きい違い

### 1. Filesystemを二重に守れる

Windowsネイティブでは、基本的にClaude Codeの

* `Read`
* `Edit`
* `Write`
* `Bash`
* `PowerShell`

などの**Permission制御**が中心になります。

WSL2ではこれに加えて、

**Claude Code Permission**
↓
**Sandbox Filesystem制御**
↓
**Linux Filesystem**

という二重構造にできます。

例えばClaude Codeに、

> `/mnt/c/Users/...` を読んで

という操作をさせようとした場合、Permissionだけでなく、Sandbox側でも`/mnt`へのアクセスを拒否できます。

これが今回WSL2を採用する大きな理由です。

---

### 2. `curl`等の外部通信までDomain allowlistにできる

WindowsネイティブでPermissionによって`WebFetch`等を制御しても、

```text
curl https://xxxx.com
```

のようなShell Commandについて、Claude Code SandboxによるNetwork allowlistは利用できません。

WSL2では、

```text
example.com
api.example.com
```

だけを許可して、

```text
evil.example
github.com
pypi.org
npmjs.com
```

など管理者が許可していないDomainをSandbox側で拒否する、といった構成ができます。

つまり、

> **「Bashは承認された。しかし、そのBashがどこへ通信してもよいわけではない」**

という制御ができます。

---

### 3. Windows側のDriveをSandboxから遮断できる

WSL2ではWindowsのCドライブが通常、

```text
/mnt/c
```

として見えます。

そのためSandboxで、

```text
/mnt
```

へのRead / Writeを禁止することで、

```text
/mnt/c
/mnt/d
/mnt/e
```

など標準的なWindows Drive Mountをまとめて制限できます。

今回の要件である、

> WSL2のLinux filesystem上の`~/claude_work`だけで作業し、Windows側のファイルを触らせたくない

という設計と非常に相性がよいです。

---

## 一方、Windowsネイティブでも実現できるもの

次の制御はSandboxとは別のClaude Code Managed Permission機能なので、**WindowsネイティブでもWSL2でも可能**です。

| 制御                     | Windows | WSL2 |
| ---------------------- | ------: | ---: |
| Editをユーザー承認制           |       ○ |    ○ |
| Writeをユーザー承認制          |       ○ |    ○ |
| Bash / PowerShellを承認制  |       ○ |    ○ |
| MCP Toolを承認制           |       ○ |    ○ |
| Auto mode禁止            |       ○ |    ○ |
| Permission bypass禁止    |       ○ |    ○ |
| Managed Permissionだけ使用 |       ○ |    ○ |
| 管理外Hooksを禁止            |       ○ |    ○ |
| 管理外MCPを禁止              |       ○ |    ○ |
| 管理外Plugin / Skillを制限   |       ○ |    ○ |
| `/cd`移動先を制限            |       ○ |    ○ |
| WebSearchを禁止           |       ○ |    ○ |
| WebFetchをPermissionで制御 |       ○ |    ○ |

したがって、**「Permissionを厳しくするだけ」ならWindowsネイティブでもかなりできます。**

しかし今回の要求は、

> ファイルアクセスやNetwork Accessについても、Command実行後のOSレベルに近いところで制限したい

というものなので、Windowsネイティブでは不足します。

---

## WSL2でも完全には保証できないもの

WSL2を使えばすべて解決するわけではありません。次の項目は**WSL2 + Managed settingsでも完全保証ではありません**。

| 項目                                       | 状態 | 理由                                               |
| ---------------------------------------- | -: | ------------------------------------------------ |
| `~/claude_work`を初期Working Directoryとして強制 |  × | Managed `settings.json`に初期CWD固定機能が確認できない         |
| Workspace以外のLinux filesystemを完全に不可視化     |  △ | Claude CodeやLinux Commandが必要とするRuntime file等がある  |
| Windows Hostへのあらゆる経路を完全遮断                |  △ | WSL Interop、Unix Socket等が関係する                    |
| Windows Network ResourceをOSレベルで完全遮断      |  △ | settings.jsonはOS自体のSecurity Boundaryではない         |
| Sandboxの全例外をManagedだけに固定                 |  △ | `excludedCommands`等に残存制約がある                      |
| 初回起動からserver-managed policyをFail-closed  |  × | 初回はまだPolicy自体を取得していない                            |
| 初回Organization LoginをPolicyだけで強制         |  △ | server-managed settings取得前というbootstrap問題がある      |
| settings.json自体をSecurity Boundaryにする     |  × | Client-side policyでありOSレベルのSecurity Boundaryではない |

## 一言でまとめると

今回の案件では、次の説明が最も分かりやすいです。

> **Windowsネイティブ版でもClaude CodeのPermission、MCP、Hooks、Plugin等の管理は可能です。しかしClaude Code Sandboxが利用できないため、Bash等の子プロセスに対するFilesystem制限・Network Domain制限・Sandbox回避防止を実現できません。WSL2ではLinux版Claude Code Sandboxが使用できるため、Permission制御に加えてFilesystemとNetworkをSandboxでも制限でき、企業向けの多層防御が可能になります。**

つまり今回の構成を図にすると、

```text
Windowsネイティブ
────────────────────
Claude Code
    │
    ├─ Managed Permission  ○
    ├─ MCP / Hooks制御     ○
    ├─ Plugin / Skill制御  ○
    │
    └─ OS Sandbox          ×


Windows + WSL2
────────────────────
Claude Code
    │
    ├─ Managed Permission      ○
    ├─ MCP / Hooks制御         ○
    ├─ Plugin / Skill制御      ○
    │
    └─ Claude Code Sandbox     ○
          │
          ├─ Filesystem制限    ○
          ├─ /mnt制限          ○
          ├─ Network制限       ○
          └─ Domain allowlist  ○
```

**今回WSL2を選択する最大の理由は、「Sandboxを使えること」、さらにそのSandboxで「Filesystem」と「Network」を制御できること**です。
