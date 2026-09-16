# ADFS/自己管理AD DS用ネットワーク（design-brief Group2「3. アーキテクチャ」、ADR-0005 Option A）。
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

# 自己管理AD DSフォレスト用DC VMのサブネット（terraform/adfs_domain_controller.tf）。
# Microsoft Entra Domain Services向けの専用デリゲートサブネット要件は自己管理AD DSでは不要。
resource "azurerm_subnet" "dc_vm" {
  provider             = azurerm.picketfence
  name                 = "snet-dc-vm"
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

# フォレスト昇格済みのDC VMのプライベートIPをVNetのDNSサーバーへ設定する。
# standalone resourceに分けることで、VNet/subnet -> DC VM作成・フォレスト昇格 -> DNS設定の順序を保ち、
# VNet定義との循環依存を避ける。dc_readyへのdepends_onで、フォレスト昇格前のVMへDNSを向けない。
resource "azurerm_virtual_network_dns_servers" "adfs" {
  provider           = azurerm.picketfence
  virtual_network_id = azurerm_virtual_network.adfs.id
  dns_servers        = [azurerm_network_interface.dc.private_ip_address]

  depends_on = [time_sleep.dc_ready]
}

# DC VM用NSG: RDPのみ許可（ADR-0001参照の対話runbook運用、トラブルシュート用）。
# AD DS内部通信（DNS/Kerberos/LDAP等、ADFS VMとの通信）はVNet内暗黙のAllowVNetInBoundルールに委ねる
# （既存ADFS VM用NSGも同じ考え方、OIDC/RDP以外の明示ルールを持たない）。
resource "azurerm_network_security_group" "dc_vm" {
  provider            = azurerm.picketfence
  name                = "nsg-dc-vm"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location

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

resource "azurerm_subnet_network_security_group_association" "dc_vm" {
  provider                  = azurerm.picketfence
  subnet_id                 = azurerm_subnet.dc_vm.id
  network_security_group_id = azurerm_network_security_group.dc_vm.id
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
