# Terraform for Azure 完全入門ガイド

> **対象読者**: Azure でインフラ構築を始めたい方、Terraform の基礎から実践までを体系的に学びたい方
> **作成日**: 2026/01/12
> **バージョン**: 1.0

このガイドでは、**Azure Container Instances (ACI)** と **Linux Virtual Machine (VM)** を組み合わせた実用的な構成を題材に、Terraform による Infrastructure as Code (IaC) のベストプラクティスを解説します。
初心者の方でも躓かないよう、図解と詳細な解説を交えて進めていきます。

---

# Part 1: 基礎と準備

## 1. はじめに：Terraform とは？

### インフラを「コード」で管理する (Infrastructure as Code)
従来、サーバーやネットワークの構築は、Webブラウザ（Azure Portal）をポチポチとクリックして設定していくのが一般的でした。しかし、システムが大きくなると、「あの設定、どこだっけ？」「同じ環境をもう一つ作って」と言われたときに大変な思いをすることになります。

**Terraform（テラフォーム）** は、インフラの構成を「コード（テキストファイル）」として記述し、それをコマンド一つで自動構築するためのツールです。これを **Infrastructure as Code (IaC)** と呼びます。

> [!NOTE]
> **初心者のためのイメージ**
> *   **手動構築 (Azure Portal)**: 積み木を一つ一つ手で積んでお城を作る作業。崩れたらまた手で積み直し。
> *   **Terraform**: お城の「設計図」と「3Dプリンター」を用意する作業。ボタンを押せば、設計図通りに何度でもまったく同じお城が自動で作られます。

### なぜ Azure × Terraform なのか？
Azure には標準で **ARM Template** や **Bicep** というツールがありますが、Terraform は以下の理由で世界中で愛用されています。
1.  **見やすい**: 人間が読みやすい言語 (HCL) で書かれています。
2.  **マルチクラウド**: AWS や Google Cloud も同じ文法で管理できます。
3.  **情報が多い**: 世界標準のツールなので、困ったときに検索しやすいです。

---

## 2. 環境構築：開発の準備をしよう

Terraform を使うための「三種の神器」を揃えます。

1.  **Visual Studio Code (VS Code)**: コードを書くエディタ
2.  **Azure CLI**: パソコンから Azure を操作するコマンドツール
3.  **Terraform CLI**: 実際に構築を行うエンジン

### (1) Visual Studio Code の準備
まだインストールしていない場合は、公式サイトからインストールしてください。
インストール後、以下の拡張機能を入れると便利です。
*   **HashiCorp Terraform**: コードの色分けや補完をしてくれます。
*   **Japanese Language Pack**: VS Code を日本語化します。

### (2) Azure CLI のインストール
コマンドプロンプトやターミナル（PowerShell）から Azure に接続するために必要です。
*   **Windows**: インストーラーをダウンロードして実行。
*   **Mac**: `brew update && brew install azure-cli`

確認コマンド:
```bash
az version
```

Azure へのログイン:
```bash
az login
```
これでお使いのブラウザが開き、Azure アカウントでのログインが求められます。ログインに成功すると、ターミナルにアカウント情報が表示されます。

### (3) Terraform のインストール
*   **Windows**:
    1.  公式サイトからバイナリ（zip）をダウンロード。
    2.  `terraform.exe` を任意のフォルダ（例: `C:\bin`）に置く。
    3.  そのフォルダに環境変数 `Path` を通す。
    *   ※または、パッケージマネージャ `Chocolatey` を使っている場合は `choco install terraform` で一発です。
*   **Mac**:
    ```bash
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
    ```

確認コマンド:
```bash
terraform -version
```
バージョン番号が表示されれば準備完了です！

---

## 3. Terraceform の基本概念

Terraform で登場する主な用語を、建設現場に例えて解説します。

| 用語 | ファイル上の記述 | 意味・役割 |
| :--- | :--- | :--- |
| **Provider** (プロバイダー) | `provider "azurerm" {...}` | **「専門業者」**です。<br>Azure用の業者、AWS用の業者などがいます。今回は「Azure業者」を呼び出します。 |
| **Resource** (リソース) | `resource "..." "..." {...}` | **「建材・設備」**です。<br>仮想マシン、ネットワーク、ストレージなど、実際に作るモノを定義します。 |
| **Variable** (バリアブル) | `variable "..." {...}` | **「パラメータ」**です。<br>「作成する場所（リージョン）」や「サーバーのサイズ」など、後で変更したい値を外出しにします。 |
| **State** (ステート) | `terraform.tfstate` | **「台帳」**です。<br>Terraform が「今、実際に何を作ったか」を記録している超重要なファイルです。絶対に手で編集してはいけません。 |

