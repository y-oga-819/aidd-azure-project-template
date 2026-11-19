"""zip に入れるファイルが、このリポジトリに置いていくものを参照していないかを確かめる(mise run harness:files から呼ばれる)。

置いていくもの(ADR、アプリとインフラのコード、プロジェクトの文書)は持ち出した先に無いので、
参照するとリンクが切れるか、持ち出した先の同じ名前の別のものを指してしまう。

- Markdown のリンクの行き先が、リポジトリにあるのに zip に入らないファイルなら失敗にする
- ADR の番号(ADR- と 4 桁の数字)を書いていたら失敗にする。ADR は zip に入れないため

使い方: python3 harness_refs.py <zip に入るファイルの一覧> <利用先に置くファイルの一覧>
標準ライブラリだけで動く。
"""

from __future__ import annotations

import posixpath
import re
import subprocess
import sys

LINK = re.compile(r"\]\(([^)\s#]+)(?:#[^)\s]*)?\)")
ADR_ID = re.compile(r"\bADR-[0-9]{4}\b")


def main() -> int:
    keep_list, init_list = sys.argv[1:3]
    keeps = [line for line in open(keep_list, encoding="utf-8").read().splitlines() if line]
    inits = [line for line in open(init_list, encoding="utf-8").read().splitlines() if line]
    shipped = set(keeps) | set(inits)
    tracked = set(subprocess.run(["git", "ls-files"], check=True, capture_output=True, text=True).stdout.splitlines())

    def in_repo(path: str) -> bool:
        return path in tracked or any(t.startswith(path + "/") for t in tracked)

    def is_shipped(path: str) -> bool:
        return path in shipped or any(s.startswith(path + "/") for s in shipped)

    problems: list[str] = []
    for name in keeps:
        try:
            text = open(name, encoding="utf-8").read()
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            for m in ADR_ID.finditer(line):
                problems.append(f"{name}:{lineno}: ADR の番号を書いている: {m.group(0)}")
            if not name.endswith(".md"):
                continue
            for m in LINK.finditer(line):
                target = m.group(1)
                if re.match(r"^[a-z]+:", target) or target.startswith("/"):
                    continue
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                if in_repo(resolved) and not is_shipped(resolved):
                    problems.append(f"{name}:{lineno}: zip に入らないファイルへリンクしている: {target}")

    if problems:
        print("zip に入れるファイルが、このリポジトリに置いていくものを参照している。", file=sys.stderr)
        print("理由が要るなら文書の中に 1〜2 文で書き、リンクと ADR の番号は外す(docs/harness/README.md の「守ること」):", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
