
        // --- SCHEMA-DRIVEN ENTITY FORMS ---
        // Declarative form definitions for the Database tabs. Each schema is
        // a list of field specs interpreted by buildEntityForm; adding a
        // field to a tab (or a whole new simple tab) means adding a spec
        // here, not hand-writing DOM. Complex tabs (units, commonEvents,
        // animations, quests, themes) still build custom panels in
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

        // State categories: a checkbox per registered category, because a state
        // belongs to several at once (poison is negative, common and physical)
        // and each is a separate handle STATE_CATEGORY_RATE can grab. Options
        // come from engine.json, so the editor cannot offer one G1 rejects.
        // The key is deleted rather than left as [] when nothing is ticked,
        // keeping unauthored states out of the diff.
        function buildStateCategoryPicker(container, state) {
            const registry = (dbPayload.engine && dbPayload.engine.stateCategories) || [];
            if (registry.length === 0) return;

            const fs = document.createElement('fieldset');
            fs.style.cssText = 'padding: 4px 6px; margin-top: 4px;';
            const leg = document.createElement('legend');
            leg.textContent = 'Categories';
            fs.appendChild(leg);

            const wrap = document.createElement('div');
            wrap.style.cssText = 'display: flex; flex-wrap: wrap; gap: 2px 10px;';

            registry.forEach(entry => {
                const label = document.createElement('label');
                label.style.cssText = 'display: flex; align-items: center; gap: 3px; font-size: 11px;';
                if (entry.description) label.title = entry.description;

                const box = document.createElement('input');
                box.type = 'checkbox';
                box.checked = (state.categories || []).indexOf(entry.category) !== -1;
                box.onchange = () => {
                    const current = (state.categories || []).slice();
                    const at = current.indexOf(entry.category);
                    if (box.checked && at === -1) {
                        current.push(entry.category);
                    } else if (!box.checked && at !== -1) {
                        current.splice(at, 1);
                    }
                    // Keep registry order rather than click order, so the same
                    // set of ticks always serialises the same way.
                    const ordered = registry
                        .map(r => r.category)
                        .filter(c => current.indexOf(c) !== -1);
                    if (ordered.length === 0) {
                        delete state.categories;
                    } else {
                        state.categories = ordered;
                    }
                    setDirty(true);
                };

                label.appendChild(box);
                label.appendChild(document.createTextNode(entry.label || entry.category));
                wrap.appendChild(label);
            });

            fs.appendChild(wrap);
            container.appendChild(fs);
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
                      options: ['consumable', 'equipment', 'quest', 'junk'], fallback: 'consumable', rerender: true },
                    { row: 'main', kind: 'select', key: 'equipType', label: 'Equip Slot',
                      options: ['Weapon', 'Armor', 'Accessory'], fallback: 'Weapon',
                      when: it => it.type === 'equipment' },
                    { row: 'main', kind: 'select', key: 'target', label: 'Target Scope',
                      options: [{ value: '', label: 'Single member' }, { value: 'party', label: 'Whole party' },
                                { value: 'none', label: 'No target' }],
                      when: it => it.type !== 'equipment',
                      get: it => it.target || '',
                      set: (it, v) => {
                          if (v === '') { delete it.target; } else { it.target = v; }
                      } },
                    // Use occasion. Options come from engine.json itemScopes so
                    // the editor cannot offer a word the engine does not know;
                    // '' writes nothing, keeping "always" the unauthored default
                    // that most items should stay at.
                    { row: 'main', kind: 'select', key: 'scope', label: 'Use Occasion',
                      when: it => it.type !== 'equipment',
                      options: () => [{ value: '', label: 'Battle and field (default)' }].concat(
                          ((dbPayload.engine && dbPayload.engine.itemScopes) || [])
                              .filter(s => s.scope !== 'always')
                              .map(s => ({ value: s.scope, label: s.label || s.scope }))),
                      get: it => it.scope === 'always' ? '' : (it.scope || ''),
                      set: (it, v) => {
                          if (v === '') { delete it.scope; } else { it.scope = v; }
                      } },
                    { row: 'main', kind: 'number', key: 'cost', label: 'Buy Cost (G)', fallback: 0 },
                    { kind: 'checkbox', key: 'meal', label: 'Meal (field-only food)', deleteIfFalse: true,
                      when: it => it.type === 'consumable',
                      set: (it, checked) => {
                          if (checked) { it.meal = true; it.scope = 'field'; }
                          else { delete it.meal; }
                      } },
                    { kind: 'checkbox', key: '_dungeonOnly', label: 'Dungeon use only',
                      when: it => it.type === 'consumable',
                      get: it => !!(it.meta || {}).dungeonOnly,
                      set: (it, checked) => {
                          it.meta = it.meta || {};
                          if (checked) it.meta.dungeonOnly = true;
                          else delete it.meta.dungeonOnly;
                      } },
                    { kind: 'custom', when: it => it.type === 'consumable',
                      build: (c, it) => buildChecklistField(c, 'Food Tags',
                          ((dbPayload.engine && dbPayload.engine.foodTags) || []).map(x => x.tag),
                          tag => tag, () => it.foodTags,
                          arr => { if (arr.length) it.foodTags = arr; else delete it.foodTags; }) },
                    { kind: 'checkbox', key: '_savorEnabled', label: 'Favorite Food grants Savor',
                      when: it => it.type === 'consumable' && (it.meal || (it.foodTags || []).length),
                      get: it => !!it.savor,
                      set: (it, checked) => {
                          if (checked) it.savor = it.savor || { battles: 3, traits: [] };
                          else delete it.savor;
                      },
                      rerender: true },
                    { kind: 'number', key: '_savorBattles', label: 'Savor Victories', fallback: 3,
                      when: it => !!it.savor,
                      get: it => it.savor.battles || 3,
                      set: (it, value) => { it.savor.battles = Math.max(1, value || 1); } },
                    { kind: 'custom', when: it => !!it.savor,
                      build: (c, it) => buildTraitsEditor(c, it.savor, 'Savor Traits') },
                    { kind: 'animationSelect', key: 'animation', label: 'Animation',
                      when: it => it.type !== 'equipment' },
                    { kind: 'custom', when: it => it.type !== 'equipment',
                      build: (c, it) => buildActionSequencePicker(c, it) },
                    { kind: 'text', key: 'description', label: 'Description (flavor)' },
                    { kind: 'text', key: 'keyArt', label: 'Showcase Image' },
                    { kind: 'text', key: 'condition', label: 'Trait Condition (e.g. HP < 50%)', deleteIfEmpty: true,
                      when: it => it.type === 'equipment' },
                    { kind: 'custom', when: it => it.type === 'equipment',
                      build: (c, it) => buildTraitsEditor(c, it, 'Equipment Traits') },
                    { kind: 'custom', when: it => it.type !== 'equipment',
                      build: (c, it) => buildEffectsEditor(c, it) }
                ]
            },
            skills: {
                resolve: item => dbPayload.skills[item.id],
                rows: { top: { gap: '0' } },
                fields: [
                    { row: 'top', kind: 'icon', key: 'icon', label: 'Icon' },
                    { row: 'top', kind: 'text', key: 'name', label: 'Name', refreshList: true },
                    { kind: 'text', key: 'description', label: 'Description' },
                    { kind: 'select', key: 'target', label: 'Target',
                      options: () => SKILL_TARGETS, fallback: 'enemy-any' },
                    { kind: 'select', key: 'element', label: 'Element',
                      options: () => elementOptions(true),
                      set: (sk, v) => { sk.element = (v === '') ? null : v; } },
                    { kind: 'animationSelect', key: 'animation', label: 'Animation' },
                    { kind: 'custom', build: (c, sk) => buildActionSequencePicker(c, sk) },
                    // No skill costs MP. Magic spends CHARGES (refilled at
                    // Rest, or Overcast out of the Summoner's pool when spent);
                    // physical skills are gated by cooldown/warmup/condition.
                    // `charges: 0` is the Overcast-only shape (dragon Breath).
                    { row: 'cost', kind: 'text', key: 'charges',
                      label: 'Charges (formula, 0 = Overcast-only)', deleteIfEmpty: true },
                    // The 'number' kind coerces a blank input to 0, so these
                    // three delete on 0 rather than authoring a meaningless
                    // `cooldown: 0` / free Overcast into every skill row.
                    { row: 'cost', kind: 'number', key: 'overcast.mp', label: 'Overcast MP',
                      get: sk => (sk.overcast || {}).mp,
                      set: (sk, v) => {
                          if (!v) { delete sk.overcast; } else { sk.overcast = { mp: Number(v) }; }
                      } },
                    { row: 'gate', kind: 'number', key: 'cooldown', label: 'Cooldown (turns)',
                      set: (sk, v) => { if (!v) { delete sk.cooldown; } else { sk.cooldown = Number(v); } } },
                    { row: 'gate', kind: 'number', key: 'warmup', label: 'Warmup (turns)',
                      set: (sk, v) => { if (!v) { delete sk.warmup; } else { sk.warmup = Number(v); } } },
                    { kind: 'text', key: 'condition',
                      label: 'Condition (formula, or state:/flag:/hasItem:)', deleteIfEmpty: true },
                    // Required alongside condition (G1 enforces it): a formula
                    // cannot produce readable text, and an unexplained greyed
                    // row in the battle menu is a bug report waiting to happen.
                    { kind: 'text', key: 'conditionText',
                      label: 'Condition Text (shown when blocked)', deleteIfEmpty: true },
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
                    { kind: 'text', key: 'condition', label: 'Trait Condition (e.g. HP < 50%)', deleteIfEmpty: true },
                    // Categories are a LIST, not a single kind: a state is
                    // routinely several things at once (poison is negative AND
                    // common AND physical), and each one is a separate handle
                    // STATE_CATEGORY_RATE can grab. Checkboxes come from the
                    // engine.json registry, so the editor cannot offer a
                    // category the validator would reject.
                    { kind: 'custom', build: (c, st) => buildStateCategoryPicker(c, st) },
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
                        note.textContent = 'The engine locates the player character by the "Summoner" role — keep exactly one Unit with it.';
                        c.appendChild(note);
                    } }
                ]
            },
            shops: {
                resolve: item => dbPayload.shops[item.id],
                fields: [
                    { kind: 'text', key: 'name', label: 'Shop Name', refreshList: true,
                      get: (s, item) => s.name || `Shop ${item.id}` },
                    { kind: 'custom', build: (container, shopData) => {
                        const listWrapper = document.createElement('div');
                        listWrapper.className = 'form-group';
                        const lbl = document.createElement('label');
                        lbl.textContent = 'Stock Selection (price override + unlock condition)';
                        listWrapper.appendChild(lbl);

                        const renderStock = () => {
                            listWrapper.querySelectorAll('.shop-stock-row').forEach(el => el.remove());
                            dbPayload.items.forEach(availItem => {
                                const stockEntry = shopData.items.find(shIt => shIt.id === availItem.id);
                                const div = document.createElement('div');
                                div.className = 'shop-stock-row';
                                div.style.cssText = 'margin: 4px 0; display: flex; align-items: center; gap: 6px;';

                                const chk = document.createElement('input');
                                chk.type = 'checkbox';
                                chk.checked = !!stockEntry;
                                chk.onchange = () => {
                                    setDirty(true);
                                    if (chk.checked) {
                                        if (!shopData.items.some(i => i.id === availItem.id)) {
                                            shopData.items.push({ id: availItem.id, price: availItem.cost });
                                        }
                                    } else {
                                        shopData.items = shopData.items.filter(i => i.id !== availItem.id);
                                    }
                                    renderStock();
                                };

                                const nameSpan = document.createElement('span');
                                nameSpan.style.flex = '1';
                                nameSpan.textContent = `${availItem.name} (base ${availItem.cost} G)`;

                                div.appendChild(chk);
                                div.appendChild(nameSpan);

                                if (stockEntry) {
                                    const price = document.createElement('input');
                                    price.type = 'number';
                                    price.className = 'win98-input';
                                    price.style.width = '64px';
                                    price.title = 'Shop price (G)';
                                    price.value = stockEntry.price !== undefined ? stockEntry.price : availItem.cost;
                                    price.oninput = () => { stockEntry.price = parseInt(price.value) || 0; setDirty(true); };
                                    div.appendChild(price);

                                    const cond = document.createElement('input');
                                    cond.type = 'text';
                                    cond.className = 'win98-input';
                                    cond.style.width = '130px';
                                    cond.placeholder = 'level:3 / flag:x / gold:50';
                                    cond.title = 'Unlock condition (blank = always available)';
                                    cond.value = stockEntry.condition || '';
                                    cond.oninput = () => {
                                        if (cond.value === '') { delete stockEntry.condition; } else { stockEntry.condition = cond.value; }
                                        setDirty(true);
                                    };
                                    div.appendChild(cond);
                                }

                                listWrapper.appendChild(div);
                            });
                        };
                        renderStock();
                        container.appendChild(listWrapper);
                    } }
                ]
            },
            lore: {
                resolve: item => dbPayload.lore[item.id],
                fields: [
                    { kind: 'custom', build: (c, entry, item) =>
                        createFormField(c, 'Lore ID (key)', item.id, val => renameLoreKey(item.id, val)) },
                    { kind: 'text', key: 'title', label: 'Title', refreshList: true },
                    { kind: 'text', key: 'category', label: 'Category' },
                    { kind: 'number', key: 'order', label: 'Sort Order', fallback: 0 },
                    { kind: 'checkbox', key: 'unlocked', label: 'Unlocked by Default', deleteIfFalse: true },
                    { kind: 'custom', build: (c, entry) => {
                        const bodyGroup = document.createElement('div');
                        bodyGroup.className = 'form-group';
                        const bodyLabel = document.createElement('label');
                        bodyLabel.textContent = 'Body';
                        const body = document.createElement('textarea');
                        body.className = 'win98-input';
                        body.style.cssText = 'width: 100%; height: 180px; box-sizing: border-box; resize: vertical;';
                        body.value = entry.body || '';
                        body.oninput = () => { entry.body = body.value; setDirty(true); };
                        bodyGroup.appendChild(bodyLabel);
                        bodyGroup.appendChild(body);
                        c.appendChild(bodyGroup);
                    } },
                    { kind: 'custom', build: (c, entry, item) => {
                        const del = document.createElement('button');
                        del.className = 'win98-btn';
                        del.textContent = 'Delete Lore Entry';
                        del.onclick = () => deleteLore(item.id);
                        c.appendChild(del);
                    } }
                ]
            }
        };

        // Label for a discipline kind, from the engine.json registry.
        function disciplineLabel(kind) {
            const reg = (dbPayload.engine && dbPayload.engine.disciplines) || [];
            const hit = reg.find(d => d.kind === kind);
            return (hit && hit.label) || kind;
        }

        // Which disciplines can PRODUCE this item: authored `meta.disciplines`
        // wins, otherwise the default implied by what the item plainly is, and
        // `meta.craftable = false` opts out entirely. Mirrors
        // engine/craft.lua's `disciplinesOf` plus the `craftable` gate that
        // `craft.pool` applies, and G1 already reports items this resolves to
        // nothing (validator.lua "has no discipline membership").
        //
        // This is the one place the editor reproduces an engine rule instead of
        // reading data straight through. It is here rather than behind a call
        // into LOVE because the previews reflect the last SAVE, and a facet
        // filter has to answer for the edit the author just made. The rule is
        // pure engine.json lookup tables — if `disciplineDefaults` grows a
        // fourth source, both sides need it.
        function resolveItemDisciplines(item) {
            const meta = item.meta || {};
            if (meta.craftable === false) return [];
            if (Array.isArray(meta.disciplines) && meta.disciplines.length > 0) {
                return meta.disciplines.slice();
            }
            const d = (dbPayload.engine && dbPayload.engine.disciplineDefaults) || {};
            let kind = item.equipType && (d.byEquipType || {})[item.equipType];
            if (!kind) {
                (item.effects || []).some(ef => {
                    kind = (d.byEffect || {})[ef.type];
                    return !!kind;
                });
            }
            if (!kind) kind = (d.byType || {})[item.type];
            return kind ? [kind] : [];
        }
        window.resolveItemDisciplines = resolveItemDisciplines;

        // Schema layer for the LIST column, the counterpart of
        // ENTITY_FORM_SCHEMAS above: a tab listed here gets search, sort and
        // facet controls interpreted by database.js, and a tab that is absent
        // keeps the plain id-ordered list. Declaring the axes here (rather than
        // hand-building controls per tab) is the same rule the form fields
        // follow — see AGENTS.md, "no copy-pasted logic".
        //
        // Everything below is read-only over the collection: sorting and
        // filtering build a view array and never reorder dbPayload, so the
        // underlying data/*.json is untouched by looking at it.
        const ENTITY_LIST_SCHEMAS = {
            items: {
                search: {
                    placeholder: 'name contains…',
                    match: (it, q) => (it.name || '').toLowerCase().includes(q)
                },
                defaultSort: { key: 'id', dir: 1 },
                sorts: [
                    { key: 'id', label: 'ID', value: it => it.id || 0 },
                    { key: 'name', label: 'Name', value: it => (it.name || '').toLowerCase() },
                    { key: 'cost', label: 'Buy Cost', value: it => it.cost || 0 },
                    { key: 'type', label: 'Type', value: it =>
                        [it.type || '', it.equipType || '', (it.name || '').toLowerCase()] },
                    // Sorting by membership groups an author's crafting work
                    // together; items no discipline can produce sort last.
                    { key: 'discipline', label: 'Discipline', value: it => {
                        const ds = resolveItemDisciplines(it).slice().sort();
                        return [ds[0] || '￿', (it.name || '').toLowerCase()];
                    } }
                ],
                facets: [
                    { key: 'type', label: 'Type',
                      values: it => [it.type || '(untyped)'] },
                    // Only equipment carries a slot; a consumable contributes
                    // no value and so is hidden whenever a slot is selected.
                    { key: 'equipType', label: 'Equip Slot',
                      values: it => it.type === 'equipment' ? [it.equipType || '(unset)'] : [] },
                    { key: 'disciplines', label: 'Produced By',
                      values: it => {
                          const ds = resolveItemDisciplines(it);
                          if (ds.length === 0) {
                              return [{ value: '(none)', label: '(none)',
                                        title: 'No discipline can produce this item — it is invisible to Item Creation' }];
                          }
                          return ds.map(d => ({ value: d, label: disciplineLabel(d) }));
                      } },
                    // Where that membership came from: authored on the item,
                    // implied by disciplineDefaults, or absent.
                    // Ingredient eligibility is the other half of the crafting
                    // relationship and is independent of output membership: the
                    // remains policy is "ingredient, never output", the
                    // promotion-key policy is neither.
                    { key: 'craftIngredient', label: 'Usable As Ingredient',
                      values: it => (it.meta || {}).craftIngredient === false
                          ? [{ value: 'no', label: 'no',
                               title: 'Excluded from Item Creation ingredient selection' }]
                          : [{ value: 'yes', label: 'yes' }] },
                    { key: 'membership', label: 'Membership',
                      values: it => {
                          const meta = it.meta || {};
                          if (meta.craftable === false) return ['opted out'];
                          if (Array.isArray(meta.disciplines) && meta.disciplines.length > 0) return ['authored'];
                          return resolveItemDisciplines(it).length > 0 ? ['default'] : ['none'];
                      } }
                ]
            }
        };
        window.ENTITY_LIST_SCHEMAS = ENTITY_LIST_SCHEMAS;

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
                    const rawVal = (typeof spec.get === 'function') ? spec.get(data, item) : (data[spec.key] !== undefined ? data[spec.key] : 0);
                    const iconVal = parseInt(rawVal) || 0;
                    const paletteVal = data.iconPalette || data.palette || null;
                    const specObj = { id: iconVal, palette: paletteVal };

                    createIconField(container, spec.label, specObj, (newId, newPalette) => {
                        const parsedId = parseInt(newId) || 0;
                        if (typeof spec.set === 'function') {
                            spec.set(data, parsedId, item);
                        } else {
                            data[spec.key] = parsedId;
                        }

                        if (newPalette) {
                            data.iconPalette = newPalette;
                        } else {
                            delete data.iconPalette;
                            delete data.palette;
                        }

                        setDirty(true);
                        if (spec.rerender) {
                            if (typeof loadFormForItem === 'function') loadFormForItem(item);
                        } else if (spec.refreshList) {
                            if (typeof initDatabaseEditor === 'function') initDatabaseEditor(true);
                        }
                    }, true);

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