### ライフサイクル (作業の流れ)

Terraform での作業は、以下の 4 ステップの繰り返しです。

1.  **`terraform init` (初期化)**
    *   現場事務所を開設するイメージです。必要な Provider（Azure業者）をダウンロードしてきます。最初に1回だけ実行します。
2.  **`terraform plan` (計画確認)**
    *   「実行計画」を確認します。「これを実行すると、リソースが 3 つ追加され、1 つ削除されます」といった内容が表示されます。**ここでしっかり確認することが事故防止の鍵です。**
3.  **`terraform apply` (適用)**
    *   実際に着工します。Azure 上にリソースが作られます。途中で「本当に実行していいですか？」と聞かれるので `yes` と入力します。
4.  **`terraform destroy` (破棄)**
    *   作ったものを全て壊します。検証環境の片付けなどに使います。

> [!IMPORTANT]
> **初心者がハマるポイント: State ファイル**
> フォルダの中にできる `terraform.tfstate` というファイルは、Terraform にとっての「記憶」そのものです。これを消してしまうと、Terraform は「自分が何を作ったか」を忘れてしまい、既存のサーバーを管理できなくなってしまいます。

---

# Part 2: 設計とベストプラクティス

いきなりコードを書き始める前に、「長期間、安全に、チームで運用するため」の設計ルール（ベストプラクティス）を学びましょう。
これは「家を建てる前の地盤調査」のようなものです。ここをサボると後で苦労します。

## 1. ディレクトリ構成：整理整頓の基本

すべてのコードを `main.tf` 1ファイルに書くこともできますが、コードが長くなると読むのが大変になります。
標準的な構成（Standard Module Structure）に従ってファイルを分割するのが鉄則です。

| ファイル名 | 役割 |
| :--- | :--- |
| `main.tf` | 主役です。リソースの定義（VMやネットワークなど）を書きます。 |
| `variables.tf` | 変数の定義。パラメータの「型」や「デフォルト値」をここで決めておきます。 |
| `outputs.tf` | 出力値の定義。作成されたリソースのIPアドレスやIDなどを画面に表示したいときに使います。 |
| `versions.tf` | Terraform 本体や Provider のバージョンを固定するための設定を書きます。 |
| `terraform.tfvars` | 変数の「中身（具体的な値）」を入れるファイルです。（※Gitにはコミットしません） |

### なぜファイルを分けるの？
「変数は `variables.tf` を見ればわかる」「何が作られるかは `main.tf` を見ればわかる」というように、情報の置き場所を決めておくことで、自分も他人もコードを読みやすくなるからです。

## 2. 命名規則：名前は重要

Azure のリソースには名前が必要です。適当に `test-vm` とか `myserver` と付けると、後で「これ何だっけ？」「本番用？テスト用？」と混乱します。
Microsoft が推奨する **Cloud Adoption Framework (CAF)** に準拠した命名規則を使うのがベストです。

**基本フォーマット:**
`[リソース種類の省略名]-[アプリ名]-[環境]-[リージョン]-[連番]`

**構成例:**
*   **リソースグループ**: `rg-mywebapp-dev-japaneast-001`
*   **仮想ネットワーク**: `vnet-mywebapp-dev-japaneast-001`
*   **仮想マシン**: `vm-web-01` （※VM名は文字数制限が厳しいので短縮することもあります）

> [!TIP]
> **省略名の例**
> *   Resource Group → `rg`
> *   Virtual Network → `vnet`
> *   Network Security Group → `nsg`
> *   Container Group → `ci` (Container Instance)
> *   Key Vault → `kv`

## 3. Remote State：状態ファイルの管理場所をクラウドへ

Part 1 で解説した「台帳」である `terraform.tfstate` ファイル。
これをローカルPC（自分のパソコンの中）に置いておくのは**非常に危険**です。

### ローカル管理のリスク
1.  **PCが壊れたら終わり**: インフラの管理不能になります。
2.  **チーム開発できない**: AさんとBさんが同時に作業すると、お互いの変更で上書きして破損する可能性があります。
3.  **セキュリティ**: パスワードなどの機密情報が平文で保存されていることがあります。

### 解決策: Azure Storage Account で管理する
State ファイルを Azure のストレージアカウント（Blob Storage）に保存します。これを **Remote State** と呼びます。

**メリット:**
*   **堅牢性**: Azure が守ってくれるので消える心配がありません。
*   **排他制御 (Locking)**: 誰かが `terraform apply` している間は、他の人が実行できないように自動でロックがかかります。これで競合事故を防げます。

