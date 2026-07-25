# Engine State (generated -- do not edit)

Produced by `lovec . engine-state` (`engine/engine_state.lua`) and gated
by G4 (`tools/golden/check-state.ps1`), which regenerates this file and
fails on any diff. This is the authority on **what exists**; `docs/SPEC.md`
is the authority on **why and how**. Hand edits will be overwritten and
will fail G4.

Campaign root: `data`

## Scenes

Every scene must declare a draw mode (SPEC Sec.1.2); G1 enforces it.

| id | kind | draw | world | windows | hooks |
|---|---|---|---|---|---|
| `1` | menu | windows | - | 0 | 8 |
| `battle` | battle | windows | - | 5 | 7 |
| `controls` | menu | windows | - | 3 | 6 |
| `dialogue` | menu | windows | - | 4 | 1 |
| `game_over` | menu | windows | - | 3 | 3 |
| `items` | menu | windows | - | 4 | 8 |
| `map` | map | world | map | 0 | 7 |
| `options` | menu | windows | - | 4 | 5 |
| `quest_log` | menu | windows | - | 4 | 4 |
| `reserve` | menu | windows | - | 5 | 8 |
| `ritual` | menu | windows | - | 15 | 8 |
| `save_menu` | menu | windows | - | 4 | 5 |
| `shop` | menu | windows | - | 4 | 7 |
| `status` | menu | windows | - | 11 | 7 |
| `title` | menu | windows | - | 6 | 5 |

## Registry (data/engine.json)

- commands: **66**
- effect types: **12**
- trait codes: **21**
- meta keys: **7** (tier, density, potency, craftElement, craftKind, detect, detectLevel)

### Registry entries with no implementation

A registry id counts as implemented when Lua source references it OR a
flow/scene consumes it (behavior can live in data). The two lists below
are what's left:

- **assigned** -- content (a passive, item, actor...) references it, but
  nothing consumes it. **These lie to the player**: the passive shows up
  in-game and does nothing. `ON_PERMADEATH` sat in this bucket for months.
- **unused** -- declared in the registry and never referenced anywhere.
  Harmless, but dead weight the editor still offers as a choice.

- trait codes (assigned): none
- trait codes (unused): none
- effect types (assigned): none
- effect types (unused): none
- commands (assigned): none
- commands (unused): none

## Flow phases (data/flows.json)

- `_test`: `scene`, `script_escape`
- `battle`: `battle_start`, `defeat`, `encounter_check`, `escaped`, `flee_attempt`, `round_end`, `victory`
- `exploration`: `step`
- `quest`: `complete`, `offer`

## Content inventory

- actors: **22** (4 summonable-from-start, 6 with promotion paths)
- item-creation disciplines across the roster: alchemyx22
- items: **46** (consumablex12, equipmentx23, junkx7, questx4)
- skills: **15**, passives: **20**, states: **7**, roles: **13**, elements: **7**
- maps: **7**, common events: **11**, shops: **6**, quests: **4**
- animations: **27**, tilesets: **9**

## Notes for agents

- This file is generated. To change it, change the engine or the data.
- `docs/SPEC.md` is the living spec; `docs/archive/**` is frozen history
  and never authoritative.
- Design docs under `docs/design/` and `docs/game design/` describe
  intent. Where they state implementation status, trust THIS file.

