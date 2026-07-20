let iconPickerCallback = null;

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
        const col = (i - 1) % 10;
        const row = Math.floor((i - 1) / 10);

        const cell = document.createElement('div');
        cell.style.width = displaySize + 'px';
        cell.style.height = displaySize + 'px';
        cell.style.backgroundImage = 'url(/assets/system/iconset.png)';
        cell.style.backgroundPosition = `-${col * displaySize}px -${row * displaySize}px`;
        cell.style.backgroundSize = `${10 * displaySize}px auto`; // Scale image 2x (10 cols * 24px)
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
