# Domain Docs

This repo uses a single-context domain documentation layout.

## Before exploring

- Read `CONTEXT.md` at the repo root.
- Read ADRs in `docs/adr/` relevant to the area being explored.

If these files do not exist, proceed silently. Do not flag their absence
or suggest creating them upfront. The `/domain-modeling` skill creates
them lazily when terminology or decisions are resolved.

## File structure

- `CONTEXT.md`: domain context and glossary.
- `docs/adr/`: numbered architectural decision records.

## Use the glossary's vocabulary

Use terms defined in `CONTEXT.md` when naming domain concepts in issues,
proposals, hypotheses, and tests. Avoid synonyms the glossary rejects.

If a concept is missing, reconsider whether it belongs to the domain.
If it represents a real gap, note it for `/domain-modeling`.

## Flag ADR conflicts

Explicitly identify any existing ADR that a proposal contradicts.
Explain why the decision may warrant reopening rather than silently
overriding it.
