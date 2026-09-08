# Group 2専用UI（insurance-ui）

Kong Gateway ADFS/OIDC × レガシー認可ロジック再現デモのGroup 2専用UI。詳細はリポジトリルートの[README.md](../../README.md)の「Group 2専用UI（insurance-ui）」節を参照。

このアプリ自身はOAuthクライアントを持たない。ログイン・セッション管理は[`kong/insurance-ui-route.yaml`](../../kong/insurance-ui-route.yaml)のopenid-connectプラグインが担い、Next.jsはKongが転送するヘッダー（グループID・アクセストークン）を信頼するだけの構成（[`services/chat-ui`](../chat-ui)と同じ方針、詳細は[docs/design-brief.md](../../docs/design-brief.md) Group 2「3. アーキテクチャ」）。単体（`bun run dev`、http://localhost:3000）で開いても認証ヘッダーが無いため、Kong経由（http://localhost:8000/insurance/、`docker compose up -d`）でのアクセスが前提。

Kong上で`/`（Chat UI）と共存させるため`/insurance`配下にマウントしている（`next.config.ts`の`basePath`参照）。
