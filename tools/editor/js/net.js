
        async function fetchDatabase() {
            try {
                const res = await fetch(`${API_URL}/data`);
                if (!res.ok) throw new Error('Database server offline');
                dbPayload = await res.json();

                initMapEditor();
                initDatabaseEditor();
                initSystemTab();
                await populateCampaignPicker();

                document.getElementById('status-db').textContent = 'Database: Connected';
                setDirty(false);
            } catch (err) {
                console.error(err);
                document.getElementById('status-db').textContent = 'Database: Offline';
                showToast('Failed to connect to Hichaukitoden dev server!\n\nVerify that the game is running.');
            }
        }

        // Campaign picker: which root the Database Manager/Map/Event editors
        // read and write, and what Test Play boots (server.js's activeCampaign,
        // kept in sync with campaign.json). Repopulated on every fetchDatabase()
        // so the dropdown always reflects what's actually loaded.
        async function populateCampaignPicker() {
            const select = document.getElementById('campaign-picker');
            if (!select) return;
            try {
                const res = await fetch(`${API_URL}/campaigns/list`);
                const result = await res.json();
                select.innerHTML = '<option value="">Default (data/)</option>';
                (result.campaigns || []).forEach(name => {
                    const opt = document.createElement('option');
                    opt.value = name;
                    opt.textContent = name;
                    select.appendChild(opt);
                });
                select.value = dbPayload._activeCampaign || '';
            } catch (err) {
                // Non-fatal: the picker just stays at its last known state.
            }
        }

        async function switchCampaign(name) {
            if (isDirty && !confirmDiscard('Switch campaigns and discard unsaved changes?')) {
                // Revert the dropdown to the still-active campaign rather than
                // leaving it showing a selection that was never applied.
                document.getElementById('campaign-picker').value = dbPayload._activeCampaign || '';
                return;
            }
            try {
                const res = await fetch(`${API_URL}/campaigns/switch`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name: name || undefined })
                });
                const result = await res.json();
                if (!result.success) {
                    showToast('Failed to switch campaign: ' + result.message);
                    return;
                }
                await fetchDatabase();
                showToast('Now editing: ' + (name || 'Default (data/)'));
            } catch (err) {
                showToast('Failed to switch campaign: ' + err.message);
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
            if (Array.isArray(obj.names) && obj.names.length === 0) {
                delete obj.names;
            }
            // Event pages (engine resolvePage): an empty list means "no pages",
            // so drop the key rather than churning maps.json with `pages: []`.
            if (Array.isArray(obj.pages) && obj.pages.length === 0) {
                delete obj.pages;
            }
            for (const key in obj) {
                if (Object.prototype.hasOwnProperty.call(obj, key) && typeof obj[key] === 'object' && obj[key] !== null) {
                    stripEmptyMeta(obj[key]);
                }
            }
        }

        // Track IDs (trk_xxx) are editor-only UI handles assigned in-memory by
        // the animation editor. They only need to persist when another track's
        // `parent` references them; otherwise they're random per-session noise
        // that churns the JSON on every save. Strip the unreferenced ones so the
        // on-disk file stays stable (no spurious GitHub diffs) while keeping
        // follow-track relationships intact.
        function stripOrphanTrackIds() {
            const anims = dbPayload && dbPayload.animations;
            if (!anims || typeof anims !== 'object') return;
            for (const key in anims) {
                const anim = anims[key];
                if (!anim || !Array.isArray(anim.tracks)) continue;
                const referenced = new Set();
                anim.tracks.forEach(t => {
                    if (t && typeof t.parent === 'string' && t.parent) referenced.add(t.parent);
                });
                anim.tracks.forEach(t => {
                    if (t && typeof t.id === 'string' && t.id.indexOf('trk_') === 0 && !referenced.has(t.id)) {
                        delete t.id;
                    }
                });
            }
        }

        async function saveData() {
            try {
                stripEmptyMeta(dbPayload);
                stripOrphanTrackIds();
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
                    validateSavedData();
                    // Fields inside the Database modal are live-bound, so a
                    // successful save means there's nothing left to "discard" if
                    // the modal is closed afterwards — refresh its snapshot.
                    if (window.dbModalSnapshotHelper && typeof window.dbModalSnapshotHelper.capture === 'function') {
                        window.dbModalSnapshotHelper.capture();
                    }
                } else {
                    showToast('Failed to save data: ' + result.message);
                }
            } catch (err) {
                console.error('saveData error:', err);
                showToast('Save failed: ' + (err.message || 'server offline'));
            }
        }

        // Post-save integrity sweep: asks the server to run the engine's own
        // validator (`lovec . validate`) against what was just written and
        // surfaces any cross-reference/schema problems. Fire-and-forget so
        // saving never blocks on the ~2s engine boot; the save itself has
        // already succeeded when this runs.
        async function validateSavedData() {
            try {
                const res = await fetch(`${API_URL}/validate`);
                const result = await res.json();
                if (!result.ok) {
                    const problems = result.problems || ['unknown validation failure'];
                    document.getElementById('status-db').textContent =
                        `Database: Saved — ${problems.length} validation problem${problems.length === 1 ? '' : 's'}`;
                    showToast('Saved, but the engine validator found problems:\n\n' + problems.join('\n'));
                } else {
                    document.getElementById('status-db').textContent = 'Database: Saved ✓ validated';
                }
            } catch (err) {
                // Server went away between save and validate — the next
                // interaction will surface the offline state; stay quiet here.
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