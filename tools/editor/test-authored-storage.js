const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const storage = require('./authored-storage');

function writeJson(filePath, value) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + '\n', 'utf8');
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'second-rite-authored-storage-'));
try {
    writeJson(path.join(root, 'tilesets.json'), {
        alpha: { id: 'alpha', name: 'Alpha' },
        beta: { id: 'beta', name: 'Beta' },
    });

    let loaded = storage.loadRegistry(root, 'tilesets');
    assert.equal(loaded.storage, 'monolith');
    assert.deepEqual(Object.keys(loaded.records), ['alpha', 'beta']);
    const monolithVersion = storage.versionToken(root, 'tilesets');

    storage.writeRegistryRecord(root, 'tilesets', { id: 'alpha', name: 'Alpha edited' }, monolithVersion);
    loaded = storage.loadRegistry(root, 'tilesets');
    assert.equal(loaded.records.alpha.name, 'Alpha edited');
    assert.notEqual(storage.versionToken(root, 'tilesets'), monolithVersion);

    fs.mkdirSync(path.join(root, 'tilesets'), { recursive: true });
    writeJson(path.join(root, 'tilesets', 'wrong-name.json'), { id: 'alpha', name: 'Fragment Alpha' });
    writeJson(path.join(root, 'tilesets', 'beta.json'), { id: 'beta', name: 'Fragment Beta' });
    fs.unlinkSync(path.join(root, 'tilesets.json'));

    loaded = storage.loadRegistry(root, 'tilesets');
    assert.equal(loaded.storage, 'fragments');
    assert.equal(loaded.records.alpha.name, 'Fragment Alpha');
    assert.ok(loaded.sourceById.alpha.endsWith('wrong-name.json'));

    const betaBefore = fs.readFileSync(path.join(root, 'tilesets', 'beta.json'), 'utf8');
    const fragmentVersion = storage.versionToken(root, 'tilesets');
    storage.writeRegistryRecord(root, 'tilesets', { id: 'alpha', name: 'Fragment Alpha edited' }, fragmentVersion);
    assert.equal(fs.readFileSync(path.join(root, 'tilesets', 'beta.json'), 'utf8'), betaBefore);
    assert.equal(storage.loadRegistry(root, 'tilesets').records.alpha.name, 'Fragment Alpha edited');
    assert.notEqual(storage.versionToken(root, 'tilesets'), fragmentVersion);

    const staleVersion = fragmentVersion;
    assert.throws(
        () => storage.writeRegistryRecord(root, 'tilesets', { id: 'alpha', name: 'stale' }, staleVersion),
        err => err && err.code === 'STALE_AUTHORED_DATA'
    );

    storage.writeRegistryRecord(root, 'tilesets', { id: 'gamma', name: 'Gamma' });
    assert.equal(storage.loadRegistry(root, 'tilesets').records.gamma.name, 'Gamma');
    assert.ok(fs.existsSync(path.join(root, 'tilesets', 'gamma.json')));

    writeJson(path.join(root, 'tilesets', 'index.json'), { files: [] });
    assert.throws(() => storage.loadRegistry(root, 'tilesets'), /must not use a shared index\.json/);
    fs.unlinkSync(path.join(root, 'tilesets', 'index.json'));

    writeJson(path.join(root, 'broken.json'), { wrong: { id: 'right' } });
    assert.throws(() => storage.loadRegistry(root, 'broken'), /disagrees with record\.id/);

    console.log('authored-storage node tests: OK');
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}
