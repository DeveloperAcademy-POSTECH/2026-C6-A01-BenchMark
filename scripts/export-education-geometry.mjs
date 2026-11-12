#!/usr/bin/env node
// Package the shared Meshy samples and web experience for offline iOS use.
// Run the Blender exporter first, then: node scripts/export-education-geometry.mjs /path/to/site/dist
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

if(!process.argv[2])throw new Error('Pass the Sites checkout dist directory.');
const web=path.resolve(process.argv[2]);
const resources=fileURLToPath(new URL('../apps/ios/OiDonation/Resources/Campus/',import.meta.url));
const bytes=await readFile(path.join(resources,'education-district-points.bin'));
const report=JSON.parse(await readFile(path.join(resources,'education-district-geometry.json'),'utf8'));
const sha=value=>createHash('sha256').update(value).digest('hex');
if(sha(bytes)!==report.assetSHA256)throw new Error('Model metadata and asset differ. Run the Blender exporter.');
const geometrySource=await readFile(path.join(web,'geometry.js'),'utf8');
const module=await import(`data:text/javascript;base64,${Buffer.from(geometrySource).toString('base64')}`);
const model=module.buildGeometry(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength));
if(model.revision!==report.revision)throw new Error('Review the changed web model revision.');
await writeFile(path.join(web,'education-district-points.bin'),bytes);
let html=await readFile(path.join(web,'index.html'),'utf8');
const css=await readFile(path.join(web,'style.css'),'utf8');
let app=await readFile(path.join(web,'app.js'),'utf8');
app=app.replace(/^import[^\n]+\n/,'').replace('document.hidden||!inViewport','document.hidden||window.__nativePaused||!inViewport');
// Source references are small JPEGs. The 4.1 MB geometry is served from the
// single app asset by WKURLSchemeHandler, never duplicated in the HTML.
for(const name of['reference.jpg',...['front','left','right','back'].map(id=>`references/${id}.jpg`)]){
 const data='data:image/jpeg;base64,'+(await readFile(path.join(web,name))).toString('base64');
 if(name.startsWith('references/')){
  // The reference gallery uses a template literal; replace its URL with a map.
  const id=path.basename(name,'.jpg');
  app=`const nativeReference_${id}=${JSON.stringify(data)};\n`+app;
 }else app=app.replaceAll('./'+name,data);
}
app=app.replace('./references/${id}.jpg','${({front:nativeReference_front,left:nativeReference_left,right:nativeReference_right,back:nativeReference_back})[id]}');
const bridge=`\nwindow.setNativeActive=active=>{window.__nativePaused=!active;if(!active){paused=true;cancelAnimationFrame(raf);}else start();};\nwindow.webkit?.messageHandlers?.building?.postMessage({kind:'ready',webgl:!!gl,...window.prototypeDiagnostics()});\n`;
const script=`<script>(async()=>{\n${geometrySource.replace(/^export /gm,'')}\n${app}\n${bridge}})();</script>`;
html=html.replace('<link rel="stylesheet" href="./style.css">',()=>`<style>${css}</style>`);
html=html.replace(/<script type="module" src="\.\/app.js"><\/script>/,()=>script);
if(html.includes('src="./app.js"')||!html.includes('async()=>'))throw new Error('HTML bundle substitution failed');
await writeFile(path.join(resources,'education-district-experience.html'),html);
console.log(JSON.stringify({revision:report.revision,assetSHA256:sha(bytes),geometryBytes:bytes.length,htmlBytes:Buffer.byteLength(html)}));
