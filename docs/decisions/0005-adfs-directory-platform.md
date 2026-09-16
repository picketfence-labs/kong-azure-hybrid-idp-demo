# ADR-0005: AD FSを構成するディレクトリ基盤

- **日付**: 2026-09-16
- **状態**: 決定

## コンテキスト

Group 2は、Microsoft Entra Domain Servicesへ参加したWindows Server 2022 VMにAD FSを構成する設計だった。Terraformは`adfs-domain-admin`を`AAD DC Administrators`へ追加し、VMのドメイン参加、DNS、カスタムOU、gMSAの作成まで完了した。

`Test-AdfsFarmInstallation`は、Domain Administrator資格情報、またはDomain Administratorが準備した`AdminConfiguration`を要求して停止した。実機では`adfs-domain-admin`が`AAD DC Administrators`と`Domain Users`に所属し、`Domain Admins`には所属していなかった。Microsoft Entra Domain ServicesはDomain AdminとEnterprise Adminの権限をテナント利用者へ提供しない。

非Domain AdminによるAD FS構成も、Domain Adminが`CN=ADFS,CN=Microsoft,CN=Program Data`配下へDKMコンテナを作り、ACLを準備することが公式手順の前提になる。実環境の`CN=Microsoft,CN=Program Data`にはDomain Admins、Enterprise Admins、SYSTEMの書込みACEだけがあり、`AAD DC Administrators`へのACEはなかった。現在の構成では、Microsoftが示すどちらのAD FSファーム作成手順も実行できない。

AD FSファームは未構成である。DNS、カスタムOU、gMSAは作成済みで、デモ用TLS証明書がLocalMachineのPersonal storeに1件作成されている。判断が終わるまで`Configure-AdfsDemoFarm.ps1 -Apply`を再実行しない。

## 検討した選択肢

### Option A: 自己管理AD DSへ切り替え、AD FSを維持する

Domain Admin権限を管理できるWindows Server AD DSを新設し、AD FS VMをそのドメインへ参加させる。テストユーザーと属性はAD DSを正本にする。Entra IDにも同じユーザーが必要な場合は、AD DSからEntra IDへの同期を別途設計する。

- **利点**: Microsoftの通常手順でAD FS、DKM、gMSA、SPN、claim ruleを構成できる。実AD FSとKong OIDC連携を維持できる。
- **欠点**: 利用者が不採用とした自己管理AD DSへ戻る。DC用VM、運用、Terraform、DNS、ユーザー作成を再設計し、現在のEntra Domain ServicesとAD FS VMを再構築する必要がある。Entra IDからAD DSへの逆同期にはならない。

### Option B: Entra Domain Servicesを維持し、AD FSを別のOIDC IdPへ置き換える

Domain Adminを必要としないOIDC IdPを使い、Entra IDまたはEntra Domain Servicesのユーザーを認証する。KongのOIDC経路とカスタム認可の構造は可能な範囲で維持する。

- **利点**: 作成済みのEntra Domain Servicesと同期済みユーザーを維持できる。Domain Admin制約を回避できる。
- **欠点**: AD FS固有のApplication Group、claim rule、OIDC endpointを検証するデモではなくなる。Group 2の確定要件を変更する。

### Option C: Entra Domain Services上で委任DKM構成を試験する

`AAD DC Administrators`が管理できるカスタムOUへDKMコンテナと必要なACLを手動作成し、`AdminConfiguration`を指定してAD FSファーム作成を試す。

- **利点**: 成功すれば現在のAzureリソースとID同期方向を維持できる。
- **欠点**: Microsoftの手順はDomain Adminによる事前準備を前提とし、標準のDKM配置先も現在の管理者には書き込めない。カスタムOU配置がEntra Domain Servicesとの組合せでサポートされる根拠は確認できていない。ディレクトリACLと暗号鍵コンテナを変更する実験になり、成功しても再現性とサポート性を保証できない。

### Option D: Group 2の実環境構築を停止する

現在の構成と検証結果を残し、AD FS経路を実装済みまたは動作確認済みとは扱わない。

- **利点**: 追加コスト、ディレクトリ変更、設計変更を避けられる。
- **欠点**: Group 2のOIDC、claim、カスタム認可をE2Eで検証できず、Projectゴールを完了できない。

## 決定

2026-09-16、利用者が**Option A（自己管理AD DSへ切替、AD FSを維持する）**を採択した。第一の理由は、本デモがAzure前提の環境で実施する必要があるという要件そのものであり、かつGroup 2で実AD FSのOIDC/claim発行を検証するという確定要件（[ADR-0002](0002-hybrid-idp-requirements.md)）を維持できる選択肢がOption Aしかなかったため。

