 const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

// Campaign generator bridge state (one run at a time; key in memory only)
let genProc = null;
let genLog = '';
let genStatus = 'idle';
let genApiKey = null;
let genModelCache = null;

// PORT env override lets a second instance (e.g. preview/CI tooling) run
// alongside a developer's own server on the default 8080.
const PORT = parseInt(process.env.PORT, 10) || 8080;
const GAME_PORT = 8081;
const PROJECT_DIR = path.resolve(__dirname, '../..');
// Single manifest of database files exposed to the editor. Keep in sync with
// DATA_FILES in engine/server.lua.
const DATA_FILES = [
    'actors', 'elements', 'events', 'items', 'maps', 'quests', 'shops',
    'sounds', 'terms', 'actionSequences', 'system', 'commonEvents',
    'skills', 'passives', 'states', 'roles', 'engine', 'flows', 'scenes', 'animations'
];
// Override with the LOVE_PATH environment variable if LÖVE lives elsewhere
const LOVE_EXE = process.env.LOVE_PATH || 'C:\\Program Files\\LOVE\\love.exe';

// Stale-save guard: a per-file version token (mtime + size). /data hands the
// tokens to the editor inside the payload; /save rejects with 409 when a file
// changed on disk after the editor loaded, instead of silently overwriting
// commits made while the editor was open.
const fileVersion = (filename) => {
    try {
        const st = fs.statSync(path.join(PROJECT_DIR, 'data', filename));
        return `${Math.floor(st.mtimeMs)}:${st.size}`;
    } catch (e) {
        return null;
    }
};

const allFileVersions = () => {
    const versions = {};
    DATA_FILES.forEach(name => {
        versions[name] = fileVersion(`${name}.json`);
    });
    return versions;
};

// E5: console-capable LOVE binary for the headless scene preview. On
// Windows only lovec.exe attaches a console, so stdout capture needs it;
// fall back to LOVE_EXE when no lovec sibling exists.
const previewExe = (() => {
    const lovec = LOVE_EXE.replace(/love\.exe$/i, 'lovec.exe');
    try {
        if (lovec !== LOVE_EXE && fs.existsSync(lovec)) return lovec;
    } catch (e) { /* fall through */ }
    return LOVE_EXE;
})();

