# ADR-0002: 6 APIのIdP分担、PostgreSQL認可マスタ、観測UI

- **日付**: 2026-09-14
- **状態**: 決定（利用者が承認した要件）。実装方式の提案はADR-0003で分離。

## コンテキスト

初期設計は保険6 API全てをADFS側へ置き、属性値をそのままグループIDとして、Kong設定の`allowed_groups`と比較していた。利用者との再整理で、認証経路の分担、RDBMS照会、デモの説明性が追加された。実装は停止中であり、この決定は実機動作の承認ではない。

## 検討した選択肢

| 論点 | 選択肢と判断 |
|---|---|
| AD基盤 | Entra DSを維持／自己管理AD DS。自己構築の手間を理由に利用者が後者を不採用 |
| Group 2認可 | 標準Pluginのみ／独立HTTP認可サービス／カスタムPlugin。簡潔なカスタム実装を見せることが目的 |
| マスタ | 属性対応だけDB化（M1）／API許可条件もDB化（M2）。利用者がM2を選択 |
| IdP画面 | 同一画面遷移／別画面。図を残すため別画面を選択。iframe内のIdP画面ではない |
| customer | IdPを一方へ固定／複製API／Path別に同一APIへ接続。最後の案を利用者が指定 |

## 決定

- 共通のKong Gateway **1 data plane**で両経路を処理する。Konnectは使用しない。
- Entra系は`insurance-product`、`insurance-simulation`、`insurance-application`、`insurance-customer`。
- ADFS系は`insurance-policy`、`insurance-claim`、`insurance-customer`。
- customerは異なるPathを持つがバックエンドは同一。全6 APIはAzure外・Kong外の同じホスティング領域に置く。
- Entra系の認可はEntra Security Groupに対応するKong条件で行う。ADFSはOIDC認証を担当し、カスタムPluginがPostgreSQLの属性対応とAPI許可条件で認可する。
- Entra DS＋ADFSを維持する。ADFS側のOBOは導入しない。既存Chat/OBO/MCP Tool ACL/LLM機能は回帰対象として保持する。
- 共通Test UIから両Routeへ接続する。UIは図を維持し、IdPは別画面。認証エラーは各IdPの標準画面で確認する。
- Headerと観測記録から、実際の判定入力・条件・結果・到達を示す。UIが観測できないIdP内部状態やtimeout後の到達は「未確認」とする。
- Archify改訂3の図を採用する。図の標準Viewer操作と実イベント連動は別物。後者は未実装。

## 判断基準・根拠

利用者の明示判断を根拠とする。図の承認は正式PathやDBドライバーの動作確認を意味しない。将来のAPI追加やKonnect移行は、このデモに汎用ルールエンジンや管理UIを先行導入する理由にしない。

## 想定していたこと vs 実際どうだったか

- 旧「全6 APIをGroup 2で処理」「属性値＝グループID」「UI自体がADFSログインへ遷移」は変更対象。
- 主要旧実装はmerge済みだが、ADFS実基盤と両経路のE2Eは未検証。図の品質検証は認証・認可E2Eの証拠ではない。
- 2026-09-16の実機確認で、Entra Domain Servicesの`AAD DC Administrators`はAD FSファーム作成に必要なDomain Admin権限を持たないと判明した。Entra DS＋ADFS維持と自己管理AD DS不採用を同時に満たす公式構成を確認できないため、この要件だけを[ADR-0005](0005-adfs-directory-platform.md)で再判断する。他のAPI分担、認可マスタ、UI、観測要件は変更しない。
- 2026-09-16、[ADR-0005](0005-adfs-directory-platform.md)でOption A（自己管理AD DSへ切替）を採択。上記「AD基盤」の選択（自己構築の手間を理由に不採用）を更新し、以後は**自己管理AD DS＋ADFS**を基盤とする。デモがAzure前提の環境で実施する必要があるという要件を優先した。

## 影響・トレードオフ

- 旧30セルの認可表をEntra 20セルとADFS 15セルへ分ける。対象外経路の負例も別に設ける。
- customerの認可をService全体に一方のIdPで掛けず、Route単位に分離する。
- RDBMS障害の扱い、セッション分離、観測の機密性、UI別画面を追加検証する。

## 関連する決定

- [ADR-0001](0001-adfs-vm-provisioning-automation.md): Terraformと手動ADFS設定の責務分担を維持。
- [ADR-0003](0003-ui-session-master-observation.md): 実装方式の提案とPoC gate。
- [ADR-0005](0005-adfs-directory-platform.md): Entra Domain Servicesの権限制約を受け、AD FSのディレクトリ基盤を再判断する。
