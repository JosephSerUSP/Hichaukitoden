# Actor Roster Expansion - Working Direction

> **Intent, not status.** This document records the agreed direction for a
> future actor and item-content expansion. For what exists right now, read the
> generated [`docs/ENGINE-STATE.md`](../ENGINE-STATE.md) (gated by G4); for how
> the engine works, read [`docs/SPEC.md`](../SPEC.md). Where this document and
> either source disagree, they win.

Status: roster direction approved for further authoring. Names explicitly
marked provisional, exact seeded growth packets, skill formulas, item IDs,
encounter placement, and implementation order remain open. Parameter tables in
this document are approved working centers, not implemented data.

## Purpose

The expanded roster must support three connected games:

- battle roles and party composition;
- exploration pressure, especially shared MP and retreat decisions;
- Item Creation identities, inputs, outputs, and promotion goals.

A creature is not justified merely by having a new sprite or elemental color.
It should create a party-building decision, an exploration decision, an Item
Creation identity, or a distinctive progression story. Promotion forms may
share a chassis: elements, subtle parameter changes, one passive, one skill,
and a different discipline can provide enough distinction.

The roster draws structurally from *Brigandine*, *Shin Megami Tensei*, *Final
Fantasy*, *Star Ocean*, RPG Maker, mythology, folklore, and unusual early
fantasy concept art. References are a shared vocabulary, not a mandate to copy
another game's full unit kits.

## Roster overview

| Family | Primary contribution | Progression |
|---|---|---|
| Undine | Blue damage caster | Undine -> Proteus |
| Cocoon | Status control | Cocoon -> Notiluca |
| Goblin | Scouting, escape, discovery | Gbl. Thief -> Gbl. Prince |
| Homunculus | Hidden parameter-driven possibility | Homunculus -> any eligible species |
| Mandrake | Cooking and botanical sustain | Mandrake -> Alraune |
| Cerberus | Early power at high expedition cost | One stage |
| Diablos | Difficult challenge recruit and MP recovery | One stage |
| Dragon | Player-chosen elemental generalist | Egg -> Dragon -> five branches -> keyed final forms |
| Giant | Heavy offensive/defensive fork | Giant -> Hill Gigas / Atlas -> keyed final forms |
| Mimic | Consumable and found-object specialist | Mimic -> keyed Pandora |
| Unicorn | Healing, cleansing, and elemental branches | Four-form branching family |
| Golem | Extreme physical HP/DEF wall | Golem -> Talos (name provisional) |
| Gargoyle | Magical provoking tank | Gargoyle -> Grotesque (name provisional) |
| Kappa | Exploration specialist and reversible curse form | One native stage |
| Moa | Strange pink exploration mount | One stage for now |

This table lists planned content, not content currently present in
`data/actors.json`.

## Agreed creature families

### Undine -> Proteus

Undine and Proteus are androgynous water casters.

- **Undine** is a straightforward Blue ice-damage spellcaster.
- **Proteus** becomes a powerful support unit while retaining spell damage and
  gaining credible physical front-line capability.
- The progression should feel like broadening command of water rather than
  abandoning the original caster identity.
- Their Item Creation disciplines still need to be selected.

### Cocoon -> Notiluca

Cocoon and Notiluca are actual giant moths.

- **Cocoon** is vulnerable and control-oriented, using dust, sleep, or related
  conditions rather than direct power.
- **Notiluca** is defined by extraordinary mesmerizing light. Its control
  becomes broader and more reliable, with room for support illumination.
- The name is intentionally `Notiluca`.

### Gbl. Thief -> Gbl. Prince

This family owns scouting and opportunism.

- **Gbl. Thief** improves escape, initiative, trap handling, or discovery.
- **Gbl. Prince** elevates the same identity through wealth, command, and
  magical or economic utility rather than becoming a generic attacker.
- Its drops should reinforce the polyvalent found-object economy.

### Mandrake -> Alraune

This is the primary botanical Cooking family.

