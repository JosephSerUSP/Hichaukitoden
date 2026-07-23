
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
                fetch(`${API_URL}/play-test-battle`, { method: 'POST' })
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
        const engineModalSnapshotHelper = window.createSnapshotModal({
            getSnapshotSource: () => ({ system: dbPayload.system, engine: dbPayload.engine }),
            onRestore: (snap) => {
                dbPayload.system = snap.system;
                dbPayload.engine = snap.engine;
                setDirty(false);
            },
            confirmMessage: 'You have unsaved engine changes. Discard them and close?'
        });

        function openEngineModal() {
            if (!dbPayload.system) dbPayload.system = {};
            if (!dbPayload.engine) dbPayload.engine = {};
            engineModalSnapshotHelper.capture();
            document.getElementById('engine-modal').classList.add('active');
            setEngineTab(activeEngineTab);
        }

        function closeEngineModal(force) {
            if (!engineModalSnapshotHelper.close(force)) return;
            document.getElementById('engine-modal').classList.remove('active');
        }

        // Shared row-rendering skeleton for the Effect Type / Trait Code /
        // Meta Key registry editors below: each list row is a set of small
        // fields (built by textField/csvField/checkboxField/selectField)
        // plus a delete button, with an "add row" button at the bottom.
        function buildRegistryRows(box, list, fields, newEntryFactory, addLabel) {
            const render = () => {
                box.innerHTML = '';
                list.forEach((entry, idx) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';
                    fields.forEach(f => row.appendChild(f(entry)));
                    row.appendChild(makeRowDeleteBtn(() => { list.splice(idx, 1); render(); }));
                    box.appendChild(row);
                });
                box.appendChild(makeAddRowBtn(addLabel, () => {
                    list.push(newEntryFactory());
                    render();
                }));
            };
            render();
        }

        function registryTextField(key, placeholder, width) {
            return (entry) => {
                const input = document.createElement('input');
                input.className = 'win98-input';
                input.placeholder = placeholder;
                input.title = placeholder;
                if (width) { input.style.width = width; } else { input.style.flex = '1'; }
                input.value = entry[key] || '';
                input.oninput = () => { entry[key] = input.value; setDirty(true); };
                return input;
            };
        }

        function registryCsvField(key, placeholder, width) {
            return (entry) => {
                const input = document.createElement('input');
                input.className = 'win98-input';
                input.placeholder = placeholder;
                input.title = placeholder;
                if (width) { input.style.width = width; } else { input.style.flex = '1'; }
                input.value = (entry[key] || []).join(', ');
                input.oninput = () => {
                    entry[key] = input.value.split(',').map(s => s.trim()).filter(s => s !== '');
                    setDirty(true);
                };
                return input;
            };
        }

        function registryCheckboxField(key, labelText) {
            return (entry) => {
                const wrap = document.createElement('label');
                wrap.style.cssText = 'font-size: 10px; display: flex; align-items: center; gap: 3px;';
                const chk = document.createElement('input');
                chk.type = 'checkbox';
                chk.checked = !!entry[key];
                chk.onchange = () => { entry[key] = chk.checked; setDirty(true); };
                wrap.appendChild(chk);
                wrap.appendChild(document.createTextNode(labelText));
                return wrap;
            };
        }

        function registrySelectField(key, options, width) {
            return (entry) => {
                const sel = makeSelect(options, entry[key] || options[0], v => { entry[key] = v; });
                sel.style.width = width || '80px';
                sel.style.height = '19px';
                sel.style.fontSize = '11px';
                return sel;
            };
        }

        function buildEffectTypeRegistryEditor(panel) {
            dbPayload.engine.effectTypes = dbPayload.engine.effectTypes || [];
            const list = dbPayload.engine.effectTypes;
            const note = document.createElement('p');
            note.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin: 0 0 8px;';
            note.textContent = 'Registered types appear in effect dropdowns and pass validation. The id must match a handler in engine/effects.lua  Enew ids need a matching Lua handler to do anything.';
            panel.appendChild(note);

            const box = makeListBox();
            buildRegistryRows(box, list, [
                registryTextField('id', 'id (Lua handler)', '110px'),
                registryTextField('label', 'Label', '110px'),
                registryCsvField('params', 'params (csv)', '120px'),
                registryTextField('description', 'Description', null),
            ], () => ({ id: 'new_effect', label: 'New Effect', params: ['value'], description: '' }), '+ Add Effect Type');
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
            buildRegistryRows(box, list, [
                registryTextField('code', 'CODE', '150px'),
                registryTextField('label', 'Label', '110px'),
                registryCheckboxField('usesDataId', 'dataId'),
                registryTextField('description', 'Description', null),
            ], () => ({ code: 'NEW_CODE', label: 'New Trait', usesDataId: false, description: '' }), '+ Add Trait Code');
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
            buildRegistryRows(box, list, [
                registryTextField('key', 'key name', '110px'),
                registrySelectField('type', ['number', 'string', 'flag'], '80px'),
                registryCsvField('appliesTo', 'appliesTo (csv)', '120px'),
                registryTextField('description', 'Description', null),
            ], () => ({ key: 'new_meta_key', type: 'number', appliesTo: ['items'], description: '' }), '+ Add Meta Key');
            panel.appendChild(box);
        }

        // --- FOG PRESETS (docs/design/fog-presets-and-panorama.md) ---
        // Shared registry: a map's fog can reference a preset by id instead
        // of carrying its own color/density/minFactor/panorama inline, so
        // editing a preset here updates every map using it. Each preset row
        // is a two-line block (base fields + a nested panorama-layer list)
        // rather than a single buildRegistryRows row, since panorama layers
        // are themselves a variable-length list.
        const FOG_BLEND_MODES = ['alpha', 'add', 'multiply', 'screen'];

        function buildFogPanoramaLayers(container, preset, rerenderPreset) {
            preset.panorama = preset.panorama || [];
            const wrap = document.createElement('div');
            wrap.style.cssText = 'margin-top: 4px; padding: 4px; border: 1px solid var(--win-shadow); background: #f4f4f4;';
            const label = document.createElement('div');
            label.style.cssText = 'font-size: 9px; color: var(--win-dark-shadow); margin-bottom: 2px;';
            label.textContent = 'Panorama layers (scrolling images, back to front):';
            wrap.appendChild(label);

            preset.panorama.forEach((layer, idx) => {
                const row = document.createElement('div');
                row.style.cssText = 'display: flex; gap: 3px; align-items: center; margin-top: 2px;';

                const img = document.createElement('input');
                img.className = 'win98-input';
                img.style.cssText = 'width: 90px; font-size: 9px;';
                img.placeholder = 'assets/panorama/<name>';
                img.title = 'Image name under assets/panorama/ (no path, no extension)';
                img.value = layer.image || '';
                img.oninput = () => { layer.image = img.value; setDirty(true); };
                row.appendChild(img);

                const scrollX = document.createElement('input');
                scrollX.type = 'number'; scrollX.step = '0.005';
                scrollX.className = 'win98-input'; scrollX.style.cssText = 'width: 52px; font-size: 9px;';
                scrollX.title = 'Horizontal scroll speed (image widths/sec)';
                scrollX.value = layer.scrollX != null ? layer.scrollX : 0;
                scrollX.oninput = () => { layer.scrollX = parseFloat(scrollX.value) || 0; setDirty(true); };
                row.appendChild(scrollX);

                const scrollY = document.createElement('input');
                scrollY.type = 'number'; scrollY.step = '0.005';
                scrollY.className = 'win98-input'; scrollY.style.cssText = 'width: 52px; font-size: 9px;';
                scrollY.title = 'Vertical scroll speed (image heights/sec)';
                scrollY.value = layer.scrollY != null ? layer.scrollY : 0;
                scrollY.oninput = () => { layer.scrollY = parseFloat(scrollY.value) || 0; setDirty(true); };
                row.appendChild(scrollY);

                row.appendChild(makeSelect(FOG_BLEND_MODES, layer.blendMode || 'alpha', v => { layer.blendMode = v; }, '0'));

                const opacity = document.createElement('input');
                opacity.type = 'number'; opacity.step = '0.05'; opacity.min = '0'; opacity.max = '1';
                opacity.className = 'win98-input'; opacity.style.cssText = 'width: 44px; font-size: 9px;';
                opacity.title = 'Opacity (0-1)';
                opacity.value = layer.opacity != null ? layer.opacity : 1;
                opacity.oninput = () => { layer.opacity = parseFloat(opacity.value); if (isNaN(layer.opacity)) layer.opacity = 1; setDirty(true); };
                row.appendChild(opacity);

                row.appendChild(makeRowDeleteBtn(() => { preset.panorama.splice(idx, 1); rerenderPreset(); }));
                wrap.appendChild(row);
            });

            wrap.appendChild(makeAddRowBtn('+ Add Layer', () => {
                preset.panorama.push({ image: 'fog_001', scrollX: 0.02, scrollY: 0, blendMode: 'alpha', opacity: 1 });
                rerenderPreset();
            }));
            container.appendChild(wrap);
        }

        function buildFogPresetsEditor(panel) {
            dbPayload.engine.fogPresets = dbPayload.engine.fogPresets || [];
            const list = dbPayload.engine.fogPresets;
            const note = document.createElement('p');
            note.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin: 0 0 8px;';
            note.textContent = 'Named fog configs a map can reference (Map Properties → Fog → Preset) instead of carrying its own color/density/panorama — editing a preset here updates every map that references it.';
            panel.appendChild(note);

            const box = makeListBox();

            const render = () => {
                box.innerHTML = '';
                list.forEach((preset, idx) => {
                    const block = document.createElement('div');
                    block.style.cssText = 'border: 1px solid var(--win-shadow); padding: 4px; margin-bottom: 4px; background: #fff;';

                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center;';

                    const id = document.createElement('input');
                    id.className = 'win98-input';
                    id.style.cssText = 'width: 90px; font-size: 10px;';
                    id.placeholder = 'id';
                    id.title = 'Referenced by maps as fog.preset -- must be unique';
                    id.value = preset.id || '';
                    id.oninput = () => { preset.id = id.value; setDirty(true); };
                    row.appendChild(id);

                    const labelInput = document.createElement('input');
                    labelInput.className = 'win98-input';
                    labelInput.style.cssText = 'width: 90px; font-size: 10px;';
                    labelInput.placeholder = 'label';
                    labelInput.value = preset.label || '';
                    labelInput.oninput = () => { preset.label = labelInput.value; setDirty(true); };
                    row.appendChild(labelInput);

                    const color = document.createElement('input');
                    color.type = 'color';
                    color.style.cssText = 'width: 32px; height: 20px;';
                    color.value = rgb01ToHex(preset.color || [0.3, 0.3, 0.35]);
                    color.oninput = () => { preset.color = hexToRgb01(color.value); setDirty(true); };
                    row.appendChild(color);

                    const density = document.createElement('input');
                    density.type = 'number'; density.step = '0.05'; density.min = '0.05';
                    density.className = 'win98-input'; density.style.cssText = 'width: 48px; font-size: 10px;';
                    density.title = 'Density (higher = fades faster)';
                    density.value = preset.density != null ? preset.density : 0.35;
                    density.oninput = () => { preset.density = parseFloat(density.value) || 0.35; setDirty(true); };
                    row.appendChild(density);

                    const minFactor = document.createElement('input');
                    minFactor.type = 'number'; minFactor.step = '0.01'; minFactor.min = '0'; minFactor.max = '1';
                    minFactor.className = 'win98-input'; minFactor.style.cssText = 'width: 48px; font-size: 10px;';
                    minFactor.title = 'Min visibility (0 = fully fogged at distance)';
                    minFactor.value = preset.minFactor != null ? preset.minFactor : 0.12;
                    minFactor.oninput = () => {
                        const v = parseFloat(minFactor.value);
                        preset.minFactor = isNaN(v) ? 0.12 : v;
                        setDirty(true);
                    };
                    row.appendChild(minFactor);

                    row.appendChild(makeRowDeleteBtn(() => { list.splice(idx, 1); render(); }));
                    block.appendChild(row);

                    buildFogPanoramaLayers(block, preset, render);
                    box.appendChild(block);
                });
                box.appendChild(makeAddRowBtn('+ Add Fog Preset', () => {
                    list.push({ id: 'new_preset', label: 'New Preset', color: [0.3, 0.3, 0.35], density: 0.35, minFactor: 0.12 });
                    render();
                }));
            };
            render();
            panel.appendChild(box);
        }

        // --- TILESET ATLAS REGISTRY ---
        // assets/tilesets/*.png + sidecar .json manifests (docs/design/
        // raycaster-tileset-lighting.md) live outside dbPayload entirely --
        // they're static assets shared across every campaign. This editor
        // fetches/saves them through their own endpoints, one atlas at a
        // time, independent of the Database's batched Save Changes.
        let tilesetRegistryCache = null;

        async function fetchTilesetRegistry() {
            const res = await fetch(`${API_URL}/api/tilesets`);
            const result = await res.json();
            tilesetRegistryCache = result.tilesets || [];
            return tilesetRegistryCache;
        }

        async function saveTilesetManifest(t, statusEl) {
            try {
                const res = await fetch(`${API_URL}/api/tilesets/save`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(t)
                });
                const result = await res.json();
                if (statusEl) statusEl.textContent = result.success ? 'Saved ✓' : ('Failed: ' + result.message);
            } catch (err) {
                if (statusEl) statusEl.textContent = 'Failed: ' + err.message;
            }
        }

        function rowNumberOrNull(placeholder, value, onChange) {
            const input = document.createElement('input');
            input.type = 'number';
            input.className = 'win98-input';
            input.style.cssText = 'width: 44px; font-size: 10px;';
            input.placeholder = placeholder;
            input.title = placeholder + ' (blank = none)';
            input.value = value != null ? value : '';
            input.oninput = () => {
                onChange(input.value === '' ? null : (parseInt(input.value) || 0));
                setDirty(true);
            };
            return input;
        }

        async function buildTilesetRegistryEditor(panel) {
            const note = document.createElement('p');
            note.style.cssText = 'font-size: 11px; color: var(--win-dark-shadow); margin: 0 0 12px;';
            note.textContent = 'All tilesets are managed through the Tileset Studio. Configure 64px grid textures, assign row roles (Wall, Door, Sky, Floor, Ceiling), define autotiling edges, and set up semantic tiles with light emitters.';
            panel.appendChild(note);

            const launchBtn = document.createElement('button');
            launchBtn.className = 'win98-btn win98-btn-success';
            launchBtn.style.cssText = 'padding: 6px 16px; font-weight: bold; cursor: pointer;';
            launchBtn.textContent = '🏰 Open Tileset Studio';
            launchBtn.onclick = () => {
                if (typeof window.openTilesetStudioModal === 'function') {
                    window.openTilesetStudioModal();
                }
            };
            panel.appendChild(launchBtn);
        }

        function labeledField(labelText, input) {
            const wrap = document.createElement('div');
            wrap.style.cssText = 'display: flex; flex-direction: column; align-items: flex-start; gap: 1px;';
            const lbl = document.createElement('span');
            lbl.style.cssText = 'font-size: 8px; color: var(--win-dark-shadow);';
            lbl.textContent = labelText;
            wrap.appendChild(lbl);
            wrap.appendChild(input);
            return wrap;
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
            } else if (tabName === 'tileset') {
                header.textContent = 'Tileset Atlases';
                buildTilesetRegistryEditor(panel);
            } else if (tabName === 'fog') {
                header.textContent = 'Fog Presets';
                dbPayload.engine.fogPresets = dbPayload.engine.fogPresets || [];
                buildFogPresetsEditor(panel);
                attachJsonToggle(header, panel, dbPayload.engine.fogPresets, rerender);
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
            } else if (tabName === 'windows') {
                header.textContent = 'Windows';
                renderWindowsTab(panel, header);
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
            battle: ['encounter_check', 'battle_start', 'round_end', 'flee_attempt', 'victory', 'defeat', 'escaped'],
            quest: ['offer', 'complete']
        };

        // Hook names expected on custom scenes (from engine/scene_host.lua).
        const SCENE_HOOK_NAMES = ['on_enter', 'on_select', 'on_cancel', 'on_up', 'on_down', 'on_left', 'on_right', 'on_page', 'on_frame'];

        function flowPhasesForScene(scene) {
            const known = KNOWN_PHASES_BY_SCENE[scene] || [];
            const existing = Object.keys((dbPayload.flows || {})[scene] || {});
            const seen = {};
            const out = [];
            known.concat(existing).forEach(p => { if (!seen[p]) { seen[p] = true; out.push(p); } });
            return out;
        }

        // E4/E3: fetches the read-only scene-template registry served by
        // /api/templates/scenes. Shared by the "+ Create Scene" gallery and
        // the hook editor's "Load from Template..." picker.
        async function fetchSceneTemplates() {
            const res = await fetch(`${API_URL}/api/templates/scenes`);
            if (!res.ok) throw new Error('HTTP ' + res.status);
            return res.json();
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

            function getSelectedScene() {
                if (activeSceneId === 'battle' || activeSceneId === 'quest') return null;
                return dbPayload.scenes.find(s => s.id === activeSceneId);
            }

            const renderSceneList = () => {
                listBox.innerHTML = '';

                // 1) Battle flow (always first)
                const battleRow = document.createElement('div');
                battleRow.className = 'tree-node-header' + (activeSceneId === 'battle' ? ' active' : '');
                battleRow.style.cssText = 'padding: 4px; cursor: pointer; display: flex; align-items: center; font-size: 11px;';
                battleRow.textContent = '⚔ Battle';
                battleRow.onclick = () => {
                    activeSceneId = 'battle';
                    activeUnifiedPhase = null;
                    renderUnifiedFlowsEditor(panel, header);
                };
                listBox.appendChild(battleRow);

                // 1b) Quest flow (second)
                const questRow = document.createElement('div');
                questRow.className = 'tree-node-header' + (activeSceneId === 'quest' ? ' active' : '');
                questRow.style.cssText = 'padding: 4px; cursor: pointer; display: flex; align-items: center; font-size: 11px;';
                questRow.textContent = '📜 Quests';
                questRow.onclick = () => {
                    activeSceneId = 'quest';
                    activeUnifiedPhase = null;
                    renderUnifiedFlowsEditor(panel, header);
                };
                listBox.appendChild(questRow);

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
                // NOTE (E6 recon): maps deliberately do NOT appear here.
                // A scene entry is BEHAVIOR (hooks, rendering rules); maps
                // in maps.json are CONTENT edited in the map workspace.
                // A "Map" scene entry belongs in this list only once the
                // engine map scene-kind exists as data
                // (docs/plans/overhaul-4/future-map-kind.md).
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
                    const templates = await fetchSceneTemplates();
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
                renderFlowSceneEditor(editorCol, header, 'battle', 'battle_phase');
            } else if (activeSceneId === 'quest') {
                renderFlowSceneEditor(editorCol, header, 'quest', 'quest');
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

        // Edits a flow scene: phase tabs, each editing via
        // renderCommandList with hostCtx.
        function renderFlowSceneEditor(container, header, sceneKey, hostCtx) {
            const phases = flowPhasesForScene(sceneKey);
            if (!activeUnifiedPhase || !phases.includes(activeUnifiedPhase)) {
                activeUnifiedPhase = phases[0];
            }

            // Phase tabs
            const phaseTabs = document.createElement('div');
            phaseTabs.style.cssText = 'display: flex; gap: 4px; flex-wrap: wrap; margin-bottom: 6px; border-bottom: 2px solid var(--win-shadow); padding-bottom: 4px;';
            phases.forEach(phase => {
                const hasData = !!((dbPayload.flows[sceneKey] || {})[phase]);
                const btn = document.createElement('button');
                btn.className = 'db-tab-btn' + (phase === activeUnifiedPhase ? ' active' : '');
                btn.style.fontSize = '10px';
                btn.textContent = phase + (hasData ? ' [has data]' : ' [legacy]');
                btn.onclick = () => { activeUnifiedPhase = phase; renderUnifiedFlowsEditor(container.parentElement.parentElement, header); };
                phaseTabs.appendChild(btn);
            });
            container.appendChild(phaseTabs);

            if (!activeUnifiedPhase) return;

            dbPayload.flows[sceneKey] = dbPayload.flows[sceneKey] || {};
            const hasData = !!dbPayload.flows[sceneKey][activeUnifiedPhase];

            const infoRow = document.createElement('div');
            infoRow.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin-bottom: 4px;';
            infoRow.textContent = hasData
                ? 'This phase has data and overrides the legacy/default block.'
                : 'This phase has no data yet. Create an override to edit it here.';
            container.appendChild(infoRow);

            if (!hasData) {
                const activateBtn = document.createElement('button');
                activateBtn.className = 'win98-btn';
                activateBtn.style.cssText = 'margin-bottom: 8px; align-self: flex-start; font-size: 10px;';
                activateBtn.textContent = '+ Create Override';
                activateBtn.onclick = () => {
                    dbPayload.flows[sceneKey][activeUnifiedPhase] = [];
                    setDirty(true);
                    renderUnifiedFlowsEditor(container.parentElement.parentElement, header);
                };
                container.appendChild(activateBtn);
                return;
            }

            const phaseCommands = dbPayload.flows[sceneKey][activeUnifiedPhase];
            const listBox = document.createElement('div');
            listBox.style.cssText = 'border: 1px solid var(--win-shadow); background: #fff; min-height: 180px; max-height: 280px; overflow-y: auto; padding: 4px; display: flex; flex-direction: column; gap: 2px; font-family: monospace; font-size: 11px;';
            const rerenderPhase = () => {
                setDirty(true);
                renderCommandList(listBox, phaseCommands, rerenderPhase, false, 0, hostCtx);
            };
            renderCommandList(listBox, phaseCommands, rerenderPhase, false, 0, hostCtx);
            container.appendChild(listBox);

            // Bottom row: remove override + JSON toggle
            const bottomRow = document.createElement('div');
            bottomRow.style.cssText = 'display: flex; gap: 6px; align-items: center; margin-top: 4px; flex-wrap: wrap;';

            const removeBtn = document.createElement('button');
            removeBtn.className = 'win98-btn';
            removeBtn.style.cssText = 'font-size: 10px;';
            removeBtn.textContent = 'Remove Override';
            removeBtn.onclick = () => {
                delete dbPayload.flows[sceneKey][activeUnifiedPhase];
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
                const panel = container;
                panel.innerHTML = '';
                const backBtn = document.createElement('button');
                backBtn.className = 'win98-btn';
                backBtn.style.cssText = 'margin-bottom: 6px; font-size: 10px;';
                backBtn.textContent = 'Back to Form';
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
                    let escaped = jsonStr.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
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
                        dbPayload.flows[sceneKey][activeUnifiedPhase] = parsed;
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
        // E3: picker over E4's scene-template registry, offering each
        // template's individual hooks (for the hook being edited) or its
        // entire hook set. Pure consumer — the registry schema/loader is E4's.
        function openHookTemplatePicker(templates, hookName, handlers) {
            const overlay = document.createElement('div');
            overlay.id = 'hook-template-picker';
            overlay.style.cssText = 'position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,0.3);display:flex;align-items:center;justify-content:center;';
            const box = document.createElement('div');
            box.style.cssText = 'min-width:340px;max-width:480px;max-height:70vh;overflow-y:auto;padding:8px;'
                + 'background:var(--win-gray);border:2px solid;'
                + 'border-color:var(--win-white) var(--win-shadow) var(--win-shadow) var(--win-white);';
            const title = document.createElement('div');
            title.textContent = `Load '${hookName}' from a template`;
            title.style.cssText = 'font-weight:bold;margin-bottom:6px;';
            box.appendChild(title);

            const makeRow = (text, sub, action) => {
                const row = document.createElement('div');
                row.style.cssText = 'padding:4px 6px;cursor:pointer;background:var(--win-white);border:1px solid var(--win-shadow);margin-bottom:3px;';
                const main = document.createElement('div');
                main.textContent = text;
                row.appendChild(main);
                if (sub) {
                    const s = document.createElement('div');
                    s.textContent = sub;
                    s.style.cssText = 'font-size:10px;color:var(--win-dark-shadow);';
                    row.appendChild(s);
                }
                row.onmouseover = () => { row.style.background = '#000080'; row.style.color = 'white'; };
                row.onmouseout = () => { row.style.background = 'var(--win-white)'; row.style.color = ''; };
                row.onclick = () => { overlay.remove(); action(); };
                return row;
            };

            templates.forEach(tpl => {
                const meta = tpl._template || {};
                const label = meta.label || tpl.name || 'Unnamed';
                const hooks = tpl.hooks || {};
                const hookNames = Object.keys(hooks).filter(h => (hooks[h] || []).length > 0);
                const head = document.createElement('div');
                head.textContent = label;
                head.style.cssText = 'font-weight:bold;margin:6px 0 3px;';
                box.appendChild(head);
                if (hooks[hookName] && hooks[hookName].length > 0) {
                    box.appendChild(makeRow(
                        `${hookName} (${hooks[hookName].length} commands)`,
                        'Replace only the hook being edited',
                        () => handlers.onHook(`${label} · ${hookName}`, hooks[hookName])
                    ));
                }
                if (hookNames.length > 0) {
                    box.appendChild(makeRow(
                        `Entire hook set (${hookNames.join(', ')})`,
                        'Replace ALL of this scene\'s hooks',
                        () => handlers.onSet(label, hooks)
                    ));
                } else {
                    box.appendChild(makeRow(
                        'Empty hook set',
                        'Clear all hooks (blank template)',
                        () => handlers.onSet(label, {})
                    ));
                }
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
        }

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

            // --- E5: visual preview canvas (headless engine preview) ---
            renderScenePreviewPanel(container, scene, () => renderUnifiedFlowsEditor(container.parentElement.parentElement, header));

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

            // E3: load a hook (or the whole hook set) from E4's template
            // registry. Custom scenes have no legacy fallback to revert to
            // (that path is renderBattleFlowsEditor's "Remove Override",
            // built-in phases only) — templates are their reset source.
            const tplBtn = document.createElement('button');
            tplBtn.className = 'win98-btn';
            tplBtn.style.cssText = 'font-size: 10px;';
            tplBtn.textContent = 'Load from Template...';
            tplBtn.onclick = async () => {
                try {
                    const templates = await fetchSceneTemplates();
                    openHookTemplatePicker(templates, activeUnifiedPhase, {
                        onHook: (label, cmds) => {
                            const cur = scene.hooks[activeUnifiedPhase] || [];
                            if (cur.length > 0 && !confirm(`Replace the current '${activeUnifiedPhase}' hook (${cur.length} command${cur.length === 1 ? '' : 's'}) with "${label}"? This cannot be undone.`)) return;
                            scene.hooks[activeUnifiedPhase] = JSON.parse(JSON.stringify(cmds));
                            setDirty(true);
                            renderUnifiedFlowsEditor(container.parentElement.parentElement, header);
                        },
                        onSet: (label, hooks) => {
                            const nonEmpty = Object.keys(scene.hooks || {}).filter(h => (scene.hooks[h] || []).length > 0);
                            if (nonEmpty.length > 0 && !confirm(`Replace ALL hooks of this scene (${nonEmpty.join(', ')}) with the full "${label}" hook set? This cannot be undone.`)) return;
                            scene.hooks = JSON.parse(JSON.stringify(hooks));
                            setDirty(true);
                            renderUnifiedFlowsEditor(container.parentElement.parentElement, header);
                        }
                    });
                } catch (err) {
                    showToast('Failed to load scene templates: ' + err.message);
                }
            };
            bottomRow.appendChild(tplBtn);

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
        const damagePopupSnapshotHelper = window.createSnapshotModal({
            getSnapshotSource: () => ({
                physics: dbPayload.system.physics || {},
                battle_screen: dbPayload.system.battle_screen || {}
            }),
            onRestore: (snap) => {
                dbPayload.system.physics = snap.physics;
                dbPayload.system.battle_screen = snap.battle_screen;
            },
            confirmMessage: 'Discard changes to Damage Popup settings?'
        });

        function openDamagePopupModal() {
            if (!dbPayload.system) dbPayload.system = {};
            damagePopupSnapshotHelper.capture();

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
            if (!damagePopupSnapshotHelper.close(force)) return;
            document.getElementById('damage-popup-modal').classList.remove('active');
        }


