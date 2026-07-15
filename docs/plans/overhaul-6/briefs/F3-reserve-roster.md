# F3: Reserve roster (4 active + 8 reserve)

**Context:** Read SPEC.md S4. `session.party` currently has no enforced
size or reserve concept (`session.lua:131`'s "6+ are reserve" comment is
aspirational, zero backing implementation). Can land in parallel with F2
(different code area) once F1 is merged, but **the swap-UI question below
needs an owner decision before you start the UI half** — do the data-model
half first if you want to start early.

**Role:** local agent fine for the data-model half; the swap-UI half needs
the owner's placement decision first (see below) — don't guess a layout.

## Acceptance Criteria
- [ ] `session.party` (or a new `session.reserve`) holds up to 4 active + 8
      reserve. Battle/MP-drain code only ever touches the active 4 (should
      already be true via `getActiveParty()` — confirm, don't re-derive).
- [ ] Reserve creatures: no MP drain, no battle actions, not targetable —
      verify by construction (battle simply never iterates reserve), not by
      adding new guard checks that duplicate what "not in the active list"
      already gives you for free.
- [ ] Reserve members stored as full `Battler`-backed data, same shape as
      active party (per SPEC S4's recommendation) — no new serialization
      format.
- [ ] **STOP before building swap UI. Ask the owner**: does the reserve
      swap live in the map's existing per-unit popup (Status/Equip/Item
      Creation options, `data/scenes.json` map scene) as a new option, or
      somewhere else? Implement whichever they say — don't default silently.
- [ ] Swap is a free action, field-menu-only (already true if it only exists
      outside battle scenes).
- [ ] Confirm the golden battle/session mock only ever populates 4 party
      members — if it needs updating to also cover a reserve slot for
      future coverage, note it in the PR but don't expand golden coverage
      speculatively without an actual reserve-affecting behavior to test.

**Gates:** G1, G2 (byte-identical — reserve additions shouldn't touch
battle's mock unless you deliberately changed it, in which case justify),
UI-golden for whichever scene gains the swap option, G3 visual check of the
new UI.
