# ハーネス

AI 駆動でチーム開発するための進め方と、それを支える skill・検査・タスクの一式を「ハーネス」と呼ぶ。
ハーネスはこのリポジトリ専用ではなく、他のリポジトリへ持ち出して使えるものとして育てる。このリポジトリの中で育て、他のリポジトリへは zip で配って最初のコミットで取り込む。

## 何がハーネスか

配るファイルの一覧は [harness-files.txt](files.txt) の 1 か所にある。一覧に無いもの(`backend/`、`infra/`、`README.md` など)は、このプロジェクトのもの。

| まとまり | 中身 |
| --- | --- |
| AI への常設の指示 | [AI エージェントへの約束](agent-rules.md)。利用先の `CLAUDE.md` が 1 行で読み込む |
| skill | プランニング(`/planning`)、PR 前の理解度テスト(`/pr-quiz`) |
| 補助ツールと mise タスク | `tools/`(aidd_spec。仕様一覧、計画との照合、テスト ID の検査)、`mise-tasks/`(`docs:spec`、`plan:*`、`test:*`、`push` / `pr` / `pr-view`)、`scripts/lib/` |
| CI | `mise run ci` を呼ぶだけの GitHub Actions と Azure Pipelines の定義 |
| 進め方の文書とテンプレート | [開発の進め方](../development-flow.md)、[テスト戦略](../testing-strategy.md)、[レビューの観点](../review-guide.md)、[PR テンプレート](../pull_request_template.md)、計画・ADR・機能 README のテンプレート |

## 守ること: 技術は具体的に書き、リポジトリごとの違いだけを分ける

- ハーネスは Angular / Python / Azure の構成を前提にする(下の「ハーネスの立場」)。skill や文書は、Azure、Front Door、App Service、Angular、`backend/` のような具体名で書く。気づくきっかけは具体名のほうで、ぼかすと AI も人も気づけなくなるため。
- リポジトリごとに違うこと(何を作るか、想定する構成と違う点、インフラのガードレールの場所)だけを [プロジェクトの前提](../project-context.md) に書く。
- このリポジトリのインフラやアプリの中身(`infra/`、`backend/` のコード)と ADR は zip に入れない。技術選定はプロジェクトの判断なので、利用先は自分の ADR を最初の番号から書く。ハーネスが持つのは、想定する構成の説明(下)と置き場所の約束まで。
- **zip に入れるものは、このリポジトリに置いていくものを参照しない。** 置いていくもの(ADR、アプリとインフラのコード、プロジェクトの文書)へのリンクや ADR の番号を書かず、それだけで読めるようにする。ハーネスの判断(なぜそうしたか、捨てた案)は、このリポジトリの ADR に今までどおり積む。配る文書には、理由を 1〜2 文で書く。`mise run harness:files`(`check` に含む)がリンクと ADR の番号を検出する。
- ハーネスにファイルを足したり、改名したり、消したりしたら、[harness-files.txt](files.txt) も直す。一覧のパスが実在するかは `mise run harness:files`(`check` に含む)が確かめる。

## ハーネスの立場

ハーネスは次の前提の上に作っている。これを外すと、ハーネスの一部を作り直すことになる。

| 前提 | どこが依存しているか | 外すとき |
| --- | --- | --- |
| アプリは Angular と Python で、Azure に載せる(下の「想定する構成」) | プランニングの観点(セキュリティ境界、構成・基盤)、テスト戦略のコードの分類と置き場所(`backend/`、`frontend/`)、レビューで疑う場所(`infra/`、`*.bicep`) | 観点とテスト戦略の具体名を書き直す。違いが小さければ、プロジェクトの前提の「想定する構成と違う点」に書くだけでよい |
| テストは pytest で書く | テスト ID の書き方(`pytest.param` の id、docstring)、仕様一覧と計画の照合(aidd_spec の pytest プラグイン) | 他のテストランナーの分だけ、仕様の収集(`spec-collect`)を足す。照合と ID の検査は収集結果の JSON を読むだけなので、そのまま使える |
| タスクは mise で動かす | すべての入口(`check`、`pr`、`docs:spec` など)、CI | 作り直しになる |
| VCS は GitHub か Azure DevOps | `push` / `pr` / `pr-view`(`AIDD_VCS_PROVIDER` で切り替え。[PR 操作の切り替え](../vcs-provider.md))、PR テンプレートの置き場所、CI の定義 | `scripts/lib/vcs.sh` に操作先を足す |
| 文書と skill は日本語 | すべての文書、skill の質問、テスト名の規約 | 翻訳になる。テスト名を日本語で書く規約([テスト戦略](../testing-strategy.md))も見直す |
| AI のエージェントは Claude Code | skill の置き場所(`.claude/skills/`)、約束を読み込む `CLAUDE.md` | skill と約束の中身は Markdown なので、他のエージェントの置き場所(`AGENTS.md` など)から読み込めば使える |

