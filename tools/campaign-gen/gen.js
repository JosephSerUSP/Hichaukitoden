#!/usr/bin/env node
// Campaign generator: prompt -> full playable campaign under campaigns/<name>/.
//
//   node tools/campaign-gen/gen.js --name mist_isle "A melancholy island of drowned bells..."
//
// Pipeline: outline (walkthrough-first) -> actors -> items -> quests -> maps
// -> events -> validate-repair loop against the REAL engine validator
// (`lovec . validate campaign=<name>`), feeding failures back verbatim.
// State persists in campaigns/<name>/gen-state.json; --resume continues a
// partial run, --stage <s> re-runs one stage, --dry-run prints a stage's
// assembled prompt without calling any API.
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chat, extractJson } = require('./lib/llm');
const ctxlib = require('./lib/context');

const HERE = __dirname;
const CONFIG = JSON.parse(fs.readFileSync(path.join(HERE, 'config.json'), 'utf8'));
const STAGE_ORDER = ['outline', 'actors', 'items', 'quests', 'maps', 'events'];

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------
const args = process.argv.slice(2);
const opts = { prompt: [], name: null, stage: null, resume: false, dryRun: false };
for (let i = 0; i < args.length; i++) {
    if (args[i] === '--name') opts.name = args[++i];
    else if (args[i] === '--stage') opts.stage = args[++i];
    else if (args[i] === '--resume') opts.resume = true;
    else if (args[i] === '--dry-run') opts.dryRun = true;
    else opts.prompt.push(args[i]);
}
opts.prompt = opts.prompt.join(' ');

if (!opts.name || !/^[a-z0-9_]+$/.test(opts.name)) {
    console.error('Usage: node gen.js --name <snake_case_name> [--stage s] [--resume] [--dry-run] "<pitch prompt>"');
    process.exit(2);
}
const DIR = path.join(ctxlib.REPO, 'campaigns', opts.name);
const STATE_PATH = path.join(DIR, 'gen-state.json');

// ---------------------------------------------------------------------------
// Campaign dir bootstrap: full copy of data/ (the campaign is instantly
// playable and validatable at every stage; stages overwrite content files).
// ---------------------------------------------------------------------------
function bootstrap() {
    if (fs.existsSync(DIR)) return;
    fs.mkdirSync(DIR, { recursive: true });
    for (const f of fs.readdirSync(path.join(ctxlib.REPO, 'data'))) {
        if (f.endsWith('.json')) {
            fs.copyFileSync(path.join(ctxlib.REPO, 'data', f), path.join(DIR, f));
        }
    }
}

function loadState() {
    if (fs.existsSync(STATE_PATH)) return JSON.parse(fs.readFileSync(STATE_PATH, 'utf8'));
    return { prompt: opts.prompt, done: [] };
}
function saveState(state) {
    fs.writeFileSync(STATE_PATH, JSON.stringify(state, null, 2));
}

// ---------------------------------------------------------------------------
// Prompt assembly: prompts/<stage>.md is the human-editable template; {{X}}
// placeholders are filled from the contract builders in lib/context.js.
// ---------------------------------------------------------------------------
function assemblePrompt(stage, state) {
    const template = fs.readFileSync(path.join(HERE, 'prompts', stage + '.md'), 'utf8');
    const fills = {
        PITCH: state.prompt,
        OUTLINE: fs.existsSync(path.join(DIR, 'outline.json'))
            ? fs.readFileSync(path.join(DIR, 'outline.json'), 'utf8') : '(not generated yet)',
        RULESET: JSON.stringify(ctxlib.ruleset(), null, 1),
        COMMANDS: JSON.stringify(ctxlib.commandRegistry(), null, 1),
        MANIFEST: JSON.stringify(ctxlib.manifest(DIR), null, 1),
        SAMPLES: JSON.stringify(ctxlib.samples(), null, 1),
    };
    return template.replace(/\{\{(\w+)\}\}/g, (_, k) => fills[k] !== undefined ? fills[k] : `{{${k}}}`);
}

// Running usage totals for the whole run, printed per call and at exit.
const totals = { prompt: 0, completion: 0, cost: 0 };

async function callStage(stage, userPrompt, extraMessages = []) {
    const sc = CONFIG.stages[stage] || CONFIG.stages.repair;
    const apiKey = process.env[CONFIG.provider.apiKeyEnv];
    if (!apiKey) {
        console.error(`Missing API key: set ${CONFIG.provider.apiKeyEnv} in your environment.`);
        process.exit(2);
    }
    const started = Date.now();
    const { content, usage } = await chat({
        baseUrl: CONFIG.provider.baseUrl,
        apiKey,
        model: sc.model,
        temperature: sc.temperature,
        // Live output: the model's reply streams to the console as it
        // generates, so long stages are visibly alive.
        onChunk: d => process.stdout.write(d),
        messages: [
            { role: 'system', content: 'You generate game data for a JSON-driven RPG engine. Reply with EXACTLY the artifact requested -- no commentary outside it.' },
            { role: 'user', content: userPrompt },
            ...extraMessages,
        ],
    });
    process.stdout.write('\n');
    const secs = ((Date.now() - started) / 1000).toFixed(1);
    if (usage) {
        totals.prompt += usage.prompt_tokens || 0;
        totals.completion += usage.completion_tokens || 0;
        if (typeof usage.cost === 'number') totals.cost += usage.cost;
        const cost = typeof usage.cost === 'number' ? ` | $${usage.cost.toFixed(5)}` : '';
        console.log(`  [${stage}] ${usage.prompt_tokens} in / ${usage.completion_tokens} out tokens${cost} | ${secs}s`
            + ` || run total: ${totals.prompt} in / ${totals.completion} out`
            + (totals.cost ? ` | $${totals.cost.toFixed(5)}` : ''));
    } else {
        console.log(`  [${stage}] done in ${secs}s (provider returned no usage data)`);
    }
    return content;
}

