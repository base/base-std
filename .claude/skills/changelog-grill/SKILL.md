---
name: changelog-grill
description: Grill a changelog or ADR template until its intent, assumptions, design decisions, and migration impact are understood. Use when reviewing a changelog template, preparing an ADR, or stress-testing a feature proposal before writing the final entry.
disable-model-invocation: true
---

# Changelog Grill

Turn an incomplete changelog or ADR template into a validated context handoff. Do not edit the
template automatically. The primary output is structured Markdown in the conversation that the user
can review, correct, and pass into a new context or use to write the final changelog entry.

## Input

The user should provide a path to the template file. If they provide pasted content instead, use it
directly. When a path is provided:

1. Read the template.
2. Read repository guidance that applies to the file, especially `AGENTS.md`, the changelog README,
   and relevant product documentation.
3. Inspect related source, interfaces, tests, existing changelog entries, and configuration when
   needed to verify facts or understand the proposal.

Do not ask the user for facts that can be obtained from the repository or tools. Clearly distinguish
facts found in the repository from decisions that only the user can make.

## Mission

Interview the user until there is a shared understanding of the proposed change. Review every
section in the supplied template, including sections that appear complete. Look for:

- Missing context or prerequisites
- Ambiguous terminology and undefined actors
- Unstated assumptions
- Claims that need source or test verification
- Missing compatibility, rollout, or migration behavior
- Design decisions that were made implicitly
- Important alternatives that were not considered
- Scope that is too broad, too narrow, or inconsistent with the repository
- Security, storage, gas, API, and operational implications where relevant

Do not merely ask the user to fill in blanks. Challenge the reasoning. When the current approach has
a plausible better alternative, explain it and ask why the user prefers the current approach. The
user owns the decisions; the skill owns fact-finding and identifying questions.

## Grilling protocol

Map the proposal as a dependency-aware design tree and work in rounds.

- The **frontier** is every decision whose prerequisites are settled.
- Ask all questions on the current frontier in one round.
- Do not ask downstream questions whose answers depend on unresolved decisions in the same round.
- Number every question and include a recommendation.
- Wait for the user's answers before recomputing the next frontier.
- Continue until every meaningful branch has been considered and no important assumption remains
  silent.

Use this format:

```markdown
❓ **Q1 - <short title>**: <question and relevant context>

➡️ **Recommendation:** <recommended answer and why>
```

Ask questions in groups that make sense together, such as scope and audience first, then behavior
and interfaces, then alternatives and migration. Keep questions specific enough to answer without
guessing.

### Challenge expectations

For each major design choice, ask:

- What problem does this solve?
- Why is this the right layer for the behavior?
- What alternatives were considered?
- Why was the chosen approach preferred?
- What future requirement or complexity does it intentionally exclude?
- What breaks, changes, or remains compatible?

For changelog entries, explicitly examine:

- Audience and user-facing purpose
- Hardfork, rollout, and activation status
- Existing behavior and compatibility guarantees
- New, renamed, deprecated, or removed interface symbols
- Functions, events, errors, selectors, topics, and interface IDs
- Behavioral and revert-order changes
- Storage layout, encoding, packing, and migration concerns
- Authorization, policy, pause, and activation behavior
- Examples that demonstrate before/after usage
- Migration steps and whether action is required
- Edge cases and precise guarantees

If a selector, signature, storage slot, or behavior is not verified, mark it as unverified and find
the source or ask the user to resolve the gap. Never invent plausible technical values.

## Completion and output

Do not modify, create, or rename template files during grilling. The session is complete only after:

1. All relevant template sections have been reviewed.
2. Repository facts have been gathered or marked unavailable.
3. The user has answered the meaningful frontier questions.
4. The skill presents a context handoff for confirmation.

The final handoff must use this structure:

```markdown
# Grilled Context Handoff

## Confirmed Understanding

## Decisions Made

## Validated Assumptions

## Design Alternatives Considered

## Missing Context

## Open Questions

## Recommended Template Additions

## Final Confirmation
```

In `Final Confirmation`, state whether the context is ready to use for writing the changelog. If
there are unresolved questions, list them plainly and do not claim the handoff is complete.

After presenting the handoff, wait for explicit confirmation. Only after confirmation may the user
ask for the template or a new changelog entry to be written.
