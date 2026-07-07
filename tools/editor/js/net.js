
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