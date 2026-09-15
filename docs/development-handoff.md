# 開発再開パッケージ

次の開発担当は、既存実装を土台にして追加要件へ移行します。Group 2は仕掛かり中であり、ゼロから作り直すプロジェクトではありません。**図版と追加要件は承認済み、実装方式はPoC待ち**です。Azure/アプリ/DBの実装再開完了を意味しません。

## 正本と依存PR

1. [Design Brief](design-brief.md): 現行実装との差分、Route/認可/観測の契約案。
2. [ADR-0002](decisions/0002-hybrid-idp-requirements.md): 利用者が決定した要件。
3. [ADR-0003](decisions/0003-ui-session-master-observation.md): 提案とPoC gate。合格後に採否を確定。
4. [TESTING](../TESTING.md)、[ADFS runbook](adfs-setup-runbook.md)、[図版素材](assets/hybrid-idp/README.md)。

この設計変更は図版PR #9のheadを土台にした独立PRとして作成しました。中断ログPR #8と図版PR #9はmainへmerge済みで、設計PR #10はbaseをmainへ変更し、stacked差分を再確認済みです。

## 変えてはいけない要件

Entra DS＋ADFS、共通Kong 1 DP、6 APIのIdP分担、customerの同一Backend/別Path、別画面IdP、M2のDBマスタ、簡潔なカスタム認可、既存Chat/OBO/Tool ACL/LLMの機能維持。図からUIを省略しない。IdP内部状態やAPI到達を推測で成功扱いしない。

## 現状と最初のgate

| 対象 | 現状 | 次の確認 |
|---|---|---|
| `kong/insurance-*.yaml` | 全6 APIがADFS、APIはBearer、UIが認可コード/セッション | 新7入口へ移行。callerとIdPを固定 |
| `handler.lua` / `authz.lua` | Header＋known_groups/allowed_groups。DBなし | 検証済み属性の安全な入力を証明してからDB化 |
| `insurance-ui` | 保護UI、サーバーtoken relay、`response.ok` | 公開静的shellと保護履歴/経路別セッションへ分離 |
| 図 | 改訂3、quality 9/9、ブラウザ検証済み | 実イベントadapterは未実装 |
| 基盤 | 中断・削除の過去記録、現在live未確認 | 再plan/承認/再構築。過去stateと現在stateを区別 |

- [ ] デモ資格情報を確認。公開履歴に記載された有効パスワードは管理者が変更する。このPRは本文をプレースホルダー化するだけで、履歴削除/失効はしない。
- [ ] Gatewayを起動する直前に、ライセンスと対象image digestを確認する。
- [ ] `kong-ee`の対象版とDB driverは、具体的な検証項目が決まったG2/G3で確認する。P0の一般調査として先行しない。
- [ ] `AGENTS.md`が未追跡でprovider設定説明に差異がある点を認識。実runtime権限を正とし、`.Codex/settings.json`の存在を推測しない。設定変更は別レビュー。

## 既存実装と追加要件の差分

2026-09-15に、PR #7までの実装とADR-0002の追加要件を比較した。追加作業の中心は、RouteのIdP分割、ADFS認可のDB化、共通UIへの変更、実イベントの表示である。既存の6バックエンド、共通Kong data plane、Entra DSとADFSの基盤コードは土台として残す。

| 対象 | 現行 | 追加要件 | 扱い |
|---|---|---|---|
| `docker-compose.yml`の保険API 6サービス | GHCRの6イメージを`kong-internal`へ接続 | 同じ6バックエンドを両IdP経路で共有 | **再利用**。バックエンドを複製しない |
| `kong/insurance-*.yaml`のService定義 | 6 Serviceと既存Upstream path | 同じ6 ServiceにEntra 4 Route、ADFS 3 Routeを接続 | **Service部分を再利用、RouteとPlugin設定を変更** |
| `kong/insurance-customer.yaml` | ADFS用`/customer`が1 Route | `/entra/customer`と`/adfs/customer`が同一Serviceへ到達 | **Serviceを再利用、2 Routeへ変更**。正式PathはP0で確定済み |
| `kong/insurance-ui-route.yaml` | UI全体をADFSの認可コードとsessionで保護 | 未認証でも図を維持し、選んだIdPを別画面で認証。両IdPの状態を混在させない | **Route設計を作り替え**。具体的なendpointとCookieはG1で決定 |
| `legacy-authz-adapter`のPlugin骨格 | access phase、403応答、Upstream Header設定 | 検証済み属性を入力にし、DBでmappingとAPI許可を判定 | **Plugin骨格を再利用、判定ロジックとschemaを変更** |
| `known_groups`と`allowed_groups` | decKとPlugin設定が認可の正本 | PostgreSQLをADFS認可の唯一の正本にする | **廃止対象**。移行後は並行保持しない |
| `insurance-ui`のNext.js基盤 | ADFS専用画面、6ボタン、Bearer token relay、`response.ok`判定 | 共通図、IdP別操作、保護された履歴、認証・認可・到達の分離表示 | **ビルド基盤を再利用、画面とサーバー処理を作り替え** |
| Archify素材 | 目標図、安定ID、イベント対応案を作成済み | 実イベントを原本とは別のadapterで表示 | **素材を再利用、adapterを追加** |
| `terraform/adfs_*.tf` | Entra DS、ADFS VM、network、domain join | Entra DSとADFSを維持 | **原則再利用**。再構築前にplanと対象資源を再確認 |
| `terraform/insurance_users.tf` | `department`に業務グループIDを直接設定 | ADFS属性からDBの業務グループへ変換。Entra側Security Group条件も追加 | **ユーザー作成骨格を再利用**。属性値の変更とGroup割当用リソースの追加が必要 |
| Group 1のChat/OBO/MCP/LLM | 実装済み | 機能を維持 | **変更対象外**。統合時に回帰試験だけ行う |

