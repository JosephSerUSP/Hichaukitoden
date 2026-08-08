# Unit, Actor, Battler, and symbolic Unit identity

Status: architectural contract for issue #147.

The core rule is:

> **Unit is authored identity. Battler is combat state. Actor is persistent
> player-owned identity. Enemy/ally is a runtime relationship.**

This vocabulary describes responsibilities. It does not require separate Actor
and Enemy databases, an Enemy subclass, or allegiance on authored creature
definitions.

## 1. Unit

A **Unit** is an authored combat-capable definition.

Examples include `pixie`, `skeleton`, `moa`, and `red_dragon`.
Unit data owns facts shared by occurrences of that definition:

- canonical symbolic resource ID
- base and growth parameters
- elements
- definition-granted skills and passives
- art and presentation references
- authored evolution and transformation rules
- recruitment eligibility and other definition-level metadata

A Unit has no intrinsic battle allegiance. The same Unit may produce a transient
opponent Battler or a persistent player-owned creature.

`data/actors.json` remains the legacy physical filename for this Unit catalog.
Renaming or fragmenting that file is a separate storage migration.

## 2. Battler

A **Battler** is the runtime abstraction for something participating in combat.
It owns or exposes current combat state such as HP, states, resolved parameters,
skills, passives, resources, and formation position.

Second Rite intentionally uses the same Battler abstraction on both sides of a
fight. `engine/troop.lua` resolves a Unit and constructs `Battler.new(Unit, ...)`.
Player-owned creatures ultimately use the same Unit definitions and Battler
behavior.

There is therefore no authored Enemy type. “Enemy” and “ally” describe where a
Battler is participating in the current encounter.

## 3. Actor

An **Actor** is the persistent player-owned identity of a Battler built from a
Unit.

Actor responsibility includes individuality that survives beyond one battle:

- instance UID
- personal/display name
- individual growth seed and accumulated history
- EXP and persistent level history
- equipment and persistent resources
- Favorite Food and discovery state
- provenance and reversible-transform origin
- creature history

Conceptually:

```text
Unit
  -> Battler              transient combat occurrence
  -> Actor : Battler      persistent player-owned occurrence
```

The notation does not require a Lua `Actor` subclass today. `Battler.new`
currently initializes some persistent-creature fields as well as universal
combat state, while `GameSession:createPersistentBattler` supplies the distinct
persistent identity. Splitting that object solely to make terminology look
finished would force growth, transforms, save/load, recruitment, equipment,
presentation, and tests across a new boundary at once.

A future Actor/Battler object cleanup should move responsibilities only when the
ownership of those fields and all of their callers can move atomically.

## 4. The legacy Summoner record

`data/actors.json` still contains the old Summoner definition. While that record
survives, its canonical symbolic ID is `summoner`, not the current display name
`Alex`.

That does **not** mean the current game architecture still treats the Summoner as
a Unit or Battler. The Summoner-as-Battler design has been removed. The identity
audit currently finds **zero Unit references** to `summoner`, which is
consistent with the record now being orphaned legacy data.

This migration deliberately leaves the record in place so numeric-to-symbolic
identity work is not mixed with a semantic roster deletion. Removing or
relocating it should be a separate cleanup that can prove no remaining runtime,
tooling, or content path depends on the old definition.

The legacy record therefore does not broaden the definition of Unit. Unit still
means an authored combat-capable definition from which a Battler may be built.

## 5. Canonical loader vocabulary

The loader exposes Unit as the canonical authored vocabulary:

```text
loader.units
loader.unitsById
loader.getUnit(id)
loader.getUnitByRole(role)
```

Legacy Actor-named loader APIs remain temporary aliases to the exact same
collection and registry:

```text
loader.actors        -> loader.units
loader.actorsById    -> loader.unitsById
loader.getActor      -> loader.getUnit
loader.getActorByRole -> loader.getUnitByRole
```

These aliases are not a second authority and may not develop different lookup
semantics.

New code that means “authored definition” should use Unit vocabulary.
Actor-named operations may remain where they genuinely mean a persistent
player-owned creature.

## 6. Canonical Unit identity

Unit IDs are symbolic strings. Numeric Unit IDs are not a supported runtime or
authoring compatibility surface.

The loader requires every Unit definition to have one non-empty string ID and
fails on duplicates. References resolve directly against that registry.

Examples of canonical IDs:

```text
Pixie       -> pixie
High Pixie  -> high_pixie
Moa         -> moa
Red Dragon  -> red_dragon
Gbl. Thief  -> goblin_thief
Gbl. Prince -> goblin_prince
Alex        -> summoner   (legacy orphan while the old record survives)
```

The last three illustrate why resource identity is not merely display-name
slugging. UI abbreviations do not define identity, and an obsolete record should
not be keyed to mutable presentation text merely because it has not been removed
yet.

