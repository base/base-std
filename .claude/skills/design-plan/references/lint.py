#!/usr/bin/env python3
"""Lint a design plan against the plan template v1.1.

Usage: python3 template/lint.py PLAN [--input INPUT] [--json]

The linter checks structure and internal consistency only; it never judges whether a
design is good. Each problem is reported as "§n RULE: message", where §0 means the
front matter or the document as a whole. With --input, the plan is also checked
against the case input: FLOW-n and CANT-n coverage, known IDs, and the FLOW items and
Motivation sentences that section 2 cites as requirement sources.

Exit codes: 0 lint-clean, 1 lint problems, 2 usage or file errors.
Standard library only.
"""

from __future__ import annotations

import argparse
import bisect
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# The input parser lives in the harness package; make it importable when this file is
# run directly from any working directory.
_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from harness.inputs import InputDocument, InputError, fence_step, load_input  # noqa: E402

# Upper bound on body words; a plan longer than this is padding, not precision.
MAX_WORDS = 4000

RULES = (
    "L-FM", "L-SEC", "L-COL", "L-TBD", "L-REQ-SOURCE", "L-COV-FLOW", "L-COV-CANT",
    "L-COV-GINV", "L-UNKNOWN-ID", "L-CHG-REF", "L-SURFACE", "L-TEST-NAME",
    "L-TEST-TRACE", "L-WORDS",
)

SECTIONS = (
    "1 Approach",
    "2 Requirement trace",
    "3 Changes",
    "4 User flows",
    "5 Hot-path cost",
    "6 Invariants",
    "7 Interactions",
    "8 Edge cases and test plan",
    "9 What this plan gives up",
    "10 Open questions",
)
SUBSECTIONS = ("Interface", "Storage", "Behavior", "Errors and events", "New surface")

# Table location -> exact header cells.
TABLES: dict[tuple[int, str | None], tuple[str, ...]] = {
    (2, None): ("Requirement", "Source", "Change IDs", "Acceptance tests"),
    (3, "Interface"): ("ID", "Signature", "New/Changed"),
    (3, "Storage"): ("ID", "Slot", "Field", "Type", "Status", "Mock = Rust"),
    (3, "Behavior"): ("ID", "Function", "Changes existing function (yes/no)", "Before", "After"),
    (3, "Errors and events"): ("ID", "Name", "Params", "Trigger"),
    (3, "New surface"): ("Kind", "Name", "Change IDs"),
    (4, None): (
        "Flow", "Steps (setup → call → state change → events → observable result)",
        "Change IDs", "Tests",
    ),
    (5, None): (
        "Function", "Cold reads", "Warm reads", "Writes", "External calls", "Δ cold",
        "Δ warm", "Δ writes", "Packed into a slot already read",
    ),
    (6, None): ("ID", "Status", "How it holds", "Change IDs", "Tests"),
    (8, None): ("Test", "Covers", "Setup and action", "Expected result"),
}
# Tables that may never be empty, because every plan has rows for them.
NONEMPTY_TABLES = {(2, None), (4, None), (5, None), (6, None), (8, None)}

# Typed cells: (table, column) -> allowed lowercase values.
ENUMS: dict[tuple[tuple[int, str | None], int], tuple[str, ...]] = {
    ((3, "Interface"), 2): ("new", "changed"),
    ((3, "Storage"), 4): ("new", "changed", "unchanged"),
    ((3, "Behavior"), 2): ("yes", "no"),
    ((6, None), 1): ("holds", "at risk"),
}

SURFACE_KINDS = ("external_functions", "roles", "storage_slots", "config_params", "errors", "events")
FM_SCALARS = ("plan_id", "perspective", "inputs_ref", "activation")
FM_KEYS = (*FM_SCALARS, "breaking", "surface")

CHANGE_PREFIX = {"Interface": ("IF",), "Storage": ("ST",), "Behavior": ("BEH",), "Errors and events": ("ERR", "EVT")}
CHANGE_ID_RE = re.compile(r"^(IF|ST|BEH|ERR|EVT)-([1-9]\d*)$")
CHANGE_SHAPE_RE = re.compile(r"^(IF|ST|BEH|ERR|EVT)-\d+$")
FLOW_RE = re.compile(r"^FLOW-([1-9]\d*)$")
CANT_RE = re.compile(r"^CANT-([1-9]\d*)$")
NEW_RE = re.compile(r"^NEW-([1-9]\d*)$")
GINV = "G-INV-1"
TEST_NAME_RE = re.compile(r"^test_[A-Za-z0-9]+_[A-Za-z0-9]+_[A-Za-z0-9]+(?:_[A-Za-z0-9]+)*$")
# Cells that state "nothing here" in reference columns.
EMPTY_SENTINELS = {"none", "—", "-", "n/a"}

_HEADING_RE = re.compile(r"^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")
_SEPARATOR_CELL_RE = re.compile(r"^:?-+:?$")
_TBD_RE = re.compile(r"\bTBD\b", re.IGNORECASE)
# A template placeholder: <text> not glued to a preceding word (so Vec<u8> is fine) and
# not padded with spaces (so "a < b and c > d" is fine). It may wrap across lines of one
# paragraph, but never across a blank line.
_PLACEHOLDER_RE = re.compile(
    r"(?<![\w<])<([^\s<>=]|[^\s<>=](?:[^<>\n]|\n(?![ \t]*(?:\n|$)))*[^\s<>=])>"
)
_QUOTES = (('"', '"'), ("“", "”"))
MOTIVATION_PREFIX = "Motivation:"
# Shortest normalized Motivation quote accepted as a requirement source.
MIN_QUOTE_CHARS = 20
SOURCE_SHAPE = 'requirement source must be FLOW-n references or Motivation: "<sentence>"'
_LIST_MARKER_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+")
# Characters that may close a sentence after its terminator: quotes, brackets, emphasis.
_SETEXT_RE = re.compile(r"^ {0,3}(?:=+|-+)[ \t]*$")
_TABLE_DELIMITER_RE = re.compile(r"^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)+\|?\s*$")
_SENTENCE_CLOSERS = "\"'”’)]*_"


