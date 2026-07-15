
        // E5: Visual scene editor — canvas preview + editing.
        //
        // The canvas shows the engine-rendered frame produced by
        // `lovec . preview-scene <id>` (GET /preview-scene?id=N):
        //   frameKind "windows"     scene_host.draw ("draw": "windows")
        //   frameKind "legacy"      the same renderer call love.draw makes
        //                           for built-in ids (menu/shop)
        //   frameKind "declarative" hook-declared windows via the window
        //                           renderer (items/status stubs)
        // plus JSON metadata (geometry, resolved rows/text/cursor) used for
        // hit-testing and the inspector. Geometry edits overlay live from
        // dbPayload.engine.windowLayout; frame CONTENT reflects the last
        // save (Save & Refresh re-renders).
        //
        // Interaction: left-click selects a window (inspector dock shows its
        // properties + resolved contents), drag moves it, dragging edges
        // resizes, right-click for Add/Remove/Jump to Hook.

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

        // E12: same scan, across EVERY scene — a windowLayout entry can be
        // shared by more than one scene now (partyGrid windows especially),
        // so Remove-Window warnings and the Windows tab's "View in Scene"
        // link both need every reference, not just one scene's.
        function scanAllScenesForWindowRefs(windowId) {
            const hits = [];
            (dbPayload.scenes || []).forEach(scene => {
                scanForWindowRefs(scene, windowId).forEach(ref => {
                    hits.push(Object.assign({ sceneId: scene.id, sceneName: scene.name || String(scene.id) }, ref));
                });
            });
            return hits;
        }

        // E12: one-shot hint so the Windows tab's "View in Scene" link can
        // land with the right window already selected — set right before
        // switching to the Scenes tab and navigating to a scene; consumed
        // (and cleared) the next time this scene's canvas renders.
        let pendingWindowSelect = null;
        function requestSceneCanvasSelect(windowId) {
            pendingWindowSelect = windowId;
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
            caveat.textContent = 'Frame shows the last save; geometry edits overlay live. Click to inspect, drag to move, drag edges to resize.';
            barRow.appendChild(refreshBtn);
            barRow.appendChild(caveat);
            box.appendChild(barRow);

            // Canvas on the left, inspector dock filling the space beside it
            const flexRow = document.createElement('div');
            flexRow.style.cssText = 'display: flex; gap: 8px; align-items: flex-start;';
            const gw = 256, gh = 240, S = SCENE_PREVIEW_SCALE;
            const canvas = document.createElement('canvas');
            canvas.width = gw * S;
            canvas.height = gh * S;
            canvas.style.cssText = 'border: 1px solid var(--win-shadow); background: #000; display: block; flex: 0 0 auto;';
            flexRow.appendChild(canvas);

            const dock = document.createElement('div');
            dock.style.cssText = 'flex: 1 1 auto; min-width: 180px; max-height: ' + (gh * S) + 'px; overflow-y: auto; font-size: 11px;';
            flexRow.appendChild(dock);
            box.appendChild(flexRow);

            const closedRow = document.createElement('div');
            closedRow.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin-top: 3px;';
            box.appendChild(closedRow);
            container.appendChild(box);

            const ctx2d = canvas.getContext('2d');
            const data = () => scenePreviewCache[scene.id];
            let selectedId = pendingWindowSelect;
            pendingWindowSelect = null;

            // Live geometry: unsaved windowLayout edits override the payload.
            // S1w: for data-authored windows (scene.windows), edits go to the
            // window def's rect directly, bypassing engine.json windowLayout.
            const liveRectOf = (id) => {
                const sceneWindows = scene.windows;
                if (sceneWindows && sceneWindows.length > 0) {
                    const dw = sceneWindows.find(x => x.id === id);
                    if (dw && dw.rect) return dw.rect;
                }
                return null;
            };
            const geomOf = (w) => {
                const l = wl()[w.id];
                if (!l) {
                    // S1w: check for data-authored window rect.
                    const live = liveRectOf(w.id);
                    if (live) return { x: live.x, y: live.y, width: live.w, height: live.h, style: w.style || 'panel', title: w.title, missing: false };
                    return { x: w.x, y: w.y, width: w.width, height: w.height, style: w.style, title: w.title, missing: !w.hasLayout };
                }
                return { x: l.x || 0, y: l.y || 0, width: l.width || 8, height: l.height || 4, style: l.style || 'panel', title: l.title != null ? l.title : w.title, contentY: l.contentY };
            };

            // S1w: helper to write rect edits back to the right place.
            const applyRectEdit = (id, key, value) => {
                const sceneWindows = scene.windows;
                if (sceneWindows && sceneWindows.length > 0) {
                    const dw = sceneWindows.find(x => x.id === id);
                    if (dw && dw.rect) {
                        dw.rect[key] = value;
                        return true;
                    }
                }
                return false;
            };

            const frameImage = (d) => {
                if (!d.image) return null;
                if (d._img) return d._img;
                if (d._imgLoading) return null;
                d._imgLoading = true;
                const img = new Image();
                img.onload = () => { d._img = img; draw(); };
                img.src = 'data:image/png;base64,' + d.image;
                return null;
            };

            const wrapText = (s, n) => {
                const out = [];
                s = String(s);
                for (let i = 0; i < s.length; i += n) out.push(s.slice(i, i + n));
                return out.slice(0, 12);
            };

            const drawOverlays = (d, ts) => {
                (d.windows || []).forEach(w => {
                    if (!w.open) return;
                    const g = geomOf(w);
                    const moved = g.x !== w.x || g.y !== w.y || g.width !== w.width || g.height !== w.height;
                    if (moved) {
                        ctx2d.save();
                        ctx2d.strokeStyle = '#ffe080';
                        ctx2d.setLineDash([4, 3]);
                        ctx2d.strokeRect(g.x * ts + 0.5, g.y * ts + 0.5, g.width * ts - 1, g.height * ts - 1);
                        ctx2d.restore();
                    }
                    if (w.id === selectedId) {
                        ctx2d.save();
                        ctx2d.strokeStyle = '#40d0ff';
                        ctx2d.lineWidth = 2;
                        ctx2d.strokeRect(g.x * ts + 1, g.y * ts + 1, g.width * ts - 2, g.height * ts - 2);
                        // corner handle
                        ctx2d.fillStyle = '#40d0ff';
                        ctx2d.fillRect((g.x + g.width) * ts - 5, (g.y + g.height) * ts - 5, 5, 5);
                        ctx2d.restore();
                    }
                });
            };

            const drawSchematic = (d, ts) => {
                const closed = [];
                (d.windows || []).forEach(w => {
                    if (!w.open) { closed.push(w.id); return; }
                    const g = geomOf(w);
                    const x = g.x * ts, y = g.y * ts, wd = g.width * ts, ht = g.height * ts;
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
                    } else if (g.style === 'confirm') {
                        ctx2d.fillStyle = '#ffffff';
                        String(w.text || '').split('\n').forEach((ln, i) => ctx2d.fillText(ln, x + 2 * ts, ty + i * ts));
                        (w.rows || []).forEach((row, i, arr) => {
                            const slot = wd / Math.max(1, arr.length);
                            const isCur = (i + 1) === (w.cursor || 1);
                            ctx2d.fillStyle = isCur ? '#ffff80' : '#ffffff';
                            ctx2d.fillText((isCur ? '>' : ' ') + row.text, x + i * slot + 0.5 * ts, y + ht - 1.5 * ts);
                        });
                    } else {
                        ctx2d.fillStyle = '#ffffff';
                        String(w.text || '').split('\n').forEach((ln, i) => {
                            if (g.style === 'frame') {
                                const tw = ctx2d.measureText(ln).width;
                                ctx2d.fillText(ln, x + (wd - tw) / 2, ty + i * ts);
                            } else {
                                ctx2d.fillText(ln, x + 0.5 * ts, ty + i * ts);
                            }
                        });
                    }
                });
                return closed;
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
                const img = frameImage(d);
                let closed = (d.windows || []).filter(w => !w.open).map(w => w.id);
                if (img) {
                    ctx2d.imageSmoothingEnabled = false;
                    ctx2d.drawImage(img, 0, 0, canvas.width, canvas.height);
                } else if (!d.image) {
                    closed = drawSchematic(d, ts);
                } else {
                    return; // decoding in progress; onload redraws
                }
                drawOverlays(d, ts);
                const notes = [];
                if (d.imageError) notes.push('Frame render error: ' + d.imageError);
                if (d.frameKind === 'legacy') notes.push('Legacy-drawn scene: this frame comes from hardcoded renderer code; window edits below change only the declarative data.');
                if (d.frameKind === 'declarative') notes.push('Stub scene: in-game look is still legacy code (inside the menu); showing its declared windows.');
                if (closed.length) notes.push('Closed windows: ' + closed.join(', '));
                closedRow.textContent = notes.join(' — ');
            };

            // ---- Inspector dock ---------------------------------------

            const renderDock = () => {
                dock.innerHTML = '';
                const d = data();
                const w = d && !d.error && (d.windows || []).find(x => x.id === selectedId);
                if (!w) {
                    const hint = document.createElement('div');
                    hint.style.cssText = 'color: var(--win-dark-shadow); padding: 4px;';
                    hint.textContent = 'Click a window in the preview to inspect and edit it. Right-click empty space to add one.';
                    dock.appendChild(hint);
                    return;
                }
                const layout = wl()[w.id];
                const head = document.createElement('div');
                head.style.cssText = 'font-weight: bold; margin-bottom: 4px;';
                head.textContent = w.id + (layout ? '' : '  (no windowLayout entry)');
                dock.appendChild(head);

                // S1w: for data-authored windows, the rect lives in scene.windows
                // entries rather than engine.json windowLayout. The inspector dock
                // reads/writes the right source.
                const sceneWindows = scene.windows;
                const isDataAuthored = sceneWindows && sceneWindows.length > 0 && sceneWindows.find(x => x.id === w.id);
                const rectSource = isDataAuthored ? (isDataAuthored.rect || {}) : layout;

                if (layout || isDataAuthored) {
                    const grid = document.createElement('div');
                    grid.style.cssText = 'display: grid; grid-template-columns: 52px 70px 52px 70px; gap: 3px; align-items: center; margin-bottom: 4px;';
                    const numField = (key) => {
                        const lbl = document.createElement('span');
                        lbl.textContent = key;
                        const inp = document.createElement('input');
                        inp.type = 'number';
                        inp.step = '0.5';
                        inp.className = 'win98-input';
                        inp.style.width = '64px';
                        // Map scene.rect keys (x,y,w,h) to layout keys (x,y,width,height).
                        const layoutKey = key === 'width' ? 'width' : key === 'height' ? 'height' : key;
                        const rectKey = key;
                        inp.value = isDataAuthored
                            ? (isDataAuthored.rect ? isDataAuthored.rect[rectKey] : 0)
                            : (layout[key] != null ? layout[key] : '');
                        inp.oninput = () => {
                            const n = parseFloat(inp.value);
                            if (isNaN(n)) return;
                            if (isDataAuthored) {
                                if (!isDataAuthored.rect) isDataAuthored.rect = { x: 0, y: 0, w: 8, h: 4 };
                                isDataAuthored.rect[rectKey] = n;
                            } else {
                                layout[key] = n;
                            }
                            setDirty(true);
                            draw();
                        };
                        grid.appendChild(lbl);
                        grid.appendChild(inp);
                        return inp;
                    };
                    dock._fields = {
                        x: numField('x'), y: numField('y'),
                        width: numField('width'), height: numField('height')
                    };
                    dock.appendChild(grid);

                    const styleRow = document.createElement('div');
                    styleRow.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-bottom: 3px;';
                    const styleLbl = document.createElement('span');
                    styleLbl.textContent = 'style';
                    styleLbl.style.width = '52px';
                    const currentStyle = isDataAuthored ? (isDataAuthored.style || 'panel') : (layout.style || 'panel');
                    const styleSel = makeSelect(['list', 'panel', 'frame', 'confirm', 'roulette', 'partyGrid'], currentStyle, (v) => {
                        if (isDataAuthored) { isDataAuthored.style = v; } else { layout.style = v; }
                        setDirty(true);
                        draw();
                    }, null);
                    styleSel.onchange = () => {
                        const v = styleSel.value;
                        if (isDataAuthored) { isDataAuthored.style = v; } else { layout.style = v; }
                        setDirty(true); draw();
                    };
                    styleRow.appendChild(styleLbl);
                    styleRow.appendChild(styleSel);
                    dock.appendChild(styleRow);

                    const titleRow = document.createElement('div');
                    titleRow.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-bottom: 4px;';
                    const titleLbl = document.createElement('span');
                    titleLbl.textContent = 'title';
                    titleLbl.style.width = '52px';
                    const titleInp = document.createElement('input');
                    titleInp.className = 'win98-input';
                    titleInp.style.flex = '1';
                    titleInp.value = isDataAuthored
                        ? (isDataAuthored.title != null ? isDataAuthored.title : '')
                        : (layout.title != null ? layout.title : '');
                    titleInp.oninput = () => {
                        const v = titleInp.value.trim() === '' ? null : titleInp.value;
                        if (isDataAuthored) { isDataAuthored.title = v; } else { layout.title = v; }
                        setDirty(true);
                        draw();
                    };
                    titleRow.appendChild(titleLbl);
                    titleRow.appendChild(titleInp);
                    dock.appendChild(titleRow);
                }

                const btnRow = document.createElement('div');
                btnRow.style.cssText = 'display: flex; gap: 4px; margin-bottom: 6px; flex-wrap: wrap;';
                const jumpBtn = document.createElement('button');
                jumpBtn.className = 'win98-btn';
                jumpBtn.style.fontSize = '10px';
                jumpBtn.textContent = 'Jump to Hook';
                jumpBtn.onclick = () => jumpToHook(w.id);
                const removeBtn = document.createElement('button');
                removeBtn.className = 'win98-btn';
                removeBtn.style.fontSize = '10px';
                removeBtn.textContent = 'Remove Window';
                removeBtn.onclick = () => removeWindow(w.id);
                btnRow.appendChild(jumpBtn);
                btnRow.appendChild(removeBtn);
                dock.appendChild(btnRow);

                // Resolved contents from the last saved preview
                const contents = document.createElement('div');
                contents.style.cssText = 'border: 1px solid var(--win-shadow); background: #fff; padding: 4px; font-family: monospace; font-size: 10px; white-space: pre-wrap; max-height: 180px; overflow-y: auto;';
                const lines = [];
                lines.push('open: ' + w.open + '   style: ' + (layout ? layout.style : w.style));
                if (w.listId) lines.push('list: ' + w.listId + (w.cursor ? '   cursor: ' + w.cursor : ''));
                if (w.rows && w.rows.length) {
                    w.rows.forEach((row, i) => lines.push(((i + 1) === w.cursor ? '> ' : '  ') + row.text + (row.highlighted ? '  *' : '')));
                } else if (w.listId) {
                    lines.push('  (no rows in last save)');
                }
                if (w.text) lines.push('text:\n' + w.text);
                if (w.error) lines.push('ERROR: ' + w.error);
                contents.textContent = lines.join('\n');
                dock.appendChild(contents);

                // S1w: if the scene has a data-authored windows array, show
                // content block editor in the inspector dock.
                // (sceneWindows is already declared above in this function scope)
                if (sceneWindows && sceneWindows.length > 0) {
                    const dataWin = sceneWindows.find(x => x.id === w.id);
                    if (dataWin) {
                        const contentBox = document.createElement('fieldset');
                        contentBox.style.cssText = 'padding: 4px; margin-top: 6px;';
                        const contentLegend = document.createElement('legend');
                        contentLegend.textContent = 'Content Blocks (scene data)';
                        contentBox.appendChild(contentLegend);

                        (dataWin.content || []).forEach((block, bi) => {
                            const blockDiv = document.createElement('div');
                            blockDiv.style.cssText = 'border: 1px solid var(--win-shadow); padding: 4px; margin-bottom: 4px; font-size: 10px;';
                            const typeLabel = document.createElement('div');
                            typeLabel.style.cssText = 'font-weight: bold; color: var(--win-highlight);';
                            typeLabel.textContent = '[' + block.type + ']';
                            blockDiv.appendChild(typeLabel);

                            if (block.type === 'text') {
                                const ta = document.createElement('textarea');
                                ta.className = 'win98-input';
                                ta.style.cssText = 'width: 100%; height: 40px; font-family: monospace; font-size: 10px; box-sizing: border-box; resize: vertical; margin-top: 2px;';
                                ta.value = block.text || '';
                                ta.oninput = () => { block.text = ta.value; setDirty(true); };
                                blockDiv.appendChild(ta);
                            } else if (block.type === 'list') {
                                const grid = document.createElement('div');
                                grid.style.cssText = 'display: grid; grid-template-columns: 60px 1fr; gap: 2px; margin-top: 2px;';
                                const addField = (label, key) => {
                                    const lbl = document.createElement('span');
                                    lbl.textContent = label;
                                    const inp = document.createElement('input');
                                    inp.className = 'win98-input';
                                    inp.style.width = '100%';
                                    inp.value = block[key] || '';
                                    inp.oninput = () => { block[key] = inp.value; setDirty(true); };
                                    grid.appendChild(lbl);
                                    grid.appendChild(inp);
                                };
                                addField('listId', 'listId');
                                addField('format', 'format');
                                addField('cursor', 'cursor');
                                blockDiv.appendChild(grid);
                            } else if (block.type === 'gauge') {
                                const grid = document.createElement('div');
                                grid.style.cssText = 'display: grid; grid-template-columns: 60px 1fr; gap: 2px; margin-top: 2px;';
                                const addField = (label, key) => {
                                    const lbl = document.createElement('span');
                                    lbl.textContent = label;
                                    const inp = document.createElement('input');
                                    inp.className = 'win98-input';
                                    inp.style.width = '100%';
                                    inp.value = block[key] || '';
                                    inp.oninput = () => { block[key] = inp.value; setDirty(true); };
                                    grid.appendChild(lbl);
                                    grid.appendChild(inp);
                                };
                                addField('label', 'label');
                                addField('value', 'value');
                                addField('max', 'max');
                                addField('width', 'width');
                                blockDiv.appendChild(grid);
                            }

                            contentBox.appendChild(blockDiv);
                        });

                        // Button to add a new content block
                        const addBlockBtn = document.createElement('button');
                        addBlockBtn.className = 'win98-btn';
                        addBlockBtn.style.cssText = 'font-size: 10px; margin-top: 4px;';
                        addBlockBtn.textContent = '+ Add Block';
                        addBlockBtn.onclick = () => {
                            showCmdContextMenu(addBlockBtn.getBoundingClientRect().left, addBlockBtn.getBoundingClientRect().bottom, [
                                { label: 'Text block', action: () => { dataWin.content.push({ type: 'text', text: '' }); setDirty(true); renderDock(); } },
                                { label: 'List block', action: () => { dataWin.content.push({ type: 'list', listId: '', format: '{name}' }); setDirty(true); renderDock(); } },
                                { label: 'Gauge block', action: () => { dataWin.content.push({ type: 'gauge', label: '', value: '0', max: '1' }); setDirty(true); renderDock(); } },
                            ]);
                        };
                        contentBox.appendChild(addBlockBtn);

                        // Button to delete the last block
                        if (dataWin.content.length > 0) {
                            const delBlockBtn = document.createElement('button');
                            delBlockBtn.className = 'win98-btn';
                            delBlockBtn.style.cssText = 'font-size: 10px; margin-top: 2px; margin-left: 4px;';
                            delBlockBtn.textContent = 'Remove Last Block';
                            delBlockBtn.onclick = () => {
                                dataWin.content.pop();
                                setDirty(true);
                                renderDock();
                            };
                            contentBox.appendChild(delBlockBtn);
                        }

                        dock.appendChild(contentBox);
                    }
                }
            };

            const syncDockFields = () => {
                const layout = selectedId && wl()[selectedId];
                if (!layout || !dock._fields) return;
                ['x', 'y', 'width', 'height'].forEach(k => {
                    if (dock._fields[k] && document.activeElement !== dock._fields[k]) dock._fields[k].value = layout[k];
                });
            };

            const fetchPreview = async () => {
                try {
                    const res = await fetch(`${API_URL}/preview-scene?id=${encodeURIComponent(scene.id)}`);
                    scenePreviewCache[scene.id] = await res.json();
                } catch (err) {
                    scenePreviewCache[scene.id] = { error: 'preview request failed: ' + err.message };
                }
                draw();
                renderDock();
            };

            refreshBtn.onclick = async () => {
                await saveData();
                await fetchPreview();
            };

            // ---- Selection, drag-move and edge-resize ------------------

            const hitTest = (px, py) => {
                const d = data();
                if (!d || d.error) return null;
                const ts = (d.tileSize || 8) * S;
                let hit = null;
                (d.windows || []).forEach(w => {
                    if (!w.open) return;
                    const g = geomOf(w);
                    if (px >= g.x * ts && px <= (g.x + g.width) * ts && py >= g.y * ts && py <= (g.y + g.height) * ts) hit = w;
                });
                return hit;
            };

            const EDGE = 6; // px threshold for resize handles
            const edgeAt = (g, px, py, ts) => {
                const x = g.x * ts, y = g.y * ts, wd = g.width * ts, ht = g.height * ts;
                const nearR = Math.abs(px - (x + wd)) <= EDGE, nearB = Math.abs(py - (y + ht)) <= EDGE;
                const nearL = Math.abs(px - x) <= EDGE, nearT = Math.abs(py - y) <= EDGE;
                let e = '';
                if (nearT) e += 'n'; else if (nearB) e += 's';
                if (nearL) e += 'w'; else if (nearR) e += 'e';
                return e;
            };

            let dragState = null;
            const canvasPos = (e) => {
                const r = canvas.getBoundingClientRect();
                return { px: e.clientX - r.left, py: e.clientY - r.top };
            };

            canvas.addEventListener('mousedown', (e) => {
                if (e.button !== 0) return;
                const { px, py } = canvasPos(e);
                const d = data();
                const ts = ((d && d.tileSize) || 8) * S;

                // Edges of the SELECTED window win over interior hits of
                // overlapping neighbors: select first, then grab an edge —
                // otherwise a shared boundary always resizes the topmost.
                const selW = selectedId && d && !d.error
                    && (d.windows || []).find(x => x.id === selectedId && x.open);
                if (selW && wl()[selectedId]) {
                    const g = geomOf(selW);
                    const edge = edgeAt(g, px, py, ts);
                    if (edge) {
                        dragState = {
                            id: selectedId, mode: 'resize', edge,
                            startPx: px, startPy: py,
                            start: { x: g.x, y: g.y, width: g.width, height: g.height },
                            moved: false
                        };
                        e.preventDefault();
                        return;
                    }
                }

                const w = hitTest(px, py);
                selectedId = w ? w.id : null;
                draw();
                renderDock();
                if (!w || !wl()[w.id]) return;
                const g = geomOf(w);
                const edge = edgeAt(g, px, py, ts);
                dragState = {
                    id: w.id, mode: edge ? 'resize' : 'move', edge,
                    startPx: px, startPy: py,
                    start: { x: g.x, y: g.y, width: g.width, height: g.height },
                    moved: false
                };
                e.preventDefault();
            });

            canvas.addEventListener('mousemove', (e) => {
                const { px, py } = canvasPos(e);
                const d = data();
                const ts = ((d && d.tileSize) || 8) * S;
                if (!dragState) {
                    // cursor feedback (selected window's edges take priority)
                    const selW = selectedId && d && !d.error
                        && (d.windows || []).find(x => x.id === selectedId && x.open);
                    if (selW && wl()[selectedId]) {
                        const edge = edgeAt(geomOf(selW), px, py, ts);
                        if (edge) { canvas.style.cursor = edge + '-resize'; return; }
                    }
                    const w = hitTest(px, py);
                    if (w && wl()[w.id]) {
                        const edge = edgeAt(geomOf(w), px, py, ts);
                        canvas.style.cursor = edge ? (edge + '-resize') : 'move';
                    } else {
                        canvas.style.cursor = '';
                    }
                    return;
                }
                const layout = wl()[dragState.id];
                if (!layout) return;
                const snap = (v) => Math.round(v * 2) / 2; // half-tile grid
                const dx = (px - dragState.startPx) / ts, dy = (py - dragState.startPy) / ts;
                if (Math.abs(px - dragState.startPx) + Math.abs(py - dragState.startPy) > 3) dragState.moved = true;
                const s = dragState.start;
                if (dragState.mode === 'move') {
                    layout.x = snap(s.x + dx);
                    layout.y = snap(s.y + dy);
                } else {
                    if (dragState.edge.includes('e')) layout.width = Math.max(2, snap(s.width + dx));
                    if (dragState.edge.includes('s')) layout.height = Math.max(2, snap(s.height + dy));
                    if (dragState.edge.includes('w')) {
                        const nx = snap(s.x + dx);
                        layout.width = Math.max(2, snap(s.width + (s.x - nx)));
                        layout.x = nx;
                    }
                    if (dragState.edge.includes('n')) {
                        const ny = snap(s.y + dy);
                        layout.height = Math.max(2, snap(s.height + (s.y - ny)));
                        layout.y = ny;
                    }
                }
                draw();
                syncDockFields();
            });

            window.addEventListener('mouseup', () => {
                if (dragState && dragState.moved) setDirty(true);
                dragState = null;
            });

            // ---- Right-click menu --------------------------------------

            const removeWindow = (id) => {
                // S1w: if the window is data-authored (scene.windows), remove
                // it from the scene data rather than from engine.json.
                const sceneWindows = scene.windows;
                if (sceneWindows && sceneWindows.length > 0) {
                    const idx = sceneWindows.findIndex(w => w.id === id);
                    if (idx !== -1) {
                        if (!confirm(`Remove window '${id}' from the scene's data-authored windows array?`)) return;
                        sceneWindows.splice(idx, 1);
                        if (selectedId === id) selectedId = null;
                        setDirty(true);
                        draw();
                        renderDock();
                        return;
                    }
                }
                // Fall back to engine.json windowLayout path.
                const refs = scanAllScenesForWindowRefs(id);
                if (refs.length > 0) {
                    const hooks = [...new Set(refs.map(r => `${r.sceneName} → ${r.hook} (${r.cmd})`))];
                    if (!confirm(`'${id}' is still referenced by ${refs.length} command(s):\n  ${hooks.join('\n  ')}\n\nRemove the windowLayout entry anyway? The commands will point at a missing window.`)) return;
                }
                delete wl()[id];
                if (selectedId === id) selectedId = null;
                setDirty(true);
                draw();
                renderDock();
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
                const d = data();
                if (d && d.windows) d.windows.push({ id, open: true, hasLayout: true, x: tileX, y: tileY, width: preset.width, height: preset.height, style: preset.style });
                selectedId = id;
                refreshEditor();
            };

            canvas.addEventListener('contextmenu', (e) => {
                e.preventDefault();
                const { px, py } = canvasPos(e);
                const w = hitTest(px, py);
                if (w) {
                    selectedId = w.id;
                    draw();
                    renderDock();
                    showCmdContextMenu(e.clientX, e.clientY, [
                        { label: `Jump to Hook (${w.id})`, action: () => jumpToHook(w.id) },
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
            renderDock();
            if (!data()) fetchPreview();
        }
