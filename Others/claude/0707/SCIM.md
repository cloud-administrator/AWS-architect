以下は、**Claude Enterprise を Microsoft Entra ID（旧 Azure AD）と連携し、SAML SSO でログインし、SCIM でユーザー・グループ・ロール・シートを自動管理する**ための公式情報ベースの整理です。

重要な前提として、**SCIM はログイン認証の仕組みではありません**。Microsoft 公式ドキュメントでも、SCIM はアプリケーションに対するユーザー・グループの作成、更新、削除、割り当て変更などの「プロビジョニング／デプロビジョニング」の仕組みとして説明されています。一方、ログイン認証は通常 SAML SSO または OIDC で行います。Claude Enterprise の Microsoft Entra ID 連携でも、公式手順は **SAML SSO を設定し、その後 SCIM プロビジョニングを設定する**流れです。([Microsoft Learn][1])

---

## 1. 結論：目指すべき全体構成

Claude Enterprise と Entra ID の連携は、以下のように分けて考えると理解しやすいです。

```text
利用者
  |
  | 1. Claude にアクセスし「Continue with SSO」でログイン
  v
Claude / WorkOS
  |
  | 2. SAML 認証要求
  v
Microsoft Entra ID
  |
  | 3. 認証、MFA、条件付きアクセスなどを実施
  v
Claude Enterprise
  |
  | 4. SAML の email 属性でユーザーを特定し、Claude ワークスペースへログイン


別系統：ユーザー・グループ同期

Microsoft Entra ID
  |
  | SCIM 2.0
  | ユーザー作成、更新、無効化、グループ同期
  v
Claude / WorkOS SCIM エンドポイント
  |
  v
Claude Enterprise のメンバー、グループ、ロール、シート管理
```

この構成では、**ログイン認証は SAML SSO**、**ユーザー・グループの自動同期は SCIM** が担当します。Claude 公式ガイドでも、Microsoft Entra ID との SSO 設定、SCIM プロビジョニング、ユーザー／グループ割り当て、SSO テストという順序で説明されています。([Claude ヘルプセンター][2])

また、Claude の SSO・SCIM 設定には **WorkOS** が関係します。Claude 公式ドキュメントでは、WorkOS は Anthropic がドメイン検証、SSO、プロビジョニング設定に使うプロバイダーであると説明されています。Claude 管理画面内の設定フローで、SAML の Entity ID、ACS URL、SCIM の Tenant URL、Secret Token などを取得します。([Claude ヘルプセンター][3])

---

## 2. 用語の整理

### SAML SSO

SAML SSO は、Claude へのログイン時に Microsoft Entra ID を認証元として使う仕組みです。ユーザーは Claude 側で SSO を選び、Entra ID 側で認証されます。Entra ID で MFA や条件付きアクセスを設定していれば、その認証ポリシーも適用できます。

Claude の Microsoft Entra ID 公式手順では、Entra の Enterprise Application に Claude アプリを作成し、SAML の **Identifier / Entity ID**、**Reply URL / ACS URL**、**Sign-on URL**、**Attributes & Claims** を設定します。([Claude ヘルプセンター][2])

### SCIM

SCIM は、Entra ID から Claude 側に対して、ユーザーやグループの情報を自動同期するための標準プロトコルです。Microsoft 公式ドキュメントでは、Entra のプロビジョニングサービスが SCIM 2.0 エンドポイントに接続し、ユーザーやグループを作成、更新、削除する仕組みとして説明されています。([Microsoft Learn][4])

Claude では、SCIM により、IdP 側で割り当てられたユーザーの追加、削除、グループ変更、ロールやシートの割り当て変更などを自動化できます。Claude 公式ドキュメントでは、SCIM は **Enterprise と Console** で利用可能であり、Team では利用できないと説明されています。([Claude ヘルプセンター][5])

### JIT プロビジョニング

JIT、つまり Just-In-Time プロビジョニングは、ユーザーが初回 SSO ログインしたタイミングで Claude にユーザーを作成する仕組みです。SCIM と異なり、ログインする前にあらかじめユーザーを同期しておく方式ではありません。

Claude 公式ドキュメントでは、Invite only、JIT、JIT + Group Mappings、SCIM、SCIM + Group Mappings の違いが整理されています。SCIM は、ログイン前から IdP の割り当てに基づいてユーザーを自動作成・自動削除できる点が特徴です。([Claude ヘルプセンター][5])

---

## 3. 導入前に確認すべき前提条件

Claude Enterprise で Entra ID 連携を行う前に、以下を確認してください。

