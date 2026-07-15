# SPEC — Summoner Rework: MP Economy, Roster, Summon/Sacrifice/Promotion (Overhaul 6)

Audience: an agent executing ONE task. Your brief tells you which sections to
read. Do not change this spec; if your task conflicts with it, stop and
report. Design source of truth for intent (read before this SPEC, not
instead of it): `docs/game design/Summoner.md`.

Integration branch: `fable-6-overhaul-6`. Ground rules (gates, golden
discipline, review protocol) are identical to overhaul-5's — see
`docs/ORCHESTRATION.md`. Restated here because this round breaks golden logs
on purpose (see S0): **every brief that touches `engine/battle.lua` or
`engine/scenes/battle.lua` is owner-supervised, never autonomous** — same
rule ORCHESTRATION.md already applies to D8/D11 in overhaul-4, now extended
to this entire round because F1–F2 rewrite the exact code those covered.

## S0 — Why, and what breaks on purpose

The Summoner currently fights: they have HP, a command phase, a spell list,
and the battle is lost when their HP hits 0 (`engine/battle.lua:388-390`).
The owner's design (`Summoner.md`) removes all of that — the Summoner
becomes a name + MP pool + equipment, sitting outside the battle loop
entirely. MP stops being "the summoner's spell-cost meter" and becomes the
resource that keeps the whole active roster alive.

This is intentionally golden-log-breaking. `tools/golden/battle.log` encodes
a battle where the summoner acts and can die — that scenario no longer
exists after F1. **F1 is the one brief in this round permitted to
regenerate `battle.log`**, and only after owner sign-off that the new
recorded sequence is correct, per the same discipline overhaul-4's D-series
used for its one sanctioned regeneration. Every brief after F1 must keep the
*new* battle.log byte-identical — the "never regenerate to green a diff"
rule resumes immediately once F1 lands.

## S1 — Current state (grounded, read before touching code)

- **Summoner today**: `session.lua:124-129` builds a `Battler` summoner with
  HP; `getActiveParty()` (session.lua:170-180) appends it as ally index 5.
  `Battle:resolveRound(summonerAction)` (`battle.lua:94`) runs the summoner's
  chosen action first, then creature AI actions. Loss = summoner dead OR all
  4 creatures dead (`battle.lua:388-399`). Command menu
  (`commands_summoner` in terms.json) is the only interactive one; monster/
  creature commands are AI-picked (`battle.lua:28-90`), `commands_monster`
  term is currently vestigial display text with no code path reading it.
