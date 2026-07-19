// Builds the generation contracts each stage's prompt embeds: excerpts of
// the shared-core ruleset (registry, roles, elements, ...) plus the id
// manifest of everything generated so far, so later stages reference real
// ids instead of hallucinating them.
'use strict';

const fs = require('fs');
const path = require('path');

const REPO = path.join(__dirname, '..', '..', '..');

function readJson(rel) {
    return JSON.parse(fs.readFileSync(path.join(REPO, rel), 'utf8'));
}

// Shared-core files (owner decision: ruleset stays fixed; content layer is
// generated). The generator copies ALL of data/ into the campaign dir first,
// then overwrites only the content-layer files stage by stage.
const CONTENT_FILES = ['actors.json', 'items.json', 'quests.json', 'maps.json',
    'shops.json', 'events.json', 'commonEvents.json'];

function commandRegistry() {
    const eng = readJson('data/engine.json');
    // Only what a content generator may emit: map/common-context commands,
    // trimmed to id/params/description.
    return (eng.commands || [])
        .filter(c => (c.contexts || []).some(x => x === 'map' || x === 'common' || x === 'any'))
        .map(c => ({
            id: c.id,
            params: (c.params || []).map(p => `${p.key}:${p.type}`),
            interactive: c.interactive || false,
            description: c.description || '',
        }));
}

function ruleset() {
    const roles = readJson('data/roles.json');
    const elements = readJson('data/elements.json');
    const states = readJson('data/states.json');
    const passives = readJson('data/passives.json');
    const skills = readJson('data/skills.json');
    return {
        roles: Object.keys(roles),
        elements: Object.keys(elements),
        states: Object.keys(states),
        passives: Object.keys(passives),
        skills: Object.entries(skills).map(([id, s]) => ({ id, name: s.name, target: s.target })),
    };
}

// One representative sample per entity type, pulled from the REAL default
// campaign -- the schema-by-example that keeps models honest about shape.
function samples() {
    const actors = readJson('data/actors.json');
    const items = readJson('data/items.json');
    const maps = readJson('data/maps.json');
    const quests = readJson('data/quests.json');
    const town = maps.find(m => m.category === 'town') || maps[0];
    return {
        actor: actors.find(a => a.role !== 'Summoner') || actors[0],
        item: items[0],
        quest: Object.values(quests)[0],
        map: { ...town, events: (town.events || []).slice(0, 2) },
        event: (town.events || []).find(e => e.script && e.script.length > 1) || (town.events || [])[0],
    };
}

// Id manifest of the campaign generated so far (reads from the campaign
// dir, which starts as a copy of data/ and gets overwritten per stage).
function manifest(campaignDir) {
    const j = f => JSON.parse(fs.readFileSync(path.join(campaignDir, f), 'utf8'));
    const actors = j('actors.json');
    const items = j('items.json');
    const maps = j('maps.json');
    const quests = j('quests.json');
    const shops = j('shops.json');
    const commonEvents = j('commonEvents.json');
    return {
        actors: actors.map(a => ({ id: a.id, name: a.name, role: a.role, tier: a.tier })),
        items: items.map(i => ({ id: i.id, name: i.name, type: i.type })),
        maps: maps.map(m => ({ id: m.id, title: m.title, category: m.category })),
        quests: Object.keys(quests),
        shops: Object.keys(shops),
        commonEvents: Object.keys(commonEvents),
    };
}

module.exports = { REPO, CONTENT_FILES, readJson, commandRegistry, ruleset, samples, manifest };
