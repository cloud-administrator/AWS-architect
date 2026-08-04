# SKYSEAによるChatGPT／Codex導入方式 設計・差分精査資料【完成版】

- 文書版: 2.0
- 精査日: 2026-08-04
- 対象: Windows、Active Directory、SKYSEA Client View、20名以上
- 前提: Codexクラウドポリシーは作成済み

---

## 1. 結論

完成版は、添付資料で提案された「1つの対象CSV＋2つのSKYSEAジョブ」という骨格を採用します。そのうえで、一次情報と実装上の安全性を再確認し、次を修正しました。

```text
中央の対象CSV
  └─ SYSTEMジョブだけが使用
       端末名 → AD SID → ProfileList → 既存プロファイル
       CodexフルパッケージをACL保護して配置
       sandbox setup --elevated
       対象SID専用のAuthorizedTarget.jsonを作成

USERジョブ
  └─ 全対象CSVを持たない
       保護されたAuthorizedTarget.jsonと現在SIDを照合
       対象本人だけに新ChatGPTアプリを導入
```

運用者の定常作業は、`targets.csv`の編集と2ジョブの順次実行です。内部の安全確認はスクリプトへ閉じ込めています。

---

## 2. 添付資料の確認結果

### 2.1 採用した内容

添付された方式解説・手順書には、次の妥当な設計が含まれていました。

- 1つのCSVで20名以上を管理する
- 1台につき1対象ユーザーとする
- SYSTEMジョブとログオンユーザージョブを分離する
- `Domain\SamAccountName`をSIDへ変換する
- SIDの`ProfileList`から正式なプロファイルを取得する
- `C:\Users`を全走査しない
- 対象ユーザーをログオフしてsandbox setupを実行する
- 段階配布を行う
- 旧sandboxキーやプロファイル上書きを検査する
- `.sandbox-secrets`を収集しない

これらは完成版でも維持しています。

### 2.2 添付範囲では検証できなかった内容

添付DOCXと手順書には、完全パッケージ、PowerShell／CMD、画像、固定ハッシュ、ZIP展開試験などが完了済みと記載されています。しかし、今回添付された実体は、方式解説MD、手順書MD、回答DOCXの3点でした。記載されたZIP、スクリプト、画像、`SHA256SUMS.txt`は添付されていないため、それらの実装とハッシュは独立検証できませんでした。

完成版では、検証可能なスクリプト一式を改めて作成し、`STATIC_VALIDATION.txt`と`SHA256SUMS.csv`を同梱します。

---

## 3. 相違点と最終判断

| 論点 | 添付資料／以前の資料 | 完成版の判断 |
|---|---|---|
| 配布単位 | 1 CSV＋2ジョブ | **採用** |
| CSVの`ProfilePath` | 任意列として保持 | **廃止**。SIDのProfileListからのみ取得 |
| USERジョブの対象表 | 端末内承認表を使う案と、全CSVを再読込する案が混在 | **SYSTEMが作る対象SID専用JSONだけを使用** |
| SYSTEM実行主体 | 管理者／SYSTEMという表現 | **LocalSystem SID `S-1-5-18`に限定** |
| Codex CLI取得 | 各端末で`install.ps1`から取得する案 | **準備端末で正確なフルアーカイブを取得・検証し媒体へ同梱** |
| Codex配置 | ProgramDataへ1コピー | **採用**。ただしフルパッケージをACL保護 |
| CLIのユーザーPATH | 不要 | **不要**。管理用ツールとしてのみ配置 |
| ChatGPT製品ID | `9PLM9XGG6VKS` | **新アプリ用として正しい** |
| 旧製品ID | 他資料に`9NT1R1C2HH7J` | **旧アプリ系。完成版では使用しない** |
| WinGet実行主体 | ログオンユーザー | **必須**。SYSTEMはMicrosoft非サポート |
| Codex版`0.146.0` | 固定版 | **2026-08-04時点の承認スナップショット**。永続固定ではない |
| config検証 | 旧キー・active profileを検出 | **採用し、全プロファイル配下の非elevated設定を安全側で停止** |
| setup検証 | configまたはmarker | **両方を必須** |
| SKYSEA画面 | 具体名を断定 | 基本経路は示すが、**版・Edition差を明示** |

