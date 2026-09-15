import { isIdentity, type AuthStatus } from "@/lib/auth";

type RouteContext = {
  params: Promise<{ identity: string }>;
};

export async function GET(request: Request, context: RouteContext) {
  const { identity } = await context.params;
  if (!isIdentity(identity)) {
    return Response.json({ error: "unknown identity route" }, { status: 400 });
  }

  const status: AuthStatus = {
    identity,
    authenticated: true,
    attributePresent: Boolean(
      request.headers.get("x-demo-verified-attribute"),
    ),
  };

  return Response.json(status, {
    headers: { "Cache-Control": "no-store" },
  });
}