@dataclass(frozen=True)
class Diagnostic:
    section: int
    rule: str
    message: str
    line: int | None = None

    def text(self) -> str:
        return f"§{self.section} {self.rule}: {self.message}"

    def as_dict(self) -> dict:
        return {"section": self.section, "rule": self.rule, "message": self.message, "line": self.line}


@dataclass
class Table:
    key: tuple[int, str | None]
    line: int
    header: list[str]
    rows: list[tuple[int, list[str]]] = field(default_factory=list)


@dataclass
class Region:
    """Lines under one heading, up to the next ## or ### heading."""

    section: int
    sub: str | None
    lines: list[tuple[int, str]] = field(default_factory=list)


class _Linter:
    def __init__(self, text: str, document: InputDocument | None) -> None:
        self.text = text
        self.doc = document
        self.diags: list[Diagnostic] = []
        self.lines = text.splitlines()
        self.body_start = 0  # index of the first body line
        self.front: dict | None = None
        self.tables: dict[tuple[int, str | None], Table] = {}
        self.section_lines: dict[int, int] = {}

    def add(self, section: int, rule: str, message: str, line: int | None = None) -> None:
        self.diags.append(Diagnostic(section, rule, message, line))

    # ---- parsing -------------------------------------------------------------------

    def parse_front_matter(self) -> None:
        lines = self.lines
        if not lines or lines[0].rstrip() != "---":
            self.add(0, "L-FM", "plan does not start with a '---' front matter block", 1)
            return
        end = next((i for i in range(1, len(lines)) if lines[i].rstrip() == "---"), None)
        if end is None:
            self.add(0, "L-FM", "front matter is not closed with '---'", 1)
            return
        self.body_start = end + 1
        values: dict = {}
        surface: dict[str, int] | None = None
        surface_open = False  # indented count lines belong to the surface key just above
        attempted: set[str] = set()  # keys present, valid or not, so missing reports stay precise
        ok = True

        def fail(message: str, index: int) -> None:
            nonlocal ok
            ok = False
            self.add(0, "L-FM", message, index + 1)

        for index in range(1, end):
            raw = lines[index]
            if not raw.strip():
                continue
            if "\t" in raw:
                fail("tabs are not allowed in front matter", index)
                continue
            nested = raw.startswith(" ")
            match = re.match(r"^( *)([A-Za-z_][A-Za-z0-9_]*):(?:[ ]+(.*?))?[ ]*$", raw)
            if not match:
                fail(f"unsupported front matter line: {raw.strip()!r}", index)
                continue
            indent, key, value = len(match.group(1)), match.group(2), match.group(3)
            attempted.add(("surface." if nested else "") + key)
            if nested:
                if not surface_open or surface is None or indent != 2:
                    fail(f"unexpected indentation for '{key}'", index)
                    continue
                if key not in SURFACE_KINDS:
                    fail(f"unknown surface key '{key}'", index)
                    continue
                if key in surface:
                    fail(f"duplicate surface key '{key}'", index)
                    continue
                if value is None or not re.fullmatch(r"\d+", value):
                    fail(f"surface.{key} must be a nonnegative integer", index)
                    continue
                surface[key] = int(value)
                continue
            surface_open = False
            if key not in FM_KEYS:
                fail(f"unknown front matter key '{key}'", index)
                continue
            if key in values:
                fail(f"duplicate front matter key '{key}'", index)
                continue
            if key == "surface":
                if value:
                    fail("surface must be a mapping of counts on indented lines", index)
                    continue
                surface = {}
                surface_open = True
                values[key] = surface
                continue
            if value is None or value == "":
                fail(f"'{key}' has no value", index)
                continue
            if key == "breaking":
                if value not in ("true", "false"):
                    fail("breaking must be true or false", index)
                    continue
                values[key] = value == "true"
                continue
            parsed = _scalar(value)
            if parsed is None:
                fail(f"'{key}' uses unsupported YAML syntax", index)
                continue
            if not parsed.strip():
                fail(f"'{key}' is empty", index)
                continue
            values[key] = parsed
        for key in FM_KEYS:
            if key not in values:
                ok = False
                if key in attempted:
                    continue
                self.add(0, "L-FM", f"missing front matter key '{key}'", 1)
        if isinstance(values.get("surface"), dict):
            for kind in SURFACE_KINDS:
                if kind not in values["surface"]:
                    ok = False
                    if "surface." + kind in attempted:
                        continue
                    self.add(0, "L-FM", f"missing surface count '{kind}'", 1)
        if ok:
            self.front = values

    def visible(self) -> tuple[list[tuple[int, str]], list[tuple[int, str]]]:
        """Body lines with HTML comments removed: (structural lines, all visible lines).

        Structural lines also drop fenced code, so headings and tables in examples do not
        count. All visible lines keep fenced content for placeholder and word checks.
        Comments and fences are tracked in source order: a fence inside a comment opens no
        code block, and comment markers inside fenced code are literal text.
        """
        body = self.lines[self.body_start:]
        structural: list[tuple[int, str]] = []
        visible: list[tuple[int, str]] = []
        in_comment = False
        fence: tuple[str, int] | None = None
        for offset, line in enumerate(body):
            number = self.body_start + offset + 1
            if not in_comment:
                role, fence = fence_step(fence, line)
                if role is not None:
                    visible.append((number, line))
                    continue
            kept, in_comment = _strip_comments(line, in_comment)
            visible.append((number, kept))
            structural.append((number, kept))
        return structural, visible

    def split_regions(self, structural: list[tuple[int, str]]) -> list[Region]:
        headings: list[tuple[int, int, str]] = []
        for number, line in structural:
            match = _HEADING_RE.match(line)
            if match:
                headings.append((number, len(match.group(1)), match.group(2).strip()))
        self.check_sections(headings)

        regions: list[Region] = []
        current: Region | None = None
        heading_at = {number: (level, title) for number, level, title in headings}
        seen_sections: set[int] = set()
        seen_subs: set[str] = set()
        for number, line in structural:
            if number in heading_at:
                level, title = heading_at[number]
                if level == 2:
                    current = None
                    if title in SECTIONS:
                        index = SECTIONS.index(title) + 1
                        if index not in seen_sections:
                            seen_sections.add(index)
                            self.section_lines[index] = number
                            current = Region(index, None)
                            regions.append(current)
                    continue
                if level == 3:
                    if current is not None and current.section == 3:
                        if title in SUBSECTIONS and title not in seen_subs:
                            seen_subs.add(title)
                            current = Region(3, title)
                            regions.append(current)
                        else:
                            current = Region(3, "?")
                    continue
                if level == 1:
                    current = None
                    continue
            if current is not None:
                current.lines.append((number, line))
        return regions

    def check_sections(self, headings: list[tuple[int, int, str]]) -> None:
        level2 = [(n, t) for n, lvl, t in headings if lvl == 2]
        titles = [t for _, t in level2]
        for number, title in level2:
            if title not in SECTIONS:
                self.add(0, "L-SEC", f"unexpected section heading '## {title}'", number)
        for index, title in enumerate(SECTIONS, start=1):
            count = titles.count(title)
            if count == 0:
                self.add(index, "L-SEC", f"missing section '## {title}'")
            elif count > 1:
                self.add(index, "L-SEC", f"section '## {title}' appears {count} times")
        known = [t for t in titles if t in SECTIONS]
        deduped = list(dict.fromkeys(known))
        if deduped != [t for t in SECTIONS if t in deduped]:
            self.add(0, "L-SEC", "sections are out of order")

        # Subsections of §3: between '## 3 Changes' and the next level-2 heading.
        in_three = False
        subs: list[tuple[int, str]] = []
        for number, level, title in headings:
            if level == 2:
                in_three = title == SECTIONS[2]
                continue
            if in_three and level == 3:
                subs.append((number, title))
        if SECTIONS[2] in titles:
            names = [t for _, t in subs]
            for number, title in subs:
                if title not in SUBSECTIONS:
                    self.add(3, "L-SEC", f"unexpected subsection '### {title}'", number)
            for title in SUBSECTIONS:
                count = names.count(title)
                if count == 0:
                    self.add(3, "L-SEC", f"missing subsection '### {title}'")
                elif count > 1:
                    self.add(3, "L-SEC", f"subsection '### {title}' appears {count} times")
            known_subs = list(dict.fromkeys(t for t in names if t in SUBSECTIONS))
            if known_subs != [t for t in SUBSECTIONS if t in known_subs]:
                self.add(3, "L-SEC", "subsections of §3 are out of order")

    def parse_tables(self, regions: list[Region]) -> None:
        for region in regions:
            key = (region.section, region.sub)
            if key not in TABLES:
                continue
            blocks = _table_blocks(region.lines)
            section = region.section
            if not blocks:
                self.add(section, "L-COL", f"{_where(key)} has no table")
                continue
            if len(blocks) > 1:
                self.add(section, "L-COL", f"{_where(key)} has more than one table", blocks[1][0][0])
            block = blocks[0]
            expected = TABLES[key]
            header_line, header_raw = block[0]
            header = [_decode(c) for c in _split_row(header_raw)]
            if tuple(header) != expected:
                self.add(section, "L-COL", f"{_where(key)} header is {header!r}, expected {list(expected)!r}", header_line)
                continue
            if len(block) < 2 or not _is_separator(_split_row(block[1][1]), len(expected)):
                self.add(section, "L-COL", f"{_where(key)} table has no valid separator row", header_line)
                continue
            table = Table(key, header_line, header)
            for number, raw in block[2:]:
                cells = _split_row(raw)
                if len(cells) != len(expected):
                    self.add(section, "L-COL", f"{_where(key)} row has {len(cells)} cells, expected {len(expected)}", number)
                    continue
                table.rows.append((number, cells))
            if not table.rows and len(block) == 2:
                after = [line for number, line in region.lines if number > block[-1][0] and line.strip()]
                if key in NONEMPTY_TABLES:
                    self.add(section, "L-COL", f"{_where(key)} table has no rows", header_line)
                elif not after or not after[0].strip().startswith("None:"):
                    self.add(section, "L-COL", f"{_where(key)} table is empty without a 'None:' reason", header_line)
            for (table_key, column), allowed in ENUMS.items():
                if table_key != key:
                    continue
                for number, cells in table.rows:
                    value = _plain(cells[column]).lower()
                    if key == (6, None) and _is_retired_row(cells[2]) and value == "retired":
                        continue
                    if value not in allowed:
                        self.add(section, "L-COL", f"{_where(key)} '{expected[column]}' is '{_plain(cells[column])}', expected one of {', '.join(allowed)}", number)
            self.tables[key] = table

    # ---- rules ----------------------------------------------------------------------

    def check_placeholders(self, visible: list[tuple[int, str]]) -> None:
        for index in range(0, self.body_start):
            self._scan_placeholders(0, index + 1, self.lines[index])
        starts = sorted((line, sec) for sec, line in self.section_lines.items())

        def section_of(number: int) -> int:
            section = 0
            for start, sec in starts:
                if number >= start:
                    section = sec
            return section

        for number, line in visible:
            if _TBD_RE.search(line):
                self.add(section_of(number), "L-TBD", f"line {number}: contains TBD", number)
        # Placeholders may wrap, so scan the visible body as one text and report the opening line.
        offsets: list[int] = []
        position = 0
        for _, line in visible:
            offsets.append(position)
            position += len(line) + 1
        text = "\n".join(line for _, line in visible)
        for match in _PLACEHOLDER_RE.finditer(text):
            number = visible[bisect.bisect_right(offsets, match.start()) - 1][0]
            shown = _short(_collapse(match.group(0)))
            self.add(section_of(number), "L-TBD", f"line {number}: unfilled placeholder '{shown}'", number)

    def _scan_placeholders(self, section: int, number: int, line: str) -> None:
        if _TBD_RE.search(line):
            self.add(section, "L-TBD", f"line {number}: contains TBD", number)
        for match in _PLACEHOLDER_RE.finditer(line):
            self.add(section, "L-TBD", f"line {number}: unfilled placeholder '{match.group(0)}'", number)

    def check_words(self, visible: list[tuple[int, str]]) -> None:
        count = sum(
            1 for _, line in visible for token in line.split() if any(ch.isalnum() for ch in token)
        )
        if count > MAX_WORDS:
            self.add(0, "L-WORDS", f"plan body has {count} words, maximum is {MAX_WORDS}")

    def collect_changes(self) -> dict[str, tuple[str, list[str]]]:
        """Return change ID -> (subsection, cells) for every §3 declaration."""
        declared: dict[str, tuple[str, list[str]]] = {}
        for sub, prefixes in CHANGE_PREFIX.items():
            table = self.tables.get((3, sub))
            if table is None:
                continue
            for number, cells in table.rows:
                change_id = _plain(cells[0])
                match = CHANGE_ID_RE.match(change_id)
                if not match or match.group(1) not in prefixes:
                    self.add(3, "L-CHG-REF", f"'{change_id}' is not a valid ID for ### {sub} (expected {' or '.join(p + '-n' for p in prefixes)})", number)
                    continue
                if change_id in declared:
                    self.add(3, "L-CHG-REF", f"duplicate change ID {change_id}", number)
                    continue
                declared[change_id] = (sub, cells)
        return declared

    def check_change_cell(self, section: int, number: int, cell: str, declared: dict, required: bool, what: str) -> list[str]:
        tokens = _tokens(cell)
        if tokens is None:
            if required:
                self.add(section, "L-CHG-REF", f"{what} cites no change IDs", number)
            return []
        good: list[str] = []
        for token in tokens:
            if not CHANGE_SHAPE_RE.match(token):
                self.add(section, "L-UNKNOWN-ID", f"{what} cites '{token}', which is not a change ID", number)
            elif not CHANGE_ID_RE.match(token):
                self.add(section, "L-UNKNOWN-ID", f"{what} cites non-canonical ID '{token}'", number)
            elif token not in declared:
                self.add(section, "L-CHG-REF", f"{what} cites {token}, which is not defined in §3", number)
            else:
                good.append(token)
        return good

    def check_tests_cell(self, section: int, number: int, cell: str, tests: dict, required: bool, what: str, row_id: str | None) -> None:
        tokens = _tokens(cell)
        if tokens is None:
            if required:
                self.add(section, "L-TEST-TRACE", f"{what} cites no tests", number)
            return
        for token in tokens:
            if not TEST_NAME_RE.match(token):
                self.add(section, "L-TEST-NAME", f"{what} cites '{token}', which does not follow test_{{function}}_{{outcome}}_{{variant}}", number)
                continue
            if token not in tests:
                self.add(section, "L-TEST-TRACE", f"{what} cites {token}, which is not defined in §8", number)
                continue
            if row_id is not None and row_id not in tests[token]:
                self.add(section, "L-TEST-TRACE", f"{what} cites {token}, whose Covers does not include {row_id}", number)

    def run(self) -> list[Diagnostic]:
        self.parse_front_matter()
        structural, visible = self.visible()
        regions = self.split_regions(structural)
        self.parse_tables(regions)
        self.check_placeholders(visible)
        self.check_words(visible)

        declared = self.collect_changes()
        flow_ids, cant_ids, retired = self.source_ids()
        new_ids = self.check_invariants(cant_ids, retired, declared)
        self.check_flows(flow_ids, retired, declared)
        tests = self.collect_tests(flow_ids, cant_ids, new_ids, declared)
        self.check_trace(declared, tests, flow_ids, retired)
        self.check_flow_and_invariant_tests(tests, retired)
        self.check_surface(declared)
        return self.diags

    def source_ids(self) -> tuple[list[str] | None, list[str] | None, set[str]]:
        """FLOW and CANT IDs from the input, or None without input. Also retired IDs."""
        if self.doc is None:
            return None, None, set()
        retired = {item.id for item in (*self.doc.flows, *self.doc.cants) if _is_retired_item(item.text)}
        return [i.id for i in self.doc.flows], [i.id for i in self.doc.cants], retired

    def check_flows(self, flow_ids: list[str] | None, retired: set[str], declared: dict) -> None:
        table = self.tables.get((4, None))
        if table is None:
            return
        seen: list[str] = []
        for number, cells in table.rows:
            row_id = _plain(cells[0])
            if not FLOW_RE.match(row_id):
                self.add(4, "L-COV-FLOW", f"'{row_id}' is not a FLOW-n ID", number)
                continue
            if row_id in seen:
                self.add(4, "L-COV-FLOW", f"duplicate row for {row_id}", number)
                continue
            seen.append(row_id)
            marked = _is_retired_row(cells[1])
            if flow_ids is not None:
                if row_id not in flow_ids:
                    self.add(4, "L-UNKNOWN-ID", f"{row_id} is not in the input", number)
                    continue
                if marked and row_id not in retired:
                    self.add(4, "L-COV-FLOW", f"{row_id} is active in the input but marked retired", number)
                if row_id in retired and not marked:
                    self.add(4, "L-COV-FLOW", f"{row_id} is retired in the input; write 'retired: ...' in Steps", number)
            is_retired = marked if flow_ids is None else row_id in retired
            self.check_change_cell(4, number, cells[2], declared, not is_retired, row_id)
        if flow_ids is not None:
            missing = [i for i in flow_ids if i not in seen]
            if missing:
                self.add(4, "L-COV-FLOW", f"missing rows for {', '.join(missing)}")
            present = [i for i in seen if i in flow_ids]
            if not missing and present != flow_ids:
                self.add(4, "L-COV-FLOW", "FLOW rows are not in input order")
        elif seen != sorted(seen, key=lambda s: int(s.split("-")[1])):
            self.add(4, "L-COV-FLOW", "FLOW rows are not in order")

    def check_invariants(self, cant_ids: list[str] | None, retired: set[str], declared: dict) -> set[str]:
        table = self.tables.get((6, None))
        if table is None:
            return set()
        cants: list[str] = []
        news: list[str] = []
        ginv_rows = 0
        phase = 0  # 0 CANT rows, 1 after G-INV-1
        for number, cells in table.rows:
            row_id = _plain(cells[0])
            marked = _is_retired_row(cells[2])
            if CANT_RE.match(row_id):
                if phase:
                    self.add(6, "L-COV-CANT", f"{row_id} comes after {GINV}; CANT rows come first", number)
                if row_id in cants:
                    self.add(6, "L-COV-CANT", f"duplicate row for {row_id}", number)
                    continue
                cants.append(row_id)
                if cant_ids is not None:
                    if row_id not in cant_ids:
                        self.add(6, "L-UNKNOWN-ID", f"{row_id} is not in the input", number)
                        continue
                    if marked and row_id not in retired:
                        self.add(6, "L-COV-CANT", f"{row_id} is active in the input but marked retired", number)
                    if row_id in retired and not marked:
                        self.add(6, "L-COV-CANT", f"{row_id} is retired in the input; write 'retired: ...' in How it holds", number)
            elif row_id == GINV:
                ginv_rows += 1
                if ginv_rows > 1:
                    self.add(6, "L-COV-GINV", f"duplicate row for {GINV}", number)
                phase = 1
                if marked:
                    self.add(6, "L-COV-GINV", f"{GINV} cannot be retired", number)
            elif NEW_RE.match(row_id):
                if not phase:
                    self.add(6, "L-COV-GINV", f"{row_id} comes before {GINV}; NEW rows come last", number)
                if row_id in news:
                    self.add(6, "L-UNKNOWN-ID", f"duplicate invariant ID {row_id}", number)
                    continue
                news.append(row_id)
            else:
                self.add(6, "L-UNKNOWN-ID", f"'{row_id}' is not a CANT-n, {GINV} or NEW-n ID", number)
                continue
            # Invariants may hold without any change touching them, so change IDs are optional.
            self.check_change_cell(6, number, cells[3], declared, False, row_id)
        if ginv_rows == 0:
            self.add(6, "L-COV-GINV", f"missing row for {GINV}")
        if cant_ids is not None:
            missing = [i for i in cant_ids if i not in cants]
            if missing:
                self.add(6, "L-COV-CANT", f"missing rows for {', '.join(missing)}")
            present = [i for i in cants if i in cant_ids]
            if not missing and present != cant_ids:
                self.add(6, "L-COV-CANT", "CANT rows are not in input order")
        elif cants != sorted(cants, key=lambda s: int(s.split("-")[1])):
            self.add(6, "L-COV-CANT", "CANT rows are not in order")
        return set(news)

    def collect_tests(self, flow_ids, cant_ids, new_ids: set[str], declared: dict) -> dict[str, set[str]]:
        table = self.tables.get((8, None))
        if table is None:
            return {}
        if flow_ids is None:
            flow_ids = self._local_ids((4, None), FLOW_RE)
        if cant_ids is None:
            cant_ids = self._local_ids((6, None), CANT_RE)
        known = set(flow_ids) | set(cant_ids) | new_ids | {GINV} | set(declared)
        tests: dict[str, set[str]] = {}
        for number, cells in table.rows:
            name = _plain(cells[0])
            if not TEST_NAME_RE.match(name):
                self.add(8, "L-TEST-NAME", f"'{name}' does not follow test_{{function}}_{{outcome}}_{{variant}}", number)
                continue
            if name in tests:
                self.add(8, "L-TEST-NAME", f"duplicate test {name}", number)
                continue
            covers = _tokens(cells[1]) or []
            if not covers:
                self.add(8, "L-TEST-TRACE", f"{name} has an empty Covers cell", number)
            for token in covers:
                if token not in known:
                    self.add(8, "L-UNKNOWN-ID", f"{name} covers unknown ID '{token}'", number)
            for column in (2, 3):
                if not _plain(cells[column]):
                    self.add(8, "L-TEST-TRACE", f"{name} has an empty '{TABLES[(8, None)][column]}' cell", number)
            tests[name] = set(covers)
        return tests

    def _local_ids(self, key, pattern) -> list[str]:
        table = self.tables.get(key)
        if table is None:
            return []
        return [_plain(c[0]) for _, c in table.rows if pattern.match(_plain(c[0]))]

    def check_trace(self, declared: dict, tests: dict, flow_ids: list[str] | None, retired: set[str]) -> None:
        table = self.tables.get((2, None))
        if table is None:
            return
        flows, retired_flows, where = self.citable_flows(flow_ids, retired)
        sentences = _motivation_sentences(self.doc.motivation) if self.doc is not None else None
        for number, cells in table.rows:
            statement = _decode(cells[0]).strip()
            if not statement or statement.lower() in EMPTY_SENTINELS:
                self.add(2, "L-REQ-SOURCE", "requirement statement is empty", number)
            problem = _source_problem(cells[1], flows, retired_flows, where, sentences)
            if problem is not None:
                self.add(2, "L-REQ-SOURCE", problem, number)
            self.check_change_cell(2, number, cells[2], declared, True, "requirement")
            self.check_tests_cell(2, number, cells[3], tests, True, "requirement", None)

    def citable_flows(self, flow_ids: list[str] | None, retired: set[str]) -> tuple[set[str] | None, set[str], str]:
        """FLOW IDs a requirement may cite, retired ones, and where they come from.

        The input is authoritative when given; otherwise §4 stands in for it. Without
        either, FLOW references are checked for form only.
        """
        if flow_ids is not None:
            return set(flow_ids), retired & set(flow_ids), "the input"
        table = self.tables.get((4, None))
        if table is None:
            return None, set(), "§4"
        flows: set[str] = set()
        marked: set[str] = set()
        for _, cells in table.rows:
            row_id = _plain(cells[0])
            if FLOW_RE.match(row_id):
                flows.add(row_id)
                if _is_retired_row(cells[1]):
                    marked.add(row_id)
        return flows, marked, "§4"

    def check_flow_and_invariant_tests(self, tests: dict, retired: set[str]) -> None:
        for key, section, text_col in (((4, None), 4, 1), ((6, None), 6, 2)):
            table = self.tables.get(key)
            if table is None:
                continue
            for number, cells in table.rows:
                row_id = _plain(cells[0])
                is_retired = row_id in retired if self.doc is not None else _is_retired_row(cells[text_col])
                self.check_tests_cell(section, number, cells[-1], tests, not is_retired, row_id, row_id)

    def check_surface(self, declared: dict) -> None:
        table = self.tables.get((3, "New surface"))
        if table is None:
            return
        counts = {kind: 0 for kind in SURFACE_KINDS}
        seen: set[tuple[str, str]] = set()
        # New IF ID -> external_functions rows citing it; each new function has exactly one row.
        cited_new_if: dict[str, list[int]] = {}
        for number, cells in table.rows:
            kind, name = _plain(cells[0]), _plain(cells[1])
            if kind not in SURFACE_KINDS:
                self.add(3, "L-SURFACE", f"unknown kind '{kind}' (expected one of {', '.join(SURFACE_KINDS)})", number)
                continue
            if not name:
                self.add(3, "L-SURFACE", f"{kind} row has no name", number)
                continue
            if (kind, name) in seen:
                self.add(3, "L-SURFACE", f"{kind} '{name}' is listed twice", number)
                continue
            seen.add((kind, name))
            counts[kind] += 1
            refs = self.check_change_cell(3, number, cells[2], declared, True, f"{kind} '{name}'")
            if not refs:
                continue
            new_ifs = [r for r in refs if r.startswith("IF-") and _plain(declared[r][1][2]).lower() == "new"]
            if kind == "external_functions":
                for change_id in new_ifs:
                    cited_new_if.setdefault(change_id, []).append(number)
                if len(new_ifs) > 1:
                    self.add(3, "L-SURFACE", f"{kind} '{name}' cites {len(new_ifs)} new IF rows ({', '.join(new_ifs)}); list one function per row", number)
            need = {
                "external_functions": (new_ifs, "a new IF row"),
                "errors": ([r for r in refs if r.startswith("ERR-")], "an ERR row"),
                "events": ([r for r in refs if r.startswith("EVT-")], "an EVT row"),
                "storage_slots": (
                    [r for r in refs if r.startswith("ST-") and _plain(declared[r][1][4]).lower() == "new"],
                    "a new ST row",
                ),
            }.get(kind)
            if need is not None and not need[0]:
                self.add(3, "L-SURFACE", f"{kind} '{name}' does not cite {need[1]}", number)
        for change_id, (sub, cells) in declared.items():
            if sub != "Interface" or _plain(cells[2]).lower() != "new":
                continue
            rows = cited_new_if.get(change_id, [])
            if not rows:
                self.add(3, "L-SURFACE", f"{change_id} is a new function but no external_functions row cites it")
            elif len(rows) > 1:
                self.add(3, "L-SURFACE", f"{change_id} is cited by {len(rows)} external_functions rows; expected one", rows[1])
        if self.front is not None:
            for kind in SURFACE_KINDS:
                claimed = self.front["surface"][kind]
                if claimed != counts[kind]:
                    self.add(3, "L-SURFACE", f"front matter surface.{kind} is {claimed} but §3 New surface lists {counts[kind]}")