| 項目             | 確認内容                                                                                                                    |
| -------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Claude プラン     | Claude Enterprise であること。SCIM は Enterprise または対象の Console 組織で利用可能です。                                                     |
| Claude 管理権限    | Claude 側で Owner、Primary Owner、または対象の管理者権限が必要です。                                                                         |
| Entra ID 権限    | Entra 側で Global Administrator または Application Administrator など、Enterprise Application と SSO/Provisioning を設定できる権限が必要です。 |
| Entra ID ライセンス | Claude 公式の Entra 手順では、SCIM には Microsoft Entra ID P1 または P2 が前提として記載されています。                                              |
| ドメイン管理         | 会社ドメインの DNS に TXT レコードを追加できること。                                                                                         |
| メール属性設計        | SAML SSO で送る email と、SCIM で同期する email が完全一致するように決めること。                                                                  |
| 対象ユーザー         | 最初はパイロット用の小さなユーザー／グループで検証すること。                                                                                          |
| ロール設計          | Owner、Admin、User、Custom などをどの Entra グループで割り当てるか決めること。                                                                   |
| シート設計          | 契約形態に応じて、Enterprise seat や legacy seat type の扱いを確認すること。                                                                 |

Claude 公式の Microsoft Entra ID セットアップ手順では、Claude Team/Enterprise/Console の対象組織、Claude 側の管理者権限、Entra ID P1/P2、Entra 側の管理者権限、検証済みドメインが前提として挙げられています。([Claude ヘルプセンター][2])

Microsoft 側でも、アプリへのユーザー・グループ割り当てには Enterprise Application の割り当て操作が必要であり、グループベースの割り当てには Entra ID P1/P2 が必要であると説明されています。([Microsoft Learn][6])

---

## 4. Claude 側の「親組織」とドメイン検証

Claude の SSO 設定では、**parent organization、つまり親組織**の考え方が出てきます。Claude 公式ドキュメントでは、親組織は複数の Claude 組織や Console 組織にまたがって SSO 設定を共有するための仕組みと説明されています。Enterprise の親組織は自動的に作成され、ドメイン検証は親組織レベルで行われます。([Claude ヘルプセンター][7])

ドメイン検証では、Claude 管理画面の Identity and access または Organization and access から対象ドメインを追加し、DNS に TXT レコードを設定します。Claude 公式情報では、TXT レコードの値は `anthropic-domain-verification-` で始まり、Host/Name は通常 `@`、値は大文字小文字を区別すると説明されています。DNS 反映は短時間で済む場合もありますが、グローバルには 24〜48 時間かかる場合があります。([Claude ヘルプセンター][3])

注意点として、**ドメイン検証自体は既存ユーザーに影響しません**。ユーザーアクセスに影響するのは、SSO の設定と強制を有効化した後です。([Claude ヘルプセンター][3])

---

## 5. 推奨する Entra グループ設計

最初にグループ設計を決めておくと、SCIM とロール割り当てが安定します。

例：

```text
anthropic-claude-owner
anthropic-claude-admin
anthropic-claude-user
anthropic-claude-custom-engineering
anthropic-claude-custom-sales
anthropic-claude-enterprise-seat
```

Claude 公式ドキュメントでは、ロールやシートごとに IdP グループを作成し、少なくとも 1 人の admin または owner を含めること、すべてのユーザーをロールベースのグループに入れることが推奨されています。また、Entra ID からの SCIM 変更は一定間隔で同期されるため、即時反映されない場合があります。([Claude ヘルプセンター][5])

ただし、**Primary Owner は SCIM のグループマッピングでは割り当てできません**。Claude 公式ドキュメントでは、Primary Owner は SCIM reconciliation の対象外で、手動で移管する必要があると説明されています。一方で、Primary Owner も SSO 強制の対象外になるわけではありません。([Claude ヘルプセンター][5])

また、Microsoft 公式ドキュメントでは、アプリ割り当てにおけるグループはネストされたグループにカスケードしないと説明されています。つまり、Entra ID 側で Claude アプリにグループを割り当てる場合、**ネストされたグループを前提にしない**設計が安全です。([Microsoft Learn][6])

---

## 6. 導入手順の全体像

推奨手順は以下です。

1. 事前設計
2. Claude 側でドメイン検証
3. Claude / WorkOS の SSO 設定フローを開始
4. Entra ID に Claude Enterprise Application を作成
5. SAML SSO を設定
6. パイロットユーザー／グループを割り当て
7. SSO ログインをテスト
8. SCIM プロビジョニングを設定
9. Claude 側でプロビジョニングモードとグループマッピングを設定
10. SCIM 同期とログインを検証
11. SSO 強制を有効化
12. 運用監視、証明書更新、ユーザー変更対応を行う

---

## 7. 手順 1：事前設計

まず、以下を決めます。

