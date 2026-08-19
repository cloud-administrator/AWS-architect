はい。結論は次のとおりです。

**Native Windows + Managed settingsだけの場合、共有フォルダへアクセスできてしまう可能性があります。**
一方、**WSL2ではSandboxを利用できるため、Native Windowsより強い制御が可能です。ただし「SandboxをONにするだけで共有フォルダへ一切アクセスできなくなる」という認識は正しくありません。追加のFilesystem制限が必要です。**

| 構成                                           | 共有フォルダの完全なアクセス防止 | 理由                                           |
| -------------------------------------------- | ---------------- | -------------------------------------------- |
| Native Windows + Managed settings            | ❌ 保証困難           | Sandbox非対応。Permissionは任意の子プロセスまでOSレベルで強制できない |
| WSL2 + Sandboxだけ                             | ⚠️ 不十分           | Sandboxは使えるが、デフォルトでは読み取り可能範囲が比較的広い           |
| **WSL2 + Sandbox + Filesystem制限**            | **✅ かなり強く制御可能**  | OSレベルでBashと子プロセスのFilesystemアクセスを制限           |
| WSL2 + Sandbox + Filesystem制限 + Permission制限 | **✅ 推奨**         | ClaudeのTool制御とOSレベル制御を二重化                    |

Anthropic公式でも、Sandboxは **macOS / Linux / WSL2 に対応し、Native Windowsは非対応**と明記されています。WSL2ではLinuxと同じ `bubblewrap` を使い、Claude Codeから起動されたコマンドとその子プロセスにOSレベルの境界を強制します。 ([Claude][1])

## Native Windowsで何が問題なのか

Managed settingsのPermissionでは、

* `Read`
* `Edit`
* `PowerShell`
* Claude Codeが認識できる一部のファイル操作コマンド

などを禁止できます。

WindowsのUNCパス、たとえば

```text
\\server01\share\data.xlsx
```

をPowerShell等の引数に含めた場合、Claude CodeはWindows Credentialが送信されるリスクを認識し、通常はPermission promptを出します。 ([Claude][2])

しかし問題はここです。

Anthropicは公式に、`Read` / `Edit` deny ruleについて、**PythonやNode.js等の任意の子プロセスが自分自身でファイルを開いた場合までは適用されない**と説明しています。そして、すべてのプロセスに対してファイルアクセスを強制的に禁止したい場合はSandboxを利用するよう案内しています。 ([Claude][2])

例えばNative Windowsでは概念的に、

```text
Claude
 ↓
PowerShell
 ↓
python script.py
 ↓
\\fileserver\share\secret.txt
```

という経路まで、`Read(...)` ルールだけで完全に封じることは保証できません。

したがって、**「共有フォルダに絶対アクセスさせない」がセキュリティ要件なら、Native Windows + Managed settingsだけでは不足**と考えた方がよいです。

---

# WSL2ならどうなるか

ここはかなり改善します。

WSL2ではClaude Code Sandboxが利用でき、

> Bashコマンドだけでなく、そのコマンドが生成した子プロセスにも同じFilesystem境界をOSレベルで適用

できます。 ([Claude][1])

つまり、

```text
Claude Code
   ↓
Sandbox
   ↓
Bash
   ↓
Python
   ↓
Node.js
   ↓
その他子プロセス
```

について、同じFilesystem制限を適用できます。

この点がNative Windowsとの大きな差です。

---

# ただし「Sandbox ONだけ」では足りません

ここが特に重要です。

Sandboxのデフォルトは、

**書き込み：基本的にWorking Directory中心に制限
読み取り：それより広い**

という設計です。

Anthropic公式も、Sandboxのデフォルト読み取りポリシーでは `~/.aws` や `~/.ssh` すら読み取り可能であるため、必要に応じてCredential保護を追加するよう説明しています。 ([Claude][1])

したがって、

```text
sandbox.enabled = true
```

だけでは、

> 「`claude_work` 以外は一切読めない」

とはなりません。

---

# 今回の要件ならこう考えるのがよいです

御社の要件は、

> `claude_work` だけ読み書き可能
> それ以外は参照すら禁止
> Windows共有フォルダも禁止

なので、**WSL2 + Sandboxで「原則全部denyして、claude_workだけallow」**という設計が適しています。

