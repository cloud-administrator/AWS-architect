# WSL 2 を Consomme モードに設定する手順書

作成日：2026年11月11日  
対象：Windows 11 22H2 以降の WSL 2 と Ubuntu  
目的：WSL 2 のネットワーク方式を Consomme に変更し、Ubuntu 側の MAC アドレスや Claude Code の動作を確認する。

> **はじめに**：この手順は MAC アドレスの永久固定や、SKYSEA の検知解消を保証するものではありません。設定はすべての WSL 2 ディストリビューションに影響します。会社の PC では情報システム管理者に確認したうえで、業務に影響のない時間に実施してください。

## 1. 事前に知っておくこと

- 対応する WSL には Consomme が含まれ、通常は別途ソフトウェアのインストールは不要です。Windows に必ず存在するとは限らず、WSL の導入と対応バージョンが必要です。
- この手順の `networkingMode=consomme` は、検証 PC の **WSL 3.0.3.0** で動作を確認しました。古い WSL では旧名称 `virtioproxy` が使われることがあります。会社の PC で認識されない場合は、自己判断で設定を重ねず、WSL のバージョンと組織の方針を確認してください。
- Microsoft の設定資料では、このネットワーク設定に Windows 11 22H2 以降の条件が付いています。Windows の版と WSL の対応状況は実機で確認してください。[Microsoft の設定資料](https://learn.microsoft.com/ja-jp/windows/wsl/wsl-config)
- WSL の再起動時には、Ubuntu のターミナル、Claude Code の WSL セッション、Linux で稼働中のプログラムが終了します。保存してから実行してください。
- 設定後は Ubuntu 側の NIC 名が `eth0` から変わることがあります。固定値を前提にしたスクリプトやアプリがある場合は動作確認してください。
- 接続不良が起きた場合に備え、設定前の状態を記録し、下記の「元に戻す方法」を確認してください。

### スクリプトで設定する場合

[Consomme設定.ps1](./Consomme設定.ps1) を一度実行すると、既存の `.wslconfig` があればバックアップを作成し、Consomme の設定を書き込んで `wsl --shutdown` を実行します。**実行中のすべての WSL セッションとサービスが停止します。** 未保存の作業を保存してから実行してください。

1. Windows の PowerShell を開きます。
2. スクリプトを置いたフォルダに移動します。下記はフォルダのパスを指定する例です。実際の保存先に書き換えてください。

   ```powershell
   Set-Location -LiteralPath 'C:\ここを実際のフォルダに変更'
   ```

3. PowerShell 7 がある場合は、次のコマンドを実行します。

   ```powershell
   pwsh.exe -NoProfile -File '.\Consomme設定.ps1'
   ```

   PowerShell 7 がない場合、Windows PowerShell 5.1 でも、スクリプトの実行が許可されていれば次を利用できます。

   ```powershell
   powershell.exe -NoProfile -File '.\Consomme設定.ps1'
   ```

4. 表示されたバックアップ先を控え、終了後に Ubuntu と Claude Code を起動します。後述の「5. 設定後に確認する」で MAC、通信、Claude Code などを確認してください。

スクリプトは不明な文字コードや競合する設定を検出した場合、変更せずに終了します。WSL のバージョン条件を満たさない場合や、組織の PowerShell 実行ポリシーで実行できない場合は管理者に確認してください。設定を戻す場合は「6. 元に戻す方法」を参照してください。

以下の「2. 現在の WSL と設定を確認する」から「4. WSL を再起動する」は、手動で設定する場合の手順です。スクリプトで設定した場合も、事前確認と「5. 設定後に確認する」は行ってください。

## 2. 現在の WSL と設定を確認する

### 2-1. WSL のバージョンを確認する

Windows の **PowerShell** を開き、次を実行します。通常は管理者として開く必要はありません。

```powershell
wsl --version
wsl --list --verbose
```

- `wsl --version` の出力に WSL のバージョンが表示されることを確認し、記録します。
- ディストリビューション一覧の `VERSION` 列で、Ubuntu が `2` であることを確認します。
- バージョンのコマンド自体が使えない、Ubuntu が WSL 1、あるいは設定の可否が不明な場合は、管理者に確認してください。勝手に WSL を更新する必要はありません。

### 2-2. 現在の MAC・IP を記録する

Ubuntu を開き、次を実行します。

```bash
ip -br link
ip -4 -br address
ip -4 route
```

表示されたインターフェース名、MAC アドレス、IPv4 アドレス、デフォルトゲートウェイを控えます。変更前は通常、`eth0` が該当します。変更後は名前が変わることがあるため、`eth0` に限定せず確認します。

### 2-3. 既存の設定ファイルを確認して保全する

PowerShell で実行します。

```powershell
Test-Path -LiteralPath "$env:USERPROFILE\.wslconfig"
```

- `True`：既存ファイルがあります。次のコマンドで日時付きバックアップを作成し、表示された保存先を控えます。
- `False`：ファイルはありません。**「設定前はファイルなし」**と控えます。バックアップは不要です。

既存ファイルがある場合だけ実行：

```powershell
$wslConfigBackup = "$env:USERPROFILE\.wslconfig.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
if (Test-Path -LiteralPath $wslConfigBackup) { throw 'バックアップ先がすでに存在します。もう一度実行してください。' }
Copy-Item -LiteralPath "$env:USERPROFILE\.wslconfig" -Destination $wslConfigBackup -ErrorAction Stop
Write-Output $wslConfigBackup
```

すでに `networkingMode` が設定されている場合は、バックアップに加えて、元の値も控えてください。変更後に他の設定が追加された可能性があるため、復元時は原則として対象行だけを元に戻します。

## 3. Consomme を設定する

### 3-1. Windows 側の設定ファイルを開く

PowerShell で次を実行します。

```powershell
notepad.exe "$env:USERPROFILE\.wslconfig"
```

ファイルが存在しない場合は、メモ帳で新規作成する旨を確認して進みます。

**設定先は Windows のユーザーフォルダ直下の `.wslconfig` です。** Ubuntu の `/etc/wsl.conf` とは別のファイルです。

### 3-2. 内容を編集する

**ファイルが新規の場合**は、次の 2 行を入力します。

```ini
[wsl2]
networkingMode=consomme
```

**既存ファイルがある場合**は、既存の `[wsl2]` の中に `networkingMode=consomme` を追加します。すでに同じ項目がある場合は、その値を変更します。既存の別の設定は残し、`[wsl2]` や `networkingMode` を重複させないでください。

例：すでにメモリ設定がある場合

```ini
[wsl2]
memory=8GB
networkingMode=consomme
```

すでに別のセクションがあり `[wsl2]` がない場合は、既存内容を残して、新たに `[wsl2]` とその設定行を追加します。別セクションの `networkingMode` もある場合など、設定の意味が分からないときは管理者に確認してください。

保存してメモ帳を閉じます。ファイル名が **`.wslconfig`** であり、`.wslconfig.txt` になっていないことを確認します。

## 4. WSL を再起動する

> 次の操作は Ubuntu だけでなく、実行中の **すべての WSL ディストリビューションと WSL 2 の仮想マシンを停止**します。作業を保存し、Claude Code や他の WSL 作業を終了してから実行してください。

PowerShell で実行：

```powershell
wsl --shutdown
```

コマンドが終了したら、Ubuntu または Claude Desktop の WSL セッションを起動します。Windows 自体の再起動は、設定反映のためには通常必要ありません。

## 5. 設定後に確認する

### 5-1. MAC と IP を確認する

Ubuntu で再度実行します。

```bash
ip -br link
ip -4 -br address
ip -4 route
```

`lo` ではない通信インターフェースの名前と MAC を確認します。検証 PC では名前が `enP...` に変わり、MAC は `00:00:00:00:01:00` でした。ただし、**この値は全環境や将来のバージョンで保証されるものではありません**。

再度 WSL を停止・起動し、同じインターフェースに相当する MAC が変化していないか比較します。再度の `wsl --shutdown` でもすべての WSL 作業が停止します。

> WSL は設定値を認識できない場合など、別の方式で起動することがあります。**WSL が起動したことや、MAC がたまたま同じことだけでは Consomme が適用されたと断定できません。** 起動時の警告、WSL バージョン、設定ファイルの場所と内容を確認し、不明な場合は管理者に調査を依頼してください。

### 5-2. インターネットと Claude Code を確認する

1. Ubuntu で次を実行し、HTTPS の応答があるか確認します。

   ```bash
   curl -I --connect-timeout 5 --max-time 15 https://www.microsoft.com
   ```

2. Claude Desktop の **Code** タブで Ubuntu の作業フォルダを開き、短い質問に回答が返ることを確認します。
3. 非機密のテスト用ファイルで、Claude Code がファイルを読んで小さな変更を行えることを確認します。変更内容を確認し、テスト後の扱いは職場の運用に従います。
4. 普段使う社内 VPN、プロキシ、Git、MCP、開発サーバー、プレビューなどを確認します。
5. SKYSEA 側で対象 NIC がどう表示・検知されるか、管理者に確認してもらいます。

Microsoft のサイトが開くだけでは、Claude への認証・通信の成功は証明できません。認証や許可リストに必要な接続先は [Anthropic のネットワーク要件](https://code.claude.com/docs/en/network-config) を確認してください。

### 5-3. 検証時に起きたこと

検証 PC の WSL 3.0.3.0 では、Consomme に変更後、外部 HTTPS は利用できましたが、Apache への IPv4 `127.0.0.1` 接続が失敗しました。すべての環境に起きるとは限りませんが、ローカルで動くツールは特に確認してください。実際の Claude Desktop による質問・回答や編集は、検証 PC では未確認です。[Claude Code 影響調査](./ClaudeCode影響調査.md)

## 6. 元に戻す方法

設定変更後に問題が起きた場合、PowerShell から再びファイルを開きます。

```powershell
notepad.exe "$env:USERPROFILE\.wslconfig"
```

- 変更前に `networkingMode` があった場合：控えておいた**元の値**に戻します。
- 変更前に `networkingMode` がなかった場合：今回追加した `networkingMode=consomme` の行だけを取り除きます。
- 今回初めて作成したファイルの場合：上記の行を取り除いた後、空の `[wsl2]` セクションが残っても構いません。ほかの設定は残します。

保存してから、実行中の WSL 作業を保存・終了し、PowerShell で次を実行します。

```powershell
wsl --shutdown
```

Ubuntu を起動し、Claude Code、通信、業務アプリが元に戻ったか確認します。元の値が不明な場合は、スクリプト実行時に表示されたバックアップ、または手順 2-3 のバックアップを参照してください。**設定前に `networkingMode` がなかった場合の既定方式は通常 NAT ですが、組織のポリシーやフォールバック動作によって異なる場合があります。**

## 7. 関連資料

- [Consomme 解説資料](./Consomme解説資料.md)
- [今回の MAC・IP 実機検証結果](./調査検証結果.md)
- [Claude Code への影響調査](./ClaudeCode影響調査.md)
- [Microsoft：WSL の詳細設定](https://learn.microsoft.com/ja-jp/windows/wsl/wsl-config)
- [Microsoft：WSL のネットワーク](https://learn.microsoft.com/ja-jp/windows/wsl/networking)
