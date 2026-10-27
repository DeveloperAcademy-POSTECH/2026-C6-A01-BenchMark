import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {randomUUID} from "node:crypto";
import {allowedCampusPosition,campusInput,campusXY,jsonBody} from "../src/lib/campus";
import geometry from "../src/lib/campus-geometry.json";
const map=JSON.parse(readFileSync(new URL("../../ios/OiDonation/Resources/Campus/campus-data.json",import.meta.url),"utf8"));
test("server placement polygons match the bundled iOS campus",()=>{
  assert.deepEqual(geometry.origin,map.origin);assert.equal(geometry.unitsPerMeter,map.unitsPerMeter);
  assert.deepEqual(geometry.bounds,map.bounds);assert.deepEqual(geometry.buildings,map.buildings.map((b:{p:number[][]})=>b.p));
});
test("WGS84 projection agrees with campus data and is not restricted to a library radius",()=>{
  const [x,y]=campusXY(geometry.origin[1],geometry.origin[0]);assert.ok(Math.hypot(x,y)<1e-8);
  // Independent approximate ENU checks at offsets away from the origin.
  const [east,north]=campusXY(geometry.origin[1]+.001,geometry.origin[0]+.001);
  assert.ok(east>10&&east<12);assert.ok(north>12&&north<14);
  let accepted=0;
  for(let lat=36.005;lat<=36.02;lat+=.0005)for(let lon=129.32;lon<=129.34;lon+=.0005)if(allowedCampusPosition(lat,lon))accepted++;
  assert.ok(accepted>30);assert.equal(allowedCampusPosition(37.5,127),false);
  assert.equal(allowedCampusPosition(NaN,129.32),false);
});
test("writers cannot set publication, identity, extra fields or unsupported coordinates/models",async()=>{
  let location:[number,number]|undefined;
  for(let lat=36.005;lat<36.02&&!location;lat+=.0005)for(let lon=129.32;lon<129.34;lon+=.0005)if(allowedCampusPosition(lat,lon)){location=[lat,lon];break;}
  assert.ok(location);
  const input={id:randomUUID(),campusID:"postech",model:"helmet-oi",latitude:location[0],longitude:location[1],heightMeters:1,headingDegrees:0,displayName:"테스트 농부",title:"테스트",story:"가상 이야기"};
  assert.equal(campusInput.safeParse(input).success,true);
  for(const change of [{status:"published"},{writerID:randomUUID()},{latitude:37.5},{model:"evil-url"},{heightMeters:0},{headingDegrees:360},{story:" "},{title:"a".repeat(81)}])assert.equal(campusInput.safeParse({...input,...change}).success,false);
  for(const body of ["null","[]","1","{invalid"]){await assert.rejects(()=>jsonBody(new Request("https://test.invalid",{method:"POST",headers:{"content-type":"application/json"},body})));}
});