- **MP today — two overlapping systems already exist**, both against the
  single shared `session.mp`/`session.maxMp` pool (init from
  `system.summoner.startMp`, no per-creature MP):
  - Round-end drain: `battle.lua:340-374` drains `traits.getParam(ally,
    "mpd", session)` per living ally creature each round (skipped on
    `mapData.safe`); at `session.mp <= 0`, `config.combat.mpExhaustionDamage`
    applies to every living creature per round. **This is the mechanism
    Summoner.md describes ("if MP hits zero... active creatures start
    suffering per-round damage") — it already exists and is close to
    correct as-is.** F2's job is auditing it for correctness under the new
    rules (does draining still make sense once summoner isn't an ally?),
    not building it from scratch.
  - Command-driven: `CHANGE_MP`/`DRAIN_MP`/`RESTORE_MP` in
    `interpreter.lua:368-388`, used by skill/item scripts. Unaffected by
    this round except insofar as spell costs move (S onto creatures, not the
    summoner — see F1).
- **`data/actors.json`**: 22 flat entries, fields include `role`,
  `evolutions: [{level, evolvesTo}]` (11/22 non-empty — Pixie → High Pixie is
  real data; Titania does not exist yet), `isRecruitable`, `isEvolved`,
  `initialParty`. **No tier or unlock-flag field exists yet** — F4 adds one.
- **`session.party`**: plain array, `getActiveParty()` only reads slots 1-4;
  nothing enforces a max today. `session.lua:131` has an aspirational
  comment ("6+ are reserve") with zero backing implementation — no reserve
  array, storage, or UI exists. F3 builds this from nothing.
- **Command lists**: summoner's are truly interactive
  (`engine/scenes/battle.lua`'s state machine); creature/"monster" ones are
  AI-generated (`battle.lua:28-90` `getAIAction`). F7 (Item joins creature
  commands) touches both the AI generator and wherever a per-creature Item
  submenu gets built.

## S2 — F1: Summoner exits the battle loop

- Remove: `session.summoner` as an ally-index-5 combatant
  (`getActiveParty`), `resolveRound`'s `summonerAction` param and the
  summoner-acts-first block, the summoner-HP loss check, the summoner status
  console block in `presentation/renderer.lua` (summoner sprite/HP/MP
  bar/spell list/command menu), `presentation/battle_layout.lua`'s
  `summonerPopupX`/`summonerStatusX`/`summonerMpText/Bar*` constants (or
  repurpose — see F2 for where MP display moves to), the
  summoner-only-targetable-after-all-creatures-dead AI branch.
- Keep: `session.mp`/`session.maxMp` as fields (their owner is now
  conceptually "the summoner" but they stay on `session`, not a `Battler`
  wrapper — no code currently needs a `Battler` interface for MP).
- New loss condition: all 4 active creatures dead. Delete the
  `session.summoner:isDead()` branch of `isDefeat()` entirely — do not leave
  it as dead-but-reachable code.
- The summoner's own turn phase is gone; battle's round loop runs creature
  actions only. Decide and document (in the brief's own PR description, not
  this SPEC) what — if anything — the summoner's `commands_summoner` Item
  submenu becomes; F7 formally moves Item onto creature command lists, but
  F1 must not leave a dangling summoner Item entry point mid-round.
- Golden: this is the one brief allowed to regenerate `battle.log`. Get
  explicit owner sign-off on the new recorded sequence before committing the
  regenerated log (same protocol as overhaul-4's sanctioned regeneration).
  UI-golden `scene_battle.log`, `scene_status.log` etc. likely also need
  regeneration if summoner display disappears from any window — same
  sign-off rule applies per-file.

## S3 — F2: MP as the central resource

- Audit the existing round-end drain (`battle.lua:340-374`) against
  Summoner.md's rules: drain source is unchanged (active creatures drain
  continuously), but confirm the drain no longer has any summoner-specific
  special-casing left over from F1's removal.
  If it drains only `session.mp` — the resource formerly framed as
  "summoner's MP" — decide whether that's still the right mental model now
  that the summoner isn't present to visually "spend" it; likely yes (MP is
  a shared party resource regardless of whose name is on it), but this is a
  design confirmation to make explicit in the brief's PR, not a silent
  no-op.
- Spell/skill MP costs: confirm `CHANGE_MP`/`DRAIN_MP` command sites still
  resolve against `session.mp` correctly now that costs are framed as "a
  creature's spell costs MP" rather than "the summoner's spell costs MP" —
  likely no code change, but audit call sites in `data/skills.json` for any
  summoner-specific assumptions.
- MP-exhaustion damage (`config.combat.mpExhaustionDamage`) already targets
  "every living creature" — confirm this still reads correctly post-F1 (it
  should, since it iterates active allies, not the removed summoner ally
  slot).
- Where does the MP bar display now live? Summoner.md doesn't specify UI
  placement. Recommend a small persistent MP readout in the same bottom
  party-window strip the map/battle HUD already shares
  (`engine.json windowLayout.party`, per o5's UI-consistency-pass
  convention) rather than reviving a dedicated summoner panel — propose this
  in the brief's own design note and get a quick owner nod before
  implementing, since it's UI-visible and not explicitly speced.
- **No balancing pass here** — costs/rates/thresholds stay at current
  values unless a value is provably broken by F1's removal (e.g. a formula
  that divided by a now-absent summoner stat). Real number tuning is
  explicitly deferred to post-round playtesting per the o6 README.
- Golden: `battle.log` must NOT change again after F1's sanctioned
  regeneration — this brief is plumbing/audit only, not new mechanics.

## S4 — F3: Reserve roster (4 active + 8 reserve)

- New session-data shape: `session.party` becomes 4 active + a new
  `session.reserve` (or equivalent) array of up to 8. Reserve creatures:
  no MP drain (already true — drain only touches active allies), no battle
  actions, not targetable (already true — battle only reads active party).
  The main change is **where reserve creatures live and how they're
  displayed/swapped**, not battle-loop logic.
- Swap UI: **owner decision needed before implementation** — o6 README
  flags this as open (map's per-unit popup vs. a new field-menu command).
  Given o5 already built a map ESC-overlay party popup with per-unit
  Status/Equip/Item Creation options (`data/scenes.json` map scene, see
  overhaul-5's memory notes), the lowest-friction answer is very likely a
  new option in that same popup or command row — but confirm with the owner
  before committing to a UI shape, this brief should not guess a layout.
- Roster storage: decide whether reserve members persist as full `Battler`-
  backed data (simplest — same shape as active party, just not iterated by
  battle) or a lighter serialized form. Recommend the former: no new
  serialization format, reuses everything `Battler`/`session.party` already
  does, "reserve" is purely "not in the first 4 slots."
- Golden: unaffected if the golden battle/session mock only ever populates 4
  party members (confirm before landing) — flag if the mock needs updating.

## S5 — F4: Summon

- New `actors.json` field: an unlock flag (e.g. `unlocked: false` by
  default, `true` for starting species — audit `initialParty`/
  `isRecruitable` to see if one of those can be repurposed instead of adding
  a redundant field; prefer reuse if the semantics genuinely match, add new
  only if they don't).
- Unlock **sources** are explicitly meant to be diverse (defeat/contract/
  negotiation/NPC/item-held/etc.) — do not build one universal gate. Start
  with the smallest viable set the owner actually needs for early content
  (likely: an interpreter command like `UNLOCK_SPECIES <id>` usable from any
  event/dialogue script, since that alone covers NPC-offers, contract
  triggers, and defeat-triggered unlocks via existing battle-end event
  hooks) and leave room for more triggers later rather than speculatively
  building all of them now.
- Summon mints a **fresh instance** at level 1 by default; paying extra MP
  buys a higher starting level via a formula — needs a formula slot (likely
  `system.json` config, following the o5 convention of formula-driven
  numeric config over hardcoded Lua) and a summon-cost-by-species-tier
  number. Since no tier field exists yet (S1), this brief either adds one or
  derives a proxy from an existing field (e.g. base stats) — decide and
  document; don't leave cost undefined for species with no tier assigned.
- Summon is **field-menu-only** (never mid-battle) — gate at the UI entry
  point, not by trying to hide it during battle scenes.
- Requires a target reserve slot (mints into an empty reserve slot, or
  choose a slot / swap out if full — decide with the owner if roster is
  full, since Summoner.md doesn't specify).
- Golden: new mechanic, no existing golden coverage — but if this touches
  any interpreter command surface exercised by golden scenes (unlikely),
  re-verify byte-identity.

## S6 — F5: Sacrifice

- Permanent creature removal from roster (active or reserve). Refund MP
  scaled by the sacrificed creature's level (formula slot, same convention
  as F4's summon-cost formula). Optional item reward gated by: creature
  state at time of sacrifice (HP%, level, conditions) AND species/discipline
  — this overlaps directly with Item Creation's per-species discipline data
  (`docs/game design/itemCreation.md`, docs-only currently). **Coordinate
  the data shape with whatever Item Creation's discipline identity ends up
  being** rather than inventing a second species-flavor table — if Item
  Creation's discipline field doesn't exist in `actors.json` yet by the time
  this brief runs, either this brief adds the shared field (documenting it
  as shared) or blocks on it; don't fork two separate per-species flavor
  systems.
- Field-menu-only, same gating rule as Summon.
- Permadeath interaction: `docs/game design/Permadeath.md` exists — read it,
  confirm Sacrifice and Permadeath are understood as distinct mechanisms
  (Permadeath = death from battle/events; Sacrifice = deliberate player
  choice) that likely share a "creature is permanently gone, roll growth
  back to nothing" code path — reuse rather than duplicate if Permadeath's
  removal logic already exists by the time this lands.

## S7 — F6: Promotion

- Ritual triggered at `evolutions[].level` threshold (real data today for
  11/22 actors; Titania doesn't exist as an actor yet — creating missing
  evolution-target actors, if wanted, is a content task, flag it separately
  from this engine brief rather than silently doing it inline).
- Cost is flexible per-species: free / MP / promotion key items, **often**
  key items. Needs: a promotion-key-item category or flag on `data/
  actors.json`-adjacent item data (new item field, e.g. `promotionKeyFor:
  <actorId>` or a generic `category: "promotion_key"` — prefer the more
  general form so it's reusable beyond promotion if a similar gated-item
  need shows up later), and a ritual UI flow (likely triggered from the
  reserve/roster UI F3 builds, or Status scene — decide with owner).
- Depends on F5 (Sacrifice) being landed if promotion-key items are meant to
  drop from sacrifice per Summoner.md ("sacrifice being one of them") —
  sequence after F5.

## S8 — F7: Battle command list — Item joins creature commands

- With the summoner gone from the command loop (F1), Item needs a home.
  Summoner.md: "Item joins each creature's own command list alongside
  Attack/Skill/Defend/Flee — using an item spends that creature's turn."
- Since creature actions are currently AI-generated
  (`battle.lua:28-90` `getAIAction`), not player-menu-driven, this brief has
  two real jobs: (1) decide/confirm with the owner whether creature turns
  become player-driven now that they're the only combatants (this is a much
  bigger UX shift than "add an Item option" — Summoner.md's phrasing implies
  yes, since it describes a per-creature *command list*, which only makes
  sense if a player is choosing from it), and (2) if so, build the
  interactive command menu per creature (reusing `commands_summoner`'s old
  UI plumbing where it fits) with Attack/Skill/Defend/Item/Flee. This is
  likely the single largest UX-shaped decision in the whole round short of
  F1 itself — **do not start this brief without an explicit owner
  conversation confirming "creatures become player-controlled in battle"
  is the intended reading**, since the alternative (AI keeps picking
  Attack/Skill/Defend/Flee automatically, Item is just a new option the AI
  can also pick) is a much smaller change with very different scope.
- Sequence last — depends on F1's loop rewrite being stable and, if player-
  driven, likely wants F3's roster UI conventions to reuse for target/
  member selection.

## S9 — Balancing, explicitly out of scope for this SPEC

No brief in this round should hand-tune MP costs, drain rates, exhaustion
damage, summon costs, or sacrifice refunds beyond "plumbing produces a
plausible non-zero number." Real numbers come from a dedicated post-round
playtesting pass per the o6 README — do not block a brief's merge on
"finding the right number."
