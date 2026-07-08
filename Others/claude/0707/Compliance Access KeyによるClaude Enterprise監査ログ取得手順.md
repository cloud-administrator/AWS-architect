## Compliance Access KeyによるClaude Enterprise監査ログ取得手順

調査日: **2026年7月8日 JST**
参照範囲: **Anthropic / Claude公式ドキュメントのみ**

本手順は、Claude Enterpriseで **Compliance Access Key** を作成し、Compliance APIの **Activity Feed** から監査ログを取得できる状態にするための設定手順です。PowerShellスクリプト自体は含めません。

なお、公式ドキュメント上、Compliance APIはClaude Enterpriseで利用可能ですが、**Public Sector組織は対象外**とされています。また、Compliance APIには監査ログイベントが含まれ、Claude導入全体のActivity Feedイベント、チャットデータ、ファイルコンテンツ等をプログラムで取得する用途に使うものと説明されています。([Claude ヘルプセンター][1])

---

# 1. この手順で実現すること

今回の目的は、Claude Enterpriseの監査ログを、手動CSVエクスポートではなく、**Compliance APIのActivity Feed** から継続的に取得できるようにすることです。

取得に使うAPIは次です。

```text
GET https://api.anthropic.com/v1/compliance/activities
```

認証には、Claude Enterpriseの `claude.ai > Organization settings > API` で作成する **Compliance Access Key** を使います。Claude Enterpriseの親組織はClaude Consoleには表示されないため、Compliance Access Keyは **Claude Consoleではなく claude.ai の Organization settings で作成する**必要があります。([Claude Platform][2])

---

# 2. 重要な前提と制限

## 2.1 手動の「Export logs」とは別物

Claudeには、Organization settingsのData and Privacyから監査ログをCSVでエクスポートする機能もあります。ただし、公式ドキュメントでは、このCSVエクスポートはCompliance APIより範囲が狭く、遡及期間の上限があり、継続的なプログラム取得にはCompliance APIを使うべきと説明されています。([Claude Platform][3])

したがって、本手順では **Export logsボタンによるCSV取得は使用しません**。

## 2.2 「完璧に取得」の対象範囲

この手順で完全取得を目指す対象は、公式に **Compliance API Activity Feedで提供されるイベント** です。Activity Feedは、認証、チャット、ファイル、プロジェクト、管理操作、プラットフォーム操作などを記録し、イベントは通常1分以内に照会可能、保持期間は6年とされています。([Claude Platform][4])

ただし、公式ドキュメント上、以下はActivity FeedまたはCompliance APIの対象外・別扱いです。

* Claude Console / Claude APIワークロードのプロンプト本文やモデル応答本文は、Compliance APIのActivity Feedでは取得対象ではありません。([Claude Platform][5])
* 組織の保持ポリシーで削除済みのコンテンツ、またはCompliance APIでハード削除済みのコンテンツは取得できません。([Claude Platform][5])
* Claude Coworkの活動は、現時点でCompliance APIに含まれないと公式ヘルプに記載されています。([Claude ヘルプセンター][6])
* Claude for Excel / PowerPoint / Word / Outlookアドインの活動は、現時点でEnterprise audit logs、Compliance API、data exportsに含まれないと公式ヘルプに記載されています。([Claude ヘルプセンター][7])

上記まで含めた「Claude関連のすべての動作ログを単一APIで完全取得する」ことは、公式情報上はできません。以下の手順は、**Compliance API Activity Feedで提供される監査イベントを欠落なく取得するための設定手順**として作成しています。

---

# 3. 作業前に確認すること

## 3.1 契約・組織種別を確認する

対象組織が **Claude Enterprise** であることを確認します。公式ヘルプでは、Compliance APIはClaude Enterpriseプラン、ただしPublic Sector組織を除く、と説明されています。([Claude ヘルプセンター][1])

確認項目は次です。

| 確認項目                   | 判断                                   |
| ---------------------- | ------------------------------------ |
| Claude Enterprise契約か   | 必須                                   |
| Public Sector組織ではないか   | Public Sectorの場合、この手順の適用可否は公式情報上は対象外 |
| claude.aiの親組織にアクセスできるか | 必須                                   |
| 作業者がプライマリオーナーか         | 必須                                   |

