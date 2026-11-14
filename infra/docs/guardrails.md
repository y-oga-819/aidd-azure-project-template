# セキュア基盤とガードレール

この文書は「何を守っているか」「なぜそうしたか」「まだ検証できていないことは何か」をまとめる。
Bicep のコードを変更する人（AI を含む）は、ここに書かれた前提を崩さないこと。

## 1. 守りたいこと（受け入れ条件）

AI が書いたアプリコードや IaC がデプロイされても、次が常に成り立つ。

| # | 受け入れ条件 | 主に効いている仕組み |
| --- | --- | --- |
| G1 | インターネットから届くのは Front Door (WAF) 経由だけ。アプリ（web / api）に直接は届かない | アプリの `publicNetworkAccess: Disabled` + Front Door の Private Link、Policy `app-no-public-network` |
| G2 | Key Vault にパブリックネットワークから届かない | `publicNetworkAccess: Disabled` + Private Endpoint、Policy `kv-no-public-network` |
| G3 | コードや設定にシークレットを置かない | マネージド ID、Key Vault 参照、FTP / SCM の基本認証無効、App Insights / Log Analytics のローカル認証無効 |
| G4 | 各 ID は必要な権限だけを持つ | アプリごとの ID、リソーススコープのロール割り当て、CI の付与可能ロールを ABAC 条件で制限 |
| G5 | CI（= AI の変更が通る経路）はガードレール自体を変更できない | Policy と CI 用 ID は bootstrap（特権者）で管理、CI 用 ID は ops RG に分離 |
| G6 | 何が起きたか後から追える | 全リソースの診断ログを Log Analytics へ、アプリは Application Insights へ |

## 2. 全体構成

```
[Internet]
    │ HTTPS
    ▼
Front Door Premium + WAF (Prevention)
    │ Private Link（/api/* → api、それ以外 → web）
    ▼
App Service プラン（Linux、1 つに相乗り）
  ├─ web (Node で Angular の静的ファイルを配信)  publicNetworkAccess: Disabled
  └─ api (Python)                                 publicNetworkAccess: Disabled
        │ VNet 統合（送信はすべて VNet 経由）
        ▼
┌──────────────── VNet ─────────────────────────────────────────┐
│ snet-app: App Service の VNet 統合（Microsoft.Web/serverFarms） │
│ snet-pe : Private Endpoint（NSG で snet-app からの 443 のみ許可）│
│   └─ Key Vault                                                 │
└───────────────────────────────────────────────────────────────┘
Log Analytics / Application Insights（全リソースの診断ログ・テレメトリ）
```

外部から届く経路は `workload/main.bicep` の Front Door の `origins` 配列に列挙したものだけ。
経路を増やす変更は、この配列の差分としてレビューで必ず見えるようにしている。

### この構成を選んだ理由

- 実行基盤を App Service にした理由と別案: [ADR-0002](../../docs/adr/0002-hosting-app-service.md)
- 入口を Front Door 1 つにし、/api を Front Door で振り分ける理由と別案: [ADR-0003](../../docs/adr/0003-single-public-entry.md)

## 3. 権限の設計

### 3.1 2 段階のデプロイ

| 段階 | 実行者 | 内容 | テンプレート |
| --- | --- | --- | --- |
| bootstrap | 特権を持つ人間（手動） | RG、CI 用 ID、ロール、Policy | `bootstrap/main.bicep` |
| workload | CI（GitHub Actions → 将来 Azure DevOps） | アプリ基盤 | `workload/main.bicep` |

### 3.2 CI 用 ID の権限

- **Contributor（ワークロード RG）**: リソースの作成・更新。ロール割り当てと Policy は変更できない。
- **Role Based Access Control Administrator（ワークロード RG、条件付き）**:
  Key Vault Secrets User / Monitoring Metrics Publisher を、ServicePrincipal（マネージド ID）に付与・削除することだけを許可。
  付与可能なロールを増やすには `bootstrap/modules/deployer-roles.bicep` の変更（= 人間のレビュー）が必要。
