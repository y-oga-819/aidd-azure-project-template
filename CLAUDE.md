@docs/harness/agent-rules.md

## このリポジトリについて

- 何を作るか、想定する構成と違う点: `docs/project-context.md`
- 始め方とタスク: `README.md`
- このリポジトリはハーネスの元でもある。ハーネスのファイルを変えるときは `docs/harness/README.md` の「守ること」に従う。特に、zip に入れるものから ADR やアプリ・インフラのコードを参照しない(`mise run harness:files` が検出する)。
- インフラ(`infra/`)を変えるときは `infra/docs/azure-infra-guardrails.md` を先に読む。
