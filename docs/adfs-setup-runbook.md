# ADFS手動設定手順（runbook）

ADR-0001（[docs/decisions/0001-adfs-vm-provisioning-automation.md](./decisions/0001-adfs-vm-provisioning-automation.md)）で採択したハイブリッド方式のうち、Terraformの管理範囲外（VM作成・ドメイン参加まではTerraform、その先のADFSロールインストール〜OAuthサーバー設定）を人手で行う手順です。デモの一度きりの構築を想定しており、`terraform destroy`後に再構築する場合はこの手順も再実施します。

> [!warning] 未実施（terraformコード作成段階でのドラフト）
> 本手順はまだ実機で実行していません。実際のADFSサーバーで手順通りに進まない箇所があれば、都度[docs/troubleshooting-log.md](./troubleshooting-log.md)に記録し、本ファイルも実際の手順に合わせて更新してください。特に7節（Claim Issuance Policy）はdocs/design-brief.md Group2「未検証・実装時に確認が必要な技術的前提」に明記されている通り、実機検証が必要です。

## 前提
- `terraform apply`（`terraform/adfs_*.tf`・`terraform/insurance_*.tf`）が完了し、ADFS用VMがMicrosoft Entra Domain Servicesのドメインに参加済みであること
- 以下の値を`terraform output`から取得済みであること:
  ```bash
  cd terraform
  terraform output adfs_vm_public_ip
  terraform output -json adfs_domain_admin_credentials
  terraform output entra_domain_services_domain_name
  ```

## 1. RDP接続
`adfs_vm_public_ip`宛にRDP接続する（NSGで許可した発信元IPからのみ到達可能、`nsg_allowed_source_cidr`参照）。ログインは`adfs_domain_admin_credentials`のドメインアカウント（`adfs-domain-admin@<domain>`）を使う。

```
mstsc /v:<adfs_vm_public_ip>
```

## 2. ADFSロールのインストール
VM内のPowerShell（管理者）で実行:
```powershell
Install-WindowsFeature ADFS-Federation -IncludeManagementTools
```

## 3. SSL証明書の準備
社内CA・パブリックCAを持たないデモ環境のため、自己署名証明書で代替する:
```powershell
$cert = New-SelfSignedCertificate `
  -DnsName "adfs.<entra_domain_services_domain_name>" `
  -CertStoreLocation Cert:\LocalMachine\My
$cert.Thumbprint
```
出力された拇印（Thumbprint）を次の手順で使う。

## 4. ADFSファーム作成
```powershell
Install-AdfsFarm `
  -CertificateThumbprint "<手順3の拇印>" `
  -FederationServiceDisplayName "Kong ADFS Demo" `
  -FederationServiceName "adfs.<entra_domain_services_domain_name>" `
  -ServiceAccountCredential (Get-Credential) `
  -OverwriteConfiguration
```
`ServiceAccountCredential`にはドメイン管理者アカウント（`adfs-domain-admin@<domain>`）を使う。本番運用ではグループ管理サービスアカウント（gMSA）の利用が推奨されるが、デモ規模のため簡略化している。

## 5. 名前解決
社内DNSサーバーを別途構築していない前提の簡易デモ構成のため、Kong実行環境（ローカル、docker-compose.ymlのkongコンテナのホスト）側の`hosts`ファイルに、手順3/4で使ったFQDN（`adfs.<entra_domain_services_domain_name>`）とADFS VMのパブリックIP（`adfs_vm_public_ip`）の対応を追加する。

## 6. OAuthサーバー機能の有効化（Application Group、KongをRelying Partyとして登録）
ADFS管理コンソール（`AdfsManagement.msc`）→「Application Groups」→「Add Application Group」から進める（PowerShellの`Add-AdfsApplicationGroup`系コマンドレットでも同等の設定は可能だが、初回はGUIの方がパラメータの対応関係を把握しやすい）:

1. テンプレートは「Server application」を選択（認可コードフロー＋クライアントシークレットに対応するテンプレート）
2. Client Identifier（`client_id`）が自動生成される。控えておく → `DECK_ADFS_CLIENT_ID`
3. Redirect URIに、Kong側の各Routeの`redirect_uri`を**全て**登録する:
   - `kong/insurance-ui-route.yaml`: `http://localhost:8000/insurance/login/callback`
4. 「Generate a shared secret」でClient Secretを生成・控える → `DECK_ADFS_CLIENT_SECRET`
5. 完了後、「Server application」の「Issuance Transform Rules」を次節で編集する

## 7. Claim Issuance Policyの設定（要検証）
design-brief通り、Entra IDのテストユーザーに設定した`department`属性（`terraform/insurance_users.tf`参照）の値（グループID: `it`/`sales`/`new-business`/`policy-admin`/`claim`）を、そのままOIDCトークンのクレームとして発行する必要がある。

手順6で作成したApplication Groupの「Web API」（または「Server application」に紐づくRelying Party相当の設定）の「Issuance Transform Rules」に、以下のようなルールを追加する想定:
- ルールテンプレート「Send LDAP Attributes as Claims」
- Attribute Store: `Active Directory`
- LDAP Attribute: `Department`
- Outgoing Claim Type: `${{ env "DECK_ADFS_GROUP_CLAIM_NAME" }}`で指定する予定のクレーム名（`kong/insurance-*.yaml`・`kong/insurance-ui-route.yaml`の`upstream_headers`参照）

**要検証事項**（docs/design-brief.md Group2「未検証・実装時に確認が必要な技術的前提」より）:
- Entra IDの`department`属性が、Microsoft Entra Domain Services経由でオンプレミス相当のAD属性`department`として実際に同期されるか
- ADFSがこのAD属性をLDAP Attribute Storeとして正しく読み取れるか
- 発行されたクレームが、Kongの`openid-connect`プラグインの`upstream_headers`で期待通り拾えるか（ID tokenのクレームとして現れるか、userinfoエンドポイント経由になるか）

確認できた実際の挙動は、本ファイルおよび[docs/troubleshooting-log.md](./troubleshooting-log.md)に追記すること。

## 8. 疎通確認
- 作業端末（`nsg_allowed_source_cidr`で許可した発信元IP）から`https://adfs.<entra_domain_services_domain_name>/adfs/.well-known/openid-configuration`にアクセスでき、OIDC discoveryドキュメントが返ること
- Kong実行環境（ローカル）からも同様にアクセスできること（`docker exec kong ...`で疎通確認、docs/troubleshooting-log.mdの既存エントリと同じ手法が使える）
- 許可リスト外のIPからは到達できないこと（NSGの効果確認、design-brief 検証方法4点目）

## 9. Kong側への反映
疎通確認後、以下の環境変数をKong実行環境に設定し、`deck gateway sync`でGroup 2のRoute群を反映する（README.md「Group 2専用UI（insurance-ui）」節、`kong/insurance-ui-route.yaml`・`kong/insurance-<service>.yaml`参照）:

```bash
export DECK_ADFS_ISSUER="https://adfs.<entra_domain_services_domain_name>/adfs"
export DECK_ADFS_CLIENT_ID="<手順6のClient Identifier>"
export DECK_ADFS_CLIENT_SECRET="<手順6のClient Secret>"
export DECK_ADFS_GROUP_CLAIM_NAME="<手順7で設定したOutgoing Claim Type>"
export DECK_ADFS_SESSION_SECRET=$(openssl rand -base64 32)

deck gateway sync kong/insurance-ui-route.yaml kong/insurance-product.yaml kong/insurance-customer.yaml \
  kong/insurance-simulation.yaml kong/insurance-application.yaml kong/insurance-policy.yaml kong/insurance-claim.yaml
```