- **ops RG には権限なし**: CI 用 ID 自身をワークロード RG に置くと、CI が自分の ID に別リポジトリのフェデレーション資格情報を足せてしまうため分離した。
- **OIDC の subject は GitHub Environment 単位**: `repo:<owner>/<repo>:environment:<env>`。
  Environment の保護ルール（承認者）を通ったジョブしかサインインできない。

### 3.3 アプリの ID

| ID | 付与ロール | スコープ |
| --- | --- | --- |
| `id-<w>-<env>-web` | なし（静的ファイルの配信だけなので） | - |
| `id-<w>-<env>-api` | Key Vault Secrets User / Monitoring Metrics Publisher | Key Vault / App Insights |

## 4. Azure Policy

ワークロード RG に組み込みポリシーを割り当てる（`bootstrap/modules/policy.bicep`）。
定義 ID は [Azure/azure-policy](https://github.com/Azure/azure-policy/tree/master/built-in-policies/policyDefinitions) で確認済み。

| キー | 効果 | 内容 |
| --- | --- | --- |
| allowed-locations | Deny | 許可リージョン以外への作成を拒否 |
| kv-no-public-network | Deny | Key Vault のパブリックアクセス |
| kv-rbac-only | Deny | Key Vault のアクセスポリシーモデル |
| kv-purge-protection | Deny | 消去保護なしの Key Vault |
| kv-resource-logs | AuditIfNotExists | Key Vault の診断ログ |
| app-no-public-network | Deny | App Service のパブリックアクセス |
| app-https-only | Deny | HTTP を許可する App Service |
| asp-private-link-sku | Deny | Private Link に対応しない SKU（Free / Shared）のプラン |
| app-private-link | AuditIfNotExists | Private Link のない App Service |
| app-latest-tls | AuditIfNotExists | 最新でない TLS バージョン |
| app-ftps-only | AuditIfNotExists | FTPS 以外の FTP |
| app-no-remote-debugging | AuditIfNotExists | リモートデバッグ |
| app-no-ftp-basic-auth | AuditIfNotExists | FTP の基本認証 |
| app-no-scm-basic-auth | AuditIfNotExists | SCM（Kudu）の基本認証 |
| app-managed-identity | AuditIfNotExists | マネージド ID のない App Service |
| fic-github-owner | Deny（Preview） | 他オーナーの GitHub リポジトリとのフェデレーション |

App Service の TLS・FTP・基本認証・マネージド ID の組み込みポリシーは Deny を選べない（AuditIfNotExists のみ）。
これらは IaC 側（`workload/modules/app-service.bicep`）で設定し、Policy は「後から崩れていないか」の監査に使う。

`policyEnforcementMode` を `DoNotEnforce` にすると、拒否せずに準拠状況だけを評価できる。
dev の初回はこれで影響を確認してから `Default` に切り替える。

## 5. ログと監視

- Log Analytics に Key Vault / App Service（web / api）/ Front Door の診断ログ（`allLogs`）とメトリックを集約。
- Application Insights はワークスペースベース、ローカル認証無効。api はマネージド ID で送信する
  （`APPLICATIONINSIGHTS_AUTHENTICATION_STRING` を設定済み）。
- アラート（WAF のブロック急増、Key Vault の認可失敗など）は未定義。「6. 今後」を参照。

## 6. 検証状況（重要）

この PR の時点では **Azure への実デプロイを行っていない**。

### 検証済み

- 組み込みポリシーの定義 ID・パラメーター・許可される効果（Azure/azure-policy リポジトリで確認）
- `bicep lint` / `bicep build-params` による型検査と linter（ルートの CI `mise run ci` が `//infra:lint` を実行。警告もエラー扱い）
- checkov による静的検査（同上）。**ただし網羅性は低い**: checkov の Bicep パーサーは `import` やユーザー定義関数などの構文を読めず、
  CI 時点で 6 ファイルが「解析エラー」として検査対象外になっている（解析できた範囲で 19 件合格）。
  コンパイル後の ARM JSON も試したが、入れ子デプロイ内のリソースは検査されなかった。
  そのため、静的検査は「早く気づくための補助」と位置づけ、最終的な強制は Azure Policy に任せる。
  Bicep を正しく展開して検査できる PSRule for Azure の導入を次の候補とする（「8. 今後」）

### 未検証（実デプロイで確認が必要）

| 項目 | 懸念 |
| --- | --- |
| bootstrap 全体 | サブスクリプション スコープのデプロイ、ABAC 条件の書式 |
| ABAC 条件付きの RBAC 管理者 | 条件式の構文と、PrincipalType 条件が期待どおり効くか |
| Front Door → App Service の Private Link | 構成自体は既存プロジェクトで実績あり。このテンプレートの Bicep（`groupId: sites`、2 オリジン、`approve-private-link` タスク）としては未確認 |
| Front Door のルート振り分け | `/api/*` と `/*` の 2 ルートで、`/api/*` が優先されるか |
| web の起動コマンド | `pm2 serve /home/site/wwwroot --no-daemon --spa` で Angular のビルド成果物が配信されるか |
| Key Vault 参照のシークレット | 初回デプロイ時、ロール割り当ての反映遅延で失敗する可能性 |
| `kv-resource-logs` の `requiredRetentionDays: 0` | 保持日数を診断設定で持たない構成で準拠と判定されるか |
| デプロイスタック | deny settings を有効にしたときの CI からの更新可否と必要権限 |
| `fic-github-owner`（Preview） | Preview ポリシーの Deny 効果 |

## 7. 既知の制約

- **アプリのデプロイ経路がない**: App Service はパブリックアクセス無効のため、デプロイ用の SCM（Kudu）サイトにも GitHub ホストランナーからは届かない。
  別案は (a) VNet 内のセルフホストランナー / Azure DevOps のマネージド DevOps プール、(b) Storage に置いたパッケージから起動（Run From Package、Storage の閉域化が別途必要）、(c) dev のみ SCM サイトに CI の送信元 IP を許可。
  アプリの CD を作るときに決める（推奨は (a)。Azure DevOps 移行とも相性が良い）。
- **送信方向の制御がない**: App Service からインターネットへの送信は制限していない。Azure Firewall + UDR で制御できるが、コスト（月数万円〜）が大きい。
- **Log Analytics の閉域化（AMPLS）は未対応**: 取り込み・クエリはパブリックエンドポイント経由（Entra ID 認証のみ）。
- **コスト**: Front Door Premium（月 330 ドル程度）が固定費の大半を占め、次が App Service プラン（P0v3 で月 60〜80 ドル程度、金額は目安）。dev で抑えたい場合は `enableFrontDoor = false`（VNet 内からのみアクセス）にできる。
- **what-if とデプロイの承認タイミング**: 現在のワークフローは「承認 → what-if → デプロイ」の順で、承認者は what-if を見る前に承認する。
  what-if 専用の権限の小さい ID を別に用意すれば「what-if → 承認 → デプロイ」にできる。

## 8. 今後

1. 実デプロイで「6. 未検証」を潰す（dev、`policyEnforcementMode = DoNotEnforce` から）
2. アプリのデプロイ経路を決める（7 を参照）
3. アラート（WAF ブロック、Key Vault 認可失敗、アプリの 5xx 増加）とアクショングループ
4. データストア（PostgreSQL Flexible Server など）を Private Endpoint + Entra 認証で追加
5. PSRule for Azure の導入（checkov で検査できていないファイルを含め、Well-Architected の観点で検査する）
6. `infra/` と `bootstrap/` に CODEOWNERS を設定し、ガードレールの変更に人間のレビューを必須にする
