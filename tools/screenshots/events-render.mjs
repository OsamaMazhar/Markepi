// node events-render.mjs [looks frames share]
// Renders events.html (events.js) as each in-app event's card (1920x1080) and detail (1080x1920) media into
// $MARKEPI_ASSETS/events/<id>-<kind>.png, flattened to RGB. Screens and exports from cap/v2, the phone from $MARKEPI_ASSETS/models.
import {chromium} from 'playwright-core'; import http from 'http'; import fs from 'fs'; import path from 'path';
import {execFileSync} from 'child_process'; import os from 'os';
const here = path.dirname(new URL(import.meta.url).pathname);
const assets = process.env.MARKEPI_ASSETS || path.join(os.homedir(), 'Projects/Markepi-Assets');
const out = path.join(assets, 'events'), roots = {'/src/': path.join(here, 'cap/v2'), '/models/': path.join(assets, 'models')};
const ids = process.argv.slice(2).length ? process.argv.slice(2) : ['looks', 'frames', 'share'];
const types = {'.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.glb': 'model/gltf-binary'};
const srv = http.createServer((q, s) => {
  const u = decodeURIComponent(q.url.split('?')[0]), r = Object.keys(roots).find(k => u.startsWith(k));
  const p = r ? path.join(roots[r], u.slice(r.length)) : path.join(here, u);
  fs.readFile(p, (e, d) => { if (e) { s.writeHead(404); s.end(); return; } s.writeHead(200, {'Content-Type': types[path.extname(p)] || 'application/octet-stream'}); s.end(d); });
}).listen(8771);
const b = await chromium.launch({channel: 'msedge'});
fs.mkdirSync(out, {recursive: true});
const made = [];
for (const id of ids) for (const k of ['card', 'detail']) {
  const p = await b.newPage({viewport: k === 'card' ? {width: 1920, height: 1080} : {width: 1080, height: 1920}});
  p.on('pageerror', e => console.log('err:', e.message));
  await p.goto(`http://localhost:8771/events.html?e=${id}&s=${k}`, {waitUntil: 'domcontentloaded', timeout: 120000});
  await p.waitForFunction(() => window.DONE, null, {timeout: 60000});
  const t = await p.title(); if (t.startsWith('ERR')) console.log(id, k, t);
  const f = path.join(out, `${id}-${k}.png`);
  await p.screenshot({path: f}); made.push(f); console.log('rendered', id, k); await p.close();
}
await b.close(); srv.close();
execFileSync('python3', ['-c', 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]: Image.open(f).convert("RGB").save(f)', ...made]);
