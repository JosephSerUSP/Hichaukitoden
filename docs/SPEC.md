# Hichaukitoden — Living Spec

The single current-state authority for architecture and design rules.
`BIBLE.md` (root) points here; everything under `docs/archive/` is a
**historical** record of how each overhaul round got us here — read those
for context, never as instructions. If code and this document disagree,
that is a bug in one of them: fix it or flag it, don't silently pick one.

Last consolidated: 2026-07-24 (legacy-purge round; battle/ritual/reserve
scenes now windows-drawn, Summoner economy live).

---

## 0. Why this engine is shaped this way

**Eventing is the backbone.** This engine is a deliberate recreation of building
whole systems out of RPG Maker 2003-style event blocks -- by an author with 20+
years in that engine -- except the blocks are far more powerful and **the engine
itself is made of them**. Battle phases (`data/flows.json`), scene logic
(`data/scenes.json` hooks), recovery sites and quest handling
(`data/commonEvents.json`), map events and traps are all command lists an author
can open and change without touching Lua.

Everything in Sec.1 follows from that goal rather than the reverse:

- A feature belongs in the command language first. If it can be a command list,
  that IS the implementation -- not a prototype of one.
- When Lua is unavoidable, add a **reusable primitive** data can compose (a
  registry command, a ref/scope, a formula token), never a one-off special case.
  `FOR_EACH`'s `neighbor` ref serves any adjacency trait; `x.trait.<CODE>` made
  every trait readable from data at once.
- Don't build a bespoke mechanism where an event already suffices: traps are
  plain events with a step trigger, so there is no "trap system" to maintain.
- Widening the command language lifts every author at once -- including the
  campaign generator, which emits the same commands.

---

## 1. Architecture

### 1.1 Data drives the engine

- **All game content lives in `data/*.json`** — actors, items, skills,
  passives, states, roles, elements, maps, events, commonEvents, quests,
  shops, sounds, themes, terms, animations, scenes, flows, system, engine.
  `data/loader.lua` loads them; Lua never hardcodes content.
- **`data/engine.json` is the registry**: command definitions (id, params,
  contexts, interactive flag), effect types, trait codes, meta keys,
  formula tokens. Adding a command/effect/trait means a registry entry +
  a handler — the validator and the editor pick it up from the registry.
- **Flows are the single source of truth for phase logic.**
  `data/flows.json` maps phases (`battle.victory`, `battle.defeat`,
  `battle.encounter_check`, …) to command lists run in immediate mode by
  `engine/interpreter.lua`. There are no legacy Lua fallback blocks; hosts
  call `flow.run(phase, ctx)` unconditionally and the validator requires
  the phases they depend on to exist and execute.
- **One command language, one interpreter** (`engine/interpreter.lua`).
  Map events, common events, battle phases, and scene hooks all compile
  through it. Interactive commands (TEXT, CHOICE, …) compile to dialogue
  graphs; non-interactive runs compile to immediate-mode blocks
  (RUN_IMMEDIATE bridges mixed lists).
- **Formulas, not scripts** (`engine/formula.lua`): numeric/boolean params
  accept sandboxed expressions over registry-declared tokens
  (`session.encounterRate`, `enemy.maxHp`, …). The sandbox rejects any
  environment access (`os.*` etc.).
- **SCRIPT is a sandboxed escape hatch, rationed.** Default battle phases
  are zero-SCRIPT (the validator enforces it); elsewhere SCRIPT usage is
  counted and reported at every validate run so growth is visible.
  `engine.json scripting.allowRawAccess` defaults to false and the
  validator asserts that.

### 1.2 Presentation

- **Scenes are data** (`data/scenes.json`): `{id, name, kind, draw, hooks,
  scripts, windows}`. **Every scene declares how it draws** — there is no
  host-side fallback (24.07.2026); an unrecognized `draw` is a hard error in
  `scene_host.draw` and a G1 failure:
  - `"draw": "windows"` — rendered entirely from the `windows` array by
    `presentation/window_renderer.lua`. 14 of 15 scenes, battle included
    (the old "legacy-drawn holdout frozen pending Summoner rework" state is
    over). Such a scene may also set `"backdrop": "map"` to show the world
    behind its windows, VN-style.
  - `"draw": "world"` — a world view named by `world` (registry:
    `presentation/world_renderer.lua`), with the scene's windows layered on
    top by the same window renderer. Only `map` (`world: "map"`, the
    raycaster) uses this. The old `town` scene — legacy-drawn, unreachable,
    superseded by the town *map* — was deleted in the purge.