---

## 4. ChatGPT製品IDの相違をどう解決したか

OpenAIの新しいエンタープライズ展開資料は、Chat、Work、Codexを含む新しいChatGPT Windowsアプリについて次の製品IDを示しています。

```text
9PLM9XGG6VKS
```

一方、以前からあるOpenAI Windowsアプリのヘルプには次が残っています。

```text
9NT1R1C2HH7J
```

OpenAIの移行資料では、新アプリと以前のアプリが併存し、以前のアプリが`ChatGPT Classic`として表示される場合があると説明されています。したがって、これは同一製品IDの単純な誤記ではなく、新旧アプリの資料が並存している状態です。

今回の目的はCodexを含む新しいChatGPTデスクトップアプリなので、完成版は`9PLM9XGG6VKS`に固定します。USERスクリプトはインストール前に`winget show --source msstore --exact`を実行します。

---

## 5. なぜSYSTEMジョブとUSERジョブを分けるのか

### 5.1 Codex sandbox setup

OpenAI Codex PR #24831は、管理者またはIT配布スクリプトが対象ユーザーに代わって、事前に`elevated` sandboxを構成する用途として追加されました。

```powershell
codex sandbox setup --elevated `
  --user "DOMAIN\user" `
  --codex-home "C:\Users\user\.codex"
```

`--elevated`は「要求するsandbox実装」を指定する引数であり、プロセスが管理者である証明ではありません。呼び出し側は実際に昇格済みである必要があります。SKYSEAのLocalSystem実行は、この管理配布用途に適合します。

完成版は、単なるAdministratorsグループ所属ではなく、実行SIDが`S-1-5-18`であることを強制します。これにより、保存したドメイン管理者資格情報や、人が対話的に起動した管理者PowerShellへ処理を広げません。

### 5.2 ChatGPTアプリとwinget

WinGetはApp Installerとしてユーザーへ登録されるパッケージアプリです。MicrosoftはWinGet CLIをLocalSystemコンテキストでサポートしないと明記しています。

したがって、1本のSYSTEMスクリプトですべてを行う設計は不適切です。ユーザートークンの複製、セッションへの注入、資格情報保存、SYSTEMからのAppX登録は採用しません。

権限境界どおりに分けることで、各ジョブの責務が明確になります。

| ジョブ | 必要な権限 | 変更対象 |
|---|---|---|
| SYSTEM | LocalSystem | sandbox用ローカル構成、対象プロファイルのCodex設定、保護状態 |
| USER | 対象ユーザー本人 | そのユーザーのStoreアプリ登録 |

---

## 6. 対象者をどう狙い撃ちするか

ユーザー名と端末名だけでは、同名アカウントの再作成や古いプロファイルを区別できません。完成版は次の全条件を照合します。

```text
CSVのComputerName
  = 現在のCOMPUTERNAME

CSVのDomain\SamAccountName
  → 現在ADが返すSID

SID
  = ProfileListキー名
  = Win32_UserProfile.SID

ProfileList.ProfileImagePath
  = Win32_UserProfile.LocalPath
  = 実在するC:\Users配下のプロファイル

プロファイル
  + NTUSER.DATが存在
  + 特殊／一時／必須／破損でない
  + SYSTEMジョブ時に未ロード
  + 再解析ポイントでない
```

### 6.1 退職者プロファイル

退職者の`C:\Users\old-user`が残っていても、CSVで指定した現行ADアカウントのSIDと一致しないため選択されません。

### 6.2 同名再作成アカウント

ADで同じ`SamAccountName`を作り直すとSIDが変わります。旧SIDのProfileListを新アカウントへ流用せず、対応する現行プロファイルがなければ停止します。

### 6.3 プロファイル名の変形

