# Skill costs: Charges, Overcast, Cooldowns, Warmups, Conditions

*Design intent, 01.08.2026. Not a status document — see `docs/ENGINE-STATE.md`
for what exists.*

## 1. The problem with MP costs

MP in this engine is **the Summoner's shared pool** (`session.mp`), not a
per-creature bar (SPEC §1.11). It prices the *expedition*: a step costs the
combined MPD of the living party, and Battle Strain prices dragging a fight out.
That is a strategic, between-decisions resource.

A per-skill `mpCost` charged against the same pool would mean every heal a
creature casts is spent out of the party's remaining walking distance. It also
gives every caster the same wallet, so a creature's own magical stamina is
invisible: two Pixies and one Bahamut draw from one number.

The evidence that this never worked: `mpCost` exists on 33 of the 44 rows in
`data/skills.json`, is read by exactly one function
(`usability.canUseSkill`), **which nothing calls**, and is never deducted
anywhere. Skill MP cost has been decorative since it was authored. So there is
nothing to preserve, and no balance data behind the numbers.

**Decision: no ability in the database costs MP.** `mpCost` is removed from
every skill. MP is spent by the Summoner on traversal, Strain, summoning and
promotion — and, newly, on **Overcast** (§3.3), which is the one place a skill
may reach the shared pool and is deliberately expensive enough to feel like
spending the party's road home.

## 2. Two cost families, one selection rule

| Family | Resource | Feel |
|---|---|---|
| Magic | **Charges** — a per-skill, per-creature counter refilled at Rest | "How many more times today?" |
| Physical | **Availability** — cooldown, warmup, and conditions | "Can I do it *this turn*?" |

Both answer the same question the battle menu asks — *is this row selectable,
and if not, why* — so both resolve through **one** predicate. `canUseSkill`
already has that shape and the right signature; it becomes the single authority
and gets wired to the callers that should always have used it:

- the battle command submenu (greying + reason text),
- `Battle:getAIAction`, so an enemy cannot cast a spell it has no charges for —
  **one rule binds both sides**, the same principle SPEC §1.12 states for
  `FORCE_ACTION`,
- the status scene's skill rows (`memberSkillRows` in
  `presentation/window_renderer.lua`), for the out-of-battle readout.

A skill that a creature *knows* is never hidden. It is shown unusable with its
reason, because a row that vanishes looks like a bug and teaches nothing.

## 3. Magic: Charges and Overcast

### 3.1 Charges, and what MDF really is

The engine's stat names are RPG-Maker-compatible, but the **intent** is wider
than mitigation:

- `mat` is **INT** — how hard a spell hits.
- `mdf` is **SPR** — the spirit's depth: how much magic a creature can *hold*.
- `def` is **VIT** — the body's resilience, not just an armour number.

Charges are where SPR stops being a damage-reduction stat and becomes an
identity. A magic skill declares a **charge formula**, not a flat number:

```json
"charges": "4 + b.base.mdf / 4"
```

Evaluated through `engine/formula.lua` against the caster, floored, minimum 1
(except a literal `0`, see §3.3). Max charges therefore rise with level and
promotion for free — a promoted caster gets more castings without the skill row
changing.

This produces two caster archetypes from one formula:

| Statline | Result |
|---|---|
| High INT, low SPR | Devastating, three castings, folds to enemy magic — a **nuke you must ration** |
| High SPR, low INT | Chip damage forever, shrugs off spells — **attrition**, cheap to run |

The glass cannon is worse on three counts at once, which would normally be a
dead archetype. Overcast is its escape hatch: it is not a bad statline, it is a
statline with a *spending problem*. And the two diverge further over a campaign
rather than converging — a very high SPR creature eventually has functionally
unlimited castings and stops needing Overcast entirely (it earned that), while
the INT caster stays on the Summoner's payroll forever, with its Overcasts
getting more expensive as its spells get bigger. **That divergence is the
design, not a leak to be capped.**