| 設計項目            | 内容                                                |
| --------------- | ------------------------------------------------- |
| 対象ドメイン          | 例：`example.co.jp`                                 |
| SSO の email 属性  | 通常は Entra の `mail` を使うのが安全です。ただし実環境の属性値を確認してください。 |
| SCIM の email 属性 | SSO と完全一致させます。                                    |
| SSO 対象ユーザー      | 最初はパイロットユーザー数名に限定します。                             |
| SCIM 対象グループ     | パイロット用グループから開始します。                                |
| 管理者グループ         | Owner/Admin を失わないよう、管理者を明示的に含めます。                 |
| ロールマッピング        | Owner、Admin、User、Custom などを Entra グループに対応させます。    |
| シート管理           | 契約形態に応じた seat type を確認します。                        |
| 既存アカウント         | Free/Pro/Team/Max など、同じ会社ドメインで使っている既存アカウントを確認します。 |

Microsoft 公式のプロビジョニング計画ガイドでも、いきなり全社展開せず、テスト環境または小さなユーザーサブセットで検証してから拡大することが推奨されています。([Microsoft Learn][8])

---

## 8. 手順 2：Claude 側でドメインを検証する

Claude 管理画面で、Identity and access または Organization and access に進み、SSO で利用する会社ドメインを追加します。その後、表示された TXT レコードを DNS に登録します。

設定例のイメージは以下です。

```text
Type: TXT
Host / Name: @
Value: anthropic-domain-verification-xxxxxxxx
```

TXT レコードの値は大文字小文字を区別します。DNS の反映には時間がかかることがあるため、すぐに検証できない場合でも、値、Host/Name、ドメイン、DNS 反映状況を確認してください。([Claude ヘルプセンター][3])

ドメイン検証後、必要に応じて **Restrict organization creation** を有効化できます。Claude 公式ドキュメントでは、この設定により、検証済みドメインのユーザーが新しい Claude / Console 組織や個人アカウントを作成することを防げると説明されています。([Claude ヘルプセンター][3])

---

## 9. 手順 3：Claude / WorkOS の SSO 設定フローを開始する

Claude 管理画面の Identity and access または Organization and access から SSO 設定を開始します。Claude 公式情報では、Team / Enterprise では `claude.ai` 側の管理画面、Console では Console 側の管理画面から設定を行う流れが説明されています。画面名やパスは公式ドキュメント内でも Identity and access / Organization and access の表記があるため、実画面では「SSO」「Identity」「Organization」「Access」関連の設定を確認してください。([Claude ヘルプセンター][2])

この設定フローの中で、Entra ID に入力する以下の値を取得します。

| Claude / WorkOS から取得する値          | Entra ID 側で入力する場所                 |
| -------------------------------- | --------------------------------- |
| Entity ID                        | Identifier                        |
| ACS URL                          | Reply URL                         |
| Federation Metadata XML のアップロード先 | Claude / WorkOS 側                 |
| SCIM Tenant URL                  | Entra Provisioning の Tenant URL   |
| SCIM Secret Token                | Entra Provisioning の Secret Token |

Claude 公式の Microsoft Entra ID 手順では、これらの設定値は WorkOS setup flow の中で提供されると説明されています。([Claude ヘルプセンター][2])

---

## 10. 手順 4：Entra ID に Claude Enterprise Application を作成する

Microsoft Entra 管理センターで、Enterprise Application を作成します。

Claude 公式手順では、Entra Admin Center で Enterprise applications に進み、New application から Claude を検索し、ギャラリーに Claude がある場合はそれを使用し、見つからない場合は独自アプリを作成すると説明されています。独自アプリの場合は、名前を Claude などにし、**Integrate any other application you don’t find in the gallery** を選びます。([Claude ヘルプセンター][2])

Microsoft 公式ドキュメントでも、ギャラリーにないアプリは Non-gallery application として作成し、SAML SSO を設定する流れが説明されています。([Microsoft Learn][9])

---

## 11. 手順 5：SAML SSO を設定する

Entra の Claude アプリで、Single sign-on から SAML を選択します。

主な設定は以下です。

| Entra ID の項目            | 入力内容                                           |
| ----------------------- | ---------------------------------------------- |
| Identifier / Entity ID  | Claude / WorkOS から取得した Entity ID               |
| Reply URL / ACS URL     | Claude / WorkOS から取得した ACS URL                 |
| Sign-on URL             | `https://claude.ai/login`                      |
| Attributes & Claims     | email claim を設定。通常は `user.mail` または SCIM と同じ属性 |
| Federation Metadata XML | Entra からダウンロードし、Claude / WorkOS 側にアップロード       |

Claude 公式の Entra ID 手順では、SAML の Basic SAML Configuration に Entity ID と Reply URL を入力し、Sign-on URL に `https://claude.ai/login` を設定し、Attributes & Claims で email claim を `user.mail` または SCIM と同じ属性にするよう説明されています。([Claude ヘルプセンター][2])

