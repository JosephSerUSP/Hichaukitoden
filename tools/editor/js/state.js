var API_URL = 'http://127.0.0.1:8080';
        var dbPayload = {};
        var isDirty = false;

        function setDirty(dirty) {
            isDirty = dirty;
            const saveBtns = [
                document.getElementById('tool-save-btn'),
                document.getElementById('status-save-btn'),
                document.getElementById('db-apply-btn')
            ];
            saveBtns.forEach(btn => {
                if (btn) btn.disabled = !dirty;
            });
        }

        // --- GENERIC MODAL DIRTY-TRACKING / ESCAPE HANDLING ---
        // Each staged-edit modal (fields only commit to dbPayload on OK) sets its
        // own `*Dirty` flag to true via a delegated input/change listener, and
        // resets it to false when the modal opens. Close handlers accept an
        // optional `force` flag so the OK button can close without prompting.
        function confirmDiscard(message) {
            return confirm(message || 'You have unsaved changes. Discard them?');
        }

        function wireModalDirtyTracking(modalId, setDirtyFn) {
            const el = document.getElementById(modalId);
            if (!el) return;
            el.addEventListener('input', setDirtyFn);
            el.addEventListener('change', setDirtyFn);
        }

        // Closes whichever staged-edit modal is topmost (by declared z-index).
        // Registered once; each entry's close function already knows how to
        // prompt-and-discard if that modal has unsaved staged changes.
        const ESCAPE_MODAL_CLOSERS = [
            ['asset-picker-modal', () => closeAssetPicker()],
            ['cmd-modal', () => closeCmdDialog()],
            ['damage-popup-modal', () => closeDamagePopupModal()],
            ['max-modal', () => closeChangeMaxDialog()],
            ['map-properties-modal', () => closeMapPropertiesModal()],
            ['event-modal', () => closeEventModal()],
            ['db-modal', () => closeDatabaseModal()],
            ['toast-modal', () => closeToast()]
        ];

        window.addEventListener('keydown', (e) => {
            if (e.key !== 'Escape') return;
            for (const [id, closeFn] of ESCAPE_MODAL_CLOSERS) {
                const el = document.getElementById(id);
                if (el && el.classList.contains('active')) {
                    closeFn();
                    return;
                }
            }
        });

        var editingMode = 'event'; // 'map' or 'event' — Event mode is the default: it's what you use most
        var activePaintTool = 'wall';
        var currentMapIndex = 0;
        var isMouseDown = false;

        var contextMenuMapIdx = null;

        function showMapContextMenu(e, mapIdx) {
            e.preventDefault();
            e.stopPropagation();
            contextMenuMapIdx = mapIdx;

            currentMapIndex = mapIdx;
            loadActiveMap();

            const menu = document.getElementById('map-context-menu');
            menu.style.left = e.clientX + 'px';
            menu.style.top = e.clientY + 'px';
            menu.style.display = 'block';
        }

        window.addEventListener('click', () => {
            ['map-context-menu', 'canvas-context-menu'].forEach(id => {
                const menu = document.getElementById(id);
                if (menu) menu.style.display = 'none';
            });
        });

        function handleMapContextMenuAction(action) {
            if (contextMenuMapIdx === null) return;
            currentMapIndex = contextMenuMapIdx;

            if (action === 'properties') {
                openMapProperties();
            } else if (action === 'new') {
                createNewMap();
            } else if (action === 'delete') {
                deleteMap();
            }
        }

        // Coordinates selected for Event edit
        var selectedEventX = 0;
        var selectedEventY = 0;

        var activeDbTab = 'actors';
        var activeDbItemId = '';

        window.addEventListener('mousedown', () => { isMouseDown = true; });
        window.addEventListener('mouseup', () => { isMouseDown = false; });
// Exports
window.setDirty = setDirty;
window.confirmDiscard = confirmDiscard;
window.wireModalDirtyTracking = wireModalDirtyTracking;
