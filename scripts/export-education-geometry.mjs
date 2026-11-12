#!/usr/bin/env node
// Export the web's assembled surface, preserving its interleaved LOD order.
// Usage: node scripts/export-education-geometry.mjs /path/to/dist/geometry.js
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

if (!process.argv[2]) throw new Error('Pass the web geometry.js source path.');
const source = await readFile(process.argv[2]);
const module = await import(`data:text/javascript;base64,${source.toString('base64')}`);
const geometry = module.buildGeometry();
if (module.CAPACITY !== 96000 || geometry.revision !== 'fine-packed-building-surfaces-5') {
  throw new Error('Review a changed web geometry revision before exporting.');
}
// Header, 96k XYZ + normal XYZ + brightness records, then depth-only triangles.
// Coordinates are unchanged. The renderer applies the same +2.18 ground offset.
const shellVertices = geometry.occluders.length / 3;
const bytes = Buffer.alloc(20 + module.CAPACITY * 28 + shellVertices * 12);
bytes.write('OIEDU002');
bytes.writeUInt32LE(module.CAPACITY, 8);
bytes.writeUInt32LE(shellVertices, 12);
bytes.writeFloatLE(2.18, 16);
let offset = 20;
for (let i = 0; i < module.CAPACITY; i++) {
  for (const k of [0, 1, 2, 8, 9, 10, 7]) {
    const value = geometry.vertices[i * 11 + k];
    if (!Number.isFinite(value)) throw new Error('Nonfinite point');
    bytes.writeFloatLE(value, offset); offset += 4;
  }
}
for (const value of geometry.occluders) {
  if (!Number.isFinite(value)) throw new Error('Nonfinite occluder');
  bytes.writeFloatLE(value, offset); offset += 4;
}
const target = new URL('../apps/ios/OiDonation/Resources/Campus/education-district-points.bin', import.meta.url);
await writeFile(target, bytes);
const sha = value => createHash('sha256').update(value).digest('hex');
const report = {
  revision: geometry.revision, sourceSHA256: sha(source), assetSHA256: sha(bytes),
  pointCount: module.CAPACITY, shellVertexCount: shellVertices,
  byteCount: bytes.length, groundOffset: 2.18,
  lod: { far: 24000, near: 96000, selection: 'prefix, never stride or random subsampling' },
  groups: geometry.groups,
};
await writeFile(new URL('education-district-geometry.json', target), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ file: fileURLToPath(target), ...report }, null, 2));
