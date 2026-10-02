# Claude Desktop / Cowork：Windows HKLM設定ガイド

調査基準日：2026年10月2日  
対象：Windows上のClaude Desktopを、通常のClaude Enterpriseアカウントで利用する構成  
設定先：`HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Claude`

## 1. HKLMで設定できる項目の一覧

### 1.1 通常のClaude Enterprise向けに公式資料で確認できた全項目

以下は、公式のEnterpriseポリシー一覧から、Coworkに適用しない専用項目を除いた**全8項目**。Coworkの直接制御だけでなく、拡張機能、ログイン、アプリ更新に関する共通設定も含む。[S01]

本資料では、通常のEnterpriseへのサインイン方式と、外部の推論基盤に接続する「Claude Desktop on third-party（以下、3P）」を区別する。3P向けの詳細なHKLM設定も公開されているが、同じレジストリパスを使うことだけでは、通常のEnterpriseでも有効とは判断できない。通常構成への適用が確認できない項目は、第1.4節で**不明**と記載し、設定コマンドから除外する。[S04]

| No. | 設定項目／レジストリの値名 | 本資料で使用するレジストリ型 | 未設定時の値・動作 | 説明 | 制御範囲・注意点 | 根拠 |
|---|---|---|---|---|---|---|
| 1 | `allowedWorkspaceFolders` | `REG_SZ`：文字列のJSON配列 | フォルダのポリシー制限なし | Coworkに接続できる作業フォルダを指定する。今回の作業範囲制限の中心となる設定 | 許可するフォルダの指定。各操作の承認方法、Windows全体のアクセス権、通信先を設定する項目ではない | [S01][S04] |
| 2 | `secureVmFeaturesEnabled` | `REG_DWORD`：`0` / `1` | `true`：有効 | `1`でDesktopからのCowork利用を許可し、`0`で無効化する | 名前にVMを含むが、WindowsのHyper-V機能をインストールする設定ではない。Coworkの利用可否の設定 | [S01][S03] |
| 3 | `isLocalDevMcpEnabled` | `REG_DWORD`：`0` / `1` | `true`：有効 | `0`でローカルMCPサーバーを無効化する。通常構成のアーキテクチャ資料では、ローカル設定およびプラグインに含まれるローカルMCPが対象 | リモートMCPを含む全外部通信の一括遮断ではない。個別サーバーを許可する一覧設定でもない | [S01][S02] |
| 4 | `isDesktopExtensionEnabled` | `REG_DWORD`：`0` / `1` | `true`：有効 | `0`でデスクトップ拡張機能を無効化する。MCPB／DXT形式の拡張サーバーの実行を止める | 拡張機能経由のアクセス経路を減らす設定。WebアクセスやすべてのMCPを止める設定ではない | [S01][S02] |
| 5 | `isDesktopExtensionDirectoryEnabled` | `REG_DWORD`：`0` / `1` | `true`：有効 | `0`で拡張機能ディレクトリへのアクセスを無効化する | ここでの「ディレクトリ」は拡張機能のカタログ。PCのフォルダやファイルへのアクセス制限ではない | [S01][S08] |
| 6 | `forceLoginOrgUUID` | `REG_SZ`：単一UUID、またはUUIDのJSON配列 | `null`：制限指定なし | 指定組織に所属するアカウントでのログインを要求する。単一UUIDではログイン時の組織も事前選択する | 複数UUIDでは、いずれかへの所属を要求し、組織は事前選択しない。組織所属の確認と、あらゆる組織切替・データ移動の禁止は別の制御 | [S01] |
| 7 | `disableAutoUpdates` | `REG_DWORD`：`0` / `1` | `false`：自動更新を無効化しない | `1`でClaude Desktopの自動更新を停止する。管理システムでアプリのバージョンを配布する場合に使用する | 停止対象はClaude Desktop自身の更新。リポジトリ、ツール、その他ソフトウェアのダウンロード禁止にはならない | [S01][S03] |
| 8 | `autoUpdaterEnforcementHours` | `REG_DWORD`：整数 `1`～`72` | `72`時間 | 準備済みの更新を適用するため、アプリを強制再起動するまでの猶予時間を指定する | 自動更新の運用に関する項目。Coworkの処理時間、ユーザー承認の有効時間、VMの稼働時間ではない | [S01][S03] |

