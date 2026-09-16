# Troubleshooting Log（知見ログ）

実装中に**想定通りに動かなかったこと**を、その場で漏れなく記録するログです。`docs/decisions/`のADR（複数の妥当な選択肢がある判断ポイント専用）とは異なり、判断ポイントかどうかに関わらず、あらゆる「期待と実際のギャップ」（エラー、ドキュメントと異なる挙動、想定した設定で動かなかった、リトライが必要だった等）を対象にします。

## 記入ルール
- **その場で書く**。後からまとめて思い出して書かない
- 追記専用。「大したことではない」と判断して省略しない
- 本プロジェクトはKong Gateway 3.16のベータ機能（Entra ID OBO）を使うため、**公式ドキュメントとの乖離・ドキュメント自体の不在**は特に優先して記録する

## 記入項目（1エントリあたり）
```markdown
## YYYY-MM-DD HH:MM（または該当タスク名） タイトル
- **何を期待していたか**:
- **実際どうだったか**（エラーメッセージ・症状を具体的に）:
- **原因**（分かれば。不明なら「不明」と書く）:
- **対処・回避方法**（または未解決なら次にどうするか）:
- **コスト**（任意。試行回数・かかった時間等、目立って大きい場合のみ）:
```

<!-- 以下、実際のログをこの下に追記していく -->

> [!note]
> 2026-09-08: 本リポジトリ（kong-azure-hybrid-idp-demo）はフォークではあるが、Picketfence Labs内での扱いとしては新規Projectのため、フォーク元での実装時に蓄積したログはここでリセットした（過去の記録はgit履歴から参照可能）。Group 1・Group 2の実装を進める中で判明した事項を、ここから改めて記録していく。

## 2026-09-08 Group 2バックエンド: kong-api-bundle-insuranceの実際のイメージタグ・ポート・パス構造を確認
- **何を期待していたか**: design-brief上は「GHCR公開コンテナ6種をそのままpullして使う」としか書いておらず、具体的なイメージタグ・待受ポート・APIパスは未確認だった
- **実際どうだったか**: `kong-api-bundle-insurance`リポジトリ（README/docs/ARCHITECTURE.md）を確認し、実際に6イメージ全て`docker pull`・`docker run`で動作確認した結果:
  - イメージ参照は`ghcr.io/picketfence-labs/insurance-<service>:v0.1.1`（`<service>`は`product`/`customer`/`simulation`/`application`/`policy`/`claim`）。6種とも同タグでpull可能なことを確認
  - 全サービス共通でFastAPI/uvicornがコンテナ内`:8000`で待ち受け、`GET /health`が`{"status":"ok","service":"<name>"}`を返す
  - コンテナ単体で動かした場合のAPIルートパスは**複数形**（例: product サービスは`/products`・`/products/{product_id}`）。design-brief記載の「パス」列（`/product`等、Kong Gateway経由フルデモでの外部公開パス）とは異なる（単数/複数の差）。本リポジトリでdecKのRoute/Serviceを書く際は、外部パス（`insurance-product.yaml`の命名規則に合わせるなら`/product`等）と実バックエンドパス（`/products`）の対応関係を明示的に設計する必要がある
- **原因**: 不明（`kong-api-bundle-insurance`側の設計判断。REST慣習として一覧系エンドポイントを複数形にしたと推測されるが未確認）
- **対処・回避方法**: `docker-compose.yml`に6サービスを追加する際、上記で確認したイメージ参照・ポート・`/health`ヘルスチェックをそのまま使用。パスの単数/複数差は、次のステップ（Kong Service/Route + `legacy-authz-adapter`カスタムプラグインの配線）で対応する

## 2026-09-08 legacy-authz-adapter実装: kong-eeソース未参照（今回のセッションで未マウント）で設計を確定
- **何を期待していたか**: CLAUDE.md「ローカル参照」節の通り、カスタムプラグイン開発では`kong-ee`（Kong EEソースコード）を一次情報源として参照する想定だった
- **実際どうだったか**: 今回のセッションでは`kong-ee`が`additionalDirectories`にマウントされておらず参照できなかった（リポジトリ自体は`/Users/shinichi.hashitanikonghq.com/LOCAL_REPO/kong-ee`に存在することは`find`で確認したが、このセッションから直接読めるパスではなかった）
- **原因**: セッション起動時の`--add-dir`指定漏れ（明示的な追加依頼をしていなかったため）
- **対処・回避方法**: `openid-connect`の`upstream_headers`によるクレーム→ヘッダー転送は、本リポジトリのGroup 1で実機検証済みの仕組み（`kong/login-route.yaml`で`name`/`preferred_username`クレームを`X-User-Name`/`X-User-Email`へ転送）であり、これをそのまま流用する設計とした（`legacy-authz-adapter`は生ヘッダーを読むだけで、openid-connect側の内部実装詳細に依存しない）。プラグインのpriority（`100`、openid-connectの後に実行）・schema.luaのDSL（`typedefs.no_consumer`等）はKongの公開されている一般的なプラグイン開発規約に基づく設計判断で、`kong-ee`固有の非公開情報には依存していない
- **検証結果（同日追記）**: `KONG_PLUGINS: bundled,legacy-authz-adapter`＋`KONG_LUA_PACKAGE_PATH`でのマウント方式（`docker-compose.yml`、`/usr/local/custom/kong/plugins/legacy-authz-adapter`）を、実際に`kong/kong-gateway-dev:pr-21082-ubuntu`を起動して確認した。Kongは正常に起動（`kong health`成功）し、Admin API `GET /plugins/schema/legacy-authz-adapter`が`schema.lua`通りの内容を返すことを確認。**プラグインのロード自体は実機で確認済み**。一方、`deck gateway validate`は本ライセンス無し（`KONG_LICENSE_DATA={}`のダミー値）だと`services`/`routes`/`plugins`（`openid-connect`だけでなくコアエンティティも含め）全てが`HTTP 403 Enterprise license missing or expired`で拒否されることを確認した。openid-connectの設定内容（`issuer`/`client_id`等のフィールド）そのものの妥当性は、実際のKong Enterpriseライセンスが無いと検証できない（Group 1と同じ制約。検証用コンテナはテスト後に`docker compose down`で削除済み）

## 2026-09-08 insurance-ui実装: Kong経由の実ルーティングはライセンス制約のため未検証、アプリ単体では確認済み
- **何を期待していたか**: `kong/insurance-ui-route.yaml`（新規）を`deck gateway sync`で実際のKongへ反映し、ブラウザ相当のリクエストで`/insurance`配下がinsurance-uiコンテナへ到達すること、ログイン後のグループヘッダー転送・6API呼び出し結果の表示までを一通り確認したかった
- **実際どうだったか**: `deck gateway sync kong/insurance-ui-route.yaml`は想定通り`403 Enterprise license missing or expired`（Service作成自体が拒否される、上記2026-09-08エントリと同一の既知制約）で失敗した。そのため、Kong自体を経由したエンドツーエンドの確認はできなかった
- **原因**: 検証用コンテナにダミーのライセンス値（`KONG_LICENSE_DATA=dummy`）しか設定していないため（実ライセンスが無い環境自体は既知の制約、ADFS実インフラ構築時に本ライセンスが用意される想定）
- **対処・回避方法**: insurance-uiコンテナを起動し、コンテナに直接（Kongを介さず）リクエストを送ることで、アプリ側のロジックのみ切り分けて確認した:
  - `GET /insurance/`（未ログイン相当、`x-adfs-group-claim`ヘッダー無し）→ 200、「未ログイン」表示
  - 同じリクエストに`x-adfs-group-claim: it`ヘッダーを付与 → 200、「ログイン中: グループ it」・ログアウトボタン表示（Kongの`upstream_headers`が転送する想定のヘッダーをこのアプリが正しく解釈することを確認）
  - `GET /insurance/api/access-check?api=product`（`Authorization`ヘッダー無し）→ 401（Kongがトークンを転送しなかった場合の防御が機能）
  - 同、`api=doesnotexist`（許可リスト外）→ 400（allowlist方式のバリデーションが機能）
  - 同、`Authorization: Bearer dummy`付き、`api=product`→ アプリが`http://kong:8000/product`へ正しくfetchし、Kong側にRouteが存在しないため`404`が返り、それをそのまま`{"allowed":false,"status":404}`として返却（Kong未経由の`404`と、legacy-authz-adapterによる実際の`403`拒否は区別できないが、リレー処理自体の配線は正しく機能していることを確認）
  - **Kong自体を介した`openid-connect`（ADFS向け設定）・`legacy-authz-adapter`と組み合わせた実際の許可/拒否判定は、Kong Enterpriseライセンス取得後かつADFS実インフラ構築後に持ち越し**（Group 1・既存6バックエンドRouteと同じ制約）

## 2026-09-08 ADFS実インフラのTerraformコード化: az login未実施のためterraform applyは未実施、validate/planレベルまで確認
- **何を期待していたか**: `terraform/adfs_*.tf`・`terraform/insurance_*.tf`（新規、ADR-0001参照）が構文・プロバイダスキーマとして正しいか、実際のterraform CLIで確認したかった
- **実際どうだったか**: `terraform init -backend=false`は成功（`azurerm`/`azuread`/`random`プロバイダのダウンロード含む）。`terraform validate`も成功（`azurerm_active_directory_domain_service`・`azurerm_virtual_machine_extension`（`JsonADDomainExtension`）・`azuread_service_principal`（AADDSの固定`client_id`）等、記憶を頼りに書いたリソース引数名がプロバイダスキーマと一致していることを確認）。`terraform plan`はダミーの`picketfence_azure_subscription_id`/`picketfence_azure_tenant_id`（全ゼロGUID）を与えたところ、想定通り`azurerm`/`azuread`プロバイダエイリアス（`terraform/adfs_providers.tf`）の認証段階で失敗した（Azure CLIが該当テナント/サブスクリプションの認証情報を持っていないため）
- **原因**: このセッションではpicketfence自身のAzureサブスクリプションへの`az login`が未実施（利用者確認済み、次のステップ）。ダミー値を使った検証のため、実際のAzure環境に対する`terraform plan`の妥当性（クォータ・リージョン提供状況・実際のIAM権限等）はまだ検証できていない
- **対処・回避方法**: `az login`実施後、`terraform/adfs.tfvars.example`をコピーして実際の値を設定し、`terraform plan -var-file=adfs.tfvars`を実行することで初めて実際の差分確認ができる。`terraform apply`はCLAUDE.mdのエスカレーション条件に該当するため、利用者の明示確認後に実行する
- **未検証のまま残る設計判断**: 属性値=グループIDの格納先としてEntra IDの標準属性`department`を採用したが、Microsoft Entra Domain Services経由でのAD属性同期・ADFSのLDAP Attribute Store経由での読み取りが実際に機能するかは実機未検証（design-brief Group2「未検証・実装時に確認が必要な技術的前提」、docs/adfs-setup-runbook.md 7節に要検証事項として明記）

