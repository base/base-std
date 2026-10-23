"""Parse and validate a case input.md.

An input has three required sections: Motivation, User flows to optimize for and
Must not break. The two requirement sections hold numbered items (FLOW-n for user
flows, CANT-n for must-not-break constraints) that later stages cite by ID, so
numbering is strict and retired items keep their slot.

A Summary section is rejected: it is written after design and would hand designers
the shipped answer. The plan linter can opt in to legacy Summary-bearing inputs with
`allow_summary=True`; designer inputs never do.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

SUMMARY = "Summary"
MOTIVATION = "Motivation"
FLOWS = "User flows to optimize for"
CANTS = "Must not break"
REQUIRED_SECTIONS = (MOTIVATION, FLOWS, CANTS)

# Requirement sections and the item prefix each one owns.
_ITEM_SECTIONS = {FLOWS: "FLOW", CANTS: "CANT"}

ITEM_RE = re.compile(r"^- (FLOW|CANT)-(\d+): .+")
_HEADING_RE = re.compile(r"^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")
_FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
_TOP_BULLET_RE = re.compile(r"^[-*+](?:[ \t]|$)")
_IDLIKE_RE = re.compile(r"^[-*+][ \t]+(?:FLOW|CANT)\b", re.IGNORECASE)


class InputError(ValueError):
    """Raised when an input file does not follow the input format."""


@dataclass(frozen=True)
class InputItem:
    id: str
    text: str


@dataclass(frozen=True)
class InputDocument:
    motivation: str
    user_flows: str
    must_not_break: str
    flows: tuple[InputItem, ...] = field(default_factory=tuple)
    cants: tuple[InputItem, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class LegacyInputDocument(InputDocument):
    """An input that still carries a Summary; only the plan linter accepts one."""

    summary: str = ""


@dataclass
class _Section:
    title: str
    level: int
    start_line: int
    lines: list[tuple[int, str]] = field(default_factory=list)


def fence_step(fence: tuple[str, int] | None, line: str) -> tuple[str | None, tuple[str, int] | None]:
    """Classify one line given the open fence (or None); returns (role, new open fence).

    A fence opens on three or more backticks or tildes (a backtick opener may not contain
    another backtick, so a one-line inline span is not a fence) and closes only on a run of
    the same character at least as long as the opener followed by nothing but whitespace.
    Roles are "delim" for a fence delimiter, "inside" for fenced content, None otherwise.
    """
    match = _FENCE_RE.match(line)
    if fence is None:
        if match and not (match.group(1)[0] == "`" and "`" in match.group(2)):
            return "delim", (match.group(1)[0], len(match.group(1)))
        return None, None
    if (
        match
        and match.group(1)[0] == fence[0]
        and len(match.group(1)) >= fence[1]
        and not match.group(2).strip()
    ):
        return "delim", None
    return "inside", fence


def fence_roles(lines: list[str]) -> list[str | None]:
    """Classify each line as a fence delimiter ("delim"), fenced content ("inside") or neither."""
    roles: list[str | None] = []
    fence: tuple[str, int] | None = None
    for line in lines:
        role, fence = fence_step(fence, line)
        roles.append(role)
    return roles


def _is_summary(title: str) -> bool:
    return title.casefold() == SUMMARY.casefold()


def _split_sections(lines: list[str], allow_summary: bool = False) -> dict[str, _Section]:
    """Split into the required sections, ignoring headings inside code fences.

    An unfenced Summary heading at any level is an error unless `allow_summary` is set.
    """
    known = REQUIRED_SECTIONS + ((SUMMARY,) if allow_summary else ())
    sections: dict[str, _Section] = {}
    current: _Section | None = None
    for number, (line, role) in enumerate(zip(lines, fence_roles(lines)), start=1):
        if role is None:
            heading = _HEADING_RE.match(line)
            if heading:
                level, title = len(heading.group(1)), heading.group(2).strip()
                if _is_summary(title):
                    if not allow_summary:
                        raise InputError(
                            f"line {number}: a Summary section is not allowed "
                            f"(inputs hold only {', '.join(REQUIRED_SECTIONS)})"
                        )
                    title = SUMMARY
                if title in known:
                    if title in sections:
                        raise InputError(f"line {number}: duplicate section '{title}'")
                    current = sections[title] = _Section(title, level, number)
                    continue
                if current is not None and level <= current.level:
                    current = None
                    continue
        if current is not None:
            current.lines.append((number, line))
    return sections


def _body(section: _Section) -> str:
    text = "\n".join(line for _, line in section.lines)
    return text.strip("\n")


def _in_fence_flags(section: _Section) -> list[bool]:
    return [role is not None for role in fence_roles([line for _, line in section.lines])]


def _reject_stray_items(section: _Section) -> None:
    """Requirement items are only valid in their own sections; elsewhere they would be dropped."""
    for (number, line), fenced in zip(section.lines, _in_fence_flags(section)):
        if not fenced and _IDLIKE_RE.match(line):
            raise InputError(
                f"line {number}: FLOW/CANT item in '{section.title}' "
                f"(items belong in '{FLOWS}' or '{CANTS}')"
            )


def _extract_items(section: _Section) -> tuple[InputItem, ...]:
    prefix = _ITEM_SECTIONS[section.title]
    items: list[InputItem] = []
    seen: set[int] = set()
    for (number, line), fenced in zip(section.lines, _in_fence_flags(section)):
        if fenced or not _TOP_BULLET_RE.match(line):
            continue
        match = ITEM_RE.match(line)
        if match is None:
            if _IDLIKE_RE.match(line):
                raise InputError(
                    f"line {number}: malformed item in '{section.title}' "
                    f"(expected '- {prefix}-<n>: <text>')"
                )
            raise InputError(
                f"line {number}: item in '{section.title}' has no {prefix}-<n> ID"
            )
        kind, digits = match.group(1), match.group(2)
        item_id = f"{kind}-{digits}"
        if kind != prefix:
            raise InputError(
                f"line {number}: {item_id} does not belong in '{section.title}'"
            )
        if len(digits) > 1 and digits.startswith("0"):
            raise InputError(f"line {number}: {item_id} is not a canonical ID")
        text = line[len(f"- {item_id}: "):]
        if not text.strip():
            raise InputError(f"line {number}: {item_id} has no description")
        value = int(digits)
        if value in seen:
            raise InputError(f"line {number}: duplicate ID {item_id}")
        expected = len(items) + 1
        if value != expected:
            raise InputError(
                f"line {number}: {item_id} out of sequence (expected {prefix}-{expected})"
            )
        seen.add(value)
        items.append(InputItem(item_id, text))
    if not items:
        raise InputError(f"section '{section.title}' has no {prefix}-<n> items")
    return tuple(items)


def parse_input(text: str, *, allow_summary: bool = False) -> InputDocument:
    """Parse an input; with `allow_summary` a legacy Summary yields a LegacyInputDocument."""
    sections = _split_sections(text.splitlines(), allow_summary)
    missing = [title for title in REQUIRED_SECTIONS if title not in sections]
    if missing:
        raise InputError("missing section(s): " + ", ".join(missing))
    for title in (SUMMARY, MOTIVATION):
        if title in sections:
            _reject_stray_items(sections[title])
    fields = dict(
        motivation=_body(sections[MOTIVATION]),
        user_flows=_body(sections[FLOWS]),
        must_not_break=_body(sections[CANTS]),
        flows=_extract_items(sections[FLOWS]),
        cants=_extract_items(sections[CANTS]),
    )
    if SUMMARY in sections:
        return LegacyInputDocument(summary=_body(sections[SUMMARY]), **fields)
    return InputDocument(**fields)


@dataclass(frozen=True)
class SourceLines:
    """Physical 1-based lines that a hidden requirement may cite in its input."""

    motivation: frozenset[int]
    flows: dict[str, int]  # active (not retired) FLOW ID -> its line


def source_lines(text: str) -> SourceLines:
    """Locate citable lines: unfenced nonblank Motivation lines and active FLOW items.

    The text must be a valid designer input; parsing errors propagate as InputError.
    """
    parse_input(text)
    sections = _split_sections(text.splitlines())
    motivation = sections[MOTIVATION]
    lines = frozenset(
        number
        for (number, line), fenced in zip(motivation.lines, _in_fence_flags(motivation))
        if not fenced and line.strip() and not _HEADING_RE.match(line)
    )
    flows: dict[str, int] = {}
    section = sections[FLOWS]
    for (number, line), fenced in zip(section.lines, _in_fence_flags(section)):
        match = None if fenced else ITEM_RE.match(line)
        if match and not line.rstrip().lower().endswith("(retired)"):
            flows[f"{match.group(1)}-{match.group(2)}"] = number
    return SourceLines(lines, flows)


def load_input(path: Path, *, allow_summary: bool = False) -> InputDocument:
    try:
        text = Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise InputError(f"cannot read {path}: {exc}") from exc
    try:
        return parse_input(text, allow_summary=allow_summary)
    except InputError as exc:
        raise InputError(f"{path}: {exc}") from exc
