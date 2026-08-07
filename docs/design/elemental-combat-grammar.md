# Elemental Combat Grammar

*Design intent, 07.08.2026. Not a status document — see `docs/ENGINE-STATE.md`
for what exists, `docs/SPEC.md` for implemented engine rules, and
`docs/design/skill-costs.md` for the current Charges / Overcast / Cooldown
economy.*

## 1. Purpose

The elemental system should not be five copies of one RPG spell ladder with
different colors. Each element should have a recognizable way of solving
combat problems, including meaningful things it **does not** normally do.

The goal is **structural symmetry without effect symmetry**.

A useful elemental grammar asks the same broad questions of every color:

- how does it deal ordinary damage?
- what does serious offensive commitment look like?
- what does it do when several battlers matter at once?
- how does it answer lost HP?
- how does it sustain advantage over several rounds?
- how does it survive future damage?
- how does it interfere with the enemy plan?
- what rule is it allowed to bend when it receives a major spell?

The answers need not be equivalent. A blank can be a boundary rather than a
hole.

The reusable elemental vocabulary is also distinct from creature techniques
and system verbs. `attack`, `defend`, `flee`, Phoenix's rebirth, Titania's
`Fairy Court`, Nurse's `Field Surgery`, Cockatrice's `Petrifying Gaze`, etc. do
not require five-color counterparts merely because they live in `skills`.

## 2. Five-color doctrine

| Element | Core idea | Time / resource attitude | Characteristic privilege |
|---|---|---|---|
| **Red** | Overdrive / commitment | **Now** — spend aggressively | Converts HP, safety and future efficiency into immediate force; can exceed ordinary HP limits |
| **Blue** | Precision / flow / conservation | **Optimize what exists** | Stable outcomes, redistribution, magical protection, efficient access to shared magical resources |
| **Green** | Nature / growth / compounding | **Later** — accumulate and mature | Max-HP growth, regeneration, long-fight engines, efficient wind and volatile thunder |
| **White** | Correction / miracle | **At the critical moment** | Best rescue, cleansing and categorical protection; very little but very authoritative offense |
| **Black** | Exploitation / intervention | **When opportunity appears** | Drain, bodily manipulation, status, execution, surgery and dangerous exchanges |

A useful shorthand for healing is:

- **Red:** vitality forced past safe limits.
- **Blue:** recovery distributed where it is needed.
- **Green:** life cultivated, expanded and circulated.
- **White:** damage corrected and the proper state restored.
- **Black:** health stolen, manipulated or technically repaired.

Every color may therefore be able to answer "my party is hurt" without making
White merely "the healer".

## 3. Shared functional domains

`CORE` means the shared spell vocabulary should represent the domain clearly.
`MUTATION` means the color participates, but the ordinary version would be the
wrong fantasy. `REFUSAL` means absence is useful identity; creature signatures
may still violate it.

| Domain | Red | Blue | Green | White | Black |
|---|---|---|---|---|---|
| **Foundation offense** | **CORE** — direct immediate fire | **CORE** — concentrated, stable single-target magic | **CORE / MUTATION** — efficient wind, not a full conventional ladder | **REFUSAL** — no cheap generic holy bolt | **MUTATION** — offense commonly carries theft, status or bodily consequence |
| **Escalated offense** | **CORE** — one large destructive result | **CORE** — precise concentration | **MUTATION** — growth, earth or thunder can occupy this space instead of another nuke | **CORE, SCARCE** — rare divine violence is extremely strong | **CORE** — dangerous damage with costs, conditions or consequence |
| **Formation-scale action** | **CORE** — straightforward AoE destruction | **CORE / MUTATION** — redistribution, especially group healing | **CORE** — diffuse control, life effects and random thunder | **MUTATION** — party correction and protection | **CORE** — mass debilitation more often than clean blast damage |
| **Immediate recovery** | **MUTATION** — scarce burst capable of Overheal | **CORE** — best immediate distributed healing | **CORE** — maintenance strongest before crisis | **CORE** — best emergency / corrective healing | **MUTATION** — surgery or stolen HP |
| **Sustain** | **MUTATION** — short violent regeneration tied to aggression | **SECONDARY** — Blue solves flow more than organic persistence | **CORE** — strongest long-fight regeneration and compounding | **CORE** — blessings, often costly / scarce | **CORE** — sustain by extraction |
| **Fortification** | **MUTATION** — exceed ordinary HP rather than safely brace | **CORE** — magical barriers and redirection | **CORE** — physical barriers, Max-HP growth, body / earth | **CORE** — wards and categorical protection | **REFUSAL** — weaken or exploit the enemy instead of cleanly fortifying |
| **Control** | **REFUSAL / SELF-MUTATION** — pressure, Berserk, forced commitment | **CORE** — tempo, flow and certainty control | **CORE** — broad, natural and often gradual control | **MUTATION** — cleanse / prevent control; hostile control is rare or signature | **CORE++** — widest hostile status vocabulary |
| **Exceptional privilege** | Overdrive / rebirth | Perfect concentration or distribution | Overgrowth / abundance / compounding | Miracle / Holy | Execution / forbidden exchange |

