// Package a reviewed external web snapshot for the existing offline iOS viewer.
// npm ci --prefix tools/education-experience
// npm run --prefix tools/education-experience build -- /path/to/reviewed/dist
import {readFile,writeFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Script} from 'node:vm';
import {build} from 'esbuild';
import {adaptNativeRenderer,adaptNativeStories} from './viewer/renderer-adapter.mjs';

if(!process.argv[2])throw Error('Pass the reviewed website dist directory.');
const web=path.resolve(process.argv[2]);
const destination=fileURLToPath(new URL('../../apps/ios/OiDonation/Resources/Campus/',import.meta.url));
const sha=data=>createHash('sha256').update(data).digest('hex');
const sourceHTML=await readFile(path.join(web,'index.html'),'utf8');
const model=JSON.parse(await readFile(path.join(web,'assets/building-v25/model.json'),'utf8'));
let html=sourceHTML;
// Drop unused cosmic images before WebKit can preload/decode them.
html=html.replace(/<div class="night-backdrop"[^>]*><\/div>/,'')
 .replace(/<div class="space-mascot"[^>]*><img[^>]*><\/div>/,'');
const assetPaths=new Set(['assets/building-v25/model.json','assets/building-v25/pearls.bin','assets/building-v25/facades.bin','vendor/three-LICENSE.txt','assets/Pretendard-LICENSE.txt']);
for(const material of Object.values(model.materials))if(material.texture)assetPaths.add('assets/building-v25/'+material.texture);
function collectAssets(text){
 for(const match of text.matchAll(/(?:url\(\s*["']?|(?:src|href)=["'])(\.\/(?:assets|references)\/[^\s"'()<>]+)/g))assetPaths.add(match[1].slice(2));
}
for(const match of [...html.matchAll(/<link rel="stylesheet" href="([^"?]+)(?:\?[^\"]*)?">/g)]){
 const css=(await readFile(path.join(web,match[1]),'utf8')).replaceAll("url('./assets/space-earth-v2.png')",'none');collectAssets(css);
 html=html.replace(match[0],()=>'<style>'+css+'</style>');
}
collectAssets(html);collectAssets(await readFile(path.join(web,'app.js'),'utf8'));
const scripts=[...html.matchAll(/<script type="module" src="([^\"]+)"><\/script>/g)];
if(scripts.length!==2)throw Error('Inspect the reviewed website entry points before packaging.');
const viewerCSS=await readFile(new URL('./viewer/native-viewer.css',import.meta.url),'utf8');
html=html.replace('</head>',()=>'<style>'+viewerCSS+'</style>\n</head>');
const viewerEntry=fileURLToPath(new URL('./viewer/native-viewer.mjs',import.meta.url));
const bridge=`
window.prototypeDiagnostics=()=>({...window.building3DDiagnostics(),webgl:stage.dataset.renderer==='3d',capacity:model.sphereCount,depthTriangles:model.meshes.reduce((sum,m)=>sum+m.vertices/3,0),spacePearlCount:spaceScatter.count,nativePaused:window.__nativePaused===true});
window.setNativeActive=active=>{window.__nativePaused=!active;if(!active){cancelAnimationFrame(animation);animation=0;}else if(scatter!==scatterTarget&&!animation)animation=requestAnimationFrame(tick);else invalidate();};
window.webkit?.messageHandlers?.building?.postMessage({kind:'ready',...window.prototypeDiagnostics()});
`;
const result=await build({
 stdin:{contents:[`import ${JSON.stringify(viewerEntry)};`,...scripts.map(match=>`import ${JSON.stringify(match[1])};`)].join('\n'),resolveDir:web,sourcefile:'native-entry.js'},
 bundle:true,format:'iife',platform:'browser',target:'safari18',minify:true,legalComments:'inline',write:false,
 define:{'import.meta.url':'document.baseURI'},
 plugins:[{name:'native-lifecycle',setup(builder){
  builder.onLoad({filter:/scatter-stories\.js$/},async args=>({
   contents:adaptNativeStories(await readFile(args.path,'utf8')),loader:'js'
  }));
  builder.onResolve({filter:/^@education\/three$/},()=>({path:path.join(web,'vendor/three.module.js')}));
  builder.onLoad({filter:/building-3d\.js$/},async args=>{
   let source=adaptNativeRenderer(await readFile(args.path,'utf8'));
   if(!source.includes('window.building3DDiagnostics=')||!source.includes('\n}catch(error)'))throw Error('Inspect the 3D ready/error bridge.');
   source=source.replaceAll('document.hidden||!visible','document.hidden||window.__nativePaused||!visible')
    .replace('if(!visible||document.hidden)','if(!visible||document.hidden||window.__nativePaused)')
    .replace('\n}catch(error)',bridge+'\n}catch(error)')
    .replace("console.error('Building 3D load failed',error);","console.error('Building 3D load failed',error);window.webkit?.messageHandlers?.building?.postMessage({kind:'error',message:'Building asset loading failed'});");
   const index=source.indexOf('const stage=');if(index<0)throw Error('Inspect the building module wrapper.');
   return {contents:source.slice(0,index)+'\n(async()=>{\n'+source.slice(index)+'\n})();',loader:'js'};
  });
 }}]
});
const assets={};
for(const name of [...assetPaths].sort()){
 const absolute=path.resolve(web,name);
 if(!absolute.startsWith(web+path.sep))throw Error('Asset outside reviewed snapshot.');
 let data=await readFile(absolute);
 if(name.endsWith('/model.json')){
  const metadata=JSON.parse(data);metadata.sourceFile=path.basename(metadata.sourceFile??'reviewed-building.blend');
  data=Buffer.from(JSON.stringify(metadata));
 }
 const extension=path.extname(name).toLowerCase();
 // iPhoneOS runs pngcrush on .png bundle resources (CgBI). Keep standard web
 // PNG bytes untouched; the manifest still serves them with image/png MIME.
 const resource='education-light-'+sha(data).slice(0,24)+(extension==='.png'?'.bin':extension);
 const mime={'.png':'image/png','.jpg':'image/jpeg','.svg':'image/svg+xml','.woff2':'font/woff2','.json':'application/json','.bin':'application/octet-stream','.txt':'text/plain'}[extension];
 if(!mime)throw Error('Unreviewed asset type: '+name);
 await writeFile(path.join(destination,resource),data);
 assets['/'+name]={resource,mime,sha256:sha(data),bytes:data.length};
}
const manifest={version:1,revision:model.revision,sourceHTMLSHA256:sha(sourceHTML),assets};
await writeFile(path.join(destination,'education-light-assets.json'),JSON.stringify(manifest,null,2)+'\n');
for(const script of scripts)html=html.replace(script[0],'');
html=html.replace('<head>','<head>\n<base href="oi-education://bundle/">\n<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; img-src oi-education: data: blob:; font-src oi-education:; connect-src oi-education:; base-uri oi-education:; form-action \'none\'">');
const javascript=result.outputFiles[0].text.replaceAll('</script','<\\/script');
new Script(javascript,{filename:'education-experience.js'}); // Parse only; never execute the snapshot in Node.
// A replacement callback preserves literal $&, $` and $' inside bundled shaders.
html=html.replace('</body>',()=>'<script>'+javascript+'</script>\n</body>');
html=html.replace(/[\t ]+$/gm,'');
const embedded=html.match(/<script>([\s\S]*?)<\/script>/);
if(!embedded)throw Error('Missing offline script.');
new Script(embedded[1],{filename:'embedded-education-experience.js'});
await writeFile(path.join(destination,'education-district-experience.html'),html);
// Remove only content-addressed outputs from an older export; never touch map assets.
const used=new Set(Object.values(assets).map(asset=>asset.resource));
for(const name of await readdir(destination))if(/^education-light-[a-f0-9]{24}\./.test(name)&&!used.has(name)){
 const {unlink}=await import('node:fs/promises');await unlink(path.join(destination,name));
}
console.log(JSON.stringify({revision:model.revision,assets:Object.keys(assets).length,assetBytes:Object.values(assets).reduce((sum,a)=>sum+a.bytes,0),htmlBytes:Buffer.byteLength(html)}));