## 想定する構成

skill の観点、テスト戦略、レビューの観点は、次の構成を前提に具体名で書いている。プロジェクトがこれと違うときは、[プロジェクトの前提](../project-context.md) の「想定する構成と違う点」に書く。
これはハーネスが想定する形の説明で、採用するかはプロジェクトが決める(プロジェクトの技術選定の ADR に書く)。

- フロントエンドは Angular、バックエンドは Python。ドメインのロジックはバックエンドに置く(`backend/src/app/domain/`)。
- 両方を 1 つのコンテナイメージにまとめ、Azure App Service で動かす。待ち受けのポートは 1 つ。
- API は `/api` の下、それ以外は Angular の静的ファイルを返し、未知のパスは `index.html` を返す。Angular は API を相対パスで呼ぶ。
- インターネットから届く口は Azure Front Door だけ。アプリへの直接のアクセスは Azure Policy で拒否する。
- シークレットは Key Vault に置き、マネージド ID で読む。インフラは Bicep で書く(`infra/`)。

## ハーネスとプロジェクトの接点

ハーネスが、プロジェクトのコンポーネント(`backend/` など)に求める約束。コンポーネントを足すときは、この約束を満たせばハーネスの検査に取り込まれる。

| 約束 | 内容 |
| --- | --- |
| 共通タスク名 | `setup` / `format` / `format-check` / `lint` / `typecheck` / `test` / `security`。該当するものだけ定義する。ルートの `check` が全コンポーネントから集める |
| `spec-collect` | テストを収集して、`AIDD_SPEC_OUT` に JSON を書く。pytest なら `PYTHONPATH` に `AIDD_TOOLS_SRC`(ルートの `mise.toml` が決める)を足し、`-p aidd_spec.pytest_plugin` で読み込む。`docs:spec`、`plan:verify`、`test:ids` が使う |
| `test-mutation` | ミューテーションテストを流す(任意)。`test:mutation` が使う |
| プロジェクトの前提 | [project-context.md](../project-context.md) に、何を作るかと、想定する構成と違う点を書く。違う点が無ければ「なし」と書く |

## 持ち出すとき

zip にまとめ、使う側のリポジトリの最初のコミットで取り込む。

```sh
mise run harness:pack            # aidd-harness-<コミット>.zip を作る
mise run harness:pack -o <file>  # 出力先を指定する
```

1. このリポジトリで `mise run harness:pack` を流す。中身は HEAD のコミットから取る(未コミットの変更は入らない)。
2. 使う側のリポジトリのルートで zip を展開し、`bash scripts/harness-init.sh` を流す。一覧の `init` のファイル(プロジェクトの前提の空の雛形、ルートの `mise.toml`)は、展開しても既存のファイルを上書きしないよう zip の `.harness-init/` に入っている。スクリプトは、置き場所に無いものだけを置く。もともと `mise.toml` があれば上書きせず、まとめ方を表示する。
3. スクリプトの案内に従って、プロジェクトの前提を書き、`mise run setup` と `mise run check` を流す。テストを持つコンポーネントがまだ無くても check は通る。
4. `HARNESS_VERSION` も一緒にコミットする。元にした版(コミット)と、置いたファイルと、入れたファイルの一覧がある。

取り込んだ後は、使う側ごとに中身が分かれていくのを受け入れる。こちらの改善を後から取り込むときは、`HARNESS_VERSION` の版と今の版の差分を見て手で取り込む。
それが重くなったら、更新を 3-way マージで取り込める [Copier](https://copier.readthedocs.io/) への切り替えを考える。この一覧はそのまま Copier のテンプレートの範囲に使える。
