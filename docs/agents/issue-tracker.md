# Issue tracker: Local Markdown

Issues and specs (PRDs) live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`.
- Specs: `.scratch/<feature-slug>/spec.md`.
- Implementation issues: `.scratch/<feature-slug>/issues/<NN>-<slug>.md`,
  numbered from `01`, with one file per ticket.
- Record triage state as a `Status:` line near the top of each issue.
  See `triage-labels.md` for the role strings.
- Append comments and conversation history under `## Comments`.

## Publishing and fetching

When a skill says "publish to the issue tracker", create the appropriate
spec or issue file using the paths above. Create directories as needed.

When a skill says "fetch the relevant ticket", read the referenced file.
Resolve issue numbers within the relevant feature directory.

## Wayfinding operations

Used by `/wayfinder`:

- Map: `.scratch/<effort>/map.md`, containing Notes, Decisions-so-far,
  and Fog sections.
- Child tickets: `.scratch/<effort>/issues/<NN>-<slug>.md`, numbered
  from `01`, with the question in the body.
- Record ticket type in a `Type:` line:
  `research`, `prototype`, `grilling`, or `task`.
- Wayfinding uses `Status: open`, `Status: claimed`, and
  `Status: resolved` for its workflow.
- Record dependencies in a `Blocked by: NN, NN` line.
  A ticket is unblocked when all listed tickets are resolved.
- Frontier: select the lowest-numbered open, unblocked, unclaimed ticket.
- Claim: set `Status: claimed` and save before starting work.
- Resolve: append the answer under `## Answer`, set `Status: resolved`,
  and append a summary and ticket link to Decisions-so-far in the map.
