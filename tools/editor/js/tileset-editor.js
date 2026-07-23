// ============================================================================
// TILESET STUDIO MODULE
// ----------------------------------------------------------------------------
// Rewritten per docs/design/tileset-and-events-redesign.md §7: the atlas
// canvas is a COORDINATE PICKER, not the primary authoring surface. The
// primary surface is the Tile Assignments list on the right -- real N-way
// weighted pools per structural role (base.walls/floors/ceilings, plus
// features/doors), fixing the old editor's core bug: the "Wall" tool always
// overwrote base.walls[0], so `weight` fields existed with nothing to weigh
// against. Clicking the atlas now assigns coordinates into whichever pool
// entry is selected in the list -- or creates a new one if none is selected.
//
// Weighted/adjacency-predicate RESOLUTION (§3: real random selection at
// generation/render time, prefabs, zone tags) is still open design work.
// This module only fixes the AUTHORING side: it's now possible to actually
// create a second variant to weigh against the first.
// ============================================================================
(function() {
    let currentTilesetId = 'dungeon_default';
    let tilesetsList = [];
    let textureFilesList = [];
    let tilesetData = null;
    let atlasImage = null;
    let canvasZoom = 1.5;

    // Which tile role is being authored, and which assignment in it is selected.
    // selectedVariantRef is a direct object reference into tilesetData (base
    // .walls/.floors/.ceilings/.features/.doors) -- deletion/mutation always
    // goes through the backing array so pool membership stays truthful.
    let activeRole = 'wall'; // 'wall' | 'floor' | 'ceiling' | 'wall_feature' | 'floor_feature' | 'door'
    let selectedVariantRef = null;

    let isMouseDownOnCanvas = false;

    window.openTilesetStudioModal = function() {
        const modal = document.getElementById('tileset-studio-modal');
        if (modal) {
            modal.style.display = 'flex';
            loadTilesetList();
            setupCanvasEvents();
        }
    };

    window.openTilesetStudioForCurrentMap = function() {
        const sel = document.getElementById('prop-map-tileset');
        if (sel && sel.value) {
            currentTilesetId = sel.value;
        }
        window.openTilesetStudioModal();
    };

    window.closeTilesetStudioModal = function() {
        const modal = document.getElementById('tileset-studio-modal');
        if (modal) modal.style.display = 'none';
    };

    window.onCanvasZoomChanged = function(zoomVal) {
        canvasZoom = parseFloat(zoomVal) || 1.5;
        renderAtlasCanvas();
    };

    // --- TILE ROLE TABS ----------------------------------------------------

    const ROLE_IDS = ['wall', 'floor', 'ceiling', 'wall_feature', 'floor_feature', 'door'];

    window.setActiveRole = function(role) {
        activeRole = role;
        // Most tilesets have one primary tile for a role. Selecting that
        // assignment immediately makes role → atlas-click a direct edit,
        // rather than unexpectedly creating a second wall/floor/sky tile.
        // "Add Tile" remains the explicit way to create another variant.
        selectedVariantRef = getPoolArray(role)[0] || null;
        ROLE_IDS.forEach(r => {
            const btn = document.getElementById(`ts-role-${r}`);
            if (btn) btn.classList.toggle('active', r === role);
        });
        renderVariantList();
        renderVariantDetail();
        renderAtlasCanvas();
    };

    // --- ROLE ASSIGNMENT ACCESS ---------------------------------------------
    // Wall/floor/ceiling/door pools are their own backing arrays; the two
    // feature roles share tilesetData.features (filtered by .role), so
    // deletion has to splice the SHARED array, not a filtered copy.

    function getPoolArray(role) {
        if (!tilesetData) return [];
        if (role === 'wall') return tilesetData.base.walls;
        if (role === 'floor') return tilesetData.base.floors;
        if (role === 'ceiling') return tilesetData.base.ceilings;
        if (role === 'door') return tilesetData.doors;
        return tilesetData.features.filter(f => f.role === role);
    }

    function nextVariantId(role) {
        const n = getPoolArray(role).length + 1;
        return `${role}_${n}`;
    }

    window.addPoolVariant = function() {
        if (!tilesetData) return;
        let variant;
        if (activeRole === 'wall') {
            variant = { id: nextVariantId('wall'), role: 'base_wall', middle: [0, 0], leftEdge: [0, 0, 0], rightEdge: [0, 0, 32], weight: 100 };
            tilesetData.base.walls.push(variant);
        } else if (activeRole === 'floor') {
            variant = { id: nextVariantId('floor'), role: 'base_floor', atlas: [0, 0], weight: 100, heightOffset: 0.0 };
            tilesetData.base.floors.push(variant);
        } else if (activeRole === 'ceiling') {
            variant = { id: nextVariantId('ceiling'), role: 'base_ceiling', atlas: [0, 0], weight: 100 };
            tilesetData.base.ceilings.push(variant);
        } else if (activeRole === 'door') {
            variant = { id: nextVariantId('door'), role: 'door', atlas: [0, 0] };
            tilesetData.doors.push(variant);
        } else { // wall_feature | floor_feature
            variant = { id: nextVariantId(activeRole), role: activeRole, atlas: [0, 0], injectProbability: 0.12 };
            tilesetData.features.push(variant);
        }
        selectedVariantRef = variant;
        renderVariantList();
        renderVariantDetail();
        renderAtlasCanvas();
    };

    window.deletePoolVariant = function() {
        if (!tilesetData || !selectedVariantRef) return;
        const backing = activeRole === 'wall' ? tilesetData.base.walls
            : activeRole === 'floor' ? tilesetData.base.floors
            : activeRole === 'ceiling' ? tilesetData.base.ceilings
            : activeRole === 'door' ? tilesetData.doors
            : tilesetData.features; // wall_feature / floor_feature share this array
        const idx = backing.indexOf(selectedVariantRef);
        if (idx >= 0) backing.splice(idx, 1);
        selectedVariantRef = null;
        renderVariantList();
        renderVariantDetail();
        renderAtlasCanvas();
    };

    window.selectPoolVariant = function(variant) {
        selectedVariantRef = variant;
        renderVariantList();
        renderVariantDetail();
        renderAtlasCanvas();
    };

    window.updateSelectedVariant = function(key, value) {
        if (!selectedVariantRef) return;
        const v = selectedVariantRef;
        if (key === 'id') {
            v.id = value.trim() || v.id;
        } else if (key === 'weight') {
            const n = parseInt(value);
            v.weight = isNaN(n) ? 100 : Math.max(1, n);
        } else if (key === 'heightOffset') {
            const n = parseFloat(value);
            v.heightOffset = isNaN(n) ? 0 : n;
        } else if (key === 'injectProbability') {
            const n = parseFloat(value);
            v.injectProbability = isNaN(n) ? 0.12 : Math.max(0, Math.min(100, n)) / 100;
        } else if (key === 'requiresAdjacentFloor') {
            if (value) v.requiresAdjacentFloor = true; else delete v.requiresAdjacentFloor;
        } else if (key === 'emitsLightToggle') {
            if (value) {
                v.emitsLight = v.emitsLight || { color: [1, 0.58, 0.22], radius: 4, falloff: 2 };
            } else {
                delete v.emitsLight;
            }
        } else if (key === 'lightColor') {
            if (!v.emitsLight) return;
            v.emitsLight.color = hexToRgb01(value);
        } else if (key === 'lightRadius') {
            if (!v.emitsLight) return;
            const n = parseFloat(value);
            v.emitsLight.radius = isNaN(n) ? 4 : n;
        } else if (key === 'lightFalloff') {
            if (!v.emitsLight) return;
            const n = parseFloat(value);
            v.emitsLight.falloff = isNaN(n) ? 2 : n;
        }
        renderVariantList();
        renderVariantDetail();
        renderAtlasCanvas();
        renderCompositePreview();
    };

    function hexToRgb01(hex) {
        const m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || '');
        if (!m) return [1, 1, 1];
        return [parseInt(m[1], 16) / 255, parseInt(m[2], 16) / 255, parseInt(m[3], 16) / 255];
    }

    function rgb01ToHex(c) {
        return '#' + (c || [1, 1, 1]).map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, '0')).join('');
    }

    function variantAtlas(v) {
        // Walls use `middle` as their primary coordinate; everything else uses `atlas`.
        return v.middle || v.atlas || [0, 0];
    }

    // --- LOADING --------------------------------------------------------------

    async function loadTilesetList() {
        try {
            const resp = await fetch('/api/tilesets');
            if (resp.ok) {
                const data = await resp.json();
                tilesetsList = data.tilesets || [];
                textureFilesList = data.textures || [];

                const selectTs = document.getElementById('ts-select-tileset');
                if (selectTs) {
                    selectTs.innerHTML = '';
                    tilesetsList.forEach(ts => {
                        const opt = document.createElement('option');
                        opt.value = ts.id;
                        opt.textContent = `${ts.name || ts.id} (${ts.id})`;
                        selectTs.appendChild(opt);
                    });
                    if (currentTilesetId && tilesetsList.some(t => t.id === currentTilesetId)) {
                        selectTs.value = currentTilesetId;
                    } else if (tilesetsList.length > 0) {
                        currentTilesetId = tilesetsList[0].id;
                        selectTs.value = currentTilesetId;
                    }
                }

                const selectTex = document.getElementById('ts-select-texture');
                if (selectTex) {
                    selectTex.innerHTML = '';
                    textureFilesList.forEach(tex => {
                        const opt = document.createElement('option');
                        opt.value = `assets/tilesets/${tex}`;
                        opt.textContent = tex;
                        selectTex.appendChild(opt);
                    });
                }
            }
        } catch (e) {
            console.warn('Failed to load tilesets list:', e);
        }
        if (currentTilesetId) {
            loadTilesetData(currentTilesetId);
        }
    }

    window.onTilesetSelected = function(id) {
        currentTilesetId = id;
        loadTilesetData(id);
    };

    async function loadTilesetData(id) {
        const found = tilesetsList.find(t => t.id === id);
        tilesetData = found ? JSON.parse(JSON.stringify(found)) : createDefaultTilesetData(id);
        tilesetData.base = tilesetData.base || { walls: [], floors: [], ceilings: [] };
        tilesetData.base.walls = tilesetData.base.walls || [];
        tilesetData.base.floors = tilesetData.base.floors || [];
        tilesetData.base.ceilings = tilesetData.base.ceilings || [];
        tilesetData.doors = tilesetData.doors || [];
        tilesetData.features = tilesetData.features || [];

        const nameInput = document.getElementById('ts-tileset-name');
        if (nameInput) nameInput.value = tilesetData.name || id;

        const selectTex = document.getElementById('ts-select-texture');
        const texPath = tilesetData.texture || 'assets/tilesets/dungeon_001.png';
        if (selectTex) selectTex.value = texPath;

        selectedVariantRef = null;
        setActiveRole(activeRole);
        loadAtlasTexture(texPath);
    }

    function loadAtlasTexture(texPath) {
        atlasImage = new Image();
        atlasImage.onload = () => {
            renderAtlasCanvas();
            renderCompositePreview();
        };
        atlasImage.onerror = () => {
            console.warn('Failed to load texture image:', texPath);
        };
        atlasImage.src = '/' + texPath + '?t=' + Date.now();
    }

    window.onTextureSelected = function(texPath) {
        if (!tilesetData) return;
        tilesetData.texture = texPath;
        loadAtlasTexture(texPath);
    };

    function createDefaultTilesetData(id) {
        return {
            id: id,
            name: id,
            texture: 'assets/tilesets/template_tileset.png',
            tileWidth: 64,
            tileHeight: 64,
            base: { walls: [], floors: [], ceilings: [] },
            doors: [],
            features: []
        };
    }

    // --- CANVAS: coordinate picker for the selected tile assignment ----------

    function setupCanvasEvents() {
        const canvas = document.getElementById('ts-atlas-canvas');
        if (!canvas || canvas.dataset.eventsBound) return;
        canvas.dataset.eventsBound = 'true';

        canvas.addEventListener('mousedown', (e) => {
            isMouseDownOnCanvas = true;
            handleCanvasPointer(e);
        });

        canvas.addEventListener('mousemove', (e) => {
            if (isMouseDownOnCanvas) handleCanvasPointer(e);
        });

        window.addEventListener('mouseup', () => {
            isMouseDownOnCanvas = false;
        });
    }

    function handleCanvasPointer(e) {
        const canvas = document.getElementById('ts-atlas-canvas');
        if (!canvas || !atlasImage || !tilesetData) return;
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        const baseTw = tilesetData.tileWidth || 64;
        const baseTh = tilesetData.tileHeight || 64;
        const tw = baseTw * canvasZoom;
        const th = baseTh * canvasZoom;

        const col = Math.floor(mouseX / tw);
        const row = Math.floor(mouseY / th);

        const atlasCols = Math.floor(atlasImage.width / baseTw);
        const atlasRows = Math.floor(atlasImage.height / baseTh);
        if (col < 0 || row < 0 || col >= atlasCols || row >= atlasRows) return;

        // A wall occupies a two-cell block: its main texture plus an adjacent
        // edge cell. Do not let a click at the right edge create bad data.
        if (activeRole === 'wall' && col + 1 >= atlasCols) {
            alert('A Wall needs two adjacent cells: main wall on the left, autotile edges on the right.');
            return;
        }

        if (!selectedVariantRef) {
            // Nothing selected: make an assignment for the active role. Once
            // selected, further clicks move that assignment rather than
            // silently changing a different tile.
            addPoolVariant();
        }

        if (activeRole === 'wall') {
            // A base wall is a fixed 128x64 block: the clicked cell is the
            // middle texture, and the cell immediately to its right holds
            // BOTH autotile edges as its left/right 32px halves (the engine
            // already renders leftEdge/rightEdge as sub-slices of one cell,
            // offX 0 vs 32 -- viewport_3d.lua:838-851 -- so this is just
            // making the editor assign what the renderer already expects
            // instead of exposing three independently-clickable slots).
            selectedVariantRef.middle = [row, col];
            selectedVariantRef.leftEdge = [row, col + 1, 0];
            selectedVariantRef.rightEdge = [row, col + 1, 32];
        } else {
            selectedVariantRef.atlas = [row, col];
        }

        renderVariantList();
        renderVariantDetail();
        renderAtlasCanvas();
        renderCompositePreview();
    }

    function renderAtlasCanvas() {
        const canvas = document.getElementById('ts-atlas-canvas');
        if (!canvas || !atlasImage || !tilesetData) return;
        const ctx = canvas.getContext('2d');

        const baseTw = tilesetData.tileWidth || 64;
        const baseTh = tilesetData.tileHeight || 64;

        canvas.width = Math.round(atlasImage.width * canvasZoom);
        canvas.height = Math.round(atlasImage.height * canvasZoom);

        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.imageSmoothingEnabled = false;
        ctx.drawImage(atlasImage, 0, 0, canvas.width, canvas.height);

        const tw = baseTw * canvasZoom;
        const th = baseTh * canvasZoom;
        const cols = Math.floor(atlasImage.width / baseTw);
        const rows = Math.floor(atlasImage.height / baseTh);

        for (let r = 0; r < rows; r++) {
            for (let c = 0; c < cols; c++) {
                const x = c * tw, y = r * th;
                const tileDef = findTileDefAt(r, c);
                let label = '', color = 'rgba(255, 255, 255, 0.7)';
                if (tileDef) {
                    if (tileDef.role === 'wall_feature') { label = '🔥'; color = '#ff9900'; }
                    else if (tileDef.role === 'floor_feature') { label = '💧'; color = '#00ccff'; }
                    else if (tileDef.role === 'autotile_left_edge') { label = '📐L'; color = '#00ffff'; }
                    else if (tileDef.role === 'autotile_right_edge') { label = '📐R'; color = '#00ffff'; }
                    else if (tileDef.role === 'base_wall') { label = 'W'; color = '#3399ff'; }
                    else if (tileDef.role === 'base_ceiling') { label = 'S'; color = '#aa66ff'; }
                    else if (tileDef.role === 'door') { label = 'D'; color = '#ffcc00'; }
                    else if (tileDef.role === 'base_floor') { label = 'F'; color = '#33cc66'; }
                }
                if (label) {
                    ctx.font = `bold ${Math.round(13 * canvasZoom)}px sans-serif`;
                    ctx.fillStyle = color;
                    ctx.fillText(label, x + (4 * canvasZoom), y + (18 * canvasZoom));
                }
            }
        }

        ctx.strokeStyle = 'rgba(255, 255, 255, 0.3)';
        ctx.lineWidth = 1;
        for (let x = 0; x <= canvas.width; x += tw) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, canvas.height); ctx.stroke(); }
        for (let y = 0; y <= canvas.height; y += th) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(canvas.width, y); ctx.stroke(); }

        // Highlight every cell the SELECTED variant currently occupies (for
        // walls: middle + both edges can be three different cells).
        if (selectedVariantRef) {
            ctx.strokeStyle = '#00ff00';
            ctx.lineWidth = Math.max(2, Math.round(3 * canvasZoom));
            const cells = activeRole === 'wall'
                ? [selectedVariantRef.middle, selectedVariantRef.leftEdge, selectedVariantRef.rightEdge].filter(Boolean)
                : [selectedVariantRef.atlas].filter(Boolean);
            cells.forEach(cell => {
                ctx.strokeRect(cell[1] * tw + 1, cell[0] * th + 1, tw - 2, th - 2);
            });
        }
    }

    // findTileDefAt scans every role for a badge at (row, col) -- purely
    // a read-only lookup for the atlas overlay, unrelated to what's selected.
    function findTileDefAt(row, col) {
        if (!tilesetData) return null;
        for (const f of (tilesetData.features || [])) {
            if (f.atlas && f.atlas[0] === row && f.atlas[1] === col) return f;
        }
        for (const d of (tilesetData.doors || [])) {
            if (d.atlas && d.atlas[0] === row && d.atlas[1] === col) return { ...d, role: 'door' };
        }
        for (const w of (tilesetData.base?.walls || [])) {
            if (w.middle && w.middle[0] === row && w.middle[1] === col) return { ...w, role: 'base_wall' };
            if (w.leftEdge && w.leftEdge[0] === row && w.leftEdge[1] === col) return { ...w, role: 'autotile_left_edge' };
            if (w.rightEdge && w.rightEdge[0] === row && w.rightEdge[1] === col) return { ...w, role: 'autotile_right_edge' };
        }
        for (const f of (tilesetData.base?.floors || [])) {
            if (f.atlas && f.atlas[0] === row && f.atlas[1] === col) return { ...f, role: 'base_floor' };
        }
        for (const c of (tilesetData.base?.ceilings || [])) {
            if (c.atlas && c.atlas[0] === row && c.atlas[1] === col) return { ...c, role: 'base_ceiling' };
        }
        return null;
    }

    // --- SIDEBAR: variant list + detail form -----------------------------------

    function renderVariantList() {
        const list = document.getElementById('ts-variant-list');
        if (!list) return;
        list.innerHTML = '';
        const pool = getPoolArray(activeRole);
        if (pool.length === 0) {
            const empty = document.createElement('div');
            empty.style.cssText = 'padding: 6px; font-size: 10px; color: #888;';
            empty.textContent = 'Nothing assigned yet — click "Add Tile" or click the atlas.';
            list.appendChild(empty);
            return;
        }
        pool.forEach(v => {
            const row = document.createElement('div');
            const a = variantAtlas(v);
            const isSelected = v === selectedVariantRef;
            row.style.cssText = `padding: 3px 6px; font-size: 11px; cursor: pointer; display: flex; justify-content: space-between; ${isSelected ? 'background: #316ac5; color: #fff;' : ''}`;
            const weightPart = (v.weight !== undefined) ? ` · w${v.weight}` : '';
            row.innerHTML = `<span>${v.id}</span><span>[${a[0]},${a[1]}]${weightPart}</span>`;
            row.onclick = () => window.selectPoolVariant(v);
            list.appendChild(row);
        });
    }

    function renderVariantDetail() {
        const detail = document.getElementById('ts-variant-detail');
        if (!detail) return;
        if (!selectedVariantRef) {
            detail.style.display = 'none';
            return;
        }
        detail.style.display = 'flex';
        const v = selectedVariantRef;

        document.getElementById('ts-v-id').value = v.id || '';

        const isWeighted = activeRole === 'wall' || activeRole === 'floor' || activeRole === 'ceiling';
        document.getElementById('ts-v-weight-row').style.display = isWeighted ? 'flex' : 'none';
        if (isWeighted) document.getElementById('ts-v-weight').value = v.weight || 100;

        const isWall = activeRole === 'wall';
        document.getElementById('ts-v-wallslot-row').style.display = isWall ? 'block' : 'none';
        document.getElementById('ts-v-atlas-row').style.display = isWall ? 'none' : 'flex';
        if (isWall) {
            const m = v.middle || [0, 0], l = v.leftEdge || ['-', '-'], r = v.rightEdge || ['-', '-'];
            document.getElementById('ts-v-wallslot-coords').textContent =
                `Middle [${m[0]},${m[1]}]  ·  Edges [${l[0]},${l[1]}] (left/right halves)`;
        } else {
            const a = variantAtlas(v);
            document.getElementById('ts-v-atlas-display').textContent = `[${a[0]}, ${a[1]}]`;
        }

        const isFloor = activeRole === 'floor';
        document.getElementById('ts-v-height-row').style.display = isFloor ? 'flex' : 'none';
        if (isFloor) document.getElementById('ts-v-height').value = v.heightOffset || 0;

        const isFeature = activeRole === 'wall_feature' || activeRole === 'floor_feature';
        document.getElementById('ts-v-inject-row').style.display = isFeature ? 'flex' : 'none';
        document.getElementById('ts-v-adjfloor-row').style.display = isFeature ? 'flex' : 'none';
        document.getElementById('ts-v-light-row').style.display = isFeature ? 'flex' : 'none';
        if (isFeature) {
            document.getElementById('ts-v-inject').value = Math.round((v.injectProbability ?? 0.12) * 100);
            document.getElementById('ts-v-adjfloor').checked = !!v.requiresAdjacentFloor;
            const emits = !!v.emitsLight;
            document.getElementById('ts-v-emits-light').checked = emits;
            document.getElementById('ts-v-light-fields').style.display = emits ? 'flex' : 'none';
            if (emits) {
                document.getElementById('ts-v-light-color').value = rgb01ToHex(v.emitsLight.color);
                document.getElementById('ts-v-light-radius').value = v.emitsLight.radius ?? 4;
                document.getElementById('ts-v-light-falloff').value = v.emitsLight.falloff ?? 2;
            }
        }
    }

    function renderCompositePreview() {
        const canvas = document.getElementById('ts-preview-canvas');
        if (!canvas || !atlasImage) return;
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        const tw = 64, th = 64;
        const checkSize = 8;
        for (let y = 0; y < canvas.height; y += checkSize) {
            for (let x = 0; x < canvas.width; x += checkSize) {
                ctx.fillStyle = ((x / checkSize + y / checkSize) % 2 === 0) ? '#333' : '#444';
                ctx.fillRect(x, y, checkSize, checkSize);
            }
        }

        if (!selectedVariantRef) return;
        const a = variantAtlas(selectedVariantRef);

        if (activeRole === 'wall_feature' || activeRole === 'door') {
            const baseWall = (tilesetData.base?.walls || [])[0];
            if (baseWall && baseWall.middle) {
                ctx.drawImage(atlasImage, baseWall.middle[1] * tw, baseWall.middle[0] * th, tw, th, 0, 0, canvas.width, canvas.height);
            }
        } else if (activeRole === 'floor_feature') {
            const baseFloor = (tilesetData.base?.floors || [])[0];
            if (baseFloor && baseFloor.atlas) {
                ctx.drawImage(atlasImage, baseFloor.atlas[1] * tw, baseFloor.atlas[0] * th, tw, th, 0, 0, canvas.width, canvas.height);
            }
        }

        ctx.drawImage(atlasImage, a[1] * tw, a[0] * th, tw, th, 0, 0, canvas.width, canvas.height);
    }

    // --- CREATE / SAVE ----------------------------------------------------------

    window.createNewTileset = async function() {
        const rawId = prompt("Enter a unique Tileset ID (e.g. dungeon_dark, castle_gothic):");
        if (!rawId || !rawId.trim()) return;
        const cleanId = rawId.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '_');
        const nameStr = prompt("Enter a Display Name for this tileset:", cleanId.replace(/_/g, ' '));
        if (!nameStr) return;

        try {
            const newTsObj = {
                id: cleanId,
                name: nameStr,
                texture: 'assets/tilesets/template_tileset.png',
                tileWidth: 64,
                tileHeight: 64,
                base: {
                    walls: [{ id: 'wall_base_1', role: 'base_wall', middle: [1, 0], leftEdge: [1, 1, 0], rightEdge: [1, 1, 32], weight: 100 }],
                    floors: [{ id: 'floor_stone', role: 'base_floor', atlas: [3, 0], weight: 100 }],
                    ceilings: [{ id: 'ceiling_stone', role: 'base_ceiling', atlas: [0, 0], weight: 100 }]
                },
                doors: [],
                features: []
            };

            const resp = await fetch('/api/tilesets/save', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(newTsObj)
            });
            const data = await resp.json();
            if (resp.ok && data.success) {
                currentTilesetId = cleanId;
                await loadTilesetList();
                alert(`New tileset '${cleanId}' created!`);
            } else {
                alert('Error creating tileset: ' + (data.message || 'Unknown error'));
            }
        } catch (e) {
            alert('Failed to create tileset: ' + e.message);
        }
    };

    window.saveTilesetStudioData = async function() {
        if (!tilesetData || !currentTilesetId) return;
        try {
            tilesetData.name = document.getElementById('ts-tileset-name')?.value || currentTilesetId;
            tilesetData.texture = document.getElementById('ts-select-texture')?.value || 'assets/tilesets/dungeon_001.png';

            delete tilesetData.wallRows;
            delete tilesetData.doorRow;
            delete tilesetData.floorRow;
            delete tilesetData.ceilingRow;
            delete tilesetData.skyRow;
            // `tiles{}` was a dead mirror of features[] the old editor wrote
            // redundantly (docs/design/tileset-and-events-redesign.md §0);
            // features[] is the single source of truth going forward.
            delete tilesetData.tiles;

            const resp = await fetch('/api/tilesets/save', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(tilesetData)
            });
            const resData = await resp.json();
            if (resp.ok && resData.success) {
                alert(`Tileset '${currentTilesetId}' saved successfully!`);
                await loadTilesetList();
            } else {
                alert('Failed to save tileset data: ' + (resData.message || 'Unknown error'));
            }
        } catch (e) {
            console.error('Save tileset error:', e);
            alert('Error saving tileset: ' + e.message);
        }
    };
})();