## 4. Red: Fire and Overdrive

### 4.1 Fire Lance is the basic Red attack

The basic Red spell is **Fire Lance**, as an intentional Valkyrie Profile
reference.

Fire Lance resolves as **two independent fire damage instances**. The two hits
are not one damage result displayed twice. Each can interact separately with:

- barriers;
- critical rolls;
- per-hit reactions;
- any later mechanic that explicitly consumes or responds to damage instances.

This makes Fire Lance naturally good at breaking one-instance barriers: the
first hit may consume the barrier and the second may still damage the target.

This must remain a **Fire Lance property**, not a rule that Fire is the
multi-hit school.

### 4.2 Other major Fire should usually be one large hit

Red's broader offensive fantasy is:

> "Wow, that's a nuke."

Flare, Eruption and future high-end Fire should generally produce one large
result per target rather than a shower of small hits. The contrast preserves
Fire Lance's identity and keeps hit count tactically meaningful.

### 4.3 Red recovery

Red does not normally receive clean, safe Cure-style healing.

Its recovery space includes:

- scarce burst healing that may **Overheal** above Max HP;
- regeneration coupled to ATK / MAT or other aggressive momentum;
- HP costs, risk or other commitment where appropriate;
- comeback / rebirth effects as rare or signature privileges.

The important boundary is:

> **Red does not heal safely.**

## 5. Blue: Ice, Water, barriers and conservation

Blue's underlying rule is:

> **Concentrate, distribute, redirect or conserve.**

### 5.1 Ice is stability

**Ice Shard** should be an immediately satisfying single-target spell with very
low damage variance. If Thunder is allowed wild results, Ice should feel close
to deterministic.

Its economy may be deliberately paradoxical:

- relatively **few natural Charges**;
- relatively **cheap Overcast** compared with similarly serious magic.

This gives Ice a limited local supply while making it unusually efficient at
drawing on the Summoner's shared MP once that supply is exhausted.

Exact numbers belong in balance work, not this doctrine.

### 5.2 Water is distribution

**Healing Rain** belongs to Blue and should be the best broadly available
**immediate group heal** when several allies have taken meaningful damage.

This does not make Blue the best healer in every situation:

- White should be better at rescuing one ally in crisis and correcting harmful
  states;
- Green should be better at maintaining and expanding health over long fights;
- Red may produce exceptional Overheal at a cost or with severe scarcity.

### 5.3 Blue and MP

Blue is the element most naturally allowed to interface with the Summoner's
shared MP, but it must not become a mandatory free-MP battery.

The preferred design direction is **conservation and redistribution**, not
creating expedition resource from nothing. Candidate spaces include:

- converting local magical capacity into shared capacity;
- especially efficient Overcast on selected Blue spells;
- refunds or recovery tied to successful magical interception;
- moving magical resources to where they are actually needed.

Any concrete MP-restoration skill must respect the strategic role established
in `skill-costs.md`: MP prices the expedition and Overcast is allowed to make a
fight shorten the road home.

### 5.4 Magical barriers

