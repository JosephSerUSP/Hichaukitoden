
        // --- ANIMATION EDITOR (Animations tab) ---
        // Effekseer-style workflow: track list + frame-based timeline at the
        // bottom, a 2X viewer with transport, and collapsible parameter
        // sections on the right. Timing is expressed in FRAMES (1 frame =
        // 50ms = one baked preview frame); the JSON keeps ms. The particle
        // model mirrors LÖVE's ParticleSystem (Direction + Speed + Spread,
        // with force fields = radial/tangential/linear acceleration).
        // Preview frames come from a debounced POST to /preview-anim.

        (function () {
        const FRAME_MS = 50;   // bake step — must match runPreviewAnim in main.lua
        const SCALE = 2;       // viewer zoom: 240px engine canvas shown at 480px
        const NAME_COL_W = 170;
        const STAGE_ORIGIN = { x: 120, y: 160 }; // sprite anchor in the engine canvas

        const msToF = ms => (ms || 0) / FRAME_MS;
        const fToMs = f => Math.round(f * FRAME_MS);
        const fmtF = ms => (Math.round(msToF(ms) * 10) / 10) + '';

        const TRACK_META = {
            transform:    { label: 'Transform',    icon: '⬈', color: '#3d7bd9' },
            particles:    { label: 'Particles',    icon: '✨', color: '#2f9e44' },
            force_field:  { label: 'Force Field',  icon: '🧲', color: '#c2255c' },
            tint:         { label: 'Tint',         icon: '🎨', color: '#d9480f' },
            blend:        { label: 'Blend',        icon: '◐',  color: '#862e9c' },
            shake:        { label: 'Shake',        icon: '〰', color: '#e8590c' },
            screen_flash: { label: 'Screen Flash', icon: '⚡', color: '#f59f00' },
            gradient_map: { label: 'Gradient Map', icon: '🌈', color: '#7048e8' }
        };

        const TYPE_DEFAULTS = {
            transform:    { fromX: 0, toX: 0, fromY: 0, toY: 0 },
            particles:    { direction: 270, speed: 50, spread: 45, rate: 20, lifetime: 0.6, gravity: 0, x: 0, y: 0, sizeStart: 1, sizeEnd: 0, layer: 'front' },
            force_field:  { field: 'gravity', strength: 60, angle: 90 },
            tint:         { color: [1, 1, 1], fromAlpha: 1, toAlpha: 0 },
            blend:        { mode: 'add' },
            shake:        { amplitude: 2, frequency: 30 },
            screen_flash: { color: [1, 1, 1], fromAlpha: 0.8, toAlpha: 0 },
            gradient_map: { lowColor: [0.1, 0.0, 0.2], highColor: [1.0, 0.9, 0.6], fromIntensity: 1, toIntensity: 1 }
        };

        // Per-field hover help (title tooltips + a "?" affordance).
        const HELP = {
            direction: 'Angle particles are fired toward. 0°=right, 90°=down, 180°=left, 270°=up. Shown as the arrow on the viewer.',
            speed: 'Initial speed in pixels/second. Each particle gets a random speed between this and Speed max.',
            speedMax: 'Upper bound of the random initial speed. Leave blank/0 to auto (1.5× Speed).',
            spread: 'Cone width around Direction, in degrees. 0 = a tight beam, 360 = every direction.',
            rate: 'Particles emitted per second while the track is active.',
            lifetime: 'How long each particle lives, in seconds.',
            gravity: "Constant downward pull on THIS track's particles (px/s²). Force Field tracks add to this.",
            sizeStart: 'Sprite scale at birth (1 = original size).',
            sizeEnd: 'Sprite scale at death (0 = shrinks away).',
            sizeVariation: '0–1 random spread of the starting size.',
            spin: 'How fast each particle sprite rotates, in degrees/second.',
            x: 'Emitter X offset from the battler anchor (px). Drag the green handle on the viewer.',
            y: 'Emitter Y offset from the battler anchor (px). Drag the green handle on the viewer.',
            mask: "Clip particles to the battler's silhouette (stencil mask).",
            layer: 'Draw these particles in front of the sprite or behind it.',
            ignoreForces: 'Exclude this particle track from all Force Field tracks in this animation.',
            intensity: 'How strongly the gradient replaces the original sprite colors (0 = none, 1 = full).',
            field: 'gravity = straight push; attract = pull toward / push from the emitter; vortex = orbit; drag = slow particles down.',
            strength: 'Acceleration magnitude (px/s²). For attract, positive pulls inward, negative pushes outward.',
            angle: 'Direction of the gravity push. 90°=down, 270°=up, 0°=right.',
            cellW: 'Width of one animation cell in the sheet (px).',
            cellH: 'Height of one animation cell in the sheet (px).',
            cellStart: 'Index of the first cell to play (row-major, 0-based).',
            cellCount: 'How many cells the flipbook plays.',
            cellMode: 'once = spread the cells across the particle life; loop = repeat them.',
            cellLoops: 'How many times to repeat the cells across the particle life (loop mode).'
        };

        // Particle starter presets (applied over the emitter/look fields; id,
        // name, parent and timing are preserved). `_sprite` is a recommended
        // texture to draw — shown when the preset is applied, never written to
        // data. Presets work with the default dot too.
        const PARTICLE_PRESETS = {
            'Puff (smoke)':   { _sprite: 'default dot is fine — or a soft round 16×16 blob, 1 frame', direction: 270, speed: 20, spread: 180, rate: 30, lifetime: 0.6, gravity: -10, sizeStart: 1.5, sizeEnd: 0, colorOverLife: [[1, 1, 1, 0.8], [1, 1, 1, 0]] },
            'Sparkle rise':   { _sprite: 'HealSpark[16x16][8f].png or Sparkles_16p.png', direction: 270, speed: 40, spread: 40, rate: 24, lifetime: 1.0, gravity: -30, sizeStart: 0.6, sizeEnd: 0, colorOverLife: [[1, 1, 0.6, 1], [1, 0.8, 0.2, 0.5], [1, 1, 1, 0]] },
            'Fountain':       { _sprite: 'default dot — or an 8×8 water droplet, 1 frame', direction: 270, speed: 120, spread: 20, rate: 40, lifetime: 1.2, gravity: 220, sizeStart: 1, sizeEnd: 0.4, colorOverLife: [[0.6, 0.8, 1, 1], [0.6, 0.8, 1, 0]] },
            'Nova burst':     { _sprite: 'default dot — or a 16×16 4-point star, 1 frame', direction: 0, speed: 140, spread: 360, rate: 90, lifetime: 0.5, gravity: 0, sizeStart: 1.2, sizeEnd: 0, colorOverLife: [[1, 1, 1, 1], [1, 0.5, 0.1, 0]] },
            'Embers':         { _sprite: 'FlameLoop[16x16][8f].png or default dot', direction: 270, speed: 30, spread: 60, rate: 16, lifetime: 1.5, gravity: -20, sizeStart: 0.5, sizeEnd: 0, colorOverLife: [[1, 0.5, 0.1, 1], [0.6, 0.1, 0, 0]] },
            'Smoke plume':    { _sprite: 'a soft 32×32 smoke puff, 1 frame (bigger = softer)', direction: 270, speed: 22, spread: 30, rate: 18, lifetime: 1.8, gravity: -8, sizeStart: 1.0, sizeEnd: 3.0, colorOverLife: [[0.5, 0.5, 0.55, 0.7], [0.3, 0.3, 0.35, 0]] },
            'Confetti':       { _sprite: 'an 8×8 solid square (draw 2–4 color variants across cells)', direction: 270, speed: 130, spread: 70, rate: 50, lifetime: 1.4, gravity: 180, sizeStart: 1.0, sizeEnd: 1.0, colorOverLife: [[1, 0.3, 0.3, 1], [0.3, 0.6, 1, 1]] },
            'Snowfall':       { _sprite: 'default dot — or a soft 8×8 flake, 1 frame', direction: 90, speed: 20, spread: 40, rate: 20, lifetime: 2.0, gravity: 15, sizeStart: 0.6, sizeEnd: 0.6, colorOverLife: [[1, 1, 1, 0.9], [0.8, 0.9, 1, 0.2]] },
            'Spark shower':   { _sprite: 'default dot — or a 4×4 bright spark', direction: 270, speed: 100, spread: 55, rate: 60, lifetime: 0.5, gravity: 260, sizeStart: 0.8, sizeEnd: 0, colorOverLife: [[1, 1, 0.6, 1], [1, 0.5, 0.1, 0]] },
            'Bubble rise':    { _sprite: 'a 16×16 hollow ring/bubble, 1 frame', direction: 270, speed: 30, spread: 35, rate: 14, lifetime: 1.6, gravity: -35, sizeStart: 0.5, sizeEnd: 1.2, colorOverLife: [[0.6, 0.9, 1, 0.7], [0.8, 1, 1, 0]] },
            'Magic swirl':    { _sprite: 'Sparkles_16p.png — then add a Vortex Force Field track', direction: 270, speed: 45, spread: 25, rate: 34, lifetime: 1.1, gravity: -10, sizeStart: 0.8, sizeEnd: 0, colorOverLife: [[0.7, 0.5, 1, 1], [0.4, 0.8, 1, 0]] },
            'Blood spray':    { _sprite: 'default dot — or a 6×6 droplet', direction: 270, speed: 90, spread: 80, rate: 45, lifetime: 0.7, gravity: 300, sizeStart: 1.0, sizeEnd: 0.5, colorOverLife: [[0.7, 0.05, 0.05, 1], [0.4, 0, 0, 0]] }
        };

        // Keys shared by every track type; everything else is type-specific
        // payload and gets replaced when the type changes.
        const SHARED_KEYS = ['id', 'name', 'parent', 'type', 't0', 'duration', 'easing', 'inheritPosition', 'inheritScale'];

        const num = (val, def) => {
            const n = parseFloat(val);
            return isFinite(n) ? n : def;
        };
        const rgb01ToHex = c => '#' + (c || [1, 1, 1]).slice(0, 3)
            .map(v => Math.round((v || 0) * 255).toString(16).padStart(2, '0')).join('');
        const hexToRgb01 = hex => [1, 3, 5].map(i => Math.round(parseInt(hex.substr(i, 2), 16) / 255 * 100) / 100);

        // Make a number input scrub by dragging left/right (in place of the
        // native spinner arrows). A small drag threshold keeps click-to-type
        // working. onScrub fires live as the value changes.
        const attachDragScrub = (input, opts) => {
            const stepSize = opts.stepSize || 1;
            const decimals = (String(stepSize).split('.')[1] || '').length;
            input.style.cursor = 'ew-resize';
            input.addEventListener('mousedown', (e) => {
                if (e.button !== 0) return;
                const startX = e.clientX;
                const startVal = parseFloat(input.value) || 0;
                let scrubbing = false;
                const mm = (ev) => {
                    const dx = ev.clientX - startX;
                    if (!scrubbing) {
                        if (Math.abs(dx) < 3) return;
                        scrubbing = true;
                        input.blur();
                        document.body.style.cursor = 'ew-resize';
                    }
                    ev.preventDefault();
                    let v = startVal + Math.round(dx / 4) * stepSize;
                    v = parseFloat(v.toFixed(decimals));
                    input.value = v;
                    opts.onScrub(v);
                };
                const mu = () => {
                    document.removeEventListener('mousemove', mm);
                    document.removeEventListener('mouseup', mu);
                    document.body.style.cursor = '';
                };
                document.addEventListener('mousemove', mm);
                document.addEventListener('mouseup', mu);
            });
        };

        // Parse cell metadata baked into a texture filename, e.g.
        // "Recovery[16x16][8f].png" → { cellW:16, cellH:16, cellCount:8 }.
        const parseCellTokens = (path) => {
            const out = {};
            const size = /\[(\d+)x(\d+)\]/.exec(path);
            if (size) { out.cellW = parseInt(size[1]); out.cellH = parseInt(size[2]); }
            const frames = /\[(\d+)\s*f(?:rames?)?\]/i.exec(path);
            if (frames) out.cellCount = parseInt(frames[1]);
            return out;
        };

        window.renderAnimationEditor = function (formPanel, item) {
            const anim = dbPayload.animations[item.id];
            if (!anim) return;
            anim.tracks = anim.tracks || [];

            const meta = t => TRACK_META[t.type] || { label: t.type || '?', icon: '❓', color: '#888' };
            const trackLabel = (t, i) => t.name || (meta(t).label + ' ' + (i + 1));
            const trackEnd = t => (t.t0 || 0) + (t.duration || 0);
            const totalMs = () => Math.max(FRAME_MS * 2, anim.duration || 0, ...anim.tracks.map(trackEnd));

            // ---------------- state ----------------
            let selected = parseInt(sessionStorage.getItem('hkt_anim_sel_' + anim.id), 10);
            if (isNaN(selected) || selected < 0 || selected >= anim.tracks.length) {
                selected = anim.tracks.length ? 0 : -1;
            }
            const selTrack = () => (selected >= 0 && anim.tracks[selected]) || null;
            const setSelected = (idx) => {
                selected = idx;
                sessionStorage.setItem('hkt_anim_sel_' + anim.id, idx);
            };

            let frames = [];
            let playheadMs = 0;
            let playing = false;
            let looping = true;
            let playTimer = null;
            let bakeTimer = null;
            let baking = false;
            let bakeQueued = false;
            let firstBake = true; // auto-play only on the first bake (i.e. on open)
            let lastPresetHint = null; // recommended sprite of the last applied preset
            let spritePath = sessionStorage.getItem('hkt_preview_sprite') || 'assets/smallBattlers/pixie.png';

            // Any edit: mark the DB dirty and re-render the preview soon.
            const markChange = () => {
                setDirty(true);
                scheduleBake();
            };
            // Other editor code signals track edits through this global.
            window.onAnimationTrackChanged = markChange;

            // ---------------- DOM skeleton ----------------
            const root = document.createElement('div');
            root.style.cssText = 'display: flex; flex-direction: column; gap: 10px; width: 100%;';
            formPanel.appendChild(root);

            // == Header bar: ID / class / duration / preview sprite ==
            const headerBar = document.createElement('div');
            headerBar.style.cssText = 'display: flex; gap: 12px; align-items: flex-end; flex-wrap: wrap; border: 2px outset var(--win-white); background: var(--win-gray); padding: 8px;';
            root.appendChild(headerBar);

            createFormField(headerBar, 'Animation ID', anim.id, val => {
                const oldId = anim.id;
                if (val && val !== oldId && !dbPayload.animations[val]) {
                    dbPayload.animations[val] = anim;
                    anim.id = val;
                    delete dbPayload.animations[oldId];
                    activeDbItemId = val;
                    setDirty(true);
                    initDatabaseEditor(true);
                }
            }, 'text', anim.class === 'system');

            createFormField(headerBar, 'Class', anim.class || 'assignable', null, 'text', true);

            createFormField(headerBar, 'Duration (frames)', fmtF(anim.duration || 1000), val => {
                anim.duration = Math.max(FRAME_MS, fToMs(num(val, 20)));
                markChange();
                renderTimeline();
                updateFrameView();
            }, 'number');

            const spacer = document.createElement('div');
            spacer.style.flex = '1';
            headerBar.appendChild(spacer);

            const sprGroup = document.createElement('div');
            sprGroup.className = 'form-group';
            const sprLbl = document.createElement('label');
            sprLbl.textContent = 'Preview Sprite:';
            sprGroup.appendChild(sprLbl);
            const sprRow = document.createElement('div');
            sprRow.style.cssText = 'display: flex; gap: 4px; align-items: center;';
            const sprInput = document.createElement('input');
            sprInput.type = 'text';
            sprInput.className = 'win98-input';
            sprInput.style.width = '220px';
            sprInput.value = spritePath;
            sprInput.onchange = () => {
                spritePath = sprInput.value;
                sessionStorage.setItem('hkt_preview_sprite', spritePath);
                scheduleBake();
            };
            sprRow.appendChild(sprInput);
            const sprBrowse = document.createElement('button');
            sprBrowse.className = 'win98-btn';
            sprBrowse.textContent = '...';
            sprBrowse.style.padding = '0 6px';
            sprBrowse.onclick = (e) => {
                e.preventDefault();
                openAssetPicker('smallBattlers', (filepath) => {
                    spritePath = filepath.replace(/\\/g, '/');
                    sprInput.value = spritePath;
                    sessionStorage.setItem('hkt_preview_sprite', spritePath);
                    scheduleBake();
                });
            };
            sprRow.appendChild(sprBrowse);
            sprGroup.appendChild(sprRow);
            headerBar.appendChild(sprGroup);

            // == Main row: viewer (left, 2X) + parameters (right) ==
            const mainRow = document.createElement('div');
            mainRow.style.cssText = 'display: flex; gap: 12px; align-items: flex-start;';
            root.appendChild(mainRow);

            const stageCol = document.createElement('div');
            stageCol.style.cssText = 'width: ' + (240 * SCALE + 20) + 'px; flex-shrink: 0; display: flex; flex-direction: column; gap: 6px; border: 2px outset var(--win-white); background: var(--win-gray); padding: 8px;';
            mainRow.appendChild(stageCol);

            const inspectorCol = document.createElement('div');
            inspectorCol.style.cssText = 'flex: 1; min-width: 0; border: 2px outset var(--win-white); background: var(--win-gray); padding: 8px; align-self: stretch; overflow-y: auto; max-height: ' + (240 * SCALE + 70) + 'px;';
            mainRow.appendChild(inspectorCol);

            // -- Viewer: preview frame at 2X + overlay handles + status chip --
            const stageWrap = document.createElement('div');
            stageWrap.style.cssText = 'width: ' + (240 * SCALE) + 'px; height: ' + (240 * SCALE) + 'px; border: 2px inset var(--win-shadow); position: relative; overflow: hidden; user-select: none; margin: 0 auto;'
                + 'background: repeating-conic-gradient(#2a2a2a 0% 25%, #1c1c1c 0% 50%) 0 0 / 32px 32px;';
            stageCol.appendChild(stageWrap);

            const previewImg = document.createElement('img');
            previewImg.style.cssText = 'width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; display: none; pointer-events: none;';
            stageWrap.appendChild(previewImg);

            const statusChip = document.createElement('div');
            statusChip.style.cssText = 'position: absolute; top: 4px; left: 4px; right: 4px; font-size: 11px; font-weight: bold; padding: 2px 6px; pointer-events: none; text-align: left; text-shadow: 1px 1px 1px #000; color: #fff; display: none; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;';
            stageWrap.appendChild(statusChip);

            const svgOverlay = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            svgOverlay.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%;';
            stageWrap.appendChild(svgOverlay);

            const setStatus = (state, detail) => {
                if (state === 'ok') { statusChip.style.display = 'none'; return; }
                statusChip.style.display = 'block';
                if (state === 'baking' || state === 'pending') {
                    statusChip.textContent = '⏳ Rendering…';
                    statusChip.style.color = '#ffdd88';
                } else if (state === 'error') {
                    statusChip.textContent = '⚠ ' + (detail || 'Preview failed');
                    statusChip.title = detail || '';
                    statusChip.style.color = '#ff8888';
                }
            };

            // -- Transport --
            const transport = document.createElement('div');
            transport.style.cssText = 'display: flex; gap: 3px; align-items: center; justify-content: center;';
            stageCol.appendChild(transport);

            const mkBtn = (txt, title) => {
                const b = document.createElement('button');
                b.className = 'win98-btn';
                b.textContent = txt;
                b.title = title;
                b.style.padding = '2px 8px';
                transport.appendChild(b);
                return b;
            };
            const rewindBtn = mkBtn('⏮', 'Back to start');
            const stepBackBtn = mkBtn('◀', 'Previous frame');
            const playBtn = mkBtn('▶', 'Play / pause');
            playBtn.style.minWidth = '40px';
            const stepFwdBtn = mkBtn('▶|', 'Next frame');
            const loopBtn = mkBtn('🔁', 'Toggle looping');

            const timeLabel = document.createElement('span');
            timeLabel.style.cssText = 'font-family: monospace; font-size: 11px; margin-left: 10px;';
            transport.appendChild(timeLabel);

            // ---------------- playback ----------------
            const lastFrameMs = () => Math.max(0, (frames.length - 1) * FRAME_MS);
            const curFrame = () => Math.max(0, Math.min(frames.length ? frames.length - 1 : 0, Math.round(playheadMs / FRAME_MS)));

            const updateFrameView = () => {
                if (frames.length) {
                    previewImg.src = 'data:image/png;base64,' + frames[curFrame()];
                    previewImg.style.display = 'block';
                }
                timeLabel.textContent = 'frame ' + curFrame() + ' / ' + Math.round(msToF(totalMs()));
                positionPlayhead();
            };

            const setPlayhead = (ms) => {
                playheadMs = Math.max(0, Math.min(totalMs(), ms));
                updateFrameView();
            };

            const stopPlayback = () => {
                if (playTimer) { clearInterval(playTimer); playTimer = null; }
                playing = false;
                playBtn.textContent = '▶';
            };

            const startPlayback = () => {
                if (!frames.length) return;
                playing = true;
                playBtn.textContent = '⏸';
                if (playheadMs >= lastFrameMs()) playheadMs = 0;
                if (playTimer) clearInterval(playTimer);
                playTimer = setInterval(() => {
                    playheadMs += FRAME_MS;
                    if (playheadMs > lastFrameMs()) {
                        if (looping) {
                            playheadMs = 0;
                        } else {
                            playheadMs = lastFrameMs();
                            stopPlayback();
                        }
                    }
                    updateFrameView();
                }, FRAME_MS);
            };

            playBtn.onclick = (e) => { e.preventDefault(); playing ? stopPlayback() : startPlayback(); };
            rewindBtn.onclick = (e) => { e.preventDefault(); stopPlayback(); setPlayhead(0); };
            stepBackBtn.onclick = (e) => { e.preventDefault(); stopPlayback(); setPlayhead(playheadMs - FRAME_MS); };
            stepFwdBtn.onclick = (e) => { e.preventDefault(); stopPlayback(); setPlayhead(playheadMs + FRAME_MS); };
            const styleLoopBtn = () => {
                loopBtn.style.background = looping ? 'var(--win-blue)' : '';
                loopBtn.style.color = looping ? '#fff' : '';
            };
            styleLoopBtn();
            loopBtn.onclick = (e) => { e.preventDefault(); looping = !looping; styleLoopBtn(); };

            // ---------------- auto-bake (preserves playhead + play state) ----------------
            const scheduleBake = () => {
                clearTimeout(bakeTimer);
                setStatus('pending');
                bakeTimer = setTimeout(doBake, 500);
            };

            const doBake = () => {
                if (baking) { bakeQueued = true; return; }
                baking = true;
                setStatus('baking');
                fetch('/preview-anim', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ id: anim.id, sprite: spritePath, data: anim })
                })
                .then(res => res.json())
                .then(resData => {
                    baking = false;
                    if (bakeQueued) { bakeQueued = false; doBake(); return; }
                    if (resData.error) { setStatus('error', resData.error); return; }
                    frames = resData.frames || [];
                    if (!frames.length) { setStatus('error', 'No frames returned'); return; }
                    setStatus('ok');
                    // Preserve where the user was: clamp the playhead into the
                    // (possibly shorter) new range, keep the paused/playing
                    // state. Only the very first bake (on open) auto-plays.
                    playheadMs = Math.min(playheadMs, lastFrameMs());
                    updateFrameView();
                    if (firstBake) { firstBake = false; startPlayback(); }
                })
                .catch(err => {
                    baking = false;
                    setStatus('error', 'Render failed — is LOVE available? (' + err.message + ')');
                });
            };

            // ---------------- viewer overlay handles ----------------
            // Overlay coordinates are viewer CSS pixels (engine px * SCALE).
            const mkSvgHandle = (ex, ey, color, label, onDrag, onDone) => {
                const x = ex * SCALE, y = ey * SCALE;
                const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
                g.style.cursor = 'move';
                const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                circle.setAttribute('cx', x); circle.setAttribute('cy', y); circle.setAttribute('r', 7);
                circle.setAttribute('fill', color);
                circle.setAttribute('stroke', '#ffffff');
                circle.setAttribute('stroke-width', '1.5');
                g.appendChild(circle);
                const txt = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                txt.setAttribute('x', x); txt.setAttribute('y', y - 11);
                txt.setAttribute('text-anchor', 'middle');
                txt.setAttribute('fill', '#ffffff');
                txt.style.cssText = 'font-size: 10px; font-family: monospace; text-shadow: 1px 1px 1px #000;';
                txt.textContent = label;
                g.appendChild(txt);
                svgOverlay.appendChild(g);

                const onMouseMove = (e) => {
                    const rect = svgOverlay.getBoundingClientRect();
                    const cx = Math.max(0, Math.min(240 * SCALE, e.clientX - rect.left));
                    const cy = Math.max(0, Math.min(240 * SCALE, e.clientY - rect.top));
                    onDrag(cx / SCALE, cy / SCALE); // back to engine px
                };
                const onMouseUp = () => {
                    document.removeEventListener('mousemove', onMouseMove);
                    document.removeEventListener('mouseup', onMouseUp);
                    if (onDone) onDone();
                };
                g.addEventListener('mousedown', (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    document.addEventListener('mousemove', onMouseMove);
                    document.addEventListener('mouseup', onMouseUp);
                });
            };

            const svgEl = (name, attrs) => {
                const el = document.createElementNS('http://www.w3.org/2000/svg', name);
                Object.keys(attrs).forEach(k => el.setAttribute(k, attrs[k]));
                svgOverlay.appendChild(el);
                return el;
            };

            // Arrow showing a direction (degrees, 0=right CW) from an engine point.
            const drawArrow = (ex, ey, deg, len, color) => {
                const a = deg * Math.PI / 180;
                const x1 = ex * SCALE, y1 = ey * SCALE;
                const x2 = (ex + Math.cos(a) * len) * SCALE, y2 = (ey + Math.sin(a) * len) * SCALE;
                svgEl('line', { x1, y1, x2, y2, stroke: color, 'stroke-width': 2 });
                const head = 6, ha = 0.5;
                svgEl('line', { x1: x2, y1: y2, x2: x2 - head * Math.cos(a - ha), y2: y2 - head * Math.sin(a - ha), stroke: color, 'stroke-width': 2 });
                svgEl('line', { x1: x2, y1: y2, x2: x2 - head * Math.cos(a + ha), y2: y2 - head * Math.sin(a + ha), stroke: color, 'stroke-width': 2 });
            };

            const drawOverlayHandles = () => {
                svgOverlay.innerHTML = '';
                const tr = selTrack();
                if (!tr) return;
                const done = () => { markChange(); renderInspector(); };

                if (tr.type === 'transform') {
                    const sx = STAGE_ORIGIN.x + (tr.fromX || 0);
                    const sy = STAGE_ORIGIN.y + (tr.fromY || 0);
                    const ex = STAGE_ORIGIN.x + (tr.toX || 0);
                    const ey = STAGE_ORIGIN.y + (tr.toY || 0);
                    svgEl('line', { x1: sx * SCALE, y1: sy * SCALE, x2: ex * SCALE, y2: ey * SCALE, stroke: '#8888ff', 'stroke-dasharray': 4, 'stroke-width': 1.5 });
                    mkSvgHandle(sx, sy, '#ff3333', 'from', (mx, my) => {
                        tr.fromX = Math.round(mx - STAGE_ORIGIN.x);
                        tr.fromY = Math.round(my - STAGE_ORIGIN.y);
                        drawOverlayHandles();
                    }, done);
                    mkSvgHandle(ex, ey, '#3399ff', 'to', (mx, my) => {
                        tr.toX = Math.round(mx - STAGE_ORIGIN.x);
                        tr.toY = Math.round(my - STAGE_ORIGIN.y);
                        drawOverlayHandles();
                    }, done);
                } else if (tr.type === 'particles') {
                    const ex = STAGE_ORIGIN.x + (tr.x || 0);
                    const ey = STAGE_ORIGIN.y + (tr.y || 0);
                    // Direction arrow whose length tracks Speed; drag the tip
                    // to set BOTH direction and speed.
                    const speed = tr.speed !== undefined ? tr.speed : (tr.velocity || 50);
                    const len = Math.max(8, Math.min(110, speed * 0.35));
                    const dir = tr.direction || 0;
                    const half = (tr.spread || 0) / 2;
                    if (half > 0 && half < 180) {
                        [dir - half, dir + half].forEach(d => {
                            const a = d * Math.PI / 180;
                            svgEl('line', { x1: ex * SCALE, y1: ey * SCALE, x2: (ex + Math.cos(a) * len) * SCALE, y2: (ey + Math.sin(a) * len) * SCALE, stroke: '#33cc33', 'stroke-dasharray': 3, 'stroke-width': 1, opacity: 0.6 });
                        });
                    }
                    drawArrow(ex, ey, dir, len, '#66ff66');
                    const ar = dir * Math.PI / 180;
                    mkSvgHandle(ex + Math.cos(ar) * len, ey + Math.sin(ar) * len, '#66ff66', 'aim', (mx, my) => {
                        const ddx = mx - ex, ddy = my - ey;
                        let deg = Math.round(Math.atan2(ddy, ddx) * 180 / Math.PI);
                        if (deg < 0) deg += 360;
                        tr.direction = deg;
                        tr.speed = Math.max(1, Math.round(Math.hypot(ddx, ddy) / 0.35));
                        delete tr.velocity; // canvas authors the new Speed field
                        drawOverlayHandles();
                    }, done);
                    mkSvgHandle(ex, ey, '#33cc33', 'emitter', (mx, my) => {
                        tr.x = Math.round(mx - STAGE_ORIGIN.x);
                        tr.y = Math.round(my - STAGE_ORIGIN.y);
                        drawOverlayHandles();
                    }, done);
                } else if (tr.type === 'force_field') {
                    const cx = STAGE_ORIGIN.x, cy = STAGE_ORIGIN.y;
                    const strength = tr.strength || 0;
                    if (tr.field === 'gravity') {
                        const len = Math.max(12, Math.min(90, strength * 0.4));
                        const ang = tr.angle || 90;
                        drawArrow(cx, cy, ang, len, '#ff66aa');
                        const a = ang * Math.PI / 180;
                        mkSvgHandle(cx + Math.cos(a) * len, cy + Math.sin(a) * len, '#ff66aa', 'force', (mx, my) => {
                            const ddx = mx - cx, ddy = my - cy;
                            let deg = Math.round(Math.atan2(ddy, ddx) * 180 / Math.PI);
                            if (deg < 0) deg += 360;
                            tr.angle = deg;
                            tr.strength = Math.max(0, Math.round(Math.hypot(ddx, ddy) / 0.4));
                            drawOverlayHandles();
                        }, done);
                    } else if (tr.field === 'attract') {
                        const r = Math.max(12, Math.min(80, Math.abs(strength) * 0.3));
                        svgEl('circle', { cx: cx * SCALE, cy: cy * SCALE, r: r * SCALE, fill: 'none', stroke: '#ff66aa', 'stroke-dasharray': 4, 'stroke-width': 1.5 });
                        [0, 90, 180, 270].forEach(d => drawArrow(cx + Math.cos(d * Math.PI / 180) * r, cy + Math.sin(d * Math.PI / 180) * r, strength >= 0 ? d + 180 : d, 16, '#ff66aa'));
                        mkSvgHandle(cx + r, cy, '#ff66aa', strength >= 0 ? 'attract' : 'repel', (mx, my) => {
                            tr.strength = Math.round((mx - cx) / 0.3);
                            drawOverlayHandles();
                        }, done);
                    } else if (tr.field === 'vortex') {
                        const r = Math.max(12, Math.min(80, Math.abs(strength) * 0.3));
                        svgEl('circle', { cx: cx * SCALE, cy: cy * SCALE, r: r * SCALE, fill: 'none', stroke: '#ff66aa', 'stroke-dasharray': 4, 'stroke-width': 1.5 });
                        [45, 135, 225, 315].forEach(d => drawArrow(cx + Math.cos(d * Math.PI / 180) * r, cy + Math.sin(d * Math.PI / 180) * r, d + 90, 14, '#ff66aa'));
                        mkSvgHandle(cx + r, cy, '#ff66aa', 'spin', (mx, my) => {
                            tr.strength = Math.round(Math.hypot(mx - cx, my - cy) / 0.3);
                            drawOverlayHandles();
                        }, done);
                    }
                }
            };

            // ---------------- timeline (frame-based) ----------------
            const timelinePanel = document.createElement('div');
            timelinePanel.style.cssText = 'border: 2px outset var(--win-white); background: var(--win-gray); padding: 8px; display: flex; flex-direction: column; gap: 6px;';
            root.appendChild(timelinePanel);

            const tlToolbar = document.createElement('div');
            tlToolbar.style.cssText = 'display: flex; gap: 4px; align-items: center;';
            timelinePanel.appendChild(tlToolbar);

            const addSelect = document.createElement('select');
            addSelect.className = 'win98-input';
            addSelect.style.width = '150px';
            const addPh = document.createElement('option');
            addPh.value = '';
            addPh.textContent = '＋ Add track…';
            addSelect.appendChild(addPh);
            Object.keys(TRACK_META).forEach(type => {
                const opt = document.createElement('option');
                opt.value = type;
                opt.textContent = TRACK_META[type].icon + ' ' + TRACK_META[type].label;
                addSelect.appendChild(opt);
            });
            addSelect.onchange = () => {
                const type = addSelect.value;
                addSelect.value = '';
                if (!type) return;
                const tr = Object.assign({
                    type: type,
                    t0: 0,
                    duration: anim.duration || 500,
                    easing: 'linear'
                }, JSON.parse(JSON.stringify(TYPE_DEFAULTS[type] || {})));
                anim.tracks.push(tr);
                setSelected(anim.tracks.length - 1);
                markChange();
                renderTimeline();
                renderInspector();
            };
            tlToolbar.appendChild(addSelect);

            const tbBtn = (txt, title, onClick) => {
                const b = document.createElement('button');
                b.className = 'win98-btn';
                b.textContent = txt;
                b.title = title;
                b.style.padding = '2px 8px';
                b.onclick = (e) => { e.preventDefault(); onClick(); };
                tlToolbar.appendChild(b);
                return b;
            };

            tbBtn('Duplicate', 'Duplicate the selected track', () => {
                const tr = selTrack();
                if (!tr) return;
                const copy = JSON.parse(JSON.stringify(tr));
                delete copy.id; // parent references must stay unique to the original
                if (copy.name) copy.name += ' copy';
                anim.tracks.splice(selected + 1, 0, copy);
                setSelected(selected + 1);
                markChange();
                renderTimeline();
                renderInspector();
            });

            tbBtn('Delete', 'Delete the selected track', () => {
                const tr = selTrack();
                if (!tr) return;
                anim.tracks.splice(selected, 1);
                if (tr.id) {
                    anim.tracks.forEach(t => { if (t.parent === tr.id) delete t.parent; });
                }
                setSelected(Math.min(selected, anim.tracks.length - 1));
                markChange();
                renderTimeline();
                renderInspector();
            });

            const moveSel = (dir) => {
                const j = selected + dir;
                if (selected < 0 || j < 0 || j >= anim.tracks.length) return;
                const tmp = anim.tracks[selected];
                anim.tracks[selected] = anim.tracks[j];
                anim.tracks[j] = tmp;
                setSelected(j);
                markChange();
                renderTimeline();
            };
            tbBtn('▲', 'Move selected track up', () => moveSel(-1));
            tbBtn('▼', 'Move selected track down', () => moveSel(1));

            const tlHint = document.createElement('span');
            tlHint.style.cssText = 'font-size: 9px; color: var(--win-dark-shadow); margin-left: auto;';
            tlHint.textContent = 'Times are in frames (1 frame = 50ms). Drag bars to move, drag edges to resize, click the ruler to scrub.';
            tlToolbar.appendChild(tlHint);

            const tlBody = document.createElement('div');
            tlBody.style.cssText = 'display: flex; border: 2px inset var(--win-shadow); background: var(--win-white); max-height: 240px; overflow-y: auto;';
            timelinePanel.appendChild(tlBody);

            const namesCol = document.createElement('div');
            namesCol.style.cssText = 'width: ' + NAME_COL_W + 'px; flex-shrink: 0; border-right: 1px solid var(--win-shadow);';
            tlBody.appendChild(namesCol);

            const laneCol = document.createElement('div');
            laneCol.style.cssText = 'flex: 1; min-width: 0; position: relative;';
            tlBody.appendChild(laneCol);

            let pxPerMs = 1;
            const snapF = ms => Math.round(ms / FRAME_MS) * FRAME_MS;
            const pickTickStepF = (totalF) => {
                const steps = [1, 2, 5, 10, 20, 50, 100];
                for (const s of steps) { if (totalF / s <= 16) return s; }
                return 200;
            };
            const positionPlayhead = () => {
                const ph = laneCol.querySelector('.anim-playhead');
                if (ph) ph.style.left = (playheadMs * pxPerMs) + 'px';
            };

            const renderTimeline = () => {
                namesCol.innerHTML = '';
                laneCol.innerHTML = '';

                const total = totalMs();
                const laneW = Math.max(50, laneCol.clientWidth || 600);
                pxPerMs = (laneW - 10) / total;

                const rulerSpacer = document.createElement('div');
                rulerSpacer.style.cssText = 'height: 20px; border-bottom: 1px solid var(--win-shadow); background: var(--win-gray); font-size: 9px; padding: 4px 6px 0; box-sizing: border-box; overflow: hidden; white-space: nowrap;';
                rulerSpacer.textContent = 'Tracks (' + anim.tracks.length + ')';
                namesCol.appendChild(rulerSpacer);

                const ruler = document.createElement('div');
                ruler.style.cssText = 'height: 20px; border-bottom: 1px solid var(--win-shadow); background: var(--win-gray); position: relative; cursor: ew-resize; overflow: hidden;';
                laneCol.appendChild(ruler);

                const totalF = msToF(total);
                const tickF = pickTickStepF(totalF);
                for (let f = 0; f <= totalF; f += tickF) {
                    const el = document.createElement('div');
                    el.style.cssText = 'position: absolute; top: 0; bottom: 0; left: ' + (f * FRAME_MS * pxPerMs) + 'px; border-left: 1px solid var(--win-shadow); padding-left: 2px; font-size: 8px; color: var(--win-dark-shadow); pointer-events: none;';
                    el.textContent = f;
                    ruler.appendChild(el);
                }

                const durX = (anim.duration || 0) * pxPerMs;
                const durLine = document.createElement('div');
                durLine.style.cssText = 'position: absolute; top: 20px; bottom: 0; left: ' + durX + 'px; width: 0; border-left: 1px dashed #b06060; pointer-events: none; z-index: 2;';
                laneCol.appendChild(durLine);

                const scrubTo = (clientX) => {
                    const rect = ruler.getBoundingClientRect();
                    stopPlayback();
                    setPlayhead(snapF((clientX - rect.left) / pxPerMs));
                };
                ruler.onmousedown = (e) => {
                    e.preventDefault();
                    scrubTo(e.clientX);
                    const mm = (ev) => scrubTo(ev.clientX);
                    const mu = () => {
                        document.removeEventListener('mousemove', mm);
                        document.removeEventListener('mouseup', mu);
                    };
                    document.addEventListener('mousemove', mm);
                    document.addEventListener('mouseup', mu);
                };

                anim.tracks.forEach((tr, i) => {
                    const m = meta(tr);
                    const isSel = i === selected;
                    const isChild = !!tr.parent;

                    const nameCell = document.createElement('div');
                    nameCell.style.cssText = 'height: 28px; box-sizing: border-box; padding: 2px 6px 2px ' + (isChild ? 18 : 6) + 'px; font-size: 10px; cursor: pointer; display: flex; flex-direction: column; justify-content: center; border-bottom: 1px solid #e0e0e0; overflow: hidden;'
                        + (isSel ? 'background: var(--win-blue); color: #fff;' : '');
                    const nameTop = document.createElement('div');
                    nameTop.style.cssText = 'font-weight: bold; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;';
                    nameTop.textContent = (isChild ? '└ ' : '') + m.icon + ' ' + trackLabel(tr, i);
                    nameCell.appendChild(nameTop);
                    const nameSub = document.createElement('div');
                    nameSub.style.cssText = 'font-size: 8px; opacity: 0.75; font-family: monospace;';
                    nameSub.textContent = fmtF(tr.t0) + '–' + fmtF(trackEnd(tr)) + ' f';
                    nameCell.appendChild(nameSub);
                    nameCell.onclick = () => {
                        setSelected(i);
                        renderTimeline();
                        renderInspector();
                    };
                    namesCol.appendChild(nameCell);

                    const lane = document.createElement('div');
                    lane.style.cssText = 'height: 28px; box-sizing: border-box; position: relative; border-bottom: 1px solid #e0e0e0;' + (isSel ? 'background: #eef2ff;' : '');
                    laneCol.appendChild(lane);

                    const bar = document.createElement('div');
                    const barX = (tr.t0 || 0) * pxPerMs;
                    const barW = Math.max(4, (tr.duration || 0) * pxPerMs);
                    bar.style.cssText = 'position: absolute; top: 4px; height: 18px; box-sizing: border-box; border-radius: 3px; font-size: 8px; color: #fff; overflow: hidden; white-space: nowrap; padding: 3px 4px; cursor: grab;'
                        + 'left: ' + barX + 'px; width: ' + barW + 'px;'
                        + 'background: ' + m.color + ';'
                        + 'border: ' + (isSel ? '2px solid #fff; box-shadow: 0 0 0 1px #000;' : '1px solid rgba(0,0,0,0.4);');
                    bar.textContent = barW > 50 ? m.label : '';
                    lane.appendChild(bar);

                    bar.onmousemove = (e) => {
                        const r = bar.getBoundingClientRect();
                        const x = e.clientX - r.left;
                        bar.style.cursor = (x < 6 || x > r.width - 6) ? 'ew-resize' : 'grab';
                    };
                    bar.onmousedown = (e) => {
                        e.preventDefault();
                        if (i !== selected) {
                            setSelected(i);
                            renderInspector();
                            bar.style.border = '2px solid #fff';
                            bar.style.boxShadow = '0 0 0 1px #000';
                        }
                        const r = bar.getBoundingClientRect();
                        const grabX = e.clientX - r.left;
                        const mode = grabX < 6 ? 'l' : (grabX > r.width - 6 ? 'r' : 'move');
                        const startX = e.clientX;
                        const o = { t0: tr.t0 || 0, dur: tr.duration || 0 };
                        let moved = false;

                        const mm = (ev) => {
                            const dms = snapF((ev.clientX - startX) / pxPerMs);
                            if (dms !== 0) moved = true;
                            if (mode === 'move') {
                                tr.t0 = Math.max(0, o.t0 + dms);
                            } else if (mode === 'l') {
                                const newT0 = Math.max(0, Math.min(o.t0 + o.dur - FRAME_MS, o.t0 + dms));
                                tr.duration = o.dur + (o.t0 - newT0);
                                tr.t0 = newT0;
                            } else {
                                tr.duration = Math.max(FRAME_MS, o.dur + dms);
                            }
                            bar.style.left = ((tr.t0 || 0) * pxPerMs) + 'px';
                            bar.style.width = Math.max(4, (tr.duration || 0) * pxPerMs) + 'px';
                            nameSub.textContent = fmtF(tr.t0) + '–' + fmtF(trackEnd(tr)) + ' f';
                        };
                        const mu = () => {
                            document.removeEventListener('mousemove', mm);
                            document.removeEventListener('mouseup', mu);
                            if (moved) markChange();
                            renderTimeline();
                            renderInspector();
                        };
                        document.addEventListener('mousemove', mm);
                        document.addEventListener('mouseup', mu);
                    };
                });

                if (!anim.tracks.length) {
                    const empty = document.createElement('div');
                    empty.style.cssText = 'padding: 16px; font-size: 10px; color: #777;';
                    empty.textContent = 'No tracks yet — use "＋ Add track…" above to start.';
                    laneCol.appendChild(empty);
                }

                const playhead = document.createElement('div');
                playhead.className = 'anim-playhead';
                playhead.style.cssText = 'position: absolute; top: 0; bottom: 0; width: 0; border-left: 2px solid #cc2222; pointer-events: none; z-index: 3; left: ' + (playheadMs * pxPerMs) + 'px;';
                laneCol.appendChild(playhead);

                drawOverlayHandles();
            };

            // ---------------- inspector (collapsible, 4-per-row, tooltips) ----------------
            const ensureTrackId = (t) => {
                if (!t.id) t.id = 'trk_' + Math.random().toString(36).slice(2, 8);
                return t.id;
            };

            const section = (parent, title, startOpen = true) => {
                const storeKey = 'hkt_anim_sec_' + title;
                const saved = sessionStorage.getItem(storeKey);
                let open = saved !== null ? saved === '1' : startOpen;

                const wrap = document.createElement('div');
                wrap.style.cssText = 'border: 1px solid var(--win-shadow); margin-bottom: 6px;';
                const head = document.createElement('div');
                head.style.cssText = 'background: var(--win-blue); color: #fff; padding: 3px 8px; font-weight: bold; font-size: 10px; cursor: pointer; display: flex; justify-content: space-between; user-select: none;';
                head.innerHTML = '<span>' + title + '</span><span>' + (open ? '▼' : '▶') + '</span>';
                wrap.appendChild(head);

                const grid = document.createElement('div');
                grid.style.cssText = 'padding: 6px; display: ' + (open ? 'grid' : 'none') + '; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 4px 8px; align-items: end;';
                wrap.appendChild(grid);

                head.onclick = () => {
                    open = grid.style.display === 'none';
                    grid.style.display = open ? 'grid' : 'none';
                    head.children[1].textContent = open ? '▼' : '▶';
                    sessionStorage.setItem(storeKey, open ? '1' : '0');
                };
                parent.appendChild(wrap);
                return grid;
            };

            // Compact cell: tiny label over an input. The help tooltip is put
            // on the field itself (and its label) — no separate icon.
            const cell = (grid, label, inputEl, span = 1, helpKey) => {
                const c = document.createElement('div');
                c.style.cssText = 'display: flex; flex-direction: column; gap: 1px; min-width: 0;' + (span > 1 ? 'grid-column: span ' + span + ';' : '');
                const l = document.createElement('label');
                l.style.cssText = 'font-size: 9px; color: var(--win-dark-shadow); white-space: nowrap; overflow: hidden; text-overflow: ellipsis;';
                l.textContent = label;
                const help = helpKey && HELP[helpKey];
                if (help) { l.title = help; l.style.cursor = 'help'; }
                c.appendChild(l);
                inputEl.style.width = '100%';
                inputEl.style.boxSizing = 'border-box';
                if (help) inputEl.title = help;
                c.appendChild(inputEl);
                grid.appendChild(c);
                return inputEl;
            };

            const numCell = (grid, label, obj, key, def, opts) => {
                opts = opts || {};
                const inp = document.createElement('input');
                inp.type = 'number';
                inp.className = 'win98-input drag-num';
                const stepSize = opts.step ? parseFloat(opts.step) : 1;
                if (opts.step) inp.step = opts.step;
                inp.value = opts.frames
                    ? fmtF(obj[key] !== undefined ? obj[key] : def)
                    : (obj[key] !== undefined ? obj[key] : def);
                const applyValue = (rawStr) => {
                    if (opts.blankable && rawStr === '') { delete obj[key]; markChange(); if (opts.handles) drawOverlayHandles(); return; }
                    let v = num(rawStr, opts.frames ? msToF(def) : def);
                    if (opts.frames) v = Math.max(opts.min !== undefined ? opts.min : 0, fToMs(v));
                    else if (opts.int) v = Math.round(v);
                    else if (opts.min !== undefined) v = Math.max(opts.min, v);
                    obj[key] = v;
                    markChange();
                    if (opts.retime) { renderTimeline(); updateFrameView(); }
                    if (opts.handles) drawOverlayHandles();
                };
                inp.onchange = () => applyValue(inp.value);
                attachDragScrub(inp, { stepSize, onScrub: () => applyValue(inp.value) });
                return cell(grid, label, inp, opts.span || 1, opts.help || key);
            };

            const selectCell = (grid, label, options, current, onChange, span = 1, helpKey) => {
                const sel = makeSelect(options, current, onChange);
                return cell(grid, label, sel, span, helpKey);
            };

            const colorCell = (grid, label, tr, key) => {
                const pick = document.createElement('input');
                pick.type = 'color';
                pick.value = rgb01ToHex(tr[key]);
                pick.style.height = '21px';
                pick.oninput = () => { tr[key] = hexToRgb01(pick.value); markChange(); };
                return cell(grid, label, pick);
            };

            const checkCell = (grid, label, checked, onChange, span = 1, helpKey) => {
                const c = document.createElement('div');
                c.style.cssText = 'display: flex; align-items: center; gap: 4px; min-width: 0;' + (span > 1 ? 'grid-column: span ' + span + ';' : '');
                const chk = document.createElement('input');
                chk.type = 'checkbox';
                chk.checked = checked;
                chk.onchange = () => onChange(chk.checked);
                c.appendChild(chk);
                const l = document.createElement('label');
                l.style.cssText = 'font-size: 9px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;';
                l.textContent = label;
                if (helpKey && HELP[helpKey]) { l.title = HELP[helpKey]; c.title = HELP[helpKey]; }
                l.onclick = () => { chk.checked = !chk.checked; chk.onchange(); };
                c.appendChild(l);
                grid.appendChild(c);
                return chk;
            };

            const noteRow = (grid, text) => {
                const n = document.createElement('div');
                n.style.cssText = 'grid-column: 1 / -1; font-size: 9px; color: var(--win-dark-shadow);';
                n.textContent = text;
                grid.appendChild(n);
            };

            // Visual cell/flipbook picker: shows the sheet with a grid overlay
            // and highlights the selected [cellStart .. cellStart+cellCount-1].
            const renderCellPicker = (grid, tr) => {
                const wrap = document.createElement('div');
                wrap.style.cssText = 'grid-column: 1 / -1; margin-top: 2px;';
                const lbl = document.createElement('label');
                lbl.style.cssText = 'font-size: 9px; color: var(--win-dark-shadow);';
                lbl.textContent = 'Cells — click a cell to set start, Shift-click to set the end:';
                wrap.appendChild(lbl);

                const holder = document.createElement('div');
                holder.style.cssText = 'position: relative; display: inline-block; border: 1px inset var(--win-shadow); background: #111; margin-top: 2px; max-width: 100%;';
                wrap.appendChild(holder);

                if (!tr.particleTexture) {
                    const none = document.createElement('div');
                    none.style.cssText = 'font-size: 9px; color: #999; padding: 8px;';
                    none.textContent = 'Pick a texture above to lay out cells.';
                    holder.appendChild(none);
                    grid.appendChild(wrap);
                    return;
                }

                const img = new Image();
                img.style.cssText = 'display: block; image-rendering: pixelated;';
                img.onload = () => {
                    const natW = img.naturalWidth, natH = img.naturalHeight;
                    const dispW = Math.min(natW, 256);
                    const s = dispW / natW;
                    img.width = Math.round(natW * s);
                    img.height = Math.round(natH * s);
                    const cw = tr.cellW || 0, ch = tr.cellH || 0;
                    if (cw > 0 && ch > 0) {
                        const cols = Math.max(1, Math.floor(natW / cw));
                        const rows = Math.max(1, Math.floor(natH / ch));
                        const start = tr.cellStart || 0;
                        const count = tr.cellCount || 0;
                        for (let idx = 0; idx < cols * rows; idx++) {
                            const col = idx % cols, row = Math.floor(idx / cols);
                            const inRange = idx >= start && idx < start + count;
                            const g = document.createElement('div');
                            g.style.cssText = 'position: absolute; box-sizing: border-box; left: ' + (col * cw * s) + 'px; top: ' + (row * ch * s) + 'px; width: ' + (cw * s) + 'px; height: ' + (ch * s) + 'px; cursor: pointer;'
                                + 'border: 1px solid ' + (inRange ? '#33ff88' : 'rgba(255,255,255,0.25)') + ';'
                                + (inRange ? 'background: rgba(51,255,136,0.22);' : '');
                            g.title = 'cell ' + idx;
                            g.onclick = (e) => {
                                if (e.shiftKey) {
                                    const st = tr.cellStart || 0;
                                    if (idx >= st) { tr.cellCount = idx - st + 1; }
                                } else {
                                    tr.cellStart = idx;
                                    if (!tr.cellCount) tr.cellCount = 1;
                                }
                                markChange();
                                renderInspector();
                            };
                            holder.appendChild(g);
                        }
                    }
                };
                img.src = '/' + tr.particleTexture.replace(/^\/+/, '');
                holder.appendChild(img);
                grid.appendChild(wrap);
            };

            const renderInspector = () => {
                inspectorCol.innerHTML = '';
                const tr = selTrack();

                if (!tr) {
                    const ph = document.createElement('div');
                    ph.style.cssText = 'color: #777; text-align: center; padding: 30px 10px; font-size: 11px;';
                    ph.textContent = anim.tracks.length
                        ? 'Select a track in the timeline below to edit it.'
                        : 'This animation has no tracks. Add one with "＋ Add track…" in the timeline.';
                    inspectorCol.appendChild(ph);
                    return;
                }

                const m = meta(tr);
                const head = document.createElement('div');
                head.style.cssText = 'display: flex; align-items: center; gap: 6px; margin-bottom: 8px;';
                const chip = document.createElement('span');
                chip.style.cssText = 'background: ' + m.color + '; color: #fff; font-size: 10px; font-weight: bold; padding: 2px 8px; border-radius: 3px; white-space: nowrap;';
                chip.textContent = m.icon + ' ' + m.label;
                head.appendChild(chip);
                const nameInput = document.createElement('input');
                nameInput.type = 'text';
                nameInput.className = 'win98-input';
                nameInput.style.flex = '1';
                nameInput.placeholder = trackLabel(tr, selected);
                nameInput.value = tr.name || '';
                nameInput.onchange = () => {
                    if (nameInput.value) tr.name = nameInput.value;
                    else delete tr.name;
                    setDirty(true);
                    renderTimeline();
                };
                head.appendChild(nameInput);
                inspectorCol.appendChild(head);

                const known = !!TRACK_META[tr.type];
                if (!known) {
                    const warn = document.createElement('div');
                    warn.style.cssText = 'font-size: 10px; color: #8a5a00; background: #ffeecc; border: 1px solid #ddbb88; padding: 4px 6px; margin-bottom: 6px;';
                    warn.textContent = 'Unknown track type "' + tr.type + '" — shown read-only so the data is preserved on save.';
                    inspectorCol.appendChild(warn);
                    const raw = document.createElement('textarea');
                    raw.className = 'win98-input';
                    raw.readOnly = true;
                    raw.style.cssText = 'width: 100%; height: 140px; font-family: monospace; font-size: 10px; box-sizing: border-box;';
                    raw.value = JSON.stringify(tr, null, 2);
                    inspectorCol.appendChild(raw);
                    return;
                }

                // -- Timing --
                const timing = section(inspectorCol, 'Timing');
                numCell(timing, 'Start (f)', tr, 't0', 0, { frames: true, retime: true, help: '_none' });
                numCell(timing, 'Length (f)', tr, 'duration', 100, { frames: true, min: FRAME_MS, retime: true, help: '_none' });
                selectCell(timing, 'Easing', [
                    { value: 'linear', label: 'Linear' },
                    { value: 'ease_out', label: 'Ease Out' }
                ], tr.easing || 'linear', val => { tr.easing = val; markChange(); });
                selectCell(timing, 'Type', Object.keys(TRACK_META).map(t => ({ value: t, label: TRACK_META[t].label })), tr.type, val => {
                    Object.keys(tr).forEach(k => { if (!SHARED_KEYS.includes(k)) delete tr[k]; });
                    tr.type = val;
                    Object.assign(tr, JSON.parse(JSON.stringify(TYPE_DEFAULTS[val] || {})));
                    markChange();
                    renderTimeline();
                    renderInspector();
                });

                // -- Type-specific --
                if (tr.type === 'transform') {
                    const motion = section(inspectorCol, 'Motion (px)');
                    numCell(motion, 'From X', tr, 'fromX', 0, { int: true, handles: true, help: '_none' });
                    numCell(motion, 'To X', tr, 'toX', 0, { int: true, handles: true, help: '_none' });
                    numCell(motion, 'From Y', tr, 'fromY', 0, { int: true, handles: true, help: '_none' });
                    numCell(motion, 'To Y', tr, 'toY', 0, { int: true, handles: true, help: '_none' });
                    noteRow(motion, 'Or drag the "from"/"to" handles on the viewer.');
                    const scale = section(inspectorCol, 'Scale (1 = normal)');
                    numCell(scale, 'From SX', tr, 'fromScaleX', 1.0, { step: '0.1', help: '_none' });
                    numCell(scale, 'To SX', tr, 'toScaleX', 1.0, { step: '0.1', help: '_none' });
                    numCell(scale, 'From SY', tr, 'fromScaleY', 1.0, { step: '0.1', help: '_none' });
                    numCell(scale, 'To SY', tr, 'toScaleY', 1.0, { step: '0.1', help: '_none' });

                } else if (tr.type === 'particles') {
                    // Presets
                    const presetWrap = section(inspectorCol, 'Preset');
                    const presetSel = document.createElement('select');
                    presetSel.className = 'win98-input';
                    const p0 = document.createElement('option'); p0.value = ''; p0.textContent = 'Apply a starter…';
                    presetSel.appendChild(p0);
                    Object.keys(PARTICLE_PRESETS).forEach(name => {
                        const o = document.createElement('option'); o.value = name; o.textContent = name; presetSel.appendChild(o);
                    });
                    presetSel.onchange = () => {
                        const p = PARTICLE_PRESETS[presetSel.value];
                        presetSel.value = '';
                        if (!p) return;
                        Object.keys(p).forEach(k => { if (k !== '_sprite') tr[k] = JSON.parse(JSON.stringify(p[k])); });
                        lastPresetHint = p._sprite || null;
                        markChange();
                        renderInspector();
                    };
                    cell(presetWrap, 'Starter preset', presetSel, 2);
                    noteRow(presetWrap, lastPresetHint
                        ? 'Recommended sprite: ' + lastPresetHint
                        : 'Presets fill emission + color; your timing and texture are kept.');

                    const emit = section(inspectorCol, 'Emission');
                    numCell(emit, 'Direction °', tr, 'direction', 270, { int: true, handles: true });
                    numCell(emit, 'Spread °', tr, 'spread', 45, { int: true, handles: true });
                    // Display falls back to the legacy `velocity` key so old
                    // data reads truthfully (the runtime prefers speed→velocity).
                    numCell(emit, 'Speed', tr, 'speed', tr.velocity !== undefined ? tr.velocity : 50, { handles: true });
                    numCell(emit, 'Speed max', tr, 'speedMax', 0, { blankable: true });
                    numCell(emit, 'Rate /s', tr, 'rate', 20);
                    numCell(emit, 'Lifetime s', tr, 'lifetime', 0.6, { step: '0.1' });
                    numCell(emit, 'Offset X', tr, 'x', 0, { int: true, handles: true });
                    numCell(emit, 'Offset Y', tr, 'y', 0, { int: true, handles: true });
                    selectCell(emit, 'Layer', [
                        { value: 'front', label: 'In front of sprite' },
                        { value: 'back', label: 'Behind sprite' }
                    ], tr.layer || 'front', val => { tr.layer = val; markChange(); }, 2, 'layer');
                    noteRow(emit, 'The green arrow on the viewer shows Direction; dashed lines show Spread.');

                    const size = section(inspectorCol, 'Size & spin');
                    numCell(size, 'Size start', tr, 'sizeStart', 1, { step: '0.1' });
                    numCell(size, 'Size end', tr, 'sizeEnd', 0, { step: '0.1' });
                    numCell(size, 'Size var', tr, 'sizeVariation', 0, { step: '0.1', blankable: true });
                    numCell(size, 'Spin °/s', tr, 'spin', 0, { int: true, blankable: true });

                    const forces = section(inspectorCol, 'Forces');
                    numCell(forces, 'Self gravity', tr, 'gravity', 0, { int: true });
                    checkCell(forces, 'Ignore Force Fields', !!tr.ignoreForces, v => {
                        if (v) tr.ignoreForces = true; else delete tr.ignoreForces;
                        markChange();
                    }, 3, 'ignoreForces');

                    const visuals = section(inspectorCol, 'Appearance');
                    const texInput = document.createElement('input');
                    texInput.type = 'text';
                    texInput.className = 'win98-input';
                    texInput.value = tr.particleTexture || '';
                    texInput.placeholder = '(default dot)';
                    const applyTex = (val) => {
                        if (val) {
                            tr.particleTexture = val;
                            const tok = parseCellTokens(val);
                            // Prefill cell size/count from filename tokens, but
                            // never clobber values the user already set.
                            if (tok.cellW && tr.cellW === undefined) tr.cellW = tok.cellW;
                            if (tok.cellH && tr.cellH === undefined) tr.cellH = tok.cellH;
                            if (tok.cellCount && tr.cellCount === undefined) tr.cellCount = tok.cellCount;
                        } else {
                            delete tr.particleTexture;
                        }
                        markChange();
                        renderInspector();
                    };
                    texInput.onchange = () => applyTex(texInput.value);
                    cell(visuals, 'Texture', texInput, 3);
                    const browseBtn = document.createElement('button');
                    browseBtn.className = 'win98-btn';
                    browseBtn.textContent = 'Browse…';
                    browseBtn.onclick = (e) => {
                        e.preventDefault();
                        openAssetPicker('animation', (filepath) => applyTex(filepath.replace(/\\/g, '/')));
                    };
                    cell(visuals, ' ', browseBtn);

                    if (tr.particleTexture) {
                        numCell(visuals, 'Cell W', tr, 'cellW', 0, { int: true, blankable: true });
                        numCell(visuals, 'Cell H', tr, 'cellH', 0, { int: true, blankable: true });
                        numCell(visuals, 'Start cell', tr, 'cellStart', 0, { int: true });
                        numCell(visuals, 'Cell count', tr, 'cellCount', 0, { int: true, blankable: true });
                        selectCell(visuals, 'Play', [
                            { value: 'once', label: 'Once over life' },
                            { value: 'loop', label: 'Loop' }
                        ], tr.cellMode || 'once', val => { tr.cellMode = val; markChange(); renderInspector(); }, 1, 'cellMode');
                        if (tr.cellMode === 'loop') {
                            numCell(visuals, 'Loops', tr, 'cellLoops', 1, { int: true, min: 1 });
                        }
                        renderCellPicker(visuals, tr);
                    }

                    checkCell(visuals, 'Mask to sprite', tr.mask === 'target', v => {
                        if (v) tr.mask = 'target'; else delete tr.mask;
                        markChange();
                    }, 2, 'mask');

                    // Color-over-life stops.
                    const stops = tr.colorOverLife || (tr.colorOverLife = [[1, 1, 1, 1], [1, 1, 1, 0]]);
                    const stopsWrap = document.createElement('div');
                    stopsWrap.style.cssText = 'grid-column: 1 / -1;';
                    const stopsLbl = document.createElement('label');
                    stopsLbl.style.cssText = 'font-size: 9px; color: var(--win-dark-shadow);';
                    stopsLbl.textContent = 'Color over lifetime (left = birth, right = death):';
                    stopsWrap.appendChild(stopsLbl);
                    const stopsRow = document.createElement('div');
                    stopsRow.style.cssText = 'display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin-top: 2px;';
                    const renderStops = () => {
                        stopsRow.innerHTML = '';
                        stops.forEach((stop, si) => {
                            const cellEl = document.createElement('div');
                            cellEl.style.cssText = 'display: flex; flex-direction: column; align-items: center; gap: 2px; border: 1px solid var(--win-shadow); padding: 3px; background: var(--win-white);';
                            const pick = document.createElement('input');
                            pick.type = 'color';
                            pick.value = rgb01ToHex(stop);
                            pick.style.cssText = 'width: 32px; height: 20px; padding: 0; border: none;';
                            pick.oninput = () => {
                                const rgb = hexToRgb01(pick.value);
                                stop[0] = rgb[0]; stop[1] = rgb[1]; stop[2] = rgb[2];
                                markChange();
                            };
                            cellEl.appendChild(pick);
                            const alpha = document.createElement('input');
                            alpha.type = 'number';
                            alpha.className = 'win98-input';
                            alpha.min = '0'; alpha.max = '1'; alpha.step = '0.1';
                            alpha.value = stop[3] !== undefined ? stop[3] : 1;
                            alpha.title = 'Alpha';
                            alpha.style.width = '42px';
                            alpha.onchange = () => { stop[3] = num(alpha.value, 1); markChange(); };
                            cellEl.appendChild(alpha);
                            if (stops.length > 2) {
                                const rm = document.createElement('button');
                                rm.className = 'win98-btn';
                                rm.textContent = '×';
                                rm.style.cssText = 'padding: 0 4px; font-size: 9px;';
                                rm.onclick = (e) => { e.preventDefault(); stops.splice(si, 1); markChange(); renderStops(); };
                                cellEl.appendChild(rm);
                            }
                            stopsRow.appendChild(cellEl);
                        });
                        const addStop = document.createElement('button');
                        addStop.className = 'win98-btn';
                        addStop.textContent = '+ stop';
                        addStop.style.padding = '2px 6px';
                        addStop.onclick = (e) => {
                            e.preventDefault();
                            const last = stops[stops.length - 1];
                            stops.push(last ? last.slice() : [1, 1, 1, 1]);
                            markChange();
                            renderStops();
                        };
                        stopsRow.appendChild(addStop);
                    };
                    renderStops();
                    stopsWrap.appendChild(stopsRow);
                    visuals.appendChild(stopsWrap);

                } else if (tr.type === 'force_field') {
                    const ff = section(inspectorCol, 'Force Field');
                    selectCell(ff, 'Field', [
                        { value: 'gravity', label: 'Gravity (push)' },
                        { value: 'attract', label: 'Attract / repel' },
                        { value: 'vortex', label: 'Vortex (orbit)' },
                        { value: 'drag', label: 'Drag (slow)' }
                    ], tr.field || 'gravity', val => { tr.field = val; markChange(); renderInspector(); }, 2, 'field');
                    numCell(ff, 'Strength', tr, 'strength', 60, { int: true, handles: true });
                    if (tr.field === 'gravity') {
                        numCell(ff, 'Angle °', tr, 'angle', 90, { int: true, handles: true });
                    }
                    noteRow(ff, 'Affects every particle track in this animation (unless a track sets "Ignore Force Fields").');

                } else if (tr.type === 'tint') {
                    const look = section(inspectorCol, 'Tint');
                    colorCell(look, 'Color', tr, 'color');
                    numCell(look, 'From α (0–1)', tr, 'fromAlpha', 1, { step: '0.1', help: '_none' });
                    numCell(look, 'To α (0–1)', tr, 'toAlpha', 0, { step: '0.1', help: '_none' });

                } else if (tr.type === 'blend') {
                    const look = section(inspectorCol, 'Blend');
                    selectCell(look, 'Mode', [
                        { value: 'add', label: 'Add (glow)' },
                        { value: 'alpha', label: 'Alpha (normal)' }
                    ], tr.mode || 'add', val => { tr.mode = val; markChange(); }, 2);

                } else if (tr.type === 'shake') {
                    const look = section(inspectorCol, 'Shake');
                    numCell(look, 'Amplitude px', tr, 'amplitude', 2, { int: true, help: '_none' });
                    numCell(look, 'Frequency Hz', tr, 'frequency', 30, { int: true, help: '_none' });

                } else if (tr.type === 'screen_flash') {
                    const look = section(inspectorCol, 'Screen Flash');
                    colorCell(look, 'Color', tr, 'color');
                    numCell(look, 'From α (0–1)', tr, 'fromAlpha', 0.8, { step: '0.1', help: '_none' });
                    numCell(look, 'To α (0–1)', tr, 'toAlpha', 0, { step: '0.1', help: '_none' });
                    noteRow(look, 'Fills the whole screen with the color; alpha fades from → to over the track.');

                } else if (tr.type === 'gradient_map') {
                    const look = section(inspectorCol, 'Gradient Map');
                    colorCell(look, 'Shadows (low)', tr, 'lowColor');
                    colorCell(look, 'Highlights (high)', tr, 'highColor');
                    numCell(look, 'Intensity from', tr, 'fromIntensity', 1, { step: '0.1', min: 0, help: 'intensity' });
                    numCell(look, 'Intensity to', tr, 'toIntensity', 1, { step: '0.1', min: 0, help: 'intensity' });
                    noteRow(look, "Recolors the sprite by brightness: dark pixels → Shadows, bright → Highlights. Animate Intensity for a wash-in/out.");
                }

                // -- Parenting (advanced) --
                const adv = section(inspectorCol, 'Parenting (advanced)', false);
                const parentOptions = [{ value: '', label: '(none)' }];
                anim.tracks.forEach((t, i) => {
                    if (t !== tr) parentOptions.push({ value: ensureTrackId(t), label: trackLabel(t, i) });
                });
                selectCell(adv, 'Follow track', parentOptions, tr.parent || '', val => {
                    if (val) { ensureTrackId(tr); tr.parent = val; }
                    else delete tr.parent;
                    markChange();
                    renderTimeline();
                    renderInspector();
                }, 2);
                if (tr.parent) {
                    checkCell(adv, 'Inherit position', tr.inheritPosition !== 'never', v => {
                        tr.inheritPosition = v ? 'always' : 'never';
                        markChange();
                    });
                    checkCell(adv, 'Inherit scale', tr.inheritScale !== 'never', v => {
                        tr.inheritScale = v ? 'always' : 'never';
                        markChange();
                    });
                }
            };

            // ---------------- boot & cleanup ----------------
            const onResize = () => renderTimeline();
            window.addEventListener('resize', onResize);

            formPanel._animCleanup = () => {
                stopPlayback();
                clearTimeout(bakeTimer);
                window.removeEventListener('resize', onResize);
                if (window.onAnimationTrackChanged === markChange) window.onAnimationTrackChanged = null;
            };

            renderInspector();
            renderTimeline();
            updateFrameView();
            doBake();
        };
        })();