## 3.2 作業者のロールを確認する

Compliance Access Keyを作成する作業は、公式ドキュメント上、**claude.aiのプライマリオーナー**として行います。APIページが表示されない場合、またはキー作成時にコンプライアンススコープが表示されない場合は、プライマリオーナーではない、またはCompliance APIがまだ有効化されていない可能性があります。([Claude Platform][2])

作業者は、次の条件を満たすアカウントにしてください。

| 項目    | 必須条件                                |
| ----- | ----------------------------------- |
| ログイン先 | `claude.ai`                         |
| ロール   | プライマリオーナー                           |
| 対象    | Claude Enterprise親組織                |
| 注意点   | Claude Console側ではなく、claude.ai側で作業する |

---

# 4. Compliance APIを有効化する

## 4.1 claude.aiにサインインする

Claude Enterpriseの **プライマリオーナー** アカウントで `claude.ai` にサインインします。

ここで、通常の一般ユーザーやメンバー権限では作業できません。Compliance Access Keyは組織全体の監査データにアクセスできる強力なキーであるため、必ず管理権限を持つアカウントで作業します。

## 4.2 Organization settingsを開く

`claude.ai` の画面から、対象のEnterprise組織の **Organization settings** を開きます。

Claude Enterpriseでは、親組織がClaude Consoleに表示されないため、`platform.claude.com` 側ではなく、`claude.ai` 側のOrganization settingsを使います。公式ドキュメントでも、Compliance Access KeyはClaude Consoleではなく、claude.aiのOrganization settingsで作成すると明記されています。([Claude Platform][2])

## 4.3 Compliance APIを有効化する

Organization settings内で **Compliance API** を有効化します。

公式ドキュメントでは、Claude Enterpriseのプライマリオーナーはclaude.aiで直接Compliance APIを有効化できるとされています。また、有効化は親組織レベルで行われ、claude.aiとClaude Consoleの両方を含むすべてのリンクされた組織に適用されると説明されています。([Claude Platform][2])

画面上でCompliance APIの設定項目が見つからない場合は、次を確認します。

| 状況                           | 対応                                           |
| ---------------------------- | -------------------------------------------- |
| Organization settingsが表示されない | 作業者が対象組織の管理者でない可能性があります                      |
| APIページが表示されない                | プライマリオーナーでない、またはCompliance APIが未有効化の可能性があります |
| Compliance scopeが表示されない      | Compliance APIが有効化されていない可能性があります             |
| Claude Console側を見ている         | claude.ai側のOrganization settingsを確認します       |

画面上の具体的な有効化ボタン名やUI文言は、公式ドキュメントからは一意に確認できませんでした。そのため、ここは **不明** とします。ただし、公式ドキュメント上は、Claude Enterpriseのプライマリオーナーがclaude.aiの組織設定からCompliance APIを有効化する流れであることは確認できます。([Claude Platform][2])

---

# 5. Compliance Access Keyを作成する

## 5.1 API設定画面を開く

claude.aiで次の場所に移動します。

```text
Organization settings > API
```

その中の **Keys** セクションを開きます。公式ドキュメントでは、Compliance Access Keyは `claude.ai > Organization settings > API` のKeysセクションから作成すると説明されています。([Claude Platform][2])

## 5.2 Create keyを選択する

Keysセクションで **Create key** を選択します。

キー名は、後から用途が分かる名前にします。例は次です。

```text
compliance-activity-feed-prod-20260708
```

キー名には、環境、用途、作成日を含めると運用しやすくなります。ただし、キー名に秘密情報、担当者の個人情報、認証情報、チケット番号などを入れないでください。

## 5.3 スコープを選択する

監査ログ、つまりActivity Feedのみを取得する場合、選択するスコープは次です。

```text
read:compliance_activities
```

公式ドキュメントでは、Activity Feedを読み取る監査パイプラインには `read:compliance_activities` のみが必要とされています。([Claude Platform][2])

他のスコープは、今回の目的では付与しません。

