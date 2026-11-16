# ADR-0001: IaC ツールに Bicep を採用する

- 状態: 採用（2026-11-14）
- 関連: [infra/docs/azure-infra-guardrails.md](../../infra/docs/azure-infra-guardrails.md)、[infra の静的検査のタスク](../../infra/mise.toml)、[Policy の定義](../../infra/bootstrap/modules/policy.bicep)

## 背景（なぜ決める必要があるか）

このリポジトリは「AI が書いたコードでも安全に動く Azure 基盤」をテンプレートとして提供する。
IaC はそのガードレールを「コードとして」レビュー・機械検証できる形にするための土台になる。

判断に効く前提は次のとおり。

1. **クラウドは Azure のみ**。マルチクラウドの予定はない。
2. **CI は当面 GitHub Actions、将来 Azure DevOps**。どちらでも同じ `mise run ...` を呼ぶ。
3. **人間は why と受け入れ条件を守り、細部は AI + 機械検証に任せる**。だから「AI が間違えたときに機械が止める仕組み」が多いほど良い。
4. **ガードレールの本体は Azure Policy と RBAC**。IaC ツールが何であっても、最後に止めるのは Azure 側。

## 選択肢

### A. Bicep（採用）

| 観点 | 評価 |
| --- | --- |
| 状態管理 | **state ファイルがない**。Azure 自体が真実の状態。state の保管場所（暗号化・ロック・アクセス制御）を設計・防御する必要がない（[Bicep の概要](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview)） |
| 新機能への追随 | ARM の API バージョンをそのまま使えるので、新しいプロパティ（例: Container Apps の `publicNetworkAccess`）を即日使える |
| 型検査 | リソースのスキーマに対してコンパイル時に型検査される。AI が存在しないプロパティを書くと `bicep lint` で検出できる |
| 静的検査 | `bicep lint`（組み込み linter）、checkov、PSRule for Azure |
| 差分確認 | `what-if`（[what-if](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-what-if)）。Terraform の plan より誤検知（ノイズ）が多い（推測。チームの経験による） |
| ドリフト・削除 | デプロイスタックで「コードから消えたリソース」の削除と、手動変更の拒否（deny settings）ができる（[デプロイスタック](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-stacks)） |
| 認証 | `az` CLI と OIDC のみ。GitHub Actions でも Azure DevOps でも同じ |
| Entra ID / GitHub の管理 | Entra は Microsoft Graph Bicep 拡張で一部可能。GitHub リポジトリ設定などは扱えない |

### B. Terraform（azurerm / azapi）

| 観点 | 評価 |
| --- | --- |
| 状態管理 | state ファイルが必要。state には**シークレットが平文で入りうる**（[Terraform: Sensitive data in state](https://developer.hashicorp.com/terraform/language/state/sensitive-data)）ため、Storage Account（それ自体を閉域化・RBAC 化）とロックの設計が要る。鶏と卵問題（state 置き場を何で作るか）もある |
| 新機能への追随 | azurerm プロバイダーの対応待ちが発生する（azapi で回避可能だが、型の恩恵が薄れる） |
| 静的検査 | tflint、checkov、trivy、`terraform test` とエコシステムが厚い |
| 差分確認 | `plan` が正確で、レビューしやすい。**ここは Terraform が明確に優位** |
| AI との相性 | 学習データが多く、生成精度は高い傾向（推測） |
| 守備範囲 | Entra ID、GitHub、Azure DevOps なども同じ言語で管理できる |

### C. Azure Verified Modules（AVM）を使う（A/B と直交）

AVM は Bicep・Terraform の両方に公式モジュールがあり、セキュアな既定値を持つ。
ただしパラメーターが非常に多く、「どこでガードレールが効いているか」がモジュールの内側に隠れる。
**ガードレールの所在をレビューで見えるようにすること**を優先し、ネイティブのリソース定義で書く。
運用フェーズで保守コストが問題になったら AVM への置き換えを検討する。

## 決定

**Bicep を採用する。**

決め手は次の 3 点。

1. **state を守る必要がない**。セキュアな基盤を作るのに、最初に「state という新しい機密データの置き場」を作らずに済む。
2. **型検査と linter が標準で付いてくる**。AI の書き間違いを、Azure の認証情報なしで CI で止められる。
   Terraform の方が AI の生成精度は高い傾向があるが、生成精度の差より、生成後の検査の強さの方が効くと判断した。Bicep はスキーマ型検査があり、checkov も両対応なので、検査面で Terraform に劣る点は小さい。
3. **Azure 以外を管理する予定がない**。Terraform の最大の強み（守備範囲の広さ）が今は効かない。

あわせて、次の約束を置く。

- what-if は「意図しない削除・置換がないか」を見る用途に絞る。「やってはいけない構成」は Azure Policy の Deny で止める。
- デプロイスタックの deny settings は、通常のデプロイと同等の挙動（`none`）から始め、検証してから削除の拒否などへ段階的に強める。デプロイスタックはまだ新しい機能なので。

## 結果（この判断で受け入れること）

- **what-if のノイズ。** Terraform の plan に比べて正確さに欠け、人間が受け入れ条件を守るうえでの弱点になる。致命的な構成は Policy の Deny で止まるので、what-if を細部まで読まなくてもよい、という前提で受け入れる。
- AVM を使わない分、モジュールの保守はこのリポジトリで持つ。

## この ADR で決めないこと

- Azure 以外（Entra のアプリ登録、GitHub のリポジトリ設定など）を何でコード化するか。必要になったときに決める。そのときは、Azure の基盤は Bicep のまま、その部分だけ Terraform を併用することを候補にする。

## 確かめ方

- CI の infra の静的検査（Bicep の型検査と linter、checkov）で、AI の書き間違いと既知の危険な設定を止める。
- 致命的な構成は、Azure Policy の Deny でデプロイ時に止める。

## 見直しの条件

次のどれかが起きたら、この ADR を見直す。

- Azure 以外（他クラウド、SaaS）のリソースを同じパイプラインで管理する必要が出た
- what-if のノイズで、レビューが実質的に機能しなくなった
- Bicep の型定義が追いつかず、`any()` やプロパティ警告の抑止が常態化した
