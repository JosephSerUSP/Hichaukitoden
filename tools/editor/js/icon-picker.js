let iconPickerCallback = null;
let activeIconSelection = { id: 0, palette: null };
let activeCustomProfile = null;

function openIconPicker(currentIcon, cb, options) {
    iconPickerCallback = cb;
    
    if (typeof currentIcon === 'number') {
        activeIconSelection = { id: currentIcon || 0, palette: null };
    } else if (typeof currentIcon === 'object' && currentIcon !== null) {
        activeIconSelection = {
            id: currentIcon.id || currentIcon.icon || 0,
            palette: currentIcon.palette || currentIcon.iconPalette || null
        };
    } else {
        activeIconSelection = { id: 0, palette: null };
    }

    const grid = document.getElementById('icon-picker-grid');
    if (!grid) return;
    grid.innerHTML = '';

    const displaySize = 24; // 24px per cell
    const maxIcons = 220;   // 220 icons total (22 rows x 10 cols)

    const iconPath = window.getIconsetPath ? window.getIconsetPath() : '/assets/system/iconset.png';

    for (let i = 1; i <= maxIcons; i++) {
        const { x, y } = iconGridPos(i, displaySize);

        const cell = document.createElement('div');
        cell.style.width = displaySize + 'px';
        cell.style.height = displaySize + 'px';
        cell.style.backgroundImage = `url("${iconPath}")`;
        cell.style.backgroundPosition = `-${x}px -${y}px`;
        cell.style.backgroundSize = `240px auto`;
        cell.style.cursor = 'pointer';
        cell.style.border = (i === activeIconSelection.id) ? '2px solid #007acc' : '1px solid #ccc';
        cell.style.boxSizing = 'border-box';
        cell.style.imageRendering = 'pixelated';

        cell.onmouseenter = () => {
            const info = document.getElementById('icon-picker-hover-info');
            if (info) info.textContent = 'Icon: ' + i;
            cell.style.backgroundColor = '#e0e0e0';
        };
        cell.onmouseleave = () => {
            cell.style.backgroundColor = '';
        };

        cell.onclick = () => {
            activeIconSelection.id = i;
            // Update grid selection borders
            for (let c = 0; c < grid.children.length; c++) {
                grid.children[c].style.border = (c + 1 === i) ? '2px solid #007acc' : '1px solid #ccc';
            }
            updatePickerPreview();
        };

        grid.appendChild(cell);
    }

    renderPaletteList();
    initProfileControls();
    updatePickerPreview();

    const modal = document.getElementById('icon-picker-modal');
    if (modal) modal.classList.add('active');

    if (activeIconSelection.id > 0 && grid.children[activeIconSelection.id - 1]) {
        grid.children[activeIconSelection.id - 1].scrollIntoView({ block: 'center' });
    }
}

function renderPaletteList() {
    const list = document.getElementById('icon-picker-palette-list');
    if (!list) return;
    list.innerHTML = '';

    const palettes = window.iconPaletteRegistry ? window.iconPaletteRegistry() : {};

    const entries = [{ id: null, label: "Original", colors: null }].concat(
        Object.keys(palettes).map(key => ({ id: key, label: palettes[key].label || key, colors: palettes[key].colors }))
    );

    entries.forEach(p => {
        const item = document.createElement('div');
        item.style.cssText = 'display: flex; align-items: center; justify-content: space-between; padding: 4px 6px; border: 1px solid #ddd; border-radius: 3px; cursor: pointer; background: #fff; font-size: 11px;';
        if (p.id === activeIconSelection.palette) {
            item.style.borderColor = '#007acc';
            item.style.backgroundColor = '#e8f4fc';
        }

        const labelSpan = document.createElement('span');
        labelSpan.textContent = p.label;
        item.appendChild(labelSpan);

        if (p.colors) {
            const ramp = document.createElement('div');
            ramp.style.cssText = 'display: flex; gap: 2px;';
            p.colors.forEach(c => {
                const swatch = document.createElement('div');
                swatch.style.cssText = `width: 10px; height: 10px; background-color: ${c}; border: 1px solid #999; border-radius: 2px;`;
                ramp.appendChild(swatch);
            });
            item.appendChild(ramp);
        } else {
            const origLabel = document.createElement('span');
            origLabel.style.color = '#888';
            origLabel.textContent = '(Native)';
            item.appendChild(origLabel);
        }

        item.onclick = () => {
            activeIconSelection.palette = p.id;
            renderPaletteList();
            updatePickerPreview();
        };

        list.appendChild(item);
    });
}

