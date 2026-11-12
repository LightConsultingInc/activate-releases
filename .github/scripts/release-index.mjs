#!/usr/bin/env node
/**
 * Build the release index installed copies read once a day (UPDATE_INDEX_URL):
 *   { product, latest, releases: [{ version, date, notes, advisory, supported }] }
 * from every GitHub release of the repository plus the release being cut now. Supported: the
 * current minor and the previous one. Advisory: the RELEASE_NOTES.md section contains
 * "Security advisory: yes".
 *
 *   node scripts/release-index.mjs --repo owner/name --version 1.2.0 --notes RELEASE_NOTES.md --out index.json
 */
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i >= 0 ? process.argv[i + 1] : d; };
const repo = arg('repo'); const version = arg('version'); const notesFile = arg('notes', 'RELEASE_NOTES.md'); const out = arg('out', 'index.json');
if (!repo || !version) { console.error('usage: --repo owner/name --version X.Y.Z [--notes file] [--out file]'); process.exit(2); }

const cmp = (a, b) => { const x = a.split('.').map(Number), y = b.split('.').map(Number); for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] - y[i]; return 0; };
const notes = readFileSync(notesFile, 'utf8');
const sectionOf = (v) => { const m = notes.split(/^## /m).find((s) => s.startsWith(`v${v}\n`) || s.startsWith(`v${v}\r\n`)); return m ?? ''; };
const advisoryOf = (v) => /^Security advisory:\s*yes/im.test(sectionOf(v));

let published = [];
try {
  const json = execFileSync('gh', ['release', 'list', '--repo', repo, '--limit', '200', '--json', 'tagName,publishedAt,isDraft,isPrerelease'], { encoding: 'utf8' });
  published = JSON.parse(json).filter((r) => !r.isDraft && !r.isPrerelease && /^v\d+\.\d+\.\d+$/.test(r.tagName));
} catch (e) {
  console.error(`gh release list failed (${e.message}); the index will carry only ${version}`);
}
const releases = new Map();
for (const r of published) releases.set(r.tagName.slice(1), { version: r.tagName.slice(1), date: (r.publishedAt ?? '').slice(0, 10), notes: `https://github.com/${repo}/releases/tag/${r.tagName}` });
releases.set(version, { version, date: new Date().toISOString().slice(0, 10), notes: `https://github.com/${repo}/releases/tag/v${version}` });

const sorted = [...releases.values()].sort((a, b) => cmp(b.version, a.version));
const minors = [...new Set(sorted.map((r) => r.version.split('.').slice(0, 2).join('.')))];
const supportedMinors = new Set(minors.slice(0, 2));
for (const r of sorted) { r.advisory = advisoryOf(r.version); r.supported = supportedMinors.has(r.version.split('.').slice(0, 2).join('.')); }
const index = { product: 'activate', latest: sorted[0].version, generatedAt: new Date().toISOString(), supportedMinors: [...supportedMinors], releases: sorted };
writeFileSync(out, JSON.stringify(index, null, 2) + '\n');
console.error(`index: latest ${index.latest}, ${sorted.length} release(s), supported ${[...supportedMinors].join(', ')}`);
