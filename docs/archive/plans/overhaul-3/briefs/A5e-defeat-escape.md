# A5e — Convert defeat/escape transitions to flow phases

- Branch: `o3/a5e-defeat-escape`
- Runtime needs: G1, G2
- Depends on: A4 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S2, S4;
  `docs/plans/overhaul-3/flow-inventory.md` (defeat/escape rows)

## Goal

Move defeat text/session-reset signaling and escape-to-map transitions into
`data/flows.json → battle.defeat` and `battle.escaped`.

## Do

- Use `EMIT_TEXT` + `SCENE_EVENT` (the interpreter emits a scene-change
  event; the existing `main.lua` handler performs the actual scene switch and
  session reset — the interpreter never touches scene state).
- Legacy fallback guards as in SPEC S4.

## Don't

- No SCRIPT commands. Do not move the actual scene-switch/reset Lua into the
  interpreter.

## Acceptance

- [ ] G1 green; G2 byte-identical
- [ ] Manual play: losing a battle returns to title with a fresh session;
      fleeing returns to the map
- [ ] PR checklist filled in
