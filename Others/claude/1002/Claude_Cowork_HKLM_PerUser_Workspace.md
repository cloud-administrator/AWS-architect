# Claude Desktop / Cowork：各ユーザーのプロファイル配下を指定する改善案

確認日：2026年10月2日  
対象：Windowsのドメインユーザーが、各自のローカルプロファイル配下にある`claude_work`を使用する構成  
位置付け：通常のClaude Enterprise構成では検証が必要な設定候補

## 1. 結論と確認できた範囲

固定の`C:\Users\alice\claude_work`を、ユーザー別に解決する`~/claude_work`へ変更する案。先頭の`~`を各ユーザーのホームフォルダへ展開する仕様は、Claude Desktop on third-party（以下、3P）の公式資料に明記されている。[S02]

**ただし、通常のClaude Enterprise構成での`~`対応は、今回確認した公式資料では不明。通常構成の本番端末へ、確認済みの設定として一括配布しない。** 通常構成でも`allowedWorkspaceFolders`自体は公式の設定項目だが、`~`の展開までは説明されていない。[S01]

| 確認対象 | 判定 | 説明 | 根拠 |
|---|---|---|---|
| 通常のEnterpriseで`allowedWorkspaceFolders`をHKLMに設定すること | 確認済み | Coworkに接続可能なフォルダを指定する設定 | [S01] |
| 3Pで先頭の`~`をユーザー別に展開すること | 確認済み | 同じ設定値を配布しても、利用者ごとのホームフォルダを基準に解決する | [S02] |
| `~`展開の追加時期 | 3Pの変更履歴で確認済み | 2026年6月18日、バージョン1.14271.0の「3P」欄に追加を記載 | [S04] |
| 通常のEnterpriseで同じ`~`表記を使用できること | **不明** | 3Pの仕様を通常構成の保証として扱わない。対象構成・対象バージョンでの確認が必要 | [S01][S04] |

この改善案は、3Pへの切り替えを提案するものではない。また、「プロファイル」はPC上のWindowsユーザープロファイルを指す前提。共有サーバー上のホームフォルダを許可する案ではない。

## 2. 変更する設定値

| 項目 | 設定内容・説明 |
|---|---|
| レジストリキー | `HKLM\SOFTWARE\Policies\Claude` |
| 値名 | `allowedWorkspaceFolders` |
| 型 | `REG_SZ`。PowerShellでは`-PropertyType String` |
| 変更前 | `["C:\\Users\\alice\\claude_work"]`。特定ユーザーの絶対パスを固定 |
| 変更案 | `["~/claude_work"]`。ホームフォルダをユーザー別に解決する書式 |
| 保存する文字列 | `~`を含むJSON配列をそのまま保存する。配布処理で絶対パスへ置換しない |
| 許可対象 | 対応環境では、各ユーザーのホームフォルダ内の`claude_work`とその配下 |
| 変更しないもの | 残りの4項目、フォルダの作成、各操作の承認方式 |

レジストリの設定場所は[S01]、`~`と配下フォルダの扱いは3P資料の[S02]、型指定は[M01]に基づく。以下の例も、`~`が意図どおり展開される環境を前提とする。

| 利用者の実際のホームフォルダの例 | `~/claude_work`が指す場所の例 |
|---|---|
| `C:\Users\alice` | `C:\Users\alice\claude_work` |
| `C:\Users\bob.CONTOSO` | `C:\Users\bob.CONTOSO\claude_work` |
| `D:\Profiles\carol` | `D:\Profiles\carol\claude_work` |

上表は説明用の仮定。ユーザー名やドメイン名からプロファイルの絶対パスを組み立てる方式ではない。[S02]

## 3. 置き換える1コマンド

前回の2番目のコマンドだけを、次に置き換える。前回の処理などで`HKLM:\SOFTWARE\Policies\Claude`キーが作成済みであることを前提とする。管理者として起動した64ビット版PowerShellで実行する。

**通常のEnterpriseでは、まず検証端末に限って使用する。以下のコメントは、通常構成への対応を保証するものではない。**

```powershell
# 固定ユーザー名をなくし、各利用者のホームフォルダ配下を指定する候補。
# ~ のユーザー別展開は3Pの公式仕様。通常のEnterpriseでの対応は不明。
# 通常構成では、対象バージョンで許可・拒否の動作を確認してから採用する。
# '~'を含むJSON文字列をそのまま保存し、管理者のプロファイルには置換しない。
# REG_SZのまま設定する。フォルダの作成や自動登録は行わない。
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'allowedWorkspaceFolders' -PropertyType String -Value '["~/claude_work"]' -Force
```

シングルクォートで囲んだ`'["~/claude_work"]'`は、PowerShellによる変数展開を行わない文字列。ユーザー別の展開を担当するのは、対応環境のClaude側。[M02][S02]

## 4. 5コマンド全体のコメント付き版

**検証用。`allowedWorkspaceFolders`の変更だけに第1章の未確認事項がある。** 他の4項目は前回と同じ値。[S01]

