以下のように、**「何の機能か」**列を追加すると初心者にも理解しやすくなります。

## 4. WindowsネイティブとWSL2の重要差分

| 機能                              | 何の機能か                                                                                                       | ネイティブWindows                       | WSL2                  | 企業導入時の意味                                                             |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------- | ---------------------------------- | --------------------- | -------------------------------------------------------------------- |
| 通常のモデル、権限、表示設定                  | Claude Codeで利用するモデル、Permission、UI表示などの基本動作を制御する設定。OSに依存しないClaude Code共通の設定群。                                | ○                                  | ○                     | JSON構造は同じ。ただしパス、環境変数、実行ファイル名はOS側に合わせる。                               |
| シェルツール                          | Claude CodeがOSコマンドを実行するときに使用するシェル。`git`、`npm`、`python`、ファイル操作などのコマンド実行に関係する。                                | Git BashがあればBash、なければPowerShellツール | LinuxのBash            | HookのmatcherはWindowsで `Bash\|PowerShell` を検討。                        |
| `defaultShell: "powershell"`    | Claude Codeの対話モードで `!` を付けて直接コマンドを実行するときなどに、どのシェルを使用するか指定する設定。                                              | ○                                  | △                     | Windowsでは対話 `!` コマンドをPowerShellへ。WSL2ではPowerShell 7 `pwsh` と環境変数が必要。 |
| サンドボックス                         | Bashなどから起動されるプロセスについて、アクセスできるファイルやネットワーク等を制限し、Claude Codeによるコマンド実行を隔離するセキュリティ機能。                            | **×**                              | **○（WSL2のみ）**         | 混在共通ポリシーで `failIfUnavailable: true` を設定しない。                          |
| `processWrapper`                | Claude Codeが外部プロセスを起動するとき、そのプロセスを管理者指定のラッパープログラム経由で実行させる機能。監査、記録、追加制御などに利用できる。                              | **×（無視）**                          | ○                     | 監査ラッパーを必須にするならネイティブWindowsでは別の端末統制が必要。                               |
| Hookのシェル形式                      | Claude Codeの特定イベント発生時に、管理者やユーザーが指定したシェルコマンドを自動実行するHook機能。例：操作ログ記録、検査処理、通知処理。                                | △ Git BashまたはPowerShell            | ○ `sh -c`             | `.cmd` / `.bat` はexec形式ではなくシェル形式を使う。パス区切りにも注意。                       |
| Hookのexec形式 (`args`)            | Hook実行時にシェルを介さず、指定した実行ファイルを直接起動する方式。引数を配列として安全・明確に渡せる。                                                      | △ 実体のある `.exe` 等が必要                | ○                     | Windowsのnpm等の `.cmd` シムは直接spawnできないことがある。                            |
| `statusLine` / `fileSuggestion` | `statusLine` はClaude Code画面下部などに独自ステータス情報を表示する機能。`fileSuggestion` はファイル入力・補完時の候補生成をカスタマイズする機能。              | △ Windows用コマンドが必要                  | △ Linux用コマンドが必要       | 同じ管理JSONで1つのコマンドしか配れないため、OS共通ランチャーか端末別ポリシーが必要。                       |
| `spellcheck`                    | Claude Code上で入力した文章などについてスペルチェックを行う機能。外部のスペルチェックコマンドを利用する場合がある。                                             | △ `.cmd` シム対応。辞書ツールをPATHへ          | △ 辞書ツールをPATHへ         | v2.1.235以降。aspell/hunspell/ispellの配布が必要。                             |
| Git worktree                    | 1つのGitリポジトリから複数の作業ディレクトリを作り、ブランチごとに並行して作業できるGitの機能。Claude Codeの並列作業でも利用される。                                 | △ GitとWindowsのsymlink権限等を確認        | △ Gitが必要              | 大規模展開前に実機検証。                                                         |
| Windows実行ファイル連携                 | WSL2からWindows側の `.exe`、たとえば `cmd.exe` や `powershell.exe` を起動できるWSLのInterop機能。Linux環境からWindows Host側へ処理を渡せる。 | ○                                  | △ Windows interop     | サンドボックス内から `powershell.exe` 等を呼ぶとUnix socket許可等が必要で隔離を弱める。           |
| 音声入力                            | マイクを使用して音声をテキスト入力し、Claude Codeへの指示として利用する機能。                                                                | △ マイク権限とClaude.aiアカウント             | △ WSLg等のマイク連携条件       | HIPAA対応組織では無効。                                                       |
| `wslInheritsWindowsSettings`    | Windows側で管理されているClaude Code設定を、WSL内で動作するClaude Codeにも引き継ぐための設定。WindowsとWSLの管理ポリシー統一に利用する。                   | ×（ネイティブWindowsには効果なし）              | △ Windowsの管理設定をWSLへ継承 | サーバー管理画面では無視。Windows管理ソースに置く。                                        |

出典: [SETUP][SET-EN][HOOK][PS][VOICE][PW][SB]

特に企業向け資料では、**「機能名」だけではその設定が何を制御しているのか分かりにくい**ため、この「何の機能か」列を入れると、`processWrapper`、Hook、Sandbox、Windows Interopあたりの理解がかなりしやすくなります。
