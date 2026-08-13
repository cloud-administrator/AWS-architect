# 調査結果

**調査基準日：2026年8月13日**

以下では、用語を次のように区別します。

* **ローカルのユーザー設定**：通常の `~/.codex/config.toml`

  * Windowsでは通常、ユーザーホーム配下の `.codex\config.toml`
  * `CODEX_HOME`を変更している場合は、その配下の`config.toml`
* **クラウド設定**：ご指定のCodex管理画面で設定し、クラウド構成バンドルとして配信される`config.toml`
* **強制ポリシー**：同じ管理画面などから配信される`requirements.toml`

## 結論

### 1. ローカルとクラウドの`config.toml`は、どちらが優先されるか

一般的なユーザー設定である`~/.codex/config.toml`と、管理画面から配信されるクラウドの`config.toml`で**同じ設定項目が指定されている場合、現行の公式実装ではローカルの`~/.codex/config.toml`が優先されます。**

OpenAI公式リポジトリのCodex設定ローダーでは、優先順位が次のように定義されています。

```text
高い
  CLI・セッション単位の指定
  プロジェクト設定 .codex/config.toml
  プロファイル設定
  ユーザー設定 ~/.codex/config.toml
  クラウド管理設定 EnterpriseManaged
  システム設定 /etc/codex/config.toml など
低い
```

公式ソースでは、ユーザー設定の優先度が`20`、クラウド管理設定が`15`、システム設定が`10`と定義されており、「数値が大きいレイヤーが小さいレイヤーを上書きする」と明記されています。したがって、ユーザー設定とクラウド設定の比較では、ユーザー設定が勝ちます。

ただし、「ローカルの`config.toml`」がどのファイルを指すかによって、次のように変わります。

| ローカル側のファイル                              | クラウドの`config.toml`との比較 |
| --------------------------------------- | ---------------------- |
| `~/.codex/config.toml`                  | **ローカルが優先**            |
| プロジェクト内の`.codex/config.toml`            | **プロジェクト設定が優先**        |
| プロファイルの`~/.codex/<profile>.config.toml` | **プロファイル設定が優先**        |
| システム設定の`/etc/codex/config.toml`など       | **クラウド設定が優先**          |
| `managed_config.toml`やMDM管理設定           | **管理設定が優先**。後述の別機能     |

したがって、ご質問の「ローカル」が通常のユーザー設定`~/.codex/config.toml`を意味するのであれば、回答は**ローカル優先**です。

---

### 2. クラウド設定が反映された後でローカルの`config.toml`を編集した場合

**Codexが設定を再読み込みした時点では、ローカルで編集した値が適用されます。**

ただし、すべてのクラウド設定が消えるわけではありません。設定はファイル単位でどちらか一方を選ぶのではなく、各レイヤーをマージして作られます。

例えば、クラウド側に次の設定があるとします。

```toml
approval_policy = "on-request"
model_reasoning_effort = "high"
```

ローカルの`~/.codex/config.toml`を次のように編集します。

```toml
approval_policy = "untrusted"
```

強制する`requirements.toml`がない場合、実効設定は概念的に次のようになります。

```toml
approval_policy = "untrusted"        # ローカルが上書き
model_reasoning_effort = "high"      # ローカルにないためクラウド値を使用
```

つまり、挙動は次のとおりです。

| 状況                   | 実効値     |
| -------------------- | ------- |
| クラウドだけに設定項目がある       | クラウド値   |
| クラウドとローカルの両方に同じ項目がある | ローカル値   |
| ローカルの上書き項目を削除する      | 再びクラウド値 |
| さらにプロジェクト設定にも同じ項目がある | プロジェクト値 |
| CLI引数でも同じ項目を指定する     | CLI値    |

## クラウド設定はローカルの`config.toml`へコピーされるわけではない

ここは重要です。

クラウドの`config.toml`は、ユーザーの`~/.codex/config.toml`を書き換えて挿入される仕組みではありません。OpenAI公式ソースでは、クラウドから取得した`config_toml.enterprise_managed`を、`EnterpriseManaged`という独立した設定レイヤーに変換しています。また、同じクラウド構成バンドルの中でも、`config.toml`と`requirements.toml`は別々に扱われています。

クラウド管理設定を導入した公式コミットでも、クラウド設定は物理的な設定ファイルを持たない「non-file managed config」として扱われると説明されています。([GitHub][1])

したがって、より正確には次の動作です。

