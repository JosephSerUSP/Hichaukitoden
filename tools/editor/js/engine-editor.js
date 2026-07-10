
        // --- SYSTEM CONFIG ---
        function initSystemTab() {
            // Managed inside form loading dynamically
        }

        function buildBattleScreenPreview(container) {
            const header = document.createElement('div');
            header.style.fontSize = '12px';
            header.style.fontWeight = 'bold';
            header.style.marginBottom = '8px';
            header.style.color = 'var(--win-dark-shadow)';
            header.textContent = 'Battle Screen Live Tester';
            container.appendChild(header);

            const launchBtn = document.createElement('button');
            launchBtn.className = 'win98-btn';
            launchBtn.style.padding = '8px 16px';
            launchBtn.style.fontWeight = 'bold';
            launchBtn.style.alignSelf = 'start';
            launchBtn.style.marginTop = '4px';
            launchBtn.innerHTML = '<span class="icon-sprite icon-play" style="margin-right: 6px;"></span> Launch Test Battle';
            container.appendChild(launchBtn);

            launchBtn.onclick = () => {
                fetch('/play-test-battle', { method: 'POST' })
                    .then(res => res.json())
                    .then(data => {
                        console.log('Launched test battle successfully.');
                    })
                    .catch(err => console.error('Failed to launch test battle:', err));
            };

            const popupBtn = document.createElement('button');
            popupBtn.className = 'win98-btn';
            popupBtn.style.padding = '8px 16px';
            popupBtn.style.alignSelf = 'start';
            popupBtn.style.marginTop = '4px';
            popupBtn.textContent = 'Damage Popup Settings...';
            popupBtn.onclick = () => openDamagePopupModal();
            container.appendChild(popupBtn);
        }

        // --- ENGINE EDITOR MODAL ---
        // Engine-level behavior, kept apart from game content in the Database:
        // battle flow, growth curves, dungeon generation, rendering layout, and
        // the effect-type / trait-code registries that drive editor dropdowns
        // and validation.
        let activeEngineTab = 'battleflow';
        let engineModalSnapshot = null;

        function engineSnapshotStr() {
            return JSON.stringify({ system: dbPayload.system, engine: dbPayload.engine });
        }

        function openEngineModal() {
            if (!dbPayload.system) dbPayload.system = {};
            if (!dbPayload.engine) dbPayload.engine = {};
            engineModalSnapshot = engineSnapshotStr();
            document.getElementById('engine-modal').classList.add('active');
            setEngineTab(activeEngineTab);
        }

        function closeEngineModal(force) {
            if (!force && engineModalSnapshot !== null && engineSnapshotStr() !== engineModalSnapshot) {
                if (!confirmDiscard('You have unsaved engine changes. Discard them and close?')) return;
                const snap = JSON.parse(engineModalSnapshot);
                dbPayload.system = snap.system;
                dbPayload.engine = snap.engine;
                setDirty(false);
            }
            engineModalSnapshot = null;
            document.getElementById('engine-modal').classList.remove('active');
        }

        function buildEffectTypeRegistryEditor(panel) {
            dbPayload.engine.effectTypes = dbPayload.engine.effectTypes || [];
            const list = dbPayload.engine.effectTypes;
            const note = document.createElement('p');
            note.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin: 0 0 8px;';
            note.textContent = 'Registered types appear in effect dropdowns and pass validation. The id must match a handler in engine/effects.lua  Enew ids need a matching Lua handler to do anything.';
            panel.appendChild(note);

            const box = makeListBox();
            const render = () => {
                box.innerHTML = '';
                list.forEach((et, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                    const mk = (val, ph, width, onInput) => {
                        const input = document.createElement('input');
                        input.className = 'win98-input';
                        input.placeholder = ph;
                        input.title = ph;
                        if (width) { input.style.width = width; } else { input.style.flex = '1'; }
                        input.value = val;
                        input.oninput = () => { onInput(input.value); setDirty(true); };
                        return input;
                    };
                    row.appendChild(mk(et.id || '', 'id (Lua handler)', '110px', v => { et.id = v; }));
                    row.appendChild(mk(et.label || '', 'Label', '110px', v => { et.label = v; }));
                    row.appendChild(mk((et.params || []).join(', '), 'params (csv)', '120px', v => {
                        et.params = v.split(',').map(s => s.trim()).filter(s => s !== '');
                    }));
                    row.appendChild(mk(et.description || '', 'Description', null, v => { et.description = v; }));
                    row.appendChild(makeRowDeleteBtn(() => { list.splice(idx, 1); render(); }));
                    box.appendChild(row);
                });
                box.appendChild(makeAddRowBtn('+ Add Effect Type', () => {
                    list.push({ id: 'new_effect', label: 'New Effect', params: ['value'], description: '' });
                    render();
                }));
            };
            render();
            panel.appendChild(box);
        }

        function buildTraitCodeRegistryEditor(panel) {
            dbPayload.engine.traitCodes = dbPayload.engine.traitCodes || [];
            const list = dbPayload.engine.traitCodes;
            const note = document.createElement('p');
            note.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin: 0 0 8px;';
            note.textContent = 'Registered codes appear in trait dropdowns and pass validation. Codes are read by engine/traits.lua and engine feature code  Enew codes need engine support to have an effect.';
            panel.appendChild(note);

            const box = makeListBox();
            const render = () => {
                box.innerHTML = '';
                list.forEach((tc, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                    const mk = (val, ph, width, onInput) => {
                        const input = document.createElement('input');
                        input.className = 'win98-input';
                        input.placeholder = ph;
                        input.title = ph;
                        if (width) { input.style.width = width; } else { input.style.flex = '1'; }
                        input.value = val;
                        input.oninput = () => { onInput(input.value); setDirty(true); };
                        return input;
                    };
                    row.appendChild(mk(tc.code || '', 'CODE', '150px', v => { tc.code = v; }));
                    row.appendChild(mk(tc.label || '', 'Label', '110px', v => { tc.label = v; }));
                    const chkWrap = document.createElement('label');
                    chkWrap.style.cssText = 'font-size: 10px; display: flex; align-items: center; gap: 3px;';
                    const chk = document.createElement('input');
                    chk.type = 'checkbox';
                    chk.checked = !!tc.usesDataId;
                    chk.onchange = () => { tc.usesDataId = chk.checked; setDirty(true); };
                    chkWrap.appendChild(chk);
                    chkWrap.appendChild(document.createTextNode('dataId'));
                    row.appendChild(chkWrap);
                    row.appendChild(mk(tc.description || '', 'Description', null, v => { tc.description = v; }));
                    row.appendChild(makeRowDeleteBtn(() => { list.splice(idx, 1); render(); }));
                    box.appendChild(row);
                });
                box.appendChild(makeAddRowBtn('+ Add Trait Code', () => {
                    list.push({ code: 'NEW_CODE', label: 'New Trait', usesDataId: false, description: '' });
                    render();
                }));
            };
            render();
            panel.appendChild(box);
        }

        function buildMetaKeyRegistryEditor(panel) {
            dbPayload.engine.metaKeys = dbPayload.engine.metaKeys || [];
            const list = dbPayload.engine.metaKeys;
            const note = document.createElement('p');
            note.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin: 0 0 8px;';
            note.textContent = 'Registered metadata keys can be attached to database entries and read in formulas. appliesTo lists collections (e.g. items, actors). types: number, string, flag.';
            panel.appendChild(note);

            const box = makeListBox();
            const render = () => {
                box.innerHTML = '';
                list.forEach((mkEntry, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                    const mkInput = (val, ph, width, onInput) => {
                        const input = document.createElement('input');
                        input.className = 'win98-input';
                        input.placeholder = ph;
                        input.title = ph;
                        if (width) { input.style.width = width; } else { input.style.flex = '1'; }
                        input.value = val;
                        input.oninput = () => { onInput(input.value); setDirty(true); };
                        return input;
                    };
                    
                    row.appendChild(mkInput(mkEntry.key || '', 'key name', '110px', v => { mkEntry.key = v; }));
                    
                    const typeSelect = makeSelect(['number', 'string', 'flag'], mkEntry.type || 'number', v => {
                        mkEntry.type = v;
                        setDirty(true);
                    });
                    typeSelect.style.width = '80px';
                    typeSelect.style.height = '19px';
                    typeSelect.style.fontSize = '11px';
                    row.appendChild(typeSelect);
                    
                    row.appendChild(mkInput((mkEntry.appliesTo || []).join(', '), 'appliesTo (csv)', '120px', v => {
                        mkEntry.appliesTo = v.split(',').map(s => s.trim()).filter(s => s !== '');
                    }));
                    
                    row.appendChild(mkInput(mkEntry.description || '', 'Description', null, v => { mkEntry.description = v; }));
                    row.appendChild(makeRowDeleteBtn(() => { list.splice(idx, 1); render(); }));
                    row.style.marginBottom = '2px';
                    box.appendChild(row);
                });
                box.appendChild(makeAddRowBtn('+ Add Meta Key', () => {
                    list.push({ key: 'new_meta_key', type: 'number', appliesTo: ['items'], description: '' });
                    render();
                }));
            };
            render();
            panel.appendChild(box);
        }

        function setEngineTab(tabName) {
            activeEngineTab = tabName;
            document.querySelectorAll('#engine-tabs .db-tab-btn').forEach(b => b.classList.remove('active'));
            const tabBtn = document.getElementById(`engine-tab-${tabName}`);
            if (tabBtn) tabBtn.classList.add('active');

            const panel = document.getElementById('engine-form-panel');
            panel.innerHTML = '';
            const header = document.createElement('div');
            header.style.cssText = 'font-weight: bold; font-size: 12px; margin-bottom: 12px; border-bottom: 1px solid var(--win-shadow); padding-bottom: 4px;';
            panel.appendChild(header);
            const rerender = () => setEngineTab(tabName);

            if (tabName === 'battleflow') {
                header.textContent = 'Battle Flow';
                dbPayload.system.combat = dbPayload.system.combat || {};
                dbPayload.engine.elementRules = dbPayload.engine.elementRules || {};
                buildRecursiveForm(panel, { combat: dbPayload.system.combat }, [], dbPayload.system);
                buildRecursiveForm(panel, { elementRules: dbPayload.engine.elementRules }, [], dbPayload.engine);
                attachJsonToggle(header, panel, dbPayload.system.combat, rerender);
            } else if (tabName === 'progression') {
                header.textContent = 'Progression & Growth';
                dbPayload.system.growth = dbPayload.system.growth || {};
                buildRecursiveForm(panel, { growth: dbPayload.system.growth }, [], dbPayload.system);
                attachJsonToggle(header, panel, dbPayload.system.growth, rerender);
            } else if (tabName === 'dungeon') {
                header.textContent = 'Map & Dungeon Generation';
                dbPayload.system.dungeon = dbPayload.system.dungeon || {};
                buildRecursiveForm(panel, { dungeon: dbPayload.system.dungeon }, [], dbPayload.system);
                attachJsonToggle(header, panel, dbPayload.system.dungeon, rerender);
            } else if (tabName === 'rendering') {
                header.textContent = 'Rendering & Menus';
                dbPayload.system.ui = dbPayload.system.ui || {};
                dbPayload.system.physics = dbPayload.system.physics || {};
                dbPayload.system.battle_screen = dbPayload.system.battle_screen || {};
                dbPayload.engine.battleLayout = dbPayload.engine.battleLayout || {};
                dbPayload.engine.windowLayout = dbPayload.engine.windowLayout || {};
                buildRecursiveForm(panel, {
                    ui: dbPayload.system.ui,
                    physics: dbPayload.system.physics,
                    battle_screen: dbPayload.system.battle_screen
                }, [], dbPayload.system);
                buildRecursiveForm(panel, { battleLayout: dbPayload.engine.battleLayout, windowLayout: dbPayload.engine.windowLayout }, [], dbPayload.engine);
                buildBattleScreenPreview(panel);
                attachJsonToggle(header, panel, dbPayload.engine.battleLayout, rerender);
            } else if (tabName === 'effectTypes') {
                header.textContent = 'Effect Type Registry';
                buildEffectTypeRegistryEditor(panel);
                attachJsonToggle(header, panel, dbPayload.engine.effectTypes, rerender);
            } else if (tabName === 'traitCodes') {
                header.textContent = 'Trait Code Registry';
                buildTraitCodeRegistryEditor(panel);
                attachJsonToggle(header, panel, dbPayload.engine.traitCodes, rerender);
            } else if (tabName === 'metaKeys') {
                header.textContent = 'Meta Keys Registry';
                buildMetaKeyRegistryEditor(panel);
                attachJsonToggle(header, panel, dbPayload.engine.metaKeys, rerender);
            } else if (tabName === 'flows') {
                header.textContent = 'Scenes';
                dbPayload.flows = dbPayload.flows || {};
                dbPayload.scenes = dbPayload.scenes || [];
                renderUnifiedFlowsEditor(panel, header);
            }
        }

        // --- UNIFIED FLOWS EDITOR (D5) ---
        // Collapses the old "Phase Flows" / "Custom Scenes" sub-tab split into a
        // single tab. Left sidebar lists all scene entities  Ethe built-in "battle"
        // flow + each custom scene from data/scenes.json. Selecting one shows its
        // phases (battle phases / scene hooks) as tabs, each editable via the same
        // renderCommandList used by map/common events. Scene hooks use hostCtx
        // 'scene' so the command palette filters to commands whose registry
        // contexts include "scene" (or "any"). Each phase/hook gets a { } JSON
        // toggle. Custom scenes also show a compact config property panel.
        let activeSceneId = null;          // numeric scene id (custom scenes) or 'battle'
        let activeUnifiedPhase = null;     // current phase/hook name

        // v1 battle phase names (SPEC S4); union'd with whatever's actually present.
        const KNOWN_PHASES_BY_SCENE = {
            battle: ['encounter_check', 'battle_start', 'round_end', 'flee_attempt', 'victory', 'defeat', 'escaped']
        };

        // Hook names expected on custom scenes (from engine/scene_host.lua).
        const SCENE_HOOK_NAMES = ['on_enter', 'on_select', 'on_cancel', 'on_up', 'on_down', 'on_left', 'on_right', 'on_frame'];

        function flowScenes() {
            const scenes = Object.keys(dbPayload.flows || {}).filter(k => k !== '_test');
            return scenes.length ? scenes : ['battle'];
        }

        function flowPhasesForScene(scene) {
            const known = KNOWN_PHASES_BY_SCENE[scene] || [];
            const existing = Object.keys((dbPayload.flows || {})[scene] || {});
            const seen = {};
            const out = [];
            known.concat(existing).forEach(p => { if (!seen[p]) { seen[p] = true; out.push(p); } });
            return out;
        }

        function renderUnifiedFlowsEditor(panel, header) {
            panel.innerHTML = '';

            const mainContainer = document.createElement('div');
            mainContainer.style.cssText = 'display: flex; gap: 8px; overflow: hidden; flex: 1; min-height: 350px;';

            // --- Left sidebar: scene list ---
            const listCol = document.createElement('div');
            listCol.style.cssText = 'width: 140px; border-right: 1px solid var(--win-shadow); padding-right: 6px; display: flex; flex-direction: column; gap: 4px; flex-shrink: 0;';

            const listBox = makeListBox();
            listBox.style.flex = '1';

            function unifiedSceneId(sc) {
                // 'battle' for the built-in flow, or the numeric id for custom scenes
                return sc === 'battle' ? 'battle' : sc.id;
            }

            function sceneLabel(sc) {
                if (sc === 'battle') return '⚔︁EBattle';
                return '🛠 ' + (sc.name || 'Unnamed');
            }

            function isBattleSelected() { return activeSceneId === 'battle'; }
            function getSelectedScene() {
                if (activeSceneId === 'battle') return null;
                return dbPayload.scenes.find(s => s.id === activeSceneId);
            }

            const renderSceneList = () => {
                listBox.innerHTML = '';

                // 1) Battle flow (always first)
                const battleRow = document.createElement('div');
                battleRow.className = 'tree-node-header' + (activeSceneId === 'battle' ? ' active' : '');
                battleRow.style.cssText = 'padding: 4px; cursor: pointer; display: flex; align-items: center; font-size: 11px;';
                battleRow.textContent = '⚔︁EBattle';
                battleRow.onclick = () => {
                    activeSceneId = 'battle';
                    activeUnifiedPhase = null;
                    renderUnifiedFlowsEditor(panel, header);
                };
                listBox.appendChild(battleRow);

                // 2) Custom scenes
                dbPayload.scenes.forEach(sc => {
                    const row = document.createElement('div');
                    row.className = 'tree-node-header' + (sc.id === activeSceneId ? ' active' : '');
                    row.style.cssText = 'padding: 4px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; font-size: 11px;';

                    const spanName = document.createElement('span');
                    spanName.textContent = '🛠 ' + (sc.name || 'Unnamed');
                    row.appendChild(spanName);

                    const delBtn = makeRowDeleteBtn(() => {
                        dbPayload.scenes = dbPayload.scenes.filter(s => s.id !== sc.id);
                        if (activeSceneId === sc.id) activeSceneId = 'battle';
                        setDirty(true);
                        renderUnifiedFlowsEditor(panel, header);
                    });
                    row.appendChild(delBtn);

                    row.onclick = (e) => {
                        if (e.target.tagName === 'BUTTON') return;
                        activeSceneId = sc.id;
                        activeUnifiedPhase = null;
                        renderUnifiedFlowsEditor(panel, header);
                    };
                    listBox.appendChild(row);
                });
            };
            renderSceneList();
            listCol.appendChild(listBox);

            // E4: "+ Create Scene" opens a template gallery built from
            // tools/editor/templates/scenes/*.json (served read-only by
            // /api/templates/scenes). Choosing one deep-clones the template,
            // strips its _template metadata and assigns a fresh numeric id.
            const instantiateTemplate = (tpl) => {
                // Numeric ids only: built-in scenes have string ids ('title',
                // 'battle', ...) which would turn Math.max into NaN.
                const nextId = dbPayload.scenes.reduce((max, s) => typeof s.id === 'number' ? Math.max(max, s.id) : max, 0) + 1;
                const newScene = JSON.parse(JSON.stringify(tpl));
                delete newScene._template;
                newScene.id = nextId;
                dbPayload.scenes.push(newScene);
                activeSceneId = nextId;
                activeUnifiedPhase = null;
                setDirty(true);
                renderUnifiedFlowsEditor(panel, header);
            };

            const openTemplateGallery = (templates) => {
                const overlay = document.createElement('div');
                overlay.id = 'scene-template-gallery';
                overlay.style.cssText = 'position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,0.3);display:flex;align-items:center;justify-content:center;';
                const box = document.createElement('div');
                box.style.cssText = 'min-width:320px;max-width:460px;max-height:70vh;overflow-y:auto;padding:8px;'
                    + 'background:var(--win-gray);border:2px solid;'
                    + 'border-color:var(--win-white) var(--win-shadow) var(--win-shadow) var(--win-white);';
                const title = document.createElement('div');
                title.textContent = 'Create Scene — choose a template';
                title.style.cssText = 'font-weight:bold;margin-bottom:6px;';
                box.appendChild(title);
                templates.forEach(tpl => {
                    const meta = tpl._template || {};
                    const row = document.createElement('div');
                    row.style.cssText = 'padding:6px;cursor:pointer;border:1px solid var(--win-shadow);margin-bottom:4px;background:var(--win-white);';
                    const lbl = document.createElement('div');
                    lbl.textContent = meta.label || tpl.name || 'Unnamed template';
                    lbl.style.fontWeight = 'bold';
                    const desc = document.createElement('div');
                    desc.textContent = meta.description || '';
                    desc.style.cssText = 'font-size:10px;color:var(--win-dark-shadow);margin-top:2px;';
                    row.appendChild(lbl);
                    row.appendChild(desc);
                    row.onmouseover = () => { row.style.background = '#000080'; lbl.style.color = 'white'; desc.style.color = '#c0c0c0'; };
                    row.onmouseout = () => { row.style.background = 'var(--win-white)'; lbl.style.color = ''; desc.style.color = 'var(--win-dark-shadow)'; };
                    row.onclick = () => { overlay.remove(); instantiateTemplate(tpl); };
                    box.appendChild(row);
                });
                const cancel = document.createElement('button');
                cancel.className = 'win98-btn';
                cancel.textContent = 'Cancel';
                cancel.style.marginTop = '4px';
                cancel.onclick = () => overlay.remove();
                box.appendChild(cancel);
                overlay.onclick = (e) => { if (e.target === overlay) overlay.remove(); };
                overlay.appendChild(box);
                document.body.appendChild(overlay);
            };

            const addBtn = makeAddRowBtn('+ Create Scene', async () => {
                try {
                    const res = await fetch(`${API_URL}/api/templates/scenes`);
                    if (!res.ok) throw new Error('HTTP ' + res.status);
                    const templates = await res.json();
                    if (!templates.length) throw new Error('no templates found');
                    openTemplateGallery(templates);
                } catch (err) {
                    showToast('Failed to load scene templates: ' + err.message);
                }
            });
            listCol.appendChild(addBtn);
            mainContainer.appendChild(listCol);

            // --- Right side: editor panel ---
            const editorCol = document.createElement('div');
            editorCol.style.cssText = 'flex: 1; overflow-y: auto; padding-left: 4px; display: flex; flex-direction: column; gap: 6px; min-width: 0;';

            if (activeSceneId === null) {
                // Default: select first scene, or battle
                if (dbPayload.scenes.length > 0) {
                    activeSceneId = dbPayload.scenes[0].id;
                } else {
                    activeSceneId = 'battle';
                }
                renderUnifiedFlowsEditor(panel, header);
                return;
            }

            if (activeSceneId === 'battle') {
                renderBattleFlowsEditor(editorCol, header);
            } else {
                const scene = getSelectedScene();
                if (scene) {
                    renderCustomSceneEditor(editorCol, header, scene);
                } else {
                    // Scene was deleted, fall back to battle
                    activeSceneId = 'battle';
                    renderUnifiedFlowsEditor(panel, header);
                    return;
                }
            }

            mainContainer.appendChild(editorCol);
            panel.appendChild(mainContainer);
        }

        // Edits a battle flow scene: phase tabs, each editing via
        // renderCommandList with hostCtx 'battle_phase'.
        function renderBattleFlowsEditor(container, header) {
            const scenes = flowScenes();
            // We only show 'battle' here since that's the only flow scene selected
            // via the sidebar; but if other flow scenes exist, a dropdown could be added.

            const phases = flowPhasesForScene('battle');
            if (!activeUnifiedPhase || !phases.includes(activeUnifiedPhase)) {
                activeUnifiedPhase = phases[0];
            }

            // Phase tabs
            const phaseTabs = document.createElement('div');
            phaseTabs.style.cssText = 'display: flex; gap: 4px; flex-wrap: wrap; margin-bottom: 6px; border-bottom: 2px solid var(--win-shadow); padding-bottom: 4px;';
            phases.forEach(phase => {
                const hasData = !!((dbPayload.flows['battle'] || {})[phase]);
                const btn = document.createElement('button');
                btn.className = 'db-tab-btn' + (phase === activeUnifiedPhase ? ' active' : '');
                btn.style.fontSize = '10px';
                btn.textContent = phase + (hasData ? ' [has data]' : ' [legacy]');
                btn.onclick = () => { activeUnifiedPhase = phase; renderUnifiedFlowsEditor(container.parentElement.parentElement, header); };
                phaseTabs.appendChild(btn);
            });
            container.appendChild(phaseTabs);

            if (!activeUnifiedPhase) return;

            dbPayload.flows['battle'] = dbPayload.flows['battle'] || {};
            const hasData = !!dbPayload.flows['battle'][activeUnifiedPhase];

            const infoRow = document.createElement('div');
            infoRow.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin-bottom: 4px;';
            infoRow.textContent = hasData
                ? 'This phase has data and overrides the legacy Lua block.'
                : 'This phase has no data yet  Ethe engine falls back to its legacy Lua block (S4). Create an override to edit it here.';
            container.appendChild(infoRow);

            if (!hasData) {
                const activateBtn = document.createElement('button');
                activateBtn.className = 'win98-btn';
                activateBtn.style.cssText = 'margin-bottom: 8px; align-self: flex-start; font-size: 10px;';
                activateBtn.textContent = '+ Create Override';
                activateBtn.onclick = () => {
                    dbPayload.flows['battle'][activeUnifiedPhase] = [];
                    setDirty(true);
                    renderUnifiedFlowsEditor(container.parentElement.parentElement, header);
                };
                container.appendChild(activateBtn);
                return;
            }

            const phaseCommands = dbPayload.flows['battle'][activeUnifiedPhase];
            const listBox = document.createElement('div');
            listBox.style.cssText = 'border: 1px solid var(--win-shadow); background: #fff; min-height: 180px; max-height: 280px; overflow-y: auto; padding: 4px; display: flex; flex-direction: column; gap: 2px; font-family: monospace; font-size: 11px;';
            const rerenderPhase = () => {
                setDirty(true);
                renderCommandList(listBox, phaseCommands, rerenderPhase, false, 0, 'battle_phase');
            };
            renderCommandList(listBox, phaseCommands, rerenderPhase, false, 0, 'battle_phase');
            container.appendChild(listBox);

            // Bottom row: remove override + JSON toggle
            const bottomRow = document.createElement('div');
            bottomRow.style.cssText = 'display: flex; gap: 6px; align-items: center; margin-top: 4px; flex-wrap: wrap;';

            const removeBtn = document.createElement('button');
            removeBtn.className = 'win98-btn';
            removeBtn.style.cssText = 'font-size: 10px;';
            removeBtn.textContent = 'Remove Override (revert to legacy)';
            removeBtn.onclick = () => {
                delete dbPayload.flows['battle'][activeUnifiedPhase];
                setDirty(true);
                renderUnifiedFlowsEditor(container.parentElement.parentElement, header);
            };
            bottomRow.appendChild(removeBtn);

            // JSON toggle for the phase commands
            const jsonBtn = document.createElement('button');
            jsonBtn.className = 'win98-btn';
            jsonBtn.style.cssText = 'font-size: 10px; font-family: monospace;';
            jsonBtn.textContent = '{ } JSON';
            jsonBtn.onclick = () => {
                // Show JSON editor for this phase's commands
                const panel = container;
                const prevInner = panel.innerHTML;
                panel.innerHTML = '';
                const backBtn = document.createElement('button');
                backBtn.className = 'win98-btn';
                backBtn.style.cssText = 'margin-bottom: 6px; font-size: 10px;';
                backBtn.textContent = 'ↁEBack to Form';
                backBtn.onclick = () => { renderUnifiedFlowsEditor(container.parentElement.parentElement, header); };
                panel.appendChild(backBtn);

                const jsonContainer = document.createElement('div');
                jsonContainer.className = 'form-control inset-bevel';
                jsonContainer.style.cssText = 'position: relative; height: 320px; background: #fff; overflow: hidden; padding: 0; box-sizing: border-box;';

                const pre = document.createElement('pre');
                pre.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; margin: 0; padding: 4px; box-sizing: border-box; overflow: hidden; font-family: monospace; font-size: 11px; white-space: pre; pointer-events: none; color: black; z-index: 0;';

                const area = document.createElement('textarea');
                area.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; margin: 0; padding: 4px; box-sizing: border-box; font-family: monospace; font-size: 11px; white-space: pre; background: transparent; color: transparent; caret-color: black; border: none; outline: none; resize: none; overflow: auto; z-index: 1;';
                area.spellcheck = false;
                area.value = JSON.stringify(phaseCommands, null, 2);

                const syntaxHighlight = (jsonStr) => {
                    let escaped = jsonStr.replace(/&/g, '&').replace(/</g, '<').replace(/>/g, '>');
                    return escaped.replace(/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g, function (match) {
                        let cls = 'color: #000;';
                        if (/^"/.test(match)) {
                            if (/:$/.test(match)) cls = 'color: #880000;';
                            else cls = 'color: #008800;';
                        } else if (/true|false/.test(match)) cls = 'color: #0000ff;';
                        else if (/null/.test(match)) cls = 'color: #888888; font-style: italic;';
                        else cls = 'color: #ff8800;';
                        return '<span style="' + cls + '">' + match + '</span>';
                    });
                };

                const updateHighlight = () => {
                    let html = syntaxHighlight(area.value);
                    if (html.endsWith('\n')) html += ' ';
                    pre.innerHTML = html;
                };

                area.onscroll = () => { pre.scrollTop = area.scrollTop; pre.scrollLeft = area.scrollLeft; };
                area.oninput = () => {
                    updateHighlight();
                    try { JSON.parse(area.value); jsonContainer.style.backgroundColor = '#fff'; }
                    catch (e) { jsonContainer.style.backgroundColor = '#ffcccc'; }
                };
                updateHighlight();
                jsonContainer.appendChild(pre);
                jsonContainer.appendChild(area);

                const applyBtn = document.createElement('button');
                applyBtn.className = 'win98-btn win98-btn-success';
                applyBtn.style.cssText = 'margin-top: 6px;';
                applyBtn.textContent = 'Apply JSON';
                applyBtn.onclick = () => {
                    let parsed;
                    try { parsed = JSON.parse(area.value); }
                    catch (e) { jsonContainer.style.backgroundColor = '#ffcccc'; return; }
                    if (Array.isArray(parsed)) {
                        dbPayload.flows['battle'][activeUnifiedPhase] = parsed;
                        setDirty(true);
                        renderUnifiedFlowsEditor(container.parentElement.parentElement, header);
                    } else {
                        jsonContainer.style.backgroundColor = '#ffcccc';
                    }
                };

                panel.appendChild(jsonContainer);
                panel.appendChild(applyBtn);
            };
            bottomRow.appendChild(jsonBtn);
            container.appendChild(bottomRow);
        }

        // Edits a custom scene: compact config panel + hook tabs with
        // renderCommandList(hostCtx='scene').
        function renderCustomSceneEditor(container, header, scene) {
            scene.config = scene.config || {};
            scene.hooks = scene.hooks || {};

            // --- Compact config panel (collapsible) ---
            const configToggle = document.createElement('div');
            configToggle.style.cssText = 'font-weight: bold; font-size: 11px; cursor: pointer; padding: 2px 4px; background: var(--win-gray); border: 1px solid var(--win-shadow); user-select: none;';
            configToggle.textContent = '[–] Scene Properties';
            container.appendChild(configToggle);

            const configBody = document.createElement('div');
            configBody.style.cssText = 'padding: 4px 8px; border: 1px solid var(--win-shadow); border-top: none; margin-bottom: 6px;';

            configToggle.onclick = () => {
                if (configBody.style.display === 'none') {
                    configBody.style.display = 'block';
                    configToggle.textContent = '[–] Scene Properties';
                } else {
                    configBody.style.display = 'none';
                    configToggle.textContent = '[+] Scene Properties';
                }
            };

            // Name
            const nameRow = document.createElement('div');
            nameRow.className = 'form-group field-inline';
            nameRow.style.marginBottom = '4px';
            const nameLbl = document.createElement('label');
            nameLbl.style.flex = '0 0 80px';
            nameLbl.textContent = 'Name:';
            nameRow.appendChild(nameLbl);
            const nameInput = document.createElement('input');
            nameInput.className = 'win98-input';
            nameInput.style.flex = '1';
            nameInput.value = scene.name || '';
            nameInput.oninput = () => { scene.name = nameInput.value; setDirty(true); renderUnifiedFlowsEditor(container.parentElement.parentElement, header); };
            nameRow.appendChild(nameInput);
            configBody.appendChild(nameRow);

            // Kind
            const kindRow = document.createElement('div');
            kindRow.className = 'form-group field-inline';
            kindRow.style.marginBottom = '4px';
            const kindLbl = document.createElement('label');
            kindLbl.style.flex = '0 0 80px';
            kindLbl.textContent = 'Kind:';
            kindRow.appendChild(kindLbl);
            // Kinds with an engine host. 'menu' is the plain default (SPEC S2);
            // scene-specific kinds like 'crafting' are being dissolved (D13) but
            // an off-list value already on the scene must stay editable.
            const kindOptions = ['menu', 'battle'];
            if (scene.kind && !kindOptions.includes(scene.kind)) kindOptions.unshift(scene.kind);
            const kindSelect = makeSelect(kindOptions, scene.kind || 'menu', (v) => {
                scene.kind = v;
                setDirty(true);
            });
            kindSelect.style.flex = '1';
            kindRow.appendChild(kindSelect);
            configBody.appendChild(kindRow);

            // Generic config editor (D13): scene config is an arbitrary
            // property bag, edited as JSON — no kind-specific field forms.
            const configArea = document.createElement('textarea');
            configArea.className = 'win98-input';
            configArea.spellcheck = false;
            configArea.style.cssText = 'width: 100%; height: 120px; font-family: monospace; font-size: 10px; box-sizing: border-box; resize: vertical;';
            configArea.value = JSON.stringify(scene.config, null, 2);
            configArea.oninput = () => {
                try {
                    const parsed = JSON.parse(configArea.value);
                    configArea.style.backgroundColor = '';
                    scene.config = parsed;
                    setDirty(true);
                } catch (e) {
                    configArea.style.backgroundColor = '#ffcccc';
                }
            };
            configBody.appendChild(configArea);

            container.appendChild(configBody);

            // --- Hook tabs ---
            const hookNames = SCENE_HOOK_NAMES;
            if (!activeUnifiedPhase || !hookNames.includes(activeUnifiedPhase)) {
                activeUnifiedPhase = hookNames[0];
            }

            const hookTabs = document.createElement('div');
            hookTabs.style.cssText = 'display: flex; gap: 4px; flex-wrap: wrap; margin-bottom: 6px; border-bottom: 2px solid var(--win-shadow); padding-bottom: 4px;';
            hookNames.forEach(hook => {
                const hasData = !!(scene.hooks[hook] && scene.hooks[hook].length > 0);
                const btn = document.createElement('button');
                btn.className = 'db-tab-btn' + (hook === activeUnifiedPhase ? ' active' : '');
                btn.style.fontSize = '10px';
                btn.textContent = hook;
                if (!hasData) {
                    btn.style.color = 'var(--text-empty)';
                }
                btn.onclick = () => { activeUnifiedPhase = hook; renderUnifiedFlowsEditor(container.parentElement.parentElement, header); };
                hookTabs.appendChild(btn);
            });
            container.appendChild(hookTabs);

            if (!activeUnifiedPhase) return;

            // --- Hook editor ---
            scene.hooks[activeUnifiedPhase] = scene.hooks[activeUnifiedPhase] || [];
            const hookCommands = scene.hooks[activeUnifiedPhase];

            // Info text
            const infoText = document.createElement('div');
            infoText.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin-bottom: 4px;';
            infoText.textContent = 'Editing hook: ' + activeUnifiedPhase + '  Ecommands run when this scene event fires.';
            container.appendChild(infoText);

            const listBox = document.createElement('div');
            listBox.style.cssText = 'border: 1px solid var(--win-shadow); background: #fff; min-height: 180px; max-height: 280px; overflow-y: auto; padding: 4px; display: flex; flex-direction: column; gap: 2px; font-family: monospace; font-size: 11px;';
            const rerenderHook = () => {
                setDirty(true);
                renderCommandList(listBox, hookCommands, rerenderHook, false, 0, 'scene');
            };
            renderCommandList(listBox, hookCommands, rerenderHook, false, 0, 'scene');
            container.appendChild(listBox);

            // Bottom row: clear + JSON toggle
            const bottomRow = document.createElement('div');
            bottomRow.style.cssText = 'display: flex; gap: 6px; align-items: center; margin-top: 4px; flex-wrap: wrap;';

            const clearBtn = document.createElement('button');
            clearBtn.className = 'win98-btn';
            clearBtn.style.cssText = 'font-size: 10px;';
            clearBtn.textContent = 'Clear Hook';
            clearBtn.onclick = () => {
                scene.hooks[activeUnifiedPhase] = [];
                setDirty(true);
                renderUnifiedFlowsEditor(container.parentElement.parentElement, header);
            };
            bottomRow.appendChild(clearBtn);

            // JSON toggle for the hook commands
            const jsonBtn = document.createElement('button');
            jsonBtn.className = 'win98-btn';
            jsonBtn.style.cssText = 'font-size: 10px; font-family: monospace;';
            jsonBtn.textContent = '{ } JSON';
            jsonBtn.onclick = (function(hookCmds) {
                return function() {
                    const panel = container;
                    const prevInner = panel.innerHTML;
                    panel.innerHTML = '';
                    const backBtn = document.createElement('button');
                    backBtn.className = 'win98-btn';
                    backBtn.style.cssText = 'margin-bottom: 6px; font-size: 10px;';
                    backBtn.textContent = 'ↁEBack to Form';
                    backBtn.onclick = () => { renderUnifiedFlowsEditor(container.parentElement.parentElement, header); };
                    panel.appendChild(backBtn);

                    const jsonContainer = document.createElement('div');
                    jsonContainer.className = 'form-control inset-bevel';
                    jsonContainer.style.cssText = 'position: relative; height: 320px; background: #fff; overflow: hidden; padding: 0; box-sizing: border-box;';

                    const pre = document.createElement('pre');
                    pre.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; margin: 0; padding: 4px; box-sizing: border-box; overflow: hidden; font-family: monospace; font-size: 11px; white-space: pre; pointer-events: none; color: black; z-index: 0;';

                    const area = document.createElement('textarea');
                    area.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; margin: 0; padding: 4px; box-sizing: border-box; font-family: monospace; font-size: 11px; white-space: pre; background: transparent; color: transparent; caret-color: black; border: none; outline: none; resize: none; overflow: auto; z-index: 1;';
                    area.spellcheck = false;
                    area.value = JSON.stringify(hookCmds, null, 2);

                    const syntaxHighlight = (jsonStr) => {
                        let escaped = jsonStr.replace(/&/g, '&').replace(/</g, '<').replace(/>/g, '>');
                        return escaped.replace(/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g, function (match) {
                            let cls = 'color: #000;';
                            if (/^"/.test(match)) {
                                if (/:$/.test(match)) cls = 'color: #880000;';
                                else cls = 'color: #008800;';
                            } else if (/true|false/.test(match)) cls = 'color: #0000ff;';
                            else if (/null/.test(match)) cls = 'color: #888888; font-style: italic;';
                            else cls = 'color: #ff8800;';
                            return '<span style="' + cls + '">' + match + '</span>';
                        });
                    };

                    const updateHighlight = () => {
                        let html = syntaxHighlight(area.value);
                        if (html.endsWith('\n')) html += ' ';
                        pre.innerHTML = html;
                    };

                    area.onscroll = () => { pre.scrollTop = area.scrollTop; pre.scrollLeft = area.scrollLeft; };
                    area.oninput = () => {
                        updateHighlight();
                        try { JSON.parse(area.value); jsonContainer.style.backgroundColor = '#fff'; }
                        catch (e) { jsonContainer.style.backgroundColor = '#ffcccc'; }
                    };
                    updateHighlight();
                    jsonContainer.appendChild(pre);
                    jsonContainer.appendChild(area);

                    const applyBtn = document.createElement('button');
                    applyBtn.className = 'win98-btn win98-btn-success';
                    applyBtn.style.cssText = 'margin-top: 6px;';
                    applyBtn.textContent = 'Apply JSON';
                    applyBtn.onclick = () => {
                        let parsed;
                        try { parsed = JSON.parse(area.value); }
                        catch (e) { jsonContainer.style.backgroundColor = '#ffcccc'; return; }
                        if (Array.isArray(parsed)) {
                            scene.hooks[activeUnifiedPhase] = parsed;
                            setDirty(true);
                            renderUnifiedFlowsEditor(container.parentElement.parentElement, header);
                        } else {
                            jsonContainer.style.backgroundColor = '#ffcccc';
                        }
                    };

                    panel.appendChild(jsonContainer);
                    panel.appendChild(applyBtn);
                };
            })(hookCommands);
            bottomRow.appendChild(jsonBtn);
            container.appendChild(bottomRow);
        }

        // --- DAMAGE POPUP SETTINGS MODAL (physics + battle_screen config) ---
        let damagePopupSnapshot = null;

        function damagePopupConfigSnapshot() {
            return JSON.stringify({
                physics: dbPayload.system.physics || {},
                battle_screen: dbPayload.system.battle_screen || {}
            });
        }

        function openDamagePopupModal() {
            if (!dbPayload.system) dbPayload.system = {};
            damagePopupSnapshot = damagePopupConfigSnapshot();

            const container = document.getElementById('damage-popup-form');
            container.innerHTML = '';
            const cfg = {
                physics: dbPayload.system.physics || {},
                battle_screen: dbPayload.system.battle_screen || {}
            };
            buildRecursiveForm(container, cfg, [], dbPayload.system);
            document.getElementById('damage-popup-modal').classList.add('active');
        }

        function closeDamagePopupModal(force) {
            if (!force && damagePopupSnapshot !== null && damagePopupConfigSnapshot() !== damagePopupSnapshot) {
                if (!confirmDiscard('Discard changes to Damage Popup settings?')) return;
                const snap = JSON.parse(damagePopupSnapshot);
                dbPayload.system.physics = snap.physics;
                dbPayload.system.battle_screen = snap.battle_screen;
            }
            damagePopupSnapshot = null;
            document.getElementById('damage-popup-modal').classList.remove('active');
        }


