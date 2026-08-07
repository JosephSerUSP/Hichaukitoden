# UI Text Style

This document defines the default writing and presentation rules for Second Rite's game UI. The goal is not minimal text at any cost. It is to make every line earn its space and to keep the same visual signals meaningful across scenes.

## 1. Action prompts use abstract actions

Menus describe the game's actions, not the player's keyboard.

Use:

- `[Confirm] Recruit`
- `[Cancel] Slots`
- `[Confirm] Placement`

Avoid:

- `Press Enter to confirm`
- `ESC to return`
- `Press Z / X`

Physical directions may be named only when the direction itself is meaningful and cannot be represented by Confirm or Cancel. Prefer letting spatial layout teach directional navigation rather than writing a miniature controls manual into every help bar.

Action prompts belong on one final line. Separate that line from explanatory copy with one blank line. Do not repeat the same actions in both the help bar and the panel body.

## 2. Text hierarchy

Each surface should normally contain, in order:

1. A short noun-phrase title.
2. The current object, choice, or consequence.
3. Optional secondary explanation.
4. One action row, when the surface owns actions.

Do not restate information already visible in the title, portrait, selected row, gauges, or neighbouring persistent panel.

Panel titles should be short nouns or noun phrases: `PLACEMENT`, `RESERVE`, `TERMS`, `TARGET`. Avoid sentence-like titles.

Labels and buttons use fragments without terminal punctuation. Explanatory copy uses complete sentences.

## 3. Spacing

- Use one blank line between distinct information groups.
- Never use repeated spaces to build columns. Use renderer columns, `formatRight`, gauges, or separate windows.
- Keep tutorials to three or four short lines per page. Split the tutorial instead of shrinking the panel or packing paragraphs into it.
- A help bar should normally contain only the current actions or one short contextual sentence, not both.
- Prefer unused space over duplicated explanation.

## 4. Color semantics

Color communicates role. It is not decorative emphasis.

- **White:** primary readable content and ordinary values.
- **Yellow:** current focus, selected choice, and panel-title emphasis.
- **Gray:** secondary context, unavailable choices, placeholders, and prior log text.
- **Green:** successful or beneficial change.
- **Blue:** MP, EXP, and explicitly informational resource values.
- **Red:** damage, HP costs, destructive consequences, and urgent warnings.

A value keeps its semantic color everywhere. Do not color ordinary prose blue or green merely to make it noticeable. Do not author raw per-scene colors when an existing renderer role already carries the meaning.

When several colors would compete in one line, color only the value or resource marker, not the whole sentence.

## 5. Terminology

Use these names consistently:

- `Active Party`: the four positioned battle slots.
- `Reserve`: the ordered nearby roster. Reserve order is not battle formation.
- `Town Storage`: long-term creature storage.
- `Confirm` and `Cancel`: abstract input actions.

Do not alternate between `formation`, `roster`, `bench`, and `party` for the same destination inside one flow.

## 6. Recruitment-specific application

Candidate review should show information once, using STATUS geometry where possible. Placement should answer only:

- Who is being recruited?
- Which destination is selected?
- Who moves as a consequence?

Active Party remains spatial because its positions matter. Reserve should read as a list because its positions do not carry battle meaning.

Confirmation repeats the final consequence, not the entire candidate profile or tutorial.

## 7. Review checklist

Before merging UI copy, verify:

- No physical Confirm/Cancel key names are exposed unnecessarily.
- No neighbouring windows repeat the same fact.
- The action row appears once.
- Tutorials fit at target resolution without compressed line spacing.
- Colors follow semantic roles.
- Blank lines separate groups rather than padding every line.
- Active Party and Reserve terminology is consistent.
