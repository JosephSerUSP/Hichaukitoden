# DRAFT — Future tasks: Summon & Promotion as standalone scenes

**Status:** Draft for future planning (post overhaul-6). Not yet an approved round.
**Author:** surveillance follow-up to overhaul-6 (F4 Summon, F6 Promotion).
**Core idea:** Both Summon and Promotion currently live *inside* the reserve/roster
scene (`data/scenes.json`, reserve scene). They should each become their **own
scene**, and both should **preview the stats of the resulting Actor** before
committing. The two scenes are intentionally similar (same "before → after"
stat-preview shape), so they should share a preview component.

---

## Shared design note (applies to both)

- **Stat preview of the resulting Actor** is the headline feature. The scene
  should show a side-by-side (or overlay) comparison:
  - current actor: name, level, maxHp, atk/def/etc. (whatever the status
    panel already renders), skills, elements, passives.
  - resulting actor: the same fields for the target actorData
    (`api.summon`'s `actorData` / `api.promote`'s `evolvesTo` actorData),
    at the relevant level (summon = actor's base level; promotion = current
    level, since `api.promote` keeps level/exp).
- Build **one reusable stat-preview window/renderer helper** (e.g. a
  `presentation` helper that takes two `actorData` + levels and draws the
  comparison) and have both scenes call it. Avoid two divergent copies.
- Both scenes consume the **same engine APIs already built in overhaul-6**:
  - Summon → `api.summon(actorId, isReserve, index)` +
    `api.getMp()` / `api.changeMp(-cost)` (summon cost model already in
    `engine/interpreter.lua:838`).
  - Promotion → `api.canPromote` / `api.promoteInfo` / `api.promote`
    (`engine/interpreter.lua:868`).
- **Golden discipline:** these are new scenes → they need their own
  `goldenScript` + UI-golden reference (G1/G2). The existing reserve
  scene's summon/promote branches get *removed* and replaced with a
  "open scene" transition, so the reserve scene's golden must be
  re-captured too.

---

## Future Task A — Summon scene (accessed from Party)

**Context:** Today Summon is reached from the reserve popup when a slot is
empty (`data/scenes.json` reserve scene `executeSummon`, `summonPool`
built in `on_enter`). It should instead be its **own scene**, launched
from the **Party** UI, with a stat preview of the creature you're about to
summon.

### Acceptance Criteria (draft)
- [ ] New standalone scene (e.g. id `"summon"`) with its own
      `goldenScript` + UI-golden reference.
- [ ] Launched from the **Party** UI (not the reserve popup). The reserve
      popup's "Summon" branch is removed and replaced with an
      open-scene transition to the new scene.
- [ ] Shows the **summon pool** (reuse existing `summonPool` construction)
      and, on selection, a **stat preview of the resulting Actor** (shared
      helper from the shared design note).
- [ ] Commits via the existing `api.summon` + MP-cost check
      (`api.getMp() >= entry.cost` → `api.changeMp(-entry.cost)`);
      keeps the "Not enough MP!" / "That slot is occupied!" guards.
- [ ] Reserve scene golden re-captured after the popup branch is removed.

**Gates:** G1, G2 (new scene golden + reserve re-capture), UI-golden, G3
visual check.

---

## Future Task B — Promotion scene (accessed from a unit's context menu)

**Context:** Today Promotion is reached from the reserve popup's "Promote"
option (`executePromote`, mode 7) when `api.canPromote` is true. It
should instead be its **own scene**, launched from the **context menu of a
unit** (the per-unit menu you get when selecting a creature in
party/reserve), with a stat preview of the evolved Actor.

### Acceptance Criteria (draft)
- [ ] New standalone scene (e.g. id `"promotion"`) with its own
      `goldenScript` + UI-golden reference.
- [ ] Launched from a unit's **context menu** (the per-unit action menu),
      shown only when `api.canPromote(isReserve, index)` is true. The
      reserve popup's "Promote" branch (mode 7) is removed and replaced
      with an open-scene transition.
- [ ] Shows a **stat preview of the resulting (evolved) Actor** (shared
      helper), including the cost line from `api.promoteInfo`
      (`(free)` / `Cost: N MP` / `Needs: <name> x1`).
- [ ] Commits via `api.promote(isReserve, index)`; on failure shows the
      existing "Promotion failed" message; on success shows the evolved
      confirmation.
- [ ] Reserve scene golden re-captured after the popup branch is removed.

**Gates:** G1, G2 (new scene golden + reserve re-capture), UI-golden, G3
visual check.

---

## Open questions for the owner (flag, don't guess)
- Exact entry point wording: Party → "Summon" option? Unit context menu →
  "Promote" option? Confirm the labels/placement.
- Should the shared stat-preview also be reused by the **Status** scene
  (overhaul-6 F6 noted promotion could have lived there)? If so, build the
  helper to be Status-friendly from the start.
- Titania (actor id 3) still does not exist, so High Pixie → Titania
  cannot be previewed/promoted — content task, unchanged from overhaul-6.
