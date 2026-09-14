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
- Entra DS＋ADFS、Group 1の既存OBO/Tool ACL、Group 2の5グループ×6API結果を維持する。

## ファイル

- `hybrid-idp-demo.architecture.json`: 再生成用Archify JSON。図の構成とIDの正本。
- `hybrid-idp-demo.html`: JS/CSS/inline SVGを同梱した自己完結Viewer。別のJS/CSSファイルは不要。
- `hybrid-idp-demo.png`: ドキュメント用プレビュー画像。
- `event-targets.json`: 将来の実行イベントと図のnode/edge IDを対応させるための資料。Archify標準APIではない。
- `delivery-receipt.json`: ハッシュ、品質検証、公開URL。

SVGファイルが同梱されている場合はArchifyの標準Exportから書き出した編集用vectorです。配信用HTMLの代わりではありません。

## 図の読み方と省略範囲

上段はGroup 1、下段はGroup 2。矢印は認証/認可の論理的な依存・処理経路で、1本のHTTP接続や時系列の全往復を表しません。例えばGroup 1のログイン後はChat UI側がトークンをMCP Routeへ再提示します。各Kongノードは論理責務で、別Gatewayプロセスではありません。

Group 1のLLM/Azure OpenAI経路は認可経路へ焦点を絞るため本図では省略し、既存実装を維持します。Entra DSへ同期するGroup 2のpicketfence側Entra IDと、Group 1のEntra IDは同一テナントという意味ではありません。同期は事前処理です。

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

初稿のラベル重なり2件と小画面での縦overflowを2回の修正で解消。再生成はArchify 2.17の`validate architecture`、`deliver architecture`、`visual-check`を使用し、同じ品質ゲートを通すこと。
