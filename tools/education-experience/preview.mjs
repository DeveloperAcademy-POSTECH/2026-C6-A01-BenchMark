// Loopback-only QA of the exact offline bundle, with the same asset allowlist.
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('../../apps/ios/OiDonation/Resources/Campus/',import.meta.url));
const server = createServer(async (request,response) => {
  try {
    const path = new URL(request.url,'http://localhost').pathname;
    if (path === '/favicon.ico') { response.writeHead(204).end(); return; }
    if (path === '/' || path === '/index.html') {
      const html = (await readFile(root+'education-district-experience.html','utf8'))
        .replace('oi-education://bundle/','/').replaceAll('oi-education:',"'self'");
      response.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'}).end(html); return;
    }
    const {assets} = JSON.parse(await readFile(root+'education-light-assets.json','utf8'));
    const asset = assets[path];
    if (!asset || !/^education-light-[a-f0-9]{24}\.[a-z0-9]+$/.test(asset.resource)) { response.writeHead(404).end(); return; }
    response.writeHead(200,{'Content-Type':asset.mime,'Cache-Control':'no-store'}).end(await readFile(root+asset.resource));
  } catch { response.writeHead(500).end('Preview unavailable'); }
});
server.listen(Number(process.argv[2] ?? 8784),'127.0.0.1',() => console.log('Local preview: http://127.0.0.1:'+server.address().port));
