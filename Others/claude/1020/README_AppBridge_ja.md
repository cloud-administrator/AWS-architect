# コンプライアンスログ収集の最終失敗を App Bridge でメール通知する手順

対象ファイル：`Invoke-ComplianceCollectionWithNotify.ps1`  
前提：Windows、Windows PowerShell 5.0/5.1、同じ Windows に App Bridge Monitor Windows Agent が導入済み、タスクスケジューラで収集を実行中。

## 最初に確認する3点

**追加するラッパーは Windows PowerShell 5 で動きます。ただし、添付された Claude 収集スクリプト本体には「64ビット版 PowerShell 7.4以上」が必要です。また、この添付版の処理完了時の終了コードは `2` です。**

| 対象 | 使用する実行エンジン | 今回の正常終了の扱い |
|---|---|---|
| 追加するラッパー | Windows PowerShell 5.0/5.1 の `powershell.exe` | 正常完了時に `0` を返す |
| 添付 Claude 収集本体 | 64ビット版 PowerShell 7.4以上の `pwsh.exe` | 本体が `2` を返した場合を処理完了として扱う |
| 別に存在する ChatGPT 収集本体 | そのスクリプトが必要とする実行エンジン | そのスクリプトの仕様に合わせて設定する |

Claude 収集本体の先頭には `#requires -Version 7.4` があり、実行中にも64ビット Windows プロセスを確認しています。正常に処理を完了した場合でも、APIの取得範囲に制約があるため、終了コードに `2` を設定する実装です。本手順では「処理が完了したか」を判定し、取得範囲の完全性まで保証するものではありません。したがって、一般的な「`0` 以外は失敗」という判定を、この添付版へそのまま適用しないでください。

これらは添付の `Collect-ClaudeCompliance(3)(2).ps1` のコード確認に基づきます。普段開くコンソールが Windows PowerShell 5 でも、タスクが PowerShell 7 を起動している可能性があります。手順1で実際のタスク設定を確認します。

PowerShell 7 は Windows PowerShell 5.1 と並行して導入できます。既存の Windows PowerShell を置き換える必要はありません。導入が必要な場合は、Microsoft公式の「[Windows に PowerShell 7 をインストールする](https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows)」を参照し、組織の導入手順で64ビット版を用意してください。

## この構成の動き

タスクスケジューラがラッパーを起動し、ラッパーが別プロセスで収集本体を実行します。本体の終了を待ち、最終終了コードを確認します。

| 1回のラッパー実行の結果 | App Bridge への通知 |
|---|---|
| 最初から処理完了 | 送信しない |
| 途中でエラーが発生したが、本体の再試行で回復して処理完了 | 送信しない |
| 本体の再試行を終えても最終的に処理失敗 | `SendErrorEx` を1回呼ぶ |
| 本体・実行エンジンが見つからない等、起動準備の失敗 | `SendErrorEx` を1回呼ぶ |
| App Bridge通知コマンドも実行できない・失敗する | ローカルログに記録し、ラッパーが終了コード `2` を返す |

ラッパーは途中のエラー出力や過去のログ内の「ERROR」という文字を通知条件に使いません。収集本体の再試行を待ち、最終終了コードだけで収集の成否を判断します。収集本体をラッパー側で追加再実行する処理も入れていません。

App Bridgeへの送信には、Windows Agent同梱の `SendErrorEx` を使用します。メールの宛先は App Bridge のWeb画面で設定します。スクリプト側に SMTPサーバー、メールパスワード、App Bridge APIトークンを追加する構成ではありません。メッセージ送信コマンドはAgent経由で動作し、WindowsではAgentのインストールフォルダ内の `CLI` に配置されます。資料上、追加のインストール・設定は不要です。［資料1、本文p.3、p.8］

---

## 手順1：既存タスクの実行設定を控える

タスクスケジューラで現在の収集タスクを選択し、プロパティを開きます。変更前にタスクをエクスポートしておくと、元の起動設定を確認できます。

次を控えてください。

| 現在の設定 | ラッパーへの引き継ぎ先 |
|---|---|
| ［操作］の「プログラム/スクリプト」 | `$CollectorPowerShell`。収集本体を実際に動かしている `pwsh.exe` 等のフルパス |
| `-File` の直後に指定されている収集本体のパス | `$CollectorScript` |
| 収集本体へ渡している引数。例：`-ConfigPath` | `$CollectorArguments` |
| PowerShell自体へ渡している起動オプション | `$CollectorHostArguments`。`-File` は含めない |
| 「開始（オプション）」 | `$CollectorWorkingDirectory` |
| ［全般］の実行ユーザー、ログオン設定、最上位権限の設定 | 変更後のタスクでも維持 |
| トリガー・実行時刻 | 変更後のタスクでも維持 |