ここで最も重要なのは、**SAML SSO で Claude に送る email と、SCIM で Claude に同期する email を完全一致させること**です。Claude 公式のトラブルシューティングでは、Claude は email を主な識別子として使うため、SAML と SCIM で異なるメール属性を使うと、ログイン不能、個人アカウントに入ってしまう、Claude Code の認証失敗などが起きると説明されています。([Claude ヘルプセンター][10])

---

## 12. 手順 6：パイロットユーザー／グループを Entra アプリに割り当てる

SAML SSO をテストする前に、Entra の Enterprise Application にユーザーまたはグループを割り当てます。

Microsoft 公式ドキュメントでは、Enterprise Application の Users and groups から Add user/group を行い、対象ユーザーまたはグループをアプリに割り当てる手順が説明されています。([Microsoft Learn][6])

Claude 公式手順でも、Claude アプリにアクセスさせるユーザーまたはグループを割り当て、割り当てられた人だけがプロビジョニングされ、SSO でアクセスできると説明されています。([Claude ヘルプセンター][2])

最初は、以下のようなパイロット構成が安全です。

```text
anthropic-claude-pilot-sso
  - IT 管理者 1
  - Claude 管理者 1
  - 一般ユーザー 1〜3 名
```

この段階では、まだ全社ユーザーを割り当てないことを推奨します。

---

## 13. 手順 7：SSO ログインをテストする

パイロットユーザーで、Claude のログイン画面から SSO を試します。

確認項目は以下です。

| 確認項目                 | 期待結果                                             |
| -------------------- | ------------------------------------------------ |
| Claude で SSO ログインできる | Entra ID の認証画面にリダイレクトされる                         |
| Entra ID で認証できる      | MFA や条件付きアクセスが期待どおり動く                            |
| Claude に戻れる          | SAML 応答後、Claude ワークスペースに入れる                      |
| 正しい組織に入る             | 個人アカウントや Free アカウントではなく Enterprise 組織に入る         |
| email が一致する          | Entra の SAML claim と Claude 側のユーザー email が一致している |

Claude 公式手順でも、テストユーザーが SSO を完了し、正しい組織ワークスペースに入れることを確認するよう説明されています。([Claude ヘルプセンター][2])

---

## 14. 手順 8：SCIM プロビジョニングを Entra ID で設定する

SSO が動作したら、SCIM を設定します。

Entra の Claude Enterprise Application で、Provisioning に進みます。

主な設定は以下です。

| Entra ID の項目        | 設定内容                                    |
| ------------------- | --------------------------------------- |
| Provisioning Mode   | Automatic                               |
| Tenant URL          | Claude / WorkOS から取得した SCIM Tenant URL  |
| Secret Token        | Claude / WorkOS から取得した Secret Token     |
| Test Connection     | 成功することを確認                               |
| Scope               | 通常は Sync only assigned users and groups |
| Provisioning Status | On                                      |
| Attribute Mappings  | email が SAML と一致するように設定                 |

Claude 公式の Entra ID 手順では、Provisioning Mode を Automatic にし、WorkOS setup flow で提供された Tenant URL と Secret Token を入力し、Test Connection を実行し、Mappings で email 属性が SSO の email claim と同じであることを確認するよう説明されています。([Claude ヘルプセンター][2])

WorkOS 公式の Entra SCIM 手順でも、Directory Sync Endpoint と Bearer Token を Entra の Tenant URL / Secret Token に入力し、Test Connection、Save、Provisioning Status On、Scope を Sync only assigned users and groups にする手順が説明されています。([WorkOS][11])

---

## 15. 手順 9：SCIM の属性マッピングを確認する

特に重要なのは、メール属性です。

Entra ID では、ユーザーに複数のメール関連属性があります。

```text
userPrincipalName
mail
proxyAddresses
otherMails
```

Claude 公式のトラブルシューティングでは、SCIM がある属性を送り、SAML が別の属性を送ると、Claude 側で同一ユーザーとして認識できず、アクセスエラーや個人アカウントへの遷移が発生すると説明されています。([Claude ヘルプセンター][10])

推奨は、以下のように **SAML と SCIM を同じ属性に統一する**ことです。

```text
SAML email claim: user.mail
SCIM emails[type eq "work"].value: mail
SCIM userName: mail または SAML email と同じ値
```

ただし、実際の Entra テナントで `mail` が空のユーザーがいる場合は注意が必要です。WorkOS 公式ドキュメントでは、クラウド管理ユーザーでは Entra が Exchange の `mail` 属性から email を取得するため、設定されていない場合は UPN など既知のメール属性を `emails[type eq "work"].value` にマッピングする必要があると説明されています。([WorkOS][11])

