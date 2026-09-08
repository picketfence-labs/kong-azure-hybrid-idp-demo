# design-brief Group2「2. 要件」: 5グループ全パターンを確認できるよう、各グループに最低1
# テストユーザーを割り当てる。属性値をそのままグループIDとして設定し、ADFSはOIDCトークンの
# クレームとしてそのまま発行する（属性→グループIDの正規化はADFS側では行わない）。
#
# 属性値を格納する具体的なEntra IDユーザー属性は設計時点で未確定だったため、Microsoft Entra
# Domain Servicesへの同期・ADFSのClaim Issuance PolicyからのAD属性参照のしやすさを優先し、
# 標準属性department（AD同期後もdepartment属性としてそのまま参照可能）を採用した
# （design-brief未指定・実装時の判断。ADFS側でのクレームカスタマイズの実際の挙動は
# docs/design-brief.md Group2「未検証・実装時に確認が必要な技術的前提」の通り実機未検証。
# docs/adfs-setup-runbook.mdのClaim Issuance Policy設定時に要確認）。

variable "insurance_test_groups" {
  description = "design-brief Group2確定の5グループID。1グループ=1テストユーザー。"
  type        = list(string)
  default     = ["it", "sales", "new-business", "policy-admin", "claim"]
}

data "azuread_domains" "picketfence_default" {
  provider     = azuread.picketfence
  only_default = true
}

locals {
  picketfence_default_domain = data.azuread_domains.picketfence_default.domains[0].domain_name
}

resource "random_password" "insurance_test_user" {
  for_each = toset(var.insurance_test_groups)

  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%^&*()-_=+"
}

resource "azuread_user" "insurance_test_user" {
  provider = azuread.picketfence
  for_each = toset(var.insurance_test_groups)

  user_principal_name   = "demo-${each.key}@${local.picketfence_default_domain}"
  display_name          = "Demo User - ${each.key}"
  mail_nickname         = "demo-${each.key}"
  password              = random_password.insurance_test_user[each.key].result
  department            = each.key
  force_password_change = false
}
