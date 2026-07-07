# Claude Enterprise × Microsoft Entra ID

# SAML SSO / SCIM プロビジョニング設計・設定手順

作成日：2026年7月7日
前提：Claude Enterprise を Microsoft Entra ID と連携し、ユーザーが Entra ID の認証で Claude Enterprise にログインでき、かつユーザー・グループ・ロール・シートを SCIM で自動管理できる状態を目指します。

本資料では、**ログイン認証は SAML SSO**、**ユーザー・グループ同期は SCIM** として設計します。SCIM はログイン認証の仕組みではなく、Microsoft Entra ID からアプリケーション側へユーザーやグループを作成・更新・削除するためのプロビジョニングの仕組みです。Microsoft 公式も、Microsoft Entra provisioning service は SCIM 2.0 を使ってユーザー・グループの provisioning / deprovisioning を自動化すると説明しています。([Microsoft Learn][1])

---

## 1. 全体像

Claude Enterprise と Microsoft Entra ID を連携する場合、機能は大きく 2 系統に分かれます。

```text
A. ログイン認証の流れ

利用者
  |
  | Claude にアクセス
  | 「Continue with SSO」などでログイン
  v
Claude / WorkOS
  |
  | SAML 認証要求
  v
Microsoft Entra ID
  |
  | ユーザー認証
  | MFA
  | 条件付きアクセス
  | サインインリスク評価など
  v
Claude Enterprise
  |
  | SAML の email claim を使ってユーザーを識別
  v
Claude Enterprise の組織ワークスペースへログイン
```

```text
B. ユーザー・グループ同期の流れ

Microsoft Entra ID
  |
  | SCIM 2.0
  | ユーザー作成
  | ユーザー更新
  | ユーザー削除 / 無効化
  | グループ同期
  | グループメンバーシップ同期
  v
WorkOS SCIM endpoint
  |
  v
Claude Enterprise
  |
  | Members
  | SCIM groups
  | Roles
  | Seat tiers
  | Custom role access
```

Claude 公式の Microsoft Entra ID セットアップ手順も、Entra 側で Claude を Enterprise Application として追加し、SAML SSO を設定し、SCIM provisioning を設定し、people / groups を割り当て、最後に検証する流れになっています。([Claudeヘルプセンター][2])

---

## 2. 最終的な推奨構成

推奨構成は以下です。

```text
Identity Provider:
  Microsoft Entra ID

Claude 側:
  Claude Enterprise

SSO:
  SAML 2.0

Provisioning:
  SCIM 2.0

SCIM 接続先:
  Claude 管理画面の WorkOS setup flow で表示される SCIM endpoint

Entra アプリ:
  Claude 用 Enterprise Application

プロビジョニングスコープ:
  Sync only assigned users and groups

アクセス制御:
  Entra ID のユーザー / グループ割り当て
  Entra ID の Conditional Access
  Claude 側の SCIM + group mappings

ユーザー識別キー:
  SAML email claim と SCIM emails[type eq "work"].value を完全一致させる
```

Claude 公式は、Entity ID、Reply URL / ACS URL、SCIM credentials は WorkOS setup flow で提供されると説明しています。また、SCIM を使う場合は WorkOS setup guide に従い、WorkOS から取得した値を IdP の Anthropic application に入力する流れです。([Claudeヘルプセンター][2])

---

## 3. 重要な前提

### 3.1 SCIM は「ログイン」ではない

SCIM は、ユーザーが Claude にログインするための認証方式ではありません。SCIM は、Entra ID から Claude 側へ「このユーザーを追加する」「このユーザーを削除する」「このグループに所属している」「このユーザーの属性を更新する」といった情報を同期するための仕組みです。

ログインそのものは、SAML SSO で行います。Microsoft Entra ID の SSO では、ユーザーは Microsoft Entra の資格情報で認証され、アプリケーションにアクセスします。Microsoft 公式は、SSO によりユーザーが 1 つの資格情報でサインインし、割り当てられたアプリケーションを利用できると説明しています。([Microsoft Learn][3])

### 3.2 Claude では WorkOS が関係する

Claude の SSO / SCIM 設定では WorkOS が関係します。実務上は、Claude 管理画面から WorkOS setup flow に進み、SAML 用の Entity ID / ACS URL、SCIM 用の endpoint / token などを取得し、それらを Entra ID 側に設定します。WorkOS 公式ドキュメントでも、Entra ID SAML では WorkOS が ACS URL と Entity ID を提供し、Entra の Reply URL / Identifier に入力すると説明されています。([WorkOS][4])

SCIM についても、WorkOS 公式ドキュメントでは、WorkOS Dashboard の Endpoint を Entra ID の Tenant URL に、Bearer Token を Secret Token に入力し、Test Connection を実行する流れが説明されています。([WorkOS][5])

---

## 4. 事前確認事項

導入前に、以下を確認します。

| 項目              | 確認内容                                                                                                       |
| --------------- | ---------------------------------------------------------------------------------------------------------- |
| Claude 契約       | Claude Enterprise であること                                                                                    |
| Claude 管理権限     | Organization settings / Identity and access / Organization and access を操作できる Owner または Primary Owner 相当の権限 |
| Entra ID 権限     | Enterprise Application、SAML SSO、Provisioning を設定できる権限                                                      |
| Entra ID ライセンス  | グループベースのアプリ割り当てや SCIM provisioning を使う前提で、必要な Entra ID P1 / P2 条件を確認                                       |
| DNS 管理権限        | 会社ドメインの TXT レコードを追加できること                                                                                   |
| 対象ドメイン          | Claude にログインさせるメールドメイン                                                                                     |
| 既存 Claude アカウント | Free / Pro / Team / Max など、同一会社ドメインの既存アカウント有無                                                              |
| メール属性           | Entra の `mail`、`userPrincipalName`、`proxyAddresses`、`otherMails` のどれを正とするか                                 |
| グループ設計          | Claude 利用者、Owner、Admin、User、Custom role、seat tier 用グループ                                                    |
| シート設計           | 現在の Enterprise 契約が単一 Enterprise seat か、既存の seat type を含むか                                                  |
| 検証方法            | パイロットユーザーとパイロットグループで段階的に検証すること                                                                             |