# ---- helpers ----------------------------------------------------------------------------


def _scalar(value: str) -> str | None:
    """Parse a restricted YAML scalar: quoted, or plain text without YAML indicators."""
    if value[0] in "\"'":
        quote = value[0]
        if len(value) < 2 or value[-1] != quote:
            return None
        inner = value[1:-1]
        if quote == "'":
            if re.search(r"(?<!')'(?!')", inner.replace("''", "")):
                return None
            return inner.replace("''", "'")
        if re.search(r'(?<!\\)"', inner):
            return None
        return inner.replace('\\"', '"').replace("\\\\", "\\")
    if value[0] in "[]{}&*!|>%@`,#" or " #" in value or value.startswith("- "):
        return None
    # A colon followed by a space (or ending the value) starts a mapping, which a plain scalar cannot hold.
    if ": " in value or value.endswith(":"):
        return None
    return value


def _strip_comments(line: str, in_comment: bool) -> tuple[str, bool]:
    out = []
    i = 0
    while i < len(line):
        if in_comment:
            end = line.find("-->", i)
            if end < 0:
                return "".join(out), True
            i = end + 3
            in_comment = False
        else:
            start = line.find("<!--", i)
            if start < 0:
                out.append(line[i:])
                break
            out.append(line[i:start])
            i = start + 4
            in_comment = True
    return "".join(out), in_comment


