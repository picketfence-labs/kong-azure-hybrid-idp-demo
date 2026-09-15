# 開発再開パッケージ

次の開発担当はこの順で作業します。**図版は承認済み、実装案は設計PRレビューとPoC待ち**です。Azure/アプリ/DBの実装再開完了を意味しません。

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
- [ ] Gatewayライセンス、対象image digest、`kong-ee`の対象版、DB driver候補、必要ツールを確認。
- [ ] `AGENTS.md`が未追跡でprovider設定説明に差異がある点を認識。実runtime権限を正とし、`.Codex/settings.json`の存在を推測しない。設定変更は別レビュー。

## 推奨実装順序

| 段階 | 作業 | 合格条件・成果物 |
|---|---|---|
| P0 | 設計レビュー、正式Path/fixture/方式案の採否 | ADR-0003の提案範囲と保留点を合意 |
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
