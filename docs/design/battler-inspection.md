# Battler Inspection and Combat-State Readability

*Design intent, 07.08.2026. Not a status document — see `docs/ENGINE-STATE.md`
for what exists and `docs/SPEC.md` for implemented engine rules. Related combat
state semantics live in `docs/design/combat-state-resources.md`.*

## 1. Purpose

Second Rite already has a battle **target window** that acts as a lightweight
battler inspector while the player is choosing a target. As combat state grows
beyond the current simple set of HP, elements and a few statuses, that existing
surface should become the foundation of a reliable inspection flow rather than
forcing the normal battle HUD to explain everything at once.

The central UI split is:

> **HUD / target window = recognition. Dedicated inspector = explanation.**

At the game's low internal resolution, trying to make every state self-explanatory
inside the ordinary battle layout would create more noise than information.

## 2. Existing target window remains useful

The current target window should continue to answer the immediate targeting
questions:

- who is selected?
- how much HP do they have?
- what are their visible elements?
- what major states / barriers / wards are active?

It should remain fast to scan and should not grow into a large permanent panel
that competes with the battle field.

This means extending the target window with compact state icons is desirable,
but using it as the only future inspection surface is not.

## 3. Preferred interaction: Select / Inspect opens a full battler view

While a battler is selected as a target, a dedicated **Select / Inspect** input
may open a larger information window or modal that occupies most of the screen.

The exact binding should use the game's normal input abstraction; "Select" here
means the player-facing inspect action, not a hard-coded keyboard key.

Desired interaction:

1. player enters target selection;
2. ordinary target window shows compact information;
3. player presses Select / Inspect;
4. a large battler-information view opens over the battle;
5. player can move through states / passives / details without the battle
   advancing;
6. Cancel / Back closes the inspector;
7. the original target and target-selection mode are preserved exactly.

The same interaction should work for allies and enemies wherever target
selection already reaches them.

A later shortcut may allow inspection outside a skill's target-selection flow,
but that is not required to establish the core surface.

## 4. Information hierarchy

### 4.1 Battle HUD

The ordinary battle HUD should stay sparse:

- battler identity / portrait / sprite as already appropriate;
- HP;
- immediate selection / cover feedback;
- small active-state icons where useful.

It should not become a scrolling character sheet.

### 4.2 Target window

The target window is the bridge between HUD and inspector. It should provide:

- name;
- current HP / Max HP in the compact form the battle already uses;
- element icons;
- compact state / barrier / ward icons;
- enough information to decide whether this is the intended target.

If space is tight, exact stack counts do not need to be rendered here.

### 4.3 Dedicated inspector

The full inspector should be authoritative for exact battle-relevant details.
It may show:

- name / identity;
- current HP and Max HP;
- Overheal when current HP exceeds Max HP;
- current elemental composition, including repeated / multiple elements where
  that is mechanically meaningful;
- every active visible state;
- exact stack counts;
- exact barrier / ward strength and consumption semantics;
- renewal / refresh effects that are currently maintaining a barrier;
- battle-relevant passives / traits where surfacing them helps explain the
  current state;
- source information where useful, e.g. a barrier came from `Arcane Shell` or
  a renewal state from a particular skill.

This is a battle inspector, not necessarily the complete out-of-battle status
screen. Information that cannot affect or explain the current battle does not
need to be duplicated here.

## 5. State list presentation

A useful layout is a navigable state list paired with one explanation area.

Conceptually:

```text
CERBERUS                     R  B
HP 130 / 100

STATES
> Magic Barrier x2
  Blood Heat
  Poison

Magic Barrier x2
Negates the next 2 magical damage instances.
Source: Arcane Shell
```

The exact geometry should be designed against the real internal resolution and
existing window system rather than this textual sketch.

The important behavior is:

- state names remain readable;
- exact stacks are available even if the HUD uses pips / a "many" marker;
- selecting a state explains what it **actually does**;
- the player can distinguish the consumable barrier from the separate effect
  that refreshes it.

## 6. Barrier / stack readability

The compact battle representation should use icons, with quantity represented
as cheaply as possible.

Preferred direction:

- one stack: icon alone;
- small quantities: tiny pips attached to / beside the icon;
- above a tested display threshold: a visually distinct **"many / full"** form
  rather than a tiny difficult decimal;
- inspector: always show the exact quantity numerically.

For example, the HUD may communicate:

```text
[shell icon + three pips]
```

or a saturated "many" shell icon, while inspection reports:

```text
Physical Barrier x7
Reduces the next 7 physical damage instances by 40%.
```

This explicitly permits **approximate quantity on the HUD and exact quantity in
inspection**.

At this resolution, that is preferable to making the player decode a 3x5 or 4x6
micro-font in every battle panel.

## 7. Quantity must not be confused with duration

If pips / a tiny counter mean **stack quantity**, the same visual language must
not sometimes mean turns remaining.

A renewing barrier is therefore better represented as two state concepts:

- **Magic Barrier** — the consumable stack resource;
- **Arcane Renewal** — the active effect that recreates / refreshes it.

The HUD can show two icons if both are important. The inspector can explain:

