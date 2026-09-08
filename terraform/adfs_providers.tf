# picketfence自身のAzureサブスクリプション＋Entra IDテナント向けプロバイダエイリアス
# （terraform/providers.tfの既定プロバイダ＝Kong社のkongstrong.onmicrosoft.com向けとは別テナント）。
# 認証はaz loginのAzure CLIセッションに委譲する点は既定プロバイダと同じだが、tenant_id/
# subscription_idを明示することで、az CLIに複数アカウントがログイン済みでも常に
# picketfence側のテナント/サブスクリプションのトークンを使わせる（同一state内で
# Group1（既定プロバイダ）とGroup2（このエイリアス）の2テナントを扱うために必要）。
#
# 前提: `az login` でpicketfence自身のアカウントを追加ログイン済みであること
# （`az account set`で対象をアクティブに切り替えている必要はない。tenant_id/subscription_idの
# 明示により、このプロバイダエイリアスは常に対象を固定する）。

provider "azuread" {
  alias     = "picketfence"
  tenant_id = var.picketfence_azure_tenant_id
}

provider "azurerm" {
  alias           = "picketfence"
  subscription_id = var.picketfence_azure_subscription_id
  tenant_id       = var.picketfence_azure_tenant_id
  features {}
}

# 認証の疎通確認用（terraform/main.tfのauth_checkと同じ狙い、picketfence側テナント版）。
data "azuread_client_config" "picketfence" {
  provider = azuread.picketfence
}

data "azurerm_client_config" "picketfence" {
  provider = azurerm.picketfence
}
