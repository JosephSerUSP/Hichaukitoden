function createIconField(container, labelText, value, onChange, useBlockLayout = true) {
    const group = document.createElement('div');
    group.className = useBlockLayout ? 'form-group' : 'form-group field-inline';
    if (!useBlockLayout) { group.style.display = 'flex';   }



    const lbl = document.createElement('label');
    lbl.textContent = labelText;
    lbl.style.marginBottom = '0';
    lbl.style.minWidth = '80px';
    group.appendChild(lbl);

    const innerContainer = document.createElement('div');
    innerContainer.style.display = 'flex';
    innerContainer.style.alignItems = 'center';
    innerContainer.style.gap = '8px';
    group.appendChild(innerContainer);

    const swatch = document.createElement('div');
    swatch.style.width = '24px';
    swatch.style.height = '24px';
    swatch.style.backgroundImage = 'url(/assets/system/iconset.png)';
    swatch.style.backgroundSize = '240px auto';
    swatch.style.border = '1px solid #ccc';
    swatch.style.imageRendering = 'pixelated';

    function updateSwatch(id) {
        if (!id || id <= 0) {
            swatch.style.backgroundPosition = '-0px -0px'; // Maybe a fallback or clear
            return;
        }
        const col = (id - 1) % 10;
        const row = Math.floor((id - 1) / 10);
        swatch.style.backgroundPosition = `-${col * 24}px -${row * 24}px`;
    }
    updateSwatch(value);
    innerContainer.appendChild(swatch);

    const idLabel = document.createElement('span');
    idLabel.textContent = `ID: ${value || 0}`;
    idLabel.style.minWidth = '40px';
    innerContainer.appendChild(idLabel);

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
            // Trigger dirty by dispatching a change event that state.js listens to
            const evt = new Event('change', { bubbles: true });
            btn.dispatchEvent(evt);
        });
    };
    innerContainer.appendChild(btn);

    container.appendChild(group);
}
window.createIconField = createIconField;
