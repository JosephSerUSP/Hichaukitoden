# Stage: events

Write the campaign's narrative: replace the town map's placeholder NPC
scripts with full conversations, and fill commonEvents.json with any SHARED
events (an event is only "common" if 2+ places call it). This is where the
walkthrough's story actually gets implemented -- quest offers/completions,
gossip, the ending.

## Outline

{{OUTLINE}}

## Command language registry (the ONLY commands you may emit; params are
`key:type`; interactive commands may appear in map/common scripts)

{{COMMANDS}}

## Id manifest

{{MANIFEST}}

## Schema by example (an event script is a JSON array of commands; study the
sample event's TEXT/CHOICE shape -- options carry nested "commands" arrays)

{{SAMPLES}}

## Deliverable

ONE JSON object: `{ "maps.json": [ ...complete array, town events' scripts
now filled... ], "commonEvents.json": { ... } }`

Rules (structure conventions this engine expects):
- Hub menus: a `LABEL` command at the menu point; loop back with
  `JUMP_TO_LABEL` (same event only -- labels do NOT cross CALL_COMMON_EVENT).
- End a conversation by letting the script (or a CHOICE option's empty
  commands list) run off the end -- there is no explicit close command.
- Quest flow: `QUEST_OFFER {questId}` / `QUEST_COMPLETE {questId}`; gate
  branches with CONDITIONAL_BRANCH conditions `questStatus:<id>:active`,
  `questStatus:<id>:completed`, `flag:<name>`, `hasItem:<itemId>`, or a
  formula. Set story flags with SET_FLAG.
- Shops open with `OPEN_SHOP {shopId}` using manifest shop ids.
- State-dependent NPCs may use event `pages`:
  `"pages": [ { "condition": "...", "script": [...] } ]` -- last matching
  page wins, absent fields inherit the base event.
- TEXT uses `"speaker"` for named lines ("\\eventName" echoes the event's
  name); speakerless TEXT reads as narration.
- Dialogue is revealed in a small box: keep individual TEXT bodies under
  ~200 characters; split longer speeches into consecutive TEXT commands.
- Do NOT touch dungeon-floor placeholder events beyond what the walkthrough
  demands; the outline's story beats live in the town cast and quest hooks.
