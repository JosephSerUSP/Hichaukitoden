// Shared window-canvas helpers used by BOTH the Scenes-tab canvas
// (scene-canvas.js) and the Windows-tab editor (window-editor.js): pointer
// math, resize-edge hit-testing, drag-delta application, and new-window
// creation. Extracted so the two canvases can't drift — the geometry these
// produce lands in data/engine.json -> windowLayout, which the engine reads
// at runtime, so the math must stay identical on both surfaces.
//
// The two canvases still own their divergent parts: scene-canvas hit-tests
// many windows and wires an OPEN_WINDOW hook on create; window-editor edits
// a single window and just selects it. This module owns only what was
// byte-for-byte identical between them.
const WindowGeom = (function () {
    const EDGE = 6; // px threshold for resize handles

    // Pointer position within a canvas, in canvas pixels.
    function canvasPos(canvas, e) {
        const r = canvas.getBoundingClientRect();
        return { px: e.clientX - r.left, py: e.clientY - r.top };
    }

    // Which edge(s) of geometry g (in tiles) the pointer is near, as an
    // 'n'/'s' + 'w'/'e' string ('' if none). ts = tile size in canvas px.
    function edgeAt(g, px, py, ts) {
        const x = g.x * ts, y = g.y * ts, wd = (g.width || 8) * ts, ht = (g.height || 4) * ts;
        const nearR = Math.abs(px - (x + wd)) <= EDGE, nearB = Math.abs(py - (y + ht)) <= EDGE;
        const nearL = Math.abs(px - x) <= EDGE, nearT = Math.abs(py - y) <= EDGE;
        let e = '';
        if (nearT) e += 'n'; else if (nearB) e += 's';
        if (nearL) e += 'w'; else if (nearR) e += 'e';
        return e;
    }

    // Mutates `layout` (in tiles) per an in-progress dragState and the
    // current pointer position. Half-tile snap; minimum 2 tiles. Sets
    // dragState.moved once the pointer has travelled past a small threshold.
    // dragState = { mode: 'move'|'resize', edge, startPx, startPy,
    //               start: {x,y,width,height}, moved }
    function applyDrag(layout, dragState, px, py, ts) {
        const snap = (v) => Math.round(v * 2) / 2;
        const dx = (px - dragState.startPx) / ts, dy = (py - dragState.startPy) / ts;
        if (Math.abs(px - dragState.startPx) + Math.abs(py - dragState.startPy) > 3) dragState.moved = true;
        const s = dragState.start;
        if (dragState.mode === 'move') {
            layout.x = snap(s.x + dx);
            layout.y = snap(s.y + dy);
        } else {
            if (dragState.edge.includes('e')) layout.width = Math.max(2, snap(s.width + dx));
            if (dragState.edge.includes('s')) layout.height = Math.max(2, snap(s.height + dy));
            if (dragState.edge.includes('w')) {
                const nx = snap(s.x + dx);
                layout.width = Math.max(2, snap(s.width + (s.x - nx)));
                layout.x = nx;
            }
            if (dragState.edge.includes('n')) {
                const ny = snap(s.y + dy);
                layout.height = Math.max(2, snap(s.height + (s.y - ny)));
                layout.y = ny;
            }
        }
    }

    // Prompts for a new window id, validates it (letters/digits/underscore),
    // checks for a collision in the windowLayout map `wl`, and on success
    // creates the base entry at (x, y) from `preset`. Returns the new id, or
    // null if the user cancelled or the id was invalid/taken (a toast is
    // shown in the latter cases). Callers do their own post-create wiring.
    function createWindow(wl, x, y, preset) {
        let id = prompt(`New ${(preset.label || 'window').toLowerCase()} id (letters/digits/underscore):`, '');
        if (id === null) return null;
        id = id.trim();
        if (!/^\w+$/.test(id)) { showToast('Invalid window id.'); return null; }
        if (wl[id]) { showToast(`windowLayout already has '${id}'.`); return null; }
        wl[id] = { x: x, y: y, width: preset.width, height: preset.height, style: preset.style, title: null };
        return id;
    }

    return { EDGE, canvasPos, edgeAt, applyDrag, createWindow };
})();
