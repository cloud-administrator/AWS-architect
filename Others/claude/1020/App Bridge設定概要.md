**元の収集スクリプトを変更せず、追加のラッパースクリプトから実行し、最終的に失敗した場合だけApp Bridgeへ通知する構成を用意しました。**  
Claude用・ChatGPT用は、ラッパー冒頭の変数を変更して使い分けられます。

ただし、添付のClaudeスクリプトには、設定前に押さえておく必要がある点が2つあります。

| 確認事項 | 添付スクリプトの仕様 | 今回の対応 |
|---|---|---|
| 必要なPowerShell | **64ビット版PowerShell 7.4以上** | 追加ラッパーはWindows PowerShell 5で動かし、収集本体はPowerShell 7の別プロセスで実行します |
| 処理完了時の終了コード | **`2`** | Claude用では`2`を正常として扱い、通知しません |

この2点は、添付ソースの実行要件と終了処理で確認しました。**PowerShell 5だけで、添付された収集本体を変更せずに実行することはできません。** ただし、現在のタスクが既にPowerShell 7を使用している可能性があるため、まず既存タスクの設定を確認してください。  
:chatgpt-content-reference{index="7"}

## 作成したファイル

ZIPには、ラッパースクリプトと詳しい日本語手順書を入れています。

- **一式：** AppBridge_Compliance_Notification_Package.zip[AppBridge_Compliance_Notification_Package.zip](sandbox:/workspace/scratch/cca9900affeb/output/appbridge/AppBridge_Compliance_Notification_Package.zip)
- **スクリプト：** Invoke-ComplianceCollectionWithNotify.ps1[Invoke-ComplianceCollectionWithNotify.ps1](sandbox:/workspace/scratch/cca9900affeb/output/appbridge/Invoke-ComplianceCollectionWithNotify.ps1)
- **詳細手順書：** README_AppBridge_ja.md[README_AppBridge_ja.md](sandbox:/workspace/scratch/cca9900affeb/output/appbridge/README_AppBridge_ja.md)

以下に、導入に必要な手順を順番に説明します。

---

## 1．今回の通知の仕組み

タスクスケジューラから追加ラッパーを起動し、ラッパーが収集本体の終了まで待ちます。その後、**収集本体の最終終了コード**を判定します。

| 収集の結果 | 通知 |
|---|---|
| 正常に処理完了 | 通知しない |
| 途中でエラーが出たが、収集本体の再試行で回復して処理完了 | 通知しない |
| 再試行後も最終的に処理失敗 | `SendErrorEx`を1回実行 |
| 収集スクリプトや実行エンジンが見つからず起動できない | `SendErrorEx`を1回実行 |

通知には、App Bridge Monitor Windows Agentに同梱されている **`SendErrorEx`** を使います。これにより、通知コード・件名・本文を指定してAgent経由でApp Bridgeへ送り、App Bridgeの「標準通知」からメールを送信します。

コマンドの配置・書式は、添付資料の本文p.3、p.8–9に基づきます。  
:chatgpt-content-reference{index="8"}

ラッパーは、途中のエラーログやエラー出力を成否判定に使いません。したがって、**再試行で回復したエラーを通知しない**という方針に合います。

## 2．既存タスクと、使用する実行ファイルを確認する

### 2-1．現在のタスク設定を控える

タスクスケジューラで、現在のClaude収集タスクのプロパティを開き、次を控えてください。変更前にタスクをエクスポートしておくと、元の設定を確認できます。

| 現在の設定 | 用途 |
|---|---|
| ［操作］の「プログラム/スクリプト」 | 収集本体を実行しているPowerShellの確認 |
| 収集スクリプトのフルパス | ラッパーの`$CollectorScript`に設定 |
| 収集スクリプトへ渡している引数 | `$CollectorArguments`に設定 |
| 「開始（オプション）」 | `$CollectorWorkingDirectory`に設定 |
| ［全般］の実行ユーザー | 変更後も同じアカウントを使用 |

