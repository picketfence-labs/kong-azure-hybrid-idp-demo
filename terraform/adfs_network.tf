# ADFS/Entra Domain Services用ネットワーク（design-brief Group2「3. アーキテクチャ」）。
# picketfence自身のAzureサブスクリプション（terraform/adfs_providers.tf）に構築する。

resource "azurerm_resource_group" "adfs" {
  provider = azurerm.picketfence
  name     = "rg-kong-adfs-demo"
  location = var.adfs_location
}

resource "azurerm_virtual_network" "adfs" {
  provider            = azurerm.picketfence
  name                = "vnet-kong-adfs-demo"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location
  address_space       = ["10.20.0.0/16"]
}

# Microsoft Entra Domain Servicesは他のワークロードと共有できない専用のデリゲートサブネットを
# 要求する（Microsoft公式要件）。
resource "azurerm_subnet" "domain_services" {
  provider             = azurerm.picketfence
  name                 = "snet-domain-services"
  resource_group_name  = azurerm_resource_group.adfs.name
  virtual_network_name = azurerm_virtual_network.adfs.name
  address_prefixes     = ["10.20.0.0/24"]
}

# ADFSサーバーVM用サブネット。
resource "azurerm_subnet" "adfs_vm" {
  provider             = azurerm.picketfence
  name                 = "snet-adfs-vm"
  resource_group_name  = azurerm_resource_group.adfs.name
  virtual_network_name = azurerm_virtual_network.adfs.name
  address_prefixes     = ["10.20.1.0/24"]
}

# Entra Domain Servicesの正常性監視・PowerShell Remotingに必須のNSG受信規則
# （Microsoft公式ドキュメントが要求する必須規則。サービスタグはAzure標準のもの）。
resource "azurerm_network_security_group" "domain_services" {
  provider            = azurerm.picketfence
  name                = "nsg-domain-services"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location

  security_rule {
    name                       = "AllowSyncWithAzureAD"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureActiveDirectoryDomainServices"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowPSRemoting"
    priority                   = 201
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = "AzureActiveDirectoryDomainServices"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "domain_services" {
  provider                  = azurerm.picketfence
  subnet_id                 = azurerm_subnet.domain_services.id
  network_security_group_id = azurerm_network_security_group.domain_services.id
}

# ADFS VM用NSG: design-brief通り、Kong実行環境（および作業端末）の発信元IPのみを許可する
# （VPN等は使わない方式、design-brief Group2「2. 要件」）。
resource "azurerm_network_security_group" "adfs_vm" {
  provider            = azurerm.picketfence
  name                = "nsg-adfs-vm"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location

  security_rule {
    name                       = "AllowOidcHttps"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.nsg_allowed_source_cidr
    destination_address_prefix = "*"
  }

  # ADR-0001（ハイブリッド方式）で採択した手動ADFS設定手順（docs/adfs-setup-runbook.md）のための
  # RDPアクセス。design-brief自体はRDP要件を明記していないが、Option B採択に伴い必要になった
  # 実装詳細（同じ発信元IP許可リストを流用し、対象を広げない）。
  security_rule {
    name                       = "AllowRdp"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.nsg_allowed_source_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "adfs_vm" {
  provider                  = azurerm.picketfence
  subnet_id                 = azurerm_subnet.adfs_vm.id
  network_security_group_id = azurerm_network_security_group.adfs_vm.id
}
