# Entra DS・ADFSの再構築と接続確認

対象は構築担当者。最新[設計](design-brief.md)と[ADR-0001](decisions/0001-adfs-vm-provisioning-automation.md)に従い、基盤/ドメイン参加をTerraform、ADFS設定を手動で行います。**本書は改訂後の検証計画であり、完走済み手順ではありません。**

## 0. 再開前のgate

- [ ] 設計PRをレビューし、対象commitを固定する。自己管理AD DSへ変更しない。
- [ ] Azureの対象テナント・subscription、権限、予算、削除担当/期限を確認する。Entra系デモのテナントとADFS同期元を同一と決めつけない。
- [ ] 以前のapply中断・削除記録を確認し、現在のAzure残存とTerraform stateを照合する。過去の削除記録を現在の実測としない。
- [ ] Gatewayライセンス、image digest、`kong-ee`参照、必要ツールを用意する。公開履歴に載った資格情報が有効なら管理者に変更を依頼する。
- [ ] terraform validate/planを確認し、**applyは別途承認を得て**実施する。provider登録やIdP設定変更も読取り作業ではない。

## 1. Entra DSとVMの準備

1. Terraformの対象resourceと変更内容をレビューする。
2. 承認後にEntra DS、ネットワーク、ADFS VM、ドメイン参加を構築する。
3. Entra DSの健全性、DNS、時刻、ユーザー同期、VMドメイン参加を確認する。伝播待ちや再起動を成功扱いで飛ばさない。
4. 必要なVM IP/FQDN、ドメイン名は既存Terraform outputsから取得する。資格情報は安全な保管先へ渡し、端末ログやPRへ出力しない。

VM作成・ドメイン参加までと、ADFSサービス設定の完了を別に記録します。Entra DSの構築時間・継続費用を見込んで作業枠を確保します。

## 2. ADFSサービス、証明書、名前解決

1. 許可した管理端末からVMへ接続し、対象Windows Server版の手順でADFSロールを設定する。
2. ADFS用FQDNに一致する証明書を用意する。ブラウザとKongコンテナの両方が信頼できるchainを設定する。検証回避を既定にしない。
3. デモで自己署名証明書を使う場合は限定例外として承認し、両クライアントのtrust storeを準備する。`tls_verify=false`やブラウザ警告の無視だけで合格にしない。
4. ADFSファーム/サービスアカウントは対象環境に合わせて設定する。既存ファームの上書きやdomain adminの常用を自動前提にしない。
5. FQDNがブラウザ端末と**Kongコンテナ内部**から解決することを確認する。ホストOSのhosts編集だけではコンテナDNSの成功証拠にならない。

正確なPowerShell引数、サービスアカウント方式、証明書配備は実機条件で確認して記録します。旧ドラフトの`OverwriteConfiguration`を無条件に再実行しないでください。

## 3. Application GroupとAPI資源

Microsoftの[Server application accessing a Web API](https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/development/msal/adfs-msal-web-app-web-api)構成を参考に、**Server application（Kongのclient）とWeb API（resource/audience）を分けて**登録します。SAML用Relying Party設定と混同しないでください。

1. Application Groupを作成し、Server applicationのclient ID/資格情報とWeb API identifierを記録する。secretは安全な保管先へ保存する。
2. `DEMO_ORIGIN/adfs/auth/callback`を完全一致で登録する。旧`/insurance/login/callback`はP1で置き換えたため登録しない。
3. 必要なscope/resource/audienceと、対象デモユーザーだけに許可するADFS側policyを確認する。公式サンプルの全員許可を本デモへ無条件コピーしない。
4. Web API側のclaim規則と、どのtokenへ必要属性が出るかを確認する。Server applicationに全claim規則があると仮定しない。
5. Entra系の新しい保険API用設定は別のclient/resource/必要権限として整理する。既存Chat/OBOのclient/audienceを黙って変更しない。

## 4. 属性同期・claim・tokenの検証

設計案では`department`に`D-IT`等の架空値を置きます。ADFSが業務グループへ正規化するのではなく、PostgreSQLで対応を解決します。

- [ ] 元ユーザーの属性がEntra DSに同期されることを確認する。
- [ ] ADFSが該当属性を読み、必要なclaimを発行できることを確認する。
- [ ] issuer、audience、署名、期限、scope、claim名・型・値の所在をID token/access tokenで分けて確認する。raw tokenは保存せず、値をマスクした結果だけ記録する。
- [ ] API側が必要とするaccess tokenを取得・検証できる。ID tokenをBearerとして流用しない。
- [ ] OIDC後のカスタムPluginが本当に検証済み属性を読むことを、G2の偽造Header負例で証明する。

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
