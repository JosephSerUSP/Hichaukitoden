# Combat State Resources: Overheal, Temporary Max HP and Barriers

*Design intent, 07.08.2026. Not a status document — see `docs/ENGINE-STATE.md`
for what exists and `docs/SPEC.md` for implemented engine rules. Elemental
ownership and spell doctrine live in `docs/design/elemental-combat-grammar.md`.*

## 1. Purpose

Second Rite needs a small set of **reusable combat-state resources** that can
support skills, passives, equipment and enemies without becoming a pile of
one-off mechanics.

This document defines the intended semantic space around:

- **Overheal** — current HP temporarily exceeding Max HP;
- **temporary Max-HP changes** — changing the body's actual capacity;
- **barriers / wards** — stackable defensive resources that respond to matching
  incoming events;
- **refreshing barrier sources** — effects that replenish barriers over time.

These are engine-level concepts. Blue, Green and White may be their most natural
spell homes, but the implementation must not hard-code elemental identities into
the resource system.

The governing principle is:

> **Small semantic primitives, broad compositional space, narrow encounter-facing complexity.**

## 2. Overheal is not temporary Max HP

Overheal and temporary Max HP may both produce a number above the ordinary HP
ceiling, but they represent different things and should remain mechanically
distinct.

Example, starting from `80 / 100 HP`:

### Temporary Max HP

```text
80 / 100 -> 105 / 125
```

The creature's actual capacity increased. The additional 25 Max HP is real
space that ordinary healing can fill.

### Overheal

```text
80 / 100 -> 125 / 100
```

Max HP remains 100. The creature is temporarily carrying vitality beyond its
ordinary capacity.

A useful elemental shorthand is:

> **Green makes the vessel larger. Red fills the vessel until it spills over.**

## 3. Overheal semantics

### 3.1 Explicit permission

Ordinary healing still clamps at Max HP.

Current HP may exceed Max HP **only when an effect explicitly permits
Overheal**. Overheal is therefore a capability of the healing effect / state,
not a global change that makes every potion and Regen tick overflow by default.

### 3.2 Overheal is real current HP

The preferred model is that Overheal is actual HP above Max HP rather than a
separate shield-health pool.

```text
current HP = 125
Max HP     = 100
```

Damage removes that HP normally before reaching 100.

This permits future mechanics to care meaningfully about:

- being at or above full HP;
- being above 100% HP;
- preserving full-HP attack conditions through small hits;
- passives that activate specifically while Overhealed.

The exact default Overheal cap remains a balance decision. A system-level cap
such as 125% or 150% Max HP is plausible, but this document intentionally does
not choose a final number.

### 3.3 Overheal lifetime

Overheal does **not** need one universal expiry rule. Its lifetime is design
space.

Possible effects may:

- persist until damaged away;
- decay at round end;
- disappear with a parent state;
- be capped or refreshed by a passive.

Do not silently make all Overheal temporary-by-duration merely because one Red
spell is.

### 3.4 Interaction with Max-HP changes

If Max HP rises while the creature is Overhealed, the Overheal is naturally
reinterpreted against the new capacity.

Example:

```text
130 / 100
+25 Max HP
=> 130 / 125
```

Most of the previous excess vitality is now ordinary HP capacity; only 5 HP is
still above Max HP.

This is an important Red/Green interaction and should fall out of the numeric
model rather than require a special synergy rule.

## 4. Temporary Max-HP semantics

Temporary Max HP is a Green-style growth primitive but must remain generic.

### 4.1 Increasing Max HP grants corresponding current HP

Preferred rule:

```text
80 / 100
+25 Max HP
=> 105 / 125
```

Increasing the body's capacity also gives the creature the newly created life.
Otherwise a "growth" spell would paradoxically lower the creature's HP
percentage and require a second heal before its new body became useful.

### 4.2 Expiry clamps; it does not deal damage

When a temporary Max-HP increase expires:

```text
117 / 125 -> 100 / 100
72 / 125  -> 72 / 100
```

The reduction in current HP caused purely by losing excess capacity is **not
combat damage**.

Expiry should therefore not:

- trigger damage reactions;
- trigger "on hit" effects;
- create damage popups unless deliberately presented as a distinct state-end
  message;
- kill a creature merely because the temporary capacity disappeared.

The result is clamped to the new Max HP.

### 4.3 Why this matters

Temporary Max HP can act simultaneously as:

- an immediate small heal;
- a temporary buffer;
- greater capacity for later White / Blue healing;
- a larger base for percentage regeneration where the relevant effect uses
  current Max HP;