**「全8項目」の範囲は、調査日時点の通常構成向け公式公開一覧。未公開・内部用設定まで含めた完全性は不明。** 導入先のアプリバージョンは未提示のため、実機での設定認識と動作確認を必要とする。

### 1.2 レジストリの読み方と設定時の基本

| 用語・事項 | 説明 |
|---|---|
| HKLM | `HKEY_LOCAL_MACHINE`の略称。端末単位の設定場所。今回はユーザー単位のHKCUを使用しない |
| PowerShellでの設定先 | `HKLM:\SOFTWARE\Policies\Claude`。レジストリエディター上の`HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Claude`と対応する |
| キーと値名 | `Claude`が設定を格納するキー。`allowedWorkspaceFolders`などは、その下に作成する「値名」。値名ごとの子キーは作成しない |
| `REG_DWORD` | 整数の保存形式。本資料の真偽値は`1`が有効／true、`0`が無効／false。ただし`disable...`という名前の項目では、`1`が「無効化を有効にする」の意味 |
| `REG_SZ` | 文字列の保存形式。配列は、JSON形式の文字列を1つの値として保存する。複数行文字列の`REG_MULTI_SZ`は使用しない |
| JSON配列 | 複数の値を`[ ]`で囲む形式。フォルダが1個でも配列を使用する。例：`["C:\\Users\\alice\\claude_work"]` |
| HKLMとHKCUの関係 | 通常構成の公式説明では、端末単位の設定がユーザー単位の設定より優先される。今回の値はHKLMに集約する |
| アプリ全体への影響 | ログイン・更新・拡張機能などの共通設定は、Coworkだけに閉じた設定ではない |
| Windows管理者権限 | HKLMへの書き込みには管理者権限を使用する。これは設定作業の権限であり、Coworkの日常利用を管理者として実行する指示ではない |
| ポリシーの境界 | HKLM設定はアプリの管理設定。管理者によるレジストリ改変を、この設定自身が禁止するものではない |

設定先・優先順位の根拠は[S01]、JSON文字列・値の配置形式の根拠は[S04]、書き込み方法の根拠は[M01][M03]。型の誤りを避けるため、本資料のコマンドは真偽値を`REG_DWORD`、JSONを`REG_SZ`に統一する。

### 1.3 `allowedWorkspaceFolders`の設定例と限界

`~/claude_work`は、本資料では「実際にCoworkを使用するWindowsユーザーのプロファイル配下にある`claude_work`」として扱う。要件中の`~claude_work`も同じフォルダを指すものとして整理する。

