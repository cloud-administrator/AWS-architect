## Primary Owner と Owner の「できること」の差分

2026年7月22日時点のAnthropic公式情報を確認した結果、**明確に確認できた差分は以下の5点です**。いずれも、**Primary Ownerにはできるが、Ownerにはできない操作**です。

1. **Primary Ownerの役割を別のユーザーへ移譲できる**

   現在のPrimary Ownerは、組織内の別ユーザーを新しいPrimary Ownerに指定し、最上位の所有権を移譲できます。通常のOwnerは、このPrimary Owner移譲を実行・申請できません。

   これは単なるOwnerへの昇格ではなく、組織に1人しか存在しない「最終責任者」を交代する操作です。移譲が完了すると、元のPrimary OwnerはPrimary Ownerではなくなります。 ([Claude ヘルプセンター][1])

2. **組織全体のデータを書き出せる**

   Primary Ownerは、組織設定から**組織全体のデータエクスポート**を実行できます。対象には、ユーザー情報やClaudeとの会話データなどが含まれます。Ownerには、このセルフサービス型の組織データエクスポート権限はありません。

   ここでいうデータエクスポートは、管理画面に表示される利用状況のCSV出力などとは異なり、ユーザーの会話内容を含み得る、機密性の非常に高いデータ取得機能です。 ([Anthropic Privacy Center][2])

3. **Claude Enterprise組織自体の削除を申請できる**

   Claude Enterpriseの組織・契約アカウントそのものを削除する場合、Anthropicサポートへの削除申請はPrimary Ownerが行う必要があります。Ownerは、メンバーの削除などはできますが、**組織全体の削除申請者にはなれません**。 ([Claude Help Center][3])

4. **Enterprise用の管理APIキーを発行できる**

   Primary Ownerは、Claude Enterpriseの親組織に対して、次のような管理APIで使用するAPIキーを発行できます。

   * Analytics API：ユーザー別の利用量・コスト・利用傾向などをプログラムから取得するAPI
   * Enterprise Admin API：利用上限の取得・変更や、利用上限引き上げ申請の承認・却下などを行うAPI

   Anthropicは、これらの管理APIキーを新規作成できるのはPrimary Ownerだけと明記しています。Ownerは管理画面上で利用分析を閲覧できても、管理APIキーそのものは発行できません。 ([Claude Help Center][4])

5. **BAAを承諾し、HIPAA対応を有効化できる**

   HIPAA-ready Enterpriseを利用する場合、Primary Ownerだけが、Anthropicの**Business Associate Agreement（BAA：事業提携者契約）**を承諾し、組織のHIPAA対応を有効化できます。Anthropicは、通常のOwnerやAdminではこの操作を代理実行できないと明記しています。

   この操作は組織全体の設定を変更し、管理画面から元に戻せない一方向の変更であるため、Primary Ownerだけに限定されています。米国の医療情報であるPHIをClaudeで処理する場合に関係する権限です。 ([Claude Help Center][5])

## 不明：新規シートの購入・追加

Anthropicの公式情報には表記の不一致があります。

権限一覧では「Provision new seats」がPrimary Ownerだけの権限であるように掲載されています。一方、より新しいEnterpriseシート管理の記事では、**OwnerとPrimary Ownerの両方が新規シートを購入・追加できる**と明記されています。 ([Claude Help Center][6])

そのため、現時点では次の整理が妥当です。

> **新規シートの購入・追加は、Primary OwnerとOwnerの確定的な差分には含めない。公式資料間の不一致があるため、厳密な権限仕様は不明。**

なお、**Ownerだけが実行でき、Primary Ownerには実行できない操作**は、今回確認したAnthropic公式資料では見つかりませんでした。

[1]: https://support.anthropic.com/en/articles/9267276-roles-and-permissions "Roles and permissions | Claude Help Center"
[2]: https://privacy.claude.com/en/articles/13346720-export-your-organization-s-data "Export your organization's data | Anthropic Privacy Center"
[3]: https://support.claude.com/en/articles/12053672-what-happens-to-a-user-s-data-when-they-are-removed-from-a-team-or-enterprise-organization "What happens to a user's data when they are removed from a Team or Enterprise organization? | Claude Help Center"
[4]: https://support.claude.com/en/articles/15330651-claude-enterprise-admin-api-reference-guide "Claude Enterprise Admin API reference guide | Claude Help Center"
[5]: https://support.claude.com/en/articles/13296973-hipaa-ready-enterprise-plans "HIPAA-ready Enterprise plans | Claude Help Center"
[6]: https://support.claude.com/en/articles/9267276-roles-and-permissions "Roles and permissions | Claude Help Center"