## 2026-09-08 ADFS実インフラのterraform apply: Microsoft.AADリソースプロバイダ未登録で`azurerm_active_directory_domain_service`作成が失敗
- **何を期待していたか**: `terraform apply`（Group 2の30リソースに`-target`でスコープ限定）が最後まで成功すること
- **実際どうだったか**: `random_password`/`azuread_user`（テストユーザー5件・ドメイン参加用管理者）・`azurerm_resource_group`/`azurerm_virtual_network`/`azurerm_subnet`/`azurerm_network_security_group`/`azurerm_public_ip`/`azurerm_network_interface`/`azurerm_role_assignment`（AADDSサービスプリンシパルへの`Network Contributor`）までは全て成功したが、`azurerm_active_directory_domain_service.this`の作成で`409 Conflict: MissingSubscriptionRegistration: The subscription is not registered to use namespace 'Microsoft.AAD'`エラーで失敗し、applyが中断した
- **原因**: picketfence自身のAzureサブスクリプション（`Azure subscription 1`、真新しいサブスクリプションで過去にEntra Domain Servicesを使ったことがない）で、`Microsoft.AAD`リソースプロバイダが未登録だったため。Azureでは初めて使うリソースプロバイダをサブスクリプション単位で明示登録する必要がある仕様（Terraformコード自体の不備ではない）
- **対処・回避方法**: `az provider register --namespace Microsoft.AAD`を実行（サブスクリプション設定の変更だが、リソース作成やコスト発生を伴わないため、CLAUDE.mdのエスカレーション条件には該当しないと判断し、利用者への追加確認なしでその場で対処。登録完了まで数分の非同期処理）。登録完了後、同じterraform planファイルではなく再度`-target`スコープで`terraform apply`を実行し直すことで、既に作成済みのリソースはスキップされ、`azurerm_active_directory_domain_service`以降の未完了分のみ再試行される（Terraformのstate管理により冪等に再開可能）

## 2026-09-08〜09 Entra Domain Servicesの作成に長時間要し中断、`terraform apply`のプロセスkillはAzure側の非同期処理を止められないことが判明
- **何を期待していたか**: `Microsoft.AAD`プロバイダ登録後の`terraform apply`再実行が、合理的な時間内（数分〜十数分程度を想定）に完了すること
- **実際どうだったか**: `azurerm_active_directory_domain_service.this`の作成が74分経過しても完了せず、利用者から「時間がかかりすぎるのでキャンセルしてください」と指示があったため、バックグラウンド実行していた`terraform apply`のシェルプロセスを`TaskStop`で停止した。しかしその直後に`az resource show`で実際のAzure側の状態を確認したところ、**Entra Domain Services自体はAzure側では既に`provisioningState: Succeeded`で作成が完了していた**。つまり、ローカルの`terraform apply`プロセスをkillしても、Azure REST API側で既に受理・実行中の非同期作成処理は一切止まらず、そのまま最後まで進行していた
- **原因**: Azure Resource Managerの非同期操作（Long-Running Operation）は、それを開始したクライアント（この場合はterraform/azurermプロバイダ）が後から切断・終了しても、サーバー側で処理が継続する仕様のため。Azureにはこの種の作成処理を明示的に中断するAPIが用意されていない
- **対処・回避方法**: 「キャンセル」の意図を実現するには、作成済みのリソースを実際に削除する必要があると判断し、以下を実施した:
  1. `az resource list --resource-group rg-kong-adfs-demo`で実際に何が作成済みかを確認（VNet/NSG/Public IP/NIC/Entra Domain Services本体、および後者に付随してAzureが自動生成したLB/PIP/NICも含む）
  2. 利用者に「terraformにimportして完了まで進める」「何もしない」「リソースグループごと削除して完全に中止」の3択を提示し、「リソースグループごと削除」を選択いただいた
  3. `az group delete --name rg-kong-adfs-demo --yes --no-wait`でリソースグループを削除（Entra Domain Servicesはterraform stateに未記録だったため、terraform destroyでは削除できず、Azure CLIでの直接削除が必要だった）
  4. Terraform state上に残っていたEntra IDオブジェクト（テストユーザー5件・ドメイン参加用管理者・AADDS管理者グループ・サービスプリンシパル・ロール割り当て）は`terraform destroy -target=...`で削除。ただしVNet/サブネットはAADDSが自動生成したNIC（terraform管理外）が紐づいていたため、`az group delete`の完了を待ってから`terraform destroy`を再実行し、既に実体が無いことを検出させてstateから除去した
  5. `az group exists`と`terraform state list`の両方で、Azure側・state側ともに何も残っていないことを確認
- **教訓（今後の運用への反映）**: `terraform apply`（特に長時間かかるリソースを含むもの）を非同期・バックグラウンドで実行する場合、「キャンセル」はローカルプロセスの停止だけでは不十分で、Azure側に実際に作成されたリソースの後始末（`import`して完了させる/実削除する）が別途必要になる。次回Group 2のADFS実インフラに再挑戦する際は、Entra Domain Servicesの作成に少なくとも74分以上（今回は打ち切ったため上限不明）かかることを見込み、時間に余裕のあるタイミングで着手すること

## 2026-09-14 Archify説明素材の改訂2: 図品質とPR本文更新の回避
- **何を期待していたか**: 6 APIの分担とAzure/1 DP/APIホスティング境界を図に反映し、PR #9を更新する。アプリやAzureの実装変更は行わない。
- **実際どうだったか**: 初稿でDB照会ラベルが処理ノードに重なり、次に横幅1550のviewBoxで小画面のcontext文字が品質下限を下回った。ラベル位置と余白を修正し、viewBox幅1390でshowcase 9/9・4画面サイズのブラウザ検証を通過。文字サイズ縮小やoverflow隠蔽は行っていない。
- **PR更新の症状**: `gh pr edit 9 --body-file ...`が`repository.pullRequest.projectCards`の旧Projects GraphQLエラーで失敗した。
- **対処**: 同じ本文をGitHub REST `PATCH /repos/picketfence-labs/kong-azure-hybrid-idp-demo/pulls/9`で更新して成功。CLI更新、権限設定変更、PR mergeはしていない。
- **補足**: 作業環境に`rg`が無かったため、限定ファイルをread/Pythonで確認した。runtime実装/E2Eの成功証拠とは分ける。

## 2026-09-14 Archify改訂3: UIの説明欠落を修復
- **症状**: 改訂2で構成境界と6 APIを優先した結果、UIを図から省略し、利用者から認可コードフローの開始点が説明できないと指摘を受けた。
- **対処**: 共通Test UIをKong外へ復元し、両Route入口とブラウザ経由のIdP redirect/callbackを追加。callbackとserver-side token交換を区別。6 APIの経路分担・1 DP・Azure/API境界は維持。
- **検証**: ラベル重なり修正後、目視で往復線の重複を検出し復路を分離。最終showcase 9/9・4画面サイズ・明暗表示・正規PNG/SVGを確認。アプリ実装や認証E2Eは未実施。

## 2026-09-14 設計再整理: 旧前提、公開資格情報、入力の信頼境界
- **症状**: 旧文書は全6 APIのADFS認可、属性値＝グループID、保護UIの自動redirectを前提にしていた。現行access-checkは`response.ok`、認可handlerはHeader取得のみで、追加要件と安全なclaim由来の証明は未実装。
- **対処**: Design Brief/ADR/TESTING/runbook/引き渡しを改訂。確定要件と未検証の実装案を分離し、35セルの認可fixture、session/claim/DB/観測のPoC gateを追加。本体コードは変更していない。
- **資格情報**: 既存TESTING.mdにデモパスワード3件が平文で載っていたため本文をプレースホルダー化した。履歴・画像を含む全面secret監査ではなく、アカウント失効・変更も未実施。有効なら管理者に変更を依頼する。
- **文書上の修正**: ADFSのServer applicationとWeb APIを区別し、TLS/コンテナDNS/同期/claim/全構成decK diffを再開gateにした。旧コマンドの無条件上書きやdomain admin常用を前提から外した。
- **調査範囲**: Graphify graphは存在しなかった。既知の設計/設定/handler/UIファイルを限定確認し、全repo解析・graph生成は行っていない。UIソース参照を最初に`app/`で試して見つからず、既存YAMLに記載された`src/app/`で確認した。
- **静的文書検査**: 初回checkerが旧Group 2シナリオ表も資格情報行として数えたため、対象を旧Group 1資格情報表へ限定して修正。42/42 pass、ローカルリンク切れなし。runtime検証とは区別する。

