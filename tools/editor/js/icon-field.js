function createIconField(container, labelText, value, onChange) {
    const group = document.createElement('div');
    group.className = 'form-group';

    const lbl = document.createElement('label');
    lbl.textContent = labelText;
    lbl.style.marginBottom = '2px';
    group.appendChild(lbl);

    // Horizontal row for swatch + ID + Pick button (icon is the leftmost element)
    const row = document.createElement('div');
    row.style.cssText = 'display: flex; align-items: flex-start; gap: 8px;';

    const swatch = document.createElement('div');
    swatch.style.width = '24px';
    swatch.style.height = '24px';
    swatch.style.backgroundImage = 'url(/assets/system/iconset.png)';
    swatch.style.backgroundSize = '240px auto';
    swatch.style.border = '1px solid #ccc';
    swatch.style.imageRendering = 'pixelated';
    swatch.style.flexShrink = '0';

    function updateSwatch(id) {
        if (!id || id <= 0) {
            swatch.style.backgroundPosition = '-0px -0px';
            return;
        }
        const col = (id - 1) % 10;
        const row = Math.floor((id - 1) / 10);
        swatch.style.backgroundPosition = `-${col * 24}px -${row * 24}px`;
    }
    updateSwatch(value);
    row.appendChild(swatch);

    const idLabel = document.createElement('span');
    idLabel.textContent = `ID: ${value || 0}`;
    idLabel.style.minWidth = '40px';
    idLabel.style.fontSize = '11px';
    row.appendChild(idLabel);

    const btn = document.createElement('button');
    btn.className = 'win-btn outset-bevel';
    btn.textContent = 'Pick...';
    btn.onclick = (e) => {
        e.preventDefault();
        openIconPicker(value || 0, (newId) => {
            value = newId;
            updateSwatch(newId);
            idLabel.textContent = `ID: ${newId}`;
            onChange(newId);
            const evt = new Event('change', { bubbles: true });
            btn.dispatchEvent(evt);
        });
    };
    row.appendChild(btn);

    group.appendChild(row);
    container.appendChild(group);
}
window.createIconField = createIconField;
