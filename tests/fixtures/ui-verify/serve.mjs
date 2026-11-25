// Fixture server for the ui-verify suite. Prints "port <n>" for the main listener and "port2 <n>" for
// a second listener the suite reaches as localhost, which counts plain hits and WebSocket upgrades.
//   node serve.mjs [--build-sha <value>]
// Main listener: /, /index.html, /hostile.html, /offsite.html, /otherport.html (reaches the second listener by the
// allowed host name on its other port), /wall.html; /hang never answers;
// /meta.html carries a build id with a pipe and a backtick; /nobody.html removes its own body; /many.html requests 61 distinct hosts off the list;
// /leave.html links to the second listener as localhost; /redirect answers 302 to the second listener as
// localhost, /redirect-port answers 302 to it by the allowed name on its other port, /redirect-ok answers 302 to /.
// /flaky?key=K answers "Error 500" on its first hit for that key and "Saved" on every later one.
// /worker.html starts a dedicated worker (/worker.js) that opens a WebSocket to the second listener by the allowed
// host name; /post-hop.html POSTs a JSON body to /redirect-307, which answers 307 to the second listener by the
// allowed host name on its other port. /late-hop.html shows its text at once and POSTs to /redirect-307-slow, which
// waits 800 ms and then answers like /redirect-307, so the hop arrives after the page has said everything it will say.
// /shared-worker.html starts a SharedWorker (/shared-worker.js) that fetches /redirect-307 by the allowed host name.
// Second listener: GET /count answers {"hits":N,"upgrades":N} and is not itself counted; GET /seen answers
// {"requests":[{"method":M,"body":B}]} for every counted plain hit, in order, and is not itself counted.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PAGES = { '/': 'index.html', '/index.html': 'index.html', '/hostile.html': 'hostile.html', '/offsite.html': 'offsite.html', '/wall.html': 'wall.html', '/otherport.html': 'otherport.html', '/leave.html': 'leave.html', '/many.html': 'many.html', '/nobody.html': 'nobody.html', '/meta.html': 'meta.html', '/worker.html': 'worker.html', '/post-hop.html': 'post-hop.html', '/late-hop.html': 'late-hop.html', '/shared-worker.html': 'shared-worker.html' };
const args = process.argv.slice(2);
const buildSha = args[0] === '--build-sha' ? args[1] : '';

const counts = { hits: 0, upgrades: 0 };
const seen = [];
const flakyHits = new Map();
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
  if (pathname === '/flaky') {
    const key = new URL(req.url, 'http://fixture').searchParams.get('key') ?? '';
    const hits = flakyHits.get(key) ?? 0;
    flakyHits.set(key, hits + 1);
    send(res, 200, 'text/html; charset=utf-8', `<!doctype html><title>Flaky</title><main><p>${hits === 0 ? 'Error 500' : 'Saved'}</p></main>`);
    return;
  }
  if (pathname === '/worker.js') {
    res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8', 'cache-control': 'no-store' });
    res.end(readFileSync(path.join(HERE, 'worker.js'), 'utf8'));
    return;
  }
  if (pathname === '/shared-worker.js') {
    res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8', 'cache-control': 'no-store' });
    res.end(readFileSync(path.join(HERE, 'shared-worker.js'), 'utf8'));
    return;
  }
  if (pathname === '/redirect-307' || pathname === '/redirect-307-slow') {
    setTimeout(() => {
      res.writeHead(307, { location: `http://127.0.0.1:${port2}/hop`, 'cache-control': 'no-store' });
      res.end();
    }, pathname === '/redirect-307-slow' ? 800 : 0);
    return;
  }
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
  if (pathname === '/seen') { send(res, 200, 'application/json', `${JSON.stringify({ requests: seen })}\n`); return; }
  counts.hits += 1;
  const chunks = [];
  req.on('data', (chunk) => chunks.push(chunk));
  req.on('end', () => {
    seen.push({ method: req.method, body: Buffer.concat(chunks).toString('utf8') });
    send(res, 200, 'text/plain; charset=utf-8', 'counted\n');
  });
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
