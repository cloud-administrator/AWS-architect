## 調査結果：Claude Enterprise のクレジット制御

前提として、Claude の公式情報では **新しい Claude Enterprise は「シート料金＋利用量課金」** と説明されています。シート料金は Claude へのアクセス権であり、実際の利用分はトークン消費などに応じて別途課金されます。旧来の **Enterprise Standard / Premium シート制** とは扱いが違うため、以下ではまず現在の usage-based Enterprise を中心に整理します。([Claude Help Center][1])

---

## 1. 結論サマリ

| 調査項目                        | 結論                                                                                                                                             |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| クレジット残高・消費の管理               | **可能**。Self-serve Enterprise では事前購入したクレジットを組織全体で共有し、使い切ると利用が停止します。Sales-assisted Enterprise は月次後払いで、残高ではなく利用額管理になります。([Claude Help Center][1]) |
| 組織単位の閾値・使用上限                | **可能**。管理者は組織全体の spend limit、つまり利用金額上限を設定できます。上限到達時は利用が停止します。([Claude Help Center][1])                                                         |
| 個人単位の閾値・使用上限                | **可能**。個人ごとの spend limit を設定できます。個人上限と組織上限の低い方が実質上限になります。([Claude Help Center][1])                                                             |
| グループ単位の閾値・使用上限              | **可能**。Enterprise ではグループごとに、各メンバーへ適用される月次の per-user spend limit を設定できます。([Claude Help Center][2])                                              |
| 通知                          | **可能**。spend limit の閾値に近づくと通知されます。ただし、通知条件の細かいカスタマイズ粒度は公式情報だけでは不明です。([Claude Help Center][1])                                                  |
| 機能ごとの利用回数制限                 | **公式情報では明確な固定回数は確認できません**。現在の Enterprise では「1人あたり何回まで」ではなく、実利用量に応じた課金・上限管理が基本です。([Claudeヘルプセンター][3])                                           |
| DeepResearch / Research の扱い | Claude 公式では **Research** と呼ばれています。Research は通常会話と同じ利用制限の対象ですが、複数ソース検索や長い回答により通常チャットより早く上限を消費する可能性があります。([Claude Help Center][4])               |
| 機能ごとのクレジット消費量               | 「通常チャット1回＝何クレジット」「Research 1回＝何クレジット」のような固定換算は公式に確認できません。公開されているのは主に **モデル別のトークン単価** と一部 Platform 機能の単価です。([Anthropic][5])                     |

---

## 2. クレジット・課金の基本構造

### Self-serve Enterprise の場合

Self-serve Enterprise では、利用量は **事前購入したクレジット** から消費されます。クレジットはユーザー別ではなく、**組織全体で共有されるプール** です。そのため、特定のユーザーが大量に使うと、同じ組織内の共有クレジット残高が減ります。クレジットがなくなると、Owner または Primary Owner が追加購入するまで利用が停止します。([Claude Help Center][1])

初心者向けに言うと、会社全体で使える「プリペイド残高」を買っておき、社員全員がそこから利用料を消費していくイメージです。

### Sales-assisted Enterprise の場合

Sales-assisted Enterprise では、クレジット残高を消費する形ではなく、月次で実利用分が後払い請求されます。この場合、残高切れという概念はありませんが、想定外の高額利用を防ぐには spend limit を設定します。([Claude Help Center][1])

---

## 3. 閾値・通知・使用上限の設定可否

### 組織単位

組織全体の spend limit を設定できます。これは会社全体の月次利用額に対する上限です。上限に達すると、Self-serve ではクレジットが残っていても利用が停止し、Sales-assisted では次の請求期間まで、または上限が引き上げられるまで利用が停止します。([Claude Help Center][1])

### 個人単位

個人ごとの spend limit も設定できます。公式情報では、組織上限と個人上限は階層的に適用され、ユーザーは **自分の個人上限** または **組織全体の上限** のどちらか低い方を超えられない、と説明されています。([Claude Help Center][1])

### グループ単位

Enterprise ではグループを作成し、グループごとの spend limit を設定できます。グループ spend limit は「そのグループに所属する各ユーザーに適用される月次上限」です。たとえば、開発部門グループには月 $200/人、一般部門グループには月 $50/人のような設計ができます。([Claude Help Center][2])

複数グループに所属するユーザーについては、どのグループ上限を適用するかを「高い方」または「低い方」で指定できます。また、個人単位の上限が設定されている場合は、個人上限がグループ上限より優先されます。([Claude Help Center][2])

### 通知

公式情報では、spend limit に近づいた際に通知が行われると説明されています。また、管理画面の Usage では月次利用額、メンバー別支出、spend limit の状態、Self-serve のクレジット残高などを確認できます。([Claude Help Center][1])

ただし、「80%で通知、90%で通知」のような通知閾値をどこまで細かく管理者が任意設定できるかは、公式情報だけでは確認できませんでした。ここは **不明** です。

---

## 4. 機能ごとの制限・消費量

