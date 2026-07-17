# SPEC — Animation System, Unified Targeting, Data-Authored Windows (Overhaul 7)

Audience: an agent executing ONE brief. Your brief tells you which sections
to read. Do not change this spec; if your task conflicts with it, stop and
report. Design source of truth for the animation pillar (read before this
SPEC, not instead of it): `docs/plans/overhaul-5/future-animation-system.md`
(owner direction note, 10.07.2026).

Integration branch: `fable-7-overhaul-7`. Ground rules (gates, golden
discipline, review protocol) are identical to overhaul-6's — see
`docs/ORCHESTRATION.md` and `docs/plans/overhaul-6/PLAYBOOK.md`. **Every
brief that touches `engine/battle.lua` or `engine/scenes/battle.lua` (T1,
T2, A2) is owner-supervised, never autonomous** — the same rule o6 applied
to its entire F-series.

Round-wide design constraint (owner, 15.07.2026): **build for
extensibility.** Every schema this round introduces (animation entries,
target specs, window definitions) must tolerate unknown future fields —
readers ignore keys they don't understand, validators warn rather than
reject on unrecognized optional fields, and version/`kind` discriminators
are included from v1 so new entry types can be added without migrating old
data.

## S0 — Why, and what breaks on purpose

Three pillars:

1. **Animation system + editor tab (A-series).** Today the only animation
   data is `data/animations.lua` — 4 hardcoded entries — and everything
   else (enemy flash timers, death tint/fade, smallBattler shake, slide-in)
   lives as inline constants and timers in `presentation/renderer.lua`.
   The owner's direction note demands one system where *everything
   battler-related that animates* is an editable data entry, including
   **system animations** (damage flash, shake, death), not just
   skill-assigned ones — the deliberate departure from RPG Maker.

2. **Unified targeting model (T-series).** Target semantics are ad-hoc
   string matches (`skill.target == "enemy"`, `"ally-any"`, `"self"`,
   `item.targetScope == "party"`) scattered through `engine/battle.lua`
   (AI action builder ~L39–93, turn resolution, applyItem ~L374+). There
   is no single resolver, no declarative spec, and player-side manual
   selection only covers what o6's reticle work wired up. T1 replaces this
   with one target-spec schema + one resolver module used by both AI and
   player paths.

3. **Windows authored in data (S-series).** `data/scenes.json` scenes carry
   `hooks` and `scripts` but their `windows` arrays are absent/empty —
   every window is still drawn by hand in `presentation/window_renderer.lua`
   / `renderer.lua`. S-series defines a window schema and moves layout,
   text, lists, and gauges into scene data, shrinking per-scene Lua.

**Golden-log impact:** T1 is expected to change enemy-AI target selection
order (RNG consumption changes when random-target picking routes through
one resolver). **T1 is the one brief in this round permitted to regenerate
`tools/golden/battle.log`**, with owner sign-off on the new sequence read
as a diff, same discipline as o6/F1. A-series must NOT change battle.log —
animations are presentation; if wiring them alters logged events, that's a
layering violation, stop and report. S-series affects UI-golden traces
(sanctioned per converted scene, owner-reviewed), never battle.log.

## S1 — Current state (grounded, read before touching code)

- **`data/animations.lua`**: 4 entries (`healing_sparkle`, `damage_shake`,
  `attack_flash`, `death`), loaded at `data/loader.lua:38`, fields are
  free-form per type. No JSON, no editor, no schema.
- **Renderer-side animation state**: `presentation/renderer.lua` keeps
  battler anim timers inline (flash on hit, death tint/fade, enemy
  slide-in ~L674; shared smallBattler timer ~L211).
  `presentation/small_battlers.lua:31` already reads a
  `config.battle_screen.animations` block — o5/E8's seed values that this
  round's system must absorb, per the direction note's "What NOT to do"
  section.
- **Interpreter**: a `PLAY_ANIM` scene command already exists (see
  direction note L49); check its semantics before adding any new command.
- **Targeting**: `engine/battle.lua` — enemy AI picks
  `livingAllies[math.random(...)]` etc. per target-string branch (~L39–93);
  player-chosen targets flow via `chosenAct.target` in resolveRound
  (~L161–200); items have a separate `targetScope` field with a `party`
  branch in `applyItem`. `engine/scenes/battle.lua` owns the player-side
  reticle/selection state machine; `renderer.getBattlerCoords` maps a
  target to screen coords for popups/reticle.