| スコープ                          |   今回の設定 | 理由                                |
| ----------------------------- | ------: | --------------------------------- |
| `read:compliance_activities`  |    付与する | Activity Feed監査ログ取得に必要            |
| `read:compliance_user_data`   | 原則付与しない | チャット、メッセージ、ファイル、プロジェクト等の閲覧権限を含むため |
| `delete:compliance_user_data` |   付与しない | ユーザーのチャット、ファイル、プロジェクトを削除できるため危険   |
| `read:compliance_org_data`    | 原則付与しない | 監査ログ取得だけなら不要                      |

特に `read:compliance_user_data` を持つキーは、プライマリオーナーが閲覧していないコンテンツも含め、リンクされた組織内のチャット、ファイル、プロジェクトを読み取れると説明されています。また、`delete:compliance_user_data` はコンテンツを完全削除できるため、今回の監査ログ取得用途では付与しないでください。([Claude Platform][2])

## 5.4 キーを作成してコピーする

キーを作成すると、`sk-ant-api01-...` で始まるCompliance Access Keyが表示されます。公式ドキュメントでは、Compliance Access Keyのプレフィックスは `sk-ant-api01-...` とされています。([Claude Platform][2])

このキーは一度しか完全表示されない前提で扱います。表示されたら、すぐにシークレット管理基盤へ保存してください。

保存先の例は次です。

| 環境           | 推奨保存先               |
| ------------ | ------------------- |
| Azure        | Azure Key Vault     |
| AWS          | AWS Secrets Manager |
| Google Cloud | Secret Manager      |
| オンプレミス       | 組織標準の特権シークレット管理製品   |

公式ドキュメントでも、Compliance Access Keyは本番データベースの認証情報と同様に扱い、シークレットマネージャーに保存し、ソース管理やSIEMフォワーダー設定には保存しないよう記載されています。([Claude Platform][2])

---

# 6. 作成したキーを確認する

キー作成後、次を確認します。

| 確認項目          | 正しい状態                                     |
| ------------- | ----------------------------------------- |
| キーの種類         | Compliance Access Key                     |
| キーのプレフィックス    | `sk-ant-api01-...`                        |
| 作成場所          | `claude.ai > Organization settings > API` |
| スコープ          | `read:compliance_activities`              |
| 保存場所          | シークレット管理基盤                                |
| ソースコード保存      | していない                                     |
| SIEM設定ファイル直書き | していない                                     |

公式ドキュメントでは、スコープはキー作成後に変更できないとされています。スコープを間違えた場合は、既存キーを修正するのではなく、新しいキーを作成してください。([Claude Platform][2])

---

# 7. ログ取得処理側に設定する値

PowerShellスクリプト自体は別途作成済みとのことなので、ここではスクリプトに設定すべき値だけを示します。

## 7.1 APIエンドポイント

```text
https://api.anthropic.com/v1/compliance/activities
```

すべてのCompliance APIエンドポイントは `https://api.anthropic.com` 上の `/v1/compliance/*` 配下にあり、Activity Feedは `GET /v1/compliance/activities` で取得します。([Claude Platform][3])

## 7.2 認証ヘッダー

```text
x-api-key: <Compliance Access Key>
```

Compliance APIは `x-api-key` ヘッダーで認証します。公式ドキュメントの例でも、Activity Feed取得時に `x-api-key` ヘッダーへCompliance Access Keyを渡しています。([Claude Platform][3])

## 7.3 通常取得時のクエリ条件

監査ログを漏れなく取得する通常運用では、原則として次のように設定します。

| 設定項目                               | 推奨値                                                   |
| ---------------------------------- | ----------------------------------------------------- |
| `limit`                            | `5000`                                                |
| `activity_types[]`                 | 通常は指定しない                                              |
| `actor_ids[]`                      | 通常は指定しない                                              |
| `organization_ids[]`               | 通常は指定しない                                              |
| `created_at.gte` / `created_at.lt` | 時刻ウィンドウ方式を使う場合のみ指定                                    |
| ページング                              | `first_id` / `last_id` / `before_id` / `after_id` を使用 |

