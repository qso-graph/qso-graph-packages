// SPDX-License-Identifier: GPL-3.0-or-later
// What packages.qso-graph.net holds that a build no longer names: a set, never an order (Desktop #134).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { staleKeys } from '../scripts/stale-keys.mjs';

test('a key that was built is never stale, whatever names begin it', () => {
  const built = ['rpm/x86_64/repodata/repomd.xml', 'rpm/x86_64/repodata/repomd.xml.asc', 'apt/dists/stable/Release'];
  const served = [...built, 'apt/dists/stable/Release.gpg.old', 'rpm/x86_64/old-1.0.0.rpm'];
  assert.deepEqual(staleKeys(built, served), ['apt/dists/stable/Release.gpg.old', 'rpm/x86_64/old-1.0.0.rpm']);
});

test('nothing served but what was built is nothing stale', () => {
  assert.deepEqual(staleKeys(['a', 'b'], ['b', 'a', 'a']), []);
});
