// SPDX-License-Identifier: GPL-3.0-or-later
// A product renamed after its first releases lists those releases with no files under its package name.
// Asking for them failed every run, for every product, so releases before products.tsv's "since" are left out.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const script = new URL('../scripts/served-since.sh', import.meta.url).pathname;
const run = (since, tags) => spawnSync('bash', [script, since], { input: tags.map((t) => `${t}\n`).join(''), encoding: 'utf8' });

test('releases before since are left out, and the rest kept in order', () => {
  const out = run('v0.1.1', ['v0.1.10', 'v0.1.2', 'v0.1.1', 'v0.1.0', 'v0.0.9']);
  assert.equal(out.status, 0);
  assert.deepEqual(out.stdout.trim().split('\n'), ['v0.1.10', 'v0.1.2', 'v0.1.1']);
  assert.match(out.stderr, /v0\.1\.0: before v0\.1\.1/);
});

test('"-" keeps every release', () => {
  const out = run('-', ['v2.0.0', 'v0.1.0']);
  assert.equal(out.status, 0);
  assert.deepEqual(out.stdout.trim().split('\n'), ['v2.0.0', 'v0.1.0']);
});

test('a tag or since that is not vX.Y.Z is refused', () => {
  assert.notEqual(run('v0.1.1', ['v0.1.2', 'v0.1.2-beta.1']).status, 0);
  assert.notEqual(run('0.1.1', ['v0.1.2']).status, 0);
  assert.notEqual(run('', ['v0.1.2']).status, 0);
});

test('every product names its since, and the workflow filters by it', () => {
  const rows = readFileSync(new URL('../products.tsv', import.meta.url), 'utf8')
    .split('\n').filter((l) => !/^\s*(#|$)/.test(l)).map((l) => l.trim().split(/\s+/));
  assert.ok(rows.length > 0);
  for (const row of rows) assert.equal(row.length, 4, row.join(' '));
  const workflow = readFileSync(new URL('../.github/workflows/packages.yml', import.meta.url), 'utf8');
  assert.match(workflow, /print \$1, \$2, \$3, \$4/);
  assert.match(workflow, /bash scripts\/served-since\.sh "\$since"/);
});
