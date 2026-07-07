# Claude Enterprise × Microsoft Entra ID Governance / SAML SSO / SCIM 導入ガイド

参照元は、Claude Help Center、Anthropic公式ページ、Microsoft Learnの公式情報に限定しています。公式情報から断定できない点は「不明」または「要確認」と記載します。

---

## 1. 目的と基本方針

Claude EnterpriseをMicrosoft Entra IDと連携する場合、役割は次の3つに分けて考えます。

| 領域           | 使用する機能                            | 目的                                                   |
| ------------ | --------------------------------- | ---------------------------------------------------- |
| ログイン         | **SAML SSO**                      | ユーザーが会社のEntra IDアカウントでClaudeへログインする                  |
| ユーザー・グループ同期  | **SCIM Provisioning**             | Entra IDからClaude Enterpriseへユーザー、グループ、ロール、シート情報を同期する |
| 申請・承認・期限・棚卸し | **Microsoft Entra ID Governance** | 誰にClaude利用権を与えるか、いつ見直すか、いつ削除するかを統制する                 |

SCIMはログイン処理そのものではありません。Microsoft Entra IDのSSOは、ユーザーがEntra IDで認証され、その結果をアプリへ渡す仕組みです。一方、Microsoft Entraのアプリケーションプロビジョニングは、SCIM 2.0 APIなどを使ってSaaSアプリ側のユーザーやグループを作成、更新、削除する仕組みです。([Microsoft Learn][1])

Claude公式のMicrosoft Entra ID手順でも、ClaudeをEntra Enterprise Applicationとして追加した後、**SAML SSO設定**、**SCIM Provisioning設定**、**ユーザー・グループ割り当て**の順に構成します。Claude側で使うEntity ID、Reply URL / ACS URL、SCIM credentialsは、ClaudeのIdentity and access設定内のWorkOSセットアップフローで提供されます。([Claude ヘルプセンター][2])

---

## 2. 推奨全体構成

```text
[人事システム / 社員マスタ / 入退社・異動情報]
        │
        ▼
[Microsoft Entra ID ユーザー]
        │
        ▼
[Microsoft Entra ID Governance]
  ├─ Access Package
  ├─ 承認ワークフロー
  ├─ 有効期限
  ├─ Access Review
  └─ Lifecycle Workflows
        │
        ▼
[Claude用Entraセキュリティグループ]
  ├─ GG-Claude-Enterprise-User
  ├─ GG-Claude-Enterprise-Admin
  ├─ GG-Claude-Enterprise-Owner
  └─ GG-Claude-Enterprise-Custom-*
        │
        ▼
[Enterprise Application: Claude]
  ├─ SAML SSO
  │    └─ Entra IDで認証し、Claudeへログイン
  │
  └─ SCIM Provisioning
       └─ Entra IDからClaude/WorkOSへユーザー・グループを同期
              │
              ▼
[Claude Enterprise]
  ├─ Verified Domain
  ├─ Require SSO
  ├─ SCIM directory sync
  ├─ Group Mapping
  ├─ Roles / Custom Roles
  └─ Seats / Usage / Admin controls
```

この構成では、Entra ID GovernanceがClaudeへ直接SCIM同期するのではなく、**Claudeアクセスを付与するEntraセキュリティグループへの所属を統制**します。そのグループをEntra Enterprise Applicationの割り当て対象にし、さらにClaude側のGroup Mappingでロールやシート種別へ対応付けます。

Microsoft Entitlement ManagementのAccess Packageでは、Microsoft Entraセキュリティグループ、Enterprise Application、SharePointサイトなどをリソースとして管理できます。また、Access Packageのポリシーでは、誰が要求できるか、誰が承認するか、アクセス期間をどうするかを定義できます。([Microsoft Learn][3])

---

## 3. 初心者向けの用語整理

| 用語                         | 意味                                                                                  |
| -------------------------- | ----------------------------------------------------------------------------------- |
| **IdP**                    | Identity Provider。認証元。今回の構成ではMicrosoft Entra ID。                                    |
| **SP**                     | Service Provider。認証される側。今回の構成ではClaude Enterprise。                                   |
| **SAML SSO**               | Entra IDで本人確認した結果をClaudeへ渡し、会社アカウントでログインさせる仕組み。                                     |
| **SCIM**                   | System for Cross-domain Identity Management。Entra IDからClaudeへユーザーやグループを同期する標準プロトコル。 |
| **Provisioning**           | Claude側にユーザーやグループを作成・更新すること。                                                        |
| **Deprovisioning**         | Claude側のアクセスを削除、無効化、またはアクセス不可にすること。                                                 |
| **Enterprise Application** | Entra管理センター上でSaaSアプリを連携管理する単位。Claude連携もここで管理する。                                     |
| **Access Package**         | Entra ID Governanceで使うアクセス権セット。申請、承認、有効期限、棚卸しをまとめて管理できる。                            |
| **Group Mapping**          | Entra IDのグループをClaude側のロール、シート種別、Custom roleに対応付ける設定。                                |
| **Primary Owner**          | Claude組織の最上位所有者。SCIMでは割り当てできず、手動管理が必要。                                              |

---

## 4. 前提条件

### 4.1 Claude側の前提

Claude公式のMicrosoft Entra ID手順では、前提としてClaude Team plan、Enterprise plan、または親組織を持つConsole organization、Claude側のOwner / Primary OwnerまたはConsole Admin、Microsoft Entra ID P1またはP2、Entra側のGlobal AdministratorまたはApplication Administratorが必要とされています。特にSCIM provisioningにはMicrosoft Entra ID P1またはP2が必要と記載されています。([Claude ヘルプセンター][2])

ただし、Claude公式のSCIM説明では、SCIM directory syncはEnterprise planおよび条件を満たすConsole organizationで利用可能で、Team planでは利用できないとされています。Team planの場合はSCIMではなくJIT provisioningを検討する構成になります。([Claude ヘルプセンター][4])