`C:\Users\tanaka-tarou.000`等でも、ProfileListがそのパスを現行SIDへ正式に割り当てていれば自動取得できます。CSVへパスを手入力する必要がありません。

---

## 7. `ProfilePath`列を廃止した理由

添付資料は`ProfilePath`を原則空欄としていました。この考え方は安全ですが、空欄運用を標準とするなら列自体を残すメリットが小さく、次の人的ミスを増やします。

- 古いフォルダー名の転記
- `user`と`user.000`の取り違え
- 退職者フォルダーの指定
- CSVとProfileListの不整合対応

完成版は4列に限定し、プロファイルは常にSIDから解決します。特殊なプロファイルであっても、正式にProfileListへ登録されていれば処理できます。ProfileListとCIMが一致しなければ自動処理を停止します。

---

## 8. なぜUSER媒体へ全対象CSVを入れないのか

全対象者CSVをUSERジョブへ含めると、各端末のユーザーセッションへ他端末・他ユーザーの一覧を配布することになります。また、SYSTEMジョブの成功前でもCSVだけを根拠にアプリを導入できてしまいます。

完成版では、SYSTEMジョブ成功後に次を作ります。

```text
C:\ProgramData\OpenAI\CodexDeployment\State\AuthorizedTarget.json
```

内容は、その端末の1ユーザーだけです。

- 端末名
- 対象SID
- 正式なプロファイル
- CODEX_HOME
- config／markerパス
- 承認Codex版
- 作成日時

ACLは次に限定します。

- SYSTEM: フルコントロール
- ローカルAdministrators: フルコントロール
- 対象SID: 読み取り・実行

USERジョブはこのファイルを作成・変更できず、別ユーザーは読み取れません。該当端末に有効なCSV行があるSYSTEMジョブを再実行すると、管理領域のACLを最初に再保護し、以前の対象SIDの読み取り権限を外した後、旧状態を失効させます。対象外化だけを行う場合は、手順書第17.2節の承認状態削除を実行します。

---

## 9. Codex CLIは「ユーザーごとにインストール」しない

ユーザーの認識どおり、`codex sandbox setup`コマンドを実行するためのCodex CLIとWindows helperは必要です。しかし、ChatGPTアプリ利用者全員のPATHへCLIを通常インストールする必要はありません。

完成版では、OpenAI公式のWindows**フルパッケージ**を次へ配置します。

```text
C:\ProgramData\OpenAI\CodexDeployment\Tools\<version>-<architecture>
```

- SYSTEM／Administratorsだけが書き込み・実行可能
- ユーザーPATHへ追加しない
- `codex.exe`だけでなくhelperとresourceを一式保持
- バージョンとハッシュを記録
- 修復・再プロビジョニングに使用可能

### 9.1 なぜ`codex.exe`だけではいけないか

Windowsのelevated sandbox setupは同梱の`codex-windows-sandbox-setup.exe`等を使用します。単体EXEだけを抜き出すと、helper探索やバージョン整合性を壊す可能性があります。

### 9.2 なぜ各端末で`install.ps1`を実行しないか

各対象端末がインターネットからインストーラーを取得・実行する設計は、次を増やします。

- 端末ごとのネットワーク差
- SYSTEMプロキシ差
- 実行時点による版の変化
- ダウンロード途中の障害
- TLSインスペクションの影響
- 監査対象の拡大

完成版は、管理された準備端末で正確な版のフルアーカイブを1回取得し、固定SHA-256とOpenAI公開ハッシュを照合した後、SKYSEA媒体へ同梱します。対象端末のSYSTEMジョブでは外部スクリプトをダウンロード・実行しません。

---

## 10. Codex版`0.146.0`の扱い

2026-08-04時点でOpenAIのlatest release channelは`0.146.0`を示し、公式のWindowsフルパッケージSHA-256は次です。

| Architecture | Package | SHA-256 |
|---|---|---|
| x64 | `codex-package-x86_64-pc-windows-msvc.tar.gz` | `a945559cc0da3437c022d53e5f601f9e8c95980d717c9aad82997e4582ecd55e` |
| Arm64 | `codex-package-aarch64-pc-windows-msvc.tar.gz` | `ddb0971b3eeed04519e2be8dedbfeb649a33cdac99265d8058c5eb73cf1afd8e` |