---

## 16. 手順 10：Claude 側でプロビジョニングモードを設定する

Claude 管理画面で、ユーザープロビジョニングの設定を行います。

Claude 公式ドキュメントでは、プロビジョニングモードとして以下が説明されています。

| モード                   | 内容                                |
| --------------------- | --------------------------------- |
| Invite only           | 管理者が手動招待する                        |
| JIT                   | SSO 初回ログイン時にユーザーを作成する             |
| JIT + Group Mappings  | 初回ログイン時にグループに基づいてロール等を割り当てる       |
| SCIM                  | IdP の割り当てに基づき、自動で作成・削除する          |
| SCIM + Group Mappings | SCIM 同期に加えて、グループに基づきロールやシートを割り当てる |

Enterprise では、一般的に **SCIM + Group Mappings** が最も運用しやすい構成です。Entra のグループを変更すれば、Claude 側のメンバー追加、削除、ロール変更を自動化できます。([Claude ヘルプセンター][5])

ただし、Claude 公式ドキュメントでは、プロビジョニングモードを保存する前に、対象ユーザーが IdP 側で Anthropic / Claude アプリに正しく割り当てられていることを確認するよう強く注意しています。割り当てが不十分な状態で SCIM を有効化すると、ユーザーが削除または deprovision される可能性があります。([Claude ヘルプセンター][5])

---

## 17. 手順 11：グループマッピングを設定する

Claude 側で、Entra から同期されたグループを Claude のロールやシートに対応させます。

例：

| Entra グループ                            | Claude 側の扱い              |
| ------------------------------------- | ------------------------ |
| `anthropic-claude-owner`              | Owner                    |
| `anthropic-claude-admin`              | Admin                    |
| `anthropic-claude-user`               | User                     |
| `anthropic-claude-custom-engineering` | Custom role: Engineering |
| `anthropic-claude-custom-sales`       | Custom role: Sales       |

Claude 公式ドキュメントでは、ロールや seat type ごとに IdP グループを作成し、Claude 側の group mappings で対応づける流れが説明されています。また、すべてのユーザーをロールベースのグループに入れること、少なくとも 1 人の admin または owner を含めることが推奨されています。([Claude ヘルプセンター][5])

カスタムロールを使う場合は、さらに注意が必要です。Claude 公式ドキュメントでは、Custom role は Enterprise の機能であり、チャット、Claude Code、Web search、Connectors、管理権限などの機能アクセスを細かく制御できると説明されています。ただし、Custom role は、そのユーザーのロールが Custom に設定されている場合にのみ効果があります。([Claude ヘルプセンター][12])

---

## 18. 手順 12：SCIM 同期を検証する

SCIM 設定後、以下を確認します。

| 確認場所                         | 確認内容                              |
| ---------------------------- | --------------------------------- |
| Entra Provisioning           | Test Connection が成功している           |
| Entra Provisioning Logs      | ユーザー作成、更新、グループ同期が成功している           |
| Entra Users and groups       | 対象ユーザー／グループが Claude アプリに割り当てられている |
| Claude Manage SCIM Directory | ユーザーやグループが同期されている                 |
| Claude Members               | ユーザーが正しいロール・シートで表示されている           |
| Claude ログイン                  | SSO で正しい Enterprise ワークスペースに入れる   |

Microsoft 公式ドキュメントでは、プロビジョニングログで SCIM 操作を確認でき、プロビジョニングサイクルの状態や同期対象数、エラーを確認できると説明されています。([Microsoft Learn][13])

Microsoft のプロビジョニングは初回同期に 20 分から数時間かかる場合があり、その後の増分同期は継続的に実行されます。非ギャラリー SCIM アプリでは、通常 40 分ごとに同期が実行されると説明されています。([Microsoft Learn][8])

また、Claude 公式ドキュメントでは、Microsoft Entra の変更は 40 分ごとに SCIM で push されると説明されています。([Claude ヘルプセンター][5])

---

## 19. 手順 13：SSO 強制を有効化する

パイロット検証後、問題がなければ Claude 側で SSO を必須化します。

Claude 公式ドキュメントでは、Require SSO for Claude / Console のトグルにより、ユーザーに SSO ログインを必須化できると説明されています。SSO を必須にしない場合、ユーザーは Continue with email でもログインできる可能性があります。([Claude ヘルプセンター][3])

SSO 強制前には、必ず以下を確認してください。

```text
- 管理者が SSO でログインできる
- 少なくとも 1 人以上の管理者が Claude 側で Owner/Admin 権限を維持している
- Entra アプリに対象ユーザーが割り当てられている
- SCIM のメール属性と SAML の email claim が一致している
- 既存の会社ドメインユーザーへの影響を把握している
- 連絡先、ヘルプデスク手順、復旧手順を用意している
```

