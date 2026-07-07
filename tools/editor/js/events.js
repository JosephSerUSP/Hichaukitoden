        // --- EVENT CONTROLLERS ---
        let activeEventLocalScript = null;

        let eventModalDirty = false;

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
                document.getElementById('event-modal-title').textContent = `Event Editor - ID: ${String(eventData.id).padStart(4, '0')}`;
                document.getElementById('event-prop-name').value = eventData.name || `EV${String(eventData.id).padStart(3, '0')}`;
                document.getElementById('event-prop-trigger').value = eventData.trigger || 'interact';
                document.getElementById('event-prop-transparent').checked = !!eventData.transparent;
                document.getElementById('event-prop-priority').value = eventData.priority || 'same';
                document.getElementById('event-prop-spawn').value = eventData.spawn || 'Fixed';

                updateEventGraphicPreview(eventData.sprite);
                setEventColorFields(eventData.minimapColor);
                activeEventLocalScript = eventData.script ? [...eventData.script] : [];

                if (eventData.scriptId) {
                    document.getElementById('event-logic-common').checked = true;
                    document.getElementById('event-prop-script-id').value = eventData.scriptId;
                } else {
                    document.getElementById('event-logic-custom').checked = true;
                }
            } else {
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
                renderCommandList(container, ce ? ce.commands : [], null, true);
            } else {
                renderCommandList(container, activeEventLocalScript, () => {
                    eventModalDirty = true;
                    toggleEventLogicType();
                }, false);
            }
        }

        function closeEventModal(force) {
            if (!force && eventModalDirty && !confirmDiscard('Discard changes to this event?')) return;
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

        // --- SHARED COMMAND LIST RENDERING ---
        // Used by the Event Editor's custom script list AND the Common Event
        // command list in the Database modal, so both surfaces look and behave
        // identically (same row format, same add/edit/delete affordances).
        function describeCommand(cmd) {
            if (cmd.type === 'TEXT') {
                const speakerPrefix = cmd.speaker ? (cmd.speaker + ': ') : '';
                return `Text: "${speakerPrefix}${cmd.text}"`;
            } else if (cmd.type === 'RECOVER_PARTY') {
                return 'Recover Party';
            } else if (cmd.type === 'DESCEND') {
                return 'Descend Floor';
            } else if (cmd.type === 'BATTLE') {
                return 'Start Battle';
            } else if (cmd.type === 'GIVE_ITEM') {
                return 'Give Random Item';
            } else if (cmd.type === 'CALL_COMMON_EVENT') {
                const ce = dbPayload.commonEvents && dbPayload.commonEvents[cmd.commonEventId];
                return `Call Common Event: ${ce ? ce.name : 'ID ' + cmd.commonEventId}`;
            }
            return `Unknown (${cmd.type})`;
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
        // CHOICE and CONDITIONAL_BRANCH render as nested branches with their own
        // sub-command-lists rendered inline (via recursion), rather than opening a
        // separate modal — you add commands directly inside the nest, like RPG Maker.
        function renderCommandList(container, commandsArray, onChange, readOnly, indent) {
            indent = indent || 0;
            container.innerHTML = '';

            if (!commandsArray || commandsArray.length === 0) {
                const line = document.createElement('div');
                line.style.padding = '2px';
                line.style.paddingLeft = (indent * 14) + 'px';
                line.style.color = '#808080';
                line.textContent = readOnly ? '<Empty Command List>' : '@>';
                if (!readOnly) {
                    line.style.cursor = 'pointer';
                    line.onclick = () => openCommandModalForAdd(commandsArray, onChange);
                }
                container.appendChild(line);
                return;
            }

            commandsArray.forEach((cmd, idx) => {
                if (cmd.type === 'CHOICE') {
                    renderChoiceBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent);
                    return;
                }
                if (cmd.type === 'CONDITIONAL_BRANCH') {
                    renderConditionalBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent);
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
                    line.onclick = () => openCommandModalForEdit(commandsArray, idx, onChange);

                    const editBtn = document.createElement('button');
                    editBtn.className = 'win-btn-small outset-bevel';
                    editBtn.style.fontSize = '8px';
                    editBtn.style.padding = '0px 3px';
                    editBtn.textContent = '✏️';
                    editBtn.onclick = (e) => { e.stopPropagation(); openCommandModalForEdit(commandsArray, idx, onChange); };

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
            });

            if (!readOnly) {
                const trailingLine = document.createElement('div');
                trailingLine.style.padding = '2px';
                trailingLine.style.paddingLeft = (indent * 14) + 'px';
                trailingLine.style.color = '#808080';
                trailingLine.style.cursor = 'pointer';
                trailingLine.textContent = '@>';
                trailingLine.onclick = () => openCommandModalForAdd(commandsArray, onChange);
                container.appendChild(trailingLine);
            }
        }

        function renderChoiceBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent) {
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
                renderCommandList(optContainer, opt.commands, onChange, readOnly, indent + 2);
            });

            if (!readOnly) {
                container.appendChild(makeMarkerRow('+ Add Option', indent + 1, () => {
                    cmd.options.push({ label: 'New Option', commands: [] });
                    if (onChange) onChange();
                }));
            }

            container.appendChild(makeMarkerRow(': End Choice', indent));
        }

        function renderConditionalBlock(container, commandsArray, idx, cmd, onChange, readOnly, indent) {
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

            const thenContainer = document.createElement('div');
            container.appendChild(thenContainer);
            renderCommandList(thenContainer, cmd.commands, onChange, readOnly, indent + 1);

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
                renderCommandList(elseContainer, cmd.elseCommands, onChange, readOnly, indent + 1);
            } else if (!readOnly) {
                container.appendChild(makeMarkerRow('+ Add Else Branch', indent, () => {
                    cmd.elseCommands = [];
                    if (onChange) onChange();
                }));
            }

            container.appendChild(makeMarkerRow(': End Branch', indent));
        }

        function openCommandModalForAdd(commandsArray, onChange) {
            populateCmdCommonEventsDropdown();
            openAddCommandDialog((cmd) => {
                commandsArray.push(cmd);
                if (onChange) onChange();
            });
        }

        function openCommandModalForEdit(commandsArray, idx, onChange) {
            populateCmdCommonEventsDropdown();
            openEditCommandDialog(commandsArray[idx], (updatedCmd) => {
                commandsArray[idx] = updatedCmd;
                if (onChange) onChange();
            });
        }

        // --- COMMAND EDITOR MODAL (single command; CHOICE/CONDITIONAL_BRANCH ---
        // create an empty shell here, then are edited inline in the tree above)
        let activeCmdCallback = null;
        let activeCmdOriginal = null;
        let cmdDialogDirty = false;

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

        function openAddCommandDialog(callback) {
            activeCmdCallback = callback;
            activeCmdOriginal = null;
            document.getElementById('cmd-select-type').value = 'TEXT';
            document.getElementById('cmd-input-text').value = 'Hello!';
            document.getElementById('cmd-input-speaker').value = '';
            document.getElementById('cmd-input-condition').value = '';
            toggleCmdTypeFields();
            cmdDialogDirty = false;
            document.getElementById('cmd-modal').classList.add('active');
        }

        function openEditCommandDialog(cmd, callback) {
            activeCmdCallback = callback;
            activeCmdOriginal = cmd;
            document.getElementById('cmd-select-type').value = cmd.type;
            if (cmd.type === 'TEXT') {
                document.getElementById('cmd-input-text').value = cmd.text || '';
                document.getElementById('cmd-input-speaker').value = cmd.speaker || '';
            } else if (cmd.type === 'CALL_COMMON_EVENT') {
                document.getElementById('cmd-select-common-event').value = cmd.commonEventId;
            } else if (cmd.type === 'CONDITIONAL_BRANCH') {
                document.getElementById('cmd-input-condition').value = cmd.condition || '';
            }
            toggleCmdTypeFields();
            cmdDialogDirty = false;
            document.getElementById('cmd-modal').classList.add('active');
        }

        function toggleCmdTypeFields() {
            const type = document.getElementById('cmd-select-type').value;
            document.getElementById('cmd-fields-text').style.display = type === 'TEXT' ? 'flex' : 'none';
            document.getElementById('cmd-fields-common-event').style.display = type === 'CALL_COMMON_EVENT' ? 'flex' : 'none';
            document.getElementById('cmd-fields-conditional').style.display = type === 'CONDITIONAL_BRANCH' ? 'flex' : 'none';
            document.getElementById('cmd-fields-nested-hint').style.display = (type === 'CHOICE' || type === 'CONDITIONAL_BRANCH') ? 'block' : 'none';
        }

        function closeCmdDialog(force) {
            if (!force && cmdDialogDirty && !confirmDiscard('Discard this command?')) return;
            document.getElementById('cmd-modal').classList.remove('active');
        }

        function applyCmdDialog() {
            const type = document.getElementById('cmd-select-type').value;
            const wasSameType = activeCmdOriginal && activeCmdOriginal.type === type;
            let cmd = { type: type };
            if (type === 'TEXT') {
                cmd.text = document.getElementById('cmd-input-text').value;
                cmd.speaker = document.getElementById('cmd-input-speaker').value;
            } else if (type === 'CALL_COMMON_EVENT') {
                cmd.commonEventId = parseInt(document.getElementById('cmd-select-common-event').value);
            } else if (type === 'CHOICE') {
                // Preserve existing nested options when just re-confirming this dialog.
                cmd.options = wasSameType ? activeCmdOriginal.options : [];
            } else if (type === 'CONDITIONAL_BRANCH') {
                cmd.condition = document.getElementById('cmd-input-condition').value;
                cmd.commands = wasSameType ? activeCmdOriginal.commands : [];
                if (wasSameType && activeCmdOriginal.elseCommands) {
                    cmd.elseCommands = activeCmdOriginal.elseCommands;
                }
            }
            closeCmdDialog(true);
            if (activeCmdCallback) activeCmdCallback(cmd);
        }

        function initEventModalTemplates() {}