### 4.2 Microsoft Entra側の前提

Entra Enterprise Applicationを追加・設定するには、Microsoft Learn上ではCloud Application AdministratorまたはApplication Administratorなどの権限が必要です。SAML SSO設定ではCloud Application Administrator、Application Administrator、またはサービスプリンシパルの所有者が必要とされています。([Microsoft Learn][5])

Microsoft Entra ID Governance機能を利用する場合、機能ごとにライセンス要件があります。Microsoft公式では、Microsoft Entra ID GovernanceはEntra ID P1/P2顧客向けの高度なIDガバナンス機能群であり、Entitlement Management、Access Reviews、Lifecycle Workflowsなどの機能はMicrosoft Entra ID GovernanceまたはMicrosoft Entra Suiteなどで提供されるものがあります。([Microsoft Learn][6])

### 4.3 ドメイン・親組織の前提

ClaudeでSSOを設定するには、先にドメイン検証が必要です。Claude公式では、ドメイン検証は親組織レベルで行われ、1つの親組織にリンクされた複数のClaude/Console組織でSSO設定を共有できると説明されています。また、1つの親組織は1つのIdentity Providerにのみリンクできます。([Claude ヘルプセンター][7])

複数会社、複数Entraテナント、M&A後の複数IdP、ClaudeとConsoleの併用がある場合は、Claudeの親組織とIdP設計を先に確認してください。

---

## 5. 設計方針

## 5.1 アクセス管理の中心はEntraセキュリティグループにする

Claude Enterpriseでは、Entra IDのユーザーを個別にClaudeアプリへ割り当てることもできます。ただし、企業運用では個別割り当てではなく、**Entraセキュリティグループを中心に設計**する方が安全です。

推奨グループ例は次のとおりです。

| Entraグループ                                 | Claude側の想定用途            |
| ----------------------------------------- | ----------------------- |
| `GG-Claude-Enterprise-User`               | 一般利用者                   |
| `GG-Claude-Enterprise-Admin`              | Claude管理者               |
| `GG-Claude-Enterprise-Owner`              | Claude Owner            |
| `GG-Claude-Enterprise-Custom-Engineering` | 開発部門向けCustom role       |
| `GG-Claude-Enterprise-Custom-Sales`       | 営業部門向けCustom role       |
| `GG-Claude-Enterprise-Seat-Chat-Code`     | レガシーまたは複数シート種別契約でのシート制御 |
| `GG-Claude-Enterprise-Seat-Chat`          | レガシーまたは複数シート種別契約でのシート制御 |

Claude公式では、Group Mappingを使う場合、IdP側でロールごとのグループを作り、単一シートのEnterprise plan以外ではシート種別ごとのグループも作るよう説明されています。また、少なくとも自分自身をClaudeのOwner、またはConsoleのAdminへマップされるグループに入れる必要があります。([Claude ヘルプセンター][4])

Microsoft Entraのプロビジョニングでは、Scopeを「Sync only assigned users and groups」にした場合、アプリに割り当てられたグループのメンバーかどうかでプロビジョニング・デプロビジョニングされます。Microsoft公式では、割り当てられたグループはSecurityEnabledがTrueである必要があること、またネストされたグループのユーザーは読み取れず、明示的に割り当てられたグループの直接メンバーのみが対象になることが説明されています。([Microsoft Learn][8])

## 5.2 Access Packageでは「Claude用グループ」を付与する

Entra ID GovernanceのAccess PackageにはEnterprise Application自体も含められますが、ClaudeのロールやCustom roleをGroup Mappingで制御する場合は、Access Packageに**Claude用セキュリティグループのメンバーシップ**を含める設計が扱いやすいです。

例：

| Access Package                               | 含めるリソース                                   | 用途           |
| -------------------------------------------- | ----------------------------------------- | ------------ |
| Claude Enterprise - Standard User            | `GG-Claude-Enterprise-User`               | 一般利用者向け      |
| Claude Enterprise - Admin                    | `GG-Claude-Enterprise-Admin`              | Claude管理者向け  |
| Claude Enterprise - Owner                    | `GG-Claude-Enterprise-Owner`              | 限定されたOwner向け |
| Claude Enterprise - Engineering Custom       | `GG-Claude-Enterprise-Custom-Engineering` | 開発部門向け       |
| Claude Enterprise - Temporary Project Access | プロジェクト専用Claudeグループ                        | 期間限定利用       |

Entitlement Managementでは、Access Packageによって、アプリケーション、グループ、Teams、SharePointサイトなどへのアクセスを、複数段階承認、有効期限、定期レビュー付きで制御できます。また、属性ベースで自動割り当てし、属性が変わったら自動で削除することも可能です。([Microsoft Learn][3])

## 5.3 Enterprise Application側では割り当て必須にする

ClaudeへのアクセスをEntra側で確実に制限するには、Enterprise ApplicationのPropertiesで、アプリ割り当てが必要になる設定を確認します。Microsoft公式では、assignment requiredの場合、割り当てられたユーザーのみがアプリへサインインできると説明されています。([Microsoft Learn][9])

Claude公式のMicrosoft Entra ID手順でも、Users and groupsでClaudeへアクセスすべきユーザーまたはグループを割り当て、割り当てられたユーザー・グループだけがプロビジョニングされSSOを許可されると説明されています。([Claude ヘルプセンター][2])

---

## 6. 設定手順

## Step 0：導入前に決めること

設定作業の前に、次の項目を決めておきます。

