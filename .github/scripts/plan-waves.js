// Plans a spoke's workload leaves in waves (LIB-0042 §1): each wave is every
// unit whose workload dependencies have all settled, planned by one
// `terragrunt run --all`, in parallel. Deferral keeps LIB-0024 §3's rule: a
// unit is deferred if any of its workload dependencies is deferred or has a
// plan with changes.
//
// terragrunt-run.yml calls it between waves:
//
//   node plan-waves.js next --dag <tsv> --done <tsv> [--stage <file>]
//     prints {"wave": [unit, ...], "deferred": [[unit, "dep, dep"], ...]}
//   node plan-waves.js classify --json-dir <dir> <unit>...
//     prints `<unit>\tsettled|changed`, one line per unit
//
// <dag> is `terragrunt find --dag --dependencies` as `unit\tdep dep`, <done>
// is `unit\tsettled|changed|deferred` for every unit decided so far, and
// <stage> limits the candidates to one stage's units (LIB-0042 §2). A
// dependency outside the DAG or outside the stage was settled before this run
// planned anything. Tested offline with node --test (plan-waves.test.js).
'use strict';

const fs = require('fs');
const path = require('path');
const { countPlan } = require('./render-run-comments.js');

const lines = (text) => text.split('\n').map((l) => l.trimEnd()).filter(Boolean);

function parseDag(text) {
  const dag = new Map();
  for (const line of lines(text)) {
    const [unit, deps = ''] = line.split('\t');
    dag.set(unit, deps.split(' ').filter(Boolean));
  }
  return dag;
}

function parseDone(text) {
  const done = new Map();
  for (const line of lines(text)) {
    const [unit, status] = line.split('\t');
    done.set(unit, status);
  }
  return done;
}

// The next wave, and the units it defers. Deferral is transitive within one
// call, so a unit behind a deferred one is deferred at once rather than
// waiting a wave. An empty wave with nothing deferred and units left means
// the DAG can't make progress: a cycle, or a dependency that never planned.
function next(dag, done, stage) {
  const inStage = (u) => !stage || stage.has(u);
  const status = new Map(done);
  const deferred = [];
  let grew = true;
  while (grew) {
    grew = false;
    for (const [unit, deps] of dag) {
      if (status.has(unit) || !inStage(unit)) continue;
      const blockers = deps.filter((d) => ['changed', 'deferred'].includes(status.get(d)));
      if (blockers.length) {
        status.set(unit, 'deferred');
        deferred.push([unit, blockers.join(', ')]);
        grew = true;
      }
    }
  }
  const wave = [];
  for (const [unit, deps] of dag) {
    if (status.has(unit) || !inStage(unit)) continue;
    const ready = deps.every((d) => !dag.has(d) || !inStage(d) || status.get(d) === 'settled');
    if (ready) wave.push(unit);
  }
  const left = [...dag.keys()].filter((u) => inStage(u) && !status.has(u));
  if (!wave.length && left.length) {
    throw new Error(`no unit can plan, but ${left.length} remain: ${left.join(', ')}`);
  }
  return { wave, deferred };
}

// changed if the unit's JSON plan has any resource or output change that
// isn't a no-op: the comment's own count (render-run-comments.js countPlan).
function classify(jsonDir, unit) {
  const dir = path.join(jsonDir, unit);
  let files = [];
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith('.json'));
  } catch {
    // reported below
  }
  if (!files.length) throw new Error(`${unit} has no JSON plan in ${jsonDir}`);
  const c = countPlan(JSON.parse(fs.readFileSync(path.join(dir, files[0]), 'utf8')));
  return c.add + c.change + c.destroy > 0 ? 'changed' : 'settled';
}

function main(argv) {
  const [cmd, ...rest] = argv;
  const opts = {};
  const units = [];
  for (let i = 0; i < rest.length; i++) {
    if (rest[i].startsWith('--')) opts[rest[i].slice(2)] = rest[++i];
    else units.push(rest[i]);
  }
  const read = (f) => (f && fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : '');
  if (cmd === 'next') {
    const stage = opts.stage ? new Set(lines(read(opts.stage))) : null;
    return JSON.stringify(next(parseDag(read(opts.dag)), parseDone(read(opts.done)), stage));
  }
  if (cmd === 'classify') {
    return units.map((u) => `${u}\t${classify(opts['json-dir'], u)}`).join('\n');
  }
  throw new Error('usage: plan-waves.js next --dag <tsv> --done <tsv> [--stage <file>] | classify --json-dir <dir> <unit>...');
}

if (require.main === module) {
  try {
    const out = main(process.argv.slice(2));
    if (out) console.log(out);
  } catch (err) {
    console.error(`::error::plan-waves.js: ${err.message}`);
    process.exit(1);
  }
}

module.exports = { next, classify, parseDag, parseDone, main };