`limit` の最大値は5000です。また、フィルターを指定すると対象イベントが絞り込まれるため、全監査イベント取得が目的の場合は、通常運用では `activity_types[]`、`actor_ids[]`、`organization_ids[]` を指定しないでください。([Claude Platform][4])

---

# 8. 初回バックフィル取得の設定

初回実行では、取得可能なActivity Feedを過去方向へ取得します。

## 8.1 初回リクエスト

初回は、ページングカーソルを指定せずに取得します。

```text
GET /v1/compliance/activities?limit=5000
```

成功すると、レスポンスには次の項目が含まれます。

| 項目         | 意味                    |
| ---------- | --------------------- |
| `data`     | Activityレコードの配列       |
| `has_more` | さらにページがあるか            |
| `first_id` | 取得ページ内の最初のActivity ID |
| `last_id`  | 取得ページ内の最後のActivity ID |

公式ドキュメントの成功レスポンス例でも、`data`、`has_more`、`first_id`、`last_id` が返ると説明されています。([Claude Platform][3])

## 8.2 取得結果を保存する

取得した `data` 配列を、監査ログ保管先に保存します。

保存時は、Activityの `id` を一意キーとして扱ってください。公式ドキュメントでは、Activity Feedは少なくとも1回配信の前提で扱い、再試行により同じイベントが再配信される可能性があるため、`id` で重複排除するよう説明されています。([Claude Platform][5])

保存すべき代表項目は次です。

| 項目                     | 保存理由              |
| ---------------------- | ----------------- |
| `id`                   | 一意キー、重複排除用        |
| `created_at`           | イベント発生時刻          |
| `organization_id`      | 対象組織              |
| `organization_uuid`    | 対象組織UUID          |
| `actor`                | 実行者情報             |
| `actor.type`           | 実行者種別             |
| `actor.user_id`        | ユーザー相関用の安定ID      |
| `actor.email_address`  | 調査時の可読性向上         |
| `actor.ip_address`     | セキュリティ調査用         |
| `type`                 | イベント種別            |
| その他の全フィールド             | 将来のスキーマ追加、監査証跡保持用 |
| レスポンスヘッダー `request-id` | 問い合わせ・証跡用         |
| 取得実行日時                 | チェーン・オブ・カストディ用    |
| APIパラメータ               | 再現性確保用            |

公式ドキュメントでは、メールアドレスは変更され得るため、SIEM相関では `actor.user_id` を主キーとして使うことが推奨されています。また、取得完了証跡として、開始カーソル、終了カーソル、件数、実行時刻、最終ページの `request-id` などを記録することが推奨されています。([Claude Platform][5])

## 8.3 次ページを取得する

レスポンスの `has_more` が `true` の場合、次のページを取得します。

過去方向へ進む場合は、前回レスポンスの `last_id` を `after_id` に指定します。

```text
GET /v1/compliance/activities?limit=5000&after_id=<前回レスポンスのlast_id>
```

Activity Feedは新しい順で返り、`last_id` を `after_id` として使うと次のページ、つまりより古いActivityへ進むと説明されています。`has_more=false` になるまで繰り返します。([Claude Platform][4])

## 8.4 初回バックフィルの完了条件

初回バックフィルは、次の状態で完了とします。

| 条件                       | 内容                |
| ------------------------ | ----------------- |
| `has_more=false` に到達     | 取得可能な過去ページを最後まで取得 |
| 各ページの `data` を保存済み       | 保存失敗ページがない        |
| `id` で重複排除済み             | 再取得時の重複を排除        |
| 最初のページの `first_id` を保存   | 今後の増分取得の開始点       |
| 最終ページの `last_id` を保存     | バックフィル完了証跡        |
| 実行日時、件数、`request-id` を保存 | 監査証跡              |

---

# 9. 継続取得の設定

初回バックフィル後は、新しく発生したActivityを定期的に取得します。

推奨方式は、**カーソル駆動の増分取得**です。公式ドキュメントでは、低遅延で再読込を避けたい場合や、カーソルを永続化できる場合にカーソル駆動方式を使うと説明されています。([Claude Platform][5])

## 9.1 増分取得の開始カーソル

初回バックフィル時に保存した、最初のページの `first_id` を使用します。