Microsoft 公式では、グループベースのアプリ割り当てには Microsoft Entra ID P1 または P2 が必要であり、入れ子グループ、つまり nested group memberships は現在サポートされていないと説明されています。([Microsoft Learn][6])

---

## 5. Claude の parent organization とドメイン検証

Claude の SSO / SCIM 設定では、**parent organization** の考え方が重要です。Claude 公式では、ドメイン検証は parent organization レベルで行われ、複数の Claude / Console 組織を同じ parent organization に紐づけて、ドメイン検証や SSO 設定を共有できると説明されています。一方で、1 つの parent organization に紐づけられる Identity Provider は 1 つだけです。([Claudeヘルプセンター][7])

Claude Enterprise だけを 1 組織で使う場合、この設計は比較的単純です。Claude Enterprise と Claude Console、または複数の Claude 組織を同じ parent organization 配下で管理する場合は、SCIM directory sync と group mappings の設計が特に重要になります。Claude 公式では、group mappings を有効化すると、parent 配下のどの組織にどのユーザーを provision するか、またどのロールで provision するかを制御できると説明されています。([Claudeヘルプセンター][7])

---

## 6. ドメイン検証

SSO を設定する前に、Claude 側で会社ドメインを検証します。Claude 公式では、ドメイン検証の TXT レコードは root domain に存在する必要があり、値は `anthropic-domain-verification-` で始まる文字列で、完全一致かつ大文字小文字を区別すると説明されています。([Claudeヘルプセンター][8])

イメージは以下です。

```text
Type:
  TXT

Host / Name:
  @

Value:
  anthropic-domain-verification-xxxxxxxxxxxx
```

DNS に TXT レコードを追加後、Claude 管理画面で検証状態が Verified になることを確認します。ドメインを削除して再追加した場合は新しい検証値が生成されるため、DNS に登録済みの値と Claude 側の現在値が一致しているか確認します。([Claudeヘルプセンター][8])

ドメイン検証後、Claude 側で **Restrict organization creation** を有効化できます。この設定により、検証済みドメインを使った新しい Claude / Console 組織や個人アカウントの作成を防止できます。([Claudeヘルプセンター][7])

---

## 7. メール属性設計

Claude + Entra ID + SCIM 構成では、**メール属性の一致が最重要ポイント**です。

Claude 公式は、SCIM が送る email と SSO が送る email が異なると、Claude は同一ユーザーとして識別できず、アクセスがブロックされると説明しています。SCIM email は Entra の Enterprise applications → Claude SCIM app → Provisioning logs の `emails[type eq "work"].value` で確認し、SSO email は Enterprise applications → Claude app → Single sign-on → Attributes & Claims の email claim で確認します。([Claudeヘルプセンター][9])

推奨は以下です。

```text
SAML email claim:
  user.mail

SCIM emails[type eq "work"].value:
  mail

SCIM userName:
  SAML email claim と同じ値に合わせる
```

ただし、すべての Entra テナントで `mail` が正しく設定されているとは限りません。WorkOS 公式では、cloud-managed users では Entra ID が Exchange の `mail` 属性から email を取得するため、`mail` が設定されていない場合は UPN など既知のメール属性を `emails[type eq "work"].value` に mapping する必要があると説明されています。([WorkOS][5])

実務上の判断基準は以下です。

| 状況                             | 推奨                                                 |
| ------------------------------ | -------------------------------------------------- |
| `mail` が全ユーザーで正しく設定されている       | SAML も SCIM も `mail` / `user.mail` に統一             |
| `mail` が空のユーザーがいる              | SAML と SCIM の両方を、実際にメールアドレスとして使える同一属性に統一           |
| `userPrincipalName` がメール形式ではない | `userPrincipalName` を使わず、`mail` など実メール属性を使う        |
| エイリアスや旧メールが混在している              | どの値を Claude の正規 email とするか決定し、SAML と SCIM で完全一致させる |

---

## 8. グループ設計

Entra ID 側では、Claude 用に専用グループを作ることを推奨します。グループ名は Claude 公式でも必須命名規則はないものの、`anthropic-claude-` や `anthropic-console-` のような接頭辞を付けると識別しやすいと説明されています。([Claudeヘルプセンター][10])

例：

```text
anthropic-claude-owner
anthropic-claude-admin
anthropic-claude-user
anthropic-claude-custom-engineering
anthropic-claude-custom-sales
anthropic-claude-seat-enterprise
anthropic-claude-seat-chat
anthropic-claude-seat-chat-code
```

基本方針は以下です。

| グループ                        | 用途                               |
| --------------------------- | -------------------------------- |
| `anthropic-claude-owner`    | Claude Owner ロール割り当て             |
| `anthropic-claude-admin`    | Claude Admin ロール割り当て             |
| `anthropic-claude-user`     | 一般ユーザー割り当て                       |
| `anthropic-claude-custom-*` | 部門別・用途別の Custom role 管理          |
| `anthropic-claude-seat-*`   | seat type が複数ある契約での seat tier 管理 |

Claude 公式では、group mappings を使う場合、すべてのユーザーをロールベースのグループに割り当てる必要があり、少なくとも 1 人、できれば設定者自身を Admin または Owner に map されるグループに含める必要があると説明されています。([Claudeヘルプセンター][10])

Entra ID のアプリ割り当てでは nested group membership がサポートされないため、Claude アプリに割り当てるグループは、ユーザーを直接メンバーとして含む構成にします。([Microsoft Learn][6])

---

## 9. Claude のロールとシート

Claude Enterprise で使うロールとシートは、契約形態により異なります。Claude 公式の provisioning guide では、Enterprise では Owner、Admin、User、Custom が利用でき、seat type は契約形態により Premium / Standard、Chat / Chat + Claude Code、または Enterprise になります。([Claudeヘルプセンター][10])

