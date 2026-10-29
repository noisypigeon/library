// Tests for check-policies.sh and its policies (LIB-0045). Run with:
//   node --test .github/scripts/
// Each case writes a minimal spoke to a temporary directory and runs the
// script there, so it needs yq and jq on PATH, as the script does. A policy's
// own cases run its jq filter on a hand-made inventory.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.join(__dirname, 'check-policies.sh');
const POLICIES = path.join(__dirname, 'policies');

const workload = (suffix, buckets = {}) => ({
  [`workloads/private/${suffix}/workload.yaml`]: [
    'workload:',
    '  deployments:',
    '    scaleway:',
    '      project:',
    '        prefix: wg',
    `        suffix: ${suffix}`,
    ...(Object.keys(buckets).length
      ? ['  backblaze:', '    bucket:', ...Object.keys(buckets).map((b) => `      ${b}:\n        description: ${buckets[b]}`)]
      : []),
    '',
  ].join('\n'),
});

const owners = (extra = '') =>
  `policies:\n  backblaze-bucket-owners:\n    workloads:\n      - private/cold\n${extra}`;

function spoke(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'check-policies-'));
  for (const [rel, content] of Object.entries({ 'spoke.hcl': 'locals {}\n', ...files })) {
    fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true });
    fs.writeFileSync(path.join(dir, rel), content);
  }
  return dir;
}

function run(files, args = []) {
  const dir = spoke(files);
  const r = spawnSync('bash', [SCRIPT, ...args], { cwd: dir, encoding: 'utf8' });
  fs.rmSync(dir, { recursive: true, force: true });
  return { status: r.status, out: r.stdout, err: r.stderr, lines: (r.stdout + r.stderr).split('\n').filter(Boolean) };
}

const policy = (id, params, inventory) =>
  spawnSync('jq', ['-c', '--argjson', 'params', JSON.stringify(params), '-f', path.join(POLICIES, `${id}.jq`)], {
    input: JSON.stringify(inventory),
    encoding: 'utf8',
  });

test('without policies.yaml nothing is checked', () => {
  const r = run(workload('other', { one: 'x' }));
  assert.equal(r.status, 0);
  assert.match(r.out, /::notice::No policies\.yaml; no policies to check/);
});

test('the inventory holds unit and hand-written leaves', () => {
  const r = run({
    ...workload('cold', { one: 'x' }),
    'terraform/scaleway/iam-policy/grafana/terragrunt.hcl': 'terraform {\n  source = "."\n}\n',
    'terraform/scaleway/iam-policy/grafana/main.tf':
      'module "p" {\n  source = "https://noisypigeon.garden/terraform/scaleway/iam-policy/v4.0.0"\n}\nresource "random_id" "x" {\n}\n',
  }, ['--inventory']);
  assert.equal(r.status, 0, r.err);
  const inv = JSON.parse(r.out);
  const bucket = inv.find((l) => l.path === 'workloads/private/cold/backblaze/bucket/one');
  assert.deepEqual(bucket.unit, { type: 'workload', id: 'private/cold' });
  assert.equal(bucket.module, 'backblaze/bucket');
  assert.equal(bucket.file, 'workloads/private/cold/workload.yaml');
  assert.equal(bucket.line, 9);
  assert.ok(inv.find((l) => l.path === 'workloads/private/cold/backblaze/api-key/deployer'), 'the implied B2 key is listed');
  const leaf = inv.find((l) => l.path === 'terraform/scaleway/iam-policy/grafana');
  assert.deepEqual(leaf.unit, { type: 'spoke', id: 'terraform/scaleway/iam-policy/grafana' });
  assert.deepEqual(leaf.modules, ['scaleway/iam-policy']);
  assert.deepEqual(leaf.resources, ['random_id']);
});

test('a bucket in a listed workload passes', () => {
  const r = run({ ...workload('cold', { one: 'x' }), 'policies.yaml': owners() });
  assert.equal(r.status, 0, r.err);
  assert.match(r.out, /1 policy, 0 violation\(s\)/);
});

test('a bucket in another workload fails, at its entry', () => {
  const r = run({ ...workload('cold'), ...workload('other', { one: 'x' }), 'policies.yaml': owners() });
  assert.equal(r.status, 1);
  assert.ok(r.lines.includes(
    '::error file=workloads/private/other/workload.yaml,line=9::backblaze-bucket-owners: workload private/other holds Backblaze bucket one; only private/cold may own one. Another workload reaches a bucket through a key, once its owner grants it (policies.yaml, LIB-0045 §§5-6)',
  ), r.err);
  assert.match(r.out, /1 violation\(s\)/);
});