増分取得では、保存済みの最新カーソルを `before_id` に指定します。

```text
GET /v1/compliance/activities?limit=5000&before_id=<保存済みのfirst_id>
```

`before_id` は、保存済みカーソルより新しいActivityを取得するために使います。([Claude Platform][4])

## 9.2 増分取得のページング

レスポンスの `has_more` が `true` の場合、まだ取得すべき新しいActivityが残っています。

この場合、取得したページの `first_id` を次の `before_id` として使用し、さらに現在時刻側へ進みます。

```text
GET /v1/compliance/activities?limit=5000&before_id=<前回レスポンスのfirst_id>
```

`has_more=false` になるまで繰り返します。

## 9.3 カーソルの保存タイミング

カーソルは、**全ページの保存が成功し、`has_more=false` に到達した後**に更新します。

途中で保存失敗、ネットワークエラー、5xx、429などが発生した場合は、保存済みカーソルを進めないでください。公式ドキュメントでは、失敗やタイムアウト時は同じカーソルで再試行し、ページ範囲を保存できた後にのみカーソルを進めると説明されています。([Claude Platform][4])

---

# 10. 時刻ウィンドウ方式を使う場合の注意

PowerShell側で時刻ウィンドウ方式を採用している場合は、次の条件を守ってください。

```text
created_at.gte=<開始時刻>
created_at.lt=<終了時刻>
```

時刻はRFC 3339形式を使います。

```text
2026-07-08T00:00:00Z
```

公式ドキュメントでは、時刻ウィンドウ方式を使う場合、`created_at.lt` は現在時刻より少なくとも1分以上前に設定すること、次のウィンドウの `created_at.gte` は前回の `created_at.lt` と同じ値にすることが説明されています。これはギャップを作らないためです。([Claude Platform][5])

ただし、遅延インデックスされたイベントを取りこぼすリスクがあるため、時刻ウィンドウ方式を使う場合でも、重複排除を前提にオーバーラップまたは再照合処理を組み込むことを推奨します。([Claude Platform][5])

---

# 11. 疎通確認手順

## 11.1 最小取得テスト

キー作成後、PowerShell側から次の条件で1件取得を行います。

```text
GET /v1/compliance/activities?limit=1
```

期待される結果は次です。

| 項目         | 期待値                           |
| ---------- | ----------------------------- |
| HTTPステータス  | 200系                          |
| レスポンス形式    | JSON                          |
| `data`     | 配列                            |
| `has_more` | true または false                |
| `first_id` | Activity ID、またはデータがない場合は空の可能性 |
| `last_id`  | Activity ID、またはデータがない場合は空の可能性 |

公式ドキュメントのサンプルでも、`limit=1` のActivity Feed取得例と、成功レスポンスに `data`、`has_more`、`first_id`、`last_id` が含まれることが示されています。([Claude Platform][3])

## 11.2 テストイベントの発生確認

次に、監査対象となる無害な操作を1つ実施します。

例:

| 操作            | 確認したいこと            |
| ------------- | ------------------ |
| テストユーザーでサインイン | 認証イベントが取得されること     |
| テスト用チャット作成    | チャット関連イベントが取得されること |
| テストファイルアップロード | ファイル関連イベントが取得されること |
| 管理設定の軽微な変更    | 管理操作イベントが取得されること   |

Activity Feedは通常1分以内に照会可能と説明されています。したがって、テスト操作後、少し時間を置いて再取得し、該当イベントが保存先に記録されることを確認します。([Claude Platform][4])

## 11.3 Compliance API自身のアクセスログ確認

Compliance APIの呼び出し自体も、`compliance_api_accessed` イベントとして記録されると説明されています。したがって、取得処理を実行した後、`compliance_api_accessed` イベントが保存先に存在するか確認します。([Claude Platform][5])

このイベントが確認できれば、少なくとも以下が成立しています。

| 確認できること             | 内容                     |
| ------------------- | ---------------------- |
| キーが有効               | API呼び出しが成功している         |
| Activity Feedが読めている | APIアクセスイベントが取得対象に入っている |
| 保存処理が動作している         | 取得結果が保存先に入っている         |