| 契約形態                                            | ロール                        | seat type                |
| ----------------------------------------------- | -------------------------- | ------------------------ |
| Seat-based Enterprise plan                      | Owner, Admin, User, Custom | Premium, Standard        |
| Usage-based Enterprise plan with two seat types | Owner, Admin, User, Custom | Chat, Chat + Claude Code |
| Usage-based Enterprise plan single seat type    | Owner, Admin, User, Custom | Enterprise               |

新しい Enterprise 契約では単一 Enterprise seat モデルが中心で、既存契約では Chat / Chat + Claude Code や Standard / Premium が残っている場合があります。Claude 公式の seat 管理ドキュメントでは、Chat / Chat + Claude Code と Standard / Premium は新規 Enterprise 契約では利用できない legacy seat type と説明されています。([Claudeヘルプセンター][11])

Custom role は Enterprise plan の機能です。Claude 公式では、Custom role により chat、Claude Code、Claude Cowork、web search、connectors、管理権限などの機能アクセスをグループ単位で制御でき、Custom role はメンバーのロールが “Custom” に設定されている場合のみ有効に働くと説明されています。([Claudeヘルプセンター][12])

---

## 10. Primary Owner の扱い

Primary Owner は特別扱いです。

Claude 公式では、Primary Owner は SCIM reconciliation から除外され、Primary Owner の membership と role は保持されます。ただし、この例外は単一の Primary Owner のみに適用され、Owner や Admin には適用されません。また、Primary Owner は SCIM group mappings では割り当てられず、Organization settings > Members から手動で移管する必要があります。([Claudeヘルプセンター][10])

重要なのは、Primary Owner は SCIM reconciliation の例外ではありますが、SSO enforcement の例外ではないことです。Primary Owner のメールが SSO enforced domain に属している場合、その Primary Owner も SSO で認証する必要があります。([Claudeヘルプセンター][10])

---

## 11. 既存 Claude アカウントへの影響

会社ドメインで既に Free / Pro / Team / Max などの Claude アカウントを使っているユーザーがいる場合、SSO 強制時の影響を確認する必要があります。

Claude 公式では、既存 Free / Pro / Team / Max アカウントのユーザーが SSO application に追加されている場合、その既存アカウントへのアクセスは維持され、Team / Enterprise plan account と既存アカウントを切り替えられると説明されています。一方、SSO application に追加されていないユーザーについては、Require SSO for Claude が有効でない場合は Continue with email で既存アカウントにアクセスできますが、Require SSO for Claude が有効な場合は既存アカウントにアクセスできなくなります。アカウント自体は削除されません。([Claudeヘルプセンター][7])

本番で SSO を強制する前に、Domain memberships で検証済みドメインに紐づく既存 Claude / Console アカウントを確認し、必要なユーザーを SSO application に追加するか、利用者へ事前周知します。([Claudeヘルプセンター][7])

---

## 12. 推奨導入順序

推奨する導入順序は以下です。

```text
1. 要件整理
2. Claude 側の parent organization と対象ドメインを確認
3. Claude 側でドメイン検証
4. Entra ID に Claude Enterprise Application を作成
5. SAML SSO を設定
6. SCIM provisioning を設定
7. Entra ID でパイロットユーザー / グループを割り当て
8. SAML email claim と SCIM email mapping を確認
9. Claude 側で SCIM directory sync を有効化
10. 必要に応じて group mappings を有効化
11. Claude 側の sync preview / Manage SCIM / Members を確認
12. パイロットユーザーで SSO ログインを検証
13. 対象グループを段階的に拡大
14. Require SSO for Claude を有効化
15. 運用監視を開始
```

Claude 公式の Microsoft Entra ID 手順は、Enterprise Application の追加、SAML SSO 設定、SCIM provisioning 設定、people / groups 割り当て、verify の順序で構成されています。([Claudeヘルプセンター][2])

---

## 13. 手順 1：要件整理

最初に、以下を決めます。

| 設計項目        | 決める内容                                              |
| ----------- | -------------------------------------------------- |
| 対象組織        | Claude Enterprise だけか、Claude Console も対象に含めるか      |
| 対象ドメイン      | 例：`example.co.jp`                                  |
| SSO 方式      | SAML SSO                                           |
| SCIM 方式     | Entra ID Provisioning → WorkOS SCIM endpoint       |
| 正規 email 属性 | `mail`、`userPrincipalName` など、SAML と SCIM で同一にする属性 |
| ロール管理       | Owner / Admin / User / Custom をどの Entra グループで制御するか |
| seat 管理     | 契約形態に応じて seat tier をマッピングするか                       |
| 初期対象        | IT 管理者、Claude 管理者、一般パイロットユーザー                      |
| SSO 強制時期    | パイロット後、既存アカウント影響確認後に実施                             |
| 復旧方法        | SSO 設定ミス、管理者権限喪失、email mismatch 時の対応               |

---

## 14. 手順 2：Claude 側でドメインを検証する

Claude の管理画面で Organization and access または Identity and access に進み、対象ドメインを追加します。画面上に表示された TXT レコードを DNS に登録し、Claude 側で Verified になることを確認します。

確認ポイントは以下です。

```text
- TXT レコードが root domain に登録されている
- www などのサブドメインではなく対象ドメインに登録されている
- 値が anthropic-domain-verification- で始まる
- 値が完全一致している
- 大文字小文字が一致している
- ドメインを再追加した場合、新しい検証値に更新している
```

Claude 公式は、TXT レコードの値は完全一致・大文字小文字区別であり、1 文字でも違うと Pending のままになると説明しています。([Claudeヘルプセンター][8])

---

## 15. 手順 3：Entra ID に Claude Enterprise Application を作成する

Microsoft Entra admin center で、Claude 用の Enterprise Application を作成します。

基本操作は以下です。

```text
Microsoft Entra admin center
  → Entra ID
  → Enterprise applications
  → New application
  → Claude を検索
  → 表示される場合は Claude を選択
  → 表示されない場合は Create your own application
  → Integrate any other application you don't find in the gallery を選択
  → アプリ名を Claude などにする
```

