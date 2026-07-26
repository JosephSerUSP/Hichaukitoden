# Item Atlas Expansion - Working Direction

> **Intent, not status.** This document records the agreed direction for a
> future item-database expansion. For what exists right now, read the generated
> [`docs/ENGINE-STATE.md`](../ENGINE-STATE.md) (gated by G4); for how the engine
> works, read [`docs/SPEC.md`](../SPEC.md). Where this document and either source
> disagree, they win.

Status: early content-atlas direction. Item counts are planning targets. Names
listed as approved directions are not authored database records; exact effects,
prices, IDs, icons, acquisition, formulas, and balance remain open.

Related roster requirements are recorded in
[`actor-roster-expansion.md`](actor-roster-expansion.md).
Approved content that requires new reusable engine vocabulary is tracked in
[`content-engine-gaps.md`](content-engine-gaps.md).

## Purpose

The planned expansion is approximately 150 new gameplay items supporting a
longer, multi-campaign game with four to five useful equipment tiers. Items
must serve battle, exploration, Item Creation, creature progression, or several
of those roles.

Item Creation is not a reason to author inert inventory filler. An item's use as
an ingredient is one role it may have, never its entire identity, except where
this document explicitly allows a single-purpose promotion key.

## Core authoring axes

These properties are independent:

- **Database form:** weapon, armor, accessory, consumable, or special key.
- **Producing disciplines:** which Item Creation disciplines may produce it.
- **Use occasion:** battle, field, or always.
- **Target:** one creature, the party, or no battler.
- **Food identity:** exact item identity and descriptive food tags.
- **Craft eligibility:** whether it may be an output and whether it may be an
  ingredient.
- **Acquisition:** shop, drop, sacrifice, exploration, event, or another
  authored source.

Cooking results need not be Meals. Meals need not be exclusive to Cooking.
For example, Cooking may produce a battle-usable MP draught, while an
alchemical nutrient food may be a field-only party Meal.

## Provisional database shape

| Form | Approximate new items |
|---|---:|
| Weapons | 28 |
| Armor | 28 |
| Accessories | 36 |
| Consumables | 48 |
| Single-purpose promotion keys | 10 |
| **Total** | **150** |

The counts may move as concrete families are authored. Functional coverage is
more important than preserving an arbitrary quota.

Ten promotion keys are currently required: five Dragon finals, two Giant
finals, Pandora, Kirin, and Firemane. Item-gated promotions normally have no
additional level requirement.

## Equipment tiers and names

Equipment uses approximately five economic/power bands, subject to simulation
against Item Creation's cost-derived intensity:

| Tier | Campaign role | Initial price region |
|---|---|---:|
| 1 | Crude, common, improvised | 5-40 |
| 2 | Reliable regional equipment | 50-160 |
| 3 | Specialized midgame gear | 200-600 |
| 4 | Rare build-defining equipment | 800-2,000 |
| 5 | Exceptional late-game objects | 2,500-7,500 |

Provisional flat-stat centers:

| Tier | Weapon primary stat | Armor HP | Armor defensive stat |
|---:|---:|---:|---:|
| 1 | +3 to +5 | +10 to +20 | +3 to +5 |
| 2 | +7 to +10 | +25 to +40 | +7 to +10 |
| 3 | +13 to +18 | +55 to +90 | +12 to +18 |
| 4 | +22 to +30 | +110 to +170 | +20 to +28 |
| 5 | +32 to +45 | +180 to +280 | +30 to +42 |

Armor need not grant both full HP and full defense. Robes may favor MAT/MDF;
plate may favor HP/DEF and carry accuracy or magic drawbacks; flexible armor
may split DEF/MDF.

Only about sixty percent of equipment should follow obvious power ladders. The
rest should be lateral equipment: exploration tools, elemental conversion,
status protection, unusual trait combinations, parameter tradeoffs, and crude
found objects with small but real equip effects.

Naming follows function:

