// Tests for render-run-comments.js (LIB-0026). Run with:
//   node --test .github/scripts/
// Fixtures in testdata/ are runway plan and apply output, captured from PR
// comments with access-key IDs and UUIDs replaced. They were captured under
// the old 55,000-character truncation, so some leaves lost their result lines.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { render, linkSummary, BUDGET, _test } = require('./render-run-comments.js');

const fixture = (name) => fs.readFileSync(path.join(__dirname, 'testdata', name), 'utf8');
const base = { success: true, sha: 'abc1234', runUrl: 'https://example.test/run', footer: 'FOOTER' };
const plan = (extra) => render({ ...base, command: 'plan', marker: '<!-- terragrunt-plan -->', ...extra });

test('a unit printed from a worktree, the base or the checkout is the same leaf', () => {
  const roots = ['/home/runner/work/runway/runway', '/home/runner/_temp/base'];
  for (const raw of [
    'terraform/scaleway/project/runway',
    '/tmp/terragrunt-worktree-HEAD-660838630/terraform/scaleway/project/runway',
    '/home/runner/work/runway/runway/terraform/scaleway/project/runway',
    '/home/runner/_temp/base/terraform/scaleway/project/runway',
    './terraform/scaleway/project/runway',
  ]) {
    assert.equal(_test.normalizeUnit(raw, roots), 'terraform/scaleway/project/runway');
  }
});

test('lines are segmented by leaf, prefixes stripped, INFO dropped', () => {
  const output = [
    '03:55:53.494 STDOUT [a/b/c] terraform: Plan: 1 to add, 0 to change, 0 to destroy.',
    '03:55:53.495 INFO   [a/b/c] terraform: Initializing the backend...',
    '03:55:53.496 INFO   [a/b/c] Downloading Terraform configurations from x',
    '03:55:53.497 STDERR [d/e/f] terraform: Error: something broke',
    '03:55:53.498 WARN   [d/e/f] a warning',
    '❯❯ Run Summary  2 units  4s',
  ].join('\n');
  const { leaves, run } = _test.parse(output, []);
  assert.deepEqual(leaves.get('a/b/c'), ['Plan: 1 to add, 0 to change, 0 to destroy.']);
  assert.deepEqual(leaves.get('d/e/f'), ['Error: something broke', 'WARN: a warning']);
  assert.deepEqual(run, ['❯❯ Run Summary  2 units  4s']);
});

test('counts come from the JSON plan, a replace counting as both', () => {
  const json = {
    resource_changes: [
      { change: { actions: ['create'] } },
      { change: { actions: ['update'] } },
      { change: { actions: ['delete', 'create'] } },
      { change: { actions: ['no-op'] } },
      { change: { actions: ['read'] } },
    ],
  };
  assert.deepEqual(_test.countPlan(json), { add: 2, change: 1, destroy: 1 });
  const r = plan({ output: '00:00:00.000 STDOUT [x/y/z] terraform: (text that says nothing)', jsonPlans: { 'x/y/z': json } });
  assert.match(r.summary, /\| `x\/y\/z` \| \+2 ~1 -1 \|/);
});

test('the staged fixture: a deployer to create, a bucket deferred behind it', () => {
  const r = plan({ output: fixture('plan-staged.txt'), deferred: ['workloads/poc/scaleway/bucket/scratch'] });
  assert.match(r.summary, /\| `workloads\/poc\/scaleway\/terraform-deployer-iam\/main` \| \+6 ~0 -0 \|/);
  assert.match(r.summary, /\| `workloads\/poc\/scaleway\/bucket\/scratch` \| deferred until `workloads\/poc\/scaleway\/terraform-deployer-iam\/main` \|/);
  // Unchanged leaves are counted, not listed; changes come before the deferred leaf.
  assert.match(r.summary, /: 1 with changes, \d+ with no changes, \d+ failed to plan, 1 deferred\./);
  assert.doesNotMatch(r.summary, /No changes \|/);
  assert.ok(r.summary.indexOf('terraform-deployer-iam/main` | +6') < r.summary.indexOf('bucket/scratch` | deferred'));
});

