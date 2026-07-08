Claude / claude.ai 側

これは、社員が普通に Claude を使う側です。

たとえば社員が、

「この資料を要約して」
「議事録を作って」
「社内ドキュメントを検索して」
「Claude Code を使って開発して」

といった形で Claude を使う場合、企業としては Claude Enterprise の管理対象になります。

公式ヘルプでは、Enterprise plan は高度なセキュリティ、コンプライアンス管理、チーム全体でのスケーラブルな AI 利用を必要とする組織向けと説明されています。また Enterprise には監査ログ、SCIM、カスタムデータ保持、Compliance API などが含まれるとされています。

Claude Console / Platform 側

こちらは、社員がチャットするための場所というより、開発者が Claude API を使うための環境です。

たとえば企業が、

「自社アプリに Claude を組み込みたい」
「社内FAQボットを作りたい」
「業務システムから Claude API を呼びたい」
「APIキー、ワークスペース、利用量、課金を管理したい」

という場合に使います。

Claude Platform Docs では、開発方法として Messages API と Claude Managed Agents が示されており、Messages API は直接モデルにプロンプトを送る方式、Managed Agents は Anthropic 管理基盤上でエージェントを動かす方式として説明されています。

監査ログの話に戻すと

前回私が Claude Console / Platform と書いたのは、次の意味です。

Claude Enterprise の利用ログを監査したい場合
→ 基本は claude.ai 側の Enterprise 組織に対して Compliance Access Key を使う。

Claude API / Platform の利用や管理をしている組織の Activity Feed を取りたい場合
→ Claude Console / Platform 側の組織に対して、Admin API key または Compliance Access Key の扱いを確認する。

公式ヘルプでは、Compliance API は Claude Enterprise plans と Claude Platform customers の両方で利用可能と説明されています。
つまり、Anthropic の世界では Enterprise で社員が使う Claude と、Platform/Console で API を使う Claude が、管理上は区別されることがあります。

実務上の見分け方

次の質問で判定するとわかりやすいです。

質問	該当するもの
社員が Claude の画面でチャットしているログを取りたい？	Claude Enterprise / claude.ai
APIキーを発行して、自社システムから Claude を呼んでいる？	Claude Console / Platform
Workbench でプロンプトを試している？	Claude Console / Platform
APIキー、ワークスペース、API利用量を管理している？	Claude Console / Platform
SCIM、SSO、監査ログ、チャット履歴、ファイル内容の統制をしたい？	主に Claude Enterprise。ただし Platform 側にも Compliance API 対象があり得る
今回の案件での言い換え

貴社案件でいうと、まず確認すべきはこの2点です。

1. 監査対象は、社員が使う Claude Enterprise か？
その場合は、前回の結論どおり Compliance Access Key を第一候補にします。

2. 監査対象に、Claude API を使った自社アプリや開発者利用も含むか？
その場合は、Claude Console / Platform 側の組織も監査対象になる可能性があります。

つまり、Claude Console / Platform = Claude API を使う開発者・管理者向けの環境と理解してください。
通常の社員利用の Claude Enterprise とは、利用目的も管理対象も少し違います。