- Plain upgrades receive plain names.
- Unique names promise unique behavior.
- An item named `Executioner` must execute; it cannot merely be `ATK +3`.
- Plain names are most common in early tiers. Individual names become more
  common as effects become stranger.

Trait budgets are not interchangeable:

- ordinary critical bonuses are +2% to +4%, strong bonuses +5% to +8%, and
  signature bonuses +10% to +15%;
- parameter-rate equipment usually ranges from +5% early to +15% late, with
  +20% to +25% reserved for exceptional single-stat pieces;
- adding an innate element consumes most of an item's trait budget because
  elemental identity compounds;
- passive direct-damage rates near 95% are useful, 90% is major, and 80% to
  85% is signature protection; Defend's temporary 50% is not an ordinary
  equipment value.

Accessories are primarily lateral. Small raw-stat objects, including a Rock
with `DEF +1`, remain valid without competing in a five-tier ladder.

## Functional slot map

Names are attached only after these jobs are reviewed.

### Weapons: 28

| Family | Count | Coverage |
|---|---:|---|
| Physical ladder | 5 | Plain ATK progression |
| Magical ladder | 5 | Plain MAT progression |
| Hybrid ladder | 5 | Split ATK/MAT or offense/support |
| Elemental weapons | 5 | One lateral identity for each element |
| Critical/status weapons | 3 | Critical reliability and attached conditions |
| Execution/penetration weapons | 2 | Specialized finishing or anti-armor |
| Improvised/remain weapons | 3 | Polyvalent drops and found objects |

Approved weapon names:

| Family | Names |
|---|---|
| Physical ladder | Iron Knife, Steel Sword, Knight Sword, Greatsword, Adamant Blade |
| Magical ladder | Hazel Wand, Silver Rod, Mage Staff, Sage Staff, Ether Staff |
| Hybrid ladder | War Staff, Rune Knife, Spell Sword, Glass Blade, Comet Edge |
| Elemental | Flame Saber, Coral Sword, Air Knife, Healing Staff, Death Sickle |
| Critical/status | Venom Knife, Sleep Blade, Barbed Spear |
| Signature | Executioner, Pile Bunker |
| Improvised/remain | Broken Cleaver, Bone Club, Cerberus Fang |

These names are approved atlas entries, not implemented database records.
`Executioner` must carry Execution, `Pile Bunker` must penetrate defense, and
the three remains are usable equipment and ingredients but never Item Creation
outputs.

### Armor: 28

| Family | Count | Coverage |
|---|---:|---|
| Physical armor ladder | 5 | HP/DEF progression |
| Magical armor ladder | 5 | MAT/MDF progression |
| Balanced armor ladder | 5 | Split survival |
| Elemental armor | 5 | Affinity and element-specific protection |
| Status armor | 3 | Broad resistance or narrow immunity |
| Guard/barrier armor | 2 | Damage-rate and defensive-action interaction |
| Improvised/remain armor | 3 | Polyvalent drops and found objects |

Approved armor names:

| Family | Names |
|---|---|
| Physical ladder | Leather Armor, Ring Mail, Chainmail, Plate Armor, Adamant Armor |
| Magical ladder | Cotton Robe, Silk Robe, Mage Robe, Sage Robe, Ether Robe |
| Balanced ladder | Traveler Coat, Brigandine, Scale Mail, Dragon Mail, Hero Armor |
| Elemental | Flame Mail, Coral Mail, Wind Robe, Holy Vestment, Black Robe |
| Status | Gas Mask, Moth Cloak, Quarantine Coat |
| Guard/barrier | Mirror Armor, Fortress Plate |
| Improvised/remain | Tin Armor, Cocoon Husk, Slime Coat |

These names are approved atlas entries, not implemented records. Cocoon Husk
and Slime Coat are monster remains and cannot be Item Creation outputs.
Quarantine Coat provides broad partial resistance; full ordinary-status
protection belongs to the accessory **Ribbon**.

### Accessories: 36

