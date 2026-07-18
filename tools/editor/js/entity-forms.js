
        // --- SCHEMA-DRIVEN ENTITY FORMS ---
        // Declarative form definitions for the Database tabs. Each schema is
        // a list of field specs interpreted by buildEntityForm; adding a
        // field to a tab (or a whole new simple tab) means adding a spec
        // here, not hand-writing DOM. Complex tabs (actors, commonEvents,
        // shops, animations, quests, themes) still build custom panels in
        // loadFormForItem and can migrate here incrementally.
        //
        // Field spec keys:
        //   kind     'icon' | 'text' | 'number' | 'checkbox' | 'select' |
        //            'animationSelect' | 'custom'
        //   key      property on the entity the field edits
        //   label    field label
        //   row      fields sharing a row id render side by side
        //   options  select choices — array or function (makeSelect format)
        //   fallback default written when input parses empty/invalid
        //   when     (data, item) => bool; skip the field when false
        //   get/set  override read/write for migrations or null-vs-delete
        //   deleteIfEmpty / deleteIfFalse   remove the key instead of
        //            writing '' / false
        //   refreshList   re-render the entity list after edits (renames)
        //   rerender      rebuild the whole form after a change (fields
        //            whose value toggles other fields' visibility)
        //   build    (container, data, item) — custom escape hatch

        // Shared "(default)" + assignable-animation select, used by items
        // and skills (previously copy-pasted in both branches).
        function animationSelectOptions() {
            const opts = [{ value: '', label: '(default)' }];
            Object.keys(dbPayload.animations || {}).forEach(id => {
                if (dbPayload.animations[id].class === 'assignable') {
                    opts.push({ value: id, label: id });
                }
            });
            return opts;
        }

        function buildActionSequencePicker(container, entity) {
            const fs = document.createElement('fieldset');
            fs.style.cssText = 'padding: 6px; margin-top: 6px; display: flex; flex-direction: column; gap: 4px;';
            const leg = document.createElement('legend');
            leg.textContent = 'Action Sequence';
            fs.appendChild(leg);

            let mode = 'default';
            if (entity.actionSequenceCommands) {
                mode = 'custom';
            } else if (entity.actionSequence) {
                mode = 'common';
            }

            const rDefault = document.createElement('input');
            rDefault.type = 'radio';
            rDefault.name = 'seq-mode-' + entity.id;
            rDefault.id = 'seq-default-' + entity.id;
            rDefault.checked = (mode === 'default');

            const lblDefault = document.createElement('label');
            lblDefault.htmlFor = rDefault.id;
            lblDefault.style.cssText = 'font-size: 10px; font-weight: bold; margin-left: 4px;';
            lblDefault.textContent = 'Default Sequence';

            const divDefault = document.createElement('div');
            divDefault.style.cssText = 'display: flex; align-items: center;';
            divDefault.appendChild(rDefault);
            divDefault.appendChild(lblDefault);
            fs.appendChild(divDefault);

            const rCommon = document.createElement('input');
            rCommon.type = 'radio';
            rCommon.name = 'seq-mode-' + entity.id;
            rCommon.id = 'seq-common-' + entity.id;
            rCommon.checked = (mode === 'common');

            const lblCommon = document.createElement('label');
            lblCommon.htmlFor = rCommon.id;
            lblCommon.style.cssText = 'font-size: 10px; font-weight: bold; margin-left: 4px;';
            lblCommon.textContent = 'Link Shared Sequence';

            const divCommonRadio = document.createElement('div');
            divCommonRadio.style.cssText = 'display: flex; align-items: center; margin-top: 4px;';
            divCommonRadio.appendChild(rCommon);
            divCommonRadio.appendChild(lblCommon);
            fs.appendChild(divCommonRadio);

            const selCommon = document.createElement('select');
            selCommon.className = 'win98-select';
            selCommon.style.cssText = 'width: 100%; margin-top: 2px; margin-bottom: 6px;';
            const seqKeys = Object.keys(dbPayload.actionSequences || {}).sort();
            seqKeys.forEach(k => {
                const opt = document.createElement('option');
                opt.value = k;
                opt.textContent = dbPayload.actionSequences[k].name || k;
                if (entity.actionSequence === k) opt.selected = true;
                selCommon.appendChild(opt);
            });
            if (mode !== 'common') selCommon.disabled = true;
            fs.appendChild(selCommon);

            const rCustom = document.createElement('input');
            rCustom.type = 'radio';
            rCustom.name = 'seq-mode-' + entity.id;
            rCustom.id = 'seq-custom-' + entity.id;
            rCustom.checked = (mode === 'custom');

            const lblCustom = document.createElement('label');
            lblCustom.htmlFor = rCustom.id;
            lblCustom.style.cssText = 'font-size: 10px; font-weight: bold; margin-left: 4px;';
            lblCustom.textContent = 'Custom Sequence';

            const divCustomRadio = document.createElement('div');
            divCustomRadio.style.cssText = 'display: flex; align-items: center; border-top: 1px solid var(--win-shadow); padding-top: 4px;';
            divCustomRadio.appendChild(rCustom);
            divCustomRadio.appendChild(lblCustom);
            fs.appendChild(divCustomRadio);

            const customCmdsBox = document.createElement('div');
            customCmdsBox.style.cssText = 'border: 1px solid var(--win-shadow); background: #fff; height: 160px; overflow-y: auto; padding: 4px; display: flex; flex-direction: column; gap: 2px; font-family: monospace; font-size: 11px; margin-top: 4px;';
            
            const rerenderCustomCommands = () => {
                setDirty(true);
                renderCommandList(customCmdsBox, entity.actionSequenceCommands, rerenderCustomCommands, false, 0, 'action_sequence');
            };

            if (mode === 'custom') {
                entity.actionSequenceCommands = entity.actionSequenceCommands || [];
                renderCommandList(customCmdsBox, entity.actionSequenceCommands, rerenderCustomCommands, false, 0, 'action_sequence');
                fs.appendChild(customCmdsBox);
            }

            const updateSelection = () => {
                if (rDefault.checked) {
                    delete entity.actionSequence;
                    delete entity.actionSequenceCommands;
                    setDirty(true);
                    loadFormForItem(entity);
                } else if (rCommon.checked) {
                    delete entity.actionSequenceCommands;
                    entity.actionSequence = selCommon.value || seqKeys[0] || 'default';
                    setDirty(true);
                    loadFormForItem(entity);
                } else if (rCustom.checked) {
                    delete entity.actionSequence;
                    entity.actionSequenceCommands = entity.actionSequenceCommands || [ { cmd: "APPLY_EFFECT" } ];
                    setDirty(true);
                    loadFormForItem(entity);
                }
            };

            rDefault.onchange = updateSelection;
            rCommon.onchange = updateSelection;
            rCustom.onchange = updateSelection;
            selCommon.onchange = () => {
                entity.actionSequence = selCommon.value;
                setDirty(true);
            };

            container.appendChild(fs);
        }

        const ENTITY_FORM_SCHEMAS = {
            items: {
                resolve: item => item,
                rows: { top: { gap: '0' } },
                fields: [
                    { row: 'top', kind: 'icon', key: 'icon', label: 'Icon' },
                    { row: 'top', kind: 'text', key: 'name', label: 'Name', refreshList: true },
                    { row: 'main', kind: 'select', key: 'type', label: 'Type',
                      options: ['consumable', 'equipment', 'quest'], fallback: 'consumable', rerender: true },
                    { row: 'main', kind: 'select', key: 'equipType', label: 'Equip Slot',
                      options: ['Weapon', 'Armor', 'Accessory'], fallback: 'Weapon',
                      when: it => it.type === 'equipment' },
                    { row: 'main', kind: 'select', key: 'target', label: 'Target Scope',
                      options: [{ value: '', label: 'Single member' }, { value: 'party', label: 'Whole party' }],
                      when: it => it.type !== 'equipment',
                      get: it => it.target || it.targetScope || '',
                      set: (it, v) => {
                          delete it.targetScope; // old field name, migrate off it on save
                          if (v === '') { delete it.target; } else { it.target = v; }
                      } },
                    { row: 'main', kind: 'number', key: 'cost', label: 'Buy Cost (G)', fallback: 0 },
                    { kind: 'animationSelect', key: 'animation', label: 'Animation',
                      when: it => it.type !== 'equipment' },
                    { kind: 'custom', when: it => it.type !== 'equipment',
                      build: (c, it) => buildActionSequencePicker(c, it) },
                    { kind: 'text', key: 'description', label: 'Description' },
                    { kind: 'custom', when: it => it.type === 'equipment',
                      build: (c, it) => buildTraitsEditor(c, it, 'Equipment Traits') },
                    { kind: 'custom', when: it => it.type !== 'equipment',
                      build: (c, it) => buildEffectsEditor(c, it) }
                ]
            },
            skills: {
                resolve: item => dbPayload.skills[item.id],
                fields: [
                    { kind: 'text', key: 'name', label: 'Name', refreshList: true },
                    { kind: 'text', key: 'description', label: 'Description' },
                    { kind: 'select', key: 'target', label: 'Target',
                      options: () => SKILL_TARGETS, fallback: 'enemy-any' },
                    { kind: 'select', key: 'element', label: 'Element',
                      options: () => elementOptions(true),
                      set: (sk, v) => { sk.element = (v === '') ? null : v; } },
                    { kind: 'animationSelect', key: 'animation', label: 'Animation' },
                    { kind: 'custom', build: (c, sk) => buildActionSequencePicker(c, sk) },
                    { row: 'cost', kind: 'number', key: 'mpCost', label: 'MP Cost', fallback: 0 },
                    { row: 'cost', kind: 'number', key: 'speed', label: 'Speed Bonus', fallback: 0 },
                    { kind: 'custom', build: (c, sk) => buildEffectsEditor(c, sk) }
                ]
            },
            passives: {
                resolve: item => dbPayload.passives[item.id],
                rows: { top: { gap: '0' } },
                fields: [
                    { row: 'top', kind: 'icon', key: 'icon', label: 'Icon' },
                    { row: 'top', kind: 'text', key: 'name', label: 'Name', refreshList: true },
                    { kind: 'text', key: 'description', label: 'Description (flavor)' },
                    { kind: 'text', key: 'effect', label: 'Effect Summary (shown in menus)' },
                    { kind: 'text', key: 'condition', label: 'Condition (e.g. HP < 50%)', deleteIfEmpty: true },
                    { kind: 'custom', build: (c, p) => buildTraitsEditor(c, p) }
                ]
            },
            states: {
                resolve: item => dbPayload.states[item.id],
                rows: { top: { gap: '0' } },
                fields: [
                    { row: 'top', kind: 'icon', key: 'icon', label: 'Icon' },
                    { row: 'top', kind: 'text', key: 'name', label: 'Name', refreshList: true },
                    { kind: 'number', key: 'duration', label: 'Duration (turns, 9999 = permanent)',
                      fallback: 0, get: st => st.duration || 3 },
                    { kind: 'checkbox', key: 'removeAtDamage', label: 'Removed when taking damage', deleteIfFalse: true },
                    { kind: 'custom', build: (c, st) => buildTraitsEditor(c, st) }
                ]
            },
            elements: {
                resolve: item => dbPayload.elements[item.id],
                rows: { top: { gap: '0' } },
                fields: [
                    { row: 'top', kind: 'icon', key: 'icon', label: 'Orb Icon',
                      get: el => el.icon !== undefined ? el.icon : 16 },
                    { row: 'top', kind: 'text', key: 'name', label: 'Name', refreshList: true,
                      get: (el, item) => el.name || item.id },
                    { kind: 'custom', build: (c, el, item) => {
                        const others = Object.keys(dbPayload.elements).filter(k => k !== item.id);
                        buildChecklistField(c, 'Strong Against (deals bonus damage to)', others,
                            id => id, () => el.strongAgainst, arr => { el.strongAgainst = arr; });
                        buildChecklistField(c, 'Weak Against (deals reduced damage to)', others,
                            id => id, () => el.weakAgainst, arr => { el.weakAgainst = arr; });
                    } }
                ]
            },
            roles: {
                resolve: item => dbPayload.roles[item.id],
                fields: [
                    { kind: 'text', key: 'name', label: 'Name', refreshList: true,
                      get: (r, item) => r.name || item.id },
                    { kind: 'text', key: 'description', label: 'Description' },
                    { kind: 'custom', when: (r, item) => item.id === 'Summoner', build: (c) => {
                        const note = document.createElement('p');
                        note.style.cssText = 'font-size: 10px; color: var(--win-dark-shadow);';
                        note.textContent = 'The engine locates the player character by the "Summoner" role — keep exactly one actor with it.';
                        c.appendChild(note);
                    } }
                ]
            }
        };

        // Interprets an ENTITY_FORM_SCHEMAS entry into the form panel.
        // Returns false when the entity can't be resolved (deleted id).
        function buildEntityForm(formPanel, item, schemaDef) {
            const data = schemaDef.resolve(item);
            if (!data) return false;

            const readValue = (spec) =>
                spec.get ? spec.get(data, item) : data[spec.key];
            const writeValue = (spec, val) => {
                if (spec.set) { spec.set(data, val); } else { data[spec.key] = val; }
                if (spec.refreshList) initDatabaseEditor(true);
                if (spec.rerender) loadFormForItem(item);
            };

            let currentRowId = null;
            let currentRowEl = null;
            const containerFor = (spec) => {
                if (!spec.row) { currentRowId = null; currentRowEl = null; return formPanel; }
                if (spec.row !== currentRowId) {
                    currentRowId = spec.row;
                    currentRowEl = document.createElement('div');
                    currentRowEl.className = 'form-row';
                    const rowCfg = (schemaDef.rows || {})[spec.row];
                    if (rowCfg && rowCfg.gap !== undefined) currentRowEl.style.gap = rowCfg.gap;
                    formPanel.appendChild(currentRowEl);
                }
                return currentRowEl;
            };

            schemaDef.fields.forEach(spec => {
                if (spec.when && !spec.when(data, item)) return;
                const container = containerFor(spec);

                if (spec.kind === 'icon') {
                    createIconField(container, spec.label, readValue(spec) || 0,
                        val => writeValue(spec, parseInt(val) || 0), true);

                } else if (spec.kind === 'text') {
                    createFormField(container, spec.label, readValue(spec) || '', val => {
                        if (spec.deleteIfEmpty && val === '') { delete data[spec.key]; }
                        else { writeValue(spec, val); }
                    });

                } else if (spec.kind === 'number') {
                    createFormField(container, spec.label, readValue(spec) !== undefined ? readValue(spec) : (spec.fallback || 0),
                        val => writeValue(spec, parseInt(val) || spec.fallback || 0), 'number');

                } else if (spec.kind === 'checkbox') {
                    createCheckboxField(container, spec.label, readValue(spec), v => {
                        if (spec.deleteIfFalse && !v) { delete data[spec.key]; setDirty(true); }
                        else { writeValue(spec, v); }
                    });

                } else if (spec.kind === 'select' || spec.kind === 'animationSelect') {
                    const group = document.createElement('div');
                    group.className = 'form-group';
                    if (container !== formPanel) group.style.flex = '1';
                    const lbl = document.createElement('label');
                    lbl.textContent = spec.label;
                    group.appendChild(lbl);
                    const options = spec.kind === 'animationSelect'
                        ? animationSelectOptions()
                        : (typeof spec.options === 'function' ? spec.options() : spec.options);
                    const current = readValue(spec) || spec.fallback || '';
                    group.appendChild(makeSelect(options, current, v => {
                        if (spec.kind === 'animationSelect') {
                            if (v === '') { delete data[spec.key]; } else { data[spec.key] = v; }
                            if (spec.rerender) loadFormForItem(item);
                        } else {
                            writeValue(spec, v);
                        }
                    }));
                    container.appendChild(group);

                } else if (spec.kind === 'custom') {
                    spec.build(container, data, item);
                }
            });
            return true;
        }
