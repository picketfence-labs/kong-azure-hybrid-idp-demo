# Group 2（ADFSグループ）専用インフラのTerraform変数。
# design-brief Group2「3. アーキテクチャ」の通り、picketfence自身のAzureサブスクリプション＋
# Entra IDテナント（Kong社のkongstrong.onmicrosoft.comとは別）に構築するため、
# terraform/providers.tfの既定プロバイダとは別に専用のプロバイダエイリアス
# （azurerm.picketfence / azuread.picketfence、terraform/adfs_providers.tf）で管理する。

variable "picketfence_azure_subscription_id" {
  description = "ADFS/Entra Domain Services等を構築するpicketfence自身のAzureサブスクリプションID（Kong社のものとは別）"
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

variable "entra_domain_services_domain_name" {
  description = <<-EOT
    Microsoft Entra Domain Services（マネージドドメイン）のDNSドメイン名。
    テナントの既定ドメイン（*.onmicrosoft.com）とは別の、どこにも登録されていない
    ドメイン名を指定する必要がある（Microsoft公式要件）。例: "adfsdemo.picketfencelabs.local"
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
  description = "ADFSサーバー用VMのサイズ。デモ用途のため最小構成（継続コストを抑える、CLAUDE.mdエスカレーション条件2番目参照）"
  type        = string
  default     = "Standard_B2s"
}

variable "adfs_vm_admin_username" {
  description = "ADFSサーバーVMのローカル管理者ユーザー名（ドメイン参加後は使わない。ADFSロール構成自体はdocs/adfs-setup-runbook.mdの通りドメイン管理者アカウントで行う、ADR-0001参照）"
  type        = string
  default     = "adfsvmadmin"
}
