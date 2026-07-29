// asset-gen UI. Thin: every button maps to one server endpoint, which maps to
// one CLI command. No generation logic lives here.
'use strict';

const $ = (id) => document.getElementById(id);
const api = async (path, body) => {
    const res = await fetch(path, body ? {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
    } : undefined);
    return res.json();
};

let CLASSES = [];
let PROVIDERS = [];
let PRICING = {};

// --- form state ---------------------------------------------------------
function currentClass() {
    return CLASSES.find(c => c.id === $('class').value);
}

function currentProvider() {
    return PROVIDERS.find(p => p.id === $('provider').value) || {};
}

function currentModel() {
    return (currentProvider().models || []).find(m => m.id === $('model').value);
}

function request() {
    return {
        class: $('class').value,
        name: $('name').value.trim(),
        description: $('description').value.trim(),
        provider: $('provider').value,
        model: $('model').value,
        quality: currentProvider().priced ? $('quality').value : '',
        variants: Number($('variants').value) || undefined,
        cell: $('cell').value.trim(),
        frames: Number($('frames').value) || undefined,
        grid: $('grid').value.trim(),
        extra: $('extra').value.trim(),
        tokens: $('tokens').value.trim(),
        refs: $('refs').value.split('\n').map(s => s.trim()).filter(Boolean),
    };
}

function syncClass() {
    const def = currentClass();
    if (!def) return;
    $('classNote').textContent = def.note;
    $('classNote').className = def.wired ? 'note' : 'note warn';
    if (!def.wired) $('classNote').textContent = 'NOT ENGINE-WIRED YET. ' + def.note;
    $('target').textContent = `${def.dir}/  ${def.size}`;
    // Sheet controls only mean something for multi-cell classes.
    $('sheetBox').style.display = (def.frames > 1 || def.sheet) ? '' : 'none';
    $('cell').placeholder = def.cell;
    $('frames').placeholder = String(def.frames);
}

function syncProvider() {
    const def = currentProvider();
    if (!def.id) return;

    $('model').innerHTML = (def.models || [])
        .map(m => `<option value="${m.id}"${m.id === def.model ? ' selected' : ''}>${m.label}</option>`)
        .join('');
    // Only the OpenAI images path takes a quality tier; the others price per token.
    $('qualityRow').style.display = def.priced ? '' : 'none';
    if (def.quality) $('quality').value = def.quality;

    $('keyNote').textContent = def.hasKey
        ? `${def.keyEnv} is set.`
        : `${def.keyEnv} is NOT set -- paste a key above, or set the env var and restart.`;
    $('keyNote').className = def.hasKey ? 'note' : 'note warn';
    syncCost();
}

// Estimate straight from the same config table the CLI reads. Deliberately
// pessimistic about its own accuracy: a price table in a repo is a snapshot.
function syncCost() {
    const model = currentModel();
    const klass = currentClass();
    const variants = Number($('variants').value) || 1;
    const cost = $('cost');
    const note = $('costNote');

    if (!model || !klass) return;
    const prices = model.prices && model.prices[$('quality').value];
    const unit = prices && prices[klass.requestSize];

    if (!currentProvider().priced || !unit) {
        cost.textContent = 'no cost estimate for this model';
        cost.className = 'cost muted';
        note.textContent = model.note || 'This provider bills per token; watch its dashboard.';
        return;
    }
    cost.textContent = `~$${(unit * variants).toFixed(3)} for ${variants} variant`
        + `${variants === 1 ? '' : 's'}  ($${unit.toFixed(3)} each)`;
    cost.className = 'cost';
    note.textContent = `Estimate from a local table checked ${PRICING.checkedOn || '?'}`
        + ' -- prices change; your invoice is the truth.';
}

// --- logging ------------------------------------------------------------
function log(text, state) {
    const el = $('log');
    el.textContent = text || '';
    el.className = state || '';
    el.scrollTop = el.scrollHeight;
}

function busy(on) {
    ['generate', 'preview', 'refresh'].forEach(id => { $(id).disabled = on; });
}

// --- runs ---------------------------------------------------------------
function scaleFor(width) {
    // Upscale small sheets so pixels are judgeable; leave big art near 1:1.
    if (width <= 96) return 5;
    if (width <= 260) return 2;
    return 1;
}

