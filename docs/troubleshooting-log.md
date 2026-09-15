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
