const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function readJson(filePath) {
    let text;
    try {
        text = fs.readFileSync(filePath, 'utf8');
    } catch (err) {
        const e = new Error(`authored JSON file does not exist: ${filePath}`);
        e.cause = err;
        throw e;
    }
    try {
        return JSON.parse(text);
    } catch (err) {
        const e = new Error(`invalid JSON in ${filePath}: ${err.message}`);
        e.cause = err;
        throw e;
    }
}

function validateRegistryRecord(record, stem, source) {
    if (!record || Array.isArray(record) || typeof record !== 'object') {
        throw new Error(`registry '${stem}' record is not an object: ${source}`);
    }
    if (typeof record.id !== 'string' || record.id.length === 0) {
        throw new Error(`registry '${stem}' record must own a non-empty string id: ${source}`);
    }
    return record.id;
}

function validateRegistryMonolith(value, stem, source) {
    if (!value || Array.isArray(value) || typeof value !== 'object' || Object.keys(value).length === 0) {
        throw new Error(`registry '${stem}' must be a non-empty object: ${source}`);
    }
    const out = {};
    for (const [key, record] of Object.entries(value)) {
        const recordId = validateRegistryRecord(record, stem, source);
        if (key !== recordId) {
            throw new Error(`registry '${stem}' key '${key}' disagrees with record.id '${recordId}': ${source}`);
        }
        if (Object.prototype.hasOwnProperty.call(out, recordId)) {
            throw new Error(`registry '${stem}' has duplicate id '${recordId}': ${source}`);
        }
        out[recordId] = record;
    }
    return out;
}

function registryFiles(directory, stem) {
    if (!fs.existsSync(directory) || !fs.statSync(directory).isDirectory()) {
        throw new Error(`registry directory does not exist: ${directory}`);
    }
    if (fs.existsSync(path.join(directory, 'index.json'))) {
        throw new Error(`registry '${stem}' must not use a shared index.json`);
    }
    const files = fs.readdirSync(directory)
        .filter(name => name.toLowerCase().endsWith('.json'))
        .sort((a, b) => a.localeCompare(b, 'en'));
    if (files.length === 0) {
        throw new Error(`registry '${stem}' has no JSON fragments: ${directory}`);
    }
    return files;
}

function loadRegistryFragments(directory, stem = path.basename(directory)) {
    const out = {};
    const sourceById = {};
    for (const name of registryFiles(directory, stem)) {
        const filePath = path.join(directory, name);
        const record = readJson(filePath);
        const recordId = validateRegistryRecord(record, stem, filePath);
        if (Object.prototype.hasOwnProperty.call(out, recordId)) {
            throw new Error(`registry '${stem}' has duplicate id '${recordId}': ${filePath}`);
        }
        out[recordId] = record;
        sourceById[recordId] = filePath;
    }
    return { records: out, sourceById };
}

function loadRegistry(root, stem) {
    const monolith = path.join(root, `${stem}.json`);
    if (fs.existsSync(monolith)) {
        return {
            records: validateRegistryMonolith(readJson(monolith), stem, monolith),
            storage: 'monolith',
            sourceById: {},
        };
    }
    const loaded = loadRegistryFragments(path.join(root, stem), stem);
    return { records: loaded.records, storage: 'fragments', sourceById: loaded.sourceById };
}

function hashFile(hasher, root, filePath) {
    const relative = path.relative(root, filePath).split(path.sep).join('/');
    const relativeBytes = Buffer.from(relative, 'utf8');
    const payload = fs.readFileSync(filePath);
    const size = Buffer.alloc(8);
    size.writeBigUInt64BE(BigInt(relativeBytes.length));
    hasher.update(size);
    hasher.update(relativeBytes);
    size.writeBigUInt64BE(BigInt(payload.length));
    hasher.update(size);
    hasher.update(payload);
}

function versionToken(root, stem) {
    const hasher = crypto.createHash('sha256');
    hasher.update(`registry\0${stem}\0`);
    const monolith = path.join(root, `${stem}.json`);
    if (fs.existsSync(monolith)) {
        hasher.update('monolith\0');
        hashFile(hasher, root, monolith);
        return hasher.digest('hex');
    }

    hasher.update('fragments\0');
    const directory = path.join(root, stem);
    for (const name of registryFiles(directory, stem)) {
        hashFile(hasher, root, path.join(directory, name));
    }
    return hasher.digest('hex');
}

function atomicWriteJson(filePath, value, indent = 2) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    const temp = path.join(
        path.dirname(filePath),
        `.${path.basename(filePath)}.${process.pid}.${Date.now()}.tmp`
    );
    fs.writeFileSync(temp, JSON.stringify(value, null, indent) + '\n', 'utf8');
    try {
        fs.renameSync(temp, filePath);
    } catch (err) {
        try { fs.unlinkSync(temp); } catch (_) {}
        throw err;
    }
}

function safeFragmentCandidate(recordId, existingNames) {
    let candidate = /^[A-Za-z0-9._-]+$/.test(recordId) && recordId !== '.' && recordId !== '..' && recordId.toLowerCase() !== 'index'
        ? `${recordId}.json`
        : null;
    const folded = new Set(existingNames.map(name => name.toLowerCase()));
    if (candidate && !folded.has(candidate.toLowerCase())) return candidate;

    const slug = recordId.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'record';
    const digest = crypto.createHash('sha256').update(recordId, 'utf8').digest('hex').slice(0, 10);
    candidate = `${slug}--${digest}.json`;
    if (folded.has(candidate.toLowerCase())) {
        throw new Error(`registry filename collision for id '${recordId}': ${candidate}`);
    }
    return candidate;
}

function writeRegistryRecord(root, stem, record, expectedVersion = null) {
    const recordId = validateRegistryRecord(record, stem, `<write ${stem}>`);
    const loaded = loadRegistry(root, stem);
    const currentVersion = versionToken(root, stem);
    const exists = Object.prototype.hasOwnProperty.call(loaded.records, recordId);
    if (exists && expectedVersion !== currentVersion) {
        const err = new Error(`registry '${stem}' changed on disk after the record was loaded`);
        err.code = 'STALE_AUTHORED_DATA';
        err.currentVersion = currentVersion;
        throw err;
    }
    if (loaded.storage === 'monolith') {
        const next = Object.assign({}, loaded.records, { [recordId]: record });
        atomicWriteJson(path.join(root, `${stem}.json`), next, 2);
    } else {
        const directory = path.join(root, stem);
        const existingPath = loaded.sourceById[recordId];
        const target = existingPath || path.join(
            directory,
            safeFragmentCandidate(recordId, fs.readdirSync(directory))
        );
        atomicWriteJson(target, record, 2);
    }
    return { id: recordId, version: versionToken(root, stem), storage: loaded.storage };
}

module.exports = {
    loadRegistry,
    loadRegistryFragments,
    validateRegistryMonolith,
    validateRegistryRecord,
    versionToken,
    writeRegistryRecord,
};