Claude 公式の Entra ID 手順では、Claude をギャラリーで検索し、利用可能なら選択、見つからない場合は独自アプリケーションを作成するよう説明されています。([Claudeヘルプセンター][2])

Microsoft 公式でも、Enterprise Application は Entra ID > Enterprise apps > All applications > New application から追加でき、ギャラリーには SSO や automated user provisioning に対応した多数のアプリが含まれると説明されています。([Microsoft Learn][13])

---

## 16. 手順 4：SAML SSO を設定する

Entra ID の Claude アプリで、Single sign-on から SAML を選択します。

```text
Enterprise applications
  → Claude
  → Single sign-on
  → SAML
```

設定項目は以下です。

| Entra ID 項目             | 入力内容                                        |
| ----------------------- | ------------------------------------------- |
| Identifier / Entity ID  | Claude / WorkOS setup flow で表示される Entity ID |
| Reply URL / ACS URL     | Claude / WorkOS setup flow で表示される ACS URL   |
| Sign-on URL             | `https://claude.ai/login`                   |
| Attributes & Claims     | email claim を設定                             |
| Federation Metadata XML | Entra からダウンロードし、Claude / WorkOS 側へ登録        |

Claude 公式の Entra ID 手順では、Basic SAML Configuration に Entity ID と Reply URL を入力し、Sign-on URL に `https://claude.ai/login` を設定し、Attributes & Claims で email claim を `user.mail` または SCIM と同じ属性にするよう説明されています。([Claudeヘルプセンター][2])

WorkOS 公式でも、WorkOS が提供する ACS URL を Entra の Reply URL、Entity ID を Entra の Identifier に設定すると説明されています。([WorkOS][4])

---

## 17. 手順 5：SAML の Attributes & Claims を確認する

SAML の Attributes & Claims で最も重要なのは email claim です。

推奨例：

```text
Claim name:
  http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress

Source attribute:
  user.mail
```

ただし、重要なのは `user.mail` を使うことそのものではなく、**SCIM が送る email と完全一致すること**です。Claude 公式は、SCIM が 1 つの属性から email を取得し、SSO が別の属性から email を送る場合、わずかな差でもアクセスがブロックされると説明しています。([Claudeヘルプセンター][9])

---

## 18. 手順 6：Entra の Federation Metadata XML を Claude / WorkOS 側へ登録する

SAML 設定後、Entra ID 側で Federation Metadata XML をダウンロードします。その後、Claude / WorkOS の SSO setup flow に戻り、metadata XML を登録します。

Microsoft 公式の SAML SSO 手順でも、Enterprise Application の SAML 設定画面で signing certificate や federation metadata に関する情報を取得し、アプリケーション側に設定する流れが説明されています。([Microsoft Learn][14])

---

## 19. 手順 7：SCIM provisioning を Entra ID で設定する

Entra ID の Claude アプリで、Provisioning を開きます。

```text
Enterprise applications
  → Claude
  → Provisioning
  → Get Started
  → Provisioning Mode: Automatic
```

設定項目は以下です。

| Entra ID 項目         | 入力内容                                            |
| ------------------- | ----------------------------------------------- |
| Provisioning Mode   | Automatic                                       |
| Tenant URL          | WorkOS / Claude setup flow で表示される SCIM Endpoint |
| Secret Token        | WorkOS / Claude setup flow で表示される Bearer Token  |
| Test Connection     | 成功することを確認                                       |
| Mappings            | ユーザー・グループ mapping を有効化                          |
| Scope               | Sync only assigned users and groups             |
| Provisioning Status | On                                              |

WorkOS 公式の Entra ID SCIM 手順では、Endpoint を Tenant URL に、Bearer Token を Secret Token に入力し、Test Connection を実行し、Provisioning Status を On、Scope を Sync only assigned users and groups にする流れが説明されています。([WorkOS][5])

---

## 20. 手順 8：SCIM の attribute mappings を確認する

Entra の Provisioning → Mappings で、ユーザー属性とグループ属性の mapping を確認します。

特に確認する項目は以下です。

| SCIM target attribute          | 推奨 source attribute        |
| ------------------------------ | -------------------------- |
| `emails[type eq "work"].value` | SAML email claim と同じ属性     |
| `userName`                     | SAML email claim と同じ値に合わせる |
| `externalId`                   | Entra の `objectId`         |
| `name.givenName`               | `givenName`                |
| `name.familyName`              | `surname`                  |
| `active`                       | Entra 側の有効状態に基づく値          |

WorkOS 公式では、Attribute Mapping で `objectId` を `externalId` に map することを確認するよう説明されています。([WorkOS][5])

email mapping を変更した場合は、保存だけで終わらせず、Entra の Provisioning overview で **Restart provisioning** を実行し、full provisioning sync を完了させます。Claude 公式の email mismatch 手順では、incremental sync では不十分で、Restart provisioning が必要と説明されています。([Claudeヘルプセンター][9])

---

## 21. 手順 9：Entra ID でユーザー / グループを割り当てる

Entra ID の Claude Enterprise Application に、Claude を利用させるユーザーまたはグループを割り当てます。

```text
Enterprise applications
  → Claude
  → Users and groups
  → Add user/group
  → 対象ユーザーまたはグループを選択
  → Assign
```

Microsoft 公式は、Enterprise Application への group-based assignment には Entra ID P1 または P2 が必要で、nested group memberships はサポートされないと説明しています。([Microsoft Learn][6])

最初は、以下のようなパイロットグループを使うのが安全です。

```text
anthropic-claude-pilot
  - Entra 管理者
  - Claude Primary Owner / Owner
  - Claude Admin
  - 一般ユーザー 1〜3 名
```

---

## 22. 手順 10：Claude 側で provisioning mode を設定する

Claude 側の Organization and access または Identity and access で、User provisioning を設定します。