**実行ユーザーは現在のままにしてください。** 添付のClaude収集本体は、実行ユーザーの環境変数からAPIキーを取得しています。別のアカウントに変えると、キーや必要なファイルにアクセスできなくなる場合があります。

### 2-2．PowerShell 7を確認する

Windows PowerShellから次を実行します。収集本体は起動しない確認コマンドです。

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString(); [Environment]::Is64BitProcess'
```

確認する結果は次の2つです。

- バージョンが **7.4以上**
- 続く行が **`True`**（64ビットプロセス）

導入先が異なる場合は、実際の`pwsh.exe`のパスに置き換えます。

PowerShell 7が未導入の場合は、対象Windowsに対応した64ビット版を[Microsoftのインストール手順](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.6)に従って用意してください。PowerShell 7とWindows PowerShell 5.1は並行して使用できます。[Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7?view=powershell-7.6\&utm_source=chatgpt.com)

### 2-3．`SendErrorEx`の実際のパスを確認する

Agentのインストールフォルダーを開き、その下の **`CLI`フォルダー**にある`SendErrorEx.exe`を確認します。

添付資料には絶対インストール先が記載されていないため、実機で確認したパスを使ってください。導入先が分からない場合、次の検索も使えます。

```powershell
Get-ChildItem -Path 'C:\Program Files','C:\Program Files (x86)' `
    -Filter 'SendErrorEx.exe' -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName
```

別ドライブにAgentを導入している場合は、そのフォルダーも確認してください。

## 3．App Bridgeでメール通知先と振分条件を設定する

以下は、**ClaudeとChatGPTの失敗を同じメールアドレスで受信する例**です。

### 3-1．「標準通知先」を追加する

1. **［メインメニュー］→［監視設定］→［ノード一覧］→［標準通知先］**を開きます。
2. ［追加］を押します。
3. 次の内容を設定して保存します。

| 項目 | 設定例 |
|---|---|
| 標準通知先コード | `COMPLIANCE_MAIL` |
| 標準通知先名 | `コンプライアンスログ収集エラー通知` |
| 有効にする | チェックする |

続いて、作成した標準通知先の詳細画面で設定します。

1. **［指定アドレスを通知先に追加］**を押します。
2. 通知先アドレスに、受信したいメールアドレスを入力します。
3. 種別を **`To`** にします。
4. 保存し、標準通知先と登録アドレスが有効であることを確認します。

### 3-2．「通知振分条件」を追加する

**［メインメニュー］→［通知設定］→［通知振分条件］→［追加］**を開きます。画面構成が異なる場合は、「通知振分条件」の項目を開いてください。

今回使用する通知コードは次の例とします。既存の用途と重複していないことを確認してください。

| 収集対象 | 通知コード |
|---|---|
| Claude | `9100-101-A` |
| ChatGPT | `9100-102-A` |

振分条件は、次のように設定します。

| 項目 | 設定内容 |
|---|---|
| 順序番号 | 例：`100`。**同じ通知に一致する既存の包括的な条件より前**になるように設定 |
| 通知振分条件コード | `COMPLIANCE_ERROR_MAIL` |
| 通知振分条件名 | `コンプライアンスログ収集 最終失敗` |
| 有効にする | チェックする |
| 利用開始日時 | 現在以前の日時 |
| 利用終了日時 | 設定しない |
| **後続振分条件の評価** | **チェックを外す** |
| メッセージの種類と発生理由 | 「設定する」をチェックし、「発生理由を指定する」を選択 |
| **発生理由** | **メッセージ受信** |
| **メッセージ種類** | **Error** |
| 通知コードを比較する正規表現 | 「設定する」をチェックし、**`^9100-(101\|102)-A$`**を入力 ※ |
| 件名・本文の条件 | 設定しない |
| 指定日・休日・曜日・時間帯の条件 | 24時間通知する場合は設定しない |
| 標準通知先 | `COMPLIANCE_MAIL` |
| 電話通知先 | 選択しない |

※入力する正規表現はこちらです。縦線の前にバックスラッシュは付けません。

