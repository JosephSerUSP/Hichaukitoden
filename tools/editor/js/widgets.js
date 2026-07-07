        // ---- Shared structured editors (used by Skills/Passives/States/Actors/Items forms) ----

        // Effect types and trait codes come from the engine registry
        // (data/engine.json), editable in the Engine editor. The literals here
        // are only fallbacks for payloads saved before the registry existed.
        function effectTypeOptions() {
            const reg = (dbPayload.engine && dbPayload.engine.effectTypes) || [];
            if (reg.length) return reg.map(et => ({ value: et.id, label: et.label || et.id }));
            return ['hp_damage', 'hp_heal', 'hp_drain', 'add_status', 'hp', 'maxHp', 'xp'];
        }
        function traitCodeOptions() {
            const reg = (dbPayload.engine && dbPayload.engine.traitCodes) || [];
            if (reg.length) return reg.map(tc => ({ value: tc.code, label: tc.label || tc.code }));
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

        function makeSelect(options, current, onChange, flex) {
            const sel = document.createElement('select');
            sel.className = 'win98-select';
            if (flex) sel.style.flex = flex;
            options.forEach(o => {
                const opt = document.createElement('option');
                opt.value = o.value !== undefined ? o.value : o;
                opt.textContent = o.label !== undefined ? o.label : (o === '' ? '(none)' : o);
                if (opt.value === String(current !== undefined && current !== null ? current : '')) opt.selected = true;
                sel.appendChild(opt);
            });
            sel.onchange = () => { onChange(sel.value); setDirty(true); };
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
        var CONFIG_SCHEMA = {
            'ui.menuSlideDuration':        { label: 'Menu Slide Duration (s)', step: 0.05 },
            'ui.moveTransitionDuration':   { label: 'Move Transition (s)', step: 0.05 },
            'ui.inputCooldown':            { label: 'Input Cooldown (s)', step: 0.05 },
            'ui.textPalette':              { label: 'Text Palette \\c[n] Colors', widget: 'colorList' },
            'physics.gravity':             { label: 'Popup Gravity (px/s²)' },
            'physics.bounceVelocityRetain':{ label: 'Popup Bounce Retention (0-1)', step: 0.05 },
            'physics.horizontalScatter':   { label: 'Popup Horizontal Scatter (px)' },
            'battle_screen.damagePopupLife': { label: 'Damage Popup Lifetime (s)', step: 0.1 },
            'combat.baseFleeChance':       { label: 'Base Flee Chance (0-1)', step: 0.05 },
            'combat.goldLossOnFleeMin':    { label: 'Gold Lost on Failed Flee (min)' },
            'combat.goldLossOnFleeMax':    { label: 'Gold Lost on Failed Flee (max)' },
            'combat.encounterChance':      { label: 'Encounter Chance per Step (0-1)', step: 0.01 },
            'combat.minEnemies':           { label: 'Encounter Size (min)' },
            'combat.maxEnemies':           { label: 'Encounter Size (max)' },
            'combat.victoryGoldMin':       { label: 'Victory Gold (min)' },
            'combat.victoryGoldMax':       { label: 'Victory Gold (max)' },
            'combat.victoryExp':           { label: 'Victory XP per Survivor' },
            'combat.baseSpeed':            { label: 'Base Action Speed' },
            'combat.speedPerLevel':        { label: 'Action Speed per Level', step: 0.1 },
            'combat.regenRate':            { label: 'Regen State: % Max HP / Turn', step: 0.01 },
            'combat.poisonRate':           { label: 'Poison State: % Max HP / Turn', step: 0.01 },
            'combat.mpExhaustionDamage':   { label: 'MP Exhaustion Damage / Turn' },
            'combat.battleItem':           { label: 'Battle "Item" Command Uses', widget: 'itemSelect' },
            'combat.defendSkillId':        { label: '"Defend" Command Skill', widget: 'skillSelect' },
            'combat.attackSkillId':        { label: '"Attack" Command Skill', widget: 'skillSelect' },
            'growth.hpPerLevelRate':       { label: 'HP Gain per Level (% of base)', step: 0.01 },
            'growth.statBase':             { label: 'Stat Base Value' },
            'growth.statPerLevel':         { label: 'Stat Gain per Level', step: 0.1 },
            'growth.expPerLevel':          { label: 'XP per Level (× current level)' },
            'dungeon.maxFloor':            { label: 'Deepest Floor' },
            'dungeon.moveMpDrain':         { label: 'MP Drain per Step' },
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
            'elementRules.strongMultiplier': { label: 'Strong-Element Damage ×', step: 0.05 },
            'elementRules.weakMultiplier': { label: 'Weak-Element Damage ×', step: 0.05 },
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
        function renderSchemaField(container, schema, value, key, currentPath, targetRoot) {
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
                group.className = 'form-group field-inline';
                const lbl = document.createElement('label');
                lbl.textContent = schema.label || key;
                group.appendChild(lbl);
                const numeric = (widget !== 'skillSelect');
                group.appendChild(makeSelect(opts, value, v => {
                    setNestedValue(targetRoot, currentPath, key, numeric ? (parseInt(v) || v) : v);
                }, '1'));
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
                group.className = 'form-group field-inline';
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
                            const mapOpts = dbPayload.maps.map((m, i) => ({ value: String(i + 1), label: m.title || ('Map ' + (i + 1)) }));
                            row.appendChild(makeSelect(mapOpts, opt.mapId, v => { opt.mapId = parseInt(v); }, '1'));
                        } else {
                            const graph = document.createElement('input');
                            graph.className = 'win98-input';
                            graph.style.flex = '1';
                            graph.placeholder = 'dialogue graph, e.g. npc_alicia';
                            graph.value = opt.graph || '';
                            graph.oninput = () => { opt.graph = graph.value; setDirty(true); };
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
                group.className = 'form-group field-inline';
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
                container.appendChild(group);
                return true;
            }

            return false;
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

                const area = document.createElement('textarea');
                area.className = 'form-control inset-bevel';
                area.style.cssText = 'font-family: monospace; font-size: 11px; height: 320px; white-space: pre;';
                area.value = JSON.stringify(targetObj, null, 2);
                area.oninput = () => {
                    try { JSON.parse(area.value); area.style.background = ''; }
                    catch (e) { area.style.background = '#ffcccc'; }
                };

                const bar = document.createElement('div');
                bar.style.cssText = 'display: flex; gap: 6px; margin-bottom: 6px;';
                const applyBtn = document.createElement('button');
                applyBtn.className = 'win98-btn win98-btn-success';
                applyBtn.textContent = 'Apply JSON';
                applyBtn.onclick = () => {
                    let parsed;
                    try { parsed = JSON.parse(area.value); }
                    catch (e) { area.style.background = '#ffcccc'; return; }
                    if (Array.isArray(targetObj) && Array.isArray(parsed)) {
                        targetObj.length = 0;
                        parsed.forEach(v => targetObj.push(v));
                    } else if (!Array.isArray(targetObj) && typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
                        Object.keys(targetObj).forEach(k => delete targetObj[k]);
                        Object.assign(targetObj, parsed);
                    } else {
                        area.style.background = '#ffcccc';
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
                formPanel.appendChild(area);
            };
            buttonHost.appendChild(btn);
        }

        // ---- Sprite-key suggestions from assets/portraits ----
        var portraitKeysLoaded = false;
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

        function buildRecursiveForm(container, obj, path, targetRoot) {
            for (const key in obj) {
                if (obj.hasOwnProperty(key)) {
                    const value = obj[key];
                    const currentPath = [...path, key];

                    const schemaEntry = CONFIG_SCHEMA[currentPath.join('.')];
                    if (schemaEntry && renderSchemaField(container, schemaEntry, value, key, currentPath, targetRoot)) {
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

                        buildRecursiveForm(content, value, currentPath, targetRoot);
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
                        }, type, false, key);
                    }
                }
            }
        }

        function createFormField(container, labelText, value, onChange, type = 'text', readOnly = false, keyId = null) {
            const group = document.createElement('div');
            group.className = 'form-group field-inline';

            const label = document.createElement('label');
            label.textContent = labelText;
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

// Exports
window.effectTypeOptions = effectTypeOptions;
window.traitCodeOptions = traitCodeOptions;
window.traitUsesDataId = traitUsesDataId;
window.elementOptions = elementOptions;
window.makeSelect = makeSelect;
window.makeListBox = makeListBox;
window.makeRowDeleteBtn = makeRowDeleteBtn;
window.makeAddRowBtn = makeAddRowBtn;
window.buildEffectsEditor = buildEffectsEditor;
window.buildTraitsEditor = buildTraitsEditor;
window.buildChecklistField = buildChecklistField;
window.buildDropsEditor = buildDropsEditor;
window.buildEvolutionsEditor = buildEvolutionsEditor;
window.createCheckboxField = createCheckboxField;
window.setNestedValue = setNestedValue;
window.renderSchemaField = renderSchemaField;
window.attachJsonToggle = attachJsonToggle;
window.ensurePortraitKeys = ensurePortraitKeys;
window.buildElementSlotsEditor = buildElementSlotsEditor;
window.buildRecursiveForm = buildRecursiveForm;
window.createFormField = createFormField;
