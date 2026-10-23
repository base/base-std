#!/usr/bin/env python3
"""Lint a design plan against the plan template v2.

Usage: python3 template/lint.py PLAN [--input INPUT] [--json]

The linter checks structure and internal consistency only; it never judges whether a
design is good. Each problem is reported as "§n RULE: message", where §0 means the
front matter or the document as a whole. With --input, the plan is also checked
against the case input: FLOW-n and CANT-n coverage, known IDs, and the FLOW items and
Motivation sentences that the requirement trace cites as sources.

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

# The input parser ships next to this file as plan_inputs.py when the linter is copied out on its own (a skill's
# references); inside this repository it comes from the harness package.
_HERE = Path(__file__).resolve().parent
if (_HERE / "plan_inputs.py").is_file():
    sys.path.insert(0, str(_HERE))
    from plan_inputs import InputDocument, InputError, fence_step, load_input  # noqa: E402
else:
    _REPO_ROOT = _HERE.parent
    if str(_REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(_REPO_ROOT))
    from harness.inputs import InputDocument, InputError, fence_step, load_input  # noqa: E402

TEMPLATE_VERSION = "v2"
TITLE = f"Design plan (template {TEMPLATE_VERSION})"
# The level-1 heading that separates the readable part from the reference part.
REFERENCE_HEADING = "Reference"

# Upper bound on body words; a plan longer than this is padding, not precision.
MAX_WORDS = 3500
# Largest table body allowed in the readable part (the Storage layout table is exempt).
MAX_READABLE_TABLE_ROWS = 6

RULES = (
    "L-FM", "L-SEC", "L-COL", "L-TBD", "L-IFACE", "L-BEH", "L-STEPS", "L-TABLE-SIZE",
    "L-REQ-SOURCE", "L-COV-FLOW", "L-COV-CANT", "L-COV-GINV", "L-UNKNOWN-ID", "L-CHG-REF",
    "L-SURFACE", "L-WORDS",
)

SECTIONS = (
    "1 Approach",
    "2 Interface",
    "3 Changes",
    "4 User flows",
    "5 What this plan gives up",
    "6 Open questions",
    "7 Requirement trace",
    "8 New surface",
    "9 Hot-path cost",
    "10 Invariants",
    "11 Interactions",
)
READABLE_SECTIONS = frozenset(range(1, 7))
INTERFACE, CHANGES, FLOWS, TRACE, SURFACE, HOT_PATH, INVARIANTS = 2, 3, 4, 7, 8, 9, 10
STORAGE = "Storage"

# Table location -> exact header cells.
TABLES: dict[tuple[int, str | None], tuple[str, ...]] = {
    (CHANGES, STORAGE): ("ID", "Slot", "Field", "Type", "Status", "Mock = Rust"),
    (TRACE, None): ("Requirement", "Source", "Change IDs"),
    (SURFACE, None): ("Kind", "Name", "Change IDs"),
    (HOT_PATH, None): (
        "Function", "Cold reads", "Warm reads", "Writes", "External calls", "Δ cold",
        "Δ warm", "Δ writes", "Packed into a slot already read",
    ),
    (INVARIANTS, None): ("ID", "Status", "How it holds", "Change IDs"),
}
# Tables that may never be empty, because every plan has rows for them.
NONEMPTY_TABLES = {(TRACE, None), (HOT_PATH, None), (INVARIANTS, None)}

# Typed cells: (table, column) -> allowed lowercase values.
ENUMS: dict[tuple[tuple[int, str | None], int], tuple[str, ...]] = {
    ((CHANGES, STORAGE), 4): ("new", "changed", "unchanged"),
    ((INVARIANTS, None), 1): ("holds", "at risk"),
}

SURFACE_KINDS = ("external_functions", "roles", "storage_slots", "config_params", "errors", "events")
# Surface kinds that must be declared in the §2 interface block, and the Solidity keyword that declares them.
DECLARED_KINDS = {"external_functions": "function", "errors": "error", "events": "event"}
FM_SCALARS = ("plan_id", "perspective", "inputs_ref", "activation")
FM_KEYS = (*FM_SCALARS, "breaking", "surface")

CHANGE_ID_RE = re.compile(r"^(ST|BEH)-([1-9]\d*)$")
CHANGE_SHAPE_RE = re.compile(r"^(ST|BEH)-\d+$")
FLOW_RE = re.compile(r"^FLOW-([1-9]\d*)$")
CANT_RE = re.compile(r"^CANT-([1-9]\d*)$")
NEW_RE = re.compile(r"^NEW-([1-9]\d*)$")
BEH_RE = re.compile(r"^BEH-([1-9]\d*)$")
GINV = "G-INV-1"
# Cells that state "nothing here" in reference columns.
EMPTY_SENTINELS = {"none", "—", "-", "n/a"}

# A subsection heading that carries its trace ID at the end: "Readable title (BEH-1)".
_TAGGED_HEADING_RE = re.compile(r"^(?P<title>\S.*?)[ \t]+\((?P<id>[A-Z][A-Z-]*-\d+)\)$")
# The first line of a behaviour change: the functions it touches and whether existing behaviour changes.
FUNCTIONS_RE = re.compile(
    r"^Functions?:[ \t]*(?P<names>\S.*);[ \t]*changes existing behaviour:[ \t]*(?P<flag>yes|no)\.?$",
    re.IGNORECASE,
)
FUNCTIONS_SHAPE = "Functions: `name`, `name`; changes existing behaviour: yes|no"
_STEP_RE = re.compile(r"^ {0,3}\d{1,9}[.)][ \t]+\S")
_DECLARATION_RE = re.compile(r"\b(function|error|event|struct|enum|type|modifier)[ \t]+([A-Za-z_][A-Za-z0-9_]*)")
_STATUS_RE = re.compile(r"\s*(new|changed)\b")
NO_INTERFACE_SENTINEL = "// No interface change."
_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
_IDENTIFIER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

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
_TABLE_DELIMITER_RE = re.compile(r"^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$")
# Lines that end a table body: a heading, block quote, fence, HTML block, list item or thematic break.
_BLOCK_START_RE = re.compile(r"^ {0,3}(?:#{1,6}(?:[ \t]|$)|>|```|~~~|<|[-*+][ \t]|\d{1,9}[.)][ \t]|(?:[-*_][ \t]*){3,}$)")
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
    """Lines under one heading, up to the next ## heading or the next subsection heading.

    `sub` is None for a section body, "Storage" for the §3 storage subsection, the trace ID
    for a tagged subsection (BEH-n in §3, FLOW-n in §4), or "?" for any other subsection there.
    """

    section: int
    sub: str | None
    lines: list[tuple[int, str]] = field(default_factory=list)
    heading_line: int | None = None
    title: str | None = None


@dataclass(frozen=True)
class Change:
    """One §3 behaviour change: its heading, the functions it names and whether it changes existing behaviour."""

    id: str
    title: str
    line: int
    functions: str | None  # raw names after "Functions:", or None when the line is missing or malformed
    changes_existing: bool | None


def function_names(raw: str) -> list[str]:
    """Names in a Functions line: comma-separated, parenthesized remarks dropped, code marks stripped."""
    label = raw
    while re.search(r"\([^()]*\)", label):
        label = re.sub(r"\([^()]*\)", " ", label)
    return [part.strip().strip("`*").strip() for part in label.split(",") if part.strip()]


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
        self.changes: dict[str, Change] = {}
        # Names declared in the §2 Solidity block by keyword, or None when there is no single block.
        self.interface: dict[str, set[str]] | None = None
        # The subset of those names marked `// new`, by keyword.
        self.new_interface: dict[str, set[str]] = {}

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
        count. All visible lines keep fenced content for placeholder, word and interface checks.
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
        seen_subs: set[tuple[int, str]] = set()
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
                            current = Region(index, None, heading_line=number, title=title)
                            regions.append(current)
                    continue
                if level == 3 and current is not None and current.section in (CHANGES, FLOWS):
                    section = current.section
                    sub = _subsection_key(section, title)
                    if sub != "?" and (section, sub) in seen_subs:
                        sub = "?"
                    seen_subs.add((section, sub))
                    tagged = _TAGGED_HEADING_RE.match(title)
                    current = Region(section, sub, heading_line=number,
                                     title=tagged.group("title") if tagged else title)
                    regions.append(current)
                    continue
                if level == 1:
                    current = None
                    continue
                if level == 3:
                    continue  # explanatory subheadings elsewhere stay in their section
            if current is not None:
                current.lines.append((number, line))
        return regions

    def check_sections(self, headings: list[tuple[int, int, str]]) -> None:
        opening = headings[0] if headings else None
        if opening is None or opening[1] != 1 or opening[2] != TITLE:
            self.add(0, "L-SEC", f"the plan must open with the heading '# {TITLE}'", opening[0] if opening else None)
        level1 = [(n, t) for n, lvl, t in headings if lvl == 1]
        for number, title in level1:
            if title != REFERENCE_HEADING and not (opening is not None and number == opening[0]):
                self.add(0, "L-SEC", f"unexpected heading '# {title}'", number)
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

        # The reference part starts with '# Reference', between the last readable and the first reference section.
        references = [n for n, t in level1 if t == REFERENCE_HEADING]
        if len(references) != 1:
            self.add(0, "L-SEC", f"expected one '# {REFERENCE_HEADING}' heading before '## {SECTIONS[TRACE - 1]}', "
                                 f"found {len(references)}")
        else:
            first = {t: n for n, t in reversed(level2)}
            before, after = first.get(SECTIONS[TRACE - 2]), first.get(SECTIONS[TRACE - 1])
            if (before is not None and references[0] < before) or (after is not None and references[0] > after):
                self.add(0, "L-SEC", f"'# {REFERENCE_HEADING}' must sit between '## {SECTIONS[TRACE - 2]}' and "
                                     f"'## {SECTIONS[TRACE - 1]}'", references[0])

        subs: dict[int, list[tuple[int, str]]] = {CHANGES: [], FLOWS: []}
        section = None
        for number, level, title in headings:
            if level <= 2:
                section = SECTIONS.index(title) + 1 if level == 2 and title in SECTIONS else None
                continue
            if level == 3 and section in subs:
                subs[section].append((number, title))
        seen_flows: set[str] = set()
        for number, title in subs[FLOWS]:
            key = _subsection_key(FLOWS, title)
            if key == "?":
                self.add(FLOWS, "L-SEC", f"unexpected subsection '### {title}' (expected 'Title (FLOW-n)')", number)
            elif key in seen_flows:
                self.add(FLOWS, "L-COV-FLOW", f"duplicate subsection for {key}", number)
            seen_flows.add(key)
        if SECTIONS[CHANGES - 1] not in titles:
            return
        keys = [(_subsection_key(CHANGES, t), n, t) for n, t in subs[CHANGES]]
        seen_changes: set[str] = set()
        for key, number, title in keys:
            if key == "?":
                self.add(CHANGES, "L-SEC", f"unexpected subsection '### {title}' (expected 'Title (BEH-n)' or "
                                           f"'{STORAGE}')", number)
            elif key != STORAGE and key in seen_changes:
                self.add(CHANGES, "L-CHG-REF", f"duplicate change ID {key}", number)
            seen_changes.add(key)
        storage = [n for key, n, _ in keys if key == STORAGE]
        if not storage:
            self.add(CHANGES, "L-SEC", f"missing subsection '### {STORAGE}'")
        elif len(storage) > 1:
            self.add(CHANGES, "L-SEC", f"subsection '### {STORAGE}' appears {len(storage)} times")
        elif keys[-1][0] != STORAGE:
            self.add(CHANGES, "L-SEC", f"'### {STORAGE}' must be the last subsection of §3", storage[0])
        if not any(BEH_RE.match(key) for key, _, _ in keys):
            self.add(CHANGES, "L-SEC", "§3 has no behaviour change subsection 'Title (BEH-n)'")

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
                    if key == (INVARIANTS, None) and _is_retired_row(cells[2]) and value == "retired":
                        continue
                    if value not in allowed:
                        self.add(section, "L-COL", f"{_where(key)} '{expected[column]}' is '{_plain(cells[column])}', expected one of {', '.join(allowed)}", number)
            self.tables[key] = table

    # ---- rules ----------------------------------------------------------------------

    def check_placeholders(self, visible: list[tuple[int, str]]) -> None:
        for index in range(0, self.body_start):
            self._scan_placeholders(0, index + 1, self.lines[index])

        for number, line in visible:
            if _TBD_RE.search(line):
                self.add(self.section_of(number), "L-TBD", f"line {number}: contains TBD", number)
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
            self.add(self.section_of(number), "L-TBD", f"line {number}: unfilled placeholder '{shown}'", number)

    def section_of(self, number: int) -> int:
        section = 0
        for sec, start in sorted(self.section_lines.items(), key=lambda item: item[1]):
            if number >= start:
                section = sec
        return section

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

    def check_interface(self, visible: list[tuple[int, str]]) -> None:
        """§2 holds exactly one nonempty ```solidity block; record the names it declares."""
        start = self.section_lines.get(INTERFACE)
        if start is None:
            return
        end = min((n for n in self.section_lines.values() if n > start), default=len(self.lines) + 1)
        blocks: list[tuple[int, list[str]]] = []
        current: list[str] | None = None
        fence: tuple[str, int] | None = None
        for number, line in visible:
            if not start < number < end:
                continue
            role, fence = fence_step(fence, line)
            if role == "delim":
                if fence is not None:  # an opening delimiter
                    info = line.strip().lstrip(line.strip()[0]).strip().split()
                    current = [] if info and info[0].lower() == "solidity" else None
                    if current is not None:
                        blocks.append((number, current))
                else:
                    current = None
            elif role == "inside" and current is not None:
                current.append(line)
        if not blocks:
            self.add(INTERFACE, "L-IFACE", "§2 has no ```solidity block; write the interface as Solidity", start)
            return
        if len(blocks) > 1:
            self.add(INTERFACE, "L-IFACE", f"§2 has {len(blocks)} ```solidity blocks; put the whole interface in one",
                     blocks[1][0])
            return
        number, body = blocks[0]
        if not any(line.strip() for line in body):
            self.add(INTERFACE, "L-IFACE", "the §2 solidity block is empty", number)
            return
        # Blank out block comments but keep line breaks, so every declaration keeps its own line.
        code = _BLOCK_COMMENT_RE.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), "\n".join(body))
        declared: dict[str, set[str]] = {}
        new: dict[str, set[str]] = {}
        sentinel = False
        for offset, line in enumerate(code.splitlines(), start=number + 1):
            source, _, comment = line.partition("//")
            if line.strip() == NO_INTERFACE_SENTINEL:
                sentinel = True
                continue
            found = _DECLARATION_RE.findall(source)
            if not found:
                continue
            status = _STATUS_RE.match(comment.lstrip("/"))
            for keyword, name in found:
                declared.setdefault(keyword, set()).add(name)
                if status is None:
                    self.add(INTERFACE, "L-IFACE", f"{keyword} '{name}' has no trailing '// new' or '// changed' "
                                                   "comment on its declaration line", offset)
                elif status.group(1) == "new":
                    new.setdefault(keyword, set()).add(name)
        if sentinel and declared:
            self.add(INTERFACE, "L-IFACE", f"'{NO_INTERFACE_SENTINEL}' cannot sit beside declarations", number)
        elif sentinel and any(line.strip() and line.strip() != NO_INTERFACE_SENTINEL for line in body):
            self.add(INTERFACE, "L-IFACE", f"a block with '{NO_INTERFACE_SENTINEL}' holds nothing else; put the "
                                           "explanation in prose after the block", number)
        elif not sentinel and not declared:
            self.add(INTERFACE, "L-IFACE", "the §2 solidity block declares nothing; declare the new or changed "
                                           f"interface, or write only '{NO_INTERFACE_SENTINEL}'", number)
        self.interface = declared
        self.new_interface = new

    def check_readable_tables(self, regions: list[Region]) -> None:
        """Tables in the readable part stay small; the Storage layout table is exempt."""
        for region in regions:
            if region.section not in READABLE_SECTIONS or (region.section, region.sub) == (CHANGES, STORAGE):
                continue
            for block in _table_blocks(region.lines):
                rows = len(block) - 2 if len(block) >= 2 and _is_table_start(block[0][1], block[1][1]) else len(block) - 1
                if rows > MAX_READABLE_TABLE_ROWS:
                    self.add(region.section, "L-TABLE-SIZE",
                             f"table has {rows} rows; the readable part allows at most {MAX_READABLE_TABLE_ROWS}, "
                             "so use code, steps or a diagram", block[0][0])

    def collect_changes(self, regions: list[Region]) -> dict[str, tuple[str, object]]:
        """Return change ID -> (kind, detail) for every §3 behaviour subsection and Storage row."""
        declared: dict[str, tuple[str, object]] = {}
        for region in regions:
            if region.section != CHANGES or region.sub is None or not BEH_RE.match(region.sub):
                continue
            declared[region.sub] = ("Behavior", region)
            self.changes[region.sub] = self._read_change(region)
        table = self.tables.get((CHANGES, STORAGE))
        for number, cells in table.rows if table is not None else []:
            change_id = _plain(cells[0])
            match = CHANGE_ID_RE.match(change_id)
            if not match or match.group(1) != "ST":
                self.add(CHANGES, "L-CHG-REF", f"'{change_id}' is not a valid ID for ### {STORAGE} (expected ST-n)", number)
                continue
            if change_id in declared:
                self.add(CHANGES, "L-CHG-REF", f"duplicate change ID {change_id}", number)
                continue
            declared[change_id] = ("Storage", cells)
        return declared

    def _read_change(self, region: Region) -> Change:
        lines = [(n, line.strip()) for n, line in region.lines if line.strip()]
        functions, changes_existing = None, None
        first = lines[0] if lines else (region.heading_line, "")
        match = FUNCTIONS_RE.match(first[1])
        if match:
            functions, changes_existing = match.group("names").strip(), match.group("flag").lower() == "yes"
            if not function_names(functions):
                functions = None
        if functions is None:
            self.add(CHANGES, "L-BEH", f"{region.sub} must start with the line '{FUNCTIONS_SHAPE}'", first[0])
        if not any(_STEP_RE.match(line) for _, line in region.lines):
            self.add(CHANGES, "L-STEPS", f"{region.sub} has no numbered steps", region.heading_line)
        return Change(region.sub, region.title or "", region.heading_line or 0, functions, changes_existing)

    def check_change_cell(self, section: int, number: int, cell: str, declared: dict, required: bool, what: str) -> list[str]:
        tokens = _tokens(cell)
        if tokens is None:
            if required:
                self.add(section, "L-CHG-REF", f"{what} cites no change IDs", number)
            return []
        good: list[str] = []
        for token in tokens:
            if not CHANGE_SHAPE_RE.match(token):
                self.add(section, "L-UNKNOWN-ID", f"{what} cites '{token}', which is not a change ID (BEH-n or ST-n)", number)
            elif not CHANGE_ID_RE.match(token):
                self.add(section, "L-UNKNOWN-ID", f"{what} cites non-canonical ID '{token}'", number)
            elif token not in declared:
                self.add(section, "L-CHG-REF", f"{what} cites {token}, which is not defined in §3", number)
            else:
                good.append(token)
        return good

    def run(self) -> list[Diagnostic]:
        self.parse_front_matter()
        structural, visible = self.visible()
        regions = self.split_regions(structural)
        self.parse_tables(regions)
        self.check_placeholders(visible)
        self.check_words(visible)
        self.check_interface(visible)
        self.check_readable_tables(regions)

        declared = self.collect_changes(regions)
        flow_ids, cant_ids, retired = self.source_ids()
        self.check_invariants(cant_ids, retired, declared)
        self.check_flows(regions, flow_ids, retired)
        self.check_trace(declared, regions, flow_ids, retired)
        self.check_surface(declared)
        return self.diags

    def source_ids(self) -> tuple[list[str] | None, list[str] | None, set[str]]:
        """FLOW and CANT IDs from the input, or None without input. Also retired IDs."""
        if self.doc is None:
            return None, None, set()
        retired = {item.id for item in (*self.doc.flows, *self.doc.cants) if _is_retired_item(item.text)}
        return [i.id for i in self.doc.flows], [i.id for i in self.doc.cants], retired

    def flow_regions(self, regions: list[Region]) -> list[Region]:
        return [r for r in regions if r.section == FLOWS and r.sub is not None and FLOW_RE.match(r.sub)]

    def check_flows(self, regions: list[Region], flow_ids: list[str] | None, retired: set[str]) -> None:
        if FLOWS not in self.section_lines:
            return
        seen: list[str] = []
        for region in self.flow_regions(regions):
            row_id, number = region.sub, region.heading_line
            seen.append(row_id)
            first = next((line for _, line in region.lines if line.strip()), "")
            marked = _is_retired_row(first)
            if flow_ids is not None:
                if row_id not in flow_ids:
                    self.add(FLOWS, "L-UNKNOWN-ID", f"{row_id} is not in the input", number)
                    continue
                if marked and row_id not in retired:
                    self.add(FLOWS, "L-COV-FLOW", f"{row_id} is active in the input but marked retired", number)
                if row_id in retired and not marked:
                    self.add(FLOWS, "L-COV-FLOW", f"{row_id} is retired in the input; start its subsection with "
                                                  "'retired: ...'", number)
            is_retired = marked if flow_ids is None else row_id in retired
            if not is_retired and not any(_STEP_RE.match(line) for _, line in region.lines):
                self.add(FLOWS, "L-STEPS", f"{row_id} has no numbered steps", number)
        if flow_ids is not None:
            missing = [i for i in flow_ids if i not in seen]
            if missing:
                self.add(FLOWS, "L-COV-FLOW", f"missing subsections for {', '.join(missing)}")
            present = [i for i in seen if i in flow_ids]
            if not missing and present != flow_ids:
                self.add(FLOWS, "L-COV-FLOW", "FLOW subsections are not in input order")
        elif not seen:
            self.add(FLOWS, "L-COV-FLOW", "§4 has no 'Title (FLOW-n)' subsections")
        elif seen != sorted(seen, key=lambda s: int(s.split("-")[1])):
            self.add(FLOWS, "L-COV-FLOW", "FLOW subsections are not in order")

    def check_invariants(self, cant_ids: list[str] | None, retired: set[str], declared: dict) -> set[str]:
        table = self.tables.get((INVARIANTS, None))
        if table is None:
            return set()
        section = INVARIANTS
        cants: list[str] = []
        news: list[str] = []
        ginv_rows = 0
        phase = 0  # 0 CANT rows, 1 after G-INV-1
        for number, cells in table.rows:
            row_id = _plain(cells[0])
            marked = _is_retired_row(cells[2])
            if CANT_RE.match(row_id):
                if phase:
                    self.add(section, "L-COV-CANT", f"{row_id} comes after {GINV}; CANT rows come first", number)
                if row_id in cants:
                    self.add(section, "L-COV-CANT", f"duplicate row for {row_id}", number)
                    continue
                cants.append(row_id)
                if cant_ids is not None:
                    if row_id not in cant_ids:
                        self.add(section, "L-UNKNOWN-ID", f"{row_id} is not in the input", number)
                        continue
                    if marked and row_id not in retired:
                        self.add(section, "L-COV-CANT", f"{row_id} is active in the input but marked retired", number)
                    if row_id in retired and not marked:
                        self.add(section, "L-COV-CANT", f"{row_id} is retired in the input; write 'retired: ...' in How it holds", number)
            elif row_id == GINV:
                ginv_rows += 1
                if ginv_rows > 1:
                    self.add(section, "L-COV-GINV", f"duplicate row for {GINV}", number)
                phase = 1
                if marked:
                    self.add(section, "L-COV-GINV", f"{GINV} cannot be retired", number)
            elif NEW_RE.match(row_id):
                if not phase:
                    self.add(section, "L-COV-GINV", f"{row_id} comes before {GINV}; NEW rows come last", number)
                if row_id in news:
                    self.add(section, "L-UNKNOWN-ID", f"duplicate invariant ID {row_id}", number)
                    continue
                news.append(row_id)
            else:
                self.add(section, "L-UNKNOWN-ID", f"'{row_id}' is not a CANT-n, {GINV} or NEW-n ID", number)
                continue
            # Invariants may hold without any change touching them, so change IDs are optional.
            self.check_change_cell(section, number, cells[3], declared, False, row_id)
        if ginv_rows == 0:
            self.add(section, "L-COV-GINV", f"missing row for {GINV}")
        if cant_ids is not None:
            missing = [i for i in cant_ids if i not in cants]
            if missing:
                self.add(section, "L-COV-CANT", f"missing rows for {', '.join(missing)}")
            present = [i for i in cants if i in cant_ids]
            if not missing and present != cant_ids:
                self.add(section, "L-COV-CANT", "CANT rows are not in input order")
        elif cants != sorted(cants, key=lambda s: int(s.split("-")[1])):
            self.add(section, "L-COV-CANT", "CANT rows are not in order")
        return set(news)

    def check_trace(self, declared: dict, regions: list[Region], flow_ids: list[str] | None, retired: set[str]) -> None:
        table = self.tables.get((TRACE, None))
        if table is None:
            return
        flows, retired_flows, where = self.citable_flows(regions, flow_ids, retired)
        sentences = _motivation_sentences(self.doc.motivation) if self.doc is not None else None
        for number, cells in table.rows:
            statement = _decode(cells[0]).strip()
            if not statement or statement.lower() in EMPTY_SENTINELS:
                self.add(TRACE, "L-REQ-SOURCE", "requirement statement is empty", number)
            problem = _source_problem(cells[1], flows, retired_flows, where, sentences)
            if problem is not None:
                self.add(TRACE, "L-REQ-SOURCE", problem, number)
            self.check_change_cell(TRACE, number, cells[2], declared, True, "requirement")

    def citable_flows(
        self, regions: list[Region], flow_ids: list[str] | None, retired: set[str]
    ) -> tuple[set[str] | None, set[str], str]:
        """FLOW IDs a requirement may cite, retired ones, and where they come from.

        The input is authoritative when given; otherwise the §4 subsections stand in for it.
        Without either, FLOW references are checked for form only.
        """
        if flow_ids is not None:
            return set(flow_ids), retired & set(flow_ids), "the input"
        if FLOWS not in self.section_lines:
            return None, set(), "§4"
        flows: set[str] = set()
        marked: set[str] = set()
        for region in self.flow_regions(regions):
            flows.add(region.sub)
            first = next((line for _, line in region.lines if line.strip()), "")
            if _is_retired_row(first):
                marked.add(region.sub)
        return flows, marked, "§4"

    def check_surface(self, declared: dict) -> None:
        table = self.tables.get((SURFACE, None))
        if table is None:
            return
        counts = {kind: 0 for kind in SURFACE_KINDS}
        seen: set[tuple[str, str]] = set()
        listed: dict[str, set[str]] = {}
        for number, cells in table.rows:
            kind, name = _plain(cells[0]), _plain(cells[1])
            if kind not in SURFACE_KINDS:
                self.add(SURFACE, "L-SURFACE", f"unknown kind '{kind}' (expected one of {', '.join(SURFACE_KINDS)})", number)
                continue
            if not name:
                self.add(SURFACE, "L-SURFACE", f"{kind} row has no name", number)
                continue
            if (kind, name) in seen:
                self.add(SURFACE, "L-SURFACE", f"{kind} '{name}' is listed twice", number)
                continue
            seen.add((kind, name))
            counts[kind] += 1
            keyword = DECLARED_KINDS.get(kind)
            # Functions, errors and events are anchored by their §2 declaration, so citing a change is optional.
            refs = self.check_change_cell(SURFACE, number, cells[2], declared, keyword is None, f"{kind} '{name}'")
            if keyword is not None and self.interface is not None:
                identifier = _IDENTIFIER_RE.search(name)
                if identifier is None or identifier.group(0) not in self.new_interface.get(keyword, set()):
                    self.add(SURFACE, "L-SURFACE", f"{kind} '{name}' is not declared as a '// new' {keyword} in the "
                                                   "§2 solidity block", number)
                else:
                    listed.setdefault(kind, set()).add(identifier.group(0))
            if kind == "storage_slots" and refs and not any(
                r.startswith("ST-") and _plain(declared[r][1][4]).lower() == "new" for r in refs
            ):
                self.add(SURFACE, "L-SURFACE", f"{kind} '{name}' does not cite a new ST row", number)
        # Every `// new` function, error and event is new surface and needs its own row.
        if self.interface is not None:
            for kind, keyword in DECLARED_KINDS.items():
                for name in sorted(self.new_interface.get(keyword, set()) - listed.get(kind, set())):
                    self.add(SURFACE, "L-SURFACE", f"{keyword} '{name}' is declared '// new' in §2 but no {kind} row "
                                                   "lists it", table.line)
        if self.front is not None:
            for kind in SURFACE_KINDS:
                claimed = self.front["surface"][kind]
                if claimed != counts[kind]:
                    self.add(SURFACE, "L-SURFACE", f"front matter surface.{kind} is {claimed} but §8 New surface lists {counts[kind]}")


