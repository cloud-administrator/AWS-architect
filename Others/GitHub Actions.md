# GitHub Actions 完全マスターガイド：Terraform & Azure 編

## はじめに：なぜ GitHub Actions なのか？

現代のクラウドインフラ構築において、手動での操作は「温かみ」以外の価値を生み出しません。ミスを誘発し、再現性を損ない、運用をブラックボックス化させます。
本ガイドでは、**Microsoft Azure** と **Terraform** を題材に、**GitHub Actions** を用いた自動化パイプライン（CI/CD）の構築方法を、初心者の方にも分かりやすく、かつ実務で使えるレベルまで徹底的に解説します。

### 対象読者
- Azure Portal でポチポチすることに疲れた方
- Terraform のコードは書いたことがあるが、自動化はまだの方
- 「CI/CD」などの用語を聞くと頭が痛くなる方
- 現場で通用するセキュリティレベル（OIDC認証など）を身につけたい方

---

## 第1部：GitHub Actions の基礎概念

### 1-1. CI/CD とは何か？（インフラ視点）

CI/CD は元々ソフトウェア開発の用語ですが、インフラエンジニアにとっても必須の概念です。

#### CI (Continuous Integration / 継続的インテグレーション)
**「検証の自動化」** です。
あなたが Terraform のコードを修正して GitHub にプッシュした瞬間、自動的に以下のチェックが走ることを想像してください。
- 文法ミスはないか？ (`terraform validate`)
- コードのフォーマットは綺麗か？ (`terraform fmt`)
- どのような変更が起きる予定か？ (`terraform plan`)

これにより、「マージしてからエラーに気づく」という絶望を未然に防ぎます。

#### CD (Continuous Delivery / 継続的デリバリー)
**「適用の自動化」** です。
コードが承認され、メインのブランチにマージされたら、自動的に Azure 上のリソースを作成・更新します (`terraform apply`)。
「本番環境へのデプロイは、誰かのPCからコマンドを叩く」という属人性を排除します。

> [!NOTE]
> **IaC (Infrastructure as Code) における CD の重要性**
> 誰かのPCから `apply` する運用は、そのPCの環境（Terraformのバージョンや認証情報）に依存してしまいます。GitHub Actions という「共通のクリーンな環境」からデプロイすることで、誰がやっても同じ結果になることを保証します。

---

### 1-2. GitHub Actions を構成する6つの重要用語

GitHub Actions を理解するには、以下の6つの用語を押さえるだけで十分です。関係性をイメージ図とともに解説します。

```mermaid
graph TD
    Event[Event: トリガー] -->|プッシュやプルリクエスト| Workflow[Workflow: 全体の流れ]
    Workflow --> Job1[Job 1: テスト]
    Workflow --> Job2[Job 2: デプロイ]
    
    subgraph Job1
        Runner1[Runner: 実行環境 (Ubuntuなど)]
        Step1[Step: 手順1] --> Step2[Step: 手順2]
    end
    
    subgraph Job2
        Runner2[Runner: 実行環境 (Ubuntuなど)]
        Step3[Step: 手順3] --> Step4[Step: 手順4]
    end
```

#### 1. Workflow (ワークフロー)
**「自動化プロセス全体」** のことです。
「ビルドして、テストして、デプロイする」という一連の流れ全体を指します。1つのリポジトリに複数のワークフロー（例：「テスト用」「本番反映用」「定期実行用」）を持つことができます。
`.github/workflows` フォルダ配下に YAML ファイルとして保存されます。

#### 2. Event (イベント)
**「ワークフローを起動するきっかけ」** です。
- **`push`**: コードをプッシュしたとき
- **`pull_request`**: プルリクエストを作成したとき
- **`schedule`**: 指定した時間になったら（cron構文）
- **`workflow_dispatch`**: 画面上のボタンを手動でクリックしたとき

#### 3. Job (ジョブ)
**「一連の作業のまとまり」** です。
1つのワークフローの中に複数のジョブを含めることができます。
**重要**: デフォルトでは、複数のジョブは**並列（同時）**に実行されます。「テストが終わってからデプロイしたい」場合は、依存関係（`needs`）を明示する必要があります。

#### 4. Step (ステップ)
**「ジョブの中の1つの手順」** です。
コマンドを実行したり（`run`）、誰かが作ったアクションを使ったり（`uses`）します。ステップは上から順に**直列**に実行されます。

