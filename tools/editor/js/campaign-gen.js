// --- CAMPAIGN GENERATOR WINDOW ---
// Client-side UI for the tools/campaign-gen bridge exposed by server.js
// (/campaign-gen/*). All run state lives in this module, NOT in the DOM,
// so the modal can be closed and reopened mid-run: the poll loop keeps
// running in the background and the console re-syncs (from=0) on open.
// The API key is kept only in its password input for the duration of the
// page — never persisted to localStorage or dbPayload.
(function() {
    const STAGES = ['outline', 'actors', 'items', 'quests', 'maps', 'events', 'repair'];
    // The visual progress strip: repair is folded into "validate" since the
    // log interleaves validate rounds and repair calls.
    const STRIP_STAGES = ['outline', 'actors', 'items', 'quests', 'maps', 'events', 'validate'];
    const MAX_SELECT_OPTIONS = 200; // catalogue is huge; the filter box narrows it

    let genConfig = null;        // /campaign-gen/config payload
    let modelCatalogue = null;   // [{id, name, promptPrice, completionPrice}] or null if fetch failed
    let catalogueFailed = false;

    // Run state (survives modal close/reopen)
    let runStatus = 'idle';      // idle | running | success | failed | cancelled
    let runName = '';            // campaign name of the current/last run
    let logOffset = 0;           // next `from` byte for /status polling
    let pollTimer = null;
    let currentStage = null;     // highlighted chip in the strip
    let doneStages = [];         // chips already completed
    let lastCostLine = '';
    let consolePinned = true;    // autoscroll unless the user scrolled up

    const $ = id => document.getElementById(id);

    // ---------------------------------------------------------------
    // Open / close
    // ---------------------------------------------------------------
    window.openCampaignGenModal = async function() {
        $('campaign-gen-modal').classList.add('active');
        if (!genConfig) {
            try {
                const res = await fetch(`${API_URL}/campaign-gen/config`);
                if (res.ok) genConfig = await res.json();
            } catch (e) { /* offline: selects just show no defaults */ }
        }
        if (!modelCatalogue && !catalogueFailed) {
            try {
                const res = await fetch(`${API_URL}/campaign-gen/models`);
                if (!res.ok) throw new Error('catalogue unavailable');
                modelCatalogue = await res.json();
                if (!Array.isArray(modelCatalogue)) throw new Error('bad catalogue');
            } catch (e) {
                modelCatalogue = null;
                catalogueFailed = true;
            }
        }
        renderModelSection();
        validateCgName();
        renderRunState();

        // Re-sync the console: mid-run reopen refetches the whole log.
        $('cg-console').textContent = '';
        consolePinned = true;
        logOffset = 0;
        try {
            const res = await fetch(`${API_URL}/campaign-gen/status?from=0`);
            const st = await res.json();
            applyStatusPayload(st);
            if (st.status === 'running' && !pollTimer) startPolling();
        } catch (e) { /* server offline; Generate will surface it */ }
    };

    window.closeCampaignGenModal = function() {
        // Never interrupts a run — polling continues headless.
        $('campaign-gen-modal').classList.remove('active');
    };

    // Escape-key support, same stack as the other staged modals.
    if (typeof ESCAPE_MODAL_CLOSERS !== 'undefined') {
        ESCAPE_MODAL_CLOSERS.unshift(['campaign-gen-modal', () => closeCampaignGenModal()]);
    }

    // ---------------------------------------------------------------
    // Inputs & validation
    // ---------------------------------------------------------------
    window.validateCgName = function() {
        const input = $('cg-name');
        const err = $('cg-name-error');
        const val = input.value;
        const ok = /^[a-z0-9_]+$/.test(val);
        if (val === '' || ok) {
            input.classList.remove('cg-input-error');
            err.style.display = 'none';
        } else {
            input.classList.add('cg-input-error');
            err.style.display = 'block';
        }
        updateRunControls();
        return ok;
    };

    window.cgInputsChanged = function() {
        updateRunControls();
    };

    function nameValid() { return /^[a-z0-9_]+$/.test($('cg-name').value); }
    function pitchFilled() { return $('cg-pitch').value.trim().length > 0; }

    // ---------------------------------------------------------------
    // Model section
    // ---------------------------------------------------------------
    function priceHint(m) {
        const pIn = parseFloat(m.promptPrice);
        const pOut = parseFloat(m.completionPrice);
        if ((!pIn || pIn === 0) && (!pOut || pOut === 0)) return 'free';
        const fmt = v => {
            const perM = v * 1e6;
            return '$' + (perM >= 10 ? perM.toFixed(0) : perM.toFixed(2)) + '/M';
        };
        return `${fmt(pIn || 0)} in · ${fmt(pOut || 0)} out`;
    }

    function filteredCatalogue() {
        const q = ($('cg-model-filter').value || '').toLowerCase().trim();
        if (!q) return modelCatalogue.slice(0, MAX_SELECT_OPTIONS);
        return modelCatalogue
            .filter(m => (m.id && m.id.toLowerCase().includes(q)) || (m.name && m.name.toLowerCase().includes(q)))
            .slice(0, MAX_SELECT_OPTIONS);
    }

    function stageDefault(stage) {
        return (genConfig && genConfig.stages && genConfig.stages[stage] && genConfig.stages[stage].model) || '';
    }

    function fillSelect(sel, keepValue, defaultLabel) {
        sel.innerHTML = '';
        const optDefault = document.createElement('option');
        optDefault.value = '';
        optDefault.textContent = defaultLabel;
        sel.appendChild(optDefault);
        const list = filteredCatalogue();
        let keepSeen = keepValue === '';
        list.forEach(m => {
            const opt = document.createElement('option');
            opt.value = m.id;
            opt.textContent = `${m.name || m.id}  —  ${m.id}  (${priceHint(m)})`;
            sel.appendChild(opt);
            if (m.id === keepValue) keepSeen = true;
        });
        // The current selection must survive re-filtering even when the
        // filter hides it — pin it right below the default entry.
        if (!keepSeen && keepValue) {
            const pin = document.createElement('option');
            pin.value = keepValue;
            pin.textContent = keepValue + '  (current)';
            sel.insertBefore(pin, sel.children[1] || null);
        }
        sel.value = keepValue;
    }

    function renderModelSection() {
        const host = $('cg-models-body');
        if (catalogueFailed || !modelCatalogue) {
            // Degraded mode: plain text inputs prefilled with config defaults.
            $('cg-model-filter-row').style.display = 'none';
            let html = '<p class="cg-models-note">Model catalogue unavailable (offline?). ' +
                'Type OpenRouter model ids directly; blank = config default.</p>';
            html += modelRowHtml('all', 'All stages', true);
            html += '<div id="cg-stage-models" style="display:none;">';
            STAGES.forEach(s => { html += modelRowHtml(s, s, true); });
            html += '</div>';
            host.innerHTML = html;
        } else {
            $('cg-model-filter-row').style.display = 'flex';
            let html = modelRowHtml('all', 'All stages', false);
            html += '<div id="cg-stage-models" style="display:none;">';
            STAGES.forEach(s => { html += modelRowHtml(s, s, false); });
            html += '</div>';
            host.innerHTML = html;
            refreshModelSelects();
        }
        $('cg-stage-models').style.display = $('cg-models-expand').checked ? 'block' : 'none';
    }

    function modelRowHtml(key, label, textMode) {
        const def = key === 'all' ? '' : stageDefault(key);
        const note = key !== 'all' && genConfig && genConfig.stages && genConfig.stages[key] && genConfig.stages[key].note;
        const control = textMode
            ? `<input type="text" id="cg-model-${key}" class="win98-input" style="flex:1; min-width:0; font-family:monospace;" ` +
              `placeholder="${def ? def.replace(/"/g, '&quot;') : 'model id'}" ${key === 'all' ? 'oninput="cgApplyAllModelText()"' : ''} />`
            : `<select id="cg-model-${key}" class="win98-select" style="flex:1; min-width:0;" ` +
              `${key === 'all' ? 'onchange="cgApplyAllModel()"' : ''}></select>`;
        return `<div class="cg-model-row" ${note ? `title="${note.replace(/"/g, '&quot;')}"` : ''}>` +
               `<label>${label}</label>${control}</div>`;
    }

    window.cgRefilterModels = function() {
        if (!modelCatalogue) return;
        refreshModelSelects();
    };

    function refreshModelSelects() {
        const allSel = $('cg-model-all');
        if (allSel && allSel.tagName === 'SELECT') {
            fillSelect(allSel, allSel.value || '', '(per-stage config defaults)');
        }
        STAGES.forEach(s => {
            const sel = $(`cg-model-${s}`);
            if (sel && sel.tagName === 'SELECT') {
                const def = stageDefault(s);
                fillSelect(sel, sel.value || '', def ? `(default: ${def})` : '(config default)');
            }
        });
    }

    // "All stages" select writes through to every per-stage control.
    window.cgApplyAllModel = function() {
        const v = $('cg-model-all').value;
        STAGES.forEach(s => {
            const sel = $(`cg-model-${s}`);
            if (!sel) return;
            if (v && !Array.from(sel.options).some(o => o.value === v)) {
                const pin = document.createElement('option');
                pin.value = v;
                pin.textContent = v;
                sel.insertBefore(pin, sel.children[1] || null);
            }
            sel.value = v;
        });
    };

    window.cgApplyAllModelText = function() {
        const v = $('cg-model-all').value;
        STAGES.forEach(s => {
            const inp = $(`cg-model-${s}`);
            if (inp) inp.value = v;
        });
    };

    window.cgToggleStageModels = function() {
        $('cg-stage-models').style.display = $('cg-models-expand').checked ? 'block' : 'none';
    };

    // Only stages that differ from the config default are sent as overrides.
    function collectModelOverrides() {
        const models = {};
        STAGES.forEach(s => {
            const el = $(`cg-model-${s}`);
            if (!el) return;
            const v = (el.value || '').trim();
            if (v && v !== stageDefault(s)) models[s] = v;
        });
        return models;
    }

    // ---------------------------------------------------------------
    // Run lifecycle
    // ---------------------------------------------------------------
    window.startCampaignGen = async function() {
        if (runStatus === 'running' || !nameValid() || !pitchFilled()) return;
        const payload = {
            name: $('cg-name').value,
            pitch: $('cg-pitch').value.trim(),
        };
        const models = collectModelOverrides();
        if (Object.keys(models).length) payload.models = models;
        const apiKey = $('cg-api-key').value.trim();
        if (apiKey) payload.apiKey = apiKey;
        const stage = $('cg-stage-select').value;
        if (stage) payload.stage = stage;
        if ($('cg-resume').checked) payload.resume = true;

        appendConsole(`\n> starting generation of campaigns/${payload.name}/ ...\n`);
        try {
            const res = await fetch(`${API_URL}/campaign-gen/start`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            });
            const result = await res.json();
            if (!res.ok || !result.success) {
                appendConsole(`! ${result.message || 'start failed'}\n`);
                setRunStatus(runStatus === 'running' ? 'running' : 'failed');
                return;
            }
            runName = payload.name;
            currentStage = null;
            doneStages = [];
            lastCostLine = '';
            $('cg-cost-readout').textContent = '';
            setRunStatus('running');
            startPolling();
        } catch (e) {
            appendConsole(`! connection failed: ${e.message}\n`);
        }
    };

    window.cancelCampaignGen = async function() {
        try {
            await fetch(`${API_URL}/campaign-gen/cancel`, { method: 'POST' });
            appendConsole('\n> cancel requested\n');
        } catch (e) {
            appendConsole(`! cancel failed: ${e.message}\n`);
        }
    };

    window.activateCampaign = async function() {
        if (!runName) return;
        try {
            const res = await fetch(`${API_URL}/campaign-gen/activate`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name: runName }),
            });
            const result = await res.json();
            if (result.success) {
                showToast(`Campaign '${runName}' is now active.\nTest Play will launch it.`);
            } else {
                showToast('Failed to activate: ' + (result.message || 'unknown error'));
            }
        } catch (e) {
            showToast('Failed to activate: ' + e.message);
        }
    };

    function startPolling() {
        stopPolling();
        pollTimer = setInterval(pollStatus, 700);
    }

    function stopPolling() {
        if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
    }

    async function pollStatus() {
        try {
            const res = await fetch(`${API_URL}/campaign-gen/status?from=${logOffset}`);
            const st = await res.json();
            applyStatusPayload(st);
            if (st.status !== 'running') {
                stopPolling();
                if (st.status === 'success') {
                    doneStages = STRIP_STAGES.slice();
                    currentStage = null;
                    renderStageStrip();
                }
                setRunStatus(st.status);
            }
        } catch (e) {
            // Server vanished mid-run: stop hammering, mark failed.
            stopPolling();
            appendConsole('\n! lost connection to the editor server\n');
            setRunStatus('failed');
        }
    }

    function applyStatusPayload(st) {
        if (typeof st.chunk === 'string' && st.chunk.length) {
            appendConsole(st.chunk);
            parseLogChunk(st.chunk);
        }
        if (typeof st.len === 'number') logOffset = st.len;
        if (st.status && st.status !== runStatus) setRunStatus(st.status);
    }

    // Scrape stage headers + usage totals out of the raw gen.js log.
    function parseLogChunk(chunk) {
        const stageRe = /^--- stage: (\w+)/gm;
        let m;
        while ((m = stageRe.exec(chunk)) !== null) {
            setCurrentStage(m[1] === 'repair' ? 'validate' : m[1]);
        }
        if (/^validate round \d+/m.test(chunk) || /-> asking repair model/.test(chunk)) {
            setCurrentStage('validate');
        }
        const costRe = /run total: [^\n]+/g;
        let c, last = null;
        while ((c = costRe.exec(chunk)) !== null) last = c[0];
        if (last) {
            lastCostLine = last;
            $('cg-cost-readout').textContent = lastCostLine;
        }
    }

    function setCurrentStage(stage) {
        if (!STRIP_STAGES.includes(stage)) return;
        if (currentStage === stage) return;
        // Everything before the new stage in strip order counts as done.
        const idx = STRIP_STAGES.indexOf(stage);
        doneStages = STRIP_STAGES.slice(0, idx);
        currentStage = stage;
        renderStageStrip();
    }

    function setRunStatus(status) {
        runStatus = status;
        renderRunState();
    }

    // ---------------------------------------------------------------
    // Rendering
    // ---------------------------------------------------------------
    function updateRunControls() {
        const running = runStatus === 'running';
        $('cg-generate-btn').disabled = running || !nameValid() || !pitchFilled();
        $('cg-cancel-btn').style.display = running ? 'inline-flex' : 'none';
        const succeeded = runStatus === 'success' && runName;
        $('cg-activate-btn').disabled = !succeeded;
        $('cg-testplay-btn').disabled = !succeeded;
        $('cg-success-hint').style.display = succeeded ? 'block' : 'none';
        if (succeeded) {
            $('cg-walkthrough-path').textContent = `campaigns/${runName}/WALKTHROUGH.md`;
        }
    }

    function renderRunState() {
        const chip = $('cg-status-chip');
        chip.textContent = runStatus;
        chip.className = 'cg-chip cg-chip-' + runStatus;
        renderStageStrip();
        updateRunControls();
    }

    function renderStageStrip() {
        const host = $('cg-stage-strip');
        host.innerHTML = '';
        STRIP_STAGES.forEach((s, i) => {
            if (i > 0) {
                const arrow = document.createElement('span');
                arrow.className = 'cg-stage-arrow';
                arrow.textContent = '›';
                host.appendChild(arrow);
            }
            const el = document.createElement('span');
            el.className = 'cg-stage';
            if (doneStages.includes(s)) el.classList.add('cg-stage-done');
            if (currentStage === s && runStatus === 'running') el.classList.add('cg-stage-active');
            el.textContent = s;
            host.appendChild(el);
        });
    }

    function appendConsole(text) {
        const con = $('cg-console');
        con.textContent += text;
        // Keep the DOM node bounded like the server-side buffer.
        if (con.textContent.length > 400000) {
            con.textContent = con.textContent.slice(-300000);
        }
        if (consolePinned) con.scrollTop = con.scrollHeight;
    }

    // Pin-to-bottom console behavior: stick unless the user scrolled up.
    document.addEventListener('DOMContentLoaded', () => {
        const con = $('cg-console');
        if (!con) return;
        con.addEventListener('scroll', () => {
            consolePinned = con.scrollTop + con.clientHeight >= con.scrollHeight - 8;
        });
    });
})();
