# Microsoft Entra Domain Services（マネージドドメイン、design-brief Group2「3. アーキテクチャ」）。
# HashiCorp公式ドキュメントのazurerm_active_directory_domain_service標準構成に準拠。
# 実際のterraform applyでの検証はまだ行っていない（az login未実施、docs/troubleshooting-log.md参照）。

# Microsoft Entra Domain Services（AADDS）の第一者アプリのサービスプリンシパル。
# テナントで初めてAADDSを有効化する際にこの手順で作成する（Microsoft公式ドキュメント記載の
# 既知のアプリID、全テナント共通）。
resource "azuread_service_principal" "domain_services" {
  provider  = azuread.picketfence
  client_id = "2565bd9d-da50-47d4-8b85-4c97f669dc36"
}

# Entra Domain Servicesの管理者グループ（グループ名"AAD DC Administrators"は公式要件で固定）。
resource "azuread_group" "aadds_admins" {
  provider         = azuread.picketfence
  display_name     = "AAD DC Administrators"
  security_enabled = true
  description      = "Microsoft Entra Domain Servicesの管理者グループ（Entra Domain Services公式要件、グループ名固定）"
}

resource "azurerm_role_assignment" "aadds_network_contributor" {
  provider             = azurerm.picketfence
  scope                = azurerm_subnet.domain_services.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.domain_services.object_id
}

# ADFS VMのドメイン参加（terraform/adfs_vm.tf）、および将来docs/adfs-setup-runbook.mdで
# ADFSロール・ファーム構築を行う際に使う専用のドメイン管理者アカウント。
# 「terraform applyを実行した人物」のEntra ID資格情報をTerraformから扱うことはできない
# （パスワードを知り得ない）ため、生成パスワード付きの専用アカウントを用意する
# （terraform/users.tfのtest_userと同じパターン）。
resource "random_password" "domain_join_admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%^&*()-_=+"
}

resource "azuread_user" "domain_join_admin" {
  provider              = azuread.picketfence
  user_principal_name   = "adfs-domain-admin@${local.picketfence_default_domain}"
  display_name          = "ADFS Domain Admin (demo)"
  mail_nickname         = "adfs-domain-admin"
  password              = random_password.domain_join_admin.result
  force_password_change = false
}

resource "azuread_group_member" "aadds_admin_domain_join" {
  provider         = azuread.picketfence
  group_object_id  = azuread_group.aadds_admins.object_id
  member_object_id = azuread_user.domain_join_admin.object_id
}

resource "azurerm_active_directory_domain_service" "this" {
  provider            = azurerm.picketfence
  name                = "adfs-demo-dc"
  location            = azurerm_resource_group.adfs.location
  resource_group_name = azurerm_resource_group.adfs.name

  domain_name           = var.entra_domain_services_domain_name
  sku                   = "Standard"
  filtered_sync_enabled = false

  initial_replica_set {
    subnet_id = azurerm_subnet.domain_services.id
  }

  notifications {
    additional_recipients = []
    notify_dc_admins      = true
    notify_global_admins  = true
  }

  security {
    sync_kerberos_passwords = true
    sync_ntlm_passwords     = true
    sync_on_prem_passwords  = true
  }

  depends_on = [
    azurerm_role_assignment.aadds_network_contributor,
    azuread_group_member.aadds_admin_domain_join,
  ]
}