| Family | Count | Coverage |
|---|---:|---|
| Small-stat and crude objects | 5 | Rocks, scraps, minor mixed bonuses |
| Elemental identity | 5 | One carefully budgeted option per element |
| Status protection | 7 | Rates, immunity, cleansing support, and the top-end Ribbon |
| Exploration economy | 5 | Escape, discovery, encounter, and rare MPD interaction |
| Item/Cooking support | 4 | Item effect, Savor, and food interaction |
| Initiative/critical/targeting | 4 | Tactical manipulation |
| Remains and found objects | 3 | Ingredient plus equip use |
| Rare defensive oddities | 3 | Death wards and other signature protection |

Approved accessory names:

| Family | Names |
|---|---|
| Small objects | Rock, Glass Bead, Copper Coin, Iron Nail, Old Bell |
| Elemental identity | Ruby Ring, Sapphire Ring, Emerald Ring, Pearl Ring, Onyx Ring |
| Status protection | Star Pendant, Silver Glasses, White Cape, Peace Ring, Earplugs, Safety Bit, Ribbon |
| Exploration | Compass, Lantern, Thief Glove, Sprint Shoes, Moa Saddle |
| Item/Cooking | Chef Hat, Apron, Medicine Ring, Mimic Tongue |
| Tactical | Sniper Eye, Black Belt, Provoke Badge, Cat Bell |
| Remains | Golem Shard, Moth Scale, Slime Core |
| Rare defensive | Protect Ring, Angel Feather, Phoenix Pinion |

Ribbon blocks ordinary negative states, not direct damage, permanent death,
event transformations, or Execution. Safety Bit owns anti-Execution protection.
Mimic Tongue, Golem Shard, Moth Scale, and Slime Core are monster remains and
cannot be Item Creation outputs.

An accessory that reduces its wearer's MPD by 1 is potentially worth hundreds
or thousands of MP across an expedition. Such an effect is late, rare, cannot
reduce MPD below 1, and consumes nearly the whole item budget. Increasing MPD
in exchange for a powerful effect is also a valid drawback.

### Consumables: 48

| Family | Count | Coverage |
|---|---:|---|
| HP recovery | 7 | Fixed, percentage, and hybrid tiers |
| MP recovery | 7 | Battle draughts and efficient field recovery |
| Cures and battle support | 8 | Conditions, buffs, escape, and tactical objects |
| Cultural foods | 20 | Mixed Meals, snacks, battle foods, and Savor identities |
| Permanent/event items | 6 | Small parameter gains and Lamp-like events |

The twenty-food roster is not twenty Meals. Occasion, discipline, target, Meal
marker, and food identity remain independent.

Approved non-food consumable names:

| Family | Names |
|---|---|
| HP recovery | Potion, Hi-Potion, X-Potion, Mega-Potion, Healing Water, Soma, Elixir |
| MP recovery | Ether, Hi-Ether, Dry Ether, Turbo Ether, Ether Drop, Ether Flask, Soma Drop |
| Cures/support | Antidote, Eye Drops, Echo Herbs, Alarm Clock, Remedy, Smoke Bomb, Hero Drink, Bacchus Wine |
| Permanent/event | Power Incense, Guard Incense, Magic Incense, Spirit Incense, Ether Seed, Forbidden Lamp |

Phoenix Down is deliberately absent because reaching zero HP causes permanent
death. Teaching tomes are not reserved in this systemic 150-item pass: they are
excluded from generative Item Creation by default and added only alongside
specific authored skills and whitelist-safe acquisition.

### Promotion keys: 10

| Destination | Keys |
|---|---:|
| Salamander, Leviathan, Fafnir, Bahamut, Nidhogg | 5 |
| Surtr, Hyperion | 2 |
| Pandora, Kirin, Firemane | 3 |

All ten are single-purpose promotion-or-sale objects and are excluded from both
Item Creation inputs and outputs.

## Recovery and permanent-gain scale

### HP restoration

| Tier | Fixed HP |
|---:|---:|
| 1 | 25-50 |
| 2 | 70-120 |
| 3 | 150-240 |
| 4 | 280-450 |
| 5 | 500-800 |

