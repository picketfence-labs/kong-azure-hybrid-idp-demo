# ADR-0004: ADFSファームのサービスIDとTLS名

- **日付**: 2026-09-15
- **状態**: 決定

## コンテキスト

TerraformでEntra Domain ServicesとADFS VMのドメイン参加まで完了した。実機ではADFSロール、ADFSサービス、Server Authentication証明書がまだ存在しない。VMのFQDN `vm-adfs-demo.adfsdemo.picketfencelabs.local` はmanaged domainのDNSで内部IPへ解決できる。Public IPにはDNS名がない。

ADFSファームを作るには、Federation Service名と一致するTLS証明書、ADFSサービス用ID、クライアント側の名前解決と証明書信頼を決める必要がある。現在のmanaged domainは`.local`であり、一般公開CAから証明書を取得できない。runbookは自己署名証明書をデモ限定で認めるが、採用前に利用者承認を求めている。

## 検討した選択肢

### Option A: VMのmanaged-domain FQDN、自己署名証明書、gMSA

Federation Service名に既存のVM FQDNを使う。Windows Server上でServer Authentication EKUと同じFQDNのSANを持つ自己署名証明書を作る。ADFSサービスはmanaged domain内の専用OUに作成したgMSAで動かす。ブラウザ端末とKongコンテナには明示的に証明書を信頼させ、名前解決を個別に設定する。

- **利点**: 既存の内部DNSレコードを再利用できる。gMSAのパスワードを作成、保存、ローテーションする必要がない。MicrosoftがADFSとEntra Domain Servicesの両方でサポートし、推奨するサービスID方式に沿う。
- **欠点**: 公式トラブルシューティングは、Federation Service名を既存サーバーのWindowsホスト名と同一にしてはならないと明記している。`HOST/<Federation Service名>` SPNがコンピューターアカウントとADFSサービス用gMSAで競合するため、この環境では採用できない。

### Option B: 専用の内部Federation Service名、自己署名証明書、gMSA

`adfs.adfsdemo.picketfencelabs.local`のような専用名をmanaged domain DNSへ追加し、その名前で証明書とファームを作る。サービスIDはOption Aと同じgMSAを使う。

- **利点**: Federation Service名をVM名から分離できる。将来ノードを入れ替える場合もissuerを維持できる。
- **欠点**: Entra Domain Servicesのmanaged DNSへレコードを追加し、権限と更新手順を管理する必要がある。外部端末とコンテナには、Option Aと同じ証明書信頼と名前解決設定が必要になる。

### Option C: 公開DNS名と公開CA証明書、gMSA

所有する公開DNS名をPublic IPへ割り当て、公開CAの証明書を取得する。managed domain内では同じ名前を内部IPへ解決させるsplit DNSを設定する。サービスIDはgMSAを使う。

- **利点**: ブラウザとKongへ自己署名証明書を配らず、標準のTLS検証を使える。Federation Service名をVM名から分離できる。
- **欠点**: 公開DNSゾーン、証明書発行と更新、split DNSの管理が追加で必要になる。短期間のローカルデモという現在要件を超える。

### サービスIDの代替

通常のドメインユーザーを専用サービスアカウントとして作る方法もある。ただし、パスワードの安全な受け渡しと更新が必要になる。既存の`adfs-domain-admin`をADFSサービスとして常用する案は、最小権限とrunbookの禁止事項に反するため採用候補にしない。

## 決定

利用者は2026-09-15にOption Aを承認した。しかし、実行コマンドへ落とす前のSPN確認でOption Aを採用できないことが判明したため、変更は実行しなかった。利用者の再確認を経てOption Bを採択する。

- Federation Service名は`adfs.adfsdemo.picketfencelabs.local`とする。
- managed domain DNSへ同名のAレコードを追加し、ADFS VMの内部IPを指す。
- Server Authentication証明書は同名のSANを持つデモ限定の自己署名証明書とする。
- ADFSサービスは専用OUに作成するgMSA `adfssvc`で動かす。
- ブラウザ端末とKongへ公開証明書を配り、TLS検証を維持する。

## 判断基準・根拠

現在のデモは1台のADFS VMを一度構築し、検証後に削除する。高可用性、長期運用、外部一般公開は要件ではない。Option Bはmanaged domain DNSのAレコードを1件追加するが、TLS検証を無効化せず、サービスパスワードも保持せず、ADFSが要求する専用SPNを安全にgMSAへ割り当てられる。Option Aを除外した後では、現在要件に対する変更範囲が最小になる。

将来、ADFSを長期公開する要件が生じた場合はOption Cへの移行を再検討し、issuer、証明書、クライアント設定を更新する。Option Bの専用名は、同じmanaged domain内でADFSノードを入れ替える場合も維持できる。Konnect移行や他IdP追加の要件には影響しない。

## 想定していたこと vs 実際どうだったか

当初はVMのFQDNを単一ノードのFederation Service名として再利用できると想定した。実際には、Microsoft公式資料がFederation Service名と既存サーバーのWindowsホスト名を同一にしてはならないと明記していた。Option Aの承認後、ADFSロールやDNSを変更する前に検出したため、Azure側のロールバックは発生していない。

Option Bの適用では、専用DNS Aレコード、gMSA、TLS証明書の作成まで成功した。AD FSファームの前提条件検査はDomain Admin権限不足で停止した。名前、TLS、サービスIDの決定とは別に、Entra Domain ServicesがAD FSのDKM準備に必要な権限を提供しない問題が判明したため、[ADR-0005](0005-adfs-directory-platform.md)の決定までこのADRの残りを適用しない。

## 影響・トレードオフ

Option Bを採用すると、managed domain DNSにデモ専用Aレコードが残る。デモ終了時にこのレコードを削除する。自己署名証明書はこのデモだけで信頼し、検証終了時にブラウザ端末とKongのtrust storeから削除する必要がある。

現在はmanaged domain DNSのAレコード、専用OU、gMSA、Personal storeとRoot storeの証明書、公開CERが作成済みである。AD FSファーム、Application Group、OIDC設定は未作成である。ADR-0005で別のディレクトリ基盤を選ぶ場合は、既存資源の削除範囲をplanとread-only inventoryで確認してから処理する。

## 関連する決定

- [ADR-0001](0001-adfs-vm-provisioning-automation.md): ADFSファーム構築をRDPの対話手順として管理する。
- [ADR-0002](0002-hybrid-idp-requirements.md): Group 2はADFS OIDCを使い、KongでTLSを検証する。
- [ADR-0005](0005-adfs-directory-platform.md): AD FSを構成できるディレクトリ基盤を再判断する。
- [Microsoft: AD FS SPNの確認](https://learn.microsoft.com/en-us/microsoft-365/troubleshoot/sign-in/federated-user-repeatedly-prompted-for-credentials)
- [Microsoft: Entra Domain ServicesのDNS管理](https://learn.microsoft.com/en-us/entra/identity/domain-services/manage-dns)
- [Microsoft: Entra Domain ServicesのgMSA](https://learn.microsoft.com/en-us/entra/identity/domain-services/create-gmsa)
