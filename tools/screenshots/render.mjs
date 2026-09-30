// node render.mjs [ids...] — renders slide.html?s=<id> to out/<id>.png at 1320x2868
import {chromium} from 'playwright'; import http from 'http'; import fs from 'fs'; import path from 'path';
const root=process.cwd(); const types={'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png','.jpg':'image/jpeg'};
const srv=http.createServer((q,s)=>{const p=path.join(root,decodeURIComponent(q.url.split('?')[0])); fs.readFile(p,(e,d)=>{if(e){s.writeHead(404);s.end();return;} s.writeHead(200,{'Content-Type':types[path.extname(p)]||'application/octet-stream'}); s.end(d);});}).listen(8766);
fs.mkdirSync('out',{recursive:true});
const IPADIO=process.env.IPAD==='1';
const b=await chromium.launch(); const p=await b.newPage({viewport:IPADIO?{width:2064,height:2752}:{width:1320,height:2868}});
p.on('pageerror',e=>console.log('err:',e.message));
for (const id of (process.argv.slice(2).length?process.argv.slice(2):['01','02b','02c','03','04b','04c','05b','05c','06','07c','08c'])) {
  await p.goto(`http://localhost:8766/slide.html?s=${id}${IPADIO?'&d=i':''}`); await p.waitForFunction(()=>window.DONE,null,{timeout:60000});
  const t=await p.title(); if(t.startsWith('ERR')) console.log(id,t);
  await p.screenshot({path:`out/${id}.png`}); console.log('rendered',id);
}
await b.close(); srv.close();