**The engine must not derive charges from a spell's potency.** The tempting
version of "powerful spells have few charges" welds damage tuning to economy
tuning, so every balance nudge silently moves charge counts and G2 goes red for
reasons nobody intended. The *base* is authored per skill — a big spell as
`1 + b.base.mdf / 12`, a cantrip as `6 + b.base.mdf / 4`. The author sizes it;
the stat scales it.

### 3.2 Charges are creature state

Current charges live on the **battler**, keyed by skill id:

```lua
battler.charges = { windBlade = 3, soothingMote = 5 }
```

Per-creature and per-skill: two creatures knowing Wind Blade have independent
pools, and one creature's Wind Blade and Soothing Mote do not share. Charges are
serialized with the battler (`serializeBattler`, `engine/savegame.lua`),
alongside the death-ward charges already stored there — the same precedent, for
the same reason: it is creature state, not loader state.

Missing key = full. A newly summoned, promoted or loaded-from-an-old-save
creature starts topped up rather than empty.

### 3.3 Overcast

A magic skill at zero charges is not dead — it may be **Overcast**, paid out of
the Summoner's MP:

```json
"charges": "4 + b.base.mdf / 4",
"overcast": { "mp": 120 }
```

The cost is deliberately steep relative to the traversal economy (a step at
party MPD 5 costs 5; opening Max MP is 3000). Overcasting a handful of times
should visibly shorten the expedition — that is the tension: *this fight, or the
walk home.*

Rules:

- Overcast is only offered at **zero charges**. It is never a cheaper
  alternative to spending a charge, so there is no optimization to think about.
- The battle menu shows it as the row's cost when charges are 0
  (`Wind Blade  ⟨0⟩  Overcast 120 MP`), unusable if `session.mp` is short.
- `overcast` absent = the skill cannot be cast at 0 charges. Some magic should
  be unavailable, not purchasable.
- **Enemies never Overcast.** They have no Summoner and no MP pool; an enemy at
  zero charges is out of that spell, which is the intended pressure release for
  a long fight.
- Overcast MP is charged in the same place a charge would be spent, so the two
  paths cannot drift.

**Overcast-only skills** are spelled with a charge pool that exists and is
permanently empty:

```json
"charges": 0,
"overcast": { "mp": 400 }
```

No second code path — the zero-charge branch is the *only* branch such a skill
ever takes. This is the intended shape for the dragon family's **Breath**
attacks (not yet authored). A Breath is not something a dragon has a daily
supply of; it is something it draws out of its Summoner. The biggest creature in
the party already has the highest MPD — it is the expensive passenger — and its
signature move bills you again, in the same currency, at the moment you use it.
A dragon is not a creature you own, it is a creature you finance.

Consequence, accepted deliberately: since enemies do not Overcast, an **enemy**
dragon cannot breathe. That is not special-cased. Enemy Breath is a separate
skill row or a troop-authored event, which is how SPEC §4.2 already prefers a
troop to own the shape of a fight.

### 3.4 Rest

**Rest fully restores charges** for every creature in party, reserve and
storage. Rest is not a new subsystem — it is `RECOVER_PARTY`, which already
exists as an interpreter command and already fires from town events. Charge
refill joins the HP/state reset it performs, so:

- **entering town rests you** (the existing town-arrival recovery),
- **a dungeon rest site is authorable today** — an event that calls
  `RECOVER_PARTY`, gated however the author likes (once per floor, an item, a
  flag). Exactly the "systems from event blocks" principle: a campfire needs no
  engine work.

**Promotion is a rest.** It is rare, it rebuilds the creature, and it happens in
the ritual — the same ceremony summoning happens in. Stating it as a rule rather
than an exception keeps it one sentence long. **Level-up is not**; levelling
raises max charges without refilling current.

Partial restores are the item/food channel, and want a new effect type rather
than a new command:

```json
{ "type": "restore_charges", "amount": 2 }            // +2 to every skill
{ "type": "restore_charges", "skill": "windBlade", "amount": "all" }
```

`amount: "all"` is the full-rest case, so the effect and the command share one
implementation in `engine/effects.lua`. `usability.canUseItem` learns the
matching "nothing to restore" guard, in the same shape as its existing full-HP
and MP-full guards, so a Mana Nut cannot be burned for nothing.

Charges do **not** regenerate per turn or per battle. Persisting across fights
is the point: the resource that makes a dungeon run a run.

## 4. Physical: Cooldown, Warmup, Conditions

These are **availability gates**, not currencies. All three are declared on the
skill and all three resolve in `canUseSkill`.

They are deliberately *not* stat-scaled, and the physical family deliberately
does not mirror the magic family. An earlier draft had DEF shorten cooldowns for
symmetry; that was symmetry for its own sake, and it would have made VIT a
super-stat. Physical skills are gated by *situation*, magic by *supply*.

### 4.1 Cooldown

```json
"cooldown": 3
```

Turns that must pass after use before the skill is available again. Ticked at
`battle.round_end` — an existing flow, so the tick is authored data rather than
new engine branching.

### 4.2 Warmup

```json
"warmup": 2
```

Turns from the **start of a battle** before the skill becomes available at all.
A finisher that unlocks on round 3 needs no state machine; it needs a number.

Warmup and cooldown are independent and may legitimately differ: a skill can
take 4 rounds to become available and then be usable every round (`cooldown`
absent), or unlock late *and* stay slow.

### 4.3 Conditions

```json
"condition": "a.hp >= a.maxHp"
"condition": "state:blind"
```

A formula string, or one of the prefixed forms `engine/conditions.lua` already
owns (`flag:`, `hasItem:`, `gold:`, `questStatus:`), extended with a `state:`
prefix. That module exists precisely to stop two grammars drifting apart, so a
new gate belongs there, not in a private parser. The formula fallback gives
"only at Max HP", "only below half HP", "only while Blind" with no new
vocabulary.

A failing condition needs an **authored reason string**, because a formula
cannot produce readable text:

```json
"condition": "a.hp >= a.maxHp",
"conditionText": "Only at full HP"
```

Missing `conditionText` is a **G1 failure**: an unexplained grey row is a bug
report waiting to happen.

### 4.4 Battle-scoped state

Cooldown and warmup counters are **battle-scoped**, not persistent — they live
with the battle's per-battler bookkeeping and are discarded at battle end, the
way states already are. They are therefore *not* in the save payload, unlike
charges. Charges answer "how much is left of the day"; cooldowns answer "what
can I do this turn". Different lifetimes, different homes.

## 5. Base stats vs final stats

**Base stats say who the creature is; final stats say how hard it is to hurt
right now.** Economy and resistance read the first, damage reads the second.

`traits.getBaseParam` already computes the base — actor base plus accumulated
growth, *before* equipment/state/passive `PARAM_PLUS` and `PARAM_RATE`. What is
missing is any way for a formula to reach it: `formula.battlerView` exposes only
`traits.getParam` (final) as `b.def` / `b.mdf`. So this needs a **`b.base.<param>`
accessor**, lazily via `__index` exactly like the existing `b.trait.<CODE>`.

Three consequences that justify the rule independent of flavour:

1. **Equipment cannot buy charges.** An accessory granting +30 MDF makes you
   resist magic; it does not hand you castings. Otherwise charge-stacking gear
   becomes the only gear.
2. **A debuff cannot strip them mid-fight.** If charges read final MDF, a
   `PARAM_RATE` debuff would shrink a creature's *maximum* charges while it
   holds spent ones — current above max, or silent losses. A bug class deleted
   by construction.
3. **Unequipping in a dungeon cannot shift max charges** under the creature's
   feet, which would be a nasty save/restore interaction.