## 2026-09-15 PR #8〜#10のマージ前確認: forkの既定repo、認証環境変数、stacked PR競合
- **何を期待していたか**: `gh`が`origin`のforkを対象にし、open PRを依存順に確認・マージできること。
- **実際どうだったか**: repo未指定の`gh pr list`はfork元を対象にしてopen PR 0件と表示した。また、無効な`GITHUB_TOKEN`がキーチェーン認証より優先され、最初のGit pushが認証エラーになった。`gh pr status --json currentBranch`は当該gh版で未対応、初回の`jq`整合検査は変数scope指定を誤り、worktree内の最初のmergeはsandboxの`.git`書込み制限で失敗した。
- **対処・回避方法**: `-R picketfence-labs/kong-azure-hybrid-idp-demo`で対象を固定し、`env -u GITHUB_TOKEN`でキーチェーン認証を使用。未対応fieldと`jq`式を修正し、Git metadata更新だけ承認済み権限で再実行した。資格情報の値は表示・記録していない。
- **PR間競合**: #8と#9は個別には`CLEAN`だったが、同じ`docs/troubleshooting-log.md`末尾への独立追記だったため、#8マージ後に#9へmainを取り込むと競合した。両方の記録を時系列順に保持して解消した。
- **追加検査**: #9の生成SVGで末尾空白を検出し、主図のJSON/HTML/PNGを変えずに整形。Archify showcase 9/9、0 errors、0 warningsと`git diff --check`を再確認した。今回のagent mergeは利用者からの明示依頼による例外で、通常の人間merge方針は変更していない。

## 2026-09-15 マージ後の作業開始前確認: sandboxと未設定Compose環境
- **何を期待していたか**: ローカルのTerraform構成とDocker Compose稼働状態を読み取り専用で確認できること。
- **実際どうだったか**: sandbox内の`terraform validate`はprovider pluginを起動できずschema読込みに失敗した。`docker compose ps`はDocker API接続権限ではなく、`.env`が無いため必須の`KONG_PG_PASSWORD`を展開できず停止した。
- **対処・回避方法**: Terraformはprovider実行だけ権限付きで再実行し、構成validを確認。Composeは設定を補完・起動せず、project labelでDockerコンテナ一覧を直接確認して該当0件と判定した。
- **現在状態**: Azure CLI認証は有効、`rg-kong-adfs-demo`は不存在、Terraform stateはdata source 3件のみ。`.env`とKong license設定は未準備で、`terraform/adfs.tfvars`とlocal stateは存在する。値は表示・変更していない。

## 2026-09-15 開発再開時の調査スコープを先行しすぎた
- **何を期待していたか**: PR #8から#11が示す追加要件を、仕掛かり中の実装と比較して再開点を定めること。
- **実際どうだったか**: `development-handoff.md`の事前確認項目を一括して進め、差分整理より先に対象image、`kong-ee`、DB driverの調査へ入った。G2/G3で必要になる可能性はあるが、P0の目的に対して範囲が広く、現在地が分かりにくくなった。repoを固定しない`gh pr list`と無効な環境変数トークンによる既知の失敗も再発した。
- **原因**: P0の「追加要件と現行実装の比較」と、後続PoCの技術的前提確認を同じ作業として扱ったため。
- **対処・回避方法**: まず現行ファイルを再利用、変更、置換、PoC待ちに分類した。`kong-ee`はG2、DB driverはG3の具体的な試験構成を決めてから必要箇所だけ確認する。GitHub CLIは対象repoを明示し、キーチェーン認証を使う場合は無効な`GITHUB_TOKEN`を当該コマンドから除外する。
- **静的検査の補足**: `api-access-map.json`のトップレベルを配列と仮定した初回`jq`集計は`Cannot index number with string "identity_route"`で失敗した。実際は`apis`配列を持つobjectだったため、schemaのkeyを確認して`.apis`を集計対象に修正した。
- **push時の再発**: 通常の`git push`も`Invalid username or token`で失敗した。上記と同じく、当該コマンドだけから無効な`GITHUB_TOKEN`と`GH_TOKEN`を除外して再試行する。

## 2026-09-15 P0 Path採用後も凍結済みの図に旧注記が残る
- **何を期待していたか**: P0で公開Pathを採用した後、開発資料内の位置づけが一致すること。
- **実際どうだったか**: Archify改訂3の再生成用JSONと配信HTMLには、P0前の「説明用のPath案」という注記が残っていた。
- **原因**: 図版を凍結、配信した後にP0の選定が完了したため。
- **対処・回避方法**: 図本体を手編集せず、Design Briefと`insurance-permissions.json`を実装の正本に指定した。図内注記はArchify再生成とreceipt更新を行う別PRで直す。

## 2026-09-15 G1/G2 PoC開始時のGit同期がsandboxで停止
- **何を期待していたか**: PR #12マージ後の`main`を通常の`git fetch`とfast-forwardで同期できること。
- **実際どうだったか**: sandbox内では`.git/FETCH_HEAD`を更新できず、`Operation not permitted`で停止した。
- **原因**: 作業ファイルではなくGitメタデータへのsandbox書き込み制限。
- **対処・回避方法**: Gitメタデータ操作だけ権限付きで再実行し、`main`をマージコミット`5bbe1b9`へfast-forwardした。未追跡の`AGENTS.md`は変更していない。

## 2026-09-15 G1/G2 PoCの初回patchが文字列構文エラーで未適用
- **何を期待していたか**: decK設定とTypeScriptファイルを1回のpatchで追加できること。
- **実際どうだったか**: TypeScriptのtemplate literalとpatch実行ラッパーの文字列構文が衝突し、`SyntaxError: Invalid or unexpected token`でpatch全体が適用前に停止した。
- **原因**: 複数言語の引用符を含む大きなpatchを1つのJavaScript文字列へ埋め込んだため。
- **対処・回避方法**: ファイルを小さいpatchへ分け、template literalを含むpatchだけエスケープして再適用する。
- **再試行**: 同一patchで同じファイルをDeleteとAddの両方へ指定したため、`multiple operations target`で検証停止した。この再試行も未適用。既存ファイルはUpdate操作で全体を置換する。
- **再発**: UIファイル群のpatchでも同じDelete＋Add指定を含めてしまい、検証段階で未適用になった。以後、削除と追加を別patchへ分ける。
- **layout追加時**: JSX内のtemplate literalにある`${...}`が実行ラッパー側で評価され、`ReferenceError`になった。削除済みファイルは`${`とbacktickの両方をエスケープしたpatchで直ちに復元する。

## 2026-09-15 G1/G2 PoCの型検査がsandboxのtempdir制限で停止
- **何を期待していたか**: insurance-uiのunit test、型検査、lint、buildを連続実行できること。
- **実際どうだったか**: `bun test`は3件成功したが、次の`bun x tsc --noEmit`が`bun is unable to write files to tempdir: EPERM`で停止した。
- **原因**: TypeScriptエラーではなく、`bun x`が使う一時ディレクトリへのsandbox書き込み制限。
- **対処・回避方法**: 同じ型検査以降を権限付きで再実行し、コード起因の結果と実行環境の制限を分けて記録する。
- **権限付き再実行**: tempdir制限は解消したが、`node_modules`が存在しない状態で`bun x tsc`を使ったため、単体のTypeScriptを取得してNext/React/Bunの型を解決できず失敗した。既存`bun.lock`に差分は無い。`bun install --frozen-lockfile`後にproject-local依存で再検証する。
- **依存導入**: sandbox内の`bun install --frozen-lockfile`も同じtempdir `EPERM`で停止した。lockfileを変更しない同コマンドだけ権限付きで実行する。
- **依存導入後の型エラー**: project-local依存で再実行すると、Next生成型`LayoutProps`がbuild前に未定義、`bun:test`の型定義が未導入という2件に絞れた。layoutのpropsを明示型に変更し、既存demo-apiと同じBun型をdev dependencyとして追加する。
- **lint**: unit testと型検査は成功したが、React 19の`react-hooks/set-state-in-effect`がeffect直下の初回status取得を同期state更新として拒否した。初回取得をtimer callbackへ移し、effectを外部状態のpolling購読として明確化する。
- **build**: unit test、型検査、lintの成功後、`next/font/google`がGoogle Fontsへ接続できずTurbopack buildが失敗した。PoCに外部Webフォントは不要で既存CSSにsystem font指定があるため、`next/font/google`依存を削除してoffline buildへ変更する。
- **Turbopack**: Webフォント削除後はCSS処理用processがlocalhost portをbindできず、`Operation not permitted`でpanicした。コードや外部通信ではなくsandboxのprocess/network制限なので、buildだけ権限付きで再実行する。
- **権限付きbuild**: 権限付きで再実行してもTurbopackのlocalhost port bindは同じ`Operation not permitted`で停止した。この実行環境では昇格対象外の制約が残るため、Next.js CLIが提供するwebpack経路でproduction buildを切り分ける。
- **CLI help確認**: リポジトリrootで`bunx next build --help`を実行したため、対象packageのlocal binaryではなくbunの一時取得へ進み、既知のtempdir `EPERM`で停止した。以後は`services/insurance-ui/node_modules/.bin/next`を直接使う。
- **decK初回検証**: 新規のidentity別session secretだけをダミー指定したが、同じstate fileに残る既存`DECK_ADFS_SESSION_SECRET`が未指定でtemplate展開前に停止した。`env`参照を列挙し、実値ではなく検証用ダミー値を全て指定して再実行する。
- **decK全state結合**: 今回のstate単体は検証成功したが、既存のKong YAML全10ファイルを`deck file merge`へ渡すと`failed deserializing data as JSON and as YAML`で停止した。原因は完全なstate file群に、部分ファイル向けの`merge`を使ったコマンド選択ミスだった。完全state向けの`deck file render`で全10ファイルを結合し、生成物の`deck file validate`まで成功した。
- **文書更新patch**: `services/insurance-ui/README.md`の全体置換で、既知のDeleteとAddの同時指定を再度使い、patch全体が検証段階で未適用になった。READMEもUpdate操作に統一し、文書ごとに小さく適用する。
- **対象revisionのschema再確認**: ローカル`kong-ee`を`picketfence-labs/LOCAL_REPO`配下と誤記してprocess workdirへ指定し、`No such file or directory`でコマンド開始前に停止した。正しい既知パスは`/Users/shinichi.hashitanikonghq.com/LOCAL_REPO/kong-ee`だった。正しい場所から対象revisionを`git show`し、`login_tokens`の空配列を拒否する制約がなく、今回使うsession Cookie設定がschemaに存在することを確認した。
- **branch push**: 無効な`GITHUB_TOKEN`と`GH_TOKEN`を除外してpushしたが、sandbox内では`github.com`を名前解決できず停止した。認証問題とは分離し、同じpushだけをネットワーク権限付きで再実行する。

