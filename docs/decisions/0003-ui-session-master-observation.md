# ADR-0003: UIセッション、認可マスタ、観測の実装方式

- **日付**: 2026-09-14
- **状態**: 提案中。要件はADR-0002で決定済み。P0でPath、fixture、最初のPoC対象を選定済み。実装方式はPoC結果で採否を確定する。

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

### 2026-09-15 P0の選定結果

利用者の進行指示を受け、次を初期実装契約とPoC対象に選定した。これはG1/G2の合格や実装方式の最終決定ではない。

- 公開Pathは`/entra/product`、`/entra/simulation`、`/entra/application`、`/entra/customer`、`/adfs/customer`、`/adfs/policy`、`/adfs/claim`とする。
- [insurance-permissions.json](../design-fixtures/insurance-permissions.json)の5論理ロール、5属性mapping、Entra 20セル、ADFS 15セルを初期実装入力として採用する。実Security Group object IDと稼働DBのseedは環境構築時に対応づける。
- 最初の実装PRではG1とG2の最小PoCを扱う。経路別の別画面ログインとsession分離、安全なclaim受け渡し、外部Header偽造の拒否を試す。
- G1/G2のPoCへDB、図連動、Azure applyを含めない。G3とG4は前段の結果を記録してから別PRで進める。
- `kong-ee`はG2の具体的な疑問が生じた場合だけ該当箇所を確認する。一般的な事前分析は行わない。

## 判断基準・根拠

- Pluginの主処理は属性取得、マスタ照会、許可判定、結果出力に限定する。
- UIの表示失敗を理由に認可を許可しない。DB障害はfail closed。
- ブラウザJavaScript、postMessage、URL、公開Pagesへcode/token/secretを渡さない。
- 既存Chat/OBOとセッション・issuer・audienceを混線させない。
- 正式Pathとfixtureは設計本文を正本とする。session、DB接続、観測の方式は各gateで決める。将来の複数グループ、deny優先、cache、マスタ管理UIは初期実装に含めない。

## 想定していたこと vs 実際どうだったか

### 2026-09-15 G1/G2の試験構成

次の構成を実装し、実Gatewayへ接続しない範囲で検証した。G1/G2の合格と最終採用はまだ記録しない。

- `/insurance/`を匿名shellにし、Entra IDとADFSのlogin、callback、status、logout Routeを分けた。
- IdPごとにsession secret、audience、Cookie name、Cookie Pathを分けた。既存Chat sessionは変更していない。
- OpenID Connect pluginの`login_tokens`を空にし、認証完了redirectへtokenを含めない。`postMessage`は再確認通知だけに使う。
- status Routeは、認証状態と検証済み属性の有無だけを返す。旧Bearer token relayは削除した。
- `/adfs/auth/probe`だけに既存`legacy-authz-adapter`を接続した。期待するscalar属性値をPoC用環境変数で1件指定し、後続の認可DBや6 APIの設定とは分離した。
- UI単体テスト8件、TypeScript、ESLint、webpack production build、Compose構文検証、今回のstate単体と既存stateを含む全10ファイルの`deck file validate`が成功した。
- 実基盤の再監査ではAzureとDockerに再利用できる環境がなく、Terraform planは56 resourceの新規作成だった。実機gateの前提として、Entra middle-tier Appへ`/entra/auth/callback`を追加し、同AppがSecurity Group claimを要求するTerraform設定を追加した。既存Chat callbackとOBO設定は維持する。

対象imageのlabelとローカルimage IDを確認し、source revisionを`7d95f6d021d05405e4c47244049ad21d64619201`へ固定した。そのrevisionのOpenID Connect pluginは、`upstream_headers`で指定したrequest Headerを先に削除し、検証済みtokenまたはuserinfoのclaimが存在する場合だけ値を設定する。OpenID Connect pluginの優先度1050は現行`legacy-authz-adapter`の100より高い。この実装順序から、外部の同名Headerを下位pluginがそのまま信頼する経路は作らない構成になっている。

残る証拠は実Gateway上の負例です。外部から`X-Demo-Verified-Attribute`を指定した未認証要求が401になり、claim欠落時に同HeaderがUpstreamや下位pluginへ残らず、正常tokenのclaimだけが渡ることを確認する。両IdPの同時sessionと片方だけのlogoutも実IdPで確認する。

## 影響・トレードオフ

- CookieベースAPIはCSRF対策を必要とする。初期ボタンは読取りGETに限定し、変更系は許可マスタ・CSRF設計・テストを揃えるまで拒否する。
- 2つの認証済みセッションと匿名の図表示を分離するため、Route優先順位と例外パスの負例を増やす。
- 観測はbest effort。イベント欠落で認可結果を再解釈せず「未確認」にする。

## 関連する決定

[ADR-0002](0002-hybrid-idp-requirements.md) / [開発再開手順](../development-handoff.md)。
