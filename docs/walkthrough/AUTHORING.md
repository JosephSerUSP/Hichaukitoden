# Authoring the walkthrough

The walkthrough is a campaign generator written in the voice of its future
player and with the precision of its future guide author.
We do not begin with a quest specification and then make the prose sound
exciting. We begin with a player anecdote worth remembering, then identify
everything the game must do to make it honest.

## The scenario-forging loop

For every episode, write these in order:

1. **The boast, regret or suspicion.** A sentence a player might actually post:
   “I thought Celina was skimming from me until I found out whose debt she was
   paying.”
2. **The attachment.** What person, creature, place, possession or theory must
   the player care about first?
3. **The decision.** What can the player do differently? A story beat without a
   decision can still work, but it cannot pretend to be a player anecdote.
4. **The price.** Time, supplies, opportunity, reputation, a changed
   relationship, or permanent loss.
5. **The witness.** Who or what in St. Maria notices? The return is where an
   expedition becomes part of the player's life.
6. **The echo.** How does the incident alter a later scene, strategy or
   interpretation?
7. **The content debt.** List the maps, events, commands, art, variables and
   tests required to make the prose true.

## A worked example

**Desired memory**

> “Moa was just the cheap bird Celina lent me. Then he started scratching at
> false walls before I knew what they were. I lost him on the third trip. Much
> later, the copy of my room had a little nest under the bed.”

**What must exist**

- Celina lends or cheaply offers a specific, nameable early creature.
- That creature has a modest exploration tell the player learns to value.
- A dangerous return creates a fair opportunity to sacrifice or lose it.
- The loss persists; replacing the species does not replace this individual.
- Celina and at least one other resident react to the absence.
- The borrowed-room scene branches on whether this Moa was lost.
- The nest contains something useful but emotionally ambiguous.

**What clicks**

The summon economy stops being an abstract roster system. The Labyrinth's
copying becomes personal, and the player cannot tell whether the nest is a
memorial, bait, or evidence that Moa survives somewhere below.

## Chapter anatomy

Every chapter must interleave:

- a section overview with boundaries, level and expected time;
- a complete numbered route;
- exhaustive enemies, stats, drops, treasure, shops and recruitment data;
- every branch, including outcomes the commentator did not choose;
- subjective player commentary and speculation, clearly labeled as one run;
- full composed game screenshots;
- a design ledger describing what must be built.

The commentator knows they are playing software. “On my first run I assumed
the bowl was flavor text” is appropriate. In-world travel-diary narration is
not.

Avoid omniscient plot summaries. “Yukio is secretly good” is inert.
“I distrusted Yukio because they counted my summons before asking my name” can
be staged, read multiple ways, and paid off later.

## Screenshot and art rules

- Use live game captures for claims marked **Playable**.
- Generated art can illustrate **Desired memories**, but label it honestly.
- Capture the instant a player understands the change, not merely a pretty
  establishing shot.
- Walkthrough screenshots show the complete **256×240 composed game frame**,
  including UI, dialogue window and overlays.
- Never use the underlying 256×144 CG or viewport crop as the guide screenshot.
  That is an asset-production format, not what the player sees.
- UI is evidence: party state, HP, MP, prompts and inventory often explain why
  a moment matters.
- Prefer one strong image from a batch over near-identical variations.

## Development audit

Every invented anecdote must eventually answer:

- Can the player cause or avoid it?
- Did the game teach enough for the consequence to feel fair?
- Does individual creature state survive saving, transfer and return?
- Does St. Maria react without every NPC repeating the same exposition?
- Is there a later echo, or is the event disposable?
- Can the moment be shown clearly in the actual raycaster and UI?
- Which part is playable today?

The walkthrough may invent future content; status labels and numeric tables may
not misrepresent present implementation. Proposed figures are marked
**Target**, verified figures **Current**.
