# 自己管理AD DS・ADFSの構築と接続確認

対象は構築担当者。最新[設計](design-brief.md)と[ADR-0001](decisions/0001-adfs-vm-provisioning-automation.md)に従い、基盤/ドメイン参加をTerraform、ADFS設定を手動で行います。2026-09-15にEntra DS前提のSection 1構築・検証を完了しましたが、2026-09-16に[ADR-0005](decisions/0005-adfs-directory-platform.md)でOption A（自己管理AD DSへ切替）が決定し、旧環境は`terraform destroy`済みです。Section 1は自己管理AD DSフォレスト構築手順へ書き換え、2026-09-16に`terraform apply`実行・実機確認まで完了済みです（[troubleshooting-log](troubleshooting-log.md)「自己管理AD DSフォレストの`terraform apply`実行」参照）。

## 0. 再開前のgate

- [x] [ADR-0005](decisions/0005-adfs-directory-platform.md)を決定した → Option A（自己管理AD DS）採択（2026-09-16）。
- [x] Section 1を自己管理AD DSフォレスト構築手順へ書き換え、`terraform apply`・実機確認まで完了した（`terraform/adfs_domain_controller.tf`ほか）。
- [ ] Azureの対象テナント・subscription、権限、予算、削除担当/期限を確認する。Entra系デモのテナントとADFS同期元を同一と決めつけない。
- [ ] 以前のapply中断・削除記録を確認し、現在のAzure残存とTerraform stateを照合する。過去の削除記録を現在の実測としない。
- [ ] Gatewayライセンス、image digest、`kong-ee`参照、必要ツールを用意する。公開履歴に載った資格情報が有効なら管理者に変更を依頼する。
- [ ] terraform validate/planを確認し、**applyは別途承認を得て**実施する。provider登録やIdP設定変更も読取り作業ではない。

## 1. 自己管理AD DSとVMの準備

Terraform（`terraform/adfs_domain_controller.tf`）が次の順序で自動構築する:

1. DC用VM（`vm-dc-demo`）をネットワーク・NSGとともに作成する。
2. CustomScriptExtension（`bootstrap-dc`）が`AD-Domain-Services`ロール導入→`Install-ADDSForest`によるフォレスト昇格を行う。完了時にVMが自動再起動し、起動時スケジュールタスク経由でドメインオブジェクト作成へ続く（`scripts/adfs/Install-AdDsForest.ps1`、`Win32_ComputerSystem.DomainRole`チェックで再apply時も冪等）。AzureのWindows VMはCustomScriptExtensionのhandlerを1台につき1つしか持てないため、フォレスト昇格とドメインオブジェクト作成は1つの拡張機能にまとめてある。スクリプト本体は非公開のBlob Storage（SAS URL）経由でVMへダウンロードされる（`commandToExecute`への直接埋め込みは長さ上限で失敗するため）。
3. 再起動・AD DSサービス起動・スケジュールタスク実行を待つ`time_sleep`（5分）を挟む。
4. スケジュールタスク（またはDC作成済みの場合はbootstrap-dc拡張機能が直接）がドメイン管理者アカウント（`adfs-domain-admin`、`Domain Admins`へ追加）とGroup 2の5テストユーザー（`department`属性付き）をDC上で作成する（`scripts/adfs/New-AdDsDomainObjects.ps1`。Entra ID cloud-onlyアカウント経由のパスワードハッシュ同期待ちは不要）。
5. VNetのDNSをDC VMのプライベートIPへ切り替える。
6. ADFS VMを、新設AD DSフォレストへドメイン参加させる（`JsonADDomainExtension`、既存の`adfs-domain-admin`アカウントを使用）。

2026-09-16、承認を得て`terraform apply -var-file=adfs.tfvars`を実行し、`az vm run-command invoke`（読み取り専用）で次を実機確認済み:

- `vm-dc-demo`: `DomainRole=5`（フォレスト昇格済み）、`Domain=adfsdemo.picketfencelabs.local`、`adfs-domain-admin`と5テストユーザー（`demo-it`/`demo-sales`/`demo-new-business`/`demo-policy-admin`/`demo-claim`、いずれも`department`属性設定済み）が存在、`adfs-domain-admin`が`Domain Admins`メンバー。
- `vm-adfs-demo`: `PartOfDomain=True`、`Domain=adfsdemo.picketfencelabs.local`、FQDN`vm-adfs-demo.adfsdemo.picketfencelabs.local`。

