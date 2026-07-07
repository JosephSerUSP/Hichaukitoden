# Overhaul 3 — Unified Event Engine & Editor UX

Who reads what:

- **Agents** read exactly two things: the one brief file you were given in
  `briefs/`, and the `SPEC.md` sections that brief lists. Nothing else in this
  directory concerns you.
- **The human** reads `PLAYBOOK.md` (kickoff steps, delegation, protocols).

Files:

- `SPEC.md` — target architecture + ground rules + gates. Agent-facing.
- `briefs/*.md` — one self-contained task each. Agent-facing.
- `PLAYBOOK.md` — sequencing, environment routing, copy-paste prompts. Human-facing.