Claude 公式では、provisioning options として Invite only、JIT、SCIM directory sync が説明されています。JIT は IdP app に割り当てられたユーザーが初回ログイン時に provision される方式で、SCIM directory sync はユーザーがログインする前に IdP の割り当てに基づいて自動 provision / deprovision される方式です。([Claudeヘルプセンター][10])

| モード                   | 内容                                |
| --------------------- | --------------------------------- |
| Invite only           | Claude 側で手動招待・手動削除                |
| JIT                   | SSO 初回ログイン時にユーザーを作成               |
| JIT + group mappings  | 初回ログイン時に IdP グループに基づきロール・シートを割り当て |
| SCIM directory sync   | IdP の割り当てに基づき自動作成・自動削除            |
| SCIM + group mappings | IdP グループに基づき、組織・ロール・シートを自動管理      |

Claude Enterprise の運用では、通常 **SCIM + group mappings** が最も管理しやすい構成です。グループに入れれば Claude に追加され、グループから外せば削除され、ロールや seat tier もグループに基づいて反映できます。Claude 公式でも、SCIM + group mappings は、mapped group に基づいて、parent org 配下の対象組織へ適切なロールで provision し、ロールや seat type の変更を group membership に基づいて自動反映すると説明されています。([Claudeヘルプセンター][10])

---

## 23. 手順 11：Claude 側で group mappings を設定する

Claude 側で Enable group mappings を有効化し、Entra から同期されたグループを Claude のロールや seat type に対応づけます。

例：

| Entra グループ                            | Claude 側の割り当て      |
| ------------------------------------- | ------------------ |
| `anthropic-claude-owner`              | Owner              |
| `anthropic-claude-admin`              | Admin              |
| `anthropic-claude-user`               | User               |
| `anthropic-claude-custom-engineering` | Custom             |
| `anthropic-claude-custom-sales`       | Custom             |
| `anthropic-claude-seat-enterprise`    | Enterprise seat    |
| `anthropic-claude-seat-chat`          | Chat               |
| `anthropic-claude-seat-chat-code`     | Chat + Claude Code |

Claude 公式では、group mappings を使う場合、すべてのユーザーをロールベースのグループに割り当てる必要があります。seat tier グループへの割り当ては任意ですが、single-seat Enterprise 以外では seat type group を設定できます。single-seat Enterprise の場合は seat type mapping は適用されず、利用可能な seat があれば全 provisioned users が Enterprise seat に割り当てられます。([Claudeヘルプセンター][10])

group mappings を保存する前に、対象ユーザーが Entra ID 側で Anthropic / Claude application に割り当てられていることを必ず確認します。Claude 公式は、ユーザーが適切に割り当てられる前に Save changes すると、ユーザーが organization から deprovision される可能性があると警告しています。([Claudeヘルプセンター][10])

---

## 24. 手順 12：SCIM sync preview と初回同期を確認する

Claude 側で SCIM や group mappings を有効化すると、同期プレビューが表示される場合があります。プレビューでは、追加・削除・変更されるユーザー数を確認します。

確認ポイントは以下です。

```text
- 想定外に大量のユーザーが削除されないか
- Owner / Admin が削除または User に降格されないか
- Primary Owner は適切に設定されているか
- 全ユーザーが少なくとも 1 つの role-based group に所属しているか
- seat 不足が発生していないか
- Console など child organization への影響がないか
```

Claude 公式は、sync preview の数字が想定と違う場合、例えば実際の退職者数よりもはるかに多い removals が表示される場合は、sync をキャンセルして IdP directory と group mappings を確認するよう説明しています。([Claudeヘルプセンター][15])

---

## 25. 手順 13：SSO ログインを検証する

パイロットユーザーで Claude にアクセスし、SSO ログインを確認します。

確認項目は以下です。

| 確認項目                     | 期待結果                                              |
| ------------------------ | ------------------------------------------------- |
| Claude ログイン画面            | SSO ログインを選択できる                                    |
| Entra ID へのリダイレクト        | Microsoft Entra の認証画面へ遷移する                        |
| MFA / Conditional Access | Entra 側のポリシーが適用される                                |
| Claude への戻り              | SAML 応答後に Claude に戻る                              |
| 組織                       | Enterprise organization に入る                       |
| ユーザー email               | SCIM で provision された email と一致する                  |
| ロール                      | group mappings どおりの Owner / Admin / User / Custom |
| seat                     | 契約・mapping どおりの seat type                         |

Claude 公式の Entra ID 手順でも、verify の段階で、SCIM を有効化している場合は provisioning logs を確認し、test user が SSO を完了して organization workspace に入ることを確認するよう説明されています。([Claudeヘルプセンター][2])

---

## 26. 手順 14：Require SSO for Claude を有効化する

パイロット検証が完了した後、Claude 側で Require SSO for Claude を有効化します。

有効化前の確認項目は以下です。

```text
- Primary Owner が SSO でログインできる
- Owner / Admin が SSO でログインできる
- Entra 側で対象ユーザー / グループが Claude アプリに割り当てられている
- SAML email claim と SCIM email が完全一致している
- 既存 Free / Pro / Team / Max アカウントへの影響を確認済み
- Domain memberships を確認済み
- 社内周知が完了している
- ヘルプデスク向けの復旧手順がある
```

Claude 公式は、Require SSO for Claude が有効な場合、SSO application に追加されていない既存 Free / Pro / Team / Max ユーザーは既存アカウントへアクセスできなくなると説明しています。([Claudeヘルプセンター][7])

---

## 27. SCIM 同期タイミング

Entra ID からの SCIM 変更は即時反映とは限りません。Claude 公式は、Microsoft Entra は SCIM changes を 40 分ごとに push するため、変更が表示されるまで遅延があると説明しています。([Claudeヘルプセンター][10])

その後、Claude Enterprise organization は WorkOS の update events を裏側で 1 分ごとにポーリングし、queue で処理します。通常は数分で完了しますが、高トラフィック時には数時間かかることがあります。([Claudeヘルプセンター][15])

同期の考え方は以下です。