## 2026-09-15 P1実機gate再開時のローカル権限制限

- **Azure CLI inventory**: `az account list`はAzure応答へ進む前に、ホーム配下の`.azure/az.sess`を更新できず`Operation not permitted`で停止した。同じ参照コマンドだけを権限付きで再実行し、ログイン先の有無を確認する。
- **Docker inventory**: sandbox内からDocker socketへ接続できず、volumeとnetworkの参照が`permission denied`で停止した。同じ読み取り専用inventoryだけを権限付きで再実行する。
- **Context7**: AzureAD providerの現行仕様を確認するためContext7 skillを選んだが、このsessionのtool inventoryにContext7 MCPが公開されていなかった。公式Terraform Registryの`azuread_application`資料と、ローカルのprovider schemaを使う`terraform validate`、planで代替した。
- **Terraform再検証**: sandbox内の`terraform validate`は3つのprovider binaryがstdout handshake前に終了し、schemaを読み込めなかった。同じ構成の権限付きvalidateとplanは成功済みで、architectureと実行権限にも不整合はない。provider子processのsandbox制限として、validateだけを権限付きで再実行する。

## 2026-09-15 15:51 ADFS VM作成が東日本リージョンのSKU容量不足で停止

- **何を期待していたか**: 承認済みの全体再構築plan（56 create、0 change、0 destroy）で、Entra Domain Servicesの完了後に`Standard_B2s`のADFS VMを東日本リージョンへ作成できること。
- **実際どうだったか**: Entra Domain Servicesは1時間19分59秒で作成完了したが、`azurerm_windows_virtual_machine.adfs`の作成がAzure APIの409 `SkuNotAvailable`で停止した。Azureは`Standard_B2s`が東日本リージョンの容量制約により現在利用できないと応答した。
- **原因**: Terraform構成や権限ではなく、対象サブスクリプションと東日本リージョンにおける`Standard_B2s`の容量制約。Azure SKU APIでもリージョンと全3ゾーンが`NotAvailableForSubscription`だった。
- **対処・回避方法**: 作成済みリソースは削除せず、同リージョンで制限がないx64、2 vCPU、4 GiBの`Standard_D2als_v7`へ変更した。利用者が追加コストを承認後、VMを作成した。別リージョンへの変更はEntra Domain Servicesを含む再作成が必要になるため選ばなかった。
- **コスト**: Entra Domain Services作成の待機に約80分。失敗したVMは作成されていないが、作成済みのEntra Domain ServicesとAzure OpenAIを含むリソースには継続コストが発生する。

## 2026-09-15 代替VM SKUの再planでEntra Domain Servicesの意図しない再作成差分を検出

- **何を期待していたか**: 部分構築後のstateに`Standard_D2als_v7`を指定すると、未作成のADFS VMとドメイン参加extensionだけが追加されること。
- **実際どうだったか**: planは3 add、0 change、1 destroyとなり、作成済みの`azurerm_active_directory_domain_service.this`を再作成しようとした。Azureから読み取った`domain_configuration_type = "FullySynced"`が構成側では未指定のため`null`との差分となり、provider schema上のForceNew属性として判定された。
- **原因**: Entra Domain Services作成後にAzureが確定した既定値をproviderがstateへ保存したが、Terraform構成が同じ値を明示していなかったため。
- **対処・回避方法**: このplanは適用しなかった。構成へ現在値`domain_configuration_type = "FullySynced"`を明記し、再planが2 add、0 change、0 destroyになったことを確認してからVMを作成した。最終の通常planも`No changes`となり、意図しない再作成差分がないことを確認した。

## 2026-09-15 ADFS VMの初回ドメイン参加でDCを発見できない

- **何を期待していたか**: `Standard_D2als_v7`のVM作成後、`JsonADDomainExtension`が`adfsdemo.picketfencelabs.local`へ参加して再起動まで完了すること。
- **実際どうだったか**: VMは63秒で作成できたが、domain join extensionが約3分後に`VMExtensionProvisioningError`で停止した。Windowsの参加ログは、ドメインコントローラーへ接続できず`NetpValidateName`と`NetpJoinDomainOnDs`が`0x54b`を返した。VMイメージはWindows Server 2022 Datacenter Azure Edition、AMD64として正常に起動している。
- **原因**: 調査中。第一候補は、Entra Domain Services作成後に確定したDC IPがVNetのDNSサーバー設定へ反映されていない、または作成済みVMのNICが更新後のDNS設定をまだ取得していないこと。
- **対処・回避方法**: VMとEntra Domain Servicesは削除しない。Azure上のVNet DNS設定、DC IP、VM/NICの状態、extensionの詳細を読み取り確認する。DNS設定を修正する場合はplanで破壊差分がないことを確認し、VMを再起動してからextensionを再試行する。
- **原因確定**: VNetにカスタムDNS設定がなく、VMがEntra Domain ServicesのDCをDNSとして使っていなかった。VNetへDC IP 2件を設定してVMを再起動した後、VM内でDNS設定、LDAP SRVレコード解決、`nltest /dsgetdc`がすべて成功した。
- **修正**: `azurerm_virtual_network_dns_servers.adfs`を追加し、VMがDNS設定完了後に作成される依存関係へ変更した。既存VMはDNS反映後に再起動した。

## 2026-09-15 domain join再試行がAzure上のfailed extensionと競合

- **何を期待していたか**: DNS修正とVM再起動後、1 add、0 destroyのplanでdomain join extensionを再作成できること。
- **実際どうだったか**: 初回失敗時にAzure上へ`domain-join` extensionが残っていた一方、Terraform stateには記録されていなかった。再applyは「resource already exists、Terraformで管理するにはimportが必要」として作成前に停止した。
- **原因**: AzureRM providerがextension作成要求後のprovisioning failureをstateへ保存しなかったが、Azure Compute側は失敗状態のextensionリソースを保持したため。
- **対処・回避方法**: failed extensionをTerraform stateへimportする。その後、`-replace=azurerm_virtual_machine_extension.domain_join`を指定したplanでextensionだけを削除、再作成し、VMや他リソースを置換しないことを確認する。

## 2026-09-15 DNS修正後のドメイン参加がアカウントロックアウトで停止

- **何を期待していたか**: failed extensionをimportし、同extensionだけを置換すれば、DNS修正後のVMがマネージドドメインへ参加できること。
- **実際どうだったか**: extensionはDCのDNS Aレコードを解決し、DC発見にも成功したが、DCのIPC接続がWindowsエラー1909、`0x775`で失敗した。このコードはアカウントのロックアウトを示す。
- **原因**: Microsoft公式情報と一致した。`domain_join_admin`はEntra Domain Servicesの有効化前に作成したcloud-onlyユーザーだったため、マネージドドメイン認証用のKerberos/NTLMパスワードハッシュが生成されていなかった。extensionの失敗試行が既定の5回に達し、マネージドドメイン側で30分ロックアウトされた。
- **対処・回避方法**: Group 2用のドメイン参加管理者とテストユーザー5件のパスワードをTerraformで再生成し、既存ユーザーへin-place更新した。構成上もこれらのユーザーをEntra Domain Services完了後に作成する依存順序へ変更した。`time_sleep.domain_services_identity_sync`で15分の資格情報同期待機を行い、パスワード変更時は待機を再実行する。既存ロックアウトの30分が経過するまで追加の認証試行を止め、解除後にfailed extensionだけを置換する。
- **解決確認**: 最後の失敗から30分以上、パスワード更新から26分以上待ってfailed extensionだけを置換した。extensionは31秒で成功した。VM内部で`PartOfDomain=True`、ドメイン名一致、secure channelの`NERR_Success`を確認し、通常のTerraform planも`No changes`になった。

## 2026-09-15 PR用ブランチのpushが無効な環境変数tokenで停止

- **何を期待していたか**: 検証済みコミットを`origin/ops/rebuild-demo-environment`へpushできること。
- **実際どうだったか**: GitHubがHTTPS認証を拒否し、`Invalid username or token`でpushが停止した。
- **原因**: `gh auth status`ではmacOS keyringに有効な`shinichi-hashitani`の認証がある一方、優先される`GITHUB_TOKEN`環境変数が無効だった。
- **対処・回避方法**: コマンド単位で`GITHUB_TOKEN`と`GH_TOKEN`を除外し、既存keyring認証を使ってpushとPR作成を再試行する。token値はログへ出力しない。
- **解決確認**: 2つの環境変数をコマンド単位で除外したpushは成功し、リモート追跡ブランチを作成できた。

## 2026-09-15 ADFS Federation Service名とVMホスト名のSPN競合を実行前に検出

- **何を期待していたか**: 利用者が承認したADR-0004 Option Aに従い、既存の`vm-adfs-demo.adfsdemo.picketfencelabs.local`をFederation Service名として再利用できること。
- **実際どうだったか**: PowerShell手順へ落とす前にMicrosoft公式資料を確認すると、Federation Service名の`HOST` SPNはADFSサービスアカウントへ登録する必要があり、既存サーバーのWindowsホスト名と同じ名前を使う構成は不正と明記されていた。VMのコンピューターアカウントが同じ`HOST` SPNを既に所有するため、gMSAと競合する。
- **原因**: Option Aの初期比較で、TLS名とDNS再利用だけを評価し、Kerberos SPNの所有者を確認していなかった。
- **対処・回避方法**: ADFSロール、証明書、DNSは変更していない。Option Aを不採用とし、専用Aレコード`adfs.adfsdemo.picketfencelabs.local`と同名証明書を使うOption Bへ切り替える案をADR-0004へ記録した。利用者の再確認後に実装する。