- **The Summoner rework is live**: per-round MP drain in battle
  (`engine/battle.lua`), per-step field drain (`engine/exploration.lua`),
  sacrifice with level-scaled EXP/rewards (`SACRIFICE_EXP_RATE` trait),
  species unlock flags, and the shared `ritual` scene
  (summon/promote/sacrifice) plus `reserve` scene.
- **`presentation/renderer.lua` is live shared presentation, not a legacy
  renderer** — despite the name it holds window-content drawers that
  `window_renderer` dispatches to (enemy row, battle log, victory panel),
  cross-cutting FX services (damage popups, text reveal, battle anims), and
  coordinate helpers. Treat it as a shared library; do not "migrate off" it.
- **The engine never requires presentation.** Where a command or SCRIPT api
  call needs presentation (is the battle log still revealing? re-point at a
  swapped session?), the host injects hooks via
  `interpreter.bindPresentation` (bound in `main.lua`); unbound, every hook
  degrades to a no-op/false so headless runs work.
- **Animations are data** (`data/animations.json`): typed track lists
  (tint, blend, transform, shake, particles, force_field, gradient_map,
  screen_flash). `system.*` reserved entries (damage_flash, shake, death,
  …) must exist and hard-validate; assignable entries soft-validate so new
  track types can ship data-first.
- **Targeting is one resolver** (`engine/targeting.lua`): declarative
  target specs on skills/items, expanded by `targeting.expand` for both AI
  and player paths. `expand` errors on unknown specs; the validator gates
  every spec in data.

### 1.3 Campaign roots (18.07.2026, "no-move" design)

- **`data/` IS the default campaign.** `campaigns/<name>/` directories are
  drop-in alternates carrying the same file set. Nothing else moves.
- Active root resolution (data/loader.lua `resolveRoot`): CLI arg
  `campaign=<name>` > `campaign.json` pointer at the repo root
  (`{"active": "<name>"}`) > `data/`. The dev server's `/data`/`/save`
  endpoints and `engine/config.lua` follow the same root.
- G1 validates whatever root is active. Golden logs (G2/G3) are recorded
  against the default campaign only — run gates with `data/` active.
- **Non-default `campaigns/<name>/` roots are disposable test artifacts**
  of the generation pipeline (21.07.2026 decision). They are not held to
  sync parity with `data/` — a scene/menu feature landing in the default
  campaign does not obligate porting it to `thestra_no_jijou_2/3/4` etc.
  Regenerate them from the pipeline when needed instead of hand-syncing.

### 1.4 Scene layout convention: context-help bar + bottom dock

Every `"draw": "windows"` menu scene shares one skeleton instead of each
scene inventing its own chrome:

- **Top: a "CONTEXT HELP" bar** (style `frame`, full width, docked at
  `y=0`). It never holds a fixed hint string — its `content` text is a
  formula keyed on scene state (`v.state`, `v.combatState`, …) so the same
  window reads as nav hints in one state and as contextual explanation
  (an item/equip description, victory spoils, …) in another. This replaces
  the old pattern of a separate description/info panel next to a static
  "UP/DOWN: select ENTER: use" bar — one window, state-dependent text, no
  redundant real estate. (Applied to the `items` scene's `help` window and
  `battle`'s `battle_help` window during `victory`.)
- **Bottom: a persistent dock**, one of two things depending on scene:
  1. **Persistent party status** — the current/selected member's compact
     status, always visible regardless of what's happening above it.
  2. **Context-aware content laid out like the dialogue box** — left pane
     is an info panel (portrait/name/stat summary), right pane is the
     larger, interactive pane (lists, explanations, previews — anything
     the player can act on lives here, not in the narrow left pane).
  Both variants share the dialogue scene's exact footprint and column
  split: left column width starts from `battle_layout.partyGridColWidth`
  (68px = 8.5 tiles — the same fixed cell width `actor_status.draw` uses
  everywhere else) but widens as needed (currently 9.5 tiles, to fit the
  status dock's stats), right column takes the remaining width. **The
  left column's width is the authority**: if a scene's info panel needs
  more room to read cleanly, widen the shared dialogue footprint to match
  rather than shrinking the info panel's content — don't let two scenes
  drift to two different "narrow left column" widths, and don't let the
  same width live in two places either (`data/engine.json`'s windowLayout
  entry AND a scene's own `rect` both set x/y/w/h — the scene's `rect`
  always wins, so when the shared width changes, both need editing or the
  engine.json one silently does nothing).
- A scene can layer scene-specific chrome above this dock (e.g. status's
  equipment-slot header + portrait), but the dock itself — and the
  context-help bar — should look and behave the same everywhere it's used.

### 1.5 Extensibility (round-wide rule since o7, keep it)

Every schema tolerates unknown future fields: readers ignore keys they
don't understand, validators warn rather than reject on unrecognized
*optional* fields, and new entry types arrive behind `kind`/version
discriminators.

**Scope narrowed (24.07.2026, owner decision):** this rule protects
*future* fields and shipped-player data only. Repo-owned content
(`data/*.json`, campaign roots, save files — saves are test artifacts for
now and may break freely) gets migrated in place when a schema changes;
dual-read shims for old shapes of our own data are carrying cost, not
compatibility, and should be deleted after a one-time migration.

Removed under this rule (24.07.2026):

- the deprecated command aliases (GIVE_ITEM/TAKE_ITEM/GIVE_ITEM_ID/DRAIN_MP/
  RESTORE_MP → CHANGE_ITEM/CHANGE_MP);
- the dual `type`/`cmd` command-key format — **every command stores its id
  under `cmd`**, and the editor no longer mirrors an interactive-id table to
  decide which key to write;
- the dual `script`/`commands` name for sub-command lists — **`commands` is
  the only name**, on events, event pages, CHOICE options and recruitEvents;
- the redundant `tiles{}` tileset mirror (`features[]` is the sole source of
  feature ids, per §1.8) and its merge in `viewport_3d.lua`;
- the `ui.elementIcons` config + hardcoded icon table in `actor_status.lua`
  (nothing set the config and the table had drifted out of sync with
  `elements.json`; one `UNKNOWN_ELEMENT_ICON` constant remains);
- main.lua's 1,351-line inline copy of the validator — `engine/validator.lua`
  was a near-identical extraction that **nothing ever required**, so the CLI
  branch now calls `validator.run(loader)` and main.lua shrank 2,737 → 1,375
  lines;
- scene_host's legacy-Lua-draw fallback, together with the `town` scene that
  was its last user: every scene now names its draw mode (§1.2), main.lua's
  `love.draw` fallback branch is gone, and G1 gates the contract. Also gone
  with town: `renderer.drawTown`, its background image load,
  `townSelectedIdx`, ~40 lines of main.lua keypress handling,
  `system.json`'s `town.options`, the editor's `townOptions` widget, and
  `tools/golden/scene_town.log`. Save/load defaults moved `"town"` → `"map"`;
- `interpreter.lua`'s `pcall(require, "presentation.renderer")`
  engine→presentation layering violation, replaced by the injected
  `interpreter.bindPresentation` seam (§1.2). `viewport_3d.draw` also
  self-initializes now instead of trapping callers who never ran the boot
  sequence.

**The purge is complete** — no known dual-read paths, compat shims, or
legacy fallbacks remain. `presentation/renderer.lua` was investigated and
deliberately NOT split: it is live shared presentation (§1.2), so a file
split would be churn with regression risk and no functional gain.

### 1.6 Map cell overrides (unified, 23.07.2026)

`mapData.overrides` is a flat array of `{x, y, visual, passable, mutateTo,
hidden}` entries (0-indexed, author-facing) — the single per-cell escape
hatch, replacing the old dead `tiles{}` grid and the lamp's free-text
`material` field (see `docs/design/tileset-and-events-redesign.md` §8.1):

- `visual` — a feature/material id resolved against the tileset's merged
  `tiles` table (same id space as `data/tilesets.json`'s `features[].id`);
  wins over generated light-object materials.
- `passable` — overrides the layout char's solidity (illusory wall = `true`
  despite `#`; one-way/blocked floor = `false` despite `.`).
- `mutateTo` — a pending structural-mutation target (`"#"`/`"."`/`"o"`),
  applied by the `MUTATE_TILE` command (`engine/exploration.lua: mutateTile`)
  and cleared once consumed.
- `hidden` (on the *event*, not the override) — an event at an overridden
  cell renders nothing until that cell's `mutateTo` has been consumed.

`engine/exploration.lua: buildOverrideIndex` indexes this once per map load
(`session.overrideIndex`, keyed 1-indexed `"x,y"` to match `session.mapGrid`).

### 1.7 Structural `opening` cell (23.07.2026)

`"o"` is a third layout char alongside `"#"`/`"."` — a doorway/gate/arch the
player walks through (design doc §2/§6), distinct from a decorative
`wall_event` door which sits on an actual `"#"` and is never passable. `"o"`
is passable by the existing `~= "#"` movement check (no change needed there)
but, unlike `"."`, still stops the raycaster's DDA loop and renders a frame
— `presentation/viewport_3d.lua`'s wall column loop treats `"o"` as a hit
alongside `"#"`, currently borrowing the door atlas row as a stand-in visual
(no dedicated weighted/adjacency-resolved opening variant yet — that's §3).
Authored via the map editor's Layout brush (`tools/editor/js/map-editor.js:
setPaintTool('opening', ...)`) or as a `MUTATE_TILE ... to="o"` runtime
mutation (hidden-passage reveal, per the override's `mutateTo`).

Still open design work: decoration-layer weighted variants, adjacency
predicates, prefabs (§3 of the redesign doc), and dungeon-generation
authorship of `opening` cells (currently hand-authored only).

### 1.8 Tileset Studio: variant pools, not cell painting (23.07.2026)

`tools/editor/js/tileset-editor.js` (design doc §7) now treats the atlas
canvas as a **coordinate picker**, not the authoring surface — a "Wall"
click used to always overwrite `base.walls[0]`, which is why `weight` fields
existed with nothing to weigh against (§0). The primary surface is now a
**Variant Pools** list per structural role (Walls/Floors/Ceilings/Wall
Fixtures/Floor Fixtures/Doors): select a pool entry (or add a new one),
*then* click the atlas to assign that entry's coordinates. Deleting/adding
goes through the real backing array (`tilesetData.base.walls`, `.floors`,
`.ceilings`, `.features` filtered by role, `.doors`), so pools can actually
hold N weighted variants now.

The redundant `tiles{}` mirror the old editor dual-wrote alongside
`features[]` (dead per §0 — nothing ever read it by map cell) is dropped on
save; `features[]` is the single source of truth. `presentation/
viewport_3d.lua`'s atlas loader no longer merges a legacy `tiles{}` at all —
the mirror was purged from both the loader and `tilesets.json` on 24.07.2026
(see §1.5).

**Base walls are a fixed 128×64 block, authored with one click.** The old
per-slot model (three independently-clickable targets — middle/leftEdge/
rightEdge — chosen via a slot radio) let an author scatter them anywhere in
the atlas, including on top of unrelated fixture cells; the engine only ever
renders leftEdge/rightEdge as 32px-wide *halves of a single cell* anyway
(`viewport_3d.lua:838-851`, offX 0 vs 32). The editor now matches that: click
a wall variant's **middle** cell in the atlas and the cell immediately to
its right is auto-assigned as both edges (offX 0/32), matching a spritesheet
laid out as `[wall middle][wall edges]` side by side — e.g. `town_test.png`
(256×128, 4×2 cells): row 0 = `[ceiling, floor, -, -]`, row 1 = `[wall
middle, wall edges, fixture 1, fixture 2]`, authored by clicking (1,0) for
the wall, then (1,2)/(1,3) for the two wall fixtures. The underlying schema
(`middle`/`leftEdge`/`rightEdge` triples) is unchanged, so existing data with
edges elsewhere in the atlas still renders — only new authoring assumes the
fixed layout.

Not in scope for this pass (§3, still open): actual weighted-random
*resolution* at render/generation time (the pools are real now, but nothing
picks between variants by weight yet), adjacency/context predicates,
prefabs, and zone/region tagging.

### 1.9 Item vocabulary (26.07.2026)

The item atlas planned in `docs/design/item-atlas-expansion.md` needs an item
to answer several independent questions at once — when it may be used, what it
restores, whether Item Creation may consume or produce it — and each of those
was previously either unauthorable or silently ignored. The primitives below
exist so that atlas can be authored without content-specific Lua. They are
reusable and registry-backed; none of them names an item.

**Use occasion.** `item.scope` is the independent occasion axis:
`always` (the unauthored default), `battle`, `field`, `none`.
`engine/usability.lua` has always branched on it; what is new is that
`engine.json -> itemScopes` enumerates the four words, **G1 fails an unknown
scope**, and the editor's Use Occasion select is built from that registry.
This is a fail-loud fix, not a feature: an unrecognized scope fell through
usability's if-chain to "usable everywhere", so a typo'd `feild` read as a
restriction and behaved as none.

**Percentage recovery.** The `hp` and `mp_heal` effects take `percent`
alongside `value` — a share of the recipient's Max HP and of the summoner's
Max MP respectively. Either part may stand alone, so one effect type covers
flat, percentage and hybrid restoration. The percentage form is what keeps a
food meaningful across creatures whose Max HP differ by an order of magnitude,
and a draught meaningful as Max MP climbs.

**Permanent Max MP.** `max_mp_plus` raises `session.maxMp` (already saved),
clamped to `system.summoner.maxMpCap`, and restores what it added. Usability
refuses the item at the cap rather than consuming it for nothing, the same
guard shape full-HP and known-skill items use.

**`ITEM_EFFECT_RATE`.** RPG Maker's Pharmacology: multiplies the magnitude of
item effects. It is read from the **recipient**, not the wielder, because
field item use has no separate wielder — a rate read from the user would do
nothing for every meal eaten outside battle. Skill effects are deliberately
untouched; this is a constitution, not a spell amplifier. Permanent gains
(`param_plus`, `maxHp`) are untouched too: an item that grants +1 ATK forever
grants exactly that.

**Ingredient exclusion.** `meta.craftIngredient: false` keeps an item out of
Item Creation *ingredient selection*, independent of `meta.craftable: false`,
which only excludes *outputs*. Both exclusions are needed because the two
policies differ: monster remains are ingredients that are never produced, and
a promotion key is neither. `craft.isIngredient` is the one shared reading;
the crafting scene applies it through the list `filter` below, and G1 reports
the count of items outside Item Creation entirely.

**List `filter`.** `SET_LIST` (and the equivalent declarative list block)
takes a `filter` row formula that **drops** rows, where `priority` only sorts
them first. It runs before the sort, so a hidden row cannot be selected,
counted, or landed on by a cursor. Item Creation must not merely bury a
promotion key at the bottom of the ingredient list, and every future
"selectable subset of a list source" is the same problem.

### 1.10 The damage model (26.07.2026)

Damage is **relative**: a share of the attacker's power decided by the ratio
to the defender's matching stat, per `docs/design/creature-parameters.md`.

```text
potency * power^2 / (power + defense)
```

The useful property is the share table — 100% of power at zero defense, 50% at
`defense = power`, 33% at twice, 25% at three times. It never reaches zero, so
scratch damage is real and a Pixie punching a Golem is meant to be an almost
useless action rather than an impossible one. It replaced a `val * (10 / DEF)`
divisor that got this backwards at low DEF and had no notion of potency.

Resolution order is fixed, and `resolveDamage` in `engine/effects.lua` is the
one implementation — `hp_damage` and `hp_drain` share it so a drain can never
drift from the curve:

```text
relative damage -> potency -> element -> critical x1.5 -> DAMAGE_RATE -> floor 1
```

**Stat pairing.** `power` names the attacker's stat and `defense` defaults to
the stat it is paired with: `atk` meets `def`, `mat` meets `mdf`. An
exceptional skill may author `defense` to cross them. This matters more than it
sounds: before it, *every* action reduced through DEF, so a creature could
advertise ruinous MDF and never once be hit through it — Golem's entire
promised identity was unreachable. Archangel's Holy Smite against Golem went
3 → 15 on this change alone.

**Direct damage.** An effect authoring `formula` *instead of* `power` is the
direct path: the authored number lands as-is. A trap that says 20 deals 20. It
takes no critical and no `DAMAGE_RATE`, matching the rule that guarding does
not blunt authored indirect damage. These are two authored intents, not a
compatibility shim — the relative path is for actions with an attacker, the
direct path for authored consequences.

**Criticals** roll in `effects.lua` rather than `battle.lua`, so every damaging
action gets them on one code path and a multi-hit action rolls per hit as the
design requires. Base rate is 5% (`traits.getRate`'s `CRI` default), multiplier
is `system.combat.criticalMultiplier` (1.5 — permadeath makes larger defaults
excessively volatile). A critical is reported on the damage event and gets its
own `critical|` line in the golden log, because a crit and an ordinary hit for
the same total are otherwise indistinguishable to G2.

Criticals also carry Brigandine's status rule: a damaging action that crits
guarantees the status attached to it, bypassing the authored chance. That is
why `APPLY_EFFECT` builds **one context per target** shared across the action's
effect list — the damage effect records the crit on it and the `add_status`
effect after it reads it. (The design also exempts explicit immunity, which
waits on `STATE_RATE`; see the gap ledger.)

**Round-end HP drift** is the `HRG` trait summed across every source, applied
by `STATE_TICKS`. Negative is degeneration, so poison is not a second
mechanism — one trait, both directions, the way RPG Maker's works. A rate too
small to move a creature emits no event rather than a `+0` line. This replaced
a branch on `state.id == "regen"` / `"poison"`, which hardcoded two content ids
in the engine, left `HRG` dead everywhere it was authored, and meant only the
one id the engine named could ever regenerate — a second regenerating state
was unauthorable.

**`DAMAGE_RATE`** multiplies direct HP damage taken by its holder, and is
**multiplicative** across sources, unlike the additive rate traits — two
independent 0.5 protections must be a quarter, not zero. Defend is now
`DAMAGE_RATE 0.5` rather than doubled DEF, which was worthless against magic
and had inconsistent value under the relative curve. The same trait serves
barriers, protective equipment and vulnerability states.

---

## 2. Design rules (from the BIBLE — enforced by review)

### 2.1 Code sharing and reuse (CRITICAL)

No copy-pasted logic or coordinate mappings. Layout systems (party grid,
window geometry) are shared helpers used by exploration menus, battle
consoles, and target overlays alike. Math/physics (gravity, bouncing,
interpolation) lives in general update code, not scattered ad-hoc.
This applies to the editor too: form fields come from the schema layer
(`tools/editor/js/entity-forms.js`, `CONFIG_SCHEMA`), not hand-written DOM.

### 2.2 UI aesthetics

- Rich vertical gradients for major menus — never flat dark overlays.
- Micro-animations: panels slide in/out via timer states.
- Elements render as colored orb bullets from the system iconset
  (`data/elements.json` supplies the icon).

### 2.3 Battle feel

- Gauges never jump: smooth interpolation for damage and healing.
- Actors flash white/cyan on action, red on impact (system animations).
- Damage numbers launch with velocity and bounce under gravity.

---

## 3. Gates (what keeps all of the above true)

| Gate | Command | Guards |
|------|---------|--------|
| G1 validate | `lovec . validate` → `VALIDATE OK` | Cross-references (every id link in data, incl. graphs/quests/scriptIds), command trees vs registry, formula compilation, targeting specs, scene windows, animation tracks, meta keys, zero-SCRIPT battle phases, required flow phases. |
| G2 golden battle | `tools/golden/check.ps1` | Battle simulation event log byte-identity, one reference per fixture (`tools/golden/battle_<key>.log`; fixtures authored in `data/goldenBattles.json`). Never regenerate to silence a red diff — regeneration is a reviewed, owner-signed action. |
| G3 golden UI | `tools/golden/check-ui.ps1` | Per-scene UI trace identity for every scene. |
| G4 engine state | `tools/golden/check-state.ps1` | `docs/ENGINE-STATE.md` matches what the engine actually reports (scene inventory + draw modes, registry counts, **registry entries with no implementation**, flow phases, content inventory). |

The `[formula] error in 'os.time()'` line during G1 is the sandbox
negative-test, not a failure. The editor runs G1 automatically after every
save (`/validate` endpoint) and surfaces problems in the UI.

**G4 is a documentation gate, and its failure mode differs from G2/G3.** A red
G2/G3 means a behavioral regression to investigate; a red G4 means the generated
doc is stale — run `tools/golden/capture-state.ps1` and commit the result. It
exists because documentation drift is a real, measured cost here: on 24.07.2026
four separate documents asserted implementation facts that had become false
(battle "frozen" on the legacy renderer, permadeath "not implemented", Item
Creation "quite early", the validator's location), which produced a wrong plan
that had to be walked back. Stale docs are worse than absent ones — they cost
rediscovery *plus* an incorrect conclusion. Hence: **prose states intent;
generated output states status.** `docs/ENGINE-STATE.md` is never hand-edited.

Its "registry entries with no implementation" section is the drift detector that
matters most: it distinguishes entries implemented in Lua, entries implemented in
data (a flow/scene consuming them), entries merely *assigned* to content with
nothing consuming them — these lie to the player, which is what `ON_PERMADEATH`
did for months while the `rebirth` passive advertised it — and entries declared
and never referenced at all.

### 3.1 Coherence vs. reachability

G1 asks whether a reference *resolves*. Two further questions do not reduce to
that, and they are answered in two different places on purpose.

**Coherent pairs are G1's job.** Where two pieces of data name each other but
only one side is ever read at runtime, the unread side is invisible dead data —
it cannot fail, it simply never happens. `elements.json` carried "White is weak
to Green" for a long time while `effects.lua` read only the attacker's lists, so
that penalty never landed on anyone; G1 now requires affinity to be reciprocal.
The same shape recurs, and each of these is now a G1 failure: a trait whose
`dataId` disagrees with the registry's `usesDataId` declaration (or names a param
`traits.getParam` never reads, or a dropped element); a `remove_status` effect
naming a state that no longer exists; a map `treasures`/`recruits`/`encounters`
pool entry that resolves to nothing (these are indexed by a random roll at
runtime, and `session:addItem` stores whatever it is handed, so a stale id became
a phantom inventory row — four such ids had two floors of chests handing out
nothing); an evolution `cost.item` that is not a `promotion_key`; a discipline
`stat` that is not a readable param; and a `flag:<name>` condition that no
`SET_FLAG` or quest reward ever writes, which is a branch the player can never
take. The reverse flag direction (written, never read) only warns: a flag may
legitimately be staged ahead of the content that reads it.

**Reachability is a report, not a gate:** `lovec . reachability`. It sweeps for
content that resolves but that nothing can produce — items no reachable shop
sells and no craft yields, shops no `OPEN_SHOP` opens, creatures no pool or
promotion path grants, states nothing applies, common events nothing calls — and
it swings the real Item Creation model over its whole possibility space
(`engine/craft.lua`, every ingredient pair × every crafter, at the ideation
centre) rather than re-implementing it. It always exits 0 **by design**: "nothing
produces this yet" is normally a design observation, and authors legitimately
build content before its source, so gating it would punish the ordinary order of
work. Read it, judge each entry, then either wire up the source or delete the
content. The repo-wide caution about "is this referenced?" sweeps applies to it
in full: ids are also resolved at runtime from pools and hooks, so each section
names the exact producers it knows about, and a new kind of producer must be
taught to the sweep rather than the sweep weakened.

Mechanical-rule enforcement map: registry/context/zero-SCRIPT/dangling-id
rules → G1; **paired-data coherence → G1; reachability → the advisory
`reachability` report**; behavioral regressions → G2; scene rendering → G3; the
aesthetic and code-sharing rules (§2) are review-enforced — call them out
in PR review when violated.

---

## 4. Editor (tools/editor)

- Vanilla JS + Node server (`server.js`), no build step. Data round-trips
  through `/data` and `/save` with stale-save (409) and shape guards.
- Database tabs are schema-driven where possible: `ENTITY_FORM_SCHEMAS`
  (entity tabs) and `CONFIG_SCHEMA` (system/engine config). A new simple
  tab should be a schema entry, not a bespoke panel. Complex editors
  (animation timeline, event commands, map painter) are custom by design.
- Previews go through the REAL engine (`lovec . preview-*`) — the editor
  never approximates rendering in the browser.
- Validation goes through the real engine too (`lovec . validate` via
  `GET /validate`) — no duplicated schema in JS.

---

## 5. Process

- **`AGENTS.md` (repo root) is the agent entry point** — document authority,
  gate commands, non-negotiables, and the gotchas that cost real time. `CLAUDE.md`
  just points at it. Keep it short; architecture rules belong in THIS file.
- **Document authority order**: `docs/ENGINE-STATE.md` (generated, what exists) >
  this file (how and why) > `docs/design/` + `docs/game design/` (intent only,
  never status) > `docs/archive/**` (frozen, never authoritative).
- `docs/ORCHESTRATION.md` is the integrator runbook (branches, briefs,
  candidate evaluation). Gates above are its G1–G4.
- Owner-supervision rule: work touching `engine/battle.lua` /
  `engine/scenes/battle.lua` is owner-supervised, never autonomous.
- `docs/archive/plans/<round>/` directories are frozen history. New rounds add a
  directory; they do not edit old ones. When a round's rule survives, it
  gets merged into THIS file and cited from here.
