# ADR template and source mapping

The ADR uses the point-form changelog structure. Keep every heading below, with this
spelling, level and order. Bracketed text is an instruction; replace it, never copy it.

## Heading tree

```markdown
# [Short name of the decision]

- **Feature Name**: [short name]
- **Start Date**: [date of writing, if known]
- **Authors**: adr-writer

## Summary

## Motivation

## Background

### [Subsystem name, optional]

## Specs

### Interface Changes

### Behavioural Changes

#### [Plain name of one behaviour change]

### Examples

## Design Decisions & Alternatives Considered

## Migration Steps
```

Subheadings in brackets are optional and may repeat. Do not add top-level sections such as
`Goals`, `Risks`, `Rollout` or `Appendix`; put that content in the closest section above.

## Metadata

- The `#` title and **Feature Name** use the same short name for the change.
- Include **Start Date** and **Authors** only when the value is known. Omit a field rather
  than write a placeholder. Never invent a person or a date.

## Section sources

Read the main plan (template v2) as follows. Its section numbers guide you while drafting;
they never appear in the ADR.

| ADR section | Draw from |
| --- | --- |
| Summary | Approach, changes, `breaking`, `activation`, interactions |
| Motivation | The input's Motivation, rewritten as a problem statement |
| Background | Code you read, the input, interactions |
| Interface Changes | Interface block (new and changed declarations) |
| Behavioural Changes | Each behaviour change and the storage subsection |
| Examples | User flows and verified current behaviour |
| Design Decisions & Alternatives Considered | Approach, what the plan gives up, the other plans |
| Migration Steps | Changes, interactions, `breaking`, `activation` |

The reference part (requirement trace, new surface, hot-path cost, invariants,
interactions) is for checking completeness and stating costs. It is not copied into the
ADR, and its IDs never appear.

## Formatting

- Interface Changes: one `solidity` block. Each declaration carries a short comment that
  says new or changed and what it does. Prose explains it outside the block.
- Behavioural Changes: one subheading per change; logic as numbered steps, a Mermaid flow
  or step-by-step prose. Storage as a small readable table.
- Examples: Solidity snippets and Mermaid diagrams, labelled "Before" and "After" when both
  exist.
- Prefer prose and short lists. Use tables only for small, regular facts.
