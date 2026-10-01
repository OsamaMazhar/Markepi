import {chromium} from 'playwright'; import http from 'http'; import fs from 'fs'; import path from 'path';
const root=process.cwd(); const types={'.html':'text/html','.js':'text/javascript','.glb':'model/gltf-binary','.png':'image/png','.jpg':'image/jpeg'};
const srv=http.createServer((q,s)=>{const p=path.join(root,decodeURIComponent(q.url.split('?')[0])); fs.readFile(p,(e,d)=>{if(e){s.writeHead(404);s.end();return;} s.writeHead(200,{'Content-Type':types[path.extname(p)]||'application/octet-stream'}); s.end(d);});}).listen(8765);
const b=await chromium.launch({args:['--use-angle=metal','--enable-gpu']}); const p=await b.newPage({viewport:{width:1400,height:2900}});
p.on('console',m=>console.log('page:',m.text())); p.on('pageerror',e=>console.log('err:',e.message));
await p.goto('http://localhost:8765/phone.html'); await p.waitForFunction(()=>window.DONE,null,{timeout:60000}); console.log(await p.evaluate(()=>window.DONE));
await p.screenshot({path:'phone_raw.png',omitBackground:true}); await b.close(); srv.close();
