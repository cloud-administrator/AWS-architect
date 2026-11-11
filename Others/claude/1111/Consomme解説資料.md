# Consomme 解説資料

作成日：2026年11月11日  
対象：Windows 上で WSL 2 と Ubuntu、Claude Code を利用する方

## 1. Consomme とは

**Consomme（コンソメ）は、WSL 2 の Ubuntu などが Windows を経由してネットワーク通信するための方式です。**

Ubuntu 側には仮想ネットワークアダプターが見えます。Ubuntu からの通信を Windows 側の Consomme が受け取り、Windows の通常の通信機能を使って接続先に中継します。専門的には、OpenVMM の「ユーザーモード NAT」と呼ばれます。

```text
WSL 2 の Ubuntu
  └─ Claude Code や Git など
          │
          ▼
   仮想ネットワークアダプター
          │
          ▼
   Windows 側の Consomme が通信を中継
          │
          ▼
   インターネット・社内ネットワークなど
```

Consomme を使っても、Windows のファイアウォールや VPN の経路などの影響を受けます。ネットワークを無条件に通過させる機能ではありません。[Microsoft：WSL の Consomme の仕組み](https://github.com/microsoft/WSL/blob/3.0.3/doc/docs/technical-documentation/localhost.md)

## 2. Windows の標準機能？ それとも第三者の OSS？

**Microsoft が公開する OpenVMM プロジェクトのオープンソース技術で、対応する WSL から利用できるネットワーク方式です。**

- OpenVMM は Microsoft が GitHub で公開しているオープンソースプロジェクトで、Consomme はその一部です。外部からの貢献も受け付けています。
- Microsoft が WSL のネットワーク方式として利用できるようにしています。対応する WSL が導入されていれば、Consomme だけを別途ダウンロード・インストールする必要は通常ありません。
- **すべての Windows に最初から入っていて使える、という意味ではありません。** WSL そのものの導入、WSL のバージョン、Windows のバージョン、組織の設定などが関係します。
- 一般的な WSL の既定ネットワーク方式は **NAT** です。対応バージョンでは NAT の構成に失敗した場合に Consomme へ自動的に切り替わることもあります。
- Consomme は以前 **VirtioProxy** と呼ばれていました。古い記事や WSL のバージョンでは、その名前が登場します。

したがって、「出所不明の第三者製ソフトを別途インストールする」というものではなく、**Microsoft が公開する OSS を Microsoft の WSL が利用する仕組み**と考えると分かりやすいです。OSS はソースコードが公開され、外部の人も条件に従って参照・利用・貢献できるソフトウェアです。

資料：[Microsoft OpenVMM](https://github.com/microsoft/openvmm)／[Microsoft の WSL 設定一覧](https://learn.microsoft.com/ja-jp/windows/wsl/wsl-config)

## 3. 通常の NAT モードとの違い

通常の NAT と Consomme は、どちらも Ubuntu から外部への通信を中継します。違いは、**Windows 側で通信を扱う仕組み**です。Consomme も広い意味では NAT の一種です。

| 観点 | 通常の NAT モード | Consomme モード |
| --- | --- | --- |
| 通信の中継 | Windows の仮想ネットワークを利用 | Windows 側の Consomme が通信を解釈し、通常の Windows の通信として中継 |
| Ubuntu 側の NIC | この PC では `eth0` | この PC では `enP...` に変化 |
| Ubuntu 側の MAC | この PC では WSL 再起動後に変化 | この PC では 2 回の WSL 起動で同じ値 |
| IP アドレス | この PC では Windows と別の仮想ネットワークの値 | この PC では Windows の Wi-Fi 側と同じ値 |

表の NIC・MAC・IP は今回の**検証 PC での観測結果**であり、すべての PC で同じになるという保証ではありません。

## 4. 今回の MAC アドレス問題との関係

利用者の実環境では、SKYSEA に検知された対象が **Ubuntu 側の仮想 NIC `eth0`** とのことです。通常の NAT モードでは、その MAC が WSL の起動時に変わることがあり、今回の検証 PC でも変化しました。

検証 PC を Consomme に切り替えたところ、Ubuntu 側の通信インターフェースは、2 回の WSL 起動時にいずれも次の MAC でした。

```text
00:00:00:00:01:00
```

ただし、次の点に注意が必要です。

- この MAC は検証した WSL の実装上の値です。将来の WSL 更新や異なる環境でも不変という保証はありません。
- 共通の既定値を使う実装があるため、PC ごとに固有の MAC として扱えない可能性があります。
- インターフェース名は `eth0` ではなくなり、検証 PC では起動ごとに変化しました。
- SKYSEA が新しい NIC をどう検知・識別するかは、この PC では未検証です。実環境の管理者に確認が必要です。

**今回の結果は、MAC の変化を抑えられる可能性を示していますが、SKYSEA の検知解消や端末の一意識別を保証するものではありません。**

参照：[Microsoft：WSL 3.0.3 の Consomme 実装](https://github.com/microsoft/WSL/blob/3.0.3/src/windows/common/ConsommeNetworking.cpp)

## 5. IP アドレスは固定される？

**固定されるとは限りません。**

検証 PC では、Consomme 時の Ubuntu の IPv4 アドレスと Windows の Wi-Fi の IPv4 アドレスが同じでした。しかし、Windows の IP は接続先ネットワークや DHCP の設定によって変わることがあります。

Consomme に切り替えただけで、Ubuntu に常に同じ IP が割り当てられると考えることはできません。IP が変わると困る用途がある場合は、その用途に応じて管理者に確認してください。

## 6. Claude Code と Ubuntu のファイルへの影響

Consomme はネットワークの方式を変更するもので、Ubuntu 内のファイルを別の場所に移動する設定ではありません。検証 PC では Consomme 使用中に Ubuntu 内でファイルを作成・読み取りでき、Windows からもテストファイルを読み取れました。

一方で、次は実環境で別途確認が必要です。

- Claude Desktop の Code タブから、Ubuntu の対象フォルダを開けるか。
- Claude Code で質問し、実際に回答を受け取れるか。
- 実際に利用するユーザー権限で、テスト用ファイルの読み取り・編集ができるか。
- 社内 VPN、プロキシ、SSO、Git、MCP、開発サーバーやプレビューが使えるか。

検証 PC では Anthropic の複数の接続先から HTTPS 応答を確認しました。ただし Claude Desktop 画面の操作が Windows 側のアクセス拒否でできず、認証済みの質問・回答や実際の Claude Code による編集は未検証です。HTTPS 応答のみで利用可能とは判断できません。[Claude Code への影響調査](./ClaudeCode影響調査.md)

また、WSL 3.0.3.0 の検証 PC では Consomme 使用中に Apache の IPv4 localhost 接続が失敗しました。Claude Code 自体が必ず使えないという意味ではありませんが、localhost に依存する関連ツールは個別確認が必要です。

## 7. 設定するには

Windows ユーザーフォルダ直下の `.wslconfig` に、次を設定します。設定前のバックアップ、既存設定との併存、WSL 全体の停止、確認方法、元に戻す方法は別紙を参照してください。

```ini
[wsl2]
networkingMode=consomme
```

**設定手順：[Consomme 設定手順書](./Consomme設定手順書.md)**

## 参考資料

- [Microsoft：WSL の詳細設定](https://learn.microsoft.com/ja-jp/windows/wsl/wsl-config)
- [Microsoft：WSL の Consomme の仕組み](https://github.com/microsoft/WSL/blob/3.0.3/doc/docs/technical-documentation/localhost.md)
- [Microsoft：OpenVMM の Consomme 解説](https://github.com/microsoft/openvmm/blob/main/Guide/src/reference/backends/consomme.md)
- [Microsoft：OpenVMM プロジェクト](https://github.com/microsoft/openvmm)
- [Anthropic：Claude Code のネットワーク要件](https://code.claude.com/docs/en/network-config)
- [今回の MAC・IP 実機検証結果](./調査検証結果.md)