| 項目              | 決める内容                                   |
| --------------- | --------------------------------------- |
| 対象者             | 全社員、特定部門、申請者のみ、開発者のみ、管理者のみなど            |
| ロール             | User、Admin、Owner、Custom                 |
| Primary Owner   | 誰をClaudeのPrimary Ownerにするか              |
| シート種別           | 契約が単一Enterprise seatか、複数seat typeを持つ契約か |
| 申請方式            | 自動付与、本人申請、上長承認、IT承認など                   |
| 有効期限            | 無期限、90日、180日、プロジェクト終了日など                |
| 棚卸し             | 月次、四半期、半期、年次など                          |
| 退職時処理           | グループ削除、Access Package削除、Entraユーザー無効化など  |
| 既存Claude個人アカウント | ドメインクレーム・移行対象があるか                       |
| 例外アカウント         | 緊急用管理者、サービスアカウント、外部ユーザーなど               |

Claude公式では、Primary OwnerはSCIM reconciliationの対象外で、SCIM group mappingsでは割り当てできず、手動で移譲する必要があります。一方で、Primary OwnerもSSO強制の対象にはなります。([Claude ヘルプセンター][4])

---

## Step 1：Claude側でドメイン検証を行う

ClaudeのOrganization and access設定、またはConsoleのIdentity and access設定から対象ドメインを追加します。Claude公式では、ドメイン検証のTXTレコード値は `anthropic-domain-verification-` で始まる文字列であり、DNSへ追加した後、通常は少し待って確認しますが、DNS変更はグローバル反映に24〜48時間かかる場合があると説明されています。([Claude ヘルプセンター][10])

作業イメージは次のとおりです。

1. Claude管理画面を開く
2. Organization and access / Identity and accessを開く
3. Domainsで対象ドメインを追加する
4. 表示されたTXTレコードをDNSに追加する
5. Claude側でVerified状態になることを確認する

ドメイン検証が完了した後、SSO設定へ進みます。Claude公式では、SSO設定時にテストを行い、Require SSOを有効化するとユーザーは「Continue with SSO」でログインする必要があると説明されています。SSO enforcementは、IdP側でユーザーが正しく割り当てられていない場合、ログイン不能につながる可能性があります。([Claude ヘルプセンター][10])

---

## Step 2：Entra IDにClaude Enterprise Applicationを作成する

Microsoft Entra管理センターで、Claude用のEnterprise Applicationを作成します。

Claude公式のMicrosoft Entra ID手順では、Entra Admin CenterでEnterprise applications → New applicationへ進み、ギャラリーで「Claude」を検索し、利用可能なら選択、なければCreate your own applicationで「Claude」という名前のnon-galleryアプリを作成すると説明されています。([Claude ヘルプセンター][2])

Microsoft Learnでも、Entra IDには事前統合済みのEnterprise Application Galleryがあり、Enterprise apps → All applications → New applicationからアプリを追加する流れが説明されています。([Microsoft Learn][5])

**不明:** すべてのEntraテナントでClaudeが常にギャラリーアプリとして表示されるかは、公式情報からは断定できません。Claude公式手順は「利用可能なら選択、なければ独自アプリを作成」という扱いです。([Claude ヘルプセンター][2])

---

## Step 3：Enterprise ApplicationのPropertiesを確認する

Claude Enterprise Applicationを作成したら、次の設定を確認します。

| 設定                                               |        推奨値 | 理由                            |
| ------------------------------------------------ | ---------: | ----------------------------- |
| Enabled for users to sign in?                    |        Yes | Claudeへサインインできる状態にする          |
| Assignment required? / User assignment required? |        Yes | 割り当てられたユーザーだけにClaudeアクセスを制限する |
| Visible to users?                                | 運用方針に応じて決定 | My Appsに表示するかを決める             |
| Owners                                           |     複数名を設定 | アプリ設定の属人化を防ぐ                  |

Microsoft公式では、Enabled for users to sign inがYesで、かつassignment requiredの場合、割り当てられたユーザーのみがサインイン可能です。Enabled for users to sign inがNoの場合、割り当てられていてもユーザーはサインインできません。([Microsoft Learn][9])

---

## Step 4：SAML SSOを設定する

ClaudeのIdentity and access設定でSSOセットアップフローを開始し、Entra側のSAML設定画面と並行して作業します。Claude公式では、Entity ID、Reply URL / ACS URL、SCIM credentialsはWorkOSセットアップフロー内で提供され、Supportへ問い合わせて取得するものではないと説明されています。([Claude ヘルプセンター][2])

Entra側では、Enterprise ApplicationのSingle sign-onからSAMLを選択します。Microsoft Learnでは、Enterprise ApplicationのSingle sign-on画面でSAMLを選択し、Basic SAML ConfigurationでReply URLやSign-on URLなどを設定する流れが説明されています。([Microsoft Learn][11])

Claude向けの主な設定は次のとおりです。

| Entra SAML項目            | 設定内容                                         |
| ----------------------- | -------------------------------------------- |
| Identifier / Entity ID  | Claude/WorkOSセットアップフローで表示された値                |
| Reply URL / ACS URL     | Claude/WorkOSセットアップフローで表示された値                |
| Sign-on URL             | `https://claude.ai/login`                    |
| email claim             | 原則 `user.mail`。SCIM側で使うメール属性と同じものにする         |
| Federation Metadata XML | EntraからダウンロードしてClaude/WorkOSセットアップフローへアップロード |

Claude公式では、Attributes & Claimsのemail claimは `user.mail`、またはSCIMで使う属性と同じものを使うよう説明されています。SCIM emailとSSO emailの属性は同一である必要があり、不一致はログイン失敗の一般的な原因です。([Claude ヘルプセンター][2])

---

## Step 5：SCIM Provisioningを設定する

Entra Enterprise ApplicationのProvisioningから、ClaudeへのSCIM同期を構成します。

Claude公式のMicrosoft Entra ID手順では、Provisioning → Get Startedへ進み、Provisioning ModeをAutomaticに設定し、WorkOSセットアップフローで取得したTenant URLとSecret Tokenを入力してTest Connectionを実行すると説明されています。([Claude ヘルプセンター][2])

設定項目は次のとおりです。