- **Mandrake** turns roots, food, and risky restorative objects into a coherent
  creature identity.
- **Alraune** becomes a stronger party-sustain and botanical support creature.

### Cerberus

Cerberus is an early recruit inspired by SMT's early access to unusually strong
allies.

- It begins with excellent parameters and immediate combat value.
- It has deliberately poor growth.
- It consumes a meaningful amount of shared MP in the dungeon.
- Its purpose is to offer safety now at the cost of expedition longevity.

Cerberus should not require a new engine mechanic; existing base parameters,
growth multiplier, and `mpd` should express the tradeoff.

### Diablos and the Forbidden Lamp

Diablos is a one-stage, exceptionally powerful Black / Black / Red creature.

- It is not part of the existing Demon -> Incubus line.
- The **Forbidden Lamp** calls a common event from field item use.
- The common event warns the player, begins a difficult fixed Diablos battle,
  and recruits Diablos after victory.
- The challenge should remain available after fleeing or losing until it is
  resolved.

Diablos has a unique **Reaper** passive: when Diablos lands the killing blow on
an enemy, it restores a flat amount of MP to the Summoner. The exact amount is
not decided. Reaper must use a reusable kill-event trait rather than bespoke
Diablos logic.

## Special transformation systems

### Egg provenance and automatic hatching

Egg is a creature instance whose result is decided by how it joined the party.

- Every Egg automatically hatches at level 10.
- Hatching does not appear in the player-controlled promotion menu.
- An Egg instance stores a provenance or hatch profile in save data.
- The hatch profile deterministically selects the result.
- The hatch occurs at a safe transition, provisionally after battle or another
  suitable event boundary.
- Evocative status/history text may hint at provenance without stating an
  internal profile ID.

Initial authored outcomes:

| Provenance | Outcome | Notes |
|---|---|---|
| Mystic Egg item | Phoenix | Fixed |
| Dungeon table | Larva | Common or regional |
| Dungeon table | Angel | Reference to *Angel's Egg* |
| Rare dungeon table or named egg | Dragon | Must remain uncommon |
| Dungeon table | Moa | Strange pink mount bird |

Dungeon provenance uses small regional authored tables, not one global random
pool. Additional outcomes may be added when regions are authored.

### Homunculus metamorphosis

Homunculus may become any eligible current or future species.

- It always displays what it currently appears destined to become.
- The game does not explain why that destination was selected.
- Equipment, temporary states, and current HP must not affect the result.
- Persistent intrinsic development may affect it: level, permanent parameter
  gains, innate growth, and possibly permanently learned skills/passives.
- The destination updates deterministically when relevant development changes.
- Summoner, Egg, another unresolved Homunculus, and other nonsensical records
  are excluded through an authored eligibility rule.

Resolution has two layers:

1. Authored rare conditions run first. Exact secrets such as intrinsic
   permanent Max HP equal to `666` may yield exceptionally powerful forms.
2. If no secret matches, a deterministic classifier selects the eligible
   species closest to the Homunculus's permanent parameter profile.

Tie-breaking must be stable. Random metamorphosis would make the visible
preview unreliable.

### Reversible Kappa transformation

Kappa is both a native recruit and a recoverable curse form.

- A trap, item, enemy, shrine, or common event may transform one eligible
  creature into Kappa.
- The transformed creature retains its name, level, EXP, history, permanent
  parameter gains, equipment, and original species.
- It temporarily uses Kappa's actor data: appearance, parameters, elements,
  skills, passives, discipline, and MP drain.
- After gaining three levels, it automatically returns to the exact species it
  had before transformation.
- Naturally recruited Kappas have no stored former species and never revert.
- A cursed Kappa cannot use ordinary promotion while awaiting restoration.
- Egg and unresolved Homunculus are provisionally immune to the curse.

The reversion condition must be visible enough to avoid a dead-save feeling,
but the interface need not expose internal implementation fields.

Kappa is intentionally better outside battle than inside it:

