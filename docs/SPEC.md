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
    polygonal world renderer) uses this. Its world-space surfaces use hardware
    depth testing; the renderer clears only depth before later 2D presentation
    layers so battlers, effects and windows remain screen-space overlays.
    Camera-independent topology (floor/wall/opening cell lists plus wall-event
    and material lookups) is cached per session. Exposed wall faces then cache
    their resolved material, atlas UV orientation, edge overlays, event sprite
    composites and texture canvases per atlas. Map loads, `MUTATE_TILE`,
    `ERASE_EVENT`, and `SET_MAP_PRESENTATION` advance explicit revisions.
    Baked map light remains a static vertex attribute; player-light distance,
    fog visibility/banding and their nonlinear falloff now run in the world
    vertex shader from camera uniforms. Resolved walls, floors and ceilings own
    persistent three-level surface quadtrees; the live camera selects the same
    distance/area subdivision nodes the earlier stream-mesh path built. Selected
    nodes update an index list on one resident mesh per texture, so ordinary
    structural geometry is drawn in texture batches without rebuilding vertex
    buffers. A surface crossing the near plane deliberately falls back to the
    dynamic clipped path. Those clipped leaves are accumulated into one stream
    mesh per texture and surface category for the frame, rather than submitted
    as one GPU draw per leaf. These stream meshes are resident, grow to the next
    power-of-two capacity when necessary, and receive new vertices/draw ranges
    in place instead of being created and destroyed each frame. Root points,
    UVs and baked-light colors also live with the cached surface descriptor.
    Openings, billboards, visibility and near-plane
    clipping remain camera-dependent per-frame work rather than stale cached
    approximations. `lovec . profile-3d <mapId> <frames>` profiles this live
    path against a deterministic generated-map topology and reports structural
    batches, dynamic sources, dynamic mesh draws, timing percentiles and memory.
    The
    old `town` scene — legacy-drawn, unreachable,
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
  track types can ship data-first. An entry may author an `anchor` saying
  where on its target it attaches — see §2.4.