---

# 12. エラー時の確認観点

## 12.1 401 Unauthorized

401の場合は、`x-api-key` が存在しない、誤っている、削除済み、または認識されていない可能性があります。シークレット管理基盤に保存した値、参照先、環境変数名、キーの有効性を確認してください。([Claude Platform][8])

## 12.2 403 Forbidden

403の場合は、キーは有効だが、必要なスコープが不足している可能性があります。

Activity Feed取得に必要なスコープは次です。

```text
read:compliance_activities
```

スコープは作成後に変更できないため、スコープ不足の場合は新しいCompliance Access Keyを作成してください。([Claude Platform][8])

## 12.3 400 Bad Request

400の場合は、クエリパラメータの形式不正を疑います。

主な確認項目は次です。

| 項目                       | 確認内容                                         |
| ------------------------ | -------------------------------------------- |
| `limit`                  | 最大5000を超えていないか                               |
| `created_at.*`           | RFC 3339形式か                                  |
| `after_id` / `before_id` | APIレスポンスの `first_id` / `last_id` をそのまま使っているか |
| ページング指定                  | `after_id` と `before_id` を同時指定していないか         |

公式ドキュメントでは、タイムスタンプはRFC 3339形式を使うこと、カーソルは不透明な値として扱い、過去レスポンスの `first_id` / `last_id` を使うことが説明されています。([Claude Platform][8])

## 12.4 429 Too Many Requests

Compliance APIの `/v1/compliance/*` エンドポイントは、親組織ごとに1分あたり600リクエストの単一レート制限を共有します。429が返った場合は、`retry-after` に従って待機し、カーソルを進めずに同じリクエストを再試行してください。([Claude Platform][3]) ([Claude Platform][8])

## 12.5 5xx系エラー

5xx、502、503、504、529の場合は、指数バックオフで再試行します。ただし、500で `x-should-retry:false` が返る場合は再試行しないと公式ドキュメントに記載されています。障害調査やAnthropicへの問い合わせに備えて、レスポンスヘッダーの `request-id` を保存してください。([Claude Platform][8]) ([Claude Platform][8])

---

# 13. キーのローテーション手順

Compliance Access Keyは自動失効しないため、組織のセキュリティ基準に従って定期的にローテーションします。公式ドキュメントでは、Compliance Access Keyは自動的には期限切れにならず、削除すると次のリクエストから即時に無効になると説明されています。([Claude Platform][2])

ローテーション手順は次です。

1. claude.aiにプライマリオーナーでサインインします。
2. `Organization settings > API > Keys` を開きます。
3. 既存キーと同じ用途の新しいCompliance Access Keyを作成します。
4. スコープは `read:compliance_activities` のみにします。
5. 新しいキーをシークレット管理基盤に保存します。
6. PowerShell取得処理の参照先を新しいキーへ切り替えます。
7. `limit=1` で疎通確認します。
8. 増分取得が正常に継続できることを確認します。
9. 旧キーを削除します。

公式ドキュメントでは、カーソルはキーのローテーション後も有効と説明されています。そのため、キー変更時に `first_id` / `last_id` などの保存済みカーソルをリセットする必要はありません。([Claude Platform][2])

キー漏えいが疑われる場合は、該当キーを即時削除し、`compliance_api_accessed` イベントで不審なAPIアクセスを確認し、必要に応じて下流システムの認証情報もローテーションしてください。([Claude Platform][2])

---

# 14. 最終チェックリスト

本番運用前に、次をすべて満たしていることを確認してください。

