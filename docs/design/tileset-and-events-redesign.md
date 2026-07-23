# Tileset System & Map-Event Fixtures — Redesign Proposal

Status: **proposal, for design board** (drafted 23.07.2026). No implementation
has started. This document captures a converged conversation; several items
are explicitly flagged as open decisions rather than settled design.

## 0. Why this exists

The current tileset editor (`tools/editor/js/tileset-editor.js`, `data/tilesets.json`)
implies a UI structure — multiple weighted wall/floor variants, per-cell
feature painting, autotile role labels — that the underlying schema and Lua
renderer only partially back up:

- The "Wall" tool always overwrites `base.walls[0]`; the schema supports N
  weighted variants but the editor can never author a second one.
- `weight` fields exist with no sibling to weigh against (painting always
  replaces, never adds, a variant at a given cell).
- Canvas role badges (`autotile_left_edge`, etc.) are UI-only synthesized
  labels never persisted to `role` in the data.
- Feature painting writes to `tiles{}`, which is structurally inert for maps
  — the only live runtime path to it is a lamp's free-text `material` field,
  not per-cell authoring.
- `engine-editor.js`'s "Tileset Atlases" tab has dead code
  (`fetchTilesetRegistry`/`saveTilesetManifest`) with no caller.

This isn't a bug list to patch — the philosophy underneath needs to change
first: **algorithmic placement, controlled by data, before (or instead of)
hand-authoring individual cells.** The editor rewrite must follow from that
philosophy, not precede it.

## 1. Core layering

Three orthogonal layers, applying identically whether the source map is
hand-authored (e.g. the town) or procedurally generated (e.g. a dungeon
floor):

- **Structure layer** — per cell: `wall | floor | ceiling | opening`.
  Authored by hand (town) or by a room/corridor generator (dungeon). This is
  the layer the town already gets right today (hand-place structure, then
  decorate algorithmically) — the redesign should generalize that pattern,
  not replace it.
- **Decoration layer** — algorithmic, rule-driven placement of visual
  features (torches, rubble, wall variants, floor variants) on top of
  structure. Driven by weighted variant pools plus adjacency/context rules
  (§3). Applies the same way regardless of who authored the structure
  beneath it.
- **Override layer** — a single per-cell escape hatch used both for "the
  generator got this one cell wrong, hand-fix it" and "the town needs a
  bespoke torch placement here." Today this role is split awkwardly between
  inert `tiles{}` writes and the lamp's free-text `material` field
  (`viewport_3d.lua:509-526`, `:806`) — those two paths should unify into one
  override concept.

## 2. Structure layer detail

Cell types: `wall`, `floor`, `ceiling`, `opening`.

- `opening` is a new first-class structural cell type — a **doorway/gate/arch**
  the player physically walks through to reach another part of the same map.
  It must exist at this layer (not as an event) because room/corridor
  generation and pathing need to know it's passable. Its visual (plain gap
  vs. arch vs. ornate gate) is a rendering variant resolved the same
  weighted/adjacency way as wall or floor variants.
- Per-cell overrides at this layer also cover passability anomalies —
  illusory walls (visually wall, actually passable), one-way walls — as a
  variant of the same override mechanism, not a new concept.
- This layer is what a dungeon generator produces algorithmically, and what
  a human edits directly for hand-authored maps like the town. Same schema,
  different author.

## 3. Decoration layer detail

- **Weighted variant pools per structural role** — real N-way weighted
  selection (fixing the current single-variant-in-practice bug), not a
  cosmetic `weight` field with nothing to weigh against.
- **Adjacency/context rules** — conditions like "only if adjacent to floor,"
  "only within N tiles of an opening," "only in zone X." Chosen approach:
  **declarative, composable predicates** (`{all: [...]}`, `{not: {...}}`,
  etc.) rather than a fixed enum, for expressive power and to support
  per-biome/per-level overrides cleanly — composability matters more here
  than a small closed vocabulary.
- **Prefabs** — the actual day-to-day authoring surface. A prefab is a
  named, pre-validated predicate composition with sane parameter ranges
  (e.g. `"torch_near_corners"`, `"sparse_rubble"`). A designer picks and
  tunes a prefab from a library instead of writing raw predicates; the raw
  composer exists for rare bespoke cases, and even then starts from a copy
  of a prefab. This keeps expressive power available without making every
  placement rule a one-off to validate.