| Entra Provisioning項目 | 設定内容                                     |
| -------------------- | ---------------------------------------- |
| Provisioning Mode    | Automatic                                |
| Tenant URL           | Claude/WorkOSセットアップフローで表示されたTenant URL   |
| Secret Token         | Claude/WorkOSセットアップフローで表示されたSecret Token |
| Test Connection      | 成功することを確認                                |
| Mappings             | ユーザー・グループ・メール属性を確認                       |
| Scope                | 原則「Sync only assigned users and groups」  |
| Provisioning Status  | On                                       |

Microsoft公式では、Entra provisioning serviceはSCIM 2.0 endpointへ接続し、ユーザーやグループを作成、更新、削除します。また、属性マッピングでは、Entra IDとターゲットアプリの間でどの属性を流すか、どの属性でユーザー・グループを一意に照合するかを確認することが重要と説明されています。([Microsoft Learn][8])

**不明:** Claude Enterpriseの固定SCIM Tenant URL形式は、公式情報では公開されていません。実装時はClaude/WorkOSセットアップフローで表示されたTenant URLとSecret Tokenを使用します。([Claude ヘルプセンター][2])

---

## Step 6：Entraアプリにユーザー・グループを割り当てる

Enterprise ApplicationのUsers and groupsで、Claudeへアクセスさせたいユーザーまたはグループを割り当てます。Claude公式では、割り当てられたユーザー・グループだけがプロビジョニングされ、SSOを許可されると説明されています。([Claude ヘルプセンター][2])

Microsoft Learnでは、ユーザーやグループをEnterprise Applicationへ割り当てると、My Appsポータルにアプリが表示され、アプリロールがある場合は特定ロールも割り当てられると説明されています。また、グループをアプリへ割り当てた場合、割り当てはネストグループへカスケードしません。([Microsoft Learn][12])

推奨は、以下のようなグループをEnterprise Applicationへ割り当てることです。

```text
GG-Claude-Enterprise-User
GG-Claude-Enterprise-Admin
GG-Claude-Enterprise-Owner
GG-Claude-Enterprise-Custom-Engineering
GG-Claude-Enterprise-Custom-Sales
```

---

## Step 7：Claude側でGroup Mappingを設定する

SCIMでユーザー・グループを同期しただけでは、Claude側でどのロール・シート種別にするかを十分に制御できません。Claude側のUser provisioning設定でGroup Mappingを有効化し、Entra IDのグループをClaudeのロールやシート種別に対応付けます。

Claude公式では、Group Mapping利用時は、全ユーザーをロールベースのグループに割り当てる必要があります。Customロールにマップされたユーザーはデフォルト権限を持たず、Claude内でグループに割り当てられたCustom roleによってアクセス権が決まります。([Claude ヘルプセンター][4])

Group Mapping例：

| Entraグループ                                 | Claudeロール | 用途         |
| ----------------------------------------- | --------- | ---------- |
| `GG-Claude-Enterprise-Owner`              | Owner     | Claude組織管理 |
| `GG-Claude-Enterprise-Admin`              | Admin     | 日常管理       |
| `GG-Claude-Enterprise-User`               | User      | 一般利用       |
| `GG-Claude-Enterprise-Custom-Engineering` | Custom    | 開発部門向け機能制御 |
| `GG-Claude-Enterprise-Custom-Sales`       | Custom    | 営業部門向け機能制御 |

単一シートEnterpriseの場合、シート種別マッピングは不要です。Claude公式では、single-seat Enterpriseでは全プロビジョニング済みユーザーが利用可能なEnterprise seatに自動割り当てされると説明されています。複数シート種別を持つ契約では、シート種別グループのマッピングも検討します。([Claude ヘルプセンター][4])

---

## Step 8：Claude Custom Rolesを設計する

Claude EnterpriseではCustom Rolesを使って、チャット、Claude Code、Web search、Connectors、管理権限などの利用可否を細かく制御できます。Claude公式では、Custom Rolesはグループと連動し、Customに設定されたメンバーのアクセスは、所属グループに割り当てられたCustom roleによって決まると説明されています。([Claude ヘルプセンター][13])

設計例：

| Custom Role             | 想定権限                                                      |
| ----------------------- | --------------------------------------------------------- |
| Engineering Claude User | Claude Code、GitHub connector、技術系機能を許可                     |
| Sales Claude User       | Slack、Google Drive、Microsoft 365 connectorなど営業利用に必要な機能を許可 |
| Compliance Reviewer     | 一部管理画面を閲覧可能にし、設定変更は不可                                     |
| Claude Admin Delegate   | Identity & Accessなど特定管理領域のみ管理可能                           |

Claude公式では、SCIM同期グループはClaude側でリネームや削除ができず、メンバー管理はIdP側で行います。また、SCIMグループはCustom role assignmentsやspend limitsにも利用できます。([Claude ヘルプセンター][14])

---

## Step 9：Entra ID GovernanceでAccess Packageを作成する

Access Packageは、Claude利用権を「申請・承認・期限付き」で管理するために使います。Microsoft公式では、Access Packageはアクセスに必要なリソースの束であり、ポリシーによって誰が要求できるか、誰が承認するか、どれくらいの期間アクセスできるかを定義できると説明されています。([Microsoft Learn][3])

作成例：

| Access Package名                       | 付与するリソース                                  | ポリシー例                  |
| ------------------------------------- | ----------------------------------------- | ---------------------- |
| Claude Enterprise - User              | `GG-Claude-Enterprise-User`               | 本人申請、上長承認、180日         |
| Claude Enterprise - Admin             | `GG-Claude-Enterprise-Admin`              | IT責任者承認、90日、四半期レビュー    |
| Claude Enterprise - Owner             | `GG-Claude-Enterprise-Owner`              | セキュリティ責任者承認、短期間、厳格レビュー |
| Claude Enterprise - Engineering       | `GG-Claude-Enterprise-Custom-Engineering` | 部門属性または上長承認            |
| Claude Enterprise - Temporary Project | プロジェクト専用グループ                              | プロジェクト終了日に失効           |

