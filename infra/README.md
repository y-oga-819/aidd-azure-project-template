# infra

Angular（フロントエンド）と Python（バックエンド）を動かす Azure 基盤の IaC（Bicep）。

- なぜ Bicep か: [docs/adr-0001-iac-tool.md](docs/adr-0001-iac-tool.md)
- 何を守っているか・未検証事項: [docs/guardrails.md](docs/guardrails.md)

## 構成

```
infra/
├── shared/naming.bicep      命名規約（bootstrap と workload で共有）
├── bootstrap/               特権者が手動で実行: RG、CI 用 ID、ロール、Policy
├── workload/                CI が実行: ネットワーク、Container Apps、Key Vault、ACR、監視、Front Door
├── bicepconfig.json         linter 設定
├── .checkov.yaml            checkov 設定
└── mise.toml                ツールとタスク
```

## タスク

ルートから `mise run //infra:<task>`、または `infra/` で `mise run <task>`。

| タスク | 認証 | 内容 |
| --- | --- | --- |
| `format` / `format-check` | 不要 | Bicep の整形 / 整形済みの確認 |
| `lint` | 不要 | `bicep lint` と `bicep build-params`（警告もエラー扱い） |
| `security` | 不要 | checkov による静的検査 |
| `bootstrap` | 特権者 | RG・CI 用 ID・Policy の作成（サブスクリプション スコープ） |
| `whatif` | CI 用 ID | workload の差分確認 |
| `deploy` | CI 用 ID | workload をデプロイスタックとしてデプロイ |
| `approve-private-link` | CI 用 ID | Front Door からの Private Link 接続を承認 |

環境は `ENV`（既定 `dev`）で切り替える。例: `ENV=prd mise run //infra:whatif`

## 初回セットアップ

1. 特権者（サブスクリプションの Owner 相当）が `az login` して `mise run //infra:bootstrap` を実行する。
2. 出力された `deployerClientId` / `tenantId` / `subscriptionId` を、GitHub の Environment（`dev` など）の
   変数 `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` に登録する（シークレットではなく変数でよい）。
3. GitHub Environment に承認者を設定する。
4. Actions の `infra-deploy` を手動実行する（`apply: false` で what-if のみ）。
5. デプロイ後、`mise run //infra:approve-private-link` で Front Door の接続を承認する。
