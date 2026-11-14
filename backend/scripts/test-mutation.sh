#!/usr/bin/env bash
# ミューテーションテスト(mutmut)を実行する。mise run test:mutation から //backend:test-mutation として呼ばれる。
#
# AIDD_MUTATION_SCOPE=changed(既定): 既定ブランチとの差分で変更した src/ の Python ファイルだけを対象にする
# AIDD_MUTATION_SCOPE=all          : src/ 全体を対象にする
# 生き残ったミュータント(テストが検出できなかった実装の誤り)か、テストが 1 本も通らないコードがあれば終了コード 1
set -euo pipefail

scope="${AIDD_MUTATION_SCOPE:-changed}"
base_branch="${AIDD_BASE_BRANCH:-main}"

patterns=()
if [[ "$scope" == "changed" ]]; then
  git fetch --quiet origin "$base_branch" 2>/dev/null || true
  merge_base="$(git merge-base "origin/$base_branch" HEAD)"
  # コミット済みの差分に、まだコミットしていない変更と新規ファイルも加える
  mapfile -t files < <(
    {
      git diff --relative --name-only --diff-filter=AMR "$merge_base" -- src/
      git ls-files --others --exclude-standard -- src/
    } | grep '\.py$' | sort -u
  )
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "backend: 既定ブランチ($base_branch)から変更した src/ の Python ファイルはありません"
    exit 0
  fi
  for file in "${files[@]}"; do
    module="${file#src/}"
    module="${module%.py}"
    module="${module%/__init__}"
    module="${module//\//.}"
    # mutmut のミュータント名は「モジュール名.x_関数名__mutmut_番号」(メソッドは「モジュール名.xǁクラスǁ…」)
    patterns+=("$module.x*")
  done
  echo "backend: 対象 ${files[*]}"
else
  echo "backend: 対象 src/ 全体"
fi

rm -rf mutants
uv run --locked mutmut run "${patterns[@]}" >/dev/null
uv run --locked mutmut export-cicd-stats >/dev/null

status=0
uv run --locked python - <<'PY' || status=$?
import json
import sys
from pathlib import Path

stats = json.loads(Path("mutants/mutmut-cicd-stats.json").read_text())
print(
    f"ミュータント {stats['total']} 件: 検出 {stats['killed']} / 生存 {stats['survived']}"
    f" / テストなし {stats['no_tests']} / タイムアウト {stats['timeout']}"
)
sys.exit(1 if stats["survived"] or stats["no_tests"] else 0)
PY
if [[ $status -ne 0 ]]; then
  echo
  echo "テストが検出できなかったミュータント(backend で uv run mutmut show <名前> を実行すると差分を見られる):"
  uv run --locked mutmut results
fi
exit $status