- very low MP drain;
- strong exploration utility;
- high HP and defenses;
- poor accuracy, speed, and damage;
- limited combat utility beyond being a durable sitting duck;
- a modest water action;
- Cooking discipline.

### Individual Favorite Food

Favorite Food belongs to the individual creature, not only to its species.

- Each actor species authors a pool of eligible exact food item IDs.
- When a new creature instance is created, one item is selected from that pool
  and stored on the battler as its one Favorite Food.
- Different instances of the same species may therefore have different
  favorites.
- The favorite is initially displayed as `?????`.
- Giving the creature that exact food discovers it permanently and displays
  the item's name thereafter.
- The selected item and discovery flag persist through save/load, ordinary
  promotion, Homunculus metamorphosis, and temporary Kappa transformation.
- A Favorite Food is part of the creature's personal history; changing species
  never rerolls it.
- Egg provenance may select from the future hatch species' pool when the Egg
  instance is created, even though the result and favorite remain hidden.
- Naturally recruited, summoned, and otherwise generated creatures all roll
  once when their persistent instance is created.

Favorite Food selection must not strand early creatures with inaccessible
late-game food. Species pools should contain foods reasonably obtainable around
the creature's recruitment window, unless an intentionally unusual creature
explicitly breaks that rule.

Food tags still matter, but they describe what kind of Savor bonus the item
provides; they do not determine whether the item is the creature's favorite.
Any tagged edible item may trigger Favorite Food, including a battle-usable
snack or draught. Field-only party meals are simply an efficient way to feed
several creatures.

When the exact favorite is given:

- the item's ordinary effect resolves normally;
- if the creature is eligible, it gains the food's Savor bonus for a
  provisional three completed battles;
- Savor cannot be refreshed while active;
- the favorite is revealed even if future balancing changes the bonus;
- permanent parameter growth is not the standard Savor reward.

Giving a creature a non-favorite food may produce a short, non-mechanical
reaction line. These lines add personality but do not change the item's normal
effect, reveal candidates, narrow the hidden pool, or impose dislike penalties.
The exact favorite receives a distinct discovery reaction when its name
replaces `?????`.

Meal discipline, use occasion, targeting, food tags, and Favorite Food identity
are independent authoring axes. Cooking may produce battle-usable draughts and
non-meal items, while a meal may belong to Cooking, Alchemy, another
discipline, or several disciplines.

## Branching promotion families

### Dragon family

Dragon is an uncommon Egg outcome, not a normal base recruit. At its first
promotion, the player simply chooses one of all five branches. The branches
remain relatively similar: elemental identity, subtle parameter differences,
one passive, one skill, and an Item Creation specialty provide sufficient
distinction.

```text
Dragon
  -> Red Dragon   -> Salamander
  -> Blue Dragon  -> Leviathan
  -> Green Dragon -> Fafnir
  -> White Dragon -> Bahamut
  -> Black Dragon -> Nidhogg
```

- All five first branches are player-chosen.
- Dragon branches at level 10. Each final form requires only its
  branch-specific promotion item once the corresponding elemental Dragon
  exists; the final promotion has no additional level requirement.
- Final forms use familiar mythic names intentionally, including the strong
  Final Fantasy reading of Bahamut.
- Each final promotion consumes its own single-purpose key item.

Working branch distinctions:

| Branch | Subtle emphasis | Item Creation specialty |
|---|---|---|
| Red Dragon | ATK and pressure | Blacksmithing |
| Blue Dragon | MAT/MDF and support | Alchemy |
| Green Dragon | HP and regeneration | Cooking |
| White Dragon | wards and recovery | Tinkering |
| Black Dragon | drain or status pressure | Alchemy |

These allocations are not final balancing commitments.

### Giant family

```text
Giant
  -> Hill Gigas -> Surtr
  -> Atlas      -> Hyperion
```

- **Hill Gigas** is Red / Black, more magical, and more offensive.
- **Atlas** is White / Green, more physical, and more defensive.
- The two branches may otherwise retain a shared heavy-creature chassis.
- Surtr and Hyperion are branch-specific, item-locked promotions with no
  additional level requirement once Hill Gigas or Atlas exists.