#### 5. Action (アクション)
**「再利用可能な機能パーツ」** です。
「GitHub からコードをチェックアウトする」「Azure にログインする」「Terraform をインストールする」といった一般的な作業は、世界中の開発者や公式が「アクション」として公開しています。これらを `uses: actions/checkout@v4` のように呼び出すだけで、複雑な処理を1行で書くことができます。

#### 6. Runner (ランナー)
**「ジョブを実行するサーバー」** です。
基本的には GitHub が用意してくれる **GitHub-hosted runner** (使い捨ての仮想マシン) を使います。
- `ubuntu-latest`: Linux 環境（Terraform ではこれが標準）
- `windows-latest`: Windows 環境
- `macos-latest`: macOS 環境

> [!TIP]
> **GitHub-hosted runner のメリット**
> 毎回クリーンな環境（初期化されたVM）が立ち上がるため、「前の実行時のゴミが残っていてエラーになる」といった問題が起きません。セキュリティ的にも安心です。

---

## 第2部：YAML構文の基礎レッスン

プログラミング未経験者にとって YAML (ヤムル) は少し取っつきにくいかもしれませんが、ルールは単純です。「インデント（スペースの数）」が命です。

### 基本的なワークフローファイルの解剖

以下は、画面に "Hello, Terraform!" と表示するだけの最小構成のワークフローです。これを見ながら構造を理解しましょう。

```yaml
# ワークフローの名前。GitHubの画面に表示されます。
name: My First Terraform Workflow

# いつ実行するか？ (トリガー)
on:
  push:
    branches:
      - main  # mainブランチにpushされた時だけ動く

# 何をするか？ (ジョブの定義)
jobs:
  # "say-hello" というIDのジョブ
  say-hello:
    # どのOSで動かすか
    runs-on: ubuntu-latest
    
    # 手順のリスト
    steps:
      # 手順1: リポジトリのコードを持ってくる
      # "uses" は公開されているアクションを使うときに記述する
      - name: Checkout Code
        uses: actions/checkout@v4

      # 手順2: シェルコマンドを実行する
      # "run" はLinuxコマンドなどを直接書くときに記述する
      - name: Greet
        run: echo "Hello, Terraform!"
```

### よく使う構文のポイント

#### `name` (必須ではないが推奨)
ステップやジョブに名前をつけると、実行ログが見やすくなります。日本語でもOKです。
```yaml
- name: Terraform の初期化を実行中...
  run: terraform init
```

#### `env` (環境変数の設定)
環境変数は、ワークフロー全体、ジョブ単位、ステップ単位のどこでも定義できます。Azure の設定情報などはここで定義することが多いです。
```yaml
env:
  TF_VAR_resource_group_name: "rg-prod-app"
  ARM_SUBSCRIPTION_ID: "xxxx-xxxx-xxxx"
```

#### `if` (条件分岐)
特定の条件のときだけステップを実行したい場合に使います。
```yaml
# mainブランチのときだけ実行する
- name: Apply Changes
  if: github.ref == 'refs/heads/main'
  run: terraform apply -auto-approve
```

---
（第1部 完）
次は、いよいよ **Microsoft Azure との安全な連携（OIDC認証）** について解説します。ここが最初の難関ですが、最も重要な部分です。

---

# 第3部：Microsoft Azure との安全な連携（OIDC認証）

Terraform で Azure のリソースを作成するには、GitHub Actions に対して「Azure を操作する権限」を与える必要があります。

一昔前までは「ID とパスワード（シークレット）」を GitHub に保存する方法が主流でしたが、現在は推奨されていません。
本ガイドでは、Microsoft と GitHub が推奨する最新かつ最も安全な **OIDC (OpenID Connect) / Workload Identity Federation** という仕組みを使います。

---

## 3-1. なぜ「パスワード」を使ってはいけないのか？

これまでのやり方（サービスプリンシパルのシークレット）には、いくつかの大きな問題がありました。

1. **漏洩のリスク**: `client_secret` という強力なパスワードを GitHub に保存する必要があります。万が一これが漏れると、Azure 環境が乗っ取られます。
2. **有効期限の管理**: シークレットには有効期限（例：1年）があります。期限が切れるたびに、「Azureで再発行」→「GitHubにコピペ」という作業が発生し、忘れるとデプロイが止まります。

### OIDC (OpenID Connect) の革命

OIDC を使うと、**パスワード（シークレット）が一切不要**になります。
代わりに、「信頼関係（フェデレーション）」を結びます。

> 「GitHub の、このリポジトリ（`my-repo`）の、このブランチ（`main`）から来たリクエストなら、一時的にアクセス許可証（トークン）を渡していいよ」

と Azure 側に登録しておくのです。これにはパスワードが存在しないため、漏洩しようがなく、有効期限の更新作業も不要です。