Claude 公式ドキュメントでは、SSO 強制を有効化すると、検証済みドメインを持つ既存アカウントのユーザーが SSO アプリに追加されていない場合、既存の Free / Pro / Team / Max アカウントにアクセスできなくなる可能性があると説明されています。アカウント自体が削除されるわけではありませんが、SSO 経由でアクセスできない状態になります。([Claude ヘルプセンター][7])

---

## 20. メール属性不一致が最重要リスク

Claude + Entra + SCIM 構成で最も注意すべきリスクは、**SAML SSO と SCIM の email 不一致**です。

Claude 公式ドキュメントでは、Claude は email を主な識別子として使うため、SCIM で同期された email と SSO で送られる email が一致しないと、以下の問題が発生し得ると説明されています。

```text
- Enterprise アカウントに入れない
- 個人用 Free アカウントに入ってしまう
- account creation blocked になる
- Claude Code の認証に失敗する
- ghost seat のような状態が発生する
```

([Claude ヘルプセンター][10])

確認方法は以下です。

| 確認対象                | 確認場所                                                                              |
| ------------------- | --------------------------------------------------------------------------------- |
| SAML email claim    | Entra Enterprise Application → Single sign-on → Attributes & Claims               |
| SCIM email          | Entra Enterprise Application → Provisioning logs → `emails[type eq "work"].value` |
| Claude 側のユーザー email | Claude Members / SCIM Directory                                                   |
| 実ログインユーザー           | SSO ログイン後に入ったワークスペース                                                              |

修正する場合は、Entra の Provisioning → Attribute mappings で、`emails[type eq "work"].value` を SSO と同じ属性に合わせます。Claude 公式ドキュメントでは、通常は `mail` に合わせる例が説明されています。修正後は、プロビジョニングの再起動や再同期、必要に応じて不要アカウントや ghost seat の整理が必要になります。([Claude ヘルプセンター][10])

---

## 21. 運用時の監視ポイント

導入後は、以下を定期的に確認します。

| 項目                        | 確認内容                                 |
| ------------------------- | ------------------------------------ |
| Entra Provisioning logs   | SCIM の成功／失敗、属性更新、削除、エラー              |
| Entra Provisioning status | 同期が停止・隔離状態になっていないか                   |
| Claude SCIM Directory     | ユーザーとグループが期待どおり同期されているか              |
| Claude Members            | ロール、シート、Custom role が正しいか            |
| シート残数                     | 新規ユーザーが seat 不足で追加できない状態になっていないか     |
| SAML 証明書                  | 証明書の有効期限、ローテーション時の更新                 |
| 管理者権限                     | Owner/Admin が IdP グループ変更で失われていないか    |
| 退職者対応                     | Entra 側の無効化／割り当て解除が Claude に反映されているか |

Claude 公式ドキュメントでは、SCIM 同期のプレビューで追加、削除、変更を確認できること、メンバー同期とグループ同期の違い、手動同期の所要時間目安、CSV エクスポートや Manage SCIM での確認方法が説明されています。([Claude ヘルプセンター][14])

Microsoft 公式ドキュメントでは、プロビジョニングログでユーザー作成・更新・削除などの操作を確認でき、同期サイクルやエラー状態を監視できると説明されています。([Microsoft Learn][13])

---

## 22. 条件付きアクセスと MFA

Claude ログインに対して MFA や端末条件を適用したい場合は、Entra ID 側の Conditional Access を使う構成になります。

Microsoft 公式ドキュメントでは、条件付きアクセスは、対象ユーザー、グループ、アプリ、条件を指定し、MFA、認証強度、準拠デバイス、ハイブリッド参加デバイス、アプリ保護ポリシーなどを要求できる仕組みとして説明されています。また、Microsoft Entra と統合されたギャラリーアプリや非ギャラリーアプリも対象リソースとして選択できます。([Microsoft Learn][15])

推奨される考え方は以下です。

```text
Claude Enterprise Application
  - 対象：Claude 利用者グループ
  - 条件：社外アクセス、非準拠端末、リスクありサインインなど
  - 制御：MFA 必須、準拠デバイス必須、認証強度指定など
```

本番適用前には、レポート専用モードや小規模グループでの検証を行うのが安全です。

---

## 23. よくあるトラブルと対処

### 1. SSO ログイン後、Claude Enterprise ではなく個人アカウントに入る

最も疑うべき原因は、SAML の email と SCIM の email が一致していないことです。SAML の Attributes & Claims と、SCIM の Provisioning logs に記録された `emails[type eq "work"].value` を比較してください。([Claude ヘルプセンター][10])

