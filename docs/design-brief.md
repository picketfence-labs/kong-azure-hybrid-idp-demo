# 基本設計（Dev Design Brief）

Picketfence Labs Obsidian Vaultの「Azure Entra IDとADFS/SAMLが共存するデモ環境の構築」プロジェクトで、利用者とのヒアリングを踏まえて確定した基本設計です（2026-09-08）。

> [!info] このリポジトリの成り立ち
> 本リポジトリは[picketfence-labs/kong-azure-obo-demo](https://github.com/picketfence-labs/kong-azure-obo-demo)をフォークして作成した。フォーク元の内容（本ドキュメントの「Group 1」に相当する部分）はそのまま踏襲し、変更しない。今回新たに追加するのが「Group 2（ADFSグループ）」。フォーク元の全体像・OBOの実装詳細は[docs/OBO.md](./OBO.md)も参照。

## 1. Projectゴール
Kong Gatewayを単一のエントリポイントとして、次の2つの異なる認証経路が共存するデモ環境を構築する:
- **Group 1**: Entra IDと直接OIDC連携し、OBO（On-Behalf-Of）でAIエージェントからのAPI利用を実現する（フォーク元の機能をそのまま維持）
- **Group 2（ADFSグループ）**: Entra IDからフェデレーションしたADFSとOIDCで連携し、レガシーサービス側に存在する認可ロジック（属性からグループ情報を導出しAPIごとのアクセス可否を判定する）をKongのカスタムプラグインとして再現する

---

## Group 1: Entra ID直結・OIDC OBO（フォーク元、変更なし）

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

## Group 2（ADFSグループ）: ADFS×OIDC・レガシー認可ロジックの再現（新規）

> [!warning] 方針転換の経緯
> 当初「Group 2はKong Enterprise公式`saml`プラグインでADFSとSAML連携」という設計だったが、`kong-ee`ソースコード確認の結果、公式`saml`プラグインがSAMLアサーションの`AttributeStatement`を一切パースせず、NameID→既存Kong Consumerの静的マッピングしか行わないことが判明した（属性ベースのグループ判定が実現不可）。利用者判断により**Group 2もOIDCで認証する方式へ転換**した（IdPはADFSのまま、ADFSのOIDC/OAuth2エンドポイントを使う）。詳細な経緯はPicketfence Labs Obsidian Vault側のProjectノートを参照（Vault内部リンクのため本リポジトリからは非公開）。

### 2. 要件（Group 2）

#### 現在（今回のスコープ）
- IdPはADFS（Entra IDからフェデレーション済み）。**プロトコルはOIDC**（SAMLではない）。ADFSのOIDC/OAuth2エンドポイント（`/adfs/.well-known/openid-configuration`）に対し、`openid-connect`プラグインで通常の認可コードフローを実施する
- **OBOは今回のスコープに含めない**（ADFSのOAuthサーバーがRFC 8693 Token ExchangeやMicrosoft固有のjwt_bearer OBO拡張をサポートするかは未検証・保証されていないため。将来拡張として残す）
- **認可ロジックはカスタムプラグイン（Lua）で実装する**。Group 2は「レガシーサービス側」に既に存在する認可ロジック（属性→〈簡略化された〉認可サービス相当の処理→グループ情報取得、という一連の処理）をKongのカスタムプラグインとして再現するデモという位置づけ。`openid-connect`の`groups_claim`/`groups`によるKong標準機能だけで宣言的に済ませる構成は**不採用**（このデモの主眼は「レガシー認可ロジックをカスタムプラグイン化する」こと自体にあるため）
- 属性→グループIDの正規化は**ADFS側では行わない**。テストユーザーの属性値自体を最初からグループID（`it`/`sales`/`claim`/`new-business`/`policy-admin`）として設定し、ADFSはOIDCトークンのクレームとしてそのまま発行する
- 5グループID: `it` / `sales` / `claim` / `new-business` / `policy-admin`
- バックエンドAPIは[kong-api-bundle-insurance](https://github.com/picketfence-labs/kong-api-bundle-insurance)のGHCRパブリックコンテナ6種（`product`/`customer`/`simulation`/`application`/`policy`/`claim`）をdocker-composeでpullして起動
- グループ⇔API アクセスマトリクス（確定、下記参照）をカスタムプラグインの設定（Service単位の`allowed_groups`）で表現し、同一プラグインでアクセス可否判定も行う
- **Group 2専用の新規UIが必要**。既存のChat UI（Group 1のAIエージェント向けフロントエンド）とは別物。**要件（確定済み）**: 最小の検証用ハーネス。ログインボタン＋バックエンド6API呼び出しボタン一覧を表示し、ログイン後は自分のグループIDと各API呼び出し結果（許可/拒否）を並べて表示する。技術スタックは既存Chat UIと同じNext.jsで統一し、別ページ/別ポートで稼働させる
- **ADFSの実体**: picketfence自身のAzureサブスクリプション＋Entra IDテナント（Kong社の`kongstrong.onmicrosoft.com`とは別）に、Terraformで新規構築する
  - ADドメイン要件はMicrosoft Entra Domain Services（旧Azure AD Domain Services、マネージドドメイン）で満たす
  - ADFSサーバー（Windows Server VM）をEntra Domain Servicesへドメイン参加させ、ADFSロールを構成
  - ADFSにOAuthサーバー機能（Application Group、Server application）を構成し、Kongをリライング・パーティとして登録
  - Entra IDにテストユーザー（属性値=グループID）を作成し、Entra Domain Servicesへ同期させ、ADFS認証対象にする
  - Kong（ローカルdocker-compose）↔ADFS（Azure）は**パブリックIP＋NSGで発信元IPを許可リスト化**する方式で疎通させる（VPN等は使わない）
  - **継続コストが発生するが、デモ実施後は`terraform destroy`で全削除する前提のため考慮不要（利用者確認済み）**

#### 将来（今回はやらないが見据えておく）
- Group 2へのOBO対応（ADFSのグラントタイプ対応状況が判明次第、再検討）
- Konnectへの移行可能性
- 他のAPI・IdPを将来追加する可能性
- CI/CD化

#### グループ⇔API アクセスマトリクス（確定）
| グループ | product | customer | simulation | application | policy | claim |
|---|---|---|---|---|---|---|
| it | ○ | ○ | ○ | ○ | ○ | ○ |
| sales | ○ | ○ | ○ | ○ | ○ | × |
| new-business | ○ | ○ | ○ | ○ | ○ | × |
| policy-admin | ○ | ○ | × | × | ○ | ○ |
| claim | × | ○ | × | × | ○ | ○ |

設計意図: `it`は全API横断アクセス（サポート・監視目的）。`sales`/`new-business`は見積り〜契約申込の営業フロー（product/customer/simulation/application）＋契約状況確認（policy）に関与し、claim業務には関与しない。`policy-admin`は既存契約管理が主務でclaimとの整合確認のためclaimも参照可能だが、営業系（simulation/application）には関与しない。`claim`は保険金請求処理が主務で、customer/policyの文脈は必要だが商品カタログ・営業系には関与しない。

### 3. アーキテクチャ（Group 2）

1. **IdP接続**: `openid-connect`プラグインがADFSのOIDCエンドポイントに対し認可コードフローを実施（OBOなし）。ログイン用の新規UI（上記）がフロー起点になる
2. **認可ロジック**: 新規カスタムLuaプラグイン（仮称`legacy-authz-adapter`）が、`openid-connect`が検証したIDトークンのクレーム（属性値=グループID）を読み取り、（デモ内で簡略化された）レガシー認可サービス相当のロジックでグループを確定、`X-Group-Id`等のヘッダーを設定した上で、プラグイン設定の`allowed_groups`（Service単位で個別設定）と照合してアクセス可否を判定する
3. **バックエンドAPI**: `kong-api-bundle-insurance`のGHCR公開イメージ6種をdocker-composeで起動し、それぞれKong Service化。各Serviceに上記カスタムプラグインを`allowed_groups`だけ変えて適用する

#### ADFS/Entra側インフラ（Terraform、picketfence自身のAzure環境）
- Microsoft Entra Domain Services（マネージドドメイン）を有効化
- ADFSサーバー用Windows Server VM を作成し、Entra Domain Servicesへドメイン参加、ADFSロールをインストール・構成
- ADFSにOAuthサーバー機能（Application Group／Server application）を構成し、KongをRelying Partyとして登録
- Entra IDにテストユーザー（属性値=グループID）を作成し、Entra Domain Servicesへ同期
- NSGでKong実行環境（ローカル）の発信元IPのみADFSエンドポイントへのアクセスを許可

#### 未検証・実装時に確認が必要な技術的前提（要検証・要ADR化候補）
- **ADFSのOAuthサーバーが対応するグラントタイプ・クレームカスタマイズの実際の挙動**（Application Group設定、Claim Issuance Policyでのカスタムクレーム発行方法）。Windows Server 2016+のADFSはOAuth 2.0/OIDCをサポートするが、Entra IDほど設定の自由度・ドキュメントが豊富ではないため実機検証が必要
- 使用中のベータイメージ`kong/kong-gateway-dev:pr-21082-ubuntu`が、ADFSのOIDCエンドポイント（Entra IDと異なるディスカバリドキュメント形式の可能性）に対しても`openid-connect`プラグインが問題なく動作するか確認する
- ADFSのWindows Server VMプロビジョニング＋ADFSロール構成の自動化度合い（Terraformのみで完結するか、追加でPowerShell DSC/カスタムスクリプト拡張が必要か）

### 4. 技術スタック（Group 2）
- Kong Gateway Enterprise（Group 1と同じイメージ、ADFS OIDC疎通確認後に最終確定）
- カスタムプラグイン: Lua
- IaC: Terraform（Azure/Entra ID/Entra Domain Services/ADFS VM）、decK
- バックエンドAPI: `kong-api-bundle-insurance`のPython/FastAPIコンテナをそのままpull（新規実装なし）
- 専用UI: Next.js（Group 1のChat UIと同一スタック、別ページ/別ポート）

### 5. 検証方法（Group 2）
- 未認証でのGroup 2系Routeアクセスは全てADFSへのリダイレクト（認可コードフロー開始）が発生し、直接のAPI応答は返らないこと
- ADFSでの認証成功後、IDトークンのクレームから正しいグループIDがヘッダーに設定されること（5グループ全パターン）
- グループ×API アクセスマトリクス（上記30セル）について、許可/拒否が設計表通りに機能すること（positive/negativeケース両方）
- Kong（ローカル）↔ADFS（Azure）のネットワーク到達性: NSG許可リスト外のIPからはADFSエンドポイントに到達できないこと

**外部依存先の前提条件確認（実装着手前）**: ADFSのOAuthサーバー機能・Claim Issuance Policyが実際にKongへ想定通りのクレーム（属性値=グループID）付きIDトークンを返せる状態になっていることを、本格的な認可ロジック実装前に確認する。

### 6. 成果物（Group 2）
- Group 2の全機能（`openid-connect`のADFS向け設定、`legacy-authz-adapter`カスタムプラグイン、6バックエンドサービスのdecK設定、専用UI）
- Terraform: Entra Domain Services・ADFS VM・NSG・Entra IDテストユーザー・ADFS OAuthサーバー設定
- 上記「検証方法」の全テストケースが確認できること

## 参照
- フォーク元: [picketfence-labs/kong-azure-obo-demo](https://github.com/picketfence-labs/kong-azure-obo-demo)（Group 1の実装・実機E2E検証済み）
- バックエンドAPI提供元: [picketfence-labs/kong-api-bundle-insurance](https://github.com/picketfence-labs/kong-api-bundle-insurance)（public、GHCR公開コンテナ6種）
- ローカル参照リポジトリ: `kong-ee`（`openid-connect`プラグインの`groups_claim`/`upstream_headers`等の実装確認、ADFS向け設定の参考。Group 2の認可ロジック用カスタムプラグインの開発にも使う）