## 2026-09-15 ローカル`kong-ee`の参照先を誤認

- **何を期待していたか**: Group 2の未検証gateに必要なOpenID Connect pluginの`resource`指定だけを、既知のローカル`kong-ee`から確認できること。
- **実際どうだったか**: 最初にこのProjectと同じ`picketfence-labs/LOCAL_REPO`配下を参照して見つからず、ホーム全体の`find`はmacOS保護領域で多数の権限エラーを出したため打ち切った。既存ログには正しいパスが`/Users/shinichi.hashitanikonghq.com/LOCAL_REPO/kong-ee`と記録済みだった。
- **原因**: 既知パスを既存ログで確認する前に、現在のProjectからの相対的な保存場所を推測した。
- **対処・回避方法**: 広い探索を続けず、今回必要な`authorization_query_args_names`、`authorization_query_args_values`、`response_mode`はKong公式資料で確認した。既存ログの正しいパスから対象revisionの該当schemaとCookie処理だけを限定確認し、設定名と既定値を照合した。実Gatewayでのschema検証はGateway起動承認後のgateに残す。

## 2026-09-15 sandbox内の`git add`が`.git/index.lock`作成で停止

- **何を期待していたか**: ProjectのAGENTS.mdにあるリポジトリ内操作の許可方針に従い、レビュー済みファイルだけをstageできること。
- **実際どうだったか**: `git add`は`.git/index.lock: Operation not permitted`で、indexを変更する前に停止した。作業ファイルの変更内容には影響しなかった。
- **原因**: 現在のsandboxはworktreeを書き込み可能だが、`.git`を読み取り専用として公開しており、Project内の許可方針より制約が強い。
- **対処・回避方法**: `AGENTS.md`を含めず対象ファイルを明示した同じ`git add`だけを権限付きで再実行する。権限設定自体は変更しない。

## 2026-09-15 公開リポジトリへのpushが安全審査で停止

- **何を期待していたか**: 検証済みのOption B実装commitを既存publicリポジトリへpushし、PRを作成できること。
- **実際どうだったか**: pushは通信開始前の安全審査で、内部ADFSドメイン等のインフラ情報を公開する操作には個別の明示承認が必要として拒否された。ローカルcommitは作成済みで、remoteは変更されていない。
- **原因**: 利用者の進行指示はあったが、公開リポジトリへ今回のインフラ識別情報を送信するリスクへの明示承認とは判定されなかった。
- **対処・回避方法**: 回避経路は使わず、公開される内容を利用者へ説明してpushの明示承認を得るまで停止する。

## 2026-09-15 `gh pr create`が`upstream`リポジトリを選択

- **何を期待していたか**: push済みの`origin/ops/configure-adfs-service`から`origin/main`へのPRを作成できること。
- **実際どうだったか**: `gh pr create`はhead/base SHAを解決できず、commit差分がないと応答した。remoteを確認するとbranchは`origin`に存在したが、`gh repo view`はfork元の`upstream`を選択していた。
- **原因**: このworktreeには`origin`と`upstream`があり、repositoryを明示しない`gh`がPR対象として`upstream`を選んだ。
- **対処・回避方法**: 今回のPR作成では`--repo picketfence-labs/kong-azure-hybrid-idp-demo`を明示する。git remote設定は変更しない。

## 2026-09-16 AD FSロール導入後の再実行を既存ファームと誤判定

- **何を期待していたか**: `Configure-AdfsDemoFarm.ps1 -Apply`が必要なWindows機能を導入し、同じ実行または安全な再実行でAD FSファームの作成まで進むこと。
- **実際どうだったか**: 最初の実行はローカル管理者で開始され、Windows機能の導入後にドメイン資格情報エラーで停止した。ドメイン管理者の昇格済みセッションから再実行すると、`adfssrv`サービスの存在だけを根拠に`The AD FS service already exists`として停止した。
- **原因**: AD FSロールの導入とファームの構成は別工程であり、ロールを導入した時点でファーム未構成でも`adfssrv`サービスが作成される。スクリプトの既存ファーム判定がサービスの存在だけを確認していたため、正常な中断再開状態を誤検出した。Runbookにもスクリプト転送、ドメインユーザー確認、Windows PowerShell 5.1の昇格確認が不足していた。
- **実測**: Azure VMの読み取り確認では、`adfssrv`は`Stopped`、`Manual`だった。`Get-AdfsProperties`と`Get-AdfsFarmInformation`は`net.tcp://localhost:1500/policy`への接続を拒否され、`FarmConfigured=False`だった。既存ファームではなく、ロールだけが導入された状態と確認した。
- **追加確認**: 構成完了レジストリ値だけを読むAzure Run Commandは完了したが、実行クライアントへ標準出力が返らなかった。値を推測せず、この追加確認は判定根拠に含めていない。
- **再実行時の互換性エラー**: 修正版をWindows PowerShell 5.1で実行すると、存在しない`InitialConfigurationCompleted`を`Get-ItemPropertyValue`で直接取得した箇所が`PSArgumentException`で停止した。`-ErrorAction SilentlyContinue`ではこの例外を抑止できなかった。レジストリキー全体を取得し、値の存在を`PSObject.Properties`で確認してから読む方式へ変更した。値の欠落はロール導入済み、ファーム未構成の正常な状態として扱う。
- **OU存在確認のエラー**: 次の再実行では、未作成の`OU=Kong Demo Service Accounts`を`Get-ADOrganizationalUnit -Identity`で取得した箇所が`ADIdentityNotFoundException`で停止した。Active Directory cmdletの`Identity`指定は対象が存在しない場合に例外を返すため、初回作成前の存在確認には使えない。同じ問題が起きる未作成gMSAの確認も含め、`Filter`、`SearchBase`、`SearchScope`を使う検索へ変更した。0件を初回作成、1件を再利用、複数件を異常として扱う。
- **証明書検索の型エラー**: OUとgMSAの作成後、証明書候補を絞る`$_.DnsNameList.Unicode`が`PropertyNotFoundStrict`で停止した。Windows Server 2022とWindows PowerShell 5.1の実測では、最初の個人証明書の`DnsNameList`は`null`、`EnhancedKeyUsageList`は空だった。`Set-StrictMode`下で空または`null`のコレクションから子プロパティを直接取得したことが原因だった。個別修正の反復を止め、証明書選択以降を含む初回構築経路全体を実環境の型情報とMicrosoft公式仕様で再監査した。
- **型診断の初回失敗**: 証明書の値を出さず型名とプロパティ名だけを得るAzure Run Commandで、`-join ','`の単一引用符がローカルシェル経由で失われ、VM側のPowerShell parserが`Missing expression after unary operator`で停止した。証明書ストアの読み取り前に停止し、値は取得されていない。引数を文字列連結に依存しない`[string]::Join()`へ変更する。
- **実機監査**: 証明書ストア全体のメタデータ取得は範囲が広いため安全審査で拒否された。値、Subject、SAN、thumbprintを出力せず、型名、プロパティ名、件数だけに限定して再実行した。VMはWindows Server 2022 build `10.0.20348`、Windows PowerShell `5.1.20348.5622`だった。ADFS `1.0.0.0`、ActiveDirectory `1.0.1.0`、PKI `1.0.0.0`の各モジュールと、使用する全cmdletの必要パラメーターを確認した。
- **AD FS結果オブジェクト**: `Test-AdfsFarmInstallation`の読み取り専用実測は、`Microsoft.IdentityServer.Deployment.Core.Result`を4件返した。各結果は`Message`、`Context`、`Status`を持ち、無効な既存証明書を使った診断では`Success` 3件と`Error` 1件だった。現行スクリプトは結果を明示評価していなかったため、全件`Success`でなければ停止する共通判定を`Test-AdfsFarmInstallation`と`Install-AdfsFarm`へ追加する。
- **全経路の修正**: 証明書検索をデモ専用FriendlyNameと安全なSAN/EKU検査へ限定した。gMSAのローカル導入は再実行可能にし、AD FS discoveryは最大60秒再試行する。Windows機能の導入後は、DNS、OU、gMSA、証明書のread-only inventoryまで行うdeep preflightを`-Apply`なしで実行し、すべて通過するまで変更処理へ進まない。
- **回帰テストの初回失敗**: deep preflightより前に変更cmdletがないことを検査するテストが、文字列tokenの`Text`に含まれる引用符を考慮せずmarkerを見つけられなかった。製品スクリプトの検査へ進む前に停止した。文字列ASTの`Value`を使う境界検出へ変更した。
- **Windows PowerShell 5.1検証**: branch上の構成スクリプトと回帰テストをVMの一意な一時フォルダーへ取得し、Windows PowerShell 5.1で実行した。構文解析と全回帰テストが成功し、stderrは空だった。一時フォルダーは同じ実行の`finally`で削除した。DNS、AD、証明書ストア、AD FSは変更していない。
- **対処・回避方法**: サービス削除や`OverwriteConfiguration`は使わない。構成完了フラグと`Get-AdfsProperties`で既存ファームを検出し、`Stopped`、`Manual`のロール導入済み状態だけ再開を許可する。その他の判定不能なサービス状態は停止する。適用前にWindows PowerShell 5.1、管理者昇格、ドメインユーザーUPNも検証する。
- **Runbook修正**: `C:\KongDemo\adfs`はTerraformで作成されないことを明記し、レビュー済みcommitからの取得コマンドを追加した。Windowsへのサインインをローカル管理者からドメイン管理者へ切り替える手順と、`whoami.exe /upn`による確認も追加した。

## 2026-09-16 AD FSファーム前提条件検査がDomain Administrator権限不足で停止

