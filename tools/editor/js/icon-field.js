function createIconField(container, labelText, value, onChange) {
    const group = document.createElement('div');
    group.className = 'form-group';

    const lbl = document.createElement('label');
    lbl.textContent = labelText;
    lbl.style.marginBottom = '2px';
    group.appendChild(lbl);

    // Swatch is double-clickable to open the icon picker
    const swatch = document.createElement('div');
    swatch.style.width = '24px';
    swatch.style.height = '24px';
    swatch.style.backgroundImage = 'url(/assets/system/iconset.png)';
    swatch.style.backgroundSize = '240px auto';
    swatch.style.border = '1px solid #ccc';
    swatch.style.imageRendering = 'pixelated';
    swatch.style.flexShrink = '0';
    swatch.style.cursor = 'pointer';
    swatch.title = 'Double-click to pick icon';

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

    swatch.ondblclick = (e) => {
        e.preventDefault();
        openIconPicker(value || 0, (newId) => {
            value = newId;
            updateSwatch(newId);
            onChange(newId);
        });
    };

    group.appendChild(swatch);
    container.appendChild(group);
}
window.createIconField = createIconField;