```text
^9100-(101|102)-A$
```

**発生理由は「メッセージ受信」を選びます。** `SendErrorEx`などのメッセージ送信コマンドによる通知は、この分類に該当します。

また、重複配送を避けるため、次の2つをセットで確認してください。

- 新しい条件を、同じ通知に一致する既存の包括的な条件より前に置く。
- 新しい条件の「後続振分条件の評価」をオフにする。

初期状態の`_DEFAULT`は順序番号`9999`ですが、現在の設定が変更されている可能性があるため、実際の一覧で順序を確認します。

### 3-3．オーナ・ノードの通知が有効か確認する

次の両方で、**「通知メッセージを有効にする」「標準通知を行う」**が有効であることを確認します。

| 対象 | 画面 |
|---|---|
| オーナ | ［基本設定］→［オーナ基本設定］ |
| 収集を実行するWindowsのノード | ［基本設定］→［ノード基本設定］→対象ノード |

あわせて、今回の通知が「抑止条件」に一致しないことを確認してください。オーナ・ノード設定が無効で変更権限がない場合は、その設定を変更できる管理者に有効化を依頼します。

これらの画面設定は、添付資料の本文p.2–10、p.35–39、p.44に基づいています。  
:chatgpt-content-reference{index="9"}

## 4．追加スクリプトを配置し、変数を設定する

ダウンロードしたスクリプトを、対象Windowsの次の場所に配置します。

```text
C:\ComplianceNotification\Invoke-ComplianceCollectionWithNotify.ps1
```

このフォルダー名は配置例です。元の収集スクリプトは、現在の場所をそのまま使用できます。

追加スクリプトを開き、冒頭の「設定する変数」の部分を編集してください。Claude用の設定例は次のとおりです。

```powershell
$JobName = 'Claude'

$CollectorPowerShell = 'C:\Program Files\PowerShell\7\pwsh.exe'
$CollectorScript = 'C:\ClaudeComplianceCollector\Collect-ClaudeCompliance.ps1'
$CollectorArguments = @('-ConfigPath', 'C:\ClaudeComplianceCollector\config.json')
$CollectorWorkingDirectory = 'C:\ClaudeComplianceCollector'

# 添付Claude版は「2」で処理完了
$SuccessExitCodes = @(2)

# 実際のAgentインストール先へ変更する
$SendErrorExPath = 'C:\REPLACE_WITH_AGENT_FOLDER\CLI\SendErrorEx.exe'
$NotificationCode = '9100-101-A'

$WrapperLogDirectory = 'C:\ComplianceNotification\logs\Claude'
$CollectorLogHint = 'C:\ClaudeComplianceCollector\logs'

$CollectorHostArguments = @('-NoLogo', '-NoProfile', '-NonInteractive')
```

特に、次の設定を実環境に合わせてください。

| 変数 | 設定する内容 |
|---|---|
| `$CollectorPowerShell` | 手順2で確認した、64ビット版PowerShell 7.4以上の実パス |
| `$CollectorScript` | **現在使用している収集本体の正確なフルパス** |
| `$CollectorArguments` | 現在の収集本体へ渡している引数。引数名と値を別の要素にする |
| `$CollectorWorkingDirectory` | 現在の収集本体が前提とする作業フォルダー |
| `$SendErrorExPath` | 手順2で確認した`SendErrorEx.exe`の実パス |
| `$WrapperLogDirectory` | タスク実行ユーザーが書き込めるログ保存先 |

`Collect-ClaudeCompliance.ps1`は設定例の名前です。実際のファイル名が添付時と同じなら、例えば次のように指定します。

```powershell
$CollectorScript = 'C:\ClaudeComplianceCollector\Collect-ClaudeCompliance(3)(2).ps1'
```

**Claude用の`$SuccessExitCodes = @(2)`は、そのままにしてください。**

