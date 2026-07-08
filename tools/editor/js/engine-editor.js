
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
            note.textContent = 'Registered types appear in effect dropdowns and pass validation. The id must match a handler in engine/effects.lua — new ids need a matching Lua handler to do anything.';
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
            note.textContent = 'Registered codes appear in trait dropdowns and pass validation. Codes are read by engine/traits.lua and engine feature code — new codes need engine support to have an effect.';
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
                buildRecursiveForm(panel, {
                    ui: dbPayload.system.ui,
                    physics: dbPayload.system.physics,
                    battle_screen: dbPayload.system.battle_screen
                }, [], dbPayload.system);
                buildRecursiveForm(panel, { battleLayout: dbPayload.engine.battleLayout }, [], dbPayload.engine);
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
                header.textContent = 'Flows & Scenes';
                dbPayload.flows = dbPayload.flows || {};
                dbPayload.scenes = dbPayload.scenes || [];
                renderFlowsAndScenesContainer(panel, header);
            }
        }

        let activeFlowsSubTab = 'phases'; // 'phases' or 'scenes'
        let activeSceneId = null;

        function renderFlowsAndScenesContainer(panel, header) {
            panel.innerHTML = '';
            
            const subTabs = document.createElement('div');
            subTabs.style.cssText = 'display: flex; gap: 4px; margin-bottom: 12px; border-bottom: 2px solid var(--win-shadow); padding-bottom: 4px;';
            
            const btnPhases = document.createElement('button');
            btnPhases.className = 'db-tab-btn' + (activeFlowsSubTab === 'phases' ? ' active' : '');
            btnPhases.textContent = 'Phase Flows';
            btnPhases.onclick = () => {
                activeFlowsSubTab = 'phases';
                renderFlowsAndScenesContainer(panel, header);
            };
            
            const btnScenes = document.createElement('button');
            btnScenes.className = 'db-tab-btn' + (activeFlowsSubTab === 'scenes' ? ' active' : '');
            btnScenes.textContent = 'Custom Scenes';
            btnScenes.onclick = () => {
                activeFlowsSubTab = 'scenes';
                renderFlowsAndScenesContainer(panel, header);
            };
            
            subTabs.appendChild(btnPhases);
            subTabs.appendChild(btnScenes);
            panel.appendChild(subTabs);
            
            if (activeFlowsSubTab === 'phases') {
                header.textContent = 'Phase Flows';
                renderFlowsTab(panel, header);
            } else {
                header.textContent = 'Custom Scenes';
                renderScenesSection(panel, header);
            }
        }

        function renderScenesSection(panel, header) {
            dbPayload.scenes = dbPayload.scenes || [];
            
            const mainContainer = document.createElement('div');
            mainContainer.style.cssText = 'display: flex; gap: 8px; height: 350px; overflow: hidden;';
            
            const listCol = document.createElement('div');
            listCol.style.cssText = 'width: 140px; border-right: 1px solid var(--win-shadow); padding-right: 6px; display: flex; flex-direction: column; gap: 4px;';
            
            const listBox = makeListBox();
            listBox.style.flex = '1';
            
            const renderList = () => {
                listBox.innerHTML = '';
                dbPayload.scenes.forEach((sc) => {
                    const row = document.createElement('div');
                    row.className = 'tree-node-header' + (sc.id === activeSceneId ? ' active' : '');
                    row.style.cssText = 'padding: 4px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; font-size: 11px;';
                    
                    const spanName = document.createElement('span');
                    spanName.textContent = `[${sc.id}] ${sc.name}`;
                    row.appendChild(spanName);
                    
                    const delBtn = makeRowDeleteBtn(() => {
                        dbPayload.scenes = dbPayload.scenes.filter(s => s.id !== sc.id);
                        if (activeSceneId === sc.id) activeSceneId = null;
                        setDirty(true);
                        renderScenesSection(panel, header);
                    });
                    row.appendChild(delBtn);
                    
                    row.onclick = (e) => {
                        if (e.target.tagName === 'BUTTON') return;
                        activeSceneId = sc.id;
                        renderScenesSection(panel, header);
                    };
                    listBox.appendChild(row);
                });
            };
            renderList();
            listCol.appendChild(listBox);
            
            const addBtn = makeAddRowBtn('+ Create Scene', () => {
                const nextId = dbPayload.scenes.reduce((max, s) => Math.max(max, s.id), 0) + 1;
                const newScene = {
                    id: nextId,
                    name: 'New Scene',
                    kind: 'crafting',
                    config: {
                        disciplines: [
                            { kind: 'blacksmithing', label: 'Blacksmithing', stat: 'atk', description: '' }
                        ],
                        alpha: 0.5,
                        yieldFormula: 'floor((i1.meta.potency + i2.meta.potency) / 2) + floor(alpha * S)',
                        penaltyFormula: '0',
                        anomalyFormula: '1.0',
                        brackets: [
                            { max: 10, tier: 0, name: 'Junk' },
                            { max: 25, tier: 1, name: 'Standard' }
                        ],
                        timing: { initialDelay: 0.05, maxDelay: 0.4, delayMult: 1.25, steps: 12 },
                        terms: { title: 'Item Creation', yieldText: 'Expected Yield: {0}', resultText: 'Crafted: {0}!' }
                    }
                };
                dbPayload.scenes.push(newScene);
                activeSceneId = nextId;
                setDirty(true);
                renderScenesSection(panel, header);
            });
            listCol.appendChild(addBtn);
            mainContainer.appendChild(listCol);
            
            const configCol = document.createElement('div');
            configCol.style.cssText = 'flex: 1; overflow-y: auto; padding-left: 4px; display: flex; flex-direction: column; gap: 8px;';
            
            if (activeSceneId === null && dbPayload.scenes.length > 0) {
                activeSceneId = dbPayload.scenes[0].id;
            }
            
            const activeScene = dbPayload.scenes.find(s => s.id === activeSceneId);
            if (activeScene) {
                activeScene.config = activeScene.config || {};
                
                const createField = (labelVal, value, onChange, type = 'text', helpType = null) => {
                    const row = document.createElement('div');
                    row.className = 'form-group field-inline';
                    const lbl = document.createElement('label');
                    lbl.textContent = labelVal;
                    row.appendChild(lbl);
                    
                    const input = document.createElement('input');
                    input.className = 'win98-input';
                    input.style.flex = '1';
                    input.value = value !== undefined ? value : '';
                    input.type = type;
                    input.oninput = () => {
                        onChange(type === 'number' ? parseFloat(input.value) || 0 : input.value);
                        setDirty(true);
                    };
                    row.appendChild(input);
                    
                    if (helpType) {
                        const btnHelp = document.createElement('button');
                        btnHelp.className = 'win98-btn';
                        btnHelp.style.cssText = 'min-width: 18px; width: 18px; height: 18px; margin-left: 4px; padding: 0; font-weight: bold;';
                        btnHelp.textContent = 'ⓘ';
                        btnHelp.onclick = (e) => {
                            e.preventDefault();
                            showParamHelpPopover(btnHelp, helpType);
                        };
                        row.appendChild(btnHelp);
                    }
                    configCol.appendChild(row);
                };
                
                createField('Scene Name:', activeScene.name, (v) => {
                    activeScene.name = v;
                    renderList();
                });
                
                const kindRow = document.createElement('div');
                kindRow.className = 'form-group field-inline';
                const kindLbl = document.createElement('label');
                kindLbl.textContent = 'Scene Kind:';
                kindRow.appendChild(kindLbl);
                const kindSelect = makeSelect(['crafting'], activeScene.kind || 'crafting', (v) => {
                    activeScene.kind = v;
                    setDirty(true);
                });
                kindSelect.style.flex = '1';
                kindRow.appendChild(kindSelect);
                configCol.appendChild(kindRow);
                
                createField('Alpha Coefficient:', activeScene.config.alpha, (v) => { activeScene.config.alpha = v; }, 'number');
                createField('Yield Formula:', activeScene.config.yieldFormula, (v) => { activeScene.config.yieldFormula = v; }, 'text', 'formula');
                createField('Penalty Formula:', activeScene.config.penaltyFormula, (v) => { activeScene.config.penaltyFormula = v; }, 'text', 'formula');
                createField('Anomaly Formula:', activeScene.config.anomalyFormula, (v) => { activeScene.config.anomalyFormula = v; }, 'text', 'formula');
                
                const timingTitle = document.createElement('div');
                timingTitle.style.cssText = 'font-weight: bold; margin-top: 8px; margin-bottom: 4px; border-bottom: 1px solid var(--win-shadow);';
                timingTitle.textContent = 'Timing Configuration';
                configCol.appendChild(timingTitle);
                
                activeScene.config.timing = activeScene.config.timing || { initialDelay: 0.05, maxDelay: 0.4, delayMult: 1.25, steps: 12 };
                createField('Initial Delay (s):', activeScene.config.timing.initialDelay, (v) => { activeScene.config.timing.initialDelay = v; }, 'number');
                createField('Max Delay (s):', activeScene.config.timing.maxDelay, (v) => { activeScene.config.timing.maxDelay = v; }, 'number');
                createField('Delay Multiplier:', activeScene.config.timing.delayMult, (v) => { activeScene.config.timing.delayMult = v; }, 'number');
                createField('Total Steps:', activeScene.config.timing.steps, (v) => { activeScene.config.timing.steps = v; }, 'number');
                
                const discTitle = document.createElement('div');
                discTitle.style.cssText = 'font-weight: bold; margin-top: 8px; margin-bottom: 4px; border-bottom: 1px solid var(--win-shadow);';
                discTitle.textContent = 'Disciplines';
                configCol.appendChild(discTitle);
                
                const discBox = makeListBox();
                const renderDiscs = () => {
                    discBox.innerHTML = '';
                    activeScene.config.disciplines = activeScene.config.disciplines || [];
                    activeScene.config.disciplines.forEach((disc, dIdx) => {
                        const row = document.createElement('div');
                        row.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-bottom: 4px;';
                        
                        const inputKind = document.createElement('input');
                        inputKind.className = 'win98-input';
                        inputKind.style.width = '70px';
                        inputKind.placeholder = 'kind';
                        inputKind.value = disc.kind || '';
                        inputKind.oninput = () => { disc.kind = inputKind.value; setDirty(true); };
                        row.appendChild(inputKind);
                        
                        const inputLabel = document.createElement('input');
                        inputLabel.className = 'win98-input';
                        inputLabel.style.width = '70px';
                        inputLabel.placeholder = 'label';
                        inputLabel.value = disc.label || '';
                        inputLabel.oninput = () => { disc.label = inputLabel.value; setDirty(true); };
                        row.appendChild(inputLabel);
                        
                        const selectStat = makeSelect(['atk', 'def', 'mat', 'mdf', 'maxHp', 'asp', 'mpd', 'level'], disc.stat || 'atk', (v) => {
                            disc.stat = v;
                            setDirty(true);
                        });
                        selectStat.style.width = '60px';
                        selectStat.style.height = '19px';
                        row.appendChild(selectStat);
                        
                        const inputDesc = document.createElement('input');
                        inputDesc.className = 'win98-input';
                        inputDesc.style.flex = '1';
                        inputDesc.placeholder = 'description';
                        inputDesc.value = disc.description || '';
                        inputDesc.oninput = () => { disc.description = inputDesc.value; setDirty(true); };
                        row.appendChild(inputDesc);
                        
                        row.appendChild(makeRowDeleteBtn(() => {
                            activeScene.config.disciplines.splice(dIdx, 1);
                            setDirty(true);
                            renderDiscs();
                        }));
                        discBox.appendChild(row);
                    });
                    
                    discBox.appendChild(makeAddRowBtn('+ Add Discipline', () => {
                        activeScene.config.disciplines.push({ kind: 'new_discipline', label: 'New', stat: 'atk', description: '' });
                        setDirty(true);
                        renderDiscs();
                    }));
                };
                renderDiscs();
                configCol.appendChild(discBox);
                
                const brTitle = document.createElement('div');
                brTitle.style.cssText = 'font-weight: bold; margin-top: 8px; margin-bottom: 4px; border-bottom: 1px solid var(--win-shadow);';
                brTitle.textContent = 'Outcome Brackets';
                configCol.appendChild(brTitle);
                
                const brBox = makeListBox();
                const renderBrackets = () => {
                    brBox.innerHTML = '';
                    activeScene.config.brackets = activeScene.config.brackets || [];
                    activeScene.config.brackets.forEach((br, bIdx) => {
                        const row = document.createElement('div');
                        row.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-bottom: 4px;';
                        
                        const inputMax = document.createElement('input');
                        inputMax.type = 'number';
                        inputMax.className = 'win98-input';
                        inputMax.style.width = '60px';
                        inputMax.placeholder = 'max Y';
                        inputMax.value = br.max !== undefined ? br.max : 0;
                        inputMax.oninput = () => { br.max = parseInt(inputMax.value) || 0; setDirty(true); };
                        row.appendChild(inputMax);
                        
                        const inputTier = document.createElement('input');
                        inputTier.type = 'number';
                        inputTier.className = 'win98-input';
                        inputTier.style.width = '50px';
                        inputTier.placeholder = 'tier';
                        inputTier.value = br.tier !== undefined ? br.tier : 0;
                        inputTier.oninput = () => { br.tier = parseInt(inputTier.value) || 0; setDirty(true); };
                        row.appendChild(inputTier);
                        
                        const inputName = document.createElement('input');
                        inputName.className = 'win98-input';
                        inputName.style.flex = '1';
                        inputName.placeholder = 'bracket name';
                        inputName.value = br.name || '';
                        inputName.oninput = () => { br.name = inputName.value; setDirty(true); };
                        row.appendChild(inputName);
                        
                        row.appendChild(makeRowDeleteBtn(() => {
                            activeScene.config.brackets.splice(bIdx, 1);
                            setDirty(true);
                            renderBrackets();
                        }));
                        brBox.appendChild(row);
                    });
                    
                    brBox.appendChild(makeAddRowBtn('+ Add Bracket', () => {
                        activeScene.config.brackets.push({ max: 50, tier: 1, name: 'New Bracket' });
                        setDirty(true);
                        renderBrackets();
                    }));
                };
                renderBrackets();
                configCol.appendChild(brBox);
                
                const termsTitle = document.createElement('div');
                termsTitle.style.cssText = 'font-weight: bold; margin-top: 8px; margin-bottom: 4px; border-bottom: 1px solid var(--win-shadow);';
                termsTitle.textContent = 'Terms / Text Keys';
                configCol.appendChild(termsTitle);
                
                activeScene.config.terms = activeScene.config.terms || {};
                const termKeys = ['title', 'selectDiscipline', 'selectCrafter', 'selectIngredients', 'yieldText', 'anomalyText', 'craftBtn', 'cancelBtn', 'resultText'];
                termKeys.forEach(tKey => {
                    createField(`Text [${tKey}]:`, activeScene.config.terms[tKey], (v) => { activeScene.config.terms[tKey] = v; });
                });
            } else {
                const empty = document.createElement('div');
                empty.style.cssText = 'font-style: italic; color: var(--win-dark-shadow); padding: 20px;';
                empty.textContent = 'No scenes defined. Click "+ Create Scene" to start.';
                configCol.appendChild(empty);
            }
            
            mainContainer.appendChild(configCol);
            panel.appendChild(mainContainer);
        }

        // --- FLOWS TAB (SPEC A6 / S4) ---
        // scene select -> phase select, each phase badged "has data" (overrides
        // the legacy Lua block) or "legacy" (falls back to it, per S4's
        // fallback rule). Editing a phase uses the same registry-driven
        // renderCommandList as map/common events, with hostCtx 'battle_phase'
        // so the palette only offers non-interactive commands valid there.
        let activeFlowScene = 'battle';
        let activeFlowPhase = null;

        // v1 phase names (SPEC S4); union'd with whatever's actually present so
        // a future phase added directly to flows.json still shows up.
        const KNOWN_PHASES_BY_SCENE = {
            battle: ['encounter_check', 'battle_start', 'round_end', 'flee_attempt', 'victory', 'defeat', 'escaped']
        };

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

        function renderFlowsTab(panel, header) {
            const scenes = flowScenes();
            if (!scenes.includes(activeFlowScene)) activeFlowScene = scenes[0];

            const sceneRow = document.createElement('div');
            sceneRow.style.cssText = 'display: flex; gap: 6px; align-items: center; margin-bottom: 8px;';
            const sceneLabel = document.createElement('label');
            sceneLabel.textContent = 'Scene:';
            sceneRow.appendChild(sceneLabel);
            const sceneSelect = makeSelect(scenes, activeFlowScene, (v) => {
                activeFlowScene = v;
                activeFlowPhase = null;
                setEngineTab('flows');
            }, null);
            sceneRow.appendChild(sceneSelect);
            panel.appendChild(sceneRow);

            const phases = flowPhasesForScene(activeFlowScene);
            if (!activeFlowPhase || !phases.includes(activeFlowPhase)) activeFlowPhase = phases[0];

            const phaseTabs = document.createElement('div');
            phaseTabs.style.cssText = 'display: flex; gap: 4px; flex-wrap: wrap; margin-bottom: 8px; border-bottom: 2px solid var(--win-shadow); padding-bottom: 4px;';
            phases.forEach(phase => {
                const hasData = !!((dbPayload.flows[activeFlowScene] || {})[phase]);
                const btn = document.createElement('button');
                btn.className = 'db-tab-btn' + (phase === activeFlowPhase ? ' active' : '');
                btn.style.fontSize = '10px';
                btn.textContent = phase + (hasData ? ' [has data]' : ' [legacy]');
                btn.onclick = () => { activeFlowPhase = phase; setEngineTab('flows'); };
                phaseTabs.appendChild(btn);
            });
            panel.appendChild(phaseTabs);

            if (!activeFlowPhase) return;

            dbPayload.flows[activeFlowScene] = dbPayload.flows[activeFlowScene] || {};
            const hasData = !!dbPayload.flows[activeFlowScene][activeFlowPhase];

            const infoRow = document.createElement('div');
            infoRow.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin-bottom: 6px;';
            infoRow.textContent = hasData
                ? 'This phase has data and overrides the legacy Lua block.'
                : 'This phase has no data yet — the engine falls back to its legacy Lua block (S4). Create an override to edit it here.';
            panel.appendChild(infoRow);

            if (!hasData) {
                const activateBtn = document.createElement('button');
                activateBtn.className = 'win98-btn';
                activateBtn.style.cssText = 'margin-bottom: 8px; align-self: flex-start;';
                activateBtn.textContent = '+ Create Override';
                activateBtn.onclick = () => {
                    dbPayload.flows[activeFlowScene][activeFlowPhase] = [];
                    setDirty(true);
                    setEngineTab('flows');
                };
                panel.appendChild(activateBtn);
                return;
            }

            const listBox = document.createElement('div');
            listBox.style.cssText = 'border: 1px solid var(--win-shadow); background: #fff; min-height: 200px; max-height: 320px; overflow-y: auto; padding: 4px; display: flex; flex-direction: column; gap: 2px; font-family: monospace; font-size: 11px;';
            const phaseCommands = dbPayload.flows[activeFlowScene][activeFlowPhase];
            const rerenderPhase = () => { setDirty(true); renderCommandList(listBox, phaseCommands, rerenderPhase, false, 0, 'battle_phase'); };
            renderCommandList(listBox, phaseCommands, rerenderPhase, false, 0, 'battle_phase');
            panel.appendChild(listBox);

            const removeBtn = document.createElement('button');
            removeBtn.className = 'win98-btn';
            removeBtn.style.cssText = 'margin-top: 6px; align-self: flex-start; font-size: 10px;';
            removeBtn.textContent = 'Remove Override (revert to legacy)';
            removeBtn.onclick = () => {
                delete dbPayload.flows[activeFlowScene][activeFlowPhase];
                setDirty(true);
                setEngineTab('flows');
            };
            panel.appendChild(removeBtn);

            attachJsonToggle(header, panel, phaseCommands, () => setEngineTab('flows'));
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
