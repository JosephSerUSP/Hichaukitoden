// Centralized Editor Icon Preview Renderer
// Matches runtime semantics in presentation/ui.lua

const ICON_GRID_COLS = 10;
const ICON_SIZE = 8;

const DEFAULT_KEY_PROFILE = {
    targetHue: 0.0,
    hueTolerance: 0.08,
    minimumSaturation: 0.25,
    minimumLightness: 0.10,
    maximumLightness: 0.95
};

// state.js declares `dbPayload` with `let`, which does NOT put it on `window`.
// Reach it through the shared script scope instead.
function iconDb() {
    return (typeof dbPayload !== 'undefined' && dbPayload) ? dbPayload : null;
}

let cachedIconsetImage = null;
let isIconsetImageLoading = false;
const pendingCallbacks = [];

function getIconsetPath() {
    if (typeof window !== 'undefined' && window.location && window.location.protocol === 'file:') {
        return '../../assets/system/iconset.png';
    }
    return '/assets/system/iconset.png';
}

function isIconsetReady() {
    return !!(cachedIconsetImage && cachedIconsetImage.complete && cachedIconsetImage.naturalWidth > 0);
}

// Register a one-shot callback for when the iconset finishes loading. Callers
// must check isIconsetReady() first: this never fires synchronously, precisely
// so a callback that re-enters the renderer cannot recurse into itself.
function onIconsetReady(cb) {
    if (cb) pendingCallbacks.push(cb);
    getIconsetImage();
}

function getIconsetImage() {
    if (isIconsetReady() || isIconsetImageLoading) {
        return cachedIconsetImage;
    }

    isIconsetImageLoading = true;
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
        cachedIconsetImage = img;
        isIconsetImageLoading = false;
        while (pendingCallbacks.length > 0) {
            const callback = pendingCallbacks.shift();
            try { callback(img); } catch (e) { console.error("Iconset callback error:", e); }
        }
    };
    img.onerror = (e) => {
        isIconsetImageLoading = false;
        console.error("Failed to load iconset.png from " + img.src, e);
    };
    img.src = getIconsetPath();
    cachedIconsetImage = img;
    return img;
}

function iconGridPos(id, cellPx) {
    const col = (id - 1) % ICON_GRID_COLS;
    const row = Math.floor((id - 1) / ICON_GRID_COLS);
    return { col, row, x: col * cellPx, y: row * cellPx };
}

function hexToRgb(hex) {
    if (Array.isArray(hex)) return hex;
    if (typeof hex !== 'string') return [255, 255, 255];
    hex = hex.replace('#', '');
    const r = parseInt(hex.substring(0, 2), 16) || 255;
    const g = parseInt(hex.substring(2, 4), 16) || 255;
    const b = parseInt(hex.substring(4, 6), 16) || 255;
    return [r, g, b];
}

// data/iconPalettes.json is the only registry. No hardcoded fallback: a second
// copy here would silently drift from the data the runtime actually renders.
function iconPaletteRegistry() {
    const db = iconDb();
    return (db && db.iconPalettes) || {};
}

function resolveIconPalette(paletteId) {
    if (!paletteId) return null;
    const entry = iconPaletteRegistry()[paletteId];
    if (!entry || !entry.colors) return null;
    return entry.colors.map(hexToRgb);
}

function resolveIconKeyProfile(iconId) {
    const db = iconDb();
    const profiles = (db && db.iconKeyProfiles) || {};
    const customProf = profiles[String(iconId)];
    const defaultProf = profiles["default"] || DEFAULT_KEY_PROFILE;
    return Object.assign({}, defaultProf, customProf || {});
}

function rgbToHsl(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    let h = 0, s = 0, l = (max + min) / 2;

    if (max !== min) {
        const d = max - min;
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        switch (max) {
            case r: h = (g - b) / d + (g < b ? 6 : 0); break;
            case g: h = (b - r) / d + 2; break;
            case b: h = (r - g) / d + 4; break;
        }
        h /= 6;
    }
    return [h, s, l];
}

