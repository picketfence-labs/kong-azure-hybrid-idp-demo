-- authz.luaの単体テスト。
--
-- Kong本体のプラグインテストは通常busted＋Kongのテストハーネス（kong-eeソース同梱）で
-- 実行するが、本リポジトリにはそのハーネスが無いため、Kongランタイムに依存しない
-- authz.lua単体を対象に、luajitのみで実行できる簡易テストにしている
-- （Kong経由の結合動作はkong/insurance-*.yaml配線後にdeck gateway sync＋実リクエストで確認する）。
--
-- 実行方法: luajit kong/plugins/legacy-authz-adapter/spec/authz_spec.lua

package.path = package.path .. ";" .. arg[0]:match("(.*/)") .. "../?.lua"
local authz = require "authz"

local KNOWN_GROUPS = { "it", "sales", "new-business", "policy-admin", "claim" }

local failures = 0
local test_count = 0

local function assert_eq(actual, expected, message)
  test_count = test_count + 1
  if actual ~= expected then
    failures = failures + 1
    print(string.format(
      "FAIL: %s (expected %s, got %s)",
      message, tostring(expected), tostring(actual)
    ))
  end
end

-- determine_group -----------------------------------------------------------

do
  local group, err = authz.determine_group("it", KNOWN_GROUPS)
  assert_eq(group, "it", "known group claim is accepted as-is")
  assert_eq(err, nil, "no error for a known group claim")
end

do
  local group, err = authz.determine_group(nil, KNOWN_GROUPS)
  assert_eq(group, nil, "missing claim is rejected")
  assert_eq(err, "group claim is missing", "missing claim reports the expected error")
end

do
  local group, err = authz.determine_group("", KNOWN_GROUPS)
  assert_eq(group, nil, "empty claim is rejected")
  assert_eq(err, "group claim is missing", "empty claim reports the expected error")
end

do
  local group, err = authz.determine_group("unknown-department", KNOWN_GROUPS)
  assert_eq(group, nil, "unrecognized claim value is rejected")
  assert_eq(err, "unrecognized group claim: unknown-department", "unrecognized claim reports the expected error")
end

-- is_allowed ------------------------------------------------------------------

-- design-briefのグループ⇔APIアクセスマトリクス（policyサービス相当: it/sales/new-business/policy-admin/claim全て許可）
local POLICY_ALLOWED = { "it", "sales", "new-business", "policy-admin", "claim" }
for _, group in ipairs(POLICY_ALLOWED) do
  assert_eq(authz.is_allowed(group, POLICY_ALLOWED), true, "'" .. group .. "' is allowed for policy-equivalent allowed_groups")
end

-- claimサービス相当: it/policy-admin/claimのみ許可、sales/new-businessは拒否
local CLAIM_ALLOWED = { "it", "policy-admin", "claim" }
assert_eq(authz.is_allowed("it", CLAIM_ALLOWED), true, "'it' is allowed for claim-equivalent allowed_groups")
assert_eq(authz.is_allowed("policy-admin", CLAIM_ALLOWED), true, "'policy-admin' is allowed for claim-equivalent allowed_groups")
assert_eq(authz.is_allowed("claim", CLAIM_ALLOWED), true, "'claim' is allowed for claim-equivalent allowed_groups")
assert_eq(authz.is_allowed("sales", CLAIM_ALLOWED), false, "'sales' is denied for claim-equivalent allowed_groups")
assert_eq(authz.is_allowed("new-business", CLAIM_ALLOWED), false, "'new-business' is denied for claim-equivalent allowed_groups")

-- simulation/applicationサービス相当: it/sales/new-businessのみ許可、policy-admin/claimは拒否
local SIMULATION_ALLOWED = { "it", "sales", "new-business" }
assert_eq(authz.is_allowed("policy-admin", SIMULATION_ALLOWED), false, "'policy-admin' is denied for simulation-equivalent allowed_groups")
assert_eq(authz.is_allowed("claim", SIMULATION_ALLOWED), false, "'claim' is denied for simulation-equivalent allowed_groups")

print(string.format("%d/%d assertions passed", test_count - failures, test_count))
if failures > 0 then
  os.exit(1)
end