```text
クラウド設定を取得
        ↓
クラウド管理レイヤーとして保持
        ↓
ローカルのユーザー設定をその上に重ねる
        ↓
最終的な実効設定を作る
```

ローカルの`config.toml`を編集しても、中央管理画面に登録されたクラウド設定自体が変更されるわけではありません。ローカル端末上の実効設定で、上位レイヤーとして上書きされるだけです。

---

# 最大の例外：`requirements.toml`

会社として「ユーザーに変更させたくない設定」を管理する場合、クラウドの`config.toml`だけでは不十分です。

OpenAIは管理設定を大きく次の2種類に分けています。

| 種類                  | 役割             | ユーザーによる上書き |
| ------------------- | -------------- | ---------- |
| `config.toml`       | 初期値・標準値・デフォルト値 | **可能**     |
| `requirements.toml` | 許可範囲・禁止事項・強制要件 | **不可能**    |

公式ドキュメントでも、`requirements.toml`は管理者が強制する制約であり、ユーザーは上書きできないと説明されています。ローカルの`config.toml`、プロファイル、CLI引数などが要件に違反すると、Codexはその値をそのまま使わず、要件に適合する値へフォールバックして利用者へ通知します。([OpenAI Developers][2])

例えば、クラウドの`requirements.toml`で次のように指定したとします。

```toml
allowed_approval_policies = ["on-request"]
```

その状態で利用者がローカルに次のように書いても、

```toml
approval_policy = "untrusted"
```

`untrusted`は許可リストにないため、実効設定としては採用されません。Codexは許可された値へフォールバックします。

また、機能フラグは`requirements.toml`の`[features]`で固定できます。公式ドキュメントでは、固定された機能フラグと競合する`config.toml`やプロファイルへの書き込みは拒否されると明記されています。([OpenAI Developers][2])

したがって、会社の管理方針は次のように設計するのが適切です。

```text
利用者が変更してもよい標準設定
    → クラウドの config.toml

利用者に変更させてはいけないセキュリティ設定
    → クラウドの requirements.toml
```

特に、次のような項目を`config.toml`だけで管理すると、利用者のローカル設定で上書きされる可能性があります。

* 承認ポリシー
* サンドボックスや権限プロファイル
* Web検索やブラウザー関連機能
* MCPサーバーの利用範囲
* プラグインマーケットプレイス
* 特定の機能フラグ
* ネットワーク関連の制限

ただし、`requirements.toml`で強制できるのはサポートされている項目だけです。任意の`config.toml`項目をすべて強制できるわけではありません。OpenAIも、利用できる要件はクライアントおよびバージョンによって異なるため、全社展開前に対象バージョンを確認し、小規模なグループでテストするよう案内しています。([OpenAI Developers][2])

---

# `managed_config.toml`とは区別が必要

OpenAIのドキュメントには、クラウドの`config.toml`とは別に、端末管理用の`managed_config.toml`が出てきます。

この`managed_config.toml`は、通常のローカル`config.toml`よりも上位です。公式ドキュメントでは次の順番になっています。

```text
高い
  macOS MDM管理設定
  managed_config.toml
  ユーザーのconfig.toml
低い
```

`managed_config.toml`はCLIの`--config`指定よりも優先されます。([OpenAI Developers][3])

つまり、似た名前ですが挙動は異なります。

| 設定                            | ローカルのユーザー`config.toml`との関係 |
| ----------------------------- | -------------------------- |
| 管理画面から配信されるクラウドの`config.toml` | ユーザー`config.toml`より下       |
| 端末に配置する`managed_config.toml`  | ユーザー`config.toml`より上       |
| クラウドまたは端末の`requirements.toml` | 優先順位というより、実効値の許可範囲を強制      |

この違いは、Codexの会社導入で特に混乱しやすい点です。

---

# 編集後、いつ反映されるか

## 確実に言えること

Codexが設定レイヤーを再読み込みすれば、現在の公式優先順位に従い、ローカルの`~/.codex/config.toml`がクラウドの`config.toml`を上書きします。

## 不明・保証されていないこと

**起動中の既存チャットや既存プロセスで、外部エディターによる`config.toml`の編集が即時に反映されるかは、公式公開資料では一律に保証されていません。**

クラウド管理設定を導入した公式コミットでは、設定の扱いは「pull-based and snapshot-oriented」であり、動的な再読み込みを追加するものではないと説明されています。([GitHub][1])

