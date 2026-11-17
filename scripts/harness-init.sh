#!/usr/bin/env bash
# ハーネスを取り込んだリポジトリで、最初に 1 回流すセットアップ(docs/harness.md の「持ち出すとき」)。
#
# mise run harness:pack で作った zip は、利用先にもともとあるファイル(mise.toml など)を上書きしないよう、
# 利用先で用意するファイルを .harness-init/ の下に入れてある。このスクリプトはそれを置き場所へ移す。
#   - 置き場所にファイルが無い → 移す
#   - 既にある → 上書きせず .harness-init/ に残し、まとめ方を表示する
#
# 使い方: リポジトリのルートで  bash scripts/harness-init.sh
# mise を使わずに動く(mise.toml を置く前に流すため)。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
staging=".harness-init"

if [[ ! -d "$staging" ]]; then
  echo "$staging がありません。zip を展開した直後のリポジトリのルートで流してください" >&2
  exit 1
fi

placed=()
kept=()
while IFS= read -r -d '' src; do
  dest="${src#"$staging"/}"
  if [[ -e "$dest" ]]; then
    kept+=("$dest")
  else
    mkdir -p "$(dirname "$dest")"
    mv "$src" "$dest"
    placed+=("$dest")
  fi
done < <(find "$staging" -type f -print0 | sort -z)

# 移し終えた空のディレクトリを片付ける
find "$staging" -depth -type d -empty -delete

for f in "${placed[@]}"; do
  echo "置いた: $f"
done
for f in "${kept[@]}"; do
  echo "既にあるので上書きしなかった: $f"
  echo "  ハーネスの版は $staging/$f にある。diff -u $f $staging/$f を見て手でまとめ、終わったら $staging/$f を消す"
done

cat <<'E'

次にやること:
  1. docs/project-context.md の各見出しを、このプロジェクトに合わせて書く(skill が質問の仮の答えをここから作る)
  2. mise trust && mise install && mise run setup
  3. テストを持つコンポーネント(backend/ など)の mise.toml に spec-collect タスクを足す(docs/harness.md の「ハーネスとプロジェクトの接点」)
  4. mise run check が通ったら、HARNESS_VERSION と一緒にコミットする
E
if ((${#kept[@]})); then
  echo
  echo "まとめ終わるまで $staging/ はコミットしない" >&2
fi
