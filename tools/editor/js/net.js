        async function fetchDatabase() {
            try {
                const res = await fetch(`${API_URL}/data`);
                if (!res.ok) throw new Error('Database server offline');
                dbPayload = await res.json();

                initMapEditor();
                initDatabaseEditor();
                initEventModalTemplates();
                initSystemTab();

                document.getElementById('status-db').textContent = 'Database: Connected';
                setDirty(false);
            } catch (err) {
                console.error(err);
                document.getElementById('status-db').textContent = 'Database: Offline';
                showToast('Failed to connect to Hichaukitoden dev server!\n\nVerify that the game is running.');
            }
        }

        function showToast(message) {
            document.getElementById('toast-text').textContent = message;
            document.getElementById('toast-modal').classList.add('active');
        }

        function closeToast() {
            document.getElementById('toast-modal').classList.remove('active');
        }

        async function saveData() {
            try {
                const res = await fetch(`${API_URL}/save`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(dbPayload)
                });
                const result = await res.json();
                if (result.success) {
                    setDirty(false);
                    // Fields inside the Database modal are live-bound, so a
                    // successful save means there's nothing left to "discard" if
                    // the modal is closed afterwards — refresh its snapshot.
                    if (dbModalSnapshot !== null) {
                        dbModalSnapshot = JSON.stringify(dbPayload);
                    }
                } else {
                    showToast('Failed to save data: ' + result.message);
                }
            } catch (err) {
                showToast('Connection failed: server offline');
            }
        }

        async function testPlay() {
            if (isDirty && confirm('Save database changes before starting Test Play?')) {
                await saveData();
            }
            try {
                const res = await fetch(`${API_URL}/play`, { method: 'POST' });
                const result = await res.json();
                if (!result.success) {
                    showToast('Failed to launch game: ' + result.message);
                }
            } catch (err) {
                showToast('Failed to start Test Play: ' + err.message);
            }
        }

        window.addEventListener('keydown', (e) => {
            if (e.key === 'F5') {
                e.preventDefault();
                testPlay();
            }
        });

        // --- ASSET PICKER IMPLEMENTATION ---
        let activeAssetCallback = null;
        function openAssetPicker(defaultDir, callback) {
            activeAssetCallback = callback;
            document.getElementById('asset-picker-selected').value = '';

            fetch(`/api/assets?dir=${encodeURIComponent(defaultDir)}`)
                .then(r => r.json())
                .then(data => {
                    const dirSelect = document.getElementById('asset-picker-dir');
                    dirSelect.innerHTML = '';
                    data.directories.forEach(d => {
                        const opt = document.createElement('option');
                        opt.value = d;
                        opt.textContent = d;
                        if (d === defaultDir) opt.selected = true;
                        dirSelect.appendChild(opt);
                    });

                    renderAssetPickerFiles(data.files);
                    document.getElementById('asset-picker-modal').classList.add('active');
                });
        }

        function loadAssetPickerFiles() {
            const dir = document.getElementById('asset-picker-dir').value;
            fetch(`/api/assets?dir=${encodeURIComponent(dir)}`)
                .then(r => r.json())
                .then(data => {
                    renderAssetPickerFiles(data.files);
                });
        }

        function renderAssetPickerFiles(files) {
            const grid = document.getElementById('asset-picker-grid');
            grid.innerHTML = '';

            files.forEach(f => {
                const card = document.createElement('div');
                card.style.border = '1px solid #c0c0c0';
                card.style.padding = '4px';
                card.style.cursor = 'pointer';
                card.style.display = 'flex';
                card.style.flexDirection = 'column';
                card.style.alignItems = 'center';
                card.style.justifyContent = 'center';
                card.style.background = '#f0f0f0';
                card.style.fontSize = '9px';
                card.style.textAlign = 'center';
                card.style.height = '64px';
                card.style.boxSizing = 'border-box';

                const img = document.createElement('img');
                img.src = '/' + f;
                img.style.maxHeight = '32px';
                img.style.maxWidth = '100%';
                img.style.display = 'block';
                img.style.marginBottom = '2px';
                card.appendChild(img);

                const name = document.createElement('div');
                name.textContent = f.split('/').pop();
                name.style.overflow = 'hidden';
                name.style.textOverflow = 'ellipsis';
                name.style.whiteSpace = 'nowrap';
                name.style.width = '100%';
                card.appendChild(name);

                card.onclick = () => {
                    document.querySelectorAll('#asset-picker-grid > div').forEach(c => c.style.border = '1px solid #c0c0c0');
                    card.style.border = '2px solid var(--win-blue)';
                    document.getElementById('asset-picker-selected').value = f;
                };

                grid.appendChild(card);
            });
        }

        function applyAssetSelection() {
            const path = document.getElementById('asset-picker-selected').value;
            if (!path) {
                alert('Please select an asset file.');
                return;
            }
            closeAssetPicker();
            if (activeAssetCallback) activeAssetCallback(path);
        }

        function closeAssetPicker() {
            document.getElementById('asset-picker-modal').classList.remove('active');
        }
