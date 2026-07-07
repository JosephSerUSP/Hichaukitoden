
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

                buildTabbedSections(panel, [
                    { id: 'combat', label: 'Combat', render: p => buildRecursiveForm(p, dbPayload.system.combat, ['combat'], dbPayload.system) },
                    { id: 'elementRules', label: 'Element Rules', render: p => buildRecursiveForm(p, dbPayload.engine.elementRules, ['elementRules'], dbPayload.engine) }
                ]);

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

                buildTabbedSections(panel, [
                    { id: 'ui', label: 'UI', render: p => buildRecursiveForm(p, dbPayload.system.ui, ['ui'], dbPayload.system) },
                    { id: 'physics', label: 'Physics', render: p => buildRecursiveForm(p, dbPayload.system.physics, ['physics'], dbPayload.system) },
                    { id: 'battle_screen', label: 'Battle Screen', render: p => buildRecursiveForm(p, dbPayload.system.battle_screen, ['battle_screen'], dbPayload.system) },
                    { id: 'battleLayout', label: 'Battle Layout', render: p => buildRecursiveForm(p, dbPayload.engine.battleLayout, ['battleLayout'], dbPayload.engine) }
                ]);

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
            }
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