// ---------------------------------------------------------------------------
// Stage output handling: each stage's template instructs the model to emit
// one JSON object keyed by target filename (plus WALKTHROUGH for outline).
// ---------------------------------------------------------------------------
function writeStageOutput(stage, reply) {
    if (stage === 'outline') {
        // outline emits: { "outline": {...}, "walkthrough": "markdown..." }
        const out = extractJson(reply);
        if (!out.outline || !out.walkthrough) throw new Error('outline stage must emit {outline, walkthrough}');
        fs.writeFileSync(path.join(DIR, 'outline.json'), JSON.stringify(out.outline, null, 2));
        fs.writeFileSync(path.join(DIR, 'WALKTHROUGH.md'), out.walkthrough);
        return ['outline.json', 'WALKTHROUGH.md'];
    }
    const out = extractJson(reply);
    const written = [];
    for (const [file, content] of Object.entries(out)) {
        if (!ctxlib.CONTENT_FILES.includes(file)) {
            console.warn(`  (ignoring unexpected file key '${file}')`);
            continue;
        }
        fs.writeFileSync(path.join(DIR, file), JSON.stringify(content, null, 2));
        written.push(file);
    }
    if (written.length === 0) throw new Error(`stage '${stage}' emitted no known content file`);
    return written;
}

// ---------------------------------------------------------------------------
// Validate-repair loop: the engine validator is the oracle. Non-zero exit ->
// feed the FAIL lines and the current content files back to the repair model.
// ---------------------------------------------------------------------------
function runValidator() {
    try {
        const out = execFileSync(CONFIG.validate.lovecPath, ['.', 'validate', `campaign=${opts.name}`],
            { cwd: ctxlib.REPO, encoding: 'utf8', timeout: 120000 });
        return { ok: true, output: out };
    } catch (err) {
        return { ok: false, output: (err.stdout || '') + (err.stderr || '') };
    }
}

async function validateRepairLoop() {
    for (let round = 1; round <= CONFIG.validate.maxRepairRounds; round++) {
        const res = runValidator();
        if (res.ok && /VALIDATE OK/.test(res.output)) {
            console.log('VALIDATE OK');
            return true;
        }
        const problems = res.output.split('\n')
            .filter(l => !/^\[formula\] error in 'os\.time/.test(l)) // sandbox negative-test noise
            .filter(l => /FAIL|error|missing|resolves to no|references/.test(l))
            .join('\n');
        console.log(`validate round ${round} failed:\n${problems}\n-> asking repair model...`);
        const files = {};
        for (const f of ctxlib.CONTENT_FILES) {
            files[f] = JSON.parse(fs.readFileSync(path.join(DIR, f), 'utf8'));
        }
        const repairPrompt = fs.readFileSync(path.join(HERE, 'prompts', 'repair.md'), 'utf8')
            .replace('{{PROBLEMS}}', problems)
            .replace('{{FILES}}', JSON.stringify(files, null, 1))
            .replace('{{COMMANDS}}', JSON.stringify(ctxlib.commandRegistry(), null, 1));
        const reply = await callStage('repair', repairPrompt);
        const out = extractJson(reply);
        for (const [file, content] of Object.entries(out)) {
            if (ctxlib.CONTENT_FILES.includes(file)) {
                fs.writeFileSync(path.join(DIR, file), JSON.stringify(content, null, 2));
                console.log(`  repaired ${file}`);
            }
        }
    }
    console.error('Repair rounds exhausted; campaign still fails validation.');
    return false;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
    bootstrap();
    const state = loadState();
    if (!state.prompt && opts.prompt) state.prompt = opts.prompt;

    const stages = opts.stage ? [opts.stage] : STAGE_ORDER.filter(s => !opts.resume || !state.done.includes(s));

    for (const stage of stages) {
        const prompt = assemblePrompt(stage, state);
        if (opts.dryRun) {
            console.log(`===== DRY RUN: stage '${stage}' prompt =====\n${prompt}`);
            continue;
        }
        console.log(`--- stage: ${stage} (${(CONFIG.stages[stage] || {}).model}) ---`);
        const reply = await callStage(stage, prompt);
        const written = writeStageOutput(stage, reply);
        console.log(`  wrote: ${written.join(', ')}`);
        if (!state.done.includes(stage)) state.done.push(stage);
        saveState(state);
    }

    if (!opts.dryRun) {
        const ok = await validateRepairLoop();
        saveState(state);
        console.log(ok
            ? `\nCampaign ready: campaigns/${opts.name}/  (play it: add {"active":"${opts.name}"} to campaign.json, or lovec . campaign=${opts.name})`
            : `\nCampaign INVALID: campaigns/${opts.name}/ -- inspect and re-run with --stage or fix by hand.`);
        process.exit(ok ? 0 : 1);
    }
})().catch(err => { console.error(err); process.exit(1); });