資格情報は`terraform output ad_ds_domain_name`・`terraform output adfs_domain_admin_credentials`・`terraform output insurance_test_user_credentials`・`terraform output dc_vm_public_ip`で取得できる。安全な保管先へ渡し、端末ログやPRへ出力しない。

実機applyで判明した3件の実装不備（CustomScriptExtensionのhandler制限、`commandToExecute`の長さ上限、SASの`timestamp()`による毎plan差分）と対処は[troubleshooting-log](troubleshooting-log.md)に記録済み。VM作成・ドメイン参加までと、ADFSサービス設定の完了を別に記録する。フォレスト構築時間・継続費用を見込んで作業枠を確保する。

## 2. ADFSサービス、証明書、名前解決

[ADR-0004](decisions/0004-adfs-farm-identity-and-tls.md)で、専用FQDN、自己署名証明書、gMSAを採択しました。自己署名証明書はこのデモだけで信頼します。`tls_verify=false`やブラウザ警告の無視は使いません。

1. `terraform output`からADFS VMのPublic IP、ドメイン管理者UPN、パスワードを安全に取得する。パスワードを画面、シェル履歴、文書へ貼らない。
2. 許可した管理端末からVMへRDP接続する。Windowsのサインイン画面では`adfs-domain-admin`のUPNを使う。`vm-adfs-demo\adfsvmadmin`はローカル管理者なので使わない。
3. スタートメニューで`Windows PowerShell`を検索し、右クリックして「管理者として実行」を選ぶ。`PowerShell 7`は使わない。非管理者のシェルを開いている場合は、次のコマンドでもWindows PowerShell 5.1を管理者として起動できる。

   ```powershell
   Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs
   ```

4. 新しく開いたウィンドウで、Windows PowerShell 5.1であることを確認する。パイプ・カンマを含む1行のコマンドはRDPのクリップボード貼り付けで改行が分割され`>>`の継続入力プロンプトへ入ったまま結果が空になることがあるため、1コマンドずつ分けて貼り付ける。

   ```powershell
   $PSVersionTable.PSEdition
   ```

   ```powershell
   $PSVersionTable.PSVersion
   ```

   1つ目が`Desktop`、2つ目が`5.1`から始まることを確認する。`>>`が表示され結果が出ない場合は、空行のままEnterを2回押すかCtrl+Cで通常のプロンプトへ戻してから再実行する。

5. 現在のWindowsユーザーがドメイン管理者のUPNであることを確認する。

   ```powershell
   whoami.exe /upn
   ```

   UPNではなく「current logged-on user is not a domain user」と表示された場合は、PowerShellだけでなくWindowsからサインアウトし、手順2からやり直す。

6. レビュー済みcommitの`scripts/adfs/`をVMの`C:\KongDemo\adfs`へコピーする。このフォルダーはTerraformでは作成されない。RDPのファイルコピーを使わない場合は、レビューした40文字のcommit SHAを指定してGitHubから3ファイルを取得する。

   ```powershell
   $Commit = "<reviewed-40-character-commit-sha>"
   ```

   ```powershell
   New-Item -ItemType Directory -Path C:\KongDemo\adfs -Force
   ```

   ```powershell
   $BaseUri = "https://raw.githubusercontent.com/picketfence-labs/kong-azure-hybrid-idp-demo/$Commit/scripts/adfs"
   ```

   ```powershell
   Invoke-WebRequest -Uri "$BaseUri/Configure-AdfsDemoFarm.ps1" -OutFile C:\KongDemo\adfs\Configure-AdfsDemoFarm.ps1
   ```

   ```powershell
   Invoke-WebRequest -Uri "$BaseUri/Register-KongDemoApplication.ps1" -OutFile C:\KongDemo\adfs\Register-KongDemoApplication.ps1
   ```

   ```powershell
   Invoke-WebRequest -Uri "$BaseUri/Test-AdfsDemo.ps1" -OutFile C:\KongDemo\adfs\Test-AdfsDemo.ps1
   ```

   commit SHAはブランチ名や`main`へ置き換えない。取得元とレビュー対象を同じrevisionに固定する。

7. 作業ディレクトリへ移動する。

   ```powershell
   Set-Location C:\KongDemo\adfs
   ```

8. 変更前のpreflightを実行する。

   ```powershell
   .\Configure-AdfsDemoFarm.ps1
   ```

