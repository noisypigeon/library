// Tests for resolve-workloads.sh's Backblaze grants (LIB-0045 §§6-7). Run with:
//   node --test .github/scripts/
// Each case writes a minimal spoke to a temporary directory and runs the
// script there without a flag, so it writes stubs and needs no network, only
// yq and jq on PATH.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.join(__dirname, 'resolve-workloads.sh');

// A private workload's workload.yaml, with its backblaze map as YAML lines.
const workload = (name, backblaze = []) => ({
  [`workloads/private/${name}/workload.yaml`]: [
    'workload:',
    '  deployments:',
    '    scaleway:',
    '      project:',
    '        prefix: wg',
    `        suffix: ${name}`,
    ...(backblaze.length ? ['  backblaze:', ...backblaze.map((l) => `    ${l}`)] : []),
    '',
  ].join('\n'),
});

const owner = (grants = ['private/app: [listFiles, readFiles]']) =>
  workload('cold', ['bucket:', '  snap:', '    description: x', ...(grants.length ? ['    grants:', ...grants.map((g) => `      ${g}`)] : [])]);

const consumer = (buckets, capabilities = '[listFiles, readFiles]') =>
  workload('app', ['apiKey:', '  reader:', `    capabilities: ${capabilities}`, `    buckets: ${buckets}`]);

function run(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'resolve-workloads-'));
  for (const [rel, content] of Object.entries({ 'spoke.hcl': 'locals {}\n', ...files })) {
    fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
    fs.writeFileSync(path.join(dir, rel), content);
  }
  const r = spawnSync('bash', [SCRIPT], { cwd: dir, encoding: 'utf8' });
  const read = (rel) => fs.readFileSync(path.join(dir, rel), 'utf8');
  const result = { status: r.status, err: r.stderr, errors: r.stderr.split('\n').filter((l) => l.startsWith('::error::')), read };
  test.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return result;
}

test('a granted bucket of another workload becomes a dependency and a bucket ID', () => {
  const r = run({ ...owner(), ...consumer('[private/cold/snap]') });
  assert.equal(r.status, 0, r.err);
  const stub = r.read('workloads/private/app/backblaze/api-key/reader/terragrunt.hcl');
  assert.match(stub, /dependency "xbucket_0" \{\n  config_path = "\.\.\/\.\.\/\.\.\/\.\.\/\.\.\/private\/cold\/backblaze\/bucket\/snap"\n\}/);
  assert.match(stub, /bucket_ids += \[dependency\.xbucket_0\.outputs\.module\.bucket_id\]/);
});

test('own and granted buckets wire together, in order', () => {
  const r = run({
    ...owner(),
    ...workload('app', [
      'bucket:', '  mine:', '    description: m',
      'apiKey:', '  reader:', '    capabilities: [readFiles]', '    buckets: [mine, private/cold/snap]',
    ]),
  });
  assert.equal(r.status, 0, r.err);
  const stub = r.read('workloads/private/app/backblaze/api-key/reader/terragrunt.hcl');
  assert.match(stub, /bucket_ids += \[dependency\.bucket_mine\.outputs\.module\.bucket_id, dependency\.xbucket_0\.outputs\.module\.bucket_id\]/);
});

test('an ungranted bucket is refused, naming where to grant it', () => {
  const r = run({ ...owner([]), ...consumer('[private/cold/snap]') });
  assert.equal(r.status, 1);
  assert.ok(r.errors.includes("::error::workloads/private/app/workload.yaml: backblaze.apiKey.reader.buckets: private/cold/snap isn't granted to private/app; add it to that bucket's grants in workloads/private/cold/workload.yaml (LIB-0045 §§6-7)"), r.err);
});

test("a key's capabilities must fit within the grant", () => {
  const r = run({ ...owner(), ...consumer('[private/cold/snap]', '[listFiles, readFiles, writeFiles, deleteFiles]') });
  assert.equal(r.status, 1);
  assert.ok(r.errors.includes('::error::workloads/private/app/workload.yaml: backblaze.apiKey.reader.capabilities: writeFiles, deleteFiles exceed what private/cold/snap grants private/app, listFiles, readFiles (LIB-0045 §§6-7)'), r.err);
});

test('a key naming two granted buckets fits within each ceiling', () => {
  const two = workload('cold', [
    'bucket:',
    '  a:', '    description: a', '    grants:', '      private/app: [listFiles, readFiles, writeFiles]',
    '  b:', '    description: b', '    grants:', '      private/app: [listFiles, readFiles]',
  ]);
  const ok = run({ ...two, ...consumer('[private/cold/a, private/cold/b]', '[listFiles, readFiles]') });
  assert.equal(ok.status, 0, ok.err);
  const over = run({ ...two, ...consumer('[private/cold/a, private/cold/b]', '[readFiles, writeFiles]') });
  assert.equal(over.status, 1);
  assert.deepEqual(over.errors.filter((l) => l.includes('exceed')), [
    '::error::workloads/private/app/workload.yaml: backblaze.apiKey.reader.capabilities: writeFiles exceed what private/cold/b grants private/app, listFiles, readFiles (LIB-0045 §§6-7)',
  ]);
});

test('an unknown workload or bucket is refused', () => {
  const r = run({ ...owner(), ...consumer('[private/nope/snap, private/cold/nope]') });
  assert.equal(r.status, 1);
  assert.ok(r.errors.includes("::error::workloads/private/app/workload.yaml: backblaze.apiKey.reader.buckets: private/nope/snap names workload private/nope, which doesn't exist (LIB-0045 §7)"), r.err);
  assert.ok(r.errors.includes("::error::workloads/private/app/workload.yaml: backblaze.apiKey.reader.buckets: private/cold/nope isn't one of private/cold's backblaze.bucket keys (LIB-0045 §7)"), r.err);
});

test("a malformed entry or grant is refused", () => {
  const r = run({
    ...owner(['private/app: []', 'not-a-workload: [readFiles]']),
    ...consumer('[cold/snap/x/y]'),
  });
  assert.equal(r.status, 1);
  assert.ok(r.errors.includes('::error::workloads/private/cold/workload.yaml: backblaze.bucket.snap.grants.private/app must list the capabilities its key may have (LIB-0045 §6)'), r.err);
  assert.ok(r.errors.includes(`::error::workloads/private/cold/workload.yaml: backblaze.bucket.snap.grants: "not-a-workload" isn't a workload ID, <parent>/<workload> (LIB-0045 §6)`), r.err);
  assert.ok(r.errors.includes(`::error::workloads/private/app/workload.yaml: backblaze.apiKey.reader.buckets: "cold/snap/x/y" names another workload's bucket as <parent>/<workload>/<bucket> (LIB-0045 §7)`), r.err);
});

test("a bucket can't grant its own workload, nor a key name its own bucket qualified", () => {
  const r = run(workload('cold', [
    'bucket:', '  snap:', '    description: x', '    grants:', '      private/cold: [readFiles]',
    'apiKey:', '  reader:', '    capabilities: [readFiles]', '    buckets: [private/cold/snap]',
  ]));
  assert.equal(r.status, 1);
  assert.ok(r.errors.includes("::error::workloads/private/cold/workload.yaml: backblaze.bucket.snap.grants names private/cold, this bucket's own workload, which needs no grant (LIB-0045 §6)"), r.err);
  assert.ok(r.errors.includes("::error::workloads/private/cold/workload.yaml: backblaze.apiKey.reader.buckets: private/cold/snap is this workload's own bucket; name it snap (LIB-0029 §3)"), r.err);
});