Percentage and fixed-plus-percentage effects keep unusual foods and rare items
relevant to creatures with very different MaxHP.

### MP restoration

| Tier | Fixed MP | Share of opening 3000 | Share of endgame 9999 |
|---:|---:|---:|---:|
| 1 | 150-250 | 5-8% | 1.5-2.5% |
| 2 | 350-500 | 12-17% | 3.5-5% |
| 3 | 700-1000 | 23-33% | 7-10% |
| 4 | 1400-2000 | 47-67% | 14-20% |
| 5 | 2500-3500 | excessive early | 25-35% |

Rare scalable restoration may restore 10%, 20%, or 30% Max MP. Full recovery is
event/relic territory rather than an ordinary item-atlas role.

### Permanent gains

| Parameter | Ordinary item | Exceptional item |
|---|---:|---:|
| MaxHP | +3 to +8 | +10 to +20 |
| ATK/DEF/MAT/MDF | +1 | +2 to +3 |
| Summoner Max MP | +50 to +100 | +150 to +250 |

Major event Max-MP increases remain much larger, often +500 or +750. Permanent
stat gains are not standard Favorite Food rewards.

## Polyvalent objects and remains

`junk` is not a desired authoring category. A Rock may be represented as a weak
accessory; a bitter fungus may be a consumable; a broken cleaver may be a
weapon. Found-object identity comes from the authored object, not from a type
that prevents every non-crafting use.

The existing Obsidian Shard, Melted Wax, and Ectoplasm should eventually be
migrated to usable or equippable forms rather than serve as the model for new
content.

Monster remains have this policy:

| Property | Monster remains |
|---|---|
| Acquired from | Drops, sacrifice, events, exploration |
| Item Creation ingredient | Yes |
| Item Creation output | No |
| Other use | Equip, use, or sell |

They use existing output exclusion (`meta.craftable: false`) while remaining
valid ingredients. A low shop value may pair with `intensityGrade: precious`
when the remain's crafting importance exceeds its sale price.

Promotion keys are the deliberate exception:

- not usable;
- not equippable;
- not valid ingredients;
- not valid outputs;
- consumed only by their corresponding promotion;
- sellable for substantial gold.

This requires a separate registry-backed ingredient exclusion in addition to
the existing output exclusion.

## Cooking, Meals, and edible objects

Food is culturally important to the project. The catalog should reflect the
developer's regular contact with Brazilian, Afro-Brazilian, Italian, Japanese,
Chinese, Thai, specific African, French, Korean, and other food traditions.
Food should feel treated with affection rather than used as a checklist or as
an elemental stereotype.

### Meal behavior

- Meals are usable only outside battle.
- Most Meals affect the whole party.
- Meals have only their immediate authored effects.
- An immediate effect may add an ordinary state that persists outside battle.
- There is no separate shared "Meal Effect" layer.
- Favorite Food Savor is the one dedicated persistent food system.

Snacks, drinks, draughts, and other edible items may be usable in battle. Any
tagged edible item, Meal or otherwise, can discover and activate an
individual's exact Favorite Food.

Favorite Food instance rules and persistence are defined in the actor roster
document.

### Food naming

- Prefer one or two words.
- Three words are acceptable when they form a familiar natural name, such as
  `Pao de Queijo` in ASCII transcription; shipped display text should preserve
  the correct `Pão de Queijo` if the font supports it.
- Use the real dish name unless a fantasy ingredient materially defines it.
- Fantasy modifiers should be concrete nouns such as Moa, Moonfish, Slime,
  Mana, or Mandrake.
- Prefer `Moonfish Moqueca` to `Moqueca de Moonfish`.
- Avoid ornamental generator-like modifiers such as Obsidian-Bean or Glowcap
  when the object is not literally defined by that substance.
- Not every food needs a fantasy modifier. Ordinary dishes ground the stranger
  ones.
- Cultural origin does not determine power tier. Potency follows serving size,
  ingredient rarity, magical properties, and gameplay role.

