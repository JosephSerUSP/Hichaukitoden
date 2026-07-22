
        // E12: the Windows tab — a visual editor for the windowLayout
        // REGISTRY itself (data/engine.json -> windowLayout), independent
        // of any one scene. A window editor, not a scene editor (owner
        // direction 12.07.2026): the canvas shows exactly ONE window in
        // isolation, at its own declared position, on an otherwise-black
        // 256x240 frame — the same real engine-rendered image E5 uses,
        // via POST /preview-window (main.lua's preview-window CLI mode).
        //
        // Preview content is a synthetic, editor-local "mock binding" (list
        // source / sample text / sibling windows for sel()) — NEVER saved
        // to data/*.json. Where a real scene already opens this window,
        // "View in Scene" jumps into E5's canvas for that scene instead of
        // building a second real-content rendering path.

        const WINDOW_STYLE_PRESETS = [
            { label: 'List window', style: 'list', width: 12, height: 16 },
            { label: 'Panel window', style: 'panel', width: 16, height: 8 },
            { label: 'Confirm window', style: 'confirm', width: 24, height: 10 },
            { label: 'Roulette window', style: 'roulette', width: 24, height: 10 },
            { label: 'Party grid window', style: 'partyGrid', width: 16, height: 10 },
        ];

        // Which windowLayout fields a data-authored scene's inline windows[]
        // entry overrides at draw time. MUST mirror window_renderer.lua's
        // synthetic-layout builder (drawWindowFromData, ~L1058-1066) — if that
        // merge rule changes, change this with it or the Windows tab starts
        // lying about which edits do anything.
        //
        // x/y/width/height are overwritten UNCONDITIONALLY: the renderer reads
        // the scene's rect and falls back to hardcoded 0/0/8/4, never to the
        // windowLayout value — so registry geometry is dead for an inline
        // window even when the scene omits rect entirely.
        const SCENE_OVERRIDES_ALWAYS = ['x', 'y', 'width', 'height'];
        // These are only overridden when the scene's entry actually sets them.
        const SCENE_OVERRIDES_IF_SET = ['style', 'title', 'emptyText', 'lineSpacing', 'visibleRows'];

        // Everything else (contentX/contentY, gridColumns, portrait*, gauges,
        // pages/pageFormula, anim, vertical, hideMp, rowPitch, ...) has no
        // scene-side path at all and is read only from windowLayout — so those
        // fields stay live and editable here even for a shadowed window.
        function computeSceneShadow(id) {
            const defs = (typeof scanAllScenesForInlineWindowDefs === 'function')
                ? scanAllScenesForInlineWindowDefs(id) : [];
            const dead = new Set();
            if (defs.length > 0) {
                SCENE_OVERRIDES_ALWAYS.forEach(k => dead.add(k));
                defs.forEach(({ winDef }) => {
                    SCENE_OVERRIDES_IF_SET.forEach(k => {
                        if (winDef[k] !== undefined) dead.add(k);
                    });
                });
            }
            return { defs, dead, isShadowed: defs.length > 0 };
        }

        let activeWindowId = null;
        let windowPreviewCache = {}; // id -> preview-window payload
        let windowMockState = {};    // id -> { listId, format, sprite, gaugeValue, gaugeMax, text, cursor, siblingsJson }

        function getWindowMock(id) {
            if (!windowMockState[id]) {
                windowMockState[id] = { listId: '', format: '', sprite: '', gaugeValue: '', gaugeMax: '', text: '', cursor: 1, siblingsJson: '' };
            }
            return windowMockState[id];
        }

        function buildMockSpecFromState(id) {
            const m = getWindowMock(id);
            const spec = {};
            if (m.listId) spec.listId = m.listId;
            if (m.format) spec.format = m.format;
            if (m.sprite) spec.sprite = m.sprite;
            if (m.gaugeValue) spec.gaugeValue = m.gaugeValue;
            if (m.gaugeMax) spec.gaugeMax = m.gaugeMax;
            if (m.text) spec.text = m.text;
            if (m.cursor) spec.cursor = m.cursor;
            if (m.siblingsJson && m.siblingsJson.trim()) {
                try { spec.siblings = JSON.parse(m.siblingsJson); } catch (e) { /* surfaced by the field's own validity styling */ }
            }
            return spec;
        }

        async function fetchWindowPreview(id) {
            try {
                const res = await fetch(`${API_URL}/preview-window`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ id, mock: buildMockSpecFromState(id) })
                });
                if (!res.ok) {
                    const body = (await res.text()).slice(0, 120);
                    windowPreviewCache[id] = { error: res.status === 404
                        ? 'preview endpoint missing (HTTP 404) — restart the editor server so it picks up /preview-window.'
                        : `preview request failed: HTTP ${res.status} ${body}` };
                    return;
                }
                windowPreviewCache[id] = await res.json();
            } catch (err) {
                windowPreviewCache[id] = { error: 'preview request failed: ' + err.message };
            }
        }

        // ---------------------------------------------------------------
        // Entry point (called from engine-editor.js's setEngineTab)
        // ---------------------------------------------------------------
        function renderWindowsTab(container, header) {
            header.textContent = 'Windows';
            const wl = () => {
                dbPayload.engine.windowLayout = dbPayload.engine.windowLayout || {};
                return dbPayload.engine.windowLayout;
            };

            // setEngineTab appends a persistent header to this container, so we
            // must NOT innerHTML-clear it; instead swap only our own body node.
            const prev = container.querySelector('#windows-tab-root');
            if (prev) prev.remove();

            const mainRow = document.createElement('div');
            mainRow.id = 'windows-tab-root';
            mainRow.style.cssText = 'display: flex; gap: 8px; align-items: flex-start;';

            // --- Left: window list ---
            const listCol = document.createElement('div');
            listCol.style.cssText = 'width: 170px; flex-shrink: 0; display: flex; flex-direction: column; gap: 4px;';
            const listBox = document.createElement('div');
            listBox.style.cssText = 'max-height: 480px; overflow-y: auto; border: 1px solid var(--win-shadow); background: var(--win-white);';

            Object.keys(wl()).sort().forEach(id => {
                const row = document.createElement('div');
                row.className = 'tree-node-header' + (id === activeWindowId ? ' active' : '');
                row.style.cssText = 'padding: 4px; cursor: pointer; font-size: 11px; display: flex; justify-content: space-between; align-items: center; gap: 4px;';
                const nameSpan = document.createElement('span');
                nameSpan.textContent = id;
                row.appendChild(nameSpan);
                // Flag scene-authored windows up front, so their geometry isn't
                // mistaken for something this tab controls.
                const sh = computeSceneShadow(id);
                if (sh.isShadowed) {
                    const badge = document.createElement('span');
                    badge.textContent = 'scene';
                    badge.style.cssText = 'font-size: 9px; padding: 0 3px; border: 1px solid var(--win-shadow); background: #ffffe1; color: #000; flex-shrink: 0;';
                    badge.title = 'Declared inline by: ' + sh.defs.map(d => d.sceneName).join(', ') + ' — that scene owns its position/size.';
                    row.appendChild(badge);
                }
                row.onclick = () => { activeWindowId = id; renderWindowsTab(container, header); };
                listBox.appendChild(row);
            });
            listCol.appendChild(listBox);

            const addBtn = document.createElement('button');
            addBtn.className = 'win98-btn';
            addBtn.style.fontSize = '10px';
            addBtn.textContent = '+ New Window';
            addBtn.onclick = (e) => {
                showCmdContextMenu(e.clientX, e.clientY, WINDOW_STYLE_PRESETS.map(p => ({
                    label: p.label,
                    action: () => {
                        const id = WindowGeom.createWindow(wl(), 0, 0, p);
                        if (!id) return;
                        setDirty(true);
                        activeWindowId = id;
                        renderWindowsTab(container, header);
                    }
                })));
            };
            listCol.appendChild(addBtn);
            mainRow.appendChild(listCol);

            // --- Right: editor for the selected window ---
            const editorCol = document.createElement('div');
            editorCol.style.cssText = 'flex: 1; min-width: 0;';

            if (!activeWindowId || !wl()[activeWindowId]) {
                const hint = document.createElement('div');
                hint.style.cssText = 'color: var(--win-dark-shadow); padding: 8px;';
                hint.textContent = 'Select a window on the left, or create one.';
                editorCol.appendChild(hint);
            } else {
                renderWindowEditorPane(editorCol, activeWindowId, () => {
                    renderWindowsTab(container, header);
                });
            }
            mainRow.appendChild(editorCol);

            container.appendChild(mainRow);
        }

        // ---------------------------------------------------------------
        // Right-side pane: actions, mock binding, canvas, property forms
        // ---------------------------------------------------------------
        function renderWindowEditorPane(container, id, refresh) {
            const wl = () => dbPayload.engine.windowLayout;
            const layout = wl()[id];
            const mock = getWindowMock(id);

            const box = document.createElement('div');
            box.style.cssText = 'display: flex; flex-direction: column; gap: 8px;';

            // --- Header: id + View in Scene + Remove ---
            const topRow = document.createElement('div');
            topRow.style.cssText = 'display: flex; justify-content: space-between; align-items: center; gap: 6px; flex-wrap: wrap; border-bottom: 1px solid var(--win-shadow); padding-bottom: 4px;';
            const idLabel = document.createElement('div');
            idLabel.style.cssText = 'font-weight: bold; font-size: 12px;';
            idLabel.textContent = id;
            topRow.appendChild(idLabel);

            const refs = scanAllScenesForWindowRefs(id);
            const shadow = computeSceneShadow(id);
            const actionsRow = document.createElement('div');
            actionsRow.style.cssText = 'display: flex; gap: 4px;';
            // A scene "uses" this window either by opening it from a hook
            // (refs) or by declaring it inline (shadow.defs) — both must count,
            // or converted scenes look unused and View in Scene goes missing.
            const usingScenes = [...new Set([...refs.map(r => r.sceneId), ...shadow.defs.map(d => d.sceneId)])];
            const usingSceneNames = [...new Set([...refs.map(r => r.sceneName), ...shadow.defs.map(d => d.sceneName)])];
            if (usingScenes.length > 0) {
                const viewBtn = document.createElement('button');
                viewBtn.className = 'win98-btn';
                viewBtn.style.fontSize = '10px';
                viewBtn.textContent = `View in Scene (${usingScenes.length})`;
                viewBtn.title = 'Scenes: ' + usingSceneNames.join(', ');
                viewBtn.onclick = () => {
                    requestSceneCanvasSelect(id);
                    activeSceneId = usingScenes[0];
                    activeUnifiedPhase = null;
                    setEngineTab('flows');
                };
                actionsRow.appendChild(viewBtn);
            }
            const removeBtn = document.createElement('button');
            removeBtn.className = 'win98-btn';
            removeBtn.style.fontSize = '10px';
            removeBtn.textContent = 'Remove Window';
            removeBtn.onclick = () => {
                if (refs.length > 0) {
                    const hooks = [...new Set(refs.map(r => `${r.sceneName} → ${r.hook} (${r.cmd})`))];
                    if (!confirm(`'${id}' is still referenced by ${refs.length} command(s):\n  ${hooks.join('\n  ')}\n\nRemove the windowLayout entry anyway? The commands will point at a missing window.`)) return;
                }
                delete wl()[id];
                delete windowPreviewCache[id];
                delete windowMockState[id];
                activeWindowId = null;
                setDirty(true);
                refresh();
            };
            actionsRow.appendChild(removeBtn);
            topRow.appendChild(actionsRow);
            box.appendChild(topRow);

            // Shadow banner: without this, editing a converted scene's window
            // here looks like it works (the tab's own preview reads
            // windowLayout directly) while changing nothing in the real scene.
            if (shadow.isShadowed) {
                const sceneNames = shadow.defs.map(d => d.sceneName).join(', ');
                const banner = document.createElement('div');
                banner.style.cssText = 'border: 1px solid var(--win-shadow); background: #ffffe1; color: #000; padding: 6px; font-size: 10px; line-height: 1.5;';
                const deadList = [...shadow.dead].join(', ');
                banner.innerHTML =
                    `<b>⚠ Authored by ${shadow.defs.length > 1 ? 'scenes' : 'scene'}: ${sceneNames}</b><br>` +
                    `This window is declared inline in the scene, which overrides <b>${deadList}</b> at draw time. ` +
                    `Editing ${shadow.dead.size > 1 ? 'those fields' : 'that field'} here changes nothing in the game — ` +
                    `edit the scene's own window instead (use “View in Scene”). ` +
                    `Fields not listed above (contentY, gauges, pages, portrait, gridColumns, anim, …) have no scene-side ` +
                    `override and are still live here.`;
                box.appendChild(banner);
            }

            // Canvas on the left (fixed, 2x nearest-neighbor), scrollable
            // input dock filling the space to its right — mirrors the
            // Scenes tab's flexRow+dock layout.
            const flexRow = document.createElement('div');
            flexRow.style.cssText = 'display: flex; gap: 8px; align-items: flex-start;';
            box.appendChild(flexRow);

            const gw = 256, gh = 240, S = 2;
            const canvas = document.createElement('canvas');
            canvas.width = gw * S;
            canvas.height = gh * S;
            canvas.style.cssText = `width: ${gw * S}px; height: ${gh * S}px; image-rendering: pixelated; border: 1px solid var(--win-shadow); background: #000; display: block; flex: 0 0 auto;`;
            flexRow.appendChild(canvas);

            const dock = document.createElement('div');
            dock.style.cssText = 'flex: 1 1 auto; min-width: 220px; max-height: ' + (gh * S) + 'px; overflow-y: auto; display: flex; flex-direction: column; gap: 8px;';
            flexRow.appendChild(dock);

            const canvasHint = document.createElement('div');
            canvasHint.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow);';
            canvasHint.textContent = shadow.isShadowed
                ? 'Preview only — this window\'s position/size come from the scene (see above), so dragging here won\'t affect the game.'
                : 'Drag to move, drag an edge/corner to resize. This window only — siblings (if any) render for context but aren\'t editable here.';
            box.appendChild(canvasHint);

            // --- Mock binding controls ---
            const mockBox = document.createElement('fieldset');
            mockBox.style.cssText = 'padding: 6px;';
            const mockLegend = document.createElement('legend');
            mockLegend.textContent = 'Preview content (editor-only, never saved)';
            mockBox.appendChild(mockLegend);
            const mockNote = document.createElement('div');
            mockNote.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin-bottom: 4px;';
            mockNote.textContent = usingScenes.length > 0
                ? 'This window is already used by a real scene — "View in Scene" shows its actual content. These fields are just for previewing here in isolation.'
                : 'No scene uses this window yet. Fill these in to see realistic content while designing it.';
            mockBox.appendChild(mockNote);

            const refreshPreviewAndCanvas = async () => {
                await fetchWindowPreview(id);
                drawCanvas();
            };

            const mockGrid = document.createElement('div');
            mockGrid.style.cssText = 'display: grid; grid-template-columns: 70px 1fr; gap: 4px; align-items: center; font-size: 10px;';
            const mockField = (labelText, key, placeholder) => {
                const lbl = document.createElement('span');
                lbl.textContent = labelText;
                const inp = document.createElement('input');
                inp.className = 'win98-input';
                inp.placeholder = placeholder || '';
                inp.value = mock[key];
                inp.oninput = () => { mock[key] = inp.value; };
                inp.onchange = refreshPreviewAndCanvas;
                mockGrid.appendChild(lbl);
                mockGrid.appendChild(inp);
            };
            mockField('List', 'listId', 'party / inventory / static:a,b,c / config:key');
            mockField('Format', 'format', '{name} (x{qty})');
            mockField('Sprite field', 'sprite', 'spriteKey');
            mockField('Gauge value', 'gaugeValue', 'hp');
            mockField('Gauge max', 'gaugeMax', 'maxHp');
            const cursorLbl = document.createElement('span');
            cursorLbl.textContent = 'Cursor';
            const cursorInp = document.createElement('input');
            cursorInp.type = 'number';
            cursorInp.className = 'win98-input';
            cursorInp.value = mock.cursor;
            cursorInp.oninput = () => { mock.cursor = parseInt(cursorInp.value, 10) || 1; };
            cursorInp.onchange = refreshPreviewAndCanvas;
            mockGrid.appendChild(cursorLbl);
            mockGrid.appendChild(cursorInp);
            mockBox.appendChild(mockGrid);

            const textLbl = document.createElement('div');
            textLbl.style.cssText = 'font-size: 10px; margin-top: 4px;';
            textLbl.textContent = 'Sample text ({expr} tokens are evaluated live):';
            mockBox.appendChild(textLbl);
            const textArea = document.createElement('textarea');
            textArea.className = 'win98-input';
            textArea.style.cssText = 'width: 100%; height: 40px; font-family: monospace; font-size: 10px; box-sizing: border-box; resize: vertical;';
            textArea.value = mock.text;
            textArea.oninput = () => { mock.text = textArea.value; };
            textArea.onchange = refreshPreviewAndCanvas;
            mockBox.appendChild(textArea);

            const sibLbl = document.createElement('div');
            sibLbl.style.cssText = 'font-size: 10px; margin-top: 4px;';
            sibLbl.textContent = 'Sibling windows for sel(\'otherWindow\') (JSON, e.g. {"status_party":{"listId":"party","cursor":1}}):';
            mockBox.appendChild(sibLbl);
            const sibArea = document.createElement('textarea');
            sibArea.className = 'win98-input';
            sibArea.style.cssText = 'width: 100%; height: 32px; font-family: monospace; font-size: 10px; box-sizing: border-box; resize: vertical;';
            sibArea.value = mock.siblingsJson;
            sibArea.oninput = () => {
                mock.siblingsJson = sibArea.value;
                if (sibArea.value.trim() === '') { sibArea.style.backgroundColor = ''; return; }
                try { JSON.parse(sibArea.value); sibArea.style.backgroundColor = ''; }
                catch (e) { sibArea.style.backgroundColor = '#ffcccc'; }
            };
            sibArea.onchange = refreshPreviewAndCanvas;
            mockBox.appendChild(sibArea);

            const refreshBtn = document.createElement('button');
            refreshBtn.className = 'win98-btn';
            refreshBtn.style.cssText = 'font-size: 10px; margin-top: 4px; align-self: flex-start;';
            refreshBtn.textContent = 'Save & Refresh Preview';
            refreshBtn.onclick = async () => { await saveData(); await refreshPreviewAndCanvas(); };
            mockBox.appendChild(refreshBtn);
            dock.appendChild(mockBox);

            const ctx2d = canvas.getContext('2d');
            const data = () => windowPreviewCache[id];

            const drawCanvas = () => {
                const d = data();
                ctx2d.fillStyle = '#000';
                ctx2d.fillRect(0, 0, canvas.width, canvas.height);
                if (!d) {
                    ctx2d.fillStyle = '#808080';
                    ctx2d.font = (7 * S) + 'px monospace';
                    ctx2d.fillText('Loading preview...', 10 * S, 20 * S);
                    return;
                }
                if (d.error) {
                    ctx2d.fillStyle = '#ff6060';
                    ctx2d.font = (6 * S) + 'px monospace';
                    const s = String(d.error);
                    for (let i = 0; i < s.length; i += 30) ctx2d.fillText(s.slice(i, i + 30), 8 * S, (16 + (i / 30) * 10) * S);
                    return;
                }
                if (d.image) {
                    if (!d._img) {
                        const img = new Image();
                        img.onload = () => { d._img = img; drawCanvas(); };
                        img.src = 'data:image/png;base64,' + d.image;
                        return;
                    }
                    ctx2d.imageSmoothingEnabled = false;
                    ctx2d.drawImage(d._img, 0, 0, canvas.width, canvas.height);
                }
                if (d.imageError) {
                    ctx2d.fillStyle = '#ff6060';
                    ctx2d.font = (6 * S) + 'px monospace';
                    ctx2d.fillText('Frame render error: ' + d.imageError, 4 * S, canvas.height - 6 * S);
                }
                // Outline the PRIMARY window (highlight it among any siblings)
                const ts = ((d.tileSize) || 8) * S;
                const primary = (d.windows || []).find(w => w.id === id);
                if (primary) {
                    ctx2d.save();
                    ctx2d.strokeStyle = '#40d0ff';
                    ctx2d.lineWidth = 2;
                    ctx2d.strokeRect(layout.x * ts + 1, layout.y * ts + 1, (layout.width || 8) * ts - 2, (layout.height || 4) * ts - 2);
                    ctx2d.fillStyle = '#40d0ff';
                    ctx2d.fillRect((layout.x + (layout.width || 8)) * ts - 5, (layout.y + (layout.height || 4)) * ts - 5, 5, 5);
                    ctx2d.restore();
                }
            };

            const edgeAt = (px, py, ts) => WindowGeom.edgeAt(layout, px, py, ts);
            const canvasPos = (e) => WindowGeom.canvasPos(canvas, e);

            let dragState = null;
            canvas.addEventListener('mousedown', (e) => {
                if (e.button !== 0) return;
                // Dragging a scene-authored window would edit x/y/width/height
                // the renderer never reads, and dirty the database for a change
                // with no effect. The banner explains where to edit instead.
                if (shadow.isShadowed) return;
                const { px, py } = canvasPos(e);
                const d = data();
                const ts = ((d && d.tileSize) || 8) * S;
                const edge = edgeAt(px, py, ts);
                const x = layout.x * ts, y = layout.y * ts, w = (layout.width || 8) * ts, h = (layout.height || 4) * ts;
                const inside = px >= x && px <= x + w && py >= y && py <= y + h;
                if (!edge && !inside) return;
                dragState = {
                    mode: edge ? 'resize' : 'move', edge,
                    startPx: px, startPy: py,
                    start: { x: layout.x, y: layout.y, width: layout.width || 8, height: layout.height || 4 },
                    moved: false
                };
                e.preventDefault();
            });
            canvas.addEventListener('mousemove', (e) => {
                if (shadow.isShadowed) return; // no drag affordance for a read-only preview
                const { px, py } = canvasPos(e);
                const d = data();
                const ts = ((d && d.tileSize) || 8) * S;
                if (!dragState) {
                    const edge = edgeAt(px, py, ts);
                    const x = layout.x * ts, y = layout.y * ts, w = (layout.width || 8) * ts, h = (layout.height || 4) * ts;
                    const inside = px >= x && px <= x + w && py >= y && py <= y + h;
                    canvas.style.cursor = edge ? (edge + '-resize') : (inside ? 'move' : '');
                    return;
                }
                WindowGeom.applyDrag(layout, dragState, px, py, ts);
                drawCanvas();
                syncFormFields();
            });
            window.addEventListener('mouseup', () => {
                if (dragState && dragState.moved) setDirty(true);
                dragState = null;
            });

            // --- Property form ---
            const propBox = document.createElement('fieldset');
            propBox.style.cssText = 'padding: 6px;';
            const propLegend = document.createElement('legend');
            propLegend.textContent = 'Properties';
            propBox.appendChild(propLegend);

            // A shadowed field is disabled rather than merely annotated: the
            // value it holds is not what the game draws, so letting it be typed
            // into only invites edits that silently do nothing.
            const markShadowed = (lbl, inp, key) => {
                if (!shadow.dead.has(key)) return false;
                lbl.style.textDecoration = 'line-through';
                lbl.style.opacity = '0.55';
                inp.disabled = true;
                inp.style.opacity = '0.55';
                inp.title = `Overridden by scene: ${shadow.defs.map(d => d.sceneName).join(', ')}. Edit it there — this value is ignored at draw time.`;
                lbl.title = inp.title;
                return true;
            };

            const fieldRefs = {};
            const grid = document.createElement('div');
            grid.style.cssText = 'display: grid; grid-template-columns: 90px 80px 90px 80px; gap: 4px; align-items: center; font-size: 10px;';
            const numField = (key, label) => {
                const lbl = document.createElement('span'); lbl.textContent = label;
                const inp = document.createElement('input');
                inp.type = 'number'; inp.step = '0.5'; inp.className = 'win98-input';
                inp.value = layout[key] != null ? layout[key] : '';
                inp.oninput = () => {
                    const n = parseFloat(inp.value);
                    if (!isNaN(n)) { layout[key] = n; setDirty(true); drawCanvas(); }
                };
                markShadowed(lbl, inp, key);
                fieldRefs[key] = inp;
                grid.appendChild(lbl); grid.appendChild(inp);
            };
            numField('x', 'x'); numField('y', 'y');
            numField('width', 'width'); numField('height', 'height');
            numField('contentX', 'contentX'); numField('contentY', 'contentY');
            numField('lineSpacing', 'lineSpacing'); numField('visibleRows', 'visibleRows');
            numField('rowPitch', 'rowPitch'); numField('spriteSize', 'spriteSize');
            numField('gaugeHeight', 'gaugeHeight'); numField('gridColumns', 'gridColumns');
            numField('portraitX', 'portraitX'); numField('portraitY', 'portraitY');
            propBox.appendChild(grid);

            const styleRow = document.createElement('div');
            styleRow.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-top: 4px; font-size: 10px;';
            const styleLbl = document.createElement('span'); styleLbl.textContent = 'style'; styleLbl.style.width = '70px';
            // Includes the 4 battle-internal singleton styles (command,
            // enemyRow, battleLog, victoryPanel — presentation/window_renderer.lua
            // ~L896-920) so their registry entries display their real style
            // instead of makeSelect silently falling back to the first option
            // when the current value isn't in the list. Deliberately NOT added
            // to WINDOW_STYLE_PRESETS above: those 4 read bespoke env.v fields
            // (battle/combatLog/victory) a freshly created window has no data
            // for, so they stay view/edit-only here, not creatable.
            const styleSel = makeSelect(['list', 'panel', 'frame', 'confirm', 'roulette', 'partyGrid', 'command', 'enemyRow', 'battleLog', 'victoryPanel'], layout.style || 'panel', (v) => {
                layout.style = v; drawCanvas();
            }, null);
            markShadowed(styleLbl, styleSel, 'style');
            styleRow.appendChild(styleLbl); styleRow.appendChild(styleSel);
            propBox.appendChild(styleRow);

            const titleRow = document.createElement('div');
            titleRow.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-top: 4px; font-size: 10px;';
            const titleLbl = document.createElement('span'); titleLbl.textContent = 'title'; titleLbl.style.width = '70px';
            const titleInp = document.createElement('input');
            titleInp.className = 'win98-input'; titleInp.style.flex = '1';
            titleInp.value = layout.title != null ? layout.title : '';
            titleInp.oninput = () => { layout.title = titleInp.value.trim() === '' ? null : titleInp.value; setDirty(true); drawCanvas(); };
            markShadowed(titleLbl, titleInp, 'title');
            titleRow.appendChild(titleLbl); titleRow.appendChild(titleInp);
            propBox.appendChild(titleRow);

            const emptyRow = document.createElement('div');
            emptyRow.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-top: 4px; font-size: 10px;';
            const emptyLbl = document.createElement('span'); emptyLbl.textContent = 'emptyText'; emptyLbl.style.width = '70px';
            const emptyInp = document.createElement('input');
            emptyInp.className = 'win98-input'; emptyInp.style.flex = '1';
            emptyInp.value = layout.emptyText || '';
            emptyInp.oninput = () => { layout.emptyText = emptyInp.value; setDirty(true); };
            markShadowed(emptyLbl, emptyInp, 'emptyText');
            emptyRow.appendChild(emptyLbl); emptyRow.appendChild(emptyInp);
            propBox.appendChild(emptyRow);

            const portraitRow = document.createElement('div');
            portraitRow.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-top: 4px; font-size: 10px;';
            const portraitLbl = document.createElement('span'); portraitLbl.textContent = 'portrait'; portraitLbl.style.width = '70px';
            const portraitInp = document.createElement('input');
            portraitInp.className = 'win98-input'; portraitInp.style.flex = '1';
            portraitInp.placeholder = "formula, e.g. sel('status_party').portraitKey";
            portraitInp.value = layout.portrait || '';
            portraitInp.oninput = () => { layout.portrait = portraitInp.value; setDirty(true); };
            portraitRow.appendChild(portraitLbl); portraitRow.appendChild(portraitInp);
            propBox.appendChild(portraitRow);

            function syncFormFields() {
                ['x', 'y', 'width', 'height'].forEach(k => {
                    if (fieldRefs[k] && document.activeElement !== fieldRefs[k]) fieldRefs[k].value = layout[k];
                });
            }
            dock.appendChild(propBox);

            // --- Gauges editor ---
            dock.appendChild(buildGaugeListEditor(layout, drawCanvas));

            // --- Pages editor ---
            dock.appendChild(buildPageListEditor(layout, drawCanvas));

            container.appendChild(box);
            drawCanvas();
            if (!data()) fetchWindowPreview(id).then(drawCanvas);
        }

        // ---------------------------------------------------------------
        // Dedicated widget: layout.gauges (declarative label+bar rows)
        // ---------------------------------------------------------------
        function buildGaugeListEditor(layoutObj, onChange) {
            layoutObj.gauges = layoutObj.gauges || [];
            const box = document.createElement('fieldset');
            box.style.cssText = 'padding: 6px;';
            const legend = document.createElement('legend');
            legend.textContent = 'Gauges (layout.gauges)';
            box.appendChild(legend);

            buildRowListEditor(box, layoutObj.gauges, {
                columns: [{ label: 'Label', flex: '1' }, { label: 'Value', flex: '1' }, { label: 'Max', flex: '1' }, { label: 'X/Y/W', flex: '1' }],
                summary: (g) => [g.label || '(no label)', g.value != null ? String(g.value) : '0', g.max != null ? String(g.max) : '1', `${g.x != null ? g.x : 1}, ${g.y != null ? g.y : 1}, ${g.width != null ? g.width : 18}`],
                editor: (row, g, idx, commit) => {
                    row.style.cssText = 'display: grid; grid-template-columns: 1fr 1fr 1fr 40px 40px 40px auto auto; gap: 3px; align-items: center; font-size: 10px;';
                    const mk = (val, ph, onInput) => {
                        const inp = document.createElement('input');
                        inp.className = 'win98-input';
                        inp.placeholder = ph;
                        inp.value = val != null ? val : '';
                        inp.oninput = () => { onInput(inp.value); setDirty(true); onChange(); };
                        inp.onkeydown = (e) => { if (e.key === 'Enter') commit(); };
                        return inp;
                    };
                    const mkNum = (val, ph, onInput) => {
                        const inp = document.createElement('input');
                        inp.type = 'number'; inp.className = 'win98-input'; inp.placeholder = ph;
                        inp.value = val != null ? val : '';
                        inp.oninput = () => { const n = parseFloat(inp.value); onInput(isNaN(n) ? undefined : n); setDirty(true); onChange(); };
                        inp.onkeydown = (e) => { if (e.key === 'Enter') commit(); };
                        return inp;
                    };
                    row.appendChild(mk(g.label, 'label', v => g.label = v));
                    row.appendChild(mk(g.value, 'value formula', v => g.value = v));
                    row.appendChild(mk(g.max, 'max formula', v => g.max = v));
                    row.appendChild(mkNum(g.x, 'x', v => g.x = v));
                    row.appendChild(mkNum(g.y, 'y', v => g.y = v));
                    row.appendChild(mkNum(g.width, 'w', v => g.width = v));
                    const doneBtn = document.createElement('button');
                    doneBtn.className = 'win98-btn';
                    doneBtn.textContent = '✓';
                    doneBtn.title = 'Done editing';
                    doneBtn.onclick = () => commit();
                    row.appendChild(doneBtn);
                    row.appendChild(makeRowDeleteBtn(() => { layoutObj.gauges.splice(idx, 1); onChange(); commit(); }));
                },
                newItem: () => ({ label: '', value: '0', max: '1', x: 1, y: 1, width: 18 }),
                addLabel: '+ Gauge'
            });
            return box;
        }

        // ---------------------------------------------------------------
        // Dedicated widget: layout.pages / layout.pageFormula
        // ---------------------------------------------------------------
        function buildPageListEditor(layoutObj, onChange) {
            const box = document.createElement('fieldset');
            box.style.cssText = 'padding: 6px;';
            const legend = document.createElement('legend');
            legend.textContent = 'Pages (layout.pages)';
            box.appendChild(legend);

            const note = document.createElement('div');
            note.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin-bottom: 4px;';
            note.textContent = 'Each page overrides any of this window\'s properties (text, contentY, its own gauges, ...) — resolved via pageFormula (e.g. "v.page or 1").';
            box.appendChild(note);

            const formulaRow = document.createElement('div');
            formulaRow.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-bottom: 6px; font-size: 10px;';
            const formulaLbl = document.createElement('span'); formulaLbl.textContent = 'pageFormula'; formulaLbl.style.width = '70px';
            const formulaInp = document.createElement('input');
            formulaInp.className = 'win98-input'; formulaInp.style.flex = '1';
            formulaInp.value = layoutObj.pageFormula || '';
            formulaInp.placeholder = 'v.page or 1';
            formulaInp.oninput = () => { layoutObj.pageFormula = formulaInp.value; setDirty(true); };
            formulaRow.appendChild(formulaLbl); formulaRow.appendChild(formulaInp);
            box.appendChild(formulaRow);

            layoutObj.pages = layoutObj.pages || [];
            buildRowListEditor(box, layoutObj.pages, {
                columns: [{ label: 'Page', flex: '1' }, { label: 'Text', flex: '2' }],
                summary: (page, idx) => ['Page ' + (idx + 1), (page.text || '(no text)').replace(/\s+/g, ' ').slice(0, 40)],
                editor: (row, page, idx, commit) => {
                    row.style.cssText = 'display: flex; flex-direction: column; gap: 4px; font-size: 10px;';

                    const textLbl = document.createElement('div');
                    textLbl.textContent = 'text:';
                    row.appendChild(textLbl);
                    const textArea = document.createElement('textarea');
                    textArea.className = 'win98-input';
                    textArea.style.cssText = 'width: 100%; height: 60px; font-family: monospace; font-size: 10px; box-sizing: border-box; resize: vertical;';
                    textArea.value = page.text || '';
                    textArea.oninput = () => { page.text = textArea.value; setDirty(true); };
                    row.appendChild(textArea);

                    const grid = document.createElement('div');
                    grid.style.cssText = 'display: grid; grid-template-columns: 70px 70px 70px 70px; gap: 4px; align-items: center; margin-top: 4px;';
                    ['contentX', 'contentY', 'lineSpacing'].forEach(key => {
                        const lbl = document.createElement('span'); lbl.textContent = key;
                        const inp = document.createElement('input');
                        inp.type = 'number'; inp.step = '0.5'; inp.className = 'win98-input';
                        inp.value = page[key] != null ? page[key] : '';
                        inp.oninput = () => { const n = parseFloat(inp.value); if (!isNaN(n)) { page[key] = n; setDirty(true); onChange(); } };
                        grid.appendChild(lbl); grid.appendChild(inp);
                    });
                    row.appendChild(grid);

                    row.appendChild(buildGaugeListEditor(page, onChange));

                    const btnRow = document.createElement('div');
                    btnRow.style.cssText = 'display: flex; gap: 4px; justify-content: flex-end;';
                    const doneBtn = document.createElement('button');
                    doneBtn.className = 'win98-btn';
                    doneBtn.textContent = '✓ Done';
                    doneBtn.onclick = () => commit();
                    btnRow.appendChild(doneBtn);
                    btnRow.appendChild(makeRowDeleteBtn(() => { layoutObj.pages.splice(idx, 1); onChange(); commit(); }));
                    row.appendChild(btnRow);
                },
                newItem: () => {
                    layoutObj.pageFormula = layoutObj.pageFormula || 'v.page or 1';
                    formulaInp.value = layoutObj.pageFormula;
                    return { text: '' };
                },
                addLabel: '+ Page'
            });
            return box;
        }
