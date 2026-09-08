import type { NextConfig } from "next";

// Kongの単一エントリポイント（docker-compose.ymlのkongサービス、ポート8000）上でChat UI
// （kong/login-route.yaml、paths: ["/"]）と共存させるため、insurance-uiは"/insurance"配下に
// マウントする（kong/insurance-ui-route.yaml、strip_path: false）。basePathを設定することで、
// Next.js自身のルーティング・静的アセット配信もこのプレフィックスを前提に解決される。
const nextConfig: NextConfig = {
  basePath: "/insurance",
};

export default nextConfig;
