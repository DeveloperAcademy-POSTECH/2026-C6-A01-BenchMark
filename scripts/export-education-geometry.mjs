#!/usr/bin/env node
// Import the reviewed web surface into the native map and offline detail viewer.
// node scripts/export-education-geometry.mjs /path/to/site/dist
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

if(!process.argv[2])throw new Error('Pass the reviewed Sites dist directory.');
const web=path.resolve(process.argv[2]);
const resources=fileURLToPath(new URL('../apps/ios/OiDonation/Resources/Campus/',import.meta.url));
const bytes=await readFile(path.join(web,'education-district-points.bin'));
const report=JSON.parse(await readFile(path.join(web,'education-grid.json'),'utf8'));
const sha=value=>createHash('sha256').update(value).digest('hex');
if(sha(bytes)!==report.assetSHA256)throw new Error('Web model metadata and asset differ.');
const counts=(await readFile(path.join(web,'education-counts.js'),'utf8')).replace(/^export /gm,'');
const geometrySource=(await readFile(path.join(web,'geometry.js'),'utf8'))
 .replace(/^import[^\n]+\n/gm,'').replace(/^export \{[^\n]+\n/gm,'').replaceAll('import.meta.url','globalThis.location.href');
const module=await import(`data:text/javascript;base64,${Buffer.from(counts+'\n'+geometrySource).toString('base64')}`);
const model=module.buildGeometry(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength));
if(model.revision!==report.revision)throw new Error('Web model revision mismatch.');
let html=await readFile(path.join(web,'index.html'),'utf8');
const css=await readFile(path.join(web,'style.css'),'utf8');
let app=(await readFile(path.join(web,'app.js'),'utf8')).replace(/^import[^\n]+\n/,'')
 .replace('document.hidden||!inViewport','document.hidden||window.__nativePaused||!inViewport');
// Small reference JPEGs are embedded once; binary geometry stays in one asset.
const temp=await mkdtemp(path.join(tmpdir(),'oi-education-references-'));
const references={};
try{
 for(const id of['front','left','right','back']){
  const output=path.join(temp,id+'.jpg');
  execFileSync('/usr/bin/sips',['-Z','1024','-s','format','jpeg','-s','formatOptions','76',path.join(web,'references',id+'.png'),'--out',output],{stdio:'ignore'});
  references[id]='data:image/jpeg;base64,'+(await readFile(output)).toString('base64');
 }
}finally{await rm(temp,{recursive:true,force:true});}
app=app.replace('src="./references/front.png"','src="\'+nativeReferences.front+\'"')
 .replace('./references/${id}.png','${nativeReferences[id]}');
const bridge=`\nwindow.setNativeActive=active=>{window.__nativePaused=!active;if(!active){paused=true;cancelAnimationFrame(raf);}else start();};\nwindow.webkit?.messageHandlers?.building?.postMessage({kind:'ready',webgl:!!gl,...window.prototypeDiagnostics()});\n`;
const script=`<script>(async()=>{\nconst nativeReferences=${JSON.stringify(references)};\n${counts}\n${geometrySource.replace(/^export /gm,'')}\n${app}\n${bridge}})();</script>`;
html=html.replace('<link rel="stylesheet" href="./style.css">',()=>`<style>${css}</style>`)
 .replace(/<a class="compare-link"[^>]+>[^<]+<\/a>/,'')
 .replace(/<script type="module" src="\.\/app.js(?:\?[^\"]*)?"><\/script>/,()=>script);
if(html.includes('src="./app.js')||!html.includes('async()=>'))throw new Error('HTML bundle substitution failed');
// Native source is the canonical placement. Fail rather than silently re-scale it.
const site=await readFile(fileURLToPath(new URL('../apps/ios/OiDonation/Features/Campus/Scene/CampusEducationSite.swift',import.meta.url)),'utf8');
const mapScale=Number(site.match(/static let scale: Float = ([\d.]+)/)?.[1]);
const center=site.match(/static let center = SIMD3<Float>\(([^)]+)\)/)?.[1].split(',').map(Number);
const anchor=site.match(/static let bridgeAnchor = SIMD3<Float>\(([^)]+)\)/)?.[1].split(',').map(Number);
if(!mapScale||center?.length!==3||anchor?.length!==3)throw new Error('Inspect native placement constants.');
const metadata={...report,shellVertexCount:bytes.readUInt32LE(12),groundOffset:bytes.readFloatLE(16),byteCount:bytes.length,
 bridgeAnchor:anchor,lod:{mapFar:report.lodCounts[0],mapNear:report.lodCounts[1],webMobile:report.lodCounts[1]},
 planningScale:{mapScale,center,heading:1.96,estimatedWidthDepthHeightM:[0,2,1].map(axis=>(report.bounds.max[axis]-report.bounds.min[axis])*mapScale/0.12),
 method:'Uniform visual scale against library/C5 and protected road corridors; approximate, not surveyed. Official building area is not equated with the model envelope.',
 source:'https://www.postech.ac.kr/kor/innovation/education_district_cp.do'}};
await writeFile(path.join(resources,'education-district-points.bin'),bytes);
await writeFile(path.join(resources,'education-district-geometry.json'),JSON.stringify(metadata,null,2)+'\n');
await writeFile(path.join(resources,'education-district-experience.html'),html);
console.log(JSON.stringify({revision:report.revision,assetSHA256:sha(bytes),geometryBytes:bytes.length,htmlBytes:Buffer.byteLength(html),...metadata.planningScale}));
