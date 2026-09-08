local authz = require "kong.plugins.legacy-authz-adapter.authz"

local LegacyAuthzAdapterHandler = {
  -- openid-connect（デフォルトで1000番台の高優先度）がIDトークンを検証し、
  -- upstream_headersでクレームをヘッダーへ書き出した後に実行される必要があるため低めに設定。
  PRIORITY = 100,
  VERSION = "0.1.0",
}

function LegacyAuthzAdapterHandler:access(conf)
  local claim_value = kong.request.get_header(conf.group_claim_header)

  local group_id, err = authz.determine_group(claim_value, conf.known_groups)
  if not group_id then
    kong.log.warn("legacy-authz-adapter: ", err)
    return kong.response.exit(403, { message = "access denied" })
  end

  if not authz.is_allowed(group_id, conf.allowed_groups) then
    kong.log.info(
      "legacy-authz-adapter: group '", group_id, "' is not in allowed_groups for this service"
    )
    return kong.response.exit(403, { message = "access denied" })
  end

  kong.service.request.set_header(conf.group_header_name, group_id)
end

return LegacyAuthzAdapterHandler