元の収集スクリプトや設定ファイルを移動・改名する必要はありません。追加ラッパーの変数に、既存ファイルの正確なフルパスを指定します。

既存タスクが `cmd.exe` やバッチファイルなどを経由している場合は、その中で実際に起動しているPowerShell、収集本体、引数を確認してください。途中で環境変数の設定などを行っている場合は、その実行条件も引き継ぐ必要があります。

「開始」が空欄で相対パスの引数を使っている場合は、どのフォルダを基準にしているかを確認してください。ラッパーでは作業フォルダを明示し、設定ファイルなどの引数もフルパスにすると設定を確認しやすくなります。

### 収集に使う PowerShell 7 を確認する

既存タスクで使っている `pwsh.exe` のフルパスに置き換えて、Windows PowerShellから次を実行します。収集本体は実行しません。

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString(); [Environment]::Is64BitProcess'
```

期待する表示は、バージョンが `7.4` 以上、続く行が `True` です。ファイルが見つからない場合は実際の導入先を確認します。PowerShell 7自体がない場合、添付版の本体を変更せずに Windows PowerShell 5だけで収集することはできません。

**タスクの実行ユーザーを変更しないでください。** 添付版のClaude本体は、実行ユーザーの環境変数からAPIキーを取得する処理があります。手作業のテストが成功しても、別のアカウントで動くタスクでは同じキーやファイルにアクセスできるとは限りません。

## 手順2：App Bridge の `SendErrorEx` の実パスを確認する

Agentのインストールフォルダを開き、その配下の `CLI` にある `SendErrorEx.exe` を確認します。資料に絶対インストール先は指定されていないため、実機で確認したフルパスを使います。［資料1、本文p.3］

導入先が不明な場合の検索例です。検索範囲によっては時間がかかります。

```powershell
$agentSearchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
    Select-Object -Unique