def _table_blocks(lines: list[tuple[int, str]]) -> list[list[tuple[int, str]]]:
    blocks: list[list[tuple[int, str]]] = []
    current: list[tuple[int, str]] = []
    for number, line in lines:
        if line.strip().startswith("|"):
            current.append((number, line))
        elif current:
            blocks.append(current)
            current = []
    if current:
        blocks.append(current)
    return blocks


def _split_row(raw: str) -> list[str]:
    """Split a table row on unescaped pipes; a backslash escapes the next character."""
    text = raw.strip()
    cells: list[str] = []
    cell: list[str] = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            cell.append(text[i:i + 2])
            i += 2
            continue
        if ch == "|":
            cells.append("".join(cell))
            cell = []
        else:
            cell.append(ch)
        i += 1
    cells.append("".join(cell))
    if text.startswith("|"):
        cells = cells[1:]
    if text.endswith("|") and not text.endswith("\\|") and cells:
        cells = cells[:-1]
    return [c.strip() for c in cells]


def _decode(cell: str) -> str:
    return cell.replace("\\|", "|")


def _is_separator(cells: list[str], width: int) -> bool:
    return len(cells) == width and all(_SEPARATOR_CELL_RE.match(c) for c in cells)


def _plain(cell: str) -> str:
    """Cell text without surrounding backticks or emphasis."""
    value = _decode(cell).strip()
    while len(value) >= 2 and value[0] == value[-1] and value[0] in "`*_":
        value = value[1:-1].strip()
    return value


