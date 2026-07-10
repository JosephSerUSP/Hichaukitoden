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

AUDIO (discuss, don't implement yet):
Sound needs to be tackled eventually. There's existing music produced for an earlier
iteration of the game, meant to be played as plain square-wave tones via the standard Web
Audio API — simple .midi-style files that worked surprisingly well for what they were.
However, that timbre doesn't fit the aesthetic tone of the current iteration of the game.
Want a discussion of the possible paths/implementations before committing to one — see
`audio-design-options.md`.
