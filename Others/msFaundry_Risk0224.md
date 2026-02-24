microsoft foundryを使用して、Azure上でAIのモデルをデプロイするプロジェクトに参加しています。
リスク評価を行うこととなりましたので、下記のデプロイ方式に対する、各種リスク項目の内容を調査してください。
※必ず公式サイトを調査してください。
※表でまとめてください。

●デプロイ方式
・Faundry標準
・serverless API
・managed compute

●リスク項目
・データの処理場所
・推論データの保存
・モデル提供者へのデータ共有
◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆

前提（公式ドキュメント上の区分）: 「Foundry標準（Foundry Models）」は Azure AI Foundry resource 側、「serverless API」は AI project resource 側のデプロイ方式です。 ([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/model-inference/faq))

| リスク項目 | Foundry標準（Foundry resource / Foundry Models・Azure Direct Models） | serverless API（AI project resource） | managed compute（Managed online deployment） |
|---|---|---|---|
| データの処理場所 | 標準: 指定 geography 内で処理（同 geography 内の複数リージョン間で処理され得る）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy))<br>Global: any geography／DataZone: 指定 data zone 内で処理され得る。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy))<br>Global/DataZone の at-rest データは指定 geography に保持（Foundry Models の Global Standard は推論が any Azure location になり得る旨の記載あり）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy)) | デプロイ時に指定した geography 内で処理（運用目的で同 geography 内のリージョン間で処理され得る）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/concept-data-privacy)) | モデル weights を dedicated VM にデプロイ（VM quota は per-region で消費）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/concept-data-privacy))<br>推論 endpoint URI に region が含まれる。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/deploy-models-managed)) |
| 推論データの保存 | モデルは stateless（prompt/completion はモデルに保存されない）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy))<br>ただし abuse monitoring で human review が必要な場合、prompt/completion のサンプルが datastore に保存され得る。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy))<br>Responses API/Threads/Stored completions 等の stateful 機能ではメッセージ履歴等を保存。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy)) | モデルは stateless で prompt/output を保存しない。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/concept-data-privacy)) | Data collector / payload logging を有効化すると、推論の request/response 等を Blob Storage に保存（既定: `azureml://datastores/workspaceblobstore/paths/modelDataCollector`。1 行=1 推論イベントの JSON）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-collect-production-data?view=azureml-api-2)) |
| モデル提供者へのデータ共有 | Azure Direct Models: prompt/completion 等は OpenAI 等の model providers に提供されず、provider-operated service とも連携しない。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy))<br>Foundry Models: prompt/output は model provider に共有されない（ただし MaaS では customer contact info/transaction details が共有され得る旨の記載あり）。 ([learn.microsoft.com](https://learn.microsoft.com/azure/ai-foundry/model-inference/faq)) | Microsoft は prompt/output を model provider に共有しない（学習/改善にも利用しない）。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/concept-data-privacy))<br>ただし customer contact info と transaction details（usage volume を含む）が model publisher に共有される可能性。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/concept-data-privacy)) | Microsoft はログ/コンテンツをモデル提供者へ共有せず、モデル提供者への runtime connection もない。 ([microsoft.com](https://www.microsoft.com/en-us/security/blog/2025/03/04/securing-generative-ai-models-on-azure-ai-foundry/))<br>また、モデルコンテナが全てスキャン済みとは限らないため、データ exfiltration 対策として VNet 利用等が推奨。 ([learn.microsoft.com](https://learn.microsoft.com/en-us/azure/ai-studio/how-to/concept-data-privacy)) |
◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆


◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆◆
