HUMAN FEEDBACK (10.07.2026, via scheduled orchestration task)

EDITOR / VISUAL SCENE AUTHORING:
1. We want a visual editor for Scenes: render windows on a game-canvas, right-click them to
   edit properties, add and remove windows, edit their behavior, etc. This should work
   for every type of scene, including Map — though map rendering is more complex and can't
   really be translated into events as directly as window-based scenes can.

EVENTING READABILITY (small changes, big cumulative effect on the Scenes/Flows editor):
1. Color-code event types in the command list. Comments are already color-coded green;
   variables should be red, media commands teal, etc. — a consistent category→color scheme.
2. Color even and odd lines differently in the event editor (row striping) for readability.
3. Remove the pencil (✏️) and X (❌) buttons from command rows. Those actions belong in a
   right-click context menu, plus keyboard equivalents: Space to edit, Delete to delete.
   Also add: Ctrl+C / Ctrl+V to copy/paste events, and selecting multiple events with
   arrow keys + Shift (range select).
4. Beyond clearing custom event/hook data back to empty, it should be possible to load from
   a template or reset to default behavior instead.
5. The crafting scene is one of what will eventually be several preset custom scenes a
   developer can choose from when creating a new scene (D13 made crafting a plain,
   nothing-hardcoded "extra" scene — it's the first sample for this gallery).

HUMAN FEEDBACK (10.07.2026, addendum):
6. Change Control Variable to Control Variables: one event command that can set either one
   or several variables at once.

HUMAN FEEDBACK (10.07.2026, post-playtest batch — battle/system):
7. Enemy flash-when-targeted is great, but must become configurable — and it is the seed of
   a future ANIMATIONS TAB in the editor, similar to RPG Maker's, with one key difference:
   besides animations assigned to skills, SYSTEM animations must be directly editable too —
   the damage flash, the damage shake, the death animation, etc. Everything battler-related
   that animates (and perhaps screen/map-related too) should live in that future animation
   editor. (See future-animation-system.md; likely an overhaul-6 flagship.)
8. IMMEDIATE: smallBattlers (party grid / summoner sprites) must flash AND shake when taking
   damage. When dead, they must NOT play a death animation — tint them dark purple/greyish,
   stop animating, show only the first frame. (Brief E8.)
9. Game-overing doesn't really work well right now; we need a dedicated Game Over scene.
   (Brief E9.)
10. The title screen needs a dedicated "New Game / Continue / Exit" selector. (Brief E10.)
11. Save data will eventually need handling, including Save and Load scenes. (Recorded as
    future work — E10's Continue option must degrade gracefully until it exists.)
12. No dedicated TRAIT_HEAL command — the HEAL command should be used to apply trait
    healing instead. (Brief E11; command-consolidation lesson, same as CALC_CRAFT_YIELD.)

AUDIO (discuss, don't implement yet):
Sound needs to be tackled eventually. There's existing music produced for an earlier
iteration of the game, meant to be played as plain square-wave tones via the standard Web
Audio API — simple .midi-style files that worked surprisingly well for what they were.
However, that timbre doesn't fit the aesthetic tone of the current iteration of the game.
Want a discussion of the possible paths/implementations before committing to one — see
`audio-design-options.md`.
