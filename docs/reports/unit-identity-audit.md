# Unit identity audit

This report records issue #147's symbolic Unit identity cutover. The executable
authority for the reference inventory is `tools/data/audit_unit_identity.py`.

## Current result

The Unit catalog now contains:

- 66 catalog definitions
- 0 numeric Unit IDs
- 66 symbolic Unit IDs
- 228 audited Unit references across authored data and deterministic G2 fixtures

The 228 references currently break down as:

- 48 map/troop `actor` references
- 19 `actorId` references
- 37 map `recruits` references
- 31 `evolvesTo` references
- 51 `eligibleFrom` references
- 8 hatch-outcome destinations
- 1 secret-transform destination
- 1 `recruit_egg.value` reference
- 1 fixed new-game member reference
- 16 G2 fixture party references
- 15 G2 fixture enemy `actor` references

Every audited reference resolves to the symbolic Unit registry.

Transform operation sentinels `hatch`, `metamorph`, and `revert` are explicitly
excluded from Unit identity and are checked as operations rather than resource
IDs.

## Additional code inventory

The cutover also removed explicit numeric Unit assumptions outside JSON data,
including literal Unit lookups, recruitment API fixtures, numeric
`actorData.id` comparisons, named Unit constants, a positional actor-catalog
test lookup, an indirect numeric validator helper, and the G2 harness's legacy
Actor lookup.

Code that means an authored definition now uses symbolic identity such as
`getUnit("pixie")`, `getUnit("skeleton")`, and `getUnit("moa")`.

The last example is intentional: Saban is an individual Actor whose authored
Unit is `moa`.

## Reference schemas discovered by the gates

The migration inventory grew under verification rather than being frozen around
its first assumptions. G1 and the unit/G2 gates exposed additional Unit-reference
surfaces that were then added to the executable audit before migration:

- map `recruits` arrays
- `recruit_egg.value`
- deterministic `goldenBattles.json` party entries and enemy `actor` fields

This is intentional. A symbolic-ID migration is complete only when every real
identity-bearing surface speaks the same domain; a passing hand-written list is
not sufficient evidence.

The G2 discovery also did **not** require rewriting a checked-in golden battle
log. The old fixture printed its header and then failed to resolve numeric Unit
IDs, which `check.ps1` surfaced as a truncated-log mismatch. Migrating the fixture
and harness restores the same battle behavior through symbolic Unit identity.

## Identity decisions

Most Unit IDs follow the durable creature concept in snake_case. Notable choices
include:

- `summoner` for the orphaned legacy record whose current display name is Alex;
  the current audit finds zero Unit references to this record, and its later
  removal/relocation is deliberately separate from the identity cutover
- `goblin_thief` and `goblin_prince` rather than abbreviating the current UI labels
- `red_dragon` rather than encoding its first-stratum boss usage into Unit identity

Evolution family and progression stage are likewise not encoded into IDs.
`pixie`, `high_pixie`, `dragon`, `red_dragon`, and related names identify the
creature concepts themselves; family/stage/branch data should be authored
explicitly if needed, while `evolvesTo` remains the graph authority.

These choices keep display text, encounter role, and progression topology out of
the resource key. Behavior must remain explicit data rather than being inferred
from the ID string.

## Save policy

Old development saves are intentionally not migrated.

The symbolic cutover bumps the save format to version 3. Deserializing an older
save fails loudly with an unsupported-version error. There is no retained
numeric-to-symbolic runtime mapping and no numeric Unit fallback.

## Ongoing use

Run:

```text
python tools/data/audit_unit_identity.py
```

The audit verifies that Unit definitions use non-empty symbolic string IDs and
that all known Unit-reference schemas resolve to the registry.

The architecture and terminology contract lives in
`docs/design/unit-actor-battler.md`.
