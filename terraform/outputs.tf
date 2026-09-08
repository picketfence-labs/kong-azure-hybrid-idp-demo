output "auth_check" {
  description = "Terraformが現在どのEntra IDテナント/Azureサブスクリプションに対して認証されているかの確認用"
  value = {
    entra_tenant_id       = data.azuread_client_config.current.tenant_id
    entra_object_id       = data.azuread_client_config.current.object_id
    azure_subscription_id = data.azurerm_client_config.current.subscription_id
  }
}

output "entra_tenant_id" {
  description = "Kong openid-connectプラグインのissuer設定に使うテナントID"
  value       = data.azuread_client_config.current.tenant_id
}

output "middle_tier_client_id" {
  description = "Kong openid-connectプラグインのclient_id（ログイン用Route・MCP用Route共通）"
  value       = azuread_application.middle_tier.client_id
}

output "middle_tier_client_secret" {
  description = "Kong openid-connectプラグインのclient_secret"
  value       = azuread_application_password.middle_tier.value
  sensitive   = true
}

output "middle_tier_application_id_uri" {
  description = "ログイン時にKongが要求するscope（<この値>/access_as_user）"
  value       = azuread_application_identifier_uri.middle_tier.identifier_uri
}

output "downstream_api_application_id_uri" {
  description = "OBO交換時にKongが要求するscope（<この値>/.default）。design-brief: audienceはscopeで指定する"
  value       = azuread_application_identifier_uri.downstream_api.identifier_uri
}

output "group_ai_agent_object_id" {
  description = "「AIエージェント」用Security GroupのObject ID"
  value       = azuread_group.ai_agent.object_id
}

output "group_api_customer_inquiry_object_id" {
  description = "Customer Inquiry Tool用Security GroupのObject ID（decKのai-mcp-proxy ACL allowリストに使う）"
  value       = azuread_group.api_customer_inquiry.object_id
}

output "group_api_customer_details_object_id" {
  description = "Customer Details Tool用Security GroupのObject ID（decKのai-mcp-proxy ACL allowリストに使う）"
  value       = azuread_group.api_customer_details.object_id
}

output "azure_openai_endpoint" {
  description = "ai-proxy-advancedプラグインのupstream URLに使うAzure OpenAIエンドポイント"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "azure_openai_deployment_name" {
  description = "ai-proxy-advancedプラグインのdeployment_idに使うモデルデプロイ名"
  value       = azurerm_cognitive_deployment.gpt_5_mini.name
}

output "azure_openai_api_key" {
  description = "ai-proxy-advancedプラグインのAPIキー"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "test_user_credentials" {
  description = "検証用ユーザーのサインイン情報（ブラウザでのログイン確認用）"
  value = {
    for key, user in azuread_user.test_user : key => {
      user_principal_name = user.user_principal_name
      password            = random_password.test_user[key].result
    }
  }
  sensitive = true
}

# --- Group 2（ADFSグループ）: picketfence自身のAzureサブスクリプション/テナント向け ---

output "adfs_auth_check" {
  description = "Terraformが現在どのpicketfence側Entra IDテナント/Azureサブスクリプションに対して認証されているかの確認用（terraform/adfs_providers.tf）"
  value = {
    entra_tenant_id       = data.azuread_client_config.picketfence.tenant_id
    entra_object_id       = data.azuread_client_config.picketfence.object_id
    azure_subscription_id = data.azurerm_client_config.picketfence.subscription_id
  }
}

output "adfs_vm_public_ip" {
  description = "ADFSサーバーVMへのRDP接続先（docs/adfs-setup-runbook.md参照）"
  value       = azurerm_public_ip.adfs_vm.ip_address
}

output "adfs_vm_local_admin_credentials" {
  description = "ADFSサーバーVMのローカル管理者アカウント（初期構築・トラブル時の復旧用）"
  value = {
    username = var.adfs_vm_admin_username
    password = random_password.adfs_vm_admin.result
  }
  sensitive = true
}

output "adfs_domain_admin_credentials" {
  description = "ドメイン参加・ADFSロール/ファーム構築（docs/adfs-setup-runbook.md）で使うドメイン管理者アカウント"
  value = {
    user_principal_name = azuread_user.domain_join_admin.user_principal_name
    password            = random_password.domain_join_admin.result
  }
  sensitive = true
}

output "entra_domain_services_domain_name" {
  description = "Microsoft Entra Domain Servicesのドメイン名（ADFSサーバーのドメイン参加先）"
  value       = var.entra_domain_services_domain_name
}

output "insurance_test_user_credentials" {
  description = "Group 2（5グループ）の検証用ユーザーのサインイン情報。TESTING.mdの表に転記して使う"
  value = {
    for key, user in azuread_user.insurance_test_user : key => {
      user_principal_name = user.user_principal_name
      password            = random_password.insurance_test_user[key].result
    }
  }
  sensitive = true
}