- **Battler placement is one module** (`presentation/battler_geometry.lua`):
  battler → rect, rect + anchor spec → point. Popups, animations, reticles,
  slot indicators and the enemy info block all read it. See §2.4.
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
- **Bottom: a persistent dock.** "Persistent" is now literal (29.07.2026):
  the dock is **not a scene's window**. It is one surface owned by
  `presentation/dock.lua`, whose state — window tables, animation clocks,
  visibility history — lives in that module and therefore survives
  `scene_host` push/pop/goto untouched. Scenes only declare *which variant*
  they want, via `config.dock` in `scenes.json`:

  ```json
  "dock": { "variant": "party_status", "cursor": "v.mode == 4 and v.partyIdx or 0" }
  ```

  The variants themselves live in `data/engine.json`'s `dock` registry, so
  adding one is a data edit; `cursor`/`visible` on the scene's dock config
  apply to the variant's declared `primary` window, and `windows: { <id>: {…} }`
  overrides any field of any window in it. An optional `offsetY` formula
  shifts the whole dock in pixels.
  Content still binds to the **current** scene, so `v.dialogueText` and
  friends resolve exactly as they did when the scene owned these windows.

  A variant declares an ordered, arbitrary-length `shells` array plus the
  content windows that occupy those shells. Transitions use one shared
  language rather than scene-specific effects: same variant on both sides
  animates nothing; on a variant change all content clears, shared shells
  morph to their destination rectangles, removed shells collapse horizontally
  to zero width, added shells grow horizontally from zero width, and only then
  does destination content appear. Leaving for a scene with no dock collapses
  every shell. This supports today's two-pane map/battle/dialogue layouts and
  future three-or-more-pane layouts without another compositor path.

  This replaced five copy-pasted `party` windows, a runtime-opened one on
  `map`, and a third copy drawn by `frame_renderer` for battle — plus the
  three band-aids that existed because the dock used to be destroyed and
  rebuilt on every scene change (`config.windowFootprint` /
  `_seamlessWindowFootprint`, the map-specific `_skipOpenAnim` block in
  `love.update`, and `frame_renderer`'s 0.15s `dialogueEnterTime` overlap).
  All are deleted; do not reintroduce a per-scene copy of the dock.

  **Not yet folded in:** `reserve_party` and `status_dock` are still
  scene-owned windows over the same footprint, and until they move those two
  scenes cut rather than dock-morph. Neither is a simple data edit:
  `reserve_party` is read by name from Lua (`drawSwapIndicator` in
  `window_renderer.lua`), and `status_dock` binds through
  `sel('status_party')` — a *scene* window — while a dock variant's list cache
  only covers the dock's own windows. `shop_party` and `ritual_party` had no
  such coupling and are gone; both are now `party_status` with a scene-level
  `visible`/`cursor` override. (Note `ritual_party`'s `gridColumns: 2` was
  inert — that key is only read from `windowLayout`, and 2 is the default.)

  **What actually covers the dock:** not the G3 UI *trace* — those lines are
  window commands emitted by scene hooks, so a declarative window of any kind
  is invisible to them (this is why a fully declarative scene's trace is one
  line). The dock is covered by G3's per-step **draw smoke test**, which calls
  `scene_host.draw` and fails the gate if drawing throws, and by
  `tests/test_dock.lua`, which pins the parts that have no visual signature —
  above all that the dock's window table is the *same table* after a
  same-variant scene change, which is what makes its animation continuous.

  The dock's shells carry scene-specific roles:
  1. **Persistent party status** — the current/selected member's compact
     status, always visible regardless of what's happening above it.
     The creature card in that pane is **one renderer**
     (`renderer.drawBattlerCard`): sprite, elements, name, level, HP bar and
     states, drawn identically by battle's target pane and the status menu, so
     the readout a player learns while fighting is the one they get while
     planning. What it *shows* varies by caller — status opts into an EXP
     gauge, battle does not — because the rows a creature needs differ by
     where you are reading it. That is a flag on one card, never a second
     lookalike card.

     **A creature's name always carries its element icons** — "🟢Saban", never
     a bare "Saban" — and that is one function,
     `actor_status.drawCreatureName`, not a convention each surface remembers
     to follow. The sequence it owns (resolve effective elements, draw icons,
     measure, offset the name, clip the name to what is left) used to be
     hand-rolled per site, and the sites that forgot it were the tell: the
     party cell, target card and victory report drew icons; the level-up
     report and the status headline did not, so the same creature read as two
     different things depending on the menu. A name rendered from an
     interpolated `"{name}"` string can never satisfy the rule, which is why
     the status headline is a `creatureHeader` window rather than a `text`
     one. Sentences in the battle log are the deliberate exception: prose
     names a creature mid-clause, where an icon would break the line.
  2. **Context-aware content laid out like the dialogue box** — left pane
     is an info panel (portrait/name/stat summary), right pane is the
     larger, interactive pane (lists, explanations, previews — anything
     the player can act on lives here, not in the narrow left pane).
  Both variants share the dialogue scene's exact footprint and column
  split: left column width starts from `battle_layout.partyGridColWidth`
  (68px = 8.5 tiles — the same fixed cell width `actor_status.draw` uses
  everywhere else) but widens as needed. It is **15 tiles** as of
  01.08.2026: battle's target pane was already 15 while status's was 9.5,
  which is exactly the drift the rule below forbids, and the creature card
  they now share is unreadable narrower (it rendered "Saban" as "Sab").
  The right column takes the remaining width. **The
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
- Shop and Items use the `item_inspect` dock variant. Their top help bar shows
  the selected item's authored description (flavor); the dock's lower-left
  shell derives gameplay text from the item's live `effects`, `traits`, and
  Savor traits using registry labels. The untitled upper-right showcase
  resolves the selected item's optional `keyArt` image, with a clear empty
  state.

### 1.4.1 Datalog

Lore is authored in `data/lore.json`, keyed by stable string id. Each entry has
a title, category, body, optional numeric order, and optional `unlocked: true`
for knowledge available from a new game. Runtime discoveries use the registered
`UNLOCK_LORE` event command; the session stores only unlocked ids and save/load
round-trips them. The `datalog` scene is an ordinary windows-drawn scene whose
`LIST_UNLOCKED_LORE` hook command materializes display rows. This keeps lore
content, discovery triggers, and menu behavior in the same data/event surfaces
as the rest of the engine.

The field main menu uses the battle command console's shared geometry and may
author no more than five top-level commands. Its current four commands are
Items, Party, Data, and Options. Party opens View, Reserve, Quests, and Notes;
Notes is the player-facing name for the `datalog` scene. Data contains Save and
Load.

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
- the dual `script`/`commands` name for owned command lists — **`commands` is
  the only name**, on events, event pages, CHOICE options and recruitEvents
  (`scriptId` remains the distinct common-event template link described in
  §4.1; it is not an owned list);
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

**Correction (26.07.2026): the purge missed three, and they are now gone.**
Three `if flow.has(phase) then ... else <legacy Lua> end` fallbacks survived
the first pass, because they predate the rule and read as deliberate ("SPEC
S4 fallback"). They were not: hosts call flow phases unconditionally and the
validator requires them, so every `else` arm was unreachable — a second
implementation kept alive by nothing but its own comment.

The round-end one proved the cost. It had already drifted: it still branched
on `state.id == "regen"` with rates from `system.json` after the live path
became `HRG`-driven (§1.13), so the two paths disagreed about what
regeneration *is*. The other two were a full duplicate flee roll (gold
penalty included) and a full duplicate weighted encounter spawner.

All three are deleted. `battle.round_end`, `battle.flee_attempt` and
`battle.battle_start` joined the validator's required-phase list in exchange:
with nothing to fall back to, a missing phase would silently skip every
end-of-round tick, make fleeing impossible, or spawn an encounter with no
enemies. That list does not merely check existence — it *runs* each phase
against a fresh session, so the three gained real smoke coverage in the
trade. `combat.regenRate` / `combat.poisonRate` went too: nothing else read
them, and the editor was still offering both as System settings that changed
nothing. The flee and encounter settings stayed, because `flows.json`
genuinely consumes those.

Map encounter entries may author `levelMin` and `levelMax` alongside `id` and
`weight`. `SPAWN_ENEMIES` resolves a level independently for every spawned
enemy and constructs the battler at that level. Omitting both fields preserves
the actor's authored default level and consumes no additional random draw.
`levelMax` requires `levelMin`; G1 rejects non-integers, inverted ranges, and
non-positive weights. The map editor authors and displays the range.

`flow.has` now has exactly one caller, the validator's required-phase check
— which is the job it should have had all along: proving a phase exists, not
choosing whether to use it.

`presentation/renderer.lua` was investigated and deliberately NOT split: it
is live shared presentation (§1.2), so a file split would be churn with
regression risk and no functional gain.

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
but, unlike `"."`, carries structural renderer geometry. The polygonal world
path resolves its axis from the surrounding wall pair and draws a passable
three-piece frame (two jambs and a lintel) sampled from a deterministic weighted
pick in the tileset's door pool, or draws that variant's model when authored.
Authored via the map editor's Layout brush (`tools/editor/js/map-editor.js:
setPaintTool('opening', ...)`) or as a `MUTATE_TILE ... to="o"` runtime
mutation (hidden-passage reveal, per the override's `mutateTo`).

Procedural maps may opt into `generateOpenings:true`. During corridor carving,
the generator records cells actually cut out of walls and turns only those on a
room's outside threshold into `"o"`; room floors cannot become openings, and
entrance/exit stair walls are excluded. The result is deterministic for the map
seed, participates in generated corridor zones and ordinary fixture predicates,
and persists as part of the cached map grid. Map Properties exposes the option
only for procedural maps.

Room-count and room-size authoring lives in reusable
`system.dungeon.generationProfiles`, with one registered default selected by
`system.dungeon.generationProfile`. A procedural map may select another profile
with `generationProfile`; Map Properties lists the registered choices. The
repository's former per-map `genMinRooms`/`genMaxRooms` and system `gen*` fields
were migrated and have no compatibility read path. G1 validates profile ranges,
the default reference, every map reference, and rejects the removed fields.

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

The renderer now resolves base wall, floor, ceiling, door and opening pools by
authored positive weight. Picks are hashed from the map cell and a role-specific
salt: revisiting or reloading a cell cannot reshuffle it, rendering consumes no
gameplay RNG, and all faces of one wall cell share one variant. Omitted weights
default to one. G1 rejects non-positive weights and missing wall-middle or atlas
coordinates. Tileset wall/floor features resolve `injectProbability`
deterministically per cell and may author a recursive `where` predicate; placement
consumes no gameplay RNG. One feature occupies a cell. Placements persist in
`session.generatedFeatures`, separately from `generatedLightObjects`, so a
non-emitting fixture never acquires an implicit torch light. Wall features bake
their atlas cell into exposed wall composites; floor features draw a
depth-tested overlay above the base floor. Both roles may instead name a model:
wall models attach to visible faces, while floor models use cell centre.

`where` is a single-operator object composed from `all`, `any`, `not`,
`adjacent`, `distance`, and `zone`. Adjacency targets a tile class (`wall`,
`floor`, `opening`), a zone tag, or a feature placed earlier in tileset order;
it is cardinal unless `diagonal:true`. Distance is Manhattan distance and
explicitly targets either a zone or an earlier feature, with optional inclusive
`min`/`max`. G1 rejects malformed predicates, ranges and feature references.
The removed `requiresAdjacentFloor` field was migrated to
`where:{"adjacent":"floor"}`; there is no dual-read compatibility path.

Authored maps may declare overlapping `zones[]` as zero-indexed rectangles or
explicit cell lists, with one `id` or several `tags`. Generated dungeons persist
per-cell structural tags for `room`, `corridor`, `anchor`, `entrance`, and
`exit`. Both sources build one runtime index, so cells may carry several tags.
Tileset Studio edits predicates and Map Properties edits authored zone records.
Tilesets may define reusable `fixturePrefabs[]`. Each prefab has a unique `id`,
a validated `where` predicate, and an optional probability `{min,max,default}`
range. A feature authors either `prefab` or a custom `where`, never both; its
probability must remain inside the selected prefab's range. Tileset Studio
exposes the library and a prefab selector, and can detach a selection by copying
its predicate into the custom-rule editor. Runtime placement still evaluates
the same predicate implementation, so prefabs introduce no parallel rule path.

A map may author a sparse `tilesetOverride` instead of duplicating its base
tileset. The delta mirrors the pool structure (`base.walls/floors/ceilings/skies`,
`doors`, `features`, `fixturePrefabs`): entries merge by `id`, new ids append,
and an existing entry may be removed with `{id,remove:true}`. Nested objects
merge while coordinate/color arrays replace. `engine/tileset_resolver.lua` is
the single immutable resolver used by both fixture injection and the renderer;
loader-owned data is never modified, and overridden maps receive distinct atlas
cache identities. G1 rejects unknown delta fields, duplicate ids, malformed
removals, invalid resolved feature roles, predicates, prefab references and
probabilities. Map Properties exposes the sparse delta as JSON.

Door and fixture variants may also author an optional `model` project path
naming a static `.obj` kit piece. Tileset Studio exposes the field on those
pools and G1 requires the file to exist; a model-backed variant does not also
need atlas coordinates.
`presentation/obj_model.lua` is the single runtime loader: it supports OBJ
positions/UVs/normals, polygon triangulation, negative indices, generated face
normals, and MTL `Kd`/`map_Kd`, with nearest-filtered textures and one cached
static GPU mesh per material group. Unsupported directives, invalid indices,
degenerate faces, and missing MTL/texture files fail loudly. World kit pieces
use a cell-centred convention: OBJ `(0,0,0)` is the centre of the owning map
cell at floor level, one model unit is one cell, X/Y are the floor plane and Z
is up. Opening-axis changes rotate about that centre. Model-backed structural
openings render cached material groups through the same depth, fog, player
light and vertex-light path as procedural structure; their OBJ normals add
directional shading. Model-backed wall-event doors attach to their exposed
face, wall fixtures use that same face rule, and floor fixtures use cell centre.
Atlas-only variants continue unchanged. Base-wall/floor/ceiling model roles
remain closed; G1 rejects them rather than silently accepting a model the
renderer would ignore.

A floor feature variant may author `blocksMovement: true`, making it SOLID --
the player cannot walk through it. G1 rejects the flag on a wall feature, which
already stands on a `"#"`.

Solidity is resolved at PLACEMENT time, not at movement time, because the
predicates that place fixtures know nothing about topology: a solid fixture in a
one-wide corridor severs the map and one in an alcove mouth strands what is
behind it. Injection therefore enforces one invariant --

> blocking a cell may remove ONLY THAT CELL from the reachable set

-- which covers both failures at once, and additionally refuses the spawn, the
entrance/exit staircases and any cell carrying an event, since blocking those
severs nothing but makes something unusable. Candidates are validated
incrementally in authored order, so fixtures that are individually safe but
jointly a cut are caught too. A refused fixture is simply not placed; losing a
decoration is far cheaper than an unwinnable floor. Placement records carry
`blocks`, so solidity survives save/load without re-resolving the tileset, and a
map already in a save keeps the solidity it was generated with. An authored
per-cell `passable` override outranks a fixture that happened to land there.

Wall and floor feature variants may also author an Effekseer `.efkefc` asset,
plus optional `effectHeight` and positive `effectMagnification`. G1 verifies
the project path and parameter types, and Tileset Studio exposes the same
fields. The prepared 3D structure owns the resulting native handles: floor
effects start at cell centre, wall effects attach just outside their first
exposed face, and invalidation/map replacement stops them. They advance through
the shared deterministic Effekseer clock. World effects bridge the game's X/Y
floor and Z-up coordinates to Effekseer's X/Z floor and Y-up convention, then
draw directly through the polygonal camera while preserving its depth
attachment. Both `env_mist` and `env_rain` are deterministically sampled down a
corridor at frame 400 and visibly change the live viewport while that depth
buffer is populated.

Effect time is advanced in **one-frame sub-steps**. A single large `deltaFrame`
does not fast-forward Effekseer's simulation, it skips it — emitters fire per
simulated frame — and it also leaves the manager unable to emit for the next
effect played. Anything that advances effect time in bulk depends on this: the
screenshot harness's settle, the editor filmstrip, a load hitch.

A map may author one `ambientEffect` (`{effect, height, magnification}`) for
**weather**, which is a different role from a cell fixture rather than a
shorthand for one. It spawns a single handle per map and is moved to the camera
cell every frame at its authored height, so it always fills the view. Two
reasons it cannot be a per-cell feature: anchored to a cell it stays behind the
player, and one endless placement reaches ~1,900 live instances against a 2,000
manager budget, so a second would starve every other effect into spawning a root
that emits nothing. Cell fixtures (torches, braziers) keep one handle per
placement, which is correct and small. G1 validates the reference, the field set,
and a positive magnification; Map Properties authors it. Particles already in
flight are world-space and stay where they were emitted, so a teleport leaves a
brief gap while the new location emits — ordinary movement never notices.

Two rules follow for anything that measures a world effect, both learned by
getting them wrong (§6.5.1g of the roadmap): observe down a view with **receding
depth**, because a camera facing a near wall has every particle rejected by the
depth buffer and reports zero pixels while the effect emits healthily; and
sample while the effect is **alive**, because a finite effect past its end also
reports zero. Together those two produced a recorded claim that `env_rain`
"produces no pixels through the perspective pass" when it renders correctly.

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
item effects. It is read from the **user**, not the recipient. Battle items use
the acting creature; field items use the best living party carrier because the
field menu has no separate user selection. Skill effects are deliberately
untouched. Permanent gains (`param_plus`, `maxHp`) are untouched too: an item
that grants +1 ATK forever grants exactly that.

**`common_event` items.** An item effect that starts an authored common event
— the Forbidden Lamp opening a scripted encounter. It cannot run the event
itself: `CALL_COMMON_EVENT` is an *interactive* command that compiles to a
dialogue node, and immediate mode refuses it, so effects have no way to hand
control to the graph walker. The effect raises a `run_common_event` request;
`scene_host` defers it alongside scene transitions (so the graph starts on a
settled stack rather than mid-hook) and asks the host through
`interpreter.bindPresentation`'s `runCommonEvent`. Unbound — the validator, the
golden harness, any headless run — the request is simply unclaimed and nothing
errors. G1 fails an effect naming a common event that does not exist, because
such an item is the only gate on the content it calls.

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

### 1.10 Creature growth is seeded and accumulated (26.07.2026)

Growth is **additive, permanent, seeded per instance, and intentionally
uneven** — never recalculated from species and current level.

Each form authors budgets for three bands (levels 2–10, 11–20, 21–30) in
`actorData.growthBands`. An instance's `growthSeed` divides each budget into
uneven per-level packets (`engine/growth.lua`), which accumulate into
`battler.growth`. A stat is then simply `base + accumulated`.

What it replaced: `base * (1 + rate * multiplier * (level-1)^exponent)` — one
smooth curve every creature of a species shared exactly. Two Pixies at level 12
were the same Pixie, and **there was nothing for a promotion to preserve**,
because changing the species silently re-derived every level the creature had
ever gained. The whole promotion / Egg / Homunculus design depends on a past
that is owned rather than re-computed.

Rules the model guarantees, each with a test:

- **Deterministic.** A creature generated directly at level 20 replays the same
  history it would have lived, and a reload can never reroll a level-up.
- **No global RNG.** `growth.lua` uses its own LCG. Touching `math.random`
  would make a creature's stats depend on *when* they were computed and shift
  every battle roll after it.
- **Within budget.** Per-instance variation is about ±5%: lucky in a stat,
  never materially richer overall.
- **HP rises every level**, and not smoothly — a band has memorable spurts,
  because a level-up showing no change reads as a bug.
- **Growth stops past the last authored band** rather than extrapolating.

`mpd`, `mxa` and `mxp` do **not** grow: they are form-defined. MPD previously
grew at 0.05/level, which quietly made a creature more expensive to keep
manifested the longer you raised it — the reverse of the economy in §1.11,
where an early form stays cheap and promotion is what costs you.

**A caution about G2 here.** Every other golden fixture builds its battlers at
level 1 (`fixture.level or 1`), so this rewrite — the largest single change to
how stats are computed — moved zero golden lines. That proved *coverage*, not
correctness. The `growth` fixture fights at level 14 on both sides so the model
is gated from now on.

**Promotion never recalculates statistics.** It carries the `growthSeed` and
the accumulated `growth` record across to the new form, adds the evolution's
fixed authored `bonus`, and lets only *future* levels draw on the destination's
band budgets — automatically, since `packetFor` reads the creature's current
`actorData`. The levels a creature earned as a Pixie stay Pixie levels.

Two details that look small and are not:

- The bonus is **fixed**, so promoting early is rewarded and delaying does not
  scale it up. A player who waits has banked more of the cheaper form's growth
  instead — that is the trade, not a larger prize for patience.
- HP is clamped **after** the growth record is restored. Clamping first would
  quietly cap a promoted creature at its *unpromoted* maximum.

An evolution's `level` is **optional**. An item-gated promotion normally has no
additional level requirement: acquiring and choosing to spend the key is the
gate, and item placement and rarity are what pace it. An entry without `level`
used to be silently ineligible forever, so a Mimic that should become Pandora at
level 1 the moment the item exists could not be authored at all.

**One transformation, four callers** (`engine/transform.lua`). Promotion, Egg
hatching, Homunculus metamorphosis and the reversible Kappa curse preserve the
same things (growth record, seed, permanent gains, learned skills, name, level,
history, provenance, Favorite Food) and swap the same things (MPD, capacities,
affinities, innate skills/passives). They differ only in how the destination is
chosen, so they are one primitive rather than four copies that would drift.

`TRANSFORM_ACTOR` exposes it to data — no engine code knows what an Egg or a
Kappa is:

| `actor` | destination |
|---|---|
| `<id>` | that species |
| `"hatch"` | the actor's `hatchOutcomes` keyed by the instance's saved `provenance` (with a provenance-specific fixed bonus) |
| `"metamorph"` | deterministic nearest eligible species by permanent parameter profile |
| `"revert"` | the remembered origin form |

`reversible: true` remembers the current form. A natively recruited creature has
none and never reverts — the only difference between a native Kappa and a cursed
one. Metamorphosis is deterministic because the design shows the player its
destination *before* it happens; a random result would make that preview a lie.

`actorData.autoTransforms` applies the same primitive after level gains. A rule
may name a direct actor, `hatch`, `metamorph`, or `revert`, and gate itself with
`atLevel` or `afterOriginLevels`. Egg cracking and curse recovery are therefore
automatic without putting species names in Lua.

Homunculus classification first checks ordered `secretTransforms`. Their
formulas receive only `intrinsic.level/maxHp/atk/def/mat/mdf`, assembled from
base parameters, accumulated growth, and permanent item gains. Equipment,
states, and current HP are absent by construction. The first matching rule
wins; otherwise classification falls through to nearest `eligibleFrom` profile.

**Favorite Food** is one exact item drawn from the species' authored
`favoriteFoods` pool, fixed at creation from the growth seed (so a reload cannot
fish for a better one) and carried through every change of form. It is the
individual's, not the species'. Eating that exact item discovers the preference
and starts the item's authored `savor` traits. Savor cannot refresh while active,
is saved on the individual, and `TICK_SAVOR` reduces it after victories only.
Meals are explicitly marked `meal`, must be field-only, and food identity uses
the registered `foodTags` vocabulary.

Three general battle traits complete the content vocabulary: `TARGET_RATE`
weights random enemy AI selection (Provoke), `ELEMENT_RATE` multiplicatively
modifies damage from one named element, and `KILL_MP_RESTORE` restores flat
Summoner MP when its carrier personally kills or Executes a target.

The expanded roster uses a shared elemental skill library rather than giving
each species a private spell list. Red emphasizes escalating damage, Blue mixes
ice/water pressure with magical defense, Green mixes wind, sleep, regeneration
and growth, White owns healing/cleansing/protection, and Black owns weakening,
sleep pressure and dark offense. Creature-named actions are exceptional
identity rewards, currently Mesmerizing Light, Aqua Dish and Fairy Court.

The systemic item atlas adds 150 authored objects: 28 weapons, 28 armors,
36 accessories, 48 consumables (including twenty culturally grounded foods),
and ten promotion keys. Equipment tiers are authoring/placement metadata rather
than an automatic statistic formula. Remains remain valid ingredients while
also being wearable, and are excluded only from generated outputs. Promotion
keys are mechanically gated to have no effects, no equipment slot, and neither
input nor output membership in Item Creation.

Party meals separate creature-targeted effects from shared Summoner effects:
HP recovery and Savor resolve for every eater, while MP recovery resolves once
for the shared pool. `HEAL_RATE` supplies Healing Staff-style skill healing
without affecting items or permanent gains.

### 1.11 The Summoner MP economy (26.07.2026)

**A step costs exactly the combined MPD of the living manifested party**, with
no Summoner base cost — `party.mpd` in `formula.groupView`, charged by the
`exploration.step` flow. Living only: a creature that dies stops costing
anything. One shared query, so the traversal cost, Strain and any UI preview
cannot disagree about what the party costs. It replaced a flat
`dungeon.moveMpDrain` applied in `exploration.lua`, which charged the same 1 MP
whether the Summoner was carrying a Pixie or a Bahamut — the entire expedition
economy was invisible.

**Ordinary battle rounds cost nothing.** Taking a tactical turn is not priced.
That is a deliberate reversal: every round used to drain each ally's MPD, which
billed the expedition for simply fighting and made a heavy party unaffordable in
a way the design explicitly rejects.

**Battle Strain** is the pressure against indefinite combat instead, authored in
`battle.round_end`:

| Completed round | Cost |
|---|---|
| 1–5 | nothing |
| 6–9 | combined party MPD × 4 |
| 10–14 | × 8 |
| 15+ | × 16 |

Opening Max MP is 3000 against a cap of 9999 (`system.summoner`), the scale the
balance tables in `creature-parameters.md` are written against — 3000 MP buys
600 steps at party MPD 5.

An accessory may modify a wearer's MPD through the ordinary `PARAM_PLUS` /
`PARAM_RATE` traits and **can never push it below 1**, because `traits.getParam`
floors every parameter at 1. That is not a special case for MPD; it is why the
design's "never below 1" needed no new mechanism, and a test pins it so a future
change to that floor cannot quietly make an MPD-0 creature possible.

### 1.12 States, categories and status infliction (26.07.2026)

A state carries a **list** of categories from `engine.json -> stateCategories`
(`negative`, `positive`, `physical`, `magical`, `mental`, `common`). A list,
because a state is routinely several things at once — poison is negative *and*
common *and* physical — and each tag is a separate handle a resistance can grab.
G1 fails an unregistered category on a state or on a trait naming one, because a
resistance keyed to `negatve` protects against nothing and says so nowhere.

**`common` is earned, never inferred.** It marks an ordinary, commonplace
affliction: the family a broad protection is meant to cover, and the tag a
Ribbon-style blanket immunity keys off. Nothing is exempted by *absence* of a
tag. This matters because the obvious alternative is broken: rates multiply, so
a blanket authored against `negative` would also cover `dead` and quietly make
its wearer immune to any authored death effect. Death simply never earns
`common`.

**`FORCE_ACTION`** takes the choice away: the holder uses the skill its `dataId`
names, whatever it or the player picked, targeted by that skill's own spec. It
is applied in `Battle:buildTurnQueue` and at the head of `getAIAction`, so **one
rule binds both sides** — a berserk enemy and a berserk party creature are
compelled by the same code, and nothing in the engine knows what "berserk"
means. The battle scene additionally skips compelled creatures in the command
menu; that is presentation of the rule, not a second copy of it, because
offering a menu whose result is discarded is worse than not offering one.

The AI check comes *before* its skill roll: choosing and then discarding would
still consume battle RNG and shift every later roll in the round.

Infliction is a three-part chain, clamped to 0..1:

```text
final chance = skill chance * attacker STATUS_SUCCESS * target state rate
```

Splitting it three ways is what lets a control specialist be better at landing
conditions without rewriting every skill, and a resistant creature shrug them
off without the skill knowing who it hit. The target rate is itself the product
of every `STATE_RATE` naming the state and every `STATE_CATEGORY_RATE` naming
one of its categories — multiplicative, so a narrow and a broad resistance
compound rather than one silently winning.

**A rate is a slope, not a switch (01.08.2026).** Driving one to 0 makes a state
vanishingly unlikely on the ordinary path, but a critical hit still forces it
through. **Absolute immunity is its own trait** — `STATE_IMMUNITY` naming a
state, `STATE_CATEGORY_IMMUNITY` naming a category (a Ribbon's actual spelling)
— and it is the only thing a critical cannot bypass.

That separation replaced "a rate of 0 is immunity", which had overloaded one
number with two meanings. It **deleted** the critical-status exemption §1.13
used to carry, and it freed the stat-derived resistance curves below to reach or
pass zero without a stat quietly drifting into categorical immunity. G1 rejects
a `STATE_RATE`/`STATE_CATEGORY_RATE` authored as 0 outright, because anyone
writing that means immunity and would otherwise never learn they did not get it.

Immunity emits a `state_immune` event and a line of text rather than passing
silently, because a status that simply never appears looks identical to a bug.

**Defensive stats resist afflictions (01.08.2026).** The target's own *base*
`def` and `mdf` fold into the same product, through the `stateResistFromStat`
curves in `system.json` — DEF as the body's resilience against `physical`
afflictions, MDF as the spirit's against `magical` and `mental`. It needed no
new mechanism because the rate is already a product. This is what gives the
defensive stats a job beyond mitigation, per the wider reading of the stat names
(`mdf` is Spirit, `def` is Vitality) in `docs/design/skill-costs.md`.

Two guards, both load-bearing:

- **Base, not final.** Gear that raises a defensive stat buys damage mitigation;
  anti-affliction gear stays authorable as an explicit `STATE_RATE`, which says
  what it does. Same rule the charge economy follows (§1.20).
- **Afflictions only.** `physical` and `magical` are *shape* tags, not intent
  tags: `defending` and `provoke` are positive **and** physical, `regen` and
  `magicGuard` positive **and** magical. Without gating the curves on
  `negative`, a creature's own VIT would resist its own Defend, and the sturdier
  it got the more often bracing would silently fail. Explicit trait rates are
  deliberately *not* gated this way — an author who writes a rate against a
  positive state means it.

**Critical evasion.** Because a critical is the universal status backdoor, being
hard to crit is worth twice what it looks like: less burst damage *and* fewer
forced afflictions. `CEV` subtracts from the attacker's `CRI`. It is
trait-driven only — gear and passives buy it, no stat derives it, or DEF would
become a super-stat on top of mitigation and affliction resistance. The roll
happens even when `CEV` has driven the rate to zero, because skipping the draw
would consume one fewer `math.random` and shift every later roll in the round.

### 1.13 The damage model (26.07.2026)

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

**Armor penetration** ignores a share of the defending stat *before* the curve,
from an effect's `penetration` plus the attacker's `PENETRATION` trait, added
then clamped at the whole stat. Applied to the defense rather than to the
damage on purpose: against a soft target it is worth almost nothing, against a
wall a great deal — which is what separates it from simply hitting harder, and
is the Pile Bunker's whole job.

**Execution.** An attacker carrying `EXECUTION_THRESHOLD` finishes a *surviving*
target left at or below that fraction of Max HP. Checked after the hit, so it
closes a wounded enemy and never gambles on a healthy one. `EXECUTION_RESIST`
**subtracts** from the threshold rather than rolling against it: that costs no
randomness (so it cannot perturb the golden stream), makes partial resistance
exact rather than a second dice roll, and lets Safety Bit be an ordinary 1.0.
It is separate vocabulary from state resistance because execution is not a
state and must not be smuggled in as one.

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
effect after it reads it. The rule has **no exemption for resistance**: a crit
forces the status through any rate, however low. The only thing that stops it is
an explicit `STATE_IMMUNITY` / `STATE_CATEGORY_IMMUNITY` trait (§1.12).

The effective critical rate is the attacker's `CRI` minus the target's `CEV`.

**Accuracy** is rolled once per target in `APPLY_EFFECT`, before any effect
resolves: `HIT` (attacker, base 100%) times `1 - EVA` (target, base 0%). A miss
skips that target's **whole** effect list, so an attack that misses cannot
still apply the status it carries, and accuracy is per target, so a multi-target
attack can connect with one creature and be dodged by the next.

Only offensive actions roll — the test is "carries damage, aimed at someone
else". A potion fed to an ally and a buff cast on oneself have nothing to
dodge, and letting them whiff would invent a failure the design never asked
for. A certain outcome takes no random draw at all, which is why adding
accuracy moved no existing golden line.

Before this, `HIT` and `EVA` were registered, `EVA` was authored on Shadow
Stalker, and nothing ever rolled either: every action always connected. Five
planned creatures (Golem, Talos, Giant, Hyperion, Kappa) are specified as
inaccurate or low-evasion, and none of that was expressible.

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

### 1.14 Persistent expedition routes and Town Portal (27.07.2026)

A procedural floor is generated once per **expedition**, not once per map
transfer. `GameSession.mapStates` retains each visited dangerous map's grid,
events, fog, lighting, entrance, exit and last player position. Descending,
climbing, and portal travel restore that snapshot; a new safe-to-dangerous
departure clears the completed route and begins a fresh expedition.

Every generated floor has two physical landmarks. Common event 1 is the lower
stair and loads the next map with `LOAD_MAP arrival: entrance`. Common event 40
is the upper stair: Floor 1 returns to the safe map, while deeper floors load
the previous map with `arrival: exit`. Arrival is always on a passable adjacent
tile facing the relevant stair, never on top of its event.

`LOAD_MAP.arrival` is registry-authored (`entrance`, `exit`, `resume`).
`PORTAL_TO_TOWN` and `RETURN_TO_PORTAL` are reusable command primitives:
the first stores map, exact tile and facing before loading safety; the second
restores that point and closes the seam. Portal resume does not start a new
expedition or reroll any floor. Both the floor cache and an open portal
round-trip through `savegame.lua`.

The Town Portal item invokes the primitive through an ordinary common-event
effect. Its `meta.dungeonOnly` is registered and editor-authorable; usability
rejects it on safe maps before consumption. Cost, sources and scarcity remain
content balance rather than engine policy.

### 1.15 Stateful map presentation (27.07.2026)

`SET_MAP_PRESENTATION` changes a map's tileset, fog preset and ambient light as
one persistent event-authored state. A change applies immediately when its map
is active, survives transfers and save/load, and is validated against the
tileset and fog registries. Campaign events use this to let town-state changes
announce themselves spatially—for example, St. Maria's first festival arrives
as an unforeshadowed change in color, light and inhabitants.

### 1.16 Illustrated town interiors (28.07.2026)

`ENTER_LOCATION` selects a static image under `assets/locationArt/` as the
backdrop for the current map-event conversation. The dialogue scene keeps its
ordinary windows and command graph; only its map backdrop is replaced. Returning
to the map clears the location automatically, so exterior conversations cannot
inherit a previous room.

Location images are still frames. Door events occupy `#` cells and use their
ordinary `sprite` image as an overlay in the wall compositor, receiving the
same edge treatment, lighting, fog and raycast projection as the wall itself;
they never enter the billboard pass. Running forward into a `trigger: bump`
door starts its event without a confirm press.

That compositor is not door-specific: any map event with `wallEvent: true`
occupies a `#` cell, uses `trigger: bump`, and draws its ordinary sprite in the
wall slice rather than as a billboard. Generated up/down stairs and authored
wall fixtures use this same path. Procedural placement selects a surviving room
boundary with an adjacent passable approach cell. Dungeon interaction art is
stored as separate 64x64 sprites under `assets/sprites/dungeon_*.png`; the 3x3
generation layout is only a contact-sheet workflow, never a runtime sheet.

The threshold sequence zooms the centered wall door for 0.24 seconds and holds
that scale while the entire screen fades to black. Only at full black does it
start the conversation; it then lingers in darkness for 0.10 seconds before
uncovering the completely static interior through the subtractive fade. Leaving
burns that unchanged CG to black, after which the map returns
during a full-black hold, and the enlarged outside door settles back as the map
is uncovered. The blackout is composited into the map or illustrated-backdrop
layer; HUD and dialogue windows remain unaffected above it. The room remains
completely motionless afterward. St. Maria's initial set is the
assigned home, Alicia's bakery, Laura's forge, the Rusty Tankard and the chapel.
Their native runtime PNGs are palette-limited, game-resolution derivatives.
High-resolution generation sources are local working files and are ignored.

The blackout uses the shared subtractive fade primitive rather than an
alpha-black overlay. At progress `p`, a white fullscreen primitive is drawn
with subtract blending, producing `max(destination.rgb - p, 0)` per channel.
Dark channels therefore reach zero before highlights. Cinematics and doors
share this burn-to-black mathematics, while door zoom choreography remains
specific to doors. Drawing the subtraction during the map or illustrated
backdrop pass keeps HUD and dialogue UI outside the effect.

Dialogue `TEXT` commands may author `expression` from 1 through 5. Human
portrait sheets are five 128x192 columns; column 1 is always the default pose.
The selected column persists into the following choice until another spoken
line changes it. Expressions are complete character redraws rather than facial
swaps, and transparent silhouettes may exceed the nominal portrait rectangle
by half a tile without moving the shared bottom-window footprint.

### 1.17 String pictures and opening cinematic (28.07.2026)

`SHOW_STRING_PICTURE` creates or replaces a numbered screen-space text object.
String pictures expose pixel position, anchor, alignment, wrapping width, font,
size, palette color, opacity, scale, shadow, optional frame and one of three
layers: `backdrop` (above the world but below windows), `screen` (above ordinary
scene UI), or `top`. `MOVE_STRING_PICTURE` interpolates position, opacity and
scale; `ERASE_STRING_PICTURE` may fade before removal, while
`ERASE_ALL_STRING_PICTURES` is the unconditional cleanup operation. They are
presentation objects rather than save state and are cleared by session reset.
An authored `reveal: true` makes a string picture use the same character timing,
UTF-8-safe prefixing and `ui.textRevealDelay` setting as ordinary dialogue
`TEXT`; cinematic captions therefore arrive like SHOW TEXT instead of fading
as whole blocks.

`SHOW_IMAGE_PICTURE`, `MOVE_IMAGE_PICTURE`, `ERASE_IMAGE_PICTURE` and
`ERASE_ALL_IMAGE_PICTURES` provide the bitmap counterpart. An image picture
names an asset path, numbered slot, screen position, anchor, opacity, scale,
rotation, layer and blend mode (`alpha` or `add`); string pictures expose the
same blend choice. Move commands interpolate all numeric presentation fields.
The renderer loads nearest-filtered assets and fails loudly when a path is
missing. Additive pictures let luminous sigils and exact engine-rendered titles
mesh with the live world without baking words into generated art. This lets
common events crossfade and move cinematic plates without introducing a
cutscene-specific Lua host.

`WAIT` in map/common-event graphs compiles to a pausing node; it does not run as
part of an immediate command batch. `ENABLE_EVENT_SKIP` names a `LABEL` in the
same common event. Cancel jumps to that label even during a wait, allowing the
event author to own cleanup and final state rather than having the host abort a
script halfway through. G1 rejects missing skip labels.

New Game starts common event 42 in the empty-window `cinematic` scene. Its
authored sequence moves through nine generated plates from one retained 3x3
production sheet: distant approach, tactile travel details, the town bell,
residents reacting in the street, the Passage House courtyard and room, the
guarded approach, the Labyrinth threshold, and a final close Saban beat.
Creature appearances alternate with geography, architecture and object
inserts; every crop is composed for the 4:3 runtime canvas. Character-revealed
captions accompany the plates, followed by a St. Maria location card. The event
exposes `ESC: Skip`, and
always rejoins at `intro_cleanup`, which clears pictures, disables skipping,
loads St. Maria, and opens the static Room 3 interior. The arrival plates
establish that the player rode into St. Maria on Saban, their long-standing
mount and only summon. The player first receives control only after the Passage
House handoff establishes that this is one of five rooms kept for visiting
Summoners, that the others are empty, and that the room has been awkwardly
adapted for both travellers. Saban is never assigned by St. Maria. Leaving uses
the ordinary reverse door transition and places the player beside its exterior
door. The opening therefore reveals cinematic, room, and navigable town in that
order instead of cutting directly into free movement. The title scene uses
`assets/title/st_maria_title_psx.png` as a native-size static backdrop and
renders its title, subtitle, and copyright through the same string-picture
commands used by the introduction.

Defeat keeps the persistent battle dock in place through the battle's final
fade, then hands it to `game_over` for the dock's single close animation. The
scene reveals `assets/cinematics/game_over_talisman_psx.png` from a full
subtractive fade and applies a slow vertical drift while its title, aftermath
message and return prompt open in three timed beats. The plate remains at
exactly 1x scale throughout: cinematic pictures do not zoom because resampling
creates visible artifacts. Its `on_exit` hook clears the image picture and
subtractive fade before the title scene is entered.

Narrative image batches may be generated as exact contact sheets and split by
`tools/image/split-contact-sheet.ps1`. The tool takes grid geometry and one
name per cell and emits only an antialiased, palette-limited 256x240 runtime
plate. High-resolution generation sheets are local working files outside the
repository. The retained crops under `assets/cinematics/ideation/` supply the
four interior studies still referenced by events. The retained
`arrival_saban_contact_sheet.png` and its nine root-level crops supply the
prerendered opening.

### 1.18 Opening expedition roster and floor ramp (28.07.2026)

The opening party is authored through `system.newGame.party.fixedMembers` and
currently contains Saban (actor 61, level 3). A fixed member may carry an
instance name; new-game construction preserves it rather than assigning a
random ally name. Narratively, Saban predates the arrival: he is the player's
mount, travelling companion, and sole opening summon.

The field Reserve scene is now an **Expedition Reserve**: four party slots plus
four reserve slots are the creatures physically committed to the trip.
Summoning and the old permanent Sacrifice command are absent from its reachable
popup and from the field command dock. Their interpreter primitives remain
available to authored content while the town-only summoning site and
inheritance/fusion replacement are designed; no field UI invokes either.

`GameSession.storage` is a distinct, save-persistent collection with 99 numbered
slots. `storeCreature` takes the first free slot and `withdrawCreature` moves an
existing instance into the first free expedition-reserve slot, refusing when
that reserve is full. While below, a populated creature context menu also offers
**Dismiss**. It transfers that exact instance to the first free town-storage
slot, making expedition room for recruitment; it refuses when storage is full
or when dismissing an active slot would leave the party empty. Dismiss is hidden
on safe maps. This is the engine foundation for a future town storage scene;
there is not yet a player-facing storage interface.

The first three Labyrinth maps author their procedural envelope. Floor 1 is
17x17 with 3--4 rooms and no random recruitment nodes; it owns a guaranteed
Cornered Pixie contract event. Floor 2 expands to 23x23 and 5--7 rooms. Floor 3
expands to 27x27 and 7--9 rooms, where the ordinary dungeon scale and recruit
pool take over. `exploration.generateDungeon` reads optional per-map room-count
and room-size bounds, falling back to global dungeon configuration when
omitted. Generated layouts remain cached for physical backtracking.

Those three maps form **Stratum I: The Bellroot Depths**. Strata are authored
campaign groupings rather than a second map type: their floors remain ordinary
maps with ordinary depth and stair rules. St. Maria's north approach separates
the guard from the threshold—the guard occupies a side alcove and handles
conversation, while a generated stone-and-iron gate is the bump-activated
entrance. An authorized first descent runs common event 43: it burns the town
to black, loads Floor 1 underneath, then slowly reveals the live polygonal world while
an additive bell-and-roots plate and exact string-picture title fade away.
Later descents retain the slow world reveal but do not replay the discovery
card.

The authored environmental encounters continue that relationship through the
deeper floors. The Cryptic Vault inventories St. Maria's ordinary possessions
and counterfeits Saban's stable; the Blood Chapel stages an unfinished Vigil
and questions which traveller is the summon; the Stillnight Sanctum turns old
Summoner records into a garden and threatens to separate what arrived together.
Each is an ordinary map event with a persistent discovery flag and changed
revisit text, so the environments participate in the narrative rather than
serving only as encounter backdrops.

### 1.19 Explicit actor art roles and native big battlers (29.07.2026)

Every actor authors three distinct visual keys: `smallBattler` is the animated
compact sheet used by party cells and map recruitment billboards, `portrait`
is the dramatic cropped illustration used by status and other portrait
surfaces, and `bigBattler` is the uncropped full-body enemy illustration.
The former generic actor `spriteKey` no longer exists.

Big battlers render at their PNG's native pixel dimensions. The battle layout
chooses only a bottom-centre anchor for each troop member; it does not fit,
normalize, stretch, or otherwise scale artwork to the troop slot or viewport.
Authored overlap and clipping are therefore intentional presentation outcomes.
Animation transforms remain relative to that native size.

G1 requires all three actor fields and resolves their assets through the same
lookup rules used by presentation. The actor editor exposes separate pickers
and previews for all three roles.

---

### 1.20 Skill costs: charges, Overcast, availability (01.08.2026)

**No ability costs MP.** MP is the Summoner's shared expedition pool (§1.11);
charging a per-skill cost against it meant every heal a creature cast came out
of the party's remaining walking distance, and gave every caster the same
wallet. `mpCost` (and `spCost`) are removed from the data and rejected by G1 —
they were authored across most of the database and read by *nothing*, so there
was no balance behind them to preserve. Design intent and the full rationale
live in `docs/design/skill-costs.md`.

Two families, one predicate:

| Family | Resource | Question it answers |
|---|---|---|
| Magic | **Charges**, refilled at Rest | "How many more times today?" |
| Physical | **Cooldown / warmup / condition** | "Can I do it *this turn*?" |

`usability.canUseSkill` is the single authority, consulted by the player's
battle submenu, `Battle:getAIAction` **and** the status scene — so a row the
player sees greyed is a skill the AI cannot pick either, the same "one rule
binds both sides" principle `FORCE_ACTION` follows (§1.12). A known skill is
never hidden; it is shown with its reason, because a row that vanishes looks
like a bug. This is also why `conditionText` is mandatory alongside `condition`:
a formula cannot produce readable text.

**Charges** are authored as a formula against the caster (`4 + b.base.mdf / 4`),
so a promoted caster gains castings without the skill row changing, and they
live per-creature *and* per-skill on the battler — saved, like `wardCharges`,
because they are creature state. Missing key means full, so an old save or a new
summon arrives rested rather than mute.

**Overcast** is the one path from a skill to the shared pool, offered *only* at
zero charges (never as a cheaper alternative, so there is nothing to optimize)
and never to enemies, who have no Summoner. `"charges": 0` is a pool that exists
and is permanently empty — the Overcast-only shape, intended for a dragon's
Breath, which is not a daily supply but something drawn out of its Summoner.

**Rest** is `GameSession:rest()` — one definition shared by `RECOVER_PARTY` and
main.lua's callback, which previously carried two hand-copied versions of the
same reset. HP/MP reach the fielded party; **charges reach reserve and storage
too**, because rest is a location, not an activity, and a bench that stayed
spent would make swapping useless. **Promotion is a rest**; levelling is not.

**Cooldown and warmup are battle-scoped** and never enter a save: charges answer
"how much is left of the day", these answer "what can I do this turn". They are
ticked by `TICK_SKILL_TIMERS` authored into `battle.round_end`, not by a branch
beside the round counter — the end of a round is a phase made of steps, and a
new step should be a line of data.

**Base stats, not final.** Charge formulas read `b.base.*` (a lazy accessor over
`traits.getBaseParam`, mirroring `b.trait.<CODE>`). Equipment must not buy
castings; a `PARAM_RATE` debuff must not shrink a *maximum* while the creature
holds spent charges; unequipping mid-dungeon must not shift max charges under a
creature's feet. Same rule the stat-derived affliction resistance follows
(§1.12): **base stats say who a creature is, final stats say how hard it is to
hurt right now.**

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

### 2.4 One battler placement, and anchors (29.07.2026)

`presentation/battler_geometry.lua` is the **single authority on where a
battler is**. It maps a battler to a rect — the sprite box, plus the `frame`
box that framing UI uses (the portrait for an enemy, the whole status cell for
a party member) — and everything that attaches to a creature reads it: damage
popups, animations, target reticles, slot indicators and the enemy info block.

This rule exists because placement was previously computed in four places that
disagreed, so a popup could spawn at a fixed row y while the creature it
belonged to was elsewhere, and any layout tweak had to be repeated four times
or drift. **Never compute battler coordinates locally.**

Anything attaching to a creature does so with an **anchor spec**, resolved by
`battler_geometry.anchor(rect, spec)`:

| Field | Meaning |
|---|---|
| `point` | `center` (default) \| `feet` \| `head` \| `top_left` |
| `offsetX` / `offsetY` | pixels, applied after the point |
| `relativeOffsetX` / `relativeOffsetY` | fraction of the battler's OWN width/height |

The relative offsets are what make one authored effect correct at both scales:
`0.5` is 32px on a 64px enemy portrait and 12px on a 24px party sprite. An
animation entry authors its anchor in `data/animations.json` (`anchor`);
entries that author none take `battleLayout.animationAnchorPoint`. Damage
popups take `battleLayout.popupAnchor*`. An unknown `point` **raises** — G1
checks every animation entry and both battleLayout defaults, so a typo is a
build failure, never a silently centered effect.

The enemy info block (element icons + name + HP gauge) is data likewise:
`battleLayout.enemyInfo*` owns its width (96px default), its offsets **from the
creature's feet line** rather than an absolute row, and an on/off switch per
channel. It is **off** by default as of 31.07.2026: target selection already
shows the same name, HP and elements for the creature under the cursor, and
showing it permanently for every enemy duplicated that on top of the art.

### 2.5 When a window animates (31.07.2026)

Window open/close animation was assigned ad hoc — some popups had an open with
no close, three different effects, four different durations — which read as
inconsistency rather than as intent. The rule:

1. **Overlays animate.** A window that appears *over* what is already on
   screen — a popup, a confirm, the dock's party slots — opens and closes with
   `rescale`, **0.16s open / 0.10s close**.
2. **Siblings sharing a surface do not.** A window that replaces a peer on the
   same footprint (battle's command ↔ skill ↔ item ↔ target info) swaps
   instantly. There is nothing to reveal: the replacement is already there.
   Animating the outgoing one also re-resolves its content from live state
   while it closes, which is why the closing command window used to flash the
   skill list for a few frames.
3. **Scene furniture does not.** The panels that make up a scene's own layout
   arrive with the scene; the scene transition owns that beat, not each panel.

`dialogue_name` keeps its slide as a deliberate exception — it is a nameplate
attaching to a portrait, not a menu surface.

The motion itself is `ui.rescaleRect`: the windowskin is **rebuilt** at the
intermediate size with real 9-slice borders (never scaled as a bitmap), the
content is drawn at full size and **scissored** to it (never squashed), and
both axes advance at the same **pixel rate** — so a wide button reaches full
height almost at once and then unrolls sideways.

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

### 4.1 One event language, one editor, one clipboard (27.07.2026)

The engine is made of event blocks (§0). It follows that **there is exactly one
way to edit a command list, everywhere one exists.** Map events, common events,
scene hooks, battle phases, troop battle events, quest hooks, action sequences
and an actor's recruit event are the *same editor* — `renderCommandList` in
`events.js` — reading the same registry and sharing one module-level clipboard.

**Map-event common-event links are templates, not command calls.** A map event
or event page with `scriptId` is linked to that common event: the linked common
event supplies the commands, and its `sprite`, `label`, and `minimapColor` are
presentation defaults when the map event does not override those fields.
This is the editor's **Link Common Event** mode and is a first-class runtime
feature. A map event or page with its own `commands` instead uses the editable
custom command list. `CALL_COMMON_EVENT` is different again: it invokes another
common event from inside a command list, but does not inherit any of that common
event's presentation properties. The obsolete field was `script`, not
`scriptId`; `commands` is the sole field for an owned command list.

`CHOICE.cancelOption` provides RPG Maker 2003-style Cancel behavior. It is an
optional one-based index into the authored options: Escape/Backspace executes
that option exactly as confirmation would. With the field absent, Cancel is
disabled. If an indexed option is hidden by its condition, Cancel is disabled
for that showing rather than entering an invisible branch.

Consequences, all of them load-bearing:

- **Commands copy between surfaces.** Ctrl+C in a battle phase and Ctrl+V in a
  troop event is a supported move, not a coincidence; that is literally how
  Battle Strain got from `flows.json` onto the base troop. A rule written in
  one place can be moved to a better one without retyping it.
- **A new surface is a call to `renderCommandList`, never a new editor.** If
  you find yourself writing a second command list UI, stop — the reason Troops
  shipped as a tab in an afternoon is that only the *container* was new.
- **The context set is closed and registry-backed.** `engine.json`
  `commandContexts` is the list; the validator checks commands against it and
  the editor builds its pickers from it. A command may only declare a context
  that exists, and every context must say where it is authored — G1 enforces
  both. This check exists because `TRANSFORM_ACTOR` spent weeks declaring
  `event` and `flow`, which matched no host context, quietly making it
  scene-only: a creature could not be transformed by a map event, and nothing
  failed. **A context with no editor surface is a command nobody can write.**
- **Pasting across contexts warns rather than silently breaking.** The
  registry knows which commands are legal where, so a cross-surface paste that
  cannot run names the offenders first — including ones nested inside branch
  bodies — instead of producing a G1 failure later that points at the
  destination rather than the paste.
- **Say so in the UI.** Every command list ends with a line naming the
  shortcut and the fact that it crosses surfaces. Seven identical editors that
  never mention each other read as seven unrelated boxes; the sharing has to be
  visible or it may as well not exist.

The generalisation: when a capability is already shared, the work is usually to
*surface* it, not to build it again.

### 4.2 A map owns its roster; a troop owns the shape of the fight (27.07.2026)

`data/troops.json` first gave every floor its own `*_wanderers` troop, whose
entire content was the weighted pool the map already had. Seven near-identical
troops, and a rename away from drift.

The split that removes them: **a map's `encounters` table is the floor's
roster — what can appear — and it stays on the map.** What a wandering
encounter *is* — how many, at what levels, under which base-troop rules — does
not vary by floor, so it is defined once as the `wandering` troop, whose one
member slot is `poolFrom: "map"`: a pool by reference rather than by value.
`combat.wanderingTroop` names it; a floor that wants something else sets
`encounterTroop`.

A map encounter entry and a troop pool entry use the *same field names*
(`actor`, `weight`, `levelMin`, `levelMax`) on purpose — a map's table is a
troop pool, so one can be pasted into the other, per §4.1.

The rule this is an instance of: **before adding a per-thing copy of a
definition, check whether the thing already owns the part that actually
varies.** Usually only the data differs and the shape does not.

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