test('the rotation fixture: a replace, and the bucket deferred', () => {
  const r = plan({ output: fixture('plan-rotation.txt'), deferred: ['workloads/poc/scaleway/bucket/scratch'] });
  assert.match(r.summary, /terraform-deployer-iam\/main` \| \+1 ~1 -1 \|/);
});

test('the apply fixture reads as applied', () => {
  const r = render({ ...base, command: 'apply', marker: '<!-- terragrunt-apply -->', output: fixture('apply-stage2.txt') });
  assert.match(r.summary, /\| `workloads\/poc\/scaleway\/bucket\/scratch` \| applied \+1 ~0 -0 \|/);
  assert.doesNotMatch(r.summary, /applied, no changes/);
  assert.match(r.summary, /: 1 with changes, \d+ with no changes, \d+ failed to apply\./);
});

test('a removed instance is labelled as a destroy', () => {
  const output = '00:00:00.000 STDOUT [/home/runner/_temp/base/workloads/w/scaleway/bucket/b] terraform: Plan: 0 to add, 0 to change, 2 to destroy.';
  const r = plan({ output, roots: ['/home/runner/_temp/base'], destroys: ['workloads/w/scaleway/bucket/b'] });
  assert.match(r.summary, /\| `workloads\/w\/scaleway\/bucket\/b` \| destroy \(removed from values.yaml\) \+0 ~0 -2 \|/);
});

test('nothing is truncated: a large plan is packed and split, within budget', () => {
  const lines = [];
  for (let u = 0; u < 30; u++) {
    for (let i = 0; i < 400; i++) lines.push(`00:00:00.000 STDOUT [t/m/u${u}] terraform:   + attribute_${i} = "${'v'.repeat(40)}"`);
    lines.push(`00:00:00.000 STDOUT [t/m/u${u}] terraform: Plan: 1 to add, 0 to change, 0 to destroy.`);
  }
  // One leaf alone is far larger than a comment.
  for (let i = 0; i < 4000; i++) lines.push(`00:00:00.000 STDOUT [t/m/huge] terraform:   ~ line_${i} = "${'w'.repeat(60)}"`);
  lines.push('00:00:00.000 STDOUT [t/m/huge] terraform: Plan: 0 to add, 1 to change, 0 to destroy.');
  const output = lines.join('\n');
  const r = plan({ output });
  assert.ok(r.details.length > 3, `expected several detail comments, got ${r.details.length}`);
  for (const d of [r.summary, ...r.details]) assert.ok(d.length <= BUDGET, `a body is ${d.length} characters`);
  // Every input line survives, in some detail comment.
  const all = r.details.join('\n');
  for (const probe of ['attribute_0 ', 'attribute_399 ', 'line_0 ', 'line_3999 ']) assert.ok(all.includes(probe), probe);
  // The huge leaf is split, and labelled as parts.
  const parts = all.match(/<code>t\/m\/huge<\/code> \(part (\d+) of (\d+)\)/g) || [];
  assert.ok(parts.length >= 3, `huge leaf in ${parts.length} parts`);
  // Fences balance in every comment, so each renders on its own.
  for (const d of r.details) {
    const fences = d.split('\n').filter((l) => /^`{3,}$/.test(l));
    assert.equal(fences.length % 2, 0);
  }
});

test('every comment carries the run marker, and details are marked as parts', () => {
  const r = plan({ output: fixture('plan-staged.txt') });
  assert.ok(r.summary.startsWith('<!-- terragrunt-plan -->'));
  for (const d of r.details) assert.ok(d.startsWith('<!-- terragrunt-plan -->\n<!-- part -->'));
});

