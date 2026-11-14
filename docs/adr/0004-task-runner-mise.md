# ADR-0004: タスクランナーと CI の入口に mise を採用する

- 状態: 提案(2026-11-14)
- 関連: [ルートの mise.toml](../../mise.toml)、[vcs-provider.md](../vcs-provider.md)

## 背景(なぜ決める必要があるか)

このリポジトリは、AI がコードの大半を書く前提で開発する。人間は「なぜ」と「受け入れ条件」を守り、コードの細部は AI と機械検証に任せる。
そのためには次が必要になる。

1. **人・AI エージェント・CI が同じコマンドで同じ検査を回せること。** AI が CI と同じ検査を手元で流してから PR を出せれば、レビュアーは機械が見られない部分に集中できる。
2. **言語ごとのツール(Python、Node/Angular、Bicep など)のバージョンを全員と CI で揃えること。**
3. **CI と PR 操作を、GitHub から Azure DevOps へ移しても書き換えが小さいこと。** 検証は GitHub と GitHub Actions で行い、将来 Azure DevOps へ移る前提でいる。
4. **並行作業でルートの設定が衝突しないこと。** backend / frontend / infra を別々のスレッドや人が同時に進める。

## 選択肢

| 案 | ツールのバージョン固定 | タスク定義 | 評価 |
| --- | --- | --- | --- |
| **A. mise(採用)** | できる(Python、uv、Node、gh、gitleaks など) | できる。モノレポ機能で各ディレクトリのタスクを `//...:lint` のように集約できる | 1 ツールで 1〜4 を満たす。新しめの機能に依存する |
| B. Makefile + 各言語のバージョン管理(pyenv、nvm など) | ツールごとに別の仕組み | Make | どこにでもある。ただし Windows での扱いにくさと、ツール固定が分散する |
| C. Task(go-task)/ just + asdf | asdf | Task / just | A に近いが 2 ツールになる。モノレポの集約は自前で書く |
| D. devcontainer / Nix | コンテナ・Nix で固定 | 別途必要 | 再現性は最も高い。CI と手元の両方で重く、学習コストも高い |
| E. CI 定義に直接書く | CI のセットアップ action | CI の YAML | 手元で同じ検査を回せず、Azure DevOps への移行で全面的に書き換えになる |

## 決定

**mise を採用し、タスク定義とツールのバージョン固定の両方を mise に寄せる。** CI の定義(GitHub Actions / Azure Pipelines)は `mise run ci` を呼ぶだけにする。

あわせて、次の約束を置く。

- 各コンポーネントは自分のディレクトリに `mise.toml`([tools] と [tasks])を置く。ルートの `mise.toml` は共通ツールと集約タスクだけを持ち、コンポーネントを足すときに編集しない。
- 共通タスク名 `setup / format / format-check / lint / typecheck / test / security` は、ルートの `mise run check` が全コンポーネントから集めて CI で実行する。これらはクラウドの認証情報なしで通るものにする。デプロイなどは別の名前にする(例: `//infra:deploy`)。
- PR 操作は `mise run push / pr / pr-view` で包み、操作先を `AIDD_VCS_PROVIDER`(github | azure)で切り替える。push は git の操作なので分岐させず、PR の作成と状況確認だけを分岐する。

## 結果(この判断で受け入れること)

- **mise 2026.11 のモノレポ機能に依存する**(`min_version = "2026.11.0"`)。比較的新しい機能で、挙動が変わる可能性がある。mise のバージョンは CI で固定し、上げるときは `mise run ci` が通ることを確かめる。
- Windows ネイティブでの動作は確かめていない(WSL を前提とする)。
- az CLI は mise で管理しない(Azure DevOps へ移るときに各自で入れる)。
- Azure DevOps 側(`az repos`、`azure-pipelines.yml`)は未検証。項目は [vcs-provider.md](../vcs-provider.md) にある。

## 見直す条件

- モノレポ機能の破壊的変更が続き、固定したバージョンから上げられなくなったとき。
- 再現性の問題(手元では通るが CI で落ちる)が頻発し、devcontainer(案 D)の重さに見合うようになったとき。