9. 出力が次の値と一致することを確認する。

   | 項目 | 期待値 |
   |---|---|
   | Domain | `adfsdemo.picketfencelabs.local` |
   | Current domain user | `adfs-domain-admin`のUPN |
   | Computer FQDN | `vm-adfs-demo.adfsdemo.picketfencelabs.local` |
   | Federation Service name | `adfs.adfsdemo.picketfencelabs.local` |
   | Server IPv4 | Terraform管理下のADFS VM内部IP |
   | AD FS role | 初回は`Available`。中断後の再実行では`Installed` |
   | AD FS farm state | `RoleInstalledOnly` |
   | DNS A record | 初回は`Create`。作成後の再実行では`Reuse` |
   | KDS root key | 初回は`Create`。作成後の再実行では`Reuse`（単一DC構成のため作成時に有効時刻を10時間過去へ調整する。[troubleshooting-log](troubleshooting-log.md)参照） |
   | gMSA | 初回は`Create`。作成後の再実行では`Reuse`（既定の`CN=Managed Service Accounts`コンテナへ作成される） |
   | TLS certificate | 初回は`Create`。有効なデモ用証明書があれば`Reuse` |

   最後に`Deep preflight only. No DNS, directory, certificate, or AD FS changes were made.`と表示されることを確認する。この表示より前に停止した場合は`-Apply`を実行しない。

10. 値を確認してから、ADFSロール、DNS Aレコード、gMSA、証明書、ファームを作成する。

   ```powershell
   .\Configure-AdfsDemoFarm.ps1 -Apply
   ```

   Windows機能が未導入の場合、この実行は機能の導入だけで終了する。`Required Windows features were installed. Rerun without -Apply for the deep preflight.`と表示されたら、手順8へ戻る。deep preflightを確認せずに次の変更処理へ進まない。

   AD FSロールのインストール直後は、ファーム未構成でも`adfssrv`サービスが`Stopped`、`Manual`で存在する。レジストリ値`InitialConfigurationCompleted`、KDS root key、gMSAが存在しないことも初回実行では正常である。サービス、レジストリ、ADオブジェクトを手動で変更しない。処理が中断した場合は、同じドメイン管理者セッションから修正版スクリプトを再実行する。`The AD FS role is installed, but no configured farm was detected. Continuing.`と表示され、残りの構成へ進む。

   スクリプトは`OverwriteConfiguration`を使いません。構成済みファーム、判定できないAD FSサービス状態、別IPの同名DNSレコード、別所有者のSPNを検出した場合は停止します。AD FSの前提条件検査とインストール結果は、全項目が`Success`の場合だけ次へ進みます。インストール後はdiscovery endpointを最大60秒待ち、issuerまで検証します。

11. VM上の`C:\ProgramData\KongDemo\adfs-demo-root.cer`を管理端末へコピーする。秘密鍵を含むPFXはエクスポートしない。
12. 管理端末とKongコンテナのtrust storeへ公開証明書を登録する。デモ終了時に削除できるよう、thumbprintと登録先だけを記録する。
13. `adfs.adfsdemo.picketfencelabs.local`を、管理端末とKongコンテナの両方からADFS VMのPublic IPへ解決させる。コンテナ側は後続のCompose設定で検証し、ホストOSの設定だけで完了扱いにしない。

## 3. Application GroupとAPI資源

Microsoftの[Server application accessing a Web API](https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/development/msal/adfs-msal-web-app-web-api)構成を参考に、**Server application（Kongのclient）とWeb API（resource/audience）を分けて**登録します。SAML用Relying Party設定と混同しないでください。

1. 変更前のpreflightを実行する。

   ```powershell
   .\Register-KongDemoApplication.ps1
   ```

2. client ID、Web API identifier、callback、claim名、scopeを確認する。callbackは`http://localhost:8000/adfs/auth/callback`だけを登録する。旧`/insurance/login/callback`は登録しない。Kong側は`allatclaims`の要件に合わせて`response_mode=form_post`を使い、認可中Cookieを`SameSite=None; Secure`にする。
3. Application Group、Server application、Web API、permissionを作成する。

   ```powershell
   .\Register-KongDemoApplication.ps1 -Apply
   ```

