# campaign-gen

Prompt → full playable campaign under `campaigns/<name>/`.

## Quick start

```
set OPENROUTER_API_KEY=sk-or-...
node tools/campaign-gen/gen.js --name mist_isle "A melancholy island where drowned bells still ring at low tide."
```

Then play it: `lovec . campaign=mist_isle`, or persist the selection with a
repo-root `campaign.json` containing `{"active": "mist_isle"}`.

## Supported providers

The generator supports three LLM providers:

| Provider    | Env var               | Type               |
|-------------|-----------------------|--------------------|
| OpenRouter  | `OPENROUTER_API_KEY`   | OpenAI-compatible  |
| DeepSeek    | `DEEPSEEK_API_KEY`     | OpenAI-compatible  |
| Gemini      | `GEMINI_API_KEY`       | Google Gemini API  |

**Default:** OpenRouter. Override with `--provider` or `CAMPAIGN_GEN_PROVIDER` env.

```
set GEMINI_API_KEY=AIza...
node tools/campaign-gen/gen.js --name mist_isle --provider gemini "A melancholy island..."
```

```
set DEEPSEEK_API_KEY=sk-...
node tools/campaign-gen/gen.js --name mist_isle --provider deepseek "A melancholy island..."
```

Each provider reads its own env var; only the one matching the active provider
needs to be set.

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

- `--dry-run`        print a stage's fully assembled prompt, no API calls
- `--stage <s>`      run exactly one stage (after hand-edits, or to reroll)
- `--resume`         skip stages recorded as done in `gen-state.json`
- `--provider <id>`  LLM provider: `openrouter`, `deepseek`, or `gemini`
- `--model <id>`     override the model for all stages (default per-stage from config)

## Configuration

`config.json`: defines LLM providers, per-stage model/temperature, and
validator settings. Add or tweak providers freely:

```json
{
  "providers": {
    "openrouter": {
      "label": "OpenRouter",
      "baseUrl": "https://openrouter.ai/api/v1",
      "apiKeyEnv": "OPENROUTER_API_KEY",
      "type": "openai-compatible",
      "default": true
    },
    "deepseek": {
      "label": "DeepSeek",
      "baseUrl": "https://api.deepseek.com/v1",
      "apiKeyEnv": "DEEPSEEK_API_KEY",
      "type": "openai-compatible"
    },
    "gemini": {
      "label": "Gemini",
      "apiKeyEnv": "GEMINI_API_KEY",
      "type": "gemini"
    }
  },
  ...
}
```

Provider `type` is either `openai-compatible` (uses `/chat/completions`) or
`gemini` (uses Google's `streamGenerateContent`). `type: gemini` providers
don't need a `baseUrl` — it's hardcoded to
`https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent`.

Prompt templates live in `prompts/*.md` — edit them freely; `{{TOKENS}}` are
filled by `lib/context.js`.

## Editor integration

Open the Campaign Generator window in the editor. Select a provider, enter
the matching API key (or rely on server env vars), pick models, and click
Generate. The provider and key are sent to the editor server, which spawns
`gen.js` as a child process with the right environment.
