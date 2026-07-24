(function() {
    let editorThemes = [];
    let activeThemeId = localStorage.getItem('activeThemeId') || 'classic';
    let studioModalSnapshot = null;
    let studioModalDirty = false;

    const THEME_CATEGORIES = [
        {
            title: "🖥️ Desktop & Window Frame",
            keys: [
                { id: "desktop-bg", label: "Desktop Workspace", desc: "Background color behind windows", default: "#008080" },
                { id: "window-bg", label: "Window Frame / Toolbar", desc: "Main window background and dialog fill", default: "#c0c0c0" },
                { id: "window-text", label: "Window Text Color", desc: "Standard text color across the editor", default: "#000000" },
                { id: "window-border", label: "Window Outer Border", desc: "Outer border color for popups and windows", default: "#000000" }
            ]
        },
        {
            title: "🏷️ Title Bars & Header",
            keys: [
                { id: "window-header-bg-start", label: "Header Gradient (Start)", desc: "Left side of window title bar gradient", default: "#000080" },
                { id: "window-header-bg-end", label: "Header Gradient (End)", desc: "Right side of window title bar gradient", default: "#0000a8" },
                { id: "window-header-text", label: "Header Title Text", desc: "Text color inside window title bars", default: "#ffffff" }
            ]
        },
        {
            title: "📄 Panels, Buttons & Selection",
            keys: [
                { id: "content-bg", label: "Container Panel Fill", desc: "Background fill for nested panels and forms", default: "#ffffff" },
                { id: "button-bg", label: "Button Fill", desc: "Background color of standard buttons", default: "#c0c0c0" },
                { id: "selection-bg", label: "Selection Highlight", desc: "Background highlight for selected rows/tabs", default: "#000080" },
                { id: "selection-text", label: "Selection Text", desc: "Text color for selected rows/tabs", default: "#ffffff" }
            ]
        },
        {
            title: "🔳 3D Bevel Highlights",
            keys: [
                { id: "bezel-light", label: "Bevel Light Highlight", desc: "Top/left raised edge color", default: "#ffffff" },
                { id: "bezel-shadow", label: "Bevel Medium Shadow", desc: "Bottom/right inner shadow color", default: "#808080" },
                { id: "bezel-dark", label: "Bevel Dark Shadow", desc: "Deep inset border shadow color", default: "#404040" }
            ]
        },
        {
            title: "💬 Tooltips & Popovers",
            keys: [
                { id: "tooltip-bg", label: "Tooltip Background", desc: "Background fill for info tooltips", default: "#ffffe1" },
                { id: "tooltip-text", label: "Tooltip Text", desc: "Text color inside tooltips", default: "#000000" }
            ]
        }
    ];

    // Apply theme to document documentElement (:root)
    function applyTheme(theme) {
        if (!theme || !theme.colors) return;
        const root = document.documentElement;
        const colors = theme.colors;
        const mappings = {
            'desktop-bg': '--desktop-teal',
            'window-bg': '--win-gray',
            'window-text': '--text-color',
            'window-border': '--win-border',
            'window-header-bg-start': '--title-blue',
            'window-header-bg-end': '--title-blue-light',
            'window-header-text': '--title-text',
            'content-bg': '--cool-bg',
            'button-bg': '--button-bg',
            'selection-bg': '--selection-bg',
            'selection-text': '--selection-text',
            'bezel-light': '--win-white',
            'bezel-shadow': '--win-shadow',
            'bezel-dark': '--win-dark-shadow',
            'tooltip-bg': '--tooltip-bg',
            'tooltip-text': '--tooltip-text'
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
        nameGroup.style.marginBottom = '12px';
        const nameLabel = document.createElement('label');
        nameLabel.style.fontWeight = 'bold';
        nameLabel.textContent = 'Theme Name:';
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

        theme.colors = theme.colors || {};
        
        THEME_CATEGORIES.forEach(cat => {
            const catHeader = document.createElement('div');
            catHeader.style.cssText = 'font-weight: bold; font-size: 11px; margin-top: 10px; margin-bottom: 6px; padding-bottom: 2px; border-bottom: 1px solid var(--win-shadow); color: var(--text-color);';
            catHeader.textContent = cat.title;
            panel.appendChild(catHeader);
            
            const grid = document.createElement('div');
            grid.style.cssText = 'display: grid; grid-template-columns: 1fr 1fr; gap: 6px 12px; margin-bottom: 8px;';
            
            cat.keys.forEach(field => {
                const key = field.id;
                if (theme.colors[key] === undefined) {
                    theme.colors[key] = field.default || '#000000';
                }
                const row = document.createElement('div');
                row.style.cssText = 'display: flex; align-items: center; gap: 6px;';
                
                const lbl = document.createElement('span');
                lbl.style.cssText = 'flex: 1; font-size: 10px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; cursor: help;';
                lbl.textContent = field.label;
                lbl.title = `${field.label} (${key}): ${field.desc}`;
                
                const isHex = /^#[0-9a-fA-F]{6}$/.test(theme.colors[key] || '');
                const pick = document.createElement('input');
                pick.type = 'color';
                pick.style.cssText = 'width: 28px; height: 20px; padding: 0; border: 1px solid var(--win-shadow); cursor: pointer;';
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
        });
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
