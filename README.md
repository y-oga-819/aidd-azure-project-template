# aidd-azure-project-template
フロントエンドをAngular、バックエンドをpythonで実装して、AI駆動に適したアーキテクチャをセキュアに保ちながらAzure上に構築するプロジェクトの検証リポジトリ。

## 開発の始め方

ツールのバージョンとタスクは [mise](https://mise.jdx.dev/) で管理する。人も AI エージェントも CI も、同じ `mise run <task>` を使う(採用理由: [ADR-0004](docs/adr/0004-task-runner-mise.md))。

```sh
mise trust          # 初回のみ。リポジトリの mise.toml を信頼する
mise install        # ツールを揃える
mise run setup      # 依存関係を入れる
mise run check      # CI と同じ検査一式(format-check / lint / typecheck / test / security)
mise run format     # 整形
mise run pr -b <本文>  # check → push → PR 作成(本文は docs/pull_request_template.md の形)
mise run pr-view    # 現在のブランチの PR と CI の状況
mise run docs:spec  # テストから仕様一覧を出す(テストが仕様の正本)
mise run plan:verify <計画>  # 計画のテストケース一覧とテストを照合する
mise tasks --all    # タスク一覧
```

## 構成

| パス | 役割 |
| --- | --- |
| `mise.toml` | 共通ツールと集約タスク(`check` など) |
| `backend/` | Python バックエンド。`backend/mise.toml` に専用ツールとタスク |
| `tools/` | 開発の進め方を支える補助ツール(仕様一覧の生成、計画との照合) |
| `mise-tasks/` | push / PR 作成などの VCS 操作タスク、仕様一覧のタスク |
| `.github/workflows/ci.yml` | GitHub Actions。`mise run ci` を呼ぶだけ |
| `azure-pipelines.yml` | 同じ形の Azure Pipelines 定義(未検証) |

コンポーネント(`frontend/`、`infra/` など)を足すときは、そのディレクトリに `mise.toml` を置き、共通タスク名(`setup` / `format` / `format-check` / `lint` / `typecheck` / `test` / `security`)のうち該当するものを定義する。ルートの `mise run check` と CI に自動で取り込まれるので、ルートの設定を編集する必要はない。共通タスクはクラウドの認証情報なしで通るものにし、デプロイなどは別の名前にする(例: `mise run //infra:deploy`)。

PR 操作の GitHub / Azure DevOps 切り替えは [docs/vcs-provider.md](docs/vcs-provider.md) を参照。

## 開発の進め方とテスト

- 進め方(計画 → テスト → 実装、コンフリクトの避け方と解消): [docs/development-flow.md](docs/development-flow.md)
- テスト戦略: [docs/testing-strategy.md](docs/testing-strategy.md)
- 仕様の正本はテストにし、計画は使い捨てにする: [ADR-0005](docs/adr/0005-tests-as-specification.md)
- テンプレート: [計画](docs/templates/plan.md)、[機能ごとの README](docs/templates/feature-readme.md)

## PR の書き方とレビュー

- PR 概要のテンプレート: [docs/pull_request_template.md](docs/pull_request_template.md)
- レビュアーの観点: [docs/review-guide.md](docs/review-guide.md)

テンプレートを `docs/` に置いているのは、GitHub(直下 / `docs/` / `.github/` を探す)と Azure DevOps(`.azuredevops/` / `.vsts/` / `docs/` / 直下を探す)の両方が読む場所だからです。移行しても置き場所を変える必要はありません。