属性ベースの自動割り当てを使う場合、Access Packageのautomatic assignment policyで、departmentやcost centerなどのユーザー属性に基づき、自動的に割り当てを追加・削除できます。Microsoft公式では、属性がルールに一致すると割り当てが追加され、一致しなくなると削除されると説明されています。([Microsoft Learn][15])

---

## Step 10：Access Reviewを設定する

Claude Enterpriseのような生成AIサービスは、利用範囲が広がりやすいため、定期的な棚卸しを設定します。

Microsoft公式では、Access Reviewsにより、グループメンバーシップ、Enterprise Applicationアクセス、ロール割り当てを定期的にレビューし、適切な人だけがアクセスを継続できるように管理できると説明されています。レビューは週次、月次、四半期、年次などの頻度で繰り返し設定できます。([Microsoft Learn][16])

推奨例：

| 対象                    |   レビュー頻度 | レビュアー       |
| --------------------- | -------: | ----------- |
| Claude一般利用者           | 半期または四半期 | 部門長         |
| Claude Custom role利用者 |      四半期 | 部門長 + AI管理者 |
| Claude Admin          |      四半期 | IT責任者       |
| Claude Owner          | 月次または四半期 | セキュリティ責任者   |
| 外部ユーザー                |       月次 | スポンサー       |

---

## Step 11：Lifecycle Workflowsを設計する

入社、異動、退職に合わせてClaudeアクセスを自動化する場合、Microsoft Entra ID GovernanceのLifecycle Workflowsを使います。Microsoft公式では、Lifecycle WorkflowsはJoiner、Mover、Leaverの3フェーズでEntraユーザーを管理するIdentity Governance機能と説明されています。([Microsoft Learn][17])

運用例：

```text
Joiner / 入社
  └─ 所属部署・職種に応じてClaude用Access Packageを自動付与
      └─ Entraセキュリティグループへ追加
          └─ Claude Enterprise Applicationへ割り当て
              └─ SCIMでClaudeへプロビジョニング

Mover / 異動
  └─ 部署属性変更
      └─ 旧Access Package削除、新Access Package付与
          └─ Claude側ロール・Custom roleがGroup Mappingで変化

Leaver / 退職
  └─ Access Package削除またはグループ削除
      └─ Claude Enterprise Applicationの対象外
          └─ SCIMでClaude側アクセスを無効化・削除相当へ
```

Microsoft公式では、Access Packageはライフサイクルワークフロー経由でも割り当て可能であり、Access Packageのポリシーによって適切なIDだけにアクセスを付与し、時間制限をかけることができます。([Microsoft Learn][3])

---

## 7. デプロビジョニングの考え方

Claude公式では、SCIM directory syncではIdPアプリから削除されたユーザーは自動的に削除され、SCIM + group mappingsではグループアクセスが取り消されると自動的に削除されると説明されています。([Claude ヘルプセンター][4])

Microsoft Entraの一般的なプロビジョニング仕様では、以前スコープ内だったユーザーが割り当て解除などでスコープ外になると、ターゲットシステムに対してdisable requestを送ります。また、ハード削除の場合やターゲットアプリの対応状況に応じてdelete requestが使われる場合があります。Microsoft公式では、unassignedになったユーザーに対してはdisable requestが送られ、その時点でプロビジョニングサービスはそのユーザーを管理しなくなると説明されています。([Microsoft Learn][8])

実装時は、次の観点で必ずテストしてください。

| テスト                          | 確認内容                       |
| ---------------------------- | -------------------------- |
| グループから削除                     | Claudeにログインできなくなるか         |
| Enterprise Application割り当て解除 | SCIM上どう反映されるか              |
| Entraユーザー無効化                 | Claude側で無効化または削除相当になるか     |
| Entraユーザー削除                  | Claude側表示、監査ログ、会話データの扱い    |
| Access Package期限切れ           | グループ削除、Claudeアクセス削除まで完了するか |

---

## 8. 同期タイミングとログ確認

Claude公式では、Microsoft EntraはSCIM変更を約40分ごとにプッシュするため、変更反映に遅延があると説明されています。さらにClaude Enterprise側はWorkOSの更新イベントを毎分ポーリングして処理し、通常は数分で完了するものの、高負荷時は数時間かかる可能性があります。([Claude ヘルプセンター][4])

Microsoft Entraのプロビジョニングは、初回サイクルの後、増分サイクルを継続的に実行します。Provisioningページでは現在のサイクル状況やProvisioning logsを確認でき、個別ユーザーの処理状況もログで確認できます。([Microsoft Learn][8])

確認場所：

| 場所                                          | 確認内容             |
| ------------------------------------------- | ---------------- |
| Entra Enterprise Application > Provisioning | プロビジョニング状態       |
| Entra Provisioning logs                     | 個別ユーザー・グループの同期成否 |
| Entra Sign-in logs                          | SAML SSOログイン成否   |
| Claude Organization settings > Members      | Claude側メンバー反映    |
| Claude Organization settings > Groups       | SCIMグループ反映       |
| Claude Manage SCIM                          | WorkOS側の保持情報     |
| Claude Sync / Check for updates             | 手動同期・同期プレビュー     |

Claude公式では、手動同期時にメンバー、グループ、または両方を選択して同期でき、同期プレビューでは追加、削除、変更されるメンバー数を確認できます。想定より削除数が多い場合は同期を中止し、IdPディレクトリやGroup Mappingを確認すべきです。([Claude ヘルプセンター][18])

---

## 9. Conditional Accessとセキュリティ制御