| 項目 | 今回の指定・扱い | 説明 |
|---|---|---|
| 実際のフォルダ例 | `C:\Users\alice\claude_work` | `alice`は説明用のユーザー名。導入先の実際のフォルダに置き換える |
| HKLMに保存する値 | `["C:\\Users\\alice\\claude_work"]` | 文字列のJSON配列。JSON内の`\\`は、実際のパスの`\`を表す |
| 許可リストの要素数 | 1個 | ホームフォルダ全体、ドライブ全体、Downloads、ネットワークドライブなどを追加しない |
| 事前のフォルダ準備 | 実在するローカルフォルダを用意する | HKLMの設定はフォルダの作成や、Windowsのファイルアクセス権の付与を行わない |
| 自動登録・選択の強制 | 通常構成のHKLM仕様では不明 | 接続可能な場所の制限と、そのフォルダを必ず選択させることは別。通常構成では「自動登録され、解除できない」とは扱わない |
| フォルダ内の無承認読み取り | この値では設定しない | 許可場所を指定する値であり、読み取りの承認要否を指定する値ではない |
| フォルダ外の読み取り禁止 | 接続先の制限として適用する | 通常構成で明記されているのは、Coworkにマウントできるパスの制限。全実行経路・権限昇格を含む完全な遮断までは保証しない |
| ネットワーク共有 | 許可リストに含めない | 共有フォルダを作業場所として接続させない方向の制限。SMBなどの通信自体を無効化する設定ではない |
| リンク・ジャンクション | 通常構成の詳細仕様は不明 | ローカルフォルダ内から外部の場所を指すリンクがある場合は、通常構成での実機検証が必要。3P資料のパス解決仕様を、そのまま通常構成の保証として転記しない |
| `~`や環境変数の展開 | 通常構成の推奨値では使用しない | 3P資料では`~`と一部の変数の展開が説明されているが、通常構成での対応範囲は不明。実体の絶対パスを使用する |
| 配布スクリプトの`$env:USERPROFILE` | 自動的に採用しない | 実行中のPowerShellの環境に依存する。管理者やSYSTEMで配布すると、実際の利用者とは別のプロファイルを参照するおそれがある |
| 複数利用者が共有するPC | この例の一律配布は避ける | HKLMに実体パスを1個設定するため、同じ端末の別ユーザー用パスには自動的に切り替わらない。利用者ごとのパス設計が必要 |

接続先の制限の根拠は[S01]。3Pでの拡張仕様・ネットワークドライブの扱いは[S05]、PowerShellの環境変数は[M05]。絶対パスの使用と許可リストの最小化は、上記の適用範囲を踏まえた本資料の設定方針。

### 1.4 取り違えを防ぐための参考：3P資料で確認した追加設定

以下は、要件に関連して調査した3P向けの追加項目。**通常のEnterprise向けに確認済みの8項目へ追加してよい、という意味ではない。** 説明は3Pにおける意味であり、通常構成への適用は表の判定に従う。[S04]

3P側の接続先・認証情報・推論モデル・表示装飾などは今回の対象外。以下は、その別方式に存在する全設定の転載ではなく、Coworkの権限・作業範囲・通信・拡張機能に関係する追加設定の調査結果。

#### 実行・承認・ワークスペース関連

| 設定項目 | 型／主な値 | 説明：3Pで何を制御するか | 通常のEnterpriseへの適用 | 根拠 |
|---|---|---|---|---|
| `coworkTabEnabled` | 真偽値 | Coworkの有効・無効 | 不明。通常構成の確認済み項目は`secureVmFeaturesEnabled` | [S04] |
| `builtinToolPolicy` | JSONオブジェクト。ツールごとに`ask` / `allow` | 組み込みツールの承認方針。`ask`は該当する呼び出しごとの確認 | 不明 | [S04] |
| `disabledBuiltinTools` | JSON文字列配列 | 指定した組み込みツールを禁止する。承認を求める設定ではなく、実行の拒否 | 不明 | [S04] |
| `autoModeEnabled` | 真偽値 | `false`でAuto modeの選択肢を取り除く | 不明 | [S04] |
| `disableBypassPermissionsMode` | 真偽値 | `true`でPermission bypassを禁止する | 不明 | [S04] |
| `scheduledTasksEnabled` | 真偽値 | `false`で定期実行を無効化する | 不明 | [S04] |
| `keepAwakeEnabled` | 真偽値 | アプリによるスリープ抑止の許可。定期実行そのものの禁止とは別 | 不明 | [S04] |
| `organizationInstructions` | 文字列 | 組織の指示文を与える。権限やアクセスを強制遮断する機能ではない | 不明 | [S04] |
| `requireCoworkFullVmSandbox` | 真偽値 | ツールをVM内に限定するための項目 | 不明。公式資料で非推奨指定があるため、今回の設定例には採用しない | [S04] |

`allowedWorkspaceFolders`自体は第1.1節の確認済み項目だが、次の拡張表現は3P資料で確認した仕様。通常構成の推奨コマンドでは使用しない。[S04][S05]

| 3Pでの表現 | 説明 | 通常構成での扱い |
|---|---|---|
| 配列要素の`path` | オブジェクト形式でのフォルダ指定 | 文字列配列を使用する |
| 配列要素の`mode: "ro"` / `"rw"` | 読み取り専用／読み書き可能の区別 | 対応は不明 |
| 配列要素の`isDefaultSelected: true` | 初期選択とフォルダ信頼確認の省略。ユーザーは選択を解除できる | 対応は不明。解除不能なWorkspace強制登録の根拠にはならない |
| `~`によるホーム展開 | 実行ユーザーのホームに置き換える | 対応は不明。絶対パスを採用する |

#### Web・ネットワーク関連

| 設定項目 | 型／主な値 | 説明：3Pで何を制御するか | 通常のEnterpriseへの適用 | 根拠 |
|---|---|---|---|---|
| `coworkEgressAllowedHosts` | JSON文字列配列 | ツールの接続先ホストの許可リスト。Web検索、推論、MCP通信まで一括で制御するものではない | 不明 | [S04][S07] |
| `builtinBrowserEnabled` | 真偽値 | 組み込みブラウザーの利用可否 | 不明 | [S04][S07] |
| `builtinBrowserDefaultDomainPolicy` | 文字列：`allow` / `block` | ブラウザーでClaudeが操作できるサイトの既定方針 | 不明 | [S04][S07] |
| `builtinBrowserAllowedDomains` | JSON文字列配列 | 既定方針が`block`の場合の許可サイト | 不明 | [S04][S07] |
| `builtinBrowserBlockedDomains` | JSON文字列配列 | 既定方針が`allow`の場合の禁止サイト | 不明 | [S04][S07] |
| `egressProxyUrl` | 文字列 | プロキシ経由の通信を指定する。許可ドメイン一覧そのものではない | 不明 | [S04] |
| `egressProxyPacUrl` | 文字列 | プロキシ自動構成ファイルを指定する | 不明 | [S04] |
| `coworkVmIpv6Enabled` | 真偽値 | Cowork VMのIPv6接続を制御する。Hyper-Vを有効化する項目ではない | 不明 | [S04] |

**ドメイン制限の対象経路に注意する。** 3Pでも、ツールの送信先制限、ブラウザーのサイト制限、MCP通信は同一の制御ではない。`coworkEgressAllowedHosts`だけで「すべてのWeb・外部通信を許可ドメイン以外は禁止」とは評価しない。[S04][S07]

#### MCP・プラグイン関連

| 設定項目 | 型／主な値 | 説明：3Pで何を制御するか | 通常のEnterpriseへの適用 | 根拠 |
|---|---|---|---|---|
| `managedMcpServers` | JSONオブジェクト配列 | 管理者が配布するMCPサーバーの定義 | 不明 | [S04][S06] |
| `managedMcpServers`内の`toolPolicy` | ツールごとに`blocked` / `ask` / `allow` | 管理MCPのツールを禁止／毎回承認／事前許可に固定する。独立したHKLM値名ではない | 不明 | [S06] |
| `mcpPersistentAlwaysAllowEnabled` | 真偽値 | `false`で継続的な「常に許可」を無効化する。セッション単位の許可までなくすとは限らない | 不明 | [S04][S06] |
| `mcpScheduledTaskApprovalLifetimeDays` | 整数：`0`～`3650` | 定期実行でMCP承認を再利用できる期間。`0`で継続承認の選択肢を取り除く | 不明 | [S04] |
| `allowedPluginMcpServers` | JSONオブジェクト配列 | プラグインから接続できるMCPを制限する。管理配布サーバーなどとは対象範囲が異なる | 不明 | [S04][S06] |
| `deniedPluginMcpServers` | JSONオブジェクト配列 | プラグインのリモートMCP接続先を禁止する | 不明 | [S04] |
| `orgPluginSettings` | JSONオブジェクト配列 | プラグインに含まれるMCPのツール権限を固定する | 不明 | [S04][S06] |
| `allowedPluginMarketplaces` | JSONオブジェクト配列 | 管理者が提供するプラグインマーケットプレースを指定する | 不明 | [S04][S06] |
| `userPluginMarketplacesEnabled` | 真偽値 | ユーザー独自のマーケットプレース追加・利用を制御する | **3P動作時のみ有効と明記** | [S04][S06] |
| `userPluginUploadsEnabled` | 真偽値 | ユーザーによるプラグイン追加を制御する。既存ファイルの完全な実行禁止ではない | **3P動作時のみ有効と明記** | [S04][S06] |
| `skillCreationEnabled` | 真偽値 | ユーザーによるスキル作成・アップロードを制御する。既存スキルの全無効化ではない | 不明 | [S06] |
| `isDesktopExtensionSignatureRequired` | 真偽値 | 署名のない拡張機能を拒否する | 不明 | [S04][S06] |
| `mcpToolTimeoutSec` | 整数：`60`～`3600`秒 | MCPツール呼び出しのタイムアウト。承認方式ではない | 不明 | [S04] |
| `toolSearchEnabled` | 真偽値 | MCPツールの詳細定義を必要時に取得する方式を制御する | 不明。アクセス許可を管理する設定とは別 | [S04] |

Hooksを管理者管理に限定するための、**Cowork独自のHKLM値名は確認できなかった**。プラグインの追加制限を、そのままHooks全体の管理者限定や、既存Hooksの無効化と読み替えない。[S06]

以上の追加項目について、通常のEnterpriseで「非対応」と断定しているものではない。**通常構成に適用できる公式根拠が確認できないため、不明として未設定にする**という判断。

## 2. 要件に対して採用する設定値

### 2.1 今回のHKLM設定値

以下の5項目を設定する。承認や通信の全要件を満たす構成ではなく、**通常のEnterprise向けに確認できたHKLM設定で実現可能な部分に限定した構成**。

`C:\Users\alice\claude_work`は実際の利用者のパスに置き換える。

| 設定項目 | 設定値 | 型 | 説明：この値で実現すること | 実現しないこと | 根拠 |
|---|---|---|---|---|---|
| `allowedWorkspaceFolders` | `["C:\\Users\\alice\\claude_work"]` | `REG_SZ` | 作業場所として接続可能なフォルダを、指定したローカルフォルダに限定する | Windows全体の共有アクセス禁止、全ツールの承認制御、権限昇格そのものの禁止 | [S01] |
| `secureVmFeaturesEnabled` | `1` | `REG_DWORD` | Coworkの利用を許可する | Windowsの仮想化機能のインストール、ローカル実行方式の固定 | [S01][S02][S03] |
| `isLocalDevMcpEnabled` | `0` | `REG_DWORD` | ローカルMCP経由のアクセスを無効化する | 管理者指定MCPだけを残す個別許可、リモートMCP全体の制御 | [S02] |
| `isDesktopExtensionEnabled` | `0` | `REG_DWORD` | デスクトップ拡張機能を無効化する | ブラウザーやすべての外部アクセスの禁止 | [S02] |
| `isDesktopExtensionDirectoryEnabled` | `0` | `REG_DWORD` | 拡張機能カタログへのアクセスを無効化する | PC上のファイル参照の禁止 | [S01][S08] |

**MCPについては「管理者が許可したものだけを残す」設定ではなく、ローカルMCPとデスクトップ拡張機能を無効化する設定を採用する。** 管理者が配布したものであっても、無効化対象の経路を使うものは利用できなくなる。管理者限定の細かな許可リストをHKLMだけで作成できるとは扱わない。[S02][S08]

### 2.2 残る3項目の扱い

| 設定項目 | 今回の扱い／条件付きの値 | 説明 | 設定コマンドへの採否 | 根拠 |
|---|---|---|---|---|
| `forceLoginOrgUUID` | 組織UUIDが不明のため既存設定を維持 | UUID確定後に、自社組織への所属確認のための設定を検討する。架空のUUIDを配布するとログインを妨げるおそれがある | 今回は変更しない | [S01] |
| `disableAutoUpdates` | 更新主体が不明のため既存設定を維持。MDMで更新を配布する運用なら`1` | 自動ダウンロード停止の対象はClaude Desktopの更新のみ。代わりの更新配布が決まっていない状態で、停止を推奨しない | 今回は変更しない | [S03] |
| `autoUpdaterEnforcementHours` | 既存設定を維持。未設定時は`72` | 更新の再起動猶予は今回のアクセス制御要件に直接関係しない | 今回は変更しない | [S01] |

### 2.3 要件との対応表

「一部対応」は、その要件全体の達成を意味しない。「不明・未設定」は、通常構成向けに有効なHKLM値を確認できず、今回のコマンドでは実現しないことを示す。HKLM以外の実装方法は記載しない。

| 要件 | 判定 | 採用する値・対応 | 説明 |
|---|---|---|---|
| WindowsのCoworkを利用する | 対応 | `secureVmFeaturesEnabled=1` | アプリ側でCoworkを許可する。組織側の有効化とWindows側の動作条件が整っていることが前提 |
| `claude_work`だけを作業場所として許可する | 接続先の制限として対応 | `allowedWorkspaceFolders`に対象パスだけを格納 | 許可する場所を限定する。指定場所を自動選択させ、解除を禁止する制御までは含まない |
| `claude_work`以外をWorkspaceに登録させない | 一部対応 | 同上 | 接続可能なパスの制限。親フォルダや別ドライブを許可リストに追加しない |
| `claude_work`内だけでファイルを読み書きする | 一部対応 | 同上。ローカルMCPと拡張機能も無効化 | 通常の接続フォルダに対するアクセス範囲を限定する。OS全体の全経路遮断とは区別する |
| Windows共有フォルダの読み書きを禁止する | 一部対応 | 共有パス・ネットワークドライブを許可リストに含めない | 作業場所として共有フォルダを接続させない方向の制限。共有通信自体の禁止や、すべての迂回経路の遮断は不明 |
| ローカルMCPや拡張機能をユーザーに自由に使わせない | 無効化として対応 | MCPと拡張機能の3項目を`0` | 管理者管理のMCPだけを残す構成ではなく、対象経路の無効化 |
| MCP全体を管理者管理に限定する | 一部対応 | 上記のローカル経路だけを無効化 | リモートMCPを含む全体の管理者限定は、今回のHKLM設定では確認できない |
| Hooksを管理者管理に限定する | 不明・未設定 | なし | Cowork独自の該当HKLM値を確認できない |
| ファイル作成・変更・削除を毎回承認必須にする | 不明・未設定 | なし | 通常構成向けのHKLM承認ポリシーを確認できない。フォルダ許可と操作承認は別 |
| 許可フォルダ内の読み取りだけを承認不要にする | 不明・未設定 | なし | `allowedWorkspaceFolders`だけでは承認方式を指定できない |
| PowerShellなどのコマンド実行を毎回承認必須にする | 不明・未設定 | なし | 通常構成向けのHKLM項目を確認できない |
| Webアクセス・MCP呼び出しを毎回承認必須にする | 不明・未設定 | なし | ローカル経路を無効化することと、許可した呼び出しで毎回承認を要求することは別 |
| Auto mode／Permission bypassを禁止する | 不明・未設定 | なし | 該当名の設定は3P資料で確認したが、通常構成への適用は不明 |
| Web・インターネットを管理者許可ドメインだけに限定する | 不明・未設定 | なし | 通常構成向けのHKLMドメイン許可リストを確認できない |
| 権限昇格によるフォルダ外アクセスを禁止する | 不明・未設定 | なし | アプリの接続先制限は、Windowsの権限昇格禁止の設定ではない |
| リポジトリ・ソフトウェアのダウンロードを制御する | 不明・未設定 | なし | `disableAutoUpdates`で制御できるのはClaude Desktop自身の自動更新のみ |
| ローカルネットワーク経由の他PC・他フォルダへのアクセスを禁止する | 不明・未設定 | なし | 今回のHKLM値は端末全体のネットワークフィルターではない |
| Hyper-Vを使用する | アプリの利用許可のみ対応 | `secureVmFeaturesEnabled=1` | ローカルセッションのシェル実行ではWindowsのHyper-Vを使用する。必要なWindows機能の有効化自体はHKLMポリシーの対象外 |

対応判定は、第1節で示した公式設定の範囲と、[S02][S03][S04][S06]に基づく本資料の評価。**上表の「不明・未設定」を、設定済み・禁止済みとして受入判定しない。**

### 2.4 Hyper-Vと実行場所に関する補足

| 確認事項 | 説明 | 根拠 |
|---|---|---|
| ローカルセッションのコマンド実行 | シェルや生成したコードは、Hyper-Vで隔離されたLinux VM内で実行する | [S02] |
| ローカルセッションのファイル操作など | 会話処理、接続フォルダの読み書き、Web取得、ローカルMCPなどはPC側でも動作する。全機能がVM内で動く構成ではない | [S02] |
| Windows側の必要機能 | 公式Windows展開手順では`VirtualMachinePlatform`が必要。有効化後は端末の再起動を必要とする | [S03] |
| `secureVmFeaturesEnabled=1`の意味 | Coworkの利用許可。Windows機能を有効化したことの代わりにはならない | [S01][S03] |
| Desktop利用とローカル実行の違い | 公式資料ではクラウド実行も説明されている。Desktopアプリを使っていることだけで、ローカル実行とは断定しない | [S02] |
| 今回の前提 | Hyper-Vを使用するローカルセッションとして導入するものとする。HKLMだけでローカル実行方式を強制する設定は確認できない | 本資料の前提・調査結果 |

### 2.5 適用後の確認項目

以下は受入テストの提案。レジストリに値を保存できたことだけをもって、製品がその値を認識し、すべての要件を満たしたとは判断しない。

| 確認項目 | 確認内容・判定の考え方 |
|---|---|
| 値と型 | 第2.1節の5項目が、指定したHKLMパスに指定した型で保存されている |
| 利用者のパス | 管理者やSYSTEMではなく、実際の利用者の`claude_work`を指している |
| 許可フォルダ | 利用者が対象フォルダをCoworkの作業場所として使用できる |
| 許可していない場所 | ホーム全体、Downloads、別ドライブ、共有ドライブなどを作業場所として追加できないことを確認する |
| 拡張機能・ローカルMCP | 再起動後に、無効化対象の拡張機能とローカルMCPが利用できないことを確認する。設定前から導入済みのものも対象にする |
| 既存セッション | 設定前から開いていたセッションだけで判断しない。アプリを完全終了し、起動し直して新しいセッションで確認する |
| リンク経由の境界 | 作業フォルダ内に外部を指すリンクなどがある環境では、通常構成での動作を別途検証する。不明なまま完全遮断と判定しない |
| 要件の取りこぼし | 毎回承認、ドメイン限定、権限昇格禁止、全MCP管理者限定などを、今回の5項目の効果として記録しない |

### 2.6 公式参照資料

参照先はAnthropic／Claudeの公式資料とMicrosoft Learnのみ。3P資料は別の展開方式であることを明示した箇所に限って使用する。検索結果や非公式記事を根拠にはしていない。

| ID | 公式資料 | 主な確認内容 |
|---|---|---|
| S01 | [Enterprise configuration for Claude Desktop][S01] | 通常のEnterprise向け設定一覧、HKLMパス、優先順位 |
| S02 | [Claude Cowork architecture overview][S02] | ローカル／クラウドの実行場所、Hyper-V、ローカルMCP・拡張機能の無効化対象 |
| S03 | [Deploy Claude Desktop for Windows][S03] | Windows仮想化機能の前提、インストール・更新の運用 |
| S04 | [Configuration reference — Claude Desktop on 3P][S04] | 3P向け追加設定、型、適用範囲、非推奨設定 |
| S05 | [Desktop and filesystem access — Claude Desktop on 3P][S05] | 3Pのフォルダ指定、初期選択、読み取り専用、ネットワークドライブ |
| S06 | [MCP, plugins, skills, and hooks — Claude Desktop on 3P][S06] | 3Pの管理MCP、プラグイン、Hooksの管理範囲 |
| S07 | [Web tools — Claude Desktop on 3P][S07] | 3PのWeb機能・通信経路 |
| S08 | [Enabling and using the desktop extension allowlist][S08] | デスクトップ拡張機能の許可リストと端末ポリシーの関係 |
| M01 | [New-ItemProperty — Microsoft Learn][M01] | 値の作成、型指定、既存値の更新 |
| M02 | [New-Item — Microsoft Learn][M02] | 既存レジストリキーに対する`-Force`の注意 |
| M03 | [reg add — Microsoft Learn][M03] | キー・値の追加、`/f`、64ビットレジストリビュー |
| M04 | [ConvertTo-Json — Microsoft Learn][M04] | 配列をJSON文字列に変換する方法 |
| M05 | [about_Environment_Variables — Microsoft Learn][M05] | 実行プロセスの環境変数 |

[S01]: https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop
[S02]: https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview
[S03]: https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows
[S04]: https://claude.com/docs/third-party/claude-desktop/configuration
[S05]: https://claude.com/docs/third-party/claude-desktop/local-access
[S06]: https://claude.com/docs/third-party/claude-desktop/extensions
[S07]: https://claude.com/docs/third-party/claude-desktop/web-tools
[S08]: https://support.claude.com/en/articles/12592343-enabling-and-using-the-desktop-extension-allowlist
[M01]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-itemproperty?view=powershell-7.5
[M02]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item?view=powershell-7.5
[M03]: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-add
[M04]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-json?view=powershell-7.5
[M05]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.5

## 3. PowerShellコマンド

### 3.1 実行前の条件

| 条件 | 内容 |
|---|---|
| 実行環境 | Windows上の64ビットPowerShellを「管理者として実行」する |
| 置換する値 | `C:\Users\alice\claude_work`を実際の利用者のフォルダに置き換える |
| フォルダの存在 | 対象フォルダはあらかじめ用意する。下の設定コマンドでは作成しない |
| 対象構成 | 通常のClaude Enterprise。3P向け追加項目は設定しない |
| 変更範囲 | 第2.1節の5項目のみ。組織UUID、更新設定、その他の既存値を消去しない |
| 途中エラー | 一括で成功・失敗が確定する処理ではない。途中でエラーが発生した場合は、値を確認し、適用完了と判断しない |
| 反映確認 | 作業を保存してClaude Desktopを完全終了し、再起動する。単にウィンドウを閉じるだけで済ませない |
| 実行確認の範囲 | 以下は公式の項目・PowerShell構文に基づく設定例。導入先のWindows／Claude Desktopでの実行検証は未実施 |

既存のレジストリキーへ無条件に`New-Item -Force`を実行すると、Microsoftの説明ではそのキーの既存プロパティ・値を消去する動作となる。そのため、通常版ではキーが存在しない場合だけ作成し、個々の値は`New-ItemProperty -Force`で更新する。[M01][M02]

`-Force`や`reg.exe`の`/f`は、**管理者によるレジストリ設定操作**のオプション。Coworkの操作承認を自動許可する設定ではない。[M01][M03]

### 3.2 通常版：パス確認を含む設定コマンド

利用者のパスは1か所で指定する。指定フォルダが存在しない場合は、レジストリを変更する前に停止する。JSONは`ConvertTo-Json`で生成し、バックスラッシュの手動エスケープを不要にする。[M04]

```powershell
$ErrorActionPreference = 'Stop'
$Key = 'HKLM:\SOFTWARE\Policies\Claude'
$Workspace = 'C:\Users\alice\claude_work'  # 実際の利用者のパスに置換

