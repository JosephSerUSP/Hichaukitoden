# Splitting `scenes.json` and `maps.json`

## Problem

`scenes.json` and `maps.json` have crossed the point where a single serialized
array is a useful authoring unit. A change to one scene or one map rewrites and
reviews an unrelated database-sized file, increases merge conflicts, and makes
it difficult to understand ownership from the repository tree.

The split cannot be treated as a loader-only rename. These collections are read
and written by several independent consumers:

- the LÖVE runtime loader;
- the web editor server and stale-save tokens;
- the in-game developer server;
- the validator, golden tools and screenshot harness;
- the campaign generator and generated campaign roots;
- direct scripts that currently assume `<root>/maps.json` or
  `<root>/scenes.json` exists.

Activating fragments before all writers agree would create two sources of truth:
the runtime could read the directory while the editor continued overwriting the
old monolith.

## Target format

Each ordered collection becomes a directory with an explicit manifest:

```text
data/
  scenes/
    index.json
    0001-1-item-creation.json
    0002-status-status.json
    0003-recruit-creature-recruitment.json
  maps/
    index.json
    0001-1-thestra.json
    0002-2-first-stratum-1f.json
```

`index.json` owns order. Each listed file contains one object; grouped arrays are
also accepted for deliberately inseparable authored content.

```json
{
  "format": 1,
  "source": "scenes.json",
  "files": [
    "0001-1-item-creation.json",
    "0002-status-status.json"
  ]
}
```

Order must not be inferred from directory enumeration. Scene fallback-by-kind,
map indices, golden output and editor selection all depend on deterministic
ordering.

## Migration phases

### Phase 1 — runtime compatibility and deterministic tooling

This branch implements Phase 1:

- `data.collection_loader` can assemble `maps` and `scenes` from an indexed
  directory when the monolith is absent;
- the existing monolith remains authoritative while both forms exist;
- `tools/data/split_json_collection.py` deterministically emits fragments and
  verifies a byte-semantic round trip;
- no production data is moved yet.

The monolith-first rule is intentional. It allows review fragments to be
produced without changing which data the game actually loads.

### Phase 2 — writer abstraction

Create one collection store for the web editor and in-game developer server:

- `readCollection(root, name)` returns the assembled ordered array and a version
  token derived from the manifest and every listed fragment;
- `writeCollection(root, name, entries)` updates only changed fragments,
  rewrites `index.json` atomically, and removes stale fragments explicitly;
- stale-save rejection compares the compound version token, not a single file's
  mtime and size;
- editor requests continue exchanging assembled arrays, so UI code does not
  need to understand storage layout.

The campaign generator and other scripts should call the same storage module or
an equivalent shared library rather than reimplementing filename rules.

### Phase 3 — activate the split

After every reader and writer is fragment-aware:

1. run the splitter with `--apply` for review;
2. run validator, unit, save, editor and golden gates against the monolith;
3. remove `scenes.json` and `maps.json` to activate fragment loading;
4. rerun the same gates and compare assembled structures exactly;
5. keep the migration in one commit so `git bisect` never lands on a mixed
   source-of-truth state.

## Commands

Dry run:

```bash
python tools/data/split_json_collection.py scenes
python tools/data/split_json_collection.py maps
```

Write review fragments beside the still-authoritative monolith:

```bash
python tools/data/split_json_collection.py scenes --apply
python tools/data/split_json_collection.py maps --apply
```

The eventual activation command, only after Phase 2 is complete:

```bash
python tools/data/split_json_collection.py scenes --apply --remove-source
python tools/data/split_json_collection.py maps --apply --remove-source
```

## Invariants

- IDs remain unchanged.
- Manifest order reproduces the original array order exactly.
- Duplicate or unsafe fragment paths fail loudly.
- Missing fragments fail loudly.
- A fragment is either one object with an `id` or a non-empty object array.
- Campaign roots use the same format as `data/`.
- No tool may silently prefer a different source of truth from the runtime.
