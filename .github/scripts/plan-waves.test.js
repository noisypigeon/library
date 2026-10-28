// Tests for plan-waves.js (LIB-0042 §1). Run with:
//   node --test .github/scripts/
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { next, classify, parseDag, parseDone } = require('./plan-waves.js');

const dag = (text) => parseDag(text.split('\n').map((l) => l.trim().replace(/ *\| */, '\t')).join('\n'));
const done = (entries) => new Map(Object.entries(entries));

// Every wave until none is left, with each wave's units settled or changed.
function plan(d, changed = [], stage = null) {
  const status = new Map();
  const waves = [];
  const deferred = [];
  for (;;) {
    const r = next(d, status, stage);
    for (const [u] of r.deferred) status.set(u, 'deferred');
    deferred.push(...r.deferred);
    if (!r.wave.length) break;
    waves.push(r.wave);
    for (const u of r.wave) status.set(u, changed.includes(u) ? 'changed' : 'settled');
  }
  return { waves, deferred };
}

const workload = dag(`
  w/project |
  w/app |
  w/policy | w/project w/app
  w/key | w/project w/app
  w/state | w/project w/key
  w/bucket | w/project w/state w/key
  w/cf | w/state w/key
  w/dns | w/cf w/state w/key
`);

test('settled units plan one wave per DAG level', () => {
  assert.deepEqual(plan(workload).waves, [
    ['w/project', 'w/app'],
    ['w/policy', 'w/key'],
    ['w/state'],
    ['w/bucket', 'w/cf'],
    ['w/dns'],
  ]);
});

test('a changed unit defers its dependents, transitively, with their blockers', () => {
  const { waves, deferred } = plan(workload, ['w/key']);
  assert.deepEqual(waves, [['w/project', 'w/app'], ['w/policy', 'w/key']]);
  assert.deepEqual(deferred, [
    ['w/state', 'w/key'],
    ['w/bucket', 'w/state, w/key'],
    ['w/cf', 'w/state, w/key'],
    ['w/dns', 'w/cf, w/state, w/key'],
  ]);
});

test('a dependency outside the selection counts as settled', () => {
  const d = dag(`
    zones/z/project |
    w/key | zones/z/project
    w/dns | w/key ../elsewhere
  `);
  d.delete('zones/z/project');
  assert.deepEqual(plan(d).waves, [['w/key'], ['w/dns']]);
});

test('a diamond waits for both sides', () => {
  const d = dag(`
    a |
    b | a
    c | a
    d | b c
  `);
  assert.deepEqual(plan(d).waves, [['a'], ['b', 'c'], ['d']]);
  assert.deepEqual(plan(d, ['c']).deferred, [['d', 'c']]);
});

test('a stage plans only its own units, against the rest as settled', () => {
  const stage = new Set(['w/state', 'w/bucket', 'w/cf', 'w/dns']);
  assert.deepEqual(plan(workload, [], stage).waves, [['w/state'], ['w/bucket', 'w/cf'], ['w/dns']]);
});

test('an empty selection is no waves', () => {
  assert.deepEqual(plan(new Map()), { waves: [], deferred: [] });
});

test('a cycle is refused rather than planned', () => {
  assert.throws(() => next(dag('a | b\nb | a'), done({}), null), /no unit can plan, but 2 remain/);
});

test('done lines parse as unit and status', () => {
  assert.deepEqual([...parseDone('a\tsettled\nb\tchanged\n')], [['a', 'settled'], ['b', 'changed']]);
});

test('classify reads the JSON plan the comment counts', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'plan-waves-'));
  const write = (unit, plan) => {
    fs.mkdirSync(path.join(dir, unit), { recursive: true });
    fs.writeFileSync(path.join(dir, unit, 'tfplan.json'), JSON.stringify(plan));
  };
  write('w/none', { resource_changes: [{ change: { actions: ['no-op'] } }, { change: { actions: ['read'] } }] });
  write('w/create', { resource_changes: [{ change: { actions: ['create'] } }] });
  write('w/output', { resource_changes: [], output_changes: { module: { actions: ['update'] } } });
  write('w/replace', { resource_changes: [{ change: { actions: ['delete', 'create'] } }] });
  assert.equal(classify(dir, 'w/none'), 'settled');
  assert.equal(classify(dir, 'w/create'), 'changed');
  assert.equal(classify(dir, 'w/output'), 'changed');
  assert.equal(classify(dir, 'w/replace'), 'changed');
  assert.throws(() => classify(dir, 'w/missing'), /w\/missing has no JSON plan/);
  fs.rmSync(dir, { recursive: true });
});