4. スクリプトがクリップボードへ置いたclient secretを、管理端末の非追跡`.env`または承認済みsecret storeへ直ちに保存する。チャット、文書、画像、PR、コマンド引数へ貼らない。VM上のバックアップは現在のWindowsユーザーだけが復号できるDPAPI形式で保存される。
5. 次の非秘密値をKong環境へ設定する。

   ```dotenv
   DECK_ADFS_ISSUER=https://adfs.adfsdemo.picketfencelabs.local/adfs
   DECK_ADFS_CLIENT_ID=5923191c-da9f-4c23-ac6f-dd7be8b5b93a
   DECK_ADFS_RESOURCE=urn:kong:insurance-api
   DECK_ADFS_GROUP_CLAIM_NAME=https://picketfencelabs.local/claims/department
   ```

   `DECK_ADFS_CLIENT_SECRET`には保存したsecretを設定する。スクリプトは全員許可を使わず、P1で現在設定されている5つの小文字`department`値だけを許可する。後続のDB認可実装で`D-IT`等へ移行する際は、ADFSの許可値も同じPRで更新する。
6. Entra系の新しい保険API用設定は別のclient/resource/必要権限として扱う。既存Chat/OBOのclient/audienceを変更しない。

## 4. 属性同期・claim・tokenの検証

設計案では`department`に`D-IT`等の架空値を置きます。ADFSが業務グループへ正規化するのではなく、PostgreSQLで対応を解決します。

- [ ] AD DS上のテストユーザーに`department`属性が作成時点で設定済みであることを確認する（自己管理AD DSのため、Entra IDからの同期待ちは発生しない）。
- [ ] ADFSが該当属性を読み、必要なclaimを発行できることを確認する。
- [ ] issuer、audience、署名、期限、scope、claim名・型・値の所在をID token/access tokenで分けて確認する。raw tokenは保存せず、値をマスクした結果だけ記録する。
- [ ] API側が必要とするaccess tokenを取得・検証できる。ID tokenをBearerとして流用しない。
- [ ] OIDC後のカスタムPluginが本当に検証済み属性を読むことを、G2の偽造Header負例で証明する。

ADFSファームとApplication Groupの静的状態はVM上で確認します。

```powershell
.\Test-AdfsDemo.ps1
```

このスクリプトはrole、service、DNS、TLS binding、gMSA、SPN、discovery、Application Group、permission、5ユーザーの`department`を確認します。raw tokenは取得も保存もしません。ID tokenとaccess tokenのclaim検証は、Kongを起動した後のブラウザ試験で別途行います。

同期やclaim発行に失敗したらgateをblockedにし、別属性へ変える案をADRでレビューします。ADFSで`D-IT → it`へ変換してDB照会の要件を消さないでください。

## 5. Kongとブラウザの疎通

- [ ] NSG許可元からブラウザとKongがdiscovery/JWKS/token endpointへ到達し、TLSを検証できる。
- [ ] NSG許可外からADFSへ到達しない。RDPなど管理経路と公開OIDCを別に点検する。
- [ ] `/adfs/auth/start`の別画面redirect→callback→セッション確立をG1で確認する。
- [ ] CookieのPath/name/secretをEntra系・既存Chatから分離し、両IdPを同時利用できる。
- [ ] IdPエラー画面、callback未帰還、期限切れ、logoutを試験する。

## 6. 認可DBとRouteの反映

1. G3を通過したライブラリ/SQL方式で認可DBを準備する。`kong-db`の内部テーブルへ業務マスタを入れない。
2. レビューfixtureに対応する5 mapping行・13 GET許可行・revisionをtransactionでseedする。
3. 完成した構成全体をdecKでvalidate/diffする。既存Chat/OBO/LLMを含むinventoryを対象とし、Group 2の一部ファイルだけを全状態としてsyncしない。
4. 正式callback、issuer、audience、secret、claim名を環境の実値に合わせる。`.env`等の非追跡設定を使う。
5. **承認後**に反映し、7入口・6 Service・customer共有・旧Path廃止を確認する。設計未対応の現行YAMLをこの手順でそのまま配備しない。
6. [TESTING.md](../TESTING.md)のG1〜G4、35セル、対象外経路、Group 1回帰を実施する。

## 7. 終了・削除・証拠

- [ ] 検証結果、失敗、未確認、対象commit/image digest、費用の確認先を残す。成功したテストだけを抜き出さない。
- [ ] デモ終了後、利用者承認を得て今回作成した資源だけを削除する。
- [ ] Azure残存、Terraformのmanaged resources、公開IP/DNS/証明書、IdP登録、認可DB volumeの扱いを確認する。既存Group 1資源を誤削除しない。
- [ ] stateにdata sourceだけが残る状態を「stateが空」と表現しない。実測と未確認を分ける。

想定外は[troubleshooting-log](troubleshooting-log.md)、設計変更は[ADR](decisions/)へその場で記録します。
