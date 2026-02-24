※この表の「推論データ」＝入力（プロンプト）＋出力（生成結果）。  
※Azure の「geography」はデータ居住性の境界で、1 geography に 1 つ以上の「region」が含まれます。([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/reliability/regions-overview?utm_source=openai))

| デプロイ方式 | データの処理場所 | 推論データの保存 | モデル提供者へのデータ共有 |
|---|---|---|---|
| **Foundry標準（Azure Direct Models：Azure OpenAI を含む）**([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy)) | **基本**: デプロイ先として指定した geography 内で処理（同 geography 内の別 region で処理される場合あり）。([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy))<br>**例外**: “Global” は任意 geography で処理され得る／“DataZone” は指定 data zone 内で処理され得る（ただし at-rest は指定 geography）。([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy)) | **基本**: モデル自体は stateless（モデルの中にプロンプト/出力は保存されない）。([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy))<br>**例外①**: 履歴を持つ機能（Responses/Assistants Threads/Stored completions 等）を使うと、メッセージ履歴などがサービス内に保存され得る。([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy))<br>**例外②**: 不正利用対策（abuse monitoring）で、プロンプト/出力のサンプルが選ばれて保存・人手レビューされる場合がある。([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy)) | プロンプト/出力/学習データは OpenAI 等のモデル提供者に提供されず、提供者のサービスともやり取りしない（Microsoft が Azure 内でホスト）。([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy)) |
| **serverless API（MaaS）**([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/how-to/concept-data-privacy)) | デプロイ時に指定した geography 内で処理（運用上、同 geography 内の別 region で処理される可能性）。([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/how-to/concept-data-privacy)) | モデルは stateless（プロンプト/出力を保存しない）。([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/how-to/concept-data-privacy)) | プロンプト/出力はモデル提供者に共有されない。([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/how-to/concept-data-privacy))<br>ただし model publisher に「連絡先」「取引情報（利用量含む）」が共有され得る。([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/how-to/concept-data-privacy)) |
| **managed compute（Managed online deployment）**([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/how-to/concept-data-privacy)) | モデル weights を専用 VM（dedicated virtual machines）にデプロイし、その REST API で推論。([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/how-to/concept-data-privacy))<br>（参考）Endpoint の Target URI は `https://<endpoint-name>.<region>.inference.ml.azure.com/score` 形式。([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/deploy-models-managed?utm_source=openai)) | **設定次第**: data collector（推論データ収集）を有効化すると、request/response や model_inputs/model_outputs が workspace の Blob Storage に保存される。([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-collect-production-data?view=azureml-api-2)) | **基本**: 推論は dedicated VM 上の endpoint で実行（serverless API のような「Microsoft 管理の共有ホスティングAPI」に投げる方式ではない）。([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/how-to/concept-data-privacy))<br>**注意**: すべてのモデルコンテナが脆弱性スキャン済みとは限らないため、データ持ち出し対策として VNet 等で保護することが推奨。([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/how-to/concept-data-privacy)) |





◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
















前提（公式ドキュメントの整理）
- 「推論の域外処理」＝プロンプト/応答など“推論時に扱うデータ”が、あなたが許容した地域（例：単一リージョン、US/EUデータゾーン等）の外で処理されてしまうこと。
- Microsoft Foundry Models では「保存データ（at rest）は指定の Azure geography に残る」が、「推論データの処理場所はデプロイ種別で変わる」と明記されています。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types))

| デプロイ方式 | 推論データの処理範囲（公式） | 「推論の域外処理」リスク（何が起きうるか） | 初学者向けの見方（どんな要件だとNGになりやすい？） |
|---|---|---|---|
| Global Standard | 任意の Azure リージョンで処理され得る ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | “処理場所を固定できない”ため、要件によっては域外処理になり得る（国/地域/社内規定の範囲外で推論処理される可能性）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 「単一リージョン固定」「国内固定」などがあると要注意（Global はどこで処理されるかを限定できない）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) |
| Data Zone Standard | Microsoft 指定のデータゾーン（US または EU）内でのみ処理 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | US/EU という“ゾーン”には収まるが、ゾーン内のどのリージョン/国（EUは加盟国）で処理されるかは固定されないため、要件次第で「域外」扱いになり得る。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 「US 内ならOK」「EU 内ならOK」要件には適合しやすい。一方「特定国（例：日本のみ）」「単一リージョンのみ」だと不適合になりやすい。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) |
| Standard | デプロイした単一リージョンで処理 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 公式上、推論処理が単一リージョンに限定されるため、域外処理リスクは相対的に低い（※“どのリージョンを選ぶか”が重要）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 「単一リージョン固定」が必要なら第一候補（ただしモデル/機能がそのリージョン・この方式で提供されるか要確認）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) |
| Global Provisioned | 任意の Azure リージョンで処理され得る ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | Global Standard と同様に、処理場所がグローバルに動き得るため、地理的制約があると域外処理になり得る。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 「処理場所の制約がある」場合は不向きになりやすい（容量予約/性能が目的でも、処理場所は限定されない）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) |
| Data Zone Provisioned | データゾーン（US/EU）内でのみ処理 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | データゾーン外には出ない一方、ゾーン内での処理先は固定されないため、要件によっては域外扱いになり得る。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 「US/EU の範囲に入っていればOK」＋「高スループット/安定」要件向き。単一リージョン固定要件だと不適合になり得る。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) |
| Provisioned（= Regional Provisioned） | デプロイした単一リージョンで処理 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 公式上、単一リージョン処理なので域外処理リスクは相対的に低い（ただし選定リージョンが要件に合っていることが前提）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 「単一リージョン固定」＋「高スループット/予測可能性」を両立したい場合の候補。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) |
| Global Batch | 任意の Azure リージョンで処理され得る ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | Global 系なので域外処理になり得る。加えてバッチは“大量データをまとめて送る”運用になりやすく、域外になった場合の影響（扱うデータ量）が大きくなりやすい。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 「処理場所を固定したい」要件がある場合は不向きになりやすい。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) |
| Data Zone Batch | データゾーン（US/EU）内でのみ処理 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | データゾーン外には出ないが、ゾーン内のどこで処理されるかは固定されないため、要件次第で域外扱いになり得る（特に“単一リージョン固定”要件）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) | 「US/EU 内でのバッチ処理ならOK」要件向き。単一リージョン固定なら Standard/Regional Provisioned を検討。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types)) |

実務での確認ポイント（域外処理リスクを潰す順番）
- まず「域」を定義（単一リージョンなのか、US/EUデータゾーンなのか、制約なしなのか）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types))
- 「単一リージョンのみ」が要件なら、公式は Standard または Regional Provisioned を案内しています。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types))
- モデルによって選べるデプロイ方式/リージョンが違うため、要件を満たす方式が“そもそも選べるか”を事前確認します。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types))
- 誤って Global 系を作れないよう、Azure Policy で特定 SKU（例：GlobalStandard 等）を禁止する運用が可能です。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/ai-services/concepts/deployment-types))
