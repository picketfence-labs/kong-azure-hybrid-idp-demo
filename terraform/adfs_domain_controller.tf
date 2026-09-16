# 自己管理AD DSフォレスト（design-brief Group2「3. アーキテクチャ」、ADR-0005 Option A）。
# Microsoft Entra Domain Servicesは`AAD DC Administrators`にDomain Admin権限を渡さず、
# AD FSファーム作成の公式パスを実行できないと実機・Microsoft公式ドキュメント双方で確認済みのため、
# 自己管理のWindows Server AD DSフォレストへ切り替える（terraform/adfs_domain_services.tf を撤去）。
#
# ADR-0001の境界（インフラ・ドメイン参加はTerraform、ADFS固有設定は対話runbook）を踏襲し、
# フォレスト昇格・ドメイン管理者/テストユーザー作成までをTerraformで自動化する。
# CustomScriptExtensionでスクリプト全文とパスワードを埋め込んだ`-EncodedCommand`を実行する方式
# （DSCはリソースモジュールの別ホスティングが必要になり、一度きりのデモ構築には割に合わないため不採用）。

locals {
  # AD FSファーム構築（docs/adfs-setup-runbook.md）・ADFS VMのドメイン参加で使うドメイン管理者。
  domain_admin_username = "adfs-domain-admin"

  # NetBIOS名はドメイン名の第1ラベルから機械的に導出する（例: "adfsdemo.picketfencelabs.local" → "ADFSDEMO"）。
  ad_ds_netbios_name = upper(split(".", var.ad_ds_domain_name)[0])

  install_ad_ds_forest_command = join("\n", [
    file("${path.module}/../scripts/adfs/Install-AdDsForest.ps1"),
    "Install-AdDsForestIfNeeded -DomainName '${var.ad_ds_domain_name}' -DomainNetbiosName '${local.ad_ds_netbios_name}' -SafeModeAdministratorPasswordPlainText '${random_password.dc_safe_mode_admin.result}'",
  ])

  create_domain_objects_command = join("\n", [
    file("${path.module}/../scripts/adfs/New-AdDsDomainObjects.ps1"),
    "New-InsuranceDemoAccounts -DomainDnsName '${var.ad_ds_domain_name}' -DomainAdminUsername '${local.domain_admin_username}' -DomainAdminPassword '${random_password.domain_join_admin.result}' -TestUsersJson '${jsonencode({ for k in var.insurance_test_groups : k => random_password.insurance_test_user[k].result })}'",
  ])
}

resource "random_password" "dc_local_admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%^&*()-_=+"
}

resource "random_password" "dc_safe_mode_admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%^&*()-_=+"
}

# AD FSファーム構築・ADFS VMのドメイン参加で使うドメイン管理者のパスワード
# （terraform/adfs_vm.tfのdomain_join拡張機能、docs/adfs-setup-runbook.md）。
# 実際のアカウント作成はcreate_domain_objects拡張機能（New-AdDsDomainObjects.ps1）が行う。
resource "random_password" "domain_join_admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%^&*()-_=+"
}

resource "azurerm_public_ip" "dc" {
  provider            = azurerm.picketfence
  name                = "pip-dc-demo"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "dc" {
  provider            = azurerm.picketfence
  name                = "nic-dc-demo"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.dc_vm.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.20.0.4"
    public_ip_address_id          = azurerm_public_ip.dc.id
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  provider            = azurerm.picketfence
  name                = "vm-dc-demo"
  resource_group_name = azurerm_resource_group.adfs.name
  location            = azurerm_resource_group.adfs.location
  size                = var.dc_vm_size
  # ローカルWindows管理者アカウント。フォレスト昇格後はドメイン管理者アカウント
  # （local.domain_admin_username）で運用するため、このアカウントは初期構築・トラブル時の復旧用。
  admin_username = var.adfs_vm_admin_username
  admin_password = random_password.dc_local_admin.result

  network_interface_ids = [azurerm_network_interface.dc.id]

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
}

resource "azurerm_virtual_machine_extension" "create_forest" {
  provider             = azurerm.picketfence
  name                 = "create-ad-ds-forest"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # DSRMパスワードを含むため、planのdiffに出さないprotected_settingsへ置く
  # （既存のadfs_vm.tf domain_join拡張機能と同じ扱い）。
  protected_settings = jsonencode({
    commandToExecute = "powershell -NonInteractive -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(local.install_ad_ds_forest_command, "UTF-16LE")}"
  })
}

# Install-ADDSForestの完了に伴う自動再起動とAD DS関連サービスの起動を待つ。
# Entra Domain Servicesの15分（Entra ID側ハッシュ同期待ち）とは待機理由が異なり、
# VM再起動＋ローカルサービス起動のみのため、より短い待機時間で足りる想定。
resource "time_sleep" "dc_ready" {
  create_duration = "5m"

  depends_on = [azurerm_virtual_machine_extension.create_forest]
}

resource "azurerm_virtual_machine_extension" "create_domain_objects" {
  provider             = azurerm.picketfence
  name                 = "create-domain-objects"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # ドメイン管理者・テストユーザーのパスワードを含むため、protected_settingsへ置く。
  protected_settings = jsonencode({
    commandToExecute = "powershell -NonInteractive -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(local.create_domain_objects_command, "UTF-16LE")}"
  })

  depends_on = [time_sleep.dc_ready]
}
