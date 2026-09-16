# ADR-0005: AD FSを構成するディレクトリ基盤

- **日付**: 2026-09-16
- **状態**: 提案中

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

未決定。現在の要件をすべて維持できる、Microsoftの公式前提に沿った選択肢はない。利用者がAD FSとEntra Domain Servicesのどちらを優先するか確認してから決定する。

## 判断基準・根拠

第一の判断基準は、実際のAD FS OIDCとclaim発行を検証すること、Entra ID由来のユーザーと属性を使うこと、サポートされる権限モデルで再現できることの優先順位である。次に、既存Azure資源の再利用、追加コスト、再構築時間、デモ終了時の削除範囲を比較する。

AD FSを維持するならOption Aが最も再現可能である。Entra Domain Servicesとクラウド側ユーザーを維持するならOption Bが最も再現可能だが、AD FS要件を変更する。Option Cは公式前提を満たさないため推奨しない。

## 想定していたこと vs 実際どうだったか

当初は`AAD DC Administrators`がAD FSファームの初回構成に必要な権限を持つと想定した。実際には、このグループはVMのローカル管理、DNS、GPO、カスタムOUなどに限定された委任管理者であり、Domain Adminではなかった。ロール導入とADオブジェクトの一部作成は成功したが、AD FSのDKM準備とファーム作成の権限要件を満たさなかった。

## 影響・トレードオフ

決定までAD FSファーム、Application Group、KongのAD FS接続、ブラウザE2Eを進めない。Entra Domain Services、AD FS VM、Azure OpenAIは稼働を続けるため、継続コストが発生する。Option AまたはBは既存の設計ベースラインを変更するため、`docs/design-brief.md`、Terraform、runbook、図を同じ変更系列で更新する。

## 関連する決定

- [ADR-0001](0001-adfs-vm-provisioning-automation.md): AD FSファーム構築をRDPの対話手順として管理する。
- [ADR-0002](0002-hybrid-idp-requirements.md): Group 2でAD FS OIDCを使う要件。
- [ADR-0004](0004-adfs-farm-identity-and-tls.md): Federation Service名、TLS証明書、gMSA。
- [Microsoft: Microsoft Entra Domain Servicesの管理権限](https://learn.microsoft.com/en-us/entra/identity/domain-services/tutorial-create-instance-advanced#configure-an-administrative-group)
- [Microsoft: 非Domain AdminによるAD FSファーム作成](https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/deployment/install-ad-fs-delegated-admin)
