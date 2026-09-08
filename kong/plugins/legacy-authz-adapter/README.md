# legacy-authz-adapter

Group 2（ADFSグループ）の認可ロジックを再現するカスタムプラグイン（[docs/design-brief.md](../../../docs/design-brief.md) Group 2「3. アーキテクチャ」参照）。

`openid-connect`がADFSのIDトークンを検証した後、`access`フェーズで実行される想定（`PRIORITY = 100`で`openid-connect`より後に実行）:

1. `config.group_claim_header`で指定したヘッダー（`openid-connect`の`upstream_headers`がIDトークンの属性値クレームをコピーしたもの）を読み取る
2. 値が`config.known_groups`（既定5グループ: `it`/`sales`/`new-business`/`policy-admin`/`claim`）のいずれかであることを確認する（レガシー認可サービス相当の「グループ確定」処理を簡略化して再現。design-briefの通り、属性値の正規化自体はADFS側で完了している前提）
3. 確定したグループIDが`config.allowed_groups`（Service単位で個別設定）に含まれるか判定し、含まれなければ403
4. 許可されれば`config.group_header_name`（既定`X-Group-Id`）にグループIDを設定し、ダウンストリームサービスへ転送する

## config

| フィールド | 型 | 既定値 | 説明 |
|---|---|---|---|
| `group_claim_header` | string | `X-ADFS-Group-Claim` | `openid-connect`がクレーム値をコピーしているヘッダー名 |
| `group_header_name` | string | `X-Group-Id` | 確定したグループIDをダウンストリームへ転送するヘッダー名 |
| `known_groups` | string[] | 5グループ | 有効なグループIDの一覧（レガシー認可サービスの既知グループ相当） |
| `allowed_groups` | string[] | （必須、既定なし） | このServiceへのアクセスを許可するグループID。design-briefのグループ⇔APIアクセスマトリクスに従いService毎に設定する |

## テスト

`authz.lua`（グループ確定・アクセス可否判定の純粋ロジック）は、Kongランタイムに依存しないため`luajit`のみで単体テストできる:

```bash
luajit kong/plugins/legacy-authz-adapter/spec/authz_spec.lua
```

`handler.lua`（Kongプラグインとしての結線: ヘッダー読み取り・`kong.response.exit`・`kong.service.request.set_header`）は、Kong本体を介した結合テストが必要なため、`kong/insurance-*.yaml`でのRoute/Service配線後に`deck gateway sync`＋実リクエストで確認する（[TESTING.md](../../../TESTING.md) Group 2節参照）。