def _tokens(cell: str) -> list[str] | None:
    """IDs or test names in a reference cell; None when the cell states there are none."""
    value = _decode(cell).strip()
    if value.lower() in EMPTY_SENTINELS or not value:
        return None
    tokens = [t.strip("`*_ ") for t in re.split(r"[,;\s]+", value)]
    return [t for t in tokens if t] or None


def _is_retired_item(text: str) -> bool:
    """An input FLOW or CANT item is retired only by its terminal '(retired)' marker."""
    return text.rstrip().lower().endswith("(retired)")


def _is_retired_row(cell: str) -> bool:
    """A plan row marks an item retired only with an explicit 'retired:' prefix."""
    return _plain(cell).lower().startswith("retired:")


def _unquote(value: str) -> str | None:
    for left, right in _QUOTES:
        if len(value) >= 2 and value.startswith(left) and value.endswith(right):
            return value[len(left):-len(right)]
    return None


def _source_problem(
    cell: str, flows: set[str] | None, retired: set[str], where: str, sentences: set[str] | None
) -> str | None:
    """Return why a §2 Source cell is invalid, or None when it is valid.

    A source is either FLOW-n references or one Motivation sentence quoted in full,
    never both. `sentences` is the input's Motivation sentences, or None without input.
    """
    value = _decode(cell).strip()
    if value.startswith(MOTIVATION_PREFIX):
        return _motivation_problem(value[len(MOTIVATION_PREFIX):].strip(), sentences)
    tokens = _tokens(value)
    if tokens is None or not any(t.upper().startswith("FLOW") for t in tokens):
        return SOURCE_SHAPE
    for token in tokens:
        if not FLOW_RE.match(token):
            return f"requirement source contains invalid FLOW reference '{token}'"
    for token in tokens:
        if flows is None:
            continue
        if token not in flows:
            return f"requirement source cites {token}, which is not in {where}"
        if token in retired:
            return f"requirement source cites {token}, which is retired in {where}"
    return None


