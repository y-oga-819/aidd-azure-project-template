"""CLI。ルートの mise-tasks/docs/spec と mise-tasks/plan/verify から呼ばれる。

python -m aidd_spec render <収集結果.json>... [--format markdown|json]
python -m aidd_spec verify <計画.md> <収集結果.json>...
python -m aidd_spec check-ids <収集結果.json>...
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import sys
from pathlib import Path

from aidd_spec import ids, plan, render, spec, verify


def _render(args: argparse.Namespace) -> int:
    items = spec.filter_items(spec.load(args.collected), args.filter)
    if args.format == "json":
        print(json.dumps([dataclasses.asdict(i) for i in items], ensure_ascii=False, indent=2))
    else:
        print(render.render_markdown(items), end="")
    return 0


def _verify(args: argparse.Namespace) -> int:
    cases = plan.parse(args.plan.read_text(encoding="utf-8"))
    if not cases:
        print(f"{args.plan}: 「テストケース一覧」の見出しの下に、ID 列のある表が見つからない")
        return 1
    findings = verify.verify(cases, spec.load(args.collected))
    for finding in findings:
        mark = "✓" if finding.ok else "✗"
        print(f"{mark} {finding.message}  ({args.plan.name}:{finding.case.line})")
    failed = [f for f in findings if not f.ok]
    print(f"\n一致 {len(findings) - len(failed)} 件 / 不一致 {len(failed)} 件")
    return 1 if failed else 0


def _check_ids(args: argparse.Namespace) -> int:
    problems = ids.check(spec.load(args.collected))
    for problem in problems:
        print(f"✗ {problem.message}")
    if problems:
        print(
            f"\nテスト ID の問題が {len(problems)} 件ある。"
            "重複は、後からマージする側が計画・テスト・PR 概要の ID を振り直す"
        )
        return 1
    print("テスト ID に重複も書き漏れもない")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="aidd_spec")
    sub = parser.add_subparsers(required=True)

    p_render = sub.add_parser("render", help="仕様一覧を出力する")
    p_render.add_argument("collected", nargs="+", type=Path)
    p_render.add_argument("--format", choices=["markdown", "json"], default="markdown")
    p_render.add_argument(
        "--filter",
        default="",
        help="テストのパスかテスト ID に、この文字列を含むものだけを出す(例: pricing、SHIPPING)",
    )
    p_render.set_defaults(func=_render)

    p_verify = sub.add_parser("verify", help="計画のテストケース一覧とテストを照合する")
    p_verify.add_argument("plan", type=Path)
    p_verify.add_argument("collected", nargs="+", type=Path)
    p_verify.set_defaults(func=_verify)

    p_ids = sub.add_parser("check-ids", help="テスト ID の重複と書き漏れを検出する")
    p_ids.add_argument("collected", nargs="+", type=Path)
    p_ids.set_defaults(func=_check_ids)

    args = parser.parse_args(argv)
    code: int = args.func(args)
    return code


if __name__ == "__main__":
    sys.exit(main())