これは今回の承認スナップショットです。アプリ側のsandbox setup versionが更新される可能性があるため、永久に固定しません。

更新時は、公式release channel、フルパッケージ名、SHA-256、現行ChatGPTアプリとの互換性をパイロットで確認し、SYSTEM媒体を再作成します。

---

## 11. config.tomlを事前・事後検証する理由

PR #24831のレビューでは、管理用setupがトップレベルに`elevated`を書いて成功を返しても、既存の旧キーやアクティブプロファイル設定が優先され、実際には別のsandbox実装が使われ得ることが報告されています。

完成版は次を自動削除しません。

- `experimental_windows_sandbox`
- `elevated_windows_sandbox`
- `enable_experimental_windows_sandbox`
- プロファイル配下の`windows.sandbox = "unelevated"`

競合を検出すると終了コード`40`で停止し、人が設定の意図を確認します。

setup後は、次の両方を確認します。

1. トップレベル`[windows] sandbox = "elevated"`
2. `.codex\.sandbox\setup_marker.json`

さらに、プロファイル配下に`elevated`以外の設定が残っていないことを確認します。

---

## 12. セキュリティ制御一覧

| リスク | 完成版の制御 |
|---|---|
| SKYSEAの対象選択ミス | CSVの端末名が完全一致しなければ無変更で停止 |
| 同一端末に複数対象 | `Enabled=1`が複数なら停止 |
| 退職者プロファイル | AD SIDとProfileListが一致する現行プロファイルだけを使用 |
| 同名再作成アカウント | SID変更を検出し旧プロファイルを使用しない |
| パス転記ミス | `ProfilePath`列を廃止 |
| ジャンクション攻撃 | 対象プロファイル、CODEX_HOME、設定、媒体の再解析ポイントを拒否 |
| 対象ユーザーがログオン中 | Profile Loaded／HKEY_USERSを検査して停止 |
| 管理者資格情報の横展開 | SYSTEMジョブはLocalSystemだけを許可 |
| Codex媒体の破損 | 公式アーカイブhash、ファイルmanifest、コピー後hashを検証 |
| DLL／resourceの追加 | manifestにないファイルを拒否 |
| CLI差し替え | ProgramDataの管理者限定ACL |
| 別ユーザーへのアプリ導入 | SYSTEM承認SIDと現在SIDを照合 |
| USER媒体への対象者一覧露出 | USER媒体にCSVを含めない |
| SYSTEMからwinget | ユーザージョブへ分離し、SYSTEM／session 0を拒否 |
| config上書き | 旧キー・非elevatedプロファイル設定を検出して停止 |
| setup成功の誤判定 | configとmarkerの両方を検証 |
| 秘密情報の収集 | `.sandbox-secrets`を読まない・ログ出力しない |

---

## 13. オーバーエンジニアリングを避ける判断

採用しなかった方式:

| 方式 | 不採用理由 |
|---|---|
| 1人ごとのSKYSEAパック | 20名以上で転記・修正・監査が非効率 |
| `C:\Users`全走査 | 退職者、保守アカウント、一時プロファイルを誤対象にする |
| SYSTEMからユーザーになりすます | トークン、資格情報、セッション管理が複雑 |
| 全ユーザーAppXプロビジョニング | 対象者限定要件に反する |
| Codex CLIを全ユーザーPATHへ追加 | 不要な複製・更新・PATH競合を増やす |
| 旧configキーを自動削除 | 利用者／管理者の意図を破壊する可能性 |
| 端末ごとにオンラインインストーラー実行 | 再現性と監査性が下がる |
| 独自サービスや常駐エージェント | SKYSEAの既存機能で足り、保守対象を増やす |

スクリプト内部の検査項目は多いものの、実行担当者の手順は次の4点です。