def _motivation_problem(rest: str, sentences: set[str] | None) -> str | None:
    quote = _unquote(rest)
    if quote is None:
        return "Motivation source must enclose one sentence in double quotation marks"
    text = _collapse(quote)
    if not text:
        return "Motivation source quote is empty"
    if len(text) < MIN_QUOTE_CHARS or not any(ch.isalnum() for ch in text):
        return f"Motivation source quote must contain at least {MIN_QUOTE_CHARS} normalized characters"
    if _sentences(text) != [(text, True)]:
        return "Motivation source quote must be one complete sentence"
    if sentences is not None and text not in sentences:
        return f"source quote is not a verbatim complete sentence from Motivation: \"{_short(text)}\""
    return None


def _motivation_sentences(motivation: str) -> set[str]:
    """Complete sentences of the Motivation prose, whitespace collapsed.

    Comments, fenced code, headings and tables are dropped; list markers are removed
    and each prose block or list item is joined across its wrapped lines.
    """
    blocks: list[list[str]] = []
    current: list[str] | None = None
    in_comment = False
    fence: tuple[str, int] | None = None
    lines = motivation.splitlines()
    in_table = False
    for index, line in enumerate(lines):
        if not in_comment:
            role, fence = fence_step(fence, line)
            if role is not None:
                current, in_table = None, False
                continue
        line, in_comment = _strip_comments(line, in_comment)
        stripped = line.strip()
        following = lines[index + 1] if index + 1 < len(lines) else ""
        if not stripped:
            current, in_table = None, False
            continue
        # A row followed by a delimiter row starts a table, which runs to the next blank line.
        if "|" in stripped and _TABLE_DELIMITER_RE.match(following):
            in_table = True
        if _SETEXT_RE.match(line):
            # An underline turns the paragraph above it into a heading (or is a thematic break).
            if current is not None and not in_table:
                blocks.pop()  # the current block is always the last one
            current = None
            continue
        if in_table or _HEADING_RE.match(line) or stripped.startswith("|"):
            current = None
            continue
        marker = _LIST_MARKER_RE.match(line)
        if marker or current is None:
            current = []
            blocks.append(current)
            if marker:
                stripped = line[marker.end():].strip()
        current.append(stripped)
    found: set[str] = set()
    for block in blocks:
        for sentence, complete in _sentences(_collapse(_decode(" ".join(block)))):
            if complete:
                found.add(sentence)
    return found


