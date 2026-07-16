
        // --- DATABASE MODAL LOGIC ---
        // Database-modal fields mutate dbPayload live (no separate "staged" copy),
        // so "discard on Cancel/ESC" is implemented by snapshotting on open and
        // restoring that snapshot if the user confirms they want to discard.
        // engine/maps/flows are owned by their own editors (Engine window,
        // map editor, Flows tab), so the Database modal snapshots everything
        // else and restores it in place on discard (references stay valid).
        function dbConfigSnapshot() {
            const snap = {};
            Object.keys(dbPayload).forEach(k => {
                if (k !== 'engine' && k !== 'maps' && k !== 'flows') {
                    snap[k] = JSON.parse(JSON.stringify(dbPayload[k]));
                }
            });
            return JSON.stringify(snap);
        }

        let dbModalSnapshot = null;

        function openDatabaseModal() {
            dbModalSnapshot = dbConfigSnapshot();
            document.getElementById('db-modal').classList.add('active');
            setDbTab(activeDbTab);
        }

        function closeDatabaseModal(force) {
            if (!force && dbModalSnapshot !== null && dbConfigSnapshot() !== dbModalSnapshot) {
                if (!confirmDiscard('You have unsaved database changes. Discard them and close?')) return;
                const snap = JSON.parse(dbModalSnapshot);
                Object.keys(dbPayload).forEach(k => {
                    if (k !== 'engine' && k !== 'maps' && k !== 'flows') {
                        delete dbPayload[k];
                    }
                });
                Object.assign(dbPayload, snap);

                initMapEditor();
                initDatabaseEditor();
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
            const changeMaxBtn = document.getElementById('db-change-max-btn');
            if (activeDbTab === 'system' || activeDbTab === 'terms') {
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