ClaudeへのSAML SSOをEntra IDで行うと、Entra側のConditional Access、MFA、デバイス準拠、場所、リスクなどの制御を適用しやすくなります。Microsoft公式では、Conditional Accessはユーザー、グループ、IP location、デバイス、アプリ、リスクなどのシグナルを使って、MFA要求、準拠デバイス要求、ブロックなどの判断を行うZero Trustポリシーエンジンと説明されています。([Microsoft Learn][19])

推奨ポリシー例：

| 対象                   | 推奨制御                             |
| -------------------- | -------------------------------- |
| Claude全利用者           | MFA必須                            |
| Claude Admin / Owner | MFA + 準拠デバイス + 場所制限              |
| 外部ユーザー               | MFA + スポンサー承認 + 短期Access Package |
| 高リスクサインイン            | ブロックまたは追加認証                      |
| 管理操作                 | PIMや管理者専用端末運用を検討                 |

Microsoft Entra IDはSAML/OIDCのプロトコルに関わらず、トークンやアサーション発行前にConditional AccessやMFAなどのポリシーを確認します。([Microsoft Learn][20])

---

## 10. 既存Claude個人アカウントへの対応

企業ドメインのメールアドレスで既にClaude Free、Pro、Maxなどの個人アカウントを使っているユーザーがいる場合、Enterprise導入前に棚卸しが必要です。

Claude公式では、Enterprise管理者は検証済み会社ドメイン上の既存個人Claudeアカウントを検出、クレーム、Enterprise workspaceへ移行できます。Domain claimingはClaude Enterprise planで利用可能です。([Claude ヘルプセンター][21])

Domain claimingを有効化するには、Restrict organization creation、DNSによるドメイン検証、SSO enforcement、JIT provisioningまたはSCIMの有効化が前提とされています。Domain captureは一方向で、いったん有効化すると元に戻せないため、対象アカウント、IdP登録状況、ユーザー周知、データ移行方針を事前に決める必要があります。([Claude ヘルプセンター][21])

---

## 11. 本番化前テスト計画

| No | テスト項目                | 期待結果                         |
| -: | -------------------- | ---------------------------- |
|  1 | Claudeドメイン検証         | Verifiedになる                  |
|  2 | Entra SAML設定         | Test SSOが成功する                |
|  3 | SAML email claim     | SCIM email属性と完全一致する          |
|  4 | SCIM Test Connection | 成功する                         |
|  5 | テストユーザー割り当て          | Claude側にユーザーが作成される           |
|  6 | テストグループ割り当て          | Claude側にSCIMグループが表示される       |
|  7 | Group Mapping        | 期待したClaudeロールになる             |
|  8 | Custom role          | 期待した機能だけ使える                  |
|  9 | Seat割り当て             | 契約シートモデル通りに割り当たる             |
| 10 | SSOログイン              | Continue with SSOでClaudeへ入れる |
| 11 | 未割当ユーザー              | Claudeへログインできない              |
| 12 | グループ削除               | Claudeアクセスが削除・無効化相当になる       |
| 13 | Access Package期限切れ   | グループメンバーシップが外れる              |
| 14 | Access Review否認      | アクセス削除まで完了する                 |
| 15 | 管理者保護                | Admin / Ownerがロックアウトされない     |
| 16 | Primary Owner        | SSOでログインでき、手動管理状態が保たれる       |
| 17 | Provisioning logs    | エラーなし                        |
| 18 | Sign-in logs         | SAMLログインが記録される               |
| 19 | Claude手動Sync         | プレビュー内容が想定通り                 |
| 20 | 大量削除防止               | 削除数が想定外なら中止できる               |

Claude公式では、SCIMやGroup Mappingを保存する前に、必要なユーザーがIdPアプリに割り当てられていることを確認するよう注意されています。正しく割り当てられていない状態で保存すると、ユーザーがClaude組織からdeprovisionされる可能性があります。([Claude ヘルプセンター][4])

---

## 12. よくあるトラブルと確認ポイント

| 事象                 | 主な原因                              | 確認・対処                     |
| ------------------ | --------------------------------- | ------------------------- |
| SSOログインできない        | SAML email claimとSCIM email属性が不一致 | `user.mail`など同一属性へ統一      |
| ユーザーがClaudeに作成されない | Entraアプリに未割り当て                    | Users and groupsを確認       |
| グループメンバーなのに同期されない  | ネストグループを使っている                     | 直接メンバーを持つグループを割り当てる       |
| ロールがUserになる        | Group Mapping不足                   | ロールベースグループへ全員を所属させる       |
| Custom role権限が効かない | ユーザーのClaudeロールがCustomではない         | Claude側ロールとグループ割当を確認      |
| Admin/Owner権限を失った  | 管理者自身がAdmin/Ownerマップグループに入っていない   | 別管理者またはIdP側でグループ追加        |
| 同期が遅い              | EntraのSCIM周期、WorkOS/Claude処理待ち    | Entra logs、Claude Syncを確認 |
| Provisioningが止まる   | 認証情報・属性・一意制約・接続エラー                | Provisioning logsで原因確認    |
| ユーザーが追加されない        | Claude側シート不足                      | シート数を確認                   |
| 退職者が残る             | Access Package/グループ削除が未実施         | Leaverワークフローと割り当て解除を確認    |
| 大量削除されそう           | Group Mapping不足やIdP割り当て漏れ         | Claude同期プレビューで中止          |

Claude公式では、ユーザーが正しく割り当てられていてDirectoryにも表示されるのにClaudeメンバーへ追加されない場合、利用可能なシート数を確認し、必要に応じてシートを追加してからSyncするよう説明されています。([Claude ヘルプセンター][4])

Microsoft公式では、プロビジョニングでエラーが発生した場合、次回サイクルで再試行されます。多くの呼び出しが継続的に失敗する場合、プロビジョニングジョブはquarantine状態になり、増分サイクルの頻度が1日1回まで下がり、4週間以上継続すると無効化される可能性があります。([Microsoft Learn][8])

---

## 13. 運用ベストプラクティス