async function loadRuns() {
    const { runs } = await api('/api/runs');
    const host = $('runs');
    host.innerHTML = '';
    if (!runs.length) {
        host.innerHTML = '<p class="note">Nothing staged yet.</p>';
        return;
    }
    for (const run of runs) {
        const div = document.createElement('div');
        div.className = 'run';
        const promoted = run.promoted.length
            ? `<span class="done">promoted -> ${run.promoted[run.promoted.length - 1].dest}</span>` : '';
        div.innerHTML = `
            <div class="head">
              <span class="cls">${run.class}</span>
              <span class="path">${run.target}</span>
              ${promoted}
              <span class="meta">${run.provider.model || ''}</span>
              <button class="mini" data-reprocess="${run.run}">reprocess</button>
            </div>
            <div class="variants"></div>`;
        const strip = div.querySelector('.variants');
        for (const variant of run.variants) {
            const cell = document.createElement('div');
            cell.className = 'variant';
            cell.innerHTML = `
                <div class="frame"><img src="${variant.url}" alt=""></div>
                <span class="cap">#${variant.index}</span>
                <button class="mini" data-run="${run.run}" data-variant="${variant.index}">promote</button>`;
            const img = cell.querySelector('img');
            img.onload = () => {
                const scale = scaleFor(img.naturalWidth);
                img.style.width = (img.naturalWidth * scale) + 'px';
                img.style.height = (img.naturalHeight * scale) + 'px';
            };
            strip.appendChild(cell);
        }
        host.appendChild(div);
    }
}

// --- job polling --------------------------------------------------------
async function pollJob() {
    const job = await api('/api/job');
    log(job.log, job.running ? 'busy' : (job.ok ? '' : 'fail'));
    if (job.running) return setTimeout(pollJob, 900);
    busy(false);
    await loadRuns();
}

async function startJob(path, body) {
    busy(true);
    log('working...', 'busy');
    const res = await api(path, body);
    if (res.busy) {
        busy(false);
        return log('a render is already running; wait for it to finish', 'fail');
    }
    pollJob();
}

// --- wiring -------------------------------------------------------------
$('class').onchange = () => { syncClass(); syncCost(); };
$('provider').onchange = syncProvider;
$('model').onchange = syncCost;
$('quality').onchange = syncCost;
$('variants').oninput = syncCost;

$('setKey').onclick = async () => {
    const def = PROVIDERS.find(p => p.id === $('provider').value);
    const res = await api('/api/key', { env: def.keyEnv, key: $('key').value });
    def.hasKey = res.hasKey;
    $('key').value = '';
    syncProvider();
    log(`${def.keyEnv} ${res.hasKey ? 'set for this session (memory only, not saved)' : 'cleared'}`);
};

$('preview').onclick = async () => {
    const res = await api('/api/prompt', request());
    log(res.text, res.ok ? '' : 'fail');
};

$('generate').onclick = () => {
    const body = request();
    if (!body.name) return log('give it a name -- the filename comes from it', 'fail');
    startJob('/api/generate', body);
};

$('refresh').onclick = loadRuns;

$('runs').onclick = async (event) => {
    const button = event.target.closest('button');
    if (!button) return;

    if (button.dataset.reprocess) {
        return startJob('/api/reprocess', { run: button.dataset.reprocess });
    }
    if (button.dataset.run) {
        const res = await api('/api/promote', {
            run: button.dataset.run,
            variant: Number(button.dataset.variant),
        });
        if (!res.ok && /already exists/.test(res.log)) {
            if (!confirm('That file already exists. Overwrite it?')) return log(res.log, 'fail');
            const forced = await api('/api/promote', {
                run: button.dataset.run,
                variant: Number(button.dataset.variant),
                force: true,
            });
            log(forced.log, forced.ok ? '' : 'fail');
        } else {
            log(res.log, res.ok ? '' : 'fail');
        }
        loadRuns();
    }
};

// --- boot ---------------------------------------------------------------
(async function init() {
    const data = await api('/api/classes');
    CLASSES = data.classes;
    PROVIDERS = data.providers;
    PRICING = data.pricing || {};

    $('class').innerHTML = CLASSES
        .map(c => `<option value="${c.id}">${c.label} (${c.size})</option>`).join('');
    $('provider').innerHTML = PROVIDERS
        .map(p => `<option value="${p.id}"${p.default ? ' selected' : ''}>${p.label}</option>`).join('');
    $('variants').value = data.variants;

    syncClass();
    syncProvider();
    await loadRuns();
    log('idle');
})();
