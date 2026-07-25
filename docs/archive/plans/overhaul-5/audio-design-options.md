# Audio — decision memo (not a brief)

**Status:** discussion only. Do not write a `PLAY_SOUND`/`PLAY_MUSIC` brief
until the owner picks a direction here. Overhaul-4 SPEC S9's rule stands:
`data/sounds.json` exists, is loaded, and is shipped to the editor, but
**nothing consumes it** — no `love.audio` anywhere in the engine — and that
must stay true until a brief lands with a real handler in the same commit as
the command registration. Stub handlers are explicitly forbidden; the
validator enforces every registered command has a real
`interpreter.isImplemented` handler, so a stub fails G1 by name, not by
accident.

## The starting material

There is existing music from an earlier iteration of the game: simple,
`.midi`-style compositions, originally intended to play as plain square-wave
tones via the standard Web Audio API. The owner's read: the *compositions*
"worked surprisingly well," but a plain square wave no longer fits this
iteration's aesthetic tone. That's the constraint to design around — this is
not "we have no music," it's "we have music whose timbre is wrong for where
the game is now visually/tonally."

## Path 1 — Runtime chiptune synthesis in `love.audio`

Parse the existing MIDI-like note data at load time; drive a square/pulse
oscillator (or a small set of waveforms — square, triangle, noise) through
`love.audio.newQueueableSource`, generating samples per-frame with an
envelope (attack/decay/sustain/release) per voice/channel.

- **Pros:** reuses the composed material as-is; tiny asset footprint (data,
  not audio files); trivially re-keyable/re-temp-able/proceduralizable at
  runtime (useful for e.g. a battle theme that layers in with intensity);
  fits a from-scratch "everything is data" philosophy this project already
  leans into.
- **Cons:** the exact problem the owner flagged — plain square-wave timbre
  reads as "NES/Game Boy chiptune," which is a specific, dated aesthetic that
  apparently no longer matches this game's current visual/tonal direction.
  A richer synth (multiple waveforms, simple FM, filters) could move the
  needle, but now you're building a small synthesizer engine as a side
  project inside a JRPG engine — real scope, real ongoing maintenance.

## Path 2 — Sample-based playback

Pre-produce/render actual audio files (OGG/WAV), play them via
`love.audio.newSource` (streaming for music, static for short SFX). Engine
side is thin: a `sounds.json`-driven registry (`{key, path, loop, volume}`,
already half-designed by the existing dormant `sounds.json`), a small
`engine/audio.lua` wrapping source creation/pooling, and two commands
(`PLAY_MUSIC`/`STOP_MUSIC` for looping tracks, `PLAY_SOUND` for one-shots).

- **Pros:** full creative control over the actual sound — can be anything,
  including a *deliberately* chiptune-adjacent-but-richer palette, or
  something else entirely; this is how the large majority of RPG-Maker-style
  games actually do audio, so the engine-side lift is small and well-trodden;
  decouples "what does it sound like" (an art/production decision) from
  "does the engine support audio" (an engineering decision) — the engine
  work is nearly identical regardless of what the files sound like.
- **Cons:** the existing MIDI compositions aren't directly reusable as files
  — they'd need to be rendered/re-produced through *something* (see Path 4);
  larger asset footprint (shipped audio files vs. tiny note-data JSON); no
  runtime remixing (a looping track is a looping track, not a live-generated
  one) unless you also build crossfade/layering logic on top, which is
  additive complexity, not a blocker.

## Path 3 — Hybrid

Sample-based playback for authored theme/BGM tracks (where aesthetic control
matters most and is hardest to fake procedurally), plus a small runtime synth
for short, reactive elements — UI blips, battle stingers, procedurally
varied ambience layers — where a lightweight oscillator is genuinely cheaper
and more flexible than a sample bank of one-shots.

- **Pros:** aesthetic control where the owner explicitly cares (music), cheap
  reactivity where a synth voice is a natural fit (UI feedback).
- **Cons:** two playback paths to build and maintain instead of one; more
  surface area for the "which system does this sound belong to" question to
  recur per-asset. Reasonable only if Path 2 is adopted for music and a synth
  voice turns out to be noticeably cheaper for UI SFX than a handful of tiny
  sample files — likely not, given how small UI blip samples are. **Weak
  recommendation to fold this into Path 2 rather than build it.**

## Path 4 — Re-produce the existing compositions as samples (recommended)

Take the actual musical material already composed — the melodies, harmonies,
arrangements — and re-render it through a richer instrument palette (a
soundfont pass, a DAW re-production, or a commissioned re-arrangement) that
matches the current aesthetic, then ship the result as sample-based audio via
Path 2's engine plumbing. This is Path 2's asset pipeline with a specific,
deliberate answer to "where do the files come from": **keep the
compositions, discard only the square-wave timbre that no longer fits.**

- **Why this is the default recommendation:** it directly resolves the
  tension in the owner's framing — the music itself was good ("worked
  surprisingly well"), the *playback method* was the mismatch, not the
  material. Path 4 preserves the existing creative investment instead of
  starting from zero, while the engine-side lift is identical to (and no
  larger than) Path 2's — the smallest, most generic, most reusable option
  of the four. It also keeps the eventual brief small and well-scoped: one
  `sounds.json` schema, one `engine/audio.lua` module, two commands, real
  handlers from commit one.

## What the owner needs to decide before a brief gets written

1. **Path 2/4 vs. Path 1/3** — sample-based (recommended) vs. runtime-synth.
   This is mostly an aesthetic call, not a technical one; the engine cost
   difference favors 2/4.
2. **If 2/4: who re-produces the audio, and in what format** — this is a
   content/production question outside engine scope, but it gates asset
   delivery, which gates the brief's file-format assumptions (`sounds.json`
   entries need real paths to real files before `PLAY_SOUND` can be tested
   against anything).
3. **Scope for v1** — music only, or music + SFX in the same brief? SFX
   (menu blips, hit sounds, item-get jingles) is a much larger content list
   than a handful of BGM tracks; it's reasonable to land music first and SFX
   as a follow-up brief once the `sounds.json`/`audio.lua` plumbing exists.

Once these are answered, the brief itself is small: `data/sounds.json` schema
(already half-drafted, dormant), `engine/audio.lua`, `PLAY_MUSIC` /
`STOP_MUSIC` / `PLAY_SOUND` registered in `engine.json → commands` with real
`interpreter.lua` handlers in the same commit, editor support for picking a
sound in `tools/editor/js` (reuse the asset-picker pattern already used for
sprites/portraits — do not build a new picker primitive), and a golden-log
consideration: audio commands should emit a normalized event (e.g.
`{type: "play_music", key: ...}`) into the existing event stream so they're
UI-golden-checkable without needing actual sound output during `love . validate`.
