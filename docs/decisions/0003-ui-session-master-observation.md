# ADR-0003: UIセッション、認可マスタ、観測の実装方式

- **日付**: 2026-09-14
- **状態**: 提案中。要件はADR-0002で決定済み。実装案はこのPRのレビューとPoC結果で採否を確定する。

## コンテキスト

UIにOAuthクライアントを重複実装せず、Kongの認可コードフローを使う。カスタム認可の短さを守りながら、DB照会と実イベントの表示を追加する。既存コードのHeader取得やセッション設定を、そのまま新構成で安全に使えるとは仮定しない。

## 検討した選択肢

| 論点 | 提案 | 代案とトレードオフ |
|---|---|---|
| UIからのAPI呼出 | 同一originの経路別Cookieを使うブラウザ→Kong要求 | UIサーバーのtoken relayは現行に近いが、token保管・利用者別結合が増える |
| ログイン | 経路別bootstrap/callback Routeを別画面で開く | UIでOAuthを実装し直す案は責務重複。同一タブへの無断fallbackは図を残す要件と不一致 |
| 図の埋め込み | 同一アプリのSVG＋独立overlayをPoC第一候補 | 同一origin iframe＋独自adapterも候補。既存Viewerにイベント受信APIがあるとは仮定しない |
| DB配置 | `authz-db`専用PostgreSQLコンテナ、専用DB/SELECTユーザー | 既存Kong DBインスタンスの別DBは軽いが、起動・障害・権限が結合する |
| DB接続 | カスタムPluginから直接照会、小さい接続helperを分離 | HTTP認可サービスは構成全体を増やす。Kong内部DAOの外部DB向け転用は前提にしない |
| 観測 | 既存insurance-uiサーバーに短期の実行記録を保持 | 専用トレース基盤はデモには重い。ブラウザresponse.okだけでは拒否・障害を判別できない |

## 決定

**まだ実装方式は決定していない。** このPRは上記第一候補と[設計本文](../design-brief.md)の契約案をレビューへ提示する。PoC前に最終採用・E2E成功と記録しない。

- G1: 経路別Cookie、別画面、callback、両IdP同時ログイン、ログアウト分離。
- G2: OIDCが検証した属性をカスタムPluginへ渡す安全な接点、外部Header偽造の拒否。
- G3: 対象Gatewayイメージで利用できるDBライブラリ、nonblocking接続、timeout、pool、安全な値バインド。
- G4: SVG/iframe adapterと観測イベントの取得、利用者・runの分離、欠落時のunknown表示。

各gateの結果を追記してから「決定」へ変更する。失敗時は代案と差分をレビューし、静かに方式を変更しない。

## 判断基準・根拠

- Pluginの主処理は属性取得、マスタ照会、許可判定、結果出力に限定する。
- UIの表示失敗を理由に認可を許可しない。DB障害はfail closed。
- ブラウザJavaScript、postMessage、URL、公開Pagesへcode/token/secretを渡さない。
- 既存Chat/OBOとセッション・issuer・audienceを混線させない。
- 正式Pathとseedのレビュー案は設計本文を正本とする。将来の複数グループ、deny優先、cache、マスタ管理UIは初期実装に含めない。

## 想定していたこと vs 実際どうだったか

未実装・PoC未実施。`authz.lua`はDB未参照、`handler.lua`はHeaderを読み、現行UIはBearer relay＋`response.ok`判定。新方式へ適合する証拠はない。

## 影響・トレードオフ

- CookieベースAPIはCSRF対策を必要とする。初期ボタンは読取りGETに限定し、変更系は許可マスタ・CSRF設計・テストを揃えるまで拒否する。
- 2つの認証済みセッションと匿名の図表示を分離するため、Route優先順位と例外パスの負例を増やす。
- 観測はbest effort。イベント欠落で認可結果を再解釈せず「未確認」にする。

## 関連する決定

[ADR-0002](0002-hybrid-idp-requirements.md) / [開発再開手順](../development-handoff.md)。
