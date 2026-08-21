以下のように、最後列に「どのような設定項目か」の説明を追加すると分かりやすいです。

| セキュリティ要件                            | Windowsネイティブ |  WSL2 | どのような設定項目か                                                                                                                                             |
| ----------------------------------- | -----------: | ----: | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Permission制御                        |            ○ |     ○ | Claude Codeがファイル編集、コマンド実行、Webアクセス、MCP実行などを行う際に、**自動許可・ユーザー承認・禁止**のどれにするかを制御する機能です。                                                                     |
| Auto mode禁止                         |            ○ |     ○ | Claude Codeが操作を自動承認して進めるAuto modeを、**企業ポリシーとして使用禁止にする設定**です。                                                                                           |
| Permission bypass禁止                 |            ○ |     ○ | Permission確認を無視して操作を実行する`bypassPermissions`や危険な権限スキップ機能を、**利用できないようにする設定**です。                                                                          |
| Managed-only Permission             |            ○ |     ○ | Permissionルールを**管理者が設定したManaged settingsだけに限定**し、User / Project設定からルールを追加・変更して企業ポリシーを弱めることを防ぐ設定です。                                                     |
| Managed Hooks / MCP                 |            ○ |     ○ | HooksやMCP Serverを、**管理者が許可・管理したものだけ利用可能にするための制御**です。ユーザーが勝手に外部連携を追加することを防ぎます。                                                                          |
| Plugin / Skill制限                    |            ○ |     ○ | 管理外Plugin、Skill、Marketplace、MCP sideload、Skill内Shell実行などを制限し、**Claude Codeの拡張機能を企業管理下に置く設定**です。                                                        |
| `/cd` Workspace制限                   |            ○ |     ○ | Claude Codeの`/cd`コマンドで移動できるDirectoryを、**指定したWorkspaceとその配下だけに限定する設定**です。                                                                               |
| **OSレベルFilesystem Sandbox**         |        **×** | **○** | Bashなどの子プロセスがアクセスできるファイルやDirectoryを、**LinuxのSandbox機構を使ってOSレベルで制限する機能**です。Native WindowsではClaude Code Sandboxが非対応です。                                   |
| **Bash subprocess Network Sandbox** |        **×** | **○** | `curl`、`wget`、package managerなど、Bashから起動したプロセスの通信先を、**Sandbox内で制限する機能**です。                                                                             |
| **管理者Domain strict allowlist**      |        **×** | **○** | SandboxからのNetwork Accessを、**管理者が登録したDomainだけに限定し、それ以外への通信を拒否する設定**です。                                                                                  |
| **Sandbox利用不能時Fail-closed**         |        **×** | **○** | Sandboxが正常に初期化できない場合に、安全性を下げてそのまま実行するのではなく、**Claude Codeの起動・実行を停止する設定**です。                                                                             |
| **Sandbox外再実行禁止**                   |        **×** | **○** | Sandboxでコマンドを実行できなかった場合でも、Sandboxを解除して再実行することを許可せず、**Sandbox回避を防止する設定**です。                                                                             |
| `/mnt/c`等Windows DriveへのSandbox制限   |            ― |     ○ | WSL2から見える`/mnt/c`、`/mnt/d`などのWindows Drive Mountに対し、**SandboxからのRead / Writeを禁止する設定**です。                                                               |
| Windows Host / UNC等の完全隔離            |            × |     △ | Windows Host側のファイル、UNC Path、Network Share、Windows executableなどへのアクセスを**完全に遮断できるか**という要件です。settings.jsonだけではOSレベルの完全隔離までは保証できません。                       |
| Workspaceだけへの完全なFilesystem隔離        |            △ |     △ | `claude_work`以外のファイルやDirectoryを、**参照を含めてすべてアクセス禁止にできるか**という要件です。Claude Code自身やOS Runtimeが必要とするPathもあるため、完全隔離には制約があります。                                 |
| 初期Working Directory固定               |            × |     × | Claude Code起動時のCurrent Working Directoryを、**Managed settingsだけで強制的に`claude_work`へ固定できるか**という要件です。現行仕様では専用設定が確認できません。                                   |
| Server-managed Policyの初回Fail-closed |            × |     × | 初回起動時にServer-managed settingsを取得できなかった場合でも、**企業ポリシーなしでClaude Codeを起動させないようにできるか**という要件です。初回はまだPolicy自体を取得していないため、server-managed settingsだけでは完全保証できません。 |

特に資料向けには、**「何を制御する設定なのか」だけでなく、「何を防ぐためのものか」まで1文で書く**と、非技術者にも伝わりやすくなります。