```text
Magic Barrier x1
Negates the next magical damage instance.

Arcane Renewal
Refreshes Magic Barrier to 1 stack at the start of each round.
```

Most state durations do not need a visible countdown in the compact HUD.

## 8. Mechanical descriptions should not drift

As combat states become more configurable, the inspector must not become a
second hand-maintained rules database.

Where practical, state explanation should be derived from semantic authored
facts.

For example, a barrier definition containing facts equivalent to:

```text
kind: magical_damage
stacks: 3
reduction: 0.40
```

should allow the UI to produce an explanation equivalent to:

> Reduces the next 3 magical damage instances by 40%.

Likewise, a full-negation state can produce:

> Negates the next magical damage instance.

Authored flavor text may still exist, but the exact mechanical explanation
should come from the same data the engine executes whenever derivation is
reasonable.

This follows the repository's broader design principle: author semantic facts,
then let runtime / editor / presentation construct appropriate views over them.

## 9. Passives and sources

Passives such as:

> Begin battle with one stack of Magic Barrier.

make source visibility useful, but the HUD should prioritize **current fact over
historical cause**.

During battle, the immediate information is:

> this battler has Magic Barrier x1.

The full inspector may additionally show:

> Source: Arcane Shell.

This keeps passive identity discoverable without forcing every source label into
the battle layout.

For effects with an ongoing producer, the producer itself is battle-relevant and
should appear as a state / effect, not merely as source metadata. A three-round
renewal that will recreate the barrier next round changes the player's decision
and deserves visibility.

## 10. Elements in inspection

The inspector should show a battler's actual authored / resolved element list,
including multiple and repeated elements, rather than flattening a creature into
one representative color.

This matters because the elemental-affinity redesign is intentionally still
open. Whatever final rule is selected must be explainable from information the
player can inspect.

The inspector should not attempt to display a complicated hidden multiplier
formula as the primary explanation. The desired end state is that the icons and
simple relationship language are sufficient to predict the important matchup.

If later design introduces explicit weakness / resistance summaries, they should
be derived from the canonical affinity rule rather than separately authored.

## 11. Hidden enemy information is an open design question

This document does **not** decide whether every enemy fact is known immediately.
Potential future policies include:

- all battle-relevant state / element information is always inspectable;
- intrinsic stats or passives may require discovery;
- lore / bestiary knowledge may reveal deeper detail over time.

Whatever policy is chosen, **active visible state must not become mysterious**.
If an enemy currently has `Magic Barrier x3`, the player needs a reliable route
to understand what that means.

Do not use information hiding to compensate for an inadequate state UI.

## 12. Relationship to the existing status scene

The battle inspector and out-of-battle status scene may eventually share
rendering primitives or semantic row builders, but they have different jobs.

The out-of-battle status scene can emphasize:

- long-term creature identity;
- equipment;
- learned skills;
- Charges;
- progression and persistent passives.

The battle inspector emphasizes:

- current HP / Overheal;
- current states;
- exact barrier stacks;
- active renewal / temporary effects;
- battle-relevant traits and elemental information.

Reuse should happen where semantics are genuinely shared; the battle inspector
should not merely embed the whole status scene.

## 13. Suggested implementation stages

This design can be staged without attempting the final inspector all at once.

### Stage 1 — compact state visibility

- extend the existing target window with active state / barrier icons;
- establish the icon + pip / "many" quantity language;
- preserve current target-selection behavior.

### Stage 2 — Select / Inspect modal

- open a large battler-info window from target selection;
- list active states with exact stack counts;
- show mechanical explanations;
- close back to the same selected target and battle-input state.

### Stage 3 — semantic explanations and sources

- derive barrier / ward explanation from executed semantic data;
- surface renewal producers and relevant passive sources;
- add Overheal / temporary-Max-HP explanation as those mechanics land.

The implementation issue may combine stages if the underlying window system
makes that safer, but the conceptual responsibilities should remain separate.

## 14. Open presentation questions

These should be answered with real-resolution prototypes rather than by doctrine
alone:

- exact number of pips shown before switching to the "many" symbol;
- whether pips sit beside, under or inside the state icon;
- the visual family for Magic Barrier, Physical Barrier and Status Ward;
- how many state rows fit comfortably in the dedicated inspector;
- whether the inspector uses one large window or a list + description split;
- whether source / passive information is always shown or available on a
  secondary page;
- whether the target window can fit state icons without reducing battle-field
  readability.

## 15. Design rules

1. **Do not make the HUD explain the whole combat system.** It only needs to
   support recognition and immediate decisions.
2. **Keep the existing target window useful.** Extend it rather than replacing
   a working targeting surface with a permanent giant inspector.
3. **Provide an exact inspection path.** Approximate pips are acceptable only
   because the exact state is one Select press away.
4. **Preserve target context.** Inspection is observational and must return to
   the same battle input state.
5. **Do not overload one micro-counter with multiple meanings.** Quantity and
   duration need different representations.
6. **Explain executed mechanics, not stale prose.** Derive state details from
   semantic data wherever feasible.
7. **Inspect both allies and enemies.** Shared Battler rules should be reflected
   in shared inspection behavior unless a deliberate information policy says
   otherwise.