- **Zone/region tagging** — map regions ("corridor," "treasure room," "boss
  arena") can carry their own rule subsets. Open question (§6): hand-tagged
  vs. algorithmically inferred; default to algorithm-first if this becomes
  contentious, per owner direction — resolve "what is a dungeon floor,
  structurally" before this.
- **Per-biome/per-level overrides** — a level references a base tileset plus
  a sparse override delta, not a full duplicate of the ruleset.

## 4. Dungeon generation becomes data-driven

`engine/exploration.lua`'s currently-hardcoded room/corridor/injection logic
moves into data files driven by the *same* rule schema as decoration
placement (§3) — one rule format feeds both "what tiles exist" and "where do
generated structures get placed," in the same rewrite (not a follow-up).

## 5. Wall/floor event fixtures — reusing, not replacing, map events

The engine already has a full RPG-Maker-style map event system:
`(x, y)`-attached entities with a `trigger` (`interact` | `step`) and a
command list compiled through `engine/interpreter.lua` against the
`data/engine.json` registry (`TEXT`, `GIVE_ITEM`, `DAMAGE`, `TELEPORT`,
`LOAD_MAP`, `BATTLE`, etc.), metered against raw `SCRIPT` use by the
zero-SCRIPT validator rule (`docs/SPEC.md:38-41`). This is the same
default+override command-list pattern already named in
[event-driven-content.md](event-driven-content.md) for action sequences and
quest hooks — wall/floor fixtures are best understood as another
instantiation of that same pattern, not a parallel system.

**Reused as-is:** chests (`interact` + `GIVE_ITEM`), traps (`step` +
`DAMAGE`), signs/paintings (`interact` + `TEXT`), teleporters (`step` +
`TELEPORT`) — zero new engine concepts, just new event instances.

**Trigger unification:** `step` and a hypothetical separate "bump" trigger
collapse into one — RPG Maker's "player touch" model: the *same* trigger
fires whether the target cell is passable (move completes, then event
fires — today's behavior) or impassable (move is rejected, event fires
instead of/alongside existing bump feedback). One trigger, branching on the
passability check that already gates movement. No new trigger type needed.

**Genuinely new, three items:**

1. **Attachment + wall-face rendering.** Events currently float on `(x,y)`
   regardless of what's at that cell and always render as a billboard
   sprite (`presentation/viewport_3d.lua:876-887`). A `wall_event` (a
   painting, a switch, a blank-wall search spot) needs an attachment concept
   (which wall face vs. a floor cell) and wall-face rendering instead of a
   floating billboard.
2. **`hidden` flag.** No such flag exists today; the near-miss `transparent`
   field looks like a rendering/priority hint, not a presence toggle.
   Hidden-passage and blank-wall-search fixtures need "don't render anything
   until found."
3. **Structural-mutation command.** Hidden-passage-reveal needs an effect
   that changes the *map grid itself* at runtime (wall → opening) — nothing
   in the current command vocabulary touches structure, only player/state.
   This is a new category of effect; flag it to whoever owns the zero-SCRIPT
   validator rule, since "mutate the map grid" hasn't been a command
   category before.

**Naming:** the general primitive is `wall_event` / `floor_event` (an
interactable attached to a cell, trigger + effect), not `door_event` — the
same primitive covers a painting, a hidden switch, a door, or a trap; "door"
was a conflation to avoid.

## 6. The two "door" concepts, resolved

- **SMT-style door** (visual decoration, triggers a scene like a shop/NPC on
  interact) → a `wall_event`, decoration layer, no structural implication.
  The wall stays a wall for pathing/generation purposes.
- **Doorway/gate/arch** (player physically walks through to another part of
  the same map) → the `opening` structural cell type (§2), not an event at
  all. No trigger, no command list — just passability + a visual variant.

Earlier "doors as events, not tiles" framing was half right: correct for the
SMT-style interaction door, wrong for the doorway/gate, which must stay
structural because it's about connectivity, not decoration.

## 7. Editor implications

- **Discard** the current atlas cell-painting UI as the primary surface — it
  assumes hand-authoring at the tile level, which is no longer the primary
  interaction.
- **New primary surface:** author variant pools + weights, author
  adjacency/context rules (via prefabs first, raw predicate composer second),
  author zone-tag rule subsets, author biome/level override deltas, plus a
  generate → preview → reseed loop.
- Hand-editing survives only as the override-layer pass on top of generated
  (or hand-authored structural) output — demoted, not deleted.
- Town-style hand-authoring keeps working unchanged at the structure layer;
  decoration still applies algorithmically on top, same as today's grain of
  "great" per the owner's own assessment.

## 8. Open questions for the design board

1. **Unified override table shape** — exact schema for the single per-cell
   override concept replacing `tiles{}` + lamp `material`. Needs to express:
   visual override, passability override, and (per §5) an event's structural
   mutation target.
2. **Predicate composition schema** — declarative composition chosen over
   fixed enum (§3); exact operator set (`all`/`any`/`not`/adjacency/distance/
   zone) needs to be enumerated and validated, not left fully open-ended.
3. **Zone/region tagging authorship** — hand-tagged vs. algorithmically
   inferred. Defer to algorithm-first if design proves contentious (owner
   direction) — resolve "what is a dungeon floor, structurally" first.
4. **Structural-mutation command's validator treatment** — new effect
   category touching the map grid; needs sign-off from whoever owns the
   zero-SCRIPT / `validateCommands` rules before it's added to the registry.
5. **`hidden` flag semantics vs. `transparent`** — confirm `transparent`'s
   actual current consumers before deciding whether to repurpose or
   supersede it.

## 9. Explicitly out of scope for this pass

- Data migration for existing peppered map events: additive only (new
  fields/attachment concept), not a rewrite of existing event instances.
  Migration is data-migration-not-fallback per stated preference — but that's
  an implementation-stage concern, not a design-board one.
- Battle/skill/quest command-list work tracked in
  [event-driven-content.md](event-driven-content.md) — this proposal is a
  sibling instantiation of the same pattern, not a dependency of it.
