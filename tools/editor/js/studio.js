(function() {
    let editorThemes = [];
    let activeThemeId = localStorage.getItem('activeThemeId') || 'classic';
    let studioModalSnapshot = null;
    let studioModalDirty = false;

    // Apply theme to document documentElement (:root)
    function applyTheme(theme) {
        if (!theme || !theme.colors) return;
        const root = document.documentElement;
        const colors = theme.colors;
        const mappings = {
            'window-bg': '--win-gray',
            'desktop-bg': '--desktop-teal',
            'window-header-bg-start': '--title-blue',
            'window-header-bg-end': '--title-blue-light',
            'window-text': '--text-color',
            'bezel-light': '--win-white',
            'bezel-shadow': '--win-shadow',
            'bezel-dark': '--win-dark-shadow',
            'content-bg': '--cool-bg',
            'selection-bg': '--selection-bg',
            'selection-text': '--selection-text',
            'tooltip-bg': '--tooltip-bg',
            'tooltip-text': '--tooltip-text',
            'text-highlight': '--win-blue'
        };
        for (const [token, cssVar] of Object.entries(mappings)) {
            if (colors[token]) {
                root.style.setProperty(cssVar, colors[token]);
            }
        }
    }

    // Load and apply theme on startup
    async function initStudioTheme() {
        try {
            const res = await fetch(`${API_URL}/api/editor-themes`);
            if (res.ok) {
                editorThemes = await res.json();
                const activeTheme = editorThemes.find(t => t.id === activeThemeId) || editorThemes[0];
                if (activeTheme) {
                    applyTheme(activeTheme);
                    activeThemeId = activeTheme.id;
                    localStorage.setItem('activeThemeId', activeThemeId);
                }
            }
        } catch (e) {
            console.error('Failed to load editor themes:', e);
        }
    }

    window.openStudioModal = function() {
        studioModalSnapshot = JSON.stringify({ themes: editorThemes, activeId: activeThemeId });
        studioModalDirty = false;
        
        const select = document.getElementById('studio-theme-select');
        select.innerHTML = '';
        editorThemes.forEach(t => {
            const opt = document.createElement('option');
            opt.value = t.id;
            opt.textContent = t.name || t.id;
            select.appendChild(opt);
        });
        select.value = activeThemeId;
        
        renderStudioThemeForm();
        document.getElementById('studio-modal').classList.add('active');
    };

    window.closeStudioModal = function(force) {
        if (!force && studioModalDirty && !confirmDiscard('Discard changes to preferences?')) return;
        
        if (!force && studioModalSnapshot) {
            const snap = JSON.parse(studioModalSnapshot);
            editorThemes = snap.themes;
            activeThemeId = snap.activeId;
            const activeTheme = editorThemes.find(t => t.id === activeThemeId);
            if (activeTheme) applyTheme(activeTheme);
        }
        
        document.getElementById('studio-modal').classList.remove('active');
    };

    window.onStudioThemeChange = function() {
        const select = document.getElementById('studio-theme-select');
        activeThemeId = select.value;
        const activeTheme = editorThemes.find(t => t.id === activeThemeId);
        if (activeTheme) {
            applyTheme(activeTheme);
        }
        renderStudioThemeForm();
        studioModalDirty = true;
    };

    function renderStudioThemeForm() {
        const panel = document.getElementById('studio-theme-form-panel');
        panel.innerHTML = '';
        
        const theme = editorThemes.find(t => t.id === activeThemeId);
        if (!theme) return;
        
        const nameGroup = document.createElement('div');
        nameGroup.className = 'field-row-stacked';
        nameGroup.style.marginBottom = '8px';
        const nameLabel = document.createElement('label');
        nameLabel.textContent = 'Name:';
        const nameInput = document.createElement('input');
        nameInput.className = 'win98-input';
        nameInput.value = theme.name || '';
        nameInput.oninput = () => {
            theme.name = nameInput.value;
            studioModalDirty = true;
            const select = document.getElementById('studio-theme-select');
            const opt = select.querySelector(`option[value="${theme.id}"]`);
            if (opt) opt.textContent = theme.name;
        };
        nameGroup.appendChild(nameLabel);
        nameGroup.appendChild(nameInput);
        panel.appendChild(nameGroup);

        const grid = document.createElement('div');
        grid.style.cssText = 'display: grid; grid-template-columns: 1fr 1fr; gap: 4px 12px;';
        
        theme.colors = theme.colors || {};
        const colorKeys = [
            "desktop-bg", "window-bg", "window-text", "window-border",
            "window-header-bg-start", "window-header-bg-end", "window-header-text",
            "button-bg", "terminal-bg", "terminal-text", "tile-bg", "tile-fog-bg",
            "tile-fog-text", "tile-player-bg", "text-danger", "text-highlight",
            "text-success", "text-mystic", "text-warning", "text-special",
            "text-info", "selection-bg", "selection-text", "content-bg",
            "gauge-hp", "gauge-bg", "text-functional", "bezel-light",
            "bezel-shadow", "bezel-dark", "tooltip-bg", "tooltip-text"
        ];
        
        colorKeys.forEach(key => {
            if (theme.colors[key] === undefined) {
                theme.colors[key] = '#000000';
            }
            const row = document.createElement('div');
            row.style.cssText = 'display: flex; align-items: center; gap: 4px;';
            const lbl = document.createElement('span');
            lbl.style.cssText = 'flex: 1; font-size: 10px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;';
            lbl.textContent = key;
            lbl.title = key;
            
            const isHex = /^#[0-9a-fA-F]{6}$/.test(theme.colors[key] || '');
            const pick = document.createElement('input');
            pick.type = 'color';
            pick.style.cssText = 'width: 28px; height: 20px; padding: 0; border: 1px solid var(--win-shadow);';
            pick.value = isHex ? theme.colors[key] : '#000000';
            
            const hex = document.createElement('input');
            hex.className = 'win98-input';
            hex.style.width = '72px';
            hex.value = theme.colors[key] || '';
            
            pick.oninput = () => {
                theme.colors[key] = pick.value;
                hex.value = pick.value;
                applyTheme(theme);
                studioModalDirty = true;
            };
            hex.oninput = () => {
                theme.colors[key] = hex.value;
                if (/^#[0-9a-fA-F]{6}$/.test(hex.value)) {
                    pick.value = hex.value;
                    applyTheme(theme);
                }
                studioModalDirty = true;
            };
            
            row.appendChild(lbl);
            row.appendChild(pick);
            row.appendChild(hex);
            grid.appendChild(row);
        });
        panel.appendChild(grid);
    }

    window.createStudioTheme = function() {
        const id = prompt('Enter ID for new theme (alphanumeric/underscore):');
        if (!id) return;
        const cleanId = id.trim().toLowerCase();
        if (!/^\w+$/.test(cleanId)) {
            showToast('Invalid ID format.');
            return;
        }
        if (editorThemes.some(t => t.id === cleanId)) {
            showToast('Theme ID already exists.');
            return;
        }
        const name = prompt('Enter Name for new theme:', id);
        if (!name) return;
        
        const activeTheme = editorThemes.find(t => t.id === activeThemeId) || { colors: {} };
        const newColors = {};
        Object.keys(activeTheme.colors || {}).forEach(k => {
            newColors[k] = activeTheme.colors[k];
        });
        
        const newTheme = {
            id: cleanId,
            name: name,
            colors: newColors
        };
        editorThemes.push(newTheme);
        activeThemeId = cleanId;
        
        const select = document.getElementById('studio-theme-select');
        const opt = document.createElement('option');
        opt.value = cleanId;
        opt.textContent = name;
        select.appendChild(opt);
        select.value = cleanId;
        
        applyTheme(newTheme);
        renderStudioThemeForm();
        studioModalDirty = true;
    };

    window.deleteStudioTheme = function() {
        if (editorThemes.length <= 1) {
            showToast('Cannot delete the last remaining theme.');
            return;
        }
        const theme = editorThemes.find(t => t.id === activeThemeId);
        if (!theme) return;
        if (!confirm(`Delete theme "${theme.name || theme.id}"?`)) return;
        
        editorThemes = editorThemes.filter(t => t.id !== activeThemeId);
        activeThemeId = editorThemes[0].id;
        
        const select = document.getElementById('studio-theme-select');
        const opt = select.querySelector(`option[value="${theme.id}"]`);
        if (opt) opt.remove();
        select.value = activeThemeId;
        
        applyTheme(editorThemes[0]);
        renderStudioThemeForm();
        studioModalDirty = true;
    };

    window.saveStudioThemes = async function() {
        try {
            const res = await fetch(`${API_URL}/api/editor-themes`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(editorThemes)
            });
            if (res.ok) {
                localStorage.setItem('activeThemeId', activeThemeId);
                studioModalDirty = false;
                studioModalSnapshot = JSON.stringify({ themes: editorThemes, activeId: activeThemeId });
            } else {
                showToast('Failed to save themes to server.');
            }
        } catch (e) {
            console.error('Failed to save themes:', e);
            showToast('Error saving themes.');
        }
    };

    initStudioTheme();
    
    window.addEventListener('DOMContentLoaded', () => {
        if (window.ESCAPE_MODAL_CLOSERS) {
            ESCAPE_MODAL_CLOSERS.unshift(['studio-modal', () => closeStudioModal()]);
        }
    });
})();