Get-ChildItem -LiteralPath $agentSearchRoots -Filter 'SendErrorEx.exe' -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName
```

検索結果が複数ある場合は、現在稼働している Windows Agent のインストールフォルダに属するものを確認します。別ドライブに導入されている場合はその場所を確認してください。

ファイルがない場合は、使用中のAgent版に `SendErrorEx` が含まれるかを管理者に確認してください。この手順が参照するユーザメッセージ監視サービスガイドは Ver.1.19.0 です。

## 手順3：App Bridgeでメールの標準通知先を登録する

今回は Claude と ChatGPT の失敗を同じメールアドレスへ送る例にします。

1. App Bridge Web画面で、［メインメニュー］→［監視設定］→［ノード一覧］→［標準通知先］を開きます。
2. 標準通知先一覧で［追加］を押します。
3. 次を設定して［OK］を押します。

| 項目 | 設定例 |
|---|---|
| 標準通知先コード | `COMPLIANCE_MAIL` |
| 標準通知先名 | `コンプライアンスログ収集エラー通知` |
| 有効にする | チェックする |

4. 作成した標準通知先の詳細画面を開きます。
5. ［指定アドレスを通知先に追加］を押します。
6. 通知先アドレスに受信メールアドレスを入力し、種別を **To** にして［OK］を押します。
7. 標準通知先と、その通知先アドレスが有効であることを確認します。

この方法は、App Bridgeのユーザー情報を使わず、メールアドレスを直接登録する「オンデマンド通知先」です。運用グループのメールアドレスでも設定できます。標準通知先コードは英数字と `_` を用い、1～50文字にします。［資料2、本文p.4–5、p.8–10］

### オーナ・対象ノードの通知が有効か確認する

以下の両方で「通知メッセージを有効にする」と「標準通知を行う」が有効であることを確認します。

| 対象 | 画面 |
|---|---|
| オーナ | ［メインメニュー］→［基本設定］→［オーナ基本設定］ |
| 収集を実行しているWindowsのノード | ［メインメニュー］→［基本設定］→［ノード基本設定］→対象ノード |

これらが無効の場合はメール通知されません。設定変更権限がない場合は、管理者へ有効化を依頼してください。［資料2、本文p.2–3、p.10］

## 手順4：通知振分条件を追加する

［メインメニュー］→［通知設定］→［通知振分条件］を開き、［追加］を押します。画面構成が異なる場合は「通知振分条件」の項目を開いてください。資料内の事例では「監視設定」配下として案内されている箇所もあります。［資料2、本文p.35］

以下の例では、Claude用を `9100-101-A`、ChatGPT用を `9100-102-A` とします。他の用途で未使用のコードであることを確認してください。

| 項目 | 設定する内容 |
|---|---|
| 順序番号 | 例：`100`。ただし、同じメッセージに一致する既存の包括的な条件より前になる値にする |
| 通知振分条件コード | `COMPLIANCE_ERROR_MAIL` |
| 通知振分条件名 | `コンプライアンスログ収集 最終失敗` |
| 有効にする | チェックする |
| 利用開始日時 | 現在以前の日時 |
| 利用終了日時 | 「設定する」のチェックを外す |
| 後続振分条件の評価 | **チェックを外す** |
| メッセージの種類と発生理由 | 「設定する」をチェックし、「発生理由を指定する」を選ぶ |
| 発生理由 | **メッセージ受信** |
| メッセージ種類 | **Error** だけをチェックする |
| 通知コードを比較する正規表現 | 「設定する」をチェックし、`^9100-(101|102)-A$` を入力する |
| ノードCD・ノードタグの条件 | この例では未設定。専用コードを対象Windows以外でも使う場合は、実際のノードCD等で絞り込む |
| 件名・本文の条件 | 未設定 |
| 指定日・休日属性・曜日指定・指定時刻 | 24時間通知する場合は未設定 |
| 標準通知先 | `COMPLIANCE_MAIL` を選択する |
| 電話通知先 | 選択しない |

設定後、［OK］で保存します。

**発生理由は「メッセージ受信」です。** メッセージ送信コマンドから受け取る通知がこの分類に該当します。「エラー発生検知」は監視ステータスの変化に関する別の分類です。［資料2、本文p.37］

### 1つの失敗でメールが重複しないようにする

通知振分条件は順序番号の小さい順に評価されます。一致した条件の「後続振分条件の評価」が有効だと、後続の条件からも通知される可能性があります。［資料2、本文p.35–38］

新しい条件を、同じ通知を拾う既存の包括的な条件より前に置き、新しい条件の後続評価を無効にしてください。初期状態の `_DEFAULT` は順序番号 `9999` ですが、現在の設定が初期状態と同じとは限りません。`100` と入力するだけで終わらず、実際の一覧で前後関係を確認します。［資料2、本文p.44］

新しい条件より前に、一致した通知を既に送信してから後続評価を続けるルールがあると、その送信を取り消すことはできません。既存条件との順序確認が必要です。

また、［監視設定］→［抑止条件］で、この通知コード・ノード・時間帯などが抑止されないことも確認してください。抑止されたメッセージは通常「確認状態：抑止」となり、通知振分の対象になりません。［資料2、本文p.39］

## 手順5：追加スクリプトを置き、冒頭の変数を設定する

作成済みの `Invoke-ComplianceCollectionWithNotify.ps1` を、実行対象Windowsの次の場所へ置きます。

```text
C:\ComplianceNotification\Invoke-ComplianceCollectionWithNotify.ps1
```

このフォルダ名は提案する配置例です。既存の収集本体は現在の場所に置いたままにします。

ファイル冒頭の「設定する変数（ここから）」～「設定する変数（ここまで）」を編集します。以下はClaude用の例です。

```powershell
$JobName = 'Claude'

$CollectorPowerShell = 'C:\Program Files\PowerShell\7\pwsh.exe'
$CollectorScript = 'C:\ClaudeComplianceCollector\Collect-ClaudeCompliance.ps1'
$CollectorArguments = @('-ConfigPath', 'C:\ClaudeComplianceCollector\config.json')
$CollectorWorkingDirectory = 'C:\ClaudeComplianceCollector'

$SuccessExitCodes = @(2)

$SendErrorExPath = 'C:\REPLACE_WITH_AGENT_FOLDER\CLI\SendErrorEx.exe'
$NotificationCode = '9100-101-A'

$WrapperLogDirectory = 'C:\ComplianceNotification\logs\Claude'
$CollectorLogHint = 'C:\ClaudeComplianceCollector\logs'