- **Scenes/windows**: 9 scenes in `data/scenes.json`
  (`1, title, map, items, status, battle, shop, game_over, reserve`), each
  `{id, name, kind, hooks, scripts}` — **no scene has a `windows` array
  today.** `presentation/window_renderer.lua` (1080 lines) draws all menu
  scenes in Lua; the editor already has `js/window-editor.js` and
  `js/scene-canvas.js` (o5's visual canvas) to build on.
- **Editor**: registry-pattern tabs exist (Effect Types, Trait Codes) —
  A3's Animations tab follows that pattern; `tools/editor/js/database.js`
  is the tab host.
- **Gates**: G1 `VALIDATE OK`, G2 `tools/golden/battle.log` byte-identity,
  G3 UI-golden traces per scene.

## S2 — A1: Animation runtime + system animations become data

Create `data/animations.json` and an engine-side animation player;
dissolve the hardcoded renderer constants into it.

- **Schema (v1, extensible): entries compose typed TRACKS, not one
  monolithic kind.** Grounding: the existing death animation
  (`renderer.lua` ~L690) is already a composite — additive blend + purple
  tint + y-offset + alpha fade running together. The schema must express
  that as data. An entry is
  `{ id, class, duration, tracks: [ {type, ...}, ... ], sound? }` where:
  - `class`: `"system"` or `"assignable"`. System entries use reserved ids
    (`system.damage_flash`, `system.damage_shake`, `system.death`,
    `system.small_damage`, `system.enemy_slide_in`, `system.heal`);
    validator requires all reserved ids present. Assignable entries are
    free-form ids referenced by skills/items (A2).
  - **Track types (v1):**
    - `tint` — color + alpha over time (flash overlays, death purple,
      fade-out). Fields: color from/to, alpha from/to.
    - `blend` — sets the target's blend mode for the track's span
      (`alpha`/`add`; leave room for `multiply`/`subtract` later). The
      death and flash effects both use `add` today.
    - `transform` — offset x/y, **scale x/y independently** (owner ask:
      squash/stretch on either or both axes; scale is about the sprite's
      anchor point, and it is SPRITE scaling — never windowskin scaling,
      per the o5 scale-anim rule), rotation reserved for later.
    - `shake` — amplitude + frequency (absorbs `damage_shake` and the
      smallBattler shake).
    - `particles` — an emitter: particle texture ref (or 1–4px colored
      quads for v1 if no texture given), emission rate, lifetime, spread/
      velocity, gravity, color-over-life, blend mode. Built on LÖVE's
      `ParticleSystem`. Optional `mask: "target"` clips emitted particles
      to the target battler's sprite silhouette (stencil test against the
      sprite's alpha) — owner ask: "a given particle only shows within
      the target". `mask` absent → particles unclipped.
    - `text_flow` — absorbs `healing_sparkle` (sequence string, interval,
      targetPart).
  - Each track has `t0`/`duration` (ms, relative to entry start) and
    `easing` (string id, v1: `linear`/`ease_out`), so tracks can stagger.
    Unknown track types must fail soft (log once, skip track) so future
    types (sprite-sheet frames, projectiles, screen-space effects) don't
    crash old engine builds.
  - `sound` (optional, id into sounds.json — wire only if PLAY_SE
    plumbing already reaches the battle layer; do not build new audio
    paths, per o4 S9 discipline).
  - Ported system entries double as the schema's proof: `system.death` =
    blend(add) + tint(purple→fade) + transform(y-offset); flash =
    blend(add) + tint; shake = shake track. If a ported entry can't be
    expressed in tracks, the schema is wrong — fix the schema, don't
    special-case the entry.
- **Player module** (`presentation/animation_player.lua` or similar): owns
  active-animation instances `{entryId, target, t0}` and their live
  ParticleSystems; renderer call sites ask it for the target's current
  transform (offset, scale x/y), tint, and blend mode instead of keeping
  their own timers, and call a `drawEffects(target)` pass for particles/
  text_flow (with stencil masking applied when the track asks for it). Existing inline timers in `renderer.lua` and the
  `battle_screen.animations` block values migrate INTO animations.json
  entries; `small_battlers.lua` reads the system entries.
- **`data/animations.lua` is deleted** once its 4 entries are ported;
  `loader.lua` loads animations.json instead. Grep for all consumers
  before deleting.
- **No behavior change**: G2 byte-identical; G3 traces unchanged (visual
  timing may shift only where the old constants were duplicated
  inconsistently — flag any such case to the owner rather than silently
  normalizing).

## S3 — A2: Assignable animations on skills/items

- `data/skills.json` entries gain optional `animation` (entry id);
  `data/items.json` likewise. Absent field → sensible system default
  (attack-ish skills fall back to `system.damage_flash` behavior exactly
  as today, so no data edit is required for existing content).
- Battle event pipeline: when the scene consumes a `skill`/`item` battle
  event, it asks the animation player to start the referenced entry on
  the event's target. **Presentation only** — `engine/battle.lua` may add
  the animation id onto emitted events (data plumbing) but must not change
  event order/content otherwise; G2 stays byte-identical (animation id may
  ride on events only if battle.log serialization ignores it — verify
  first; if the logger prints whole events, resolve the id scene-side
  instead and touch battle.lua not at all).
- Validator: dangling `animation` refs fail G1.

## S4 — A3: Editor Animations tab + live preview

- New tab in `tools/editor` following the registry pattern: system entries
  pre-seeded, always present, not deletable; assignable entries CRUD.
- Entries edit as a **track list**: add/remove/reorder typed tracks, each
  rendering its own field set per track type (widgets.js patterns) —
  tint colors via the existing color widgets, particle emitter params,
  the `mask: "target"` toggle, per-axis scale inputs, blend-mode dropdown.
  `sound` uses the sounds picker if one exists. Unknown track types in
  loaded data render read-only, never break the tab.
- **Live preview** (owner: first-class requirement): a preview pane that
  runs the entry against a dummy battler sprite. With particles, stencil
  masking, and blend modes in the schema, a faithful JS re-implementation
  is no longer realistic — **the preview should reuse the engine** via
  the existing editor↔engine bridge, following the E5/E12 precedent
  (`preview-scene`/`preview-window` CLI modes + server endpoints): a
  `preview-anim <id> <mockJSON>` mode that plays the entry on a dummy
  battler and returns frames (an animated sequence of PNGs at fixed
  timestamps is acceptable v1; a live-rendering channel is the stretch
  goal). Confirm the approach with the owner before building; document
  what shipped. Fidelity bar: timing, color, blend, and masking must
  visibly match the in-game result for the ported system entries.
- Skills/items editors gain an `animation` picker (dropdown of assignable
  entries + "(default)").

## S5 — T1: Unified target spec + resolver

Owner-supervised. The sanctioned battle.log regeneration lives here.

- **Target spec schema** on skills/items (one field, same shape for both;
  `targetScope` on items is absorbed):
  `{ side: "enemy"|"ally"|"self"|"any", count: n|"all", mode:
  "choose"|"random", state: "alive"|"dead"|"any" }` with string shorthands
  for the common cases so existing data stays terse (e.g. `"enemy"` expands
  to `{side:"enemy", count:1, mode:"choose", state:"alive"}` for players
  and `mode:"random"` semantics for AI — resolver decides, data doesn't
  duplicate). `state:"dead"` is the door for future revival skills; no
  revival content ships this round.
- **Resolver module** (`engine/targeting.lua`): given (actor, spec,
  session/battle state, optional chosen target) returns the concrete
  target list. Both `getAIAction` and the player command flow call it;
  the per-branch string matches in `battle.lua` are deleted.
- Migration: existing `skills.json`/`items.json` target strings map onto
  shorthands; a validator pass ensures every skill/item resolves to a
  legal spec (G1 fails on unknown scope strings — the current silent
  fallthrough dies here).
- **battle.log regeneration**: expected once, owner reads the diff before
  commit. After T1 lands, byte-identity discipline resumes.

## S6 — T2: Manual target selection everywhere

Owner-supervised (touches `engine/scenes/battle.lua`).

- Every player action whose resolved spec is `mode:"choose"` routes through
  the o6 reticle picker — including items and multi-target confirm
  (count:"all" shows the reticle on the whole group, select confirms).
- Picker constraints come from the spec (side/state filters); dead-target
  specs highlight dead battlers — build the filter path even though no
  revival content exists yet.
- Undo (o6's action-undo) must keep working through the new picker states.
- G3: UI-golden trace for the battle scene updated (sanctioned,
  owner-reviewed); G2 byte-identical — player-side selection must not
  perturb AI RNG.

## S7 — S1w: Window schema + pilot scene conversion

("S1w"/"S2w" to avoid colliding with spec section numbers.)

- **Window schema (v1, extensible)** inside a scene's `windows` array:
  `{ id, rect: {x,y,w,h} (values may be exprs against layout vars),
  visible: <expr>, content: [ ... ] }` where content items are typed
  blocks: `text` (term key or expr), `list` (binding expr + item template +
  cursor binding), `gauge` (current/max exprs, style ref), `image`. Exprs
  evaluate in the same sandboxed env scene hooks already use (`v.*`,
  formulaEngine) — no new expression language.
- `presentation/window_renderer.lua` gains a generic `drawWindowFromData`
  path; hand-drawn code for the pilot scene is deleted, not shadowed.
- **Pilot scene: `items`** (simplest list-scene; `status` is the backup
  pick if items turns out to be entangled with battle item-submenu code —
  check first, report which was chosen).
- Editor: o5's scene canvas (`scene-canvas.js`) renders these windows
  click-to-edit; `window-editor.js` edits content blocks.
- G3: pilot scene's UI-golden trace regenerated (sanctioned,
  owner-reviewed diff). All other scenes' traces byte-identical.

## S8 — S2w: Convert remaining menu scenes

- Convert `status`, `shop`, `reserve`, `title`, `game_over` windows to
  data, one commit per scene, each with its sanctioned trace regen.
- **Explicitly out of scope: `battle` and `map`.** The battle HUD
  (party grid, log window, command menus) and map overlays stay Lua this
  round — they're entangled with T2's picker states; converting them is
  a future round once both systems are stable.
- Each conversion must delete the Lua drawing path it replaces. If a
  scene needs a content-block type the schema lacks, extend the schema
  (additively) rather than special-casing Lua — that's the round's
  extensibility constraint in action.

## S9 — What NOT to do this round

- No audio system work beyond optional `sound` refs on animation entries
  (o4 S9 discipline stands; audio remains undecided per orchestration
  memory).
- ~~No AI targeting intelligence (focus fire, heal-lowest) — T1 keeps AI
  behavior semantics equivalent to today (random within legal set) except
  where the old code was buggy; flag bugs, don't redesign.~~
  **AMENDED 17.07.2026 (owner decision, post-audit):** T1 shipped two AI
  heuristics in violation of this line — heal-lowest target priority
  (`targeting.lua`, resolve()'s wounded-ally sort) and a heal-skip re-roll
  in `battle.lua`'s `getAIAction` — plus one semantic change: `ally-any`'s
  friendly group now includes the caster (pre-T1 code excluded self).
  The 16.07 audit measured the revert: 10 of 30 battle.log lines, and the
  S9-compliant behavior it restores is visibly degenerate — the golden
  enemy Pixie randomly targets its own full-HP self with soothingMote and
  heals for 0, a wasted turn, twice in the three-round fixture. The
  self-inclusion and heal-lowest changes are complementary (self-healing
  is legitimate; heal-lowest is what prevents the full-HP-self pick).
  Owner reviewed the diff and chose to sanction what shipped rather than
  spend a second battle.log regeneration restoring worse behavior. All
  three changes are now sanctioned and baked into the T1 golden log; code
  comments at both heuristics record this. Focus-fire and any FURTHER AI
  intelligence remain out of scope — the prohibition stands for new work.
- No battle/map scene window conversion (S8).
- No sprite-sheet-frame or projectile track types — schema leaves the
  door open, v1 does not implement them. (Particles ARE in scope — owner
  ask, 15.07.2026.) No screen/map-level animation tracks either (the
  direction note's "perhaps"): battler-scoped only this round.
- No new interpreter commands unless a brief strictly needs one; check
  `PLAY_ANIM` first.
