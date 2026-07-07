
        // --- ASSET PICKER IMPLEMENTATION ---
        let activeAssetCallback = null;
        function openAssetPicker(defaultDir, callback) {
            activeAssetCallback = callback;
            document.getElementById('asset-picker-selected').value = '';

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

        // ---- Config schema: friendly labels + typed widgets for system/engine keys ----
        // Keys not listed fall back to the generic key-name field.
        const CONFIG_SCHEMA = {
            'ui.menuSlideDuration':        { label: 'Menu Slide Duration (s)', step: 0.05, min: 0 },
            'ui.moveTransitionDuration':   { label: 'Move Transition (s)', step: 0.05, min: 0 },
            'ui.inputCooldown':            { label: 'Input Cooldown (s)', step: 0.05, min: 0 },
            'ui.textPalette':              { label: 'Text Palette \\c[n] Colors', widget: 'colorList' },
            'physics.gravity':             { label: 'Popup Gravity (px/s²)', min: 0 },
            'physics.bounceVelocityRetain':{ label: 'Popup Bounce Retention (0-1)', step: 0.05, min: 0, max: 1 },
            'physics.horizontalScatter':   { label: 'Popup Horizontal Scatter (px)', min: 0 },
            'battle_screen.damagePopupLife': { label: 'Damage Popup Lifetime (s)', step: 0.1, min: 0 },
            'battle_screen.popup.damageFormat': { label: 'Damage Popup Format' },
            'battle_screen.popup.healFormat': { label: 'Heal Popup Format' },
            'battle_screen.popup.damageColor': { label: 'Damage Popup Color', widget: 'color' },
            'battle_screen.popup.healColor': { label: 'Heal Popup Color', widget: 'color' },
            'battle_screen.popup.deathFormat': { label: 'Death Popup Format' },
            'battle_screen.popup.deathColor': { label: 'Death Popup Color', widget: 'color' },
            'battle_screen.popup.stateFormat': { label: 'State Popup Format' },
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
            'battleLayout.fallbackY':      { label: 'Popup Fallback Y (px)' }
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
        function renderSchemaField(container, schema, value, key, currentPath, targetRoot, useBlockLayout = false) {
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
                const group = document.createElement('div');
                group.className = useBlockLayout ? 'form-group' : 'form-group field-inline';
                const lbl = document.createElement('label');
                lbl.textContent = schema.label || key;
                group.appendChild(lbl);
                const input = document.createElement('input');
                input.className = 'form-control inset-bevel';
                input.value = value || '';
                input.oninput = () => { setNestedValue(targetRoot, currentPath, key, input.value); setDirty(true); };
                group.appendChild(input);
                const btn = document.createElement('button');
                btn.className = 'win98-btn';
                btn.textContent = '...';
                btn.onclick = () => openAssetPicker(schema.dir || 'sprites', path => {
                    input.value = path;
                    setNestedValue(targetRoot, currentPath, key, path);
                    setDirty(true);
                });
                group.appendChild(btn);
                container.appendChild(group);
                return true;
            }

            if (widget === 'color' && Array.isArray(value)) {
                const group = document.createElement('div');
                group.className = 'form-group';
                const lbl = document.createElement('label');
                lbl.textContent = schema.label || key;
                group.appendChild(lbl);
                const pick = document.createElement('input');
                pick.type = 'color';
                pick.value = rgb01ToHex(value);
                pick.oninput = () => {
                    const rgb = hexToRgb01(pick.value);
                    setNestedValue(targetRoot, currentPath, key, rgb);
                    setDirty(true);
                };
                group.appendChild(pick);
                container.appendChild(group);
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
                const spriteRow = document.createElement('div');
                spriteRow.className = 'form-group field-inline';
                const spriteLbl = document.createElement('label');
                spriteLbl.textContent = 'Default Sprite (inherited)';
                spriteRow.appendChild(spriteLbl);
                const spriteInput = document.createElement('input');
                spriteInput.className = 'form-control inset-bevel';
                spriteInput.value = eventData.sprite || '';
                spriteInput.oninput = () => {
                    if (spriteInput.value === '') { delete eventData.sprite; } else { eventData.sprite = spriteInput.value; }
                    setDirty(true);
                };
                spriteRow.appendChild(spriteInput);
                const spriteBtn = document.createElement('button');
                spriteBtn.className = 'win98-btn';
                spriteBtn.textContent = '...';
                spriteBtn.onclick = () => openAssetPicker('sprites', path => {
                    spriteInput.value = path;
                    eventData.sprite = path;
                    setDirty(true);
                });
                spriteRow.appendChild(spriteBtn);
                formPanel.appendChild(spriteRow);

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
                createFormField(formPanel, 'Name', item.name, val => { item.name = val; initDatabaseEditor(true); });

                const roleGroup = document.createElement('div');
                roleGroup.className = 'form-group field-inline';
                const roleLbl = document.createElement('label');
                roleLbl.textContent = 'Role';
                roleGroup.appendChild(roleLbl);
                roleGroup.appendChild(makeSelect(Object.keys(dbPayload.roles || { Spirit: 1 }), item.role || 'Spirit', v => { item.role = v; }, '1'));
                formPanel.appendChild(roleGroup);

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
                const spriteGroup = document.createElement('div');
                spriteGroup.className = 'form-group field-inline';
                const spriteLbl = document.createElement('label');
                spriteLbl.textContent = 'Sprite Key (assets/portraits)';
                spriteGroup.appendChild(spriteLbl);
                const spriteInput = document.createElement('input');
                spriteInput.className = 'form-control inset-bevel';
                spriteInput.setAttribute('list', 'portrait-keys-list');
                spriteInput.value = item.spriteKey || '';
                spriteInput.oninput = () => { item.spriteKey = spriteInput.value; setDirty(true); };
                spriteGroup.appendChild(spriteInput);
                formPanel.appendChild(spriteGroup);

                buildElementSlotsEditor(formPanel, item);
                createFormField(formPanel, 'Flavor Text', item.flavor || '', val => { item.flavor = val; });

                createCheckboxField(formPanel, 'In starting-party pool (initialParty)', item.initialParty, v => { item.initialParty = v; });
                createCheckboxField(formPanel, 'Recruitable in dungeons (isRecruitable)', item.isRecruitable, v => { item.isRecruitable = v; });

                const twoCol = document.createElement('div');
                twoCol.style.cssText = 'display: grid; grid-template-columns: 1fr 1fr; gap: 10px;';
                const skillsCol = document.createElement('div');
                const passivesCol = document.createElement('div');
                twoCol.appendChild(skillsCol);
                twoCol.appendChild(passivesCol);
                formPanel.appendChild(twoCol);

                buildChecklistField(skillsCol, 'Skills',
                    Object.keys(dbPayload.skills || {}),
                    id => (dbPayload.skills[id] && dbPayload.skills[id].name) || id,
                    () => item.skills, arr => { item.skills = arr; });
                buildChecklistField(passivesCol, 'Passives',
                    Object.keys(dbPayload.passives || {}),
                    id => (dbPayload.passives[id] && dbPayload.passives[id].name) || id,
                    () => item.passives, arr => { item.passives = arr; });

                buildTraitsEditor(formPanel, item, 'Innate Traits');
                buildDropsEditor(formPanel, item);
                buildEvolutionsEditor(formPanel, item);

            } else if (activeDbTab === 'items') {
                createFormField(formPanel, 'Name', item.name, val => { item.name = val; initDatabaseEditor(true); });

                const typeGroup = document.createElement('div');
                typeGroup.className = 'form-group';
                const typeLbl = document.createElement('label');
                typeLbl.textContent = 'Type';
                typeGroup.appendChild(typeLbl);
                typeGroup.appendChild(makeSelect(['consumable', 'equipment', 'quest'], item.type || 'consumable', v => {
                    item.type = v;
                    loadFormForItem(item); // re-render: equipment shows equip fields
                }));
                formPanel.appendChild(typeGroup);

                createFormField(formPanel, 'Description', item.description || '', val => { item.description = val; });

                const attrRow = document.createElement('div');
                attrRow.className = 'form-row';
                createFormField(attrRow, 'Buy Cost (G)', item.cost || 0, val => { item.cost = parseInt(val) || 0; }, 'number');
                createIconField(attrRow, 'Icon', item.icon || 0, val => { item.icon = parseInt(val) || 0; });
                formPanel.appendChild(attrRow);

                if (item.type === 'equipment') {
                    const eqGroup = document.createElement('div');
                    eqGroup.className = 'form-group';
                    const eqLbl = document.createElement('label');
                    eqLbl.textContent = 'Equip Slot';
                    eqGroup.appendChild(eqLbl);
                    eqGroup.appendChild(makeSelect(['Weapon', 'Armor', 'Accessory'], item.equipType || 'Weapon', v => { item.equipType = v; }));
                    formPanel.appendChild(eqGroup);
                    buildTraitsEditor(formPanel, item, 'Equipment Traits');
                } else {
                    const scopeGroup = document.createElement('div');
                    scopeGroup.className = 'form-group';
                    const scopeLbl = document.createElement('label');
                    scopeLbl.textContent = 'Target Scope';
                    scopeGroup.appendChild(scopeLbl);
                    scopeGroup.appendChild(makeSelect(
                        [{ value: '', label: 'Single member' }, { value: 'party', label: 'Whole party' }],
                        item.targetScope || '',
                        v => { if (v === '') { delete item.targetScope; } else { item.targetScope = v; } }));
                    formPanel.appendChild(scopeGroup);
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

                const costRow = document.createElement('div');
                costRow.className = 'form-row';
                createFormField(costRow, 'MP Cost', skill.mpCost || 0, val => { skill.mpCost = parseInt(val) || 0; }, 'number');
                createFormField(costRow, 'Speed Bonus', skill.speed || 0, val => { skill.speed = parseInt(val) || 0; }, 'number');
                formPanel.appendChild(costRow);

                buildEffectsEditor(formPanel, skill);

            } else if (activeDbTab === 'passives') {
                const passive = dbPayload.passives[item.id];
                if (!passive) return;
                createFormField(formPanel, 'Name', passive.name || '', val => { passive.name = val; initDatabaseEditor(true); });
                createFormField(formPanel, 'Description (flavor)', passive.description || '', val => { passive.description = val; });
                createFormField(formPanel, 'Effect Summary (shown in menus)', passive.effect || '', val => { passive.effect = val; });
                createIconField(formPanel, 'Icon', passive.icon || 0, val => { passive.icon = parseInt(val) || 0; });
                createFormField(formPanel, 'Condition (e.g. HP < 50%)', passive.condition || '', val => {
                    if (val === '') { delete passive.condition; } else { passive.condition = val; }
                });
                buildTraitsEditor(formPanel, passive);

            } else if (activeDbTab === 'states') {
                const state = dbPayload.states[item.id];
                if (!state) return;
                createFormField(formPanel, 'Name', state.name || '', val => { state.name = val; initDatabaseEditor(true); });
                const stRow = document.createElement('div');
                stRow.className = 'form-row';
                createIconField(stRow, 'Icon', state.icon || 0, val => { state.icon = parseInt(val) || 0; });
                createFormField(stRow, 'Duration (turns, 9999 = permanent)', state.duration || 3, val => { state.duration = parseInt(val) || 0; }, 'number');
                formPanel.appendChild(stRow);
                createCheckboxField(formPanel, 'Removed when taking damage', state.removeAtDamage, v => {
                    if (v) { state.removeAtDamage = true; } else { delete state.removeAtDamage; }
                });
                buildTraitsEditor(formPanel, state);

            } else if (activeDbTab === 'elements') {
                const elem = dbPayload.elements[item.id];
                if (!elem) return;
                createFormField(formPanel, 'Name', elem.name || item.id, val => { elem.name = val; initDatabaseEditor(true); });
                createIconField(formPanel, 'Orb Icon', elem.icon !== undefined ? elem.icon : 16, val => { elem.icon = parseInt(val) || 0; });

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
                    } else if (key === 'activeFont') {
                        const group = document.createElement('div');
                        group.className = 'form-group';
                        const lbl = document.createElement('label');
                        lbl.textContent = 'Active UI Font';
                        group.appendChild(lbl);

                        const select = document.createElement('select');
                        select.className = 'form-control inset-bevel';
                        const fonts = ['Lucida', 'Silkscreen', 'PressStart2P', 'Silver'];
                        fonts.forEach(f => {
                            const opt = document.createElement('option');
                            opt.value = f;
                            opt.textContent = f;
                            if (value === f) opt.selected = true;
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

        function createFormField(container, labelText, value, onChange, type = 'text', readOnly = false, keyId = null, useBlockLayout = false) {
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