test('a hand-written bucket fails, by module source or by resource', () => {
  const r = run({
    ...workload('cold'),
    'terraform/backblaze/bucket/sourced/terragrunt.hcl':
      'terraform {\n  source = "https://noisypigeon.garden/terraform/backblaze/bucket/v0.2.0"\n}\n',
    'terraform/scaleway/project/raw/terragrunt.hcl': 'terraform {\n  source = "."\n}\n',
    'terraform/scaleway/project/raw/main.tf': 'resource "b2_bucket" "b" {\n}\n',
    'policies.yaml': owners(),
  });
  assert.equal(r.status, 1);
  assert.ok(r.lines.some((l) => l.startsWith('::error file=terraform/backblaze/bucket/sourced/terragrunt.hcl::backblaze-bucket-owners: hand-written leaf terraform/backblaze/bucket/sourced holds a Backblaze bucket;')), r.err);
  assert.ok(r.lines.some((l) => l.startsWith('::error file=terraform/scaleway/project/raw/terragrunt.hcl::backblaze-bucket-owners: hand-written leaf terraform/scaleway/project/raw holds a Backblaze bucket;')), r.err);
});

test('a hand-written B2 key fails', () => {
  const r = run({
    ...workload('cold'),
    'terraform/scaleway/project/key/terragrunt.hcl': 'terraform {\n  source = "."\n}\n',
    'terraform/scaleway/project/key/main.tf': 'resource "b2_application_key" "k" {\n}\n',
    'policies.yaml': owners(),
  });
  assert.equal(r.status, 1);
  assert.ok(r.lines.includes('::error file=terraform/scaleway/project/key/terragrunt.hcl::backblaze-bucket-owners: hand-written leaf terraform/scaleway/project/key holds a B2 key, which no grant covers; declare it as backblaze.apiKey in a workload (LIB-0045 §5)'), r.err);
});

test('an exemption drops its violation with its reason; a stale one fails', () => {
  const exempt = [
    '    exempt:',
    '      - path: workloads/private/other/backblaze/bucket/one',
    '        reason: moving next week',
    '      - path: terraform/gone',
    '        reason: long gone',
    '',
  ].join('\n');
  const r = run({ ...workload('cold'), ...workload('other', { one: 'x' }), 'policies.yaml': owners(exempt) });
  assert.equal(r.status, 1);
  assert.ok(r.lines.includes('::notice file=policies.yaml::backblaze-bucket-owners: workloads/private/other/backblaze/bucket/one is exempt: moving next week'));
  assert.ok(r.lines.includes('::error file=policies.yaml::backblaze-bucket-owners: exempt path terraform/gone matches no violation; remove it'));
  assert.match(r.out, /0 violation\(s\)/);
});

test('an exemption needs a reason', () => {
  const r = run({ ...workload('cold'), 'policies.yaml': owners('    exempt:\n      - path: x\n') });
  assert.equal(r.status, 1);
  assert.ok(r.lines.includes('::error file=policies.yaml::policies.backblaze-bucket-owners.exempt: {"path":"x"} needs a path and a reason, and nothing else'), r.err);
});

test('an unknown policy fails, naming the real ones', () => {
  const r = run({ ...workload('cold'), 'policies.yaml': 'policies:\n  no-such-policy: {}\n' });
  assert.equal(r.status, 1);
  assert.ok(r.lines.some((l) => l.startsWith("::error file=policies.yaml::no-such-policy isn't a policy; the policies are backblaze-bucket-owners")), r.err);
});

test("a policy's own param errors are reported against policies.yaml", () => {
  const r = run({ ...workload('cold'), 'policies.yaml': 'policies:\n  backblaze-bucket-owners: {}\n' });
  assert.equal(r.status, 1);
  assert.ok(r.lines.includes('::error file=policies.yaml::backblaze-bucket-owners: needs workloads: a list of the workload IDs, <parent>/<workload>, that may own Backblaze buckets'), r.err);
});

test('backblaze-bucket-owners: zones and unlisted units fail; workload keys pass', () => {
  const leaf = (unit, extra) => ({ path: `${unit.id}/x`, file: 'f', line: null, unit, modules: [], resources: [], instance: 'x', ...extra });
  const r = policy('backblaze-bucket-owners', { workloads: ['private/cold'] }, [
    leaf({ type: 'zone', id: 'example.com' }, { modules: ['backblaze/bucket'] }),
    leaf({ type: 'workload', id: 'private/cold' }, { modules: ['backblaze/bucket'] }),
    leaf({ type: 'workload', id: 'example.com/app' }, { modules: ['backblaze/api-key'] }),
    leaf({ type: 'workload', id: 'example.com/app' }, { modules: ['cloudflare/bucket'] }),
  ]);
  assert.equal(r.status, 0, r.stderr);
  const found = r.stdout.trim().split('\n').map((l) => JSON.parse(l));
  assert.deepEqual(found.map((v) => v.path), ['example.com/x']);
  assert.match(found[0].message, /^zone example\.com holds Backblaze bucket x;/);
});

test('backblaze-bucket-owners: an unknown param is refused', () => {
  const r = policy('backblaze-bucket-owners', { workloads: ['private/cold'], owners: [] }, []);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /owners isn't a param; the one param is workloads/);
});
