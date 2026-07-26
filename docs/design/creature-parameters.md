# Creature Parameters, Growth, and Summoner MP

> **Intent, not status.** This document describes the provisional balance model
> we mean to build. For what exists now, read
> [`docs/ENGINE-STATE.md`](../ENGINE-STATE.md); for how the current engine works,
> read [`docs/SPEC.md`](../SPEC.md). Where those sources disagree with this
> document, they win.

## Parameters

Creatures use `maxHp`, `atk`, `def`, `mat`, `mdf`, `mpd`, `mxa`, and `mxp`.

- `maxHp`, `atk`, `def`, `mat`, and `mdf` receive permanent level growth.
- `mpd` is a form-defined expedition cost and never grows from levels.
- `mxa` and `mxp` are form-defined capacities and never grow from levels.
- Equipment, traits, states, permanent item gains, natural growth, and
  promotion bonuses remain distinct layers.

The Summoner does not have a traversal cost. Each dungeon step costs exactly the
combined MPD of the living manifested party:

```text
step MP cost = sum(living manifested creatures' MPD)
```

A lone MPD-1 Pixie can therefore walk almost indefinitely, but must survive with
that party. Creatures outside the manifested party cost nothing. A creature
that dies is permanently lost and no longer contributes MPD.

Ordinary battle rounds do not drain MPD. Creature spells and other invoked
effects spend Summoner MP directly. After five completed rounds, prolonged
battle may create visible, escalating **Strain** based on combined party MPD.
Exact Strain multipliers remain to be tested.

## Summoner MP progression

The provisional opening maximum is 3000 MP and the hard cap is 9999. Max MP
does not require conventional Summoner levels. Major events provide most
capacity increases; rare permanent-use items may provide smaller increases.

Max MP and desired party MPD should rise together:

| Campaign stage | Max MP | Typical party MPD | Pure walking range |
|---|---:|---:|---:|
| Opening | 3000 | 4-7 | 429-750 |
| Early-mid | 4500 | 7-11 | 409-643 |
| Midgame | 6000 | 10-15 | 400-600 |
| Late | 7800 | 13-19 | 411-600 |
| Endgame | 9999 | 16-24 | 417-625 |

Retaining economical early forms converts increased capacity into exceptional
range. Promoting converts it into greater party power.

## Damage

The provisional core damage curve is:

```text
base damage = potency * power^2 / (power + defense)
```

- Physical actions normally use ATK against DEF.
- Magical actions normally use MAT against MDF.
- An exceptional skill may explicitly author another pairing.
- Elemental affinity, traits, states, guarding, and final rounding apply after
  the relative-stat calculation.
- The final minimum is 1 damage. There is no proportional damage floor.

Useful properties:

| Defense relationship | Damage before potency |
|---|---:|
| DEF = 0 | 100% of Power |
| DEF = Power | 50% of Power |
| DEF = 2 x Power | 33% of Power |
| DEF = 3 x Power | 25% of Power |

This permits genuine scratch damage. Pixie attacking Golem physically is
supposed to be an almost useless action.

Provisional potency language:

| Potency | Intended use |
|---:|---|
| 0.35-0.60 | One hit of a multi-hit action |
| 0.80 | Weak attack carrying useful utility |
| 1.00 | Basic attack |
| 1.15-1.30 | Standard skill |
| 1.40-1.70 | Strong costly skill |
| 1.80-2.25 | Finisher or heavily conditional attack |

Multi-hit potency is applied to the final relative-stat result, so repeated hits
do not accidentally bypass or multiply flat defense.

Elemental identity compounds. Repeated innate elements create multiple
attacker-target pairings, and a deeply aligned skill can compound with that
identity. Triple alignment is therefore a matchup-defining strength and
liability, not a simple 1.15 multiplier.

## Healing

Healing does not use the damage formula. The provisional standard form is:

```text
healing = caster MAT * potency + target MaxHP * percentage
```

A starting standard heal might use `MAT * 0.6 + target MaxHP * 0.15`. This
restores a large fraction of fragile creatures, a useful fraction of ordinary
creatures, and a smaller fraction of extreme HP tanks.

Provisional healing bands:

```text
standard single: MAT * 0.60 + target MaxHP * 0.15
strong single:   MAT * 0.90 + target MaxHP * 0.22
standard party:  MAT * 0.35 + target MaxHP * 0.08, per target
regeneration:    5-8% target MaxHP per completed round
```