test('masked values are replaced with *** everywhere', () => {
  const output = [
    '00:00:00.000 STDOUT [a/b/c] terraform: project_id = "s3cr3t-project-id"',
    '00:00:00.000 STDERR [a/b/c] terraform: Error: token hunter2token rejected',
  ].join('\n');
  const r = plan({ output, masked: ['s3cr3t-project-id', 'hunter2token', ''] });
  const all = [r.summary, ...r.details].join('\n');
  assert.ok(!all.includes('s3cr3t-project-id'));
  assert.ok(!all.includes('hunter2token'));
  assert.ok(all.includes('project_id = "***"'));
});

test('a fence never closes early on backticks in the output', () => {
  assert.equal(_test.fenceFor('no ticks'), '```');
  assert.equal(_test.fenceFor('has ``` inside'), '````');
});

test('linkSummary fills each row with its detail comment', () => {
  const r = plan({ output: fixture('plan-rotation.txt') });
  assert.match(r.summary, /\{\{detail:0\}\}/);
  const linked = linkSummary(r.summary, ['https://example.test/c/1']);
  assert.doesNotMatch(linked, /\{\{detail/);
  assert.match(linked, /\[detail 1\]\(https:\/\/example\.test\/c\/1\)/);
});

const leafLine = (unit, text) => `00:00:00.000 STDOUT [${unit}] terraform: ${text}`;
const noChanges = (unit) => leafLine(unit, 'No changes. Your infrastructure matches the configuration.');

test('unchanged leaves are counted, never listed or given a section', () => {
  const output = [
    leafLine('w/changed', 'Plan: 1 to add, 0 to change, 0 to destroy.'),
    ...Array.from({ length: 14 }, (_, i) => noChanges(`w/same-${i}`)),
  ].join('\n');
  const r = plan({ output });
  assert.match(r.summary, /`abc1234`: 1 with changes, 14 with no changes, 0 failed to plan\. /);
  assert.doesNotMatch(r.summary, /same-/);
  assert.equal(r.details.length, 1);
  assert.doesNotMatch(r.details[0], /same-/);
  assert.match(r.details[0], /<code>w\/changed<\/code>/);
});

test('an apply counts what failed to apply', () => {
  const output = [
    leafLine('w/a', 'Apply complete! Resources: 1 added, 0 changed, 0 destroyed.'),
    leafLine('w/b', 'Apply complete! Resources: 0 added, 0 changed, 0 destroyed.'),
    '00:00:00.000 STDERR [w/c] terraform: Error: boom',
  ].join('\n');
  const r = render({ ...base, success: false, command: 'apply', marker: '<!-- terragrunt-apply -->', output });
  assert.match(r.summary, /: 1 with changes, 1 with no changes, 1 failed to apply\./);
  assert.doesNotMatch(r.summary, /w\/b/);
});

test('a run with nothing to change posts only its summary', () => {
  const output = [noChanges('w/a'), noChanges('w/b'), '❯❯ Run Summary  2 units  4s'].join('\n');
  const r = plan({ output });
  assert.match(r.summary, /: 0 with changes, 2 with no changes, 0 failed to plan\./);
  assert.match(r.summary, /_Nothing changes\._/);
  assert.equal(r.details.length, 0);
  assert.doesNotMatch(r.summary, /Run section/);
});

test('deferred is counted only when there is one', () => {
  const r = plan({ output: noChanges('w/a') });
  assert.doesNotMatch(r.summary, /deferred/);
});

test("Terragrunt's own output is kept when a leaf fails", () => {
  const output = ['00:00:00.000 STDERR [w/a] terraform: Error: boom', '❯❯ Run Summary  1 units  1s'].join('\n');
  const r = render({ ...base, success: false, command: 'plan', marker: '<!-- terragrunt-plan -->', output });
  assert.match(r.summary, /Run section/);
  assert.ok(r.details.some((d) => d.includes('<code>Run</code>')));
});