採択前にVault側で次を公式ドキュメントで裏取りした。
- Microsoft Entra Domain Servicesは「Domain AdministratorまたはEnterprise Administrator権限をテナント利用者へ一切提供しない」仕様である（[Configure an administrative group](https://learn.microsoft.com/en-us/entra/identity/domain-services/tutorial-create-instance-advanced#configure-an-administrative-group)、原文: *"You don't have Domain Administrator or Enterprise Administrator permissions on a managed domain using Domain Services. The service reserves these permissions and doesn't make them available to users within the tenant."*）。実機で確認した`adfs-domain-admin`の所属（`AAD DC Administrators`／`Domain Users`のみ）と完全に一致する。
- 非Domain Admin向けの「delegated administration」手順（[Creating an AD FS farm without Domain Administrator privileges](https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/deployment/install-ad-fs-delegated-admin)）も、DKMコンテナの事前準備自体をDomain Administratorが実行する前提になっている。Entra DSはそのDomain Adminを誰にも渡さないため、この抜け道も構造的に塞がれている。

このため**Option C（Entra DS上での委任DKM試験）は採用しない**（試す価値がないほど原理的に不可能と判断）。Option B（別OIDC IdPへ置換）とOption D（構築停止）は、Group 2の確定要件（実AD FSの検証）を変更または放棄するため不採用。

## 判断基準・根拠

第一の判断基準は、実際のAD FS OIDCとclaim発行を検証すること、Entra ID由来のユーザーと属性を使うこと、サポートされる権限モデルで再現できることの優先順位である。次に、既存Azure資源の再利用、追加コスト、再構築時間、デモ終了時の削除範囲を比較する。

AD FSを維持するならOption Aが最も再現可能である。Entra Domain Servicesとクラウド側ユーザーを維持するならOption Bが最も再現可能だが、AD FS要件を変更する。Option Cは公式前提を満たさないため推奨しない。

## 実行時の留意点（Option Aへの移行で新たに生じる作業・リスク）

- Entra Domain Services関連リソース（`terraform/adfs_domain_services.tf`の`azurerm_active_directory_domain_service.this`ほか一式）は撤去し、代わりに自己管理AD DSフォレスト用のVM・Terraformコードを新規に用意する（実装は委譲先セッションの責務）。
- テストユーザー（`terraform/insurance_users.tf`）は、Entra ID経由のcloud-onlyアカウント作成→パスワードハッシュ同期待ちという手順が不要になる。`New-ADUser`等で作成時に即時使えるパスワードを設定できるため、Entra DSの15分待機ステップ（`time_sleep.domain_services_identity_sync`）に相当する順序依存は解消される。
- VNetのDNS設定は、Entra DSが払い出すDC IPではなく、新設するAD DS VMのプライベートIPを向くよう変更する。
- フォレスト/ドメイン名は既存のEntra DS用ドメイン名`adfsdemo.picketfencelabs.local`を再利用するか、新規名にするかを実装時に決める（Entra DSのような命名制約はなく自由度は高い）。
- 実機確認（`japaneast`、2026-09-16時点）で、Standard DSv2/DSv3/DSv4/DSv5ファミリのvCPU上限がいずれも4だった。AD DS VM追加により合計vCPUが不足する場合はAzure Support経由でquota引き上げが必要になる可能性がある（申請から反映まで数時間〜1営業日を見込む）。
- [ADR-0004](0004-adfs-farm-identity-and-tls.md)（Federation Service名・TLS・gMSA方式）はディレクトリ基盤に依存しない部分がほとんどのため、自己管理AD DSへそのまま適用可能とみなす。[ADR-0001](0001-adfs-vm-provisioning-automation.md)（Terraform/手動手順の責務分担）も、自己管理AD DSフォレスト作成というTerraform管理対象が増える点を除き、方針（インフラ・ドメイン参加はTerraform、ADFSファーム構築は対話的手順）は維持する。
- 公式に「Azure AD DS上でADFSファーム構築に成功した」と読める記事を1件発見したが、全文確認はできていない（有料壁）。検索結果の要約では同じdelegated adminパターン（DKMContainerDn等）を使っており、内容が一次情報の制約と矛盾するとは判断していない。「Azure AD DS」という表記が自己構築のAD DS（Option A相当）を指している可能性もある。

## 想定していたこと vs 実際どうだったか

当初は`AAD DC Administrators`がAD FSファームの初回構成に必要な権限を持つと想定した。実際には、このグループはVMのローカル管理、DNS、GPO、カスタムOUなどに限定された委任管理者であり、Domain Adminではなかった。ロール導入とADオブジェクトの一部作成は成功したが、AD FSのDKM準備とファーム作成の権限要件を満たさなかった。

## 影響・トレードオフ

2026-09-16の`terraform destroy`完了により、Entra Domain Services・AD FS VM・Azure OpenAIの稼働はすべて停止済みで、決定待ちによる追加コストの継続はない。Option A採択に伴い、`docs/design-brief.md`・`docs/development-handoff.md`・`docs/adfs-setup-runbook.md`は本PRで更新する。Terraform（AD DSフォレスト用の新規リソース、ADFS VMのドメイン参加先変更、`insurance_users.tf`のユーザー作成方式変更）と`scripts/adfs/`配下のPowerShellスクリプトの書き換えは実装フェーズ（委譲先セッション）で行う。

## 関連する決定

- [ADR-0001](0001-adfs-vm-provisioning-automation.md): AD FSファーム構築をRDPの対話手順として管理する。
- [ADR-0002](0002-hybrid-idp-requirements.md): Group 2でAD FS OIDCを使う要件。
- [ADR-0004](0004-adfs-farm-identity-and-tls.md): Federation Service名、TLS証明書、gMSA。
- [Microsoft: Microsoft Entra Domain Servicesの管理権限](https://learn.microsoft.com/en-us/entra/identity/domain-services/tutorial-create-instance-advanced#configure-an-administrative-group)
- [Microsoft: 非Domain AdminによるAD FSファーム作成](https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/deployment/install-ad-fs-delegated-admin)
