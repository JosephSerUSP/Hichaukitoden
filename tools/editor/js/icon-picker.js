let iconPickerCallback = null;

// Iconset has 10 columns; every icon-grid position (picker cells, field
// swatches) derives from this one lookup instead of re-deriving col/row.
const ICON_GRID_COLS = 10;

function iconGridPos(id, cellPx) {
    const col = (id - 1) % ICON_GRID_COLS;
    const row = Math.floor((id - 1) / ICON_GRID_COLS);
    return { col, row, x: col * cellPx, y: row * cellPx };
}
window.iconGridPos = iconGridPos;

function openIconPicker(currentId, cb) {
    iconPickerCallback = cb;
    const grid = document.getElementById('icon-picker-grid');
    grid.innerHTML = '';

    // Iconset has 10 columns
    const iconSize = 8; // 8x8
    const displaySize = 24; // Scaled 3x

    // Assuming max icons is large, say 200, could determine from image dimensions but this is simpler
    const maxIcons = 300;

    for (let i = 1; i <= maxIcons; i++) {
        const { x, y } = iconGridPos(i, displaySize);

        const cell = document.createElement('div');
        cell.style.width = displaySize + 'px';
        cell.style.height = displaySize + 'px';
        cell.style.backgroundImage = 'url(/assets/system/iconset.png)';
        cell.style.backgroundPosition = `-${x}px -${y}px`;
        cell.style.backgroundSize = `${ICON_GRID_COLS * displaySize}px auto`; // Scale image 2x (10 cols * 24px)
        cell.style.cursor = 'pointer';
        cell.style.border = (i === currentId) ? '2px solid red' : '1px solid #ccc';
        cell.style.boxSizing = 'border-box';

        // Use image rendering pixelated
        cell.style.imageRendering = 'pixelated';

        cell.onmouseenter = () => {
            document.getElementById('icon-picker-hover-info').textContent = 'Icon: ' + i;
            cell.style.backgroundColor = '#e0e0e0';
        };
        cell.onmouseleave = () => {
            cell.style.backgroundColor = '';
        };

        cell.onclick = () => {
            if (iconPickerCallback) {
                iconPickerCallback(i);
            }
            closeIconPicker();
        };

        grid.appendChild(cell);
    }

    document.getElementById('icon-picker-modal').classList.add('active');
    // Scroll to current id if needed
    if (currentId > 0) {
        const currentCell = grid.children[currentId - 1];
        if (currentCell) {
             currentCell.scrollIntoView({ block: 'center' });
        }
    }
}

function closeIconPicker() {
    document.getElementById('icon-picker-modal').classList.remove('active');
}
window.openIconPicker = openIconPicker;
window.closeIconPicker = closeIconPicker;
