# セキュア基盤とガードレール

この文書は「何を守っているか」「なぜそうしたか」「まだ検証できていないことは何か」をまとめる。
Bicep のコードを変更する人（AI を含む）は、ここに書かれた前提を崩さないこと。

## 1. 守りたいこと（受け入れ条件）

AI が書いたアプリコードや IaC がデプロイされても、次が常に成り立つ。

| # | 受け入れ条件 | 主に効いている仕組み |
| --- | --- | --- |
| G1 | インターネットから届くのは Front Door (WAF) 経由のフロントエンドだけ | 内部モードの Container Apps 環境、Policy `ca-no-external-ingress` / `cae-internal-only` |
| G2 | Key Vault・ACR にパブリックネットワークから届かない | `publicNetworkAccess: Disabled` + Private Endpoint、Policy `kv-no-public-network` / `acr-no-public-network` |
| G3 | コードや設定にシークレットを置かない | マネージド ID、Key Vault 参照、ACR 管理者ユーザー無効、App Insights / Log Analytics のローカル認証無効 |
| G4 | 各 ID は必要な権限だけを持つ | アプリごとの ID、リソーススコープのロール割り当て、CI の付与可能ロールを ABAC 条件で制限 |
| G5 | CI（= AI の変更が通る経路）はガードレール自体を変更できない | Policy と CI 用 ID は bootstrap（特権者）で管理、CI 用 ID は ops RG に分離 |
| G6 | 何が起きたか後から追える | 全リソースの診断ログを Log Analytics へ、アプリは Application Insights へ |

## 2. 全体構成

```
[Internet]
    │ HTTPS
    ▼
Front Door Premium + WAF (Prevention)
    │ Private Link
    ▼
┌──────────────── VNet ─────────────────────────────────────────┐
│ snet-cae: Container Apps 環境（内部モード・パブリック無効）     │
│   ├─ web (Angular / nginx)  ingress.external = true            │
│   │     └─ /api を内部でリバースプロキシ                        │
│   └─ api (Python)           ingress.external = false           │
│                                                               │
│ snet-pe: Private Endpoint（NSG で snet-cae からの 443 のみ許可） │
│   ├─ Key Vault                                                 │
│   └─ Container Registry                                        │
└───────────────────────────────────────────────────────────────┘
Log Analytics / Application Insights（全リソースの診断ログ・テレメトリ）
```

### なぜ Container Apps か（別案との比較）

| 案 | 長所 | 短所 | 判断 |
| --- | --- | --- | --- |
| **Container Apps（採用）** | Angular も Python もコンテナで同じ扱い。VNet 内部モード、マネージド ID、Key Vault 参照が標準。スケール to 0 | ACR の閉域化に伴う push 経路の課題（後述） | 採用 |
| App Service | 成熟、Python のビルトイン実行環境 | フロントとバックで別の仕組みになりやすい。閉域化に Private Endpoint が個別に必要 | 次点 |
| Static Web Apps + Functions | フロントの配信が簡単 | 閉域化の選択肢が少なく、Python API の自由度が低い | 不採用 |
| AKS | 何でもできる | 運用負荷が大きく、テンプレートの目的に対して過剰 | 不採用 |

### なぜ api をブラウザから直接呼ばせないか

Angular の SPA はブラウザで動くため、通常は API も外部公開が必要になる。
ここでは web（nginx）が `/api` を環境内部の api にプロキシする構成にし、**外部公開されるアプリを 1 つに限定**した。
こうすると Policy で「web 以外の外部公開を Deny」と書ける（G1）。
AI が新しいアプリを追加して `external: true` にしても、デプロイが失敗する。

nginx 側の設定（`BACKEND_BASE_URL` 環境変数を使ったプロキシ）はアプリ側のスレッドで実装する。

## 3. 権限の設計

### 3.1 2 段階のデプロイ

| 段階 | 実行者 | 内容 | テンプレート |
| --- | --- | --- | --- |
| bootstrap | 特権を持つ人間（手動） | RG、CI 用 ID、ロール、Policy | `bootstrap/main.bicep` |
| workload | CI（GitHub Actions → 将来 Azure DevOps） | アプリ基盤 | `workload/main.bicep` |

### 3.2 CI 用 ID の権限

- **Contributor（ワークロード RG）**: リソースの作成・更新。ロール割り当てと Policy は変更できない。
- **Role Based Access Control Administrator（ワークロード RG、条件付き）**:
  AcrPull / Key Vault Secrets User / Monitoring Metrics Publisher を、ServicePrincipal（マネージド ID）に付与・削除することだけを許可。
  付与可能なロールを増やすには `bootstrap/modules/deployer-roles.bicep` の変更（= 人間のレビュー）が必要。
- **ops RG には権限なし**: CI 用 ID 自身をワークロード RG に置くと、CI が自分の ID に別リポジトリのフェデレーション資格情報を足せてしまうため分離した。
- **OIDC の subject は GitHub Environment 単位**: `repo:<owner>/<repo>:environment:<env>`。
  Environment の保護ルール（承認者）を通ったジョブしかサインインできない。

### 3.3 アプリの ID

