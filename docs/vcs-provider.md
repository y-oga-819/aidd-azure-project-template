# PR 操作の切り替え(GitHub / Azure DevOps)

`mise run push` / `mise run pr` / `mise run pr-view` は、操作先を環境変数 `AIDD_VCS_PROVIDER` で切り替える。

| 値 | 使う CLI | 状態 |
| --- | --- | --- |
| `github`(既定) | `gh`(mise が入れる) | 検証済み |
| `azure` | `az` + `azure-devops` 拡張(各自で入れる) | **未検証** |

`push` は git の操作なのでプロバイダに依存しない。違いが出るのは PR の作成と状況確認だけなので、抽象化はその 2 つに絞っている。

## Azure DevOps へ移行するとき

1. Azure CLI と拡張を入れてログインする

   ```sh
   az extension add --name azure-devops
   az login
   ```

2. `origin` を Azure Repos に向ける。`az repos` は `--detect true` で git remote から organization / project / repository を読む。
3. ルートの `mise.toml` の `AIDD_VCS_PROVIDER` の既定値を `azure` にする。
4. `azure-pipelines.yml` をパイプラインとして登録し、`main` のブランチポリシー「Build validation」に設定する(Azure Repos では YAML の `pr:` トリガーは効かない)。
5. PR テンプレートを Azure Repos の探索場所(`.azuredevops/pull_request_template.md` など)にも置くか、`mise run pr -b <file>` で本文を渡す。

## 未検証の項目

Azure DevOps 上では次をまだ一度も動かしていない。移行時に確認し、確認できたらこの一覧から消す。

- `az repos pr create --detect true` で remote から正しく組織・プロジェクトを検出できるか
- `--description` に複数行の本文を 1 引数で渡したときの改行の扱い
- `mise run pr-view` のポリシー一覧でパイプラインの結果が読めるか
- `azure-pipelines.yml` の mise インストールと `mise run ci` が Microsoft ホストエージェントで通るか
- `MISE_TRUSTED_CONFIG_PATHS` の指定で子ディレクトリの `mise.toml` が信頼されるか
