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

function initProfileControls() {
    const prof = window.resolveIconKeyProfile ? window.resolveIconKeyProfile(activeIconSelection.id) : {};
    activeCustomProfile = Object.assign({}, prof);

    const hueEl = document.getElementById('pk-hue');
    const tolEl = document.getElementById('pk-tol');
    const satEl = document.getElementById('pk-sat');

    // `||` would discard a legitimately-saved 0 and snap back to the default.
    const fieldOr = (v, fallback) => (typeof v === 'number' && !isNaN(v)) ? v : fallback;

    if (hueEl) {
        hueEl.value = fieldOr(activeCustomProfile.targetHue, 0);
        document.getElementById('pk-hue-val').textContent = parseFloat(hueEl.value).toFixed(2);
        hueEl.oninput = () => {
            activeCustomProfile.targetHue = parseFloat(hueEl.value);
            document.getElementById('pk-hue-val').textContent = activeCustomProfile.targetHue.toFixed(2);
            updatePickerPreview();
        };
    }
    if (tolEl) {
        tolEl.value = fieldOr(activeCustomProfile.hueTolerance, 0.08);
        document.getElementById('pk-tol-val').textContent = parseFloat(tolEl.value).toFixed(2);
        tolEl.oninput = () => {
            activeCustomProfile.hueTolerance = parseFloat(tolEl.value);
            document.getElementById('pk-tol-val').textContent = activeCustomProfile.hueTolerance.toFixed(2);
            updatePickerPreview();
        };
    }
    if (satEl) {
        satEl.value = fieldOr(activeCustomProfile.minimumSaturation, 0.25);
        document.getElementById('pk-sat-val').textContent = parseFloat(satEl.value).toFixed(2);
        satEl.oninput = () => {
            activeCustomProfile.minimumSaturation = parseFloat(satEl.value);
            document.getElementById('pk-sat-val').textContent = activeCustomProfile.minimumSaturation.toFixed(2);
            updatePickerPreview();
        };
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
