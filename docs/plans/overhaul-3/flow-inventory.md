# Hardcoded Flow Inventory

| file:line | behavior | proposed phase | proposed command(s) | notes |
|---|---|---|---|---|
| `main.lua:966-972` | Encounter chance roll (`math.random() < chance`) | `exploration.encounter_check` | `ROLL_ENCOUNTER` | Reads `encounterRate` from map data or config fallback. |
| `main.lua:614-630` | Random enemy count & weighted enemy selection | `battle.battle_start` | `SPAWN_ENEMIES` | Uses `minEnemies`, `maxEnemies` config and weighted lists. |
| `main.lua:641` | Emit battle encounter text | `battle.battle_start` | `EMIT_TEXT` | Uses `battle.encounter` localized term. |
| `engine/battle.lua:115-125` | Flee chance roll including base & bonuses | `battle.flee_attempt` | `IF`, `SET_VAR` | Formula computes `baseFleeChance` + `FLEE_CHANCE_BONUS`. |
| `engine/battle.lua:126-127` | Flee success emission | `battle.flee_attempt` | `SCENE_EVENT` | Emits `flee_success` to break combat loop. |
| `engine/battle.lua:129-135` | Flee failure text and gold loss penalty | `battle.flee_attempt` | `EMIT_TEXT`, `IF`, `GAIN_GOLD` | Gold reduction random between min/max bounds. |
| `engine/battle.lua:244-254` | Regeneration tick & heal emission | `battle.round_end` | `STATE_TICKS` | Uses `regenRate` to heal up max HP. Part of general tick block. |
| `engine/battle.lua:255-271` | Poison tick, damage emission, and death check | `battle.round_end` | `STATE_TICKS` | Uses `poisonRate`. Emits `damage` and potentially `death`. |
| `engine/battle.lua:273-288` | State duration decay and removal emission | `battle.round_end` | `STATE_TICKS` | Decays state duration and removes if 0. |
| `engine/battle.lua:291-306` | MP drain for active summons | `battle.round_end` | `FOR_EACH`, `DRAIN_MP` | Applies `mpd` stat to reduce global session MP. |
| `engine/battle.lua:307-325` | MP exhaustion damage and text emission on 0 MP | `battle.round_end` | `IF`, `FOR_EACH`, `DAMAGE`, `EMIT_TEXT` | Progression damage if party is at 0 MP. |
| `main.lua:1368-1369` | Victory random gold gain | `battle.victory` | `GAIN_GOLD` | Uses `victoryGoldMin` and `victoryGoldMax` config. |
| `main.lua:1374` | Grant victory XP to survivors | `battle.victory` | `FOR_EACH`, `GRANT_XP` | Driven by `victoryExp`. |
| `engine/session.lua:90-105` | Level-up logic and max HP refill | `battle.victory` | `GRANT_XP` internal | Handled by `gainExp` natively, refilling maxHp on level-up. |
| `main.lua:1375-1378` | POST_BATTLE_HEAL trait regen | `battle.victory` | `FOR_EACH`, `TRAIT_HEAL` | Checks POST_BATTLE_HEAL trait rate. |
| `main.lua:789-790` | Victory text emission | `battle.victory` | `EMIT_TEXT` | Uses `battle.victory_full` localized term. |
| `main.lua:1383-1387` | Transition to title and re-initialize session/party | `battle.defeat` | `SCENE_EVENT` | Hard reset when summoner/party dies. |
| `main.lua:791-792` | Defeat text emission | `battle.defeat` | `EMIT_TEXT` | Uses `battle.defeat_full` localized term. |
| `main.lua:1389-1392` | Transition map after successful escape | `battle.escaped` | `SCENE_EVENT` | Uses `battleEscaped` flag to return to map. |
| `main.lua:793-795` | Flee success text emission | `battle.escaped` | `EMIT_TEXT` | Uses `battle.flee_success` localized term. |
| `main.lua:503-513` | GIVE_ITEM path (random loot roll, inventory addition, text) | `exploration.treasure` | `GIVE_ITEM` / `GIVE_ITEM_ID` | `GIVE_ITEM` macro command that handles all these pieces. |