- **何を期待していたか**: deep preflightで既存のDNS、OU、gMSAを再利用し、`Configure-AdfsDemoFarm.ps1 -Apply`がTLS証明書とAD FSファームを作成すること。
- **実際どうだったか**: TLS証明書作成後、`Test-AdfsFarmInstallation`が「Domain Administrator credentials、または`AdminConfiguration`とDomain Administrator preparationが必要」と返し、スクリプトがファーム作成前に停止した。表示されたUPNは`adfs-domain-admin@hashipicketfence.onmicrosoft.com`だった。
- **現時点の判断**: `whoami /upn`はドメインアカウントであることしか確認しておらず、現在の昇格トークンがマネージドドメインの`AAD DC Administrators`／`Domain Admins`相当権限を持つことは検証していない。ユーザーのディレクトリ所属、Windowsトークン内のSID、管理グループの対応関係を読み取り専用で確認するまで、`-Apply`を再実行しない。
- **部分変更**: DNS、OU、gMSAは既存を再利用し、AD FSファームは未構成のまま。実機のread-only inventoryで、デモ用TLS証明書がPersonal storeに1件、そのthumbprintと一致する証明書がRoot storeに1件あり、`C:\ProgramData\KongDemo\adfs-demo-root.cer`も存在すると確認した。
- **診断コマンドの初回失敗**: Azure CLIのJMESPath query `value[].message`を引用しなかったため、ローカルzshが角括弧をglobとして解釈し、`no matches found`で停止した。Azure APIは呼ばれず、VMにも到達していない。query全体を単一引用符で囲んで再実行する。
- **実機確認**: `adfs-domain-admin`の所属は`AAD DC Administrators`と`Domain Users`であり、`Domain Admins`には所属していない。デモ用TLS証明書はLocalMachineのPersonal storeに1件作成済み、`CN=ADFS,CN=Microsoft,CN=Program Data`のDKM親コンテナは未作成、`adfssrv`は`Stopped`／`Manual`でファーム未構成だった。
- **原因確定**: Microsoft Entra Domain Servicesはテナント利用者へDomain Admin／Enterprise Admin権限を提供しない。`AAD DC Administrators`はドメイン参加VMのローカル管理、DNS、GPO、カスタムOU等に限定された委任管理者である。一方、通常の`Install-AdfsFarm`はDomain Admin資格情報を要求し、非Domain Admin方式もDomain Adminが事前にDKMコンテナとACLを準備した`AdminConfiguration`を必要とする。現在のEntra Domain Services構成だけでは、その公式前提を満たせない。
- **PR準備時の認証停止**: 設計記録commitの最初のHTTPS pushは`Invalid username or token`で停止し、remoteを変更しなかった。値を表示せず認証元を確認すると、`GITHUB_TOKEN`環境変数と`~/.config/gh/hosts.yml`の両方をGitHub CLIが無効と判定した。環境変数を除外するだけでは解消しなかった。既存SSH認証による同じrepositoryの`ls-remote`は成功したため、remote設定を変更せず、pushコマンドだけSSH URLを使用した。SSH pushは成功し、設計記録branchを作成できた。
- **GitHub CLI再認証**: 最初のdevice codeは利用者確認を待つ間に期限切れとなり、GitHubの許可ボタンが無効になった。次の試行は既存の失敗画面を再利用した状態で入力と送信を同時に行い、GitHubが`not_found`を返した。3回目はaccount selectionからdevice画面を開き直し、入力結果を確認してから送信した。passkey認証後、keyringへの保存、`repo` scope、対象repositoryの`ADMIN`権限を確認した。codeやtoken値は記録していない。
- **HTTPS Git認証の復旧**: GitHub CLI再認証後も、最初のHTTPS pushはmacOSの既存credential helperを使って認証エラーになった。`gh auth setup-git`でGitHub向けhelperをGitHub CLIへ設定し、コマンド環境から無効な`GITHUB_TOKEN`を除外するとHTTPS pushが成功した。repositoryのremote URLは変更していない。

## 2026-09-16 destroy終盤でEntra application identifier URI削除が一時的な404になった

- **何を期待していたか**: `terraform destroy -var-file=adfs.tfvars`が、planで確認した58リソースを1回で削除し、空のstateで正常終了すること。
- **実際どうだったか**: Azureの両リソースグループ、Entra Domain Services、VM、Azure OpenAI、および大半のEntraオブジェクトは削除されたが、`azuread_application_identifier_uri.downstream_api`の削除でMicrosoft Graphが`Request_ResourceNotFound`を返し、初回destroyは終了コード1になった。Terraform stateにはdownstream APIのapplicationとidentifier URIの2件が残った。
- **調査結果**: 直後のMicrosoft Graph照合では、stateと同じobject IDのdownstream API applicationとidentifier URIが実在していた。他の対象EntraオブジェクトとAzureリソースグループは残っていなかった。このため、実リソース消失ではなく、並行削除中のMicrosoft GraphまたはAzureAD providerから見た一時的な整合性のずれと判断した。
- **対処・解決確認**: 残存2件を確認してから同じdestroyを再実行した。identifier URIとapplicationは順に削除され、`Destroy complete! Resources: 2 destroyed.`で正常終了した。手動削除や`terraform state rm`は行っていない。

## 2026-09-16 `gh pr create`がfork元（upstream）のkong-azure-obo-demoへPRを作ろうとして失敗した

- **何を期待していたか**: `git push`後、`gh pr create`が`origin`（`picketfence-labs/kong-azure-hybrid-idp-demo`）に対してPRを作成すること。
- **実際どうだったか**: `git push -u origin <branch>`は成功し、`git log origin/main..HEAD`でも新規commitがリモート追跡ブランチ上に存在することを確認できたにもかかわらず、`gh pr create`は`Head sha can't be blank, ... No commits between main and <branch>`で失敗した。`gh repo view --json nameWithOwner`で確認すると、gh CLIが解決していたリポジトリは`picketfence-labs/kong-azure-obo-demo`（本リポジトリのfork元、`git remote`の`upstream`）で、`origin`ではなかった。
- **原因**: このリポジトリは`kong-azure-obo-demo`のフォークで、`upstream`remoteが設定されている。`gh`はデフォルトのリポジトリ解決で、フォーク元（upstream）を優先することがある。
- **対処・解決確認**: `gh pr create`に`--repo picketfence-labs/kong-azure-hybrid-idp-demo --head <branch> --base main`を明示指定したところ成功した（PR #25）。フォーク関係のあるリポジトリで`gh`コマンドを使う際は、対象リポジトリを毎回明示指定するか、事前に`gh repo view`でgh CLIの解決先を確認する。

## 2026-09-16 自己管理AD DSフォレストの`terraform apply`実行で、CustomScriptExtension関連の実装不備が3件見つかった

PR #25マージ後、利用者承認を得て`terraform apply -var-file=adfs.tfvars`を実行した。以下3件はいずれも実機実行で初めて判明し、コード修正→再applyで解決した（設計判断ではなく実装不備のため、既存ADRの改訂ではなく本ログにのみ記録する）。

- **1件目: Windows VMはCustomScriptExtensionのhandlerを1台につき1つしか持てない**
  - **何を期待していたか**: `create_forest`（フォレスト昇格）と`create_domain_objects`（ドメイン管理者/テストユーザー作成）を別々の`azurerm_virtual_machine_extension`（いずれも`Microsoft.Compute`/`CustomScriptExtension`）として、`time_sleep`を挟んで順に適用できること。
  - **実際どうだったか**: `create_forest`（フォレスト昇格）は3分54秒で正常完了したが、続く`create_domain_objects`の作成が`400 Bad Request: Multiple VMExtensions per handler not supported for OS type 'Windows'`で失敗した。
  - **対処・解決確認**: 2つの拡張機能を1つ（`bootstrap_dc`）へ統合し、スクリプト側で「既にドメインコントローラーなら直接実行、未昇格ならフォレスト昇格→再起動後に起動時スケジュールタスクで続行」という分岐で同じ目的を達成する設計へ変更した（`scripts/adfs/Install-AdDsForest.ps1`）。
- **2件目: CustomScriptExtensionの`commandToExecute`に長いスクリプト全文を`-EncodedCommand`で埋め込むと"The command line is too long."で失敗する**
  - **何を期待していたか**: 1件目の統合後、2つの`.ps1`ファイルの内容を1本のコマンド文字列へ結合し、`textencodebase64(..., "UTF-16LE")` + `-EncodedCommand`でそのまま実行できること。
  - **実際どうだったか**: `azurerm_virtual_machine_extension.bootstrap_dc`の作成が`VMExtensionProvisioningError`（`Command execution finished, but failed... 'The command line is too long.'`）で失敗した。cmd.exe経由で渡される`commandToExecute`には実用上の長さ上限がある。
  - **対処・解決確認**: スクリプト本体は非公開のBlob Storage（`azurerm_storage_account`/`_container`/`_blob`、SAS URL）へ配置し`fileUris`でVMへダウンロードさせ、`commandToExecute`は`-File`呼び出しの短い1行だけにする方式へ変更した。
- **3件目: SASの`start`/`expiry`に`timestamp()`を使うと評価のたびに値が変わり、`protected_settings`に毎plan差分が出る**
  - **何を期待していたか**: 2件目の対処後、`terraform plan`が収束し`No changes`になること。
  - **実際どうだったか**: `data.azurerm_storage_account_sas`の`start`/`expiry`に`timestamp()`を直接使ったため、SAS文字列が評価のたびに変わり、`bootstrap_dc`の`protected_settings`が毎回差分として現れた。
  - **対処・解決確認**: `time_static`リソースで作成時刻を1回だけ固定し、それを`start`/`expiry`の基準に使うよう変更した。以降`terraform plan`は`No changes`で安定した。