概念的には、

```text
WSL2 filesystem
│
├─ ~/claude_work
│      ↑
│      └── Read / Write 許可
│
├─ /mnt/c
│      └── Read / Write 禁止
│
├─ /mnt/d
│      └── Read / Write 禁止
│
├─ Network mount
│      └── Read / Write 禁止
│
└─ その他
       └── 原則禁止
```

という形です。

Sandboxでは

`filesystem.denyRead`
`filesystem.denyWrite`
`filesystem.allowRead`
`filesystem.allowWrite`

を使ってこの境界を作れます。deny領域の中でも、より具体的な `allowRead` パスを再許可できる仕様です。 ([Claude][3])

例えばAnthropic公式でも、

```text
Home全体 → denyRead
特定Project → allowRead
```

という設計例が示されています。 ([Claude][3])

---

# Windows側のファイルにも注意

WSL2からは通常、

```text
/mnt/c/
```

を通じてWindowsのCドライブを見ることができます。

したがって、今回の要件なら**`/mnt/c` 等のWindows filesystem側も明示的な禁止対象として設計する**のが安全です。

なおAnthropic公式では、Sandbox化されたWSL2コマンドについて、`cmd.exe`、`powershell.exe`、`/mnt/c/` 配下のWindows実行ファイルなどをWindowsホスト側で起動する経路はSandboxによってブロックされると説明されています。 ([Claude][1])

ただし、これは

> `/mnt/c` のファイルがすべて自動的に読み取り禁止

という意味ではありません。

**読み取り自体を禁止したいならFilesystemの `denyRead` が必要**です。

---

# さらに重要な3設定

企業用途ならSandboxは少なくとも次の考え方をセットにすることを推奨します。

```text
sandbox.enabled = true
```

Sandboxを必須化。

```text
sandbox.failIfUnavailable = true
```

Sandboxを起動できなかった場合、**Sandboxなしで続行せずClaude Codeを停止**。

```text
sandbox.allowUnsandboxedCommands = false
```

Claudeが「このCommandはSandboxでは動かないのでSandbox外で実行します」というEscape hatchを使うことを禁止。

Anthropic自身も、組織でSandboxを強制するときのManaged settings例として、この3つの組み合わせを提示しています。 ([Claude][1])

---

# したがって今回の要件なら

私は構成要件を次のように変更することを推奨します。

**Native WindowsでClaude Codeを直接実行するのではなく、Windows端末上のWSL2内でClaude Codeを実行する。**

その上で、

1. Sandboxを必須化
2. Sandbox利用不可ならClaude Code起動禁止
3. Sandbox外Command実行禁止
4. `claude_work` のみRead/Write許可
5. `claude_work` 外はRead/Write禁止
6. `/mnt/c` 等Windows filesystemへのアクセス禁止
7. WSL2上にMountされた共有フォルダも禁止
8. Permission側でも `claude_work` 外をdeny
9. `allowManagedReadPathsOnly` でユーザーがRead許可Pathを追加できないようにする
10. `permissions.disableBypassPermissionsMode` でPermission bypassも禁止

という**Permission + Sandboxの二重制御**が適しています。SandboxのFilesystem設定とPermissionルールは統合され、OSレベルではSandboxが子プロセスまで制限します。 ([Claude][1])

### 一言で整理すると

**Native Windows**

> 「Claude Codeに“アクセスしないよう指示・制御する”」ところまではできるが、子プロセスまで含めたOSレベルの保証が弱い。

**WSL2 + Sandbox**

> 「OSそのものに“そのPathへアクセスさせない”境界を作れる」。

です。

したがって、今回の**「`claude_work` 以外は参照すら禁止」「共有フォルダも禁止」**という企業要件を重視するなら、**Native Windows直接実行より「Windows端末 + WSL2 + Claude Code Sandbox」を採用する方が要件との整合性が高い**です。 ([Claude][1])

[1]: https://code.claude.com/docs/ja/sandboxing "サンドボックス化された Bash ツールを設定する - Claude Code Docs"
[2]: https://code.claude.com/docs/en/permissions "Configure permissions - Claude Code Docs"
[3]: https://code.claude.com/docs/en/sandboxing "Configure the sandboxed Bash tool - Claude Code Docs"
