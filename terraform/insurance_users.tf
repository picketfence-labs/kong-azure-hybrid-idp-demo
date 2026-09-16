# design-brief Group2「2. 要件」: 5グループ全パターンを確認できるよう、各グループに最低1
# テストユーザーを割り当てる。属性値をそのままグループIDとして設定し、ADFSはOIDCトークンの
# クレームとしてそのまま発行する（属性→グループIDの正規化はADFS側では行わない）。
#
# 属性値を格納する具体的な属性は設計時点で未確定だったため、ADFSのClaim Issuance Policyから
# のAD属性参照のしやすさを優先し、標準属性department（AD DS上でそのまま参照可能）を採用した
# （design-brief未指定・実装時の判断。ADFS側でのクレームカスタマイズの実際の挙動は
# docs/design-brief.md Group2「未検証・実装時に確認が必要な技術的前提」の通り実機未検証。
# docs/adfs-setup-runbook.mdのClaim Issuance Policy設定時に要確認）。
#
# 実際のユーザー作成は自己管理AD DS側（terraform/adfs_domain_controller.tf の
# create_domain_objects拡張機能、scripts/adfs/New-AdDsDomainObjects.ps1）で行う
# （ADR-0005 Option A、Entra ID cloud-onlyアカウント経由のパスワードハッシュ同期待ちは不要）。
# ここではテストデータの定義（グループ一覧・パスワード生成）だけを持つ。

variable "insurance_test_groups" {
  description = "design-brief Group2確定の5グループID。1グループ=1テストユーザー。"
  type        = list(string)
  default     = ["it", "sales", "new-business", "policy-admin", "claim"]
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