### Promotion key policy

Third-stage Dragon/Giant keys and other special promotion items are deliberately
single-purpose.

As a general rule, an item-gated promotion is not also level-gated. Acquiring
and choosing to consume the promotion item is the requirement. Item placement,
rarity, price, and the need to possess the preceding form provide progression
control. Exceptions must be explicit rather than assumed.

- They cannot be equipped.
- They cannot be used as ordinary items.
- They cannot be selected as Item Creation ingredients.
- They cannot appear as Item Creation outputs.
- They may be sold for a large amount of gold.
- Promotion consumes the corresponding item.

Current `craftable: false` semantics only exclude an item from output pools.
The design therefore requires a separate registry-backed ingredient exclusion
such as `meta.craftIngredient: false`, with editor support and validation.

Exact promotion-item names are not locked. Naming direction is concise,
indirect JRPG object names without constructions such as "The X." Working
examples include Cinder Ruby, Abyssal Pearl, Verdigris Coin, Celestial Fossil,
Blackroot, Molten Manacle, and Adamant Weight; any or all may change.

## Other approved families

### Pixie -> High Pixie -> Titania

Pixie retains her level-10 promotion into High Pixie. High Pixie may promote at
level 20 into **Titania**.

```text
Pixie -> High Pixie -> Titania
                       (level 20, no promotion item)
```

Titania completes the reward arc for protecting and raising the roster's
frailest creature. She is a deliberate exception to the general item-locked
third-stage rule. Successfully raising the Pixie line to level 20 is the entire
promotion requirement; adding an item gate would dilute that accomplishment.

The provisional MPD trajectory is:

```text
Pixie 1 -> High Pixie 2 -> Titania 4
```

Titania is substantially stronger without becoming physically durable. Her
future growth remains centered on MAT and MDF, with improved HP and enough DEF
to be less precarious than her earlier forms. Her defining reward includes a
fairy-queen support identity rather than raw damage alone, provisionally through
an aura that strengthens or protects cheaper creatures the player has chosen to
raise.

Provisional fixed promotion bonus:

```text
HP +18
MAT +9
MDF +7
DEF +3
MPD 2 -> 4
```

### Mimic -> Pandora

Mimic and Pandora are item-use specialists rather than Item Creation
specialists.

- Mimic is durable, clumsy, and already gains unusual value from consumables
  and found objects.
- Pandora requires a dedicated promotion item.
- Pandora may promote from Mimic at level 1; the item is the entire gate.
- Pandora is reasonably stronger, but not a massive tier jump.
- Pandora has a stronger item-effect bonus and broader tactical flexibility.
- It becomes slightly frailer than Mimic, redistributing power away from raw
  HP/DEF.

The family needs an `ITEM_EFFECT_RATE` trait equivalent in purpose to RPG Maker
MZ's Pharmacology.

### Unicorn family

```text
Unicorn
  -> Sleipnir -> Kirin       (later promotion item)
  -> Nightmare
  -> Firemane                (earlier/easier promotion item)
```

- Unicorn, Sleipnir, Firemane, and Kirin retain basic healing.
- Nightmare deliberately gives up healing for Black status pressure and
  offense.
- Sleipnir emphasizes speed, initiative, and expedition efficiency.
- Kirin becomes a true healer and cleanser with party-wide regeneration.
- Firemane is a Red magical-offense branch and an intentional Final Fantasy XII
  reference.
- Firemane's promotion key is easier to obtain than Kirin's. Choosing it early
  gives up the later Sleipnir -> Kirin route.

### Golem -> Talos (provisional)

Golem is the strictly nonmagical physical wall.

- enormous HP and DEF;
- extremely low MDF and severe magical vulnerability;
- low evasion and accuracy;
- poor MAT and no magical actions;
- no innate target-rate bonus;
- progression exaggerates the same identity rather than correcting its
  weaknesses.

