# ハーネス

AI 駆動でチーム開発するための進め方と、それを支える skill・検査・タスクの一式を「ハーネス」と呼ぶ。
ハーネスはこのリポジトリ専用ではなく、他のリポジトリへ持ち出して使えるものとして育てる。このリポジトリの中で育て、他のリポジトリへは zip で配って最初のコミットで取り込む([ADR-0011](adr/0011-harness-boundary.md))。

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

zip にまとめ、使う側のリポジトリの最初のコミットで取り込む([ADR-0011](adr/0011-harness-boundary.md))。

```sh
mise run harness:pack            # aidd-harness-<コミット>.zip を作る
mise run harness:pack -o <file>  # 出力先を指定する
```

1. このリポジトリで `mise run harness:pack` を流す。中身は HEAD のコミットから取る(未コミットの変更は入らない)。
2. 使う側のリポジトリで zip を展開してコミットする。zip の `HARNESS_VERSION` に、元にした版(コミット)と、書き直すファイルと、入れたファイルの一覧がある。`HARNESS_VERSION` もコミットしておく。
3. `HARNESS_VERSION` の `rewrite` に挙げたファイル(プロジェクトの前提、ルートの `mise.toml`)を書き直す。プロジェクトの前提は、このプロジェクトの内容が入ったまま届くので、見出しを残して中身を差し替える。

取り込んだ後は、使う側ごとに中身が分かれていくのを受け入れる。こちらの改善を後から取り込むときは、`HARNESS_VERSION` の版と今の版の差分を見て手で取り込む。
それが重くなったら、更新を 3-way マージで取り込める [Copier](https://copier.readthedocs.io/) への切り替えを考える。この一覧はそのまま Copier のテンプレートの範囲に使える。
