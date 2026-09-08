# ADFSサーバー用Windows Server VM（design-brief Group2「3. アーキテクチャ」）。
# ADR-0001（ハイブリッド方式）の通り、Terraformが担うのはVM作成・ドメイン参加までで、
# ADFSロールのインストール・ファーム構築・OAuthサーバー設定はdocs/adfs-setup-runbook.mdに
# 従って手動で行う。

resource "random_password" "adfs_vm_admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%^&*()-_=+"
}

resource "azurerm_public_ip" "adfs_vm" {
  provider            = azurerm.picketfence
  name                = "pip-adfs-vm"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "adfs_vm" {
  provider            = azurerm.picketfence
  name                = "nic-adfs-vm"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.adfs_vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.adfs_vm.id
  }
}

resource "azurerm_windows_virtual_machine" "adfs" {
  provider            = azurerm.picketfence
  name                = "vm-adfs-demo"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location
  size                = var.adfs_vm_size
  # ローカルWindows管理者アカウント。ドメイン参加後のADFS設定作業（docs/adfs-setup-runbook.md）は
  # azuread_user.domain_join_admin（ドメインアカウント）で行うため、このアカウントは初期構築・
  # トラブル時の復旧用。
  admin_username = var.adfs_vm_admin_username
  admin_password = random_password.adfs_vm_admin.result

  network_interface_ids = [azurerm_network_interface.adfs_vm.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  depends_on = [
    azurerm_active_directory_domain_service.this,
  ]
}

# 標準のドメイン参加専用VM拡張機能（Azure公式、汎用的で信頼性が高い。ADR-0001参照）。
# ADFSロールのインストール・ファーム構築・OAuthサーバー設定はここでは行わない
# （docs/adfs-setup-runbook.md、手動で実施）。
resource "azurerm_virtual_machine_extension" "domain_join" {
  provider             = azurerm.picketfence
  name                 = "domain-join"
  virtual_machine_id   = azurerm_windows_virtual_machine.adfs.id
  publisher            = "Microsoft.Compute"
  type                 = "JsonADDomainExtension"
  type_handler_version = "1.3"

  settings = jsonencode({
    Name    = var.entra_domain_services_domain_name
    User    = azuread_user.domain_join_admin.user_principal_name
    Restart = "true"
    Options = 3
  })

  protected_settings = jsonencode({
    Password = random_password.domain_join_admin.result
  })
}