### 2. `AADSTS50011` が出る

Microsoft 公式ドキュメントでは、`AADSTS50011` は SAML 応答の Reply URL が Entra 側に設定された Reply URL と一致しない場合に発生すると説明されています。Claude / WorkOS から取得した ACS URL と、Entra の Reply URL が完全一致しているか確認してください。([Microsoft Learn][16])

### 3. `AADSTS50105` が出る

Microsoft 公式ドキュメントでは、`AADSTS50105` はユーザーがアプリに割り当てられていない場合に発生すると説明されています。ユーザーを直接割り当てるか、割り当て済みグループに所属させる必要があります。ネストされたグループはサポートされないため注意してください。([Microsoft Learn][17])

### 4. SCIM の Test Connection が失敗する

Tenant URL または Secret Token が誤っている可能性があります。Claude / WorkOS の setup flow で取得した値を再確認してください。WorkOS 公式ドキュメントでは、Directory Sync Endpoint を Tenant URL に、Bearer Token を Secret Token に設定する手順が説明されています。([WorkOS][11])

### 5. ユーザーが Claude に追加されない

以下を確認してください。

```text
- Entra アプリにユーザーまたはグループが割り当てられているか
- Provisioning Scope が Sync only assigned users and groups の場合、対象が割り当てられているか
- Provisioning Status が On か
- Entra Provisioning logs にエラーが出ていないか
- Claude 側の seat が不足していないか
- ユーザーが role-based group に入っているか
- 同期待ち時間を考慮しているか
```

Claude 公式ドキュメントでは、seat が不足している場合、ユーザーの追加が完了しないことがあると説明されています。また、Microsoft 公式ドキュメントでは、初回同期に 20 分から数時間かかる場合があると説明されています。([Claude ヘルプセンター][18])

### 6. ロールが正しく反映されない

Entra 側のグループ所属、Claude 側の group mappings、SCIM 同期状況を確認します。Claude 公式ドキュメントでは、JIT の場合はログアウト／ログイン、SCIM の場合は同期実行または次回同期を待つことが案内されています。([Claude ヘルプセンター][5])

### 7. 管理者権限を失った

SCIM group mappings の設定ミスで Admin / Owner の割り当てが外れる可能性があります。Claude 公式ドキュメントでは、別の admin が修正するか、IdP グループを修正して同期する対応が説明されています。Primary Owner は SCIM グループマッピングでは割り当てできないため、手動で管理する必要があります。([Claude ヘルプセンター][5])

---

## 24. 本番移行チェックリスト

本番展開前に、以下を確認してください。

```text
[ドメイン]
□ 会社ドメインが Claude で Verified になっている
□ TXT レコードの値を記録している
□ Restrict organization creation の適用方針を決めている

[SSO]
□ Entra Enterprise Application が作成済み
□ SAML の Entity ID / ACS URL が Claude / WorkOS の値と一致している
□ Sign-on URL が設定されている
□ Federation Metadata XML を Claude / WorkOS 側に登録済み
□ email claim が決定済み
□ パイロットユーザーで SSO ログイン成功

[SCIM]
□ Tenant URL / Secret Token を設定済み
□ Test Connection 成功
□ Provisioning Status が On
□ Scope が意図どおり
□ SCIM email と SAML email が完全一致
□ Provisioning logs で成功を確認
□ Claude SCIM Directory でユーザー・グループを確認

[グループ・ロール]
□ Entra グループ設計が完了
□ ネストされたグループに依存していない
□ Admin / Owner グループに管理者が入っている
□ Primary Owner の手動管理方針を決めている
□ Custom role を使う場合はパイロットで検証済み

[シート]
□ 契約上の seat model を確認済み
□ seat 不足時の対応手順を決めている
□ 新規ユーザー追加時の seat 割り当てを確認済み

[運用]
□ Entra Provisioning logs の確認手順を用意
□ Claude 側の Manage SCIM / Members 確認手順を用意
□ SAML 証明書更新手順を用意
□ 退職者・異動者の運用フローを定義
□ SSO 強制前の復旧手順を用意
```

---

## 25. 不明または実環境で確認が必要な点

公式情報だけでは、以下は環境依存または契約依存のため断定できません。

| 項目                                         | 理由                                                                                                 |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| あなたの Entra テナントで Claude がギャラリーアプリとして表示されるか | Claude 公式手順では、見つかる場合はギャラリーアプリ、見つからない場合は独自アプリを作成すると説明されています。                                        |
| 実際に使うべき email 属性                           | Entra テナント内で `mail`、`userPrincipalName`、`proxyAddresses` などの値がどう整備されているかに依存します。                    |
| 契約上の seat type                             | Claude Enterprise の契約形態により、単一 Enterprise seat か、legacy seat type を含むかが異なります。                       |
| Claude 管理画面の正確な表示名                         | 公式ドキュメント上でも Identity and access / Organization and access など表記が分かれています。                            |
| Console 組織も同じ SSO / SCIM 対象にするか            | Claude Enterprise だけか、Anthropic Console も含めるかで parent organization や organization merge の検討が変わります。 |
| 実際の SCIM Tenant URL / Secret Token         | WorkOS setup flow 内で生成される値であり、公式ドキュメント上には固定値として掲載されていません。                                          |