Claude Enterprise の現行モデルでは、基本的に **機能ごとに固定の利用回数が割り当てられる** というより、利用したモデル・入力トークン・出力トークン・ツール利用などに応じて費用が発生する考え方です。公式の Enterprise 説明では、Claude、Claude Code、Cowork の利用は標準 API レートで課金されるとされています。([Claude Help Center][1])

| 機能             | 公式に確認できた制限・消費の考え方                                                                                                                                         |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 通常チャット         | 使用回数の固定上限は確認できません。入力文、添付情報、会話履歴、出力の長さ、利用モデル、effort level によってトークン消費が変わります。([Claudeヘルプセンター][6])                                                            |
| Research       | Claude 公式では Research と記載されています。通常会話と同じ利用制限の対象ですが、複数ソースを検索・分析するため、通常チャットより上限を早く消費する可能性があります。1回あたりの固定クレジット量は不明です。([Claude Help Center][4])                  |
| Claude Code    | 通常チャットより高いトークン消費になりやすいと説明されています。理由は、システムプロンプト、ファイルコンテキスト、ツール呼び出し、複数ターンの推論が含まれるためです。([Claude Help Center][7])                                              |
| Claude Cowork  | エージェント型の複数ステップ処理や Skills により、ユーザーには見えない中間処理でもトークンが発生し、通常チャットより高消費になりやすいと説明されています。([Claude Help Center][7])                                                |
| Web search     | Platform pricing では Web search は $10 / 1,000 searches と公開されています。ただし、Claude.ai Enterprise の Research 利用時にこの単価が請求上どう表示されるかの詳細は公式情報だけでは不明です。([Anthropic][5]) |
| Code execution | Platform pricing では、組織あたり毎日 50 時間までは無料、その後は $0.05 / container-hour と公開されています。([Anthropic][5])                                                             |

---

## 5. モデルごとの消費差

Claude の費用は、どのモデルを使うかで大きく変わります。公式の Enterprise consumption guide でも、Opus は Sonnet より数倍多くの利用量を消費し得ると説明されています。また、effort level を高くすると、より多くの計算・トークンを消費します。([Claude Help Center][7])

2026年7月8日時点で公式 Pricing ページに掲載されている主なモデル単価は以下です。

| モデル       |              入力単価 |              出力単価 | 備考                                                    |
| --------- | ----------------: | ----------------: | ----------------------------------------------------- |
| Fable 5   | $10 / 100万 tokens | $50 / 100万 tokens | 長時間・高性能エージェント向けの高消費モデル                                |
| Opus 4.8  |  $5 / 100万 tokens | $25 / 100万 tokens | 複雑な推論・研究・多段タスク向け                                      |
| Sonnet 5  |  $2 / 100万 tokens | $10 / 100万 tokens | 2026年8月31日までの introductory pricing。以後は $3 / $15 と記載あり |
| Haiku 4.5 |  $1 / 100万 tokens |  $5 / 100万 tokens | 低コスト・高速処理向け                                           |

([Anthropic][5])

つまり、同じ「1回のチャット」でも、短い質問を Haiku で処理する場合と、大量の資料を読み込ませて Opus や Fable で長文回答させる場合では、消費額が大きく変わります。

---

## 6. 機能単位で制限できるか

公式情報上、**「Research だけ月100回」「Claude Code だけ月$500」** のような、機能別の使用回数・金額上限を直接設定できるとは確認できませんでした。確認できた spend limit は、主に以下の単位です。

| 制御単位      | 可否             |
| --------- | -------------- |
| 組織全体      | 可能             |
| 個人        | 可能             |
| グループ      | 可能             |
| 機能ごとの金額上限 | 公式情報では確認できず、不明 |
| 機能ごとの回数上限 | 公式情報では確認できず、不明 |

ただし、Enterprise の RBAC では、グループやカスタムロールを使って、特定の機能・コネクタ・製品サーフェスへのアクセス権を管理できます。たとえば、Engineering には Claude Code を許可し、Marketing には Cowork や Web Search を許可する、といった設計例が公式に示されています。([Claude Help Center][8])

したがって実務上は、
**「機能ごとの金額上限」ではなく、「機能アクセス制御＋グループ/個人 spend limit」でコントロールする**
のが公式情報に沿った設計になります。

---

## 7. 管理・可視化できる情報

Enterprise の Usage Analytics では、利用状況や支出を確認できます。公式情報では、Claude.ai、Claude Code、Cowork などプロダクト別の分析があり、Spend レポートではユーザー、プロダクト、モデル、リクエスト数、入力 tokens、出力 tokens、推定支出などを CSV で確認できると説明されています。([Claude Help Center][9])

これは、導入後の運用ではかなり重要です。たとえば、以下のような見方ができます。

| 見たいこと                                     | 公式機能での確認可能性 |
| ----------------------------------------- | ----------- |
| 誰が多く使っているか                                | 可能          |
| どのモデルで費用が発生しているか                          | 可能          |
| Claude Code / Chat / Cowork などプロダクト別の利用傾向 | 可能          |
| 入力・出力 token 数                             | 可能          |
| 機能別の固定クレジット単価                             | 公式情報では不明    |