$CollectorHostArguments = @('-NoLogo', '-NoProfile', '-NonInteractive')
```

**この例をそのまま保存する前に、次の設定を実環境に合わせてください。**

| 変数 | 設定のポイント |
|---|---|
| `$CollectorPowerShell` | 手順1で確認した、64ビット版7.4以上の `pwsh.exe` の実パス |
| `$CollectorScript` | 現在使っている収集本体の実パス。例の `Collect-ClaudeCompliance.ps1` は仮の名前であり、添付名のような括弧付きファイル名でも実名をそのまま指定する |
| `$CollectorArguments` | 現在の本体用引数を要素ごとに指定。引数名と値は別要素にする。引数がなければ `@()` |
| `$CollectorWorkingDirectory` | 現在の収集が前提とする作業フォルダ。タスクの変更後も本体の作業フォルダはこちらで維持する |
| `$SuccessExitCodes` | 添付Claude版は **`@(2)` のまま**。安易に `@(0, 2)` へ広げない |
| `$SendErrorExPath` | 手順2で確認した実パス。`REPLACE_WITH_AGENT_FOLDER` は必ず置き換える |
| `$NotificationCode` | Webの振分条件と合わせる。Claudeはこの例では `9100-101-A` |
| `$WrapperLogDirectory` | 追加ラッパーの診断ログを置く場所。実行ユーザーが作成・追記できること |
| `$CollectorLogHint` | メールに案内する収集本体のログフォルダ。本文ログを読み取る設定ではない |
| `$CollectorHostArguments` | 収集本体を呼ぶPowerShellの起動オプション。既存タスクで必要な指定があれば引き継ぐ。`-File` と収集本体パスはラッパーが付与するので含めない |

括弧付きファイル名の設定例：

```powershell
$CollectorScript = 'C:\ClaudeComplianceCollector\Collect-ClaudeCompliance(3)(2).ps1'
```

APIキーやパスワードをこのラッパーへ貼り付ける必要はありません。収集本体はこれまでと同じ実行アカウント・設定を使って起動します。通知本文には本体の生のログやAPI応答、APIキーを載せず、判定結果・終了コード・実行ID・診断ログの場所を記載します。

### 保存時の注意

配布した `.ps1` は **UTF-8 BOM付き**です。日本語を含むため、編集後もUTF-8 BOM付きのまま保存してください。Windows PowerShell 5でUTF-8の日本語を正しく読み取れるようにするためです。［Microsoft公式：[about_Character_Encoding](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding?view=powershell-5.1)］

実行アカウントが、追加 `.ps1` と収集本体・設定ファイルを読み取り、ログ出力先へ書き込み、`SendErrorEx.exe` を実行できることを確認します。スクリプトの実行が組織の実行ポリシーで制限される場合は、署名など既存の運用手順に従ってください。ラッパー自体が起動できなければ、ラッパーからの通知も実行できません。

## 手順6：収集本体を動かさず、成功・失敗の通知分岐を確認する

通常のWindows PowerShellコンソールを開き、以下を実行します。可能であれば、実際のタスクと同じアカウントで確認してください。ここで使用する `powershell.exe` は追加ラッパー用です。

### 成功分岐の試験

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File 'C:\ComplianceNotification\Invoke-ComplianceCollectionWithNotify.ps1' -TestMode Success
$LASTEXITCODE
```

期待する結果：

- 収集本体は実行されない。
- メールは送られない。
- ラッパーの終了コードは `0`。
- ラッパーログに `TEST_SUCCESS` と `SUCCESS` が記録される。

この成功試験は、成功時に通知しない分岐を確認するものです。収集本体のファイルやPowerShell 7の起動、APIキー、API通信を確認する試験ではありません。

### 失敗分岐・メール到達の試験