## Skill potency and MP

| Skill class | Potency | Opening MP | Endgame MP |
|---|---:|---:|---:|
| Utility attack | 0.75-0.90 | 10-25 | 30-70 |
| Standard attack spell | 1.15-1.30 | 35-60 | 90-150 |
| Strong attack spell | 1.40-1.70 | 65-100 | 160-260 |
| Finisher | 1.80-2.25 | 130-220 | 300-550 |
| Minor support | authored | 25-50 | 70-140 |
| Major party support | authored | 80-150 | 200-400 |

Costs belong to individual skills. An early skill does not automatically become
more expensive when Max MP rises; later forms learn stronger, more expensive
actions. A coordinated opening burst and endgame burst should each consume
roughly comparable percentages of the relevant Max MP scale.

## Status infliction

Status chance is deliberately not derived from MAT, MDF, ATK, DEF, level, or
another parameter. It follows an RPG Maker MZ-style trait model with no Luck
adjustment:

```text
final chance =
skill infliction chance
* attacker status-success rate
* target state rate
```

- Ordinary results are clamped from 0% to 100%.
- A target state rate of zero is explicit immunity.
- Guaranteed non-damaging effects are authored explicitly.
- Different states retain separate target rates and immunities.

### Critical status rule

An HP-damaging action that critically hits guarantees its attached statuses
unless the target is explicitly immune. This Brigandine-inspired rule bypasses
ordinary infliction chance and partial resistance, but never immunity.

```text
normal hit:   skill chance * success rate * state rate
critical hit: 100%, unless state rate = 0
```

For a multi-hit action, each damaging hit rolls its own critical. A status
attached once after the action is guaranteed if at least one relevant hit
critically lands. Non-damaging status actions do not naturally critical.

## Critical hits

The provisional baseline critical chance is 5% and provisional critical damage
is 1.5 times ordinary final damage. Permanent death makes larger default
critical multipliers excessively volatile.

```text
relative damage
-> potency
-> element
-> ordinary damage modifiers
-> critical x1.5
-> guarding and final damage-rate protection
-> rounding
```

Critical traits are therefore valuable both for damage and for attached status
reliability.

## Defend

Defend should not merely double DEF: that fails to protect against magic and
has inconsistent value under the relative damage curve. It should apply a
temporary reusable final-damage rate:

```text
direct HP damage taken * 0.5
```

The protection applies to physical, magical, elemental, and drain damage. It
does not automatically reduce poison ticks or other authored indirect damage.
A general `DAMAGE_RATE` trait can also serve barriers, equipment, vulnerability
states, and creature passives.

## Battle Strain

Ordinary rounds do not drain MPD. Prolonged battles pay visible Strain at the
end of the round:

| Completed round | Strain cost |
|---:|---:|
| 1-5 | 0 |
| 6-9 | combined party MPD * 4 |
| 10-14 | combined party MPD * 8 |
| 15+ | combined party MPD * 16 |

The interface must announce escalation and show the upcoming cost before the
player commits actions. Strain is exceptional pressure against indefinite
combat, not the ordinary price of taking a tactical turn.

## Benchmark profiles

These are balancing rulers, not mandatory actor templates.

### Pixie

| Level | HP | ATK | DEF | MAT | MDF |
|---:|---:|---:|---:|---:|---:|
| 1 | 30 | 10 | 12 | 18 | 16 |
| 10 | 70 | 14 | 25 | 45 | 38 |
| 20 | 125 | 20 | 38 | 82 | 62 |
| 30 | 185 | 28 | 55 | 125 | 90 |

### Golem

| Level | HP | ATK | DEF | MAT | MDF |
|---:|---:|---:|---:|---:|---:|
| 1 | 70 | 16 | 25 | 5 | 8 |
| 10 | 155 | 35 | 55 | 10 | 15 |
| 20 | 285 | 58 | 92 | 17 | 27 |
| 30 | 465 | 85 | 140 | 25 | 40 |

### Physical attacker

| Level | HP | ATK | DEF | MAT | MDF |
|---:|---:|---:|---:|---:|---:|
| 1 | 48 | 18 | 14 | 8 | 10 |
| 10 | 110 | 42 | 32 | 18 | 24 |
| 20 | 190 | 75 | 55 | 30 | 43 |
| 30 | 285 | 115 | 80 | 45 | 65 |