---

## 3-2. 実践：Azure Entra ID (旧 Azure AD) の設定手順

それでは、実際に設定を行っていきましょう。Azure Portal での操作となります。
※ コマンドライン（Azure CLI）でも可能ですが、構造を理解するために最初は画面で行うことを推奨します。

### ステップ1：アプリの登録 (App Registration)
1. Azure Portal にログインし、**[Microsoft Entra ID]** に移動します。
2. 左メニューから **[アプリの登録]** (App registrations) を選択し、**[新規登録]** をクリックします。
3. 以下の通りに入力して作成します。
    - **名前**: `gh-actions-terraform-app` （任意の識別できる名前）
    - **アカウントの種類**: シングルテナント（デフォルトのまま）
    - **リダイレクト URI**: 空欄でOK
4. 作成後、**[概要]** ページに表示される以下の2つの値をメモ帳などに控えてください。後で GitHub Actions で使います。
    - **クライアント ID (Client ID)**
    - **テナント ID (Tenant ID)**

### ステップ2：フェデレーション資格情報の追加
ここが OIDC のキモとなる設定です。

1. 作成したアプリの左メニューから **[証明書とシークレット]** を選択します。
2. **[フェデレーション資格情報]** タブをクリックし、**[資格情報の追加]** を押します。
3. 「フェデレーション資格情報のシナリオ」で **[GitHub Actions による Azure リソースのデプロイ]** を選択します。
4. 以下の情報を入力します。
    - **組織 (Organization)**: あなたの GitHub ユーザー名（または組織名）
    - **リポジトリ (Repository)**: 今回使用するリポジトリ名
    - **エンティティタイプ**: `Branch` を選択
    - **GitHub ブランチ名**: `main` （※ main ブランチからのデプロイを許可する場合）
    - **名前**: `allow-main-branch` など（任意）
5. **[追加]** をクリックして完了です。

> [!IMPORTANT]
> **Pull Request で `plan` したい場合**
> ブランチ名 `main` だけを許可すると、Pull Request のとき（ブランチ名が違うため）に権限エラーになります。
> PR 時にも Terraform Plan を実行したい場合は、もう一度 [資格情報の追加] を行い、エンティティタイプで **[Pull Request]** を選択して追加登録してください。

### ステップ3：アクセス権限（RBAC）の付与
アプリを作っただけでは、まだ Azure リソース（仮想マシンなど）を作る権限を持っていません。サブスクリプションに対して権限を割り当てます。

1. Azure Portal で **[サブスクリプション]** を検索・選択します。
2. ターゲットとなるサブスクリプションを選択し、左メニューの **[アクセス制御 (IAM)]** をクリックします。
3. **[追加]** > **[ロールの割り当ての追加]** を選択します。
4. **ロール (Role)**:
    - 特権管理者になりたい場合: `Contributor` (共同作成者)
    - 権限管理も含めたい場合: `Owner` (所有者)
    - ※ 初学者の練習用であれば `Contributor` で十分です。
5. **メンバー (Members)**:
    - アクセスの割り当て先: `ユーザー、グループ、またはサービスプリンシパル`
    - **[メンバーを選択する]** をクリックし、先ほど作成したアプリ名 `gh-actions-terraform-app` を検索して選択します。
6. 設定を完了させます。

これで、Azure 側の準備は整いました。

---

## 3-3. GitHub Actions ワークフローからの接続

Azure へのログインには、公式アクション `azure/login` を使います。
まずは、控えておいたIDを GitHub リポジトリの Secret ではなく、**Variable (変数)** または **Secret** に登録します。これらは機密情報（パスワード）ではないので Variable でも構いませんが、慣習的に Secret に入れることも多いです。今回は Secret として登録しましょう。

### GitHub Secrets の設定
リポジトリの **[Settings]** > **[Secrets and variables]** > **[Actions]** に移動し、以下の3つを登録します。

- `AZURE_CLIENT_ID`: （メモしたクライアントID）
- `AZURE_TENANT_ID`: （メモしたテナントID）
- `AZURE_SUBSCRIPTION_ID`: （サブスクリプションID ※Azure Portalのサブスクリプション概要ページで確認）

### ワークフローファイル (YAML) の記述例

ここでの重要ポイントは `permissions` の設定です。OIDC を使うために、JWT トークンの書き込み権限が必要です。