**次の試験では実際のエラーメールが送られます。** 件名の先頭に `[TEST]` が付きます。収集本体は実行されません。

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File 'C:\ComplianceNotification\Invoke-ComplianceCollectionWithNotify.ps1' -TestMode Failure
$LASTEXITCODE
```

期待する結果：

- App Bridgeへの通知コマンドを1回実行する。
- コマンドが正常終了した場合、ラッパーの終了コードは `1`。これは失敗を模擬した結果として正常な試験結果。
- App Bridge Webの通知メッセージに、`9100-101-A` のErrorが1件表示される。
- 設定した宛先にメールが1通届く。
- ラッパーログに `TEST_FAILURE`、`NOTIFY_ATTEMPT`、`NOTIFY_EXIT exit=0`、`FAILURE_NOTIFIED` が記録される。

ラッパーの戻り値が `2` の場合は、通知コマンドの起動や実行にも失敗しています。手順10のログ確認で原因を調べます。

**`SendErrorEx` の戻り値 `0` はメール到達完了を意味しません。** Agentからセンタへは他の監視データとともに送られるため、到着まで時間がかかることがあります。センタと通信できない場合の再送はAgentが担当します。Agent停止中にコマンドが正常終了し、Agent起動後に送信される場合もあります。［資料1、本文p.3、p.9］

## 手順7：タスクスケジューラの起動先をラッパーへ変更する

手順6でWeb通知とメール到達を確認してから、現在のClaude収集タスクのプロパティを開きます。収集が動作中の場合は、完了を待ってから変更します。

### ［操作］タブ

既存の収集起動の操作を編集し、次に置き換えます。元の収集操作を残してラッパー操作を追加すると、二重に収集を起動してしまいます。**収集を起動する操作はラッパー1つにしてください。**

| 入力欄 | 設定例 |
|---|---|
| 操作 | プログラムの開始 |
| プログラム/スクリプト | `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` |
| 引数の追加 | `-NoLogo -NoProfile -NonInteractive -File "C:\ComplianceNotification\Invoke-ComplianceCollectionWithNotify.ps1"` |
| 開始（オプション） | `C:\ComplianceNotification` |

Windowsのインストール先が `C:\Windows` 以外なら、その実パスに合わせます。「開始」欄のフォルダは引用符で囲みません。通常実行用の引数には `-TestMode` を入れません。

ラッパー用の作業フォルダは `C:\ComplianceNotification` ですが、収集本体は `$CollectorWorkingDirectory` を作業フォルダとして起動します。既存の収集に必要な作業フォルダは手順5で維持しています。

PowerShellの `-File` はスクリプトを起動し、明示した `exit` の値をプロセスの終了コードとして返せます。ラッパーの最終終了コードがタスクの結果になります。［Microsoft公式：[about_PowerShell_exe](https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)］

### ［全般］・［設定］タブ

| 項目 | 設定する内容 |
|---|---|
| 実行ユーザー・ログオン設定・最上位権限の設定 | 現在の収集に必要な設定を維持する |
| トリガー | 現在の収集スケジュールを維持する |
| タスクが既に実行中の場合 | 「新しいインスタンスを開始しない」を選ぶ |
| タスクが失敗した場合の自動再起動 | 今回の構成では無効にする |
| 実行時間超過時の強制停止 | 必要な収集時間・本体の再試行時間より短い値を設定しない |

タスクスケジューラが失敗したタスクを自動再起動すると、ラッパーをもう1回実行することになります。その再実行も失敗すれば、別の実行としてもう1通通知します。**本手順で待つ再試行は収集本体の内部の再試行です。** 最終失敗後にタスク全体を何回か再実行し、すべて失敗した後だけ通知する構成は、今回のラッパーには含めていません。

### 実際のタスクで1回確認する

保存後、同じタスクを右クリックして［実行］します。今度は実際の収集本体が動きます。

完了後は次を確認します。

- ラッパーログの `COLLECTOR_EXIT` に、本体の終了コードが記録されている。
- Claude本体が `2` で完了した場合、ラッパーログは `SUCCESS`、タスクの最終結果は `0x0` になる。
- 正常完了時はメールが送られない。
- 収集本体が最終失敗した場合は、ラッパーと本体のログを確認し、メールが1通届く。

手動コンソールの試験だけで終わらず、実際のタスクの実行アカウントで確認することが大切です。

## 手順8：ChatGPT用はラッパーをコピーし、変数を変更する

同じラッパーを次の名前でコピーします。

```text
C:\ComplianceNotification\Invoke-ChatGPTComplianceWithNotify.ps1
```

ChatGPT本体が「処理成功は終了コード `0`、最終失敗は `0` 以外を返す」仕様で、Windows PowerShell 5で動く場合の設定例です。実際の仕様を確認して変更してください。

```powershell
$JobName = 'ChatGPT'

$CollectorPowerShell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$CollectorScript = 'C:\ChatGPTComplianceCollector\Collect-ChatGPTCompliance.ps1'
$CollectorArguments = @()
$CollectorWorkingDirectory = 'C:\ChatGPTComplianceCollector'

$SuccessExitCodes = @(0)

$SendErrorExPath = 'C:\REPLACE_WITH_AGENT_FOLDER\CLI\SendErrorEx.exe'
$NotificationCode = '9100-102-A'

$WrapperLogDirectory = 'C:\ComplianceNotification\logs\ChatGPT'
$CollectorLogHint = 'C:\ChatGPTComplianceCollector\logs'

