# Stage: repair

The engine validator rejected the campaign data below. Fix ONLY what the
problems list requires -- smallest possible edits, no rewrites, no new
content, keep all dialogue text and structure intact.

## Validator problems (verbatim)

{{PROBLEMS}}

## Command registry (for reference when a command/param is flagged)

{{COMMANDS}}

## Current campaign content files

{{FILES}}

## Deliverable

ONE JSON object containing ONLY the files you changed, complete:
`{ "<filename>": <complete corrected content>, ... }`

Rules for repair:
- Make ONLY targeted edits that fix the specific reported errors.
- Do NOT rewrite or re-generate unaffected events, maps, or items.
- Fix broken ID references by replacing them with valid IDs from the manifest.
- Do NOT introduce SCRIPT commands or custom code logic during repair.