`Talos` is a provisional promotion name. Magical damage must actually consume
MDF or another explicit magic-vulnerability mechanism before this identity is
authored; a weakness that only appears on the status screen is unacceptable.

### Gargoyle -> Grotesque (provisional)

Gargoyle is a more magical, active defensive creature.

- less absolute HP/DEF than Golem;
- credible MAT and MDF;
- an active Provoke skill;
- a party-wide magical-defense increase;
- more tactical control and better general competence than Golem.

Provoke should apply an ordinary temporary state carrying `TARGET_RATE`, not
invoke special-case enemy logic. `Grotesque` is a provisional promotion name.

### Moa

Moa is a strange pink mount bird inspired by Yoshitaka Amano's early,
Moebius-like chocobo drafts.

- The name `Moa` is approved.
- It is an Egg outcome.
- Its primary value is exploration: low MP burden, escape assistance, and
  eventually encounter-rate control.
- It should remain sturdy and useful without becoming another major combat
  family.
- No evolution is planned in this pass.

## Required reusable engine vocabulary

These are design requirements, not claims of current implementation.

| Addition | Purpose |
|---|---|
| `common_event` item effect | Run an existing common event from item use, RPG Maker-style |
| kill-trigger MP restore trait | Implement Diablos's Reaper without Diablos-specific Lua |
| `ITEM_EFFECT_RATE` | Scale consumable effects for Mimic/Pandora and equipment |
| `TARGET_RATE` | Let states such as Provoke modify enemy target selection |
| `ELEMENT_RATE` | Express elemental resistance and weakness on actors, states, and equipment |
| `STATE_RATE` / `STATE_RESIST` | Express condition vulnerability, resistance, and immunity |
| status-success rate | Let control specialists improve authored `add_status` effects |
| automatic promotion trigger | Hatch Egg and resolve other non-menu transformations safely |
| saved instance provenance | Preserve Egg source and other per-creature origins |
| saved Favorite Food identity | Preserve one randomized exact favorite and its discovery flag across forms |
| deterministic metamorphosis rule | Resolve Homunculus preview and destination |
| actor transformation command | Apply and later reverse Kappa-like transformations from events |
| Item Creation ingredient exclusion | Keep promotion keys out of ingredient selection |

## Provisional family balance sheets

These figures are intent benchmarks, not current data. They use the seeded,
budget-first growth model in `creature-parameters.md`. Tables for ordinary
level-gated forms assume promotion at the first eligible level. Tables for
item-gated forms use a representative acquisition point for comparison, not an
eligibility requirement. All include the fixed promotion bonus. Delayed
promotion preserves the lower form's actual accumulated history instead.

### Pixie family

The expected central history is:

| Form and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Pixie 1 | 30 | 10 | 12 | 18 | 16 | 1 |
| Pixie 10, before promotion | 70 | 14 | 25 | 45 | 38 | 1 |
| High Pixie 10, after promotion | 78 | 14 | 26 | 50 | 41 | 2 |
| High Pixie 20, before promotion | 143 | 21 | 42 | 92 | 69 | 2 |
| Titania 20, after promotion | 161 | 21 | 45 | 101 | 76 | 4 |
| Titania 30 | 241 | 30 | 67 | 151 | 111 | 4 |

High Pixie's level 11-20 central growth budget is:

```text
HP +65, ATK +7, DEF +16, MAT +42, MDF +28
```

Titania's level 21-30 central growth budget is:

```text
HP +80, ATK +9, DEF +22, MAT +50, MDF +35
```

If High Pixie declines Titania, her cheaper level 21-30 central budget is:

```text
HP +70, ATK +9, DEF +20, MAT +48, MDF +32
```

That produces an expected level-30 High Pixie near `213 / 30 / 62 / 140 /
101` at MPD 2. Titania is stronger and gains her fairy-queen support identity,
but an unpromoted High Pixie retains twice Titania's pure walking range.