| No. | チェック項目         | 合格条件                                                                 |
| --: | -------------- | -------------------------------------------------------------------- |
|   1 | 契約             | Claude Enterpriseである                                                 |
|   2 | 対象外確認          | Public Sector組織ではない、またはAnthropic側に適用可否を確認済み                          |
|   3 | 作業者            | claude.aiのプライマリオーナーで作業している                                           |
|   4 | 作業場所           | Claude Consoleではなく、claude.aiのOrganization settingsで作業している            |
|   5 | Compliance API | 親組織で有効化済み                                                            |
|   6 | キー種別           | Compliance Access Keyである                                             |
|   7 | キープレフィックス      | `sk-ant-api01-...` で始まる                                              |
|   8 | スコープ           | `read:compliance_activities` のみ付与                                    |
|   9 | 過剰権限           | `read:compliance_user_data` と `delete:compliance_user_data` を付与していない |
|  10 | シークレット管理       | キーをシークレット管理基盤に保存している                                                 |
|  11 | 直書き禁止          | ソースコード、設定ファイル、SIEMフォワーダー設定にキーを直書きしていない                               |
|  12 | APIエンドポイント     | `GET /v1/compliance/activities` を使用している                              |
|  13 | 認証ヘッダー         | `x-api-key` を使用している                                                  |
|  14 | 通常取得           | 全件取得目的では `activity_types[]` 等の絞り込みを指定していない                           |
|  15 | ページング          | `has_more=false` まで取得する                                              |
|  16 | 過去方向取得         | `after_id=<last_id>` を使う                                             |
|  17 | 新規方向取得         | `before_id=<first_id>` を使う                                           |
|  18 | 重複排除           | Activity `id` を一意キーとして保存している                                         |
|  19 | カーソル更新         | 全ページ保存後にのみカーソルを更新している                                                |
|  20 | 失敗時            | エラー時にカーソルを進めない                                                       |
|  21 | レート制限          | 429時は `retry-after` に従う                                              |
|  22 | 証跡             | `request-id`、取得件数、取得時刻、開始・終了カーソルを保存している                              |
|  23 | 疎通確認           | `limit=1` で200系レスポンスを確認済み                                            |
|  24 | テストイベント        | サインイン等のテストイベントが保存先に記録されることを確認済み                                      |
|  25 | API自己監査        | `compliance_api_accessed` イベントが保存されることを確認済み                          |
|  26 | ローテーション        | 新旧キー切替手順を文書化済み                                                       |
|  27 | 対象外ログ          | Cowork、Microsoft 365アドイン等の公式対象外範囲を関係者に説明済み                           |

---

# 15. 不明点として残る事項

公式情報のみを確認した範囲では、次は不明です。

| 不明点                                      | 理由                                                        |
| ---------------------------------------- | --------------------------------------------------------- |
| claude.ai画面上のCompliance API有効化ボタンの正確な表示名 | 公式ドキュメントに具体的なUI文言までは明記されていません                             |
| Public Sector組織での代替手段                    | 公式ヘルプではCompliance API対象外と記載されていますが、代替APIや例外手続きは確認できませんでした |
| Organization settings画面の細かな表示順やUI差分      | 公式ドキュメントは手順概要を示していますが、画面キャプチャベースの完全なUI遷移までは確認できませんでした     |

この手順どおりに設定すれば、**Compliance API Activity Feedで提供されるClaude Enterpriseの監査イベントを、ページング・重複排除・カーソル管理・エラー時再試行を前提に、欠落を避けて取得できる構成**になります。

[1]: https://support.claude.com/en/articles/13015708-access-the-compliance-api "Access the Compliance API | Claude Help Center"
[2]: https://platform.claude.com/docs/ja/manage-claude/compliance-api-access "Compliance APIへのアクセスを取得する - Claude Platform Docs"
[3]: https://platform.claude.com/docs/ja/manage-claude/compliance-api "Compliance API - Claude Platform Docs"
[4]: https://platform.claude.com/docs/ja/manage-claude/compliance-activity-feed "アクティビティフィードのクエリ - Claude Platform Docs"
[5]: https://platform.claude.com/docs/ja/manage-claude/compliance-integration-patterns "コンプライアンス統合の設計 - Claude Platform Docs"
[6]: https://support.claude.com/en/articles/13455879-use-claude-cowork-on-team-and-enterprise-plans "Use Claude Cowork on Team and Enterprise plans | Claude Help Center"
[7]: https://support.claude.com/en/articles/13892150-work-across-microsoft-365-apps "Work across Microsoft 365 apps | Claude Help Center"
[8]: https://platform.claude.com/docs/ja/manage-claude/compliance-errors "Compliance APIエラーの処理 - Claude Platform Docs"
