# Claude Desktop：Coworkに適用しないHKLM専用項目の解説

調査基準日：2026年10月2日  
対象：Windows版Claude Desktopを通常のClaude Enterpriseアカウントで利用する構成  
設定先：`HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Claude`

## 1. 前回資料から除外した専用項目の全一覧

前回資料の「Coworkに適用しない専用項目」は、次の**2項目**を指す。いずれもClaude Desktop内の**Claude Code向け**の設定。[S01]

| No. | 設定項目／レジストリの値名 | レジストリ型 | 公式の既定値 | 説明：何を設定できるか | Cowork向け一覧から除外した理由 | 対応バージョン | 根拠 |
|---|---|---|---|---|---|---|---|
| 1 | `isClaudeCodeForDesktopEnabled` | `REG_DWORD`：整数 | `true`：有効 | Claude Desktop内のClaude Code機能を利用可能にするか、無効化するかを指定する | 制御対象はDesktop内のClaude Codeへのアクセス。Coworkの利用可否や操作権限を設定する項目ではない | 最低対応バージョンは不明。公式一覧に記載なし | [S01][S02] |
| 2 | `effortLevel` | `REG_SZ`：文字列 | `null`：指定なし | Claude Desktop内で開始するClaude Codeセッションの、推論にかける力の初期値を指定する | 公式説明に、Desktop内のCoworkセッションには適用しないと明記 | Claude Desktop **1.25927.0以降** | [S01] |

型の補足：`isClaudeCodeForDesktopEnabled`の`REG_DWORD`はAnthropicのWindows設定例に基づく。`effortLevel`は公式一覧の文字列型に対応させ、Windowsでは通常の文字列値`REG_SZ`として記載する。[S01][M01][M02]

### 1.1 「全8項目」との関係

調査日時点の通常構成向け公式「Enterprise policy options」には10項目が掲載されている。そのうち上記2項目を除いたものが、前回資料の8項目。したがって、**前回8項目＋今回2項目＝当該公式一覧の10項目**という関係。[S01]

ここでの「全2項目」は、**前回の集計から除外した項目のすべて**という意味。Claude関連製品全体の専用設定、未公開設定、別の設定経路に存在する全項目まで含むものではない。

前回資料の第1.4節に記載した3P向け追加項目は、今回の2項目とは別の分類。「通常のEnterpriseへの適用が不明」と、「Coworkには適用しないと確認できる専用項目」を混同しない。本資料では、前回除外した2項目だけを解説し、設定ファイルを用いる管理方法や他の専用設定には範囲を広げない。

## 2. 各設定値の意味

### 2.1 `isClaudeCodeForDesktopEnabled`：Desktop内のClaude Codeを利用できるか

この項目は、機能の**利用可否のスイッチ**。ファイル変更などの操作ごとに承認を求める設定ではない。公式の端末管理資料でも、Claude Code機能の有効化・無効化をDesktopの管理ポリシーとして説明している。[S01][S02]

| HKLMに保存する値 | 対応する真偽値 | 説明：この値でできること | 注意点 | 根拠 |
|---|---|---|---|---|
| `0` | `false` | Desktop内のClaude Codeを無効化する | Coworkの無効化ではない。「Claude Codeを使いながら毎回承認させる」という意味でもない | [S01][S02] |
| `1` | `true` | この端末ポリシーでは、Desktop内のClaude Codeの利用を許可する | 組織側の利用条件や認証を無視して、無条件に利用可能にする設定ではない | [S01][S02] |
| 値を作成しない | 公式既定値は`true` | HKLMから明示的な許可・禁止を指定しない | HKCUなどに別の設定がある場合もあるため、「HKLMが未設定＝必ず利用可能」とは判断しない | [S01] |

**`0`にしても、Cowork内のコマンド実行やコード生成を禁止する設定にはならない。** 制御対象は、同じアプリ内にある別機能のClaude Code。Coworkの機能や権限を制限したい場合に、この値を代用しない。[S01][S02]

また、公式説明で確認できる範囲はDesktop内のClaude Codeへのアクセス。別途インストールしたCLIやWeb版まで一括で禁止する効果は確認できないため、その目的には採用しない。[S01][S02]

### 2.2 `effortLevel`：推論にかける力の初期値

「effort」は、モデルが問題を検討する際にかける推論の強さを表す。低い値は速度や消費量を重視する方向、高い値は複雑な問題に対して深く検討する方向。**アクセス権限の強さや、管理者権限の有無を表す値ではない。**[S03]

次の5種類がDesktopのHKLMポリシーとして公式に列挙されている。各段階の説明はモデル設定の公式資料を要約したもの。レベル名が同じでも、モデルが異なれば推論量が同一とは限らない。[S01][S03]