def _subsection_key(section: int, title: str) -> str:
    """Region key for a ### heading in §3 or §4: "Storage", the trace ID it is tagged with, or "?"."""
    if section == CHANGES and title == STORAGE:
        return STORAGE
    tagged = _TAGGED_HEADING_RE.match(title)
    if tagged is None:
        return "?"
    pattern = BEH_RE if section == CHANGES else FLOW_RE
    return tagged.group("id") if pattern.match(tagged.group("id")) else "?"


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
    """Group table lines into blocks: (line number, raw line) per row, header and delimiter included.

    A GitHub-flavoured table is a row with an unescaped pipe directly followed by a delimiter row with the same
    number of cells; outer pipes are optional. It runs to the next blank line or the start of another block. A run
    of pipe-led lines with no delimiter row is also returned, so a malformed table is reported rather than skipped.
    """
    blocks: list[list[tuple[int, str]]] = []
    i = 0
    while i < len(lines):
        number, line = lines[i]
        if i + 1 < len(lines) and lines[i + 1][0] == number + 1 and _is_table_start(line, lines[i + 1][1]):
            block = [lines[i], lines[i + 1]]
            i += 2
            while (i < len(lines) and lines[i][0] == block[-1][0] + 1 and lines[i][1].strip()
                   and not _BLOCK_START_RE.match(lines[i][1])):
                block.append(lines[i])
                i += 1
            blocks.append(block)
            continue
        if line.strip().startswith("|"):
            block = []
            while i < len(lines) and lines[i][1].strip().startswith("|") and (
                    not block or lines[i][0] == block[-1][0] + 1):
                block.append(lines[i])
                i += 1
            blocks.append(block)
            continue
        i += 1
    return blocks


def _has_pipe(line: str) -> bool:
    """True when the line has a pipe that no backslash escapes."""
    return len(_split_row("x" + line.strip() + "x")) > 1


def _is_table_start(header: str, delimiter: str) -> bool:
    if not _has_pipe(header) or not _has_pipe(delimiter) or not _TABLE_DELIMITER_RE.match(delimiter):
        return False
    return len(_split_row(header)) == len(_split_row(delimiter))


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
        if _is_table_start(stripped, following):
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
        prog="lint.py", description=f"Lint a design plan against the plan template {TEMPLATE_VERSION}."
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