```yaml
name: Azure Connection Test

on: [workflow_dispatch] # テスト用に手動実行ボタンを有効化

# OIDC 認証に必須の権限設定
permissions:
  id-token: write # これがないと OIDC は動きません！
  contents: read

jobs:
  test-login:
    runs-on: ubuntu-latest
    steps:
      - name: Log in to Azure
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Verify Login
        run: az account show
```

このワークフローを実行し、緑色のチェックマーク（成功）が出れば、GitHub Actions から Azure への「キーレス接続」は成功です！

---
（第3部 完）
次は、**Terraform の状態管理（State）** のためのバックエンド構築について解説します。ここを間違えると、チーム開発で事故が起きます。

---

# 第4部：Terraform の準備と状態管理 (State)

GitHub Actions で Terraform を動かす前に、「状態管理ファイル（tfstate）」の保管場所を決める必要があります。
これは Terraform 初学者が最初につまずくポイントですが、チーム開発や自動化においては絶対に避けて通れません。

---

## 4-1. State（ステート）ファイルとは？

Terraform は、現在のインフラの状態を `terraform.tfstate` という JSON 形式のファイルに記録しています。
Terraform は、以下のアクションを行う際、必ずこのファイルを参照します。

1. **現状の把握**: 今、Azure 上にどんなリソースがあるか？
2. **差分の計算**: あなたの書いたコードと、実際のリソースにどんな違いがあるか？

### ローカル管理の致命的な欠点
もし自分の PC 内だけで Terraform を実行していると、このファイルは PC のフォルダ内に作られます。
これを GitHub Actions でやろうとすると、以下の問題が起きます。

- **GitHub Actions は毎回クリーンな環境**: 実行が終わると環境は消滅します。つまり、`terraform.tfstate` も消えてしまいます。
- **結果**: 次回実行時、Terraform は「まだ何も作られていない」と勘違いし、既に存在するリソースを重複して作ろうとしてエラーになったり、意図せず破壊したりします。

**解決策**: State ファイルを、消えない安全な外部の場所（リモートバックエンド）に保存します。Azure の場合は **Azure Storage Account (Blob Storage)** が標準的な保存先です。

---

## 4-2. State 保存用ストレージアカウントの作成

Terraform を実行するための「準備としての箱」を、まずは手動（またはCLI）で作成します。
※ 鶏と卵の問題（Terraformの状態を保存する箱をTerraformで作るかどうか）がありますが、最初の箱だけは手動で作るのが一番シンプルでトラブルが少ないです。

### 手順
1. **リソースグループの作成**: State 管理専用のグループを作成します（例: `rg-tfstate-management`）。
2. **ストレージアカウントの作成**:
    - 名前: 全世界でユニークである必要があります（例: `tfstate12345`）。
    - 設定: パフォーマンスは「Standard」、冗長性は「LRS」で十分です。
3. **コンテナの作成**:
    - ストレージアカウント作成後、メニューから **[データストレージ]** > **[コンテナ]** を選択します。
    - **[+ コンテナ]** をクリックし、名前を付けます（例: `tfstate`）。
    - パブリックアクセスレベル: **「プライベート (匿名アクセスなし)」**（重要！インフラ情報が丸見えになるのを防ぐため）。

この作業で作成した以下の情報をメモしてください。
- **リソースグループ名** (`rg-tfstate-management`)
- **ストレージアカウント名** (`tfstate12345`)
- **コンテナ名** (`tfstate`)

---

## 4-3. Terraform コードでの設定 (Backend Block)

Terraform のコード（`main.tf`など）に、このストレージを使うよう指示を書きます。

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0" # バージョンはプロジェクトに合わせてください
    }
  }

  # ここが重要！バックエンド設定
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-management"  # 先ほど作ったRG
    storage_account_name = "tfstate12345"           # 先ほど作ったストレージ
    container_name       = "tfstate"                # 先ほど作ったコンテナ
    key                  = "prod.terraform.tfstate" # ファイル名（任意）
    use_oidc             = true                     # OIDCを使うための魔法の言葉
  }
}