function updatePickerPreview() {
    const canvas = document.getElementById('icon-picker-preview-canvas');
    if (canvas && window.renderIconPreview) {
        window.renderIconPreview(canvas, {
            id: activeIconSelection.id,
            palette: activeIconSelection.palette,
            profile: activeCustomProfile
        });
    }

    const idLabel = document.getElementById('icon-picker-selected-id');
    if (idLabel) idLabel.textContent = `Icon #${activeIconSelection.id || 0}`;

    const paletteLabel = document.getElementById('icon-picker-selected-palette');
    if (paletteLabel) {
        paletteLabel.textContent = `Palette: ${activeIconSelection.palette || 'Original'}`;
    }
}

// All five keying fields the runtime profile carries, in panel order.
const PROFILE_SLIDERS = [
    { el: 'pk-hue',  out: 'pk-hue-val',  field: 'targetHue',         fallback: 0.0  },
    { el: 'pk-tol',  out: 'pk-tol-val',  field: 'hueTolerance',      fallback: 0.08 },
    { el: 'pk-sat',  out: 'pk-sat-val',  field: 'minimumSaturation', fallback: 0.25 },
    { el: 'pk-lmin', out: 'pk-lmin-val', field: 'minimumLightness',  fallback: 0.10 },
    { el: 'pk-lmax', out: 'pk-lmax-val', field: 'maximumLightness',  fallback: 0.95 },
];

function initProfileControls() {
    const prof = window.resolveIconKeyProfile ? window.resolveIconKeyProfile(activeIconSelection.id) : {};
    activeCustomProfile = Object.assign({}, prof);

    // `||` would discard a legitimately-saved 0 and snap back to the default.
    const fieldOr = (v, fallback) => (typeof v === 'number' && !isNaN(v)) ? v : fallback;

    PROFILE_SLIDERS.forEach(spec => {
        const el = document.getElementById(spec.el);
        const out = document.getElementById(spec.out);
        if (!el) return;

        el.value = fieldOr(activeCustomProfile[spec.field], spec.fallback);
        if (out) out.textContent = parseFloat(el.value).toFixed(2);

        el.oninput = () => {
            activeCustomProfile[spec.field] = parseFloat(el.value);
            // G1 rejects a profile whose window is inverted, so keep the two
            // lightness handles from crossing rather than letting the author
            // save something the validator will refuse.
            clampLightnessWindow(spec.field);
            PROFILE_SLIDERS.forEach(s => {
                const e = document.getElementById(s.el);
                const o = document.getElementById(s.out);
                if (e) e.value = activeCustomProfile[s.field];
                if (o) o.textContent = parseFloat(activeCustomProfile[s.field]).toFixed(2);
            });
            updatePickerPreview();
        };
    });
}

function clampLightnessWindow(movedField) {
    const lo = activeCustomProfile.minimumLightness;
    const hi = activeCustomProfile.maximumLightness;
    if (typeof lo !== 'number' || typeof hi !== 'number' || lo <= hi) return;
    if (movedField === 'minimumLightness') {
        activeCustomProfile.maximumLightness = lo;
    } else if (movedField === 'maximumLightness') {
        activeCustomProfile.minimumLightness = hi;
    }
}

function saveIconKeyProfile() {
    if (!activeIconSelection.id) return;
    const db = window.iconDb ? window.iconDb() : null;
    if (!db) return;
    db.iconKeyProfiles = db.iconKeyProfiles || {};
    db.iconKeyProfiles[String(activeIconSelection.id)] = Object.assign({}, activeCustomProfile);
    if (typeof setDirty === 'function') setDirty(true);
    alert(`Saved key profile calibration for Icon #${activeIconSelection.id}`);
}

function resetIconKeyProfile() {
    if (!activeIconSelection.id) return;
    const db = window.iconDb ? window.iconDb() : null;
    if (db && db.iconKeyProfiles) {
        delete db.iconKeyProfiles[String(activeIconSelection.id)];
    }
    initProfileControls();
    updatePickerPreview();
    if (typeof setDirty === 'function') setDirty(true);
}

function applyIconPickerSelection() {
    if (iconPickerCallback) {
        iconPickerCallback({
            id: activeIconSelection.id,
            palette: activeIconSelection.palette
        });
    }
    closeIconPicker();
}

function closeIconPicker() {
    const modal = document.getElementById('icon-picker-modal');
    if (modal) modal.classList.remove('active');
}

window.openIconPicker = openIconPicker;
window.closeIconPicker = closeIconPicker;
window.applyIconPickerSelection = applyIconPickerSelection;
window.saveIconKeyProfile = saveIconKeyProfile;
window.resetIconKeyProfile = resetIconKeyProfile;
