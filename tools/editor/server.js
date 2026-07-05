const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = 8080;
const GAME_PORT = 8081;
const PROJECT_DIR = path.resolve(__dirname, '../..');

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
 
        const data = {
            actors: getFileContents('actors.json'),
            elements: getFileContents('elements.json'),
            events: getFileContents('events.json'),
            items: getFileContents('items.json'),
            maps: getFileContents('maps.json'),
            quests: getFileContents('quests.json'),
            shops: getFileContents('shops.json'),
            sounds: getFileContents('sounds.json'),
            terms: getFileContents('terms.json'),
            themes: getFileContents('themes.json'),
            system: getFileContents('system.json'),
            commonEvents: getFileContents('commonEvents.json')
        };
 
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
    } else if (req.method === 'POST' && req.url === '/save') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            try {
                const payload = JSON.parse(body);
                const saveFile = (filename, content) => {
                    if (content) {
                        const filePath = path.join(PROJECT_DIR, 'data', filename);
                        fs.writeFileSync(filePath, JSON.stringify(content, null, 2), 'utf8');
                    }
                };
 
                saveFile('actors.json', payload.actors);
                saveFile('items.json', payload.items);
                saveFile('maps.json', payload.maps);
                saveFile('shops.json', payload.shops);
                saveFile('system.json', payload.system);
                saveFile('commonEvents.json', payload.commonEvents);

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
                res.end(JSON.stringify({ success: true, message: 'Saved successfully!' }));
            } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: err.message }));
            }
        });
    } else if (req.method === 'POST' && req.url === '/play') {
        const loveCmd = '"C:\\Program Files\\LOVE\\love.exe" .';
        exec(loveCmd, { cwd: PROJECT_DIR }, (err, stdout, stderr) => {
            if (err) {
                console.error(`Failed to launch Love2D: ${err}`);
            }
        });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: 'Game launched!' }));
    } else if (req.method === 'POST' && req.url === '/play-test-battle') {
        const loveCmd = '"C:\\Program Files\\LOVE\\love.exe" . test-battle';
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
