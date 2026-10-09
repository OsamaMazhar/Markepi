// node creative-render.mjs header search — renders creative.html?s=<kind> at its exact App Store size
import {chromium} from 'playwright'; import http from 'http'; import fs from 'fs'; import path from 'path';
const root=process.cwd(); const types={'.html':'text/html','.json':'application/json','.png':'image/png','.jpg':'image/jpeg'};
const srv=http.createServer((q,s)=>{const p=path.join(root,decodeURIComponent(q.url.split('?')[0])); fs.readFile(p,(e,d)=>{if(e){s.writeHead(404);s.end();return;} s.writeHead(200,{'Content-Type':types[path.extname(p)]||'application/octet-stream'}); s.end(d);});}).listen(8768);
const b=await chromium.launch();
for (const k of process.argv.slice(2)) {
  const H=k==='header'?1646:2560; const p=await b.newPage({viewport:{width:3840,height:H}});
  p.on('pageerror',e=>console.log('err:',e.message));
  await p.goto(`http://localhost:8768/creative.html?s=${k}`); await p.waitForFunction(()=>window.DONE,null,{timeout:60000});
  const t=await p.title(); if(t.startsWith('ERR')) console.log(k,t);
  await p.screenshot({path:`out/creative-${k}.png`}); console.log('rendered',k); await p.close();
}
await b.close(); srv.close();
