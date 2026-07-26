# Item Creation

> **Intent, not status.** This document describes what we mean to build and why.
> For what is actually implemented right now, read the generated
> [`docs/ENGINE-STATE.md`](../ENGINE-STATE.md) (gated by G4); for how the engine
> works, `docs/SPEC.md`. Where this document and those disagree, they win.

The appeal is **breadth** — a vast combination space that dangles possibilities
in front of the player, like exploring a latent space of items. That is why
there is deliberately **no recipe table**: authored exact-match recipes would
narrow the very thing that makes the system exciting.

The first version undercut its own ambition. Two ingredients and a stat were
compressed into one scalar, quantised into one of four tier brackets, and used
to index a shelf of 1–4 items. Everything the player did reached the outcome
through a two-bit channel, so ingredients had no identity beyond a number,
element could only ever subtract, and nothing the player learned accumulated.
No amount of extra content fixes a two-bit channel. This design widens it.

---

## 1. Each discipline is its own space

**Form is categorical and comes from the crafter. Element and intensity are
continuous and come from the ingredients.**

A cook cannot forge a sword — not because a rule forbids it, but because
cooking *is* the act of making food. The gate is definitional, so it needs no
threshold, no penalty and no exception. There is no cross-discipline escape
hatch at all, not even a rare one.

So there is no single "craft space". There are four, one per discipline, each
small and dense rather than one large and sparse: **hue plane × value axis ×
intensity.** Recruiting a crafter is not unlocking a filter, it is unlocking a
whole map.

## 2. Elements are a colour space

The element relationships are not a flat list, and their shapes differ:

- **Red > Green > Blue > Red** is a *cycle*. No two are opposed, so they sit
  120° apart on a plane — a **hue plane**, in barycentric coordinates.
- **White ↔ Black** is a true *opposition*. That is one signed axis — **value**.
- **Non-elemental is the origin** of both.

A hue plane plus a light/dark axis is a colour space. The fiction and the
geometry are the same object, which is what makes the whole model legible.

Consequences that fall out rather than being designed in:

- **Mismatch relocates rather than punishes.** Red + Black does not cost you
  points; it pulls you off the pure-Red spine toward the neutral centre, which
  is where non-elemental items actually live. The old flat −15 penalty is
  deleted, not reduced.
- **The two kinds of mismatch grade differently.** White and Black are 180°
  apart and cancel fully — the canonical route to true neutral. Red and Green
  are 120° apart and only partially cancel, drifting centre-ward.
- **Saturation is a scarce resource.** The deep-element items sit far out on
  their spines. Reaching them demands element *purity*, which demands matched
  ingredients, which is a real constraint to plan around.
- **Blending is dominance-weighted** using `elementRules` — the same table the
  battle system uses for elemental advantage — so the stronger element asserts
  itself in a mixture instead of meeting at the midpoint. One table, two systems.

## 3. Signatures are read, not authored

An item's position is derived from what it already is. Nothing is hand-authored,
because hand-authored parallel fields drift: the old `meta.potency` and `cost`
disagreed badly (Ambrosia 500g/p45 against Radiant Blade Flavio 1995g/p22), and
that drift was invisible.

| source | contributes | confidence |
|---|---|---|
| `traits[]` via the `traitCodes` registry | element | exact — `ELEMENT_CHANGE` names an element outright |
| `effects[]` via the `effectTypes` registry | element | strong — `hp`→Green, `learn_skill`→White, `param_plus` follows its param |
| name, and description at lower weight | element | a small authored lexicon; the "in moderation" signal |
| `cost` | intensity | the game's own hand-tuned statement of worth, log-scaled |

The registry-driven rows matter most architecturally: one table mapping
`effectTypes` and `traitCodes` entries to element contributions means **every
new effect or trait automatically participates in crafting.**

Naming an item is therefore an act of design. "Ember Root" *is* fiery, with no
meta authoring — which also means generated content signs itself.

**The one admitted override is intensity**, as a closed set of named grades
multiplying the price-derived value (`mundane`, `precious`, `legendary`). It
records where the author *disagrees with the price* — a rare herb that costs
nothing and does a lot. Multiplicative and enumerated on purpose: an absolute
field would fork the number and drift exactly the way `potency` did.

## 4. Membership says what a craft can produce

`meta.disciplines` is an array naming the disciplines that can produce an item.
It defaults from what the item plainly is — `Weapon`/`Armor` → blacksmithing,
`Accessory` → tinkering, consumable with `mp_heal` → cooking, other consumables
→ alchemy — so only the interesting exceptions are ever written.

This is authored rather than derived, and that is consistent: element and
intensity are *duplicates* of what the item already states, but "a spring-loaded
blade belongs to tinkering as well as blacksmithing" is a judgement about the
fiction that no property encodes.

**Overlap is the cheapest density multiplier available.** Letting a few elixirs
also register as cooking furnishes a thin discipline with zero new content.

## 5. The craft

**The crafter is the third vertex.** Two ingredients only define a line; the
crafter's own elements lift the point off it. That is why two slots suffice —
the third point is *who does the work*, which is legible without any numbers and
makes the roster the real breadth dial. The pull uses **innate elements only**:
crafting identity is what a creature *is*, not what it is wearing, or a bag of
`ELEMENT_CHANGE` trinkets would collapse the whole roster into one.

**Ingredients are ungated, but foreign ingredients steer without empowering.**
Anyone may put anything in the pot; an ingredient whose membership excludes the
crafter's discipline contributes its element in full but only a fraction of its
intensity. Iron filings in a stockpot tint the stew and add no worth, so the mix
collapses toward the origin and yields slop — consistently, and occasionally,
via scatter, something interesting. No special case required.

