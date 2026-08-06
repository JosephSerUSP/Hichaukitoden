# Unified Asset Language

This directory contains versioned authoring vocabularies for the unified asset contract.

- `contract.json` is the machine-readable contract data.
- `materials.json` is the semantic material registry.
- `docs/asset-pipeline/ASSET_CONTRACT.md` is the normative human-readable explanation.

Neither JSON file is consumed by the runtime yet. Existing assets remain legacy-compatible; implementation and adapters begin in later phases.

## Read-only checks

```text
python tools/asset-language/check.py contract
python tools/asset-language/check.py record FILE
python tools/asset-language/check.py regression
python tools/asset-language/check.py all
python tools/asset-language/check.py snapshot --output PATH
```

`contract`, `record`, `regression`, and `all` are read-only. `snapshot` writes
only the explicitly requested output and refuses to overwrite it unless
`--force` is supplied. The runtime does not consume the unified contract yet.