$CollectorHostArguments = @('-NoLogo', '-NoProfile', '-NonInteractive')
```

実際のChatGPT収集本体がPowerShell 7を必要とする場合は、`$CollectorPowerShell` にその `pwsh.exe` を指定します。引数がある場合は既存タスクの引数を `$CollectorArguments` に引き継ぎます。例のフォルダ名・本体名・ログ出力先は仮の名前です。

続いて、手順6の成功・失敗試験をChatGPT用ラッパーのパスで実施します。`9100-102-A` がWebの振分条件に含まれていれば、同じメール通知先に届きます。

ChatGPT用の既存タスクの操作も、手順7と同様に、コピーしたラッパーを起動する設定に変更します。

```text
-NoLogo -NoProfile -NonInteractive -File "C:\ComplianceNotification\Invoke-ChatGPTComplianceWithNotify.ps1"
```

### ChatGPT本体に必要な終了コードの仕様

ChatGPT収集スクリプトは添付されていないため、その終了コードや失敗時の挙動は未確認です。次が満たされていれば、ラッパーの処理本体を変えず、設定変数だけで対応できます。

- 成功した実行は、設定した正常終了コードを返す。
- 最終失敗した実行は、正常終了コードとは異なる値を返す。
- 内部の再試行が完了するまで収集プロセスが終了しない。
- バックグラウンド処理を起動しただけで、収集完了前に親プロセスが成功終了しない。

失敗を `catch` で握りつぶして正常と同じ `0` を返す本体では、終了コードだけで失敗を区別できません。また、途中の `Write-Error` の有無だけで最終失敗を決めると、再試行で回復した実行も通知してしまいます。成功と失敗が同じ終了コードになる場合は、本体が既に出力する今回実行のステータスファイルなど、別の確実な判定材料に合わせた調整が必要です。

したがって、**「どのようなChatGPTスクリプトでも変数だけで確実に通知できる」とは保証していません。** 本体の終了コードを確認することが、汎用ラッパーを使う前提です。

## 手順9：終了コードとログの見方

### 追加ラッパーの終了コード

タスクスケジューラが最終結果として見るのは、この表の値です。

| 値 | タスク表示の例 | 意味 |
|---|---|---|
| `0` | `0x0` | 収集本体が指定された正常終了コードで完了。通知しない |
| `1` | `0x1` | 収集または起動準備が失敗。`SendErrorEx` は正常終了した |
| `2` | `0x2` | 収集または起動準備が失敗。`SendErrorEx` も失敗・起動不可 |

ここでラッパーの `2` は通知側の失敗です。添付Claude本体の処理完了を表す `2` とは意味が異なります。本体の `2` はラッパーが `0` に変換して終了します。

### 添付Claude本体の終了コード

添付ソースの終了分岐に基づく整理です。

| 値 | 主な意味 | 今回の通知 |
|---|---|---|
| `2` | 処理完了。取得範囲の制約は残る | なし |
| `1` | API・ネットワーク再試行の消化、回復不能なHTTP応答、一般的なローカル処理失敗、ログ保存失敗など | あり |
| `3` | 認証・権限の問題など | あり |
| `4` | チェックポイント、保存データ等の整合性に関する問題など | あり |
| `5` | 実行環境・設定・APIキー取得等の問題など | あり |
| `6` | 別の収集プロセスがロックを保持している | あり |
| その他 | 予期しない終了、エンジン側の起動・実行問題など | あり |

この表は代表的な原因です。最終的な詳細は収集本体の保護されたログを確認してください。互換性エラーや構文エラーのように、本体の終了処理へ到達する前にエンジンが終了する場合もあります。

### `SendErrorEx` の終了コード

| 値 | 意味 |
|---|---|
| `0` | コマンド正常終了。メール到達までは保証しない |
| `12` | 引数の誤り |
| `16` | 例外が発生した |
| `20` | 1時間あたりの最大実行回数を超えた |

`12` と `16` のエラー情報は標準エラーにも出力されます。ラッパーはその生テキストをメールへ転記せず、戻り値と判定ラベルを記録します。［資料1、本文p.9］

`SendErrorEx` の通知コードは `ZZXX-XXX-X` の形式です。先頭の `ZZ` は `91`～`95`、`X` は英数字です。件名と本文にはUTF-8換算のバイト数制限があるため、ラッパーでは件名を180バイト、本文を3,500バイト以内に収めます。日本語の文字数ではなくバイト数で制限しています。［資料1、本文p.8］

### 診断ログ

Claude用のラッパーログの例：

```text
C:\ComplianceNotification\logs\Claude\20261020_094109_<実行ID>.log
```

1回の実行ごとに別ファイルを作り、日時・実行ID・イベント・終了コードを記録します。日時は実行Windowsのローカル時刻とUTCオフセットで記録します。

本体のログは既存の出力先に残ります。添付Claude版は `C:\ClaudeComplianceCollector\logs` です。ラッパーは本体の標準出力・標準エラーを別ファイルへ丸ごと保存しません。通常の収集障害の詳細は、本体が既に保存するログを確認します。

ラッパーのログ保持日数や自動削除は実装していません。既存のログ保管運用に合わせて管理してください。

## 手順10：メールが届かない場合の確認順

### まずラッパーが起動したか

ログに `START` がない場合は、タスクの起動先、ラッパーのパス、実行アカウント、実行ポリシー、構文エラー、ログフォルダへの権限を確認します。ログ保存自体に失敗した場合は標準エラーへ退避するため、同じコマンドをコンソールで実行して確認します。

ラッパーが動き始める前のエラーは、ラッパー内から通知できません。

### ラッパーがどこで失敗したか

| ログのイベント・判定理由 | 主な確認先 |
|---|---|
| `SUCCESS` | 正常分岐。メールがないのは想定どおり |
| `COLLECTOR_POWERSHELL_NOT_FOUND` | `$CollectorPowerShell` のフルパス |
| `COLLECTOR_SCRIPT_NOT_FOUND` | `$CollectorScript` の実ファイル名・フルパス |
| `COLLECTOR_WORKING_DIRECTORY_NOT_FOUND` | `$CollectorWorkingDirectory` の実在 |
| `COLLECTOR_START_OR_WAIT_FAILED` | 実行ファイルの権限、プロセス起動条件、実行アカウント |
| `COLLECTOR_EXIT_NOT_ACCEPTED` | 本体の終了コードと `$SuccessExitCodes`、本体の既存ログ |
| `WRAPPER_SETUP` | ラッパーログ出力先、正常コード設定等の起動準備 |
| `INVALID_NOTIFICATION_CODE` | `$NotificationCode` の書式 |
| `SEND_ERROR_EX_NOT_FOUND` | `$SendErrorExPath` の実パス |
| `SEND_ERROR_EX_START_OR_WAIT_FAILED` | App Bridge CLIの実行権限、起動条件 |
| `SEND_ERROR_EX_NONZERO_EXIT` | `NOTIFY_EXIT` の戻り値、上の `SendErrorEx` 戻り値表 |
| `FAILURE_NOTIFIED` | 通知コマンドは正常終了。次にWeb上の受信とメール経路を確認 |

### Webに通知メッセージがあるか

`SendErrorEx` が正常終了したのにWebに出ない場合は、Agentの稼働、センタとの通信、送信待ちを確認します。本文p.3の仕様どおり、通信できない場合の再送はAgentが行います。スケーリング制御ノードでは、Agent停止中にノードレベルの送信を行うと戻り値 `16` になる場合があります。［資料1、本文p.3–4］

### Webには出るがメールが届かない場合

次を順に確認します。

1. 通知コードが `9100-101-A` または `9100-102-A` で、振分条件と一致している。
2. 発生理由が「メッセージ受信」、種類が `Error` の条件になっている。
3. オーナ・ノードの「通知メッセージを有効にする」「標準通知を行う」が有効。
4. 標準通知先と個々のメールアドレスが有効で、標準通知先を振分条件で選択している。
5. 利用開始・終了日時、曜日や時間帯、先行する振分条件が妨げていない。
6. 抑止条件に一致していない。
7. メールの受信アドレス、迷惑メール、受信側の振分を確認する。

設定項目と評価条件の根拠は、資料2の本文p.2–10、p.35–39です。

### 同じ失敗にメールが複数届く場合

実行IDを比較します。実行IDが違えば、タスクの自動再起動・二重トリガー・手動再実行などで、ラッパー自体が複数回動いていないかを調べます。実行IDが同じなら、通知振分の後続評価、先行ルール、通知先アドレスの重複、別の監視設定による通知を確認します。

ラッパーは1実行につき通知コマンドを1回しか呼びません。このことと、メールシステム全体での厳密な重複排除は別です。今回の設定では、振分条件の重複配送も避けるようにします。

### 試験を連続実行した場合の制限

`SendError`・`SendErrorEx`・`SendErrorAPI` は、同じWindows上のエラー系コマンドのグループとして、初期設定で合計100回/時間までです。上限を超えると `20` を返します。ClaudeとChatGPTで通知コードを分けても、この上限は別枠にはなりません。［資料1、本文p.4］

センタ側では、ノードレベルのユーザメッセージは、同一サーバインスタンス・同一メッセージ種類・同一通知コードについて、同一発生分内10件に書込みを抑止します。試験を短時間に繰り返して未着になる場合は、この制限も確認してください。［資料2、本文p.43］

## 任意の追加確認：途中のエラー出力後に成功したとき通知しない

この試験は本番ラッパーを直接変更せず、コピーで行います。以下はPowerShellで作成するダミー本体の例です。

```powershell
@'
Write-Error 'Simulated transient error; recovered before completion.' -ErrorAction Continue
Write-Output 'Simulated retry completed successfully.'
exit 2
'@ | Set-Content -LiteralPath 'C:\ComplianceNotification\Test-TransientThenSuccess.ps1' -Encoding UTF8

