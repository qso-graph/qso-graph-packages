// SPDX-License-Identifier: GPL-3.0-only
// built-from.txt says a build is served, and a run that finds it served builds nothing. So it is written
// only after every file is checked as served: written first, a failed run left a broken build recorded
// as current and every run after it skipped the repair.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync(new URL('../.github/workflows/packages.yml', import.meta.url), 'utf8');
const steps = workflow.split(/\n      - name: /).slice(1).map((step) => ({ name: step.split('\n')[0], body: step }));
const writes = (step) => /cp built-from\.txt "s3:/.test(step.body);

test('built-from.txt is uploaded by one step, after the check that every file is served as built', () => {
  const writers = steps.filter(writes).map((step) => step.name);
  assert.deepEqual(writers, ['Recorded as served']);
  const names = steps.map((step) => step.name);
  assert.ok(names.indexOf('Served as built') >= 0);
  assert.ok(names.indexOf('Recorded as served') > names.indexOf('Served as built'));
  assert.equal(names.at(-1), 'Recorded as served');
});

test('the files uploaded with the packages leave built-from.txt out', () => {
  const upload = steps.find((step) => step.name === 'Uploaded to packages.qso-graph.net');
  assert.match(upload.body, /--exclude built-from\.txt/);
});
