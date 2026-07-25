# A5d — Convert battle start / encounter roll to flow phases

- Branch: `o3/a5d-battle-start`
- Runtime needs: G1, G2 (+ a brief manual play check)
- Depends on: A4 merged; recommended last of the A5 batch
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S2, S4;
  `docs/plans/overhaul-3/flow-inventory.md` (encounter/battle-start rows)

## Goal

Move the encounter chance roll (`main.lua` step handler) and enemy-group
composition (count roll + weighted pick, `triggerBattle`) into
`data/flows.json → battle.encounter_check` and `battle.battle_start`.

## Do

- Implement the `ROLL_ENCOUNTER` (chance:formula) and `SPAWN_ENEMIES`
  (count:formula, table) handlers and add their `engine.json → commands`
  registry entries as part of this task.
- Respect the per-map `encounterRate` override and safe-map exemption exactly
  as today.
- Legacy fallback guards as in SPEC S4.

## Don't

- No SCRIPT commands. Do not change encounter math — reproduce it.

## Acceptance

- [ ] G1 green; G2 byte-identical
- [ ] Manual play: encounters still trigger in the dungeon; safe map (town)
      never triggers
- [ ] PR checklist filled in
