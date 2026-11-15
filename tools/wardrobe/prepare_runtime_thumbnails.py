"""Prepare set thumbnails from actual OiWardrobeScene XCTest snapshots.
python3 tools/wardrobe/prepare_runtime_thumbnails.py ATTACHMENTS RENDERED_APP STAGING
Run the two wardrobe render tests and export their xcresult attachments first.
This only crops/resizes, using sips; it never grades colors or edits USDZs.
"""
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('attachments',type=Path);parser.add_argument('rendered_app',type=Path);parser.add_argument('staging',type=Path);parser.add_argument('--only',nargs='+',help='Regenerate selected set IDs only')
args=parser.parse_args();attachments,app,output=map(Path.resolve,[args.attachments,args.rendered_app,args.staging]);output.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((attachments/'manifest.json').read_text())
items=json.loads((ROOT/'tools/wardrobe/mobile-costumes-manifest.json').read_text())['costumes']
requests=[(i['id'],f"wardrobe-render-{i['id']}_",f"wardrobe-costume-{i['id']}",f"oi-costume-{i['id']}", 'testNewCostumesRenderInWardrobePreview') for i in items]
requests.append(('postech','wardrobe-skin-wardrobe-postech-long_','wardrobe-postech-long','oi-look-postech','testModularOutfitsKeepApprovedSkinAndRenderInWardrobe'))
if args.only:
 assert set(args.only)<={r[0] for r in requests},'Unknown set ID'
 requests=[r for r in requests if r[0] in args.only]
records=[]
for ID,prefix,model,thumbnail,test in requests:
 matches=[(group,a) for group in manifest if test in group['testIdentifier'] for a in group['attachments'] if a['suggestedHumanReadableName'].startswith(prefix) and not a['isAssociatedWithFailure']]
 assert len(matches)==1,(ID,len(matches));group,a=matches[0];source=attachments/a['exportedFileName'];model_file=ROOT/'apps/ios/OiDonation/Resources/Wardrobe'/f'{model}.usdz';bundled=list(app.rglob(model+'.usdz'));assert len(bundled)==1 and sha(bundled[0])==sha(model_file),(ID,'Rendered app/model mismatch')
 assert a['timestamp']>=model_file.stat().st_mtime,(ID,'Model changed after capture; rerun the tests')
 raw=source.read_bytes();assert raw[:8]==b'\x89PNG\r\n\x1a\n';w,h=struct.unpack_from('>II',raw,16);assert w/h==390/500,(w,h)
 # Crop a little of the unused studio margin, keeping the 3:4 tile and
 # the established character scale. sips preserves the snapshot's sRGB profile.
 crop_h=round(h*.96);crop_w=round(crop_h*.75);dest=output/(thumbnail+'.png')
 subprocess.run(['sips','--cropToHeightWidth',str(crop_h),str(crop_w),str(source),'--out',str(dest)],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['sips','--resampleHeightWidth','256','192',str(dest)],check=True,stdout=subprocess.DEVNULL)
 reference=output/(thumbnail+'-reference.png');reference.write_bytes(raw)
 records.append({'id':ID,'renderer':'OiWardrobeScene / RealityKit SDR snapshot','testIdentifier':group['testIdentifier'],'captureViewportPoints':[390,500],'capturedAtEpoch':a['timestamp'],'sourceModel':str(model_file.relative_to(ROOT)),'sourceModelSHA256':sha(model_file),'sourceImageSize':[w,h],'cropSize':[crop_w,crop_h],'colorAdjustment':False,'reference':{'path':f'docs/assets/wardrobe-runtime-previews/{reference.name}','sha256':sha(reference)},'thumbnail':{'path':f'apps/ios/OiDonation/Resources/WardrobeThumbnails/{dest.name}','sha256':sha(dest)}})
(output/'runtime-thumbnails-manifest.json').write_text(json.dumps(records,indent=2)+'\n');print('RUNTIME_THUMBNAILS_READY',len(records))
