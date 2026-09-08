# ADR-0001: ADFSサーバーVMのプロビジョニング・ファーム構築の自動化度合い

- **日付**: 2026-09-08
- **状態**: 決定

## コンテキスト
docs/design-brief.md Group 2「未検証・実装時に確認が必要な技術的前提」で、この論点は明示的にADR化候補として挙げられている:「ADFSのWindows Server VMプロビジョニング＋ADFSロール構成の自動化度合い（Terraformのみで完結するか、追加でPowerShell DSC/カスタムスクリプト拡張が必要か）」。

design-briefは「TerraformでADFSサーバー用VMを作成し、ADFSロールを構成する」ことまでは要求しているが、その構成作業（Windowsドメイン参加、ADFSロールのインストール、ADFSファーム構築、OAuthサーバー機能・Application Group・Relying Party登録、Claim Issuance Policyでのカスタムクレーム発行設定）を`terraform apply`だけで完全自動化するか、一部を手動手順として切り出すかまでは指定していない。

ADFSファーム構築は本番運用でも典型的に以下の理由で自動化が難しいとされる:
- ドメインコントローラ（Entra Domain Services）への参加・伝播待ちのタイミング依存
- ADFS SSL証明書のバインド（自己署名 or 外部証明書の準備）
- サービスアカウント・信頼済み発行者ストアの設定
- 初回のADFSファーム作成（`Install-AdfsFarm`）はドメイン管理者相当の権限・DNS名前解決が前提

## 検討した選択肢

### Option A: フル自動化（Terraform + VM拡張機能でADFSファーム構築・OAuthサーバー設定まで完結）
`azurerm_virtual_machine_extension`（CustomScriptExtension）でPowerShellスクリプトを実行し、ドメイン参加・ADFSロールインストール・`Install-AdfsFarm`・`Add-AdfsApplicationGroup`等のOAuthサーバー設定までを`terraform apply`一発で完結させる。

- **Pro**: 完全にIaC化され、`terraform destroy`→再`apply`での再現性が高い
- **Con**: タイミング依存の処理（ドメイン参加の伝播待ち、証明書生成、DNS解決）が多く、非対話スクリプトでのエラーハンドリングが難しい。初回実行が失敗した場合、VM内のログ（イベントログ・ADFSトレースログ）を漁ってデバッグする必要があり、`terraform apply`のフィードバックループが長い（VM起動+ドメイン参加+ADFSインストールだけで数十分オーダー）。デモ環境の一度きりの構築でこの複雑さに見合うかは疑問

### Option B: ハイブリッド（インフラ・ドメイン参加はTerraform、ADFSファーム構築・OAuth設定は手順書化して手動）
Terraformはリソースグループ・VNet/NSG・VM作成・Azure公式の`JsonADDomainExtension`（ドメイン参加専用の標準VM拡張、汎用的で信頼性が高い）までを担当する。ADFSロールのインストール・ファーム構築・OAuthサーバー機能構成（Application Group、Relying Party登録、Claim Issuance Policy）は、TESTING.mdまたは専用runbook（`docs/adfs-setup-runbook.md`等）にPowerShellコマンド手順として記載し、利用者がRDP接続して対話的に実行する。

- **Pro**: ADFS特有の複雑な設定を対話的に進められるため、初回構築時のデバッグが容易（各コマンドの実行結果をその場で確認しながら進められる）。VM・ネットワーク・ドメイン参加という「失敗しても安全に再実行できる」部分のみをTerraformで管理し、状態を持ちやすい
- **Con**: 完全なIaCではなくなり、`terraform destroy`→再`apply`のたびに手動手順を再実行する必要がある（ただし本デモは「一度構築して検証し、終わったら`destroy`する」想定であり、繰り返し構築する運用ではないため実用上の支障は小さいと考えられる）

### Option C: 完全手動（VMもTerraform管理下に置かない）
design-brief Group2「3. アーキテクチャ」が明確に「TerraformでADFSサーバー用VMを作成」と要求しているため、この選択肢はdesign-briefの要件と矛盾する。検討対象から除外。

## 決定
**Option B（ハイブリッド）を採択**。リソースグループ・VNet/NSG・VM作成・標準の`JsonADDomainExtension`によるドメイン参加までをTerraform（`terraform/adfs_*.tf`）で管理する。ADFSロールのインストール・ファーム構築（`Install-AdfsFarm`）・OAuthサーバー機能構成（Application Group、Relying Party登録、Claim Issuance Policyでのグループ属性クレーム発行設定）は、`docs/adfs-setup-runbook.md`（新規）にPowerShellコマンド手順として記載し、利用者がRDP接続して対話的に実行する。

## 判断基準・根拠
利用者確認の結果、Option Bを採択（2026-09-08）。デモ環境は「一度構築して検証し、終わったら`terraform destroy`する」想定であり繰り返し構築する運用ではないため、完全なIaC化（Option A）で得られる再現性の価値よりも、ADFSファーム構築特有のタイミング依存処理（ドメイン参加の伝播待ち・証明書生成・DNS解決）を対話的に進められる初回構築時のデバッグしやすさを優先した。design-brief「将来の要件」（Konnectへの移行可能性、他IdP追加）とも矛盾しない（ADFSサーバー自体の構成方法は将来要件に影響しないローカルな実装詳細のため）。

## 想定していたこと vs 実際どうだったか
（ADFS実インフラ構築・runbook実行後に追記）

## 影響・トレードオフ
（決定後に追記）

## 関連する決定
なし