Likewise, `red_dragon` remains a creature-concept identity even though one troop
uses it as a boss. Boss status belongs to troop/encounter data. Encoding that
status as `first_stratum_boss` would make Unit identity carry gameplay context
that the same Unit does not always have.

## 7. IDs are opaque handles

No gameplay or tooling behavior may be inferred by parsing a Unit ID.

In particular, code must not infer from the string:

- element
- tier
- allegiance
- recruitability
- boss status
- progression position
- evolution order
- role
- presentation category

Those are authored fields or relationships.

Symbolic identity exists to make references meaningful and stable, not to hide
rules inside names.

Evolution-family or progression information should likewise be explicit data if
it becomes useful. IDs such as `pixie`, `high_pixie`, and `titania` identify the
resources themselves; family, stage, branch, and the actual `evolvesTo` graph
must not be inferred from naming conventions such as `pixie_1` or `dragon_2a`.

## 8. Legacy reference field names

Several data fields still use Actor-era or generic vocabulary even though their
values are Unit IDs:

- map/troop/G2-fixture `actor`
- `actorId`
- map `recruits` entries
- `recruit_egg.value`
- `evolvesTo`
- `eligibleFrom`
- transform destination `actor`
- fixed new-game member `id`
- G2 fixture `party` entries

That spelling migration is intentionally separate from the identity migration.
Changing a field name and changing the identity domain at the same time would
make failures harder to diagnose.

`tools/data/audit_unit_identity.py` knows the current Unit-reference schemas and
checks that every actual destination resolves. This includes deterministic
`data/goldenBattles.json`, because verification fixtures must speak the same
canonical identity domain as gameplay data rather than retaining a private
numeric convention.

Transform operation sentinels are not Unit IDs:

```text
hatch
metamorph
revert
```

A new Unit-reference schema should be added to the audit when it is introduced.

## 9. Actor names and Unit identities are different

Persistent creature names must not become resource lookup keys.

For example, the player-owned creature called **Saban** is currently built from
Unit `moa`. Code that wants the species/definition must resolve `moa`. Code that
wants the individual Actor may display or modify Saban's personal identity.

This distinction is the point of the Unit/Actor vocabulary rather than an edge
case to paper over.

## 10. Save compatibility for the symbolic cutover

The numeric-to-symbolic Unit migration intentionally does **not** migrate old
development saves.

Current saves use save format version 3. A pre-version-3 save fails loudly during
deserialization rather than attempting numeric Unit fallback.

There is deliberately no retained numeric-to-symbolic runtime mapping. Keeping
such a table for normal lookup would create a second identity system and make
obsolete numeric IDs a permanent compatibility surface.

New saves persist symbolic Unit identity normally in fields such as current
Battler `id` and reversible-transform `originForm`.

## 11. Names intentionally not changed by this contract

The following legacy names can move independently when their responsibility is
being changed or their storage is migrated:

- `data/actors.json`
- authored `actor` / `actorId` field names
- `Battler.actorData`
- `GameSession:createPersistentBattler`
- `GameSession:recruitActor`
- historical save/session field names such as `firstRecruitOriginalActorId`
- presentation modules whose “actor” surface genuinely describes a persistent
  party creature

A broad textual rename is not itself architecture.

## 12. Future Actor/Battler object cleanup

A useful test for moving a field out of Battler is:

> Can a transient opponent meaningfully need this fact during one battle, or is
> it meaningful only because this individual persists outside battle?

Personal name, instance UID, Favorite Food discovery, provenance, and long-term
history are strong Actor-owned candidates. Other fields require more care.
Growth affects enemy combat stats too. Equipment may eventually be valid for
opponents. Persistent resources may need a battle representation.

Trace actual readers and writers before moving them.

## 13. Invariants

1. **Unit definitions have no intrinsic ally/enemy side.**
2. **Troops and player rosters resolve the same Unit registry.**
3. **Battler is the shared combat abstraction.**
4. **Actor means persistent player-owned identity, not the authored catalog.**
5. **Canonical Unit IDs are unique, non-empty symbolic strings.**
6. **Numeric Unit IDs are not a compatibility surface.**
7. **Legacy Actor loader APIs are aliases only and may not diverge from Unit.**
8. **Unit IDs are opaque handles; behavior and progression structure are explicit data.**
9. **Transform operation sentinels are not Unit identities.**
10. **Personal Actor names are never Unit lookup keys.**
11. **Old pre-symbolic development saves are rejected rather than migrated.**
12. **Verification fixtures use the same canonical Unit identity domain as gameplay data.**
13. **The orphaned Summoner record does not redefine Unit semantics and may be removed separately.**
14. **Storage migration, field-name cleanup, and Actor/Battler object cleanup remain separately diagnosable changes.**
