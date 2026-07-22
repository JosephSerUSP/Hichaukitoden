
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
        let selectedLightObject = null;
        let lightObjectCopyBuffer = null;
        let lightObjectDragging = false;
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
            selectedLightObject = null;
            lightObjectDragging = false;
            const lampSettings = document.getElementById('light-object-settings');
            if (lampSettings) lampSettings.style.display = 'none';
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

            if (editingMode === 'light') {
                const alpha = lightToolMode === 'object' ? 1 : 0.42;
                (map.lightObjects || []).forEach(light => {
                    ctx.save();
                    ctx.globalAlpha = alpha;
                    ctx.font = '16px sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
                    ctx.fillText('💡', (light.x + 0.5) * TILE_SIZE, (light.y + 0.5) * TILE_SIZE + 1);
                    if (light === selectedLightObject) {
                        ctx.strokeStyle = '#00a000'; ctx.lineWidth = 2;
                        ctx.strokeRect(light.x * TILE_SIZE + 1, light.y * TILE_SIZE + 1, TILE_SIZE - 2, TILE_SIZE - 2);
                    }
                    ctx.restore();
                });
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
                        if (lightToolMode === 'object') {
                            selectOrCreateLightObjectAt(x, y);
                            lightObjectDragging = !!selectedLightObject;
                            return;
                        }
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
                    if (lightObjectDragging && lightToolMode === 'object' && selectedLightObject) {
                        moveSelectedLamp(x, y);
                    } else if (isMouseDown && lightToolMode !== 'object') {
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
            if (editingMode === 'light' && lightToolMode === 'object' && lightObjectCopyBuffer && e.ctrlKey && e.key === 'v') {
                const canvas = document.getElementById('map-canvas');
                if (!canvas) return;
                const rect = canvas.getBoundingClientRect();
                pasteLampAt(Math.floor((mouseX - rect.left) / TILE_SIZE), Math.floor((mouseY - rect.top) / TILE_SIZE));
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
            document.getElementById('light-object-hint').style.display = mode === 'object' ? 'block' : 'none';
            document.getElementById('light-object-settings').style.display = mode === 'object' && selectedLightObject ? 'block' : 'none';
            renderGridCells();
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
        let mapPropsOriginal = null;

        const mapPropsSnapshotHelper = window.createSnapshotModal({
            getSnapshotSource: () => mapPropsOriginal,
            getIsDirty: () => mapPropsDirty,
            onRestore: (snap, originalData) => {
                if (originalData && snap) {
                    Object.keys(originalData).forEach(k => delete originalData[k]);
                    Object.assign(originalData, snap);
                }
            },
            confirmMessage: 'Discard changes to this map\'s properties?'
        });

        function toggleFogFields() {
            const enabled = document.getElementById('prop-map-fog-enabled').checked;
            document.getElementById('prop-fog-settings').style.display = enabled ? 'block' : 'none';
            if (enabled) { populateFogPresetDropdown(); onFogPresetChange(); }
        }

        // Fog presets (dbPayload.engine.fogPresets, docs/design/
        // fog-presets-and-panorama.md): shared configs a map can reference
        // instead of carrying its own color/density/panorama. "(custom)"
        // keeps this map's own inline fields, which is what the dropdown
        // defaults to for maps that don't reference a preset.
        function populateFogPresetDropdown() {
            const sel = document.getElementById('prop-map-fog-preset');
            const map = dbPayload.maps[currentMapIndex];
            const currentPresetId = (map && map.fog && map.fog.preset) || '';
            sel.innerHTML = '';
            const customOpt = document.createElement('option');
            customOpt.value = '';
            customOpt.textContent = '(custom -- this map\'s own values below)';
            sel.appendChild(customOpt);
            (dbPayload.engine.fogPresets || []).forEach(p => {
                const opt = document.createElement('option');
                opt.value = p.id;
                opt.textContent = p.label || p.id;
                sel.appendChild(opt);
            });
            sel.value = currentPresetId;
        }

        function onFogPresetChange() {
            const usingPreset = document.getElementById('prop-map-fog-preset').value !== '';
            document.getElementById('prop-fog-custom-fields').style.display = usingPreset ? 'none' : 'block';
            setDirty(true);
        }

        // Fog presets: click a button to set color + label
        function setFogPreset(hex, label) {
            document.getElementById('prop-map-fog-color').value = hex;
            document.getElementById('prop-map-fog-label').value = label;
            updateFogPreview();
        }

        // Draw the fog preview canvas: a horizontal strip showing how tiles
        // blend from their original color (left) into the fog color (right)
        // at the configured density and minFactor values.
        function updateFogPreview() {
            const canvas = document.getElementById('fog-preview-canvas');
            if (!canvas) return;
            const ctx = canvas.getContext('2d');
            const w = canvas.width, h = canvas.height;

            const hex = document.getElementById('prop-map-fog-color').value;
            const fogRgb = hexToRgb01(hex);
            const density = parseFloat(document.getElementById('prop-map-fog-density').value) || 0.35;
            const minFactor = parseFloat(document.getElementById('prop-map-fog-minfactor').value) || 0.12;

            // Simulate a stone wall tile (dark grey) and render fog mixing
            // per pixel across the strip, left = near, right = far.
            const wallColor = [0.45, 0.40, 0.35]; // a generic stone wall

            for (let x = 0; x < w; x++) {
                // Map x position to distance (0..12 grid units)
                const dist = (x / w) * 12;
                const fogAlpha = Math.max(minFactor, 1.0 / (1.0 + dist * density));

                // Wall: fogColor * (1-fogAlpha) + wallColor * fogAlpha
                const r = Math.round((fogRgb[0] * (1 - fogAlpha) + wallColor[0] * fogAlpha) * 255);
                const g = Math.round((fogRgb[1] * (1 - fogAlpha) + wallColor[1] * fogAlpha) * 255);
                const b = Math.round((fogRgb[2] * (1 - fogAlpha) + wallColor[2] * fogAlpha) * 255);

                ctx.fillStyle = `rgb(${r},${g},${b})`;
                ctx.fillRect(x, 0, 1, h);
            }

            // Overlay distance markers
            ctx.fillStyle = 'rgba(255,255,255,0.5)';
            ctx.font = '7px sans-serif';
            ctx.fillText('←near', 2, 8);
            ctx.textAlign = 'right';
            ctx.fillText('far→', w - 2, 8);
            ctx.textAlign = 'left';
        }

        function openMapProperties() {
            const map = dbPayload.maps[currentMapIndex];
            if (!map) return;

            mapPropsOriginal = map;
            mapPropsSnapshotHelper.capture();

            document.getElementById('prop-map-title').value = map.title || map.name || '';
            document.getElementById('prop-map-category').value = getMapCategory(map, currentMapIndex);
            document.getElementById('prop-map-gen').value = map.generation || 'Fixed';
            document.getElementById('prop-map-width').value = map.width || (map.layout ? map.layout[0].length : 15);
            document.getElementById('prop-map-height').value = map.height || (map.layout ? map.layout.length : 15);
            document.getElementById('prop-map-bgm').value = map.bgm || '';
            document.getElementById('prop-map-enc-steps').value = map.encounterSteps || 0;
            document.getElementById('prop-map-enc-rate').value = (map.encounterRate !== undefined) ? map.encounterRate : '';
            document.getElementById('prop-map-safe').checked = !!map.safe;
            document.getElementById('prop-map-tileset').value = map.tileset || '';
            document.getElementById('prop-map-ceiling').value = map.ceilingStyle || 'solid';

            // Fog properties
            const fog = map.fog;
            if (fog) {
                document.getElementById('prop-map-fog-enabled').checked = true;
                document.getElementById('prop-map-fog-color').value = rgb01ToHex(fog.color || [0.5, 0.55, 0.6]);
                document.getElementById('prop-map-fog-density').value = fog.density != null ? fog.density : 0.35;
                document.getElementById('prop-map-fog-density-val').textContent = fog.density != null ? fog.density : '0.35';
                document.getElementById('prop-map-fog-minfactor').value = fog.minFactor != null ? fog.minFactor : 0.12;
                document.getElementById('prop-map-fog-minfactor-val').textContent = fog.minFactor != null ? fog.minFactor : '0.12';
            } else {
                document.getElementById('prop-map-fog-enabled').checked = false;
                document.getElementById('prop-map-fog-color').value = '#73808a';
                document.getElementById('prop-map-fog-density').value = 0.35;
                document.getElementById('prop-map-fog-density-val').textContent = '0.35';
                document.getElementById('prop-map-fog-minfactor').value = 0.12;
                document.getElementById('prop-map-fog-minfactor-val').textContent = '0.12';
            }
            toggleFogFields();

            // Label preset and draw preview
            const fhex = document.getElementById('prop-map-fog-color').value.toUpperCase();
            const pLabels = { '#FFFFFF': 'White Mist', '#A0C4E8': 'Pale Blue', '#73808A': 'Blue Haze', '#333344': 'Dark Fog', '#1A1A2E': 'Underground', '#4A3066': 'Purple Dusk' };
            document.getElementById('prop-map-fog-label').value = pLabels[fhex] || 'Custom';
            updateFogPreview();

            mapPropsEncounters = JSON.parse(JSON.stringify(map.encounters || []));
            renderEncountersList(mapPropsEncounters);
            mapPropsDirty = false;
            document.getElementById('map-properties-modal').classList.add('active');
        }

        function closeMapPropertiesModal(force) {
            if (!mapPropsSnapshotHelper.close(force)) return;

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

            const tileset = document.getElementById('prop-map-tileset').value.trim();
            if (tileset) map.tileset = tileset;
            else delete map.tileset;

            const ceilingStyle = document.getElementById('prop-map-ceiling').value;
            if (ceilingStyle === 'sky') map.ceilingStyle = 'sky';
            else delete map.ceilingStyle;

            // Fog settings. NaN-checked rather than ||-defaulted: a
            // minFactor of 0 (fully fogged at distance) is a legitimate
            // slider value that || would silently replace with the default.
            const fogPresetId = document.getElementById('prop-map-fog-preset').value;
            if (document.getElementById('prop-map-fog-enabled').checked && fogPresetId) {
                // Shared preset reference (docs/design/fog-presets-and-panorama.md)
                // -- no inline fields, so editing the preset in Engine Editor
                // updates this map too.
                map.fog = { preset: fogPresetId };
            } else if (document.getElementById('prop-map-fog-enabled').checked) {
                const density = parseFloat(document.getElementById('prop-map-fog-density').value);
                const minFactor = parseFloat(document.getElementById('prop-map-fog-minfactor').value);
                map.fog = {
                    color: hexToRgb01(document.getElementById('prop-map-fog-color').value),
                    density: isNaN(density) ? 0.35 : density,
                    minFactor: isNaN(minFactor) ? 0.12 : minFactor,
                };
            } else {
                delete map.fog;
            }

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

        // map.tileset is a bare atlas name (e.g. "dungeon_001"), not a path --
        // the engine resolves it to assets/tilesets/<name>.png itself
        // (viewport_3d.lua resolveTileset/getAtlas). Strip the picked file
        // down to that name.
        function openAssetPickerForTileset() {
            openAssetPicker('tilesets', (path) => {
                const filename = path.split('/').pop();
                document.getElementById('prop-map-tileset').value = filename.replace(/\.[^/.]+$/, '');
            });
        }

        function refreshSelectedLampSettings() {
            const panel = document.getElementById('light-object-settings');
            panel.style.display = selectedLightObject ? 'block' : 'none';
            if (!selectedLightObject) return;
            document.getElementById('lamp-color').value = rgb01ToHex(selectedLightObject.color || [1, 0.58, 0.22]);
            document.getElementById('lamp-radius').value = selectedLightObject.radius || 4;
            document.getElementById('lamp-falloff').value = selectedLightObject.falloff || 2;
            document.getElementById('lamp-material').value = selectedLightObject.material || '';
        }

        function selectOrCreateLightObjectAt(x, y) {
            const map = dbPayload.maps[currentMapIndex];
            if (!map || x < 0 || y < 0) return;
            map.lightObjects = map.lightObjects || [];
            selectedLightObject = map.lightObjects.find(l => l.x === x && l.y === y);
            if (!selectedLightObject) {
                selectedLightObject = { x, y, color: [1, 0.58, 0.22], radius: 4, falloff: 2, material: 'wall_torch' };
                map.lightObjects.push(selectedLightObject);
            }
            refreshSelectedLampSettings();
            setDirty(true);
            renderGridCells();
        }

        function moveSelectedLamp(x, y) {
            const map = dbPayload.maps[currentMapIndex];
            if (!map || !selectedLightObject || x < 0 || y < 0) return;
            const occupied = (map.lightObjects || []).find(l => l !== selectedLightObject && l.x === x && l.y === y);
            if (occupied || (selectedLightObject.x === x && selectedLightObject.y === y)) return;
            selectedLightObject.x = x; selectedLightObject.y = y;
            setDirty(true); renderGridCells();
        }

        function updateSelectedLamp(key, value) {
            if (!selectedLightObject) return;
            selectedLightObject[key] = key === 'color' ? hexToRgb01(value) : (key === 'material' ? value.trim() : Math.max(0.1, parseFloat(value) || 0.1));
            setDirty(true); renderGridCells();
        }

        function copySelectedLamp() {
            if (selectedLightObject) lightObjectCopyBuffer = JSON.stringify(selectedLightObject);
        }

        function pasteLampAt(x, y) {
            const map = dbPayload.maps[currentMapIndex];
            if (!map || !lightObjectCopyBuffer || x < 0 || y < 0 || (map.lightObjects || []).some(l => l.x === x && l.y === y)) return;
            selectedLightObject = JSON.parse(lightObjectCopyBuffer);
            selectedLightObject.x = x; selectedLightObject.y = y;
            map.lightObjects = map.lightObjects || []; map.lightObjects.push(selectedLightObject);
            refreshSelectedLampSettings(); setDirty(true); renderGridCells();
        }

        function deleteSelectedLamp() {
            const map = dbPayload.maps[currentMapIndex];
            if (!map || !selectedLightObject) return;
            map.lightObjects = (map.lightObjects || []).filter(l => l !== selectedLightObject);
            selectedLightObject = null; refreshSelectedLampSettings(); setDirty(true); renderGridCells();
        }

        function bakeVisible(grid, x0, y0, x1, y1) {
            let dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
            let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx - dy;
            let x = x0, y = y0;
            while (x !== x1 || y !== y1) {
                if ((x !== x0 || y !== y0) && (!grid[y] || grid[y][x] === '#')) return false;
                const e2 = err * 2;
                if (e2 > -dy) { err -= dy; x += sx; }
                if (e2 < dx) { err += dx; y += sy; }
            }
            return true;
        }

        // Bake is intentionally explicit: it replaces the baseline grid; any
        // subsequent Paint stroke becomes the artist's direct override.
        function bakeMapLighting() {
            const map = dbPayload.maps[currentMapIndex];
            if (!map || !map.layout || !map.layout.length) return;
            const h = map.layout.length, w = map.layout[0].length, ambient = [0.12, 0.12, 0.12];
            const out = Array.from({ length: h + 1 }, () => Array.from({ length: w + 1 }, () => ambient.slice()));
            (map.lightObjects || []).forEach(source => {
                const radius = Math.max(0.1, source.radius || 4), color = source.color || [1, 0.58, 0.22];
                for (let vy = Math.max(0, Math.floor(source.y - radius)); vy <= Math.min(h, Math.ceil(source.y + radius)); vy++) {
                    for (let vx = Math.max(0, Math.floor(source.x - radius)); vx <= Math.min(w, Math.ceil(source.x + radius)); vx++) {
                        const dx = vx - (source.x + 0.5), dy = vy - (source.y + 0.5), d = Math.hypot(dx, dy);
                        if (d > radius || !bakeVisible(map.layout, source.x, source.y, Math.max(0, Math.min(w - 1, vx)), Math.max(0, Math.min(h - 1, vy)))) continue;
                        const s = Math.pow(1 - d / radius, source.falloff || 2);
                        for (let c = 0; c < 3; c++) out[vy][vx][c] = Math.min(1, out[vy][vx][c] + color[c] * s);
                    }
                }
            });
            canvas.addEventListener('mouseup', () => { lightObjectDragging = false; });
            map.light = out;
            setDirty(true);
            renderGridCells();
        }