**最終確認（実測）**: `az vm run-command invoke`で`vm-dc-demo`に読み取り専用コマンドを実行し、`DomainRole=5`（フォレスト昇格済み）、`adfs-domain-admin`と5テストユーザー（`demo-it`/`demo-sales`/`demo-new-business`/`demo-policy-admin`/`demo-claim`、いずれも`department`属性設定済み）の存在、`adfs-domain-admin`が`Domain Admins`メンバーであることを確認した。`vm-adfs-demo`でも同様に`PartOfDomain=True`、`Domain=adfsdemo.picketfencelabs.local`、FQDN`vm-adfs-demo.adfsdemo.picketfencelabs.local`を確認した。`Install-ADDSForest`は昇格対象サーバーのローカル管理者アカウント（`adfsvmadmin`）も`Domain Admins`へ引き継ぐ（Windows標準の仕様）ため、`adfs-domain-admin`と並んでこのアカウントも`Domain Admins`に含まれることを確認済み（想定外ではなく仕様通り）。

## 2026-09-16 `adfs-domain-admin`のRDPログインが失敗し、パスワード同期バグとCLIパラメータ経由の露出2件が判明した

- **何を期待していたか**: `terraform output adfs_domain_admin_credentials`のUPN・パスワードで、`vm-dc-demo`・`vm-adfs-demo`いずれへもRDPログインできること。
- **実際どうだったか**: 両VMとも`The Credentials Did Not Work`で拒否された。`az vm run-command invoke`（読み取り専用）で`adfs-domain-admin`のAD属性を確認すると、`BadPwdCount=7`（AD側が実際に比較・拒否した実測値）かつ`PasswordLastSet`がアカウント作成時刻から一度も変わっていなかった。
- **原因確定**: `scripts/adfs/New-AdDsDomainObjects.ps1`のアカウント作成ロジックが「`SamAccountName`が既に存在すれば作成をスキップ」という設計で、パスワードをTerraform管理値へ同期する処理を持っていなかった。PR #26のバグ対応中に発生した複数回の`terraform apply`試行のいずれかで、AD側へ実際に反映された時点のパスワードと、収束後にstateへ残ったパスワードがずれた（テストユーザー5名の作成ロジックも同じ設計だったため、同種のズレが理論上あり得る状態だった）。
- **調査・復旧作業中の事故（パスワード露出2件）**: 原因切り分けと復旧のため`az vm run-command invoke`を使う過程で、パスワードを平文でCLI引数として扱い、このセッションのツール出力へ2回露出させてしまった。1回目は`--protected-parameters`という当該azバージョンの`vm run-command invoke`には存在しないオプションを指定し、CLIの引数解析エラーメッセージにその場でパスワードが含まれて出力された。2回目は`--parameters`経由でパスワードを渡した際、値に含まれる特殊文字（`!`・`)`等）をWindows側のコマンドライン解析が誤って分割し、`'<password>' is not recognized as an internal or external command`という形でやはり実際の値がそのままエラー出力に含まれた。**教訓**: `az vm run-command invoke`の`--parameters`／`--protected-parameters`は特殊文字を含む値の受け渡しに使わない。値はローカルの一時ファイルへ書き出し（Bashのheredocで変数展開し、コマンド引数には出さない）、`--scripts @{file}`で読み込ませる方式に統一する（Terraform側で既に実績のある`-EncodedCommand`方式と同じ考え方）。
- **対処・解決確認**:
  1. `scripts/adfs/New-AdDsDomainObjects.ps1`を修正し、アカウントが既存でも`Set-ADAccountPassword -Reset`でTerraform管理値へ常に同期するよう変更（ドメイン管理者・テストユーザー5名とも）。
  2. 2回露出した値をこれ以上使い続けないよう、`terraform apply -var-file=adfs.tfvars -replace="random_password.domain_join_admin"`でパスワードを再採番（承認済み）。これにより`azurerm_storage_blob.new_ad_ds_domain_objects`（修正後のスクリプト内容）と、`bootstrap_dc`・`domain_join`両拡張機能の`protected_settings`が更新され、`vm-dc-demo`上で修正後のスクリプトが再実行された。
  3. ローカルの一時ファイル方式で`System.DirectoryServices.AccountManagement.PrincipalContext.ValidateCredentials`を`vm-dc-demo`上で実行し、新しいパスワードがAD側の実際の値と一致すること（`ValidateCredentials=True`）を確認した。`vm-adfs-demo`は`domain_join`拡張機能の再実行後も`PartOfDomain=True`のまま（ドメイン再参加は問題なく冪等だった）。
  4. `terraform plan -var-file=adfs.tfvars`は`No changes`に収束済み。
  5. 検証・復旧に使ったローカルの一時スクリプト・ログファイル（平文パスワードを含む）はすべて削除済み。

## 2026-09-16 RDP経由でパイプ・カンマを含むコマンドを貼り付けると`>>`の継続入力プロンプトへ入り結果が空になった

- **何を期待していたか**: `docs/adfs-setup-runbook.md`Section 2手順4の`$PSVersionTable | Select-Object PSEdition, PSVersion`を管理者Windows PowerShellへ貼り付け、`PSEdition`/`PSVersion`が1行で表示されること。
- **実際どうだったか**: RDP経由のクリップボード貼り付けで、コマンドが`>>`（PowerShellの継続入力プロンプト）に入ったまま止まり、Enterで確定させても`PSEdition`/`PSVersion`の見出しだけが表示されデータ行が空になった。空行のままEnterを2回押して`>>`状態を解消しても再現した。
- **対処・解決確認**: パイプ・カンマを使わない`$PSVersionTable.PSEdition`／`$PSVersionTable.PSVersion`の2コマンドへ分けて個別に貼り付けたところ、それぞれ`Desktop`／`5.1...`が正しく表示された。`docs/adfs-setup-runbook.md`Section 2手順4を、この2コマンド方式へ更新した。RDP先へ複数行のPowerShellコマンドを貼り付ける手順は、今後もパイプ・カンマを含む1行コマンドを避け、可能な限り1コマンド1行へ分割する。

## 2026-09-16 `Configure-AdfsDemoFarm.ps1 -Apply`のgMSA/AD FSファーム作成が繰り返し失敗し、原因が2つ重なっていた

Section 2手順10（`.\Configure-AdfsDemoFarm.ps1 -Apply`）の初回実行から、`AD FS farm installation failed: Unable to retrieve group Managed Service Account information. The system cannot find the file specified`まで、複数の仮説を順番に検証しながら原因を切り分けた。最終的に**2つの独立した原因**が重なっていたことが判明した。

- **原因1: 単一DCフォレストでKDS root keyの`msKds-CreateTime`が実時間で10時間経過していないと、AD FSが独自に拒否する**
  - **何を期待していたか**: `New-ADServiceAccount`実行時にKDS root keyが存在しなければ自動作成され、gMSAのパスワードがすぐに取得できること。
  - **実際どうだったか**: 自動作成されたroot keyの既定の有効時刻（作成から10時間後）が未到来のため、`WARNING: The root key for the group Managed Service Account was created at ...`とともに`Install-AdfsFarm`が失敗した。`Test-ADServiceAccount`はこの間`True`/`False`を行き来し、一時的にキャッシュの影響で`True`になることもあったが、`Install-AdfsFarm`は毎回同じ警告付きで失敗し続けた。
  - **切り分けの過程**: (a) `msKds-UseStartTime`属性だけを`Set-ADObject`で過去日時へ書き換える対処は不十分だった。(b) Root keyを削除し`Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))`で作り直しても、`Get-KdsRootKey`の`EffectiveTime`は過去になるが`CreationTime`（`msKds-CreateTime`属性）は実際の作成時刻のまま変わらず、`Install-AdfsFarm`は`EffectiveTime`ではなく`CreateTime`を直接チェックしていることが実機で判明した。(c) DC側の`KdsSvc`（Key Distribution Service）の再起動も無関係だった（内部キャッシュの問題ではなかった）。
  - **対処・解決確認**: `msKds-CreateTime`と`msKds-UseStartTime`の両方を`Set-ADObject`で同じ過去日時（実行時刻の11時間前）へ書き換えたところ、`Install-AdfsFarm`の警告は消えた（ただし後述の原因2はまだ残っていた）。単一DCのラボ/デモ環境限定の対処であり、複数DC環境では正規の10時間待ちが必要。