## 6. Defensive stats do more, and hit less hard

Giving DEF and MDF jobs beyond mitigation means their mitigation should be worth
proportionally less.

### 6.1 Ailment resistance from base DEF/MDF

This is not a new mechanism. SPEC §1.12 already has states carrying a *list* of
categories (`physical`, `magical`, `mental`, `negative`, `common`) and already
resolves infliction through a **product** of every `STATE_RATE` and
`STATE_CATEGORY_RATE` that names one of them. Poison is already tagged
`physical`. So the stats become one more multiplicand in a product that already
multiplies:

```text
physical category rate ×= f(base DEF)
magical / mental rate  ×= f(base MDF)
```

`f` is authored as a formula in `engine.json`, so the curve is a data knob. This
makes the two defensive stats feel different rather than mirrored: DEF is the
body's resilience (Poison, Paralysis, Blind), MDF is the spirit's (Sleep, Charm,
Confusion), *and* MDF alone carries the charge economy.

### 6.2 The damage coefficient (sequenced separately)

Defense appears in exactly one place in the damage model
(`potency × power² / (power + defense)`), so weakening it is one coefficient:

```text
potency × power² / (power + defense × k)
```

`k` lives in `engine.json`. **This must not land in the same commit as the cost
system.** It moves every damage number in the game at once, invalidates the
balance tables in `creature-parameters.md`, and turns G2 red for every golden
fixture simultaneously — at which point a G2 diff can no longer tell you whether
the charge system is correct. Its own step, its own owner-signed regeneration,
after the cost system is in and stable.

## 7. Immunity is a trait; a critical bypasses rates

Today, a state rate of 0 means absolute immunity, and that is the single
exemption to the rule that a critical hit forces the status attached to it.
Overloading 0 this way costs a special case in the code and a paragraph of
explanation in two spec sections.

**Immunity becomes its own trait**, as in RPG Maker MZ, and the rate chain loses
its special case:

| Code | Meaning |
|---|---|
| `STATE_IMMUNITY` | `dataId` = state id. Binary. Nothing lands it, ever. |
| `STATE_CATEGORY_IMMUNITY` | `dataId` = category. The Ribbon's actual spelling. |

```text
chance = skill chance × STATUS_SUCCESS × state rate      -- floored at 0
critical         → lands, skipping the whole chain
immunity trait   → never lands, including on a critical
```

A rate of 0 (or below) now means *vanishingly unlikely*, not immune: a
high-VIT creature is functionally unpoisonable, but a critical still gets
through. The **critical-status exemption disappears from the code entirely** —
one branch and one concept deleted. That is the tell that this is the right
model.

It also retires a constraint an earlier draft imposed: the derived DEF/MDF
resistance curve (§6.1) no longer needs to asymptote away from zero, because
zero is no longer magic. The curve can be whatever shape reads best.

The existing `state_immune` event and its line of text are kept — the trigger
changes from "rate was 0" to "an immunity trait blocked it", but a status that
never appears must still say so rather than passing silently.

### 7.1 Critical defense

