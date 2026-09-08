# Claude Enterprise — Compliance Access Key 発行手順書

Web管理画面での発行・権限確認・Windows収集環境への受け渡し

対象：Activity Feedとチャット・プロジェクト本文を読む本番用キー  
確認日：2026年9月8日　／　版：1.0

> **操作するのは claude.ai の組織設定です**
>
> Claude ConsoleのAdmin API keyは、Compliance APIでは監査イベントの取得にだけ対応し、本文取得には使えません。通常のモデル呼出し用APIキーとも異なります。[4](#ref-4)

## 1. 実施前に確認すること

Web管理画面での操作は第2～3章、発行後のWindowsへの設定は第4章、トラブル対応は第5章、完了記録と公式資料は第6章に記載しています。

| 実施者の役割 | APIの有効化 | キー発行範囲 |
| --- | --- | --- |
| Primary Owner<br>（プライマリオーナー） | 可能 | 親組織配下全体、または単一組織 |
| Organization Owner<br>（組織オーナー） | 不可 | 自分の組織に限定 |
| Admin<br>（管理者） | 不可 | 本手順のAPIページは表示されない |

Enterpriseでの有効化は親組織のPrimary Ownerが行い、配下のリンク組織に適用されます。OwnerにはAPIページは見えても有効化トグルは見えません。[2](#ref-2)[3](#ref-3)

### 作業前に決めておく値

対象の本番組織名、キーの対象組織範囲、発行担当者、Windowsタスク実行アカウント、秘密の保管先、キー管理責任者を決めます。単一組織だけが対象なら、組織限定キーを基本とします。これは本手順の運用方針です。

キー名の例：prod-compliance-collector-read-20260908  
これは識別用の命名例であり、名前にprodを付けても対象組織や権限が変わるわけではありません。

適用範囲：公式ヘルプはPublic Sector組織を対象外としています。本書は通常のClaude Enterprise組織を対象とします。[2](#ref-2)

実テナントの管理画面にはログインしていません。画面名は公式資料の英語表記です。日本語UIの正確なラベル、画面配置、追加の確認ダイアログは不明です。実在しない画面図は掲載していません。

## 2. Web管理画面での発行

### 01  対象組織の組織設定を開く

ブラウザーで https://claude.ai/ にサインインし、本番の対象組織であることを確認します。画面左下のイニシャルからOrganization settingsを選び、APIを開きます。有効化から行う担当者はPrimary Ownerで操作します。[2](#ref-2)[10](#ref-10)

確認：対象組織と操作者の役割が、作業前に承認した内容と一致している。

### 02  Compliance APIを有効にする

Primary OwnerがCompliance APIのトグルを有効にします。既に有効なら変更しません。Ownerが発行を担当する場合は、親組織のPrimary Ownerに有効化を依頼してから次へ進みます。[2](#ref-2)

確認：Primary Ownerが有効状態を確認し、有効化日時を作業記録に残した。

> **動作確認のためにOFF／ONしないでください**
>
> OFFの間は新しい監査イベントが記録されず、未記録のイベントは後から回収できません。既に記録されたイベントを消す操作ではありません。[4](#ref-4)

### 03  キーの作成画面を開く

発行担当のPrimary Ownerまたは対象組織のOwnerで、同じAPIページのKeysセクションを開き、+ Create key（資料によってはCreate key）を選びます。用途が分かるキー名を入力します。[2](#ref-2)[3](#ref-3)

組織範囲：Ownerのキーは自組織限定です。Primary Ownerは親配下全体／単一組織のどちらも発行可能です。ただし、範囲を選ぶUI項目名・配置は公開資料では不明です。意図した範囲を確認できなければ、作成を確定せずPrimary OwnerまたはAnthropicへ確認してください。[3](#ref-3)

### 04  読み取りスコープを指定する

| 選択 | スコープ | 本案件での扱い |
| --- | --- | --- |
| 選択する | read:compliance_activities | Activity Feedを読む |
| 選択する | read:compliance_user_data | チャット・プロジェクト等を読む |
| 選択しない | delete:compliance_user_data | 削除はしない |
| 選択しない | read:compliance_org_data | 組織設定等のAPI取得はしない |

選ぶのは上の読み取り2種類だけです。analytics、write等の追加権限も不要です。組織UUIDは画面から取得します。スコープの権限内容は[1](#ref-1)、付与する組合せは本案件の要件によります。

### 05  作成を確定する

対象組織範囲・キー名・2つのスコープを確認し、Createを選びます。キー全文が表示されたら、その画面を閉じずに第3章の保管へ進みます。[1](#ref-1)[3](#ref-3)

## 3. キーの保管・発行内容の確認

### 06  キー全文を安全に保管する

表示された秘密値をコピーし、会社が承認した秘密管理先へ保管します。Compliance Access Keyの接頭辞はsk-ant-api01-です。全文の表示は一度だけなので、保管の完了を確認してから作成画面を閉じます。[3](#ref-3)

確認：秘密の保管先に値を登録でき、担当者がその保管レコードを特定できる。

メール、通常のチャット、作業チケット、手順書、ソースコード、画面録画にキーを書き込まないでください。画面共有中は秘密値を表示しません。クリップボードの履歴・同期も、社内の秘密情報取扱方針に従って管理します。これは本手順の安全上の運用ルールです。

### 07  一覧でスコープを再確認する

Organization settings → API → Keysに戻り、作成したキーのScopes列を確認します。read:compliance_activitiesとread:compliance_user_dataだけになっていることを記録します。接頭辞だけで権限が正しいとは判断しません。[1](#ref-1)

確認：削除権限・その他の不要な権限がなく、キー名と対象範囲が承認内容と一致している。

スコープは作成後に変更できません。誤った場合は、正しいスコープで別キーを作成して置き換えます。[3](#ref-3) 使用を始めていない誤発行キーは、識別を確認して削除する運用とします。

### 08  収集対象の組織UUIDを確認する

対象Enterprise組織でOrganization settings → Organizationを開き、ページ下部のOrganization IDをコピーします。Settings → AccountのOrganization IDからも確認できます。[5](#ref-5)

確認：本番の収集対象組織名とUUIDを一緒に記録した。

収集用のOrganizationUuidsには、実際のチャット・プロジェクトが属する組織UUIDを指定します。親範囲のキーを発行したことと、収集対象UUIDの指定は別です。親と実データ組織の対応が判別できない場合は推測せず確認します。前回の収集スクリプトは親UUIDから対象を自動展開しません。

> **キーの権限は「ファイルのメタデータだけ」には限定されません**
>
> read:compliance_user_dataは本文やファイル等を読む権限です。[1](#ref-1) 添付ファイル実体を取得しない制御は収集スクリプト側で行います。キー自体をメタデータ専用と説明しないでください。

### 発行完了と、収集完了は別です

Webでのキー発行は、秘密値の安全な保管と、対象範囲・スコープの確認までで完了です。API接続の成功や、対象データをすべて保存できたことは、この時点では未確認です。作業記録は第6章の様式を使用します。

## 4. Windows収集環境への受け渡し

この章は、前回のPowerShell収集スクリプトを使用する場合の追加作業です。発行担当者とWindowsタスク実行者が別でも構いません。秘密値は承認済みの安全な方法で受け渡してください。

### タスクを実行するWindowsアカウントで設定する

同じWindowsアカウントでPowerShell 7.6を起動します。次の先頭行でアカウント名を確認し、その後を実行して非表示の入力欄へキーを貼り付けます。管理者として別アカウントを使用しないでください。User環境変数はユーザー単位です。[7](#ref-7)[8](#ref-8)

```powershell
[Security.Principal.WindowsIdentity]::GetCurrent().Name
 
$Name = 'ANTHROPIC_COMPLIANCE_ACCESS_KEY'
$Target = [EnvironmentVariableTarget]::User
$Secret = Read-Host 'Compliance Access Key' -AsSecureString
$Ptr = [IntPtr]::Zero
try {
    if ($Secret.Length -eq 0) { throw 'Key is empty.' }
    $Ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    [Environment]::SetEnvironmentVariable(
        $Name,
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr),
        $Target
    )
}
finally {
    if ($Ptr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)
    }
    $Secret.Dispose()
}
-not [string]::IsNullOrWhiteSpace(
    [Environment]::GetEnvironmentVariable($Name, $Target)
)
```

最後のTrueは「そのアカウントのUser環境変数に空でない値がある」という確認だけです。API認証やスコープの確認ではありません。コードは[7](#ref-7)～[9](#ref-9)のAPIに基づく設定例で、この調査ではWindows上の実行確認はしていません。

### 既存の設定ファイルとの対応

C:\ClaudeComplianceCollector\config\collector.config.jsonで、KeyEnvironmentVariableをANTHROPIC_COMPLIANCE_ACCESS_KEY、KeyEnvironmentScopeをUserにします。OrganizationUuidsには手順08のUUIDを設定します。JSONへキーそのものは書きません。

User環境変数は秘密保管庫ではなく、値は文字列として保存されます。[7](#ref-7) 収集アカウント・端末を保護してください。既存スクリプトは起動時にUserスコープを明示して読みます。キー更新後は新しい収集プロセスで確認し、監査と本文それぞれの結果を運用手順に沿って評価します。

## 5. トラブル対応・キーの交換

### 画面が見つからない／APIが失敗する

| 症状 | 確認・対処 |
| --- | --- |
| APIページが見えない | claude.aiか、正しい組織か、Primary Owner／Ownerかを確認。Adminには当該ページが見えない。[2](#ref-2) |
| トグルだけが見えない | Ownerでは表示されない。親組織のPrimary Ownerに確認する。[2](#ref-2) |
| Compliance用スコープが選べない | APIの有効化と役割を確認する。[1](#ref-1) 解消しなければ担当窓口へ連絡し、別種のキーで代用しない。 |
| キー全文を控えず画面を閉じた | 全文は一度だけ表示される。[3](#ref-3) 再表示を前提にせず、新しいキーを発行し、未使用の旧キーを整理する。 |
| HTTP 401 | キー未設定、無効、削除・無効化等を確認する。タスク実行者のUser環境変数も確認。連続再試行で解決しようとしない。[6](#ref-6) |
| 監査は成功するが本文が403 | Admin API keyを使っていないか、read:compliance_user_dataがあるか確認する。正しいCompliance Access Keyへ置き換える。[4](#ref-4)[6](#ref-6) |
| 組織情報APIだけが403 | 本手順ではread:compliance_org_dataを付けないため、そのAPIで権限不足になることがある。疎通確認のためだけに追加しない。[6](#ref-6) |

問い合わせには日時、対象組織名／UUID、操作者の役割、キー名、キーID（確認できる場合）、HTTPステータス、request-idを記録します。秘密値、認証ヘッダー、本文は送らないでください。

### 通常の交換手順

新キーを同じ組織範囲・2つの読み取りスコープで作成 → 安全に保管 → 収集実行者の環境変数を更新 → 次の収集で監査と本文を確認 → 旧キーをKeys一覧から削除、の順に行います。[1](#ref-1) 旧キーを使用中の処理がないことも確認します。

公式資料ではCompliance Access Keyは自動失効しません。削除は次のAPIリクエストから有効で猶予はありません。[1](#ref-1) 交換周期と責任者は社内ルールで決めます。漏えい時は通常交換と異なり、露出したキーの即時削除を優先してください。

### 未確認事項（推測しない）

組織範囲を選ぶ具体的なUI項目名、本番／検証を切り替える専用項目、キー作成者の退職・役割変更が既存キーへ及ぼす影響は、この調査では不明です。必要な事項をPrimary OwnerまたはAnthropicへ確認して記録します。

管理画面のスクリーンショット、実テナントでの発行・接続試験は未実施です。キーが使えることは、収集対象データの完全保存を意味しません。

## 6. 完了記録・参照した公式資料

### 秘密値を書かない作業記録

| 記録項目 | 記入欄 |
| --- | --- |
| 対象組織名／収集対象UUID | 組織名：　　　　　　　　　UUID： |
| 発行者・日時／キー名 | 発行者：　　　　　　日時（JST）：<br>キー名： |
| 対象範囲・付与スコープ | 範囲：単一組織／親配下全体<br>□ 指定の読み取り2種類だけ　□ 削除権限なし |
| 保管・Windowsへの受け渡し | 保管レコード名：　　　　　タスク実行アカウント：<br>□ Web発行確認済み　□ 環境変数設定済み |
| API／収集確認（別判定） | 監査：未実施／成功／失敗　本文：未実施／成功／失敗<br>実行ID・結果・取得制約の記録先： |

### 公式資料一覧　確認日：2026年9月8日

<a id="ref-1"></a>

**[1] Anthropic｜Set up the Compliance API**

<https://platform.claude.com/docs/en/manage-claude/compliance-api-access>

<a id="ref-2"></a>

**[2] Anthropic｜Access the Compliance API**

<https://support.claude.com/en/articles/13015708-access-the-compliance-api>

<a id="ref-3"></a>

**[3] Anthropic｜Create an Admin API key（Enterprise向けの節を参照）**

<https://platform.claude.com/docs/en/manage-claude/admin-api-keys>

<a id="ref-4"></a>

**[4] Anthropic｜Compliance API FAQ**

<https://platform.claude.com/docs/en/manage-claude/compliance-faq>

<a id="ref-5"></a>

**[5] Anthropic｜Tenant Restrictions（Find your organization UUIDの節）**

<https://support.claude.com/en/articles/13198485-enforce-network-level-access-control-with-tenant-restrictions>

<a id="ref-6"></a>

**[6] Anthropic｜Handle Compliance API errors**

<https://platform.claude.com/docs/en/manage-claude/compliance-errors>

<a id="ref-7"></a>

**[7] Microsoft｜about_Environment_Variables**

<https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.6>

<a id="ref-8"></a>

**[8] Microsoft｜Read-Host**

<https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/read-host?view=powershell-7.6>

<a id="ref-9"></a>

**[9] Microsoft｜Marshal.SecureStringToBSTR**

<https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.marshal.securestringtobstr?view=net-10.0>

<a id="ref-10"></a>

**[10] Anthropic｜Export your organization’s data（組織設定への移動のみ参照）**

<https://support.claude.com/en/articles/13346720-export-your-organization-s-data>

補足：Windowsへの受け渡しと確認基準は前回提示の収集スクリプト・設定ファイルに合わせた運用手順です。公式資料に記載された画面操作と、本案件の運用方針を区別して記載しています。