- **原因2: gMSAが既定の`CN=Managed Service Accounts`コンテナ以外（独自OU）に作成されていると、`Test-ADServiceAccount`は成功するのに`Install-AdfsFarm`だけが同じ`file specified`エラーで失敗する**
  - **何を期待していたか**: `scripts/adfs/Configure-AdfsDemoFarm.ps1`が独自OU（`OU=Kong Demo Service Accounts`）へ作成したgMSA（`adfssvc`）を、`Install-AdfsFarm`が問題なく利用できること。
  - **実際どうだったか**: 原因1を解消した後も、`Test-ADServiceAccount -Identity 'adfssvc'`は一貫して`True`を返すのに、`Install-AdfsFarm`だけが同一メッセージで失敗し続けた。gMSA自体の削除・再作成、DC再起動、`vm-adfs-demo`自体の再起動を試しても変化がなく、AD FS自身のイベントログ（`AD FS/Admin`、`Get-WinEvent -ListLog 'AD FS*'`）にも記録が0件で、`Install-AdfsFarm`の戻り値オブジェクト（`Message`/`Context`/`Status`のみ、詳細な例外情報なし）からもこれ以上の手がかりが得られなかった。
  - **原因確定の方法**: WebSearchで実エラーメッセージを検索し、複数の一次情報（[IT in realworld](https://fromreallife.wordpress.com/2019/03/05/unable-to-retrieve-group-managed-service-account-information-the-system-cannot-find-the-file-specified/)、[Ulysses Neves](https://ulyssesneves.com/2021/09/28/ad-fs-fixing-error-message-the-system-cannot-find-the-file-specified-when-adding-a-new-ad-fs-node-to-the-farm/)）で「AD FSはgMSAが既定の`CN=Managed Service Accounts`コンテナにあることを前提にしており、それ以外の場所だとこの`file specified`エラーになる」という既知の制約が報告されていることを確認した。汎用のADコマンドレット（`Get-ADServiceAccount`/`Test-ADServiceAccount`）はgMSAの格納場所に依存せず動作するため、この制約はAD FS固有の未文書化の前提だった。
  - **対処・解決確認**: `Get-ADServiceAccount -Identity 'adfssvc' | Move-ADObject -TargetPath "CN=Managed Service Accounts,<domain DN>"`でgMSAを既定のコンテナへ移動したところ、`Install-AdfsFarm`が成功し、AD FSファームが作成された（`Issuer: https://adfs.adfsdemo.picketfencelabs.local/adfs`、`Service state: Running`）。
- **恒久修正**: `scripts/adfs/Configure-AdfsDemoFarm.ps1`を修正し、(1) KDS root keyが存在しなければ`Add-KdsRootKey -EffectiveTime`で作成した直後に`msKds-CreateTime`/`msKds-UseStartTime`を両方過去日時へ調整、(2) gMSAを独自OUではなく既定の`CN=Managed Service Accounts`コンテナへ作成、するよう変更した。これにより次回このデモを最初から構築する際は、今回の手動対処（KDS属性の直接書き換え、gMSAの手動移動）を経由せず一度で成功する想定。
- **副次的な所見**: `Install-ADServiceAccount`実行後にVMを再起動しても、gMSA/KDS関連の問題は解消しなかった（キャッシュ由来ではなく、上記2つの構造的な原因だった）。`Install-AdfsFarm`のエラーメッセージ・戻り値は極めて簡素（`Message`/`Context`/`Status`のみ）で、AD FS自身のイベントログにも記録されないため、AD FS関連の未知のエラーメッセージはまず文字列そのものをWeb検索するのが有効（このリポジトリの一次情報だけでは特定できなかった）。

## 2026-09-16 ADFS自己署名証明書のtrust store登録・DNS疎通（Section 2手順11〜13）実装で判明した2件

- **何を期待していたか**: `docs/adfs-setup-runbook.md`Section 2手順11に従い、`vm-adfs-demo`上の`C:\ProgramData\KongDemo\adfs-demo-root.cer`をRDPのファイルコピー機能で管理端末へ取り出せること。
- **実際どうだったか**: RDPのクリップボードベースのファイル転送は接続元クライアント・設定に依存し再現性が低いため、手順6（スクリプト取得）や過去のパスワード復旧作業と同じ`az vm run-command invoke`（読み取り専用）方式に統一する方が確実と判断した。証明書は秘密鍵を含まない公開情報のため、この方式でコマンド出力へBase64文字列が乗ってもCLAUDE.md「機密情報の扱い」には抵触しない（[[az-run-command-secret-exposure]]の対象はあくまで秘密鍵・パスワード等）。
  - **対処・解決確認**: `[Convert]::ToBase64String([IO.File]::ReadAllBytes(...))`を`--scripts`のインラインコマンドとして実行し、`--query "value[0].message" -o tsv`の出力をローカルで`base64 -d`→`openssl x509 -inform DER -out ... -outform PEM`でPEM化する手順に確定した。実機（`vm-adfs-demo`、`4.216.110.53`）で実行し、`CN=adfs.adfsdemo.picketfencelabs.local`・有効期限`2026-11-16`・SHA-256 fingerprint`47:EA:E4:...:84:94`のPEMを取得できることを確認した。
- **何を期待していたか（2件目）**: Kongコンテナ内から`curl`でADFSのdiscovery endpointへ疎通確認できること。
- **実際どうだったか**: 使用イメージ`kong/kong-gateway-dev:pr-21082-ubuntu`には`curl`が含まれていない（`which curl`が失敗、`getent`は存在）。
- **対処・解決確認**: コンテナに同梱されている`openssl s_client`で代替する方式へ変更した。同イメージのコンテナへ`--add-host`でDNSを固定し、取得したPEMを`-CAfile`に指定して`vm-adfs-demo`（443番ポート）へ実際に接続し、`getent hosts`が指定Public IPを返すこと・`openssl s_client`の`Verify return code: 0 (ok)`を実測確認した上で、`docker-compose.yml`の`kong`サービスへ`extra_hosts`（`${ADFS_PUBLIC_IP}`）と`KONG_LUA_SSL_TRUSTED_CERTIFICATE=system,/etc/kong/adfs-demo-root.pem`を追加した。`docs/adfs-setup-runbook.md`Section 2手順11〜13を、これらの実測済みコマンドへ書き換えた。

## 2026-09-16 MDM管理端末でmacOSのSystemキーチェーンへの証明書信頼設定が反映されない

- **何を期待していたか**: Section 2手順12（当時案）の`sudo security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain certs/adfs-demo-root.pem`で、管理端末（macOS 26.6.2、arm64）のSystemキーチェーンへ証明書が信頼登録されること。
- **実際どうだったか**: 初回実行は`SecTrustSettingsSetTrustSettings: One or more parameters passed to a function were not valid.`で失敗（証明書自体はキーチェーンへインポートされたが信頼設定は未適用）。WebSearchで同種の既知事象を確認し`-d`を外し`-r trustRoot`へ変更して再実行したところ、`sudo`のパスワード誤入力で未実行の回、パスワードは通ったが`exit code: 0`で正常終了したように見える回のいずれでも、`security dump-trust-settings -d`（admin domain）・`security dump-trust-settings`（user domain、実ユーザー側／root側とも）のいずれにも証明書が一切現れなかった。Keychain Access.appを開いても、サイドバーに「System」キーチェーンの項目自体が存在しなかった（新しい「パスワード」アプリのカテゴリ表示（すべて/パスキー/コード/Wi-Fi/セキュリティ/削除済み）と、証明書管理ができる本来のKeychain Access.appを混同していたことも判明したが、後者を`open -a "Keychain Access"`で開いても状況は変わらなかった）。
- **原因の推定**: `profiles status -type enrollment`で、この端末がKandji経由のMDM管理下（DEP登録、User Approved MDM）にあることを確認した。macOS Big Sur以降、System/Adminドメインの信頼設定変更にはGUI経由の追加承認（SecurityAgent）が必要という既知の制約があり、MDM管理端末ではこれがポリシーでさらに制限され、CLIから`sudo`で実行しても`exit 0`のまま実質的にno-opになっている可能性が高いと判断した（会社所有のMDM管理端末で、原因の完全な特定にはIT/Kandji管理者側のポリシー確認が必要なため、これ以上の切り分けは行わない）。証明書自体に`X509v3 Basic Constraints`拡張が存在しない（ADFSの既定の自己署名証明書生成の仕様）ことも、症状を助長した可能性がある。
- **対処・解決確認**: OSのSystemキーチェーンに依存しない**Firefox自身の証明書ストア**（`about:preferences#privacy`→証明書を表示→認証局証明書→インポート）へ切り替える方針とした（利用者確認済み）。Firefoxは独自のNSS証明書ストアを持ちOSのトラスト設定ポリシーに影響されないため、MDM制限の影響を受けずに確実に機能する。`docs/adfs-setup-runbook.md`Section 2手順12・Section 5冒頭を、Firefoxでの証明書登録・Firefoxでのブラウザ試験に統一する形で更新した。Kongコンテナ側の信頼設定（前エントリ参照）はこの問題の影響を受けず、既に解決済みのまま。
  - **追記（下記2026-09-16エントリ参照）**: 上記「認証局証明書タブへインポート」という対処方法自体が誤りだったことが後日判明した。証明書に`Basic Constraints`（`CA:TRUE`）が無いため、Firefoxはこの証明書を認証局として受理しない。正しい対処は次のエントリに記載した「サーバー例外登録」。

## 2026-09-16 Firefoxの認証局証明書タブへのインポートが「認証局の証明書ではない」で拒否される

- **何を期待していたか**: 直前のエントリの対処に従い、`certs/adfs-demo-root.pem`をFirefoxの`about:preferences#privacy`→証明書を表示→**認証局証明書**タブ→インポート、で登録できること。
- **実際どうだったか**: Firefoxが`この証明書は認証局の証明書ではないため、認証局の一覧には追加できません`という警告を出し、インポートを拒否した（利用者が実機で確認・報告）。
- **原因の特定**: `openssl x509 -in certs/adfs-demo-root.pem -noout -text`で確認したところ、この証明書には`X509v3 Basic Constraints`拡張自体が存在しない（`CA:TRUE`の記載がない）。つまりこの証明書はADFSが生成した通常の自己署名**サーバー（リーフ）証明書**であり、Issuer=Subjectの自己署名ではあっても認証局証明書ではない。FirefoxのNSS証明書ストアは「認証局」タブへの登録時に`Basic Constraints`の`CA:TRUE`を要求するため、原理的にこの証明書を認証局として登録することはできない（macOSのSystemキーチェーンでの信頼設定不調（直前のエントリ）についても、MDM制限に加えてこの証明書の構造自体が一因だった可能性がある）。
- **対処・解決確認**: 認証局として登録する代わりに、Firefoxの**サーバー**タブ（`証明書を表示`→サーバー→追加→ホスト名`adfs.adfsdemo.picketfencelabs.local:443`を入力して証明書を取得→フィンガープリント確認→セキュリティ例外を承認）でホスト単位の例外として登録する方式へ変更した。この方式は自己署名のリーフ証明書に対する標準的なブラウザの扱いであり、`Basic Constraints`を要求しない。`docs/adfs-setup-runbook.md`Section 2手順12・Section 5冒頭の記載を修正した（未検証、利用者による実機確認待ち）。この例外登録はFirefoxが実際にホストへ接続して証明書を取得するため、手順13（DNS解決）を先に完了させる必要がある旨も明記した。Kongコンテナ側の信頼設定（`KONG_LUA_SSL_TRUSTED_CERTIFICATE`）はOpenSSLの`lua_ssl_trusted_certificate`が`Basic Constraints`の有無を問わず自己署名証明書を直接信頼できるため、この問題の影響を受けず既に解決済みのまま。
