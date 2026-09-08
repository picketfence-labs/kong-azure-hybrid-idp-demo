local typedefs = require "kong.db.schema.typedefs"

return {
  name = "legacy-authz-adapter",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          -- openid-connectのupstream_headersが、検証済みIDトークンの属性値クレームを
          -- そのままコピーしているヘッダー名（design-brief: 属性値=グループID）。
          { group_claim_header = {
              type = "string",
              required = true,
              default = "X-ADFS-Group-Claim",
          } },
          -- グループ確定後、ダウンストリームサービスへ転送するヘッダー名。
          { group_header_name = {
              type = "string",
              required = true,
              default = "X-Group-Id",
          } },
          -- design-briefで確定済みの5グループID。クレーム値がこの一覧に無ければ拒否する。
          { known_groups = {
              type = "array",
              elements = { type = "string" },
              required = true,
              default = { "it", "sales", "new-business", "policy-admin", "claim" },
          } },
          -- このServiceへのアクセスを許可するグループID（Service単位で個別設定、design-briefのマトリクス参照）。
          { allowed_groups = {
              type = "array",
              elements = { type = "string" },
              required = true,
          } },
        },
      },
    },
  },
}
