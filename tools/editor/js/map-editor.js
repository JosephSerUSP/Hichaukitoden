
        // --- LAYER / EDITING MODE LOGIC ---
        function switchMode(mode) {
            editingMode = mode;
            document.getElementById('tool-map-btn').classList.remove('active');
            document.getElementById('tool-event-btn').classList.remove('active');

            document.getElementById(`tool-${mode}-btn`).classList.add('active');
            document.getElementById('status-mode').textContent = `Layer: ${mode === 'map' ? 'Map Layer' : 'Event Layer'}`;

            if (mode === 'map') {
                document.getElementById('map-palette-section').style.display = 'block';
                document.getElementById('event-palette-section').style.display = 'none';
            } else {
                document.getElementById('map-palette-section').style.display = 'none';
                document.getElementById('event-palette-section').style.display = 'block';
            }

            // Re-render the map cells to update active visual style representation
            renderGridCells();
        }

        // --- MAP EDITOR LOGIC ---
        function initMapEditor() {
            renderMapTree();
            currentMapIndex = 0;
            loadActiveMap();
        }

        // A map's category is explicit metadata (map.category); maps saved
        // before this field existed fall back to "index 0 = town" for compatibility.
        function getMapCategory(map, idx) {
            return map.category || (idx === 0 ? 'town' : 'dungeon');
        }

        function makeMapTreeItem(map, idx) {
            const mapItem = document.createElement('div');
            mapItem.className = 'tree-node-header map-tree-item';
            mapItem.dataset.idx = idx;
            mapItem.innerHTML = '🟩 ' + (map.title || `Map ${idx}`);
            mapItem.onclick = () => {
                currentMapIndex = idx;
                loadActiveMap();
            };
            mapItem.ondblclick = () => {
                currentMapIndex = idx;
                loadActiveMap();
                openMapProperties();
            };
            mapItem.oncontextmenu = (e) => {
                showMapContextMenu(e, idx);
            };
            return mapItem;
        }

        function makeTreeFolder(title) {
            const folder = document.createElement('div');
            folder.className = 'tree-node';
            const header = document.createElement('div');
            header.className = 'tree-node-header';
            header.innerHTML = title;
            const children = document.createElement('div');
            children.style.marginLeft = '12px';
            folder.appendChild(header);
            folder.appendChild(children);
            return { folder, children };
        }

        function renderMapTree() {
            const container = document.getElementById('map-tree');
            container.innerHTML = '';

            const rootNode = document.createElement('div');
            rootNode.className = 'tree-node';

            const rootHeader = document.createElement('div');
            rootHeader.className = 'tree-node-header';
            rootHeader.innerHTML = '📁 Hichaukitoden';
            rootNode.appendChild(rootHeader);

            const rootChildren = document.createElement('div');
            rootChildren.style.marginLeft = '12px';
            rootNode.appendChild(rootChildren);

            const town = makeTreeFolder('📁 Town');
            const dungeon = makeTreeFolder('📁 Dungeon Floors');

            dbPayload.maps.forEach((map, idx) => {
                const target = getMapCategory(map, idx) === 'town' ? town.children : dungeon.children;
                target.appendChild(makeMapTreeItem(map, idx));
            });

            rootChildren.appendChild(town.folder);
            rootChildren.appendChild(dungeon.folder);
            container.appendChild(rootNode);
        }

        const TILE_SIZE = 24;
        let mapCanvas = null;
        let ctx = null;
        let selectedEvent = null;
        let dragOffset = { x: 0, y: 0 };
        let mouseX = 0, mouseY = 0;
        let eventCopyBuffer = null;
        const imageCache = {};

        function getCachedImage(src) {
            if (imageCache[src]) {
                return imageCache[src];
            }
            const img = new Image();
            img.src = '/' + src;
            img.onload = () => {
                renderGridCells();
            };
            imageCache[src] = img;
            return img;
        }

        function loadActiveMap() {
            // Initialize canvas event listeners once canvas is loaded
            const canvas = document.getElementById('map-canvas');
            if (canvas && !mapCanvas) {
                mapCanvas = canvas;
                ctx = canvas.getContext('2d');
                initCanvasEvents();
            }
            renderGridCells();
            document.querySelectorAll('.map-tree-item').forEach(el => {
                if (parseInt(el.dataset.idx) === currentMapIndex) {
                    el.classList.add('active');
                } else {
                    el.classList.remove('active');
                }
            });
        }

        function renderGridCells() {
            const map = dbPayload.maps[currentMapIndex];
            if (!map) return;

            const canvas = document.getElementById('map-canvas');
            if (!canvas) return;
            ctx = canvas.getContext('2d');

            const isProcedural = !map.layout || map.layout.length === 0;
            const height = isProcedural ? 21 : map.layout.length;
            const width = isProcedural ? 21 : map.layout[0].length;

            const targetW = width * TILE_SIZE;
            const targetH = height * TILE_SIZE;

            if (canvas.width !== targetW || canvas.height !== targetH) {
                canvas.width = targetW;
                canvas.height = targetH;
            }

            ctx.clearRect(0, 0, canvas.width, canvas.height);

            // 1. Draw tiles (wall or floor)
            for (let y = 0; y < height; y++) {
                for (let x = 0; x < width; x++) {
                    let tile = '#';
                    if (isProcedural) {
                        tile = (x === 0 || y === 0 || x === width - 1 || y === height - 1) ? '#' : '.';
                    } else {
                        tile = map.layout[y][x];
                    }

                    if (tile === '#') {
                        ctx.fillStyle = '#808080'; // Wall
                    } else {
                        ctx.fillStyle = '#ffffff'; // Floor
                    }
                    ctx.fillRect(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE);

                    // Grid borders
                    ctx.strokeStyle = '#e0e0e0';
                    ctx.lineWidth = 0.5;
                    ctx.strokeRect(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE);
                }
            }

            // 2. Draw Events
            (map.events || []).forEach(ev => {
                if (ev.x === undefined || ev.y === undefined) return;
                const ex = ev.x;
                const ey = ev.y;

                if (selectedEvent === ev) {
                    ctx.strokeStyle = '#00ff00';
                    ctx.lineWidth = 2;
                    ctx.strokeRect(ex * TILE_SIZE, ey * TILE_SIZE, TILE_SIZE, TILE_SIZE);
                } else {
                    ctx.strokeStyle = '#ef4444';
                    ctx.lineWidth = 1.5;
                    ctx.strokeRect(ex * TILE_SIZE + 1.5, ey * TILE_SIZE + 1.5, TILE_SIZE - 3, TILE_SIZE - 3);
                }

                ctx.fillStyle = 'rgba(239, 68, 68, 0.2)';
                ctx.fillRect(ex * TILE_SIZE + 1.5, ey * TILE_SIZE + 1.5, TILE_SIZE - 3, TILE_SIZE - 3);

                if (ev.sprite) {
                    const img = getCachedImage(ev.sprite);
                    if (img && img.complete) {
                        ctx.drawImage(img, ex * TILE_SIZE + 2, ey * TILE_SIZE + 2, TILE_SIZE - 4, TILE_SIZE - 4);
                    } else {
                        ctx.fillStyle = '#ef4444';
                        ctx.font = 'bold 10px sans-serif';
                        ctx.textAlign = 'center';
                        ctx.textBaseline = 'middle';
                        ctx.fillText('E', ex * TILE_SIZE + TILE_SIZE / 2, ey * TILE_SIZE + TILE_SIZE / 2);
                    }
                } else {
                    ctx.fillStyle = '#ef4444';
                    ctx.font = 'bold 10px sans-serif';
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.fillText('?', ex * TILE_SIZE + TILE_SIZE / 2, ey * TILE_SIZE + TILE_SIZE / 2);
                }
            });

            // 3. Draw Player spawn indicator
            const isSpawn = dbPayload.system && dbPayload.system.spawn &&
                            currentMapIndex === 0;
            if (isSpawn) {
                const sx = parseInt(dbPayload.system.spawn.x);
                const sy = parseInt(dbPayload.system.spawn.y);

                ctx.fillStyle = 'rgba(0, 128, 0, 0.25)';
                ctx.fillRect(sx * TILE_SIZE, sy * TILE_SIZE, TILE_SIZE, TILE_SIZE);
                ctx.strokeStyle = '#008000';
                ctx.lineWidth = 1.5;
                ctx.strokeRect(sx * TILE_SIZE + 1, sy * TILE_SIZE + 1, TILE_SIZE - 2, TILE_SIZE - 2);

                ctx.font = '12px sans-serif';
                ctx.textAlign = 'center';
                ctx.textBaseline = 'middle';
                ctx.fillText('👤', sx * TILE_SIZE + TILE_SIZE / 2, sy * TILE_SIZE + TILE_SIZE / 2);
            }
        }

        function initCanvasEvents() {
            const canvas = document.getElementById('map-canvas');
            if (!canvas) return;

            canvas.addEventListener('contextmenu', (e) => {
                e.preventDefault();
                const rect = canvas.getBoundingClientRect();
                const x = Math.floor((e.clientX - rect.left) / TILE_SIZE);
                const y = Math.floor((e.clientY - rect.top) / TILE_SIZE);
                showCanvasContextMenu(e, x, y);
            });

            canvas.addEventListener('mousedown', (e) => {
                e.preventDefault();
                if (e.button === 2) return; // handled by the contextmenu event instead

                const rect = canvas.getBoundingClientRect();
                const x = Math.floor((e.clientX - rect.left) / TILE_SIZE);
                const y = Math.floor((e.clientY - rect.top) / TILE_SIZE);

                const map = dbPayload.maps[currentMapIndex];
                if (!map) return;

                if (editingMode === 'map') {
                    if (e.button === 0) {
                        isMouseDown = true;
                        paintCellAt(x, y);
                    }
                } else {
                    if (e.button === 0) {
                        const clickedEvent = (map.events || []).find(ev => ev.x === x && ev.y === y);
                        if (clickedEvent) {
                            selectedEvent = clickedEvent;
                            isMouseDown = true;
                            renderGridCells();
                        } else {
                            selectedEvent = null;
                            renderGridCells();
                        }
                    }
                }
            });

            canvas.addEventListener('mousemove', (e) => {
                const rect = canvas.getBoundingClientRect();
                const x = Math.floor((e.clientX - rect.left) / TILE_SIZE);
                const y = Math.floor((e.clientY - rect.top) / TILE_SIZE);

                const map = dbPayload.maps[currentMapIndex];
                if (!map) return;

                const isProcedural = !map.layout || map.layout.length === 0;
                const width = isProcedural ? 21 : map.layout[0].length;
                const height = isProcedural ? 21 : map.layout.length;
                if (x < 0 || x >= width || y < 0 || y >= height) return;

                if (editingMode === 'map' && isMouseDown) {
                    paintCellAt(x, y);
                } else if (editingMode === 'event' && isMouseDown && selectedEvent) {
                    if (selectedEvent.x !== x || selectedEvent.y !== y) {
                        const occupied = (map.events || []).find(ev => ev !== selectedEvent && ev.x === x && ev.y === y);
                        if (!occupied) {
                            selectedEvent.x = x;
                            selectedEvent.y = y;
                            setDirty(true);
                            renderGridCells();
                        }
                    }
                }
            });

            canvas.addEventListener('dblclick', (e) => {
                e.preventDefault();
                const rect = canvas.getBoundingClientRect();
                const x = Math.floor((e.clientX - rect.left) / TILE_SIZE);
                const y = Math.floor((e.clientY - rect.top) / TILE_SIZE);

                if (editingMode === 'event') {
                    openEventModal(x, y);
                }
            });
        }

        // Pastes eventCopyBuffer at (x, y) on the current map, if the tile is free.
        // Shared by the Ctrl+V shortcut and the canvas right-click menu's Paste option.
        function pasteEventAt(x, y) {
            if (!eventCopyBuffer) return;
            const map = dbPayload.maps[currentMapIndex];
            if (!map || x < 0 || x >= map.layout[0].length || y < 0 || y >= map.layout.length) return;

            const occupied = (map.events || []).find(ev => ev.x === x && ev.y === y);
            if (occupied) return;

            const copiedObj = JSON.parse(eventCopyBuffer);
            let maxId = 0;
            (map.events || []).forEach(ev => {
                if (ev.id > maxId) maxId = ev.id;
            });
            copiedObj.id = maxId + 1;
            copiedObj.x = x;
            copiedObj.y = y;

            map.events = map.events || [];
            map.events.push(copiedObj);
            selectedEvent = copiedObj;
            setDirty(true);
            renderGridCells();
        }

        window.addEventListener('keydown', (e) => {
            if (editingMode === 'event' && selectedEvent) {
                if (e.ctrlKey && e.key === 'c') {
                    eventCopyBuffer = JSON.stringify(selectedEvent);
                }
            }
            if (editingMode === 'event' && eventCopyBuffer && e.ctrlKey && e.key === 'v') {
                const canvas = document.getElementById('map-canvas');
                if (!canvas) return;
                const rect = canvas.getBoundingClientRect();
                const x = Math.floor((mouseX - rect.left) / TILE_SIZE);
                const y = Math.floor((mouseY - rect.top) / TILE_SIZE);
                pasteEventAt(x, y);
            }
        });

        // --- CANVAS RIGHT-CLICK CONTEXT MENU ---
        function showCanvasContextMenu(e, x, y) {
            const map = dbPayload.maps[currentMapIndex];
            if (!map) return;

            const menu = document.getElementById('canvas-context-menu');
            menu.innerHTML = '';

            const addItem = (label, onClick, danger) => {
                const item = document.createElement('div');
                item.className = 'context-menu-item';
                item.style.padding = '4px 8px';
                item.style.cursor = 'default';
                item.style.display = 'flex';
                item.style.alignItems = 'center';
                item.style.gap = '6px';
                if (danger) item.style.color = '#cc0000';
                item.textContent = label;
                item.onclick = () => { menu.style.display = 'none'; onClick(); };
                menu.appendChild(item);
            };
            const addSeparator = () => {
                const sep = document.createElement('div');
                sep.style.borderTop = '1px solid #808080';
                sep.style.margin = '2px 0';
                menu.appendChild(sep);
            };

            if (editingMode === 'event') {
                const existingEvent = (map.events || []).find(ev => ev.x === x && ev.y === y);
                if (existingEvent) {
                    addItem('✏️ Edit Event...', () => openEventModal(x, y));
                    addItem('📋 Copy Event', () => { selectedEvent = existingEvent; eventCopyBuffer = JSON.stringify(existingEvent); });
                    addItem('❌ Delete Event', () => {
                        map.events = map.events.filter(ev => ev !== existingEvent);
                        setDirty(true);
                        renderGridCells();
                    }, true);
                } else {
                    addItem('➕ Add Event Here...', () => openEventModal(x, y));
                    if (eventCopyBuffer) {
                        addItem('📋 Paste Event', () => pasteEventAt(x, y));
                    }
                }
                addSeparator();
            }

            addItem('🚩 Set Player Start Position Here', () => setPlayerStartPosition(x, y));

            menu.style.left = e.clientX + 'px';
            menu.style.top = e.clientY + 'px';
            menu.style.display = 'block';
        }

        window.addEventListener('mousemove', (e) => {
            mouseX = e.clientX;
            mouseY = e.clientY;
        });

        function paintCellAt(x, y) {
            const map = dbPayload.maps[currentMapIndex];
            if (!map || !map.layout[y]) return;

            let tileChar = activePaintTool === 'floor' ? '.' : '#';
            const line = map.layout[y];
            const updatedLine = line.substring(0, x) + tileChar + line.substring(x + 1);
            map.layout[y] = updatedLine;
            setDirty(true);
            renderGridCells();
        }

        function setPlayerStartPosition(x, y) {
            if (!dbPayload.system) dbPayload.system = {};
            if (!dbPayload.system.spawn) dbPayload.system.spawn = {};

            dbPayload.system.spawn.x = x;
            dbPayload.system.spawn.y = y;

            setDirty(true);
            renderGridCells();
        }

        function setPaintTool(toolName, btn) {
            document.querySelectorAll('.tool-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            activePaintTool = toolName;
        }

        // --- MAP PROPERTIES & EVENTS CONTROLLERS ---
        // Encounters are edited as a staged working copy so Cancel/ESC can
        // discard them cleanly, matching the rest of this dialog's OK/Cancel semantics.
        let mapPropsEncounters = [];
        let mapPropsSnapshot = null;
        let mapPropsDirty = false;

        function openMapProperties() {
            const map = dbPayload.maps[currentMapIndex];
            if (!map) return;

            document.getElementById('prop-map-title').value = map.title || map.name || '';
            document.getElementById('prop-map-category').value = getMapCategory(map, currentMapIndex);
            document.getElementById('prop-map-gen').value = map.generation || 'Fixed';
            document.getElementById('prop-map-width').value = map.width || (map.layout ? map.layout[0].length : 15);
            document.getElementById('prop-map-height').value = map.height || (map.layout ? map.layout.length : 15);
            document.getElementById('prop-map-bgm').value = map.bgm || '';
            document.getElementById('prop-map-enc-steps').value = map.encounterSteps || 0;
            document.getElementById('prop-map-enc-rate').value = (map.encounterRate !== undefined) ? map.encounterRate : '';
            document.getElementById('prop-map-safe').checked = !!map.safe;

            mapPropsEncounters = JSON.parse(JSON.stringify(map.encounters || []));
            renderEncountersList(mapPropsEncounters);
            mapPropsDirty = false;
            mapPropsSnapshot = JSON.stringify(map);
            document.getElementById('map-properties-modal').classList.add('active');
        }

        function closeMapPropertiesModal(force) {
            if (!force && mapPropsDirty && !confirmDiscard('Discard changes to this map\'s properties?')) return;
            if (!force && mapPropsDirty && mapPropsSnapshot) {
                const map = dbPayload.maps[currentMapIndex];
                if (map) {
                    const snap = JSON.parse(mapPropsSnapshot);
                    Object.keys(map).forEach(k => {
                        if (k !== 'events' && k !== 'layout') delete map[k];
                    });
                    Object.keys(snap).forEach(k => {
                        if (k !== 'events' && k !== 'layout') map[k] = snap[k];
                    });
                }
            }
            document.getElementById('map-properties-modal').classList.remove('active');
            mapPropsSnapshot = null;
        }

        function togglePropGenMode() {}

        function renderEncountersList(encounters) {
            const list = document.getElementById('prop-enc-list');
            list.innerHTML = '';
            encounters.forEach((enc, idx) => {
                const actor = (dbPayload.actors || []).find(a => a.id === enc.id);
                const item = document.createElement('div');
                item.style.fontSize = '10px';
                item.style.padding = '2px 4px';
                item.style.cursor = 'pointer';
                item.textContent = `${actor ? actor.name : 'Unknown'} (ID ${enc.id}) — Weight: ${enc.weight || 10}`;
                item.onclick = () => {
                    document.querySelectorAll('#prop-enc-list > div').forEach(d => d.style.background = '');
                    item.style.background = 'var(--win-blue)';
                    item.style.color = '#fff';
                    list.dataset.selectedIdx = idx;
                };
                list.appendChild(item);
            });
        }

        function addEncounterToMap() {
            const actorList = (dbPayload.actors || []).map(a => `${a.id}: ${a.name}`).join('\n');
            const actorId = parseInt(prompt(`Enter Actor ID to encounter:\n${actorList}`, dbPayload.actors && dbPayload.actors[0] ? dbPayload.actors[0].id : '1'));
            if (!isNaN(actorId)) {
                const weight = parseInt(prompt("Enter Spawn Weight (probability weight):", "10")) || 10;
                mapPropsEncounters.push({ id: actorId, weight: weight });
                mapPropsDirty = true;
                renderEncountersList(mapPropsEncounters);
            }
        }

        function removeEncounterFromMap() {
            const list = document.getElementById('prop-enc-list');
            const idx = parseInt(list.dataset.selectedIdx);
            if (!isNaN(idx) && mapPropsEncounters[idx]) {
                mapPropsEncounters.splice(idx, 1);
                delete list.dataset.selectedIdx;
                mapPropsDirty = true;
                renderEncountersList(mapPropsEncounters);
            }
        }

        function saveMapProperties() {
            const map = dbPayload.maps[currentMapIndex];
            if (!map) return;

            const newTitle = document.getElementById('prop-map-title').value;
            const newGen = document.getElementById('prop-map-gen').value;
            const newW = parseInt(document.getElementById('prop-map-width').value) || 15;
            const newH = parseInt(document.getElementById('prop-map-height').value) || 15;
            const newBgm = document.getElementById('prop-map-bgm').value;
            const newSteps = parseInt(document.getElementById('prop-map-enc-steps').value) || 0;

            map.title = newTitle;
            map.category = document.getElementById('prop-map-category').value;
            map.generation = newGen;
            map.bgm = newBgm;
            map.encounterSteps = newSteps;
            map.encounters = mapPropsEncounters;

            const rateRaw = document.getElementById('prop-map-enc-rate').value;
            if (rateRaw === '') {
                delete map.encounterRate;
            } else {
                map.encounterRate = Math.min(1, Math.max(0, parseFloat(rateRaw) || 0));
            }
            map.safe = document.getElementById('prop-map-safe').checked;
            if (!map.safe) delete map.safe;

            if (map.layout) {
                const currentH = map.layout.length;
                const currentW = map.layout[0].length;

                if (newH !== currentH || newW !== currentW) {
                    if (newH > currentH) {
                        for (let y = currentH; y < newH; y++) {
                            map.layout.push(".".repeat(newW));
                        }
                    } else if (newH < currentH) {
                        map.layout = map.layout.slice(0, newH);
                    }

                    for (let y = 0; y < map.layout.length; y++) {
                        const row = map.layout[y];
                        if (row.length < newW) {
                            map.layout[y] = row + ".".repeat(newW - row.length);
                        } else if (row.length > newW) {
                            map.layout[y] = row.substring(0, newW);
                        }
                    }
                }
            }

            closeMapPropertiesModal(true);
            renderMapTree();
            renderGridCells();
            setDirty(true);
        }

        function createNewMap() {
            let maxId = 0;
            dbPayload.maps.forEach(m => {
                if (m.id && m.id > maxId) maxId = m.id;
            });

            const newId = maxId + 1;
            const newMap = {
                id: newId,
                title: `New Floor ${newId}`,
                category: 'dungeon',
                generation: 'Fixed',
                layout: [
                    "###############",
                    "#.............#",
                    "#.............#",
                    "#.............#",
                    "#.............#",
                    "#.............#",
                    "#.............#",
                    "#.............#",
                    "#.............#",
                    "#.............#",
                    "###############"
                ],
                bgm: "assets/midi/dungeon.mid",
                encounterSteps: 25,
                encounters: [],
                events: []
            };

            dbPayload.maps.push(newMap);
            currentMapIndex = dbPayload.maps.length - 1;
            renderMapTree();
            loadActiveMap();
            setDirty(true);
        }

        function deleteMap() {
            const map = dbPayload.maps[currentMapIndex];
            if (getMapCategory(map, currentMapIndex) === 'town') {
                alert("Cannot delete a Town category map.");
                return;
            }
            if (confirm(`Are you sure you want to delete "${map.title}"?`)) {
                dbPayload.maps.splice(currentMapIndex, 1);
                currentMapIndex = 0;
                renderMapTree();
                loadActiveMap();
                setDirty(true);
            }
        }

        function openAssetPickerForBgm() {
            openAssetPicker('midi', (path) => {
                document.getElementById('prop-map-bgm').value = path;
            });
        }