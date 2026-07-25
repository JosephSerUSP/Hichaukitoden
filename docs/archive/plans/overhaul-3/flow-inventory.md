# Flow Inventory

| file:line | behavior | proposed phase | proposed command(s) | notes |
|---|---|---|---|---|
| `main.lua:610` | Roll encounter size and pick enemies from map data | `battle.encounter_check` | `SPAWN_ENEMIES` |  |
| `main.lua:641` | Emit 'A hostile group blocks your path!' | `battle.battle_start` | `EMIT_TEXT` |  |
| `engine/battle.lua:115` | Calculate flee chance + roll vs base (combat.baseFleeChance) and traits | `battle.flee_attempt` | `SET_VAR, FOR_EACH, IF` | Emits flee_success or text event |
| `engine/battle.lua:130` | Deduct gold (combat.goldLossOnFleeMin/Max) on failed flee | `battle.flee_attempt` | `GAIN_GOLD` | Negative amount |
| `main.lua:793` | Emit 'Escaped successfully!' text and switch to map scene | `battle.escaped` | `EMIT_TEXT, SCENE_EVENT` |  |
| `engine/battle.lua:242` | Process regen state (heal maxHp * combat.regenRate) | `battle.round_end` | `STATE_TICKS` | Emits heal event |
| `engine/battle.lua:252` | Process poison state (damage maxHp * combat.poisonRate) and death if hp <= 0 | `battle.round_end` | `STATE_TICKS` | Emits damage and death events |
| `engine/battle.lua:269` | Decay state duration and remove state if expired | `battle.round_end` | `STATE_TICKS` | Emits state_remove event |
| `engine/battle.lua:291` | MP drain per living monster based on 'mpd' trait | `battle.round_end` | `DRAIN_MP` | Skipped on safe maps |
| `engine/battle.lua:307` | MP exhaustion damage (combat.mpExhaustionDamage) when MP <= 0 | `battle.round_end` | `IF, FOR_EACH, DAMAGE, EMIT_TEXT` | Emits damage and text events |
| `main.lua:789` | Emit 'Victory! All hostile forces vanquished.' | `battle.victory` | `EMIT_TEXT` | Emitted via battle combat log |
| `main.lua:1368` | Gain random gold (combat.victoryGoldMin to Max) | `battle.victory` | `GAIN_GOLD` | Added to session.gold |
| `main.lua:1374` | Grant fixed XP (combat.victoryExp) to living party members | `battle.victory` | `FOR_EACH, GRANT_XP` |  |
| `engine/session.lua:103` | Refill HP when leveling up (triggered by XP gain) | `battle.victory` | `HEAL` | Currently hardcoded in Battler:gainExp; might be an engine-level rule or TRAIT_HEAL-like? |
| `main.lua:1375` | Apply POST_BATTLE_HEAL trait (passive mending / trick heal) | `battle.victory` | `FOR_EACH, TRAIT_HEAL` |  |
| `main.lua:1382` | Switch to map scene | `battle.victory` | `SCENE_EVENT` |  |
| `main.lua:791` | Emit 'Defeat! The party has fallen in battle...' | `battle.defeat` | `EMIT_TEXT` |  |
| `main.lua:1384` | Reset session and switch to title screen | `battle.defeat` | `SCENE_EVENT` |  |
| `engine/exploration.lua:227` | Drain MP (dungeonConf moveMpDrain) on non-safe maps | `exploration.step` | `IF, DRAIN_MP` | Triggered in tryMove |
| `main.lua:967` | Roll for random encounter (map encounterRate or combat.encounterChance) | `exploration.step` | `ROLL_ENCOUNTER` |  |
| `main.lua:357` | RECOVER_PARTY command: restore full MP, revive and heal all party members | `exploration.event` | `FOR_EACH, HEAL, REMOVE_STATE, RESTORE_MP` | Legacy code conversion candidate |
| `main.lua:493` | DESCEND_FLOOR command: increase dungeon floor, clamped to dungeon.maxFloor | `exploration.event` | `SET_VAR, IF, SCENE_EVENT` | Legacy code conversion candidate |
| `main.lua:504` | GIVE_ITEM_ACTION: pick random item from map.treasures (or dungeon.defaultLoot), add to inventory, show found text | `exploration.event` | `GIVE_ITEM` | Referred to as GIVE_ITEM in spec. S1 registry. |
