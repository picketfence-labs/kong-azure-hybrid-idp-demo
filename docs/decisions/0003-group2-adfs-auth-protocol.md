# ADR-0003: Group 2（ADFSグループ）の認証プロトコル選定

- **日付**: 2026-09-08
- **状態**: 決定

## コンテキスト
本リポジトリ（`kong-azure-obo-demo`のフォーク）にGroup 2を新設するにあたり、当初の要件は「Kong GatewayからSAML認証でADFSに対して認証し、アサーションから抽出した属性を認可サービスに送りグループ情報を取得する」というものだった。この要件通りにKong Enterprise公式`saml`プラグインを使う前提でPicketfence Labs Obsidian Vault側の設計ヒアリングが進んでいたが、実装着手前に`kong-ee`ソースコード（ローカル最新版、master @ 2026-09-03）を確認したところ、公式`saml`プラグインの実装が要件を満たせないことが判明した。

## 検討した選択肢

**A. Kong Enterprise公式`saml`プラグインをそのまま使う（当初案）**
- Pros: 実装コストが低い（XML署名検証・暗号処理を自前実装しなくてよい）
- Cons: **実現不可能と判明**。`kong-ee/plugins-ee/saml/kong/plugins/saml/saml.lua`の`parse_and_validate_login_response()`が返すのは`username`（NameID）/`issuer`/`session_idx`のみで、SAMLアサーションの`AttributeStatement`を一切パースしない（`saml.lua:378-382`）。認証後の仕組みもNameID→既存Kong Consumerの静的マッピングのみ（`handler.lua:229-247`、`consumers.lua`）で、カスタム属性をダウンストリームへ渡す仕組みが存在しない。加えて`saml.lua:240`のコメントに「AzureAD digest verification can fail when an AttributeStatement is present in the assertion」という既知の懸念も記載されている

**B. 公式`saml`プラグインを改造（フォーク）してAttributeStatement解析を追加**
- Pros: 当初要件（SAML＋属性抽出）に忠実
- Cons: XML署名検証・暗号処理を含む複雑なEnterprise専有コードの改造になり実装難度・セキュリティリスクが高い。Kong Enterpriseライセンス下のソースコード改造の可否も利用者の契約上の判断が必要で、技術的な検討だけでは決め切れない

**C. Group 2もOIDCで認証する方式へ変更（ADFSはOIDC/OAuth2エンドポイントとして使う）**
- Pros: Group 1と同じ`openid-connect`プラグイン（実績あり、`kong-ee`で`groups_claim`/`groups`/`upstream_headers`/`consumer_groups_claim`等のクレームベース機能を確認済み）を使い回せる。ADFS自体もWindows Server 2016+でOAuth 2.0/OIDCをネイティブサポートしており、プロトコル変更自体の実現性は高い
- Cons: 当初要件の「SAML認証」という体裁とは異なる。IdP自体はADFSのまま維持できるため、本デモが検証したい「Entra ID直結OIDCとADFS経由の認証が共存する」という上位の目的（Entra ID/ADFSフェデレーション構成の実演）は引き続き満たせる

## 決定
**C. Group 2もOIDCで認証する方式**を採用する（利用者判断、2026-09-08）。IdPはADFS（Entra IDからフェデレーション）のまま維持し、プロトコルのみSAMLからOIDCへ変更する。

## 判断基準・根拠
- 選択肢Aは技術的に実現不可能（ソースコードで確認済みの事実）
- 選択肢Bはセキュリティリスク・ライセンス上の懸念が実装コストに見合わない
- 選択肢Cのみが「Entra ID直結とADFS経由の認証が共存するデモ」という上位ゴールを、実装リスクを抑えつつ満たせる

**付随する決定（同時に確定）**:
- Group 2の認可ロジックは、`openid-connect`の`groups_claim`/`groups`による宣言的decK設定のみで完結させる案（実装コスト最小）は不採用とし、**カスタムLuaプラグイン**で実装する。理由: Group 2は「レガシーサービス側」に実在する認可ロジック（属性抽出→認可サービス相当の処理→グループ確定）を模したデモであり、そのロジック自体をカスタムプラグイン化することが本デモの主眼であるため（利用者判断）
- Group 2のOBO対応は今回のスコープに含めない（ADFSのOAuthサーバーがRFC 8693 Token ExchangeやMicrosoft固有のjwt_bearer OBO拡張をサポートするかは未検証・保証されていないため）。将来拡張として`docs/design-brief.md`に記録

## 想定していたこと vs 実際どうだったか
（実装・検証を経てから追記する。特にADFSのOAuthサーバーが対応するグラントタイプ・Claim Issuance Policyの実際の挙動は実機検証が必要）

## 影響・トレードオフ
- 呼称を「SAMLグループ」から「Group 2（ADFSグループ）」に変更した（本リポジトリ・ドキュメント全体で統一）
- 将来的にOBO対応が必要になった場合、ADFSのグラントタイプ対応状況を別途調査した上で本ADRを見直す
- Kong Enterprise公式`saml`プラグインは本リポジトリでは未使用のまま（将来、属性受け渡し機能が追加された場合に再検討の余地はある）

## 関連する決定
なし
