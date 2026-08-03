function createIconField(container, labelText, value, onChange, compact) {
    const group = document.createElement('div');

    const lbl = document.createElement('label');
    lbl.textContent = labelText;
    lbl.style.marginBottom = '2px';
    group.appendChild(lbl);

    const swatch = document.createElement('div');
    swatch.style.width = '24px';
    swatch.style.height = '24px';
    swatch.style.border = '1px solid #ccc';
    swatch.style.imageRendering = 'pixelated';
    swatch.style.flexShrink = '0';
    swatch.style.cursor = 'pointer';
    swatch.title = 'Click to pick icon & palette';

    let currentSpec = (typeof value === 'object' && value !== null)
        ? { id: parseInt(value.id || value.icon) || 0, palette: value.palette || value.iconPalette || null }
        : { id: parseInt(value) || 0, palette: null };

    function updateSwatch(spec) {
        currentSpec = (typeof spec === 'object' && spec !== null)
            ? { id: parseInt(spec.id || spec.icon) || 0, palette: spec.palette || spec.iconPalette || null }
            : { id: parseInt(spec) || 0, palette: null };

        if (window.renderIconSwatch) {
            window.renderIconSwatch(swatch, currentSpec);
        } else {
            const id = currentSpec.id || 0;
            const { x, y } = iconGridPos(id, 24);
            const iconPath = window.getIconsetPath ? window.getIconsetPath() : '/assets/system/iconset.png';
            swatch.style.backgroundImage = `url("${iconPath}")`;
            swatch.style.backgroundPosition = `-${x}px -${y}px`;
            swatch.style.backgroundSize = `240px auto`;
        }
    }
    updateSwatch(value);

    const handleOpen = (e) => {
        if (e) {
            e.preventDefault();
            e.stopPropagation();
        }
        if (window.openIconPicker) {
            window.openIconPicker(currentSpec, (res) => {
                const newId = (typeof res === 'object' && res !== null) ? (parseInt(res.id) || 0) : (parseInt(res) || 0);
                const newPalette = (typeof res === 'object' && res !== null) ? (res.palette || null) : null;
                const newSpec = { id: newId, palette: newPalette };
                updateSwatch(newSpec);
                if (onChange) onChange(newId, newPalette);
            });
        }
    };

    swatch.onclick = handleOpen;

    group.appendChild(swatch);

    if (compact) {
        group.style.cssText = 'display: flex; flex-direction: column; align-items: flex-start; flex-shrink: 0; margin-right: 0;';
    } else {
        group.className = 'form-group';
    }

    container.appendChild(group);
}
window.createIconField = createIconField;
