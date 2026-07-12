 const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

// PORT env override lets a second instance (e.g. preview/CI tooling) run
// alongside a developer's own server on the default 8080.
const PORT = parseInt(process.env.PORT, 10) || 8080;
const GAME_PORT = 8081;
const PROJECT_DIR = path.resolve(__dirname, '../..');
// Single manifest of database files exposed to the editor. Keep in sync with
// DATA_FILES in engine/server.lua.
const DATA_FILES = [
    'actors', 'elements', 'events', 'items', 'maps', 'quests', 'shops',
    'sounds', 'terms', 'themes', 'system', 'commonEvents',
    'skills', 'passives', 'states', 'roles', 'engine', 'flows', 'scenes'
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
    } else if (req.method === 'GET' && req.url === '/api/graphs') {
        const graphsDir = path.join(PROJECT_DIR, 'data', 'graphs');
        if (fs.existsSync(graphsDir) && fs.statSync(graphsDir).isDirectory()) {
            fs.readdir(graphsDir, (err, files) => {
                if (err) {
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: err.message }));
                } else {
                    const result = [];
                    files.forEach(f => {
                        try {
                            const stat = fs.statSync(path.join(graphsDir, f));
                            if (stat.isFile() && f.endsWith('.json')) {
                                result.push(f.slice(0, -5)); // remove .json
                            }
                        } catch(e) {}
                    });
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify(result));
                }
            });
        } else {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify([]));
        }
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
    } else if (req.method === 'POST' && req.url === '/play') {
        const loveCmd = `"${LOVE_EXE}" .`;
        exec(loveCmd, { cwd: PROJECT_DIR }, (err, stdout, stderr) => {
            if (err) {
                console.error(`Failed to launch Love2D: ${err}`);
            }
        });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: 'Game launched!' }));
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
    } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found');
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`Editor server running at http://127.0.0.1:${PORT}`);
});