### 構成イメージ
```mermaid
graph LR
    User[開発者] -->|terraform apply| Terraform
    Terraform -->|Read/Write| State[terraform.tfstate<br>(Azure Storage Blob)]
    Terraform -->|Create/Update| Azure[Azure Resources]
```

初心者のうちはローカルで練習しても構いませんが、**「本番運用するなら絶対に Remote State」** と覚えておいてください。

---

# Part 3: インフラ構築の実践

いよいよ実際にコードを書いてインフラを構築していきます。
ここでは、ベストプラクティスに基づいた「安全で拡張性の高い」構成を作成します。

## 作成する構成図

```mermaid
graph TB
    subgraph Azure[Azure Cloud (Japan East)]
        RG[Resource Group] --> VNet[Virtual Network]
        VNet --> SubnetVM[Subnet: snet-vm]
        VNet --> SubnetCont[Subnet: snet-container]
        
        SubnetVM --> NIC[NIC]
        NIC --> VM[Linux VM (Ubuntu)]
        
        SubnetCont --> ACI[Container Instance (Nginx)]
        
        Internet((Internet)) -->|SSH (22)| VM
        Internet -->|HTTP (80)| ACI
    end
```

## 1. プロジェクトの初期化 (versions.tf)

まずは `versions.tf` を作成し、Terraform と Azure Provider のバージョンを固定します。
これは「どの道具を使うか」を宣言する重要なファイルです。

```hcl
# versions.tf

terraform {
  # Terraform 本体のバージョンを指定 (1.5.0以上)
  required_version = ">= 1.5.0"

  required_providers {
    # Azure用プロバイダー (azurerm) のバージョン指定
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0" # メジャーバージョン3系を使用
    }
  }

  # リモートステートの設定 (Part 2で解説。練習時はコメントアウトでも可)
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstatexxxx"
  #   container_name       = "tfstate"
  #   key                  = "prod.terraform.tfstate"
  # }
}

provider "azurerm" {
  features {} # おまじない。空でも必須です。
}
```

## 2. 変数の定義 (variables.tf)

ハードコーディング（値を直接書き込むこと）は避け、`variables.tf` で変数を定義します。
これにより、後から「場所を変えたい」「名前のプレフィックスを変えたい」といった変更に数秒で対応できます。

```hcl
# variables.tf

variable "prefix" {
  description = "リソース名の接頭辞 (例: demo)"
  type        = string
  default     = "demo"
}

variable "location" {
  description = "リソースを作成するリージョン"
  type        = string
  default     = "japaneast" # 東日本
}

variable "ssh_public_key" {
  description = "VMログイン用のSSH公開鍵"
  type        = string
  sensitive   = true # ログに出力されないようにマスクする
}
```

## 3. ネットワークの構築 (main.tf - Network)

まずは土台となるネットワークを作成します。
`main.tf` に記述していきます。

### リソースグループ
すべてのリソースを入れる「箱」です。

```hcl
# main.tf

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}-resources"
  location = var.location
  
  tags = {
    Environment = "Dev"
    ManagedBy   = "Terraform"
  }
}
```

### 仮想ネットワーク (VNet) とサブネット
家を建てるための「土地」と「区画」です。
今回は VM 用とコンテナ用で区画（サブネット）を分けます。これはセキュリティの基本です。

```hcl
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.prefix}-network"
  address_space       = ["10.0.0.0/16"] # 大きなアドレス空間
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# VM用のサブネット
resource "azurerm_subnet" "vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# コンテナ用のサブネット (将来的なVNet統合のため)
resource "azurerm_subnet" "container" {
  name                 = "snet-container"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
  
  # ACIをVNetに入れる場合に必要な設定 (今回はPublic ACIのため必須ではないが入れておく)
  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}
```

## 4. Linux 仮想マシンの構築 (main.tf - VM)

いよいよサーバーを立てます。
VM の作成には「パブリックIP」「NIC (LANカード)」「VM本体」の3点セットが必要です。

### パブリックIP & NIC
外部から SSH できるように IP を払い出します。

```hcl
resource "azurerm_public_ip" "vm" {
  name                = "pip-${var.prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static" # IPが変わらないように静的に固定
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-${var.prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}
```

### ネットワークセキュリティグループ (NSG)
「ファイアウォール」です。デフォルトでは全て拒否されているため、SSH (Port 22) だけ穴を開けます。

```hcl
resource "azurerm_network_security_group" "vm" {
  name                = "nsg-${var.prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" # 本番では自分のIPだけに制限してください
    destination_address_prefix = "*"
  }
}

# NSGをNICに関連付け
resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}
```