Copy-Item -LiteralPath 'C:\ComplianceNotification\Invoke-ComplianceCollectionWithNotify.ps1' -Destination 'C:\ComplianceNotification\Test-Wrapper.ps1'
```

コピーした `Test-Wrapper.ps1` の設定だけを次のように変更します。他の設定は動作確認済みの値を維持します。

```powershell
$JobName = 'Claude-TransientTest'
$CollectorScript = 'C:\ComplianceNotification\Test-TransientThenSuccess.ps1'
$CollectorArguments = @()
$CollectorWorkingDirectory = 'C:\ComplianceNotification'
$SuccessExitCodes = @(2)
$WrapperLogDirectory = 'C:\ComplianceNotification\logs\TransientTest'
```

`-TestMode` を付けずにコピーを実行します。

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File 'C:\ComplianceNotification\Test-Wrapper.ps1'
$LASTEXITCODE
```

期待する結果は、途中でエラー文が表示されてもラッパーの終了コードは `0`、メールなしです。これは「エラー出力があっても最終コードが正常なら通知しない」という判定を確認します。実APIへの再試行そのものを再現する試験ではありません。

試験用コピーは通常の収集タスクに登録しないでください。本番タスクの起動先が元の `Invoke-ComplianceCollectionWithNotify.ps1` のままであることを確認します。

