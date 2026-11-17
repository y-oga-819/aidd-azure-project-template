# ハーネス

AI 駆動でチーム開発するための進め方と、それを支える skill・検査・タスクの一式を「ハーネス」と呼ぶ。
ハーネスはこのリポジトリ専用ではなく、他のリポジトリへ持ち出して使えるものとして育てる。今はこのリポジトリの中で育て、持ち出すのは 2 つ目の利用先が来たとき([ADR-0011](adr/0011-harness-boundary.md))。

## 何がハーネスか

配るファイルの一覧は [harness-files.txt](harness-files.txt) の 1 か所にある。一覧に無いもの(`backend/`、`infra/`、`README.md`、ADR-0001〜0003 など)は、このプロジェクトのもの。

| まとまり | 中身 |
| --- | --- |
| skill | プランニング(`/planning`)、PR 前の理解度テスト(`/pr-quiz`) |
| 補助ツールと mise タスク | `tools/`(aidd_spec。仕様一覧、計画との照合、テスト ID の検査)、`mise-tasks/`(`docs:spec`、`plan:*`、`test:*`、`push` / `pr` / `pr-view`)、`scripts/lib/` |
| CI | `mise run ci` を呼ぶだけの GitHub Actions と Azure Pipelines の定義 |
| 進め方の文書とテンプレート | [開発の進め方](development-flow.md)、[テスト戦略](testing-strategy.md)、[レビューの観点](review-guide.md)、[PR テンプレート](pull_request_template.md)、計画・ADR・機能 README のテンプレート |
| ハーネスの判断 | ADR-0004〜0011 |

## 守ること: プロジェクト固有の前提をハーネスに書かない

- プロジェクトに固有の前提(技術、コードの置き場所、実行基盤、外部から届く口、レビューで疑う場所)は [プロジェクトの前提](project-context.md) にだけ書く。ハーネスの文書や skill は、その見出しを名前で指す。
- 持ち出した先では、プロジェクトの前提だけを書き直せばハーネスが使える状態を保つ。
- ハーネスにファイルを足したり、改名したり、消したりしたら、[harness-files.txt](harness-files.txt) も直す。一覧のパスが実在するかは `mise run harness:files`(`check` に含む)が確かめる。
- 例を書くのはかまわない(「CDN など」「例: `backend`」)。読んだ人が「このプロジェクトではそうなっている」と受け取る書き方(「このリポジトリでは〜」)にしない。

## ハーネスの立場

ハーネスは次の前提の上に作っている。これを外すと、ハーネスの一部を作り直すことになる。

| 前提 | どこが依存しているか | 外すとき |
| --- | --- | --- |
| テストは pytest で書く | テスト ID の書き方(`pytest.param` の id、docstring)、仕様一覧と計画の照合(aidd_spec の pytest プラグイン) | 他のテストランナーの分だけ、仕様の収集(`spec-collect`)を足す。照合と ID の検査は収集結果の JSON を読むだけなので、そのまま使える |
| タスクは mise で動かす([ADR-0004](adr/0004-task-runner-mise.md)) | すべての入口(`check`、`pr`、`docs:spec` など)、CI | 作り直しになる |
| VCS は GitHub か Azure DevOps | `push` / `pr` / `pr-view`(`AIDD_VCS_PROVIDER` で切り替え。[PR 操作の切り替え](vcs-provider.md))、PR テンプレートの置き場所、CI の定義 | `scripts/lib/vcs.sh` に操作先を足す |
| 文書と skill は日本語 | すべての文書、skill の質問、テスト名の規約 | 翻訳になる。テスト名を日本語で書く規約([テスト戦略](testing-strategy.md))も見直す |
| AI のエージェントは Claude Code | skill の置き場所(`.claude/skills/`) | skill の中身は Markdown なので、他のエージェントの置き場所に移せば読める |

## ハーネスとプロジェクトの接点

ハーネスが、プロジェクトのコンポーネント(`backend/` など)に求める約束。コンポーネントを足すときは、この約束を満たせばハーネスの検査に取り込まれる。

| 約束 | 内容 |
| --- | --- |
| 共通タスク名 | `setup` / `format` / `format-check` / `lint` / `typecheck` / `test` / `security`。該当するものだけ定義する。ルートの `check` が全コンポーネントから集める |
| `spec-collect` | テストを収集して、`AIDD_SPEC_OUT` に JSON を書く。pytest なら `PYTHONPATH` に `AIDD_TOOLS_SRC`(ルートの `mise.toml` が決める)を足し、`-p aidd_spec.pytest_plugin` で読み込む。`docs:spec`、`plan:verify`、`test:ids` が使う |
| `test-mutation` | ミューテーションテストを流す(任意)。`test:mutation` が使う |
| プロジェクトの前提 | [project-context.md](project-context.md) の見出し(「技術とコードの置き場所」「実行基盤と外部から届く口」「レビューで疑う場所」)を保つ |

## 持ち出すとき

今はやらない。2 つ目の利用先が来たら、次の順で考える([ADR-0011](adr/0011-harness-boundary.md))。

- 第一候補は [Copier](https://copier.readthedocs.io/)。このリポジトリをテンプレートにして、[harness-files.txt](harness-files.txt) の範囲を取り込む。取り込み先に「どの版から取り込んだか」が残り、ハーネスを直したら `copier update` で 3-way マージして更新できる。
- Copier を入れられない環境には、同じ範囲を `git archive` で zip にする。zip には版と、入れたファイルの一覧(`mise run harness:files --list`)を含める。zip は更新が手作業のマージになるので、使う側ごとに中身が分かれやすい。
- 持ち出した先では、`rewrite` のファイル(プロジェクトの前提、ルートの `mise.toml`)を書き直す。