### 13.1 個別ユーザー割り当てを避ける

利用者が少ない検証段階を除き、Enterprise Applicationへの個別ユーザー割り当ては避けます。Entraセキュリティグループを割り当て、Access Packageでそのグループ所属を管理する構成にすると、申請、承認、期限切れ、棚卸し、退職時削除を統制しやすくなります。

### 13.2 SAMLとSCIMのメール属性を最優先で統一する

Claude公式では、SCIM emailとSSO emailの属性が同一である必要があり、不一致はログイン失敗の一般的な原因とされています。最初に `mail`、`userPrincipalName`、別メール属性のどれを使うかを決め、SAML claimとSCIM mappingを一致させてください。([Claude ヘルプセンター][2])

### 13.3 ネストグループを使わない

Microsoft Entraのアプリ割り当てとプロビジョニングでは、ネストグループは期待通りに展開されません。Claude用グループは、実ユーザーを直接メンバーにするか、動的グループで直接メンバーシップを評価する設計にします。([Microsoft Learn][8])

### 13.4 Primary Ownerは手動管理として設計する

Primary OwnerはSCIM group mappingsでは割り当てできません。導入前にPrimary Ownerを明確にし、そのユーザーがSSO強制後も確実にログインできることを確認してください。([Claude ヘルプセンター][4])

### 13.5 Require SSOは最後に有効化する

Require SSOを有効化すると、対象ドメインのユーザーはSSOでログインする必要があります。IdP側でユーザーがClaudeアプリに正しく割り当てられていない場合、ログイン不能になる可能性があります。([Claude ヘルプセンター][10])

### 13.6 同期プレビューを必ず確認する

Claude公式では、手動同期またはMapping変更時に、追加、削除、変更されるメンバー数のプレビューを確認できると説明されています。削除数が想定より多い場合は、同期を中止してIdPディレクトリとGroup Mappingを確認してください。([Claude ヘルプセンター][18])

---

## 14. 不明・要確認事項

| 項目                                    | 状態                                                                                                                                  |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 自社EntraテナントでClaudeがギャラリーアプリとして表示されるか  | **不明**。Claude公式は、利用可能なら選択、なければ独自アプリ作成と説明しています。([Claude ヘルプセンター][2])                                                                 |
| Claude Enterpriseの固定SCIM Tenant URL形式 | **不明**。公式情報では固定URL形式は示されておらず、WorkOSセットアップフローで表示される値を使います。([Claude ヘルプセンター][2])                                                      |
| 自社契約のシートモデル                           | **要確認**。単一Enterprise seatか、Chat / Chat + Claude CodeやStandard / Premiumのような既存シート種別があるかでGroup Mapping設計が変わります。([Claude ヘルプセンター][22]) |
| 割り当て解除後のClaude管理画面表示                  | **要検証**。Claude公式上は自動削除・自動removalと説明されますが、Microsoft Entraの一般仕様ではdisable/deleteの扱いがターゲットアプリ実装やマッピングに依存します。([Claude ヘルプセンター][4])       |
| 既存個人Claudeアカウントの数                     | **要確認**。Domain claiming前にClaude側で検出・CSV出力し、IdP登録状況と移行方針を確認します。([Claude ヘルプセンター][21])                                                |
| Entra ID Governanceライセンス充足            | **要確認**。Access Package、Access Review、Lifecycle Workflows、自動割り当てなど、利用機能ごとに契約・ライセンスを確認してください。([Microsoft Learn][6])                   |

---

## 15. 本番導入チェックリスト

| 区分                 | チェック項目                                                                                   |
| ------------------ | ---------------------------------------------------------------------------------------- |
| 契約                 | Claude EnterpriseでSCIM利用可能か                                                              |
| 契約                 | 自社のシートモデルを確認したか                                                                          |
| Claude権限           | Primary Owner / Owner / Adminを確認したか                                                      |
| Entra権限            | Global Administrator / Application Administrator / Cloud Application Administratorを確認したか |
| Entraライセンス         | Entra ID P1/P2、Entra ID Governance、Entra Suite要否を確認したか                                   |
| ドメイン               | Claudeで対象ドメインを検証したか                                                                      |
| Entraアプリ           | Claude Enterprise Applicationを作成したか                                                      |
| Properties         | Assignment requiredをYesにしたか                                                              |
| SAML               | Entity ID、ACS URL、Sign-on URLを設定したか                                                      |
| SAML               | Federation Metadata XMLをClaude/WorkOSへアップロードしたか                                          |
| メール属性              | SAML email claimとSCIM email属性が一致しているか                                                    |
| SCIM               | Tenant URL、Secret Tokenを設定したか                                                            |
| SCIM               | Test Connectionが成功したか                                                                    |
| SCIM               | ScopeをSync only assigned users and groupsにしたか                                            |
| グループ               | Claude用グループを作成したか                                                                        |
| グループ               | ネストグループを使っていないか                                                                          |
| 割り当て               | Claude用グループをEnterprise Applicationへ割り当てたか                                                |
| Group Mapping      | ClaudeロールへEntraグループを対応付けたか                                                               |
| Custom role        | 必要なCustom roleを作成しグループに割り当てたか                                                            |
| Primary Owner      | SCIMではなく手動管理として確認したか                                                                     |
| 管理者保護              | 少なくとも1名以上がOwner/Adminマップグループに入っているか                                                      |
| Access Package     | Claude利用者向けAccess Packageを作成したか                                                          |
| 承認                 | 上長・IT・セキュリティ承認を設定したか                                                                     |
| 有効期限               | アクセス期限を設定したか                                                                             |
| Access Review      | 定期棚卸しを設定したか                                                                              |
| Lifecycle          | Joiner/Mover/Leaver処理を設計したか                                                              |
| Conditional Access | MFA、準拠デバイス、場所、リスク制御を検討したか                                                                |
| 既存アカウント            | 企業ドメインの既存Claude個人アカウントを確認したか                                                             |
| テスト                | SSO、SCIM、Group Mapping、削除、期限切れを確認したか                                                     |
| 本番化                | Require SSOを最後に有効化したか                                                                    |
| 運用                 | Provisioning logs、Sign-in logs、Claude Sync確認手順を整備したか                                     |