| 操作                 | 反映の考え方                                                            |
| ------------------ | ----------------------------------------------------------------- |
| Entra グループにユーザー追加  | 次回 SCIM push 後、Claude 側に反映                                        |
| Entra グループからユーザー削除 | 次回 SCIM push 後、Claude 側で deprovision                              |
| ロール用グループ変更         | SCIM 同期または Claude 側 manual sync 後に反映                              |
| seat mapping 変更    | 既存メンバーには manual sync が必要な場合あり                                     |
| email mapping 変更   | Entra 側で Restart provisioning が必要                                 |
| 即時確認               | Entra の Provision on demand、Claude の Sync / Check for updates を検討 |

Claude 公式は、group mappings による seat provisioning や seat roles の更新時、既存メンバーは自動 resync されないため、manual sync を実行して変更を適用する必要があると説明しています。([Claudeヘルプセンター][15])

---

## 28. Entra ID 側の Conditional Access

Claude へのログインに MFA、端末準拠、ネットワーク条件、サインインリスクなどを適用する場合は、Microsoft Entra Conditional Access を使用します。

Microsoft 公式では、Conditional Access は複数のシグナルを組み合わせてポリシー判断を行い、組織のポリシーを強制する Zero Trust policy engine と説明されています。([Microsoft Learn][16])

例：

```text
Policy name:
  Require MFA for Claude Enterprise

Users:
  Claude 利用者グループ

Target resources:
  Claude Enterprise Application

Conditions:
  任意
  例：社外アクセス、非準拠端末、リスクありサインイン

Grant controls:
  Require multifactor authentication
  Require compliant device
  Require authentication strength
```

本番適用前は、対象をパイロットグループに限定し、必要に応じて report-only 相当の検証運用を行います。

---

## 29. ユーザーライフサイクル運用

### 29.1 入社者を追加する

```text
1. Entra ID にユーザーを作成
2. mail など正規 email 属性を確認
3. Claude 用グループに直接追加
4. Entra の provisioning logs を確認
5. Claude の Manage SCIM / Members を確認
6. ユーザーが SSO でログインできることを確認
```

SCIM + group mappings の場合、対象グループに追加されたユーザーは、Entra の SCIM push 後に Claude 側へ provision されます。

### 29.2 異動者のロールを変更する

```text
1. Entra ID で旧ロールグループから削除
2. 新ロールグループへ追加
3. 必要に応じて seat type グループも変更
4. Entra の provisioning logs を確認
5. Claude 側で Sync / Check for updates を実行
6. Members でロール・seat を確認
```

Claude 公式では、SCIM の場合、Sync をクリックして即時同期するか、自動同期サイクルを待つことでロール反映を確認できると説明されています。([Claudeヘルプセンター][10])

### 29.3 退職者を削除する

```text
1. Entra ID でアカウントを無効化、または Claude 用グループから削除
2. Entra の provisioning logs で deprovision を確認
3. Claude Members から削除されていることを確認
4. 必要に応じて audit logs を確認
```

Claude 公式では、Enterprise organization で SCIM provisioning を使用している場合、Identity Provider から削除されたメンバーは Claude から自動的に削除されると説明されています。([Claudeヘルプセンター][17])

---

## 30. 監視ポイント

導入後は以下を定期的に確認します。

| 監視対象                      | 確認内容                                              |
| ------------------------- | ------------------------------------------------- |
| Entra Provisioning logs   | user create / update / delete、group update、失敗イベント |
| Entra Provisioning status | Provisioning が On のままか、停止していないか                   |
| Entra Sign-in logs        | SSO 成功 / 失敗、MFA、Conditional Access 結果             |
| Claude Manage SCIM        | WorkOS 側に同期されている users / groups                   |
| Claude Members            | ロール、seat、所属状態                                     |
| Claude Groups             | SCIM groups、custom role、spend limits              |
| Claude sync preview       | 想定外の大量削除がないか                                      |
| seat 残数                   | 新規ユーザーが seat 不足で追加失敗していないか                        |
| SAML 証明書                  | 証明書期限、metadata 更新手順                               |
| Primary Owner             | 手動管理されているか、SSO ログイン可能か                            |

Microsoft 公式では、provisioning logs に identity、action、source system、target system、status などが表示され、provisioning event のトラブルシューティングに利用できると説明されています。([Microsoft Learn][18])

Claude 公式では、SCIM sync 状態の確認方法として、member list の CSV export と、Organization and access から Manage SCIM を開いて WorkOS integration の record を確認する方法が説明されています。([Claudeヘルプセンター][15])

---

## 31. トラブルシューティング

### 31.1 SSO 後に Enterprise organization に入れない

最初に確認するべきは、SAML email claim と SCIM email の不一致です。

確認場所：

```text
SCIM email:
  Entra Admin Center
    → Enterprise applications
    → Claude SCIM app
    → Provisioning
    → Provisioning logs
    → Modified attributes
    → emails[type eq "work"].value

SSO email:
  Entra Admin Center
    → Enterprise applications
    → Claude app
    → Single sign-on
    → Attributes & Claims
    → email claim
```

Claude 公式は、SCIM と SSO の email が異なる場合、正しい組織に入れない、個人アカウントに入る、ghost account が発生する、out-of-seats error が出るなどの問題が発生し得ると説明しています。([Claudeヘルプセンター][9])

### 31.2 email mapping を直したのに反映されない

Entra の SCIM attribute mapping を直しただけでは、既存ユーザーの email が更新されない場合があります。Claude 公式は、email mapping 修正後は incremental sync ではなく full sync が必要で、Provisioning overview から Restart provisioning を実行する必要があると説明しています。([Claudeヘルプセンター][9])

対応：

```text
1. Entra Admin Center → Enterprise applications → Claude SCIM app
2. Provisioning → Edit provisioning → Attribute mappings
3. emails[type eq "work"].value を修正
4. userName mapping も必要に応じて修正
5. Save
6. Provisioning overview → Restart provisioning
7. Provisioning logs で email が更新されたことを確認
8. Claude 側で Manage SCIM / Members を確認
```

### 31.3 AADSTS50011 が出る

