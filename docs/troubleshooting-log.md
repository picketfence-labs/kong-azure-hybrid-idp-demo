# Troubleshooting Log（知見ログ）

実装中に**想定通りに動かなかったこと**を、その場で漏れなく記録するログです。`docs/decisions/`のADR（複数の妥当な選択肢がある判断ポイント専用）とは異なり、判断ポイントかどうかに関わらず、あらゆる「期待と実際のギャップ」（エラー、ドキュメントと異なる挙動、想定した設定で動かなかった、リトライが必要だった等）を対象にします。

## 記入ルール
- **その場で書く**。後からまとめて思い出して書かない
- 追記専用。「大したことではない」と判断して省略しない
- 本プロジェクトはKong Gateway 3.16のベータ機能（Entra ID OBO）を使うため、**公式ドキュメントとの乖離・ドキュメント自体の不在**は特に優先して記録する

## 記入項目（1エントリあたり）
```markdown
## YYYY-MM-DD HH:MM（または該当タスク名） タイトル
- **何を期待していたか**:
- **実際どうだったか**（エラーメッセージ・症状を具体的に）:
- **原因**（分かれば。不明なら「不明」と書く）:
- **対処・回避方法**（または未解決なら次にどうするか）:
- **コスト**（任意。試行回数・かかった時間等、目立って大きい場合のみ）:
```

<!-- 以下、実際のログをこの下に追記していく -->

> [!note]
> 2026-09-08: 本リポジトリ（kong-azure-hybrid-idp-demo）はフォークではあるが、Picketfence Labs内での扱いとしては新規Projectのため、フォーク元での実装時に蓄積したログはここでリセットした（過去の記録はgit履歴から参照可能）。Group 1・Group 2の実装を進める中で判明した事項を、ここから改めて記録していく。

## 2026-09-08 Group 2バックエンド: kong-api-bundle-insuranceの実際のイメージタグ・ポート・パス構造を確認
- **何を期待していたか**: design-brief上は「GHCR公開コンテナ6種をそのままpullして使う」としか書いておらず、具体的なイメージタグ・待受ポート・APIパスは未確認だった
- **実際どうだったか**: `kong-api-bundle-insurance`リポジトリ（README/docs/ARCHITECTURE.md）を確認し、実際に6イメージ全て`docker pull`・`docker run`で動作確認した結果:
  - イメージ参照は`ghcr.io/picketfence-labs/insurance-<service>:v0.1.1`（`<service>`は`product`/`customer`/`simulation`/`application`/`policy`/`claim`）。6種とも同タグでpull可能なことを確認
  - 全サービス共通でFastAPI/uvicornがコンテナ内`:8000`で待ち受け、`GET /health`が`{"status":"ok","service":"<name>"}`を返す
  - コンテナ単体で動かした場合のAPIルートパスは**複数形**（例: product サービスは`/products`・`/products/{product_id}`）。design-brief記載の「パス」列（`/product`等、Kong Gateway経由フルデモでの外部公開パス）とは異なる（単数/複数の差）。本リポジトリでdecKのRoute/Serviceを書く際は、外部パス（`insurance-product.yaml`の命名規則に合わせるなら`/product`等）と実バックエンドパス（`/products`）の対応関係を明示的に設計する必要がある
- **原因**: 不明（`kong-api-bundle-insurance`側の設計判断。REST慣習として一覧系エンドポイントを複数形にしたと推測されるが未確認）
- **対処・回避方法**: `docker-compose.yml`に6サービスを追加する際、上記で確認したイメージ参照・ポート・`/health`ヘルスチェックをそのまま使用。パスの単数/複数差は、次のステップ（Kong Service/Route + `legacy-authz-adapter`カスタムプラグインの配線）で対応する