| HKLMに保存する文字列 | 段階の意味 | 説明：どのような方向に調整するか | 注意点 | 根拠 |
|---|---|---|---|---|
| `low` | 低い推論レベル | 小さな変更や簡単な検討などで、早く結果を得る方向に調整する | 出力の確認を省略してよいという意味ではない | [S01][S03] |
| `medium` | 中程度の推論レベル | 速度・消費量と検討の深さのバランスを取る方向に調整する | すべてのモデルの既定値が`medium`という意味ではない | [S01][S03] |
| `high` | 高い推論レベル | 不具合の調査など、確認や例外条件の検討を重視する方向に調整する | ファイル操作やコマンド実行を許可する値ではない | [S01][S03] |
| `xhigh` | さらに高い推論レベル | `high`より深い検討を行う方向に調整する | 使用できる推論レベルはモデルに依存する | [S01][S03] |
| `max` | 最大の推論レベル | 最も深い検討を行う方向に調整する | 結果の正確性や費用対効果を保証する値ではない。最大権限・承認省略という意味でもない | [S01][S03] |
| 値を作成しない | HKLMでは初期値を指定しない | この端末ポリシーから推論レベルを指定しない | 公式既定値の`null`は「文字列`null`を保存する」という指示ではない | [S01] |

推論レベルは、処理時間を秒数で固定したり、利用料金の上限を金額で設定したりする項目ではない。実際の対応レベルや挙動は、利用するモデルにも依存する。[S03]

#### 適用タイミングと制御の限界

| 確認事項 | 説明 | 根拠 |
|---|---|---|
| 適用対象 | Claude Desktop内のClaude Codeセッション。Coworkセッションは対象外 | [S01] |
| 適用タイミング | 各セッションの開始時に、管理者が指定した値を改めて適用する | [S01] |
| 前のセッションで利用者が変更した場合 | 前のセッションで選択を変えていても、次のセッション開始時には管理者指定値を適用する | [S01] |
| 推論レベルの固定・上限設定との違い | 初期値を指定する項目。セッション中の変更を全面的に禁止する設定や、変更不能な上限としては扱わない | [S01][S03] |
| 対応するアプリのバージョン | `1.25927.0`はClaude Desktopのバージョン。Windowsや別途導入するCLIのバージョンではない | [S01] |
| 旧バージョンでの扱い | 対応条件を満たさない版での詳細な挙動は不明。保存できたことだけをもって適用済みと判断しない | [S01] |
| 不正な文字列や異なる型を設定した場合 | Desktopの当該HKLMポリシーとしての詳細なエラー処理は不明。公式に列挙された値と型を使用する | [S01] |

## 3. 今回の導入案件での扱い

### 3.1 設定目的との対応

今回の資料は、前回除外した項目の内容を説明するための補足資料。**Coworkの要件を満たす目的で、この2項目を追加設定する必要はない。** Claude Codeを別途管理する前提を維持し、ここでは既存値を勝手に変更しない。

| 目的 | この2項目での対応 | 説明 |
|---|---|---|
| Coworkの作業フォルダ、共有フォルダへのアクセスを制限する | 対象外 | どちらもCoworkのファイルアクセス制御ではない |
| Coworkの自動承認、Web・MCP通信、権限昇格を制限する | 対象外 | どちらもCoworkの操作権限・通信制御ではない |
| CoworkのHyper-V利用を設定する | 対象外 | 仮想化機能や実行環境を設定する項目ではない |
| Desktop内のClaude Code機能を無効化する | `isClaudeCodeForDesktopEnabled=0` | Coworkとは別に、この利用禁止を決定した場合の設定 |
| Desktop内のClaude Codeの推論初期値をそろえる | `effortLevel`に承認済みのレベルを指定する | コスト・速度・検討の深さを検証したうえで決定する初期値。今回は具体的な採用値を決定しない |

上表は、公式に記載された適用範囲に基づく本資料の整理。[S01][S02][S03]

### 3.2 設定時に取り違えやすい点

| 項目 | 説明 |
|---|---|
| 設定先 | PowerShellでは`HKLM:\SOFTWARE\Policies\Claude`。`Claude`キーの直下に、上記の値名を作成する |
| キーと値の違い | `effortLevel`や`isClaudeCodeForDesktopEnabled`という子キーを作るのではなく、「値」を作成する |
| 端末単位の適用 | HKLMは端末単位の設定。公式説明では、同じ設定がHKCUにもある場合はHKLMを優先する |
| 既定値と既存値の違い | 公式の既定値は、現在の端末に保存されている値とは限らない。変更前に現在値を確認する |
| 未設定と無効の違い | `isClaudeCodeForDesktopEnabled`の未設定は、`0`による明示的な無効化とは異なる |
| `null`の扱い | `effortLevel`を指定しない場合に、文字列`null`や空文字列を代わりに設定しない |
| 利用停止と削除の違い | 機能の利用可否を制御する値であり、アプリや保存済みデータの削除を指示するものではない |

設定先と優先順位は[S01]、レジストリの値の作成方法は[M01][M02]に基づく。

## 4. 公式参照資料

参照先はAnthropic／Claudeの公式資料とMicrosoft Learnのみ。設定名・既定値・Coworkへの適用範囲は、Desktop向けの[S01]を主な根拠とする。[S03]は推論レベルの意味の説明に使用し、別の設定経路の仕様をそのままHKLMへ転用しない。

