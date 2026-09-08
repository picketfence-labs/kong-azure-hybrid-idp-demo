// Kongをホストするdocker composeの内部ネットワーク名（docker-compose.yml参照）。
const KONG_BASE_URL = process.env.KONG_INTERNAL_BASE_URL ?? "http://kong:8000";

// design-brief Group2アクセスマトリクスの6API（kong/insurance-<key>.yamlのRoute pathと一致）。
// クエリパラメータをそのままバックエンドパスへ使うとオープンリダイレクト相当のリスクが
// あるため、既知の6キーのみ許可するallowlist方式にする。
const KNOWN_APIS = [
  "product",
  "customer",
  "simulation",
  "application",
  "policy",
  "claim",
] as const;
type KnownApi = (typeof KNOWN_APIS)[number];

function isKnownApi(value: string | null): value is KnownApi {
  return (KNOWN_APIS as readonly string[]).includes(value ?? "");
}

export async function GET(req: Request) {
  const url = new URL(req.url);
  const api = url.searchParams.get("api");
  if (!isKnownApi(api)) {
    return Response.json({ error: "unknown api" }, { status: 400 });
  }

  // kong/insurance-ui-route.yamlのopenid-connect（upstream_access_token_header、デフォルト
  // "authorization:bearer"）がこのリクエストにAuthorizationヘッダーとして転送したADFSの
  // アクセストークン。同じトークンを各バックエンドRoute（kong/insurance-<api>.yaml、
  // auth_methods: bearer）へBearerとして再提示することで、legacy-authz-adapterによる
  // 許可/拒否をKong経由で確認する（services/chat-ui/src/app/api/chat/route.tsと同じ
  // トークン再提示パターン、OBOは行わない点のみGroup 1と異なる）。
  const authorization = req.headers.get("authorization");
  if (!authorization) {
    return Response.json(
      { error: "no access token forwarded by Kong" },
      { status: 401 },
    );
  }

  const response = await fetch(`${KONG_BASE_URL}/${api}`, {
    headers: { Authorization: authorization },
  });

  return Response.json({ allowed: response.ok, status: response.status });
}