provider "azurerm" {
  features {}
  use_oidc = true # プロバイダ側でもOIDCを有効化
}
```

### なぜ `use_oidc = true` なのか？
第3部で設定した OIDC 認証を使って、GitHub Actions がこのストレージアカウントにアクセスできるようにするためです。これがないと、ストレージへのアクセスキーなどを別途管理しなければならなくなります。OIDC はここでも威力を発揮します。

> [!WARNING]
> **アクセス権限の注意点**
> 前の章で作成した Azure アプリ（`gh-actions-terraform-app`）には、サブスクリプションへの貢献者権限を付けました。
> もし権限を厳密に絞っている場合、この State 用ストレージアカウントに対しても「ストレージ BLOB データ所有者」などの権限が必要になる場合があります。貢献者権限があれば通常は読み書き可能です。

これで、GitHub Actions が実行されるたびに、状態ファイルは Azure Storage から読み込まれ、変更があれば書き込まれるようになりました。消えることはありません。

---
（第4部 完）
いよいよ、これらを組み合わせて **完全自動化された CI/CD パイプライン** をコードに落とし込みます。実際に動く YAML を書いていきます。

---

# 第5部：実践！CI/CD パイプラインの構築

これまでの準備で、役者はすべて揃いました。
1.  **GitHub Actions**: 実行環境
2.  **OIDC**: 認証の鍵
3.  **Azure Storage**: 記憶領域 (State)

ここからは、実際の運用で使われる「2つのワークフロー」を構築します。
1.  **CI (PR作成時)**: コードをチェックし、`terraform plan` の結果を通知する。
2.  **CD (マージ時)**: 実際に `terraform apply` してリソースを作成する。

---

## 5-1. 戦略：Pull Request vs Main Branch

Terraform の運用で最も一般的なのは、以下のようなフローです。

1.  開発者がブランチ (`feature-x`) を切り、コードを修正する。
2.  Pull Request (PR) を作成する。
3.  **GitHub Actions が起動 (CI)**: `terraform plan` を実行し、「この変更でリソースがどう変わるか」を PR のコメントに自動投稿する。
4.  レビュアーが Plan 結果とコードを確認し、マージする。
5.  **GitHub Actions が起動 (CD)**: `terraform apply` が走り、本番環境に反映される。

この流れを1つの YAML ファイルで書くこともできますが、管理しやすくするために、ここでは1つのファイル内で `if` 条件分岐を使って記述する「統合型パターン」を紹介します。

---

## 5-2. 完成版ワークフロー (`terraform.yml`)

以下のコードを `.github/workflows/terraform.yml` として保存してください。
これが、現場でそのまま使えるレベルの「完成形」です。

```yaml
name: Terraform CI/CD

on:
  push:
    branches:
      - main
  pull_request:

permissions:
  id-token: write # OIDC用
  contents: read  # ソースコード読み取り用
  pull-requests: write # PRへのコメント投稿用

env:
  # 変数は Secrets から読み込むか、ここで直接定義
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  # Backend config (これらは公開してもリスク低だがSecret推奨)
  RESOURCE_GROUP: "rg-tfstate-management"
  STORAGE_ACCOUNT: "tfstate12345"
  CONTAINER_NAME: "tfstate"
  TF_KEY: "prod.terraform.tfstate"

jobs:
  terraform:
    name: "Terraform"
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash

    steps:
      # 1. コードのチェックアウト
      - name: Checkout
        uses: actions/checkout@v4

      # 2. Azure へのログイン (OIDC)
      # terraform-provider-azurerm が環境変数を読むため、
      # 実は azure/login アクションは必須ではない場合もあるが、
      # 明示的なログインはトラブルシュートで役立つため推奨。
      - name: 'Az CLI Login'
        uses: azure/login@v2
        with:
          client-id: ${{ env.ARM_CLIENT_ID }}
          tenant-id: ${{ env.ARM_TENANT_ID }}
          subscription-id: ${{ env.ARM_SUBSCRIPTION_ID }}

      # 3. Terraform のセットアップ
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.7 # プロジェクトに合わせて固定推奨

      # 4. コードのフォーマットチェック (CIのみ)
      - name: Terraform Format
        id: fmt
        run: terraform fmt -check

      # 5. 初期化 (Backend接続)
      - name: Terraform Init
        id: init
        run: |
          terraform init \
            -backend-config="resource_group_name=$RESOURCE_GROUP" \
            -backend-config="storage_account_name=$STORAGE_ACCOUNT" \
            -backend-config="container_name=$CONTAINER_NAME" \
            -backend-config="key=$TF_KEY"

      # 6. バリデーション (文法チェック)
      - name: Terraform Validate
        id: validate
        run: terraform validate -no-color

      # 7. Plan (変更予測の作成)
      # PRのときのみ実行する。失敗しても後続のステップで通知するために continue-on-error を使う場合もあるが、
      # 基本は失敗したら止めるのが安全。
      - name: Terraform Plan
        id: plan
        if: github.event_name == 'pull_request'
        run: terraform plan -no-color -input=false
        continue-on-error: true # エラーでもPRコメントしたい場合はtrue

      # 8. PRへの結果コメント (CIのみ)
      # 非常に便利なステップ。Planの結果を整形してPRに書き込む。
      - name: Update Pull Request
        uses: actions/github-script@v7
        if: github.event_name == 'pull_request'
        env:
          PLAN: ${{ steps.plan.outputs.stdout }}
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const output = `#### Terraform Format and Style 🖌\`${{ steps.fmt.outcome }}\`
            #### Terraform Initialization ⚙️\`${{ steps.init.outcome }}\`
            #### Terraform Validation 🤖\`${{ steps.validate.outcome }}\`
            #### Terraform Plan 📖\`${{ steps.plan.outcome }}\`

            <details><summary>Show Plan</summary>

            \`\`\`terraform
            ${process.env.PLAN}
            \`\`\`

            </details>

            *Pusher: @${{ github.actor }}, Action: \`${{ github.event_name }}\`*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.name,
              body: output
            })

      # 9. Plan Status Check
      # Planが失敗していたらここでワークフローも失敗させる
      - name: Terraform Plan Status
        if: steps.plan.outcome == 'failure'
        run: exit 1

      # 10. Apply (変更の適用)
      # mainブランチへのpush時、かつ、ここまでのステップが成功している場合のみ
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve -input=false
```