また、少なくともクラウドの`requirements.toml`については、バックグラウンド更新でキャッシュが更新されても、現在のプロセスに読み込まれた要件は置き換えられず、後の起動で使用されると公式ドキュメントに記載されています。([OpenAI Developers][2])

そのため、検証時は次の運用が最も確実です。

1. ローカルの`config.toml`を保存する。
2. Codex CLI、IDE拡張機能、またはデスクトップアプリを完全に終了する。
3. Codexを再起動する。
4. 新しいセッションで実効設定を確認する。

「新しいチャットを作るだけで必ず全設定が再読み込みされるか」は、クライアントやバージョンによって異なる可能性があるため、会社の検証では**プロセスの完全再起動**を推奨します。

---

# 実機での確認方法

現在のCodex CLIには、設定レイヤーとポリシーの診断を表示する`/debug-config`があります。

```text
/debug-config
```

公式ドキュメントによると、このコマンドは次の情報を表示します。

* 設定レイヤーの順番
* 各レイヤーが有効か無効か
* ポリシーの取得元
* `allowed_approval_policies`
* `allowed_sandbox_modes`
* MCP、ルール、ネットワーク制約など

表示順は**優先順位が低いものから高いもの**です。したがって、現在の実装であれば、クラウドの`EnterpriseManaged`レイヤーが先に表示され、その後に`User`レイヤーが表示されることが期待されます。`/status`では、現在有効なモデル、承認ポリシー、書き込み可能範囲などを確認できます。([ChatGPT Learn][4])

会社での検証例は次のとおりです。

### 手順1：クラウド側

クラウドの`config.toml`に次を設定します。

```toml
approval_policy = "on-request"
```

### 手順2：ローカル側

`~/.codex/config.toml`に次を設定します。

```toml
approval_policy = "untrusted"
```

### 手順3：完全再起動

Codexを完全に終了し、再度起動します。

### 手順4：確認

```text
/debug-config
/status
```

強制する`requirements.toml`がなければ、現在の優先順位では`untrusted`が有効になるはずです。

### 手順5：強制ポリシーを追加

クラウドの`requirements.toml`に次を設定します。

```toml
allowed_approval_policies = ["on-request"]
```

再起動後、ローカルの`untrusted`は適用されず、許可された`on-request`へフォールバックすることを確認します。

この2段階のテストを行うと、

* クラウド`config.toml`がデフォルトであること
* ローカル`config.toml`が通常は上書きできること
* `requirements.toml`はローカルから上書きできないこと

を分けて確認できます。

---

# 最終回答

| ご質問                                                          | 回答                                  |
| ------------------------------------------------------------ | ----------------------------------- |
| 通常のローカル`~/.codex/config.toml`とクラウド管理画面の`config.toml`はどちらが優先か | **ローカルの`~/.codex/config.toml`が優先**  |
| クラウド設定反映後にローカルを編集したら適用されるか                                   | **設定再読み込み後は適用される**                  |
| クラウド設定はローカルファイルへ書き込まれるのか                                     | **いいえ。別のクラウド管理レイヤーとしてマージされる**       |
| ローカルで同じ項目を設定した場合                                             | **ローカル値がクラウド値を上書きする**               |
| ローカルから項目を削除した場合                                              | **クラウド値が再び有効になる**                   |
| `requirements.toml`と競合した場合                                   | **ローカル値は適用されない**                    |
| 起動中の既存セッションへ即時反映されるか                                         | **不明。公式には一律保証されていないため、完全再起動が確実**    |
| `managed_config.toml`の場合                                     | **クラウドの通常設定やユーザー設定とは別で、ユーザー設定より上位** |

**会社として確実にコントロールしなければならない設定は、クラウドの`config.toml`だけに置かず、対応する項目を`requirements.toml`で制約することが重要です。** `config.toml`は標準値、`requirements.toml`は強制的なガードレールとして設計するのが、現在の公式仕様・実装に沿った運用です。

[1]: https://github.com/openai/codex/commit/8a556296f0b222412be75db039724d1cac624217?utm_source=chatgpt.com "Add cloud-managed config layer support (#24620) · openai/codex@8a55629 · GitHub"
[2]: https://developers.openai.com/codex/enterprise/managed-configuration "Managed configuration | ChatGPT Learn"
[3]: https://developers.openai.com/codex/enterprise/managed-configuration?utm_source=chatgpt.com "Managed configuration | ChatGPT Learn"
[4]: https://learn.chatgpt.com/codex/developer-commands "Developer commands | ChatGPT Learn"