With criticals now the universal status backdoor, being hard to crit matters
twice: less burst damage *and* fewer forced statuses. The trait registry has
`CRI` (base 5%) but **no counterpart**, so there is currently no way to buy that
defense. Add `CEV` (MZ's Critical Evasion):

```text
effective critical rate = CRI − CEV, floored at 0
```

Rolled where criticals already roll, in `effects.lua`. `CEV` is **trait-driven
only, not derived from a stat** — gear and passives buy crit defense. Deriving
it from base DEF would hand VIT a third job and recreate the super-stat problem
§4 just avoided.

## 8. Data and validation

Skill rows gain (all optional):

| Field | Family | Type |
|---|---|---|
| `charges` | magic | formula string or integer (`0` = Overcast-only) |
| `overcast.mp` | magic | integer |
| `cooldown` | physical | integer turns |
| `warmup` | physical | integer turns |
| `condition` | physical | formula or prefixed condition string |
| `conditionText` | physical | display string, required with `condition` |

`mpCost` is **deleted** from `data/skills.json`, from `usability.canUseSkill`,
and from the editor form (`tools/editor/js/entity-forms.js`, whose cost row
becomes the charges/cooldown group). No compatibility shim, per the no-compat
decision — a leftover `mpCost` is a **G1 failure**, not a silently ignored field.

G1 additions:

- `charges` and `condition` formulas compile (the existing formula-compilation
  sweep already covers effect formulas — same pass),
- `condition` present without `conditionText`,
- `overcast` present without a `charges` key (Overcast needs a pool to exhaust,
  even an empty one),
- `mpCost` present anywhere,
- `cooldown` / `warmup` non-negative integers,
- `STATE_RATE` / `STATE_CATEGORY_RATE` authored with value 0 — rejected pointing
  at the immunity codes, because someone writing 0 almost certainly means
  immunity and would otherwise never learn they did not get it.

The editor gets the same fields, with the charge formula shown alongside a live
evaluated preview at a sample level — the convention the ritual scene already
uses for previewing a not-yet-summoned creature.

## 9. Presentation

- **Battle submenu**: each row shows its live gate — `⟨3/6⟩` for charges,
  `CD 2` for a cooling skill, `Rd 3` for a warming one, or the `conditionText`.
  Unusable rows are greyed with the reason in the context-help bar, per the
  §1.4 layout convention.
- **Status scene**: the skills page shows max charges and the gate in the
  description line — out of battle, current charges are what decides whether to
  go back to town.
- No new HUD element. The party HUD's MP gauge already reads the pool Overcast
  spends from.

## 10. Content pass

Every skill in `data/skills.json` is re-authored into one family. Rough intent,
to be tuned:

- Attack-like basics: no gate at all. There must always be something to do.
- Standard spells: 4–8 charges at typical SPR, Overcast 100–200 MP.
- Big spells: 1–3 charges, Overcast 300+ MP, or no Overcast at all.
- Dragon Breaths: `charges: 0`, Overcast 350–500 MP.
- Signature physicals: cooldown 2–4.
- Situational physicals: a condition, and usually no cooldown — the condition
  *is* the cost.

## 11. Migration (things that break quietly if missed)

- `data/items.json` has **two live rate-0 traits** — `STATE_RATE sleep 0` and
  `STATE_RATE blind 0`. Under §7 they degrade from "immune" to "almost never,
  and a crit lands it". They must become `STATE_IMMUNITY`, or two accessories
  are stealth-nerfed by a change nobody would connect to them.
- `data/engine.json`'s description of the `common` category names
  `STATE_CATEGORY_RATE common 0` as how a Ribbon works. Stale on landing.
- SPEC §1.12's "a rate of 0 is absolute immunity" paragraph and §1.13's
  critical-status parenthetical both change. These ship **in the same commit**
  as the code, or the docs are lying — the failure mode `AGENTS.md` names.

## 12. Gate impact (expected, not optional)

- **G2** (battle log byte-identity) goes red: the AI can no longer pick a spell
  it has no charges for, which changes both the actions taken and the RNG
  stream. A real behavioral change, so the goldens need an **owner-signed**
  regeneration — never a silent recapture.
- **G3/G5** go red on the battle scene once the submenu shows cost columns.
  Also owner-signed.
- **savetest** must cover a charge-depleted creature round-tripping, and an old
  save with no `charges` key deserializing to full.
- **unittest** covers what the goldens cannot see: charge formula evaluation and
  its floor, `charges: 0` staying 0, Overcast gated strictly to zero charges and
  refused to enemies, cooldown/warmup ticking at round end, condition prefixes
  and the formula fallback, rest reaching reserve and storage rather than just
  the active party, and a critical forcing a status through a 0 rate but not
  through `STATE_IMMUNITY`.
