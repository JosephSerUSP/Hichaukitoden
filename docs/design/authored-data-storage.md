# Authored data storage and identity

Issue #147 separates four concerns that older monolithic JSON files often mix:

1. **identity** — the canonical `record.id` of an independently addressable resource;
2. **storage** — whether records live in one file or many files;
3. **ordering** — whether authored order itself carries meaning;
4. **gameplay semantics** — what the resource does at runtime.

Storage layout must not invent identity or gameplay behavior. A filename is not
an id, and no runtime rule may be parsed from an id string.

## Storage classes

### Ordered collections

Use an ordered collection only when sequence is authored meaning. The fragmented
form is `<stem>/index.json` plus the files listed by that manifest. Directory
enumeration never defines order.

`maps` and `scenes` are the current examples: their existing consumers rely on
stable sequence while their files are being prepared for eventual fragmentation.

### Registries

Use a registry for independently addressable resources whose order has no
semantic meaning. Every record owns exactly one non-empty string `id`, and the
runtime dictionary key is derived from that field.

A fragmented registry is simply:

```text
data/tilesets/
  dungeon_default.json
  stillnight_bellroot_vigil.json
  town_default.json
```

There is deliberately no `index.json`. Tools sort paths only for deterministic
processing and diagnostics. Filenames may be readable mirrors of ids, but they
remain storage details; loaders must read `record.id`.

During a staged migration, `<stem>.json` remains authoritative while it exists.
Deleting it is the explicit activation boundary. Readers and writers must not
silently choose different authorities.

### Configuration and fixtures

Singleton configuration, heterogeneous engine policy, override bundles and test
fixtures remain ordinary JSON documents. Fragmentation is not a goal by itself.
In particular, `engine.json` and `flows.json` must not be forced into registry
shape merely for uniformity.

## Current `data/*.json` classification

This table classifies semantic ownership, not the current serialization shape.
A registry candidate may still be a numeric array or numeric-string-keyed
object until its own migration is reviewed.

| Resource | Class | Migration direction |
| --- | --- | --- |
| `actionSequences` | registry | canonical record ids; fragment when useful |
| `actors` | registry | becomes `units`; symbolic ids in a later phase |
| `animations` | registry | canonical record ids; fragment when useful |
| `commonEvents` | registry | replace numeric-string key authority with record ids |
| `elements` | registry | preserve authored element identity; no id-parsed behavior |
| `items` | registry | canonical record ids; symbolic ids in a later phase |
| `lore` | registry | canonical record ids |
| `maps` | ordered collection | manifest-backed fragments |
| `passives` | registry | canonical record ids |
| `quests` | registry | canonical record ids |
| `roles` | registry | canonical record ids |
| `scenes` | ordered collection | manifest-backed fragments |
| `shops` | registry | canonical record ids |
| `skills` | registry | canonical record ids; symbolic ids in a later phase |
| `sounds` | registry | canonical record ids |
| `states` | registry | canonical record ids |
| `tilesets` | registry | **activated proof:** 14 record-owned fragments, no manifest |
| `troops` | registry | canonical record ids |
| `iconPalettes` | registry | fragment only if authoring pressure justifies it |
| `iconKeyProfiles` | registry | fragment only if authoring pressure justifies it |
| `engine` | configuration | keep heterogeneous policy together |
| `flows` | configuration | keep flow configuration together |
| `input` | configuration | keep input policy together |
| `system` | configuration | keep campaign/system policy together |
| `terms` | configuration | keep localized/structured term tree together |
| `scene_overrides` | override configuration | keep replacement bundle together |
| `goldenBattles` | verification fixture | keep gate-owned fixture semantics separate from authored registries |

## Canonical identity rules

- Each registry record owns exactly one non-empty string `id`.
- For a monolithic keyed registry, the outer key must equal `record.id` exactly.
- For fragmented registries, filename and directory order are irrelevant to identity.
- Duplicate canonical ids are hard errors.
- Numeric-to-symbolic migration is separate from fragmentation; storage work must
  preserve existing ids until a dedicated migration changes references atomically.
- Resource namespaces are registry-local. A skill id and item id may share text
  without becoming the same resource.

## Version tokens and stale saves

Any writer that edits fragmented storage needs one version token for the whole
logical resource. The token covers every authoritative file:

- monolith mode: the monolith;
- ordered fragments: `index.json` plus every listed fragment in manifest order;
- registry fragments: every `.json` fragment in sorted path order.

A content-derived compound token is preferred to a single mtime/size pair. The
editor sends the token it read; the server rejects a save when the current token
differs. A per-record write may touch only one fragment, but stale detection
still guards the complete logical registry.

Tileset Studio now exercises that contract end to end. `/api/tilesets` assembles
the active campaign's registry and gives each editor record the current compound
storage token as transport metadata. Existing-record saves are rejected with
HTTP 409 if any tileset fragment changed since the editor loaded. A successful
save updates only the touched record's fragment and reloads the list, which gives
the browser a fresh whole-registry token. New tilesets are created as new
fragments rather than rewriting unrelated authored records.

## Tilesets: first activated proof

`tilesets` is the first resource to cross the full migration boundary:

1. The original keyed monolith and generated fragments were compared as decoded
   values: all 14 records matched exactly.
2. Re-running the canonical splitter over the committed fragments produced no
   diff, proving the checked-in representation is deterministic.
3. Runtime loading, Tileset Studio, asset regression, asset-generation preview
   helpers, and model-census provenance were routed through shared storage
   semantics before activation.
4. `data/tilesets.json` was then deleted. Its absence is what activates
   `data/tilesets/*.json`; no compatibility flag or alternate authority exists.
5. The ordinary repository verification suite is the post-activation proof and
   must remain green before this migration is considered complete.

The important property is not merely that tilesets occupy many files. One
logical registry still has one canonical identity model, one activation rule,
and shared reader/writer semantics across runtime and authoring tools.

## Migration sequence

1. Add shared ordered/registry loading and strict validation without moving data.
2. Generate review fragments and prove semantic round trips while monoliths still win.
3. Convert every reader and writer of one chosen resource, including stale-save tokens.
4. Delete that monolith in the same change that activates the fragmented source.
5. Run deterministic, unit, save, editor and presentation gates against the activated form.
6. Migrate other resources only where conflict pressure or authoring scale justifies it.
7. Perform symbolic-id and Unit/Actor/Battler terminology migrations independently,
   so storage changes never disguise gameplay/reference changes.

Tilesets demonstrate the contract; they are not a mandate to fragment every
resource. Future migrations should follow observed authoring/conflict pressure
and preserve the same separation between identity, storage and gameplay meaning.