def _sentences(text: str) -> list[tuple[str, bool]]:
    """Split collapsed text into (sentence, complete) pairs.

    A sentence ends at '.', '!' or '?' (plus any closing quotes, brackets or emphasis)
    followed by whitespace or the end of the text. Terminators inside inline code do not
    count. A trailing piece without a terminator is returned as incomplete.
    """
    result: list[tuple[str, bool]] = []
    start = 0
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "`":
            run = len(text[i:]) - len(text[i:].lstrip("`"))
            # A code span closes only at a backtick run of exactly the opening length.
            close = re.compile(rf"(?<!`)`{{{run}}}(?!`)").search(text, i + run)
            i = close.end() if close else i + run
            continue
        if ch in ".!?":
            end = i + 1
            while end < n and text[end] in ".!?":
                end += 1
            while end < n and text[end] in _SENTENCE_CLOSERS:
                end += 1
            if end == n or text[end].isspace():
                result.append((text[start:end].strip(), True))
                start = end
            i = end
            continue
        i += 1
    tail = text[start:].strip()
    if tail:
        result.append((tail, False))
    return result


def _collapse(text: str) -> str:
    """Treat any whitespace run as one space, so a quote need not follow line wrapping."""
    return re.sub(r"\s+", " ", text).strip()


def _short(text: str, limit: int = 80) -> str:
    return text if len(text) <= limit else text[: limit - 3] + "..."


