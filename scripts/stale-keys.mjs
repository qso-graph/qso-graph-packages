// SPDX-License-Identifier: GPL-3.0-only
// What packages.qso-graph.net holds that this build no longer names, so the
// Packages workflow can remove it (Desktop #134).
//
//   node scripts/stale-keys.mjs <built-keys> <served-keys>
//
// Each file one key a line: what was built, and what R2 lists. Prints the keys
// only R2 has, one a line.
//
// This replaced `aws s3 sync --delete`, which on R2 deleted files it had just
// uploaded. sync walks the two listings side by side and relies on R2 listing
// keys in the order it sorts them itself; where one name begins another
// (repomd.xml and repomd.xml.asc, Packages and Packages.gz, Release and
// Release.gpg) it judged the file both missing and extra, uploaded and deleted
// it at once, and the last to land won. Promoting 0.5.0 lost x86_64's
// repomd.xml, and its rerun aarch64's: dnf could not read that repository. A
// set has no order to rely on, and a key that was built is never stale.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export function staleKeys(built, served) {
  const keep = new Set(built);
  return [...new Set(served)].filter(key => !keep.has(key)).sort();
}

function lines(file) {
  return readFileSync(file, 'utf8').split('\n').filter(line => line !== '');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [built, served] = process.argv.slice(2);
  if (!built || !served) {
    console.error('Usage: node scripts/stale-keys.mjs <built-keys> <served-keys>');
    process.exit(2);
  }
  for (const key of staleKeys(lines(built), lines(served))) console.log(key);
}