配布した`.ps1`はUTF-8 BOM付きです。日本語を含むため、編集後も**UTF-8 BOM付き**で保存してください。Windows PowerShellでは、BOMのないUTF-8スクリプト中の日本語を正しく解釈できない場合があります。[Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding?view=powershell-5.1\&utm_source=chatgpt.com)

## 5．収集本体を動かさず、通知をテストする

ラッパーには、実際の収集本体を起動しないテスト機能を付けています。

Windows PowerShellを開き、可能であれば**実際のタスクと同じアカウント**で実施してください。

### 5-1．正常時に通知しないことを確認する

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File 'C:\ComplianceNotification\Invoke-ComplianceCollectionWithNotify.ps1' -TestMode Success

$LASTEXITCODE
```

期待する結果は次のとおりです。

- 収集本体は実行されない。
- メールは送られない。
- 終了コードが **`0`** になる。

これは正常時の分岐を確認する試験です。収集本体やAPI接続の動作確認は、後の実タスク確認で行います。

### 5-2．失敗時にメールを受信できることを確認する

**次の試験では、実際にApp Bridgeへ通知します。** 件名の先頭に`[TEST]`が付き、収集本体は実行されません。

```powershell
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File 'C:\ComplianceNotification\Invoke-ComplianceCollectionWithNotify.ps1' -TestMode Failure

$LASTEXITCODE
```

期待する結果は次のとおりです。

- App Bridgeの通知メッセージに、コード`9100-101-A`のErrorが1件表示される。
- 設定した宛先にメールが1通届く。
- ラッパーの終了コードが **`1`** になる。

**この試験での`1`は、失敗を模擬して通知した結果として想定どおりです。** `2`だった場合は、通知コマンドの起動・実行にも失敗しています。

なお、`SendErrorEx`の正常終了は、メールの到着完了を意味しません。Agent経由で送信されるため、**Web画面への表示とメールの受信まで確認してください。**

## 6．タスクスケジューラの起動先を変更する

メール到達を確認できたら、既存のClaude収集タスクのプロパティを開きます。収集が動作中なら、完了を待ってから変更します。

### ［操作］タブ

現在の収集を起動する操作を編集し、次に置き換えます。

**プログラム/スクリプト**

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
```

**引数の追加**

```text
-NoLogo -NoProfile -NonInteractive -File "C:\ComplianceNotification\Invoke-ComplianceCollectionWithNotify.ps1"
```

**開始（オプション）**

```text
C:\ComplianceNotification
```

「開始」欄は引用符で囲みません。Windowsの導入先が`C:\Windows`以外なら、その実パスに合わせてください。

通常運用の引数には、`-TestMode`を入れません。

### ［全般］・［設定］タブ

| 項目 | 今回の設定 |
|---|---|
| 実行ユーザー・ログオン設定・必要な権限 | 現在の設定を維持 |
| トリガー | 現在の収集スケジュールを維持 |
| 既にタスクが実行中の場合 | **新しいインスタンスを開始しない** |
| タスクが失敗した場合の自動再起動 | **無効** |
| 実行時間超過時の停止 | 収集と内部再試行に必要な時間を確保 |

タスクスケジューラが自動再起動すると、ラッパーをもう一度実行することになります。その再実行も失敗すれば、別の実行として再び通知します。今回は、**収集本体の内部再試行が終わった時点で通知する運用**にするため、タスク全体の自動再起動は無効にします。多重起動を防ぐ設定と再起動設定は、Windowsのタスク設定として指定できます。[Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset?view=windowsserver2025-ps\&utm_source=chatgpt.com)

保存後、タスクを右クリックして［実行］し、実際の収集を1回確認してください。

**Claude本体が`2`で完了した場合、ラッパーは`0`を返すため、タスクの最終結果は`0x0`になります。**

## 7．ChatGPT用はコピーして変数を変更する

ラッパーを、例えば次の名前でコピーします。

```text
C:\ComplianceNotification\Invoke-ChatGPTComplianceWithNotify.ps1
```

以下は、ChatGPT収集本体が **Windows PowerShell 5で動き、成功時は`0`、最終失敗時は`0`以外を返す場合**の設定例です。