---

## 8. 旧 Enterprise Standard / Premium の場合の注意

旧来の seat-based Enterprise Standard / Premium では、現在の usage-based Enterprise と異なり、シートごとの利用上限が存在します。その上限を超えた場合に usage credits を使って継続利用する仕組みです。([Claude Help Center][10])

この旧モデルでは、usage credits に対して以下のような制御ができます。

| 制御                    | 可否 |
| --------------------- | -- |
| 組織全体の usage credit 上限 | 可能 |
| シート種別ごとの上限            | 可能 |
| ユーザー単位の上限             | 可能 |
| usage credit のリクエスト承認 | 可能 |
| 上限到達時の利用停止            | 可能 |

([Claude Help Center][10])

ただし、公式情報では Standard / Premium シート制の Enterprise はレガシー扱いで、次回更新後は継続しない旨が説明されています。新規導入案件であれば、通常は usage-based Enterprise 前提で整理すべきです。([Claudeヘルプセンター][3])

---

## 9. 導入時の推奨設計

初心者にもわかりやすく言うと、Claude Enterprise のコスト管理は「回数券」よりも「利用額上限」に近いです。以下の順で設計すると安全です。

1. **組織全体の月次上限を設定する**
   会社全体の最大支出を決める。ただし、低くしすぎると全社で利用停止になるため注意。

2. **グループごとの per-user 上限を設定する**
   開発、営業、管理部門などで想定利用量が違うため、部門別に上限を変える。

3. **高利用者には個人上限を設定する**
   PoC 期間中は特に、想定外に使いすぎるユーザーを抑止する。

4. **Claude Code / Cowork / Research / Web Search など高消費機能は RBAC で利用対象を絞る**
   全員に最初から解放せず、必要な部門から段階的に展開する。

5. **デフォルトモデルを Sonnet または Haiku 寄りにする**
   Opus / Fable は高性能ですが高コストになりやすいため、必要なユーザーだけに許可するのが安全です。

6. **Usage Analytics を定期確認する**
   ユーザー別、モデル別、プロダクト別の消費を見て、上限やロール設定を調整する。

---

## 10. 不明点として残るもの

公式サイトのみを確認した範囲では、以下は明確に確認できませんでした。

| 不明点                     | コメント                                             |
| ----------------------- | ------------------------------------------------ |
| Research 1回あたりの固定クレジット量 | 公開なし。Research は通常会話と同じ制限対象だが、消費が早い可能性あり、という説明まで。 |
| 通常チャット1回あたりの固定クレジット量    | 公開なし。トークン量・モデル・出力長・会話履歴で変動。                      |
| 機能ごとの月次回数上限             | 公開情報では確認できず。                                     |
| 機能ごとの spend limit       | 公開情報では確認できず。アクセス制御は RBAC で可能。                    |
| 通知閾値の細かいカスタマイズ可否        | spend limit 通知はあるが、細かい閾値設定の仕様は不明。                |

総合すると、Claude Enterprise のクレジット制御は **「組織・グループ・個人ごとの金額上限」＋「機能アクセス権」＋「モデル/effort 制御」＋「利用分析」** で設計するのが公式情報に沿った考え方です。

[1]: https://support.claude.com/en/articles/11526368-how-am-i-billed-for-my-enterprise-plan "How am I billed for my Enterprise plan? | Claude Help Center"
[2]: https://support.claude.com/en/articles/13799932-manage-groups-and-group-spend-limits-on-enterprise-plans "Manage groups and group spend limits on Enterprise plans | Claude Help Center"
[3]: https://support.anthropic.com/en/articles/9797531-what-is-the-claude-enterprise-plan "What is the Enterprise plan? | Claude Help Center"
[4]: https://support.claude.com/en/articles/11088861-use-research-on-claude "Use research on Claude | Claude Help Center"
[5]: https://www.anthropic.com/pricing "Plans & Pricing | Claude by Anthropic"
[6]: https://support.anthropic.com/en/articles/11647753-understanding-usage-and-length-limits "How do usage and length limits work? | Claude Help Center"
[7]: https://support.claude.com/en/articles/14782391-claude-enterprise-consumption-guide "Claude Enterprise consumption guide | Claude Help Center"
[8]: https://support.claude.com/en/articles/13930458-set-up-role-based-permissions-on-enterprise-plans "Set up role-based permissions on Enterprise plans | Claude Help Center"
[9]: https://support.claude.com/en/articles/12883420-view-usage-analytics-for-team-and-enterprise-plans "View usage analytics for Team and Enterprise plans | Claude Help Center"
[10]: https://support.claude.com/en/articles/12005970-manage-usage-credits-for-team-and-seat-based-enterprise-plans "Manage usage credits for Team and seat-based Enterprise plans | Claude Help Center"