### コードの解説

#### `permissions: pull-requests: write`
ステップ8で `actions/github-script` を使って PR にコメントを書き込むために必要です。これがないと「403 Forbidden」エラーになります。

#### `-backend-config` の使用
`terraform init` の引数でバックエンド情報を渡しています。これにより、`main.tf` 内にハードコードした値ではなく、環境変数（Secrets）を使ってバックエンドを動的に構成でき、セキュリティと再利用性が向上します。

#### `actions/github-script`
JavaScript で GitHub API を直接叩ける強力なアクションです。ここでは `terraform plan` の実行結果（ログ）を見やすく整形して、Pull Request のコメント欄に投稿しています。
これにより、レビュアーはわざわざ Actions のログ画面を見に行かなくても、PR の会話の中で「インフラがどう変わるか」を確認できます。これは現代的な Terraform 運用の **ベストプラクティス** です。

---
（第5部 完）
最後に、さらに安全性を高めるための **「承認フロー (Environments)」** と、運用上の注意点について解説して締めくくります。

---

# 第6部：承認フローと運用のベストプラクティス

前章のワークフローは強力ですが、`main` ブランチにマージされた瞬間、問答無用で本番環境に変更が適用されます。
小規模なプロジェクトなら問題ありませんが、重要なシステムでは**「人間による最終確認（承認ボタン）」**を挟みたい場合があります。

GitHub Actions の **Environments (環境)** 機能を使うと、これを簡単に実現できます。

---

## 6-1. 手動承認 (Manual Approval) の設定

### GitHub 側の設定
1. リポジトリの **[Settings]** > **[Environments]** を開きます。
2. **[New environment]** をクリックし、`Production` という名前で作成します。
3. **[Deployment protection rules]** の中の **[Required reviewers]** にチェックを入れます。
4. 承認者（自分自身やチームリーダー）を指定して保存します。

### ワークフローの修正
承認フローを入れるためには、ワークフローを「Plan用のジョブ」と「Apply用のジョブ」に分割する必要があります。

```yaml
jobs:
  plan:
    name: "Terraform Plan"
    runs-on: ubuntu-latest
    # (Planの手順は前章と同じなので省略)
  
  apply:
    name: "Terraform Apply"
    needs: plan  # Planが終わらないと実行されない
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: Production # <--- ここが重要！
    
    steps:
      # (Checkout, Login, Setup, Init は必要。Apply だけ実行する)
      - name: Terraform Apply
        run: terraform apply -auto-approve
```

こうすることで、`apply` ジョブが始まる直前にワークフローが一時停止し、「Review deployments」というポップアップが出現します。指定された人が「Approve」ボタンを押さない限り、本番環境への変更は実行されません。
これにより、「うっかりマージしたら本番が壊れた」という事故を物理的に防ぐことができます。

---

## 6-2. 運用ベストプラクティス

最後に、長く運用していくためのヒントをまとめます。

### 1. バージョンを固定する
アクション (`uses`) や Terraform のバージョンは必ず固定しましょう。
- × `uses: actions/checkout@v4` (v4系の最新が使われる。ある日突然壊れるかも)
- ○ `uses: actions/checkout@v4.1.1` (確実)
- ◎ SHAハッシュ指定 (最も安全だが更新が手間)

Terraform 本体も `required_version` で固定し、プロバイダ (`azurerm`) もバージョンを固定することで、「昨日まで動いていたのに」を防げます。