Titania's provisional aura should inspect allies' form-defined MPD through
ordinary reusable flow vocabulary. Its exact effect remains open; it should
protect or strengthen economical allies rather than becoming an unconditional
party-wide statistic bonus.

### Undine -> Proteus

Undine begins as a straightforward Blue damage caster. Proteus keeps credible
spell power while redirecting future growth into HP, physical competence, and
support durability.

| Form and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Undine 1 | 44 | 9 | 12 | 19 | 16 | 2 |
| Undine 10, before promotion | 100 | 18 | 28 | 47 | 38 | 2 |
| Proteus 10, after promotion | 114 | 20 | 30 | 52 | 41 | 4 |
| Proteus 20 | 199 | 48 | 60 | 90 | 70 | 4 |
| Proteus 30 | 309 | 86 | 100 | 134 | 104 | 4 |

Proteus's central future budgets are:

```text
levels 11-20: HP +85,  ATK +28, DEF +30, MAT +38, MDF +29
levels 21-30: HP +110, ATK +38, DEF +40, MAT +44, MDF +34
```

An Undine that never promotes should finish near the ordinary caster profile,
approximately `260 / 42 / 65 / 125 / 90` at MPD 2. Proteus therefore gains
substantial physical and survival capability but only a modest MAT advantage.
Its doubled MPD pays for role compression: damage caster, support unit, and
credible frontliner in one party slot.

### Cocoon -> Notiluca

| Form and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Cocoon 1 | 38 | 8 | 16 | 15 | 18 | 1 |
| Cocoon 10 | 85 | 16 | 35 | 38 | 44 | 1 |
| Notiluca 10, promoted | 95 | 17 | 37 | 44 | 49 | 3 |
| Notiluca 30 | 250 | 42 | 78 | 128 | 125 | 3 |

Notiluca pays for status reliability, multi-target mesmerizing light, and
support illumination rather than direct damage. Retaining Cocoon at MPD 1 is a
valid extreme-economy control choice, but with worse success rates, targets,
and survivability.

### Gbl. Thief -> Gbl. Prince

| Form and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Gbl. Thief 1 | 45 | 17 | 12 | 7 | 10 | 1 |
| Gbl. Thief 10 | 100 | 40 | 27 | 15 | 22 | 1 |
| Gbl. Prince 10, promoted | 112 | 45 | 29 | 19 | 25 | 2 |
| Gbl. Prince 30 | 280 | 112 | 70 | 60 | 65 | 2 |

The Prince remains an opportunistic physical creature rather than a front-line
fighter. Its modest MAT supports magical/economic tricks. Exploration,
discovery, escape, and wealth manipulation justify the promotion more than raw
combat growth.

### Mandrake -> Alraune

| Form and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Mandrake 1 | 55 | 10 | 18 | 15 | 17 | 2 |
| Mandrake 10 | 125 | 22 | 40 | 38 | 42 | 2 |
| Alraune 10, promoted | 140 | 24 | 44 | 44 | 48 | 3 |
| Alraune 30 | 345 | 62 | 102 | 125 | 120 | 3 |

Alraune is a durable botanical support caster. Cooking identity, field sustain,
condition care, and food interaction carry much of her value.

### Golem -> Talos

| Form and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Golem 1 | 70 | 16 | 25 | 5 | 8 | 2 |
| Golem 10 | 155 | 35 | 55 | 10 | 15 | 2 |
| Talos 10, promoted | 177 | 39 | 63 | 10 | 16 | 3 |
| Talos 30 | 560 | 105 | 175 | 30 | 50 | 3 |

Talos intensifies HP, DEF, and physical pressure without repairing accuracy,
evasion, magic, or magical defense. `Talos` remains provisional.

### Gargoyle -> Grotesque

| Form and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Gargoyle 1 | 58 | 13 | 20 | 17 | 20 | 3 |
| Gargoyle 10 | 130 | 30 | 45 | 42 | 47 | 3 |
| Grotesque 10, promoted | 145 | 32 | 49 | 47 | 53 | 4 |
| Grotesque 30 | 390 | 85 | 115 | 120 | 135 | 4 |