AADSTS50011 は、SAML authentication で Reply URL が一致しない場合に発生します。Microsoft 公式は、SAML request の `AssertionConsumerServiceURL` と Microsoft Entra ID に設定された Reply URL が一致していることを確認するよう説明しています。([Microsoft Learn][19])

対応：

```text
- Claude / WorkOS 側の ACS URL を確認
- Entra の Reply URL と完全一致しているか確認
- 末尾スラッシュ、http/https、大小文字、余分な空白を確認
- 複数 Reply URL がある場合、実際の SAML request と一致する URL を確認
```

### 31.4 AADSTS50105 が出る

AADSTS50105 は、ユーザーがアプリケーションへのアクセスを許可されていない場合に発生します。Microsoft 公式は、ユーザーがアプリケーションに直接割り当てられているか、アプリケーションに割り当てられたグループに属している必要があり、nested group はサポートされないと説明しています。([Microsoft Learn][20])

対応：

```text
- Entra Enterprise Application → Users and groups を確認
- ユーザーが直接割り当てられているか確認
- ユーザーが割り当て済みグループの直接メンバーか確認
- nested group 経由だけになっていないか確認
- Assignment required の設定を確認
```

### 31.5 ユーザーが Claude に provision されない

確認項目：

```text
- Entra の Claude app にユーザーまたはグループが割り当てられているか
- ユーザーが nested group ではなく直接メンバーか
- Provisioning Status が On か
- Scope が Sync only assigned users and groups か
- Provisioning logs にエラーがないか
- SCIM email が空ではないか
- Claude 側の seat が不足していないか
- role-based group に所属しているか
- group mappings 保存前に必要ユーザーを割り当て済みか
```

Claude 公式では、対象ユーザーが Directory に表示されているのに Claude members として追加されない場合、利用可能な seat 数を確認し、必要なら seat を追加してから Sync now を実行するよう説明されています。([Claudeヘルプセンター][10])

### 31.6 ロールが正しく反映されない

確認項目：

```text
- ユーザーが正しい Entra グループに所属しているか
- そのグループが Claude 側で正しい role に mapped されているか
- Custom role を使う場合、ユーザーの role が Custom になっているか
- seat tier mapping が必要な契約か
- Claude 側で Sync を実行したか
```

Claude 公式は、ユーザーが正しいロールで provision されない場合、IdP のグループ割り当て、Claude 側の group mapping、JIT の再ログイン、SCIM の Sync または自動同期サイクルを確認するよう説明しています。([Claudeヘルプセンター][10])

### 31.7 Admin / Owner 権限を失った

group mappings を有効化した際、設定者自身が Admin または Owner に map されるグループに入っていないと、User に降格される可能性があります。

対応：

```text
- 別の Admin / Owner に Claude 側でロールを戻してもらう
- Entra 側で自分を Admin / Owner に map されるグループへ追加する
- SCIM の場合、Claude 側で Sync してもらうか自動同期を待つ
```

Claude 公式も、group mappings を設定したユーザーが Admin / Owner role に map されるグループにいない場合、権限が User に downgraded されると説明しています。([Claudeヘルプセンター][10])

---

## 32. 本番展開チェックリスト

### 32.1 ドメイン・親組織

```text
□ parent organization の構成を確認した
□ Claude Enterprise だけか、Console も含むか確認した
□ 1 parent organization に 1 IdP であることを理解した
□ 対象ドメインを Claude で追加した
□ DNS に TXT レコードを追加した
□ ドメインが Verified になった
□ Restrict organization creation の適用方針を決めた
□ Domain memberships で既存アカウントを確認した
```

### 32.2 Entra SAML SSO

```text
□ Claude 用 Enterprise Application を作成した
□ Identifier / Entity ID を設定した
□ Reply URL / ACS URL を設定した
□ Sign-on URL を設定した
□ email claim を決めた
□ email claim が SCIM email と一致している
□ Federation Metadata XML を Claude / WorkOS 側に登録した
□ パイロットユーザーで SSO ログインに成功した
```

### 32.3 Entra SCIM

```text
□ Provisioning Mode を Automatic にした
□ Tenant URL を設定した
□ Secret Token を設定した
□ Test Connection に成功した
□ User mapping を確認した
□ Group mapping を確認した
□ emails[type eq "work"].value を確認した
□ userName mapping を確認した
□ objectId → externalId を確認した
□ Scope を Sync only assigned users and groups にした
□ Provisioning Status を On にした
□ Provisioning logs を確認した
```

### 32.4 Entra グループ

```text
□ Claude 用グループを作成した
□ nested group に依存していない
□ Owner group に適切な管理者を入れた
□ Admin group に適切な管理者を入れた
□ User group に一般ユーザーを入れた
□ Custom role 用グループを作成した
□ seat type が必要な場合は seat group を作成した
□ パイロットグループから開始した
```

### 32.5 Claude provisioning / group mappings

```text
□ SCIM directory sync を有効化した
□ 必要に応じて Enable group mappings を有効化した
□ role-based group mappings を設定した
□ seat tier group mappings を設定した
□ すべての利用者が role-based group に所属している
□ Primary Owner を手動で正しく設定した
□ Primary Owner が SSO でログインできる
□ sync preview を確認した
□ 想定外の大量削除がない
□ seat 不足がない
```

### 32.6 本番移行

```text
□ 既存 Free / Pro / Team / Max アカウントへの影響を整理した
□ 利用者に SSO 移行を周知した
□ ヘルプデスク手順を用意した
□ 管理者の復旧手順を用意した
□ Require SSO for Claude を有効化した
□ 本番ユーザーで SSO ログインを確認した
□ Entra sign-in logs を確認した
□ Entra provisioning logs を確認した
□ Claude Members / Groups / Manage SCIM を確認した
```

---

## 33. 公式情報だけでは断定できない点

以下は、公式情報だけでは環境に対して断定できません。