1. `targets.csv`を更新
2. 1回だけ媒体作成
3. 対象をサインアウトしてSYSTEMジョブ
4. 対象本人をログオンしてUSERジョブ

---

## 14. 残るリスク

### 14.1 SKYSEA版差

公開資料では基本画面とSYSTEMチェックを確認できますが、ログオンユーザー実行の名称・挙動は導入版で確認が必要です。完成版のUSERスクリプトは実行SIDとSessionIdを検査し、誤ったコンテキストなら変更せず停止します。

### 14.2 GPO／EDR差

LocalSystemであっても、組織ポリシーがsandboxに必要なローカルアカウント、Firewall、ログオン権利、helperを禁止すれば失敗します。スクリプトで制御を回避せず、パイロットの具体的なブロックログを基に最小例外を審査します。

### 14.3 アプリとCLIの更新差

ChatGPTアプリはStore経由で更新され得ます。アプリ側のsandbox setup versionが変わると、以前のmarkerを再構成する必要があります。UAC再表示、marker不整合、`sandbox.log`のsetup refreshエラーを監視します。

### 14.4 ネットワーク／プロキシ差

sandboxのオフライン・オンライン境界はプロキシやローカルバインド設定の影響を受けます。実運用と同じネットワーク、VPN、プロキシ条件でパイロットします。

### 14.5 実機未検証

本成果物はWindows／AD／SKYSEAの実環境で実行していません。文字コード、改行、PowerShellの字句構造、固定値、ファイル参照、CSV、CMDラッパー、媒体作成ロジックを静的検査しています。一方、Windows PowerShell AST／実行時検証、AD、SKYSEA、WinGet、Store、Codex helperの統合試験は未実施です。組織固有のGPO、EDR、SKYSEA設定、Store制御はパイロットで確認する必要があります。

---

## 15. 変更管理で記録する項目

| 項目 | 記録内容 |
|---|---|
| 対象表 | `targets.csv`の版とSHA-256 |
| 対象グループ | SKYSEAグループ名、端末名一覧、件数 |
| SYSTEM媒体 | ZIP名、SHA-256、Codex版、architecture |
| USER媒体 | ZIP名、SHA-256、製品ID |
| Codex公式archive | package名、公式SHA-256 |
| 配布結果 | 端末ごとの日時、ジョブ、終了コード |
| パイロット | UAC、whoami、marker、config、アプリ起動 |
| 例外 | GPO、EDR、Firewall、Storeの変更内容 |
| 更新 | 新旧Codex版、再プロビジョニング日 |

パスワード、`.sandbox-secrets`、sandboxユーザーの秘密情報は記録しません。

---

## 16. 成果物検証資料

- `STATIC_VALIDATION.txt`: 静的検査項目、合否、未検証範囲
- `SHA256SUMS.csv`: 配布元一式のSHA-256とファイルサイズ

`targets.csv`は運用時に編集するため、確定後のSHA-256を変更管理票へ別途記録します。SKYSEA登録用SYSTEM／USER媒体は準備スクリプトが作る`SKYSEA_MEDIA_SHA256.csv`で管理します。

---

## 17. 参照資料

1. OpenAI, Deploy the Windows app  
   https://learn.chatgpt.com/docs/enterprise/windows-deployment
2. OpenAI, Moving to the new ChatGPT desktop app  
   https://help.openai.com/en/articles/20001276-moving-to-the-new-chatgpt-desktop-app
3. OpenAI, Using the ChatGPT Windows app（旧アプリ資料）  
   https://help.openai.com/en/articles/9982051
4. OpenAI, Windows sandbox  
   https://learn.chatgpt.com/docs/windows/windows-sandbox
5. OpenAI Codex PR #24831  
   https://github.com/openai/codex/pull/24831
6. OpenAI Codex release channel  
   https://releases.openai.com/codex/channels/latest
7. Microsoft, WinGet troubleshooting — System Context  
   https://learn.microsoft.com/windows/package-manager/winget/troubleshooting
8. SKYSEA Client View, ソフトウェア配布  
   https://www.skyseaclientview.net/function/res/
