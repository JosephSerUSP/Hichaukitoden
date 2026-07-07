        // --- DATABASE MODAL LOGIC ---
        // Database-modal fields mutate dbPayload live (no separate "staged" copy),
        // so "discard on Cancel/ESC" is implemented by snapshotting on open and
        // restoring that snapshot if the user confirms they want to discard.
        var dbModalSnapshot = null;

        function openDatabaseModal() {
            dbModalSnapshot = JSON.stringify(dbPayload);
            document.getElementById('db-modal').classList.add('active');
            setDbTab(activeDbTab);
        }

        function closeDatabaseModal(force) {
            if (!force && dbModalSnapshot !== null && JSON.stringify(dbPayload) !== dbModalSnapshot) {
                if (!confirmDiscard('You have unsaved database changes. Discard them and close?')) return;
                dbPayload = JSON.parse(dbModalSnapshot);
                initMapEditor();
                initDatabaseEditor();
                setDirty(false);
            }
            dbModalSnapshot = null;
            document.getElementById('db-modal').classList.remove('active');
        }

        function setDbTab(tabName) {
            document.querySelectorAll('.db-tab-btn').forEach(b => b.classList.remove('active'));
            document.getElementById(`db-tab-${tabName}`).classList.add('active');

            activeDbTab = tabName;
            activeDbItemId = '';

            // Hide middle column on tabs that don't need lists/IDs
            const itemsCol = document.getElementById('db-items-column');
            if (tabName === 'system' || tabName === 'terms') {
                itemsCol.style.display = 'none';
            } else {
                itemsCol.style.display = 'flex';
            }

            initDatabaseEditor();
        }

        // listOnly = true refreshes the list column without rebuilding the
        // form panel (so typing in a Name field doesn't lose focus)
        function initDatabaseEditor(listOnly) {
            const listContainer = document.getElementById('db-list-box');
            listContainer.innerHTML = '';

            let items = [];
            if (activeDbTab === 'actors') items = dbPayload.actors;
            else if (activeDbTab === 'items') items = dbPayload.items;
            else if (activeDbTab === 'shops') {
                items = Object.keys(dbPayload.shops)
                    .map(k => ({ id: k, name: dbPayload.shops[k].name || `Shop ${k}` }))
                    .sort((a, b) => parseInt(a.id) - parseInt(b.id));
            }
            else if (activeDbTab === 'commonEvents') {
                if (!dbPayload.commonEvents) dbPayload.commonEvents = {};
                items = Object.keys(dbPayload.commonEvents)
                    .map(k => ({ id: k, name: dbPayload.commonEvents[k].name || `Event ${k}` }))
                    .sort((a, b) => parseInt(a.id) - parseInt(b.id));
            }
            else if (activeDbTab === 'skills' || activeDbTab === 'passives' || activeDbTab === 'states'
                  || activeDbTab === 'elements' || activeDbTab === 'roles') {
                // String-keyed collections (skills/passives/states/elements/roles)
                if (!dbPayload[activeDbTab]) dbPayload[activeDbTab] = {};
                items = Object.keys(dbPayload[activeDbTab])
                    .map(k => ({ id: k, name: dbPayload[activeDbTab][k].name || k }))
                    .sort((a, b) => a.name.localeCompare(b.name));
            }
            else if (activeDbTab === 'terms') items = [{ id: 'terms_settings', name: 'Game Terms' }];
            else if (activeDbTab === 'system') items = [{ id: 'system_settings', name: 'System Settings' }];

            items.forEach((item, idx) => {
                const btn = document.createElement('button');
                btn.className = 'db-list-item';

                // Format prefix like RPG Maker "0001: summoner"
                const idxStr = String(idx + 1).padStart(4, '0');
                btn.textContent = activeDbTab === 'system' ? item.name : `${idxStr}: ${item.name || item.id}`;

                if (activeDbItemId === item.id || (activeDbItemId === '' && idx === 0)) {
                    btn.classList.add('active');
                    activeDbItemId = item.id;
                    if (!listOnly) loadFormForItem(item);
                }

                btn.onclick = () => {
                    document.querySelectorAll('.db-list-item').forEach(b => b.classList.remove('active'));
                    btn.classList.add('active');
                    activeDbItemId = item.id;
                    loadFormForItem(item);
                };

                listContainer.appendChild(btn);
            });

            // Toggle change max visibility (system doesn't need expandable count)
            const changeMaxBtn = document.querySelector('.db-items-column button');
            if (activeDbTab === 'system' || activeDbTab === 'terms') {
                changeMaxBtn.style.display = 'none';
            } else {
                changeMaxBtn.style.display = 'block';
            }
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
                const rerenderCeCommands = () => {
                    setDirty(true);
                    renderCommandList(listBox, eventData.commands, rerenderCeCommands, false);
                };
                renderCommandList(listBox, eventData.commands, rerenderCeCommands, false);
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
                createFormField(attrRow, 'Icon #', item.icon || 0, val => { item.icon = parseInt(val) || 0; }, 'number');
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
                createFormField(formPanel, 'Icon #', passive.icon || 0, val => { passive.icon = parseInt(val) || 0; }, 'number');
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
                createFormField(stRow, 'Icon #', state.icon || 0, val => { state.icon = parseInt(val) || 0; }, 'number');
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
                createFormField(formPanel, 'Orb Icon #', elem.icon !== undefined ? elem.icon : 16, val => { elem.icon = parseInt(val) || 0; }, 'number');

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

        // --- CHANGE MAXIMUM LOGIC ---
        function openChangeMaxDialog() {
            let maxVal = 0;
            if (activeDbTab === 'actors') maxVal = dbPayload.actors.length;
            else if (activeDbTab === 'items') maxVal = dbPayload.items.length;
            else if (activeDbTab === 'shops') maxVal = Object.keys(dbPayload.shops).length;
            else if (activeDbTab === 'commonEvents') maxVal = Object.keys(dbPayload.commonEvents || {}).length;
            else if (activeDbTab === 'skills' || activeDbTab === 'passives' || activeDbTab === 'states'
                  || activeDbTab === 'elements' || activeDbTab === 'roles') {
                maxVal = Object.keys(dbPayload[activeDbTab] || {}).length;
            }

            document.getElementById('max-input-val').value = maxVal;
            document.getElementById('max-modal').classList.add('active');
        }

        function closeChangeMaxDialog() {
            document.getElementById('max-modal').classList.remove('active');
        }

        function applyChangeMax() {
            const newMax = parseInt(document.getElementById('max-input-val').value);
            if (isNaN(newMax) || newMax < 1 || newMax > 99) {
                alert('Invalid max size (Enter 1 - 99).');
                return;
            }

            if (activeDbTab === 'actors') {
                const currentLen = dbPayload.actors.length;
                let maxId = 0;
                dbPayload.actors.forEach(a => { if (a.id > maxId) maxId = a.id; });
                if (newMax > currentLen) {
                    for (let i = currentLen + 1; i <= newMax; i++) {
                        maxId += 1;
                        dbPayload.actors.push({
                            id: maxId,
                            name: `New Actor ${maxId}`,
                            role: 'Spirit',
                            maxHp: 10,
                            mpd: 2,
                            elements: [],
                            skills: []
                        });
                    }
                } else if (newMax < currentLen) {
                    dbPayload.actors = dbPayload.actors.slice(0, newMax);
                }
            } else if (activeDbTab === 'items') {
                const currentLen = dbPayload.items.length;
                let maxId = 0;
                dbPayload.items.forEach(it => { if (it.id > maxId) maxId = it.id; });
                if (newMax > currentLen) {
                    for (let i = currentLen + 1; i <= newMax; i++) {
                        maxId += 1;
                        dbPayload.items.push({
                            id: maxId,
                            name: `New Item ${maxId}`,
                            type: 'consumable',
                            description: 'Item description.',
                            cost: 0,
                            value: 0
                        });
                    }
                } else if (newMax < currentLen) {
                    dbPayload.items = dbPayload.items.slice(0, newMax);
                }
            } else if (activeDbTab === 'shops') {
                const shopKeys = Object.keys(dbPayload.shops).sort((a, b) => parseInt(a) - parseInt(b));
                const currentLen = shopKeys.length;
                if (newMax > currentLen) {
                    let maxId = 0;
                    shopKeys.forEach(k => { if (parseInt(k) > maxId) maxId = parseInt(k); });
                    for (let i = currentLen + 1; i <= newMax; i++) {
                        maxId += 1;
                        dbPayload.shops[String(maxId)] = { name: `New Shop ${maxId}`, items: [] };
                    }
                } else if (newMax < currentLen) {
                    const keysToDelete = shopKeys.slice(newMax);
                    keysToDelete.forEach(k => delete dbPayload.shops[k]);
                }
            } else if (activeDbTab === 'commonEvents') {
                if (!dbPayload.commonEvents) dbPayload.commonEvents = {};
                const currentKeys = Object.keys(dbPayload.commonEvents).sort((a, b) => parseInt(a) - parseInt(b));
                const currentLen = currentKeys.length;
                if (newMax > currentLen) {
                    for (let i = currentLen + 1; i <= newMax; i++) {
                        dbPayload.commonEvents[String(i)] = {
                            name: `New Common Event ${i}`,
                            commands: []
                        };
                    }
                } else if (newMax < currentLen) {
                    for (let i = newMax + 1; i <= currentLen; i++) {
                        delete dbPayload.commonEvents[String(i)];
                    }
                }
            } else if (activeDbTab === 'skills' || activeDbTab === 'passives' || activeDbTab === 'states'
                    || activeDbTab === 'elements' || activeDbTab === 'roles') {
                // String-keyed collections: grow with generated unique ids,
                // shrink by dropping the alphabetically-last entries
                const coll = dbPayload[activeDbTab] = dbPayload[activeDbTab] || {};
                const defaults = {
                    skills: n => ({ id: n, name: `New Skill`, target: 'enemy-any', element: null, description: '', effects: [] }),
                    passives: n => ({ id: n, name: `New Passive`, description: '', effect: '', icon: 1, traits: [] }),
                    states: n => ({ id: n, name: `New State`, icon: 1, duration: 3, traits: [] }),
                    elements: n => ({ name: `New Element`, icon: 16, strongAgainst: [], weakAgainst: [] }),
                    roles: n => ({ name: `New Role`, description: '' })
                };
                const prefixes = { skills: 'newSkill', passives: 'newPassive', states: 'newState', elements: 'NewElement', roles: 'NewRole' };
                const prefix = prefixes[activeDbTab];
                let currentLen = Object.keys(coll).length;
                let counter = 1;
                while (currentLen < newMax) {
                    let id = prefix + counter;
                    while (coll[id]) { counter++; id = prefix + counter; }
                    coll[id] = defaults[activeDbTab](id);
                    coll[id].name += ' ' + counter;
                    currentLen++;
                }
                if (currentLen > newMax) {
                    const keys = Object.keys(coll).sort((a, b) => a.localeCompare(b));
                    keys.slice(newMax).forEach(k => delete coll[k]);
                }
            }

            setDirty(true);
            closeChangeMaxDialog();
            initDatabaseEditor();
        }

// Exports
window.openDatabaseModal = openDatabaseModal;
window.closeDatabaseModal = closeDatabaseModal;
window.setDbTab = setDbTab;
window.initDatabaseEditor = initDatabaseEditor;
window.loadFormForItem = loadFormForItem;
window.openChangeMaxDialog = openChangeMaxDialog;
window.closeChangeMaxDialog = closeChangeMaxDialog;
window.applyChangeMax = applyChangeMax;
