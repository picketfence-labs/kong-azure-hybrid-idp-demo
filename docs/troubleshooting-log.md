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
