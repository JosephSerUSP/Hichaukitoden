
        // --- LAYER / EDITING MODE LOGIC ---
        function switchMode(mode) {
            editingMode = mode;
            ['map', 'event', 'light'].forEach(m => document.getElementById(`tool-${m}-btn`).classList.remove('active'));
            document.getElementById(`tool-${mode}-btn`).classList.add('active');

            const modeLabels = { map: 'Map Layer', event: 'Event Layer', light: 'Light Layer' };
            document.getElementById('status-mode').textContent = `Layer: ${modeLabels[mode]}`;

            document.getElementById('map-palette-section').style.display = mode === 'map' ? 'block' : 'none';
            document.getElementById('event-palette-section').style.display = mode === 'event' ? 'block' : 'none';
            document.getElementById('light-palette-section').style.display = mode === 'light' ? 'block' : 'none';

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
                initCanvasEvents(canvas);
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

                // Pages badge: navy corner tag with the page count so multi-page
                // events are spottable on the grid (matches the navy accents used
                // across the editor).
                if (Array.isArray(ev.pages) && ev.pages.length > 0) {
                    ctx.fillStyle = '#000080';
                    ctx.fillRect(ex * TILE_SIZE + TILE_SIZE - 9, ey * TILE_SIZE + 1, 8, 8);
                    ctx.fillStyle = '#ffffff';
                    ctx.font = 'bold 7px sans-serif';
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.fillText(String(ev.pages.length), ex * TILE_SIZE + TILE_SIZE - 5, ey * TILE_SIZE + 5.5);
                }
            });

            // 3. Draw Player spawn indicator (only on the map spawn.mapId points at)
            const currentMap = dbPayload.maps[currentMapIndex];
            const isSpawn = dbPayload.system && dbPayload.system.spawn && currentMap &&
                            dbPayload.system.spawn.mapId === currentMap.id;
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

            // 4. Light layer overlay: a bilinearly-interpolated gradient fill
            // between grid CORNERS (not cells) previewing exactly what the
            // raycaster samples per wall-slice column, plus small handle dots
            // at each corner for precise click targeting. Only drawn while
            // actively editing light so it doesn't clutter the Map/Event layers.
            if (editingMode === 'light' && map.layout && map.layout.length) {
                const lh = map.layout.length, lw = map.layout[0].length;
                const SUB = 4; // subdivisions per cell edge; mirrors the engine's per-pixel bilerp at display resolution
                const step = TILE_SIZE / SUB;

                for (let y = 0; y < lh; y++) {
                    for (let x = 0; x < lw; x++) {
                        const c00 = lightAt(map, x, y);
                        const c10 = lightAt(map, x + 1, y);
                        const c01 = lightAt(map, x, y + 1);
                        const c11 = lightAt(map, x + 1, y + 1);
                        for (let j = 0; j < SUB; j++) {
                            const fy = (j + 0.5) / SUB;
                            for (let i = 0; i < SUB; i++) {
                                const fx = (i + 0.5) / SUB;
                                const top = [0, 1, 2].map(k => c00[k] + (c10[k] - c00[k]) * fx);
                                const bot = [0, 1, 2].map(k => c01[k] + (c11[k] - c01[k]) * fx);
                                const col = top.map((v, k) => Math.round(Math.max(0, Math.min(1, v + (bot[k] - v) * fy)) * 255));
                                ctx.fillStyle = `rgba(${col[0]},${col[1]},${col[2]},0.6)`;
                                ctx.fillRect(x * TILE_SIZE + i * step, y * TILE_SIZE + j * step, step + 0.5, step + 0.5);
                            }
                        }
                    }
                }

                for (let vy = 0; vy <= lh; vy++) {
                    for (let vx = 0; vx <= lw; vx++) {
                        const v = lightAt(map, vx, vy);
                        const col = v.map(c => Math.round(Math.max(0, Math.min(1, c)) * 255));
                        ctx.beginPath();
                        ctx.arc(vx * TILE_SIZE, vy * TILE_SIZE, 4, 0, Math.PI * 2);
                        ctx.fillStyle = `rgb(${col[0]},${col[1]},${col[2]})`;
                        ctx.fill();
                        ctx.strokeStyle = 'rgba(0,0,0,0.6)';
                        ctx.lineWidth = 1;
                        ctx.stroke();
                    }
                }
            }
        }

        function initCanvasEvents(canvas) {
            canvas = canvas || document.getElementById('map-canvas');
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
                } else if (editingMode === 'light') {
                    if (e.button === 0) {
                        // Light is painted onto grid CORNERS, not cells, so the
                        // nearest vertex is a round() of the same pixel math the
                        // cell coords above use a floor() of.
                        const vx = Math.round((e.clientX - rect.left) / TILE_SIZE);
                        const vy = Math.round((e.clientY - rect.top) / TILE_SIZE);
                        isMouseDown = true;
                        paintLightAt(vx, vy);
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

                if (editingMode === 'light') {
                    // Vertices range 0..width/height inclusive (one more than
                    // cells), so this is bounds-checked separately below by
                    // paintLightAt rather than reusing the cell bounds check.
                    if (isMouseDown) {
                        const vx = Math.round((e.clientX - rect.left) / TILE_SIZE);
                        const vy = Math.round((e.clientY - rect.top) / TILE_SIZE);
                        paintLightAt(vx, vy);
                    }
                    return;
                }

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

            // E6: shared context-menu primitive (same one the command list
            // and scene canvas use) — replaces the bespoke
            // #canvas-context-menu popup so map/window editing look alike.
            const items = [];
            if (editingMode === 'event') {
                const existingEvent = (map.events || []).find(ev => ev.x === x && ev.y === y);
                if (existingEvent) {
                    items.push({ label: '✏️ Edit Event...', action: () => openEventModal(x, y) });
                    items.push({ label: '📋 Copy Event', action: () => { selectedEvent = existingEvent; eventCopyBuffer = JSON.stringify(existingEvent); } });
                    items.push({ label: '❌ Delete Event', action: () => {
                        map.events = map.events.filter(ev => ev !== existingEvent);
                        setDirty(true);
                        renderGridCells();
                    } });
                } else {
                    items.push({ label: '➕ Add Event Here...', action: () => openEventModal(x, y) });
                    items.push({ label: '📋 Paste Event', action: () => pasteEventAt(x, y), disabled: !eventCopyBuffer });
                }
                items.push('-');
            }
            items.push({ label: '🚩 Set Player Start Position Here', action: () => setPlayerStartPosition(x, y) });
            showCmdContextMenu(e.clientX, e.clientY, items);
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

            const map = dbPayload.maps[currentMapIndex];
            dbPayload.system.spawn.mapId = map ? map.id : dbPayload.system.spawn.mapId;
            dbPayload.system.spawn.x = x;
            dbPayload.system.spawn.y = y;

            setDirty(true);
            renderGridCells();
        }

        // --- LIGHT LAYER ("vertex colorer") ---
        // Paints map.light: a (layout height + 1) x (layout width + 1) grid of
        // [r,g,b] triples (each 0..1) over the map's grid *corners*, bilinearly
        // sampled per-channel by the raycaster per wall-slice column. See
        // docs/design/raycaster-tileset-lighting.md and engine/main.lua's
        // validator (dimension + per-vertex shape checks against layout size).
        // The color picker IS the paint value -- no separate intensity scalar,
        // since a dark/black pick already achieves low brightness directly.
        let lightBrushColor = [1, 1, 1]; // hex -> 0..1 via hexToRgb01 (events.js)
        let lightBrushRadius = 0;
        let lightToolMode = 'paint'; // 'paint' | 'blur'

        function setLightColor(hex) {
            lightBrushColor = hexToRgb01(hex);
        }

        function setLightTool(mode) {
            lightToolMode = mode;
            document.getElementById('light-color-row').style.display = mode === 'paint' ? 'flex' : 'none';
            document.getElementById('light-blur-hint').style.display = mode === 'blur' ? 'block' : 'none';
        }

        function setLightRadius(v) {
            lightBrushRadius = Math.max(0, Math.min(6, parseInt(v) || 0));
            document.getElementById('light-radius-value').textContent = lightBrushRadius;
        }

        // Round brush membership: vertices within `radius` grid units of
        // (cx, cy), Euclidean rather than the square block the brush used
        // to paint.
        function inBrush(dx, dy, radius) {
            return dx * dx + dy * dy <= radius * radius + 0.001;
        }

        // Lazily creates map.light filled with full-white brightness ([1,1,1]),
        // sized to match what the validator expects: layout height/width + 1
        // (vertices, not cells). Procedural maps have no fixed layout, so no
        // light grid.
        function ensureMapLight(map) {
            if (!map.layout || !map.layout.length) return null;
            if (map.light) return map.light;
            const h = map.layout.length + 1;
            const w = map.layout[0].length + 1;
            map.light = Array.from({ length: h }, () => Array.from({ length: w }, () => [1, 1, 1]));
            return map.light;
        }

        // A vertex's stored color, or full white if unset/absent (matches the
        // engine's default-brightness-1.0 behavior for maps without a light grid).
        function lightAt(map, vx, vy) {
            const v = map.light && map.light[vy] && map.light[vy][vx];
            return Array.isArray(v) ? v : [1, 1, 1];
        }

        // Clamped grid read for blur's neighbor sampling -- edges repeat their
        // nearest in-bounds vertex rather than pulling in a phantom [1,1,1].
        function clampedGridAt(grid, x, y, w, h) {
            const cx = Math.max(0, Math.min(w, x)), cy = Math.max(0, Math.min(h, y));
            const v = grid[cy] && grid[cy][cx];
            return Array.isArray(v) ? v : [1, 1, 1];
        }

        function paintLightAt(vx, vy) {
            const map = dbPayload.maps[currentMapIndex];
            if (!map || !map.layout || !map.layout.length) return;
            const h = map.layout.length, w = map.layout[0].length;
            if (vx < 0 || vx > w || vy < 0 || vy > h) return;

            const light = ensureMapLight(map);

            if (lightToolMode === 'blur') {
                // Single-pass box blur (3x3) over every vertex the round brush
                // covers, sampled from a snapshot so the pass doesn't feed
                // its own already-blurred neighbors within one stroke.
                const snapshot = light.map(row => row.map(c => c.slice()));
                for (let dy = -lightBrushRadius; dy <= lightBrushRadius; dy++) {
                    for (let dx = -lightBrushRadius; dx <= lightBrushRadius; dx++) {
                        if (!inBrush(dx, dy, lightBrushRadius)) continue;
                        const tx = vx + dx, ty = vy + dy;
                        if (tx < 0 || tx > w || ty < 0 || ty > h) continue;
                        const sum = [0, 0, 0];
                        for (let ny = ty - 1; ny <= ty + 1; ny++) {
                            for (let nx = tx - 1; nx <= tx + 1; nx++) {
                                const c = clampedGridAt(snapshot, nx, ny, w, h);
                                sum[0] += c[0]; sum[1] += c[1]; sum[2] += c[2];
                            }
                        }
                        light[ty][tx] = sum.map(v => v / 9);
                    }
                }
            } else {
                const color = lightBrushColor.slice();
                for (let dy = -lightBrushRadius; dy <= lightBrushRadius; dy++) {
                    for (let dx = -lightBrushRadius; dx <= lightBrushRadius; dx++) {
                        if (!inBrush(dx, dy, lightBrushRadius)) continue;
                        const tx = vx + dx, ty = vy + dy;
                        if (tx < 0 || tx > w || ty < 0 || ty > h) continue;
                        light[ty][tx] = color.slice();
                    }
                }
            }
            setDirty(true);
            renderGridCells();
        }

        function clearMapLight() {
            const map = dbPayload.maps[currentMapIndex];
            if (!map || !map.light) return;
            delete map.light;
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
        let mapPropsDirty = false;
        let mapPropsSnapshot = null;
        let mapPropsOriginal = null;

        function openMapProperties() {
            const map = dbPayload.maps[currentMapIndex];
            if (!map) return;

            mapPropsSnapshot = JSON.stringify(map);
            mapPropsOriginal = map;

            document.getElementById('prop-map-title').value = map.title || map.name || '';
            document.getElementById('prop-map-category').value = getMapCategory(map, currentMapIndex);
            document.getElementById('prop-map-gen').value = map.generation || 'Fixed';
            document.getElementById('prop-map-width').value = map.width || (map.layout ? map.layout[0].length : 15);
            document.getElementById('prop-map-height').value = map.height || (map.layout ? map.layout.length : 15);
            document.getElementById('prop-map-bgm').value = map.bgm || '';
            document.getElementById('prop-map-enc-steps').value = map.encounterSteps || 0;
            document.getElementById('prop-map-enc-rate').value = (map.encounterRate !== undefined) ? map.encounterRate : '';
            document.getElementById('prop-map-safe').checked = !!map.safe;
            document.getElementById('prop-map-ceiling').value = map.ceilingStyle || 'solid';

            mapPropsEncounters = JSON.parse(JSON.stringify(map.encounters || []));
            renderEncountersList(mapPropsEncounters);
            mapPropsDirty = false;
            document.getElementById('map-properties-modal').classList.add('active');
        }

        function closeMapPropertiesModal(force) {
            if (!force && mapPropsDirty && !confirmDiscard('Discard changes to this map\'s properties?')) return;

            // Revert only on discard: saveMapProperties() mutates the map then
            // calls close(true) while still dirty, so a force-path restore would
            // undo the save.
            if (!force && mapPropsDirty && mapPropsOriginal && mapPropsSnapshot) {
                const snap = JSON.parse(mapPropsSnapshot);
                Object.keys(mapPropsOriginal).forEach(k => delete mapPropsOriginal[k]);
                Object.assign(mapPropsOriginal, snap);
            }

            mapPropsSnapshot = null;
            mapPropsOriginal = null;
            mapPropsDirty = false;
            document.getElementById('map-properties-modal').classList.remove('active');
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
            const actors = dbPayload.actors || [];
            if (!actors.length) { showToast('No actors defined — add one in the Actors tab first.'); return; }

            const overlay = document.createElement('div');
            overlay.style.cssText = 'position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,0.3);display:flex;align-items:center;justify-content:center;';
            const box = document.createElement('div');
            box.style.cssText = 'min-width:280px;padding:10px;'
                + 'background:var(--win-gray);border:2px solid;'
                + 'border-color:var(--win-white) var(--win-shadow) var(--win-shadow) var(--win-white);'
                + 'display:flex;flex-direction:column;gap:8px;';

            const title = document.createElement('div');
            title.textContent = 'Add Encounter';
            title.style.cssText = 'font-weight:bold;';
            box.appendChild(title);

            const actorRow = document.createElement('div');
            actorRow.style.cssText = 'display:flex;align-items:center;gap:6px;';
            const actorLabel = document.createElement('label');
            actorLabel.textContent = 'Actor:';
            actorLabel.style.cssText = 'font-size:10px;min-width:50px;';
            const actorSelect = document.createElement('select');
            actorSelect.className = 'win98-select';
            actorSelect.style.flex = '1';
            actors.forEach(a => {
                const opt = document.createElement('option');
                opt.value = a.id;
                opt.textContent = `${a.name} (ID ${a.id})`;
                actorSelect.appendChild(opt);
            });
            actorRow.appendChild(actorLabel);
            actorRow.appendChild(actorSelect);
            box.appendChild(actorRow);

            const weightRow = document.createElement('div');
            weightRow.style.cssText = 'display:flex;align-items:center;gap:6px;';
            const weightLabel = document.createElement('label');
            weightLabel.textContent = 'Weight:';
            weightLabel.style.cssText = 'font-size:10px;min-width:50px;';
            const weightInput = document.createElement('input');
            weightInput.type = 'number';
            weightInput.className = 'win98-input';
            weightInput.value = '10';
            weightInput.style.flex = '1';
            weightRow.appendChild(weightLabel);
            weightRow.appendChild(weightInput);
            box.appendChild(weightRow);

            const btnRow = document.createElement('div');
            btnRow.style.cssText = 'display:flex;gap:6px;justify-content:flex-end;margin-top:4px;';
            const cancelBtn = document.createElement('button');
            cancelBtn.className = 'win98-btn';
            cancelBtn.textContent = 'Cancel';
            cancelBtn.onclick = () => overlay.remove();
            const okBtn = document.createElement('button');
            okBtn.className = 'win98-btn';
            okBtn.textContent = 'Add';
            okBtn.onclick = () => {
                const weight = parseInt(weightInput.value) || 10;
                mapPropsEncounters.push({ id: parseInt(actorSelect.value), weight: weight });
                mapPropsDirty = true;
                renderEncountersList(mapPropsEncounters);
                overlay.remove();
            };
            btnRow.appendChild(cancelBtn);
            btnRow.appendChild(okBtn);
            box.appendChild(btnRow);

            overlay.onclick = (e) => { if (e.target === overlay) overlay.remove(); };
            overlay.appendChild(box);
            document.body.appendChild(overlay);
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

            const ceilingStyle = document.getElementById('prop-map-ceiling').value;
            if (ceilingStyle === 'sky') map.ceilingStyle = 'sky';
            else delete map.ceilingStyle;

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