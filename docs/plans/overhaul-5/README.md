# Overhaul 5 — Visual Scene Authoring & Eventing Readability

Who reads what:

- **Agents** read exactly two things: the one brief file you were given in
  `briefs/`, and the `SPEC.md` sections that brief lists. Nothing else in this
  directory concerns you.
- **The human** reads `PLAYBOOK.md` (kickoff steps, delegation, protocols).

Files:

- `SPEC.md` — target architecture + ground rules + gates. Agent-facing.
- `briefs/*.md` — one self-contained task each. Agent-facing.
- `PLAYBOOK.md` — sequencing, environment routing, copy-paste prompts. Human-facing.
- `FEEDBACK.md` — owner feedback trail that seeded this round.
- `audio-design-options.md` — a decision memo, not a brief. Audio has no
  brief yet (see SPEC S6) — read this when the owner is ready to pick a
  direction, then write the brief.

## Where this picks up

Overhaul 4 made scenes data (`data/scenes.json` hooks, the D2 UI command
vocabulary, `engine.json → windowLayout`, the D3 UI-golden harness, and D13's
generic window renderer with zero scene-kind hardcoding). Overhaul 5 builds
the *authoring* surface on top of that foundation: a visual, click-to-edit
scene editor, and a pass on the event-list editor's readability that the
owner has flagged twice now (overhaul-3 FEEDBACK, overhaul-4 FEEDBACK).

See `SPEC.md` S0 for the full framing.
