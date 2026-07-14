
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

        function stripEmptyMeta(obj) {
            if (!obj || typeof obj !== 'object') return;
            if (Array.isArray(obj)) {
                obj.forEach(stripEmptyMeta);
                return;
            }
            if (obj.meta && typeof obj.meta === 'object' && Object.keys(obj.meta).length === 0) {
                delete obj.meta;
            }
            for (const key in obj) {
                if (Object.prototype.hasOwnProperty.call(obj, key) && typeof obj[key] === 'object' && obj[key] !== null) {
                    stripEmptyMeta(obj[key]);
                }
            }
        }

        async function saveData() {
            try {
                stripEmptyMeta(dbPayload);
                const res = await fetch(`${API_URL}/save`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(dbPayload)
                });
                const result = await res.json();
                if (result.success) {
                    // Stale-save guard: adopt the fresh on-disk tokens so the
                    // next save validates against what was just written.
                    if (result.versions) dbPayload._fileVersions = result.versions;
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