### 2. コスト管理
Terraform でリソースを作るのは簡単ですが、消すのを忘れがちです。
学習用や検証用の環境であれば、一定時間で `terraform destroy` を実行するスケジュール実行 (`on: schedule`) のワークフローを作っておくと、クラウド破産を防げます。

### 3. シークレットスキャン
GitHub には、リポジトリに誤ってパスワードが含まれていないかチェックする機能があります (**Secret scanning**)。
パブリックリポジトリなら無料です。プライベートでも Enterprise プランなら使えます。これらを有効にしておくと、万が一 `main.tf` にパスワードを書き込んでプッシュしてしまっても、即座に検知してくれます。

---

## おわりに

お疲れ様でした！
これで、あなたは **GitHub Actions × Terraform × Azure** という現代的なインフラ運用の武器を手に入れました。

最初は「YAML を書くのが面倒」「画面でやったほうが早い」と思うかもしれません。
しかし、一度パイプラインを構築してしまえば、あとはコードを書いてプッシュするだけで、安全・確実・高速にインフラがデプロイされます。その快適さを一度味わうと、もう手動オペレーションには戻れないはずです。

ぜひ、このガイドを参考に、あなたのプロジェクトに自動化の風を吹き込んでください。
Happy Automating! 🚀

---

# 第7部：プロフェッショナルのための応用テクニックとトラブルシューティング

ここまでの内容で、基本的な運用は完璧です。
この章では、さらに一歩進んだ「プロの技」と、困ったときの「トラブルシューティング」を紹介します。

---

## 7-1. Matrix Strategy (マトリックス戦略)

「Terraform のバージョンを上げたいけど、既存のコードが壊れないか心配…」
そんなときは、Actions の **Matrix Strategy** を使って、複数のバージョンで同時にテストを実行できます。

```yaml
jobs:
  test-versions:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        tf-version: [1.5.0, 1.6.0, 1.7.0]
    
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ matrix.tf-version }}
      
      - run: terraform init
      - run: terraform validate
```
これで、GitHub は自動的に3つのジョブ並列に起動し、それぞれのバージョンで検証を行います。どれか1つでも失敗すれば、「バージョンアップには修正が必要」と即座にわかります。

---

## 7-2. Reusable Workflows (再利用可能なワークフロー)

マイクロサービスなどでリポジトリが10個、20個と増えてくると、すべてのリポジトリに同じ `terraform.yml` をコピー＆ペーストするのは悪夢です。
**Reusable Workflows** を使うと、1つのリポジトリ（例: `infra-modules`）に「共通のワークフロー」を置き、他のリポジトリからそれを呼び出すことができます。

### 呼び出される側 (ex: infra-modules/.github/workflows/tf-template.yml)
```yaml
name: Shared Terraform Workflow
on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
    secrets:
      CLIENT_ID:
        required: true

jobs:
  plan:
    # ... (いつものPlan処理)
```

### 呼び出す側 (各アプリリポジトリ)
```yaml
jobs:
  call-workflow:
    uses: my-org/infra-modules/.github/workflows/tf-template.yml@main
    with:
      environment: production
    secrets:
      CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
```
これにより、共通処理を修正したい場合は1箇所直すだけで、全リポジトリに反映されます。

---

## 7-3. トラブルシューティングガイド

初心者が必ず直面するエラーとその対処法をまとめました。

### Q1. "Error: AADSTS70021: No matching federated identity record found for presented assertion." が出る
**原因**: OIDC の信頼設定（フェデレーション）が間違っています。
**チェック項目**:
- Azure Portal の「アプリの登録」 > 「フェデレーション資格情報」を確認してください。
- リポジトリ名は正しいですか？ (`my-org/my-repo`)
- ブランチ名は正しいですか？ (`main` なのに `master` と書いていないか)
- エンティティタイプは合っていますか？ (`Branch` vs `Pull Request`)

### Q2. "Error: Error acquiring the state lock" が出る
**原因**: 前回の GitHub Actions が途中で強制終了したり、誰かが手動で実行していて、State ファイルがロックされています。
**対処法**:
- **安全な方法**: ロックが解除されるまで待つ（Azure Blob のリース期間）。
- **強引な方法**: `terraform force-unlock <LOCK_ID>` コマンドを実行する。
- **予防策**: ワークフローのタイムアウト時間を設定し、ゾンビプロセスが残らないようにする。

### Q3. "403 Forbidden" (GitHub Actions 上で)
**原因**: `GITHUB_TOKEN` の権限不足です。
**対処法**:
- YAML ファイルのトップレベルに `permissions` ブロックがあるか確認してください。
- 特に OIDC を使う場合は `id-token: write` が、PRコメントをする場合は `pull-requests: write` が必須です。

