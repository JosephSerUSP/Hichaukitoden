
        // --- ASSET PICKER IMPLEMENTATION ---
        let activeAssetCallback = null;

        window.createSnapshotModal = function({ getSnapshotSource, onRestore, confirmMessage, getIsDirty }) {
            let snapshot = null;
            let originalData = null;

            function capture() {
                originalData = getSnapshotSource();
                snapshot = JSON.stringify(originalData);
            }

            function close(force) {
                if (!force && snapshot !== null) {
                    const dirty = getIsDirty ? getIsDirty() : JSON.stringify(getSnapshotSource()) !== snapshot;
                    if (dirty) {
                        if (!window.confirmDiscard(confirmMessage)) return false;

                        const snap = JSON.parse(snapshot);
                        onRestore(snap, originalData);
                    }
                }

                snapshot = null;
                originalData = null;
                return true;
            }

            return { capture, close };
        };

        window.createSpriteField = function(container, labelText, value, onChange, useBlockLayout = false, defaultDir = 'sprites', isBareKey = false, animate = false) {
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
                thumbWrap.classList.remove('sprite-sheet-anim');
                thumbWrap.style.backgroundImage = '';
                // The base thumbWrap style sets "background: #000" as a shorthand,
                // which (being inline) always outranks the .sprite-sheet-anim
                // class's background-size/repeat — so those must be set inline too.
                thumbWrap.style.backgroundRepeat = '';
                thumbWrap.style.backgroundSize = '';
                if (path) {
                    path = path.replace(/\\/g, '/');
                    const resolved = (isBareKey && !path.includes('/'))
                        ? '/assets/' + defaultDir + '/' + path + '.png'
                        : '/' + path;

                    if (animate) {
                        // Sprite sheets follow the engine convention (see
                        // presentation/small_battlers.lua): a horizontal strip of
                        // square cells, cell size = image height, frame count =
                        // width / height. [speed=N]/[fps=N] tokens embedded in the
                        // key (e.g. "pixie[fps=15]") override the default 4fps,
                        // same as small_battlers.frame()'s `ss.fps or (ss.speed and
                        // 4*ss.speed or 4)`.
                        img.style.display = 'none';
                        noneTxt.style.display = 'none';
                        const tokens = {};
                        path.replace(/\[([^=\]]+)=([^\]]+)\]/g, (m, k, v) => { tokens[k] = parseFloat(v); return ''; });
                        const fps = tokens.fps || (tokens.speed ? 4 * tokens.speed : 4);
                        const probe = new Image();
                        probe.onload = () => {
                            const boxPx = thumbWrap.clientWidth || 48;
                            const cell = Math.min(probe.naturalWidth, probe.naturalHeight);
                            const frames = Math.max(1, Math.floor(probe.naturalWidth / cell));
                            thumbWrap.style.backgroundImage = `url('${resolved}')`;
                            thumbWrap.style.backgroundRepeat = 'no-repeat';
                            // Explicit px sizing (rather than "auto 100%") keeps each
                            // frame exactly boxPx wide, so the steps() animation below
                            // lands precisely on cell boundaries instead of drifting.
                            thumbWrap.style.backgroundSize = `${frames * boxPx}px ${boxPx}px`;
                            thumbWrap.style.setProperty('--sprite-frames', frames);
                            thumbWrap.style.setProperty('--sprite-cell-px', boxPx + 'px');
                            thumbWrap.style.setProperty('--sprite-dur', (frames / fps) + 's');
                            thumbWrap.classList.add('sprite-sheet-anim');
                        };
                        probe.onerror = () => { noneTxt.style.display = 'block'; };
                        probe.src = resolved;
                    } else {
                        img.src = resolved;
                        img.style.display = 'block';
                        noneTxt.style.display = 'none';
                    }
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

            fetch(`${API_URL}/api/assets?dir=${encodeURIComponent(defaultDir)}`)
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
            fetch(`${API_URL}/api/assets?dir=${encodeURIComponent(dir)}`)
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

        function createMapPicker(current, onChange, flex) {
            const mapOpts = dbPayload.maps ? dbPayload.maps.map((m, i) => ({ value: String(i + 1), label: m.title || ('Map ' + (i + 1)) })) : [];
            return makeSelect(mapOpts, current, onChange, flex);
        }

        // Compact <fieldset class="groupbox"><legend>...</legend> wrapper for
        // dense, RM2003-style form sections. Returns the fieldset so callers
        // can keep appending rows into it.
        function makeGroupbox(parent, title, extraStyle) {
            const fs = document.createElement('fieldset');
            fs.className = 'groupbox';
            if (extraStyle) fs.style.cssText += extraStyle;
            const legend = document.createElement('legend');
            legend.textContent = title;
            fs.appendChild(legend);
            parent.appendChild(fs);
            return fs;
        }

        // Small sparkline showing how a growth-scaled stat (maxHp, atk, def,
        // mat, mdf, mpd) rises from level 1 to the actor's max level, using
        // the same formula as engine/traits.lua traits.getBaseParam:
        //   value(level) = base * (1 + rate * growthMultiplier * (level-1)^exponent)
        function buildStatCurve(container, label, base, rate, growthMultiplier, exponent, maxLevel) {
            const box = document.createElement('div');
            box.className = 'stat-curve';

            const head = document.createElement('div');
            head.className = 'stat-curve-head';
            const nameSpan = document.createElement('span');
            nameSpan.textContent = label;
            const valSpan = document.createElement('span');
            valSpan.className = 'stat-curve-val';
            head.appendChild(nameSpan);
            head.appendChild(valSpan);
            box.appendChild(head);

            const lvls = Math.max(1, maxLevel || 99);
            const points = [];
            let maxVal = 0;
            for (let lvl = 1; lvl <= lvls; lvl++) {
                const factor = 1 + rate * growthMultiplier * Math.pow(Math.max(0, lvl - 1), exponent);
                const val = base * factor;
                points.push(val);
                if (val > maxVal) maxVal = val;
            }
            valSpan.textContent = Math.round(points[points.length - 1]);
            if (maxVal <= 0) maxVal = 1;

            const w = 100, h = 30;
            const toXY = (i, v) => [
                (i / (lvls - 1 || 1)) * w,
                h - (v / maxVal) * (h - 3) - 1
            ];
            let pathD = '';
            points.forEach((v, i) => {
                const [x, y] = toXY(i, v);
                pathD += (i === 0 ? 'M' : 'L') + x.toFixed(1) + ',' + y.toFixed(1) + ' ';
            });
            const [lastX] = toXY(points.length - 1, points[points.length - 1]);
            const fillD = pathD + `L${lastX.toFixed(1)},${h} L0,${h} Z`;

            const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            svg.setAttribute('viewBox', `0 0 ${w} ${h}`);
            svg.setAttribute('preserveAspectRatio', 'none');
            const gridG = document.createElementNS('http://www.w3.org/2000/svg', 'g');
            gridG.setAttribute('class', 'curve-grid');
            [0.25, 0.5, 0.75].forEach(frac => {
                const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
                line.setAttribute('x1', '0'); line.setAttribute('x2', String(w));
                line.setAttribute('y1', String(h * frac)); line.setAttribute('y2', String(h * frac));
                gridG.appendChild(line);
            });
            svg.appendChild(gridG);
            const fillPath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            fillPath.setAttribute('class', 'curve-fill');
            fillPath.setAttribute('d', fillD);
            svg.appendChild(fillPath);
            const linePath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            linePath.setAttribute('class', 'curve-path');
            linePath.setAttribute('d', pathD.trim());
            svg.appendChild(linePath);

            box.appendChild(svg);
            container.appendChild(box);
            return box;
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
            box.className = 'win98-listbox';
            box.style.cssText = 'border: 1px solid var(--win-shadow); background: #fff; padding: 4px; display: flex; flex-direction: column; gap: 2px;';
            return box;
        }

        // Optional sticky column-header row for a list box (e.g. "Type | Content"),
        // matching how RPG Maker MZ labels its trait/effect list columns.
        function makeListHeader(box, columns) {
            const header = document.createElement('div');
            header.className = 'listbox-header';
            columns.forEach(col => {
                const span = document.createElement('span');
                span.textContent = col.label;
                span.style.flex = col.flex || '1';
                if (col.width) { span.style.flex = '0 0 ' + col.width; }
                header.appendChild(span);
            });
            box.appendChild(header);
        }

        // Generic MZ-style row-list editor: fixed-height scrollable box,
        // compact single-line summary rows, click/shift-click range select,
        // Delete/Ctrl+C/X/V act on the whole selection, double-click or
        // Enter/Space edits a row in place. Every list in the Actors form
        // (and elsewhere) is built from this one engine so the interaction
        // model — and the "only one row edits at a time" guarantee — is
        // shared rather than reimplemented per list.
        //
        // The "only one edit at a time" and "edit rows match summary-row
        // height" bugs from the first Traits-only version both came from
        // editing being done as an ad-hoc in-place DOM mutation with no
        // shared state. Here editingIdx lives in the closure and render()
        // is the ONLY thing that ever produces a row: at most one row can
        // ever be in edit mode because render() only builds edit UI for
        // `idx === editingIdx`, and both row kinds share the same CSS class
        // sizing (.list-row / .list-row-edit, both fixed-height).
        //
        // opts:
        //   label       - form-group label above the box (optional)
        //   columns     - [{label, flex?}] sticky header (optional)
        //   summary(item, idx)     -> [text, text, ...] matching columns
        //   editor(row, item, idx, commit) -> populate row with edit
        //                             controls; call commit() to exit edit
        //                             mode (structural changes and Done/
        //                             Enter should commit; free-typing in a
        //                             text/number field should not, so the
        //                             row doesn't collapse mid-keystroke)
        //   newItem()   -> object pushed by "+ Add"; omit to hide Add
        //   addLabel
        function buildRowListEditor(container, array, opts) {
            const group = document.createElement('div');
            group.className = 'form-group';
            if (opts.label) {
                const lbl = document.createElement('label');
                lbl.textContent = opts.label;
                group.appendChild(lbl);
            }
            const box = makeListBox();

            let sel = null; // { anchor, focus }
            let clipboard = null;
            let editingIdx = null;

            const selRange = () => sel ? { lo: Math.min(sel.anchor, sel.focus), hi: Math.max(sel.anchor, sel.focus) } : null;
            const selectedIndices = () => {
                const r = selRange();
                if (!r) return [];
                const out = [];
                for (let i = r.lo; i <= r.hi; i++) out.push(i);
                return out;
            };
            const applySelectionStyle = () => {
                (box._rows || []).forEach((row, i) => {
                    const r = selRange();
                    row.classList.toggle('selected', !!r && i >= r.lo && i <= r.hi && editingIdx === null);
                });
            };
            const doDeleteSelected = () => {
                const idxs = selectedIndices();
                if (!idxs.length) return;
                idxs.sort((a, b) => b - a).forEach(i => array.splice(i, 1));
                sel = null; editingIdx = null; setDirty(true); render();
            };
            const doCopy = () => {
                const idxs = selectedIndices();
                if (!idxs.length) return;
                clipboard = idxs.map(i => JSON.parse(JSON.stringify(array[i])));
            };
            const doCut = () => { doCopy(); doDeleteSelected(); };
            const doPaste = () => {
                if (!clipboard || !clipboard.length) return;
                const at = sel ? selRange().hi + 1 : array.length;
                array.splice(at, 0, ...JSON.parse(JSON.stringify(clipboard)));
                setDirty(true); render();
            };
            const commit = () => { editingIdx = null; render(); };
            const enterEditMode = (idx) => { editingIdx = idx; render(); };

            const render = () => {
                box.innerHTML = '';
                if (opts.columns) makeListHeader(box, opts.columns);
                box._rows = array.map((item, idx) => {
                    const row = document.createElement('div');
                    row.tabIndex = -1;

                    if (idx === editingIdx) {
                        row.className = 'list-row-edit';
                        const reopen = () => { row.innerHTML = ''; opts.editor(row, item, idx, commit, reopen); };
                        opts.editor(row, item, idx, commit, reopen);
                    } else {
                        row.className = 'list-row' + (idx % 2 === 1 ? ' stripe-alt' : '');
                        opts.summary(item, idx).forEach(text => {
                            const span = document.createElement('span');
                            span.textContent = text;
                            span.style.flex = '1';
                            row.appendChild(span);
                        });
                        row.addEventListener('mousedown', (e) => {
                            // .focus() without preventScroll can scrollIntoView the
                            // row — on a tall form that shifts everything under the
                            // cursor, so a real double-click's second half can land
                            // on a DIFFERENT row that just scrolled into place. That
                            // was the actual cause of "multiple rows editing at
                            // once": not missing single-edit enforcement (each list
                            // only ever has one editingIdx), but clicks silently
                            // hitting the wrong list entirely.
                            const wasEditing = editingIdx !== null;
                            editingIdx = null;
                            if (e.shiftKey) { e.preventDefault(); sel = { anchor: sel ? sel.anchor : idx, focus: idx }; }
                            else { sel = { anchor: idx, focus: idx }; }
                            if (wasEditing) render(); else applySelectionStyle();
                            const target = box._rows[idx];
                            if (target) target.focus({ preventScroll: true });
                        });
                        row.addEventListener('dblclick', () => enterEditMode(idx));
                        row.addEventListener('keydown', (e) => {
                            const rows = box._rows;
                            if (e.key === 'Delete') { e.preventDefault(); doDeleteSelected(); }
                            else if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); enterEditMode(idx); }
                            else if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
                                e.preventDefault();
                                const dir = e.key === 'ArrowUp' ? -1 : 1;
                                const anchor = e.shiftKey ? (sel ? sel.anchor : idx) : null;
                                const from = sel ? sel.focus : idx;
                                const nf = Math.max(0, Math.min(rows.length - 1, from + dir));
                                sel = e.shiftKey ? { anchor, focus: nf } : { anchor: nf, focus: nf };
                                applySelectionStyle();
                                if (rows[nf]) rows[nf].focus({ preventScroll: true });
                            } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'c') { e.preventDefault(); doCopy(); }
                            else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'x') { e.preventDefault(); doCut(); }
                            else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'v') { e.preventDefault(); doPaste(); }
                        });
                    }
                    box.appendChild(row);
                    return row;
                });
                applySelectionStyle();
                if (opts.newItem) {
                    box.appendChild(makeAddRowBtn(opts.addLabel || '+ Add', () => {
                        array.push(opts.newItem());
                        editingIdx = array.length - 1;
                        render();
                    }));
                }
            };
            render();
            group.appendChild(box);
            container.appendChild(group);
            return { render, box };
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
            btn.className = 'win98-btn listbox-add-btn';
            btn.style.cssText = 'font-size: 10px; align-self: flex-start; margin-top: 2px;';
            btn.textContent = label;
            btn.onclick = () => { onAdd(); setDirty(true); };
            return btn;
        }

        // Editable list of skill/item effect rows ({type, formula|value|status...})
        function effectTypeLabel(type) {
            const opt = effectTypeOptions().find(o => (o.value !== undefined ? o.value : o) === type);
            return (opt && opt.label) || type;
        }
        function effectContentText(eff) {
            if (eff.type === 'hp_damage' || eff.type === 'hp_heal' || eff.type === 'hp_drain') {
                return eff.formula || '(no formula)';
            }
            if (eff.type === 'add_status') {
                const pct = Math.round((eff.chance !== undefined ? eff.chance : 1) * 100);
                return `${eff.status || '?'} @ ${pct}% for ${eff.duration !== undefined ? eff.duration : 3}t`;
            }
            return String(eff.value !== undefined ? eff.value : 0);
        }

        function buildEffectsEditor(container, owner) {
            owner.effects = owner.effects || [];
            buildRowListEditor(container, owner.effects, {
                label: 'Effects',
                columns: [{ label: 'Type', flex: '1' }, { label: 'Content', flex: '1' }],
                summary: (eff) => [effectTypeLabel(eff.type), effectContentText(eff)],
                editor: (row, eff, idx, commit, reopen) => {
                    row.appendChild(makeSelect(effectTypeOptions(), eff.type, v => {
                        eff.type = v;
                        setDirty(true);
                        reopen(); // rebuild this row's fields (formula vs status vs plain value) without collapsing to summary
                    }));

                    if (eff.type === 'hp_damage' || eff.type === 'hp_heal' || eff.type === 'hp_drain') {
                        const f = document.createElement('input');
                        f.className = 'win98-input';
                        f.style.flex = '1';
                        f.placeholder = 'formula, e.g. 6 + 1.2 * a.level';
                        f.value = eff.formula || '';
                        f.oninput = () => { eff.formula = f.value; setDirty(true); };
                        f.onkeydown = (e) => { if (e.key === 'Enter') commit(); };
                        row.appendChild(f);
                    } else if (eff.type === 'add_status') {
                        const stateIds = Object.keys(dbPayload.states || {});
                        row.appendChild(makeSelect(stateIds, eff.status, v => { eff.status = v; setDirty(true); }, '1'));
                        const chance = document.createElement('input');
                        chance.type = 'number'; chance.step = '0.05'; chance.min = '0'; chance.max = '1';
                        chance.className = 'win98-input'; chance.style.width = '48px';
                        chance.title = 'Chance (0-1)';
                        chance.value = eff.chance !== undefined ? eff.chance : 1;
                        chance.oninput = () => { eff.chance = parseFloat(chance.value) || 0; setDirty(true); };
                        row.appendChild(chance);
                        const dur = document.createElement('input');
                        dur.type = 'number'; dur.className = 'win98-input'; dur.style.width = '40px';
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
                        v.onkeydown = (e) => { if (e.key === 'Enter') commit(); };
                        row.appendChild(v);
                    }

                    const doneBtn = document.createElement('button');
                    doneBtn.className = 'win98-btn';
                    doneBtn.textContent = '✓';
                    doneBtn.title = 'Done editing';
                    doneBtn.onclick = () => commit();
                    row.appendChild(doneBtn);
                    row.appendChild(makeRowDeleteBtn(() => { owner.effects.splice(idx, 1); commit(); }));
                },
                newItem: () => ({ type: 'hp_damage', formula: '' }),
                addLabel: '+ Add Effect'
            });
        }

        function traitTypeLabel(code) {
            const opt = traitCodeOptions().find(o => (o.value !== undefined ? o.value : o) === code);
            return (opt && opt.label) || code;
        }

        // RPG Maker MZ shows traits as one summary line per row ("Max HP * 150%")
        // rather than a row of dropdowns — far denser, and it reads at a glance.
        function traitContentText(tr) {
            const dataLabel = tr.dataId || '';
            if (/RATE/.test(tr.code)) return `${dataLabel} × ${Math.round((tr.value || 0) * 100)}%`;
            if (/PLUS/.test(tr.code)) return `${dataLabel}${dataLabel ? ' ' : ''}+ ${tr.value}`;
            return dataLabel ? `${dataLabel}: ${tr.value}` : String(tr.value != null ? tr.value : '');
        }

        // Editable list of trait rows ({code, dataId?, value}), MZ-style,
        // built on the shared buildRowListEditor engine.
        function buildTraitsEditor(container, owner, label) {
            owner.traits = owner.traits || [];
            buildRowListEditor(container, owner.traits, {
                label: label || 'Traits',
                columns: [{ label: 'Type', flex: '1' }, { label: 'Data / Value', flex: '1' }],
                summary: (tr) => [traitTypeLabel(tr.code), traitContentText(tr)],
                editor: (row, tr, idx, commit) => {
                    row.appendChild(makeSelect(traitCodeOptions(), tr.code, v => {
                        tr.code = v;
                        if (!traitUsesDataId(v)) delete tr.dataId;
                        setDirty(true);
                        commit();
                    }, '1'));
                    if (traitUsesDataId(tr.code)) {
                        // ELEMENT_CHANGE's dataId is an element; param traits use stat ids
                        const dataIdOpts = tr.code === 'ELEMENT_CHANGE' ? elementOptions(false) : PARAM_IDS;
                        row.appendChild(makeSelect(dataIdOpts, tr.dataId || dataIdOpts[0], v => { tr.dataId = v; setDirty(true); }));
                    }
                    const v = document.createElement('input');
                    v.type = 'number'; v.step = 'any';
                    v.className = 'win98-input';
                    v.style.width = '64px';
                    v.title = 'Trait value';
                    v.value = tr.value !== undefined ? tr.value : 0;
                    v.oninput = () => { tr.value = parseFloat(v.value) || 0; setDirty(true); };
                    v.onkeydown = (e) => { if (e.key === 'Enter') commit(); };
                    row.appendChild(v);
                    const doneBtn = document.createElement('button');
                    doneBtn.className = 'win98-btn';
                    doneBtn.textContent = '✓';
                    doneBtn.title = 'Done editing';
                    doneBtn.onclick = () => commit();
                    row.appendChild(doneBtn);
                    row.appendChild(makeRowDeleteBtn(() => { owner.traits.splice(idx, 1); commit(); }));
                    v.focus({ preventScroll: true });
                },
                newItem: () => ({ code: 'PARAM_PLUS', dataId: 'atk', value: 1 }),
                addLabel: '+ Add Trait'
            });
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
            // buildRowListEditor mutates its array in place (push/splice), so
            // it needs one stable array reference for the lifetime of this
            // widget — grab-or-create it once and attach it back immediately.
            const arr = ownerArrGetter() || [];
            ownerArrSetter(arr);
            const options = allIds.map(id => ({ value: id, label: nameOf(id) }));

            buildRowListEditor(container, arr, {
                label,
                summary: (id) => [nameOf(id)],
                editor: (row, id, idx, commit) => {
                    row.appendChild(makeSelect(options, id, v => {
                        arr[idx] = v;
                        setDirty(true);
                        commit();
                    }, '1'));
                    row.appendChild(makeRowDeleteBtn(() => { arr.splice(idx, 1); commit(); }));
                },
                newItem: () => (allIds.length > 0 ? allIds[0] : ''),
                addLabel
            });
        }

        // Editable list of drop rows ({itemId, chance}) for actors
        function buildDropsEditor(container, actor) {
            actor.drops = actor.drops || [];
            const itemOptions = dbPayload.items.map(it => ({ value: String(it.id), label: it.name }));
            const itemName = (id) => (itemOptions.find(o => o.value === String(id)) || {}).label || String(id);

            buildRowListEditor(container, actor.drops, {
                label: 'Item Drops (item + chance 0-1)',
                columns: [{ label: 'Item', flex: '1' }, { label: 'Chance', flex: '1' }],
                summary: (drop) => [itemName(drop.itemId), String(drop.chance !== undefined ? drop.chance : 0.1)],
                editor: (row, drop, idx, commit) => {
                    row.appendChild(makeSelect(itemOptions, drop.itemId, v => { drop.itemId = parseInt(v); setDirty(true); }, '1'));
                    const chance = document.createElement('input');
                    chance.type = 'number'; chance.step = '0.05'; chance.min = '0'; chance.max = '1';
                    chance.className = 'win98-input'; chance.style.width = '56px';
                    chance.title = 'Drop chance (0-1)';
                    chance.value = drop.chance !== undefined ? drop.chance : 0.1;
                    chance.oninput = () => { drop.chance = parseFloat(chance.value) || 0; setDirty(true); };
                    chance.onkeydown = (e) => { if (e.key === 'Enter') commit(); };
                    row.appendChild(chance);
                    const doneBtn = document.createElement('button');
                    doneBtn.className = 'win98-btn'; doneBtn.textContent = '✓'; doneBtn.title = 'Done editing';
                    doneBtn.onclick = () => commit();
                    row.appendChild(doneBtn);
                    row.appendChild(makeRowDeleteBtn(() => { actor.drops.splice(idx, 1); commit(); }));
                },
                newItem: () => ({ itemId: dbPayload.items[0] ? dbPayload.items[0].id : 1, chance: 0.1 }),
                addLabel: '+ Add Drop'
            });
        }

        // Editable list of sacrifice reward rows ({itemId, chance, count, minLevel})
        // for actors. Empty list = the actor falls back to
        // system.summoner.defaultSacrificeRewards.
        function buildSacrificeRewardsEditor(container, actor) {
            actor.sacrificeRewards = actor.sacrificeRewards || [];
            const itemOptions = dbPayload.items.map(it => ({ value: String(it.id), label: it.name }));
            const itemName = (id) => (itemOptions.find(o => o.value === String(id)) || {}).label || String(id);

            buildRowListEditor(container, actor.sacrificeRewards, {
                label: 'Sacrifice Rewards (item, chance 0-1, count, min level)',
                columns: [{ label: 'Item', flex: '2' }, { label: 'Chance / Count / MinLv', flex: '2' }],
                summary: (r) => [itemName(r.itemId),
                    `${r.chance !== undefined ? r.chance : 1} × ${r.count !== undefined ? r.count : 1}` + (r.minLevel ? ` (Lv${r.minLevel}+)` : '')],
                editor: (row, reward, idx, commit) => {
                    row.appendChild(makeSelect(itemOptions, reward.itemId, v => { reward.itemId = parseInt(v); setDirty(true); }, '1'));
                    const chance = document.createElement('input');
                    chance.type = 'number'; chance.step = '0.05'; chance.min = '0'; chance.max = '1';
                    chance.className = 'win98-input'; chance.style.width = '48px';
                    chance.title = 'Reward chance (0-1)';
                    chance.value = reward.chance !== undefined ? reward.chance : 1;
                    chance.oninput = () => { reward.chance = parseFloat(chance.value) || 0; setDirty(true); };
                    row.appendChild(chance);
                    const count = document.createElement('input');
                    count.type = 'number'; count.min = '1';
                    count.className = 'win98-input'; count.style.width = '38px';
                    count.title = 'Item count';
                    count.value = reward.count !== undefined ? reward.count : 1;
                    count.oninput = () => { reward.count = parseInt(count.value) || 1; setDirty(true); };
                    row.appendChild(count);
                    const minLevel = document.createElement('input');
                    minLevel.type = 'number'; minLevel.min = '0';
                    minLevel.className = 'win98-input'; minLevel.style.width = '38px';
                    minLevel.title = 'Minimum creature level for this reward (0 = always)';
                    minLevel.value = reward.minLevel !== undefined ? reward.minLevel : 0;
                    minLevel.oninput = () => {
                        const v = parseInt(minLevel.value) || 0;
                        if (v > 0) { reward.minLevel = v; } else { delete reward.minLevel; }
                        setDirty(true);
                    };
                    minLevel.onkeydown = (e) => { if (e.key === 'Enter') commit(); };
                    row.appendChild(minLevel);
                    const doneBtn = document.createElement('button');
                    doneBtn.className = 'win98-btn'; doneBtn.textContent = '✓'; doneBtn.title = 'Done editing';
                    doneBtn.onclick = () => commit();
                    row.appendChild(doneBtn);
                    row.appendChild(makeRowDeleteBtn(() => { actor.sacrificeRewards.splice(idx, 1); commit(); }));
                },
                newItem: () => ({ itemId: dbPayload.items[0] ? dbPayload.items[0].id : 1, chance: 1, count: 1 }),
                addLabel: '+ Add Reward'
            });
        }

        // Editable list of evolution rows ({level, evolvesTo}) for actors
        function buildEvolutionsEditor(container, actor) {
            actor.evolutions = actor.evolutions || [];
            const actorOptions = dbPayload.actors.map(a => ({ value: String(a.id), label: a.name }));
            const actorName = (id) => (actorOptions.find(o => o.value === String(id)) || {}).label || String(id);

            buildRowListEditor(container, actor.evolutions, {
                label: 'Evolutions (at level → becomes)',
                columns: [{ label: 'Level', flex: '1' }, { label: 'Becomes', flex: '1' }],
                summary: (evo) => [String(evo.level !== undefined ? evo.level : 5), actorName(evo.evolvesTo)],
                editor: (row, evo, idx, commit) => {
                    const level = document.createElement('input');
                    level.type = 'number'; level.min = '1';
                    level.className = 'win98-input'; level.style.width = '56px';
                    level.title = 'Evolution level';
                    level.value = evo.level !== undefined ? evo.level : 5;
                    level.oninput = () => { evo.level = parseInt(level.value) || 1; setDirty(true); };
                    level.onkeydown = (e) => { if (e.key === 'Enter') commit(); };
                    row.appendChild(level);
                    row.appendChild(makeSelect(actorOptions, evo.evolvesTo, v => { evo.evolvesTo = parseInt(v); setDirty(true); }, '1'));
                    const doneBtn = document.createElement('button');
                    doneBtn.className = 'win98-btn'; doneBtn.textContent = '✓'; doneBtn.title = 'Done editing';
                    doneBtn.onclick = () => commit();
                    row.appendChild(doneBtn);
                    row.appendChild(makeRowDeleteBtn(() => { actor.evolutions.splice(idx, 1); commit(); }));
                },
                newItem: () => ({ level: 5, evolvesTo: dbPayload.actors[0] ? dbPayload.actors[0].id : 1 }),
                addLabel: '+ Add Evolution'
            });
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
            'growth.growthExponent':       { label: 'Growth Curve Exponent', step: 0.1, min: 1,
                                             help: 'Superlinear growth curve. 1.2 is the default.' },
            'growth.baseParams.maxHp':     { label: 'Default Base Max HP', min: 0 },
            'growth.baseParams.atk':       { label: 'Default Base ATK', min: 0 },
            'growth.baseParams.def':       { label: 'Default Base DEF', min: 0 },
            'growth.baseParams.mat':       { label: 'Default Base MAT', min: 0 },
            'growth.baseParams.mdf':       { label: 'Default Base MDF', min: 0 },
            'growth.baseParams.mpd':       { label: 'Default Base MPD', min: 0 },
            'growth.baseParams.mxa':       { label: 'Default Max Actions (mxa)', min: 0 },
            'growth.baseParams.mxp':       { label: 'Default Max Passives (mxp)', min: 0 },
            'growth.growthRates.maxHp':    { label: 'Max HP Growth Rate', step: 0.01, min: 0 },
            'growth.growthRates.atk':      { label: 'ATK Growth Rate', step: 0.01, min: 0 },
            'growth.growthRates.def':      { label: 'DEF Growth Rate', step: 0.01, min: 0 },
            'growth.growthRates.mat':      { label: 'MAT Growth Rate', step: 0.01, min: 0 },
            'growth.growthRates.mdf':      { label: 'MDF Growth Rate', step: 0.01, min: 0 },
            'growth.growthRates.mpd':      { label: 'MPD Growth Rate', step: 0.01, min: 0 },
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
            'summoner.sacrificeExpRate':   { label: 'Sacrifice EXP Rate (Multiplier)', step: 0.1,
                                             help: 'Also the rate at which permadeath converts fallen spirits to banked EXP.' },
            'spawn.mapId':                 { label: 'Spawn Map ID',
                                             help: 'Which map New Game loads into. Set via right-click in the Map painter, or type a map id here.' },
            'spawn.x':                     { label: 'Spawn X' },
            'spawn.y':                     { label: 'Spawn Y' },
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
            'battleLayout.consoleTileY':   { label: 'Console Y (tiles)' },
            'battleLayout.headerTileOffset': { label: 'Console Header Offset (tiles)' },
            'battleLayout.slotPopupOffsetX': { label: 'Party Popup Offset X (px)' },
            'battleLayout.slotPopupOffsetY': { label: 'Party Popup Offset Y (px)' },
            'battleLayout.fallbackX':      { label: 'Popup Fallback X (px)' },
            'battleLayout.fallbackY':      { label: 'Popup Fallback Y (px)' },
            'battleLayout.enemyY':         { label: 'Enemy Y (px)' },
            'battleLayout.enemyNameY':     { label: 'Enemy Name Y (px)' },
            'battleLayout.enemyHpBarY':    { label: 'Enemy HP Bar Y (px)' },
            'battleLayout.enemyHpBarWidth': { label: 'Enemy HP Bar Width (px)' },
            'battleLayout.enemyHpBarHeight': { label: 'Enemy HP Bar Height (px)' },
            'battleLayout.enemySpriteSize': { label: 'Enemy Sprite Size (px)' },
            'battleLayout.enemyFallbackSize': { label: 'Enemy Fallback Sprite Size (px)' },
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
                        }
                        row.appendChild(makeRowDeleteBtn(() => { arr.splice(idx, 1); render(); }));
                        box.appendChild(row);
                    });
                    box.appendChild(makeAddRowBtn('+ Add Option', () => {
                        arr.push({ label: 'New Option', action: 'dialogue' });
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
            fetch(`${API_URL}/api/assets?dir=portraits`)
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
            owner.elements = owner.elements || [];
            buildRowListEditor(container, owner.elements, {
                label: 'Elements (slots; duplicates stack)',
                summary: (el) => [el],
                editor: (row, el, idx, commit) => {
                    row.appendChild(makeSelect(elementOptions(false), el, v => { owner.elements[idx] = v; setDirty(true); commit(); }, '1'));
                    row.appendChild(makeRowDeleteBtn(() => { owner.elements.splice(idx, 1); commit(); }));
                },
                newItem: () => elementOptions(false)[0],
                addLabel: '+ Add Element'
            });
        }

        function loadFormForItem(item) {
            const formPanel = document.getElementById('db-form-panel');
            // The animation editor owns timers/listeners; tear them down
            // whenever the form is rebuilt (including leaving the tab).
            if (formPanel._animCleanup) {
                formPanel._animCleanup();
                delete formPanel._animCleanup;
            }
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
                item.baseParams = item.baseParams || {};
                const base = (key, fallback) => item.baseParams[key] != null ? item.baseParams[key] : (item[key] != null ? item[key] : fallback);

                // Top row: Identity | Level & Rewards | Capacity, three tight groupboxes
                const topRow = document.createElement('div');
                topRow.className = 'groupbox-grid';
                topRow.style.gridTemplateColumns = '1.3fr 1fr 1fr';
                formPanel.appendChild(topRow);

                const idBox = makeGroupbox(topRow, 'Identity');
                createFormField(idBox, 'Name', item.name, val => { item.name = val; initDatabaseEditor(true); }, 'text', false, null, false);
                const roleField = document.createElement('div');
                roleField.className = 'form-group field-inline';
                const roleLbl = document.createElement('label');
                roleLbl.textContent = 'Role';
                roleField.appendChild(roleLbl);
                roleField.appendChild(makeSelect(Object.keys(dbPayload.roles || { Spirit: 1 }), item.role || 'Spirit', v => { item.role = v; }, '1'));
                idBox.appendChild(roleField);
                createFormField(idBox, 'Biography', item.flavor || '', val => { item.flavor = val; }, 'text', false, null, false);

                const lvlBox = makeGroupbox(topRow, 'Level & Rewards');
                createFormField(lvlBox, 'Base Level', item.level || 1, val => { item.level = parseInt(val) || 1; renderActorStatCurves(); }, 'number', false, null, false);
                createFormField(lvlBox, 'Growth Multiplier', item.growthMultiplier == null ? 1 : item.growthMultiplier, val => { item.growthMultiplier = parseFloat(val) || 1; renderActorStatCurves(); }, 'number', false, null, false);
                createFormField(lvlBox, 'Exp Growth', item.expGrowth || 0, val => { item.expGrowth = parseInt(val) || 0; }, 'number', false, null, false);
                createFormField(lvlBox, 'Gold Reward', item.gold || 0, val => { item.gold = parseInt(val) || 0; }, 'number', false, null, false);

                const capBox = makeGroupbox(topRow, 'Capacity');
                createFormField(capBox, 'Max Actions (mxa)', base('mxa', 4), val => { item.baseParams.mxa = parseFloat(val) || 0; }, 'number', false, null, false);
                createFormField(capBox, 'Max Passives (mxp)', base('mxp', 2), val => { item.baseParams.mxp = parseFloat(val) || 0; }, 'number', false, null, false);
                createFormField(capBox, 'MP Drain', base('mpd', 2), val => { item.baseParams.mpd = parseFloat(val) || 2; renderActorStatCurves(); }, 'number', false, null, false);

                // Base Stats groupbox: editable base value + growth-curve sparkline per stat
                const statsBox = makeGroupbox(formPanel, 'Base Stats & Growth Curves (Lv 1-' + (item.maxLevel || 99) + ')');
                const statsGrid = document.createElement('div');
                statsGrid.className = 'groupbox-grid';
                statsGrid.style.gridTemplateColumns = 'repeat(6, 1fr)';
                statsBox.appendChild(statsGrid);

                const growthCfg = (dbPayload.system && dbPayload.system.growth) || {};
                const exponent = growthCfg.growthExponent != null ? growthCfg.growthExponent : 1.2;
                const rates = growthCfg.growthRates || {};
                const STAT_DEFS = [
                    ['maxHp', 'Max HP'], ['atk', 'ATK'], ['def', 'DEF'],
                    ['mat', 'MAT'], ['mdf', 'MDF'], ['mpd', 'MP Drain']
                ];
                function renderActorStatCurves() {
                    statsGrid.innerHTML = '';
                    STAT_DEFS.forEach(([key, label]) => {
                        const cell = document.createElement('div');
                        const input = document.createElement('input');
                        input.type = 'number';
                        input.className = 'form-control win98-input';
                        input.style.cssText = 'width: 100%; margin-bottom: 3px;';
                        input.value = base(key, 10);
                        input.oninput = () => {
                            item.baseParams[key] = parseFloat(input.value) || 0;
                            setDirty(true);
                            renderActorStatCurves();
                        };
                        cell.appendChild(input);
                        statsGrid.appendChild(cell);
                        const rate = rates[key] != null ? rates[key] : (key === 'maxHp' ? 0.15 : 0);
                        buildStatCurve(cell, label, base(key, 10), rate,
                            item.growthMultiplier == null ? 1 : item.growthMultiplier, exponent, item.maxLevel || 99);
                    });
                }
                renderActorStatCurves();

                ensurePortraitKeys();
                // Sprite fields in a horizontal row
                const spriteBox = makeGroupbox(formPanel, 'Sprites');
                const spriteRow = document.createElement('div');
                spriteRow.className = 'form-row';
                spriteBox.appendChild(spriteRow);
                window.createSpriteField(spriteRow, 'Sprite Key', item.spriteKey || '', (path) => {
                    item.spriteKey = path;
                    setDirty(true);
                }, false, 'portraits', true);
                window.createSpriteField(spriteRow, 'Small Battler', item.smallBattler || '', (path) => {
                    item.smallBattler = path;
                    setDirty(true);
                }, false, 'smallBattlers', true, true);

                const flagsBox = makeGroupbox(formPanel, 'Flags');
                createCheckboxField(flagsBox, 'In starting-party pool (initialParty)', item.initialParty, v => { item.initialParty = v; });
                createCheckboxField(flagsBox, 'Unlocked by Default', item.unlocked, v => { item.unlocked = v; });
                createCheckboxField(flagsBox, 'Recruitable in dungeons (isRecruitable)', item.isRecruitable, v => { item.isRecruitable = v; });
                const flagsFieldsRow = document.createElement('div');
                flagsFieldsRow.className = 'form-row';
                flagsBox.appendChild(flagsFieldsRow);
                createFormField(flagsFieldsRow, 'Tier', item.tier, v => { item.tier = parseFloat(v); }, 'number');
                createFormField(flagsFieldsRow, 'Discipline (Item Creation)', item.discipline, v => { item.discipline = v; }, 'text');

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

                // Sacrifice rewards row (full width below the three columns)
                const sacrificeRow = document.createElement('div');
                formPanel.appendChild(sacrificeRow);
                buildSacrificeRewardsEditor(sacrificeRow, item);

                // Custom names row
                const namesRow = document.createElement('div');
                formPanel.appendChild(namesRow);
                item.names = item.names || [];
                buildStringListEditor(namesRow, 'Possible Custom Names (Allies)', item.names, 'e.g. Sparky');

            } else if (ENTITY_FORM_SCHEMAS[activeDbTab]) {
                if (!buildEntityForm(formPanel, item, ENTITY_FORM_SCHEMAS[activeDbTab])) return;

            } else if (activeDbTab === 'animations') {
                renderAnimationEditor(formPanel, item);

            } else if (activeDbTab === 'quests') {
                buildQuestForm(formPanel, item.id);

            } else if (activeDbTab === 'actionSequences') {
                buildActionSequenceForm(formPanel, item.id);

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
                    case 'actionSequences': return dbPayload.actionSequences[item.id];
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

                        const select = makeSelect(['N', 'E', 'S', 'W'], value, (v) => {
                            let target = targetRoot;
                            for (let i = 0; i < currentPath.length - 1; i++) {
                                if (!target[currentPath[i]]) target[currentPath[i]] = {};
                                target = target[currentPath[i]];
                            }
                            target[key] = v;
                        });

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