This also makes the ingredient vocabulary discipline-aware. Cheap, fully
saturated items are universal **reagents** that steer for anyone; expensive
items are **valuables** that only empower their own craft.

**Precision is scatter, and scatter is the whole of the difficulty curve.** The
ideation point is displaced by noise whose size shrinks as the crafter's
discipline stat grows. A novice's hand wanders; a master lands where they aimed.
Mastery manifests as the world becoming predictable to you, which is a better
progression beat than a rising number.

**Reach is a falloff, not a wall.** Items above the crafter's reach are not
forbidden, only distant, and the distance grows with the excess. Scatter
occasionally carries a craft up there anyway — which is the entire "barely got
it, inconsistently, with the right mix" experience. **There is no anomaly and no
critical hit.** The exciting outcome is earned by a good mix at the edge of
ability, and it is never announced.

**Determinism is per attempt.** The attempt's seed is stored in the save, so
reloading reproduces the outcome but a genuinely new attempt rolls fresh. No
save-scumming, and crafting never degenerates into a lookup table.

**Resolution is nearest-neighbour** over the items the crafter's discipline can
produce, weighted across element, value and intensity, plus the beyond-reach
cost. Both ingredients are always consumed and something is always produced —
when nothing coherent is near, that something is one of the weak items at the
origin.

## 6. What the player sees: nothing numeric

Numbers are fantasy poison. `Expected Yield: 34` and `Expected Tier: Superior`
are gone, along with the element-conflict warning. The confirm screen is two
ingredients, a crafter, a reaction, and Craft/Back.

Three diegetic channels replace them:

1. **The crafter reacts.** One line before committing, banded by coherence —
   *"Candle turns the two over, and something in the flame steadies"* against
   *"Candle doesn't seem to know what to do with these."* The player learns to
   read the creature, not a gauge. This is the floor: opacity plus scatter
   without an honest reaction line leaves a new player with no handle at all.
2. **The reel is the readout.** It is populated with the actual neighbourhood in
   distance order, and its behaviour carries the information — high coherence
   snaps decisively, low coherence wanders through slag before settling. The
   player sees what they were *near* without a single digit, and the near-miss
   becomes drama instead of a statistic.
3. **Unknowns flash past as silhouettes.** `???` cards for items ideated near but
   never made. That is the "there is something over there" tease, and it is what
   makes the space feel explorable rather than merely large.

The ideation may also be rendered as **a colour** — it literally is one — so the
crafter's own light takes the hue of what is being imagined. Deep crimson when
driving hard into Red, muddy grey when incoherent. Zero digits, read fluently in
about three crafts.

## 7. Why the roster is the real content

Crafting aptitude comes from the levers the roster already has, not a separate
"crafting" number: discipline usually does *not* match a creature's strongest
stat, so battle performance, Item Creation aptitude and sacrifice value pull in
different directions. Candle is the archetype — 7 HP and 7 ATK make it useless
in a fight, it cannot evolve, and MDF 22 makes it the best tinker on the roster.
Recruiting it is a crafting decision. Aptitude can also come from what a creature
*is*: `CRAFT_YIELD_RATE` scales a crafter's reach without touching a battle stat.

And a crafted item is not a dead end. Products and ingredients share one table,
so **every item you make is a new coordinate you own** — a stepping stone to
regions you could not previously triangulate to.

**A diverse party buys you breadth, and this is measurable.** Reachability is the
intersection of *(native reagents in each element)* × *(crafter elements)* ×
*(intensity headroom)*. Cooking has zero unreachable items because its crafters
span four elements; blacksmithing has several because its crafters span only
three, all dark, and it has no Green reagent at any usable intensity — so Wind
Dancer and Water Scepter cannot be made by anyone alive.

That yields a concrete authoring rule:

> **Every discipline wants a low-to-mid-intensity reagent in each element, and
> crafters spanning several elements.** For smithing that is ores; for alchemy,
> essences; for cooking, staples.

A discipline missing an element in either list has a hole in its space that no
amount of engine tuning will fill.

## 8. What crafting is for

Promotion keys and creature-shaping items are craftable, and that is the intended
path to them — the Chrysalis Sigil is a `promotion_key` with full craft meta, and
a creature's branching promotion is authored as an `evolutions` entry with
`cost: {item: <key>}`. The `learn_skill` and `param_plus` effects make skillbooks
and permanent stat-ups possible, and they may come from both sacrifice rewards
and crafting pools. The balance levers are therefore reach and pool composition,
not source scarcity.

## 9. Open

- **Content is the binding constraint.** The model wants roughly 10–20 items per
  discipline plus per-element reagents; cooking currently has six. The map in
  `tools/craft-space/` reports reachability and concentration per discipline and
  is the instrument for this.
- Only one promotion key exists for ~5 promotion lines.
- `evolutions` entries require a `level` threshold, so a purely item-gated
  promotion needs a dummy `level: 1`, and cost is the only gate — no element,
  discipline or flag conditions yet.
- More crafting passives. `CRAFT_YIELD_RATE` exists and `artisan` (+25%, Candle)
  is its only holder; the obvious companions are a negative rate for creatures
  that are all thumbs, and a scatter-reducing trait distinct from reach.
- Whether alignment *depth* should strengthen a crafter's pull. It currently does
  not — `Red` and `Red/Red/Red` produce identical pull directions — so depth is a
  battle-only dial.