Blue is the natural home of **Magic Barrier** effects. Barrier mechanics are a
general combat-state resource, not a Blue-only engine subsystem; see
`combat-state-resources.md`.

## 6. Green: nature has several tempos

Green should be strong in long fights, but **Green is not uniformly slow**.
Its natural expressions have deliberately different time profiles.

### 6.1 Earth / Wood / Life: growth and compounding

This family owns:

- temporary Max-HP increases;
- regeneration;
- healing that is strongest while the target is still reasonably healthy;
- physical barriers / bark / stone / body fortification;
- effects that improve as a fight continues;
- effects that mature while unused;
- Leech-style persistent life transfer.

Green's promise is:

> **If you let it establish itself, the battle increasingly belongs to Green.**

Ramping effects must still respect Charges. A ramping spell must be worth its
first charge; the player should not spend two scarce charges merely to reach
another color's ordinary baseline. If a spell asks the player to "invest"
charges in one fight, the payoff should be correspondingly strong.

Two distinct growth grammars are useful:

1. **Cultivation:** the effect becomes stronger each time it is used in the
   current battle.
2. **Ripening:** the effect becomes stronger the longer the player waits before
   using it again, then resets when harvested.

Neither should be applied to every Green spell. Growth that requires constant
bookkeeping would undermine readability.

### 6.2 Wind: lightness, agility and low cost

Wind should not need a ramp mechanic merely because Green likes long fights.

**Wind Blade** is better understood as:

> **the spell you almost never regret casting.**

Wind's vocabulary favors:

- plentiful Charges;
- low cost;
- speed / initiative;
- moderate but efficient damage;
- low opportunity cost.

This keeps Wind distinct from both slow Earth/Wood growth and volatile Thunder.

### 6.3 Thunder: variance and immediate volatility

Thunder is Green's immediate, unpredictable expression.

It favors:

- high damage variance;
- independent strikes;
- random targets;
- occasionally disappointing and occasionally frightening results.

This is deliberately opposed to Ice's stability.

A representative spell is **Thunderstorm**:

> Resolve `X` independent Thunder strikes against random enemy targets. Targets
> may repeat.

Because each strike is a real damage instance, Thunderstorm may shred a
barrier if several bolts happen to hit the protected target — or fail to touch
it at all. That is useful emergent counterplay rather than an authored
"anti-barrier" bonus.

### 6.4 Green life transfer: Leech and Whisper Wind

Green and Black may both drain life, but for different reasons.

**Black Drain:** immediate, concentrated appropriation. Hurt one target and
receive the stolen HP now.

**Green Leech:** establish a persistent biological relationship. Life transfers
over time; the value is in continued circulation and long-fight pressure.

**Whisper Wind:** reference the Final Fantasy / Sylph ability correctly — drain
HP from one enemy and distribute that stolen life across the whole party. Its
identity should remain **modest, broad sustain**, not a premium party heal.

A useful distinction is:

> **Black asks who owns the HP. Green asks where the HP is flowing.**

## 7. White: correction and scarce violence

White should have the **least offensive vocabulary**, not weak offense.

The reusable school should not need a cheap Holy equivalent of every Red, Blue
or Green attack rung. When White does receive offensive magic, it should feel
like **Divine Ray / Holy**: scarce, expensive or otherwise privileged, and
conspicuously powerful even against neutral targets.

White owns:

- emergency single-target recovery;
- cleansing;
- restoration toward a proper state;
- long blessings;
- categorical protection;
- **Status Ward** as the natural barrier family for hostile conditions.

A useful doctrine is:

> **White's offense is scarce but authoritative.**

## 8. Black: exploitation and intervention

Black should not collapse into "dark damage plus debuffs." Its stronger
identity is **intervention into bodies and resources**.

Its vocabulary includes:

- Drain and other immediate extraction;
- Poison, Sleep, Charm, Petrify, Weaken and other hostile statuses;
- self-HP costs and risky exchanges;
- execution / finishers;
- surgery and technical healing;
- damage with consequences or riders.

Nurse is an important proof that Black healing does not have to be vampiric:
`Field Surgery` can remain a cooldown-based technical heal whose economy is
fundamentally different from charged restorative magic.

## 9. Barrier color allocation

