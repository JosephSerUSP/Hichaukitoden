
        // --- EVENT CONTROLLERS ---
        let activeEventLocalScript = null;

        let eventModalDirty = false;
        let eventModalSnapshot = null;
        let eventOriginalData = null;

        // rgb01 array <-> #rrggbb hex for <input type=color>
        function rgb01ToHex(c) {
            return '#' + (c || [0.4, 0.6, 1]).slice(0, 3)
                .map(v => Math.round((v || 0) * 255).toString(16).padStart(2, '0')).join('');
        }
        function hexToRgb01(hex) {
            return [1, 3, 5].map(i => Math.round(parseInt(hex.substr(i, 2), 16) / 255 * 100) / 100);
        }

        function setEventColorFields(minimapColor) {
            const chk = document.getElementById('event-prop-color-enabled');
            const pick = document.getElementById('event-prop-color');
            chk.checked = Array.isArray(minimapColor);
            pick.disabled = !chk.checked;
            pick.value = rgb01ToHex(minimapColor);
        }
        document.getElementById('event-prop-color-enabled').onchange = () => {
            document.getElementById('event-prop-color').disabled =
                !document.getElementById('event-prop-color-enabled').checked;
            eventModalDirty = true;
        };

        function openEventModal(x, y) {
            selectedEventX = x;
            selectedEventY = y;

            document.getElementById('event-coords-info').textContent = `Coords: (${x}, ${y})`;

            // Populate common events dropdown
            const commonSelect = document.getElementById('event-prop-script-id');
            commonSelect.innerHTML = '';
            Object.keys(dbPayload.commonEvents || {}).forEach(k => {
                const opt = document.createElement('option');
                opt.value = k;
                opt.textContent = `${k.padStart(4, '0')}: ${dbPayload.commonEvents[k].name}`;
                commonSelect.appendChild(opt);
            });

            commonSelect.onchange = () => {
                toggleEventLogicType();
            };

            const map = dbPayload.maps[currentMapIndex];
            const eventData = (map.events || []).find(e => e.x === x && e.y === y);

            if (eventData) {
                eventModalSnapshot = JSON.stringify(eventData);
                eventOriginalData = eventData;

                document.getElementById('event-modal-title').textContent = `Event Editor - ID: ${String(eventData.id).padStart(4, '0')}`;
                document.getElementById('event-prop-name').value = eventData.name || `EV${String(eventData.id).padStart(3, '0')}`;
                document.getElementById('event-prop-trigger').value = eventData.trigger || 'interact';
                document.getElementById('event-prop-transparent').checked = !!eventData.transparent;
                document.getElementById('event-prop-priority').value = eventData.priority || 'same';
                document.getElementById('event-prop-spawn').value = eventData.spawn || 'Fixed';

                updateEventGraphicPreview(eventData.sprite);
                setEventColorFields(eventData.minimapColor);
                activeEventLocalScript = eventData.script ? JSON.parse(JSON.stringify(eventData.script)) : [];

                if (eventData.scriptId) {
                    document.getElementById('event-logic-common').checked = true;
                    document.getElementById('event-prop-script-id').value = eventData.scriptId;
                } else {
                    document.getElementById('event-logic-custom').checked = true;
                }
            } else {
                eventModalSnapshot = null;
                eventOriginalData = null;
                let maxId = 0;
                (map.events || []).forEach(e => { maxId = Math.max(maxId, e.id || 0); });
                const nextId = maxId + 1;

                document.getElementById('event-modal-title').textContent = `Event Editor - ID: ${String(nextId).padStart(4, '0')}`;
                document.getElementById('event-prop-name').value = `EV${String(nextId).padStart(3, '0')}`;
                document.getElementById('event-prop-trigger').value = 'interact';
                document.getElementById('event-prop-transparent').checked = false;
                document.getElementById('event-prop-priority').value = 'same';
                document.getElementById('event-prop-spawn').value = 'Fixed';

                updateEventGraphicPreview('');
                setEventColorFields(null);
                activeEventLocalScript = [];
                document.getElementById('event-logic-common').checked = true;
            }

            toggleEventLogicType();
            eventModalDirty = false;
            document.getElementById('event-modal').classList.add('active');
        }

        function updateEventGraphicPreview(spritePath) {
            const img = document.getElementById('event-graphic-img');
            const none = document.getElementById('event-graphic-none');
            window.activeEventSpritePath = spritePath || '';

            if (spritePath) {
                img.src = '/' + spritePath;
                img.style.display = 'block';
                none.style.display = 'none';
            } else {
                img.style.display = 'none';
                none.style.display = 'block';
            }
        }

        function openAssetPickerForEventSprite() {
            openAssetPicker('sprites', (filepath) => {
                filepath = filepath.replace(/\\/g, '/');
                updateEventGraphicPreview(filepath);
                eventModalDirty = true;
            });
        }

        function toggleEventLogicType() {
            const isCommon = document.getElementById('event-logic-common').checked;
            const commonSelect = document.getElementById('event-prop-script-id');

            commonSelect.disabled = !isCommon;

            const container = document.getElementById('event-contents-list');
            if (isCommon) {
                const ceId = commonSelect.value;
                const ce = dbPayload.commonEvents && dbPayload.commonEvents[ceId];
                // Read-only preview of the linked common event's own body, so
                // its palette context is 'common' even though this event is 'map'.
                renderCommandList(container, ce ? ce.commands : [], null, true, 0, 'common');
            } else {
                renderCommandList(container, activeEventLocalScript, () => {
                    eventModalDirty = true;
                    toggleEventLogicType();
                }, false, 0, 'map');
            }
        }

        function closeEventModal(force) {
            if (!force && eventModalDirty && !confirmDiscard('Discard changes to this event?')) return;

            // Only revert on an actual discard: applyEventProperties() mutates
            // eventData (== eventOriginalData) and then calls close(true) while
            // still dirty, so restoring on the force path would undo the Apply.
            if (!force && eventModalDirty && eventOriginalData && eventModalSnapshot) {
                // Restore in place
                const snap = JSON.parse(eventModalSnapshot);
                Object.keys(eventOriginalData).forEach(k => delete eventOriginalData[k]);
                Object.assign(eventOriginalData, snap);
            }

            eventModalSnapshot = null;
            eventOriginalData = null;
            eventModalDirty = false;
            document.getElementById('event-modal').classList.remove('active');
        }

        function applyEventProperties() {
            const map = dbPayload.maps[currentMapIndex];
            if (!map.events) map.events = [];

            let eventData = map.events.find(e => e.x === selectedEventX && e.y === selectedEventY);

            const isNew = !eventData;
            if (isNew) {
                eventData = { x: selectedEventX, y: selectedEventY };
            }

            eventData.name = document.getElementById('event-prop-name').value;
            eventData.trigger = document.getElementById('event-prop-trigger').value;
            eventData.sprite = window.activeEventSpritePath || '';
            eventData.transparent = document.getElementById('event-prop-transparent').checked;
            eventData.priority = document.getElementById('event-prop-priority').value;
            eventData.spawn = document.getElementById('event-prop-spawn').value;
            if (document.getElementById('event-prop-color-enabled').checked) {
                eventData.minimapColor = hexToRgb01(document.getElementById('event-prop-color').value);
            } else {
                delete eventData.minimapColor;
            }

            const isCommon = document.getElementById('event-logic-common').checked;
            if (isCommon) {
                eventData.scriptId = parseInt(document.getElementById('event-prop-script-id').value);
                delete eventData.script;
            } else {
                delete eventData.scriptId;
                eventData.script = activeEventLocalScript;
            }

            if (isNew) {
                let maxId = 0;
                map.events.forEach(e => { maxId = Math.max(maxId, e.id || 0); });
                eventData.id = maxId + 1;
                map.events.push(eventData);
            }

            closeEventModal(true);
            renderGridCells();
            setDirty(true);
        }

        function deleteEventAtCoords() {
            const map = dbPayload.maps[currentMapIndex];
            if (map.events) {
                map.events = map.events.filter(e => !(e.x === selectedEventX && e.y === selectedEventY));
            }
            closeEventModal(true);
            renderGridCells();
            setDirty(true);
        }

        // --- REGISTRY-DRIVEN COMMAND SYSTEM (SPEC A6) ---
        // The command palette (add/edit dialog) and the command-list tree are
        // both generated from data/engine.json -> commands, so any command
        // registered there (with a matching Lua handler) is automatically
        // addable/editable/nestable in every host that lists it in `contexts`.
        // The nine commands the interactive interpreter (engine/interpreter.lua
        // compile()) actually knows how to run — TEXT, CHOICE,
        // CONDITIONAL_BRANCH, RECOVER_PARTY, DESCEND, BATTLE, GIVE_ITEM,
        // CALL_COMMON_EVENT, COMMENT — are stored under the legacy `type` field
        // when added to a map/common host, matching what that interpreter path
        // reads; everything else (and COMMENT in battle_phase flows, matching
        // existing data/flows.json) is stored under `cmd`, which both
        // interpreter.runImmediate and the A7 validator resolve via
        // `cmd.cmd or cmd.type`.
        const INTERACTIVE_COMPILE_IDS = {
            TEXT: 1, CHOICE: 1, CONDITIONAL_BRANCH: 1, RECOVER_PARTY: 1,
            DESCEND: 1, BATTLE: 1, GIVE_ITEM: 1, CALL_COMMON_EVENT: 1, COMMENT: 1
        };
        function cmdFieldName(id, hostCtx) {
            return (hostCtx !== 'battle_phase' && INTERACTIVE_COMPILE_IDS[id]) ? 'type' : 'cmd';
        }
        function cmdId(cmd) {
            return cmd.cmd || cmd.type;
        }
        function cmdRegistry() {
            return (dbPayload.engine && dbPayload.engine.commands) || [];
        }
        function getCmdDef(id) {
            return cmdRegistry().find(c => c.id === id);
        }

        function closeCmdSelectorModal() {
            document.getElementById('cmd-selector-modal').classList.remove('active');
        }

        function openCommandSelector(hostCtx, cb) {
            const container = document.getElementById('cmd-selector-categories');
            container.innerHTML = '';

            const cmds = cmdsForContext(hostCtx);
            const groups = {};

            // Group by category
            cmds.forEach(cmd => {
                const cat = cmd.category || 'Other';
                if (!groups[cat]) groups[cat] = [];
                groups[cat].push(cmd);
            });

            // Sort categories in some order, or just keep as is
            const categoryOrder = ["Message", "Flow Control", "Party", "Battler", "Progression", "Advanced", "Other"];
            const cats = Object.keys(groups).sort((a, b) => {
                let idxA = categoryOrder.indexOf(a);
                let idxB = categoryOrder.indexOf(b);
                if (idxA === -1) idxA = 999;
                if (idxB === -1) idxB = 999;
                if (idxA !== idxB) return idxA - idxB;
                return a.localeCompare(b);
            });

            cats.forEach(cat => {
                const fs = document.createElement('fieldset');
                // Give each fieldset a minimum width to arrange them nicely
                fs.style.cssText = 'padding: 6px; flex: 1 1 200px; min-width: 180px; max-width: 250px; display: flex; flex-direction: column; gap: 4px;';

                const legend = document.createElement('legend');
                legend.textContent = cat;
                fs.appendChild(legend);

                groups[cat].forEach(cmd => {
                    const btn = document.createElement('button');
                    btn.className = 'win98-btn';
                    btn.style.cssText = 'width: 100%; text-align: left; padding: 2px 4px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 10px;';
                    btn.textContent = cmd.label || cmd.id;
                    if (cmd.description) {
                        btn.title = cmd.description;
                    }
                    btn.onclick = () => {
                        closeCmdSelectorModal();
                        cb(cmd.id);
                    };
                    fs.appendChild(btn);
                });

                container.appendChild(fs);
            });

            document.getElementById('cmd-selector-modal').classList.add('active');
        }

        function cmdsForContext(hostCtx) {
            return cmdRegistry().filter(c => (c.contexts || []).some(ctx => ctx === 'any' || ctx === hostCtx) && !c.deprecatedBy);
        }
        function showCommentsPref() {
            return localStorage.getItem('hkt_showComments') !== '0';
        }
        function setShowCommentsPref(v) {
            localStorage.setItem('hkt_showComments', v ? '1' : '0');
        }

        // --- SHARED COMMAND LIST RENDERING ---
        // Used by the Event Editor's custom script list, the Common Event
        // command list in the Database modal, and the Engine window's Flows
        // tab, so all three surfaces look and behave identically (same row
        // format, same add/edit/delete affordances).
        function describeCommand(cmd) {
            const id = cmdId(cmd);
            if (id === 'TEXT') {
                const speakerPrefix = cmd.speaker ? (cmd.speaker + ': ') : '';
                return `Text: "${speakerPrefix}${cmd.text}"`;
            } else if (id === 'RECOVER_PARTY') {
                return 'Recover Party';
            } else if (id === 'TELEPORT') {
                return 'Teleport';
            } else if (id === 'BATTLE') {
                return 'Start Battle';
            } else if (id === 'GIVE_ITEM') {
                return 'Give Random Item';
            } else if (id === 'CALL_COMMON_EVENT') {
                const ce = dbPayload.commonEvents && dbPayload.commonEvents[cmd.commonEventId];
                return `Call Common Event: ${ce ? ce.name : 'ID ' + cmd.commonEventId}`;
            }
            const def = getCmdDef(id);
            if (!def) return `Unknown (${id})`;
            const parts = [];
            (def.params || []).forEach(p => {
                if (p.type === 'commands') return;
                const v = cmd[p.key];
                if (v === undefined || v === null || v === '') return;
                parts.push(`${p.key}=${p.type === 'script' ? '<script>' : v}`);
            });
            return def.label + (parts.length ? ' (' + parts.join(', ') + ')' : '');
        }

        function makeCommentLine(text, indent) {
            const line = document.createElement('div');
            line.style.padding = '2px';
            line.style.paddingLeft = (indent * 14) + 'px';
            line.style.color = '#008000';
            line.style.fontFamily = 'monospace';
            line.style.fontSize = '10px';
            line.textContent = '// ' + text;
            return line;
        }

        function makeMarkerRow(text, indent, onClick) {
            const row = document.createElement('div');
            row.style.padding = '2px';
            row.style.paddingLeft = (indent * 14) + 'px';
            row.style.color = '#808080';
            row.style.display = 'flex';
            row.style.alignItems = 'center';
            row.style.gap = '4px';
            row.textContent = text;
            if (onClick) {
                row.style.cursor = 'pointer';
                row.onclick = onClick;
            }
            return row;
        }

        // Renders `commandsArray` into `container` as an RPG-Maker-style command
        // list. `onChange()` is called after any add/edit/delete so the caller can
        // re-render and mark itself dirty; pass null/readOnly=true for a static preview.
        // `hostCtx` ('map'/'common'/'battle_phase') filters which registry
        // commands the add/edit dialog offers (SPEC S1 contexts) and picks the
        // storage field (SPEC A6 note above cmdFieldName). CHOICE and
        // CONDITIONAL_BRANCH render as nested branches with their own
        // sub-command-lists rendered inline (via recursion); any other
        // registered command with a `commands`-type param (IF, FOR_EACH, ...)
        // gets the same inline nested treatment generically, so new block
        // commands need zero editor code (SPEC S1/A6). You add commands
        // directly inside the nest, like RPG Maker.
        function renderCommandList(container, commandsArray, onChange, readOnly, indent, hostCtx) {
            indent = indent || 0;
            hostCtx = hostCtx || 'map';
            container.innerHTML = '';

            if (indent === 0) {
                const toggleRow = document.createElement('label');
                toggleRow.style.cssText = 'display: flex; align-items: center; gap: 4px; padding: 2px; font-size: 10px; color: var(--win-dark-shadow); cursor: pointer;';
                const chk = document.createElement('input');
                chk.type = 'checkbox';
                chk.checked = showCommentsPref();
                chk.onchange = () => {
                    setShowCommentsPref(chk.checked);
                    renderCommandList(container, commandsArray, onChange, readOnly, indent, hostCtx);
                };
                toggleRow.appendChild(chk);
                toggleRow.appendChild(document.createTextNode('Show comments'));
                container.appendChild(toggleRow);
            }

            if (!commandsArray || commandsArray.length === 0) {
                const line = document.createElement('div');
                line.style.padding = '2px';
                line.style.paddingLeft = (indent * 14) + 'px';
                line.style.color = '#808080';
                line.textContent = readOnly ? '<Empty Command List>' : '@>';
                if (!readOnly) {
                    line.style.cursor = 'pointer';
                    line.onclick = () => openCommandModalForAdd(commandsArray, onChange, hostCtx);
                }
                container.appendChild(line);
                return;
            }

            commandsArray.forEach((cmd, idx) => {
                const id = cmdId(cmd);

                if (id === 'COMMENT') {
                    if (showCommentsPref()) {
                        renderCommentRow(container, commandsArray, idx, cmd, onChange, readOnly, indent, hostCtx);
                    }
                    return;
                }
                if (id === 'CHOICE') {
                    renderChoiceBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent, hostCtx);
                    return;
                }
                if (id === 'CONDITIONAL_BRANCH') {
                    renderConditionalBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent, hostCtx);
                    return;
                }
                const def = getCmdDef(id);
                if (def && (def.params || []).some(p => p.type === 'commands')) {
                    renderGenericBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent, hostCtx);
                    return;
                }

                const line = document.createElement('div');
                line.style.padding = '2px';
                line.style.paddingLeft = (indent * 14) + 'px';
                line.style.display = 'flex';
                line.style.alignItems = 'center';

                const label = document.createElement('span');
                label.style.flex = '1';
                label.style.overflow = 'hidden';
                label.style.textOverflow = 'ellipsis';
                label.style.whiteSpace = 'nowrap';
                label.textContent = '@>' + describeCommand(cmd);
                line.appendChild(label);

                if (!readOnly) {
                    line.style.cursor = 'pointer';
                    line.onmouseover = () => { line.style.background = '#000080'; line.style.color = 'white'; };
                    line.onmouseout = () => { line.style.background = ''; line.style.color = ''; };
                    line.onclick = () => openCommandModalForEdit(commandsArray, idx, onChange, hostCtx);

                    const editBtn = document.createElement('button');
                    editBtn.className = 'win-btn-small outset-bevel';
                    editBtn.style.fontSize = '8px';
                    editBtn.style.padding = '0px 3px';
                    editBtn.textContent = '✏️';
                    editBtn.onclick = (e) => { e.stopPropagation(); openCommandModalForEdit(commandsArray, idx, onChange, hostCtx); };

                    const delBtn = document.createElement('button');
                    delBtn.className = 'win-btn-small outset-bevel';
                    delBtn.style.fontSize = '8px';
                    delBtn.style.padding = '0px 3px';
                    delBtn.style.color = 'red';
                    delBtn.textContent = '×';
                    delBtn.onclick = (e) => {
                        e.stopPropagation();
                        commandsArray.splice(idx, 1);
                        if (onChange) onChange();
                    };

                    const controls = document.createElement('div');
                    controls.style.display = 'flex';
                    controls.style.gap = '2px';
                    controls.appendChild(editBtn);
                    controls.appendChild(delBtn);
                    line.appendChild(controls);
                } else {
                    line.style.color = '#808080';
                }
                container.appendChild(line);

                if (cmd.comment && showCommentsPref()) {
                    container.appendChild(makeCommentLine(cmd.comment, indent + 1));
                }
            });

            if (!readOnly) {
                const trailingLine = document.createElement('div');
                trailingLine.style.padding = '2px';
                trailingLine.style.paddingLeft = (indent * 14) + 'px';
                trailingLine.style.color = '#808080';
                trailingLine.style.cursor = 'pointer';
                trailingLine.textContent = '@>';
                trailingLine.onclick = () => openCommandModalForAdd(commandsArray, onChange, hostCtx);
                container.appendChild(trailingLine);
            }
        }

        // A standalone COMMENT row (SPEC S3): documentation only, rendered in
        // green, hidden entirely (not just dimmed) when "Show comments" is off.
        function renderCommentRow(container, commandsArray, idx, cmd, onChange, readOnly, indent, hostCtx) {
            const line = document.createElement('div');
            line.style.padding = '2px';
            line.style.paddingLeft = (indent * 14) + 'px';
            line.style.display = 'flex';
            line.style.alignItems = 'center';
            line.style.color = '#008000';
            line.style.fontFamily = 'monospace';
            line.style.fontSize = '10px';

            const label = document.createElement('span');
            label.style.flex = '1';
            label.style.overflow = 'hidden';
            label.style.textOverflow = 'ellipsis';
            label.style.whiteSpace = 'nowrap';
            label.textContent = '// ' + (cmd.text || '');
            line.appendChild(label);

            if (!readOnly) {
                line.style.cursor = 'pointer';
                line.onclick = () => openCommandModalForEdit(commandsArray, idx, onChange, hostCtx);

                const delBtn = document.createElement('button');
                delBtn.className = 'win-btn-small outset-bevel';
                delBtn.style.fontSize = '8px';
                delBtn.style.padding = '0px 3px';
                delBtn.style.color = 'red';
                delBtn.textContent = '×';
                delBtn.onclick = (e) => {
                    e.stopPropagation();
                    commandsArray.splice(idx, 1);
                    if (onChange) onChange();
                };
                line.appendChild(delBtn);
            }
            container.appendChild(line);
        }

        // Generic nested-block renderer (SPEC A6): any registered command with
        // one or more `commands`-type params (IF's then/else, FOR_EACH's do, and
        // any future block command) renders its scalar params in the header and
        // each command-list param as its own inline sub-tree, with zero
        // command-specific editor code required.
        function renderGenericBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent, hostCtx) {
            const id = cmdId(cmd);
            const def = getCmdDef(id);

            const header = document.createElement('div');
            header.style.padding = '2px';
            header.style.paddingLeft = (indent * 14) + 'px';
            header.style.display = 'flex';
            header.style.alignItems = 'center';
            header.style.fontWeight = 'bold';
            const headerLabel = document.createElement('span');
            headerLabel.style.flex = '1';
            headerLabel.style.overflow = 'hidden';
            headerLabel.style.textOverflow = 'ellipsis';
            headerLabel.style.whiteSpace = 'nowrap';
            headerLabel.textContent = '@>' + describeCommand(cmd);
            header.appendChild(headerLabel);
            if (!readOnly) {
                const editBtn = document.createElement('button');
                editBtn.className = 'win-btn-small outset-bevel';
                editBtn.style.fontSize = '8px';
                editBtn.style.padding = '0px 3px';
                editBtn.textContent = '✏️';
                editBtn.onclick = (e) => { e.stopPropagation(); openCommandModalForEdit(commandsArray, idx, onChange, hostCtx); };
                const delBtn = document.createElement('button');
                delBtn.className = 'win-btn-small outset-bevel';
                delBtn.style.fontSize = '8px';
                delBtn.style.padding = '0px 3px';
                delBtn.style.color = 'red';
                delBtn.textContent = '×';
                delBtn.onclick = (e) => {
                    e.stopPropagation();
                    commandsArray.splice(idx, 1);
                    if (onChange) onChange();
                };
                header.appendChild(editBtn);
                header.appendChild(delBtn);
            } else {
                header.style.color = '#808080';
            }
            container.appendChild(header);

            if (cmd.comment && showCommentsPref()) {
                container.appendChild(makeCommentLine(cmd.comment, indent + 1));
            }

            (def.params || []).forEach(p => {
                if (p.type !== 'commands') return;
                cmd[p.key] = cmd[p.key] || [];
                const marker = makeMarkerRow(`: ${p.key}`, indent + 1);
                marker.style.color = '#000080';
                marker.style.fontWeight = 'bold';
                container.appendChild(marker);
                const subContainer = document.createElement('div');
                container.appendChild(subContainer);
                renderCommandList(subContainer, cmd[p.key], onChange, readOnly, indent + 2, hostCtx);
            });

            container.appendChild(makeMarkerRow(`: End ${def.label || id}`, indent));
        }

        function renderChoiceBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent, hostCtx) {
            cmd.options = cmd.options || [];

            const header = document.createElement('div');
            header.style.padding = '2px';
            header.style.paddingLeft = (indent * 14) + 'px';
            header.style.display = 'flex';
            header.style.alignItems = 'center';
            header.style.fontWeight = 'bold';
            const headerLabel = document.createElement('span');
            headerLabel.style.flex = '1';
            headerLabel.textContent = '@>Show Choice';
            header.appendChild(headerLabel);
            if (!readOnly) {
                const delBtn = document.createElement('button');
                delBtn.className = 'win-btn-small outset-bevel';
                delBtn.style.fontSize = '8px';
                delBtn.style.padding = '0px 3px';
                delBtn.style.color = 'red';
                delBtn.textContent = '×';
                delBtn.onclick = (e) => {
                    e.stopPropagation();
                    commandsArray.splice(idx, 1);
                    if (onChange) onChange();
                };
                header.appendChild(delBtn);
            }
            container.appendChild(header);

            if (cmd.comment && showCommentsPref()) {
                container.appendChild(makeCommentLine(cmd.comment, indent + 1));
            }

            cmd.options.forEach((opt, optIdx) => {
                opt.commands = opt.commands || [];
                const marker = makeMarkerRow(`: ${opt.label || '(no label)'}${opt.setFlag ? '  [sets flag: ' + opt.setFlag + ']' : ''}`, indent + 1);
                marker.style.color = '#000080';
                marker.style.fontWeight = 'bold';
                if (!readOnly) {
                    const renameBtn = document.createElement('button');
                    renameBtn.className = 'win-btn-small outset-bevel';
                    renameBtn.style.fontSize = '8px';
                    renameBtn.style.padding = '0px 3px';
                    renameBtn.textContent = '✏️';
                    renameBtn.onclick = (e) => {
                        e.stopPropagation();
                        const newLabel = prompt('Option label:', opt.label || '');
                        if (newLabel === null) return;
                        opt.label = newLabel;
                        const newFlag = prompt('Set flag when chosen (blank for none):', opt.setFlag || '');
                        if (newFlag === null) return;
                        if (newFlag.trim()) { opt.setFlag = newFlag.trim(); } else { delete opt.setFlag; }
                        if (onChange) onChange();
                    };
                    const delOptBtn = document.createElement('button');
                    delOptBtn.className = 'win-btn-small outset-bevel';
                    delOptBtn.style.fontSize = '8px';
                    delOptBtn.style.padding = '0px 3px';
                    delOptBtn.style.color = 'red';
                    delOptBtn.textContent = '×';
                    delOptBtn.onclick = (e) => {
                        e.stopPropagation();
                        cmd.options.splice(optIdx, 1);
                        if (onChange) onChange();
                    };
                    marker.appendChild(renameBtn);
                    marker.appendChild(delOptBtn);
                }
                container.appendChild(marker);

                const optContainer = document.createElement('div');
                container.appendChild(optContainer);
                renderCommandList(optContainer, opt.commands, onChange, readOnly, indent + 2, hostCtx);
            });

            if (!readOnly) {
                container.appendChild(makeMarkerRow('+ Add Option', indent + 1, () => {
                    cmd.options.push({ label: 'New Option', commands: [] });
                    if (onChange) onChange();
                }));
            }

            container.appendChild(makeMarkerRow(': End Choice', indent));
        }

        function renderConditionalBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent, hostCtx) {
            cmd.commands = cmd.commands || [];

            const header = document.createElement('div');
            header.style.padding = '2px';
            header.style.paddingLeft = (indent * 14) + 'px';
            header.style.display = 'flex';
            header.style.alignItems = 'center';
            header.style.fontWeight = 'bold';
            const headerLabel = document.createElement('span');
            headerLabel.style.flex = '1';
            headerLabel.style.overflow = 'hidden';
            headerLabel.style.textOverflow = 'ellipsis';
            headerLabel.style.whiteSpace = 'nowrap';
            headerLabel.textContent = `@>If [${cmd.condition || '(no condition)'}]`;
            header.appendChild(headerLabel);
            if (!readOnly) {
                const editBtn = document.createElement('button');
                editBtn.className = 'win-btn-small outset-bevel';
                editBtn.style.fontSize = '8px';
                editBtn.style.padding = '0px 3px';
                editBtn.textContent = '✏️';
                editBtn.onclick = (e) => {
                    e.stopPropagation();
                    const newCond = prompt('Condition (e.g. flag:metAlicia or hasItem:silver_blade):', cmd.condition || '');
                    if (newCond === null) return;
                    cmd.condition = newCond;
                    if (onChange) onChange();
                };
                const delBtn = document.createElement('button');
                delBtn.className = 'win-btn-small outset-bevel';
                delBtn.style.fontSize = '8px';
                delBtn.style.padding = '0px 3px';
                delBtn.style.color = 'red';
                delBtn.textContent = '×';
                delBtn.onclick = (e) => {
                    e.stopPropagation();
                    commandsArray.splice(idx, 1);
                    if (onChange) onChange();
                };
                header.appendChild(editBtn);
                header.appendChild(delBtn);
            }
            container.appendChild(header);

            if (cmd.comment && showCommentsPref()) {
                container.appendChild(makeCommentLine(cmd.comment, indent + 1));
            }

            const thenContainer = document.createElement('div');
            container.appendChild(thenContainer);
            renderCommandList(thenContainer, cmd.commands, onChange, readOnly, indent + 1, hostCtx);

            if (cmd.elseCommands) {
                const elseMarker = makeMarkerRow(': Else', indent);
                if (!readOnly) {
                    const removeElseBtn = document.createElement('button');
                    removeElseBtn.className = 'win-btn-small outset-bevel';
                    removeElseBtn.style.fontSize = '8px';
                    removeElseBtn.style.padding = '0px 3px';
                    removeElseBtn.style.color = 'red';
                    removeElseBtn.textContent = 'Remove';
                    removeElseBtn.onclick = (e) => {
                        e.stopPropagation();
                        delete cmd.elseCommands;
                        if (onChange) onChange();
                    };
                    elseMarker.appendChild(removeElseBtn);
                }
                container.appendChild(elseMarker);

                const elseContainer = document.createElement('div');
                container.appendChild(elseContainer);
                renderCommandList(elseContainer, cmd.elseCommands, onChange, readOnly, indent + 1, hostCtx);
            } else if (!readOnly) {
                container.appendChild(makeMarkerRow('+ Add Else Branch', indent, () => {
                    cmd.elseCommands = [];
                    if (onChange) onChange();
                }));
            }

            container.appendChild(makeMarkerRow(': End Branch', indent));
        }

        function openCommandModalForAdd(commandsArray, onChange, hostCtx) {
            populateCmdCommonEventsDropdown();
            openCommandSelector(hostCtx, (cmdId) => {
                openAddCommandDialog((cmd) => {
                    commandsArray.push(cmd);
                    if (onChange) onChange();
                }, hostCtx, cmdId);
            });
        }

        function openCommandModalForEdit(commandsArray, idx, onChange, hostCtx) {
            populateCmdCommonEventsDropdown();
            openEditCommandDialog(commandsArray[idx], (updatedCmd) => {
                commandsArray[idx] = updatedCmd;
                if (onChange) onChange();
            }, hostCtx);
        }

        // --- COMMAND EDITOR MODAL ---
        // Registry-driven (SPEC A6): #cmd-select-type is populated from
        // data/engine.json -> commands, filtered to activeCmdHostCtx (S1
        // contexts), and #cmd-fields-dynamic is rebuilt per param schema by
        // renderParamField. CHOICE/CONDITIONAL_BRANCH/any command with a
        // `commands`-type param show the nested-edit hint instead of a field —
        // those lists are edited inline in the tree above (see
        // renderChoiceBlock/renderConditionalBlock/renderGenericBlock).
        let activeCmdCallback = null;
        let activeCmdOriginal = null;
        let activeCmdHostCtx = 'map';
        let cmdDialogDirty = false;
        let cmdModalSnapshot = null;

        function populateCmdCommonEventsDropdown() {
            const select = document.getElementById('cmd-select-common-event');
            if (!select) return;
            select.innerHTML = '';

            if (dbPayload.commonEvents) {
                Object.keys(dbPayload.commonEvents).forEach(id => {
                    const ce = dbPayload.commonEvents[id];
                    const opt = document.createElement('option');
                    opt.value = id;
                    opt.textContent = `${id.padStart(4, '0')}: ${ce.name}`;
                    select.appendChild(opt);
                });
            }
        }

        function populateCmdTypeSelect(hostCtx, ensureId) {
            const select = document.getElementById('cmd-select-type');
            select.innerHTML = '';
            const defs = cmdsForContext(hostCtx);
            defs.forEach(def => {
                const opt = document.createElement('option');
                opt.value = def.id;
                opt.textContent = def.label || def.id;
                opt.title = def.description || '';
                select.appendChild(opt);
            });
            // Defensive: if editing a command whose id somehow isn't offered in
            // this host's palette (stale/foreign data), still let it be edited.
            if (ensureId && !defs.some(d => d.id === ensureId)) {
                const def = getCmdDef(ensureId);
                const opt = document.createElement('option');
                opt.value = ensureId;
                opt.textContent = (def && def.label) || ensureId;
                select.appendChild(opt);
            }
        }

        function openAddCommandDialog(callback, hostCtx, ensureId) {
            activeCmdCallback = callback;
            activeCmdOriginal = null;
            cmdModalSnapshot = null;
            activeCmdHostCtx = hostCtx || 'map';
            populateCmdTypeSelect(activeCmdHostCtx, ensureId);
            const select = document.getElementById('cmd-select-type');

            if (ensureId) {
                select.value = ensureId;
                select.disabled = true; // Lock it for adding
            } else {
                if ([...select.options].some(o => o.value === 'TEXT')) { select.value = 'TEXT'; }
                else if (select.options.length) { select.selectedIndex = 0; }
                select.disabled = false;
            }

            document.getElementById('cmd-input-comment').value = '';
            toggleCmdTypeFields();
            cmdDialogDirty = false;
            document.getElementById('cmd-modal').classList.add('active');
        }

        function openEditCommandDialog(cmd, callback, hostCtx) {
            activeCmdCallback = callback;
            activeCmdOriginal = cmd;
            cmdModalSnapshot = JSON.stringify(cmd);
            activeCmdHostCtx = hostCtx || 'map';
            const id = cmdId(cmd);
            populateCmdTypeSelect(activeCmdHostCtx, id);
            const select = document.getElementById('cmd-select-type');
            select.value = id;
            select.disabled = true; // Type shown read-only in edit mode
            document.getElementById('cmd-input-comment').value = cmd.comment || '';
            toggleCmdTypeFields(cmd);
            cmdDialogDirty = false;
            document.getElementById('cmd-modal').classList.add('active');
        }

        // Builds one labeled field for a registry param. `commonEventId` gets
        // the friendlier common-event dropdown; `term`/`state`/`item`/`skill`
        // use pickers (term via B4's window.cmdParamWidgets.term); `formula`/
        // `script` get an (i) popover into formulaHelp/scriptingHelp (S5/S6).
        function renderParamField(container, cmdTypeId, paramDef, currentValue) {
            const wrap = document.createElement('div');
            wrap.className = 'field-row-stacked';
            const labelRow = document.createElement('div');
            labelRow.style.cssText = 'display: flex; align-items: center; gap: 4px;';
            const label = document.createElement('label');
            label.textContent = paramDef.key + ':';
            labelRow.appendChild(label);
            if (paramDef.type === 'formula' || paramDef.type === 'script') {
                const infoBtn = document.createElement('button');
                infoBtn.type = 'button';
                infoBtn.className = 'win-btn-small outset-bevel';
                infoBtn.style.cssText = 'font-size: 8px; padding: 0 3px;';
                infoBtn.textContent = 'ⓘ';
                infoBtn.onclick = (e) => { e.preventDefault(); e.stopPropagation(); showParamHelpPopover(infoBtn, paramDef.type); };
                labelRow.appendChild(infoBtn);
            }
            wrap.appendChild(labelRow);

            let input;
            if (paramDef.key === 'commonEventId') {
                input = document.createElement('select');
                input.className = 'win98-select';
                if (dbPayload.commonEvents) {
                    Object.keys(dbPayload.commonEvents).forEach(id => {
                        const opt = document.createElement('option');
                        opt.value = id;
                        opt.textContent = `${id.padStart(4, '0')}: ${dbPayload.commonEvents[id].name || ''}`;
                        input.appendChild(opt);
                    });
                }
                if (currentValue !== undefined) input.value = String(currentValue);
            } else if (paramDef.type === 'script') {
                input = document.createElement('textarea');
                input.className = 'form-control inset-bevel';
                input.style.fontFamily = 'monospace';
                input.rows = 4;
                input.value = currentValue || '';
            } else if (paramDef.type === 'text' && cmdTypeId === 'TEXT' && paramDef.key === 'text') {
                input = document.createElement('textarea');
                input.className = 'form-control inset-bevel';
                input.rows = 3;
                input.value = currentValue || '';
            } else if (paramDef.type === 'number') {
                input = document.createElement('input');
                input.type = 'number';
                input.className = 'win98-input';
                input.value = currentValue !== undefined && currentValue !== null ? currentValue : '';
            } else if (paramDef.type === 'flag') {
                input = document.createElement('input');
                input.type = 'checkbox';
                input.checked = !!currentValue;
            } else if (paramDef.type === 'scope') {
                input = makeSelect(['enemies', 'living_enemies', 'allies', 'living_allies', 'party', 'slot_allies'], currentValue || 'enemies', () => {}, null);
                input.title = 'Which battlers FOR_EACH iterates. slot_allies = living battlers in battle slots 1-4.';
            } else if (paramDef.type === 'battlerRef') {
                input = document.createElement('input');
                input.className = 'win98-input';
                input.setAttribute('list', 'cmd-battlerref-suggestions');
                input.value = currentValue || '';
                input.placeholder = 'e.g. ally (a FOR_EACH "as" name) or target';
                input.title = 'A FOR_EACH loop variable (its "as" name), one of a/b/target/enemy/ally, or "summoner".';
            } else if (paramDef.type === 'state') {
                const opts = Object.keys(dbPayload.states || {}).map(id => ({ value: id, label: (dbPayload.states[id].name || id) }));
                input = makeSelect(opts, currentValue, () => {}, null);
            } else if (paramDef.type === 'item') {
                const opts = [{ value: "random", label: "Random Map Treasure" }].concat((dbPayload.items || []).map(it => ({ value: String(it.id), label: it.name })));
                input = makeSelect(opts, currentValue, () => {}, null);
            } else if (paramDef.type === 'skill') {
                const opts = Object.keys(dbPayload.skills || {}).map(id => ({ value: id, label: (dbPayload.skills[id].name || id) }));
                input = makeSelect(opts, currentValue, () => {}, null);
            } else if (paramDef.type === 'term' && window.cmdParamWidgets && window.cmdParamWidgets.term) {
                input = window.cmdParamWidgets.term(currentValue, () => {});
            } else {
                input = document.createElement('input');
                input.type = 'text';
                input.className = 'win98-input';
                input.value = currentValue !== undefined && currentValue !== null ? currentValue : '';
                if (paramDef.key === 'condition') {
                    // CONDITIONAL_BRANCH's string condition — the most
                    // open-ended field in the dialog (feedback #1).
                    input.placeholder = 'e.g. flag:metAlicia or hasItem:3';
                    input.title = 'flag:<name> checks a session flag; hasItem:<itemId> checks item presence. IF also accepts a formula here.';
                } else if (paramDef.key === 'flag') {
                    input.placeholder = 'flag name, e.g. metAlicia';
                    input.title = 'The same session flags flag:<name> conditions read.';
                } else if (paramDef.key === 'as') {
                    input.placeholder = 'loop variable name, e.g. ally';
                    input.title = 'Nested commands and formulas can reference each iterated battler by this name.';
                } else if (paramDef.key === 'trait') {
                    input.placeholder = 'e.g. POST_BATTLE_HEAL';
                    input.title = 'A trait code from the Engine window’s Trait Codes registry.';
                } else if (paramDef.type === 'formula') {
                    input.placeholder = 'e.g. random(1, 6) + session.floor';
                    input.title = 'A formula over the sandboxed context — see the ⓘ button for every token.';
                }
            }
            input.id = 'cmd-dyn-' + paramDef.key;
            wrap.appendChild(input);
            container.appendChild(wrap);
        }

        // Small floating popover listing engine.json -> formulaHelp/scriptingHelp
        // (S5/S6), positioned under the (i) button that opened it.
        function showParamHelpPopover(anchorEl, paramType) {
            const pop = document.getElementById('cmd-help-popover');
            if (pop.style.display === 'block' && pop._anchor === anchorEl) {
                pop.style.display = 'none';
                pop._anchor = null;
                return;
            }
            const entries = (paramType === 'script')
                ? ((dbPayload.engine && dbPayload.engine.scriptingHelp) || [])
                : ((dbPayload.engine && dbPayload.engine.formulaHelp) || []);
            pop.innerHTML = '';
            const title = document.createElement('div');
            title.style.cssText = 'font-weight: bold; margin-bottom: 4px;';
            title.textContent = paramType === 'script' ? 'Script Call context' : 'Formula context';
            pop.appendChild(title);
            entries.forEach(e => {
                const row = document.createElement('div');
                row.style.marginBottom = '3px';
                const tok = document.createElement('span');
                tok.style.cssText = 'font-family: monospace; color: #000080; font-weight: bold;';
                tok.textContent = e.token;
                row.appendChild(tok);
                row.appendChild(document.createTextNode(' — ' + e.description));
                pop.appendChild(row);
            });
            const rect = anchorEl.getBoundingClientRect();
            pop.style.left = Math.max(4, rect.left) + 'px';
            pop.style.top = (rect.bottom + 2) + 'px';
            pop.style.display = 'block';
            pop._anchor = anchorEl;
        }
        document.addEventListener('click', (e) => {
            const pop = document.getElementById('cmd-help-popover');
            if (pop && pop.style.display === 'block' && !pop.contains(e.target) && e.target !== pop._anchor) {
                pop.style.display = 'none';
                pop._anchor = null;
            }
        });

        function toggleCmdTypeFields(existingCmd) {
            const type = document.getElementById('cmd-select-type').value;
            const def = getCmdDef(type);
            document.getElementById('cmd-type-description').textContent = def ? (def.description || '') : '';

            const dynContainer = document.getElementById('cmd-fields-dynamic');
            dynContainer.innerHTML = '';
            (def && def.params || []).forEach(p => {
                if (p.type === 'commands') return;
                const currentValue = existingCmd ? existingCmd[p.key] : undefined;
                renderParamField(dynContainer, type, p, currentValue);
            });

            const hasNested = def && (def.params || []).some(p => p.type === 'commands');
            document.getElementById('cmd-fields-nested-hint').style.display = hasNested ? 'block' : 'none';
        }

        function closeCmdDialog(force) {
            if (!force && cmdDialogDirty && !confirmDiscard('Discard this command?')) return;

            // Revert only on discard, never on the force path applyCmdDialog uses.
            if (!force && cmdDialogDirty && activeCmdOriginal && cmdModalSnapshot) {
                const snap = JSON.parse(cmdModalSnapshot);
                Object.keys(activeCmdOriginal).forEach(k => delete activeCmdOriginal[k]);
                Object.assign(activeCmdOriginal, snap);
            }

            cmdModalSnapshot = null;
            cmdDialogDirty = false;
            document.getElementById('cmd-modal').classList.remove('active');
        }

        function applyCmdDialog() {
            const type = document.getElementById('cmd-select-type').value;
            const def = getCmdDef(type);
            const wasSameType = activeCmdOriginal && cmdId(activeCmdOriginal) === type;

            let cmd = {};
            cmd[cmdFieldName(type, activeCmdHostCtx)] = type;

            (def && def.params || []).forEach(p => {
                if (p.type === 'commands') {
                    // Preserve existing nested command lists when just
                    // re-confirming the same type; start empty otherwise.
                    cmd[p.key] = (wasSameType && activeCmdOriginal[p.key]) ? activeCmdOriginal[p.key] : [];
                    return;
                }
                const el = document.getElementById('cmd-dyn-' + p.key);
                if (!el) return;
                if (p.type === 'flag') {
                    cmd[p.key] = el.checked;
                } else if (p.type === 'number') {
                    cmd[p.key] = el.value === '' ? undefined : parseFloat(el.value);
                } else if (p.key === 'commonEventId') {
                    cmd[p.key] = parseInt(el.value);
                } else {
                    cmd[p.key] = el.value;
                }
            });

            const comment = document.getElementById('cmd-input-comment').value.trim();
            if (comment) { cmd.comment = comment; }

            closeCmdDialog(true);
            if (activeCmdCallback) activeCmdCallback(cmd);
        }

        function initEventModalTemplates() {}
        wireModalDirtyTracking('map-properties-modal', () => { mapPropsDirty = true; });
        wireModalDirtyTracking('event-modal', () => { eventModalDirty = true; });
        wireModalDirtyTracking('cmd-modal', () => { cmdDialogDirty = true; });
        wireModalDirtyTracking('damage-popup-modal', () => { setDirty(true); });

        fetchDatabase();
