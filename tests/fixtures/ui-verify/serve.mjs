// Fixture server for the ui-verify suite. Prints "port <n>" for the main listener and "port2 <n>" for
// a second listener the suite reaches as localhost, which counts plain hits and WebSocket upgrades.
//   node serve.mjs [--build-sha <value>]
// Main listener: /, /index.html, /hostile.html, /offsite.html, /otherport.html (reaches the second listener by the
// allowed host name on its other port), /wall.html; /hang never answers;
// /meta.html carries a build id with a pipe and a backtick; /nobody.html removes its own body; /many.html requests 61 distinct hosts off the list;
// /leave.html links to the second listener as localhost; /redirect answers 302 to the second listener as
// localhost, /redirect-port answers 302 to it by the allowed name on its other port, /redirect-ok answers 302 to /.
// Second listener: GET /count answers {"hits":N,"upgrades":N} and is not itself counted.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PAGES = { '/': 'index.html', '/index.html': 'index.html', '/hostile.html': 'hostile.html', '/offsite.html': 'offsite.html', '/wall.html': 'wall.html', '/otherport.html': 'otherport.html', '/leave.html': 'leave.html', '/many.html': 'many.html', '/nobody.html': 'nobody.html', '/meta.html': 'meta.html' };
const args = process.argv.slice(2);
const buildSha = args[0] === '--build-sha' ? args[1] : '';

const counts = { hits: 0, upgrades: 0 };
let port2 = 0;

function send(res, status, type, body) {
  const headers = { 'content-type': type, 'cache-control': 'no-store' };
  if (buildSha) headers['x-build-sha'] = buildSha;
  res.writeHead(status, headers);
  res.end(body);
}

function readPage(name) {
  try { return readFileSync(path.join(HERE, name), 'utf8').replaceAll('__PORT2__', String(port2)); } catch { return null; }
}

const main = http.createServer((req, res) => {
  const pathname = new URL(req.url, 'http://fixture').pathname;
  if (pathname === '/hang') return;
  if (pathname === '/redirect' || pathname === '/redirect-ok' || pathname === '/redirect-port') {
    const target = { '/redirect': `http://localhost:${port2}/pixel`, '/redirect-ok': '/', '/redirect-port': `http://127.0.0.1:${port2}/pixel` }[pathname];
    res.writeHead(302, { location: target, 'cache-control': 'no-store' });
    res.end();
    return;
  }
  const file = PAGES[pathname];
  const page = file ? readPage(file) : null;
  if (page === null) { send(res, 404, 'text/plain; charset=utf-8', 'not found\n'); return; }
  send(res, 200, 'text/html; charset=utf-8', page);
});

const counter = http.createServer((req, res) => {
  const pathname = new URL(req.url, 'http://fixture').pathname;
  if (pathname === '/count') { send(res, 200, 'application/json', `${JSON.stringify(counts)}\n`); return; }
  counts.hits += 1;
  send(res, 200, 'text/plain; charset=utf-8', 'counted\n');
});

counter.on('upgrade', (req, socket) => {
  counts.upgrades += 1;
  const accept = createHash('sha1').update(`${req.headers['sec-websocket-key']}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`).digest('base64');
  socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  socket.end();
});

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}

port2 = await listen(counter);
const port = await listen(main);
console.log(`port ${port}`);
console.log(`port2 ${port2}`);
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => process.exit(0));