The shared barrier grammar is generic, but the most intuitive elemental homes
are:

| Color | Defensive family |
|---|---|
| **Blue** | Magical barriers / magical-force interception |
| **Green** | Physical barriers / bark, stone, body |
| **White** | Status wards / categorical preservation |

These are not required to be identical one-stack full-negation effects. The
barrier system intentionally allows different stack counts, strengths,
lifetimes and refresh rules. See `combat-state-resources.md`.

Red generally fortifies by exceeding safe vitality rather than cleanly
blocking. Black generally survives by weakening, disabling, draining or
exploiting rather than by safe barrier maintenance.

## 10. Basic RGB spell identity

The primary basic attacks should teach their colors immediately:

| Spell | Identity |
|---|---|
| **Fire Lance** | Two independent hits; immediate commitment; naturally cracks a one-instance barrier |
| **Ice Shard** | Hard, extremely stable single-target magic; lower natural Charges can coexist with cheap Overcast |
| **Wind Blade** | Light, efficient, plentiful, low-opportunity-cost offense |

Thunder is intentionally not represented by Wind Blade. Thunder owns Green's
volatile burst space instead.

## 11. Multi-element affinity is unresolved

The current affinity implementation cross-multiplies the acting creature's own
elements against the target's elements and separately applies the skill's
element against the target. This can produce mathematically tidy but
player-hostile near-neutral values: a creature with both favorable and
unfavorable relationships may land at something like `1.035x` rather than a
clean, readable neutral result.

Several conclusions are already decided:

- creatures may have **two or three elements**, including RGB creatures;
- repeated elements should be allowed to matter;
- RGB should **not** receive a bespoke "complete tricolor" rule merely to fix
  the current math;
- replacing innate-element interaction wholesale with a simple
  skill-resonance bonus is also **not adopted**;
- one general rule should accommodate mono-, dual-, repeated- and
  three-element creatures;
- outcomes should be readable enough that the player can anticipate them from
  the displayed element icons;
- awkward values that are "almost neutral but not neutral" are a design smell.

A promising direction is to resolve elemental relationships into a **signed
score first** — favorable pairings contribute positive values, unfavorable
pairings negative values — and only then convert the aggregate score into a
single multiplier. This is elegant because contrary relationships can cancel
before multiplication creates numerical residue.

The exact aggregation rule, weighting of repeated elements, skill-vs-user
layers and final multiplier curve remain open design work. Do not implement a
new affinity formula from this document alone.

## 12. Authoring rules

1. **Do not fill every blank.** Ask whether a missing spell is a hole or a
   boundary.
2. **Do not make every skill carry the whole color identity.** Fire Lance may
   simply hit twice; Ice Shard may simply be very stable; complexity should
   emerge from interactions.
3. **Do not make signatures prove a school-wide rule.** Phoenix rebirth,
   Titania's Fairy Court, Kappa's Aqua Dish, Nurse's Field Surgery and similar
   creature vocabulary can cross boundaries without rewriting the color
   doctrine.
4. **Do not derive Charges from potency.** `skill-costs.md` remains authoritative
   for magic economy. Elemental tendencies can influence authored Charge and
   Overcast shapes, but power and economy remain separate tuning knobs.
5. **Do not require fake tier symmetry.** Add explicit skill tiers only if tier
   becomes semantic authored data, not merely a sorting convenience.
6. **Prefer simple skills with strong interactions.** Hit count, barrier shape,
   variance, healing distribution and resource timing should create tactical
   complexity without paragraphs of bespoke rules on every row.

## 13. Next design step

Before broad numeric rebalance, turn this grammar into a proposed shared spell
roster:

- classify existing reusable skills versus signatures / system verbs;
- identify which existing rows still fit the doctrine;
- design candidate rows for the genuine open spaces;
- assign rough relative roles and economy shapes without final potency tuning;
- implement new combat primitives (barriers, Overheal / temporary Max HP,
  inspection) separately enough that balance changes can be diagnosed.

The doctrine should survive later number changes. If a future balance pass can
change potency, Charges or Overcast costs without requiring this document to be
rewritten, it is doing its job.