### Q4. Terraform の変更が反映されない (No changes)
**原因**: ローカルで `apply` してしまったか、ディレクトリ指定が間違っています。
**対処法**:
- `defaults: run: working-directory: ./terraform` のように、tfファイルがあるディレクトリを指定していますか？
- リポジトリのルートに `main.tf` がない場合、ディレクトリ移動が必要です。

---

## 7-4. 学習リソースと次のステップ

このガイドですべてをカバーすることはできませんが、基礎から応用まで強力な土台ができました。
さらに深く学ぶために、以下の公式サイトをブックマークすることをお勧めします。

- **GitHub Actions Documentation**: [https://docs.github.com/ja/actions](https://docs.github.com/ja/actions)
- **Terraform Azure Provider**: [https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- **Azure Architecture Center**: [https://learn.microsoft.com/ja-jp/azure/architecture/](https://learn.microsoft.com/ja-jp/azure/architecture/)

自動化の旅はここからが本番です。
あなたのインフラが、コードによって美しく管理され、堅牢に動作することを願っています。

---

# 付録：用語集とコマンドチートシート

## 用語集 (Glossary)

本ガイドで登場した重要用語をまとめました。迷ったときはここに戻って確認してください。

### GitHub Actions 関連
- **Workflow (ワークフロー)**: `.github/workflows` に定義される、自動化プロセス全体のこと。
- **Job (ジョブ)**: ワークフロー内で実行される一連の作業単位。デフォルトは並列実行。
- **Step (ステップ)**: ジョブ内の個々の手順（コマンド実行やアクション利用）。
- **Runner (ランナー)**: ジョブを実行するサーバー環境（例: `ubuntu-latest`）。
- **Event (イベント)**: ワークフローを開始するトリガー（例: `push`, `pull_request`）。
- **Artifact (アーティファクト)**: ワークフロー実行中に生成され、保存されるファイル（ログ、ビルド成果物など）。
- **Action (アクション)**: `uses:` で呼び出せる、共有された機能パーツ。

### Azure / OIDC 関連
- **Entra ID (旧 Azure AD)**: Microsoft の ID 管理サービス。
- **Service Principal (サービスプリンシパル)**: アプリケーションが Azure リソースにアクセスするための「ユーザーID」のようなもの。
- **Workload Identity Federation**: シークレット（パスワード）を使わずに、外部システム（GitHub）と信頼関係を結ぶ認証方式。推奨。
- **Tenant ID**: Azure Entra ID の組織全体を識別するID。
- **Subscription ID**: アプリやVMなどのリソースが属する課金・管理単位のID。

### Terraform 関連
- **State (ステート)**: インフラのあるべき姿と現状を記録したファイル (`.tfstate`)。
- **Backend (バックエンド)**: State ファイルの保存場所。Azure Blob Storage など。
- **Provider (プロバイダ)**: クラウド（Azure, AWS）と会話するためのプラグイン。
- **Plan**: 「実行すると何が起きるか」のシミュレーション。
- **Apply**: 実際の変更適用。

---

## コマンドチートシート (Command Reference)

開発中によく使うコマンドの抜粋です。

### Terraform コマンド

| コマンド | 説明 | 備考 |
| --- | --- | --- |
| `terraform init` | 初期化 | 最初に必ず実行。プロバイダのDLなどを行う。 |
| `terraform fmt` | 整形 | コードをきれいにフォーマットする。 |
| `terraform validate` | 検証 | 文法エラーがないかチェックする。 |
| `terraform plan` | 計画 | 変更内容のプレビューを表示。 |
| `terraform apply` | 適用 | 変更を実際に反映。`-auto-approve` で確認スキップ。 |
| `terraform destroy` | 削除 | 管理下にあるリソースをすべて削除。要注意。 |
| `terraform state list` | 確認 | State ファイルにあるリソース一覧を表示。 |
| `terraform force-unlock <ID>` | 解除 | ロックされた State を強制解除する。 |

### Azure CLI コマンド (デバッグ用)

| コマンド | 説明 | 備考 |
| --- | --- | --- |
| `az login` | ログイン | ブラウザ経由で Azure にログイン。 |
| `az account show` | 確認 | 現在ログイン中のサブスクリプション情報を表示。 |
| `az account set -s <ID>` | 切替 | 操作対象のサブスクリプションを変更。 |
| `az group list` | 一覧 | リソースグループの一覧を表示。 |