### First food roster

Effects below are identity sketches, not balanced values.

| Item | Form | Immediate identity |
|---|---|---|
| Pão de Queijo | Meal | Affordable party HP recovery |
| Coxinha | Snack | Battle-usable HP recovery |
| Feijoada | Meal | Strong party HP recovery; possible defensive state |
| Moonfish Moqueca | Meal | Party HP and MP recovery |
| Mana Congee | Meal | MP recovery and cleansing |
| Onigiri | Snack | Reliable battle HP recovery |
| Moa Tamagoyaki | Meal | Recovery and possible initiative state |
| Slime Natto | Meal | Condition resistance or cleansing, with unusual risk |
| Mooncake | Snack | MP or XP recovery |
| Mochi | Snack | Small HP/MP recovery |
| Daifuku | Snack | Stronger MP recovery than Mochi |
| Curry | Meal | Party recovery and possible offensive state |
| Beef Stew | Meal | Substantial HP recovery |
| Sushi | Meal | Balanced HP/MP recovery |
| Ramen | Meal | Strong post-expedition recovery |
| Pizza | Meal | Large party HP recovery |
| Risotto | Meal | Gentle HP/MP recovery |
| Tempura | Meal | Recovery and possible initiative state |
| Kimchi | Side or snack | Cure or resist conditions |
| Mandrake Tempura | Meal | Botanical variation with a distinct effect |

Names already strongly favored include:

- Moonfish Moqueca
- Mana Congee
- Moa Tamagoyaki
- Slime Natto
- Pão de Queijo
- Feijoada
- Coxinha
- Mandrake Tempura

Potential later additions include Acaraje, Brigadeiro, Quindim, Ochazuke,
Baozi, Mapo Tofu, Tom Yum, Jollof Rice, Egusi Soup, Injera, Ratatouille,
Cassoulet, Polenta, and Gnocchi. Correct display spelling and diacritics should
be preserved and verified rather than silently flattened.

### Food-tag and Savor direction

Food tags characterize an edible item and help define its Savor effect, but a
creature's Favorite Food is one exact item ID selected from a species-authored
pool.

Initial descriptive tags may include:

- meat;
- fish;
- vegetable or root;
- rice or bread;
- sweet;
- fermented;
- spicy;
- sour or bitter;
- fungus;
- mineral;
- spirit.

Tags do not automatically stack bonuses. Each food authors one Savor result,
informed by its tags. Broad defaults may speed authoring, while exceptional
foods may override them.

Non-favorite foods may produce short personality reactions without penalties,
mechanical clues, or candidate elimination.

## Required reusable vocabulary

These are design requirements, not implementation claims:

| Addition | Purpose |
|---|---|
| Item `occasion` | Restrict use to battle, field, or both |
| Food tags | Describe edible identity and support authored Savor defaults |
| Meal marker | Support UI/presentation without defining discipline |
| Individual Favorite Food state | Store exact item, discovery, and Savor counter |
| Battle-count Savor duration | Prevent immediate refresh while keeping food relevant |
| `ITEM_EFFECT_RATE` | Support Mimic/Pandora and other item specialists |
| `EXECUTION_THRESHOLD` | Let Executioner and Diablos finish weakened enemies |
| Execution resistance | Explicitly protect authored targets where appropriate |
| `common_event` item effect | Let items such as Forbidden Lamp invoke event content |
| Ingredient exclusion | Keep promotion keys out of Item Creation selection |

## Open questions

- Exact food effects, prices, acquisition sources, Savor values, and Favorite
  Food pools.
- Whether Savor lasts exactly three completed battles.
- Which states are allowed to persist from field use and how duration is
  presented.
- Final count of Meals versus battle-usable foods within the consumable pool.
- Exact names, effects, prices, and acquisition for the approved equipment
  families.
- Whether enemy-side Execution is allowed to affect player creatures.
- Boss and special-enemy Execution resistance policy.
- Exact discipline coverage once all families exist.
- Font coverage for Portuguese and other required diacritics.
