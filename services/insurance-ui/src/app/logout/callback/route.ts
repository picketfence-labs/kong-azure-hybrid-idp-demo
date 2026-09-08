// kong/insurance-ui-route.yamlのopenid-connectはlogin_action:upstream（既定値）のため、
// ADFSからのpost_logout_redirect_uriコールバックのリクエストパスがそのままここへ転送される。
// ログアウト自体（セッションcookie破棄）はKongの時点で完了済みなので、ここではトップページへ
// 送り返すだけでよい。トップページはセッションが無いため、再度Kongのopenid-connectがADFSの
// ログイン画面へ誘導する（services/chat-ui/src/app/logout/callback/route.tsと同じパターン）。
export async function GET() {
  return Response.redirect("http://localhost:8000/insurance/", 303);
}
