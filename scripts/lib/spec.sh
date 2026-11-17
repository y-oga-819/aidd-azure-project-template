# shellcheck shell=bash
# 仕様一覧タスク(mise-tasks/docs/spec, plan/verify)の共通処理。
#
# 各コンポーネントが `spec-collect` タスク(テストを収集して AIDD_SPEC_OUT に JSON を書く)を持つ。
# ここではそれを全部呼び、収集結果のファイルを並べて返す。
# コンポーネントを足すときは、そのディレクトリの mise.toml に spec-collect を定義するだけでよい。

set -euo pipefail

# spec-collect タスクの名前を 1 行に 1 つ返す(無ければ何も返さない)
spec_collect_tasks() {
  mise tasks ls --all --json | python3 -c 'import json,sys; print("\n".join(t["name"] for t in json.load(sys.stdin) if t["name"].endswith(":spec-collect")))'
}

# 収集結果を書き出すディレクトリを作り、そのパスを返す
spec_collect_all() {
  local out_dir
  out_dir="$(mktemp -d)"
  local tasks
  tasks="$(spec_collect_tasks)"
  if [[ -z "$tasks" ]]; then
    echo "spec-collect タスクを持つコンポーネントがありません" >&2
    return 1
  fi
  local task component
  while IFS= read -r task; do
    component="${task#//}"
    component="${component%%:*}"
    AIDD_SPEC_OUT="$out_dir/$component.json" mise run --quiet "$task" >/dev/null
  done <<<"$tasks"
  echo "$out_dir"
}