## この構成で検知できる範囲

このラッパーが動き、子プロセスの終了を確認できた実行について、設定した終了コードで最終成否を判定します。元の収集スクリプトの内容は変更しません。ログやチェックポイントの更新は本体の既存処理に任せます。

次はこのラッパー内のエラー通知だけでは検知できません。

- Windows停止、電源断、OS障害。
- タスクがそもそも起動しない、実行アカウントの問題で起動できない。
- ラッパー自身の構文エラー・実行ポリシー制限など、コード実行開始前の失敗。
- タスクやラッパーが外部から強制終了される。
- 収集本体が終了せず、ラッパーが終了待ちを続ける。
- 本体が最終失敗を正常と同じ終了コードで返す。

これらが必要な監視対象に含まれる場合は、タスク実行有無・最終成功時刻・死活監視など、別の観測が必要です。今回のコードにタイムアウトや追加再試行は入れていません。

今回の成果物は、添付資料と添付ソースを照合し、オフラインでコードを確認したものです。実機の Windows PowerShell 5・Windowsのプロセス起動・導入済み App Bridge Agent・メール配送を組み合わせた試験は未実施です。導入時には手順6の通知試験と手順7の実タスク確認を行ってください。

## 参照資料

以下のPDFページ番号は、PDFビューアの通し番号ではなく、本文下部に印刷されたページ番号です。両資料とも本文p.1はPDF上の4ページ目です。

1. 添付「App Bridge Monitor ユーザメッセージ監視サービスガイド」Ver.1.19.0。ファイル名 `011900_070_App_Bridge_Monitor_UserMessage(1).pdf`。本文p.3：Agent経由の送信とWindows CLI配置、p.4：実行制限、p.8：`SendErrorEx` の書式・通知コード・長さ制限、p.9：戻り値。
2. 添付「App Bridge Notification 通知サービスガイド」Ver.1.19.2。ファイル名 `011902_100_App_Bridge_Notification (1)(1).pdf`。本文p.2–3：オーナ・ノードの通知有効化、p.4–10：標準通知先・アドレス、p.35–38：通知振分、p.39：抑止、p.43：書込み抑止、p.44：初期設定。
3. 添付収集ソース `Collect-ClaudeCompliance(3)(2).ps1`。必要エンジン、実行環境チェック、終了コード、内部再試行、ログとAPIキーの参照方法を確認。
4. Microsoft Learn「[Windows に PowerShell 7 をインストールする](https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows)」。Windows PowerShellとの共存、導入方法。
5. Microsoft Learn「[about_PowerShell_exe](https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)」。Windows PowerShellの `-File` と終了コード。
6. Microsoft Learn「[about_Character_Encoding](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding?view=powershell-5.1)」。Windows PowerShellで非ASCII文字を含むスクリプトをUTF-8 BOM付きにする理由。