```powershell
# 管理者として起動した64ビット版PowerShellで、上から順に実行する。
# 通常のEnterpriseでは、~ の対応を確認する検証端末で使用する。
# 各ユーザーのclaude_workフォルダは別途用意する。
# コマンドが失敗した場合は、以降を実行せず原因を確認する。

# 1. Claude DesktopでCoworkの利用を許可する。
# このコマンドでClaudeキーも作成する。Hyper-V自体の有効化ではない。
reg.exe add 'HKLM\SOFTWARE\Policies\Claude' /v secureVmFeaturesEnabled /t REG_DWORD /d 1 /f /reg:64

# 2. 各ユーザーのホームフォルダ内のclaude_workを許可する設定候補。
# ~ の展開は3Pで公式確認済み。通常のEnterpriseでの対応は不明。
# 文字列をそのまま保存するため、配布実行者のパスに固定しない。
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'allowedWorkspaceFolders' -PropertyType String -Value '["~/claude_work"]' -Force

# 3. ローカルMCPサーバーを無効化する。
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'isLocalDevMcpEnabled' -PropertyType DWord -Value 0 -Force

# 4. デスクトップ拡張機能を無効化する。
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'isDesktopExtensionEnabled' -PropertyType DWord -Value 0 -Force

# 5. デスクトップ拡張機能のカタログへのアクセスを無効化する。
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'isDesktopExtensionDirectoryEnabled' -PropertyType DWord -Value 0 -Force
```

`reg.exe`の`/reg:64`は64ビットのレジストリビューを指定する。`New-ItemProperty`の型指定についてはMicrosoftの公式資料を参照する。[M03][M01]

## 5. 避ける指定方法

| 指定方法 | 今回採用しない理由 | 根拠 |
|---|---|---|
| `$env:USERPROFILE`を設定スクリプト内で展開してHKLMに保存する | そのPowerShellプロセスの環境に依存する。別の管理者やSYSTEMで配布すると、実際の利用者とは異なるパスを保存するおそれがある。保存後に利用者を切り替えても値は自動で変わらない | [M04][S01]に基づく注意点 |
| `["%USERPROFILE%\\claude_work"]`を文字列として保存する | 3Pの公式資料に列挙された対応トークンに`%USERPROFILE%`は含まれず、未対応トークンを含む項目は無視される。通常構成でも対応を確認できない | [S03] |
| `REG_EXPAND_SZ`に変更する | 3P資料では、この型の内容をアプリが読めないと明記。型を変えれば解決するとは判断しない | [S03] |
| 全ユーザーの`claude_work`をHKLMに列挙する | HKLMは端末共通の設定。「各ユーザーは自分のフォルダだけ」という要件を、許可リスト自体では表現できない | [S01]に基づく設計上の注意点 |

## 6. 通常のEnterpriseで採用する前の確認

以下は実施すべき検証項目であり、実機で確認済みの結果ではない。機密データを置かない検証用フォルダを使用する。

| 確認項目 | 合格条件 |
|---|---|
| 保存値 | `allowedWorkspaceFolders`が`REG_SZ`で、値が`["~/claude_work"]`のまま保存されている |
| ユーザーAでの動作 | A自身の`claude_work`を作業フォルダとして接続でき、その配下を読み書きできる |
| ユーザーBでの動作 | 同じHKLM設定のまま、B自身の`claude_work`を接続できる |
| 他人の作業フォルダ | AからBの`claude_work`、BからAの`claude_work`を接続できない。検証用フォルダに限りOS権限で読める条件も用意し、OS権限による拒否だけで合格と判断しない |
| 範囲外 | 自分のプロファイル全体、Documentsなどの兄弟フォルダ、共有フォルダを作業フォルダとして接続できない |
| 再起動後 | Claude Desktopを完全終了して起動し直し、新しいタスクでも許可・拒否が維持される |

レジストリに値を書き込めたことだけでは、Claudeがその書式を読み取って制限している証拠にならない。特に「自分のフォルダを使えること」と「範囲外を使えないこと」の両方を確認する。

対応を確認できない場合は、通常構成の確定済み設定として採用しない。1端末1利用者なら端末ごとに実際の絶対パスを配布する方法を維持できるが、複数利用者の共用端末に対するユーザー別の自動切り替えとは別の方法。

本資料では対象端末での実行・動作確認を行っていない。元の資料を確認済み仕様として上書きせず、検証用の別紙として作成した。

## 公式参照資料

| ID | 公式資料 | 主な確認箇所 |
|---|---|---|
| S01 | [Enterprise configuration for Claude Desktop][S01] | Windows enterprise configuration、Enterprise policy options |
| S02 | [Desktop and filesystem access — Claude Desktop on 3P][S02] | Workspace folder allowlist |
| S03 | [Configuration reference — Claude Desktop on 3P][S03] | Value types、allowedWorkspaceFolders details |
| S04 | [Changelog — Cowork][S04] | 2026年6月18日、v1.14271.0、3P欄 |
| M01 | [New-ItemProperty — Microsoft Learn][M01] | レジストリ値の作成、型指定 |
| M02 | [about_Quoting_Rules — Microsoft Learn][M02] | Single-quoted strings |
| M03 | [reg add — Microsoft Learn][M03] | キー・値の追加、`/reg:64` |
| M04 | [about_Environment_Variables — Microsoft Learn][M04] | Process scope、環境変数の参照 |

[S01]: https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop
[S02]: https://claude.com/docs/third-party/claude-desktop/local-access
[S03]: https://claude.com/docs/third-party/claude-desktop/configuration
[S04]: https://claude.com/docs/cowork/changelog
[M01]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-itemproperty?view=powershell-7.6
[M02]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules?view=powershell-7.6
[M03]: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-add
[M04]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.5
