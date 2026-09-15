import { isIdentity } from "@/lib/auth";

type RouteContext = {
  params: Promise<{ identity: string }>;
};

export async function GET(_request: Request, context: RouteContext) {
  const { identity } = await context.params;
  if (!isIdentity(identity)) {
    return new Response("Unknown identity route", { status: 400 });
  }

  const serializedIdentity = JSON.stringify(identity);
  const html = `<!doctype html>
<html lang="ja">
  <head><meta charset="utf-8"><title>認証状態を更新しました</title></head>
  <body>
    <p>元の画面で認証状態を確認します。この画面は閉じて構いません。</p>
    <script>
      if (window.opener) {
        window.opener.postMessage(
          { type: "insurance-auth-state-changed", identity: ${serializedIdentity} },
          window.location.origin
        );
        window.close();
      }
    </script>
  </body>
</html>`;

  return new Response(html, {
    headers: {
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'none'; base-uri 'none'; frame-ancestors 'none'",
      "Content-Type": "text/html; charset=utf-8",
      "Referrer-Policy": "no-referrer",
    },
  });
}