### Linux VM 本体
Ubuntu 22.04 を使用します。
認証には **SSH鍵** を使用します（パスワード認証はセキュリティ的に非推奨です）。

```hcl
resource "azurerm_linux_virtual_machine" "main" {
  name                = "vm-${var.prefix}-01"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B1s" # 安価なバースト可能インスタンス
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.vm.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = var.ssh_public_key # 変数から読み込み
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # 安価なHDD
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  
  # マネージドID (システム割り当て) を有効化
  # これにより、Azure CLIなどでログインせずに他のAzureリソースへアクセス可能になります
  identity {
    type = "SystemAssigned"
  }
}
```

## 5. コンテナの構築 (main.tf - ACI)

VM を立てるまでもない小規模なアプリやジョブには、**Azure Container Instances (ACI)** が最適です。
Kubernetes (AKS) は高機能ですが、初心者が触るには複雑すぎます。まずは ACI で「コンテナをコードでデプロイする」体験をしましょう。

ここでは、サンプルの Nginx サーバーを立ち上げます。

```hcl
resource "azurerm_container_group" "main" {
  name                = "ci-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_address_type     = "Public" 
  dns_name_label      = "aci-${var.prefix}-demo" # URLの一部になります
  os_type             = "Linux"

  container {
    name   = "hello-nginx"
    image  = "nginx:latest" # Docker Hubから取得
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 80
      protocol = "TCP"
    }
  }

  tags = {
    Environment = "Dev"
  }
}
```

### 解説: なぜ ACI なのか？
*   **サーバーレス**: VM の管理（OSアップデートなど）が不要です。
*   **起動が速い**: 数秒でコンテナが立ち上がります。
*   **安い**: 実行している秒数分だけ課金されます。

このコードにより、`http://aci-demo-demo.<region>.azurecontainer.io` というURLで Nginx の画面が見られるようになります。

---

# Part 4: 運用とトラブルシューティング

コードが完成しました！ここからは実際にコマンドを実行して、Azure 上にリソースを構築（デプロイ）する手順を解説します。
「コマンドを実行するのが怖い」という初心者の方も多いですが、Terraform には **「実行前に何が起きるか確認する機能 (Plan)」** があるので安心してください。

## 1. 運用のワークフロー (基本の4ステップ)

日々の運用は、以下のコマンドの繰り返しです。

### Step 1: 初期化 (`terraform init`)
プロジェクトフォルダで最初に1回だけ実行します。

```bash
terraform init
```

**何が起きている？**
*   Azure と会話するためのプラグイン (`provider "azurerm"`) をダウンロードしています。
*   成功すると `Terraform has been successfully initialized!` という緑色の文字が表示されます。

### Step 2: 構文チェックと修正 (`terraform fmt` / `valdiate`)
コードが正しいかチェックします。

```bash
# コードのフォーマットを整える（インデントなどを綺麗にする）
terraform fmt

# 文法ミスがないかチェックする
terraform validate
```

`Success! The configuration is valid.` と出ればOKです。

### Step 3: 実行計画の確認 (`terraform plan`)
**これが最重要コマンドです。**
いきなり本番環境を変更するのではなく、「シミュレーション」を行います。

```bash
terraform plan
```

実行すると、大量のログが表示されますが、最後の行に注目してください。

```text
Plan: 7 to add, 0 to change, 0 to destroy.
```

*   **`+` (緑色)**: 新しく作られるリソース
*   **`~` (黄色)**: 設定が変更されるリソース
*   **`-` (赤色)**: 削除されるリソース

**チェックポイント:**
*   意図せず `destroy` (削除) が含まれていませんか？
*   リソースの名前や作成場所は合っていますか？

### Step 4: 適用 (`terraform apply`)
計画に問題なければ、実際に構築を行います。

```bash
terraform apply
```

再度、実行計画が表示され、最後に確認を求められます。

```text
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: 
```

ここで **`yes`** と入力して Enter を押すと、構築が始まります。
数分後（ACIやVMなら 3〜5分程度）、`Apply complete!` と表示されれば成功です！

---

## 2. 構築後の確認と接続

Azure Portal を見てみましょう。指定したリソースグループの中に、VM やネットワークができているはずです。

### Linux VM への SSH 接続
Part 3 で、SSH 鍵を使って作成しました。
接続するには、VM のパブリック IP アドレスが必要です。Portal で確認するか、以下のコマンドで出力できます（`outputs.tf` を作っている場合）。

```bash
ssh -i <秘密鍵のパス> adminuser@<VMのパブリックIP>
```

> [!NOTE]
> `ssh-keygen` で鍵を作った場合、秘密鍵は通常 `~/.ssh/id_rsa` にあります。

