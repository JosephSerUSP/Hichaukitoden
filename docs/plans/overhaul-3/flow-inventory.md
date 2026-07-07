# Flow Inventory

| file:line | behavior | proposed phase | proposed command(s) | notes |
|---|---|---|---|---|
| **exploration.* (Map Mechanics)** | | | | |
| main.lua:967 | Encounter Roll | exploration.step | `ROLL_ENCOUNTER` | Triggered after moving |
| main.lua:614 | Enemy Composition (Spawn Enemies) | battle.battle_start | `SPAWN_ENEMIES` | Rolls enemy count and composition from map encounters |
| main.lua:504 | Treasure GIVE_ITEM path | exploration.interact | `GIVE_ITEM` / `GIVE_ITEM_ID` | Currently hardcoded random loot generation and addition |
| engine/exploration.lua:228 | Map MP Drain | exploration.step | `DRAIN_MP` | Drains MP for moving outside safe maps |
| **battle.encounter_check** | | | | |
| main.lua:610 | Check possible encounters | battle.encounter_check | `IF` + `ROLL_ENCOUNTER` | Checks if current map has enemies before spawning |
| **battle.battle_start** | | | | |
| main.lua:614 | Roll enemy composition | battle.battle_start | `SPAWN_ENEMIES` | Sets up the battle enemies |
| **battle.flee_attempt** | | | | |
| engine/battle.lua:116 | Flee resolution | battle.flee_attempt | `IF` + `ROLL_ENCOUNTER` (or specific FLEE command) | Rolls math.random vs baseFlee + passives |
| engine/battle.lua:126 | Flee success | battle.flee_attempt | `SCENE_EVENT` | Sets battle Escaped |
| engine/battle.lua:130 | Flee failure gold penalty | battle.flee_attempt | `GAIN_GOLD` (negative) / `EMIT_TEXT` | Lose random gold on fail |
| **battle.round_end** | | | | |
| engine/battle.lua:245 | State ticks (Regen) | battle.round_end | `STATE_TICKS` | Restores HP and logs heal event |
| engine/battle.lua:255 | State ticks (Poison) | battle.round_end | `STATE_TICKS` | Drains HP and logs damage event |
| engine/battle.lua:274 | State duration decay | battle.round_end | `STATE_TICKS` | Reduces state duration and removes if 0 |
| engine/battle.lua:298 | MP drain | battle.round_end | `DRAIN_MP` | Passive MP drain per living member |
| engine/battle.lua:307 | MP exhaustion damage | battle.round_end | `IF` + `DAMAGE` + `EMIT_TEXT` | Damage to party when MP is 0 |
| **battle.victory** | | | | |
| main.lua:1368 | Victory rewards (Gold) | battle.victory | `GAIN_GOLD` | Rolls math.random for victory gold |
| main.lua:1374 | Victory rewards (Exp) | battle.victory | `FOR_EACH` + `GRANT_XP` | Awards exp to survivors |
| main.lua:1375 | Post-battle heal (Mending) | battle.victory | `TRAIT_HEAL` | Heals based on POST_BATTLE_HEAL trait |
| engine/session.lua:103 | Level-up HP refill | battle.victory | `IF` + `HEAL` (or automated via GRANT_XP) | Refills HP to max when leveling up |
| **battle.defeat** | | | | |
| main.lua:1383 | Defeat reset | battle.defeat | `SCENE_EVENT` | Switches scene to title, resets GameSession, and initial party |
| **battle.escaped** | | | | |
| main.lua:1389 | Escaped map transition | battle.escaped | `SCENE_EVENT` | Transitions back to map upon successful flee |
| **Other Mechanics** | | | | |
| engine/session.lua:95 | Level-up calculation | battle.victory / exploration.step | n/a (handled within `GRANT_XP` logic) | Checks if exp >= needed and increments level |
| engine/battle.lua:87 | Spell MP cost | battle.round_start | `IF` + `DRAIN_MP` | Subtracts MP when casting spell |
| engine/effects.lua:163 | Inn MP heal | exploration.interact | `RESTORE_MP` | Recovers shared MP pool (pub drinks) |
