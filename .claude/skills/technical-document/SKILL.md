---
name: technical-document
description: "Convert changelog/TEMPLATE_POINT_FORM.md from point form into a written technical specification. Use the exact template structure. Apply ASD-STE100-inspired Simplified Technical English and Google technical-writing guidance while preserving technical facts, uncertainty, and scope."
version: 2.0.0
---

# Convert the point-form template into a written specification

Use this skill for one task only: convert the repository template
`changelog/TEMPLATE_POINT_FORM.md` into a complete written specification.

Do not use this skill to create a generic RFC, design document, technical overview,
or implementation plan. The template is the source of truth for the output structure.

## Source template

Read and follow:

```text
changelog/TEMPLATE_POINT_FORM.md
```

Also follow the repository guidance in:

```text
changelog/AGENTS.md
changelog/README.md
```

## Exact output structure

The output must use this structure and heading text in this order:

```markdown
# [Title]

- **Feature Name**: [value]
- **Start Date**: [value]
- **Authors**: [value]
- **Title**: [value]

## Summary

## Motivation

## Background

## Specs

### Interface Changes

### Behavioural Changes

### Examples

## Design Decisions & Alternatives Considered

## Migration Steps
```

Template conformance is mandatory:

- Use the exact heading text and heading order.
- Keep all required headings, even when a section contains a TODO.
- Do not add headings such as `Goals`, `Risks`, `Open Questions`, `Decision`,
  `Rollout`, or `Appendix`.
- Put content that would normally use those headings into the closest defined section.
- Add headings under `## Specs` only when the source template or user explicitly requires them.
- Do not add generic preambles, summaries, transformation notes, or closing reports.
- Return only the completed specification unless the user explicitly asks for an audit or explanation.

## Conversion workflow

### 1. Read the complete input

Read the entire point-form document before drafting. Extract:

- Feature name, start date, authors, and title.
- Summary and audience.
- Problem, motivation, and current limitations.
- Background concepts, prior art, standards, and existing patterns.
- Interface changes, including functions, events, errors, signatures, and selectors.
- Behavioral changes, including execution flow, storage, compatibility, and gas effects.
- Examples, expected values, emitted events, and call sequences.
- Design decisions and rejected alternatives.
- Migration steps, deprecations, compatibility, and breaking changes.

Treat comments in the template as instructions. Do not copy those comments into the output.

### 2. Map content to the fixed sections

Use this mapping:

- Metadata → document metadata.
- Summary bullets → `## Summary`.
- Problem and rationale → `## Motivation`.
- Prerequisites, prior art, standards, and terminology → `## Background`.
- Interface facts → `### Interface Changes`.
- Runtime, storage, gas, and compatibility facts → `### Behavioural Changes`.
- Before/after snippets and call sequences → `### Examples`.
- Chosen approach and rejected options → `## Design Decisions & Alternatives Considered`.
- Integrator adoption and rollout actions → `## Migration Steps`.

Do not move content to a new heading to make the document easier to organize.

### 3. Preserve technical fidelity

- Preserve every fact, number, condition, qualifier, and scope boundary.
- Preserve uncertainty. Keep `may`, `could`, `estimated`, and `unknown` unchanged in strength.
- Do not invent selectors, topic values, signatures, storage slots, gas costs, owners, dates, or compatibility claims.
- Mark missing information with `[TODO: ...]` in the relevant section.
- Mark an inference with `[Inferred — verify: ...]`.
- If a technical value is not verified, write `[TODO: verify against source]`.
- Keep code and signatures exactly as provided unless the user asks for a correction.

Before citing a function signature, event signature, error selector, topic0, function
selector, or ERC-165 interface ID, verify it against the source or mark it for verification.

### 4. Write the specification

Convert point-form fragments into complete technical prose. Keep the meaning and
technical detail, but improve structure, readability, and consistency.

Use tables for mappings when the input contains multiple comparable entries. Use
numbered lists for migration steps. Use code blocks for verified code or call sequences.

### 5. Apply Simplified Technical English principles

Use the public `asd-ste100-skill` as a source of writing principles:

```text
https://github.com/danyuchn/asd-ste100-skill
```

Apply these rules:

- Prefer active voice and name the actor when the actor is known.
- Use one clear action per sentence.
- Keep procedures near 20 words per sentence and descriptions near 25 words when possible.
- Split long or compound sentences when splitting preserves precision.
- Do not use semicolons in procedural text.
- Keep subjects, verbs, articles, and conditions explicit.
- Put conditions before instructions.
- Replace ambiguous phrasal verbs such as `spin up` and `kick off` with plain verbs.
- Use one term for one technical concept. Do not rotate synonyms.
- Prefer direct, common words over formal or vague alternatives.
- Preserve technical terms when simplifying them would reduce accuracy.

Apply structural rules confidently. Treat dictionary-specific lexical rules as guidance
only. Never claim that the output is officially ASD-STE100 compliant, and never reproduce
the official ASD-STE100 dictionary.

### 6. Apply Google technical-writing guidance

Use Google’s technical-writing guidance as the style reference:

```text
https://developers.google.com/style
https://developers.google.com/tech-writing
```

Apply these rules:

- Write for the technical reader’s role and existing knowledge.
- State the purpose and scope in `Summary` and `Motivation`.
- Use clear, descriptive sentence-case headings from the template.
- Put important information before supporting detail.
- Use plain, globally understandable English.
- Define acronyms and unfamiliar domain terms at first use.
- Use numbered lists for ordered steps and bullets for unordered information.
- Avoid idioms, slang, cultural references, buzzwords, and marketing language.
- Replace vague claims with measurements when the input provides measurements.
- Use descriptive link text and unambiguous dates.

### 7. Review before returning

Check all of the following:

- The output matches the exact template heading structure.
- No template heading is missing, renamed, duplicated, or reordered.
- No unsupported technical fact was added.
- No source fact, qualifier, or condition was removed.
- The output contains no invented selector, signature, storage detail, or compatibility claim.
- Interface changes are separated from behavioral changes.
- Examples contain only supplied or verified values.
- Migration steps identify compatibility and breaking changes when the input provides them.
- Missing information uses TODO markers.
- Active voice, terminology consistency, sentence clarity, and plain language were applied.

## Output rules

Return only the written specification by default. Do not explain the conversion and do
not add headings outside the template.

If the user asks for an audit, return the conforming specification first. Add the audit
after a plain-text separator such as `--- Review ---`, and do not treat the audit as part
of the specification.

## Boundaries

This skill will not:

- Generate other document types.
- Invent technical facts or evidence.
- Claim official ASD-STE100 compliance.
- Reproduce the ASD-STE100 approved-word dictionary.
- Verify repository behavior without reading the relevant source.
- Manufacture selectors, signatures, storage layouts, or migration guarantees.

## References

- `references/google-technical-writing.md`
- `references/template-point-form.md`
- `references/simplified-technical-english.md`
- `examples/point-form-input.md`
- `examples/generated-spec.md`
