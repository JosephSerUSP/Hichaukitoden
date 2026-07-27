# Level 1-10 vertical-slice balance

> **Intent and test protocol, not implementation status.** Live status remains
> the authority of `docs/ENGINE-STATE.md`. This document defines the first
> playable balance pass over the existing six-floor campaign.

## Purpose

The slice must prove that the expanded database forms a progression rather than
merely a valid collection of content. A successful run begins with ordinary
level-1 creatures and ends near level 10 after visiting Floors 1-3, with later
floors reserved for follow-up testing.

The slice must exercise:

- field MP pressure and a meaningful retreat decision;
- at least three elemental matchups;
- one Favorite Food discovery and one useful Savor activation;
- one meal used for party recovery and one battle-usable drink;
- Item Creation with found, bought, and monster-derived ingredients;
- one Egg with visible provenance and an automatic level-10 hatch;
- two ordinary level promotions;
- one branch-specific item promotion whose key cannot be crafted;
- one fragile low-MPD party and one expensive high-power party.

## First audit: structural findings

### Experience cannot presently reach the target

The live curve costs `level * 15` EXP for each next level:

| Goal | Cumulative EXP | Victories at the former flat 5 EXP |
|---|---:|---:|
| Level 2 | 15 | 3 |
| Level 5 | 150 | 30 |
| Level 8 | 420 | 84 |
| Level 10 | 675 | 135 |

The slice now uses a provisional flat reward of **15 EXP per ordinary
victory**, reaching level 10 in 45 victories. This is explicitly a test value:
encounter danger, enemy count, and enemy level should eventually determine the
reward.

### Dungeon danger now has an authored level ramp

Map encounter entries now accept:

```json
{
  "id": 25,
  "weight": 3,
  "levelMin": 2,
  "levelMax": 3
}
```

`SPAWN_ENEMIES` resolves one level per spawned enemy inside that range. Entries
without a range retain the actor's default level without consuming another
random draw. G1 validates the range, and the map editor authors it. Floors 1-3
now use the provisional 1-3, 3-6, and 6-10 bands.

### Legacy starting HP has joined the expanded scale

Legacy base Max HP was raised while preserving deliberate exceptions: Pixie
remains at 12, Golem remains the early 70-HP wall, and Bat remains among the
frailest ordinary bodies. Egg was raised from 5 to 30 so carrying one to level
10 is risky without being a near-automatic death sentence. The next playtest
must still measure the legacy growth-band budgets; this pass aligned starting
durability rather than pretending the complete level-30 curve is settled.

### Encounter frequency is global

All dungeon maps currently inherit `combat.encounterChance = 0.1`; the authored
`encounterSteps` field does not drive the live encounter check. A ten-percent
roll on every moved tile has high variance and cannot promise a stable number
of fights per floor. For the first playtest it should remain unchanged and be
measured, not pre-emptively replaced.

## Provisional slice targets

| Measure | Floor 1 | Floor 2 | Floor 3 |
|---|---:|---:|---:|
| Expected party level on entry | 1 | 3-4 | 6-7 |
| Enemy level range | 1-3 | 3-6 | 6-10 |
| Expected victories | 10-14 | 12-16 | 14-18 |
| Ordinary battle length | 2-4 rounds | 3-5 rounds | 3-6 rounds |
| Boss/pressure battle length | 5-8 rounds | 6-9 rounds | 7-10 rounds |
| Retreat MP remaining | 35-65% | 25-55% | 15-45% |
| New crafting discoveries | 2-4 | 3-5 | 3-5 |

These are measurement bands, not promises. A low-MPD Pixie/Kappa-style party
should exceed the MP band and pay for that endurance through combat risk. A
Cerberus or heavy frontline should fall below it and gain safer battles.

## Availability pass

- Floor 1 introduces Cocoon, Gbl. Thief, Mandrake, Kappa, and ordinary legacy
  creatures.
- Floor 2 introduces Undine, Homunculus, Mimic, Unicorn, and Gargoyle.
- Floor 3 introduces Cerberus and Giant as expensive early power choices.
- Ordinary equipment shops stop at tier 3.
- Tier-4/5 equipment and promotion keys belong to the auction.
- The pub is the primary meal source; dungeon merchants sell expedition staples.

The Floor 1 hidden-workshop reward now guarantees a Mystic Egg, Pão de Queijo,
and Onigiri alongside its existing quest reward. The trapped chest also grants
Black Hinge on either successful opening path, making Mimic-to-Pandora the
slice's first branch-specific item promotion. The foods remain useful items in
their own right and can also participate in Item Creation.

## Playtest record

For every expedition record:

- party species, levels, MPD, equipment, Favorite Food discoveries;
- steps moved, encounters won/fled, rounds per battle;
- starting/retreat MP and spell MP spent;
- damage taken, incapacitations, and cause of each permanent death;
- EXP and levels gained;
- items found, consumed, sold, and used as ingredients;
- recipes discovered and whether each result was immediately relevant;
- promotions available, chosen, or delayed.

Balance changes should answer a recorded failure. Passing the validator is not
evidence that a number is good.

## First static encounter sample

A deterministic 10,000-pick sample of each weighted table, using the authored
level ranges and an approximate share of the level-2-10 HP budget, produced:

| Floor | Mean enemy level | Approx. mean enemy HP | Most common species |
|---|---:|---:|---|
| 1 | 1.83 | 40.2 | Pixie 22.5%, Skeleton 22.2%, Mandrake 14.4% |
| 2 | 4.46 | 63.6 | Skeleton 28.1%, Imp 17.0%, Wisp 13.8% |
| 3 | 7.62 | 110.8 | Golem 28.8%, Demon 18.6%, Angel 14.8% |

This confirms a readable numerical ramp, but it is not a combat simulation.
Floor 3's Golem share is the first likely pressure point: almost 29% of enemy
picks are the anti-physical wall. The first manual run should determine whether
that teaches party composition or merely makes the floor repetitive.
