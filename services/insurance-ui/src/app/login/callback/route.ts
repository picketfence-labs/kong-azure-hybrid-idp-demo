// kong/insurance-ui-route.yamlのopenid-connectはlogin_action:upstream（既定値）のため、
// ADFSからのコールバックのリクエストパスがそのままここへ転送される。認証自体はKongの時点で
// 完了済み（セッションcookie発行済み）なので、ここではトップページへ送り返すだけでよい
// （services/chat-ui/src/app/login/callback/route.tsと同じパターン）。
export async function GET() {
  return Response.redirect("http://localhost:8000/insurance/", 303);
}
