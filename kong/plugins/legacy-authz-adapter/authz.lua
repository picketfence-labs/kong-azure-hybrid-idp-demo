-- グループ判定・アクセス可否判定の純粋ロジック（Kongランタイムに依存しない）。
-- handler.luaから呼ばれるほか、spec/authz_spec.luaで単体テストする。

local _M = {}

-- IDトークンのクレーム値からグループIDを確定する。
-- design-brief（Group 2）の通り、属性値=グループIDの正規化はADFS側で完了している前提のため、
-- ここでの「確定」は既知の5グループのいずれかであることの検証のみ（レガシー認可サービスが
-- 未知の属性値を拒否する挙動を簡略化して再現している）。
function _M.determine_group(claim_value, known_groups)
  if claim_value == nil or claim_value == "" then
    return nil, "group claim is missing"
  end

  for _, known in ipairs(known_groups) do
    if known == claim_value then
      return claim_value
    end
  end

  return nil, "unrecognized group claim: " .. tostring(claim_value)
end

-- 確定したグループIDが、Service単位で設定されたallowed_groupsに含まれるか判定する。
function _M.is_allowed(group_id, allowed_groups)
  for _, allowed in ipairs(allowed_groups) do
    if allowed == group_id then
      return true
    end
  end
  return false
end

return _M
