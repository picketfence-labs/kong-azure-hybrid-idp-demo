# 自己管理AD DSフォレスト（design-brief Group2「3. アーキテクチャ」、ADR-0005 Option A）。
# Microsoft Entra Domain Servicesは`AAD DC Administrators`にDomain Admin権限を渡さず、
# AD FSファーム作成の公式パスを実行できないと実機・Microsoft公式ドキュメント双方で確認済みのため、
# 自己管理のWindows Server AD DSフォレストへ切り替える（terraform/adfs_domain_services.tf を撤去）。
#
# ADR-0001の境界（インフラ・ドメイン参加はTerraform、ADFS固有設定は対話runbook）を踏襲し、
# フォレスト昇格・ドメイン管理者/テストユーザー作成までをTerraformで自動化する。
# CustomScriptExtensionの`commandToExecute`はcmd.exe経由で実行されるため長さに実用上の上限があり
# （実機で"The command line is too long."を確認）、スクリプト本体をコマンド行へ直接埋め込む方式は
# 不採用。代わりにスクリプト本体は非公開のBlob Storage（SAS URL、短い有効期限）へ配置し、
# `fileUris`でVMへダウンロードさせた上で、短い`-File`呼び出し行だけを`-EncodedCommand`経由で
# 実行する（DSCはリソースモジュールの別ホスティングが必要になり、一度きりのデモ構築には
# 割に合わないため不採用）。

locals {
  # AD FSファーム構築（docs/adfs-setup-runbook.md）・ADFS VMのドメイン参加で使うドメイン管理者。
  domain_admin_username = "adfs-domain-admin"

  # NetBIOS名はドメイン名の第1ラベルから機械的に導出する（例: "adfsdemo.picketfencelabs.local" → "ADFSDEMO"）。
  ad_ds_netbios_name = upper(split(".", var.ad_ds_domain_name)[0])

  # scripts/adfs/Install-AdDsForest.ps1を、fileUrisでダウンロードされた同じフォルダから
  # `.\<file>`相対パスで呼び出す短い1行。cmd.exeの特殊文字（生成パスワードに含まれる
  # !%^&*() 等）を経由させないよう、-EncodedCommand（UTF-16LE base64）でPowerShellへ直接渡す。
  bootstrap_dc_invocation = "& '.\\${azurerm_storage_blob.install_ad_ds_forest.name}' -DomainName '${var.ad_ds_domain_name}' -DomainNetbiosName '${local.ad_ds_netbios_name}' -SafeModeAdministratorPasswordPlainText '${random_password.dc_safe_mode_admin.result}' -DomainAdminUsername '${local.domain_admin_username}' -DomainAdminPassword '${random_password.domain_join_admin.result}' -TestUsersJson '${jsonencode({ for k in var.insurance_test_groups : k => random_password.insurance_test_user[k].result })}'"
}

# scripts/adfs/配下の2つのスクリプトをホストする専用Storage Account（非公開、SAS URL経由でのみ
# 読み取り可能）。CustomScriptExtensionのfileUrisにこのSAS URLを渡し、VM上へダウンロードさせる。
resource "random_id" "dc_bootstrap_storage_suffix" {
  byte_length = 4
}

resource "azurerm_storage_account" "dc_bootstrap" {
  provider                        = azurerm.picketfence
  name                            = "stkongadfs${random_id.dc_bootstrap_storage_suffix.hex}"
  resource_group_name             = azurerm_resource_group.adfs.name
  location                        = azurerm_resource_group.adfs.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "dc_bootstrap" {
  provider              = azurerm.picketfence
  name                  = "dc-bootstrap"
  storage_account_id    = azurerm_storage_account.dc_bootstrap.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "install_ad_ds_forest" {
  provider             = azurerm.picketfence
  name                 = "Install-AdDsForest.ps1"
  storage_container_id = azurerm_storage_container.dc_bootstrap.id
  type                 = "Block"
  source_content       = file("${path.module}/../scripts/adfs/Install-AdDsForest.ps1")
}

resource "azurerm_storage_blob" "new_ad_ds_domain_objects" {
  provider             = azurerm.picketfence
  name                 = "New-AdDsDomainObjects.ps1"
  storage_container_id = azurerm_storage_container.dc_bootstrap.id
  type                 = "Block"
  source_content       = file("${path.module}/../scripts/adfs/New-AdDsDomainObjects.ps1")
}

# SASのstart/expiryに`timestamp()`を直接使うと評価のたびに値が変わり、`bootstrap_dc`拡張機能の
# protected_settingsが毎plan差分を生む（実機で確認）。`time_static`でリソース作成時刻を1回だけ
# 固定し、以降のplanで同じSAS文字列が再生成されるようにする。
# フォレスト昇格の拡張機能実行中だけ有効であればよいため、有効期限は短く（数時間）設定する。
resource "time_static" "dc_bootstrap_sas" {}

data "azurerm_storage_account_sas" "dc_bootstrap" {
  provider          = azurerm.picketfence
  connection_string = azurerm_storage_account.dc_bootstrap.primary_connection_string
  https_only        = true
  signed_version    = "2022-11-02"

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = time_static.dc_bootstrap_sas.rfc3339
  expiry = timeadd(time_static.dc_bootstrap_sas.rfc3339, "6h")

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
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
# 実際のアカウント作成はbootstrap_dc拡張機能（New-AdDsDomainObjects.ps1）が行う。
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

# フォレスト昇格 + ドメイン管理者/テストユーザー作成を1つの拡張機能にまとめる
# （AzureのWindows VMはCustomScriptExtensionのhandlerを1台につき1つしか持てないため、
# 2つの拡張機能に分割できない。scripts/adfs/Install-AdDsForest.ps1のコメント参照）。
# フォレスト未昇格の場合は昇格→再起動後にスケジュールタスク経由でドメインオブジェクトを作成し、
# 既に昇格済みの場合（再apply等）はこの拡張機能の実行中に直接作成する。
resource "azurerm_virtual_machine_extension" "bootstrap_dc" {
  provider             = azurerm.picketfence
  name                 = "bootstrap-dc"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # fileUris（SAS URL）・DSRM・ドメイン管理者・テストユーザーのパスワードを含むため、
  # planのdiffに出さないprotected_settingsへ置く（既存のadfs_vm.tf domain_join拡張機能と同じ扱い）。
  protected_settings = jsonencode({
    fileUris = [
      "${azurerm_storage_blob.install_ad_ds_forest.url}?${data.azurerm_storage_account_sas.dc_bootstrap.sas}",
      "${azurerm_storage_blob.new_ad_ds_domain_objects.url}?${data.azurerm_storage_account_sas.dc_bootstrap.sas}",
    ]
    commandToExecute = "powershell -NonInteractive -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(local.bootstrap_dc_invocation, "UTF-16LE")}"
  })
}

moved {
  from = azurerm_virtual_machine_extension.create_forest
  to   = azurerm_virtual_machine_extension.bootstrap_dc
}

# フォレスト昇格に伴う自動再起動と、再起動後のドメインオブジェクト作成（スケジュールタスク経由）を
# 待つ。Entra Domain Servicesの15分（Entra ID側ハッシュ同期待ち）とは待機理由が異なり、
# VM再起動＋ローカルサービス起動＋スケジュールタスク実行のみのため、より短い待機時間で足りる想定。
resource "time_sleep" "dc_ready" {
  create_duration = "5m"

  depends_on = [azurerm_virtual_machine_extension.bootstrap_dc]
}
