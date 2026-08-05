# Content Reachability and Acquisition Audit

**Engine Reachability Tool:** `lovec . reachability` (`engine/reachability.lua`)  
**Date:** August 5, 2026

---

## 1. Executive Summary & Inventory Counts

The database contains extensive actor and item rosters designed for a multi-stratum campaign. A full sweep of shops, quest rewards, event commands, chest pools, sacrifice rewards, recruitment pools, promotion paths, and Item Creation ideation space yields the following reachability totals:

| Roster Category | Total Count | Directly Obtainable | Craftable / Evolvable | Total Reachable | Unreachable Count | Reachability % |
|---|---:|---:|---:|---:|---:|---:|
| **Items** | 207 | 191 | 13 (craft-only) | 204 | 3 | 98.6% |
| **Actors (Creatures)** | 65 | 50 (direct / starting) | 6 (promotion) | 56 | 9 | 86.2% |
| **Shops** | 8 | 8 | N/A | 8 | 0 | 100.0% |
| **Common Events** | 20 | 18 | N/A | 18 | 2 | 90.0% |
| **Status States** | 14 | 12 | N/A | 12 | 2 | 85.7% |

*Note on actor producers:* 56 actors have at least one recognized producer in the engine data, while 9 actors have no recognized producer. Categories above summarize primary sources; individual actors may possess multiple acquisition paths.

---

## 2. Unreachable Entities Grouped by Reason

### A. Items with No Source (16 items without direct source)

#### 1. Deliberate Craft-Only Items (13 items)
These items have no direct shop/chest/event source because they are intended to be produced via Item Creation (alchemy, blacksmithing, cooking, tinkering):
* `[34]` **Burnt Slop** (consumable)
* `[35]` **Broken Spring** (equipment)
* `[36]` **Ambrosia** (consumable)
* `[37]` **Philosopher's Stone** (consumable)
* `[42]` **Warding Charm** (equipment)
* `[43]` **Vial of Second Breath** (equipment)
* `[44]` **Thrice-Blessed Bead** (equipment)
* `[45]` **Tome: Wind Blade** (consumable)
* `[46]` **Whetstone Draught** (consumable)
* `[107]` **Quarantine Coat** (equipment)
* `[128]` **Safety Bit** (equipment)
* `[134]` **Moa Saddle** (equipment)
* `[137]` **Medicine Ring** (equipment)

#### 2. Accidental Reachability Gaps (3 items)
These items have no shop/chest/drop source and CANNOT be produced by any Item Creation recipe:
* `[38]` **Chrysalis Sigil** (quest item — `meta.craftable = false`, `meta.craftIngredient = false`)
* `[196]` **Forbidden Lamp** (consumable)
* `[197]` **Town Portal** (consumable item variant — `Town Portal` common event exists, but item 197 is not sold in shops or dropped by enemies)

---

### B. Uncraftable Items in Discipline Pools (14 items)
These items belong to a discipline's item pool in `data/items.json`, but sweeping 2,785,185 ideation points shows no deliberate ingredient combination yields them as the top result:
* **Blacksmithing:** `[73]` Coral Sword, `[74]` Air Knife, `[75]` Healing Staff, `[76]` Death Sickle, `[109]` Fortress Plate
* **Alchemy:** `[103]` Holy Vestment, `[104]` Black Robe, `[122]` Onyx Ring, `[164]` Eye Drops, `[165]` Echo Herbs, `[194]` Spirit Incense, `[206]` Bell Salt
* **Tinkering:** `[133]` Sprint Shoes
* **Cooking:** `[189]` Kimchi

---

### C. Unobtainable Creatures (9 actors)

1. **`[16]` Phoenix** (High-tier fire summon — reserved for Stratum 3+)
2. **`[21]` Shadow Stalker** (High-tier dark summon — reserved for Stratum 3+)
3. **`[25]` Cocoon** (Special evolution state — missing promotion source)
4. **`[30]` Mandrake** (Mid-tier plant summon — reserved for Stratum 2)
5. **`[33]` Diablos** (Boss summon — reserved for boss contract)
6. **`[34]` Dragon** (Late-game summon — reserved for Stratum 4+)
7. **`[60]` Kappa** (Mid-tier water summon — reserved for Stratum 2)
8. **`[63]` Lamia** (Mid-tier summon — reserved for Stratum 2)
9. **`[65]` Cockatrice** (Mid-tier petrification summon — reserved for Stratum 2)

*(Note: Actor 61 Moa / Saban is already present in `data/system.json -> newGame.party.fixedMembers` at level 3 and consumed by `engine/newgame.lua`.)*

---

### D. Unapplied Status States (2 states)
* **`blind`** (Blind status effect)
* **`silence`** (Silence status effect)

---

## 3. Highest-Value Accidental Reachability Gaps

1. **Town Portal (Item 197):** Consumable item form is unbuyable; adding it to Shop 1 (Alicia's Bakery) provides immediate escape utility.
2. **Chrysalis Sigil (Item 38):** Quest item with no chest or event drop.
3. **Bell Salt (Item 206):** In alchemy pool but uncraftable via ideation and unbuyable in shops.
4. **Forbidden Lamp (Item 196):** Consumable item with no acquisition source.
5. **Sprint Shoes (Item 133):** Speed accessory in tinkering pool that no recipe can craft.
6. **Eye Drops (Item 164) & Echo Herbs (Item 165):** Key status recovery items in alchemy pool that no recipe can craft.
7. **Healing Staff (Item 75):** Essential early-mid healer weapon in blacksmithing pool that cannot be crafted.
8. **Blind & Silence States:** No skill or item inflicts or cures these states yet.
9. **Cocoon (Actor 25):** Evolution target with no evolution key or trigger path.

---

## 4. Global Reachability Analyzer Scope and Temporal Limits

`lovec . reachability` performs a **global static analysis** across all maps, shops, quests, common events, sacrifice tables, and recipe spaces in `data/*.json`. It identifies whether a item or creature has a valid producer anywhere in the project data.

**Important boundary:** The analyzer is global and does **not** establish temporal claims such as "available before first descent" or "unlocked after Incursion 2". Items stocked in late-stratum shops or awarded by deep quests count as reachable globally even if unavailable during the opening vertical slice.

---

## 5. Recommendations for Opening Vertical Slice

1. **Add Town Portal (`Item 197`) to Shop 1 stock:** Makes dungeon return emergency items available to buy before entering Floor 1.
2. **Add `Chrysalis Sigil` to Floor 3 chest pool (`data/maps.json` Map 4):** Resolves quest item reachability gap.
3. **Keep high-tier summons (`Diablos`, `Dragon`, `Phoenix`) unreachable:** Preserves late-game progression integrity.