### 今は変更しない範囲

- `services/chat-ui`、`kong/login-route.yaml`、`kong/mcp-route.yaml`、`kong/llm-route.yaml`
- 保険APIのコンテナイメージとアプリケーション実装
- Entra DSまたはADFSを別製品へ置き換える設計
- ADFSへのOBO追加
- 複数グループ、deny優先、cache、再試行、汎用ルールエンジン、認可マスタ管理UI
- Azure資源の作成、削除、ADFS設定、decK sync。各操作は実行前に別途承認を得る

### PoCまで保留する方式

以下はADR-0003の候補であり、追加要件そのものではない。具体的なgateを先に定め、必要な範囲だけ調査する。

| Gate | 確認すること | 調査を始める条件 |
|---|---|---|
| G1 | 別画面ログイン、経路別Cookie、callback、logout分離 | 最小RouteとUI shellの試験構成を決めた後 |
| G2 | 検証済みOIDC claimの安全な受け渡し、偽造Header拒否 | 対象imageと試験Routeを固定した後。必要なら該当`kong-ee`箇所だけ確認 |
| G3 | nonblocking DB接続、timeout、pool、値バインド、fail closed | DB schemaと1回の判定queryを決めた後。ここでdriver候補を比較 |
| G4 | SVGまたはiframe adapter、実イベント、owner/run分離 | 最小イベント契約を決めた後 |

この順序により、実装に使うか未定の内部コードやライブラリを先に広く分析しない。

### P0の選定結果

- [x] Entra 4入口とADFS 3入口の正式Pathに`/entra/...`と`/adfs/...`を採用した。
- [x] `insurance-permissions.json`の論理ロール、属性値、35セルの期待値を初期実装入力として採用した。
- [x] ADR-0003の第一候補をG1/G2のPoC対象として採用した。実装方式はPoC合格後に決定する。
- [x] 最初の実装PRをG1/G2の最小PoCに限定した。DB、図連動、Azure applyを同じPRへ含めない。

## 推奨実装順序

| 段階 | 作業 | 合格条件・成果物 |
|---|---|---|
| P0 | **完了**。設計レビュー、正式Path、fixture、PoC対象を選定 | ADR-0003に選定結果と保留点を記録 |
| P1 | 小さな認証・属性PoC（G1/G2） | 別画面、両IdP、session分離、検証済みclaim、偽造負例の証拠 |
| P2 | DB接続と判定PoC（G3） | nonblocking/timeout/pool、安全SQL、5 mapping/13 allow、障害fail closed |
| P3 | 図adapterと保護観測PoC（G4） | 原本を改変せず状態連動。owner/run分離、欠落時unknown |
| P4 | Route/UI/Plugin/seedの本実装を小PRへ分割 | 新7入口、customer共有、旧入口廃止、回帰テスト |
| P5 | 承認後のAzure再構築と統合E2E | 35セル＋追加負例＋既存Group 1回帰、未達なし |
| P6 | デモ・削除・引き取り | 結果/コスト/残存確認、ハーネスfeedback |

G1/G2の実IdP部分は基盤が必要です。ローカルのstub試験を先行しても実IdP合格へ繰り上げません。P1時点でAzureが必要なら最小構築の承認を先に得ます。費用が掛かる実基盤の時間を抑え、P2/P3のローカル部分を先行する順序変更は可。新しい方式変更はADR化します。

## PR・検証の運用

- 1 PRを1テーマにし、design/acceptance case ID、実行した試験、未実行、残件を本文に記載する。
- 既存Lua単体試験、UI build/test、decK validate/diff、Terraform validate/planを変更範囲に応じて実施する。新実行ツールは権限と最小動作確認を揃える。
- API/Pluginに触れないこの設計PRで、上記runtime testを実行済みとは報告しない。
- semantic graphの外部送信、常駐サービス、権限設定、CI導入を本件に便乗して追加しない。
- 想定外はtroubleshooting-logへ、アーキテクチャの分岐はADRへ記録。最後に差分/証拠/未達/harness feedbackをVault側へ返す。
