# 基本設計（Dev Design Brief）

2026-09-16改訂。読者は開発担当とデモ実施者です。利用者が承認した要件・図と、これから検証する実装案を分けます。

> [!warning] 開発停止からの設計更新。新要件は未実装
> 旧実装PR #3〜#7はmerge済みですが、保険APIは全6本がADFS向け、カスタム認可はDB未参照、UIは旧方式です。ADFS実基盤の中断・削除は過去記録であり、現在liveや新E2Eを確認したものではありません。図版PR #9は利用者レビュー後、2026-09-15にmerge済みです。本書を含むPR #10は設計ベースラインをmainへ取り込むもので、実装案の採否はADR-0003のG1〜G4 PoCで確定します。

> [!warning] Entra Domain ServicesとAD FSの組合せを再検討中
> 2026-09-16の実機構築で、Microsoft Entra Domain Servicesの`AAD DC Administrators`はAD FSファーム作成に必要なDomain Admin権限を持たず、公式の非Domain Admin手順に必要なDKM事前準備もできないと確認しました。AD FSファームは未構成です。[ADR-0005](decisions/0005-adfs-directory-platform.md)でディレクトリ基盤を再判断するまで、Group 2の基盤構築と実装を進めません。

[![共通UI・Azure・1 DP・6 API](assets/hybrid-idp/hybrid-idp-demo.png)](https://picketfence-labs.github.io/diagrams/5ecfdbb4c0e9/)

## 1. ゴールと変更しない範囲

- 共通Kong Gateway **1 data plane**でEntra IDとADFSのOIDC認証を扱い、経路ごとの認可を説明・検証する。
- Entra DS＋ADFSの維持は承認済み要件だったが、実機で権限モデルが成立しないと確認した。[ADR-0005](decisions/0005-adfs-directory-platform.md)の決定後に、この要件と自己管理AD DSの不採用を更新する。
- 保険6 APIはEntra対象3、ADFS対象2、customer共有1へ分担する。APIは全てKong外・Azure外の同じホスティング領域。
- Group 2のカスタム認可は簡潔なまま、PostgreSQLで属性対応とAPI許可条件を照会する。
- 共通Test UIの図を維持し、IdPは別画面。判定に用いた属性・ルール・結果・停止地点を証拠付きで表示する。
- 既存Chat、OBO、MCP Tool ACL、Azure OpenAI/LLMの機能は維持する。新しい保険APIのREST認可と同一視しない。
- 本PRは文書・設計fixtureだけを変更する。アプリ、Plugin、Route YAML、Terraform、DB migrationは変更しない。

確定要件は[ADR-0002](decisions/0002-hybrid-idp-requirements.md)、実装案は[ADR-0003](decisions/0003-ui-session-master-observation.md)、AD FSディレクトリ基盤の再判断は[ADR-0005](decisions/0005-adfs-directory-platform.md)、作業順序は[開発再開パッケージ](development-handoff.md)を参照してください。既存Group 1は次節、新規の保険API横断要件はその後に記載します。

## Group 1: 既存Chat・OIDC OBO（機能維持・回帰対象）

### 2. 要件（Group 1）

#### 現在（今回のスコープで確実に必要なもの）

**全体フロー**:
1. ブラウザベースの簡単なChat UI + エージェント。ログイン必須・ログアウト可
2. ブラウザからEntra IDへ認可コードフローでアクセストークン発行（Kongが仲介）
3. ユーザーがプロンプトでバックエンドAPIアクセスを要求
4. MCPエンドポイントへのリクエストをKongが検知 → OIDC OBOでユーザーPrincipal情報を元にMCP(API)用トークンへExchange
5. AI MCP ProxyのACLを評価。許可されればtools/listで利用可能なToolを返却
6. AIエージェントがtools/callでMCP/APIを実行し結果を返却
7. ログイン後、Chat UI上部に自分のトークン情報の一部を表示

**Kongが経路全体をフロントする構成**（重要）: Chat UI→AIエージェントの経路も含め、ブラウザからの通信は全てKong Gatewayを経由する。Kongは最低3系統のRoute/Serviceをフロントする:
1. **Chat UI/エージェントアクセス用Route**: `openid-connect`（OBOなし、認可コードフロー＋ログイン可否判定のみ。「AIエージェント」用Security Groupで判定）
2. **MCPエンドポイント用Route**: `openid-connect`（`token_exchange`でOBO）＋`ai-mcp-proxy`（ACL、「API」用Security Groupで判定）
3. **LLM（Azure OpenAI）アクセス用Route**: `ai-proxy-advanced`

LLMアクセスは`ai-proxy-advanced`プラグイン必須。実LLMはAzure OpenAI。エージェント側には抽象化されたエンドポイントを提供し、Azure OpenAI固有の詳細（エンドポイントURL・APIバージョン・デプロイ名等）を意識しない設計にする。

**デモAPI（2本、同じ顧客データを参照）**:

| API | 検索条件 | 戻り値 |
|---|---|---|
| Customer Inquiry | 氏名（部分一致）/性別/都道府県、AND条件 | 顧客ID/氏名/性別/都道府県 |
| Customer Details | 顧客ID（UUID）による一意取得のみ。顧客IDは推測困難なUUID形式であり、事前にCustomer Inquiryを実行してIDを取得することが前提（Customer Details単体では顧客を検索できない。必ずInquiry→Detailsの順で呼ばれる設計） | 顧客ID/氏名/年齢/性別/マイナンバー/都道府県/住所/電話番号/eメールアドレス等（フル項目） |

顧客データ: 100人分のテストデータを生成。顧客IDはUUID。

**Entra ID・権限モデル**:
- Security Groupを「AIエージェント」用と「API」用で別々に定義
- ログイン（Chat UI利用可否）はAIエージェント側のグループで判定、MCP（Tool実行可否）はAPI側のグループでAI MCP Proxy ACLが判定
- ユーザーは最低3人、全員Entra IDアカウントあり
  - 2人にAIエージェントへのアクセスあり（Chat UIにログイン可能）
  - そのうち1人はCustomer Inquiryのみ権限あり、もう1人はCustomer Inquiry・Customer Details両方に権限あり
  - 残り1人はEntra IDアカウントはあるがAIエージェントへのアクセス無し（ログイン不可の反例）

**技術要素**:
- Kongイメージ: `kong/kong-gateway-dev:pr-21082-ubuntu`（ベータ、OBO機能を含むビルド）
- 必須プラグイン: OpenID Connect（OBO用、Chat UIログイン用の2用途）、AI MCP Proxy（ACLはそのネイティブ機能）、AI Proxy Advanced（LLMアクセスの抽象化）
- Konnect不使用（Gateway単体）
- Entra ID連携部分はTerraformでコード化（対象範囲はEntra ID/Azureのみ。Kong/Konnectは対象外）
- Kong自体の設定管理はdecKの宣言的YAML
- 実LLM: Azure OpenAI（`ai-proxy-advanced`経由）
- Kongのデータストア: Postgres（DB-less不採用。decKでの反復的な宣言的変更を行うため）

#### 将来（今回のスコープ外だが、明示的に認識しておくもの）
- **Tool/APIの追加**: 可能性あり。ただし現時点ではToolは2つのみのため、`ai-mcp-proxy`は自己完結の`conversion-listener`モードで開始する。将来Tool追加が必要になった時点で`listener`+`conversion-only`の集約パターンへ作り替える
- **他IdPとの組み合わせ**: なし（Group 1単体としては）。OBOの性質上IdPはEntra ID限定
- **Konnect管理への移行**: 将来的な可能性あり。今回はGateway単体で構築するが、後からKonnectへ移行しやすいよう、Konnect非対応の設定は避け、decKで完結する構成に留める

### 3. アーキテクチャ（Group 1）

#### OIDC OBO機能の実装詳細
`kong/kong-gateway-dev:pr-21082-ubuntu`が含む、Entra ID On-Behalf-Ofフロー対応のベータ機能（`openid-connect`プラグイン）:
- `config.token_exchange.grant_type = "jwt_bearer"` でRFC 7523 JWT Bearerフローを使う（デフォルトは`token_exchange`＝RFC 8693標準のToken Exchange。Entra ID OBOには`jwt_bearer`を使う）
- `config.token_exchange.provider = "microsoft"` にすると、Entra IDのOBOが要求する`requested_token_use=on_behalf_of`パラメータが自動付与される
- 送信されるOAuth2パラメータ: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`、`assertion=<受信した元のBearerトークン>`、`requested_token_use=on_behalf_of`、`scope=<config.scopesまたはtoken_exchange.request.scopes>`
  - `jwt_bearer`グラントでは`audience`パラメータは送信されない。**ダウンストリームAPIの対象（audience）はscopeで指定する**（Entra ID流に`api://<downstream-app-id>/.default`等）
- OBO交換を実行する主体はKong自身（`openid-connect`プラグインの`client_id`/`client_secret`）。この`client_id`は「受信したBearerトークンのaudience」と一致している必要がある
- `config.token_exchange.subject_token_issuers`で信頼する発行者（Entra IDのテナントissuer URL）と、必要ならJWT検証条件を設定する
- `config.token_exchange.map_identities_from`（既定`exchanged_tokens`）で、Consumer/Consumer Group/Principalマッピングに使うクレームを「交換後トークン」由来にするか「交換前の元トークン」由来にするか選べる
- **`openid-connect`単体で`ai-mcp-proxy`のACLに接続できる**: このベータビルドでは`openid-connect`プラグイン自身が`kong.ctx.shared.ai_mcp_oauth2 = { access_token_claims = ... }`を書き込むため、`ai-mcp-oauth2`プラグインを別途有効化する必要はない

#### Entra IDアプリ構成
少なくとも以下2種のApp Registrationが必要:
1. **ミドル層App**（Kongが`client_id`/`client_secret`として保持するApp）: Chat UI（Next.js）自体はOAuthクライアントを持たないため、ログイン用の認可コードフローもOBO交換も、Kongが同じApp Registrationの認証情報で行う
2. **ダウンストリームAPI App**（Customer Inquiry / Customer Details、1つにまとめる）: OBO交換後のトークンのaudience。Security Group 2つ（Inquiry用／両方用）をユーザーに割り当て、`groups`クレームとしてトークンに含める

#### Kong側のプラグインチェーン
1. **Chat UI/エージェント アクセス用Route**: `openid-connect`（認可コードフロー、OBOなし）。ログイン可否判定はEntra ID Enterprise Applicationの「割り当てが必要」設定＋Security Groupの割り当てのみで行う（Kongは非関与）
2. **MCPエンドポイント用Route**: `openid-connect`（`token_exchange.grant_type=jwt_bearer`+`provider=microsoft`でOBO）＋`ai-mcp-proxy`（`acl_attribute_type: oauth_access_token`、`access_token_claim_field`で`groups`クレームを指定）
3. **LLM（Azure OpenAI）アクセス用Route**: `ai-proxy-advanced`。追加認証は掛けず、Docker Composeの内部専用ネットワークで保護

### 4. 技術スタック（Group 1）
- **Kong Gateway**: `kong/kong-gateway-dev:pr-21082-ubuntu`、Docker Compose、Konnect不使用
- **Kongのデータストア**: Postgres
- **Kong側の設定管理**: decKの宣言的YAML
- **Entra ID連携のIaC**: Terraform（`azuread` provider）
- **Chat UI/エージェント**: Next.js（App Router）+ Vercel AI SDK。Auth.js不採用
- **LLM**: Azure OpenAI（`ai-proxy-advanced`経由）
- **デモAPI（Customer Inquiry/Details）バックエンド**: TypeScript、ランタイムはBun

### 5. 検証方法（Group 1、回帰確認）
フォーク元[TESTING.md](../TESTING.md)にある既存テストケース（ログイン拒否／ACL許可・拒否／OBOトークン交換／LLMプロキシ応答）が、本リポジトリでも同様に動作することを確認する（新規スコープなし）。

---

## 共通保険APIデモ: Entra系とADFS系

### 2. 要件と適用範囲

[ADR-0002](decisions/0002-hybrid-idp-requirements.md)が確定要件、[ADR-0003](decisions/0003-ui-session-master-observation.md)が実装案を管理する。2026-09-15のP0確認で、7つの公開Pathと[認可fixture](design-fixtures/insurance-permissions.json)を初期実装契約として採用した。DB schema、UI/session、観測、状態コードはPoCで採否を決める案であり、現行YAMLや配備済みAPIの説明ではない。

- 共通Kong Gateway 1 data planeで両経路を扱う。Kong設定用PostgreSQLと認可業務マスタは分離する。
- 現在のAzure実環境にはEntra ID、Entra DS、ADFS VMがある。ただし、このIdP構成はADR-0005の判断対象であり、目標構成として確定しない。全保険APIはKong外・Azure外の共通ホスティング領域に置き、既存ローカルCompose構成を基本にする。
- カスタム認可はADFS系に限定する。Entra系はSecurity Groupに応じたKong標準機能の条件、既存MCPはTool ACLを維持する。
- Test UIは既存Chat UIを置換しない。保険6 APIの7つの入口（customerは2経路）を対象にする。
- Group 2は引き続きOIDC。初期SAML案は公式`saml` Pluginで必要属性を取り出せなかったため取り下げた。SAMLへ戻さない。

### 3. RouteとAPIの対応

| Backend ID | Entra系公開prefix | ADFS系公開prefix | Upstreamの既存base path |
|---|---|---|---|
| insurance-product | `/entra/product` | なし | `/products` |
| insurance-simulation | `/entra/simulation` | なし | `/simulations` |
| insurance-application | `/entra/application` | なし | `/applications` |
| insurance-customer | `/entra/customer` | `/adfs/customer` | `/customers` |
| insurance-policy | なし | `/adfs/policy` | `/policies` |
| insurance-claim | なし | `/adfs/claim` | `/claims` |

- prefixは完全一致または`/`区切りの子Pathだけに一致させる。`/entra/customer-evil`等の曖昧なprefixを拒否する。
- prefixを一度だけ除去して既存base pathを付加する。例: `/adfs/customer/ITEM_ID` → `/customers/ITEM_ID`。queryは保持し、二重decode・二重prefix除去・Path traversalを拒否する。
- customerは1 Service/同一Upstreamに2 Routeを置く。認証・認可PluginはRoute単位に設定し、ServiceへADFS専用認可を掛けない。
- `/adfs/product`など対象外の組合せと、旧`/product`等の無接頭辞入口は移行完了後に残さない。別IdPへの自動fallbackを設けない。
- 表の「対象経路あり」は利用者への許可ではない。認証後も以下の認可表で判定する。
- APIボタンの初期操作は読取りGETに限定する。各Upstreamで実在するGET operationとfixtureをOpenAPIまたは実機で確認するまで、正常応答を仮定しない。POST等は別途設計する。

### 4. UI、別画面ログイン、セッション

#### Routeの責務案

| 用途 | Path案 | 認証・応答 |
|---|---|---|
| 図と操作UI | `/insurance/`と静的素材 | 未認証で開ける。認証済み属性・履歴は含めない |
| ログイン開始/完了 | `/entra/auth/start`、`/entra/auth/callback`、ADFSは`/adfs/auth/...` | 対応IdPだけの認可コード/セッション処理。KongがOAuthクライアント |
| 認証完了確認 | `/entra/auth/status`、`/adfs/auth/status` | 対応セッションを検証し、最小の状態のみ返す。未認証は401で、XHRをIdPへ転送しない |
| ログアウト | `/entra/auth/logout`、`/adfs/auth/logout` | 対応するデモセッションだけを終了。IdP全体SSO logoutとは区別 |
| 保険API | 前節の7 prefix | session/bearerを検証し認可。APIの未認証は401。ログインはUIの別画面操作から開始 |
| 実行履歴 | `/entra/demo/runs/...`、`/adfs/demo/runs/...` | 対応セッション＋所有者照合。API Serviceへ転送しない |

1. 利用者のクリックで別画面を開ける状態を作り、サーバーが確定したAPIキー→IdP対応を使ってログインを開始する。任意の`issuer`/`return_to`を受け入れない。
2. 未認証ならKongが別画面ブラウザを選択済みIdPへredirectする。元の図画面は維持する。
3. IdPは別画面ブラウザを認可コード付きcallbackへ戻す。Kongがstate/nonce等を検証し、codeをtokenへ交換、tokenを検証してセッションを確立する。UIがcode交換を代行しない。
4. 元画面は同一originの認証状態を再確認する。postMessageは通知だけで、認証成功の証拠にはしない。origin/source/schemaを検証し、code/tokenを含めない。
5. API要求は対応CookieでKongへ送る。認可後だけUpstreamへ到達し、記録された結果を図へ表示する。

Cookie案は`insurance_entra_session`と`insurance_adfs_session`、scopeは対応prefix、秘密鍵も分離。既存ChatのCookieとは共有しない。実際のPlugin設定名・Cookie Path・SameSite・Secure・HttpOnly・callback遷移はG1で確認する。HTTPSを標準の検証条件とし、localhost HTTPが必要なら限定例外と証拠を記録する。

popupがブロックされたら「別画面で開く」リンクを提示する。COOP等でopenerが切れても状態確認で成立させる。同一タブへ黙って切り替えない。両IdPのログイン状態は別表示し、セッション再利用をIdP往復のアニメーションにしない。

IdP内のエラーは各IdP標準画面で確認する。callbackにエラーが返らずIdPに留まる場合、UIは認証待ち/未確認とする。APIの401、Kongの403、DBの503、Upstreamの5xxをIdP画面のエラーへ置き換えない。

### 5. 認可表とPostgreSQLマスタ

#### Entra系のSecurity Group条件

実際のクレームはSecurity Groupのobject IDで照合する。以下はP0で採用したfixtureの論理ロール名で、Azure object IDではない。Terraform等で実IDを取得して環境設定へ対応させる。新しいテナント側割当は未実施。

| 論理ロール | product | simulation | application | customer |
|---|---|---|---|---|
| it | allow | allow | allow | allow |
| sales | allow | allow | allow | allow |
| new-business | allow | allow | allow | allow |
| policy-admin | allow | deny | deny | allow |
| claim | deny | deny | deny | allow |

各Routeの許可Security Group集合をKong標準機能で照合する。新規保険APIの認可を既存MCPのOBO/Tool ACLへ勝手に置換しない。既存Chat/OBOは前節の回帰対象として別に維持する。複数Security Groupの場合は対象Routeの許可集合との積があれば許可する案。groups欠落・overage等で完全な集合が得られない場合はfail closedとし、Graphへの自動照会は初期実装に含めない。

#### ADFS系の業務マスタ

ADFSは入力属性を発行し、PluginがDBで業務グループへ変換する。`department`は既存候補を維持するが、ディレクトリからADFSへの属性供給、ADFS発行、token種別の確認はG2の前提とする。具体的なディレクトリ基盤はADR-0005で決め、token上のclaim名は実機結果で固定する。

| 架空の属性値 | 業務グループ | customer | policy | claim |
|---|---|---|---|---|
| D-IT | it | allow | allow | allow |
| D-SALES | sales | allow | allow | deny |
| D-NEW-BUSINESS | new-business | allow | allow | deny |
| D-POLICY-ADMIN | policy-admin | allow | allow | allow |
| D-CLAIM | claim | allow | allow | allow |

旧業務表のADFS対象3列を投影する。5 mapping行、GETの許可行は13件、denyは2件の「許可行なし」で表現する。API対象外のEntra3サービスをADFSマスタへ登録しない。

| テーブル案 | 主な列・制約 |
|---|---|
| `attribute_group_map` | `attribute_value`主キー、`group_id`必須。入力属性名はPlugin設定で1つ固定 |
| `api_permission` | `group_id, api_id, http_method`の複合主キー、`rule_id`一意。初期は明示GET allow行だけ |
| `master_revision` | seed版を示す1行。判定と同じDB snapshotで読む |

- Pluginから読む認可の正本はPostgreSQL。seedファイルは配備入力、Kongの`allowed_groups`を並行正本にしない。
- `api_id`はRoute/Plugin設定で固定し、callerのHeader/queryで上書きしない。HTTP methodは実リクエストから取得する。
- 1つのJOIN照会または同一snapshotの読取りでmapping、許可行、revisionを取得する。複数グループ・deny優先・cache・再試行・汎用ルールエンジンは初期実装に含めない。
- 主処理は「検証済み属性取得 → DB照会 → 判定 → 最小結果出力」。DB接続helperと観測出力を分け、図の制御をPluginに入れない。
- SQLを文字列連結しない。ドライバーの安全な値バインド、nonblocking動作、timeout、pool、解放、対象イメージでのロードをG3で証明する。ライブラリ名やバージョンは未決。
- DBはKong内部テーブルと分離。Pluginユーザーは必要なSELECTだけ。migration/seedユーザーを分け、DB portをホストへ公開しない。seed更新はtransactionで行う。

#### 認証済み属性の信頼境界

現行`handler.lua`の`kong.request.get_header`を、その名前だけで「検証済み属性」とみなさない。OIDC前にcaller由来の予約Headerを削除し、OIDCが検証したclaimだけを後段へ渡す必要がある。

G2では対象`kong-ee`版を確認し、検証済みcontextへの接点、または証明済みのHeader bridgeを選ぶ。Plugin順序・phase・header欠落時・同名重複Headerの負例を実Gatewayで試験する。安全な接点がなければ認可Pluginの本実装を進めない。ID tokenをAPI用access tokenの代わりに流用しない。

### 6. 判定結果と観測契約案

| 結果 | API/内部結果の目安 | 表示と後段 |
|---|---|---|
| token無効/未認証 | API 401 | authentication failed、Upstreamへ転送しない |
| 必要属性欠落・不正 | 403 / `invalid_attribute` | 認証成功と属性要件不足を区別 |
| mappingなし | 403 / `attribute_unmapped` | 属性未登録。DB接続障害ではない |
| 対象API/操作の許可行なし | 403 / `permission_missing` | 認可拒否、Upstreamへ転送しない |
| DB接続/timeout/schema障害 | 503 / `authorization_unavailable` | DB障害でfail closed。権限不足と表示しない |
| 許可・Upstream正常 | allow＋Upstream status | 認可成功と到達を別段階で記録 |
| 許可・Upstream障害 | allow＋5xx/timeout | 認可をdenyに戻さない。到達証拠なしならunknown |
| callback未帰還/イベント欠落 | 結果未取得 | timeoutだけでIdP失敗・未到達を断定しない |

この表は目標の分類。OIDCが生成する実際のstatus/reasonはPoCでマッピングし、値を架空の実測として埋めない。

#### Headerと実行記録

提案する予約Headerは`X-Demo-Request-Id`、`X-Demo-Identity-Route`、`X-Demo-Authz-Result`、`X-Demo-Rule-Id`、`X-Demo-Master-Revision`。入力属性の限定要約は`X-Demo-Authz-Input`、業務グループは既存`X-Group-Id`を使う案。Entraでは実際に比較したSecurity Group ID集合とマッチした条件を示す。

- ingressの同名HeaderとUpstreamの同名response Headerを削除/上書きし、Gatewayが生成した値だけを観測に使う。デバッグHeaderを認可入力へ再利用しない。
- allow時のUpstream request Headerはバックエンドログ等で確認する。deny時はUpstreamへ送らないため、保護された結果APIで判定情報を表示する。
- token、code、cookie、client secret、全claim、氏名/UPNの不要な表示はしない。属性値は架空デモ値のallowlist・長さ制限・エンコードを適用する。
- Entra標準Pluginの拒否も観測できるよう、認可の後段access処理だけに依存しない観測hookを検証する。観測層は認可を決めず、失敗時もallowへ変更しない。

実行記録案: `schema_version, run_id, request_id, sequence, stage, status, evidence_source, observed_at, identity_route, api_id, method, input_summary, matched_rule, master_revision, authz_result, upstream_status`。`stage`とdiagram IDを別にし、1つのRoute箱に認証/認可の複数段階を対応できるようにする。

- 状態は`not_started/pending/succeeded/denied/failed/not_reached/unknown`。`not_reached`は前段停止などの証拠がある時だけ使う。
- 各runをサーバー発行のランダムIDと所有者に結合し、run IDそのものを認可に使わない。履歴取得時に対応IdPセッションとownerを検証する。
- 未認証の図画面が持てるのは本人の開始/待機状態だけ。認証後の属性・判定履歴は経路別の保護endpointから取得する。
- 既存UIサーバーの有期限・件数制限付きメモリ保持とpollingを第一候補とする。再起動/期限切れは履歴消失として表示する。tokenはこの保存先へ入れない。
- Gateway観測hookからの書込みは内部専用・送信元認証付きとする。ブラウザから任意の成功イベントを書き込めない。欠落、順不同、重複、別runを検出する。
- 外部公開Pagesは静的説明用。実行中の属性や履歴を送らない。開発repo内の素材を同一アプリで使用し、SVG＋overlayまたはiframe＋adapterをG4で選ぶ。

### 7. 検証gateと完了条件

[TESTING.md](../TESTING.md)の新規ケースと既存Group 1回帰を実施し、commit/image digest/環境/操作/期待値/実測/証拠/未達を記録する。文書更新、図のpass、単体test、E2Eのpassを混同しない。

実装順序: [開発再開手順](development-handoff.md)。G1〜G4を小さいPoCで検証してADR-0003を確定した後に、本体の変更と実基盤E2Eへ進む。Azureへのapply/destroy、IdP設定変更、decK syncには別途承認を得る。

### 8. 一次資料と保証範囲

- [Kong OpenID Connect](https://developer.konghq.com/plugins/openid-connect/): セッションと認可コードフローの一般的な機能。対象ベータイメージでの組合せは未検証。
- [Kong request PDK](https://developer.konghq.com/gateway/pdk/reference/kong.request/): Header取得API。claimの信頼性そのものを保証しない。
- [Microsoft AD FS Server App/Web API](https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/development/msal/adfs-msal-web-app-web-api): Application Group内のServer applicationとWeb APIを区別。具体的なKong接続条件はrunbookで検証する。