### コンテナ (ACI) へのアクセス
ブラウザを開き、設定した FQDN (例: `http://aci-demo-jae.japaneast.azurecontainer.io`) にアクセスします。
"Welcome to nginx!" の画面が表示されれば大成功です。

---

## 3. インフラの変更と削除

### 設定を変更するには？
例えば、「VM のサイズを大きくしたい」「コンテナの数を増やしたい」といった場合、コード (`main.tf`) を書き換えて保存します。

その後にやることは同じです。
1.  `terraform plan` → 「変更点」だけが表示されます（差分更新）。
2.  `terraform apply` → 変更だけが適用されます。

### 環境を削除するには？ (`terraform destroy`)
検証が終わってリソースを消したいときは、以下のコマンドを使います。

```bash
terraform destroy
```

これも `plan` と同じように「本当に消していいですか？」と聞かれるので、`yes` と入力します。
リソースグループごと全部消えるので、課金も止まります。

---

## 4. トラブルシューティング (よくあるエラー)

初心者が遭遇しやすいエラーとその対処法です。

### Q1. `Error: locking state`
**原因**: 前回のコマンドが異常終了したり、別のターミナルで実行中の場合に起きます。
**対処**: 
*   他に実行しているプロセスがないか確認する。
*   絶対に誰も実行していないと確信できる場合のみ、エラーメッセージに表示されている `LockID` を使ってロックを強制解除します（`terraform force-unlock <ID>`）。※慎重に！

### Q2. `Error: resource already exists`
**原因**: Terraform で作ろうとしたリソースが、既に Azure 上に（手動など別の方法で）存在しています。
**対処**:
*   Terraform 管理下にインポートする (`terraform import`)。
*   または、既存のリソースを削除してから再度実行する。

### Q3. `Status=400` や `Status=404`
**原因**: パラメータが間違っていることが多いです。
*   VM の名前やパスワードの要件（大文字小文字必須など）を満たしていない。
*   存在しないリージョンや SKU を指定している。
**対処**: エラーメッセージの英文をよく読みましょう。"InvalidParameter" などのヒントが必ず書いてあります。

---

# Appendix A: 完全なソースコード

コピペして使えるように、すべてのファイルの完成形をここに掲載します。

### `versions.tf`
```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
provider "azurerm" {
  features {}
}
```

### `variables.tf`
```hcl
variable "prefix" {
  description = "Prefix for all resources"
  type        = string
  default     = "demo"
}
variable "location" {
  description = "Azure Region"
  type        = string
  default     = "japaneast"
}
variable "ssh_public_key" {
  description = "SSH Public Key"
  type        = string
  sensitive   = true
}
```

### `main.tf`
```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}-resources"
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "container" {
  name                 = "snet-container"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "vm" {
  name                = "pip-${var.prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-${var.prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_network_security_group" "vm" {
  name                = "nsg-${var.prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_linux_virtual_machine" "main" {
  name                = "vm-${var.prefix}-01"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [azurerm_network_interface.vm.id]
  admin_ssh_key {
    username   = "adminuser"
    public_key = var.ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

resource "azurerm_container_group" "main" {
  name                = "ci-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_address_type     = "Public"
  dns_name_label      = "aci-${var.prefix}-demo"
  os_type             = "Linux"
  container {
    name   = "hello-nginx"
    image  = "nginx:latest"
    cpu    = "0.5"
    memory = "1.5"
    ports {
      port     = 80
      protocol = "TCP"
    }
  }
}
```

---

# Appendix B: 用語集 (Glossary)

| 用語 | 読み方 | 意味 |
| :--- | :--- | :--- |
| **Terraform** | テラフォーム | HashiCorp社が開発したIaCツール。 |
| **IaC** | アイエーシー | Infrastructure as Code。インフラをコード化すること。 |
| **HCL** | エイチシーエル | HashiCorp Configuration Language。Terraformの設定を記述する言語。 |
| **Provider** | プロバイダー | 各クラウド（Azure, AWSなど）を操作するためのプラグイン。 |
| **State** | ステート | Terraformが管理するインフラの現在の状態を記録したファイル。 |
| **Idempotency** | 冪等性（べきとうせい） | 何度実行しても同じ結果になる性質のこと。IaCの重要な特徴。 |
| **ACI** | エーシーアイ | Azure Container Instances。サーバーレスでコンテナを実行できるサービス。 |

---

# おわりに

これで、Terraform を使った Azure インフラ構築の基礎は完了です。
このガイドが、あなたの「コードによるインフラ管理」への第一歩となれば幸いです。

Happy Terraforming! 🚀
