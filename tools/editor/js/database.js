
        // --- DATABASE MODAL LOGIC ---
        // Database-modal fields mutate dbPayload live (no separate "staged" copy),
        // so "discard on Cancel/ESC" is implemented by snapshotting on open and
        // restoring that snapshot if the user confirms they want to discard.
        // engine/maps/flows are owned by their own editors (Engine window,
        // map editor, Flows tab), so the Database modal snapshots everything
        // else and restores it in place on discard (references stay valid).
        const dbModalSnapshotHelper = window.createSnapshotModal({
            getSnapshotSource: () => {
                const snap = {};
                Object.keys(dbPayload).forEach(k => {
                    if (k !== 'engine' && k !== 'maps' && k !== 'flows') {
                        snap[k] = dbPayload[k];
                    }
                });
                return snap;
            },
            onRestore: (snap) => {
                Object.keys(dbPayload).forEach(k => {
                    if (k !== 'engine' && k !== 'maps' && k !== 'flows') {
                        delete dbPayload[k];
                    }
                });
                Object.assign(dbPayload, snap);
                initMapEditor();
                initDatabaseEditor();
            },
            confirmMessage: 'You have unsaved database changes. Discard them and close?'
        });

        function openDatabaseModal() {
            dbModalSnapshotHelper.capture();
            document.getElementById('db-modal').classList.add('active');
            setDbTab(activeDbTab);
        }

        function closeDatabaseModal(force) {
            if (!dbModalSnapshotHelper.close(force)) return;
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
                  || activeDbTab === 'elements' || activeDbTab === 'roles' || activeDbTab === 'animations') {
                // String-keyed collections (skills/passives/states/elements/roles/animations)
                if (!dbPayload[activeDbTab]) dbPayload[activeDbTab] = {};
                items = Object.keys(dbPayload[activeDbTab])
                    .map(k => ({ id: k, name: dbPayload[activeDbTab][k].name || k }));
                // Animations keep insertion order (new entries append to the
                // bottom); the engine keys by id so JSON order is cosmetic.
                if (activeDbTab !== 'animations') {
                    items.sort((a, b) => a.name.localeCompare(b.name));
                }
            }
            else if (activeDbTab === 'quests') {
                // Object keyed by quest id (like commonEvents), but the keys are
                // string slugs rather than numeric.
                if (!dbPayload.quests) dbPayload.quests = {};
                items = Object.keys(dbPayload.quests)
                    .map(k => ({ id: k, name: dbPayload.quests[k].name || k }));
            }
            else if (activeDbTab === 'actionSequences') {
                if (!dbPayload.actionSequences) dbPayload.actionSequences = {};
                items = Object.keys(dbPayload.actionSequences)
                    .map(k => ({ id: k, name: dbPayload.actionSequences[k].name || k }))
                    .sort((a, b) => a.id.localeCompare(b.id));
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

            // Quests and Themes create entries via their own "+ New" button
            // (string-keyed / self-contained array entries), not the numeric
            // Change Maximum flow.
            if (activeDbTab === 'quests' || activeDbTab === 'actionSequences') {
                const addBtn = document.createElement('button');
                addBtn.className = 'db-list-item';
                addBtn.style.cssText = 'font-weight: bold; color: var(--win-highlight);';
                addBtn.textContent = activeDbTab === 'quests' ? '＋ New Quest' : '＋ New Sequence';
                addBtn.onclick = () => activeDbTab === 'quests' ? createNewQuest() : createNewActionSequence();
                listContainer.appendChild(addBtn);
            }

            // Toggle change max visibility (system doesn't need expandable count)
            const changeMaxBtn = document.getElementById('db-change-max-btn');
            if (activeDbTab === 'system' || activeDbTab === 'terms'
                || activeDbTab === 'quests' || activeDbTab === 'actionSequences') {
                changeMaxBtn.style.display = 'none';
            } else {
                changeMaxBtn.style.display = 'block';
            }
            // Animations get a dedicated append button; Change Maximum stays as
            // a fallback but the "＋ New Animation" flow is the intended path.
            const newAnimBtn = document.getElementById('db-new-anim-btn');
            if (newAnimBtn) newAnimBtn.style.display = activeDbTab === 'animations' ? 'block' : 'none';
        }

        // Append a fresh assignable animation with a unique placeholder id and
        // select it. The id is renamed in the editor's header field.
        function createNewAnimation() {
            const coll = dbPayload.animations = dbPayload.animations || {};
            let counter = 1;
            let id = 'newAnimation' + counter;
            while (coll[id]) { counter++; id = 'newAnimation' + counter; }
            coll[id] = { id: id, class: 'assignable', duration: 1000, tracks: [] };
            activeDbItemId = id;
            setDirty(true);
            initDatabaseEditor();
        }

        // --- QUESTS ---
        function createNewQuest() {
            const coll = dbPayload.quests = dbPayload.quests || {};
            let counter = 1;
            let id = 'new_quest_' + counter;
            while (coll[id]) { counter++; id = 'new_quest_' + counter; }
            coll[id] = { name: 'New Quest', giver: '', summary: '', description: '', objectives: [], rewards: {} };
            activeDbItemId = id;
            setDirty(true);
            initDatabaseEditor();
        }

        // Renames a quest's key, preserving object insertion order so the list
        // doesn't jump around. Quest keys are referenced by dialogue/flags, so a
        // rename here does not chase those references — surfaced via the toast.
        function renameQuestKey(oldKey, newKey) {
            newKey = (newKey || '').trim();
            if (!newKey || newKey === oldKey) return oldKey;
            if (!/^\w+$/.test(newKey)) { showToast('Quest id must be letters/digits/underscore.'); return oldKey; }
            if (dbPayload.quests[newKey]) { showToast(`Quest id '${newKey}' already exists.`); return oldKey; }
            const rebuilt = {};
            Object.keys(dbPayload.quests).forEach(k => {
                rebuilt[k === oldKey ? newKey : k] = dbPayload.quests[k];
            });
            dbPayload.quests = rebuilt;
            activeDbItemId = newKey;
            setDirty(true);
            showToast(`Renamed quest to '${newKey}'. Update any dialogue/flags that referenced '${oldKey}'.`);
            initDatabaseEditor();
            return newKey;
        }

        function deleteQuest(id) {
            if (!confirm(`Delete quest '${id}'? This cannot be undone.`)) return;
            delete dbPayload.quests[id];
            activeDbItemId = '';
            setDirty(true);
            initDatabaseEditor();
        }

        // --- ACTION SEQUENCES ---
        function createNewActionSequence() {
            const coll = dbPayload.actionSequences = dbPayload.actionSequences || {};
            let counter = 1;
            let id = 'new_sequence_' + counter;
            while (coll[id]) { counter++; id = 'new_sequence_' + counter; }
            coll[id] = { name: 'New Sequence', commands: [ { cmd: "APPLY_EFFECT" } ] };
            activeDbItemId = id;
            setDirty(true);
            initDatabaseEditor();
        }

        function renameActionSequenceKey(oldKey, newKey) {
            newKey = (newKey || '').trim();
            if (!newKey || newKey === oldKey) return oldKey;
            if (oldKey === 'default' || oldKey === 'default_item') {
                showToast(`Cannot rename reserved sequence '${oldKey}'.`);
                return oldKey;
            }
            if (!/^\w+$/.test(newKey)) { showToast('Sequence id must be letters/digits/underscore.'); return oldKey; }
            if (dbPayload.actionSequences[newKey]) { showToast(`Sequence id '${newKey}' already exists.`); return oldKey; }
            const rebuilt = {};
            Object.keys(dbPayload.actionSequences).forEach(k => {
                rebuilt[k === oldKey ? newKey : k] = dbPayload.actionSequences[k];
            });
            dbPayload.actionSequences = rebuilt;
            activeDbItemId = newKey;
            setDirty(true);
            showToast(`Renamed sequence to '${newKey}'. Update any skills/items that referenced '${oldKey}'.`);
            initDatabaseEditor();
            return newKey;
        }

        function deleteActionSequence(id) {
            if (id === 'default' || id === 'default_item') {
                showToast(`Cannot delete reserved sequence '${id}'.`);
                return;
            }
            if (!confirm(`Delete action sequence '${id}'? This cannot be undone.`)) return;
            delete dbPayload.actionSequences[id];
            activeDbItemId = '';
            setDirty(true);
            initDatabaseEditor();
        }

        // Editable list of plain strings (actor custom names, quest
        // objectives, reward flags), built on the shared buildRowListEditor
        // engine (same click/shift-click/Delete/Ctrl+C/X/V model as every
        // other list in the database editor).
        function buildStringListEditor(container, labelText, arr, placeholder) {
            buildRowListEditor(container, arr, {
                label: labelText,
                summary: (val) => [val || '(empty)'],
                editor: (row, val, idx, commit) => {
                    const inp = document.createElement('input');
                    inp.className = 'win98-input';
                    inp.style.flex = '1';
                    inp.placeholder = placeholder || '';
                    inp.value = val;
                    inp.oninput = () => { arr[idx] = inp.value; setDirty(true); };
                    inp.onkeydown = (e) => { if (e.key === 'Enter') commit(); };
                    row.appendChild(inp);
                    const doneBtn = document.createElement('button');
                    doneBtn.className = 'win98-btn'; doneBtn.textContent = '✓'; doneBtn.title = 'Done editing';
                    doneBtn.onclick = () => commit();
                    row.appendChild(doneBtn);
                    row.appendChild(makeRowDeleteBtn(() => { arr.splice(idx, 1); commit(); }));
                    inp.focus({ preventScroll: true });
                },
                newItem: () => '',
                addLabel: '+ Add'
            });
        }

        // Editable list of { id, qty, [consume] } item references (quest
        // requirements / rewards). `withConsume` adds the consume checkbox.
        function buildItemRefListEditor(container, labelText, arr, withConsume) {
            const group = document.createElement('div');
            group.className = 'form-group';
            const lbl = document.createElement('label');
            lbl.textContent = labelText;
            group.appendChild(lbl);

            const itemOpts = (dbPayload.items || []).map(it => ({ value: it.id, label: `${it.name} (#${it.id})` }));
            const list = document.createElement('div');
            const render = () => {
                list.innerHTML = '';
                arr.forEach((entry, i) => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; gap: 4px; align-items: center; margin-bottom: 2px;';

                    const sel = makeSelect(itemOpts, entry.id, v => { entry.id = parseInt(v); });
                    sel.style.flex = '1';
                    row.appendChild(sel);

                    const qty = document.createElement('input');
                    qty.type = 'number';
                    qty.className = 'win98-input';
                    qty.style.width = '54px';
                    qty.title = 'Quantity';
                    qty.value = entry.qty !== undefined ? entry.qty : 1;
                    qty.oninput = () => { entry.qty = parseInt(qty.value) || 1; setDirty(true); };
                    row.appendChild(qty);

                    if (withConsume) {
                        const cWrap = document.createElement('label');
                        cWrap.style.cssText = 'font-size: 10px; display: flex; align-items: center; gap: 2px;';
                        const chk = document.createElement('input');
                        chk.type = 'checkbox';
                        chk.checked = !!entry.consume;
                        chk.onchange = () => { entry.consume = chk.checked; setDirty(true); };
                        cWrap.appendChild(chk);
                        cWrap.appendChild(document.createTextNode('consume'));
                        row.appendChild(cWrap);
                    }

                    row.appendChild(makeRowDeleteBtn(() => { arr.splice(i, 1); render(); }));
                    list.appendChild(row);
                });
                list.appendChild(makeAddRowBtn('+ Add Item', () => {
                    const first = (dbPayload.items || [])[0];
                    const e = { id: first ? first.id : 1, qty: 1 };
                    if (withConsume) e.consume = true;
                    arr.push(e);
                    render();
                }));
            };
            render();
            group.appendChild(list);
            container.appendChild(group);
        }

        function buildQuestForm(formPanel, id) {
            const q = dbPayload.quests[id];
            if (!q) return;

            createFormField(formPanel, 'Quest ID (key)', id, val => { renameQuestKey(id, val); });
            createFormField(formPanel, 'Name', q.name || '', val => { q.name = val; initDatabaseEditor(true); });
            createFormField(formPanel, 'Giver', q.giver || '', val => { q.giver = val; });
            window.createSpriteField
                ? window.createSpriteField(formPanel, 'Giver Portrait', q.portrait || '', (p) => { if (p === '') delete q.portrait; else q.portrait = p; setDirty(true); })
                : createFormField(formPanel, 'Giver Portrait (key)', q.portrait || '', val => { if (val === '') delete q.portrait; else q.portrait = val; });
            createFormField(formPanel, 'Summary', q.summary || '', val => { q.summary = val; });

            const descGroup = document.createElement('div');
            descGroup.className = 'form-group';
            const descLbl = document.createElement('label');
            descLbl.textContent = 'Description';
            descLbl.style.marginBottom = '2px';
            const descTa = document.createElement('textarea');
            descTa.className = 'win98-input';
            descTa.style.cssText = 'width: 100%; height: 60px; font-family: inherit; box-sizing: border-box; resize: vertical;';
            descTa.value = q.description || '';
            descTa.oninput = () => { q.description = descTa.value; setDirty(true); };
            descGroup.appendChild(descLbl);
            descGroup.appendChild(descTa);
            formPanel.appendChild(descGroup);

            q.objectives = q.objectives || [];
            buildStringListEditor(formPanel, 'Objectives', q.objectives, 'Objective text');

            // Requirements (items to hand in)
            q.requirements = q.requirements || {};
            q.requirements.items = q.requirements.items || [];
            buildItemRefListEditor(formPanel, 'Required Items (handed in)', q.requirements.items, true);

            // Rewards
            q.rewards = q.rewards || {};
            const rewardsFs = document.createElement('fieldset');
            rewardsFs.style.cssText = 'padding: 6px; margin-top: 6px;';
            const rewardsLeg = document.createElement('legend');
            rewardsLeg.textContent = 'Rewards';
            rewardsFs.appendChild(rewardsLeg);
            createFormField(rewardsFs, 'Gold', q.rewards.gold || 0, val => { q.rewards.gold = parseInt(val) || 0; }, 'number');
            createFormField(rewardsFs, 'XP', q.rewards.xp || 0, val => { q.rewards.xp = parseInt(val) || 0; }, 'number');
            q.rewards.items = q.rewards.items || [];
            buildItemRefListEditor(rewardsFs, 'Reward Items', q.rewards.items, false);
            q.rewards.flags = q.rewards.flags || [];
            buildStringListEditor(rewardsFs, 'Flags Set on Completion', q.rewards.flags, 'flag_name');
            formPanel.appendChild(rewardsFs);

            // Per-quest hook overrides (main.lua:2677/2711 run these instead of
            // the flows.json quest.offer/complete default when present). Until
            // now these fields were only settable via the raw-JSON escape hatch
            // even though the flow-level defaults have a full editor (Engine ->
            // Flows -> Quests).
            buildQuestHookEditor(formPanel, q, 'acceptHook', 'Accept Hook (overrides default quest.offer)');
            buildQuestHookEditor(formPanel, q, 'completeHook', 'Complete Hook (overrides default quest.complete)');

            const delBtn = document.createElement('button');
            delBtn.className = 'win98-btn';
            delBtn.style.cssText = 'margin-top: 10px; color: #cc0000;';
            delBtn.textContent = 'Delete Quest';
            delBtn.onclick = () => deleteQuest(id);
            formPanel.appendChild(delBtn);
        }

        // Create/Remove-Override + renderCommandList (events.js), mirroring
        // the flows.json phase-override pattern in engine-editor.js's
        // renderFlowSceneEditor so quest-level hooks are edited the same way
        // as the flow-level defaults they override.
        function buildQuestHookEditor(formPanel, quest, field, label) {
            const fs = document.createElement('fieldset');
            fs.style.cssText = 'padding: 6px; margin-top: 6px;';
            const leg = document.createElement('legend');
            leg.textContent = label;
            fs.appendChild(leg);
            formPanel.appendChild(fs);

            const body = document.createElement('div');
            fs.appendChild(body);

            const render = () => {
                body.innerHTML = '';
                if (!Array.isArray(quest[field])) {
                    const info = document.createElement('div');
                    info.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow); margin-bottom: 4px;';
                    info.textContent = 'No override — this quest uses the flow-level default.';
                    body.appendChild(info);
                    const createBtn = document.createElement('button');
                    createBtn.className = 'win98-btn';
                    createBtn.style.fontSize = '10px';
                    createBtn.textContent = '+ Create Override';
                    createBtn.onclick = () => { quest[field] = []; setDirty(true); render(); };
                    body.appendChild(createBtn);
                    return;
                }

                const listBox = document.createElement('div');
                listBox.style.cssText = 'border: 1px solid var(--win-shadow); background: #fff; min-height: 80px; max-height: 200px; overflow-y: auto; padding: 4px; display: flex; flex-direction: column; gap: 2px; font-family: monospace; font-size: 11px;';
                const rerenderList = () => { setDirty(true); renderCommandList(listBox, quest[field], rerenderList, false, 0, 'quest'); };
                renderCommandList(listBox, quest[field], rerenderList, false, 0, 'quest');
                body.appendChild(listBox);

                const removeBtn = document.createElement('button');
                removeBtn.className = 'win98-btn';
                removeBtn.style.cssText = 'margin-top: 4px; font-size: 10px;';
                removeBtn.textContent = 'Remove Override';
                removeBtn.onclick = () => { delete quest[field]; setDirty(true); render(); };
                body.appendChild(removeBtn);
            };
            render();
        }

        function buildActionSequenceForm(formPanel, id) {
            const seqData = dbPayload.actionSequences[id];
            if (!seqData) return;

            createFormField(formPanel, 'Sequence ID', id, val => {
                const renamed = renameActionSequenceKey(id, val);
                activeDbItemId = renamed;
            });

            createFormField(formPanel, 'Sequence Name', seqData.name || '', val => {
                seqData.name = val;
                initDatabaseEditor(true);
            });

            const cmdTitle = document.createElement('div');
            cmdTitle.style.fontWeight = 'bold';
            cmdTitle.style.marginTop = '12px';
            cmdTitle.style.marginBottom = '6px';
            cmdTitle.textContent = 'Action Sequence Commands:';
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

            seqData.commands = seqData.commands || [];
            const rerenderSeqCommands = () => {
                setDirty(true);
                renderCommandList(listBox, seqData.commands, rerenderSeqCommands, false, 0, 'action_sequence');
            };
            renderCommandList(listBox, seqData.commands, rerenderSeqCommands, false, 0, 'action_sequence');
            formPanel.appendChild(listBox);

            if (id !== 'default' && id !== 'default_item') {
                const delBtn = document.createElement('button');
                delBtn.className = 'win98-btn';
                delBtn.style.cssText = 'margin-top: 10px; color: #cc0000;';
                delBtn.textContent = 'Delete Sequence';
                delBtn.onclick = () => deleteActionSequence(id);
                formPanel.appendChild(delBtn);
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
                  || activeDbTab === 'elements' || activeDbTab === 'roles' || activeDbTab === 'animations') {
                maxVal = Object.keys(dbPayload[activeDbTab] || {}).length;
            }

            const input = document.getElementById('max-input-val');
            input.value = maxVal;
            // B5: Enter applies, like clicking OK.
            input.onkeydown = (e) => { if (e.key === 'Enter') { e.preventDefault(); applyChangeMax(); } };
            document.getElementById('max-modal').classList.add('active');
            input.focus();
            input.select();
        }

        function closeChangeMaxDialog() {
            document.getElementById('max-modal').classList.remove('active');
        }

        function currentCollectionLength(tab) {
            if (tab === 'actors') return dbPayload.actors.length;
            if (tab === 'items') return dbPayload.items.length;
            if (tab === 'shops') return Object.keys(dbPayload.shops || {}).length;
            if (tab === 'commonEvents') return Object.keys(dbPayload.commonEvents || {}).length;
            if (['skills', 'passives', 'states', 'elements', 'roles', 'animations'].includes(tab)) {
                return Object.keys(dbPayload[tab] || {}).length;
            }
            return 0;
        }

        function applyChangeMax() {
            const newMax = parseInt(document.getElementById('max-input-val').value);
            if (isNaN(newMax) || newMax < 1 || newMax > 99) {
                showToast('Invalid max size (Enter 1 - 99).');
                return;
            }

            const currentLenBefore = currentCollectionLength(activeDbTab);
            if (newMax < currentLenBefore) {
                const removed = currentLenBefore - newMax;
                const ok = confirm(`Shrinking to ${newMax} will permanently delete the trailing ${removed} ${activeDbTab} entr${removed === 1 ? 'y' : 'ies'}. Continue?`);
                if (!ok) return;
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
                    || activeDbTab === 'elements' || activeDbTab === 'roles' || activeDbTab === 'animations') {
                // String-keyed collections: grow with generated unique ids,
                // shrink by dropping the alphabetically-last entries
                const coll = dbPayload[activeDbTab] = dbPayload[activeDbTab] || {};
                const defaults = {
                    skills: n => ({ id: n, name: `New Skill`, target: 'enemy-any', element: null, description: '', effects: [] }),
                    passives: n => ({ id: n, name: `New Passive`, description: '', effect: '', icon: 1, traits: [] }),
                    states: n => ({ id: n, name: `New State`, icon: 1, duration: 3, traits: [] }),
                    elements: n => ({ name: `New Element`, icon: 16, strongAgainst: [], weakAgainst: [] }),
                    roles: n => ({ name: `New Role`, description: '' }),
                    animations: n => ({ id: n, class: 'assignable', duration: 1000, tracks: [] })
                };
                const prefixes = { skills: 'newSkill', passives: 'newPassive', states: 'newState', elements: 'NewElement', roles: 'NewRole', animations: 'newAnimation' };
                const prefix = prefixes[activeDbTab];
                let currentLen = Object.keys(coll).length;
                let counter = 1;
                while (currentLen < newMax) {
                    let id = prefix + counter;
                    while (coll[id]) { counter++; id = prefix + counter; }
                    coll[id] = defaults[activeDbTab](id);
                    if (activeDbTab !== 'animations') {
                        coll[id].name += ' ' + counter;
                    }
                    currentLen++;
                }
                if (currentLen > newMax) {
                    const keys = Object.keys(coll).sort((a, b) => a.localeCompare(b));
                    if (activeDbTab === 'animations') {
                        // Safe delete: protect system entries, only delete assignable ones
                        const assignableKeys = keys.filter(k => coll[k].class !== 'system');
                        const numToDelete = currentLen - newMax;
                        const toDelete = assignableKeys.slice(-numToDelete);
                        toDelete.forEach(k => delete coll[k]);
                    } else {
                        keys.slice(newMax).forEach(k => delete coll[k]);
                    }
                }
            }

            setDirty(true);
            closeChangeMaxDialog();
            initDatabaseEditor();
        }