Gargoyle actively controls attacks and protects the party from magic.
Grotesque remains far below Talos's physical extremes but has no comparably
catastrophic matchup. `Grotesque` remains provisional.

### Unicorn branches

| Form and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Unicorn 1 | 52 | 14 | 15 | 17 | 18 | 2 |
| Unicorn 10 | 118 | 32 | 35 | 43 | 45 | 2 |
| Sleipnir 20 | 225 | 70 | 72 | 78 | 82 | 3 |
| Sleipnir 30, no Kirin | 350 | 110 | 110 | 110 | 120 | 3 |
| Kirin 30 | 375 | 105 | 115 | 145 | 155 | 5 |
| Nightmare 30 | 300 | 120 | 78 | 135 | 90 | 3 |
| Firemane 30 | 350 | 125 | 90 | 140 | 95 | 4 |

Sleipnir is the economical balanced route. Kirin converts that foundation into
high-end healing, cleansing, and regeneration. Nightmare gives up healing for
Black pressure. Firemane pays more MPD for the strongest immediate mixed
offense. The table uses level 10 for the first branch and level 20 for Kirin as
representative comparison points. Firemane and Kirin have no level requirement
when their respective item and prerequisite form are available.

### Dragon branches

Dragon hatches at level 10 near `170 / 48 / 48 / 48 / 48` at MPD 4. Choosing
an elemental branch grants shared `HP +15` and `+3` to each core stat, followed
by a small branch emphasis. Expected final-form centers are:

| Final form | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Salamander | 520 | 150 | 115 | 120 | 105 | 9 |
| Leviathan | 500 | 115 | 115 | 155 | 140 | 9 |
| Fafnir | 570 | 120 | 130 | 125 | 130 | 9 |
| Bahamut | 520 | 125 | 135 | 135 | 155 | 9 |
| Nidhogg | 480 | 125 | 105 | 155 | 115 | 9 |

Elemental Dragons are MPD 6 and final forms are MPD 9. Final-form centers use
level 20 as a comparison point, but the branch-specific item may be consumed at
any level after entering the corresponding elemental branch. The five lines
retain a shared generalist chassis; passive, signature skill, affinity, and
Item Creation discipline must matter more than their modest statistical
differences.

### Giant branches

| Form and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Giant 1 | 75 | 20 | 20 | 8 | 10 | 4 |
| Giant 10 | 175 | 48 | 48 | 22 | 28 | 4 |
| Hill Gigas 20 | 350 | 95 | 80 | 75 | 55 | 6 |
| Atlas 20 | 390 | 105 | 105 | 45 | 75 | 6 |
| Surtr 30 | 600 | 160 | 115 | 145 | 85 | 9 |
| Hyperion 30 | 680 | 165 | 180 | 70 | 130 | 9 |

Hill Gigas and Surtr are Red/Black mixed attackers. Atlas and Hyperion are
White/Green physical and defensive monsters. Both remain inaccurate,
low-evasion heavy creatures.

### Mimic -> Pandora

Pandora has no level requirement. A level-1 Mimic may promote as soon as the
dedicated item is available. The table compares level-30 outcomes.

| Form | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Mimic 30 | 380 | 90 | 120 | 55 | 90 | 3 |
| Pandora 30 | 350 | 100 | 105 | 85 | 105 | 4 |

Pandora is slightly frailer, modestly stronger, and much better at exploiting
items. `ITEM_EFFECT_RATE` and her expanded item interactions are the real
promotion reward.

### One-stage creatures

