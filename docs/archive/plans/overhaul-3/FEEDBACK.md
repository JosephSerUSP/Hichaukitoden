# Human feedback — overhaul-3 play-test (2026-07-07)

Source: the owner's play-test after A7 + B1–B4 + A6 merged. Play-test debt
from the round (lose→title, flee→map, dungeon/town encounter gating, menu
ESC feel) was cleared successfully in the same session.

Each item lists where it was routed. "C-brief" = a new brief in
`docs/plans/overhaul-3/briefs/`.

## Editor

1. **Open-ended fields lack hot help** (e.g. Conditional Branch's condition,
   Damage's target). → *Folded into B5* (condition/battlerRef ⓘ popovers and
   tooltips, same pattern as the formula help).
2. **Modal content margins** — content should sit a few pixels off the modal
   edges, matching the OK/Apply/Cancel footer inset. → *Folded into B5.*
3. **Dedicated Event Command selector modal** that groups commands by
   category and context, RPG-Maker style (reference screenshot: the VX Ace
   "Event Commands" 3-tab dialog). → *C1 brief* (Jules-able; needs a
   `category` field in the command registry).
4. **Command consolidation** — GIVE_ITEM / GIVE_ITEM_ID / TAKE_ITEM should
   collapse into one CHANGE_ITEM command whose item param is a dropdown with
   a "random treasure" option and +/- count; same pattern elsewhere (DAMAGE/
   HEAL, DRAIN_MP/RESTORE_MP, ADD_STATE/REMOVE_STATE are candidates).
   → *C2 brief* (registry + engine handlers + data migration; keep legacy ids
   valid as aliases so existing data and the golden log stay green).
5. **Damage popup color and text are not configurable** — e.g. the "-"
   prefix on damage numbers is hardcoded. → *C3 brief* (move popup
   prefix/format/colors into system.json `battle_screen`, expose in the
   Damage Popup Settings modal).
6. **Future: visual UI editor for scenes.** → *Deferred*, no brief this
   round. Depends on battleLayout/menu layout being fully data-driven first
   (C4 is the groundwork).

## Game

1. **Legacy bugs preserved by the A5 conversions can now be squashed** —
   e.g. the duplicated MP drain. → *C5 brief*, routed **local-only**: fixing
   it changes the golden log, and the golden discipline (PLAYBOOK) requires a
   deliberate, reviewed regeneration — never a Jules task.
2. **Battle interface needs work** — battle commands overlap the Summoner
   status display, plus other minor layout issues. Owner deferred manual
   tweaks until the editor gives enough control. → *C4 brief*: finish
   data-driving the battle screen layout (hunt remaining hardcoded
   coordinates into `engine.json → battleLayout`, per BIBLE.md), then the
   owner tunes values in the editor rather than anyone hand-placing UI.

## Discovered during A8 (same session)

- The interactive interpreter path (`interpreter.compile` → GraphWalker) had
  no bridge for the new v1 commands, so registry commands with `map`/`common`
  contexts (TAKE_ITEM, GIVE_ITEM_ID, formula IF, …) silently no-op'd in map/
  common events, contradicting SPEC S1's promise. → *Fixed as A4b* (same
  session): contiguous non-interactive runs compile to a `RUN_IMMEDIATE`
  node executed through `interpreter.runImmediate`; emitted text events
  render as dialogue. The validator now also rejects interactive commands
  nested inside immediate-only blocks (IF/FOR_EACH) in any host.

# Feedback round 2 (2026-07-07, after Workbench shipped)

## Editor
1. Cancel/× on a modal must REVERT changes (currently kept). → *C6 brief.*
2. Actor Skills/Passives should be "+ Add" rows, not a full checklist. → *C7 brief.*
3. Missing image previews; actor sprite selection should reuse the Event
   asset selector + preview; Common Events too. → *C8 brief.*
4. Future: visual previews for all Scenes in the flow menu — likely by
   dynamically interpreting the Lua in JS for accuracy rather than
   rebuilding UI code in JavaScript. → *Deferred (research; groundwork C4/C9).*

## Game
1. Battle/crafting: working per owner play-test.
2. Item Creation should be a menu-accessible SCENE with its own Star Ocean
   -style interface; scenes get numeric IDs, are creatable in the editor,
   and their flows edited under Engine → Flows. → *C9 brief (flagship).*

## Round-2 addendum (Item Creation design doc)
The owner supplied a full Star Ocean 2-style design: dynamic parameter
crafting (no fixed recipes), stat-driven disciplines, yield formula
Y = floor((I1+I2)/2) + floor(alpha*S), bracket-based outcome pools,
roulette UI, element-conflict/stat-deficit failures, 5% anomaly crit.
→ *C10 brief* (typed meta system — registry-backed, the notetag analog)
is the prerequisite; *C9 REV 2* rewritten to this design. C4 landed
(Antigravity), G1/G2 re-verified locally.

# Round close (merged to main 2026-07-07, tag `overhaul-3`)

Gates green at merge: G1 validate, G2 golden byte-identical, G3 editor-console.
main had diverged by PR #5 (`\c[x]` + `\eventName`), which independently
reimplemented a feature this round already had in superseding form (structured
`speaker` field vs inlined `\eventName:` markup). All four conflicting files
resolved to the branch; the merged tree is byte-identical to the gated branch.

## Known limitations carried forward (NOT defects — scope lines)

1. **Scene UI/input is still hardcoded Lua.** `engine/scenes/crafting.lua` is
   570 lines, of which ~356 (62%) are `drawCraftingScene` (190) and
   `keypressedCraftingScene` (166). The *game logic* — yield formula, outcome
   brackets, disciplines — is already data in `scenes.json`. What remains
   hardcoded is drawing windows and moving a cursor. SPEC S9 explicitly scoped
   "full menu scripting (input loops as data)" out of this round.
2. **The editor's "Custom Scenes" tab is a paradigm mismatch,** not a bug (it
   renders cleanly, zero console errors). It is a property form sitting beside
   "Phase Flows", which is a command-list editor. The owner's instinct that
   Phase Flows "looks more like what I visualized scenes to be" is correct and
   is the architecture for the next round.
3. Battle likewise retains hardcoded presentation, though C4 data-drove its
   coordinates into `engine.json → battleLayout`.

All three are the subject of **overhaul-4 — Scenes as data** (`docs/plans/overhaul-4/SPEC.md`).
