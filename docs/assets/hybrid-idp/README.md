# ハイブリッドIdPデモ図の開発用素材

[![目標構成](hybrid-idp-demo.png)](https://picketfence-labs.github.io/diagrams/5ecfdbb4c0e9/)

[GitHub Pagesで開く](https://picketfence-labs.github.io/diagrams/5ecfdbb4c0e9/) / [ローカルHTML](hybrid-idp-demo.html)

## この素材の位置づけ

2026-09-14の要件整理を反映した目標設計です。実装済み構成、実リクエストの実測、E2E成功の証跡ではありません。`docs/design-brief.md`の全面更新は別タスクです。

合意済み追加要件:
- Group 2の属性対応とAPI許可条件をPostgreSQLのマスタへ集約する。decKとDBへ同じ許可ルールを二重に保持しない。
- IdPログインは別画面で開き、図を表示した画面を維持する。Group 1はEntra ID、Group 2はADFSの標準画面。
- UIは判定入力・条件・結果、実行経路と停止地点を表示する。
- カスタム認可は短い判定処理に保ち、UI/図の制御を入れない。
- この図はEntra DS＋ADFSを維持する設計時点の成果物。実機で権限モデルが成立しないと判明したため、[ADR-0005](../../decisions/0005-adfs-directory-platform.md)の決定後にIdP部分を更新する。既存OBO/Tool ACLは維持する（本図では詳細を省略）。
- **改訂2**: product/simulation/applicationはEntra、policy/claimはADFS、customerは別Pathで双方から同じAPIへ。全6 APIをAzure外・Kong外の共通ホスティングに配置する。
- Kongの2処理系を**1つのData Plane**で扱う。従来の「Group 2で全6 API」前提と5グループ×6APIテスト表は設計更新で再編する。

## ファイル

- `hybrid-idp-demo.architecture.json`: 再生成用Archify JSON。図の構成とIDの正本。
- `hybrid-idp-demo.html`: JS/CSS/inline SVGを同梱した自己完結Viewer。別のJS/CSSファイルは不要。
- `hybrid-idp-demo.png`: ドキュメント用プレビュー画像。
- `api-access-map.json`: 6 APIと認証経路の対応表。PathはP0で採用済みだが、配備設定や実測結果ではない。
- `event-targets.json`: 将来の実行イベントと図のnode/edge IDを対応させるための資料。Archify標準APIではない。
- `delivery-receipt.json`: ハッシュ、品質検証、公開URL。

SVGファイルが同梱されている場合はArchifyの標準Exportから書き出した編集用vectorです。配信用HTMLの代わりではありません。

## 図の読み方と省略範囲

左はAzure認証基盤、中央は共通Kong Gateway 1 DP、右はAzure外・Kong外の共通APIホスティングです。Kong境界内の2箱は同じDP上の認証・認可処理系であり、別プロセスではありません。PostgreSQL認可マスタはDPの外です。具体的なAPIホスティング製品やプロバイダーはこの図では指定しません。

| API | Entra系 | ADFS系 |
|---|---|---|
| insurance-product | 対象 | — |
| insurance-simulation | 対象 | — |
| insurance-application | 対象 | — |
| insurance-customer | 対象（別Path） | 対象（別Path） |
| insurance-policy | — | 対象 |
| insurance-claim | — | 対象 |

「対象」は経路の対応であり、全利用者への許可ではありません。各経路で認証・認可に成功した時だけAPIへ転送します。APIへの矢印はこの意味を共有するため、customer以外に同じ「許可時のみ」を反復していません。

customerの `/entra/customer/*` と `/adfs/customer/*` はP0で採用した公開Pathです。同じ `insurance-customer` バックエンドを指し、APIコンテナを2つに増やす意味ではありません。prefix除去と書き換え、issuerとsessionの経路間分離はPoCと実装で検証します。

凍結済みの改訂3 HTMLと再生成用JSONには、P0前の「説明用のPath案」という注記が残っています。図本体を手編集せず、実装では[Design Brief](../../design-brief.md)と[認可fixture](../../design-fixtures/insurance-permissions.json)を正本にします。図内注記の更新は、Archifyで図を再生成してreceiptを更新する別PRで行います。

①はUIから対象Pathへの要求、②は未認証時にKongが返すリダイレクトにブラウザが従ってIdPへ進む処理、③はIdP認証後に別画面ブラウザが認可コード付きでKong callbackへ戻る処理です。②③の線はブラウザ経由の論理経路であり、サーバー同士のリダイレクトやIdPからKongへの直接通知ではありません。callback後のcode→token交換・token検証はKongが行い、認可後にAPIへ転送します。有効なセッションの再利用時は②③を省略します。**改訂3では共通のTest UIノードを復元**し、Entra系とADFS系Routeへ明示接続。図の画面を維持し、IdPログインだけ別画面で行います。OBO/MCP/LLMの詳細は本図では省略し、既存機能を削除する意図はありません。Entra DSへの同期はこの図を作成した時点の前提であり、ADR-0005の決定後に更新します。図のEntra IDとEntra DSの元テナントが同一であるとは断定しません。

章選択、focus、path、theme、exportは構成説明のViewer操作です。自動実トレースではありません。固定Viewer UIとHTML langはArchifyの英語fallback、図の本文は日本語です。

## Test UIへの組み込み

1. HTMLを同一アプリの静的素材としてiframe表示するか、SVG＋独立overlay層を使うかを小さなPoCで決める。
2. `event-targets.json`の安定IDに実行イベントを対応させる。HTML内の私的DOM/CSS classを公開APIとみなさない。
3. 図原本を手編集せず、連携層を別ファイルで実装する。再生成しても対応表が有効か検査する。
4. 実行中/成功/拒否/障害/未到達/未確認を区別する。取得した証跡だけで状態を変更する。
5. 別画面のIdP DOMは読まない。callback結果やサーバーイベントがない場合は認証待ち/未確認とする。
6. run/request/Tool-call IDを区別し、本人の履歴だけを取得する。run IDは認可の代わりにしない。message方式ならorigin/source/schemaを検証し、token/secretを渡さない。

このPRにはevent receiver、認証window制御、DB照会、プラグイン変更、画面への本組み込みは含みません。

## 検証

Archify showcase validate/deliver: 9/9、0 errors、0 warnings。Chrome visual-check: 4画面サイズでcontainment合格、1440×900/2048×1320のlight/darkをcapture。PNGの目視でも重なり・切れ・大きな余白の問題なし。

改訂3ではredirect/callbackラベルのノード重なりを修正し、目視で重なって見えた往路/復路を別ルートに分離（修正2回）。再生成はArchify 2.17の`validate architecture`、`deliver architecture`、`visual-check`を使用し、同じ品質ゲートを通すこと。
