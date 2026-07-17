# Summoner Rework — Design Doc (DRAFT: skeleton, owner decisions pending)

Status: **skeleton**. This document gates the battle-presentation
conversion to the windows system (`docs/SPEC.md` §1.2): battle drawing
stays frozen on the legacy renderer until the sections below are decided,
so the UI is only built once. Sections marked ❓ need owner input;
sections marked ✅ record what is already true in the engine and should be
built upon, not replaced.

## 1. What exists today (✅ grounded)

- **The player IS the Summoner**: the engine locates the player character
  by the `Summoner` role (exactly one actor carries it). The party the
  player fields is summoned spirits.
  - **MP is the Summoner's central resource** (o6 F2): summoning costs MP
  (`summoner.summonCostBase/PerLevel/PerTier`), dungeon movement drains MP
  (`dungeon.moveMpDrain`), MP exhaustion deals per-turn damage
  (`combat.mpExhaustionDamage`).
- **Summoner spells** (`system.summoner.spells`): a skill list cast from
  the battle console, resolved as slot 1 actions in `resolveRound`.
- **Ritual scene**: one shared scene handles summon / promote / sacrifice,
  backed by the EXP Bank economy (sacrifice converts spirits to banked EXP
  at `summoner.sacrificeExpRate`; promotion spends it).
- **Battle slots**: party slots 1–4 on a 2x2 grid; reserve exists outside
  battle via the reserve scene.
- **Presentation**: battle is the last legacy-drawn scene. All animation
  is data (`data/animations.json`), targeting is declarative specs +
  one resolver — both ready for whatever the rework needs.

## 2. Core fantasy and battle role (❓ owner)

- What does the Summoner DO during a battle round beyond spell casting?
  (Direct a command per spirit as now? Only spells + stance while spirits
  act on AI? Something between?)
  R: Only spells and swapping to/from reserve.
- Is mid-battle summoning/dismissal a mechanic? (Swap a spirit for MP as
  an action? Replace fallen spirits mid-fight?)
  R: Only swapping from reserve. No sacrifice, no summoning. 
- Does the Summoner have a visible battler presence (targetable, HP) or
  stay off-field with MP as the only life-adjacent resource?
  R: Off-field. 

## 3. Party / reserve flow (❓ owner)

- Reserve size limits, and whether reserve spirits are reachable in
  battle (swap action?) or only between fights.
  R: Swap action is possible. Reserve size limit should not be hardcoded (per our philosophy).
- Do slots have positional meaning (front/back row, grid adjacency
  effects) that the new UI must expose?
  R: Yes, front/back row should affect certain mechanics, but right now we only need this to be able to be verified /accessed in engine. 

## 4. Economy touchpoints (❓ owner)

- Does the EXP Bank interact with battle (banked-EXP costs for mid-battle
  effects?) or stay a ritual-scene-only economy?
  R: Ritual-only economy.
- MP regeneration model in and out of battle.
R: Items only, basically. Therefore it's important for the summoner to handle MP well and have means of exiting the dungeon swiftly. 

## 5. UI implications (derived from §2–§4, decided 17.07.2026)

Design consequences first:

- The Summoner is **off-field** and acts only through **spells** and
  **reserve swaps** — so the battle console is NOT a per-spirit command
  menu. Spirits act on AI; the console is the Summoner's two verbs plus
  round confirmation.
- MP is the resource the whole screen revolves around (no regen outside
  items): the **MP gauge is a first-class, always-visible window**, not a
  corner stat. MP-cost previews appear wherever a spell or swap is
  hovered.
- Front/back row exists as engine-verifiable state only for now — the UI
  must *display* row membership on the party grid but needs no
  row-manipulation window this round.
- EXP Bank never appears in battle (ritual-only).

Window inventory for `data/scenes.json` battle (`"draw": "windows"`),
all through shared helpers (party grid, gauges, gradient panels — SPEC
§2, no new legacy drawing):

| Window | Content | Notes |
|--------|---------|-------|
| `enemy_row` | enemy sprites, names, HP gauges | animated gauges; existing enemy layout numbers from `engine.json battleLayout` |
| `party_grid` | 2x2 spirit grid: name, HP gauge, states, **row badge** (front/back) | shared `drawPartyGrid` binding; row badge reads the new engine row flag |
| `summoner_panel` | Summoner name/portrait, **MP gauge**, banked-spell count | always visible; MP gauge interpolates |
| `command_console` | verbs: Spell, Swap, (Flee/round-control as today) | replaces per-spirit command loop |
| `spell_menu` | `system.summoner.spells` list with MP costs, disabled when unaffordable | MP-cost preview updates `summoner_panel` on hover |
| `swap_menu` | reserve list (no hardcoded size — scrolling list), MP cost per swap | swap is an action resolved in-round |
| `target_overlay` | reticle over party grid / enemy row | driven by `targeting.expand` specs, shared with menus |
| `battle_log` | event text + SPACE prompt | existing log panel geometry |
| popups | damage/heal numbers | stay physics-driven via the animation system, not windows |

## 6. Conversion gate checklist

- [x] §2–§4 decided by owner (17.07.2026)
- [x] §5 window inventory written
- [x] Battle windows brief drafted — `docs/design/battle-windows-brief.md`
      (golden-UI trace regeneration is sanctioned per converted scene,
      owner-reviewed; battle.log must not change — presentation only)
- [ ] Engine prerequisites landed (owner-supervised — touches
      `engine/battle.lua`): swap-from-reserve action, front/back row flag
- [ ] Battle scene converted to `"draw": "windows"`
- [ ] Legacy renderer path deleted from `main.lua` / `presentation/`
