# campaign-gen

Prompt → full playable campaign under `campaigns/<name>/`.

```
set OPENROUTER_API_KEY=sk-or-...
node tools/campaign-gen/gen.js --name mist_isle "A melancholy island where drowned bells still ring at low tide."
```

Then play it: `lovec . campaign=mist_isle`, or persist the selection with a
repo-root `campaign.json` containing `{"active": "mist_isle"}`.

## How it works

1. `campaigns/<name>/` bootstraps as a full copy of `data/` (the shared-core
   ruleset ships with every campaign; the campaign is playable and
   validatable after every stage).
2. Stages run in order — `outline → actors → items → quests → maps → events`
   — each one an LLM call whose prompt embeds the machine-readable contracts
   (command registry, ruleset ids, id manifest of everything generated so
   far, schema-by-example from the real default campaign). The outline stage
   writes `WALKTHROUGH.md` FIRST; everything else derives from it.
3. After the last stage, the validate-repair loop runs the real engine
   validator (`lovec . validate campaign=<name>`) and feeds any failures
   verbatim to the repair model until `VALIDATE OK` (bounded rounds).

## Flags

- `--dry-run`     print a stage's fully assembled prompt, no API calls
- `--stage <s>`   run exactly one stage (after hand-edits, or to reroll)
- `--resume`      skip stages recorded as done in `gen-state.json`

## Configuration

`config.json`: OpenAI-compatible `provider.baseUrl` (OpenRouter by default —
DeepSeek direct or any compatible endpoint works by swapping the URL), per-
stage `model`/`temperature` (route the outline to your strongest model, bulk
JSON stages to something cheap), key env var name, validator path.

Prompt templates live in `prompts/*.md` — edit them freely; `{{TOKENS}}` are
filled by `lib/context.js`.

## Assets

Generated campaigns REUSE existing sprite/portrait keys (the actors prompt
mandates it), so everything renders with placeholder art immediately. Image
generation (Gemini or an OpenRouter image model) is a planned separate pass
that walks the campaign's asset references and fills in bespoke art.