def _where(key: tuple[int, str | None]) -> str:
    section, sub = key
    return f"### {sub}" if sub else f"§{section}"


def lint_plan(text: str, input_document: InputDocument | None = None) -> list[Diagnostic]:
    """Lint plan text; returns diagnostics in document order of discovery (empty = clean)."""
    return _Linter(text, input_document).run()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="lint.py", description="Lint a design plan against the plan template v1.1."
    )
    parser.add_argument("plan", type=Path, help="plan Markdown file")
    parser.add_argument("--input", type=Path, help="case input.md to check sources and coverage against")
    parser.add_argument("--json", action="store_true", help="print a JSON report")
    args = parser.parse_args(argv)

    def fail(message: str) -> int:
        if args.json:
            print(json.dumps({"ok": False, "error": message, "diagnostics": []}, indent=2))
        else:
            print(f"error: {message}", file=sys.stderr)
        return 2

    try:
        text = args.plan.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return fail(f"cannot read {args.plan}: {exc}")
    document = None
    if args.input is not None:
        try:
            document = load_input(args.input)
        except InputError as exc:
            return fail(str(exc))
    diagnostics = lint_plan(text, document)
    if args.json:
        print(json.dumps({"ok": not diagnostics, "diagnostics": [d.as_dict() for d in diagnostics]}, indent=2))
    else:
        for diagnostic in diagnostics:
            print(diagnostic.text())
    return 1 if diagnostics else 0


if __name__ == "__main__":
    sys.exit(main())