| 項目                                                 | 状態                                                                                             |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Entra のギャラリーに Claude が必ず表示されるか                     | 不明。Claude 公式は、Claude が見つかる場合は選択し、見つからない場合は独自アプリを作成すると説明しています。                                  |
| 最終的に使うべき email 属性                                  | 不明。Entra テナント内の `mail`、`userPrincipalName`、Exchange 属性、オンプレ AD 同期状態に依存します。                     |
| 契約上の seat model                                    | 不明。単一 Enterprise seat か、Chat / Chat + Claude Code、Standard / Premium を含む既存契約かは契約確認が必要です。       |
| Claude 管理画面の表示名                                    | 一部不明。公式ドキュメント上でも Organization and access、Identity and access など文脈により表記が分かれます。                  |
| Claude Console も同じ IdP / parent organization に含めるか | 不明。Claude Enterprise だけを対象にするか、Console も対象にするかで parent organization と group mappings 設計が変わります。 |
| 実際の SCIM Tenant URL / Secret Token                 | 不明。Claude / WorkOS setup flow 内で生成される値であり、固定値ではありません。                                          |
| SSO 強制の実施日時                                        | 不明。社内周知、既存アカウント影響確認、パイロット結果に基づき決定する必要があります。                                                    |

---

## 34. 推奨する最終設計

最終設計は以下を推奨します。

```text
ログイン:
  Microsoft Entra ID + SAML SSO

ユーザー同期:
  Microsoft Entra ID Provisioning Service + SCIM 2.0

Claude 側プロビジョニング:
  SCIM directory sync + group mappings

Entra provisioning scope:
  Sync only assigned users and groups

メール属性:
  SAML email claim と SCIM emails[type eq "work"].value を完全一致

グループ:
  Claude 専用 Entra グループを作成
  nested group に依存しない
  role-based group を必須化

管理者:
  Primary Owner は手動管理
  Owner / Admin は group mappings で管理
  少なくとも複数名の管理者を Admin / Owner group に直接所属させる

シート:
  契約形態を確認
  single Enterprise seat の場合は seat type mapping 不要
  既存 seat type がある場合は seat group mapping を設計

セキュリティ:
  Entra Conditional Access で MFA や端末条件を適用
  Claude 側で Require SSO for Claude を段階的に有効化
  Restrict organization creation を検討

運用:
  Entra provisioning logs
  Entra sign-in logs
  Claude Manage SCIM
  Claude Members
  Claude Groups
  seat 残数
  SAML 証明書期限
  を定期確認
```

この構成により、ユーザーは Microsoft Entra ID の認証で Claude Enterprise にログインし、IT 管理者は Entra ID のグループ管理を起点に Claude のユーザー追加、削除、ロール変更、シート割り当てを統制できます。

[1]: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/how-provisioning-works?utm_source=chatgpt.com "How Application Provisioning works in Microsoft Entra ID"
[2]: https://support.claude.com/en/articles/13917889-microsoft-entra-id-sso-setup?utm_source=chatgpt.com "Microsoft Entra ID SSO setup - Claude Help Center"
[3]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/what-is-single-sign-on?utm_source=chatgpt.com "What is single sign-on (SSO) in Microsoft Entra ID?"
[4]: https://workos.com/docs/integrations/entra-id-saml?utm_source=chatgpt.com "Entra ID SAML (formerly Azure AD) – Integrations"
[5]: https://workos.com/docs/integrations/entra-id-scim?utm_source=chatgpt.com "Entra ID SCIM (formerly Azure AD) – Integrations"
[6]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/assign-user-or-group-access-portal?utm_source=chatgpt.com "Manage users and groups assignment to an application"
[7]: https://support.claude.com/en/articles/10276682-important-considerations-before-enabling-single-sign-on-sso-and-jit-scim-provisioning "Important considerations before enabling single sign-on (SSO) and JIT/SCIM provisioning | Claude Help Center"
[8]: https://support.claude.com/en/articles/13132885-set-up-single-sign-on-sso?utm_source=chatgpt.com "Set up single sign-on (SSO) | Claude Help Center"
[9]: https://support.claude.com/en/articles/13917829-microsoft-entra-id-sso-scim-email-mismatch "Microsoft Entra ID SSO/SCIM email mismatch | Claude Help Center"
[10]: https://support.claude.com/en/articles/13133195-set-up-jit-or-scim-provisioning "Set up JIT or SCIM provisioning | Claude Help Center"
[11]: https://support.claude.com/en/articles/13393991-purchase-and-manage-seats-on-enterprise-plans?utm_source=chatgpt.com "Purchase and manage seats on Enterprise plans"
[12]: https://support.claude.com/en/articles/13930452-manage-custom-roles-on-enterprise-plans?utm_source=chatgpt.com "Manage custom roles on Enterprise plans | Claude Help Center"
[13]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/add-application-portal?utm_source=chatgpt.com "Quickstart: Add an enterprise application - Microsoft Entra ID"
[14]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/add-application-portal-setup-sso?utm_source=chatgpt.com "Enable SAML single sign-on for an enterprise application"
[15]: https://support.claude.com/en/articles/14499648-how-scim-sync-works-for-enterprise-organizations "How SCIM sync works for Enterprise organizations | Claude Help Center"
[16]: https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview?utm_source=chatgpt.com "Microsoft Entra Conditional Access: Zero Trust Policy Engine"
[17]: https://support.claude.com/en/articles/13133750-manage-members-on-team-and-enterprise-plans?utm_source=chatgpt.com "Manage members on Team and Enterprise plans"
[18]: https://learn.microsoft.com/en-us/entra/identity/monitoring-health/concept-provisioning-logs?utm_source=chatgpt.com "User provisioning logs in Microsoft Entra ID"
[19]: https://learn.microsoft.com/en-us/troubleshoot/entra/entra-id/app-integration/error-code-aadsts50011-reply-url-mismatch?utm_source=chatgpt.com "The reply URL specified in the request does not match"
[20]: https://learn.microsoft.com/ja-jp/troubleshoot/entra/entra-id/app-integration/error-code-aadsts50105-user-not-assigned-role?utm_source=chatgpt.com "エラー AADSTS50105 - サインインしているユーザーが ..."