const server = http.createServer((req, res) => {
    // Enable CORS
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }

    let requestPath = req.url === '/' ? '/index.html' : req.url;
    requestPath = requestPath.split('?')[0];
    const decodedUrl = decodeURIComponent(requestPath);
    const relativePath = decodedUrl.replace(/^[\/\\]/, '');
    const safePath = path.normalize(relativePath).replace(/^(\.\.[\/\\])+/, '');
    const isAsset = relativePath.startsWith('assets');
    const baseDir = isAsset ? PROJECT_DIR : __dirname;
    const filePath = path.join(baseDir, safePath);

    if (req.method === 'GET' && fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
        console.log(`GET ${req.url} -> ${filePath} [FOUND]`);
        const ext = path.extname(filePath).toLowerCase();
        let contentType = 'text/html';
        if (ext === '.js') contentType = 'text/javascript';
        else if (ext === '.css') contentType = 'text/css';
        else if (ext === '.png') contentType = 'image/png';
        else if (ext === '.jpg' || ext === '.jpeg') contentType = 'image/jpeg';
        else if (ext === '.json') contentType = 'application/json';
        else if (ext === '.ttf') contentType = 'font/ttf';
        else if (ext === '.otf') contentType = 'font/otf';

        fs.readFile(filePath, (err, content) => {
            if (err) {
                res.writeHead(500, { 'Content-Type': 'text/plain' });
                res.end('Error loading asset');
            } else {
                res.writeHead(200, { 'Content-Type': contentType });
                res.end(content);
            }
        });
        return;
    }
    
    if (req.method === 'GET' && req.url === '/data') {
        const getFileContents = (filename) => {
            try {
                const filePath = path.join(PROJECT_DIR, 'data', filename);
                return JSON.parse(fs.readFileSync(filePath, 'utf8'));
            } catch (e) {
                return null;
            }
        };
 
        const data = {};
        DATA_FILES.forEach(name => {
            data[name] = getFileContents(`${name}.json`);
        });
        // The editor posts the whole payload back on /save, so the tokens
        // round-trip without any bookkeeping on the client.
        data._fileVersions = allFileVersions();

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
    } else if (req.method === 'GET' && req.url.startsWith('/api/assets')) {
        const parsedUrl = new URL(req.url, 'http://127.0.0.1:8080');
        const subDir = parsedUrl.searchParams.get('dir') || 'sprites';
        const safeSubDir = path.normalize(subDir).replace(/^(\.\.[\/\\])+/, '');
        const assetsDir = path.join(PROJECT_DIR, 'assets', safeSubDir);
        
        if (fs.existsSync(assetsDir) && fs.statSync(assetsDir).isDirectory()) {
            fs.readdir(assetsDir, (err, files) => {
                if (err) {
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: err.message }));
                } else {
                    const result = {
                        directories: [],
                        files: []
                    };
                    
                    try {
                        const parentFiles = fs.readdirSync(path.join(PROJECT_DIR, 'assets'));
                        result.directories = parentFiles.filter(f => {
                            return fs.statSync(path.join(PROJECT_DIR, 'assets', f)).isDirectory();
                        });
                    } catch(e) {}

                    files.forEach(f => {
                        try {
                            const stat = fs.statSync(path.join(assetsDir, f));
                            if (stat.isFile() && /\.(png|jpe?g|gif|webp)$/i.test(f)) {
                                result.files.push(`assets/${safeSubDir}/${f}`);
                            }
                        } catch(e) {}
                    });
                    
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify(result));
                }
            });
        } else {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Invalid directory' }));
        }
    } else if (req.method === 'GET' && req.url === '/api/fonts') {
        // Font picker choices, read straight off disk so dropping a new
        // .ttf/.otf into assets/fonts/ is the only step needed — no editor
        // code change. "Lucida" is prepended as the pseudo-entry with no
        // file, mirroring presentation/ui.lua's built-in-font fallback.
        const fontsDir = path.join(PROJECT_DIR, 'assets', 'fonts');
        let names = [];
        try {
            names = fs.readdirSync(fontsDir)
                .filter(f => /\.(ttf|otf)$/i.test(f))
                .map(f => f.replace(/\.(ttf|otf)$/i, ''))
                .sort((a, b) => a.localeCompare(b));
        } catch (e) { /* no fonts dir yet — just Lucida */ }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ fonts: ['Lucida', ...names] }));
    } else if (req.method === 'GET' && req.url === '/api/templates/scenes') {
        // E4: scene template registry — read-only JSON files, one per
        // template, each a scenes.json entry shape (minus id) plus a
        // _template { label, description } metadata block. Adding a preset
        // means dropping a file here; nothing else changes.
        const tplDir = path.join(__dirname, 'templates', 'scenes');
        const templates = [];
        if (fs.existsSync(tplDir) && fs.statSync(tplDir).isDirectory()) {
            fs.readdirSync(tplDir).forEach(f => {
                if (!f.endsWith('.json')) return;
                try {
                    templates.push(JSON.parse(fs.readFileSync(path.join(tplDir, f), 'utf8')));
                } catch (e) {
                    console.warn(`Skipping unparsable scene template ${f}: ${e.message}`);
                }
            });
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(templates));
    } else if (req.method === 'GET' && req.url.startsWith('/preview-scene')) {
        // E5: invoke the engine's headless preview against the SAVED data
        // files and return the materialized window state. The preview
        // reflects the last save, not unsaved editor state — the UI states
        // that caveat. Failures are structured JSON (the canvas renders
        // them), never a 500 that kills the tab.
        const parsedUrl = new URL(req.url, 'http://127.0.0.1:8080');
        const sceneId = parsedUrl.searchParams.get('id');
        console.log(`[preview-scene] handler invoked — req.url="${req.url}" sceneId="${sceneId}"`);
        const fail = (msg) => {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: msg }));
        };
        if (!sceneId || !/^[\w-]+$/.test(sceneId)) return fail('missing or invalid scene id');
        console.log(`[preview-scene] previewExe="${previewExe}" exists=${fs.existsSync(previewExe)}`);
        if (!fs.existsSync(previewExe)) return fail('preview unavailable — LOVE not found at ' + previewExe + ' (set LOVE_PATH)');
        // Argument list form (no shell): sceneId can't be used for injection.
        const { execFile } = require('child_process');
        execFile(previewExe, ['.', 'preview-scene', sceneId], {
            cwd: PROJECT_DIR,
            timeout: 15000,
            windowsHide: true,
            maxBuffer: 4 * 1024 * 1024
        }, (err, stdout) => {
            const text = String(stdout || '');
            const begin = text.indexOf('PREVIEW BEGIN');
            const end = text.indexOf('PREVIEW END');
            if (begin === -1 || end === -1 || end < begin) {
                return fail('preview produced no output' + (err ? ' (' + err.message + ')' : ''));
            }
            const jsonText = text.slice(begin + 'PREVIEW BEGIN'.length, end).trim();
            try {
                JSON.parse(jsonText); // validate before relaying
            } catch (e) {
                return fail('preview output was not valid JSON: ' + e.message);
            }
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(jsonText);
        });
    } else if (req.method === 'POST' && req.url === '/preview-window') {
        // E12: invoke the engine's headless SINGLE-WINDOW preview against
        // the SAVED windowLayout registry (same staleness caveat as
        // /preview-scene: reflects the last save). POST because the mock
        // spec (list source, sample text, sibling windows for sel()) can
        // be nontrivially sized — a GET query string would be fragile.
        // Body: { id: "windowId", mock: { ...mockSpec, see main.lua
        // runPreviewWindow } }. Failures are structured JSON, never a 500.
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            const fail = (msg) => {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: msg }));
            };
            let parsed;
            try {
                parsed = JSON.parse(body || '{}');
            } catch (e) {
                return fail('request body was not valid JSON: ' + e.message);
            }
            const windowId = parsed.id;
            if (!windowId || !/^[\w-]+$/.test(windowId)) return fail('missing or invalid window id');
            if (!fs.existsSync(previewExe)) return fail('preview unavailable — LOVE not found at ' + previewExe + ' (set LOVE_PATH)');

            let mockJson;
            try {
                mockJson = JSON.stringify(parsed.mock || {});
            } catch (e) {
                return fail('mock spec could not be serialized: ' + e.message);
            }

            // Argument list form (no shell): mockJson can't be used for
            // injection regardless of its content.
            const { execFile } = require('child_process');
            execFile(previewExe, ['.', 'preview-window', windowId, mockJson], {
                cwd: PROJECT_DIR,
                timeout: 15000,
                windowsHide: true,
                maxBuffer: 4 * 1024 * 1024
            }, (err, stdout) => {
                const text = String(stdout || '');
                const begin = text.indexOf('PREVIEW BEGIN');
                const end = text.indexOf('PREVIEW END');
                if (begin === -1 || end === -1 || end < begin) {
                    return fail('preview produced no output' + (err ? ' (' + err.message + ')' : ''));
                }
                const jsonText = text.slice(begin + 'PREVIEW BEGIN'.length, end).trim();
                try {
                    JSON.parse(jsonText); // validate before relaying
                } catch (e) {
                    return fail('preview output was not valid JSON: ' + e.message);
                }
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(jsonText);
            });
        });
    } else if (req.method === 'POST' && req.url === '/preview-anim') {
        // A3: invoke the engine's headless preview for animations.
        // Body: { id: "animId", sprite: "spritePath", data: { ... } }.
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            const fail = (msg) => {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: msg }));
            };
            let parsed;
            try {
                parsed = JSON.parse(body || '{}');
            } catch (e) {
                return fail('request body was not valid JSON: ' + e.message);
            }
            const animId = parsed.id;
            const spritePath = parsed.sprite || 'assets/smallBattlers/pixie.png';
            if (!animId) return fail('missing animation id');
            if (!fs.existsSync(previewExe)) return fail('preview unavailable — LOVE not found at ' + previewExe + ' (set LOVE_PATH)');

            let mockJson;
            try {
                mockJson = JSON.stringify(parsed.data || {});
            } catch (e) {
                return fail('animation data could not be serialized: ' + e.message);
            }

            const { execFile } = require('child_process');
            execFile(previewExe, ['.', 'preview-anim', animId, mockJson, spritePath], {
                cwd: PROJECT_DIR,
                timeout: 15000,
                windowsHide: true,
                maxBuffer: 4 * 1024 * 1024
            }, (err, stdout) => {
                const text = String(stdout || '');
                const begin = text.indexOf('PREVIEW BEGIN');
                const end = text.indexOf('PREVIEW END');
                if (begin === -1 || end === -1 || end < begin) {
                    return fail('preview produced no output' + (err ? ' (' + err.message + ')' : ''));
                }
                const jsonText = text.slice(begin + 'PREVIEW BEGIN'.length, end).trim();
                try {
                    JSON.parse(jsonText); // validate before relaying
                } catch (e) {
                    return fail('preview output was not valid JSON: ' + e.message);
                }
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(jsonText);
            });
        });
    } else if (req.method === 'GET' && req.url.startsWith('/preview-font')) {
        // Font picker preview: invokes the engine's real ui.drawPanel +
        // ui.drawString path with a candidate font/size, never touching
        // data/system.json — so the editor shows exactly what the engine
        // will render instead of a browser-side approximation.
        const parsedUrl = new URL(req.url, 'http://127.0.0.1:8080');
        const fontName = parsedUrl.searchParams.get('name') || '';
        const fontSize = parsedUrl.searchParams.get('size') || '8';
        const fail = (msg) => {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: msg }));
        };
        if (!/^[\w-]*$/.test(fontName)) return fail('invalid font name');
        if (!/^\d+$/.test(fontSize)) return fail('invalid font size');
        if (!fs.existsSync(previewExe)) return fail('preview unavailable — LOVE not found at ' + previewExe + ' (set LOVE_PATH)');
        const { execFile } = require('child_process');
        execFile(previewExe, ['.', 'preview-font', fontName, fontSize], {
            cwd: PROJECT_DIR,
            timeout: 15000,
            windowsHide: true,
            maxBuffer: 4 * 1024 * 1024
        }, (err, stdout) => {
            const text = String(stdout || '');
            const begin = text.indexOf('PREVIEW BEGIN');
            const end = text.indexOf('PREVIEW END');
            if (begin === -1 || end === -1 || end < begin) {
                return fail('preview produced no output' + (err ? ' (' + err.message + ')' : ''));
            }
            const jsonText = text.slice(begin + 'PREVIEW BEGIN'.length, end).trim();
            try {
                JSON.parse(jsonText);
            } catch (e) {
                return fail('preview output was not valid JSON: ' + e.message);
            }
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(jsonText);
        });
    } else if (req.method === 'POST' && req.url === '/save') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            try {
                const payload = JSON.parse(body);

                // Stale-save guard: refuse the whole save if any file the
                // payload would write changed on disk since the editor loaded
                // its tokens (git checkout, another editor, a commit...).
                const clientVersions = payload._fileVersions;
                if (clientVersions && typeof clientVersions === 'object') {
                    const stale = DATA_FILES.filter(name =>
                        payload[name] &&
                        clientVersions[name] !== undefined &&
                        clientVersions[name] !== null &&
                        clientVersions[name] !== fileVersion(`${name}.json`)
                    );
                    if (stale.length > 0) {
                        console.warn(`SAVE REJECTED (stale): ${stale.join(', ')} changed on disk since the editor loaded`);
                        res.writeHead(409, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({
                            success: false,
                            staleFiles: stale,
                            message: `Save blocked: ${stale.map(n => n + '.json').join(', ')} changed on disk after the editor loaded. Reload the editor (browser refresh) to pick up the new data, or your save would overwrite it.`
                        }));
                        return;
                    }
                }

                // Shape guard: unlike /preview-scene, /preview-window, and
                // /preview-font (which regex-validate their inputs), this was
                // the direct write path to every data file the game loads at
                // runtime with no check beyond payload[name] truthiness. A
                // client bug that leaves e.g. a list field as the wrong type
                // would silently overwrite data/actors.json with malformed
                // data. Refuse to flip a file's top-level array-vs-object
                // shape, checked for every file BEFORE any writes happen so a
                // bad payload can't leave a partial save on disk.
                const shapeMismatches = [];
                DATA_FILES.forEach(name => {
                    const content = payload[name];
                    if (content === undefined || content === null) return;
                    const filePath = path.join(PROJECT_DIR, 'data', `${name}.json`);
                    let existing;
                    try {
                        existing = JSON.parse(fs.readFileSync(filePath, 'utf8'));
                    } catch (e) {
                        return; // no existing file (or unparseable) — nothing to compare against
                    }
                    if (Array.isArray(existing) !== Array.isArray(content)) {
                        shapeMismatches.push(`${name}.json (expected ${Array.isArray(existing) ? 'an array' : 'an object'}, got ${Array.isArray(content) ? 'an array' : 'an object'})`);
                    }
                });
                if (shapeMismatches.length > 0) {
                    throw new Error(`Save blocked: payload shape doesn't match the file on disk for ${shapeMismatches.join(', ')}.`);
                }

                const saveFile = (filename, content) => {
                    if (content) {
                        const filePath = path.join(PROJECT_DIR, 'data', filename);
                        fs.writeFileSync(filePath, JSON.stringify(content, null, 2), 'utf8');
                    }
                };

                DATA_FILES.forEach(name => {
                    saveFile(`${name}.json`, payload[name]);
                });

                // Notify Love2D game to reload if it is running
                const notifyReq = http.request({
                    hostname: '127.0.0.1',
                    port: GAME_PORT,
                    path: '/reload',
                    method: 'GET',
                    timeout: 500
                }, (notifyRes) => {});
                notifyReq.on('error', (err) => {
                    // Ignore errors if game is not running
                });
                notifyReq.end();

                res.writeHead(200, { 'Content-Type': 'application/json' });
                // Fresh tokens so the editor's next save validates against
                // the files it just wrote.
                res.end(JSON.stringify({ success: true, message: 'Saved successfully!', versions: allFileVersions() }));
            } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: err.message }));
            }
        });
    } else if (req.method === 'GET' && req.url === '/validate') {
        // Runs the engine's own validator (`lovec . validate`) against the
        // SAVED data files and relays its verdict. One validator, zero
        // duplicated schema: the editor surfaces exactly what the game
        // would refuse to load. Reflects the last save, like the previews.
        const respond = (payload) => {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(payload));
        };
        if (!fs.existsSync(previewExe)) {
            return respond({ ok: false, problems: ['validation unavailable — LOVE not found at ' + previewExe + ' (set LOVE_PATH)'] });
        }
        const { execFile } = require('child_process');
        execFile(previewExe, ['.', 'validate'], {
            cwd: PROJECT_DIR,
            timeout: 60000,
            windowsHide: true,
            maxBuffer: 4 * 1024 * 1024
        }, (err, stdout) => {
            const text = String(stdout || '');
            if (text.includes('VALIDATE OK')) return respond({ ok: true, problems: [] });
            const idx = text.indexOf('VALIDATE FAIL:');
            const problems = idx >= 0
                ? text.slice(idx + 'VALIDATE FAIL:'.length).trim().split('\n').map(l => l.trim()).filter(Boolean)
                : ['validator produced no verdict' + (err ? ' (' + err.message + ')' : '')];
            respond({ ok: false, problems });
        });
    } else if (req.method === 'POST' && req.url === '/play') {
        const loveCmd = `"${LOVE_EXE}" .`;
        exec(loveCmd, { cwd: PROJECT_DIR }, (err, stdout, stderr) => {
            if (err) {
                console.error(`Failed to launch Love2D: ${err}`);
            }
        });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: 'Game launched!' }));
    // ------------------------------------------------------------------
    // Campaign generator bridge (tools/campaign-gen): the editor's
    // Generator window drives one gen.js child process at a time and
    // polls its buffered log. The API key is held in server memory only
    // (env var preferred; a key POSTed from the UI is never written to
    // disk) and passed to the child via its environment.
    // ------------------------------------------------------------------
    } else if (req.method === 'POST' && req.url === '/campaign-gen/start') {
        let body = '';
        req.on('data', c => { body += c; });
        req.on('end', () => {
            if (genProc) {
                res.writeHead(409, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: 'A generation run is already in progress.' }));
                return;
            }
            let p;
            try { p = JSON.parse(body); } catch (e) { p = null; }
            if (!p || !p.name || !/^[a-z0-9_]+$/.test(p.name) || !p.pitch) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: 'Need a snake_case name and a pitch.' }));
                return;
            }
            const apiKey = p.apiKey || process.env.OPENROUTER_API_KEY || genApiKey;
            if (!apiKey) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: 'No API key: set OPENROUTER_API_KEY or supply one.' }));
                return;
            }
            if (p.apiKey) genApiKey = p.apiKey; // session memory only
            const { spawn } = require('child_process');
            const args = [path.join(PROJECT_DIR, 'tools', 'campaign-gen', 'gen.js'), '--name', p.name];
            if (p.stage) args.push('--stage', p.stage);
            if (p.resume) args.push('--resume');
            args.push(p.pitch);
            genLog = '';
            genStatus = 'running';
            genProc = spawn(process.execPath, args, {
                cwd: PROJECT_DIR,
                env: Object.assign({}, process.env, {
                    OPENROUTER_API_KEY: apiKey,
                    CAMPAIGN_GEN_MODELS: JSON.stringify(p.models || {}),
                }),
            });
            genProc.stdout.on('data', d => { genLog += d.toString(); if (genLog.length > 2000000) genLog = genLog.slice(-1500000); });
            genProc.stderr.on('data', d => { genLog += d.toString(); });
            genProc.on('exit', code => {
                genStatus = code === 0 ? 'success' : 'failed';
                genProc = null;
            });
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: true }));
        });
    } else if (req.method === 'GET' && req.url.startsWith('/campaign-gen/status')) {
        const from = parseInt(new URL(req.url, 'http://x').searchParams.get('from') || '0', 10) || 0;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: genStatus, len: genLog.length, chunk: genLog.slice(from) }));
    } else if (req.method === 'POST' && req.url === '/campaign-gen/cancel') {
        if (genProc) { genProc.kill(); genStatus = 'cancelled'; }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true }));
    } else if (req.method === 'GET' && req.url === '/campaign-gen/models') {
        // Public OpenRouter catalogue, cached for the session; trimmed to
        // what the picker needs (id, name, prompt/completion pricing).
        if (genModelCache) {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(genModelCache);
        } else {
            fetch('https://openrouter.ai/api/v1/models').then(r => r.json()).then(j => {
                const trimmed = (j.data || []).map(m => ({
                    id: m.id, name: m.name,
                    promptPrice: m.pricing && m.pricing.prompt,
                    completionPrice: m.pricing && m.pricing.completion,
                }));
                genModelCache = JSON.stringify(trimmed);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(genModelCache);
            }).catch(e => {
                res.writeHead(502, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: String(e) }));
            });
        }
    } else if (req.method === 'GET' && req.url === '/campaign-gen/config') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(fs.readFileSync(path.join(PROJECT_DIR, 'tools', 'campaign-gen', 'config.json'), 'utf8'));
    } else if (req.method === 'POST' && req.url === '/campaign-gen/activate') {
        let body = '';
        req.on('data', c => { body += c; });
        req.on('end', () => {
            try {
                const p = JSON.parse(body);
                if (p.name && /^[a-z0-9_]+$/.test(p.name)) {
                    fs.writeFileSync(path.join(PROJECT_DIR, 'campaign.json'),
                        JSON.stringify({ active: p.name }, null, 2));
                } else {
                    // No name = revert to the default campaign (data/).
                    const ptr = path.join(PROJECT_DIR, 'campaign.json');
                    if (fs.existsSync(ptr)) fs.unlinkSync(ptr);
                }
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true }));
            } catch (e) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: String(e) }));
            }
        });
    } else if (req.method === 'POST' && req.url === '/play-test-battle') {
        const loveCmd = `"${LOVE_EXE}" . test-battle`;
        exec(loveCmd, { cwd: PROJECT_DIR }, (err, stdout, stderr) => {
            if (err) {
                console.error(`Failed to launch Love2D in test battle: ${err}`);
            }
        });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: 'Test battle launched!' }));
    } else if (req.method === 'GET' && req.url.startsWith('/ping')) {
        const parsedUrl = new URL(req.url, 'http://127.0.0.1:8080');
        const scene = parsedUrl.searchParams.get('scene') || 'unknown';
        console.log(`\n[GAME STATUS PING] Game connected! Scene: ${scene.toUpperCase()}`);
        console.log(`[GAME STATUS PING] Build checks: Input Cooldown & Repeat Filters are fully active.\n`);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true }));
    } else if (req.method === 'GET' && req.url === '/api/editor-themes') {
        try {
            const filePath = path.join(__dirname, 'themes.json');
            if (fs.existsSync(filePath)) {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(fs.readFileSync(filePath, 'utf8'));
            } else {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify([]));
            }
        } catch (e) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: e.message }));
        }
    } else if (req.method === 'POST' && req.url === '/api/editor-themes') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            try {
                const themes = JSON.parse(body);
                const filePath = path.join(__dirname, 'themes.json');
                fs.writeFileSync(filePath, JSON.stringify(themes, null, 2), 'utf8');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true }));
            } catch (e) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: e.message }));
            }
        });
    } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found');
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`Editor server running at http://127.0.0.1:${PORT}`);
});
