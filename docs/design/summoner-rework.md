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
- Is mid-battle summoning/dismissal a mechanic? (Swap a spirit for MP as
  an action? Replace fallen spirits mid-fight?)
- Does the Summoner have a visible battler presence (targetable, HP) or
  stay off-field with MP as the only life-adjacent resource?

## 3. Party / reserve flow (❓ owner)

- Reserve size limits, and whether reserve spirits are reachable in
  battle (swap action?) or only between fights.
- Do slots have positional meaning (front/back row, grid adjacency
  effects) that the new UI must expose?

## 4. Economy touchpoints (❓ owner)

- Does the EXP Bank interact with battle (banked-EXP costs for mid-battle
  effects?) or stay a ritual-scene-only economy?
- MP regeneration model in and out of battle.

## 5. UI implications (derived — fill in once §2–§4 are decided)

For each decided mechanic, list the windows the battle scene needs
(command console, party grid, target overlay, summon picker, …) so the
windows-conversion brief can author them in `data/scenes.json` directly.
Constraint from SPEC §2: shared party-grid helpers, animated gauges,
gradient panels — no new legacy drawing.

## 6. Conversion gate checklist

- [ ] §2–§4 decided by owner
- [ ] §5 window inventory written
- [ ] Battle windows brief drafted (golden-UI trace regeneration is
      sanctioned per converted scene, owner-reviewed; battle.log must not
      change — presentation only)
- [ ] Legacy renderer path deleted from `main.lua` / `presentation/`