## 2026-09-08 legacy-authz-adapter実装: kong-eeソース未参照（今回のセッションで未マウント）で設計を確定
- **何を期待していたか**: CLAUDE.md「ローカル参照」節の通り、カスタムプラグイン開発では`kong-ee`（Kong EEソースコード）を一次情報源として参照する想定だった
- **実際どうだったか**: 今回のセッションでは`kong-ee`が`additionalDirectories`にマウントされておらず参照できなかった（リポジトリ自体は`/Users/shinichi.hashitanikonghq.com/LOCAL_REPO/kong-ee`に存在することは`find`で確認したが、このセッションから直接読めるパスではなかった）
- **原因**: セッション起動時の`--add-dir`指定漏れ（明示的な追加依頼をしていなかったため）
- **対処・回避方法**: `openid-connect`の`upstream_headers`によるクレーム→ヘッダー転送は、本リポジトリのGroup 1で実機検証済みの仕組み（`kong/login-route.yaml`で`name`/`preferred_username`クレームを`X-User-Name`/`X-User-Email`へ転送）であり、これをそのまま流用する設計とした（`legacy-authz-adapter`は生ヘッダーを読むだけで、openid-connect側の内部実装詳細に依存しない）。プラグインのpriority（`100`、openid-connectの後に実行）・schema.luaのDSL（`typedefs.no_consumer`等）はKongの公開されている一般的なプラグイン開発規約に基づく設計判断で、`kong-ee`固有の非公開情報には依存していない
- **検証結果（同日追記）**: `KONG_PLUGINS: bundled,legacy-authz-adapter`＋`KONG_LUA_PACKAGE_PATH`でのマウント方式（`docker-compose.yml`、`/usr/local/custom/kong/plugins/legacy-authz-adapter`）を、実際に`kong/kong-gateway-dev:pr-21082-ubuntu`を起動して確認した。Kongは正常に起動（`kong health`成功）し、Admin API `GET /plugins/schema/legacy-authz-adapter`が`schema.lua`通りの内容を返すことを確認。**プラグインのロード自体は実機で確認済み**。一方、`deck gateway validate`は本ライセンス無し（`KONG_LICENSE_DATA={}`のダミー値）だと`services`/`routes`/`plugins`（`openid-connect`だけでなくコアエンティティも含め）全てが`HTTP 403 Enterprise license missing or expired`で拒否されることを確認した。openid-connectの設定内容（`issuer`/`client_id`等のフィールド）そのものの妥当性は、実際のKong Enterpriseライセンスが無いと検証できない（Group 1と同じ制約。検証用コンテナはテスト後に`docker compose down`で削除済み）

## 2026-09-08 insurance-ui実装: Kong経由の実ルーティングはライセンス制約のため未検証、アプリ単体では確認済み
- **何を期待していたか**: `kong/insurance-ui-route.yaml`（新規）を`deck gateway sync`で実際のKongへ反映し、ブラウザ相当のリクエストで`/insurance`配下がinsurance-uiコンテナへ到達すること、ログイン後のグループヘッダー転送・6API呼び出し結果の表示までを一通り確認したかった
- **実際どうだったか**: `deck gateway sync kong/insurance-ui-route.yaml`は想定通り`403 Enterprise license missing or expired`（Service作成自体が拒否される、上記2026-09-08エントリと同一の既知制約）で失敗した。そのため、Kong自体を経由したエンドツーエンドの確認はできなかった
- **原因**: 検証用コンテナにダミーのライセンス値（`KONG_LICENSE_DATA=dummy`）しか設定していないため（実ライセンスが無い環境自体は既知の制約、ADFS実インフラ構築時に本ライセンスが用意される想定）
- **対処・回避方法**: insurance-uiコンテナを起動し、コンテナに直接（Kongを介さず）リクエストを送ることで、アプリ側のロジックのみ切り分けて確認した:
  - `GET /insurance/`（未ログイン相当、`x-adfs-group-claim`ヘッダー無し）→ 200、「未ログイン」表示
  - 同じリクエストに`x-adfs-group-claim: it`ヘッダーを付与 → 200、「ログイン中: グループ it」・ログアウトボタン表示（Kongの`upstream_headers`が転送する想定のヘッダーをこのアプリが正しく解釈することを確認）
  - `GET /insurance/api/access-check?api=product`（`Authorization`ヘッダー無し）→ 401（Kongがトークンを転送しなかった場合の防御が機能）
  - 同、`api=doesnotexist`（許可リスト外）→ 400（allowlist方式のバリデーションが機能）
  - 同、`Authorization: Bearer dummy`付き、`api=product`→ アプリが`http://kong:8000/product`へ正しくfetchし、Kong側にRouteが存在しないため`404`が返り、それをそのまま`{"allowed":false,"status":404}`として返却（Kong未経由の`404`と、legacy-authz-adapterによる実際の`403`拒否は区別できないが、リレー処理自体の配線は正しく機能していることを確認）
  - **Kong自体を介した`openid-connect`（ADFS向け設定）・`legacy-authz-adapter`と組み合わせた実際の許可/拒否判定は、Kong Enterpriseライセンス取得後かつADFS実インフラ構築後に持ち越し**（Group 1・既存6バックエンドRouteと同じ制約）
