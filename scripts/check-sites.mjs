import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const projects = [
  ['web', 'appgprj_6acf2f2aba648191a53e08da88cf1bb2', 'DB', 'BUCKET'],
  ['oi-web', 'appgprj_6acf33605044819182d185f849dcc0d6', null, null],
  ['team-web', 'appgprj_6acf3351f814819199fc2ee2a2c0e895', null, null],
];
const ignored = new Set(['node_modules', '.git', '.next', '.vinext', '.wrangler', '.sites-runtime', 'dist']);
async function scan(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (ignored.has(entry.name) || entry.name.startsWith('.env')) continue;
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) await scan(file);
    else if (/\.(?:ts|tsx|mjs|json)$/.test(entry.name)) {
      const text = await readFile(file, 'utf8');
      assert.doesNotMatch(text, /(?:up\.railway\.app|railway\.internal|from\s+["'](?:pg|railway)(?:["'/])|process\.env\.DATABASE_URL)/i, `${file} still uses the old host`);
    }
  }
}
for (const [name, id, d1, r2] of projects) {
  const directory = path.join(root, 'apps', name);
  const hosting = JSON.parse(await readFile(path.join(directory, '.openai/hosting.json'), 'utf8'));
  assert.equal(hosting.project_id, id);
  assert.equal(hosting.d1, d1);
  assert.equal(hosting.r2, r2);
  const manifest = JSON.parse(await readFile(path.join(directory, 'package.json'), 'utf8'));
  for (const dependencies of [manifest.dependencies, manifest.devDependencies]) {
    for (const name of ['railway', '@railway/cli', 'pg', 'sharp']) assert.equal(dependencies?.[name], undefined);
  }
  await scan(directory);
  console.log(`${name}: Sites identity, bindings and runtime dependency checks passed`);
}
