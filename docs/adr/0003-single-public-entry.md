# ADR-0003: 入口を Front Door 1 つにし、/api は Front Door で api に振り分ける

- 状態: 提案（2026-11-14）
- 関連: [ADR-0002](0002-hosting-app-service.md)、[infra/docs/guardrails.md](../../infra/docs/guardrails.md)（G1）

## 背景（なぜ決める必要があるか）

Angular の SPA はブラウザで動くので、ブラウザから API に届く経路が必要になる。

このプロジェクトでは AI がアプリやデプロイ定義を追加していく。
「外部から届く口」が増えていくと、どれが意図した公開なのかをレビューで見分けにくくなる。
そこで、**外部から届く口を 1 つに固定し、それ以外は Azure Policy で機械的に拒否したい**。

## 選択肢

| 案 | 内容 | 長所 | 短所 |
| --- | --- | --- | --- |
| **A. Front Door で振り分け（採用）** | web も api もパブリックアクセス無効。Front Door が Private Link で両方に接続し、`/api/*` を api、それ以外を web に送る | プロキシのコードが不要。ブラウザから見ると同一オリジンなので CORS も不要。Front Door + App Service の定番構成 | Front Door のオリジンが 2 つになる。経路の追加は Policy では止められず、IaC のレビューで見る |
| B. web が /api を api に中継 | Front Door のオリジンは web だけ。web のサーバーが api に転送する | Front Door の経路が 1 つで単純 | web に中継用のサーバーコード（Node など）が必要。web が落ちると API も使えない |
| C. api を独立して公開 | ブラウザが api の URL を直接呼ぶ | 構成が最も単純 | 外部の口が 2 つ。CORS の設定が必要 |
| D. BFF（Backend for Frontend）を別アプリで立てる | 認証やセッションを BFF で扱う | 認証トークンをブラウザに置かずに済む | アプリが 1 つ増える。現時点の要件に対して過剰 |

## 決定

**A を採用する。**

- すべてのアプリを `publicNetworkAccess: Disabled` にし、Policy `app-no-public-network`（Deny）で強制する。
  AI が新しいアプリを追加して公開しようとしても、デプロイが失敗する。
- 外部から届く経路は、`infra/workload/main.bicep` の Front Door の `origins` 配列に列挙したものだけになる。
  経路を増やすには、この配列を変更する必要があり、差分としてレビューで必ず見える。

アプリ側への影響:

- Angular は API を相対パス（`/api/...`）で呼ぶ。API の URL を設定に持たない。
- api は `/api` 配下でルーティングする（Front Door はパスを書き換えずに転送する）。
- 認証・認可は api 側で必ず行う（Front Door を通ることは認証の代わりにならない）。

## 批判的な再検討

- **「当初の案（web の nginx が中継）の方が、外部公開が 1 アプリに絞れて強いのでは？」**
  Container Apps のときは「web 以外の外部公開を Deny」と書けたので中継案に意味があった。
  App Service では全アプリが閉域になり、外部から届くかどうかは Front Door の設定だけで決まる。
  中継のコードを書いて保守するより、経路を `origins` 配列 1 か所に集めてレビューする方が単純で確実と判断した。
- **「Front Door の経路の追加を機械で止められないのは弱いのでは？」**
  そのとおりで、ここはレビュー頼みになる。`infra/` に CODEOWNERS を付けて人間のレビューを必須にする（guardrails.md 8 章）。
  Front Door は CI がデプロイするワークロード側にあるので、Policy で固定するなら bootstrap 側に移す必要があり、今回はそこまでしない。
- **「認証が入ったら D（BFF）が必要になるのでは？」**
  可能性はある。トークンをブラウザに置きたくない要件が出たら、`/api/*` の振り分け先を BFF に変える。
  その場合も「入口は Front Door 1 つ」という方針は変わらない。

## 見直しの条件

- 認証方式の決定で、ブラウザにトークンを置かない要件が出た → D を検討
- api を外部の別システムからも直接呼ぶ必要が出た → 公開 API 用の入口（API Management など）を別に設計する
