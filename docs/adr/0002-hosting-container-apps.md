# ADR-0002: アプリの実行基盤に Azure Container Apps を採用する

- 状態: 提案（2026-11-14）
- 関連: [ADR-0003](0003-single-public-entry.md)、[infra/docs/guardrails.md](../../infra/docs/guardrails.md)

## 背景（なぜ決める必要があるか）

Angular（フロントエンド）と Python（バックエンド）を Azure 上で動かす。基盤に求めることは次のとおり。

1. **閉域にできる**: アプリも依存先（Key Vault、ACR、将来の DB）もパブリックネットワークに出さない。
2. **シークレットを持たない**: マネージド ID で他のリソースに接続でき、シークレットは Key Vault 参照で渡せる。
3. **ガードレールを Azure Policy で書ける**: 「外部公開しない」「マネージド ID を使う」などを組み込みポリシーで Deny できる。
4. **フロントとバックを同じ仕組みで扱える**: AI が書くデプロイ定義の種類を減らし、レビューする場所を絞る。
5. **運用の負荷が小さい**: テンプレートとして、少人数のチームでも運用できる。

## 選択肢

| 案 | 長所 | 短所 |
| --- | --- | --- |
| **A. Container Apps（採用）** | Angular も Python もコンテナとして同じ扱い。VNet 注入 + 内部モード、マネージド ID、Key Vault 参照が標準機能。外部公開・VNet 注入・マネージド ID に組み込みポリシーがある。0 台までスケールできる | イメージのビルドと ACR が必要。ACR を閉域にすると、GitHub ホストランナーから push できない |
| B. App Service | 成熟している。Python の実行環境が組み込みで、コンテナ不要 | フロント（静的配信）とバックで別の仕組みになりやすい。閉域化はアプリごとに Private Endpoint と VNet 統合を組む必要がある |
| C. Static Web Apps + Functions | フロントの配信が簡単 | 閉域化の選択肢が少ない。Python API の実行時間や構成の自由度が低い |
| D. AKS | 何でもできる | クラスターの運用（アップグレード、ノード、ネットワークポリシー）が重く、テンプレートの目的に対して過剰 |

## 決定

**A. Container Apps を採用する。**

決め手は、要件 1〜3 を**標準機能と組み込みポリシーの組み合わせだけで**満たせること。
特に「アプリを外部公開しない」（`ingress.external = false`）と「環境を内部モードにする」を Policy で Deny できるため、
AI が新しいアプリを追加しても、閉域の前提を崩す構成はデプロイ時に失敗する。

## 批判的な再検討

- **「Python の API だけなら App Service の方が簡単では？」**
  単体ならその通り。ただしフロントも含めると仕組みが 2 つになり、ガードレールも 2 系統必要になる。
  コンテナ化の手間（Dockerfile）は AI が書ける部分で、人間のレビュー負荷はあまり増えない。
- **「ACR の push 経路がないのは致命的では？」**
  閉域の ACR を選んだ結果で、Container Apps 固有の問題ではない（App Service でもコンテナを使えば同じ）。
  VNet 内のランナー（Azure DevOps のマネージド DevOps プールなど）で解決でき、Azure DevOps への移行方針とも合う。アプリの CD を作るときに決める。
- **「Container Apps の新しい機能（Private Link、`publicNetworkAccess`）は枯れていないのでは？」**
  その懸念は残る。Front Door からの Private Link 接続は実デプロイで未検証（guardrails.md 6 章）。
  動かなかった場合の代替は、Application Gateway（WAF）を VNet 内に置いて内部モードの環境に接続する構成。この場合も Container Apps の採用自体は変わらない。

## 見直しの条件

- コンテナの運用（ベースイメージの更新、脆弱性対応）がチームの負担になった → App Service を再検討
- ネットワークポリシーやサービスメッシュなど、Container Apps で表現できない要件が出た → AKS を再検討
