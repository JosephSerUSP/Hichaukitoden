
        // --- ASSET PICKER IMPLEMENTATION ---
        let activeAssetCallback = null;

        window.createSpriteField = function(container, labelText, value, onChange, useBlockLayout = false, defaultDir = 'sprites', isBareKey = false) {
            const group = document.createElement('div');
            group.className = 'form-group';

            const lbl = document.createElement('label');
            lbl.textContent = labelText;
            lbl.style.marginBottom = '2px';
            group.appendChild(lbl);

            // Thumbnail-row: thumbnail + path label
            const thumbRow = document.createElement('div');
            thumbRow.style.cssText = 'display: flex; align-items: center; gap: 6px;';

            const thumbWrap = document.createElement('div');
            thumbWrap.style.cssText = 'width: 48px; height: 48px; border: 1px inset var(--win-shadow); background: #000; display: inline-flex; align-items: center; justify-content: center; overflow: hidden; flex-shrink: 0; cursor: pointer;';
            thumbWrap.title = 'Double-click to select image';

            const img = document.createElement('img');
            img.style.cssText = 'max-width: 100%; max-height: 100%; image-rendering: pixelated;';

            const noneTxt = document.createElement('div');
            noneTxt.style.cssText = 'color: #888; font-size: 9px; font-family: monospace;';
            noneTxt.textContent = '(none)';

            // A missing/broken sprite falls back to the (none) placeholder
            // rather than the browser's broken-image glyph.
            img.onerror = () => { img.style.display = 'none'; noneTxt.style.display = 'block'; };

            function updateThumb(path) {
                if (path) {
                    path = path.replace(/\\/g, '/');
                    if (isBareKey && !path.includes('/')) {
                        img.src = '/assets/' + defaultDir + '/' + path + '.png';
                    } else {
                        img.src = '/' + path;
                    }
                    img.style.display = 'block';
                    noneTxt.style.display = 'none';
                } else {
                    img.style.display = 'none';
                    noneTxt.style.display = 'block';
                }
            }
            updateThumb(value);

            thumbWrap.appendChild(img);
            thumbWrap.appendChild(noneTxt);
            thumbRow.appendChild(thumbWrap);

            group.appendChild(thumbRow);

            // Double-click on thumbnail opens asset picker
            thumbWrap.ondblclick = () => openAssetPicker(defaultDir, path => {
                if (isBareKey) {
                    const parts = path.replace(/\\/g, '/').split('/');
                    const filename = parts.pop();
                    path = filename.replace(/\.[^/.]+$/, ""); // remove extension
                }
                updateThumb(path);
                onChange(path);
            });

            container.appendChild(group);
        };

        function openAssetPicker(defaultDir, callback) {
            activeAssetCallback = callback;
            document.getElementById('asset-picker-selected').value = '';
            // Clear preview
            const prevImg = document.getElementById('asset-preview-img');
            const prevNone = document.getElementById('asset-preview-none');
            if (prevImg) { prevImg.style.display = 'none'; prevImg.src = ''; }
            if (prevNone) prevNone.style.display = 'block';

            fetch(`/api/assets?dir=${encodeURIComponent(defaultDir)}`)
                .then(r => r.json())
                .then(data => {
                    const dirSelect = document.getElementById('asset-picker-dir');
                    dirSelect.innerHTML = '';
                    data.directories.forEach(d => {
                        const opt = document.createElement('option');
                        opt.value = d;
                        opt.textContent = d;
                        if (d === defaultDir) opt.selected = true;
                        dirSelect.appendChild(opt);
                    });

                    renderAssetPickerFiles(data.files);
                    document.getElementById('asset-picker-modal').classList.add('active');
                });
        }

        function loadAssetPickerFiles() {
            const dir = document.getElementById('asset-picker-dir').value;
            fetch(`/api/assets?dir=${encodeURIComponent(dir)}`)
                .then(r => r.json())
                .then(data => {
                    renderAssetPickerFiles(data.files);
                });
        }

        function renderAssetPickerFiles(files) {
            const grid = document.getElementById('asset-picker-grid');
            grid.innerHTML = '';

            files.forEach(f => {
                const card = document.createElement('div');
                card.style.border = '1px solid #c0c0c0';
                card.style.padding = '4px';
                card.style.cursor = 'pointer';
                card.style.display = 'flex';
                card.style.flexDirection = 'column';
                card.style.alignItems = 'center';
                card.style.justifyContent = 'center';
                card.style.background = '#f0f0f0';
                card.style.fontSize = '9px';
                card.style.textAlign = 'center';
                card.style.height = '64px';
                card.style.boxSizing = 'border-box';

                const img = document.createElement('img');
                img.src = '/' + f;
                img.style.maxHeight = '32px';
                img.style.maxWidth = '100%';
                img.style.display = 'block';
                img.style.marginBottom = '2px';
                card.appendChild(img);

                const name = document.createElement('div');
                name.textContent = f.split('/').pop();
                name.style.overflow = 'hidden';
                name.style.textOverflow = 'ellipsis';
                name.style.whiteSpace = 'nowrap';
                name.style.width = '100%';
                card.appendChild(name);

                card.onclick = () => {
                    document.querySelectorAll('#asset-picker-grid > div').forEach(c => c.style.border = '1px solid #c0c0c0');
                    card.style.border = '2px solid var(--win-blue)';
                    document.getElementById('asset-picker-selected').value = f;
                    // Update the full-resolution preview
                    const prevImg = document.getElementById('asset-preview-img');
                    const prevNone = document.getElementById('asset-preview-none');
                    if (prevImg && prevNone) {
                        prevImg.src = '/' + f;
                        prevImg.style.display = 'block';
                        prevNone.style.display = 'none';
                    }
                };

                grid.appendChild(card);
            });
        }

        function applyAssetSelection() {
            const path = document.getElementById('asset-picker-selected').value;
            if (!path) {
                alert('Please select an asset file.');
                return;
            }
            closeAssetPicker();
            if (activeAssetCallback) activeAssetCallback(path);
        }

        function closeAssetPicker() {
            document.getElementById('asset-picker-modal').classList.remove('active');
        }

        // ---- Shared structured editors (used by Skills/Passives/States/Actors/Items forms) ----

        // Effect types and trait codes come from the engine registry
        // (data/engine.json), editable in the Engine editor. The literals here
        // are only fallbacks for payloads saved before the registry existed.
        function effectTypeOptions() {
            const reg = (dbPayload.engine && dbPayload.engine.effectTypes) || [];
            if (reg.length) return reg.map(et => ({ value: et.id, label: et.label || et.id, title: et.description || '' }));
            return ['hp_damage', 'hp_heal', 'hp_drain', 'add_status', 'hp', 'maxHp', 'xp'];
        }
        function traitCodeOptions() {
            const reg = (dbPayload.engine && dbPayload.engine.traitCodes) || [];
            if (reg.length) return reg.map(tc => ({ value: tc.code, label: tc.label || tc.code, title: tc.description || '' }));
            return ['PARAM_PLUS', 'PARAM_RATE', 'HIT', 'EVA', 'CRI', 'HRG'];
        }
        function traitUsesDataId(code) {
            const reg = (dbPayload.engine && dbPayload.engine.traitCodes) || [];
            const entry = reg.find(tc => tc.code === code);
            if (entry) return !!entry.usesDataId;
            return code === 'PARAM_PLUS' || code === 'PARAM_RATE' || code === 'ELEMENT_CHANGE';
        }
        const PARAM_IDS = ['maxHp', 'atk', 'def', 'mat', 'mdf', 'asp', 'mpd'];
        const SKILL_TARGETS = ['enemy', 'enemy-any', 'ally-any', 'self'];
        function elementOptions(includeNone) {
            const names = Object.keys(dbPayload.elements || {});
            const opts = names.length ? names : ['White', 'Black', 'Green', 'Red', 'Blue', 'Yellow'];
            return includeNone ? [''].concat(opts) : opts;
        }

        window.cmdParamWidgets = window.cmdParamWidgets || {};
        window.cmdParamWidgets.term = function(current, onChange) {
            const terms = [];
            function walk(obj, path) {
                if (!obj || typeof obj !== 'object') return;
                for (const k in obj) {
                    const newPath = path ? path + '.' + k : k;
                    if (typeof obj[k] === 'string') {
                        terms.push(newPath);
                    } else if (typeof obj[k] === 'object') {
                        walk(obj[k], newPath);
                    }
                }
            }
            if (window.dbPayload && window.dbPayload.terms) {
                walk(window.dbPayload.terms, '');
            }

            const sel = document.createElement('select');
            sel.className = 'win98-select';
            sel.style.width = '100%';

            const defaultOpt = document.createElement('option');
            defaultOpt.value = '';
            defaultOpt.textContent = '(none)';
            sel.appendChild(defaultOpt);

            terms.forEach(t => {
                const opt = document.createElement('option');
                opt.value = t;
                opt.textContent = t;
                if (current === t) opt.selected = true;
                sel.appendChild(opt);
            });

            sel.onchange = () => { onChange(sel.value); };
            return sel;
        };

        function createGraphPicker(current, onChange, flex) {
            const sel = document.createElement('select');
            sel.className = 'win98-select';
            if (flex) sel.style.flex = flex;

            const defaultOpt = document.createElement('option');
            defaultOpt.value = '';
            defaultOpt.textContent = '(none)';
            sel.appendChild(defaultOpt);

            fetch('/api/graphs')
                .then(r => r.json())
                .then(graphs => {
                    graphs.forEach(g => {
                        const opt = document.createElement('option');
                        opt.value = g;
                        opt.textContent = g;
                        if (current === g) opt.selected = true;
                        sel.appendChild(opt);
                    });
                })
                .catch(e => console.error('Failed to load graphs', e));

            sel.onchange = () => { onChange(sel.value); setDirty(true); };
            return sel;
        }

        function createMapPicker(current, onChange, flex) {
            const mapOpts = dbPayload.maps ? dbPayload.maps.map((m, i) => ({ value: String(i + 1), label: m.title || ('Map ' + (i + 1)) })) : [];
            return makeSelect(mapOpts, current, onChange, flex);
        }

        function makeSelect(options, current, onChange, flex) {
            const sel = document.createElement('select');
            sel.className = 'win98-select';
            if (flex) sel.style.flex = flex;
            // Registry-sourced descriptions surface as native tooltips, both
            // per-option and on the select (kept in sync with the selection).
            const syncTitle = () => {
                const chosen = sel.options[sel.selectedIndex];
                sel.title = (chosen && chosen.title) || '';
            };
            options.forEach(o => {
                const opt = document.createElement('option');
                opt.value = o.value !== undefined ? o.value : o;
                opt.textContent = o.label !== undefined ? o.label : (o === '' ? '(none)' : o);
                if (o.title) opt.title = o.title;
                if (opt.value === String(current !== undefined && current !== null ? current : '')) opt.selected = true;
                sel.appendChild(opt);
            });
            syncTitle();
            sel.onchange = () => { onChange(sel.value); setDirty(true); syncTitle(); };
            return sel;
        }

        function makeListBox() {
            const box = document.createElement('div');
            box.style.cssText = 'border: 1px solid var(--win-shadow); background: #fff; padding: 4px; display: flex; flex-direction: column; gap: 2px;';
            return box;
        }

        function makeRowDeleteBtn(onDelete) {
            const del = document.createElement('button');
            del.className = 'win98-btn';
            del.style.cssText = 'min-width: 20px; color: #cc0000; font-weight: bold;';
            del.textContent = '×';
            del.onclick = () => { onDelete(); setDirty(true); };
            return del;
        }

        function makeAddRowBtn(label, onAdd) {
            const btn = document.createElement('button');
            btn.className = 'win98-btn';
            btn.style.cssText = 'font-size: 10px; align-self: flex-start; margin-top: 2px;';
            btn.textContent = label;
            btn.onclick = () => { onAdd(); setDirty(true); };
            return btn;
        }

        // Editable list of skill/item effect rows ({type, formula|value|status...})
        function buildEffectsEditor(container, owner) {
            owner.effects = owner.effects || [];
            const group = document.createElement('div');
            group.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = 'Effects';
            group.appendChild(lbl);
            const box = makeListBox();

            const render = () => {
                box.innerHTML = '';
                owner.effects.forEach((eff, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                    row.appendChild(makeSelect(effectTypeOptions(), eff.type, v => {
                        eff.type = v;
                        render();
                    }));

                    if (eff.type === 'hp_damage' || eff.type === 'hp_heal' || eff.type === 'hp_drain') {
                        const f = document.createElement('input');
                        f.className = 'win98-input';
                        f.style.flex = '1';
                        f.placeholder = 'formula, e.g. 6 + 1.2 * a.level';
                        f.value = eff.formula || '';
                        f.oninput = () => { eff.formula = f.value; setDirty(true); };
                        row.appendChild(f);
                    } else if (eff.type === 'add_status') {
                        const stateIds = Object.keys(dbPayload.states || {});
                        row.appendChild(makeSelect(stateIds, eff.status, v => { eff.status = v; }, '1'));
                        const chance = document.createElement('input');
                        chance.type = 'number'; chance.step = '0.05'; chance.min = '0'; chance.max = '1';
                        chance.className = 'win98-input'; chance.style.width = '52px';
                        chance.title = 'Chance (0-1)';
                        chance.value = eff.chance !== undefined ? eff.chance : 1;
                        chance.oninput = () => { eff.chance = parseFloat(chance.value) || 0; setDirty(true); };
                        row.appendChild(chance);
                        const dur = document.createElement('input');
                        dur.type = 'number'; dur.className = 'win98-input'; dur.style.width = '44px';
                        dur.title = 'Duration (turns)';
                        dur.value = eff.duration !== undefined ? eff.duration : 3;
                        dur.oninput = () => { eff.duration = parseInt(dur.value) || 0; setDirty(true); };
                        row.appendChild(dur);
                    } else {
                        const v = document.createElement('input');
                        v.type = 'number';
                        v.className = 'win98-input';
                        v.style.flex = '1';
                        v.title = 'Effect value';
                        v.value = eff.value !== undefined ? eff.value : 0;
                        v.oninput = () => { eff.value = parseInt(v.value) || 0; setDirty(true); };
                        row.appendChild(v);
                    }

                    row.appendChild(makeRowDeleteBtn(() => { owner.effects.splice(idx, 1); render(); }));
                    box.appendChild(row);
                });
                box.appendChild(makeAddRowBtn('+ Add Effect', () => {
                    owner.effects.push({ type: 'hp_damage', formula: '' });
                    render();
                }));
            };
            render();
            group.appendChild(box);
            container.appendChild(group);
        }

        // Editable list of trait rows ({code, dataId?, value})
        function buildTraitsEditor(container, owner, label) {
            owner.traits = owner.traits || [];
            const group = document.createElement('div');
            group.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = label || 'Traits';
            group.appendChild(lbl);
            const box = makeListBox();

            const render = () => {
                box.innerHTML = '';
                owner.traits.forEach((tr, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                    row.appendChild(makeSelect(traitCodeOptions(), tr.code, v => {
                        tr.code = v;
                        if (!traitUsesDataId(v)) delete tr.dataId;
                        render();
                    }, '1'));
                    if (traitUsesDataId(tr.code)) {
                        // ELEMENT_CHANGE's dataId is an element; param traits use stat ids
                        const dataIdOpts = tr.code === 'ELEMENT_CHANGE' ? elementOptions(false) : PARAM_IDS;
                        row.appendChild(makeSelect(dataIdOpts, tr.dataId || dataIdOpts[0], v => { tr.dataId = v; }));
                    }
                    const v = document.createElement('input');
                    v.type = 'number'; v.step = 'any';
                    v.className = 'win98-input';
                    v.style.width = '64px';
                    v.title = 'Trait value';
                    v.value = tr.value !== undefined ? tr.value : 0;
                    v.oninput = () => { tr.value = parseFloat(v.value) || 0; setDirty(true); };
                    row.appendChild(v);
                    row.appendChild(makeRowDeleteBtn(() => { owner.traits.splice(idx, 1); render(); }));
                    box.appendChild(row);
                });
                box.appendChild(makeAddRowBtn('+ Add Trait', () => {
                    owner.traits.push({ code: 'PARAM_PLUS', dataId: 'atk', value: 1 });
                    render();
                }));
            };
            render();
            group.appendChild(box);
            container.appendChild(group);
        }

        // Editable list of animation track rows
        function buildTracksEditor(container, anim) {
            anim.tracks = anim.tracks || [];
            const originalSetDirty = window.setDirty || (typeof setDirty !== 'undefined' ? setDirty : () => {});
            const localSetDirty = (val) => {
                originalSetDirty(val);
                if (window.onAnimationTrackChanged) window.onAnimationTrackChanged();
            };
            const setDirty = localSetDirty;

            const group = document.createElement('div');
            group.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = 'Tracks';
            group.appendChild(lbl);

            const box = makeListBox();
            box.style.maxHeight = '400px';
            box.style.overflowY = 'auto';

            const rgb01ToHex = c => '#' + (c || [1, 1, 1]).slice(0, 3)
                .map(v => Math.round((v || 0) * 255).toString(16).padStart(2, '0')).join('');
            const hexToRgb01 = hex => [1, 3, 5].map(i => Math.round(parseInt(hex.substr(i, 2), 16) / 255 * 100) / 100);

            const render = () => {
                box.innerHTML = '';
                anim.tracks.forEach((tr, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'border: 1px solid var(--win-shadow); padding: 6px; margin-bottom: 8px; background: var(--win-gray); display: flex; flex-direction: column; gap: 4px;';

                    const topRow = document.createElement('div');
                    topRow.style.cssText = 'display: flex; gap: 6px; align-items: center; flex-wrap: wrap;';

                    const t0Lbl = document.createElement('span');
                    t0Lbl.textContent = 't0:';
                    t0Lbl.style.fontSize = '10px';
                    topRow.appendChild(t0Lbl);

                    const t0Input = document.createElement('input');
                    t0Input.type = 'number';
                    t0Input.className = 'win98-input';
                    t0Input.style.width = '50px';
                    t0Input.value = tr.t0 !== undefined ? tr.t0 : 0;
                    t0Input.oninput = () => { tr.t0 = parseInt(t0Input.value) || 0; setDirty(true); };
                    topRow.appendChild(t0Input);

                    const durLbl = document.createElement('span');
                    durLbl.textContent = 'Dur:';
                    durLbl.style.fontSize = '10px';
                    topRow.appendChild(durLbl);

                    const durInput = document.createElement('input');
                    durInput.type = 'number';
                    durInput.className = 'win98-input';
                    durInput.style.width = '50px';
                    durInput.value = tr.duration !== undefined ? tr.duration : 100;
                    durInput.oninput = () => { tr.duration = parseInt(durInput.value) || 0; setDirty(true); };
                    topRow.appendChild(durInput);

                    const typeLbl = document.createElement('span');
                    typeLbl.textContent = 'Type:';
                    typeLbl.style.fontSize = '10px';
                    topRow.appendChild(typeLbl);

                    const trackTypes = [
                        { value: 'tint', label: 'Tint' },
                        { value: 'blend', label: 'Blend Mode' },
                        { value: 'transform', label: 'Transform' },
                        { value: 'shake', label: 'Shake' },
                        { value: 'particles', label: 'Particles' },
                        { value: 'text_flow', label: 'Text Flow' }
                    ];
                    
                    const isKnownType = trackTypes.some(tt => tt.value === tr.type);
                    
                    const typeSelect = makeSelect(trackTypes, tr.type, val => {
                        tr.type = val;
                        Object.keys(tr).forEach(k => {
                            if (k !== 'type' && k !== 't0' && k !== 'duration' && k !== 'easing') {
                                delete tr[k];
                            }
                        });
                        if (val === 'tint') {
                            tr.color = [1, 1, 1];
                            tr.fromAlpha = 1;
                            tr.toAlpha = 0;
                        } else if (val === 'blend') {
                            tr.mode = 'add';
                        } else if (val === 'transform') {
                            tr.fromX = 0; tr.toX = 0; tr.fromY = 0; tr.toY = 0;
                        } else if (val === 'shake') {
                            tr.amplitude = 2;
                            tr.frequency = 30;
                        } else if (val === 'particles') {
                            tr.rate = 10; tr.lifetime = 0.5; tr.spread = 45; tr.velocity = 50; tr.gravity = 0;
                        } else if (val === 'text_flow') {
                            tr.sequence = '...'; tr.interval = 100; tr.color = [1, 1, 1]; tr.targetPart = 'hp_gauge';
                        }
                        setDirty(true);
                        render();
                    });
                    
                    if (!isKnownType) {
                        typeSelect.disabled = true;
                        typeSelect.innerHTML = `<option value="${tr.type}">${tr.type} (Unknown)</option>`;
                    }
                    
                    topRow.appendChild(typeSelect);

                    const easeLbl = document.createElement('span');
                    easeLbl.textContent = 'Ease:';
                    easeLbl.style.fontSize = '10px';
                    topRow.appendChild(easeLbl);

                    const easingOpts = [
                        { value: 'linear', label: 'Linear' },
                        { value: 'ease_out', label: 'Ease Out' }
                    ];
                    const easeSelect = makeSelect(easingOpts, tr.easing || 'linear', val => {
                        tr.easing = val;
                        setDirty(true);
                    });
                    if (!isKnownType) {
                        easeSelect.disabled = true;
                    }
                    topRow.appendChild(easeSelect);

                    const controls = document.createElement('div');
                    controls.style.cssText = 'display: flex; gap: 2px; margin-left: auto;';

                    const upBtn = document.createElement('button');
                    upBtn.className = 'win98-btn';
                    upBtn.textContent = '▲';
                    upBtn.style.padding = '0 3px';
                    upBtn.disabled = idx === 0;
                    upBtn.onclick = (e) => {
                        e.preventDefault();
                        anim.tracks.splice(idx, 1);
                        anim.tracks.splice(idx - 1, 0, tr);
                        setDirty(true);
                        render();
                    };
                    controls.appendChild(upBtn);

                    const dnBtn = document.createElement('button');
                    dnBtn.className = 'win98-btn';
                    dnBtn.textContent = '▼';
                    dnBtn.style.padding = '0 3px';
                    dnBtn.disabled = idx === anim.tracks.length - 1;
                    dnBtn.onclick = (e) => {
                        e.preventDefault();
                        anim.tracks.splice(idx, 1);
                        anim.tracks.splice(idx + 1, 0, tr);
                        setDirty(true);
                        render();
                    };
                    controls.appendChild(dnBtn);

                    controls.appendChild(makeRowDeleteBtn(() => {
                        anim.tracks.splice(idx, 1);
                        setDirty(true);
                        render();
                    }));

                    topRow.appendChild(controls);
                    row.appendChild(topRow);

                    if (isKnownType) {
                        const paramRow = document.createElement('div');
                        paramRow.style.cssText = 'display: flex; gap: 8px; align-items: center; padding: 4px; background: var(--win-white); border: 1px inset var(--win-shadow); flex-wrap: wrap;';

                        if (tr.type === 'tint') {
                            const colPick = document.createElement('input');
                            colPick.type = 'color';
                            colPick.value = rgb01ToHex(tr.color);
                            colPick.oninput = () => {
                                tr.color = hexToRgb01(colPick.value);
                                setDirty(true);
                            };
                            paramRow.appendChild(colPick);

                            const faLbl = document.createElement('span');
                            faLbl.textContent = 'Alpha Start:';
                            faLbl.style.fontSize = '10px';
                            paramRow.appendChild(faLbl);

                            const faInput = document.createElement('input');
                            faInput.type = 'number';
                            faInput.step = '0.1';
                            faInput.className = 'win98-input';
                            faInput.style.width = '40px';
                            faInput.value = tr.fromAlpha !== undefined ? tr.fromAlpha : 1;
                            faInput.oninput = () => { tr.fromAlpha = parseFloat(faInput.value) || 0; setDirty(true); };
                            paramRow.appendChild(faInput);

                            const taLbl = document.createElement('span');
                            taLbl.textContent = 'End:';
                            taLbl.style.fontSize = '10px';
                            paramRow.appendChild(taLbl);

                            const taInput = document.createElement('input');
                            taInput.type = 'number';
                            taInput.step = '0.1';
                            taInput.className = 'win98-input';
                            taInput.style.width = '40px';
                            taInput.value = tr.toAlpha !== undefined ? tr.toAlpha : 0;
                            taInput.oninput = () => { tr.toAlpha = parseFloat(taInput.value) || 0; setDirty(true); };
                            paramRow.appendChild(taInput);

                        } else if (tr.type === 'blend') {
                            const modeSelect = makeSelect([
                                { value: 'add', label: 'Add' },
                                { value: 'alpha', label: 'Alpha' }
                            ], tr.mode || 'add', val => {
                                tr.mode = val;
                                setDirty(true);
                            });
                            paramRow.appendChild(modeSelect);

                        } else if (tr.type === 'transform') {
                            const addCoord = (lblText, key) => {
                                const l = document.createElement('span');
                                l.textContent = lblText + ':';
                                l.style.fontSize = '10px';
                                paramRow.appendChild(l);
                                const inp = document.createElement('input');
                                inp.type = 'number';
                                inp.className = 'win98-input';
                                inp.style.width = '35px';
                                inp.value = tr[key] !== undefined ? tr[key] : 0;
                                inp.dataset.trackIndex = idx;
                                inp.dataset.paramKey = key;
                                inp.oninput = () => {
                                    tr[key] = parseInt(inp.value) || 0;
                                    setDirty(true);
                                    if (anim.drawOverlayHandles) anim.drawOverlayHandles();
                                };
                                paramRow.appendChild(inp);
                            };
                            addCoord('fromX', 'fromX');
                            addCoord('toX', 'toX');
                            addCoord('fromY', 'fromY');
                            addCoord('toY', 'toY');
                            
                            const addScale = (lblText, key) => {
                                const l = document.createElement('span');
                                l.textContent = lblText + ':';
                                l.style.fontSize = '10px';
                                paramRow.appendChild(l);
                                const inp = document.createElement('input');
                                inp.type = 'number';
                                inp.step = '0.1';
                                inp.className = 'win98-input';
                                inp.style.width = '35px';
                                inp.value = tr[key] !== undefined ? tr[key] : 1.0;
                                inp.oninput = () => { tr[key] = parseFloat(inp.value) || 1.0; setDirty(true); };
                                paramRow.appendChild(inp);
                            };
                            addScale('fromSX', 'fromScaleX');
                            addScale('toSX', 'toScaleX');
                            addScale('fromSY', 'fromScaleY');
                            addScale('toSY', 'toScaleY');

                        } else if (tr.type === 'shake') {
                            const ampLbl = document.createElement('span');
                            ampLbl.textContent = 'Amplitude:';
                            ampLbl.style.fontSize = '10px';
                            paramRow.appendChild(ampLbl);

                            const ampInput = document.createElement('input');
                            ampInput.type = 'number';
                            ampInput.className = 'win98-input';
                            ampInput.style.width = '40px';
                            ampInput.value = tr.amplitude !== undefined ? tr.amplitude : 2;
                            ampInput.oninput = () => { tr.amplitude = parseInt(ampInput.value) || 0; setDirty(true); };
                            paramRow.appendChild(ampInput);

                            const freqLbl = document.createElement('span');
                            freqLbl.textContent = 'Freq:';
                            freqLbl.style.fontSize = '10px';
                            paramRow.appendChild(freqLbl);

                            const freqInput = document.createElement('input');
                            freqInput.type = 'number';
                            freqInput.className = 'win98-input';
                            freqInput.style.width = '40px';
                            freqInput.value = tr.frequency !== undefined ? tr.frequency : 30;
                            freqInput.oninput = () => { tr.frequency = parseInt(freqInput.value) || 0; setDirty(true); };
                            paramRow.appendChild(freqInput);

                        } else if (tr.type === 'particles') {
                            const addPartParam = (lblText, key, def) => {
                                const l = document.createElement('span');
                                l.textContent = lblText + ':';
                                l.style.fontSize = '9px';
                                paramRow.appendChild(l);
                                const inp = document.createElement('input');
                                inp.type = 'number';
                                inp.className = 'win98-input';
                                inp.style.width = '35px';
                                inp.value = tr[key] !== undefined ? tr[key] : def;
                                inp.dataset.trackIndex = idx;
                                inp.dataset.paramKey = key;
                                inp.oninput = () => {
                                    tr[key] = parseFloat(inp.value) || 0;
                                    setDirty(true);
                                    if ((key === 'x' || key === 'y') && anim.drawOverlayHandles) {
                                        anim.drawOverlayHandles();
                                    }
                                };
                                paramRow.appendChild(inp);
                            };
                            addPartParam('Rate', 'rate', 10);
                            addPartParam('Life', 'lifetime', 0.5);
                            addPartParam('Spread', 'spread', 45);
                            addPartParam('Vel', 'velocity', 50);
                            addPartParam('Grav', 'gravity', 0);
                            addPartParam('X', 'x', 0);
                            addPartParam('Y', 'y', 0);

                            addPartParam('QWidth', 'quadWidth', '');
                            addPartParam('QHeight', 'quadHeight', '');
                            addPartParam('QCount', 'quadCount', '');

                            const maskLbl = document.createElement('span');
                            maskLbl.textContent = 'Mask Target:';
                            maskLbl.style.fontSize = '9px';
                            paramRow.appendChild(maskLbl);

                            const maskChk = document.createElement('input');
                            maskChk.type = 'checkbox';
                            maskChk.checked = tr.mask === 'target';
                            maskChk.onchange = () => {
                                if (maskChk.checked) tr.mask = 'target';
                                else delete tr.mask;
                                setDirty(true);
                            };
                            paramRow.appendChild(maskChk);

                            const texLbl = document.createElement('span');
                            texLbl.textContent = 'Texture:';
                            texLbl.style.fontSize = '9px';
                            paramRow.appendChild(texLbl);

                            const texInput = document.createElement('input');
                            texInput.type = 'text';
                            texInput.className = 'win98-input';
                            texInput.style.width = '100px';
                            texInput.value = tr.particleTexture || '';
                            texInput.oninput = () => {
                                tr.particleTexture = texInput.value || undefined;
                                setDirty(true);
                            };
                            paramRow.appendChild(texInput);

                            const browseBtn = document.createElement('button');
                            browseBtn.className = 'win98-btn';
                            browseBtn.textContent = '...';
                            browseBtn.style.padding = '0 4px';
                            browseBtn.onclick = (e) => {
                                e.preventDefault();
                                openAssetPicker('animation', (filepath) => {
                                    texInput.value = filepath.replace(/\\/g, '/');
                                    tr.particleTexture = texInput.value;
                                    setDirty(true);
                                });
                            };
                            paramRow.appendChild(browseBtn);

                            const colOverLbl = document.createElement('span');
                            colOverLbl.textContent = 'Colors:';
                            colOverLbl.style.fontSize = '9px';
                            paramRow.appendChild(colOverLbl);

                            const colOverLife = document.createElement('input');
                            colOverLife.type = 'text';
                            colOverLife.className = 'win98-input';
                            colOverLife.style.width = '120px';
                            colOverLife.value = JSON.stringify(tr.colorOverLife || [[1, 1, 1, 1], [1, 1, 1, 0]]);
                            colOverLife.oninput = () => {
                                try {
                                    tr.colorOverLife = JSON.parse(colOverLife.value);
                                    setDirty(true);
                                    colOverLife.style.backgroundColor = '';
                                } catch (e) {
                                    colOverLife.style.backgroundColor = '#ffcccc';
                                }
                            };
                            paramRow.appendChild(colOverLife);

                        } else if (tr.type === 'text_flow') {
                            const seqLbl = document.createElement('span');
                            seqLbl.textContent = 'Sequence:';
                            seqLbl.style.fontSize = '10px';
                            paramRow.appendChild(seqLbl);

                            const seqInput = document.createElement('input');
                            seqInput.type = 'text';
                            seqInput.className = 'win98-input';
                            seqInput.style.width = '60px';
                            seqInput.value = tr.sequence || '';
                            seqInput.oninput = () => { tr.sequence = seqInput.value; setDirty(true); };
                            paramRow.appendChild(seqInput);

                            const intLbl = document.createElement('span');
                            intLbl.textContent = 'Interval:';
                            intLbl.style.fontSize = '10px';
                            paramRow.appendChild(intLbl);

                            const intInput = document.createElement('input');
                            intInput.type = 'number';
                            intInput.className = 'win98-input';
                            intInput.style.width = '45px';
                            intInput.value = tr.interval || 100;
                            intInput.oninput = () => { tr.interval = parseInt(intInput.value) || 100; setDirty(true); };
                            paramRow.appendChild(intInput);

                            const colPick = document.createElement('input');
                            colPick.type = 'color';
                            colPick.value = rgb01ToHex(tr.color);
                            colPick.oninput = () => {
                                tr.color = hexToRgb01(colPick.value);
                                setDirty(true);
                            };
                            paramRow.appendChild(colPick);

                            const partLbl = document.createElement('span');
                            partLbl.textContent = 'Part:';
                            partLbl.style.fontSize = '10px';
                            paramRow.appendChild(partLbl);

                            const partSelect = makeSelect([
                                { value: 'hp_gauge', label: 'HP Gauge' },
                                { value: 'mp_gauge', label: 'MP Gauge' },
                                { value: 'top', label: 'Top / Head' }
                            ], tr.targetPart || 'hp_gauge', val => {
                                tr.targetPart = val;
                                setDirty(true);
                            });
                            paramRow.appendChild(partSelect);
                        }

                        row.appendChild(paramRow);
                    } else {
                        const unknownRow = document.createElement('div');
                        unknownRow.style.cssText = 'padding: 4px; background: var(--win-white); border: 1px inset var(--win-shadow); font-family: monospace; font-size: 10px; color: var(--win-dark-shadow);';
                        unknownRow.textContent = JSON.stringify(tr);
                        row.appendChild(unknownRow);
                    }

                    box.appendChild(row);
                });

                box.appendChild(makeAddRowBtn('+ Add Track', () => {
                    anim.tracks.push({ type: 'tint', t0: 0, duration: 500, color: [1, 1, 1], fromAlpha: 1, toAlpha: 0, easing: 'linear' });
                    setDirty(true);
                    render();
                }));
            };

            render();
            group.appendChild(box);
            container.appendChild(group);
        }

        // Checkbox list bound to an array of ids (actor skills/passives)
        function buildChecklistField(container, label, allIds, nameOf, ownerArrGetter, ownerArrSetter) {
            const group = document.createElement('div');
            group.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = label;
            group.appendChild(lbl);
            const box = makeListBox();
            box.style.maxHeight = '120px';
            box.style.overflowY = 'auto';

            allIds.forEach(id => {
                const row = document.createElement('div');
                row.style.cssText = 'display: flex; align-items: center; gap: 6px;';
                const chk = document.createElement('input');
                chk.type = 'checkbox';
                chk.checked = (ownerArrGetter() || []).includes(id);
                chk.onchange = () => {
                    let arr = ownerArrGetter() || [];
                    if (chk.checked) {
                        if (!arr.includes(id)) arr.push(id);
                    } else {
                        arr = arr.filter(x => x !== id);
                    }
                    ownerArrSetter(arr);
                    setDirty(true);
                };
                const span = document.createElement('span');
                span.style.fontSize = '11px';
                span.textContent = nameOf(id);
                row.appendChild(chk);
                row.appendChild(span);
                box.appendChild(row);
            });
            group.appendChild(box);
            container.appendChild(group);
        }

        // List field bound to an array of ids (actor skills/passives)
        function buildIdListEditor(container, label, allIds, nameOf, ownerArrGetter, ownerArrSetter, addLabel) {
            const group = document.createElement('div');
            group.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = label;
            group.appendChild(lbl);
            const box = makeListBox();
            box.style.maxHeight = '120px';
            box.style.overflowY = 'auto';

            const options = allIds.map(id => ({ value: id, label: nameOf(id) }));

            const render = () => {
                box.innerHTML = '';
                const arr = ownerArrGetter() || [];
                arr.forEach((id, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';

                    row.appendChild(makeSelect(options, id, v => {
                        arr[idx] = v;
                        ownerArrSetter(arr);
                        render();
                    }, '1'));

                    row.appendChild(makeRowDeleteBtn(() => {
                        arr.splice(idx, 1);
                        ownerArrSetter(arr);
                        render();
                    }));

                    box.appendChild(row);
                });

                box.appendChild(makeAddRowBtn(addLabel, () => {
                    const newArr = ownerArrGetter() || [];
                    newArr.push(allIds.length > 0 ? allIds[0] : '');
                    ownerArrSetter(newArr);
                    render();
                }));
            };

            render();
            group.appendChild(box);
            container.appendChild(group);
        }

        // Editable list of drop rows ({itemId, chance}) for actors
        function buildDropsEditor(container, actor) {
            const group = document.createElement('div');
            group.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = 'Item Drops (item + chance 0-1)';
            group.appendChild(lbl);
            const box = makeListBox();
            const itemOptions = dbPayload.items.map(it => ({ value: String(it.id), label: it.name }));

            const render = () => {
                actor.drops = actor.drops || [];
                box.innerHTML = '';
                actor.drops.forEach((drop, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                    row.appendChild(makeSelect(itemOptions, drop.itemId, v => { drop.itemId = parseInt(v); }, '1'));
                    const chance = document.createElement('input');
                    chance.type = 'number'; chance.step = '0.05'; chance.min = '0'; chance.max = '1';
                    chance.className = 'win98-input'; chance.style.width = '56px';
                    chance.title = 'Drop chance (0-1)';
                    chance.value = drop.chance !== undefined ? drop.chance : 0.1;
                    chance.oninput = () => { drop.chance = parseFloat(chance.value) || 0; setDirty(true); };
                    row.appendChild(chance);
                    row.appendChild(makeRowDeleteBtn(() => { actor.drops.splice(idx, 1); render(); }));
                    box.appendChild(row);
                });
                box.appendChild(makeAddRowBtn('+ Add Drop', () => {
                    actor.drops.push({ itemId: dbPayload.items[0] ? dbPayload.items[0].id : 1, chance: 0.1 });
                    render();
                }));
            };
            render();
            group.appendChild(box);
            container.appendChild(group);
        }

        // Editable list of evolution rows ({level, evolvesTo}) for actors
        function buildEvolutionsEditor(container, actor) {
            const group = document.createElement('div');
            group.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = 'Evolutions (at level → becomes)';
            group.appendChild(lbl);
            const box = makeListBox();
            const actorOptions = dbPayload.actors.map(a => ({ value: String(a.id), label: a.name }));

            const render = () => {
                actor.evolutions = actor.evolutions || [];
                box.innerHTML = '';
                actor.evolutions.forEach((evo, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                    const level = document.createElement('input');
                    level.type = 'number'; level.min = '1';
                    level.className = 'win98-input'; level.style.width = '56px';
                    level.title = 'Evolution level';
                    level.value = evo.level !== undefined ? evo.level : 5;
                    level.oninput = () => { evo.level = parseInt(level.value) || 1; setDirty(true); };
                    row.appendChild(level);
                    row.appendChild(makeSelect(actorOptions, evo.evolvesTo, v => { evo.evolvesTo = parseInt(v); }, '1'));
                    row.appendChild(makeRowDeleteBtn(() => { actor.evolutions.splice(idx, 1); render(); }));
                    box.appendChild(row);
                });
                box.appendChild(makeAddRowBtn('+ Add Evolution', () => {
                    actor.evolutions.push({ level: 5, evolvesTo: dbPayload.actors[0] ? dbPayload.actors[0].id : 1 });
                    render();
                }));
            };
            render();
            group.appendChild(box);
            container.appendChild(group);
        }

        function createCheckboxField(container, labelText, checked, onChange) {
            const row = document.createElement('div');
            row.style.cssText = 'display: flex; align-items: center; gap: 6px; margin: 4px 0;';
            const chk = document.createElement('input');
            chk.type = 'checkbox';
            chk.checked = !!checked;
            chk.onchange = () => { onChange(chk.checked); setDirty(true); };
            const lbl = document.createElement('label');
            lbl.style.fontSize = '11px';
            lbl.textContent = labelText;
            row.appendChild(chk);
            row.appendChild(lbl);
            container.appendChild(row);
        }

        // ---- Active UI Font: choices + live in-engine preview ----
        // 'Lucida' has no .ttf on disk — it's LÖVE's built-in default font,
        // exactly mirroring presentation/ui.lua's ui.setFont fallback (any
        // other name is looked up generically at assets/fonts/<name>.ttf).
        // The choice list itself is fetched from GET /api/fonts (a straight
        // directory listing of assets/fonts/*.ttf|*.otf) so dropping a new
        // font file in is the only step needed — no editor code change.
        let _fontChoicesPromise = null;
        function getFontChoices() {
            if (!_fontChoicesPromise) {
                _fontChoicesPromise = fetch(`${API_URL}/api/fonts`)
                    .then(res => res.json())
                    .then(d => (d && Array.isArray(d.fonts) && d.fonts.length) ? d.fonts : ['Lucida'])
                    .catch(() => ['Lucida']);
            }
            return _fontChoicesPromise;
        }

        // Builds a { el, render(fontName, size) } pair: a canvas fed by
        // GET /preview-font, which runs the actual engine's ui.drawPanel +
        // ui.drawString (the real 9-slice windowskin, not an approximation
        // of it) headlessly and returns a screenshot. Same technique and
        // the same 2x nearest-neighbor scale as the Scenes/Windows tabs'
        // canvases, so the picker shows exactly what the game will render.
        function buildFontPreview() {
            const wrap = document.createElement('div');
            wrap.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = 'Preview';
            wrap.appendChild(lbl);

            const S = 2;
            const canvas = document.createElement('canvas');
            canvas.style.cssText = 'image-rendering: pixelated; border: 1px solid var(--win-shadow); display: block; background: #000;';
            wrap.appendChild(canvas);
            const ctx2d = canvas.getContext('2d');

            let renderToken = 0;
            let debounceTimer = null;
            const doRender = (fontName, size) => {
                const myToken = ++renderToken;
                fetch(`${API_URL}/preview-font?name=${encodeURIComponent(fontName)}&size=${encodeURIComponent(size)}`)
                    .then(res => res.json())
                    .then(d => {
                        if (myToken !== renderToken) return; // a newer render superseded this one
                        if (d.error || !d.image) {
                            canvas.width = 240 * S; canvas.height = 64 * S;
                            ctx2d.fillStyle = '#000'; ctx2d.fillRect(0, 0, canvas.width, canvas.height);
                            ctx2d.fillStyle = '#ff6060'; ctx2d.font = '11px monospace';
                            ctx2d.fillText(d.error || 'preview failed', 6, 16);
                            return;
                        }
                        const img = new Image();
                        img.onload = () => {
                            if (myToken !== renderToken) return;
                            canvas.width = d.width * S;
                            canvas.height = d.height * S;
                            canvas.style.width = (d.width * S) + 'px';
                            canvas.style.height = (d.height * S) + 'px';
                            ctx2d.imageSmoothingEnabled = false;
                            ctx2d.clearRect(0, 0, canvas.width, canvas.height);
                            ctx2d.drawImage(img, 0, 0, canvas.width, canvas.height);
                        };
                        img.src = 'data:image/png;base64,' + d.image;
                    })
                    .catch(err => {
                        if (myToken !== renderToken) return;
                        ctx2d.fillStyle = '#ff6060'; ctx2d.font = '11px monospace';
                        ctx2d.fillText('preview request failed: ' + err.message, 6, 16);
                    });
            };

            // Debounced so rapid size-input keystrokes don't spawn a lovec
            // process per keypress.
            const render = (fontName, size) => {
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => doRender(fontName, size), 250);
            };

            return { el: wrap, render };
        }

        // ---- Config schema: friendly labels + typed widgets for system/engine keys ----
        // Keys not listed fall back to the generic key-name field.
        const CONFIG_SCHEMA = {
            'windowLayout.headerSpacing': { label: 'Header Spacing (px)', type: 'number', step: 1 },
            'ui.menuSlideDuration':        { label: 'Menu Slide Duration (s)', step: 0.05, min: 0 },
            'ui.moveTransitionDuration':   { label: 'Move Transition (s)', step: 0.05, min: 0 },
            'ui.inputCooldown':            { label: 'Input Cooldown (s)', step: 0.05, min: 0 },
            'ui.textPalette':              { label: 'Text Palette \\c[n] Colors', widget: 'colorList' },
            'physics.gravity':             { label: 'Popup Gravity (px/s²)', min: 0 },
            'physics.bounceVelocityRetain':{ label: 'Popup Bounce Retention (0-1)', step: 0.05, min: 0, max: 1 },
            'physics.horizontalScatter':   { label: 'Popup Horizontal Scatter (px)', min: 0 },
            'battle_screen.damagePopupLife': { label: 'Damage Popup Lifetime (s)', step: 0.1, min: 0 },
            'battle_screen.popup.font': { label: 'Popup Font' },
            'battle_screen.popup.fontSize': { label: 'Popup Font Size (px)' },
            'battle_screen.popup.damageFormat': { label: 'Damage Popup Format', type: 'text' },
            'battle_screen.popup.damageColor': { label: 'Damage Popup Color', widget: 'color' },
            'battle_screen.popup.healFormat': { label: 'Heal Popup Format', type: 'text' },
            'battle_screen.popup.healColor': { label: 'Heal Popup Color', widget: 'color' },
            'battle_screen.popup.critFormat': { label: 'Crit Popup Format', type: 'text' },
            'battle_screen.popup.critColor': { label: 'Crit Popup Color', widget: 'color' },
            'battle_screen.popup.deadFormat': { label: 'Dead Popup Format', type: 'text' },
            'battle_screen.popup.deadColor': { label: 'Dead Popup Color', widget: 'color' },
            'battle_screen.popup.stateFormat': { label: 'State Popup Format', type: 'text' },
            'battle_screen.popup.stateColor': { label: 'State Popup Color', widget: 'color' },

            'combat.baseFleeChance':       { label: 'Base Flee Chance (0-1)', step: 0.05, min: 0, max: 1 },
            'combat.goldLossOnFleeMin':    { label: 'Gold Lost on Failed Flee (min)', min: 0 },
            'combat.goldLossOnFleeMax':    { label: 'Gold Lost on Failed Flee (max)', min: 0 },
            'combat.encounterChance':      { label: 'Encounter Chance per Step (0-1)', step: 0.01, min: 0, max: 1 },
            'combat.minEnemies':           { label: 'Encounter Size (min)', min: 1 },
            'combat.maxEnemies':           { label: 'Encounter Size (max)', min: 1 },
            'combat.victoryGoldMin':       { label: 'Victory Gold (min)', min: 0 },
            'combat.victoryGoldMax':       { label: 'Victory Gold (max)', min: 0 },
            'combat.victoryExp':           { label: 'Victory XP per Survivor', min: 0 },
            'combat.baseSpeed':            { label: 'Base Action Speed', min: 0 },
            'combat.speedPerLevel':        { label: 'Action Speed per Level', step: 0.1, min: 0 },
            'combat.regenRate':            { label: 'Regen State: % Max HP / Turn', step: 0.01, min: 0, max: 1 },
            'combat.poisonRate':           { label: 'Poison State: % Max HP / Turn', step: 0.01, min: 0, max: 1 },
            'combat.mpExhaustionDamage':   { label: 'MP Exhaustion Damage / Turn', min: 0 },
            'combat.battleItem':           { label: 'Battle "Item" Command Uses', widget: 'itemSelect' },
            'combat.defendSkillId':        { label: '"Defend" Command Skill', widget: 'skillSelect' },
            'combat.attackSkillId':        { label: '"Attack" Command Skill', widget: 'skillSelect' },
            'growth.hpPerLevelRate':       { label: 'HP Gain per Level (% of base)', step: 0.01, min: 0,
                                             help: 'Each level adds this fraction of the actor\'s base max HP (0.15 = +15%/level).' },
            'growth.statBase':             { label: 'Stat Base Value', min: 0,
                                             help: 'The level-1 value every growth curve starts from for atk/def/mat/mdf.' },
            'growth.statPerLevel':         { label: 'Stat Gain per Level', step: 0.1, min: 0,
                                             help: 'Flat amount added to each stat per level on top of the base value.' },
            'growth.expPerLevel':          { label: 'XP per Level (× current level)', min: 1,
                                             help: 'XP needed for the next level = this value × the current level.' },
            'dungeon.maxFloor':            { label: 'Deepest Floor', min: 1 },
            'dungeon.moveMpDrain':         { label: 'MP Drain per Step', min: 0 },
            'dungeon.defaultLoot':         { label: 'Default Treasure Item', widget: 'itemSelect' },
            'dungeon.genWidth':            { label: 'Generated Map Width' },
            'dungeon.genHeight':           { label: 'Generated Map Height' },
            'dungeon.genMinRooms':         { label: 'Rooms per Floor (min)' },
            'dungeon.genMaxRooms':         { label: 'Rooms per Floor (max)' },
            'dungeon.genMinRoomSize':      { label: 'Room Size (min)' },
            'dungeon.genMaxRoomSize':      { label: 'Room Size (max)' },
            'dungeon.exitSprite':          { label: 'Exit Stairs Sprite', widget: 'assetPath', dir: 'sprites' },
            'dungeon.exitScriptId':        { label: 'Exit Stairs Common Event', widget: 'commonEventSelect' },
            'summoner.startMp':            { label: 'Starting MP' },
            'summoner.summonCostBase':     { label: 'Summon Base Cost (MP)' },
            'summoner.summonCostPerLevel': { label: 'Summon Cost / Level (MP)' },
            'summoner.summonCostPerTier':  { label: 'Summon Cost / Tier (MP)' },
            'summoner.sacrificeMpRefundRate': { label: 'Sacrifice Refund Rate (Multiplier)', step: 0.1 },
            'summoner.spells':             { label: 'Summoner Spells', widget: 'skillChecklist' },
            'spawn.x':                     { label: 'Town Spawn X' },
            'spawn.y':                     { label: 'Town Spawn Y' },
            'newGame.goldMin':             { label: 'Starting Gold (min)' },
            'newGame.goldMax':             { label: 'Starting Gold (max)' },
            'newGame.guaranteedItem.id':   { label: 'Guaranteed Item', widget: 'itemSelect' },
            'newGame.guaranteedItem.minQty': { label: 'Guaranteed Item Qty (min)' },
            'newGame.guaranteedItem.maxQty': { label: 'Guaranteed Item Qty (max)' },
            'newGame.randomConsumables':   { label: 'Random Consumables (count)' },
            'newGame.randomEquipment':     { label: 'Random Equipment (count)' },
            'newGame.bonusItems':          { label: 'Fixed Bonus Items', widget: 'itemChecklist' },
            'newGame.party.twoMemberChance': { label: 'Duo Start Chance (0-1)', step: 0.05 },
            'newGame.party.twoMemberBonusLevels': { label: 'Duo Start Bonus Levels' },
            'newGame.party.defaultSize':   { label: 'Trio Start Party Size' },
            'town.options':                { label: 'Town Menu Options', widget: 'townOptions' },
            'elementRules.strongMultiplier': { label: 'Strong-Element Damage ×', step: 0.05, min: 0,
                                               help: 'Damage multiplier when the attack element is strong against the target (1.5 = +50%).' },
            'elementRules.weakMultiplier': { label: 'Weak-Element Damage ×', step: 0.05, min: 0,
                                             help: 'Damage multiplier when the attack element is weak against the target (0.65 = -35%).' },
            'battleLayout.enemyRowWidth':  { label: 'Enemy Row Width (px)' },
            'battleLayout.enemyStartX':    { label: 'Enemy Row Start X (px)' },
            'battleLayout.enemyPopupOffsetX': { label: 'Enemy Popup Offset X (px)' },
            'battleLayout.enemyPopupY':    { label: 'Enemy Popup Y (px)' },
            'battleLayout.partyGridTileX': { label: 'Party Grid X (tiles)' },
            'battleLayout.consoleTileY':   { label: 'Console Y (tiles)' },
            'battleLayout.headerTileOffset': { label: 'Console Header Offset (tiles)' },
            'battleLayout.slotPopupOffsetX': { label: 'Party Popup Offset X (px)' },
            'battleLayout.slotPopupOffsetY': { label: 'Party Popup Offset Y (px)' },
            'battleLayout.summonerPopupX': { label: 'Summoner Popup X (px)' },
            'battleLayout.summonerPopupYOffset': { label: 'Summoner Popup Y Offset (px)' },
            'battleLayout.fallbackX':      { label: 'Popup Fallback X (px)' },
            'battleLayout.fallbackY':      { label: 'Popup Fallback Y (px)' },
            'battleLayout.enemyY':         { label: 'Enemy Y (px)' },
            'battleLayout.enemyNameY':     { label: 'Enemy Name Y (px)' },
            'battleLayout.enemyHpBarY':    { label: 'Enemy HP Bar Y (px)' },
            'battleLayout.enemyHpBarWidth': { label: 'Enemy HP Bar Width (px)' },
            'battleLayout.enemyHpBarHeight': { label: 'Enemy HP Bar Height (px)' },
            'battleLayout.enemySpriteSize': { label: 'Enemy Sprite Size (px)' },
            'battleLayout.enemyFallbackSize': { label: 'Enemy Fallback Sprite Size (px)' },
            'battleLayout.enemySlideOffset': { label: 'Enemy Slide-in Offset (px)' },
            'battleLayout.enemyDeathYOffset': { label: 'Enemy Death Bounce Height (px)' },
            'battleLayout.viewportOverlayW': { label: 'Viewport Overlay Width (px)' },
            'battleLayout.viewportOverlayH': { label: 'Viewport Overlay Height (px)' },
            'battleLayout.logPanelX':      { label: 'Log Panel X (px)' },
            'battleLayout.logPanelY':      { label: 'Log Panel Y (px)' },
            'battleLayout.logPanelWidth':  { label: 'Log Panel Width (px)' },
            'battleLayout.logPanelHeight': { label: 'Log Panel Height (px)' },
            'battleLayout.logTextX':       { label: 'Log Text X (px)' },
            'battleLayout.logTextY':       { label: 'Log Text Y (px)' },
            'battleLayout.logTextLimit':   { label: 'Log Text Width Limit (px)' },
            'battleLayout.logSpaceX':      { label: 'Log SPACE Prompt X (px)' },
            'battleLayout.logSpaceY':      { label: 'Log SPACE Prompt Y (px)' },
            'battleLayout.consoleTileX':   { label: 'Console X (tiles)' },
            'battleLayout.consoleTileW':   { label: 'Console Width (tiles)' },
            'battleLayout.consoleTileH':   { label: 'Console Height (tiles)' },
            'battleLayout.consoleTextTileX': { label: 'Console Text X (tiles)' },
            'battleLayout.menuChoiceSpacing': { label: 'Menu Choice Spacing (px)' },
            'battleLayout.summonerStatusX': { label: 'Summoner Status X (px)' },
            'battleLayout.summonerNameYOffset': { label: 'Summoner Name Y Offset (px)' },
            'battleLayout.summonerMpTextYOffset': { label: 'Summoner MP Text Y Offset (px)' },
            'battleLayout.summonerMpBarYOffset': { label: 'Summoner MP Bar Y Offset (px)' },
            'battleLayout.summonerMpBarWidth': { label: 'Summoner MP Bar Width (px)' },
            'battleLayout.summonerMpBarHeight': { label: 'Summoner MP Bar Height (px)' },
            'battleLayout.partyGridColWidth': { label: 'Party Grid Column Width (px)' },
            'battleLayout.partyGridRowHeight': { label: 'Party Grid Row Height (px)' },
            'battleLayout.partyGridNameXOffset': { label: 'Party Grid Name X Offset (px)' },
            'battleLayout.partyGridHpXOffset': { label: 'Party Grid HP X Offset (px)' },
            'battleLayout.partyGridHpYOffset': { label: 'Party Grid HP Y Offset (px)' },
            'battleLayout.partyGridHpBarXOffset': { label: 'Party Grid HP Bar X Offset (px)' },
            'battleLayout.partyGridHpBarYOffset': { label: 'Party Grid HP Bar Y Offset (px)' },
            'battleLayout.partyGridHpBarWidth': { label: 'Party Grid HP Bar Width (px)' },
            'battleLayout.partyGridHpBarHeight': { label: 'Party Grid HP Bar Height (px)' },
            'battleLayout.partyGridEmptyYOffset': { label: 'Party Grid Empty Y Offset (px)' }
        };

        function setNestedValue(targetRoot, currentPath, key, val) {
            let target = targetRoot;
            for (let i = 0; i < currentPath.length - 1; i++) {
                if (!target[currentPath[i]]) target[currentPath[i]] = {};
                target = target[currentPath[i]];
            }
            target[key] = val;
        }

        // Renders a schema-typed widget; returns false to fall through to the
        // generic renderer.
        function renderSchemaField(container, schema, value, key, currentPath, targetRoot, useBlockLayout = true) {
            const widget = schema.widget || (typeof value === 'number' ? 'number' : null);

            if (widget === 'itemSelect' || widget === 'skillSelect' || widget === 'commonEventSelect') {
                let opts;
                if (widget === 'itemSelect') {
                    opts = dbPayload.items.map(it => ({ value: String(it.id), label: it.name }));
                } else if (widget === 'skillSelect') {
                    opts = Object.keys(dbPayload.skills || {}).map(id => ({ value: id, label: (dbPayload.skills[id].name || id) }));
                } else {
                    opts = Object.keys(dbPayload.commonEvents || {}).map(id => ({ value: id, label: `${id}: ${dbPayload.commonEvents[id].name || ''}` }));
                }
                const group = document.createElement('div');
                group.className = useBlockLayout ? 'form-group' : 'form-group field-inline';
                const lbl = document.createElement('label');
                lbl.textContent = schema.label || key;
                group.appendChild(lbl);
                const numeric = (widget !== 'skillSelect');
                group.appendChild(makeSelect(opts, value, v => {
                    setNestedValue(targetRoot, currentPath, key, numeric ? (parseInt(v) || v) : v);
                }, '1'));
                appendFieldHelp(group, schema);
                container.appendChild(group);
                return true;
            }

            if (widget === 'skillChecklist' || widget === 'itemChecklist') {
                const ids = widget === 'skillChecklist'
                    ? Object.keys(dbPayload.skills || {})
                    : dbPayload.items.map(it => it.id);
                const nameOf = widget === 'skillChecklist'
                    ? id => (dbPayload.skills[id] && dbPayload.skills[id].name) || id
                    : id => { const it = dbPayload.items.find(x => x.id === id); return it ? it.name : id; };
                buildChecklistField(container, schema.label || key, ids, nameOf,
                    () => {
                        let target = targetRoot;
                        for (let i = 0; i < currentPath.length - 1; i++) target = target[currentPath[i]] || {};
                        return target[key];
                    },
                    arr => setNestedValue(targetRoot, currentPath, key, arr));
                return true;
            }

            if (widget === 'assetPath') {
                window.createSpriteField(container, schema.label || key, value || '', (path) => {
                    setNestedValue(targetRoot, currentPath, key, path);
                    setDirty(true);
                }, useBlockLayout, schema.dir || 'sprites');
                return true;
            }

            if (widget === 'colorList' && Array.isArray(value)) {
                const group = document.createElement('div');
                group.className = 'form-group';
                const lbl = document.createElement('label');
                lbl.textContent = schema.label || key;
                group.appendChild(lbl);
                const box = makeListBox();
                const arr = value;
                const render = () => {
                    box.innerHTML = '';
                    arr.forEach((col, idx) => {
                        const row = document.createElement('div');
                        row.style.cssText = 'display: flex; gap: 6px; align-items: center;';
                        const tag = document.createElement('span');
                        tag.style.cssText = 'font-size: 10px; width: 42px;';
                        tag.textContent = '\\c[' + idx + ']';
                        row.appendChild(tag);
                        const pick = document.createElement('input');
                        pick.type = 'color';
                        pick.value = rgb01ToHex(col);
                        pick.oninput = () => {
                            const rgb = hexToRgb01(pick.value);
                            arr[idx] = [rgb[0], rgb[1], rgb[2], (col && col[3]) !== undefined ? col[3] : 1];
                            setDirty(true);
                        };
                        row.appendChild(pick);
                        row.appendChild(makeRowDeleteBtn(() => { arr.splice(idx, 1); render(); }));
                        box.appendChild(row);
                    });
                    box.appendChild(makeAddRowBtn('+ Add Color', () => { arr.push([1, 1, 1, 1]); render(); }));
                };
                render();
                group.appendChild(box);
                container.appendChild(group);
                return true;
            }


            if (schema.type === 'text' && widget !== 'assetPath') {
                const group = document.createElement('div');
                group.className = useBlockLayout ? 'form-group' : 'form-group field-inline';
                const lbl = document.createElement('label');
                lbl.textContent = schema.label || key;
                group.appendChild(lbl);
                const input = document.createElement('input');
                input.className = 'form-control inset-bevel';
                input.value = value !== undefined && value !== null ? value : '';
                input.oninput = () => { setNestedValue(targetRoot, currentPath, key, input.value); setDirty(true); };
                group.appendChild(input);
                appendFieldHelp(group, schema);
                container.appendChild(group);
                return true;
            }

            if (widget === 'color') {
                const group = document.createElement('div');
                group.className = useBlockLayout ? 'form-group' : 'form-group field-inline';
                const lbl = document.createElement('label');
                lbl.textContent = schema.label || key;
                group.appendChild(lbl);

                const pick = document.createElement('input');
                pick.type = 'color';
                pick.value = rgb01ToHex(value);
                pick.oninput = () => {
                    const rgb = hexToRgb01(pick.value);
                    const newVal = [rgb[0], rgb[1], rgb[2], (value && value[3]) !== undefined ? value[3] : 1];
                    setNestedValue(targetRoot, currentPath, key, newVal);
                    setDirty(true);
                };
                group.appendChild(pick);
                container.appendChild(group);
                return true;
            }

            if (widget === 'townOptions' && Array.isArray(value)) {
                const group = document.createElement('div');
                group.className = 'form-group';
                const lbl = document.createElement('label');
                lbl.textContent = schema.label || key;
                group.appendChild(lbl);
                const box = makeListBox();
                const arr = value;
                const graphNames = ['npc_weapon_shop', 'npc_alicia', 'npc_drunkard'];
                const render = () => {
                    box.innerHTML = '';
                    arr.forEach((opt, idx) => {
                        const row = document.createElement('div');
                        row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                        const label = document.createElement('input');
                        label.className = 'win98-input';
                        label.style.width = '90px';
                        label.title = 'Menu label';
                        label.value = opt.label || '';
                        label.oninput = () => { opt.label = label.value; setDirty(true); };
                        row.appendChild(label);
                        row.appendChild(makeSelect(['enter_dungeon', 'dialogue', 'rest'], opt.action, v => {
                            opt.action = v;
                            setDirty(true);
                            render();
                        }));
                        if (opt.action === 'enter_dungeon') {
                            row.appendChild(createMapPicker(opt.mapId, v => { opt.mapId = parseInt(v); }, '1'));
                        } else {
                            const graph = createGraphPicker(opt.graph || '', v => { opt.graph = v; }, '1');
                            row.appendChild(graph);
                        }
                        row.appendChild(makeRowDeleteBtn(() => { arr.splice(idx, 1); render(); }));
                        box.appendChild(row);
                    });
                    box.appendChild(makeAddRowBtn('+ Add Option', () => {
                        arr.push({ label: 'New Option', action: 'dialogue', graph: graphNames[0] });
                        render();
                    }));
                };
                render();
                group.appendChild(box);
                container.appendChild(group);
                return true;
            }

            if (widget === 'number' || typeof value === 'number') {
                const group = document.createElement('div');
                group.className = useBlockLayout ? 'form-group' : 'form-group field-inline';
                const lbl = document.createElement('label');
                lbl.textContent = schema.label || key;
                group.appendChild(lbl);
                const input = document.createElement('input');
                input.type = 'number';
                input.className = 'form-control inset-bevel';
                if (schema.step) input.step = schema.step;
                if (schema.min !== undefined) input.min = schema.min;
                if (schema.max !== undefined) input.max = schema.max;
                input.value = value;
                input.oninput = () => {
                    const parsed = parseFloat(input.value);
                    setNestedValue(targetRoot, currentPath, key, isNaN(parsed) ? 0 : parsed);
                    setDirty(true);
                };
                group.appendChild(input);
                appendFieldHelp(group, schema);
                container.appendChild(group);
                return true;
            }

            return false;
        }

        // B5: schema entries with a `help` string render it as a muted line
        // beneath the field, so the label can stay short.
        function appendFieldHelp(group, schema) {
            if (!schema || !schema.help) return;
            const span = document.createElement('span');
            span.className = 'field-help';
            span.textContent = schema.help;
            group.appendChild(span);
        }

        // ---- Direct JSON editing mode ----
        // Adds an "Edit as JSON" button to buttonHost; clicking swaps formPanel
        // for a JSON textarea. Apply replaces the target's contents in place
        // (references stay valid) and re-renders the form via onApplied.
        function attachJsonToggle(buttonHost, formPanel, targetObj, onApplied) {
            if (!targetObj || typeof targetObj !== 'object') return;
            const btn = document.createElement('button');
            btn.className = 'win98-btn';
            btn.style.cssText = 'float: right; font-size: 10px; font-family: monospace; margin-top: -2px;';
            btn.textContent = '{ } JSON';
            btn.onclick = () => {
                formPanel.innerHTML = '';

                const container = document.createElement('div');
                container.className = 'form-control inset-bevel';
                container.style.cssText = 'position: relative; height: 320px; background: #fff; overflow: hidden; padding: 0; box-sizing: border-box;';

                const pre = document.createElement('pre');
                pre.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; margin: 0; padding: 4px; box-sizing: border-box; overflow: hidden; font-family: monospace; font-size: 11px; white-space: pre; pointer-events: none; color: black; z-index: 0;';

                const area = document.createElement('textarea');
                area.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; margin: 0; padding: 4px; box-sizing: border-box; font-family: monospace; font-size: 11px; white-space: pre; background: transparent; color: transparent; caret-color: black; border: none; outline: none; resize: none; overflow: auto; z-index: 1;';
                area.spellcheck = false;
                area.value = JSON.stringify(targetObj, null, 2);

                const syntaxHighlight = (jsonStr) => {
                    let escaped = jsonStr.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
                    // In order to correctly match trailing newlines and spaces, we make sure to match them inside the pre tag natively.
                    return escaped.replace(/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g, function (match) {
                        let cls = 'color: #000;';
                        if (/^"/.test(match)) {
                            if (/:$/.test(match)) {
                                cls = 'color: #880000;'; // key
                            } else {
                                cls = 'color: #008800;'; // string
                            }
                        } else if (/true|false/.test(match)) {
                            cls = 'color: #0000ff;'; // boolean
                        } else if (/null/.test(match)) {
                            cls = 'color: #888888; font-style: italic;'; // null
                        } else {
                            cls = 'color: #ff8800;'; // number
                        }
                        return '<span style="' + cls + '">' + match + '</span>';
                    });
                };

                const updateHighlight = () => {
                    // Add an extra newline at the end if it ends with one, to keep the pre scrollheight the same as textarea.
                    let html = syntaxHighlight(area.value);
                    if (html.endsWith('\n')) {
                        html += ' ';
                    }
                    pre.innerHTML = html;
                };

                area.onscroll = () => {
                    pre.scrollTop = area.scrollTop;
                    pre.scrollLeft = area.scrollLeft;
                };

                area.oninput = () => {
                    updateHighlight();
                    try {
                        JSON.parse(area.value);
                        container.style.backgroundColor = '#fff';
                    } catch (e) {
                        container.style.backgroundColor = '#ffcccc';
                    }
                };

                updateHighlight();

                container.appendChild(pre);
                container.appendChild(area);

                const bar = document.createElement('div');
                bar.style.cssText = 'display: flex; gap: 6px; margin-bottom: 6px;';
                const applyBtn = document.createElement('button');
                applyBtn.className = 'win98-btn win98-btn-success';
                applyBtn.textContent = 'Apply JSON';
                applyBtn.onclick = () => {
                    let parsed;
                    try { parsed = JSON.parse(area.value); }
                    catch (e) { container.style.backgroundColor = '#ffcccc'; return; }
                    if (Array.isArray(targetObj) && Array.isArray(parsed)) {
                        targetObj.length = 0;
                        parsed.forEach(v => targetObj.push(v));
                    } else if (!Array.isArray(targetObj) && typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
                        Object.keys(targetObj).forEach(k => delete targetObj[k]);
                        Object.assign(targetObj, parsed);
                    } else {
                        container.style.backgroundColor = '#ffcccc';
                        return;
                    }
                    setDirty(true);
                    if (onApplied) onApplied();
                };
                const backBtn = document.createElement('button');
                backBtn.className = 'win98-btn';
                backBtn.textContent = 'Back to Form';
                backBtn.onclick = () => { if (onApplied) onApplied(); };
                bar.appendChild(applyBtn);
                bar.appendChild(backBtn);

                formPanel.appendChild(bar);
                formPanel.appendChild(container);
            };
            buttonHost.appendChild(btn);
        }

        // ---- Sprite-key suggestions from assets/portraits ----
        let portraitKeysLoaded = false;
        function ensurePortraitKeys() {
            if (portraitKeysLoaded) return;
            portraitKeysLoaded = true;
            let list = document.getElementById('portrait-keys-list');
            if (!list) {
                list = document.createElement('datalist');
                list.id = 'portrait-keys-list';
                document.body.appendChild(list);
            }
            fetch('/api/assets?dir=portraits')
                .then(r => r.json())
                .then(data => {
                    (data.files || []).forEach(f => {
                        const base = f.split('/').pop().replace(/\.(png|jpe?g|gif|webp)$/i, '').replace(/^NPC_/, '');
                        const opt = document.createElement('option');
                        opt.value = base;
                        list.appendChild(opt);
                    });
                })
                .catch(() => {});
        }

        // Editable list of element slots (duplicates allowed, e.g. Green ×2)
        function buildElementSlotsEditor(container, owner) {
            const group = document.createElement('div');
            group.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = 'Elements (slots; duplicates stack)';
            group.appendChild(lbl);
            const box = makeListBox();
            const render = () => {
                owner.elements = owner.elements || [];
                box.innerHTML = '';
                owner.elements.forEach((el, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                    row.appendChild(makeSelect(elementOptions(false), el, v => { owner.elements[idx] = v; }, '1'));
                    row.appendChild(makeRowDeleteBtn(() => { owner.elements.splice(idx, 1); render(); }));
                    box.appendChild(row);
                });
                box.appendChild(makeAddRowBtn('+ Add Element', () => {
                    owner.elements.push(elementOptions(false)[0]);
                    render();
                }));
            };
            render();
            group.appendChild(box);
            container.appendChild(group);
        }

        function loadFormForItem(item) {
            const formPanel = document.getElementById('db-form-panel');
            formPanel.innerHTML = '';
            formPanel.style.display = 'block'; // Reset layout

            const header = document.createElement('div');
            header.style.fontWeight = 'bold';
            header.style.fontSize = '12px';
            header.style.marginBottom = '12px';
            header.style.borderBottom = '1px solid var(--win-shadow)';
            header.style.paddingBottom = '4px';
            header.textContent = `General Settings - ${item.name || item.id}`;
            formPanel.appendChild(header);

            if (activeDbTab === 'commonEvents') {
                const eventData = dbPayload.commonEvents[item.id];
                if (!eventData) return;

                createFormField(formPanel, 'Event Name', eventData.name, val => {
                    eventData.name = val;
                    initDatabaseEditor(true);
                });

                // Default sprite: map events linked to this common event
                // inherit it unless they set their own graphic.
                window.createSpriteField(formPanel, 'Default Sprite (inherited)', eventData.sprite || '', (path) => {
                    if (path === '') { delete eventData.sprite; } else { eventData.sprite = path; }
                    setDirty(true);
                });

                // Default minimap marker color: map events linked to this
                // common event use it unless they set their own.
                const colorRow = document.createElement('div');
                colorRow.style.cssText = 'display: flex; align-items: center; gap: 8px; margin: 6px 0;';
                const colorChk = document.createElement('input');
                colorChk.type = 'checkbox';
                colorChk.checked = Array.isArray(eventData.minimapColor);
                const colorLbl = document.createElement('label');
                colorLbl.style.fontSize = '11px';
                colorLbl.textContent = 'Default minimap color (events can override):';
                const colorPick = document.createElement('input');
                colorPick.type = 'color';
                colorPick.disabled = !colorChk.checked;
                const toHex = c => '#' + (c || [0.4, 0.6, 1]).slice(0, 3)
                    .map(v => Math.round((v || 0) * 255).toString(16).padStart(2, '0')).join('');
                colorPick.value = toHex(eventData.minimapColor);
                const applyPick = () => {
                    eventData.minimapColor = [1, 3, 5].map(i =>
                        Math.round(parseInt(colorPick.value.substr(i, 2), 16) / 255 * 100) / 100);
                    setDirty(true);
                };
                colorChk.onchange = () => {
                    colorPick.disabled = !colorChk.checked;
                    if (colorChk.checked) { applyPick(); } else { delete eventData.minimapColor; setDirty(true); }
                };
                colorPick.oninput = applyPick;
                colorRow.appendChild(colorChk);
                colorRow.appendChild(colorLbl);
                colorRow.appendChild(colorPick);
                formPanel.appendChild(colorRow);

                const cmdTitle = document.createElement('div');
                cmdTitle.style.fontWeight = 'bold';
                cmdTitle.style.marginTop = '12px';
                cmdTitle.style.marginBottom = '6px';
                cmdTitle.textContent = 'Event Commands:';
                formPanel.appendChild(cmdTitle);

                const listBox = document.createElement('div');
                listBox.style.border = '1px solid var(--win-shadow)';
                listBox.style.background = '#fff';
                listBox.style.height = '240px';
                listBox.style.overflowY = 'auto';
                listBox.style.padding = '4px';
                listBox.style.display = 'flex';
                listBox.style.flexDirection = 'column';
                listBox.style.gap = '2px';
                listBox.style.fontFamily = 'monospace';
                listBox.style.fontSize = '11px';
                listBox.id = 'common-event-commands-list';

                eventData.commands = eventData.commands || [];
                // Same renderCommandList used by the Event Editor's script list,
                // so Common Events and Map Events edit commands identically.
                // hostCtx 'common' filters the add/edit palette to commands whose
                // registry contexts include "common" (SPEC A6).
                const rerenderCeCommands = () => {
                    setDirty(true);
                    renderCommandList(listBox, eventData.commands, rerenderCeCommands, false, 0, 'common');
                };
                renderCommandList(listBox, eventData.commands, rerenderCeCommands, false, 0, 'common');
                formPanel.appendChild(listBox);
            }

            if (activeDbTab === 'actors') {
                // Name + Role side by side
                const nameRoleRow = document.createElement('div');
                nameRoleRow.className = 'form-row';
                createFormField(nameRoleRow, 'Name', item.name, val => { item.name = val; initDatabaseEditor(true); });

                const roleGroup = document.createElement('div');
                roleGroup.className = 'form-group';
                roleGroup.style.flex = '1';
                const roleLbl = document.createElement('label');
                roleLbl.textContent = 'Role';
                roleGroup.appendChild(roleLbl);
                roleGroup.appendChild(makeSelect(Object.keys(dbPayload.roles || { Spirit: 1 }), item.role || 'Spirit', v => { item.role = v; }, '1'));
                nameRoleRow.appendChild(roleGroup);
                formPanel.appendChild(nameRoleRow);

                // Biography (renamed from Flavor Text) under Name/Role
                createFormField(formPanel, 'Biography', item.flavor || '', val => { item.flavor = val; });

                const statsRow = document.createElement('div');
                statsRow.className = 'form-row';
                createFormField(statsRow, 'Base HP', item.maxHp || 10, val => { item.maxHp = parseInt(val) || 10; }, 'number');
                createFormField(statsRow, 'Base MP Drain', item.mpd || 2, val => { item.mpd = parseInt(val) || 2; }, 'number');
                createFormField(statsRow, 'Base Level', item.level || 1, val => { item.level = parseInt(val) || 1; }, 'number');
                formPanel.appendChild(statsRow);

                const growthRow = document.createElement('div');
                growthRow.className = 'form-row';
                createFormField(growthRow, 'Exp Growth', item.expGrowth || 0, val => { item.expGrowth = parseInt(val) || 0; }, 'number');
                createFormField(growthRow, 'Gold Reward', item.gold || 0, val => { item.gold = parseInt(val) || 0; }, 'number');
                formPanel.appendChild(growthRow);

                ensurePortraitKeys();
                // Sprite fields in a horizontal row
                const spriteRow = document.createElement('div');
                spriteRow.className = 'form-row';
                window.createSpriteField(spriteRow, 'Sprite Key', item.spriteKey || '', (path) => {
                    item.spriteKey = path;
                    setDirty(true);
                }, false, 'portraits', true);
                window.createSpriteField(spriteRow, 'Small Battler', item.smallBattler || '', (path) => {
                    item.smallBattler = path;
                    setDirty(true);
                }, false, 'smallBattlers', true);
                formPanel.appendChild(spriteRow);

                createCheckboxField(formPanel, 'In starting-party pool (initialParty)', item.initialParty, v => { item.initialParty = v; });
                createCheckboxField(formPanel, 'Unlocked by Default', item.unlocked, v => { item.unlocked = v; });
                createFormField(formPanel, 'Tier', item.tier, v => { item.tier = parseFloat(v); }, 'number');
                createFormField(formPanel, 'Discipline (Item Creation)', item.discipline, v => { item.discipline = v; }, 'text');
                createCheckboxField(formPanel, 'Recruitable in dungeons (isRecruitable)', item.isRecruitable, v => { item.isRecruitable = v; });

                // Three-column grid: Skills, Passives, Traits
                const threeCol = document.createElement('div');
                threeCol.style.cssText = 'display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 10px;';
                const skillsCol = document.createElement('div');
                const passivesCol = document.createElement('div');
                const traitsCol = document.createElement('div');
                threeCol.appendChild(skillsCol);
                threeCol.appendChild(passivesCol);
                threeCol.appendChild(traitsCol);
                formPanel.appendChild(threeCol);

                buildIdListEditor(skillsCol, 'Skills',
                    Object.keys(dbPayload.skills || {}),
                    id => (dbPayload.skills[id] && dbPayload.skills[id].name) || id,
                    () => item.skills, arr => { item.skills = arr; }, '+ Add Skill');
                buildIdListEditor(passivesCol, 'Passives',
                    Object.keys(dbPayload.passives || {}),
                    id => (dbPayload.passives[id] && dbPayload.passives[id].name) || id,
                    () => item.passives, arr => { item.passives = arr; }, '+ Add Passive');
                buildTraitsEditor(traitsCol, item, 'Innate Traits');

                // Three-column grid: Elements, Item Drops, Evolutions
                const threeColBottom = document.createElement('div');
                threeColBottom.style.cssText = 'display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 10px;';
                const elementsCol = document.createElement('div');
                const dropsCol = document.createElement('div');
                const evolutionsCol = document.createElement('div');
                threeColBottom.appendChild(elementsCol);
                threeColBottom.appendChild(dropsCol);
                threeColBottom.appendChild(evolutionsCol);
                formPanel.appendChild(threeColBottom);

                buildElementSlotsEditor(elementsCol, item);
                buildDropsEditor(dropsCol, item);
                buildEvolutionsEditor(evolutionsCol, item);

            } else if (activeDbTab === 'items') {
                const topRow = document.createElement('div');
                topRow.className = 'form-row';
                topRow.style.gap = '0';
                createIconField(topRow, 'Icon', item.icon || 0, val => { item.icon = parseInt(val) || 0; }, true);
                createFormField(topRow, 'Name', item.name, val => { item.name = val; initDatabaseEditor(true); });
                formPanel.appendChild(topRow);

                // Type, Scope/EquipSlot, Buy Cost side by side
                const itemRow = document.createElement('div');
                itemRow.className = 'form-row';

                const typeGroup = document.createElement('div');
                typeGroup.className = 'form-group';
                typeGroup.style.flex = '1';
                const typeLbl = document.createElement('label');
                typeLbl.textContent = 'Type';
                typeGroup.appendChild(typeLbl);
                typeGroup.appendChild(makeSelect(['consumable', 'equipment', 'quest'], item.type || 'consumable', v => {
                    item.type = v;
                    loadFormForItem(item); // re-render: equipment shows equip fields
                }));
                itemRow.appendChild(typeGroup);

                if (item.type === 'equipment') {
                    const eqGroup = document.createElement('div');
                    eqGroup.className = 'form-group';
                    eqGroup.style.flex = '1';
                    const eqLbl = document.createElement('label');
                    eqLbl.textContent = 'Equip Slot';
                    eqGroup.appendChild(eqLbl);
                    eqGroup.appendChild(makeSelect(['Weapon', 'Armor', 'Accessory'], item.equipType || 'Weapon', v => { item.equipType = v; }));
                    itemRow.appendChild(eqGroup);
                } else {
                    const scopeGroup = document.createElement('div');
                    scopeGroup.className = 'form-group';
                    scopeGroup.style.flex = '1';
                    const scopeLbl = document.createElement('label');
                    scopeLbl.textContent = 'Target Scope';
                    scopeGroup.appendChild(scopeLbl);
                    scopeGroup.appendChild(makeSelect(
                        [{ value: '', label: 'Single member' }, { value: 'party', label: 'Whole party' }],
                        item.targetScope || '',
                        v => { if (v === '') { delete item.targetScope; } else { item.targetScope = v; } }));
                    itemRow.appendChild(scopeGroup);
                }

                createFormField(itemRow, 'Buy Cost (G)', item.cost || 0, val => { item.cost = parseInt(val) || 0; }, 'number');
                formPanel.appendChild(itemRow);

                if (item.type !== 'equipment') {
                    const animGroup = document.createElement('div');
                    animGroup.className = 'form-group';
                    const aLbl = document.createElement('label');
                    aLbl.textContent = 'Animation';
                    animGroup.appendChild(aLbl);
                    const animOpts = [{ value: '', label: '(default)' }];
                    if (dbPayload.animations) {
                        Object.keys(dbPayload.animations).forEach(id => {
                            const animObj = dbPayload.animations[id];
                            if (animObj.class === 'assignable') {
                                animOpts.push({ value: id, label: id });
                            }
                        });
                    }
                    animGroup.appendChild(makeSelect(animOpts, item.animation || '', v => {
                        if (v === '') { delete item.animation; } else { item.animation = v; }
                    }));
                    formPanel.appendChild(animGroup);
                }

                createFormField(formPanel, 'Description', item.description || '', val => { item.description = val; });

                if (item.type === 'equipment') {
                    buildTraitsEditor(formPanel, item, 'Equipment Traits');
                } else {
                    buildEffectsEditor(formPanel, item);
                }

            } else if (activeDbTab === 'skills') {
                const skill = dbPayload.skills[item.id];
                if (!skill) return;
                createFormField(formPanel, 'Name', skill.name || '', val => { skill.name = val; initDatabaseEditor(true); });
                createFormField(formPanel, 'Description', skill.description || '', val => { skill.description = val; });

                const targetGroup = document.createElement('div');
                targetGroup.className = 'form-group';
                const tLbl = document.createElement('label');
                tLbl.textContent = 'Target';
                targetGroup.appendChild(tLbl);
                targetGroup.appendChild(makeSelect(SKILL_TARGETS, skill.target || 'enemy-any', v => { skill.target = v; }));
                formPanel.appendChild(targetGroup);

                const elGroup = document.createElement('div');
                elGroup.className = 'form-group';
                const eLbl = document.createElement('label');
                eLbl.textContent = 'Element';
                elGroup.appendChild(eLbl);
                elGroup.appendChild(makeSelect(elementOptions(true), skill.element || '', v => {
                    if (v === '') { skill.element = null; } else { skill.element = v; }
                }));
                formPanel.appendChild(elGroup);

                const animGroup = document.createElement('div');
                animGroup.className = 'form-group';
                const aLbl = document.createElement('label');
                aLbl.textContent = 'Animation';
                animGroup.appendChild(aLbl);
                const animOpts = [{ value: '', label: '(default)' }];
                if (dbPayload.animations) {
                    Object.keys(dbPayload.animations).forEach(id => {
                        const animObj = dbPayload.animations[id];
                        if (animObj.class === 'assignable') {
                            animOpts.push({ value: id, label: id });
                        }
                    });
                }
                animGroup.appendChild(makeSelect(animOpts, skill.animation || '', v => {
                    if (v === '') { delete skill.animation; } else { skill.animation = v; }
                }));
                formPanel.appendChild(animGroup);

                const costRow = document.createElement('div');
                costRow.className = 'form-row';
                createFormField(costRow, 'MP Cost', skill.mpCost || 0, val => { skill.mpCost = parseInt(val) || 0; }, 'number');
                createFormField(costRow, 'Speed Bonus', skill.speed || 0, val => { skill.speed = parseInt(val) || 0; }, 'number');
                formPanel.appendChild(costRow);

                buildEffectsEditor(formPanel, skill);

            } else if (activeDbTab === 'passives') {
                const passive = dbPayload.passives[item.id];
                if (!passive) return;
                const topRow = document.createElement('div');
                topRow.className = 'form-row';
                topRow.style.gap = '0';
                createIconField(topRow, 'Icon', passive.icon || 0, val => { passive.icon = parseInt(val) || 0; }, true);
                createFormField(topRow, 'Name', passive.name || '', val => { passive.name = val; initDatabaseEditor(true); });
                formPanel.appendChild(topRow);

                createFormField(formPanel, 'Description (flavor)', passive.description || '', val => { passive.description = val; });
                createFormField(formPanel, 'Effect Summary (shown in menus)', passive.effect || '', val => { passive.effect = val; });
                createFormField(formPanel, 'Condition (e.g. HP < 50%)', passive.condition || '', val => {
                    if (val === '') { delete passive.condition; } else { passive.condition = val; }
                });
                buildTraitsEditor(formPanel, passive);

            } else if (activeDbTab === 'states') {
                const state = dbPayload.states[item.id];
                if (!state) return;
                const topRow = document.createElement('div');
                topRow.className = 'form-row';
                topRow.style.gap = '0';
                createIconField(topRow, 'Icon', state.icon || 0, val => { state.icon = parseInt(val) || 0; }, true);
                createFormField(topRow, 'Name', state.name || '', val => { state.name = val; initDatabaseEditor(true); });
                formPanel.appendChild(topRow);

                const stRow = document.createElement('div');
                stRow.className = 'form-row';
                createFormField(stRow, 'Duration (turns, 9999 = permanent)', state.duration || 3, val => { state.duration = parseInt(val) || 0; }, 'number');
                formPanel.appendChild(stRow);
                createCheckboxField(formPanel, 'Removed when taking damage', state.removeAtDamage, v => {
                    if (v) { state.removeAtDamage = true; } else { delete state.removeAtDamage; }
                });
                buildTraitsEditor(formPanel, state);

            } else if (activeDbTab === 'elements') {
                const elem = dbPayload.elements[item.id];
                if (!elem) return;
                const topRow = document.createElement('div');
                topRow.className = 'form-row';
                topRow.style.gap = '0';
                createIconField(topRow, 'Orb Icon', elem.icon !== undefined ? elem.icon : 16, val => { elem.icon = parseInt(val) || 0; }, true);
                createFormField(topRow, 'Name', elem.name || item.id, val => { elem.name = val; initDatabaseEditor(true); });
                formPanel.appendChild(topRow);

                const others = Object.keys(dbPayload.elements).filter(k => k !== item.id);
                buildChecklistField(formPanel, 'Strong Against (deals bonus damage to)', others,
                    id => id,
                    () => elem.strongAgainst, arr => { elem.strongAgainst = arr; });
                buildChecklistField(formPanel, 'Weak Against (deals reduced damage to)', others,
                    id => id,
                    () => elem.weakAgainst, arr => { elem.weakAgainst = arr; });

            } else if (activeDbTab === 'roles') {
                const role = dbPayload.roles[item.id];
                if (!role) return;
                createFormField(formPanel, 'Name', role.name || item.id, val => { role.name = val; initDatabaseEditor(true); });
                createFormField(formPanel, 'Description', role.description || '', val => { role.description = val; });
                if (item.id === 'Summoner') {
                    const note = document.createElement('p');
                    note.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow);';
                    note.textContent = 'The engine locates the player character by the "Summoner" role — keep exactly one actor with it.';
                    formPanel.appendChild(note);
                }

            } else if (activeDbTab === 'animations') {
                const anim = dbPayload.animations[item.id];
                if (!anim) return;

                // Playback Cleanup at start of rendering new form
                if (formPanel._playbackCleanup) {
                    formPanel._playbackCleanup();
                    delete formPanel._playbackCleanup;
                }

                // Ensure all tracks have unique ids and names
                anim.tracks = anim.tracks || [];
                anim.tracks.forEach((t, i) => {
                    if (!t.id) {
                        t.id = 'node_' + Math.random().toString(36).substr(2, 5) + '_' + i;
                    }
                    if (!t.name) {
                        t.name = 'Node ' + (i + 1) + ' (' + t.type + ')';
                    }
                });

                let activeNodeId = sessionStorage.getItem('hkt_active_node_id_' + anim.id) || (anim.tracks[0] ? anim.tracks[0].id : null);
                if (activeNodeId && !anim.tracks.some(t => t.id === activeNodeId)) {
                    activeNodeId = anim.tracks[0] ? anim.tracks[0].id : null;
                }

                // Create a container with columns to fit Tree, Properties, and Preview side-by-side
                const container = document.createElement('div');
                container.style.cssText = 'display: flex; gap: 16px; align-items: flex-start; width: 100%;';

                const timelineCol = document.createElement('div');
                timelineCol.style.cssText = 'width: 220px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;';

                const propsCol = document.createElement('div');
                propsCol.style.cssText = 'flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 8px; border: 2px outset var(--win-white); padding: 8px; background: var(--win-gray); box-sizing: border-box;';

                const previewCol = document.createElement('div');
                previewCol.style.cssText = 'width: 260px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;';

                // Helpers for collapsible panels
                const createCollapsibleGroup = (parent, titleText, isInitiallyOpen = true) => {
                    const group = document.createElement('div');
                    group.style.cssText = 'border: 1px solid var(--win-shadow); background: var(--win-gray); display: flex; flex-direction: column; margin-bottom: 6px;';

                    const header = document.createElement('div');
                    header.style.cssText = 'background: var(--win-blue); color: #fff; padding: 4px 8px; font-weight: bold; font-size: 11px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; user-select: none;';
                    header.innerHTML = `<span>${titleText}</span><span class="toggle-icon">${isInitiallyOpen ? '▼' : '▶'}</span>`;
                    group.appendChild(header);

                    const content = document.createElement('div');
                    content.style.cssText = `padding: 8px; display: ${isInitiallyOpen ? 'flex' : 'none'}; flex-direction: column; gap: 6px; background: var(--win-gray);`;
                    group.appendChild(content);

                    header.onclick = () => {
                        const isOpen = content.style.display !== 'none';
                        content.style.display = isOpen ? 'none' : 'flex';
                        header.querySelector('.toggle-icon').textContent = isOpen ? '▶' : '▼';
                    };

                    parent.appendChild(group);
                    return content;
                };

                // Render Timeline Track List
                const renderTimelineList = () => {
                    timelineCol.innerHTML = '';
                    
                    const header = document.createElement('div');
                    header.style.cssText = 'font-weight: bold; margin-bottom: 4px;';
                    header.textContent = 'Tracks Timeline';
                    timelineCol.appendChild(header);

                    const toolbar = document.createElement('div');
                    toolbar.style.cssText = 'display: flex; gap: 4px; margin-bottom: 6px;';

                    const addBtn = document.createElement('button');
                    addBtn.className = 'win98-btn';
                    addBtn.textContent = '+ Add Track';
                    addBtn.style.flex = '1';
                    addBtn.onclick = (e) => {
                        e.preventDefault();
                        const newId = 'node_' + Math.random().toString(36).substr(2, 5);
                        anim.tracks.push({
                            id: newId,
                            name: 'Track ' + (anim.tracks.length + 1),
                            type: 'transform',
                            t0: 0,
                            duration: 500,
                            easing: 'linear'
                        });
                        activeNodeId = newId;
                        sessionStorage.setItem('hkt_active_node_id_' + anim.id, newId);
                        setDirty(true);
                        renderAll();
                    };
                    toolbar.appendChild(addBtn);

                    const delBtn = document.createElement('button');
                    delBtn.className = 'win98-btn';
                    delBtn.textContent = 'Delete';
                    delBtn.style.flex = '1';
                    delBtn.disabled = !activeNodeId;
                    delBtn.onclick = (e) => {
                        e.preventDefault();
                        if (!activeNodeId) return;
                        const idx = anim.tracks.findIndex(t => t.id === activeNodeId);
                        if (idx !== -1) {
                            const deletedId = activeNodeId;
                            anim.tracks.splice(idx, 1);
                            anim.tracks.forEach(t => {
                                if (t.parent === deletedId) t.parent = null;
                            });
                            activeNodeId = anim.tracks[0] ? anim.tracks[0].id : null;
                            if (activeNodeId) {
                                sessionStorage.setItem('hkt_active_node_id_' + anim.id, activeNodeId);
                            } else {
                                sessionStorage.removeItem('hkt_active_node_id_' + anim.id);
                            }
                            setDirty(true);
                            renderAll();
                        }
                    };
                    toolbar.appendChild(delBtn);
                    timelineCol.appendChild(toolbar);

                    const listContainer = document.createElement('div');
                    listContainer.style.cssText = 'border: 2px inset var(--win-shadow); background: var(--win-white); overflow-y: auto; height: 350px; padding: 4px; display: flex; flex-direction: column; gap: 4px;';
                    
                    anim.tracks.forEach(tr => {
                        const row = document.createElement('div');
                        row.setAttribute('data-track-id', tr.id);
                        row.style.cssText = 'padding: 6px; cursor: pointer; display: flex; flex-direction: column; gap: 2px; border: 1px solid var(--win-shadow); background: var(--win-gray); box-shadow: 1px 1px 0px #fff inset;';
                        
                        if (tr.id === activeNodeId) {
                            row.style.background = 'var(--win-blue)';
                            row.style.color = '#fff';
                            row.style.borderColor = 'var(--win-dark-shadow)';
                            row.style.boxShadow = 'none';
                        } else {
                            row.onmouseenter = () => { row.style.background = '#f0f0f0'; };
                            row.onmouseleave = () => { if (tr.id !== activeNodeId) row.style.background = 'var(--win-gray)'; };
                        }

                        const topRow = document.createElement('div');
                        topRow.style.cssText = 'display: flex; justify-content: space-between; align-items: center; font-weight: bold; font-size: 11px;';
                        
                        const typeLabel = document.createElement('span');
                        typeLabel.textContent = (tr.type === 'particles' ? '✨ ' : tr.type === 'transform' ? '⬜ ' : '📝 ') + tr.type.toUpperCase();
                        typeLabel.style.fontSize = '9px';
                        typeLabel.style.opacity = '0.7';
                        topRow.appendChild(typeLabel);

                        const nameSpan = document.createElement('span');
                        nameSpan.className = 'track-name-label';
                        nameSpan.textContent = tr.name || tr.id;
                        nameSpan.style.cssText = 'flex: 1; text-align: right; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; margin-left: 6px;';
                        topRow.appendChild(nameSpan);

                        row.appendChild(topRow);

                        const bottomRow = document.createElement('div');
                        bottomRow.className = 'track-time-label';
                        bottomRow.style.cssText = 'font-size: 9px; opacity: 0.8;';
                        bottomRow.textContent = `t = ${tr.t0 || 0}ms (${tr.duration || 0}ms)`;
                        row.appendChild(bottomRow);

                        row.onclick = () => {
                            activeNodeId = tr.id;
                            sessionStorage.setItem('hkt_active_node_id_' + anim.id, tr.id);
                            renderAll();
                        };

                        listContainer.appendChild(row);
                    });

                    timelineCol.appendChild(listContainer);
                };

                // Active Node Properties Panel
                const renderActiveNodeProps = () => {
                    propsCol.innerHTML = '';

                    const header = document.createElement('div');
                    header.style.cssText = 'font-weight: bold; border-bottom: 1px solid var(--win-shadow); padding-bottom: 4px; margin-bottom: 6px;';
                    header.textContent = 'Active Track Settings';
                    propsCol.appendChild(header);

                    const tr = anim.tracks.find(t => t.id === activeNodeId);
                    if (!tr) {
                        const placeholder = document.createElement('div');
                        placeholder.style.cssText = 'color: #777; text-align: center; padding: 20px;';
                        placeholder.textContent = 'No track selected. Add or select a track from the timeline.';
                        propsCol.appendChild(placeholder);
                        return;
                    }

                    // Section 1: Node Settings
                    const settingsGroup = createCollapsibleGroup(propsCol, 'Track Configuration', true);
                    
                    createFormField(settingsGroup, 'Name', tr.name || '', val => {
                        tr.name = val;
                        setDirty(true);
                        const labelEl = timelineCol.querySelector(`[data-track-id="${tr.id}"] .track-name-label`);
                        if (labelEl) labelEl.textContent = val || tr.id;
                    });

                    // Type Select
                    const typeGroup = document.createElement('div');
                    typeGroup.className = 'form-group';
                    const typeLbl = document.createElement('label');
                    typeLbl.textContent = 'Type:';
                    typeGroup.appendChild(typeLbl);
                    const trackTypes = [
                        { value: 'transform', label: 'Transform' },
                        { value: 'particles', label: 'Particles' },
                        { value: 'tint', label: 'Tint' },
                        { value: 'blend', label: 'Blend Mode' },
                        { value: 'shake', label: 'Shake' },
                        { value: 'text_flow', label: 'Text Flow' }
                    ];
                    const typeSelect = makeSelect(trackTypes, tr.type, val => {
                        tr.type = val;
                        // Clean properties
                        Object.keys(tr).forEach(k => {
                            if (k !== 'id' && k !== 'name' && k !== 'parent' && k !== 'type' && k !== 't0' && k !== 'duration' && k !== 'easing' && k !== 'inheritPosition' && k !== 'inheritScale') {
                                delete tr[k];
                            }
                        });
                        // Defaults
                        if (val === 'tint') {
                            tr.color = [1, 1, 1];
                            tr.fromAlpha = 1;
                            tr.toAlpha = 0;
                        } else if (val === 'blend') {
                            tr.mode = 'add';
                        } else if (val === 'transform') {
                            tr.fromX = 0; tr.toX = 0; tr.fromY = 0; tr.toY = 0;
                        } else if (val === 'shake') {
                            tr.amplitude = 2;
                            tr.frequency = 30;
                        } else if (val === 'particles') {
                            tr.rate = 10; tr.lifetime = 0.5; tr.spread = 45; tr.velocity = 50; tr.gravity = 0; tr.x = 0; tr.y = 0;
                        } else if (val === 'text_flow') {
                            tr.sequence = '...'; tr.interval = 100; tr.color = [1, 1, 1]; tr.targetPart = 'hp_gauge';
                        }
                        setDirty(true);
                        renderAll();
                    });
                    typeGroup.appendChild(typeSelect);
                    settingsGroup.appendChild(typeGroup);

                    // Parent Select (Optional parenting)
                    const parentGroup = document.createElement('div');
                    parentGroup.className = 'form-group';
                    const parentLbl = document.createElement('label');
                    parentLbl.textContent = 'Parent Track (Optional):';
                    parentGroup.appendChild(parentLbl);
                    const parentOptions = [{ value: '', label: '(None)' }];
                    anim.tracks.forEach(t => {
                        if (t.id !== tr.id) {
                            parentOptions.push({ value: t.id, label: t.name || t.id });
                        }
                    });
                    const parentSelect = makeSelect(parentOptions, tr.parent || '', val => {
                        tr.parent = val || null;
                        setDirty(true);
                        if (window.onAnimationTrackChanged) window.onAnimationTrackChanged();
                    });
                    parentGroup.appendChild(parentSelect);
                    settingsGroup.appendChild(parentGroup);

                    if (tr.parent) {
                        // Inherit Position
                        const inhPosGroup = document.createElement('div');
                        inhPosGroup.className = 'form-group';
                        const inhPosLbl = document.createElement('label');
                        inhPosLbl.textContent = 'Inherit Position:';
                        inhPosGroup.appendChild(inhPosLbl);
                        const inhPosSelect = makeSelect([
                            { value: 'always', label: 'Always' },
                            { value: 'never', label: 'Never' }
                        ], tr.inheritPosition || 'always', val => {
                            tr.inheritPosition = val;
                            setDirty(true);
                            if (window.onAnimationTrackChanged) window.onAnimationTrackChanged();
                        });
                        inhPosGroup.appendChild(inhPosSelect);
                        settingsGroup.appendChild(inhPosGroup);

                        // Inherit Scale
                        const inhScaleGroup = document.createElement('div');
                        inhScaleGroup.className = 'form-group';
                        const inhScaleLbl = document.createElement('label');
                        inhScaleLbl.textContent = 'Inherit Scale:';
                        inhScaleGroup.appendChild(inhScaleLbl);
                        const inhScaleSelect = makeSelect([
                            { value: 'always', label: 'Always' },
                            { value: 'never', label: 'Never' }
                        ], tr.inheritScale || 'always', val => {
                            tr.inheritScale = val;
                            setDirty(true);
                            if (window.onAnimationTrackChanged) window.onAnimationTrackChanged();
                        });
                        inhScaleGroup.appendChild(inhScaleSelect);
                        settingsGroup.appendChild(inhScaleGroup);
                    }

                    // Section 2: Timing & Parameters
                    const paramsGroup = createCollapsibleGroup(propsCol, 'Timing & Coordinates', true);

                    createFormField(paramsGroup, 'Start Time t0 (ms)', tr.t0 !== undefined ? tr.t0 : 0, val => {
                        tr.t0 = parseInt(val) || 0;
                        setDirty(true);
                        const timeEl = timelineCol.querySelector(`[data-track-id="${tr.id}"] .track-time-label`);
                        if (timeEl) timeEl.textContent = `t = ${tr.t0}ms (${tr.duration || 0}ms)`;
                        if (window.onAnimationTrackChanged) window.onAnimationTrackChanged();
                    }, 'number');

                    createFormField(paramsGroup, 'Duration (ms)', tr.duration !== undefined ? tr.duration : 100, val => {
                        tr.duration = parseInt(val) || 0;
                        setDirty(true);
                        const timeEl = timelineCol.querySelector(`[data-track-id="${tr.id}"] .track-time-label`);
                        if (timeEl) timeEl.textContent = `t = ${tr.t0 || 0}ms (${tr.duration}ms)`;
                        if (window.onAnimationTrackChanged) window.onAnimationTrackChanged();
                    }, 'number');

                    // Easing
                    const easeGroup = document.createElement('div');
                    easeGroup.className = 'form-group';
                    const easeLbl = document.createElement('label');
                    easeLbl.textContent = 'Easing:';
                    easeGroup.appendChild(easeLbl);
                    const easeSelect = makeSelect([
                        { value: 'linear', label: 'Linear' },
                        { value: 'ease_out', label: 'Ease Out' }
                    ], tr.easing || 'linear', val => {
                        tr.easing = val;
                        setDirty(true);
                        if (window.onAnimationTrackChanged) window.onAnimationTrackChanged();
                    });
                    easeGroup.appendChild(easeSelect);
                    paramsGroup.appendChild(easeGroup);

                    // Custom properties based on Type
                    if (tr.type === 'transform') {
                        const rowCoords = document.createElement('div');
                        rowCoords.className = 'form-row';
                        createFormField(rowCoords, 'Start X (fromX)', tr.fromX !== undefined ? tr.fromX : 0, val => {
                            tr.fromX = parseInt(val) || 0;
                            setDirty(true);
                            if (anim.drawOverlayHandles) anim.drawOverlayHandles();
                        }, 'number', false, 'fromX');
                        createFormField(rowCoords, 'End X (toX)', tr.toX !== undefined ? tr.toX : 0, val => {
                            tr.toX = parseInt(val) || 0;
                            setDirty(true);
                            if (anim.drawOverlayHandles) anim.drawOverlayHandles();
                        }, 'number', false, 'toX');
                        paramsGroup.appendChild(rowCoords);

                        const rowCoordsY = document.createElement('div');
                        rowCoordsY.className = 'form-row';
                        createFormField(rowCoordsY, 'Start Y (fromY)', tr.fromY !== undefined ? tr.fromY : 0, val => {
                            tr.fromY = parseInt(val) || 0;
                            setDirty(true);
                            if (anim.drawOverlayHandles) anim.drawOverlayHandles();
                        }, 'number', false, 'fromY');
                        createFormField(rowCoordsY, 'End Y (toY)', tr.toY !== undefined ? tr.toY : 0, val => {
                            tr.toY = parseInt(val) || 0;
                            setDirty(true);
                            if (anim.drawOverlayHandles) anim.drawOverlayHandles();
                        }, 'number', false, 'toY');
                        paramsGroup.appendChild(rowCoordsY);

                        const rowScale = document.createElement('div');
                        rowScale.className = 'form-row';
                        createFormField(rowScale, 'Start Scale X', tr.fromScaleX !== undefined ? tr.fromScaleX : 1.0, val => {
                            tr.fromScaleX = parseFloat(val) || 1.0;
                            setDirty(true);
                        }, 'number');
                        createFormField(rowScale, 'End Scale X', tr.toScaleX !== undefined ? tr.toScaleX : 1.0, val => {
                            tr.toScaleX = parseFloat(val) || 1.0;
                            setDirty(true);
                        }, 'number');
                        paramsGroup.appendChild(rowScale);

                        const rowScaleY = document.createElement('div');
                        rowScaleY.className = 'form-row';
                        createFormField(rowScaleY, 'Start Scale Y', tr.fromScaleY !== undefined ? tr.fromScaleY : 1.0, val => {
                            tr.fromScaleY = parseFloat(val) || 1.0;
                            setDirty(true);
                        }, 'number');
                        createFormField(rowScaleY, 'End Scale Y', tr.toScaleY !== undefined ? tr.toScaleY : 1.0, val => {
                            tr.toScaleY = parseFloat(val) || 1.0;
                            setDirty(true);
                        }, 'number');
                        paramsGroup.appendChild(rowScaleY);

                    } else if (tr.type === 'particles') {
                        const rowCoords = document.createElement('div');
                        rowCoords.className = 'form-row';
                        createFormField(rowCoords, 'Offset X', tr.x !== undefined ? tr.x : 0, val => {
                            tr.x = parseInt(val) || 0;
                            setDirty(true);
                            if (anim.drawOverlayHandles) anim.drawOverlayHandles();
                        }, 'number', false, 'x');
                        createFormField(rowCoords, 'Offset Y', tr.y !== undefined ? tr.y : 0, val => {
                            tr.y = parseInt(val) || 0;
                            setDirty(true);
                            if (anim.drawOverlayHandles) anim.drawOverlayHandles();
                        }, 'number', false, 'y');
                        paramsGroup.appendChild(rowCoords);

                        const rowRate = document.createElement('div');
                        rowRate.className = 'form-row';
                        createFormField(rowRate, 'Emission Rate', tr.rate !== undefined ? tr.rate : 10, val => {
                            tr.rate = parseFloat(val) || 10;
                            setDirty(true);
                        }, 'number');
                        createFormField(rowRate, 'Particle Lifetime', tr.lifetime !== undefined ? tr.lifetime : 0.5, val => {
                            tr.lifetime = parseFloat(val) || 0.5;
                            setDirty(true);
                        }, 'number');
                        paramsGroup.appendChild(rowRate);

                        const rowSpread = document.createElement('div');
                        rowSpread.className = 'form-row';
                        createFormField(rowSpread, 'Spread Angle (deg)', tr.spread !== undefined ? tr.spread : 45, val => {
                            tr.spread = parseFloat(val) || 0;
                            setDirty(true);
                        }, 'number');
                        createFormField(rowSpread, 'Velocity', tr.velocity !== undefined ? tr.velocity : 50, val => {
                            tr.velocity = parseFloat(val) || 0;
                            setDirty(true);
                        }, 'number');
                        paramsGroup.appendChild(rowSpread);

                        createFormField(paramsGroup, 'Gravity Acceleration', tr.gravity !== undefined ? tr.gravity : 0, val => {
                            tr.gravity = parseFloat(val) || 0;
                            setDirty(true);
                        }, 'number');

                        // Section 3: Visual Settings (Particles specific)
                        const visualGroup = createCollapsibleGroup(propsCol, 'Particle Visuals & Textures', true);

                        // Particle texture
                        const texGroup = document.createElement('div');
                        texGroup.className = 'form-group';
                        const texLbl = document.createElement('label');
                        texLbl.textContent = 'Particle Texture:';
                        texGroup.appendChild(texLbl);

                        const texRow = document.createElement('div');
                        texRow.style.cssText = 'display: flex; gap: 4px;';
                        const texInput = document.createElement('input');
                        texInput.type = 'text';
                        texInput.className = 'win98-input';
                        texInput.style.flex = '1';
                        texInput.value = tr.particleTexture || '';
                        texInput.oninput = () => {
                            tr.particleTexture = texInput.value || undefined;
                            setDirty(true);
                        };
                        texRow.appendChild(texInput);

                        const browseBtn = document.createElement('button');
                        browseBtn.className = 'win98-btn';
                        browseBtn.textContent = '...';
                        browseBtn.style.padding = '0 6px';
                        browseBtn.onclick = (e) => {
                            e.preventDefault();
                            openAssetPicker('animation', (filepath) => {
                                const clean = filepath.replace(/\\/g, '/');
                                texInput.value = clean;
                                tr.particleTexture = clean;
                                setDirty(true);
                            });
                        };
                        texRow.appendChild(browseBtn);
                        texGroup.appendChild(texRow);
                        visualGroup.appendChild(texGroup);

                        // Quads slicing
                        const rowQuads = document.createElement('div');
                        rowQuads.className = 'form-row';
                        createFormField(rowQuads, 'Quad Width', tr.quadWidth !== undefined ? tr.quadWidth : '', val => {
                            if (val === '') delete tr.quadWidth;
                            else tr.quadWidth = parseInt(val) || undefined;
                            setDirty(true);
                        }, 'number');
                        createFormField(rowQuads, 'Quad Height', tr.quadHeight !== undefined ? tr.quadHeight : '', val => {
                            if (val === '') delete tr.quadHeight;
                            else tr.quadHeight = parseInt(val) || undefined;
                            setDirty(true);
                        }, 'number');
                        createFormField(rowQuads, 'Quad Count', tr.quadCount !== undefined ? tr.quadCount : '', val => {
                            if (val === '') delete tr.quadCount;
                            else tr.quadCount = parseInt(val) || undefined;
                            setDirty(true);
                        }, 'number');
                        visualGroup.appendChild(rowQuads);

                        // Mask Target checkbox
                        createCheckboxField(visualGroup, 'Mask to Target Battler Sprite', tr.mask === 'target', v => {
                            if (v) tr.mask = 'target';
                            else delete tr.mask;
                            setDirty(true);
                        });

                        // Colors Over Life
                        createFormField(visualGroup, 'Colors Over Life (JSON Array)', JSON.stringify(tr.colorOverLife || [[1, 1, 1, 1], [1, 1, 1, 0]]), val => {
                            try {
                                tr.colorOverLife = JSON.parse(val);
                                setDirty(true);
                            } catch (e) {}
                        });

                    } else if (tr.type === 'tint') {
                        const rgb01ToHex = c => '#' + (c || [1, 1, 1]).slice(0, 3)
                            .map(v => Math.round((v || 0) * 255).toString(16).padStart(2, '0')).join('');
                        const hexToRgb01 = hex => [1, 3, 5].map(i => Math.round(parseInt(hex.substr(i, 2), 16) / 255 * 100) / 100);

                        const colGroup = document.createElement('div');
                        colGroup.className = 'form-group';
                        const colLbl = document.createElement('label');
                        colLbl.textContent = 'Tint Color:';
                        colGroup.appendChild(colLbl);

                        const colPick = document.createElement('input');
                        colPick.type = 'color';
                        colPick.value = rgb01ToHex(tr.color);
                        colPick.oninput = () => {
                            tr.color = hexToRgb01(colPick.value);
                            setDirty(true);
                        };
                        colGroup.appendChild(colPick);
                        paramsGroup.appendChild(colGroup);

                        const rowAlpha = document.createElement('div');
                        rowAlpha.className = 'form-row';
                        createFormField(rowAlpha, 'Start Alpha', tr.fromAlpha !== undefined ? tr.fromAlpha : 1, val => {
                            tr.fromAlpha = parseFloat(val) || 0;
                            setDirty(true);
                        }, 'number');
                        createFormField(rowAlpha, 'End Alpha', tr.toAlpha !== undefined ? tr.toAlpha : 0, val => {
                            tr.toAlpha = parseFloat(val) || 0;
                            setDirty(true);
                        }, 'number');
                        paramsGroup.appendChild(rowAlpha);

                    } else if (tr.type === 'blend') {
                        const blendGroup = document.createElement('div');
                        blendGroup.className = 'form-group';
                        const blendLbl = document.createElement('label');
                        blendLbl.textContent = 'Blend Mode:';
                        blendGroup.appendChild(blendLbl);
                        const blendSelect = makeSelect([
                            { value: 'add', label: 'Add' },
                            { value: 'alpha', label: 'Alpha' }
                        ], tr.mode || 'add', val => {
                            tr.mode = val;
                            setDirty(true);
                        });
                        blendGroup.appendChild(blendSelect);
                        paramsGroup.appendChild(blendGroup);

                    } else if (tr.type === 'shake') {
                        const rowShake = document.createElement('div');
                        rowShake.className = 'form-row';
                        createFormField(rowShake, 'Amplitude (px)', tr.amplitude !== undefined ? tr.amplitude : 2, val => {
                            tr.amplitude = parseInt(val) || 0;
                            setDirty(true);
                        }, 'number');
                        createFormField(rowShake, 'Frequency (Hz)', tr.frequency !== undefined ? tr.frequency : 30, val => {
                            tr.frequency = parseInt(val) || 0;
                            setDirty(true);
                        }, 'number');
                        paramsGroup.appendChild(rowShake);

                    } else if (tr.type === 'text_flow') {
                        const rgb01ToHex = c => '#' + (c || [1, 1, 1]).slice(0, 3)
                            .map(v => Math.round((v || 0) * 255).toString(16).padStart(2, '0')).join('');
                        const hexToRgb01 = hex => [1, 3, 5].map(i => Math.round(parseInt(hex.substr(i, 2), 16) / 255 * 100) / 100);

                        createFormField(paramsGroup, 'Text Sequence', tr.sequence || '', val => {
                            tr.sequence = val;
                            setDirty(true);
                        });

                        createFormField(paramsGroup, 'Character Interval (ms)', tr.interval || 100, val => {
                            tr.interval = parseInt(val) || 100;
                            setDirty(true);
                        }, 'number');

                        const colGroup = document.createElement('div');
                        colGroup.className = 'form-group';
                        const colLbl = document.createElement('label');
                        colLbl.textContent = 'Text Color:';
                        colGroup.appendChild(colLbl);

                        const colPick = document.createElement('input');
                        colPick.type = 'color';
                        colPick.value = rgb01ToHex(tr.color);
                        colPick.oninput = () => {
                            tr.color = hexToRgb01(colPick.value);
                            setDirty(true);
                        };
                        colGroup.appendChild(colPick);
                        paramsGroup.appendChild(colGroup);

                        const targetPartGroup = document.createElement('div');
                        targetPartGroup.className = 'form-group';
                        const targetPartLbl = document.createElement('label');
                        targetPartLbl.textContent = 'Target Placement:';
                        targetPartGroup.appendChild(targetPartLbl);
                        const targetPartSelect = makeSelect([
                            { value: 'hp_gauge', label: 'HP Gauge' },
                            { value: 'mp_gauge', label: 'MP Gauge' },
                            { value: 'top', label: 'Top / Head' }
                        ], tr.targetPart || 'hp_gauge', val => {
                            tr.targetPart = val;
                            setDirty(true);
                        });
                        targetPartGroup.appendChild(targetPartSelect);
                        paramsGroup.appendChild(targetPartGroup);
                    }
                };

                const renderAll = () => {
                    renderTimelineList();
                    renderActiveNodeProps();
                    if (drawOverlayHandles) drawOverlayHandles();
                };

                // Render left-side globals (ID, Class, Duration) above the tree
                const globalsWrap = document.createElement('div');
                globalsWrap.style.cssText = 'width: 100%; border: 2px outset var(--win-white); padding: 8px; background: var(--win-gray); margin-bottom: 12px; display: flex; gap: 12px;';

                createFormField(globalsWrap, 'Animation ID', anim.id, val => {
                    const oldId = anim.id;
                    if (val && val !== oldId && !dbPayload.animations[val]) {
                        dbPayload.animations[val] = anim;
                        anim.id = val;
                        delete dbPayload.animations[oldId];
                        activeDbItemId = val;
                        initDatabaseEditor(true);
                    }
                }, 'text', anim.class === 'system');

                createFormField(globalsWrap, 'Class', anim.class || 'assignable', null, 'text', true);

                createFormField(globalsWrap, 'Duration (ms)', anim.duration || 1000, val => {
                    anim.duration = parseInt(val) || 1000;
                }, 'number');

                formPanel.appendChild(globalsWrap);

                // Right Column: Live Preview Panel
                const previewGroup = document.createElement('div');
                previewGroup.className = 'form-group';
                previewGroup.style.cssText = 'border: 2px outset var(--win-white); padding: 8px; background: var(--win-gray);';

                const prevTitle = document.createElement('div');
                prevTitle.style.cssText = 'font-weight: bold; margin-bottom: 6px;';
                prevTitle.textContent = 'Live Animation Preview';
                previewGroup.appendChild(prevTitle);

                // Notice bar for sync/desync
                const noticeBar = document.createElement('div');
                noticeBar.style.cssText = 'padding: 4px; font-size: 10px; margin-bottom: 8px; border: 1px solid var(--win-shadow); font-weight: bold; text-align: center;';
                previewGroup.appendChild(noticeBar);

                // Sprite Picker
                const sprLabel = document.createElement('label');
                sprLabel.textContent = 'Preview Sprite:';
                previewGroup.appendChild(sprLabel);

                const sprRow = document.createElement('div');
                sprRow.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-bottom: 8px;';

                const sprInput = document.createElement('input');
                sprInput.type = 'text';
                sprInput.className = 'win98-input';
                sprInput.style.flex = '1';
                sprInput.value = sessionStorage.getItem('hkt_preview_sprite') || 'assets/smallBattlers/pixie.png';
                sprInput.oninput = () => {
                    sessionStorage.setItem('hkt_preview_sprite', sprInput.value);
                    setPreviewDesynced(true);
                };

                const sprBrowse = document.createElement('button');
                sprBrowse.className = 'win98-btn';
                sprBrowse.textContent = '...';
                sprBrowse.style.padding = '0 6px';
                sprBrowse.onclick = (e) => {
                    e.preventDefault();
                    openAssetPicker('smallBattlers', (filepath) => {
                        const cleanPath = filepath.replace(/\\/g, '/');
                        sprInput.value = cleanPath;
                        sessionStorage.setItem('hkt_preview_sprite', cleanPath);
                        setPreviewDesynced(true);
                    });
                };

                sprRow.appendChild(sprInput);
                sprRow.appendChild(sprBrowse);
                previewGroup.appendChild(sprRow);

                // Preview screen (image + SVG overlay for editing)
                const imgWrap = document.createElement('div');
                imgWrap.style.cssText = 'width: 240px; height: 240px; border: 2px inset var(--win-shadow); background: #000; display: flex; align-items: center; justify-content: center; margin: 8px auto; position: relative; overflow: hidden; user-select: none;';
                
                const previewImg = document.createElement('img');
                previewImg.style.cssText = 'width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; display: none; pointer-events: none;';
                imgWrap.appendChild(previewImg);

                const noPreviewTxt = document.createElement('div');
                noPreviewTxt.style.cssText = 'color: #888; font-size: 11px; text-align: center; pointer-events: none;';
                noPreviewTxt.textContent = 'Bake required';
                imgWrap.appendChild(noPreviewTxt);

                // SVG overlay for handles
                const svgOverlay = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
                svgOverlay.id = 'preview-svg';
                svgOverlay.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: auto;';
                imgWrap.appendChild(svgOverlay);

                previewGroup.appendChild(imgWrap);

                // Scrubber / Slider
                const scrubber = document.createElement('input');
                scrubber.type = 'range';
                scrubber.className = 'win98-slider';
                scrubber.style.cssText = 'width: 100%; margin-bottom: 6px;';
                scrubber.min = '0';
                scrubber.max = '0';
                scrubber.value = '0';
                scrubber.disabled = true;
                previewGroup.appendChild(scrubber);

                // Timeline Controls
                const ctrlRow = document.createElement('div');
                ctrlRow.style.cssText = 'display: flex; gap: 4px; align-items: center; justify-content: space-between; margin-bottom: 8px;';

                const frameLabel = document.createElement('span');
                frameLabel.textContent = 'Frame: 0 / 0';
                frameLabel.style.cssText = 'font-size: 10px; min-width: 75px; font-family: monospace;';
                ctrlRow.appendChild(frameLabel);

                const playbackBtns = document.createElement('div');
                playbackBtns.style.cssText = 'display: flex; gap: 2px;';

                const prevFrameBtn = document.createElement('button');
                prevFrameBtn.className = 'win98-btn';
                prevFrameBtn.textContent = '◀';
                prevFrameBtn.style.padding = '0 5px';
                prevFrameBtn.disabled = true;
                playbackBtns.appendChild(prevFrameBtn);

                const playBtn = document.createElement('button');
                playBtn.className = 'win98-btn';
                playBtn.textContent = 'Play';
                playBtn.style.padding = '0 10px';
                playBtn.disabled = true;
                playbackBtns.appendChild(playBtn);

                const nextFrameBtn = document.createElement('button');
                nextFrameBtn.className = 'win98-btn';
                nextFrameBtn.textContent = '▶';
                nextFrameBtn.style.padding = '0 5px';
                nextFrameBtn.disabled = true;
                playbackBtns.appendChild(nextFrameBtn);

                const stopBtn = document.createElement('button');
                stopBtn.className = 'win98-btn';
                stopBtn.textContent = 'Stop';
                stopBtn.style.padding = '0 10px';
                stopBtn.disabled = true;
                playbackBtns.appendChild(stopBtn);

                ctrlRow.appendChild(playbackBtns);
                previewGroup.appendChild(ctrlRow);

                // Bake button
                const bakeBtn = document.createElement('button');
                bakeBtn.className = 'win98-btn';
                bakeBtn.textContent = 'Bake / Render Preview';
                bakeBtn.style.cssText = 'width: 100%; padding: 6px; font-weight: bold;';
                previewGroup.appendChild(bakeBtn);

                // Playback states
                let bakedFrames = [];
                let currentFrameIdx = 0;
                let isPlaying = false;
                let playbackInterval = null;
                let previewDesynced = true;

                const updateNoticeBar = () => {
                    if (previewDesynced) {
                        noticeBar.textContent = '⚠️ Preview desynced. Re-bake required.';
                        noticeBar.style.backgroundColor = '#ffeecc';
                        noticeBar.style.color = '#8a5a00';
                        noticeBar.style.borderColor = '#ddbb88';
                    } else {
                        noticeBar.textContent = '✅ Preview up to date';
                        noticeBar.style.backgroundColor = '#ddffdd';
                        noticeBar.style.color = '#006600';
                        noticeBar.style.borderColor = '#99cc99';
                    }
                };

                const setPreviewDesynced = (val) => {
                    previewDesynced = val;
                    updateNoticeBar();
                };

                // Assign global callback for the tracks editor to mark desync on any track modification
                window.onAnimationTrackChanged = () => {
                    setPreviewDesynced(true);
                };

                const updateFrameView = () => {
                    if (bakedFrames.length === 0) {
                        previewImg.style.display = 'none';
                        noPreviewTxt.style.display = 'block';
                        noPreviewTxt.textContent = 'Bake required';
                        frameLabel.textContent = 'Frame: 0 / 0';
                        return;
                    }

                    noPreviewTxt.style.display = 'none';
                    previewImg.style.display = 'block';
                    previewImg.src = 'data:image/png;base64,' + bakedFrames[currentFrameIdx];
                    frameLabel.textContent = `Frame: ${currentFrameIdx + 1} / ${bakedFrames.length}`;
                    scrubber.value = currentFrameIdx;
                };

                const stopPlayback = () => {
                    if (playbackInterval) {
                        clearInterval(playbackInterval);
                        playbackInterval = null;
                    }
                    isPlaying = false;
                    playBtn.textContent = 'Play';
                    currentFrameIdx = 0;
                    updateFrameView();
                };

                const pausePlayback = () => {
                    if (playbackInterval) {
                        clearInterval(playbackInterval);
                        playbackInterval = null;
                    }
                    isPlaying = false;
                    playBtn.textContent = 'Play';
                };

                const playPlayback = () => {
                    if (bakedFrames.length === 0) return;
                    isPlaying = true;
                    playBtn.textContent = 'Pause';
                    playbackInterval = setInterval(() => {
                        currentFrameIdx = (currentFrameIdx + 1) % bakedFrames.length;
                        updateFrameView();
                    }, 50); // 20 FPS
                };

                playBtn.onclick = (e) => {
                    e.preventDefault();
                    if (isPlaying) {
                        pausePlayback();
                    } else {
                        playPlayback();
                    }
                };

                stopBtn.onclick = (e) => {
                    e.preventDefault();
                    stopPlayback();
                };

                prevFrameBtn.onclick = (e) => {
                    e.preventDefault();
                    pausePlayback();
                    if (bakedFrames.length > 0) {
                        currentFrameIdx = (currentFrameIdx - 1 + bakedFrames.length) % bakedFrames.length;
                        updateFrameView();
                    }
                };

                nextFrameBtn.onclick = (e) => {
                    e.preventDefault();
                    pausePlayback();
                    if (bakedFrames.length > 0) {
                        currentFrameIdx = (currentFrameIdx + 1) % bakedFrames.length;
                        updateFrameView();
                    }
                };

                scrubber.oninput = () => {
                    pausePlayback();
                    currentFrameIdx = parseInt(scrubber.value);
                    updateFrameView();
                };

                bakeBtn.onclick = (e) => {
                    e.preventDefault();
                    stopPlayback();
                    noPreviewTxt.textContent = 'Rendering...';
                    previewImg.style.display = 'none';
                    noPreviewTxt.style.display = 'block';
                    bakeBtn.disabled = true;

                    fetch('/preview-anim', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            id: anim.id,
                            sprite: sprInput.value,
                            data: anim
                        })
                    })
                    .then(res => res.json())
                    .then(resData => {
                        bakeBtn.disabled = false;
                        if (resData.error) {
                            noPreviewTxt.textContent = 'Error: ' + resData.error;
                            return;
                        }
                        bakedFrames = resData.frames || [];
                        if (bakedFrames.length === 0) {
                            noPreviewTxt.textContent = 'No frames returned';
                            return;
                        }

                        scrubber.disabled = false;
                        scrubber.max = bakedFrames.length - 1;
                        playBtn.disabled = false;
                        prevFrameBtn.disabled = false;
                        nextFrameBtn.disabled = false;
                        stopBtn.disabled = false;

                        setPreviewDesynced(false);
                        currentFrameIdx = 0;
                        updateFrameView();
                        
                        playPlayback();
                    })
                    .catch(err => {
                        bakeBtn.disabled = false;
                        noPreviewTxt.textContent = 'Bake failed';
                    });
                };

                // SVG interactive drag handles drawing
                const createSvgHandle = (svg, x, y, color, label, onDrag) => {
                    const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
                    g.style.cursor = 'pointer';

                    const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                    circle.setAttribute('cx', x);
                    circle.setAttribute('cy', y);
                    circle.setAttribute('r', 6);
                    circle.setAttribute('fill', color);
                    circle.setAttribute('stroke', '#ffffff');
                    circle.setAttribute('stroke-width', '1.5');
                    g.appendChild(circle);

                    const txt = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                    txt.setAttribute('x', x);
                    txt.setAttribute('y', y - 10);
                    txt.setAttribute('text-anchor', 'middle');
                    txt.setAttribute('fill', '#ffffff');
                    txt.style.fontSize = '9px';
                    txt.style.fontFamily = 'monospace';
                    txt.style.textShadow = '1px 1px 1px #000000';
                    txt.textContent = label;
                    g.appendChild(txt);

                    svg.appendChild(g);

                    const onMouseMove = (e) => {
                        const rect = svg.getBoundingClientRect();
                        const mx = e.clientX - rect.left;
                        const my = e.clientY - rect.top;
                        const clampedX = Math.max(0, Math.min(240, mx));
                        const clampedY = Math.max(0, Math.min(240, my));
                        onDrag(clampedX, clampedY);
                    };

                    const onMouseUp = () => {
                        document.removeEventListener('mousemove', onMouseMove);
                        document.removeEventListener('mouseup', onMouseUp);
                    };

                    g.addEventListener('mousedown', (e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        document.addEventListener('mousemove', onMouseMove);
                        document.addEventListener('mouseup', onMouseUp);
                    });
                };

                const drawOverlayHandles = () => {
                    svgOverlay.innerHTML = '';

                    const tr = anim.tracks.find(t => t.id === activeNodeId);
                    if (!tr) return;

                    const idx = anim.tracks.findIndex(t => t.id === activeNodeId);
                    const trackNum = idx + 1;
                    if (tr.type === 'transform') {
                        const startX = 120 + (tr.fromX || 0);
                        const startY = 120 + (tr.fromY || 0);
                        createSvgHandle(svgOverlay, startX, startY, '#ff3333', `T${trackNum} Start`, (mx, my) => {
                            tr.fromX = Math.round(mx - 120);
                            tr.fromY = Math.round(my - 120);
                            setDirty(true);
                            
                            const fieldX = document.getElementById('field-fromX');
                            const fieldY = document.getElementById('field-fromY');
                            if (fieldX) fieldX.value = tr.fromX;
                            if (fieldY) fieldY.value = tr.fromY;
                            
                            drawOverlayHandles();
                        });

                        const endX = 120 + (tr.toX || 0);
                        const endY = 120 + (tr.toY || 0);
                        createSvgHandle(svgOverlay, endX, endY, '#3333ff', `T${trackNum} End`, (mx, my) => {
                            tr.toX = Math.round(mx - 120);
                            tr.toY = Math.round(my - 120);
                            setDirty(true);
                            
                            const fieldX = document.getElementById('field-toX');
                            const fieldY = document.getElementById('field-toY');
                            if (fieldX) fieldX.value = tr.toX;
                            if (fieldY) fieldY.value = tr.toY;
                            
                            drawOverlayHandles();
                        });

                        const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
                        line.setAttribute('x1', startX);
                        line.setAttribute('y1', startY);
                        line.setAttribute('x2', endX);
                        line.setAttribute('y2', endY);
                        line.setAttribute('stroke', '#8888ff');
                        line.setAttribute('stroke-dasharray', '4');
                        line.setAttribute('stroke-width', '1.5');
                        svgOverlay.appendChild(line);

                    } else if (tr.type === 'particles') {
                        const x = 120 + (tr.x || 0);
                        const y = 120 + (tr.y || 0);
                        createSvgHandle(svgOverlay, x, y, '#33cc33', `T${trackNum} Emitter`, (mx, my) => {
                            tr.x = Math.round(mx - 120);
                            tr.y = Math.round(my - 120);
                            setDirty(true);
                            
                            const fieldX = document.getElementById('field-x');
                            const fieldY = document.getElementById('field-y');
                            if (fieldX) fieldX.value = tr.x;
                            if (fieldY) fieldY.value = tr.y;
                            
                            drawOverlayHandles();
                        });
                    }
                };

                anim.drawOverlayHandles = drawOverlayHandles;

                // Render everything initially
                renderAll();

                formPanel._playbackCleanup = () => {
                    stopPlayback();
                    window.onAnimationTrackChanged = null;
                };

                previewCol.appendChild(previewGroup);

                container.appendChild(timelineCol);
                container.appendChild(propsCol);
                container.appendChild(previewCol);
                formPanel.appendChild(container);

            } else if (activeDbTab === 'terms') {
                if (!dbPayload.terms) dbPayload.terms = {};
                buildRecursiveForm(formPanel, dbPayload.terms, [], dbPayload.terms);

            } else if (activeDbTab === 'shops') {
                const shopData = dbPayload.shops[item.id];
                createFormField(formPanel, 'Shop Name', shopData.name || '', val => {
                    shopData.name = val;
                    initDatabaseEditor(true);
                });

                const listWrapper = document.createElement('div');
                listWrapper.className = 'form-group';
                const lbl = document.createElement('label');
                lbl.textContent = 'Stock Selection (price override + unlock condition)';
                listWrapper.appendChild(lbl);

                const renderStock = () => {
                    listWrapper.querySelectorAll('.shop-stock-row').forEach(el => el.remove());
                    dbPayload.items.forEach(availItem => {
                        const stockEntry = shopData.items.find(shIt => shIt.id === availItem.id);
                        const div = document.createElement('div');
                        div.className = 'shop-stock-row';
                        div.style.cssText = 'margin: 4px 0; display: flex; align-items: center; gap: 6px;';

                        const chk = document.createElement('input');
                        chk.type = 'checkbox';
                        chk.checked = !!stockEntry;
                        chk.onchange = () => {
                            setDirty(true);
                            if (chk.checked) {
                                if (!shopData.items.some(i => i.id === availItem.id)) {
                                    shopData.items.push({ id: availItem.id, price: availItem.cost });
                                }
                            } else {
                                shopData.items = shopData.items.filter(i => i.id !== availItem.id);
                            }
                            renderStock();
                        };

                        const nameSpan = document.createElement('span');
                        nameSpan.style.flex = '1';
                        nameSpan.textContent = `${availItem.name} (base ${availItem.cost} G)`;

                        div.appendChild(chk);
                        div.appendChild(nameSpan);

                        if (stockEntry) {
                            const price = document.createElement('input');
                            price.type = 'number';
                            price.className = 'win98-input';
                            price.style.width = '64px';
                            price.title = 'Shop price (G)';
                            price.value = stockEntry.price !== undefined ? stockEntry.price : availItem.cost;
                            price.oninput = () => { stockEntry.price = parseInt(price.value) || 0; setDirty(true); };
                            div.appendChild(price);

                            const cond = document.createElement('input');
                            cond.type = 'text';
                            cond.className = 'win98-input';
                            cond.style.width = '130px';
                            cond.placeholder = 'level:3 / flag:x / gold:50';
                            cond.title = 'Unlock condition (blank = always available)';
                            cond.value = stockEntry.condition || '';
                            cond.oninput = () => {
                                if (cond.value === '') { delete stockEntry.condition; } else { stockEntry.condition = cond.value; }
                                setDirty(true);
                            };
                            div.appendChild(cond);
                        }

                        listWrapper.appendChild(div);
                    });
                };
                renderStock();
                formPanel.appendChild(listWrapper);
            } else if (activeDbTab === 'system') {
                // Game-content configuration; engine behavior (combat, growth,
                // dungeon generation, rendering) lives in the Engine editor.
                if (!dbPayload.system) dbPayload.system = {};
                const systemConfig = {
                    summoner: dbPayload.system.summoner || {},
                    spawn: dbPayload.system.spawn || {},
                    newGame: dbPayload.system.newGame || {},
                    town: dbPayload.system.town || {}
                };
                buildRecursiveForm(formPanel, systemConfig, [], dbPayload.system);
            }

            // Every tab gets a direct-JSON escape hatch on its edit target
            const jsonTarget = (function () {
                switch (activeDbTab) {
                    case 'actors': case 'items': return item;
                    case 'skills': case 'passives': case 'states':
                    case 'elements': case 'roles': return dbPayload[activeDbTab][item.id];
                    case 'shops': return dbPayload.shops[item.id];
                    case 'commonEvents': return dbPayload.commonEvents[item.id];
                    case 'terms': return dbPayload.terms;
                    case 'system': return dbPayload.system;
                    default: return null;
                }
            })();
            if (jsonTarget) {
                attachJsonToggle(header, formPanel, jsonTarget, () => {
                    initDatabaseEditor();
                });
                if (activeDbTab !== 'terms' && activeDbTab !== 'system') {
                    buildMetaEditor(formPanel, jsonTarget, activeDbTab);
                }
            }
        }

        function buildTabbedSections(container, sections) {
            const tabsContainer = document.createElement('div');
            tabsContainer.style.cssText = 'display: flex; gap: 4px; margin-bottom: 8px; border-bottom: 2px solid var(--win-shadow); padding-bottom: 2px; flex-wrap: wrap;';
            const panelContainer = document.createElement('div');

            let activeTab = null;

            sections.forEach((sec, idx) => {
                const btn = document.createElement('button');
                btn.className = 'db-tab-btn';
                btn.style.padding = '4px 8px';
                btn.textContent = sec.title;
                if (idx === 0) {
                    btn.classList.add('active');
                    activeTab = btn;
                    sec.render(panelContainer);
                }

                btn.onclick = () => {
                    if (activeTab) activeTab.classList.remove('active');
                    btn.classList.add('active');
                    activeTab = btn;
                    panelContainer.innerHTML = '';
                    sec.render(panelContainer);
                };

                tabsContainer.appendChild(btn);
            });

            container.appendChild(tabsContainer);
            container.appendChild(panelContainer);
        }

        function buildFieldGroup(title, cols) {
            const fieldset = document.createElement('fieldset');
            fieldset.style.cssText = `border: 1px solid var(--win-shadow); padding: 8px; margin-bottom: 8px; display: grid; grid-template-columns: repeat(${cols}, 1fr); gap: 10px;`;

            if (title) {
                const legend = document.createElement('legend');
                legend.textContent = title;
                fieldset.appendChild(legend);
            }

            return fieldset;
        }

        function buildRecursiveForm(container, obj, path, targetRoot, depth = 0) {
            if (depth === 0 && obj && typeof obj === 'object') {
                const sections = [];
                for (const key in obj) {
                    if (obj.hasOwnProperty(key)) {
                        sections.push({
                            title: key,
                            render: (panel) => {
                                const subObj = {};
                                subObj[key] = obj[key];
                                buildRecursiveForm(panel, subObj, path, targetRoot, depth + 1);
                            }
                        });
                    }
                }
                if (sections.length > 0) {
                    buildTabbedSections(container, sections);
                    return;
                }
            }

            if (depth === 1 && obj && typeof obj === 'object') {
                for (const topKey in obj) {
                    if (obj.hasOwnProperty(topKey)) {
                        const topVal = obj[topKey];
                        if (typeof topVal === 'object' && topVal !== null && !Array.isArray(topVal)) {
                            // Find properties to put inside the fieldset
                            const keys = Object.keys(topVal);
                            const cols = keys.length > 4 ? 4 : (keys.length > 0 ? keys.length : 1);
                            const fieldset = buildFieldGroup(topKey, cols);
                            buildRecursiveForm(fieldset, topVal, [...path, topKey], targetRoot, depth + 1);
                            container.appendChild(fieldset);
                        } else {
                            // Not an object, just render it normally inside the current container
                            const subObj = {};
                            subObj[topKey] = topVal;
                            // Using a private loop to not change signature too much, just rendering the single property
                            const currentPath = [...path, topKey];
                            const schemaEntry = CONFIG_SCHEMA[currentPath.join('.')];
                            if (schemaEntry && renderSchemaField(container, schemaEntry, topVal, topKey, currentPath, targetRoot, true)) {
                                // rendered
                            } else {
                                // Fallback for single primitive at depth 1
                                const type = typeof topVal === 'number' ? 'number' : 'text';
                                createFormField(container, topKey, topVal, (newVal) => {
                                    let target = targetRoot;
                                    for (let i = 0; i < currentPath.length - 1; i++) {
                                        if (!target[currentPath[i]]) target[currentPath[i]] = {};
                                        target = target[currentPath[i]];
                                    }
                                    if (type === 'number') {
                                        const parsed = parseFloat(newVal);
                                        target[topKey] = isNaN(parsed) ? 0 : parsed;
                                    } else {
                                        target[topKey] = newVal;
                                    }
                                }, type, false, topKey, true);
                            }
                        }
                    }
                }
                return;
            }

            for (const key in obj) {
                if (obj.hasOwnProperty(key)) {
                    const value = obj[key];
                    const currentPath = [...path, key];

                    const useBlockLayout = (depth === 2);

                    const schemaEntry = CONFIG_SCHEMA[currentPath.join('.')];
                    if (schemaEntry && renderSchemaField(container, schemaEntry, value, key, currentPath, targetRoot, useBlockLayout)) {
                        // rendered by a typed schema widget
                    } else if (key === 'fontSize') {
                        // Rendered as part of the 'activeFont' widget below —
                        // both live in ui.lua's ui.setFont(name, size) pair.
                    } else if (key === 'activeFont' || key === 'font') {
                        const navTarget = () => {
                            let target = targetRoot;
                            for (let i = 0; i < currentPath.length - 1; i++) {
                                if (!target[currentPath[i]]) target[currentPath[i]] = {};
                                target = target[currentPath[i]];
                            }
                            return target;
                        };

                        const group = document.createElement('div');
                        group.className = 'form-group';
                        // This widget (select + size + a 200px-wide preview canvas)
                        // needs more room than a single narrow grid column, whatever
                        // the parent field-group's column count happens to be.
                        group.style.gridColumn = '1 / -1';
                        const lbl = document.createElement('label');
                        lbl.textContent = key === 'activeFont' ? 'Active UI Font' : 'Popup Font';
                        group.appendChild(lbl);

                        const row = document.createElement('div');
                        row.style.cssText = 'display: flex; gap: 6px; align-items: center;';

                        const select = document.createElement('select');
                        select.className = 'form-control inset-bevel';
                        select.style.flex = '1';
                        // Seed with the current value alone so the field isn't empty
                        // before /api/fonts responds; getFontChoices() below fills
                        // in the rest and re-applies the selection.
                        const seedOpt = document.createElement('option');
                        seedOpt.value = value; seedOpt.textContent = value;
                        select.appendChild(seedOpt);
                        getFontChoices().then(choices => {
                            select.innerHTML = '';
                            choices.forEach(f => {
                                const opt = document.createElement('option');
                                opt.value = f;
                                opt.textContent = f;
                                if (value === f) opt.selected = true;
                                select.appendChild(opt);
                            });
                        });
                        row.appendChild(select);

                        const sizeInp = document.createElement('input');
                        sizeInp.type = 'number';
                        sizeInp.className = 'form-control inset-bevel';
                        sizeInp.style.width = '56px';
                        sizeInp.min = '6';
                        sizeInp.max = '24';
                        sizeInp.value = (navTarget().fontSize != null) ? navTarget().fontSize : 8;
                        row.appendChild(sizeInp);

                        const sizeLbl = document.createElement('span');
                        sizeLbl.textContent = 'px';
                        sizeLbl.style.fontSize = '10px';
                        row.appendChild(sizeLbl);

                        group.appendChild(row);
                        container.appendChild(group);

                        const preview = buildFontPreview();
                        container.appendChild(preview.el);

                        const refreshPreview = () => preview.render(select.value, parseInt(sizeInp.value, 10) || 8);

                        select.onchange = () => {
                            setDirty(true);
                            navTarget()[key] = select.value;
                            refreshPreview();
                        };
                        sizeInp.oninput = () => {
                            setDirty(true);
                            const n = parseInt(sizeInp.value, 10);
                            navTarget().fontSize = isNaN(n) ? 8 : n;
                            refreshPreview();
                        };

                        refreshPreview();
                    } else if (key === 'dir') {
                        const group = document.createElement('div');
                        group.className = 'form-group';
                        const lbl = document.createElement('label');
                        lbl.textContent = 'Spawn Facing Direction';
                        group.appendChild(lbl);

                        const select = document.createElement('select');
                        select.className = 'form-control inset-bevel';
                        select.id = 'field-dir';
                        const directions = ['N', 'E', 'S', 'W'];
                        directions.forEach(d => {
                            const opt = document.createElement('option');
                            opt.value = d;
                            opt.textContent = d;
                            if (value === d) opt.selected = true;
                            select.appendChild(opt);
                        });

                        select.onchange = () => {
                            setDirty(true);
                            let target = targetRoot;
                            for (let i = 0; i < currentPath.length - 1; i++) {
                                if (!target[currentPath[i]]) target[currentPath[i]] = {};
                                target = target[currentPath[i]];
                            }
                            target[key] = select.value;
                        };

                        group.appendChild(select);
                        container.appendChild(group);
                    } else if (Array.isArray(value)) {
                        const group = document.createElement('div');
                        group.className = 'form-group';
                        const lbl = document.createElement('label');
                        lbl.textContent = key + ' (JSON array)';
                        group.appendChild(lbl);

                        const area = document.createElement('textarea');
                        area.className = 'form-control inset-bevel';
                        area.rows = Math.min(6, Math.max(2, value.length + 1));
                        area.style.fontFamily = 'monospace';
                        area.value = JSON.stringify(value);
                        area.onchange = () => {
                            try {
                                const parsed = JSON.parse(area.value);
                                if (!Array.isArray(parsed)) throw new Error('not an array');
                                let target = targetRoot;
                                for (let i = 0; i < currentPath.length - 1; i++) {
                                    if (!target[currentPath[i]]) target[currentPath[i]] = {};
                                    target = target[currentPath[i]];
                                }
                                target[key] = parsed;
                                area.style.background = '';
                                setDirty(true);
                            } catch (e) {
                                area.style.background = '#ffcccc';
                            }
                        };

                        group.appendChild(area);
                        container.appendChild(group);
                    } else if (typeof value === 'object' && value !== null) {
                        // Create collapsible section header
                        const sectionWrapper = document.createElement('div');
                        sectionWrapper.style.marginBottom = '10px';
                        sectionWrapper.style.border = '1px solid var(--win-shadow)';
                        sectionWrapper.style.padding = '4px';

                        const header = document.createElement('div');
                        header.style.fontWeight = 'bold';
                        header.style.cursor = 'pointer';
                        header.style.backgroundColor = 'var(--win-gray)';
                        header.style.padding = '2px 4px';
                        header.textContent = `[-] ${key}`;

                        const content = document.createElement('div');
                        content.style.marginTop = '6px';
                        content.style.paddingLeft = '10px';

                        header.onclick = () => {
                            if (content.style.display === 'none') {
                                content.style.display = 'block';
                                header.textContent = `[-] ${key}`;
                            } else {
                                content.style.display = 'none';
                                header.textContent = `[+] ${key}`;
                            }
                        };

                        sectionWrapper.appendChild(header);
                        sectionWrapper.appendChild(content);
                        container.appendChild(sectionWrapper);

                        buildRecursiveForm(content, value, currentPath, targetRoot, depth + 1);
                    } else {
                        // Primitive value input
                        const type = typeof value === 'number' ? 'number' : 'text';
                        createFormField(container, key, value, (newVal) => {
                            // Update nested object value
                            let target = targetRoot;
                            for (let i = 0; i < currentPath.length - 1; i++) {
                                if (!target[currentPath[i]]) target[currentPath[i]] = {};
                                target = target[currentPath[i]];
                            }
                            if (type === 'number') {
                                const parsed = parseFloat(newVal);
                                target[key] = isNaN(parsed) ? 0 : parsed;
                            } else {
                                target[key] = newVal;
                            }
                        }, type, false, key, useBlockLayout);
                    }
                }
            }
        }

        function createFormField(container, labelText, value, onChange, type = 'text', readOnly = false, keyId = null, useBlockLayout = true) {
            const group = document.createElement('div');
            group.className = useBlockLayout ? 'form-group' : 'form-group field-inline';

            const label = document.createElement('label');
            label.textContent = labelText;
            if (useBlockLayout) {
                label.style.marginBottom = '2px';
            }
            group.appendChild(label);

            const input = document.createElement('input');
            input.type = type;
            input.className = 'form-control inset-bevel';
            input.value = value;
            input.readOnly = readOnly;
            if (keyId) {
                input.id = 'field-' + keyId;
            }
            if (readOnly) {
                input.style.backgroundColor = 'var(--win-gray)';
                input.style.color = 'var(--win-dark-shadow)';
            }

            if (onChange && !readOnly) {
                input.addEventListener('input', () => {
                    onChange(input.value);
                    setDirty(true);
                });
            }

            group.appendChild(input);
            container.appendChild(group);
        }

        function buildMetaEditor(container, owner, appliesToName) {
            if (!owner) return;
            
            const group = document.createElement('div');
            group.className = 'form-group';
            group.style.marginTop = '16px';
            group.style.borderTop = '1px solid var(--win-shadow)';
            group.style.paddingTop = '8px';
            
            const title = document.createElement('label');
            title.style.fontWeight = 'bold';
            title.textContent = 'Meta Parameters';
            group.appendChild(title);
            
            const box = makeListBox();
            
            const render = () => {
                box.innerHTML = '';
                const meta = owner.meta || {};
                
                const registeredKeys = ((dbPayload.engine && dbPayload.engine.metaKeys) || []).filter(
                    mk => mk.appliesTo && mk.appliesTo.includes(appliesToName)
                );
                
                const presentKeys = Object.keys(meta);
                if (presentKeys.length === 0) {
                    const empty = document.createElement('div');
                    empty.style.color = 'var(--win-dark-shadow)';
                    empty.style.fontSize = '10px';
                    empty.style.fontStyle = 'italic';
                    empty.style.marginBottom = '6px';
                    empty.textContent = 'No meta parameters set.';
                    box.appendChild(empty);
                } else {
                    presentKeys.forEach(k => {
                        const reg = registeredKeys.find(r => r.key === k);
                        const regType = reg ? reg.type : (typeof meta[k] === 'boolean' ? 'flag' : (typeof meta[k] === 'number' ? 'number' : 'string'));
                        
                        const row = document.createElement('div');
                        row.style.cssText = 'display: flex; gap: 8px; align-items: center; margin-bottom: 4px;';
                        
                        const keySpan = document.createElement('span');
                        keySpan.style.cssText = 'font-weight: bold; font-size: 11px; width: 100px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;';
                        keySpan.textContent = k;
                        if (reg && reg.description) {
                            keySpan.title = reg.description;
                        }
                        row.appendChild(keySpan);
                        
                        let input;
                        if (regType === 'flag') {
                            input = document.createElement('input');
                            input.type = 'checkbox';
                            input.checked = !!meta[k];
                            input.onchange = () => {
                                owner.meta[k] = input.checked;
                                setDirty(true);
                            };
                        } else if (regType === 'number') {
                            input = document.createElement('input');
                            input.type = 'number';
                            input.className = 'win98-input';
                            input.style.flex = '1';
                            input.style.boxSizing = 'border-box';
                            input.style.height = '19px';
                            input.value = meta[k];
                            input.oninput = () => {
                                owner.meta[k] = parseFloat(input.value) || 0;
                                setDirty(true);
                            };
                        } else {
                            input = document.createElement('input');
                            input.type = 'text';
                            input.className = 'win98-input';
                            input.style.flex = '1';
                            input.style.boxSizing = 'border-box';
                            input.style.height = '19px';
                            input.value = meta[k];
                            input.oninput = () => {
                                owner.meta[k] = input.value;
                                setDirty(true);
                            };
                        }
                        row.appendChild(input);
                        
                        row.appendChild(makeRowDeleteBtn(() => {
                            delete owner.meta[k];
                            if (Object.keys(owner.meta).length === 0) {
                                delete owner.meta;
                            }
                            setDirty(true);
                            render();
                        }));
                        
                        box.appendChild(row);
                    });
                }
                
                const missingKeys = registeredKeys.filter(mk => !presentKeys.includes(mk.key));
                if (missingKeys.length > 0) {
                    const addContainer = document.createElement('div');
                    addContainer.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-top: 6px;';
                    
                    const select = document.createElement('select');
                    select.className = 'win98-select';
                    select.style.flex = '1';
                    select.style.height = '19px';
                    
                    const helpSpan = document.createElement('span');
                    helpSpan.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); max-width: 150px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;';
                    
                    const updateHelp = () => {
                        const selectedKey = select.value;
                        const selectedReg = missingKeys.find(mk => mk.key === selectedKey);
                        helpSpan.textContent = selectedReg ? selectedReg.description : '';
                        helpSpan.title = selectedReg ? selectedReg.description : '';
                    };
                    
                    missingKeys.forEach(mk => {
                        const opt = document.createElement('option');
                        opt.value = mk.key;
                        opt.textContent = `${mk.key} (${mk.type})`;
                        select.appendChild(opt);
                    });
                    
                    select.onchange = updateHelp;
                    updateHelp();
                    
                    const addBtn = document.createElement('button');
                    addBtn.className = 'win98-btn';
                    addBtn.textContent = '+ Add Key';
                    addBtn.onclick = (e) => {
                        e.preventDefault();
                        const selectedKey = select.value;
                        const reg = missingKeys.find(mk => mk.key === selectedKey);
                        const defVal = reg.type === 'flag' ? false : (reg.type === 'number' ? 0 : '');
                        owner.meta = owner.meta || {};
                        owner.meta[selectedKey] = defVal;
                        setDirty(true);
                        render();
                    };
                    
                    addContainer.appendChild(select);
                    addContainer.appendChild(helpSpan);
                    addContainer.appendChild(addBtn);
                    box.appendChild(addContainer);
                }
            };
            
            render();
            group.appendChild(box);
            container.appendChild(group);
        }