if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) { throw "作業フォルダが存在しない: $Workspace" }
if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force | Out-Null }

New-ItemProperty -Path $Key -Name 'allowedWorkspaceFolders' -PropertyType String -Value (ConvertTo-Json -InputObject @($Workspace) -Compress) -Force | Out-Null
New-ItemProperty -Path $Key -Name 'secureVmFeaturesEnabled' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $Key -Name 'isLocalDevMcpEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -Path $Key -Name 'isDesktopExtensionEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -Path $Key -Name 'isDesktopExtensionDirectoryEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
```

### 3.3 簡易版：変数・分岐・ループを使わないコマンド

通常版と設定結果は同じ。**通常版か簡易版のどちらか一方を実行する。** 簡易版はフォルダの存在確認を省略するため、パスの置換と実在確認を事前に行う。

先頭の`reg.exe add`でCoworkの値を設定すると同時に、キーが存在しなければ作成する。JSONの値はPowerShellの文字列として渡し、ネイティブコマンドにJSONを渡す際の引用符の問題を避ける。[M01][M03]

```powershell
reg.exe add 'HKLM\SOFTWARE\Policies\Claude' /v secureVmFeaturesEnabled /t REG_DWORD /d 1 /f /reg:64
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'allowedWorkspaceFolders' -PropertyType String -Value '["C:\\Users\\alice\\claude_work"]' -Force
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'isLocalDevMcpEnabled' -PropertyType DWord -Value 0 -Force
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'isDesktopExtensionEnabled' -PropertyType DWord -Value 0 -Force
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Claude' -Name 'isDesktopExtensionDirectoryEnabled' -PropertyType DWord -Value 0 -Force
```

### 3.4 保存された値と型の確認

次のコマンドはレジストリに保存された値と型を表示する。**製品での有効性や、未設定とした要件の達成を証明するコマンドではない。** アプリ再起動後、第2.5節の動作確認も行う。

```powershell
reg.exe query 'HKLM\SOFTWARE\Policies\Claude' /reg:64
```
