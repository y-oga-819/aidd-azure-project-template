# shellcheck shell=bash
# VCS 操作タスク(mise-tasks/push, pr, pr-view)の共通処理。
#
# 操作先は AIDD_VCS_PROVIDER で切り替える。
#   github: gh CLI(検証済み)
#   azure : az CLI + azure-devops 拡張(未検証。docs/vcs-provider.md を参照)
#
# push は git の操作なのでプロバイダに依存しない。違いが出るのは PR 操作だけ。

set -euo pipefail

vcs_provider() {
  local provider="${AIDD_VCS_PROVIDER:-github}"
  case "$provider" in
    github | azure) echo "$provider" ;;
    *)
      echo "AIDD_VCS_PROVIDER は github か azure を指定してください(現在: $provider)" >&2
      return 1
      ;;
  esac
}

vcs_base_branch() {
  echo "${AIDD_BASE_BRANCH:-main}"
}

vcs_current_branch() {
  git rev-parse --abbrev-ref HEAD
}

# ベースブランチや detached HEAD からの push / PR を止める
vcs_require_feature_branch() {
  local branch base
  branch="$(vcs_current_branch)"
  base="$(vcs_base_branch)"
  if [[ "$branch" == "HEAD" ]]; then
    echo "detached HEAD です。作業ブランチに切り替えてください" >&2
    return 1
  fi
  if [[ "$branch" == "$base" ]]; then
    echo "$base へ直接 push しないでください。作業ブランチを切ってください" >&2
    return 1
  fi
}

vcs_require_command() {
  local cmd="$1" hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd が見つかりません。$hint" >&2
    return 1
  fi
}