| Creature and level | HP | ATK | DEF | MAT | MDF | MPD |
|---|---:|---:|---:|---:|---:|---:|
| Cerberus 1 | 100 | 30 | 22 | 18 | 15 | 6 |
| Cerberus 30 | 280 | 90 | 65 | 55 | 50 | 6 |
| Diablos 10 | 220 | 70 | 55 | 75 | 50 | 8 |
| Diablos 30 | 480 | 145 | 105 | 155 | 100 | 8 |
| Native Kappa 1 | 65 | 12 | 24 | 10 | 22 | 1 |
| Native Kappa 30 | 350 | 65 | 110 | 55 | 105 | 1 |
| Moa 1 | 60 | 14 | 20 | 8 | 15 | 1 |
| Moa 30 | 300 | 75 | 90 | 40 | 70 | 1 |

Cerberus begins around an ordinary creature's level-7-to-10 power and then
grows poorly. Its MPD never becomes more efficient, so the rest of the roster
eventually catches it. Diablos remains exceptional; Reaper partially offsets
MPD 8 only when Diablos personally secures kills.

Native Kappa is an extremely economical, sturdy exploration specialist and a
poor combat finisher. Curse-transformed Kappas retain their accumulated
statistics and growth history rather than receiving the native Kappa table.
Moa is similarly economical and sturdy, with exploration and escape utility
instead of magical or offensive distinction.

### Egg hatch outcomes

Egg remains MPD 0 while unresolved. At level 10, provenance selects an outcome
and applies an outcome-specific fixed hatch bonus calibrated to that species'
normal level-10 center:

| Outcome | Expected level-10 center | MPD |
|---|---|---:|
| Larva | `95 / 35 / 25 / 20 / 20` | 3 |
| Angel | `100 / 25 / 35 / 45 / 50` | 2 |
| Moa | `130 / 30 / 40 / 18 / 30` | 1 |
| Dragon | `170 / 48 / 48 / 48 / 48` | 4 |
| Phoenix | `200 / 55 / 55 / 80 / 70` | 8 |

The hatch bonus is fixed and provenance-specific, not a generic recalculation.
The Egg's seeded variation can perturb that bonus narrowly so the hatched
creature remains an individual. Mystic Egg produces Phoenix; ordinary dungeon
tables never casually grant that result.

### Homunculus

Homunculus cannot have a single destination table. It retains its exact
accumulated statistics when transforming, adopts the destination form's MPD,
and uses that form's future growth budgets. The visible preview therefore tells
the truth about the result without revealing why the current parameters select
it. Rare exact rules, including permanent intrinsic MaxHP equal to 666, resolve
before general profile matching.

Where an existing state, formula, trait, effect, or event command can express
the behavior faithfully, no new primitive should be added.

## Relationship to the item atlas

The actor roster should be documented before the planned approximately 150
gameplay items, but actors and items should be implemented together in
vertical slices.

The item pass must furnish:

- four to five useful equipment tiers;
- polyvalent found objects with uses beyond Item Creation;
- sufficient output density for all four disciplines;
- regional Egg provenance sources;
- branch-specific promotion keys;
- consumables that justify Mimic/Pandora;
- food pools, food tags, Savor bonuses, and Favorite Food discovery;
- status, resistance, and elemental equipment that justify the new traits;
- Lamp and curse objects that call data-authored common events;
- monster drops and sacrifice rewards that reinforce each creature's identity.

Promotion keys are the deliberate exception to polyvalence: they exist only to
unlock a promotion or to be sold for substantial gold.

## Open authoring questions

- Seeded band budgets, allowable variance, skill formulas, and passive values
  around the approved working parameter centers.
- Final disciplines for Undine/Proteus, Cocoon/Notiluca, Goblin, Homunculus,
  Gargoyle, Moa, and several promoted forms.
- Exact regional Egg tables and their weights.
- Diablos encounter composition, level, Reaper MP value, and Lamp resolution
  behavior after victory.
- Homunculus eligibility exclusions, rare exact conditions, and comparison
  metric.
- Final promotion names for Golem and Gargoyle.
- Final promotion-key names, prices, icons, and acquisition locations.
- Exact encounter-rate behavior for Moa and exploration behavior for Kappa.
- Whether physical and magical damage currently route through DEF and MDF in a
  way sufficient for Golem's promised weakness.
