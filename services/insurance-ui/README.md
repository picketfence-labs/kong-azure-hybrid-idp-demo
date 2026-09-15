# 共通保険デモUI（insurance-ui）

`insurance-ui`は、Entra ID経路とADFS経路の認証状態を同じ画面で確認するNext.jsアプリです。`/insurance/`のshellは未認証でも表示されます。OAuthクライアントとセッション検証は、[`kong/insurance-ui-route.yaml`](../../kong/insurance-ui-route.yaml)のOpenID Connect pluginが担当します。

## 現在のPoC範囲

- `/entra/auth/start`と`/adfs/auth/start`を別画面で開く
- `insurance_entra_session`と`insurance_adfs_session`を別Cookie Pathで管理する
- `/entra/auth/status`と`/adfs/auth/status`から、認証状態と検証済み属性の有無だけを取得する
- `/adfs/auth/probe`で、OIDCが検証したscalar属性を既存`legacy-authz-adapter`へ渡す
- `postMessage`を状態再確認の通知にだけ使い、認証成功の根拠にしない
- 対応する経路だけをログアウトする

API認可、PostgreSQLマスタ、実行履歴、図のイベント連動は後続gateで実装します。削除済みの`api/access-check`によるBearer token relayは使いません。

## ローカルで検証する

依存関係をインストールします。

```bash
bun install --frozen-lockfile
```

単体テスト、型検査、lintを実行します。

```bash
bun test
```

```bash
bun x tsc --noEmit
```

```bash
bun run lint
```

production buildを実行します。このリポジトリで使うNext.js 16.3.4のTurbopack buildが実行環境のlocalhost port制限を受ける場合は、webpack経路でコードと生成物を検証します。

```bash
./node_modules/.bin/next build --webpack
```

アプリ単体ではKongのセッション検証を再現できません。実IdP、Cookie分離、Header偽造の負例は、GatewayとIdPを準備してKong経由で確認します。probeでは`DECK_ADFS_POC_ATTRIBUTE_VALUE`に対象ユーザーの期待属性値を指定します。この値はPoC専用で、後続のPostgreSQL認可マスタを代替しません。