| ID | 公式資料 | 本資料で確認した内容 |
|---|---|---|
| S01 | [Enterprise configuration for Claude Desktop][S01] | 通常構成の公式ポリシー一覧、今回の2項目、既定値、対応バージョン、HKLM設定先と優先順位 |
| S02 | [Desktop application — Claude Code Docs][S02] | Chat・Cowork・Codeの区別、Desktop内のCode機能を端末管理で有効化・無効化できること |
| S03 | [Model configuration — Claude Code Docs][S03] | 推論レベルの意味、各段階の位置付け、モデルによる違い |
| M01 | [reg add — Microsoft Learn][M01] | 値の追加・変更、レジストリ型、`/f`、64ビットレジストリビュー |
| M02 | [New-ItemProperty — Microsoft Learn][M02] | PowerShellによる値の作成・上書きと型の指定 |
| M03 | [New-Item — Microsoft Learn][M03] | レジストリキーの作成、既存キーに`-Force`を使う場合の注意 |
| M04 | [reg query — Microsoft Learn][M04] | 既存値と型の確認方法 |

[S01]: https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop
[S02]: https://code.claude.com/docs/en/desktop#device-management-policies
[S03]: https://code.claude.com/docs/en/model-config#adjust-effort-level
[M01]: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-add
[M02]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-itemproperty?view=powershell-7.5
[M03]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item?view=powershell-7.5
[M04]: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-query

## 5. PowerShellコマンド例

**以下は任意の参考例。Coworkの要件を満たすための追加実行は不要。** Desktop内のClaude Codeについて、別途変更が承認された場合に限り、必要な例だけを使用する。`effortLevel=high`は構文説明用の値であり、今回の推奨値ではない。

### 5.1 実行条件と確認事項

| 条件・確認事項 | 説明 |
|---|---|
| 実行環境 | Windows上の64ビットPowerShellを「管理者として実行」する |
| 変更前の確認 | 第5.4節のコマンドで現在値を記録し、既存の管理方針と競合しないことを確認する |
| 実行例の選択 | Claude Codeの無効化と推論レベルの設定は別の目的。すべての例を続けて実行する手順ではない |
| 既存設定への配慮 | 同名の値は上書きする。他のCowork向け設定や組織・更新の設定は変更しない |
| 適用後の確認 | 作業を保存してClaude Desktopを完全終了し、再起動後の新しいセッションで確認する。これは本資料の確認手順であり、即時反映の保証ではない |
| 実機検証 | 導入先Windows／Claude Desktopでの実行検証は未実施 |

### 5.2 PowerShellのコマンドレットを使用する版

#### 共通の準備

キーが存在しない場合だけ作成する。既存キーに対して無条件に`New-Item -Force`を実行しない。[M03]

```powershell
$p = 'HKLM:\SOFTWARE\Policies\Claude'
if (-not (Test-Path $p)) { New-Item -Path $p -Force -ErrorAction Stop | Out-Null }
```

#### 例A：Desktop内のClaude Codeを無効化する

```powershell
New-ItemProperty -Path $p -Name 'isClaudeCodeForDesktopEnabled' -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
```

明示的に利用を許可する場合は、上記の`-Value 0`を`-Value 1`に変更する。未設定に戻す操作とは異なる。[S01]

#### 例B：Desktop内のClaude Codeの推論初期値を`high`にする

```powershell
New-ItemProperty -Path $p -Name 'effortLevel' -PropertyType String -Value 'high' -Force -ErrorAction Stop | Out-Null
```

この例はClaude Codeを利用する構成で使用する。例Aによる無効化を解除する効果はない。コマンド構文と型指定は[M02]に基づく。

### 5.3 1行コマンドだけを使用する版

PowerShellからWindows標準の`reg.exe`を実行する版。第5.2節の共通準備や変数の定義は不要。`/f`は確認なしの上書き、`/reg:64`は64ビットレジストリビューの指定。[M01]

**例A：Desktop内のClaude Codeを無効化する。**

```powershell
reg.exe add "HKLM\SOFTWARE\Policies\Claude" /v isClaudeCodeForDesktopEnabled /t REG_DWORD /d 0 /f /reg:64
```

**例B：Desktop内のClaude Codeの推論初期値を`high`にする。**

```powershell
reg.exe add "HKLM\SOFTWARE\Policies\Claude" /v effortLevel /t REG_SZ /d high /f /reg:64
```

### 5.4 現在値の確認

設定を変更せず、今回の2項目だけを表示する。[M04]

```powershell
reg.exe query "HKLM\SOFTWARE\Policies\Claude" /v isClaudeCodeForDesktopEnabled /reg:64
reg.exe query "HKLM\SOFTWARE\Policies\Claude" /v effortLevel /reg:64
```

| 確認内容 | 説明 |
|---|---|
| 型と値 | 例Aの設定後は`REG_DWORD`と`0x0`、例Bの設定後は`REG_SZ`と`high`を確認する |
| 値が見つからない場合 | 値が存在しない場合のほか、確認操作が失敗している場合もある。エラー内容を確認し、製品の最終的な有効・無効と同一視しない |
| 製品側の動作 | 値を保存できたことと、製品が認識して適用したことは別。無効化した機能の利用可否、または新規セッションの推論レベルを実機で確認する |