| ID | 付与ロール | スコープ |
| --- | --- | --- |
| `id-<w>-<env>-web` | AcrPull | ACR |
| `id-<w>-<env>-api` | AcrPull / Key Vault Secrets User / Monitoring Metrics Publisher | ACR / Key Vault / App Insights |

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
| acr-no-public-network | Deny | ACR のパブリックアクセス |
| acr-no-admin-user | Deny | ACR の管理者ユーザー |
| acr-no-anonymous-pull | Deny | ACR の匿名プル |
| cae-vnet-injection | Deny | VNet 注入なしの Container Apps 環境 |
| cae-internal-only | Deny | 内部モードでない Container Apps 環境 |
| ca-no-external-ingress | Deny（web は除外） | Container App の外部公開 |
| ca-https-only | Deny | HTTP を許可する Container App |
| ca-managed-identity | Deny | マネージド ID のない Container App |
| fic-github-owner | Deny（Preview） | 他オーナーの GitHub リポジトリとのフェデレーション |

`policyEnforcementMode` を `DoNotEnforce` にすると、拒否せずに準拠状況だけを評価できる。
dev の初回はこれで影響を確認してから `Default` に切り替える。

## 5. ログと監視

- Log Analytics に Key Vault / ACR / Container Apps 環境 / Front Door の診断ログ（`allLogs`）とメトリックを集約。
- Application Insights はワークスペースベース、ローカル認証無効。api はマネージド ID で送信する
  （`APPLICATIONINSIGHTS_AUTHENTICATION_STRING` を設定済み）。
- アラート（WAF のブロック急増、Key Vault の認可失敗など）は未定義。「6. 今後」を参照。

## 6. 検証状況（重要）

この PR の時点では **Azure への実デプロイを行っていない**。

### 検証済み

- 組み込みポリシーの定義 ID・パラメーター・許可される効果（Azure/azure-policy リポジトリで確認）
- `bicep lint` / `bicep build-params` / checkov による静的検査（CI の `infra-static`）

### 未検証（実デプロイで確認が必要）

| 項目 | 懸念 |
| --- | --- |
| bootstrap 全体 | サブスクリプション スコープのデプロイ、ABAC 条件の書式 |
| ABAC 条件付きの RBAC 管理者 | 条件式の構文と、PrincipalType 条件が期待どおり効くか |
| Front Door → Container Apps の Private Link | `groupId: managedEnvironments` での接続、`approve-private-link` タスクでの承認、内部モード + `publicNetworkAccess: Disabled` との組み合わせ |
| Container Apps 環境の `publicNetworkAccess`（`@2025-07-01`） | 型定義には存在する（lint で確認）が、内部モードとの組み合わせで期待どおり動くか |
| web → api の内部 HTTPS 呼び出し | 内部 FQDN と証明書の扱い |
| Key Vault 参照のシークレット | 初回デプロイ時、ロール割り当ての反映遅延で失敗する可能性 |
| `kv-resource-logs` の `requiredRetentionDays: 0` | 保持日数を診断設定で持たない構成で準拠と判定されるか |
| デプロイスタック | deny settings を有効にしたときの CI からの更新可否と必要権限 |
| `fic-github-owner`（Preview） | Preview ポリシーの Deny 効果 |

## 7. 既知の制約

- **ACR への push 経路がない**: パブリックアクセス無効 + `networkRuleBypassOptions: None` のため、GitHub ホストランナーからは push できない。
  別案は (a) VNet 内のセルフホストランナー / Azure DevOps のマネージド DevOps プール、(b) ACR Tasks のエージェントプール、(c) dev のみ CI の送信元 IP を許可。
  アプリの CD を作るときに決める（推奨は (a)。Azure DevOps 移行とも相性が良い）。
- **送信方向の制御がない**: Container Apps からインターネットへの送信は制限していない。Azure Firewall + UDR で制御できるが、コスト（月数万円〜）が大きい。
- **Log Analytics の閉域化（AMPLS）は未対応**: 取り込み・クエリはパブリックエンドポイント経由（Entra ID 認証のみ）。
- **コスト**: Front Door Premium と ACR Premium が固定費の大半を占める。dev で抑えたい場合は `enableFrontDoor = false`（VNet 内からのみアクセス）にできる。
- **what-if とデプロイの承認タイミング**: 現在のワークフローは「承認 → what-if → デプロイ」の順で、承認者は what-if を見る前に承認する。
  what-if 専用の権限の小さい ID を別に用意すれば「what-if → 承認 → デプロイ」にできる。

## 8. 今後

1. 実デプロイで「6. 未検証」を潰す（dev、`policyEnforcementMode = DoNotEnforce` から）
2. ACR への push 経路を決める（7 を参照）
3. アラート（WAF ブロック、Key Vault 認可失敗、コンテナ再起動）とアクショングループ
4. データストア（PostgreSQL Flexible Server など）を Private Endpoint + Entra 認証で追加
5. PSRule for Azure の導入（Well-Architected の観点での検査を追加）
6. `infra/` と `bootstrap/` に CODEOWNERS を設定し、ガードレールの変更に人間のレビューを必須にする