---

## 16. 最終構成

```text
Microsoft Entra ID
  ├─ ユーザー属性
  │    ├─ mail
  │    ├─ userPrincipalName
  │    ├─ department
  │    └─ employeeStatus など
  │
  ├─ Microsoft Entra ID Governance
  │    ├─ Access Package
  │    ├─ 承認
  │    ├─ 有効期限
  │    ├─ Access Review
  │    └─ Lifecycle Workflows
  │
  ├─ Claude用セキュリティグループ
  │    ├─ GG-Claude-Enterprise-User
  │    ├─ GG-Claude-Enterprise-Admin
  │    ├─ GG-Claude-Enterprise-Owner
  │    └─ GG-Claude-Enterprise-Custom-*
  │
  └─ Enterprise Application: Claude
       ├─ Enabled for users to sign in = Yes
       ├─ Assignment required = Yes
       ├─ SAML SSO
       ├─ SCIM Provisioning
       └─ Users and groups にClaude用グループを割り当て

Claude Enterprise
  ├─ Domain verification
  ├─ SSO configuration
  ├─ Require SSO
  ├─ SCIM directory sync
  ├─ Group Mapping
  ├─ Roles / Custom Roles
  ├─ Seats
  ├─ Groups
  └─ Audit / Analytics / Admin controls
```

この構成により、ユーザーはEntra IDのSAML SSOでClaudeへログインし、ユーザー・グループ・ロール・シートはSCIMとClaude Group Mappingで同期されます。アクセス申請、承認、有効期限、定期棚卸し、入退社・異動連動はEntra ID Governanceで管理します。実装上の最重要ポイントは、**SAMLとSCIMのメール属性一致、Enterprise Applicationの割り当て必須化、ネストグループ不使用、Claude側Group Mapping、Require SSOの有効化タイミング、Primary Ownerの手動管理**です。

[1]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/what-is-single-sign-on "What is single sign-on (SSO) in Microsoft Entra ID? - Microsoft Entra ID | Microsoft Learn"
[2]: https://support.claude.com/en/articles/13917889-microsoft-entra-id-sso-setup "Microsoft Entra ID SSO setup | Claude Help Center"
[3]: https://learn.microsoft.com/en-us/entra/id-governance/entitlement-management-overview "What is entitlement management? - Microsoft Entra ID Governance | Microsoft Learn"
[4]: https://support.claude.com/en/articles/13133195-set-up-jit-or-scim-provisioning "Set up JIT or SCIM provisioning | Claude Help Center"
[5]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/add-application-portal "Quickstart: Add an enterprise application - Microsoft Entra ID | Microsoft Learn"
[6]: https://learn.microsoft.com/en-us/entra/id-governance/licensing-fundamentals "Microsoft Entra ID Governance licensing fundamentals - Microsoft Entra ID Governance | Microsoft Learn"
[7]: https://support.claude.com/en/articles/10276682-important-considerations-before-enabling-single-sign-on-sso-and-jit-scim-provisioning "Important considerations before enabling single sign-on (SSO) and JIT/SCIM provisioning | Claude Help Center"
[8]: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/how-provisioning-works "Understand how Application Provisioning in Microsoft Entra ID - Microsoft Entra ID | Microsoft Learn"
[9]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/application-properties "Properties of an enterprise application - Microsoft Entra ID | Microsoft Learn"
[10]: https://support.claude.com/en/articles/13132885-set-up-single-sign-on-sso "Set up single sign-on (SSO) | Claude Help Center"
[11]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/add-application-portal-setup-sso "Enable SAML single sign-on for an enterprise application - Microsoft Entra ID | Microsoft Learn"
[12]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/assign-user-or-group-access-portal "Manage users and groups assignment to an application - Microsoft Entra ID | Microsoft Learn"
[13]: https://support.claude.com/en/articles/13930452-manage-custom-roles-on-enterprise-plans "Manage custom roles on Enterprise plans | Claude Help Center"
[14]: https://support.claude.com/en/articles/13799932-manage-groups-and-group-spend-limits-on-enterprise-plans "Manage groups and group spend limits on Enterprise plans | Claude Help Center"
[15]: https://learn.microsoft.com/en-us/entra/id-governance/entitlement-management-access-package-auto-assignment-policy "Configure an automatic assignment policy for an access package in entitlement management - Microsoft Entra - Microsoft Entra ID Governance | Microsoft Learn"
[16]: https://learn.microsoft.com/en-us/entra/id-governance/access-reviews-overview "What are access reviews? - Microsoft Entra - Microsoft Entra ID Governance | Microsoft Learn"
[17]: https://learn.microsoft.com/en-us/entra/id-governance/what-are-lifecycle-workflows "What are lifecycle workflows? - Microsoft Entra ID Governance | Microsoft Learn"
[18]: https://support.claude.com/en/articles/14499648-how-scim-sync-works-for-enterprise-organizations "How SCIM sync works for Enterprise organizations | Claude Help Center"
[19]: https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview "Microsoft Entra Conditional Access: Zero Trust Policy Engine - Microsoft Entra ID | Microsoft Learn"
[20]: https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/understand-microsoft-sso-model "Understand Microsoft's SSO model - Microsoft Entra ID | Microsoft Learn"
[21]: https://support.claude.com/en/articles/14625619-claim-and-migrate-accounts-on-your-domain "Claim and migrate accounts on your domain | Claude Help Center"
[22]: https://support.claude.com/en/articles/13393991-purchase-and-manage-seats-on-enterprise-plans "Purchase and manage seats on Enterprise plans | Claude Help Center"