### Caster

| Level | HP | ATK | DEF | MAT | MDF |
|---:|---:|---:|---:|---:|---:|
| 1 | 42 | 10 | 11 | 18 | 15 |
| 10 | 95 | 20 | 25 | 43 | 35 |
| 20 | 165 | 32 | 43 | 78 | 60 |
| 30 | 250 | 46 | 62 | 120 | 88 |

### Durable hybrid

| Level | HP | ATK | DEF | MAT | MDF |
|---:|---:|---:|---:|---:|---:|
| 1 | 56 | 15 | 17 | 14 | 16 |
| 10 | 125 | 35 | 38 | 32 | 37 |
| 20 | 220 | 65 | 68 | 58 | 65 |
| 30 | 350 | 100 | 105 | 90 | 98 |

An ordinary neutral matchup should take about five basic hits throughout the
level curve. A durable hybrid takes about six. A conventional physical attacker
takes about nine or ten neutral hits to defeat Golem, while a conventional
caster takes about five or six magical hits.

## Seeded, budget-first growth

Growth is additive, permanent, seeded per creature instance, and intentionally
uneven. It is not recalculated from species and current level.

Each form authors budgets for three bands:

- Levels 2-10: nine level-ups.
- Levels 11-20: ten level-ups.
- Levels 21-30: ten level-ups.

The instance growth seed:

1. Applies narrow variation to the authored band budgets.
2. Keeps total growth within the species' permitted range.
3. Divides each budget into uneven level packets.
4. Shuffles those packets deterministically.
5. Guarantees at least +1 HP at every level.
6. Gives every growing stat at least scant lifetime growth.
7. Favors one spotlight stat and sometimes a support stat per level.

Typical final-stat variation should remain near plus or minus 5%. A creature may
be notably lucky in one statistic, but not receive a materially larger total
growth budget.

HP packets should not be smooth. A Pixie with a +60 HP budget for levels 21-30
might receive:

```text
+3, +4, +2, +3, +16, +4, +3, +17, +4, +4
```

Every level raises HP, but two levels are memorable growth spurts. Other stat
spotlights keep the low-HP levels meaningful.

The seed is assigned when the instance is created and saved. Directly generated
high-level creatures replay their seeded history. Reloading cannot reroll a
level-up.

## Promotion

Promotion never recalculates statistics. It:

- preserves all accumulated lower-form growth;
- grants a fixed, authored one-time bonus where appropriate;
- replaces only future unused growth budgets;
- changes form-defined MPD, capacities, affinities, skills, and passives.

An item-gated promotion normally has no additional level requirement. The
promotion item, prerequisite form, and authored availability of that item are
the progression gate. Requiring both an item and a level is reserved for an
explicit exceptional design, not used as a default.

Fixed bonuses reward early promotion without scaling upward for players who
delay. Delaying preserves cheaper MPD for longer but permanently accumulates
more lower-form growth.

Illustrative level-30 outcomes:

| Choice | HP | ATK | MPD |
|---|---:|---:|---:|
| Never promote | 285 | 102 | 2 |
| Promote at level 20 | 317 | 115 | 3 |
| Promote at level 10 | 337 | 121 | 3 |

Provisional ordinary level-10 promotion bonus:

- HP +8 to +18.
- Primary stat +3 to +6.
- One or two supporting stats +1 to +3.
- MPD usually +1, occasionally unchanged or +2.

Provisional later item-locked promotion bonus:

- HP +15 to +35.
- Primary stat +6 to +10.
- Supporting stats +2 to +6.
- MPD usually +1 to +3.

These are guidelines. A promotion may derive most of its value from a skill,
passive, affinity, capacity, or crafting specialty. Pandora, for example,
belongs near the bottom of the later raw-stat band and gains its identity from
item-effect interactions.

Promotion branches author different future budgets. A Unicorn entering
Sleipnir, Nightmare, or Firemane at the same level begins diverging immediately.
Kirin's later value may come more from healing, cleansing, and party regeneration
than from a large raw-stat advantage.

## Still to test

- Full encounter pacing with deep elemental alignment.
- Armor penetration.
- Skill and healing bands against authored kits.
- MP recovery values across the 3000-9999 Max MP curve.
- Actor-family growth budgets, promotion bonuses, and MPD trajectories.
