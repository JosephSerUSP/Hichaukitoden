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

    if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
        const filePath = path.join(__dirname, 'index.html');
        fs.readFile(filePath, 'utf8', (err, content) => {
            if (err) {
                res.writeHead(500, { 'Content-Type': 'text/plain' });
                res.end('Error loading editor');
            } else {
                res.writeHead(200, { 'Content-Type': 'text/html' });
                res.end(content);
            }
        });
    } else if (req.method === 'GET' && req.url === '/data') {
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
            system: getFileContents('system.json')
        };

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
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
    } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found');
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`Editor server running at http://127.0.0.1:${PORT}`);
});
