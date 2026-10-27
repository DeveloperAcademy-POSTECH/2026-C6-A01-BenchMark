import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
const source=JSON.parse(readFileSync(resolve(process.cwd(),"../ios/OiDonation/Resources/Campus/campus-data.json"),"utf8"));
const geometry={frame:"WGS84_ENU_XY_V06",origin:source.origin,unitsPerMeter:source.unitsPerMeter,bounds:source.bounds,buildings:source.buildings.map((b:{p:number[][]})=>b.p)};
writeFileSync(resolve(process.cwd(),"src/lib/campus-geometry.json"),JSON.stringify(geometry));