- a way to alter HP-threshold play without pretending to be a conventional DEF
  buff.

## 5. Barrier is a family, not one effect

A **Barrier** is a defensive resource with a matching rule and one or more
consumable stacks. The familiar "negate one magic hit" version is only one
member of the family.

Useful independent axes are:

| Axis | Examples |
|---|---|
| **Match kind** | magical damage, physical damage, hostile status, critical, drain, a particular element |
| **Stacks** | 1, 2, 5, etc. |
| **Strength** | 100% negation, 50% reduction, 30% reduction |
| **Expiry** | consumed only, timed, timed + consumed, battle-long |
| **Refresh** | never, round start, battle start, conditional |
| **Maximum stacks** | 1, 3, 5, etc. |
| **Consumption rule** | matching successful instance, matching attempt, whole action, other explicit variant |

The engine should support the family without requiring every authored barrier to
use every axis.

## 6. Stacks and strength are different

A barrier's **stack count** answers how many matching instances remain.
Its **strength** answers how much one stack prevents.

Examples:

### Sharp negation

```text
Magic Barrier x1
reduction: 100%
```

Negates the next magical damage instance, then disappears.

### Layered mitigation

```text
Magic Barrier x5
reduction: 40%
```

The next five magical damage instances are each reduced by 40%; one stack is
consumed per matching instance.

This distinction creates useful attack-shape interactions:

- one huge Flare may be completely negated by a sharp barrier;
- Fire Lance may spend the barrier on hit one and damage with hit two;
- many Thunderstorm bolts may rapidly consume a layered barrier if they happen
  to select that target.

The system should not need authored "anti-barrier" bonuses for those
interactions to occur.

## 7. Damage instances, not cosmetic hit counts

Barrier design makes hit count meaningful, so multi-hit actions must resolve
actual independent damage instances.

**Fire Lance** is the canonical simple example:

1. first Fire hit resolves;
2. if a one-stack Magic Barrier matches it, the barrier is consumed and that
   hit is prevented / reduced according to its strength;
3. second Fire hit resolves against the now-changed state.

**Thunderstorm** is the random example:

- each bolt is its own strike;
- each independently selects a random enemy target;
- targets may repeat;
- a barrier may be untouched, merely broken, or broken and followed by further
  damage depending on the random distribution.

Do not turn every spell into multi-hit merely because barriers exist. Hit count
must remain meaningful enough that Fire Lance being two-hit is an identity and
Thunderstorm being many random hits is a risk profile.

## 8. Physical, magical and status families

The elemental-combat doctrine suggests these common homes:

- **Blue:** Magic Barrier;
- **Green:** Physical Barrier;
- **White:** Status Ward.

These are semantic families, not requirements that all three use identical
numbers or expiry rules.

A possible family set might include:

```text
Magic Barrier x1
Negates the next magical damage instance.
```

```text
Physical Barrier x5
Reduces the next five physical damage instances by 30%.
```

```text
Status Ward x2
Negates the next two hostile status applications that would otherwise succeed.
```

The examples illustrate design space; exact strengths and stack counts are not
balance decisions in this document.

## 9. Status Ward should consume on a successful application

For the ordinary Status Ward family, preferred semantics are:

1. the hostile condition resolves its normal success logic;
2. if it would succeed, the Ward intercepts it;
3. one Ward stack is consumed;
4. the condition is not applied.

A naturally failed Poison attempt should therefore **not** consume the Ward.

This avoids invisible-feeling losses where a protection disappears against an
effect that would not have landed anyway.

Rare signature effects may later define different consumption rules, but the
ordinary Ward should remain easy to reason about.

## 10. Refreshing barriers

A spell that "protects for three rounds" does not need to mean one barrier with
a three-round duration.

A more interesting pattern is a **barrier-producing effect** that repeatedly
replenishes the consumable resource.

Example:

> Gain one Magic Barrier now. For the next three rounds, refresh Magic Barrier
> to at least one stack at round start.

Battle shape:

```text
cast          -> Barrier present
enemy hit     -> Barrier consumed
same round    -> further matching hits get through
next round    -> Barrier reforms
```

This means the protection is strong against one major magical event per round
but can be overwhelmed by concentrated or multi-hit pressure.

### 10.1 Generator and resource should be conceptually separate

The consumable barrier and the effect that refreshes it should be distinct
state concepts.

For example:

```text
Magic Barrier        -- x1 consumable resource
Arcane Renewal       -- 3-round source that refreshes Magic Barrier
```

If the barrier is broken, the renewal effect remains and can recreate it next
round.

If the barrier survives, a `refresh to at least 1` effect should not
accumulate a second stack unless the spell explicitly says it can.

Other barrier-producing effects may instead:

- add `+1` stack per round;
- refresh to a maximum of 2;
- restore all missing stacks;
- only refresh after a condition.

That variation is useful design space and belongs in authored data rather than
separate hard-coded barrier systems.

## 11. Passives and battle-start state

Barriers are particularly valuable passive design because one stack remains
qualitatively meaningful across level ranges.

Examples:

- **Arcane Shell:** begin battle with Magic Barrier x1;
- **Carapace:** begin battle with Physical Barrier x2;
- **Sacred Veil:** begin battle with Status Ward x1.

Passives may also modify barrier behavior rather than merely grant stacks:

- react when a barrier breaks;
- change refresh amount;
- restore a stack under a condition;
- add another benefit when a Ward successfully intercepts a status.

These should use the same generic barrier vocabulary.

## 12. What not to make the default

### 12.1 Do not default to a second HP bar

A barrier with its own absorbable "barrier HP" is possible future design space,
but it should not be the initial generic model. Instance-based stacks are more
legible and scale without creating another health pool.

### 12.2 Avoid fixed absorption as the main scalable form

"Absorb 20 damage" is easy to understand but risks becoming dominant early and
irrelevant later unless another scaling rule is introduced. Percentage
reduction and full negation are more naturally durable across the game's stat
range.

Fixed absorption can still exist for signatures where that exact behavior is
valuable.

### 12.3 Do not expose every axis in every encounter

The engine may support:

- multiple kinds;
- different strengths;
- refresh;
- expiry;
- stack limits;
- special consumption rules.

An ordinary creature should usually present **one simple barrier concept at a
time**. Complexity should accumulate across the game's encounter language, not
all inside one enemy tooltip.

## 13. HUD representation

The low-resolution battle HUD should communicate **recognition**, not exact
mechanical prose.

Preferred direction:

- one distinct icon per major barrier / ward family;
- a single stack has no extra counter;
- small stack counts may use tiny **pips** around / beside the icon;
- above a small display threshold, replace individual pips with a distinct
  **"many / full" marker** rather than attempting to show a difficult tiny
  decimal number;
- the exact stack count always remains available through battler inspection.

The exact pip ceiling and "many" glyph are presentation decisions to test at
the real internal resolution.

This is preferable to relying on a tiny decimal overlay: a readable `3` already
requires roughly five vertical pixels, which is expensive relative to the
status icon itself.

### 13.1 Never overload the same small number with duration

If a visible number / pip language means **quantity**, it should not sometimes
mean "turns remaining."

A renewing barrier is therefore better represented as:

```text
[Magic Barrier icon + stack pips] [Renewal-state icon]
```

rather than trying to encode both stack count and remaining renewal duration in
one tiny symbol.

Most ordinary states need not expose duration numerically at all.

## 14. Inspector representation

The exact semantics belong in the battler inspector, not the compact HUD.

Examples:

```text
Magic Barrier x7
Reduces the next 7 magical damage instances by 40%.
```

```text
Status Ward x2
Negates the next 2 hostile status applications that would otherwise succeed.
```

```text
Arcane Renewal
Refreshes Magic Barrier to 1 stack at the start of each round.
```

Where practical, this text should be generated from the semantic state / barrier
configuration rather than maintained as a second hand-written mechanical truth
that can drift from the actual effect.

See `docs/design/battler-inspection.md`.

## 15. Authoring principles

1. **Barrier is one vocabulary, not one behavior.** One-stack full negation is
   an example, not the definition.
2. **Stacks and strength are separate.** `x5` must not secretly mean either
   "500 shield HP" or "five times stronger."
3. **Refresh is production, not stored duration.** The resource can disappear
   while the producer remains active.
4. **Hit count is a combat property.** Cosmetic multi-hit presentation must not
   silently acquire mechanical meaning and vice versa.
5. **UI approximation is allowed.** The HUD may say "many" while the inspector
   reports `x7` exactly.
6. **Do not hard-code colors into the primitive.** Blue / Green / White are
   spell-doctrine owners, not engine branches.
7. **Prefer interactions over exception text.** Fire Lance should beat a
   one-stack Magic Barrier because it has two hits, not because it carries an
   `antiBarrier = true` flag.
