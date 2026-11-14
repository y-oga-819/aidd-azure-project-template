"""計画(docs/templates/plan.md)のテストケース一覧を読む。

「テストケース一覧」を含む見出しから、同じか上の階層の次の見出しまでを対象にする。
その中の表のうち、ヘッダーに「ID」がある表の各行を、計画のテストケースとして扱う。
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from aidd_spec.spec import ID_PATTERN

_HEADING = re.compile(r"^(?P<level>#{1,6})\s+(?P<title>.+?)\s*$")
_SECTION_TITLE = "テストケース一覧"


@dataclass(frozen=True)
class PlannedCase:
    test_id: str
    name: str
    state: str
    heading: str
    line: int
    values: dict[str, str] = field(default_factory=dict)

    @property
    def deleted(self) -> bool:
        return "削除" in self.state


def _cells(line: str) -> list[str]:
    body = line.strip().removeprefix("|").removesuffix("|")
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", body)]


def _is_separator(line: str) -> bool:
    return bool(re.fullmatch(r"\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?", line.strip()))


def _section(lines: list[str]) -> list[tuple[int, str]]:
    start_level: int | None = None
    section: list[tuple[int, str]] = []
    for number, line in enumerate(lines, start=1):
        heading = _HEADING.match(line)
        if heading:
            level = len(heading["level"])
            if start_level is None:
                if _SECTION_TITLE in heading["title"]:
                    start_level = level
                continue
            if level <= start_level:
                break
        if start_level is not None:
            section.append((number, line))
    return section


def parse(text: str) -> list[PlannedCase]:
    lines = text.splitlines()
    section = _section(lines)
    cases: list[PlannedCase] = []
    heading = ""
    header: list[str] | None = None
    for index, (number, line) in enumerate(section):
        match = _HEADING.match(line)
        if match:
            heading = match["title"]
            header = None
            continue
        if not line.strip().startswith("|"):
            header = None
            continue
        if header is None:
            following = section[index + 1][1] if index + 1 < len(section) else ""
            if _is_separator(following):
                header = _cells(line)
            continue
        if _is_separator(line):
            continue
        if "ID" not in header:
            continue
        row = dict(zip(header, _cells(line), strict=False))
        test_id = row.get("ID", "")
        if not ID_PATTERN.match(test_id):
            continue
        values = {
            k: v
            for k, v in row.items()
            if k not in {"ID", "テスト名", "状態"} and v not in {"", "-"}
        }
        cases.append(
            PlannedCase(
                test_id=test_id,
                name=row.get("テスト名", ""),
                state=row.get("状態", ""),
                heading=heading,
                line=number,
                values=values,
            )
        )
    return cases
