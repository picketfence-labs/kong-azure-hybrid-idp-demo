# Group 2（ADFSグループ）専用インフラのTerraform変数。
# design-brief Group2「3. アーキテクチャ」の通り、picketfence自身のAzureサブスクリプション＋
# Entra IDテナント（Kong社のkongstrong.onmicrosoft.comとは別）に構築するため、
# terraform/providers.tfの既定プロバイダとは別に専用のプロバイダエイリアス
# （azurerm.picketfence / azuread.picketfence、terraform/adfs_providers.tf）で管理する。

variable "picketfence_azure_subscription_id" {
  description = "ADFS/自己管理AD DS等を構築するpicketfence自身のAzureサブスクリプションID（Kong社のものとは別）"
  type        = string
}

variable "picketfence_azure_tenant_id" {
  description = "picketfence自身のEntra IDテナントID（Kong社のkongstrong.onmicrosoft.comとは別）"
  type        = string
}

variable "adfs_location" {
  description = "ADFS関連リソースを作成するAzureリージョン"
  type        = string
  default     = "japaneast"
}

variable "ad_ds_domain_name" {
  description = <<-EOT
    自己管理AD DSフォレスト（terraform/adfs_domain_controller.tf、ADR-0005 Option A）のDNSドメイン名。
    外部に公開・登録されていない名前を使う（AD DSの一般的なベストプラクティス。ここでは
    ".local"の内部限定名を使う）。例: "adfsdemo.picketfencelabs.local"
  EOT
  type        = string
}

variable "nsg_allowed_source_cidr" {
  description = <<-EOT
    ADFSのOIDCエンドポイント（443番ポート）およびADFS VMへのRDP（3389番ポート）へのアクセスを
    許可する発信元IP（Kong実行環境・作業端末のグローバルIP）。CIDR形式（例: "203.0.113.10/32"）。
    design-brief Group2「3. アーキテクチャ」: NSGで発信元IPを許可リスト化する方式。
  EOT
  type        = string
}

variable "adfs_vm_size" {
  description = "ADFSサーバー用VMのサイズ。東日本で利用可能な2 vCPU・4 GiBのx64最小構成"
  type        = string
  default     = "Standard_D2als_v7"
}

variable "dc_vm_size" {
  description = "自己管理AD DSフォレストのDC用VMのサイズ。ADFSサーバー用VMと同じ理由（東日本のvCPUクォータ制約）で同サイズを既定値にする"
  type        = string
  default     = "Standard_D2als_v7"
}

variable "adfs_vm_admin_username" {
  description = "ADFSサーバーVMのローカル管理者ユーザー名（ドメイン参加後は使わない。ADFSロール構成自体はdocs/adfs-setup-runbook.mdの通りドメイン管理者アカウントで行う、ADR-0001参照）"
  type        = string
  default     = "adfsvmadmin"
}