```powershell
$JobName = 'ChatGPT'

$CollectorPowerShell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$CollectorScript = 'C:\ChatGPTComplianceCollector\Collect-ChatGPTCompliance.ps1'
$CollectorArguments = @()
$CollectorWorkingDirectory = 'C:\ChatGPTComplianceCollector'

$SuccessExitCodes = @(0)

$NotificationCode = '9100-102-A'

$WrapperLogDirectory = 'C:\ComplianceNotification\logs\ChatGPT'
$CollectorLogHint = 'C:\ChatGPTComplianceCollector\logs'
```

同じWindowsのため、`$SendErrorExPath`は、Claude用で動作確認した値を使用できます。

実際のChatGPT本体がPowerShell 7を必要とする場合は、その`pwsh.exe`を指定してください。フォルダー・ファイル名・引数・ログ保存先も、現在のChatGPT用タスクに合わせます。

その後、ChatGPT用ラッパーでも成功・失敗のテストを実施し、既存のChatGPT収集タスクの引数を次に変更します。

```text
-NoLogo -NoProfile -NonInteractive -File "C:\ComplianceNotification\Invoke-ChatGPTComplianceWithNotify.ps1"
```

**ChatGPT側の終了コードの仕様だけは確認が必要です。** 本体が未添付のため、成功・失敗時の挙動は確認できていません。

最終失敗を`catch`で処理して正常時と同じ`0`を返すスクリプトでは、終了コードだけでは失敗を区別できません。その場合は、本体が既に出力する最終結果ファイルなど、別の判定材料に合わせた調整が必要です。

## 8．運用時の結果と、メールが届かない場合の確認

### タスクの最終結果

タスクスケジューラが見るのは、追加ラッパーの終了コードです。

| 終了コード | 意味 |
|---|---|
| **`0` / `0x0`** | 収集本体が設定した正常終了コードで完了。通知なし |
| **`1` / `0x1`** | 収集または起動準備が失敗。`SendErrorEx`は正常終了 |
| **`2` / `0x2`** | 収集または起動準備が失敗し、`SendErrorEx`も失敗・起動不可 |

ラッパーの診断ログは、Claude用の例では次のフォルダーに、実行ごとに作成されます。

```text
C:\ComplianceNotification\logs\Claude
```

メール本文には、収集対象、ホスト名、開始・終了時刻、実行ID、収集本体の終了コード、ログの場所を記載します。

### メール未着時の確認順

| 状況 | 確認する箇所 |
|---|---|
| ラッパーログに`START`がない | タスクの起動先、ファイルパス、実行アカウント、実行ポリシー、ログ保存権限 |
| ラッパーが`2`で終了 | `SendErrorEx`の実パス、実行権限、ログの`NOTIFY_FAILED`の理由 |
| 通知コマンドは正常終了したが、Webに通知が出ない | Agentの稼働、App Bridgeセンタとの通信、送信待ち |
| Webに通知が出るが、メールが届かない | 標準通知の有効設定、振分条件、条件の順序、抑止条件、宛先、迷惑メール |

詳細手順書には、通知コマンドの戻り値一覧と、**途中でエラーを出した後に正常終了するダミースクリプトで、通知されないことを確認する試験**も載せています。

### 検知できる範囲

この方式は、ラッパーが起動し、収集本体の終了結果を確認できた実行を対象にします。Windowsの停止、タスク自体の未起動、ラッパーの強制終了、収集が終了しない状態は、このラッパーだけでは通知できません。

また、添付Claude版の`2`は「処理完了」を示しますが、APIの取得範囲の制約などは残ります。今回の通知は、**収集処理の最終失敗を検知するもの**です。

スクリプトは添付資料・ソースとの照合、静的レビュー、Windows引数の扱いの確認を行っています。**Windows PowerShell 5と導入済みApp Bridgeを組み合わせた実機試験は未実施**のため、導入時には、手順5のメール受信確認と、手順6の実タスクでの確認を行ってください。
