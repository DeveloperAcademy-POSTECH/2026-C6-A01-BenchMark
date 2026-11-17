// Build the standalone Site using the same reviewed renderer and interactions.
import {readFile,writeFile,mkdir,rm} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {build} from 'esbuild';
import {adaptNativeRenderer,adaptNativeStories} from './viewer/renderer-adapter.mjs';
if(!process.argv[2]||!process.argv[3])throw Error('Pass reviewed source and output directories.');
const source=path.resolve(process.argv[2]),destination=path.resolve(process.argv[3]);
if(source===destination||source.startsWith(destination+path.sep))throw Error('Output must not contain the source snapshot.');
let html=(await readFile(path.join(source,'index.html'),'utf8'))
 .replace(/<div class="night-backdrop"[^>]*><\/div>/,'')
 .replace(/<div class="space-mascot"[^>]*><img[^>]*><\/div>/,'');
const model=JSON.parse(await readFile(path.join(source,'assets/building-v25/model.json'),'utf8'));
model.sourceFile=path.basename(model.sourceFile??'reviewed-building.blend');
const assets=new Set(['assets/building-v25/model.json','assets/building-v25/pearls.bin','assets/building-v25/facades.bin','vendor/three-LICENSE.txt','assets/Pretendard-LICENSE.txt']);
for(const material of Object.values(model.materials))if(material.texture)assets.add('assets/building-v25/'+material.texture);
const collect=text=>{for(const m of text.matchAll(/(?:url\(\s*["']?|(?:src|href)=["'])(\.\/(?:assets|references)\/[^\s"'()<>]+)/g))assets.add(m[1].slice(2));};
const css=[];
for(const match of html.matchAll(/<link rel="stylesheet" href="([^"?]+)(?:\?[^\"]*)?">/g)){
 const name=match[1].replace(/^\.\//,'');
 if(name.includes('..')||path.isAbsolute(name))throw Error('CSS outside reviewed source.');
 const text=(await readFile(path.join(source,name),'utf8')).replaceAll("url('./assets/space-earth-v2.png')",'none');collect(text);css.push([name,text]);
}
collect(html);collect(await readFile(path.join(source,'app.js'),'utf8'));
const scripts=[...html.matchAll(/<script type="module" src="([^\"]+)"><\/script>/g)];
if(scripts.length!==2)throw Error('Inspect standalone web entry points.');
const entry=fileURLToPath(new URL('./viewer/web-viewer.mjs',import.meta.url));
const result=await build({stdin:{contents:[`import ${JSON.stringify(entry)};`,...scripts.map(m=>`import ${JSON.stringify(m[1])};`)].join('\n'),resolveDir:source},bundle:true,format:'iife',platform:'browser',target:'safari18',minify:true,legalComments:'inline',write:false,define:{'import.meta.url':'document.baseURI'},plugins:[{name:'shared-garden-viewer',setup(builder){
 builder.onResolve({filter:/^@education\/three$/},()=>({path:path.join(source,'vendor/three.module.js')}));
 // The renderer snapshot supplies the garden. Use the repository's current
 // story modules even if that snapshot predates the current review contract.
 builder.onLoad({filter:/education-(service|card|library|web-transport|native-transport|ui)\.js$/},async args=>{
  if(path.dirname(args.path)!==source)return;
  const contents=await readFile(new URL('./shared/'+path.basename(args.path),import.meta.url),'utf8');
  return {contents,loader:'js',resolveDir:source};
 });
 builder.onLoad({filter:/scatter-stories\.js$/},async args=>({contents:adaptNativeStories(await readFile(args.path,'utf8'),{web:true}),loader:'js'}));
 builder.onLoad({filter:/building-3d\.js$/},async args=>{
  let text=adaptNativeRenderer(await readFile(args.path,'utf8'),{web:true});const i=text.indexOf('const stage=');
  if(i<0)throw Error('Inspect standalone renderer wrapper.');
  return {contents:text.slice(0,i)+'\n(async()=>{\n'+text.slice(i)+'\n})();',loader:'js'};
 });
}}]});
// Destination is a generated dist only; source and site identity stay outside it.
if(path.basename(destination)!=='dist')throw Error('Output directory must be named dist.');
await rm(destination,{recursive:true,force:true});await mkdir(destination,{recursive:true});
for(const name of [...assets].sort()){
 const file=path.resolve(source,name);if(!file.startsWith(source+path.sep))throw Error('Asset outside reviewed source.');
 const out=path.join(destination,name);await mkdir(path.dirname(out),{recursive:true});
 await writeFile(out,name==='assets/building-v25/model.json'?JSON.stringify(model):await readFile(file));
}
for(const [name,text] of css)await writeFile(path.join(destination,name),text);
await writeFile(path.join(destination,'web-viewer.css'),await readFile(new URL('./viewer/web-viewer.css',import.meta.url)));
await writeFile(path.join(destination,'viewer.js'),result.outputFiles[0].text);
for(const script of scripts)html=html.replace(script[0],'');
html=html.replace('</head>','<link rel="stylesheet" href="./web-viewer.css">\n</head>').replace('</body>','<script src="./viewer.js"></script>\n</body>');
await writeFile(path.join(destination,'index.html'),html.replace(/[\t ]+$/gm,''));
console.log(JSON.stringify({revision:model.revision,assets:assets.size,output:destination}));
