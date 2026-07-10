
        // E5: Visual scene editor — canvas preview + right-click editing.
        //
        // The canvas renders the MATERIALIZED window state produced by the
        // engine's headless preview (`lovec . preview-scene <id>` via
        // GET /preview-scene?id=N): real list rows, interpolated text and
        // cursor positions, resolved by the same Lua code paths the game
        // uses. Geometry (rects/style/title) is overlaid live from
        // dbPayload.engine.windowLayout so canvas edits show immediately;
        // CONTENT reflects the last save (the engine reads saved files) —
        // the panel says so and offers Save & Refresh.
        //
        // This is a companion lens onto the same scenes.json/engine.json
        // data as the command-list editor — not a second source of truth.

        const SCENE_PREVIEW_SCALE = 2;
        let scenePreviewCache = {}; // sceneId -> payload

        // Editor-side window presets (S3): the shapes D13 deleted from
        // engine/scenes/crafting.lua, generalized. NOT engine data.
        const SCENE_WINDOW_PRESETS = [
            { label: 'List window', style: 'list', width: 12, height: 16 },
            { label: 'Panel window', style: 'panel', width: 16, height: 8 },
            { label: 'Confirm window', style: 'confirm', width: 24, height: 10 }
        ];

        // Deep-scan a scene's hooks for commands referencing a windowId
        // (OPEN_WINDOW/SET_* — anything carrying windowId), nested blocks
        // included. Returns [{ hook, array, idx, cmd }].
        function scanForWindowRefs(scene, windowId) {
            const hits = [];
            const visit = (arr, hook) => {
                (arr || []).forEach((c, i) => {
                    if (!c || typeof c !== 'object') return;
                    if (c.windowId === windowId) hits.push({ hook, array: arr, idx: i, cmd: c.cmd });
                    ['then', 'else', 'commands', 'elseCommands', 'do'].forEach(k => {
                        if (Array.isArray(c[k])) visit(c[k], hook);
                    });
                    if (Array.isArray(c.options)) c.options.forEach(o => visit(o && o.commands, hook));
                });
            };
            Object.keys(scene.hooks || {}).forEach(h => visit(scene.hooks[h], h));
            return hits;
        }

        function renderScenePreviewPanel(container, scene, refreshEditor) {
            const wl = () => {
                dbPayload.engine.windowLayout = dbPayload.engine.windowLayout || {};
                return dbPayload.engine.windowLayout;
            };

            const box = document.createElement('fieldset');
            box.style.cssText = 'padding: 6px; margin-bottom: 6px;';
            const legend = document.createElement('legend');
            legend.textContent = 'Visual Preview';
            box.appendChild(legend);

            const barRow = document.createElement('div');
            barRow.style.cssText = 'display: flex; gap: 6px; align-items: center; margin-bottom: 4px; flex-wrap: wrap;';
            const refreshBtn = document.createElement('button');
            refreshBtn.className = 'win98-btn';
            refreshBtn.style.fontSize = '10px';
            refreshBtn.textContent = 'Save & Refresh Preview';
            const caveat = document.createElement('span');
            caveat.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow);';
            caveat.textContent = 'Content reflects the last save; geometry edits show live. Right-click windows or empty canvas to edit.';
            barRow.appendChild(refreshBtn);
            barRow.appendChild(caveat);
            box.appendChild(barRow);

            const gw = 256, gh = 240, S = SCENE_PREVIEW_SCALE;
            const canvas = document.createElement('canvas');
            canvas.width = gw * S;
            canvas.height = gh * S;
            canvas.style.cssText = 'border: 1px solid var(--win-shadow); background: #000; display: block;';
            box.appendChild(canvas);

            const closedRow = document.createElement('div');
            closedRow.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin-top: 3px;';
            box.appendChild(closedRow);
            container.appendChild(box);

            const ctx2d = canvas.getContext('2d');
            const data = () => scenePreviewCache[scene.id];

            // Live geometry: unsaved windowLayout edits override the payload
            const geomOf = (w) => {
                const l = wl()[w.id];
                if (!l) return { x: w.x, y: w.y, width: w.width, height: w.height, style: w.style, title: w.title, missing: !w.hasLayout };
                return { x: l.x || 0, y: l.y || 0, width: l.width || 8, height: l.height || 4, style: l.style || 'panel', title: l.title != null ? l.title : w.title, contentY: l.contentY };
            };

            const draw = () => {
                const d = data();
                ctx2d.fillStyle = '#000';
                ctx2d.fillRect(0, 0, canvas.width, canvas.height);
                closedRow.textContent = '';
                if (!d) {
                    ctx2d.fillStyle = '#808080';
                    ctx2d.font = (7 * S) + 'px monospace';
                    ctx2d.fillText('Loading preview...', 10 * S, 20 * S);
                    return;
                }
                if (d.error) {
                    ctx2d.fillStyle = '#ff6060';
                    ctx2d.font = (6 * S) + 'px monospace';
                    wrapText(d.error, 30).forEach((ln, i) => ctx2d.fillText(ln, 8 * S, (16 + i * 10) * S));
                    return;
                }
                const ts = (d.tileSize || 8) * S;
                const closed = [];
                (d.windows || []).forEach(w => {
                    if (!w.open) { closed.push(w.id); return; }
                    const g = geomOf(w);
                    const x = g.x * ts, y = g.y * ts, wd = g.width * ts, ht = g.height * ts;
                    // window body
                    ctx2d.fillStyle = 'rgba(10, 16, 40, 0.92)';
                    ctx2d.fillRect(x, y, wd, ht);
                    ctx2d.strokeStyle = (d.focused === w.id) ? '#ffe080' : '#c0c0c0';
                    ctx2d.lineWidth = (d.focused === w.id) ? 2 : 1;
                    ctx2d.strokeRect(x + 0.5, y + 0.5, wd - 1, ht - 1);
                    ctx2d.font = (6 * S) + 'px monospace';
                    let ty = y + (g.contentY != null ? g.contentY : 2) * ts;
                    if (g.title) {
                        ctx2d.fillStyle = '#ffd080';
                        ctx2d.fillText(String(g.title), x + 0.5 * ts, y + 1 * ts);
                    }
                    if (w.error) {
                        ctx2d.fillStyle = '#ff6060';
                        ctx2d.fillText('! ' + String(w.error).slice(0, 40), x + 0.5 * ts, ty);
                        ty += ts;
                    }
                    if (g.style === 'list' || g.style === 'roulette') {
                        (w.rows || []).forEach((row, i) => {
                            const isCur = (i + 1) === (w.cursor || 1);
                            ctx2d.fillStyle = isCur ? '#ffff80' : (row.highlighted ? '#90ee90' : '#ffffff');
                            ctx2d.fillText((isCur ? '>' : ' ') + row.text, x + 0.5 * ts, ty + i * ts);
                        });
                        if (w.text) {
                            ctx2d.fillStyle = '#ffffff';
                            ctx2d.fillText(String(w.text).split('\n')[0], x + 0.5 * ts, ty);
                        }
                    } else if (g.style === 'confirm') {
                        ctx2d.fillStyle = '#ffffff';
                        String(w.text || '').split('\n').forEach((ln, i) => ctx2d.fillText(ln, x + 2 * ts, ty + i * ts));
                        const opts = w.rows || [];
                        opts.forEach((row, i) => {
                            const slot = wd / Math.max(1, opts.length);
                            const isCur = (i + 1) === (w.cursor || 1);
                            ctx2d.fillStyle = isCur ? '#ffff80' : '#ffffff';
                            ctx2d.fillText((isCur ? '>' : ' ') + row.text, x + i * slot + 0.5 * ts, y + ht - 1.5 * ts);
                        });
                    } else { // panel, frame, unknown
                        ctx2d.fillStyle = '#ffffff';
                        const lines = String(w.text || '').split('\n');
                        lines.forEach((ln, i) => {
                            if (g.style === 'frame') {
                                const tw = ctx2d.measureText(ln).width;
                                ctx2d.fillText(ln, x + (wd - tw) / 2, ty + i * ts);
                            } else {
                                ctx2d.fillText(ln, x + 0.5 * ts, ty + i * ts);
                            }
                        });
                    }
                    if (g.missing) {
                        ctx2d.fillStyle = '#ff6060';
                        ctx2d.fillText('(no windowLayout entry)', x + 0.5 * ts, y + ht - 0.5 * ts);
                    }
                });
                closedRow.textContent = closed.length ? ('Closed windows (right-click canvas to edit layouts): ' + closed.join(', ')) : '';
            };

            const wrapText = (s, n) => {
                const out = [];
                s = String(s);
                for (let i = 0; i < s.length; i += n) out.push(s.slice(i, i + n));
                return out.slice(0, 12);
            };

            const fetchPreview = async () => {
                try {
                    const res = await fetch(`${API_URL}/preview-scene?id=${encodeURIComponent(scene.id)}`);
                    scenePreviewCache[scene.id] = await res.json();
                } catch (err) {
                    scenePreviewCache[scene.id] = { error: 'preview request failed: ' + err.message };
                }
                draw();
            };

            refreshBtn.onclick = async () => {
                await saveData();
                await fetchPreview();
            };

            // ---- Right-click editing ----------------------------------

            const hitWindow = (px, py) => {
                const d = data();
                if (!d || d.error) return null;
                const ts = (d.tileSize || 8) * S;
                let hit = null; // topmost = last in draw order
                (d.windows || []).forEach(w => {
                    if (!w.open) return;
                    const g = geomOf(w);
                    if (px >= g.x * ts && px <= (g.x + g.width) * ts && py >= g.y * ts && py <= (g.y + g.height) * ts) hit = w;
                });
                return hit;
            };

            const editProps = (id) => {
                const layout = wl()[id] || {};
                const overlay = document.createElement('div');
                overlay.id = 'window-props-modal';
                overlay.style.cssText = 'position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,0.3);display:flex;align-items:center;justify-content:center;';
                const form = document.createElement('div');
                form.style.cssText = 'min-width:260px;padding:8px;background:var(--win-gray);border:2px solid;border-color:var(--win-white) var(--win-shadow) var(--win-shadow) var(--win-white);';
                const title = document.createElement('div');
                title.textContent = `Window properties — ${id}`;
                title.style.cssText = 'font-weight:bold;margin-bottom:6px;';
                form.appendChild(title);

                const fields = {};
                const numRow = (key, val) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display:flex;gap:4px;align-items:center;margin-bottom:3px;';
                    const lbl = document.createElement('span');
                    lbl.textContent = key;
                    lbl.style.cssText = 'width:70px;font-size:10px;';
                    const inp = document.createElement('input');
                    inp.type = 'number';
                    inp.step = '0.5';
                    inp.className = 'win98-input';
                    inp.style.width = '70px';
                    inp.value = val != null ? val : '';
                    fields[key] = inp;
                    row.appendChild(lbl);
                    row.appendChild(inp);
                    return row;
                };
                form.appendChild(numRow('x', layout.x));
                form.appendChild(numRow('y', layout.y));
                form.appendChild(numRow('width', layout.width));
                form.appendChild(numRow('height', layout.height));

                const styleRow = document.createElement('div');
                styleRow.style.cssText = 'display:flex;gap:4px;align-items:center;margin-bottom:3px;';
                const styleLbl = document.createElement('span');
                styleLbl.textContent = 'style';
                styleLbl.style.cssText = 'width:70px;font-size:10px;';
                const styleSel = makeSelect(['list', 'panel', 'frame', 'confirm', 'roulette'], layout.style || 'panel', () => {}, null);
                styleRow.appendChild(styleLbl);
                styleRow.appendChild(styleSel);
                form.appendChild(styleRow);

                const titleRow = document.createElement('div');
                titleRow.style.cssText = 'display:flex;gap:4px;align-items:center;margin-bottom:6px;';
                const titleLbl = document.createElement('span');
                titleLbl.textContent = 'title';
                titleLbl.style.cssText = 'width:70px;font-size:10px;';
                const titleInp = document.createElement('input');
                titleInp.className = 'win98-input';
                titleInp.style.flex = '1';
                titleInp.value = layout.title != null ? layout.title : '';
                titleRow.appendChild(titleLbl);
                titleRow.appendChild(titleInp);
                form.appendChild(titleRow);

                const btnRow = document.createElement('div');
                btnRow.style.cssText = 'display:flex;gap:6px;justify-content:flex-end;';
                const applyBtn = document.createElement('button');
                applyBtn.className = 'win98-btn win98-btn-success';
                applyBtn.textContent = 'Apply';
                applyBtn.onclick = () => {
                    const entry = wl()[id] || {};
                    ['x', 'y', 'width', 'height'].forEach(k => {
                        const n = parseFloat(fields[k].value);
                        if (!isNaN(n)) entry[k] = n;
                    });
                    entry.style = styleSel.value;
                    entry.title = titleInp.value.trim() === '' ? null : titleInp.value;
                    wl()[id] = entry;
                    setDirty(true);
                    overlay.remove();
                    draw();
                };
                const cancelBtn = document.createElement('button');
                cancelBtn.className = 'win98-btn';
                cancelBtn.textContent = 'Cancel';
                cancelBtn.onclick = () => overlay.remove();
                btnRow.appendChild(applyBtn);
                btnRow.appendChild(cancelBtn);
                form.appendChild(btnRow);
                overlay.onclick = (e) => { if (e.target === overlay) overlay.remove(); };
                overlay.appendChild(form);
                document.body.appendChild(overlay);
            };

            const removeWindow = (id) => {
                const refs = scanForWindowRefs(scene, id);
                if (refs.length > 0) {
                    const hooks = [...new Set(refs.map(r => `${r.hook} (${r.cmd})`))];
                    if (!confirm(`'${id}' is still referenced by ${refs.length} command(s):\n  ${hooks.join('\n  ')}\n\nRemove the windowLayout entry anyway? The commands will point at a missing window.`)) return;
                }
                delete wl()[id];
                setDirty(true);
                draw();
            };

            const jumpToHook = (id) => {
                const refs = scanForWindowRefs(scene, id);
                const open = refs.find(r => r.cmd === 'OPEN_WINDOW') || refs[0];
                if (!open) {
                    showToast(`No hook command references window '${id}'.`);
                    return;
                }
                activeUnifiedPhase = open.hook;
                cmdRestoreTarget = { array: open.array, idx: open.idx };
                refreshEditor();
            };

            const addWindowAt = (tileX, tileY, preset) => {
                let id = prompt(`New ${preset.label.toLowerCase()} id (letters/digits/underscore):`, '');
                if (id === null) return;
                id = id.trim();
                if (!/^\w+$/.test(id)) { showToast('Invalid window id.'); return; }
                if (wl()[id]) { showToast(`windowLayout already has '${id}'.`); return; }
                wl()[id] = { x: tileX, y: tileY, width: preset.width, height: preset.height, style: preset.style, title: null };
                scene.hooks = scene.hooks || {};
                scene.hooks.on_enter = scene.hooks.on_enter || [];
                scene.hooks.on_enter.push({ cmd: 'OPEN_WINDOW', windowId: id });
                setDirty(true);
                // Show it immediately: synthesize a payload entry until the
                // next Save & Refresh materializes real content.
                const d = data();
                if (d && d.windows) d.windows.push({ id, open: true, hasLayout: true, x: tileX, y: tileY, width: preset.width, height: preset.height, style: preset.style });
                refreshEditor();
            };

            canvas.addEventListener('contextmenu', (e) => {
                e.preventDefault();
                const rect = canvas.getBoundingClientRect();
                const px = e.clientX - rect.left, py = e.clientY - rect.top;
                const w = hitWindow(px, py);
                if (w) {
                    showCmdContextMenu(e.clientX, e.clientY, [
                        { label: `Edit Properties (${w.id})`, action: () => editProps(w.id) },
                        { label: 'Jump to Hook', action: () => jumpToHook(w.id) },
                        '-',
                        { label: 'Remove Window', action: () => removeWindow(w.id) }
                    ]);
                } else {
                    const d = data();
                    const ts = ((d && d.tileSize) || 8) * S;
                    const tileX = Math.floor(px / ts), tileY = Math.floor(py / ts);
                    showCmdContextMenu(e.clientX, e.clientY, SCENE_WINDOW_PRESETS.map(p => ({
                        label: `Add Window: ${p.label}`,
                        action: () => addWindowAt(tileX, tileY, p)
                    })));
                }
            });

            // First render: draw from cache immediately, fetch if absent
            draw();
            if (!data()) fetchPreview();
        }