function renderIconPreview(canvas, iconSpec) {
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    ctx.imageSmoothingEnabled = false;

    const id = typeof iconSpec === 'number' ? iconSpec : (iconSpec && (iconSpec.id || iconSpec.icon));
    const paletteId = typeof iconSpec === 'object' ? (iconSpec.palette || iconSpec.iconPalette) : null;

    if (!id || id <= 0) {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        return;
    }

    if (!isIconsetReady()) {
        onIconsetReady(() => renderIconPreview(canvas, iconSpec));
        return;
    }
    const img = cachedIconsetImage;

    const col = (id - 1) % ICON_GRID_COLS;
    const row = Math.floor((id - 1) / ICON_GRID_COLS);
    const sx = col * ICON_SIZE;
    const sy = row * ICON_SIZE;

    // Create 8x8 offscreen canvas
    const tempCanvas = document.createElement('canvas');
    tempCanvas.width = ICON_SIZE;
    tempCanvas.height = ICON_SIZE;
    const tempCtx = tempCanvas.getContext('2d');
    tempCtx.imageSmoothingEnabled = false;
    tempCtx.drawImage(img, sx, sy, ICON_SIZE, ICON_SIZE, 0, 0, ICON_SIZE, ICON_SIZE);

    const paletteColors = resolveIconPalette(paletteId);
    if (paletteColors) {
        try {
            const imgData = tempCtx.getImageData(0, 0, ICON_SIZE, ICON_SIZE);
            const data = imgData.data;
            const profile = (iconSpec && iconSpec.profile) || resolveIconKeyProfile(id);

            const targetHue = profile.targetHue !== undefined ? profile.targetHue : 0.0;
            const hueTol = profile.hueTolerance !== undefined ? profile.hueTolerance : 0.08;
            const minSat = profile.minimumSaturation !== undefined ? profile.minimumSaturation : 0.25;
            const minLum = profile.minimumLightness !== undefined ? profile.minimumLightness : 0.10;
            const maxLum = profile.maximumLightness !== undefined ? profile.maximumLightness : 0.95;

            for (let i = 0; i < data.length; i += 4) {
                if (data[i + 3] < 10) continue;
                const [h, s, l] = rgbToHsl(data[i], data[i + 1], data[i + 2]);

                let dh = Math.abs(h - targetHue);
                if (dh > 0.5) dh = 1.0 - dh;

                const isKeyed = (dh <= hueTol && s >= minSat && l >= minLum && l <= maxLum);
                if (isKeyed) {
                    const normLum = Math.max(0, Math.min(1, (l - minLum) / Math.max(0.0001, maxLum - minLum)));
                    let rampIdx = Math.floor(normLum * 4);
                    if (rampIdx > 3) rampIdx = 3;

                    const mappedRGB = paletteColors[rampIdx];
                    data[i] = mappedRGB[0];
                    data[i + 1] = mappedRGB[1];
                    data[i + 2] = mappedRGB[2];
                }
            }
            tempCtx.putImageData(imgData, 0, 0);
        } catch (err) {
            console.error("Canvas icon recolor error:", err);
        }
    }

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(tempCanvas, 0, 0, ICON_SIZE, ICON_SIZE, 0, 0, canvas.width, canvas.height);
}

function renderIconSwatch(element, iconSpec) {
    if (!element) return;
    const id = typeof iconSpec === 'number' ? iconSpec : (iconSpec && (iconSpec.id || iconSpec.icon));
    const paletteId = typeof iconSpec === 'object' ? (iconSpec.palette || iconSpec.iconPalette) : null;

    if (!id || id <= 0) {
        element.style.backgroundImage = 'none';
        element.innerHTML = '';
        return;
    }

    const iconPath = getIconsetPath();

    if (!paletteId) {
        element.innerHTML = '';
        const { x, y } = iconGridPos(id, 24);
        element.style.backgroundImage = `url("${iconPath}")`;
        element.style.backgroundPosition = `-${x}px -${y}px`;
        element.style.backgroundSize = `${ICON_GRID_COLS * 24}px auto`;
        element.style.imageRendering = 'pixelated';
        return;
    }

    // Render using Canvas for accurate palette preview
    let canvas = element.querySelector('canvas');
    if (!canvas) {
        element.innerHTML = '';
        element.style.backgroundImage = 'none';
        canvas = document.createElement('canvas');
        canvas.width = 24;
        canvas.height = 24;
        canvas.style.width = '24px';
        canvas.style.height = '24px';
        canvas.style.imageRendering = 'pixelated';
        element.appendChild(canvas);
    }
    renderIconPreview(canvas, { id, palette: paletteId });
}

window.getIconsetPath = getIconsetPath;
window.iconPaletteRegistry = iconPaletteRegistry;
window.iconDb = iconDb;
window.iconGridPos = iconGridPos;
window.resolveIconPalette = resolveIconPalette;
window.resolveIconKeyProfile = resolveIconKeyProfile;
window.renderIconPreview = renderIconPreview;
window.renderIconSwatch = renderIconSwatch;
