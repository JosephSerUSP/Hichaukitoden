# Summoner Rework — Design Doc (DECIDED 17.07.2026, rev. 2)

Status: **decided**. This document gates the battle-presentation
conversion to the windows system (`docs/SPEC.md` §1.2). Owner decisions
are recorded inline; §1 records what is already true in the engine and
should be built upon, not replaced. Execution plan:
`docs/design/battle-windows-brief.md`.

## 1. What exists today (grounded)

- **The player IS the Summoner**: the engine locates the player character
  by the `Summoner` role (exactly one actor carries it). The party the
  player fields is summoned spirits.
- **MP is the Summoner's central resource** (o6 F2): summoning costs MP
  (`summoner.summonCostBase/PerLevel/PerTier`), dungeon movement drains MP
  (`dungeon.moveMpDrain`), MP exhaustion deals per-turn damage
  (`combat.mpExhaustionDamage`).
- **Ritual scene**: one shared scene handles summon / promote / sacrifice,
  backed by the EXP Bank economy (sacrifice converts spirits to banked EXP
  at `summoner.sacrificeExpRate`; promotion spends it).
- **Battle slots**: party slots 1–4 on a 2x2 grid; reserve exists outside
  battle via the reserve scene.
- **Presentation**: battle is the last legacy-drawn scene. All animation
  is data (`data/animations.json`), targeting is declarative specs +
  one resolver — both ready for the rework.
- *(Retiring: `system.summoner.spells` battle spell-casting — see §2.)*

## 2. Battle role

- **The player directs each fielded spirit's action per round** — the
  per-spirit command model stays. The Summoner has NO verbs of their own:
  **summoner spells are removed as a mechanic** (`system.summoner.spells`
  and its resolveRound slot-1 path retire).
- **No mid-battle summoning, dismissal, or sacrifice.** The only reserve
  access in battle is the emergency wave (§3).
- The Summoner stays **off-field** — no battler presence, no HP. MP
  exhaustion continues to damage the fielded spirits per turn.

## 3. Wipe, permadeath, game over

- **Emergency wave**: when the fielded party wipes and reserve spirits
  exist, the whole reserve wave (up to the 4 slots) deploys automatically,
  **free of MP cost** — the price is the lost turn (nobody acts that
  round) and the fallen spirits.
- **Permadeath**: a spirit at 0 HP is *downed* during battle (mid-fight
  revival by items remains possible). Any spirit still down when the
  battle ends is **permanently gone** and **auto-converts to banked EXP at
  the sacrifice rate** (`summoner.sacrificeExpRate`).
- **Game over** = party wiped AND reserve empty. MP reaching zero is
  survivable (exhaustion drain), never an instant loss.

## 4. Party / reserve / economy

- Reserve has **no hardcoded size limit** (per SPEC extensibility rule).
- **Front/back row**: each fielded spirit carries row state, persisted and
  formula/engine-accessible. No combat math consumes it yet — state +
  access only this round; the UI displays it.
- **EXP Bank is ritual-only** — it never appears in or interacts with
  battle (the permadeath auto-bank in §3 happens at battle end, surfaced
  in the results flow, not as an in-battle mechanic).
- **MP regenerates through items only.** Managing MP and exiting the
  dungeon swiftly is core play pressure — the UI must keep MP readable at
  all times without dramatizing it.

## 5. UI implications

Design consequences:

- The console is the **per-spirit command menu** (as today, minus the
  spell verb). No swap verb: the emergency wave is an automatic
  event with its own notice, not a menu.
- **MP stays a slim, discreet gauge** — no dedicated summoner panel.
- **Cost/gain preview is a shared gauge-widget feature**, not a window:
  hovering anything that would spend or grant a gauged resource tints the
  affected portion of the gauge red (often a single pixel) and may append
  a slim `cost: xxxx` / `gain: xxxx` text after the gauge. One widget,
  used everywhere — ritual summon/promotion/sacrifice, shops, item use —
  wherever MP/EXP/gold gauges appear.
- Party grid shows a **row badge** (front/back) per spirit; no
  row-manipulation UI this round.

Window inventory for `data/scenes.json` battle (`"draw": "windows"`),
all through shared helpers (party grid, gauges, gradient panels — SPEC
§2, no new legacy drawing):

| Window | Content | Notes |
|--------|---------|-------|
| `enemy_row` | enemy sprites, names, HP gauges | animated gauges; layout numbers from `engine.json battleLayout` |
| `party_grid` | 2x2 spirit grid: name, HP gauge, states, row badge | shared `drawPartyGrid` binding; slim MP gauge lives with the grid header |
| `command_console` | per-spirit commands (attack/defend/item/flee as today, spell verb removed) | existing console geometry |
| `target_overlay` | reticle over party grid / enemy row | driven by `targeting.expand` specs, shared with menus |
| `wave_notice` | emergency-wave banner ("reserves deploy — the round is lost") | event-triggered, transient |
| `battle_log` | event text + SPACE prompt | existing log panel geometry |
| popups | damage/heal numbers | stay physics-driven via the animation system, not windows |

## 6. Conversion gate checklist

- [x] §2–§4 decided by owner (17.07.2026, rev. 2)
- [x] §5 window inventory written
- [x] Battle windows brief drafted — `docs/design/battle-windows-brief.md`
- [x] Engine prerequisites landed (owner-supervised, 17.07.2026): spell
      mechanic removed, emergency wave, REAP_FALLEN permadeath + auto-bank
      (wired into battle.victory/battle.escaped), game-over condition,
      row flag + `a.row` formula token. battle.log stayed byte-identical
      (the golden fixture's spell cast became the same skill cast by its
      owner), so no sanctioned regen was needed.
- [ ] Shared cost/gain gauge-preview widget (windows schema feature)
- [ ] Battle scene converted to `"draw": "windows"`
- [ ] Legacy renderer path deleted from `main.lua` / `presentation/`