---

## 26. 推奨構成まとめ

最終的な推奨構成は以下です。

```text
認証:
  Microsoft Entra ID + SAML SSO

ユーザー同期:
  Microsoft Entra ID Provisioning Service + SCIM 2.0

アプリ:
  Entra Enterprise Application: Claude

プロビジョニング範囲:
  Sync only assigned users and groups

メール属性:
  SAML email claim と SCIM emails[type eq "work"].value を完全一致

グループ:
  Entra グループで Claude のロール・シート・Custom role を管理

展開方式:
  1. パイロット
  2. SCIM 同期検証
  3. SSO 検証
  4. 既存アカウント影響確認
  5. SSO 強制
  6. 全社展開

運用:
  Entra Provisioning logs、Claude SCIM Directory、Members、seat 残数、SAML 証明書期限を定期確認
```

この構成であれば、ユーザーは Entra ID の認証基盤で Claude にログインでき、入退社・異動・ロール変更は Entra ID のグループ管理を起点に Claude Enterprise へ自動反映できます。

[1]: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/user-provisioning "What is automated app user provisioning in Microsoft Entra ID - Microsoft Entra ID | Microsoft Learn"
[2]: https://support.claude.com/en/articles/13917889-microsoft-entra-id-sso-setup "Microsoft Entra ID SSO setup | Claude Help Center"
[3]: https://support.anthropic.com/en/articles/13132885-setting-up-single-sign-on-sso "Set up single sign-on (SSO) | Claude Help Center"
[4]: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/how-provisioning-works "Understand how Application Provisioning in Microsoft Entra ID - Microsoft Entra ID | Microsoft Learn"
[5]: https://support.claude.com/en/articles/13133195-set-up-jit-or-scim-provisioning "Set up JIT or SCIM provisioning | Claude Help Center"
[6]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/assign-user-or-group-access-portal "Manage users and groups assignment to an application - Microsoft Entra ID | Microsoft Learn"
[7]: https://support.anthropic.com/en/articles/10276682-important-considerations-before-enabling-domain-capture-and-sso "Important considerations before enabling single sign-on (SSO) and JIT/SCIM provisioning | Claude Help Center"
[8]: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/plan-auto-user-provisioning "Plan an automatic user provisioning deployment for Microsoft Entra ID - Microsoft Entra ID | Microsoft Learn"
[9]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/add-application-portal-setup-sso-rpsts "Enable single sign-on for an enterprise application with a relying party security token service - Microsoft Entra ID | Microsoft Learn"
[10]: https://support.claude.com/en/articles/13917829-microsoft-entra-id-sso-scim-email-mismatch "Microsoft Entra ID SSO/SCIM email mismatch | Claude Help Center"
[11]: https://workos.com/docs/integrations/entra-id-scim "Entra ID SCIM (formerly Azure AD) – Integrations – WorkOS Docs"
[12]: https://support.anthropic.com/en/articles/9267276-roles-and-permissions "Roles and permissions | Claude Help Center"
[13]: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/check-status-user-account-provisioning "Report automatic user account provisioning from Microsoft Entra ID to Software as a Service (SaaS) applications - Microsoft Entra ID | Microsoft Learn"
[14]: https://support.claude.com/en/articles/14499648-how-scim-sync-works-for-enterprise-organizations "How SCIM sync works for Enterprise organizations | Claude Help Center"
[15]: https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview "Microsoft Entra Conditional Access: Zero Trust Policy Engine - Microsoft Entra ID | Microsoft Learn"
[16]: https://learn.microsoft.com/en-us/troubleshoot/entra/entra-id/app-integration/error-code-aadsts50011-reply-url-mismatch "Error AADSTS50011 - The reply URL specified in the request does not match the reply URLs configured for the application <GUID>. | Microsoft Learn"
[17]: https://learn.microsoft.com/en-us/troubleshoot/entra/entra-id/app-integration/error-code-aadsts50105-user-not-assigned-role "Error AADSTS50105 - The signed in user isn't assigned to a role for the application. | Microsoft Learn"
[18]: https://support.claude.com/en/articles/13393991-purchase-and-manage-seats-on-enterprise-plans "Purchase and manage seats on Enterprise plans | Claude Help Center"
