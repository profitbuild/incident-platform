// ============================================================
// Tests the logic of .claude/workflows/backlog-autopilot.js (backlog #0-163): its helper functions one by one, and
// whole runs with a fake agent() that answers each agent and factory script as a scenario says.
// And how .claude/workflows/seed-bugs.js turns the seeder's answer into an outcome (backlog #0-170), reads its args and
// types the factory scripts' answers (#0-174) and the panel's verdicts, and ends on main after an error (#0-176).
// And that /backlog-autopilot, /audit and /docs-audit start from their command's words as from the object (#0-175, AC1).
//
// The workflow is not a module: Claude Code's workflow runtime evaluates its text as the body of an async function,
// with agent, parallel, phase, log and args in scope, and has no import (the workflow-authoring reference: "No
// filesystem or Node.js API access"). So this reads the file and evaluates it the same way, with stubs:
//   - helpers: the text up to the `// ---- run` marker, plus a `return { …the functions… }`, so each function can be
//     called with chosen inputs;
//   - runs: the whole text, whose `return` is the run's outcome.
// `export const meta` loses its `export`, and Date.now(), new Date() and Math.random() throw, as they do in the
// runtime (they would break a resume). A marker that moved or is not unique fails every test loudly.
//
// What it is not: a copy of the runtime. The stubs' behaviour (parallel() resolving a thunk that throws to null,
// Date and Math throwing) is what the workflow-authoring reference of Claude Code states, not something tested
// against the runtime, so a wrong reference would be repeated here; the workflow's own "VERIFY BEFORE THE FIRST
// RUN" still applies. The fake agent() does not validate an answer against its `schema` (the runtime does), and
// Node's globals (process, globalThis and the rest) stay reachable, so a workflow change that leans on either passes
// here and fails in the runtime. It tests the script's decisions, not its fit to the runtime. It records each call's
// schema, though: seed-bugs.js's are checked against the scripts' output with conforms() (#0-174, where an untyped
// schema let the agent answer in strings).
//
// Node's built-in modules only (no npm, ADR-0043). Run by Factory guards after .github/actions/setup-node; locally:
//   node .github/scripts/test-autopilot-workflow.mjs
// ============================================================
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const FILE = process.env.WORKFLOW
  ?? join(dirname(fileURLToPath(import.meta.url)), '..', '..', '.claude', 'workflows', 'backlog-autopilot.js')
const SRC = readFileSync(FILE, 'utf8')
const HELPERS = '// ---------------------------------------------------------------- helpers'
const RUN = '// ---------------------------------------------------------------- run'
const EXPORTED = [
  'scopeOf', 'valid', 'ruleFilesOf', 'claimKey', 'claimId', 'openClaims', 'verifyClaims', 'refutedFindings',
  'unsettledReason', 'q', 'record', 'CLAIM_ID', 'ACCEPT_UNVERIFIABLE', 'as', 'stopItem', 'VERDICT', 'ITEM_BRANCH',
]

function once(marker) {
  const at = SRC.indexOf(marker)
  if (at < 0 || SRC.indexOf(marker, at + 1) >= 0) {
    throw new Error(`${FILE}: the marker "${marker}" must appear exactly once (this test reads the script by it)`)
  }
  return at
}
once(HELPERS)
const RUN_AT = once(RUN)
if (!SRC.startsWith('export const meta = ')) throw new Error(`${FILE}: must begin with "export const meta = "`)
const strip = (text) => text.replace(/^export const meta = /, 'const meta = ')

// What the runtime forbids, as it forbids it.
class RuntimeDate extends Date {
  constructor(...a) {
    if (!a.length) throw new Error('new Date() without arguments throws in the workflow runtime')
    super(...a)
  }
  static now() { throw new Error('Date.now() throws in the workflow runtime') }
}
const RuntimeMath = Object.create(Math, { random: { value() { throw new Error('Math.random() throws in the workflow runtime') } } })
const AsyncFunction = (async () => {}).constructor

function evaluate(body, { args, agent, logs }) {
  // parallel() resolves a thunk that throws to null and never rejects (the workflow-authoring reference).
  const parallel = (thunks) => Promise.all(thunks.map((t) => Promise.resolve().then(t).catch(() => null)))
  const fn = new AsyncFunction('agent', 'parallel', 'phase', 'log', 'args', 'Date', 'Math', body)
  return fn(agent, parallel, () => {}, (m) => logs.push(m), args, RuntimeDate, RuntimeMath)
}

// The helpers of a run started with `args`, and the agent calls they make.
async function helpers({ args = {}, answers = {} } = {}) {
  const fake = fakeAgent(answers)
  const fns = await evaluate(`${strip(SRC.slice(0, RUN_AT))}\nreturn { ${EXPORTED.join(', ')} }`, { args, agent: fake.agent, logs: [] })
  return { ...fns, calls: fake.calls }
}

// One whole run: its outcome, the agent calls in order and the log lines.
async function run({ args = {}, answers = {} } = {}) {
  const fake = fakeAgent(answers)
  const logs = []
  const outcome = await evaluate(strip(SRC), { args, agent: fake.agent, logs })
  return { outcome, calls: fake.calls, logs }
}

// ---------------------------------------------------------------- the fake agent

const SHA = (c) => c.repeat(40)
const BASE = SHA('a'), HEAD = SHA('c')

// A run that goes through: every agent and script answers as on a good day (low risk and complexity, one round).
const DEFAULTS = {
  'ops:preflight.sh': { ok: true, reasons: [], baseSha: BASE, runId: 'run-1' },
  isolation: { tools: ['Read', 'Grep', 'Glob', 'Bash'], opening: 'You are the general reviewer: correctness, tests and conventions.' },
  'ops:next-item.sh': { ok: true, item: '#0-1', source: 'queue', position: 1, eligible: true, modules: ['incident-service'],
    risk: 'low', complexity: 'low', type: 'bug', branchPrefix: 'fix' },
  picker: { none: false, itemId: '#0-1', title: 'An item', slug: 'an-item', branch: 'fix/0-1-an-item', workDir: '.ai/work/0-1',
    risk: 'low', complexity: 'low', acceptanceCriteria: ['AC1. It works.'] },
  architect: { blocked: false, plan: { steps: [] }, adrs: [], rules: [{ id: 'GEN-01' }], modules: ['incident-service'] },
  implementer: { blocked: false, headSha: SHA('b') },
  'implementer-light': { blocked: false, headSha: SHA('b') },
  'ops:changed-paths.sh': { needsHuman: false, files: ['x.java'], areas: ['incident-service'], ruleFiles: ['general'],
    modules: ['incident-service'], mergeBase: BASE, head: HEAD, migrationTouched: false, k8sOrBuildTouched: false },
  'ops:run-tests.sh': { status: 'pass', head: HEAD, artifact: '.ai/runs/0-1/gate-r1.json', log: '.ai/runs/0-1/tests.log',
    modules: 'incident-service' },
  verifier: { items: [] },
  'acceptance-reviewer': { verdict: 'ACCEPT', criteria: [{ id: 'AC1', met: true }] },
  shipper: { mode: 'ship', prNumber: 7, prUrl: 'https://github.com/o/r/pull/7', followUpsCreated: [] },
  // state.sh branch <name> answers the branch it recorded (backlog #0-131); its other commands, {}.
  'ops:state.sh': ({ prompt }) => { const m = prompt.match(/state\.sh 'branch' '([^']+)'/); return m ? { branch: m[1] } : {} },
  'ops:notify.sh': {}, 'ops:return-to-main.sh': {}, 'ops:local-review.sh': {},
  // start-item.sh <base> <item> <branch> <run id> answers the branch it created (backlog #0-209).
  'ops:start-item.sh': ({ prompt }) => {
    const m = prompt.match(/start-item\.sh '[0-9a-f]{40}' '(0-\d+)' '([^']+)'/)
    return m ? { ok: true, branch: m[2], workDir: `.ai/work/${m[1]}`, head: SHA('d') } : { ok: false, reasons: ['usage'] }
  },
  // resume-item.sh <base> <branch> answers the branch it switched to and its item (backlog #0-215).
  'ops:resume-item.sh': ({ prompt }) => {
    const m = prompt.match(/resume-item\.sh '[0-9a-f]{40}' '([a-z]+\/(0-\d+)-[^']+)'/)
    return m ? { ok: true, branch: m[1], item: m[2], head: SHA('d') } : { ok: false, reasons: ['usage'] }
  },
}
const approve = (dimension, extra = {}) => ({ dimension, verdict: 'APPROVE', blocking: [], nonBlocking: [], resolved: [],
  upheldDisputes: [], unverified: [], ...extra })

// answers: key → an answer, or a function of { prompt, opts, n } (n: this key's call number, from 1). Keys are the
// agent type, `ops:<script>` for factory-ops, `isolation` for the isolation check.
function fakeAgent(answers) {
  const calls = []
  const agent = async (prompt, opts = {}) => {
    const type = opts.agentType
    let key = type
    if (type === 'factory-ops') key = `ops:${(prompt.match(/scripts\/factory\/([\w.-]+)/) ?? [])[1]}`
    else if (opts.label === 'isolation check') key = 'isolation'
    calls.push({ key, type, label: opts.label, prompt, schema: opts.schema, opts })
    const n = calls.filter((c) => c.key === key).length
    let answer = key in answers ? answers[key] : DEFAULTS[key]
    if (answer === undefined && type?.startsWith('review-')) answer = approve(type.slice('review-'.length))
    if (answer === undefined) throw new Error(`the fake agent has no answer for ${key}`)
    if (typeof answer === 'function') answer = answer({ prompt, opts, n })
    return answer === null ? null : structuredClone(answer)
  }
  return { agent, calls }
}
const keys = (calls) => calls.map((c) => c.key)

// ---------------------------------------------------------------- helpers

test('the script is read by its markers and the runtime stubs', async () => {
  const h = await helpers()
  for (const name of EXPORTED) assert.ok(h[name] !== undefined, `${name} is defined before the run marker`)
})

test('scopeOf: every category of the three predictions', async () => {
  const { scopeOf } = await helpers()
  const cat = (t, p, a) => scopeOf(t, p, a).category
  assert.equal(cat(['a'], ['a'], null), 'not-measured')
  assert.equal(cat(null, null, ['a']), 'not-measured')
  assert.equal(cat(null, ['a', 'b'], ['a']), 'within-plan')
  assert.equal(cat(null, ['a'], ['a', 'b']), 'diff-outside-plan')
  assert.equal(cat(['a', 'b'], null, ['b']), 'within-touches')
  assert.equal(cat(['a'], null, ['c']), 'diff-outside-touches')
  assert.equal(cat(['a', 'b'], ['a'], ['a']), 'consistent')
  assert.equal(cat(['a'], ['a', 'b'], ['b']), 'backlog-estimate-off')
  assert.equal(cat(['a', 'b'], ['a'], ['b']), 'plan-off')
  assert.equal(cat(['a'], ['a'], ['a', 'b']), 'implementation-drift')
  assert.equal(cat(['a'], ['b'], ['c']), 'unclear-item')
  const s = scopeOf(['b', 'a', 'a'], [], ['a', 'c'])
  assert.deepEqual(s.touches, ['a', 'b'], 'sorted, without repeats')
  assert.equal(s.plan, null, 'an empty prediction is no prediction')
  assert.deepEqual(s.outsideTouches, ['c'])
})

test('valid: a verdict with every list, and blocking findings with id, ruleId and impact', async () => {
  const { valid } = await helpers()
  assert.ok(valid(approve('general')))
  assert.ok(valid(approve('general', { blocking: [{ id: 'g-1', ruleId: 'GEN-01', impact: 'x' }] })))
  assert.ok(!valid(null))
  assert.ok(!valid({ ...approve('general'), verdict: undefined }))
  for (const list of ['blocking', 'resolved', 'upheldDisputes']) {
    assert.ok(!valid({ ...approve('general'), [list]: undefined }), `no ${list}`)
  }
  for (const field of ['id', 'ruleId', 'impact']) {
    const f = { id: 'g-1', ruleId: 'GEN-01', impact: 'x' }
    delete f[field]
    assert.ok(!valid(approve('general', { blocking: [f] })), `a blocking finding without ${field}`)
  }
})

test('ruleFilesOf: rule ids to their files, unknown prefixes dropped, each file once', async () => {
  const { ruleFilesOf } = await helpers()
  assert.deepEqual(ruleFilesOf([{ id: 'GEN-03' }, { id: 'GEN-04' }, { id: 'SEC-01' }, { id: 'FAC-S01' }, { id: 'XYZ-1' }, {}]),
    ['general', 'security', 'factory'])
  assert.deepEqual(ruleFilesOf(undefined), [])
})

test('claimKey and claimId: one id per claim, whatever its spacing and case', async () => {
  const { claimKey, claimId, CLAIM_ID } = await helpers()
  assert.equal(claimKey('  The  Gate\tran \n'), 'the gate ran')
  assert.equal(claimId('The gate ran'), claimId('  the   GATE ran '))
  assert.notEqual(claimId('The gate ran'), claimId('The gate did not run'))
  assert.match(claimId('anything'), CLAIM_ID)
  // Pinned: an owner accepts claims by these ids (acceptUnverifiable), so the hash must not change unnoticed.
  assert.equal(claimId('The gate ran'), 'ver-ea2281f6')
})

test('openClaims: the last verdict of each dimension, the same claim once with every dimension that raised it', async () => {
  const h = await helpers()
  h.record.rounds.push({ round: 1, verdicts: [
    approve('general', { unverified: ['Old claim'] }), approve('security', { unverified: ['Shared  claim', ' '] }), null] })
  h.record.rounds.push({ round: 2, verdicts: [approve('general', { unverified: ['shared claim', 'New claim'] })] })
  assert.deepEqual(h.openClaims(), [
    { claim: 'shared claim', dimensions: ['general', 'security'] },
    { claim: 'New claim', dimensions: ['general'] },
  ])
})

const ITEM = { itemId: '#0-1', id: '0-1' }
async function verifying(claims, answer, args) {
  const h = await helpers({ args, answers: { verifier: answer } })
  h.record.rounds.push({ round: 1, verdicts: [approve('general', { unverified: claims })] })
  return { h, result: await h.verifyClaims(ITEM, 1, HEAD, 'gate.json') }
}

test('verifyClaims: no claim, no verifier', async () => {
  const h = await helpers()
  const result = await h.verifyClaims(ITEM, 1, HEAD, 'gate.json')
  assert.deepEqual(result, { ok: true, items: [] })
  assert.equal(h.calls.length, 0)
})

test('verifyClaims: the verifier gets the claims, the commit and the artifact, never the diff', async () => {
  const { h } = await verifying(['A claim'], { items: [] })
  assert.equal(h.calls.length, 1)
  assert.match(h.calls[0].prompt, /commit c{40}/)
  assert.match(h.calls[0].prompt, /gate\.json/)
  assert.match(h.calls[0].prompt, /"claim":"A claim"/)
})

test('verifyClaims: no answer stops; a missing or unsourced answer is unverifiable (fail closed)', async () => {
  assert.deepEqual((await verifying(['A'], null)).result, { ok: false, reason: 'verifier gave no answer' })
  const { result } = await verifying(['A', 'B', 'C', 'D'], { items: [
    { index: 1, verdict: 'verified', source: 'https://x', quote: null, why: 'w' },
    { index: 2, verdict: 'refuted', source: null, quote: 'q', why: 'w' },
    { index: 3, verdict: 'verified', source: 'https://x', quote: 'q', why: 'it says so' },
  ] })
  assert.ok(result.ok)
  const [a, b, c, d] = result.items
  assert.equal(a.verdict, 'unverifiable'); assert.equal(a.why, 'the verifier gave no answer for this claim')
  assert.equal(b.verdict, 'unverifiable'); assert.equal(b.why, 'answered verified without a source and a quote')
  assert.equal(c.verdict, 'unverifiable'); assert.equal(c.why, 'answered refuted without a source and a quote')
  assert.equal(d.verdict, 'verified'); assert.equal(d.why, 'it says so')
})

test('verifyClaims: a sourced refutation stays refuted', async () => {
  const { result } = await verifying(['A'], { items: [{ index: 0, verdict: 'refuted', source: 'https://x', quote: 'no', why: 'w' }] })
  assert.equal(result.items[0].verdict, 'refuted')
})

test('acceptUnverifiable: the owner accepts an unverifiable claim by its id, on a resumed branch only', async () => {
  const unverifiable = { items: [{ index: 0, verdict: 'unverifiable', source: null, quote: null, why: 'w' }] }
  const { claimId } = await helpers()
  const id = claimId('A claim')
  const resumed = await verifying(['A claim'], unverifiable, { branch: 'fix/0-1-x', acceptUnverifiable: [id] })
  assert.equal(resumed.result.items[0].acceptedByOwner, true)
  const other = await verifying(['A claim'], unverifiable, { branch: 'fix/0-1-x', acceptUnverifiable: [claimId('Another')] })
  assert.equal(other.result.items[0].acceptedByOwner, undefined, 'another id accepts nothing')
  const noBranch = await verifying(['A claim'], unverifiable, { acceptUnverifiable: [id] })
  assert.equal(noBranch.result.items[0].acceptedByOwner, undefined, 'without branch the ids count for nothing')
  const refuted = await verifying(['A claim'], { items: [{ index: 0, verdict: 'refuted', source: 's', quote: 'q', why: 'w' }] },
    { branch: 'fix/0-1-x', acceptUnverifiable: [id] })
  assert.equal(refuted.result.items[0].acceptedByOwner, undefined, 'a refuted claim cannot be accepted')
})

test('refutedFindings and unsettledReason', async () => {
  const { refutedFindings, unsettledReason } = await helpers()
  const items = [
    { id: 'ver-00000001', claim: 'R', dimensions: ['security'], verdict: 'refuted', source: 's', quote: 'q', why: 'w' },
    { id: 'ver-00000002', claim: 'U', dimensions: ['general'], verdict: 'unverifiable', why: 'no source' },
    { id: 'ver-00000003', claim: 'A', dimensions: ['general'], verdict: 'unverifiable', why: 'w', acceptedByOwner: true },
    { id: 'ver-00000004', claim: 'V', dimensions: ['general'], verdict: 'verified', why: 'w' },
  ]
  const [f, ...rest] = refutedFindings(items)
  assert.equal(rest.length, 0)
  assert.equal(f.dimension, 'verification'); assert.equal(f.id, 'ver-00000001'); assert.deepEqual(f.raisedBy, ['security'])
  assert.ok(f.impact && f.ruleId, 'shaped like a blocking finding (valid() needs id, ruleId, impact)')
  const why = unsettledReason(items)
  assert.match(why, /^NEEDS_HUMAN — the verifier could not settle 1 claim/)
  assert.match(why, /ver-00000002 U/)
  assert.doesNotMatch(why, /ver-00000003/)
  assert.equal(unsettledReason(items.filter((i) => i.id !== 'ver-00000002')), null)
})

test('q: only ids, refs and shas reach a factory script', async () => {
  const { q } = await helpers()
  assert.equal(q('0-1'), "'0-1'")
  assert.equal(q('origin/main'), "'origin/main'")
  assert.equal(q(SHA('a')), `'${SHA('a')}'`)
  for (const bad of ['a b', "a'b", 'a;b', '$(x)', 'a`b', '', 'a\nb']) assert.throws(() => q(bad), /unsafe argument/, bad)
})

// ---------------------------------------------------------------- runs

test('a good run ships in shadow mode, never merging', async () => {
  const { outcome, calls } = await run()
  assert.equal(outcome.outcome, 'SHIPPED')
  assert.equal(outcome.mode, 'shadow')
  assert.equal(outcome.rounds, 1)
  const ship = calls.find((c) => c.key === 'shipper')
  assert.match(ship.prompt, /shadow: true\. risk-high: false\. merge: false\./)
  assert.ok(keys(calls).includes('implementer-light'), 'low complexity in the backlog and the picker: the lighter implementer')
  assert.ok(!keys(calls).includes('verifier'), 'no claim, no verifier')
})

test('the panel is the five dimensions, plus migration and k8s when the paths call for them', async () => {
  const plain = await run()
  const panel = (calls) => calls.filter((c) => c.key.startsWith('review-')).map((c) => c.key).sort()
  assert.deepEqual(panel(plain.calls), ['review-architecture', 'review-docs', 'review-general', 'review-performance', 'review-security'])
  const both = await run({ answers: { 'ops:changed-paths.sh': { ...DEFAULTS['ops:changed-paths.sh'], migrationTouched: true, k8sOrBuildTouched: true } } })
  assert.ok(panel(both.calls).includes('review-migration') && panel(both.calls).includes('review-k8s'))
})

test('preflight: no answer, a refusal or no base commit stops before anything starts', async () => {
  const none = await run({ answers: { 'ops:preflight.sh': null } })
  assert.equal(none.outcome.outcome, 'NOT_STARTED'); assert.match(none.outcome.reasons[0], /AGENT_TYPE_OPTION/)
  const refused = await run({ answers: { 'ops:preflight.sh': { ok: false, reasons: ['STOP file present'] } } })
  assert.deepEqual(refused.outcome, { outcome: 'NOT_STARTED', reasons: ['STOP file present'] })
  const noBase = await run({ answers: { 'ops:preflight.sh': { ok: true, reasons: [], baseSha: 'main' } } })
  assert.deepEqual(noBase.outcome.reasons, ['preflight returned no base commit'])
})

test('isolation: a reviewer that can edit files, or without its definition, stops the run', async () => {
  const own = 'You are the general reviewer: correctness, tests and conventions.'
  for (const [iso, why] of [
    [{ tools: ['Read', 'Edit'], opening: own }, /can edit files/],
    [{ tools: ['Read'], opening: 'You are a helpful assistant.' }, /instructions are not review-general's/],
    [{ tools: ['Read'], opening: '' }, /instructions are not review-general's/],
    [{ tools: ['Read'] }, /instructions are not review-general's/],
    [{ tools: 'Read, Edit', opening: own }, /did not list its tools/],
    [{ tools: [1, 2], opening: own }, /did not list its tools/],
    [{ opening: own }, /did not list its tools/],
    [null, /no answer/],
  ]) {
    const { outcome, calls } = await run({ answers: { isolation: iso } })
    assert.equal(outcome.outcome, 'NOT_STARTED')
    assert.match(outcome.reasons[0], /agent isolation check failed/)
    assert.match(outcome.reasons[0], why)
    assert.ok(keys(calls).includes('ops:state.sh'), 'the lock is released')
    assert.ok(!keys(calls).includes('picker'))
  }
})

test('isolation: a reviewer quoting its own definition goes on, after a runtime preamble too', async () => {
  for (const opening of [
    '  You are the general reviewer: correctness, tests and conventions. ',
    "You are a Claude agent, built on Anthropic's Claude Agent SDK.You are the general reviewer: correctness, tests and conventions.",
  ]) {
    const { calls } = await run({ answers: { isolation: { tools: ['Read', 'Bash', 'StructuredOutput'], opening } } })
    assert.ok(keys(calls).includes('picker'), `the run went past the isolation check (${opening.slice(0, 40)})`)
  }
})

test('isolation: the question does not point the reviewer at its definition file (review round 1 of #0-248)', async () => {
  const { calls } = await run({})
  const iso = calls.find((c) => c.key === 'isolation')
  assert.ok(iso, 'the isolation check was asked')
  assert.ok(!/review-general\.md|\.claude\/agents/.test(iso.prompt), `its prompt names no definition file: ${iso.prompt}`)
  assert.ok(!iso.prompt.includes('You are the general reviewer'), 'its prompt does not hold the phrase it looks for')
  assert.ok(!('bare' in iso.opts), 'as() does not pass its own option on to agent()')
  const other = calls.find((c) => c.key === 'picker')
  assert.match(other.prompt, /\.claude\/agents\/picker\.md/, 'other agents keep the preamble')
})

test('isolation: REVIEW_GENERAL_OPENING is how review-general.md begins (backlog #0-248)', () => {
  const opening = SRC.match(/const REVIEW_GENERAL_OPENING = '([^']+)'/)?.[1]
  assert.ok(opening, 'REVIEW_GENERAL_OPENING is a single-quoted string in the workflow')
  const md = readFileSync(join(dirname(FILE), '..', 'agents', 'review-general.md'), 'utf8')
  const body = md.split(/^---$/m).slice(2).join('---').split('\n').find((l) => l.trim() !== '')
  assert.ok(body?.startsWith(opening), `review-general.md's body begins "${body}", not "${opening}"`)
})

test('args: acceptUnverifiable without branch, a malformed item, malformed claim ids', async () => {
  const noBranch = await run({ args: { acceptUnverifiable: ['ver-00000001'] } })
  assert.match(noBranch.outcome.reasons[0], /acceptUnverifiable needs branch/)
  const badItem = await run({ args: { item: '0-1; rm -rf /' } })
  assert.match(badItem.outcome.reasons[0], /the item must look like #0-25/)
  assert.ok(!keys(badItem.calls).includes('ops:next-item.sh'), 'refused before any script sees it')
  for (const ids of [[], ['ver-xyz'], 'ver-00000001', ['ver-00000001', 'nope']]) {
    const bad = await run({ args: { branch: 'fix/0-1-x', acceptUnverifiable: ids } })
    assert.equal(bad.outcome.outcome, 'NOT_STARTED', JSON.stringify(ids))
    assert.match(bad.outcome.reasons[0], /acceptUnverifiable must be a list of claim ids/)
  }
})

test('`/backlog-autopilot #0-N [<branch>]` passes one string, read as the item and the branch (#0-175, AC1)', async () => {
  // A run from the words makes exactly the calls a run from the object does, so every check the object meets applies.
  for (const [words, object] of [
    ['', {}], ['  \n', {}],
    ['#0-2', { item: '#0-2' }], [' #0-2\t', { item: '#0-2' }],
    ['#0-1 fix/0-1-an-item', { item: '#0-1', branch: 'fix/0-1-an-item' }],
    ['  #0-1\tfix/0-1-an-item\n', { item: '#0-1', branch: 'fix/0-1-an-item' }],
    // The same refusals as the object's, before any script sees the value.
    ['0-1;rm', { item: '0-1;rm' }], ['#0-2 fix/0-1-an-item', { item: '#0-2', branch: 'fix/0-1-an-item' }],
    ['#0-1 main', { item: '#0-1', branch: 'main' }],
  ]) {
    const fromWords = await run({ args: words })
    const fromObject = await run({ args: object })
    assert.deepEqual(fromWords.outcome, fromObject.outcome, JSON.stringify(words))
    assert.deepEqual(fromWords.calls.map((c) => c.prompt), fromObject.calls.map((c) => c.prompt), JSON.stringify(words))
  }
  // The item is the one named, not the queue's next (the defect: args.item was undefined on a string).
  const named = await run({ args: '#0-2' })
  assert.ok(named.calls.find((c) => c.key === 'ops:next-item.sh').prompt.endsWith(`'${BASE}' '0-2'`))
  const resumed = await run({ args: '#0-1 fix/0-1-an-item' })
  assert.ok(keys(resumed.calls).includes('ops:resume-item.sh') && !keys(resumed.calls).includes('ops:next-item.sh'))
  // Three words or more: no run, and nothing runs (not even the preflight).
  for (const words of ['#0-1 fix/0-1-an-item extra', '#0-1 fix/0-1-an-item ver-00000001', 'a b c d']) {
    const { outcome, calls } = await run({ args: words })
    assert.equal(outcome.outcome, 'NOT_STARTED', words)
    assert.match(outcome.reasons[0], /^\d+ words: pass no words \(the next item\), "#0-N" \(that item\) or "#0-N <branch>"/, words)
    assert.equal(calls.length, 0, `nothing runs on ${JSON.stringify(words)}`)
  }
  // shadow, maxRounds and acceptUnverifiable stay object fields: a run from words is in shadow mode, with three rounds.
  const shadow = await run({ args: '#0-1' })
  assert.equal(shadow.outcome.mode, 'shadow')
  assert.match(shadow.calls.find((c) => c.key === 'shipper').prompt, /shadow: true\. risk-high: false\. merge: false\./)
})

test('the item: nothing to do, a malformed next item, a malformed or different pick', async () => {
  const nothing = await run({ answers: { 'ops:next-item.sh': { ok: true, item: null, reason: 'queue empty' } } })
  assert.equal(nothing.outcome.outcome, 'NOTHING_TO_DO')
  const malformed = await run({ answers: { 'ops:next-item.sh': { ...DEFAULTS['ops:next-item.sh'], item: '0-1' } } })
  assert.match(malformed.outcome.reasons[0], /malformed item/)
  // The prefix of the branch is next-item.sh's (backlog #0-195): without one, nothing starts and no picker is asked.
  for (const branchPrefix of [undefined, null, '', 'Fix', 'fix/', 'fix x']) {
    const noPrefix = await run({ answers: { 'ops:next-item.sh': { ...DEFAULTS['ops:next-item.sh'], branchPrefix } } })
    assert.match(noPrefix.outcome.reasons[0], /next-item returned no branch prefix for #0-1/, String(branchPrefix))
    assert.ok(!keys(noPrefix.calls).includes('picker'), String(branchPrefix))
  }
  for (const [pick, why] of [
    [{ ...DEFAULTS.picker, acceptanceCriteria: [] }, /picker answer incomplete/],
    [{ ...DEFAULTS.picker, slug: 'an item' }, /picker gave no usable slug/],
    [{ ...DEFAULTS.picker, itemId: '#0-2' }, /picker prepared #0-2 instead of #0-1/],
    [null, /picker gave no answer/],
  ]) {
    const { outcome } = await run({ answers: { picker: pick } })
    assert.equal(outcome.outcome, 'BLOCKED'); assert.match(outcome.reason, why)
  }
})

// backlog #0-206: what the runtime does when an agent ends without its structured answer (its maxTurns spent):
// agent() throws. Runs wf_bc03d7e8-742 and wf_c1597fde-23e ended there, leaving the lock with no state.
const ENDS_WITHOUT_ANSWER = () => { throw new Error('the agent ended without calling StructuredOutput (max turns reached)') }
const stateCalls = (calls) => calls.filter((c) => c.key === 'ops:state.sh').map((c) => c.prompt.slice(c.prompt.indexOf('scripts/factory/')))

test('an agent that ends without an answer stops the item: draft PR, state recorded with the stage, notified', async () => {
  for (const [type, stage, why] of [
    ['architect', 'plan', /^architect gave no answer \(last agent call without an answer: architect: the agent ended without calling StructuredOutput \(max turns reached\)\)$/],
    ['implementer-light', 'implement', /^implementer gave no answer \(last agent call without an answer: implementer-light: .*max turns reached/],
  ]) {
    const { outcome, calls, logs } = await run({ answers: { [type]: ENDS_WITHOUT_ANSWER } })
    assert.equal(outcome.outcome, 'BLOCKED', type)
    assert.equal(outcome.item, '#0-1')
    assert.match(outcome.reason, why)
    assert.ok(logs.some((l) => l.startsWith(`${type} ended without an answer: `)), `${type}: the log names the agent`)
    const draft = calls.find((c) => c.key === 'shipper')
    assert.ok(draft && /^Mode: blocked\./m.test(draft.prompt), `${type}: a draft PR of the branch`)
    assert.ok(stateCalls(calls).includes(`scripts/factory/state.sh 'record' 'blocked' '0-1' 'https://github.com/o/r/pull/7' '${stage}'`),
      `${type}: the state recorded with the stage (record also releases the lock): ${stateCalls(calls).join(' | ')}`)
    assert.ok(calls.some((c) => c.key === 'ops:notify.sh' && c.prompt.includes("notify.sh 'blocked' '0-1'")), `${type}: notified`)
  }
})

test('a tolerated no-answer earlier in the run is not named in a later, unrelated stop', async () => {
  const { outcome, logs } = await run({ args: { localReview: true },
    answers: { 'ops:local-review.sh': ENDS_WITHOUT_ANSWER, 'acceptance-reviewer': null } })
  assert.ok(logs.some((l) => l.startsWith('local second opinion ended without an answer: ')), 'the local review did throw')
  assert.equal(outcome.outcome, 'BLOCKED')
  assert.equal(outcome.reason, 'acceptance-reviewer gave no answer', 'no suffix from the earlier local review')
})

test('a shipper that ends without an answer while stopping still records the state and notifies', async () => {
  const { outcome, calls } = await run({ answers: { architect: null, shipper: ENDS_WITHOUT_ANSWER } })
  assert.equal(outcome.outcome, 'BLOCKED')
  assert.ok(stateCalls(calls).includes("scripts/factory/state.sh 'record' 'blocked' '0-1' '-' 'plan'"), stateCalls(calls).join(' | '))
  assert.ok(keys(calls).includes('ops:notify.sh'))
})

test("the picker's own failure stops the item at pick; a real none is still nothing to do", async () => {
  for (const [pick, why] of [
    [{ none: false, failed: true, reason: 'git switch -c refused by guard-protected-bash.sh' }, /^picker failed: git switch -c refused by guard-protected-bash\.sh$/],
    [{ none: false, failed: true, reason: 'cp refused', branch: 'fix/0-1-an-item' },
      /^picker failed: cp refused; the branch fix\/0-1-an-item was left: next-item\.sh skips the item while it exists$/],
  ]) {
    const { outcome, calls } = await run({ answers: { picker: pick } })
    assert.equal(outcome.outcome, 'BLOCKED'); assert.equal(outcome.item, '#0-1'); assert.match(outcome.reason, why)
    assert.ok(stateCalls(calls).includes("scripts/factory/state.sh 'record' 'blocked' '0-1' '-' 'pick'"), stateCalls(calls).join(' | '))
    assert.ok(!stateCalls(calls).some((s) => s.includes("'branch'")), 'no branch is recorded in the lock for a failed pick')
    assert.ok(!keys(calls).includes('shipper'), 'no draft PR: the run has no branch of its own to push')
    assert.ok(keys(calls).includes('ops:return-to-main.sh') && keys(calls).includes('ops:notify.sh'))
    assert.ok(!keys(calls).includes('architect'))
  }
  // On resume the branch is the owner's: its stop does not say the picker left it (review round 1).
  const resumed = await run({ args: { branch: 'fix/0-1-an-item', item: '#0-1' },
    answers: { picker: { none: false, failed: true, reason: 'gh refused', branch: 'fix/0-1-an-item' } } })
  assert.equal(resumed.outcome.outcome, 'BLOCKED'); assert.equal(resumed.outcome.reason, 'picker failed: gh refused')
  assert.ok(stateCalls(resumed.calls).includes("scripts/factory/state.sh 'record' 'blocked' '0-1' '-' 'pick'"))
  const thrown = await run({ answers: { picker: ENDS_WITHOUT_ANSWER } })
  assert.equal(thrown.outcome.outcome, 'BLOCKED'); assert.match(thrown.outcome.reason, /^picker gave no answer \(last agent call without an answer: picker: /)
  const none = await run({ answers: { picker: { none: true, reason: '#0-1 has no numbered acceptance criteria' } } })
  assert.equal(none.outcome.outcome, 'NOTHING_TO_DO')
  assert.ok(!keys(none.calls).includes('ops:notify.sh') && !stateCalls(none.calls).some((s) => s.includes("'record'")))
})

test('the item starts in code: start-item.sh after the pick and before the lock, never on resume or none (#0-209)', async () => {
  const { outcome, calls } = await run()
  assert.equal(outcome.outcome, 'SHIPPED')
  const at = calls.findIndex((c) => c.key === 'ops:start-item.sh')
  assert.ok(calls[at]?.prompt.endsWith(`\nRun exactly: scripts/factory/start-item.sh '${BASE}' '0-1' 'fix/0-1-an-item' 'run-1'`), calls[at]?.prompt)
  assert.ok(at > calls.findIndex((c) => c.key === 'picker'), 'after the picker named the branch')
  assert.ok(at < calls.findIndex((c) => /state\.sh 'branch'/.test(c.prompt)), 'before the lock records the branch')
  assert.match(calls.find((c) => c.key === 'picker').prompt, /do not create the branch/)
  assert.equal(calls.filter((c) => c.key === 'ops:start-item.sh').length, 1)
  // The work directory is the script's, not the picker's.
  const odd = await run({ answers: { picker: { ...DEFAULTS.picker, workDir: '.ai/work/elsewhere' } } })
  assert.match(odd.calls.find((c) => c.key === 'architect').prompt, /Work dir \.ai\/work\/0-1\./)
  const resumed = await run({ args: { branch: 'fix/0-1-an-item', item: '#0-1' } })
  assert.ok(!keys(resumed.calls).includes('ops:start-item.sh'), 'a resumed branch has started already')
  const none = await run({ answers: { picker: { none: true, reason: 'not ready' } } })
  assert.ok(!keys(none.calls).includes('ops:start-item.sh'))
  const failed = await run({ answers: { picker: { none: false, failed: true, reason: 'gh refused' } } })
  assert.ok(!keys(failed.calls).includes('ops:start-item.sh'))
  for (const slug of [undefined, '', 'An-item', 'a/b', 'a_b', '-a', 'a--b', 'a.b', 'a-b-c-d-e-f-g-h-i']) {
    const wrong = await run({ answers: { picker: { ...DEFAULTS.picker, slug } } })
    assert.ok(!keys(wrong.calls).includes('ops:start-item.sh'), `${slug}: refused before anything is created`)
  }
})

test('a resume switches in code: resume-item.sh before the picker, on resume only; the picker only reads (#0-215)', async () => {
  const { outcome, calls } = await run({ args: { branch: 'fix/0-1-an-item', item: '#0-1' } })
  assert.equal(outcome.outcome, 'SHIPPED')
  const at = calls.findIndex((c) => c.key === 'ops:resume-item.sh')
  assert.ok(calls[at]?.prompt.endsWith(`\nRun exactly: scripts/factory/resume-item.sh '${BASE}' 'fix/0-1-an-item'`), calls[at]?.prompt)
  assert.ok(at >= 0 && at < calls.findIndex((c) => c.key === 'picker'), 'before the picker')
  assert.equal(calls.filter((c) => c.key === 'ops:resume-item.sh').length, 1)
  assert.match(calls.find((c) => c.key === 'picker').prompt, /do not switch or create a branch/)
  assert.doesNotMatch(calls.find((c) => c.key === 'picker').prompt, /\(git switch /)
  // Without args.item the item is the branch's.
  const bare = await run({ args: { branch: 'fix/0-1-an-item' } })
  assert.equal(bare.outcome.outcome, 'SHIPPED'); assert.match(bare.calls.find((c) => c.key === 'picker').prompt, /Item #0-1\./)
  const fresh = await run()
  assert.ok(!keys(fresh.calls).includes('ops:resume-item.sh'), 'a fresh run starts its item instead')
  // A picker that fails on a resume without args.item is recorded against the branch's item, not lost (review of #0-215).
  const failed = await run({ args: { branch: 'fix/0-1-an-item' }, answers: { picker: { none: false, failed: true, reason: 'gh refused' } } })
  assert.equal(failed.outcome.outcome, 'BLOCKED'); assert.equal(failed.outcome.item, '#0-1')
  assert.ok(stateCalls(failed.calls).includes("scripts/factory/state.sh 'record' 'blocked' '0-1' '-' 'pick'"), stateCalls(failed.calls).join(' | '))
})

test("a resume's arguments are checked before anything moves; a refused switch stops the item at pick (#0-215)", async () => {
  for (const [args, why] of [
    [{ branch: 'main' }, /branch must be an item's branch/],
    [{ branch: 'fix/0-1' }, /branch must be an item's branch/],
    [{ branch: 'fix/0-1-an-item', item: '#0-2' }, /item #0-2 is not the item of the branch fix\/0-1-an-item \(#0-1\)/],
  ]) {
    const { outcome, calls } = await run({ args })
    assert.equal(outcome.outcome, 'NOT_STARTED', JSON.stringify(args)); assert.match(outcome.reasons[0], why)
    assert.ok(!keys(calls).includes('ops:resume-item.sh') && !keys(calls).includes('picker'), JSON.stringify(args))
  }
  for (const [answer, why] of [
    [{ ok: false, reasons: ['no local branch fix/0-1-an-item to resume'] }, /: no local branch fix\/0-1-an-item to resume$/],
    [{ error: 'resume-item.sh: Permission denied', exitCode: 126 }, /: resume-item\.sh: Permission denied$/],
    [{ ok: true, branch: 'fix/0-1-other', item: '0-1', head: SHA('d') }, /: no answer$/],
    [{ ok: true, branch: 'fix/0-1-an-item', item: '0-2', head: SHA('d') }, /: no answer$/],
    [{ ok: 'true', branch: 'fix/0-1-an-item', item: '0-1' }, /: no answer$/],
    [null, /: no answer/],
  ]) {
    const { outcome, calls } = await run({ args: { branch: 'fix/0-1-an-item', item: '#0-1' }, answers: { 'ops:resume-item.sh': answer } })
    const label = JSON.stringify(answer)
    assert.equal(outcome.outcome, 'BLOCKED', label); assert.equal(outcome.item, '#0-1', label)
    assert.match(outcome.reason, /^could not resume #0-1 on fix\/0-1-an-item/, label); assert.match(outcome.reason, why, label)
    assert.ok(stateCalls(calls).includes("scripts/factory/state.sh 'record' 'blocked' '0-1' '-' 'pick'"), stateCalls(calls).join(' | '))
    assert.ok(!keys(calls).includes('picker') && !keys(calls).includes('shipper'), label)
    assert.ok(keys(calls).includes('ops:return-to-main.sh') && keys(calls).includes('ops:notify.sh'), label)
  }
})

test('a start that fails stops the item at pick, recorded and notified, with no branch to push (#0-209)', async () => {
  for (const [answer, why] of [
    [{ ok: false, reasons: ['the branch fix/0-1-an-item exists already'] }, /: the branch fix\/0-1-an-item exists already$/],
    [{ error: 'start-item.sh: Permission denied', exitCode: 126 }, /: start-item\.sh: Permission denied$/],
    [{ ok: true, branch: 'fix/0-1-other', workDir: '.ai/work/0-1', head: SHA('d') }, /: no answer$/],
    [{ ok: 'true', branch: 'fix/0-1-an-item' }, /: no answer$/],
    [{ ok: true, branch: 'fix/0-1-an-item', head: SHA('d') }, /: no answer$/],
    [{ ok: true, branch: 'fix/0-1-an-item', workDir: '.ai/work/0-2', head: SHA('d') }, /: no answer$/],
    [null, /: no answer/],
  ]) {
    const { outcome, calls } = await run({ answers: { 'ops:start-item.sh': answer } })
    const label = JSON.stringify(answer)
    assert.equal(outcome.outcome, 'BLOCKED', label); assert.equal(outcome.item, '#0-1', label)
    assert.match(outcome.reason, /^could not start #0-1 on fix\/0-1-an-item/, label); assert.match(outcome.reason, why, label)
    assert.ok(stateCalls(calls).includes("scripts/factory/state.sh 'record' 'blocked' '0-1' '-' 'pick'"), stateCalls(calls).join(' | '))
    assert.ok(!stateCalls(calls).some((s) => s.includes("'branch'")), `${label}: no branch recorded in the lock`)
    assert.ok(!keys(calls).includes('shipper') && !keys(calls).includes('architect'), label)
    assert.ok(keys(calls).includes('ops:return-to-main.sh') && keys(calls).includes('ops:notify.sh'), label)
  }
})

test("the run's branch is recorded in the lock before any agent works on it, or the run stops", async () => {
  const { calls } = await run()
  const at = calls.findIndex((c) => /state\.sh 'branch' 'fix\/0-1-an-item'/.test(c.prompt))
  assert.ok(at > 0, 'state.sh branch <the picked branch>')
  assert.ok(at > calls.findIndex((c) => c.key === 'picker') && at < calls.findIndex((c) => c.key === 'architect'))
  const resumed = await run({ args: { branch: 'fix/0-1-an-item', item: '#0-1' } })
  assert.ok(resumed.calls.some((c) => /state\.sh 'branch' 'fix\/0-1-an-item'/.test(c.prompt)), 'a resumed run records it too')
  // The last two: what factory-ops answered in run wf_8c632098-97c (the schema refuses it now, so the runtime asks
  // again; were it to get through, the run still stops), and _common.sh's own failure (backlog #0-175).
  for (const answer of [{ error: 'this run already recorded its branch (fix/0-9-x)' }, { branch: 'fix/0-9-other' }, null,
    { output: '{"branch": "fix/0-1-an-item"}' }, { ok: false, reasons: ['jq is not installed'] }]) {
    const { outcome, calls: c } = await run({ answers: { 'ops:state.sh': ({ prompt }) => (/'branch'/.test(prompt) ? answer : {}) } })
    assert.equal(outcome.outcome, 'BLOCKED')
    assert.match(outcome.reason, /could not record the run's branch fix\/0-1-an-item/)
    if (answer?.reasons) assert.match(outcome.reason, /jq is not installed/, 'the stop names _common.sh\'s reason')
    assert.ok(!c.some((x) => x.key === 'architect' || x.key === 'shipper'), 'nothing works on, or pushes, a branch the lock does not name')
  }
})

test("the run's branch: code's prefix and the picker's slug, and on resume the owner's (#0-195)", async () => {
  // The prefix is next-item.sh's, read from the item's Type on the base commit; a branch the picker names is not used,
  // whatever its prefix (four runs gave a security item feat/, backlog #0-195).
  for (const prefix of ['refactor', 'perf', 'fix']) {
    const { outcome, calls } = await run({ answers: { 'ops:next-item.sh': { ...DEFAULTS['ops:next-item.sh'], branchPrefix: prefix },
      picker: { ...DEFAULTS.picker, branch: 'feat/0-1-the-pickers-own' } } })
    assert.equal(outcome.outcome, 'SHIPPED', prefix)
    assert.match(calls.find((c) => c.key === 'picker').prompt, new RegExp(`the branch is ${prefix}/0-1-<slug>`), prefix)
    assert.ok(calls.some((c) => c.prompt.includes(`start-item.sh '${BASE}' '0-1' '${prefix}/0-1-an-item'`)), `${prefix}: started on its branch`)
    assert.ok(calls.some((c) => c.prompt.includes(`state.sh 'branch' '${prefix}/0-1-an-item'`)), `${prefix}: recorded`)
    assert.ok(!calls.some((c) => c.prompt.includes('the-pickers-own')), `${prefix}: the picker's branch is never used`)
  }
  for (const slug of [undefined, 'Fix', 'a b', 'a/b', '0-1-x/y']) {
    const { outcome, calls } = await run({ answers: { picker: { ...DEFAULTS.picker, slug } } })
    assert.equal(outcome.outcome, 'BLOCKED', String(slug))
    assert.match(outcome.reason, /picker gave no usable slug for #0-1/, String(slug))
    assert.ok(!calls.some((c) => /state\.sh 'branch'/.test(c.prompt)), `${slug}: never recorded`)
  }
  const other = await run({ args: { branch: 'fix/0-1-an-item', item: '#0-1' }, answers: { picker: { ...DEFAULTS.picker, branch: 'fix/0-1-another' } } })
  assert.match(other.outcome.reason, /picker answered the branch fix\/0-1-another, not fix\/0-1-an-item/)
  assert.ok(!other.calls.some((c) => /state\.sh 'branch'/.test(c.prompt)))
})

test("the workflow's rule of an item's branch is the scripts' rule (#0-216)", async () => {
  // The rule lives twice, ITEM_BRANCH here and ITEM_BRANCH_RE in _common.sh (start-item.sh, resume-item.sh): a drift
  // stops a run at whichever copy is stricter. The same text first, then the same answers from both engines (bash's
  // ERE is not JavaScript's: a `\d` or a class the two read differently would pass the first check alone).
  const { ITEM_BRANCH } = await helpers()
  const common = readFileSync(join(dirname(FILE), '../../scripts/factory/_common.sh'), 'utf8')
  const shell = common.match(/^ITEM_BRANCH_RE='([^']+)'$/m)?.[1]
  assert.ok(shell, '_common.sh defines ITEM_BRANCH_RE')
  assert.equal(ITEM_BRANCH.source.replaceAll('\\/', '/'), shell)
  assert.equal(ITEM_BRANCH.flags, '', 'no flag: bash has none, and `g` would make exec() stateful')
  const names = ['fix/0-1-an-item', 'ci/0-216-one.rule_v2', 'feat/0-40-A-b', 'fix/0-10-x', 'main', 'fix/0-1', 'fix/0-1-',
    'fix/x0-1-y', 'fix/0-1-a/b', 'Fix/0-1-x', 'fix/0-1-a b', '/0-1-x', 'fix/0-1-x\nfix', 'review/0123abcd']
  for (const name of names) {
    const js = ITEM_BRANCH.exec(name)?.[1] ?? null
    const sh = spawnSync('bash', ['-c', '[[ $2 =~ $1 ]] && printf %s "${BASH_REMATCH[1]}"', 'match', shell, name], { encoding: 'utf8' })
    assert.equal(sh.error, undefined, 'bash runs')
    assert.equal(sh.status === 0 ? sh.stdout : null, js, JSON.stringify(name))
  }
  assert.equal(ITEM_BRANCH.exec('ci/0-216-one.rule_v2')?.[1], '0-216')
})

test('complexity: anything but low, in the backlog or the pick, takes the full implementer', async () => {
  for (const [next, pick] of [['high', 'low'], ['low', 'medium'], [undefined, 'low']]) {
    const { calls } = await run({ answers: {
      'ops:next-item.sh': { ...DEFAULTS['ops:next-item.sh'], complexity: next }, picker: { ...DEFAULTS.picker, complexity: pick } } })
    assert.ok(keys(calls).includes('implementer') && !keys(calls).includes('implementer-light'), `${next}/${pick}`)
  }
})

test('plan and implementation: a block or no answer stops the item', async () => {
  for (const [answers, why] of [
    [{ architect: null }, /architect gave no answer/],
    [{ architect: { blocked: true, reason: 'irreversible' } }, /architect: irreversible/],
    [{ 'implementer-light': null }, /implementer gave no answer/],
    [{ 'implementer-light': { blocked: true, reason: 'ambiguous', headSha: SHA('b') } }, /implementer: ambiguous/],
  ]) {
    const { outcome } = await run({ answers })
    assert.equal(outcome.outcome, 'BLOCKED'); assert.match(outcome.reason, why)
  }
})

test('self-check: a rule file the diff calls for and the plan did not cover', async () => {
  const paths = { ...DEFAULTS['ops:changed-paths.sh'], ruleFiles: ['general', 'migration'] }
  const { calls } = await run({ answers: { 'ops:changed-paths.sh': paths } })
  const check = calls.find((c) => c.label === 'self-check migration')
  assert.ok(check, 'the implementer checks the change against migration.md')
  assert.match(check.prompt, /\.ai\/rules\/review\/migration\.md/)
  const covered = await run({ answers: { 'ops:changed-paths.sh': paths,
    architect: { ...DEFAULTS.architect, rules: [{ id: 'MIG-02' }] } } })
  assert.ok(!covered.calls.some((c) => c.label?.startsWith('self-check')), 'the plan listed a migration rule: no self-check')
  const none = await run({ answers: { 'ops:changed-paths.sh': (c) => (c.n === 1 ? { ...paths, ruleFiles: undefined } : paths) } })
  assert.match(none.outcome.reason, /changed-paths returned no rule files/)
})

test('the path gate: a change that needs the owner stops before the tests run', async () => {
  const paths = { ...DEFAULTS['ops:changed-paths.sh'], needsHuman: true, protectedTouched: ['.github/workflows/ci.yml'] }
  const { outcome, calls } = await run({ answers: { 'ops:changed-paths.sh': (c) => (c.n === 1 ? DEFAULTS['ops:changed-paths.sh'] : paths) } })
  assert.equal(outcome.outcome, 'BLOCKED')
  assert.match(outcome.reason, /NEEDS_HUMAN — human-owned paths changed: \.github\/workflows\/ci\.yml/)
  assert.ok(!keys(calls).includes('ops:run-tests.sh'))
})

test('the test gate: stop, a pass without its artifact, another commit, failing tests after the fixes', async () => {
  const gate = DEFAULTS['ops:run-tests.sh']
  for (const [answers, why] of [
    [{ 'ops:run-tests.sh': { status: 'stop', log: 'l', summary: ['Docker is not running'] } }, /test gate stopped \(log l\): Docker is not running/],
    [{ 'ops:run-tests.sh': { ...gate, artifact: null } }, /passed without its artifact/],
    [{ 'ops:run-tests.sh': { ...gate, head: SHA('d') } }, /the tested commit \(d{40}\) is not the branch HEAD/],
    [{ 'ops:run-tests.sh': { ...gate, status: 'fixable', summary: ['1 failed'] } }, /tests still failing after 2 fix attempts/],
    [{ 'ops:run-tests.sh': null }, /test gate returned no result/],
  ]) {
    const { outcome } = await run({ answers })
    assert.equal(outcome.outcome, 'BLOCKED'); assert.match(outcome.reason, why)
  }
  const fixed = await run({ answers: { 'ops:run-tests.sh': (c) => (c.n === 1 ? { ...gate, status: 'fixable', summary: ['1 failed'] } : gate) } })
  assert.equal(fixed.outcome.outcome, 'SHIPPED', 'a fixable failure the implementer fixes goes on')
  assert.ok(fixed.calls.some((c) => c.label === 'fix tests r1'))
})

test('the panel: an invalid verdict, a wrong dimension, NEEDS_HUMAN or an upheld dispute stops the item', async () => {
  for (const [answer, why] of [
    [{ ...approve('security'), blocking: [{ id: 's-1', ruleId: 'SEC-01' }] }, /no valid verdict in round 1 \(fail closed\)/],
    [approve('general'), /no valid verdict in round 1/],
    [null, /no valid verdict in round 1/],
    [approve('security', { verdict: 'NEEDS_HUMAN' }), /NEEDS_HUMAN from security/],
    [approve('security', { upheldDisputes: [{ id: 's-1' }] }), /dispute upheld by security/],
  ]) {
    const { outcome } = await run({ answers: { 'review-security': answer } })
    assert.equal(outcome.outcome, 'BLOCKED'); assert.match(outcome.reason, why)
  }
})

const FINDING = { id: 'sec-1a2b', ruleId: 'SEC-01', issue: 'a leak', impact: 'tenant data' }

test('a blocking finding is fixed in a second round, judged by its dimension, security and general', async () => {
  const { outcome, calls } = await run({ answers: {
    'review-architecture': (c) => (c.n === 1 ? approve('architecture', { verdict: 'CHANGES_REQUESTED', blocking: [FINDING] }) : approve('architecture')) } })
  assert.equal(outcome.outcome, 'SHIPPED'); assert.equal(outcome.rounds, 2)
  const fix = calls.find((c) => c.label === 'fix r1')
  assert.match(fix.prompt, /sec-1a2b/)
  const round2 = calls.slice(calls.indexOf(fix)).filter((c) => c.key.startsWith('review-')).map((c) => c.key).sort()
  assert.deepEqual(round2, ['review-architecture', 'review-general', 'review-security'])
  assert.match(round2.length && calls.filter((c) => c.key === 'review-architecture')[1].prompt, /previousRoundSha: c{40}/)
})

test('the same blocking findings after a fix round: no progress; three rounds without approval: BLOCKED', async () => {
  const blocked = approve('architecture', { verdict: 'CHANGES_REQUESTED', blocking: [FINDING] })
  const same = await run({ answers: { 'review-architecture': blocked } })
  assert.equal(same.outcome.outcome, 'BLOCKED'); assert.match(same.outcome.reason, /no progress: the same blocking findings \(sec-1a2b\)/)
  const moving = await run({ answers: { 'review-architecture': (c) =>
    approve('architecture', { verdict: 'CHANGES_REQUESTED', blocking: [{ ...FINDING, id: `arc-${c.n}` }] }) } })
  assert.equal(moving.outcome.outcome, 'BLOCKED'); assert.match(moving.outcome.reason, /review did not converge in 3 rounds/)
  const one = await run({ args: { maxRounds: 1 }, answers: { 'review-architecture': blocked } })
  assert.match(one.outcome.reason, /review did not converge in 1 rounds/)
})

test('a claim the panel could not check: unverifiable stops for the owner, who accepts it by id on resume', async () => {
  const claim = 'The library is not affected by CVE-2026-1'
  const answers = {
    'review-general': approve('general', { unverified: [claim] }),
    verifier: { items: [{ index: 0, verdict: 'unverifiable', source: null, quote: null, why: 'no allowed source' }] },
  }
  const first = await run({ answers })
  assert.equal(first.outcome.outcome, 'BLOCKED')
  const id = first.outcome.reason.match(/ver-[0-9a-f]{8}/)[0]
  assert.match(first.outcome.reason, /NEEDS_HUMAN — the verifier could not settle 1 claim/)
  const resumed = await run({ args: { branch: 'fix/0-1-an-item', item: '#0-1', acceptUnverifiable: [id] }, answers })
  assert.equal(resumed.outcome.outcome, 'SHIPPED')
  assert.ok(!keys(resumed.calls).includes('architect') && !keys(resumed.calls).includes('ops:next-item.sh'), 'resume skips pick, plan, implement')
  const ship = resumed.calls.find((c) => c.key === 'shipper')
  assert.match(ship.prompt, /"acceptedByOwner":true/)
  const another = await run({ args: { branch: 'fix/0-1-an-item', item: '#0-1', acceptUnverifiable: ['ver-00000000'] }, answers })
  assert.equal(another.outcome.outcome, 'BLOCKED', 'an id the owner did not give accepts nothing')
})

test('a refuted claim blocks like a finding, and goes back to the dimension that raised it', async () => {
  const { outcome, calls } = await run({ answers: {
    'review-performance': (c) => approve('performance', { unverified: c.n === 1 ? ['Kafka 4 batches by default'] : [] }),
    verifier: { items: [{ index: 0, verdict: 'refuted', source: 'https://kafka.apache.org', quote: 'it does not', why: 'w' }] },
  } })
  assert.equal(outcome.outcome, 'SHIPPED'); assert.equal(outcome.rounds, 2)
  const fix = calls.find((c) => c.label === 'fix r1')
  assert.match(fix.prompt, /refuted: Kafka 4 batches by default/)
  const round2 = calls.slice(calls.indexOf(fix)).filter((c) => c.key.startsWith('review-')).map((c) => c.key)
  assert.ok(round2.includes('review-performance'))
  const again = await run({ answers: {
    'review-performance': approve('performance', { unverified: ['Kafka 4 batches by default'] }),
    verifier: { items: [{ index: 0, verdict: 'refuted', source: 's', quote: 'q', why: 'w' }] } } })
  assert.match(again.outcome.reason, /no progress: the same blocking findings \(ver-[0-9a-f]{8}\)/)
})

test('acceptance: a rejection is fixed once and reviewed again; twice rejected, or no answer, stops', async () => {
  const reject = { verdict: 'REJECT', criteria: [{ id: 'AC1', met: false }] }
  const fixed = await run({ answers: { 'acceptance-reviewer': (c) => (c.n === 1 ? reject : DEFAULTS['acceptance-reviewer']) } })
  assert.equal(fixed.outcome.outcome, 'SHIPPED')
  assert.ok(fixed.calls.some((c) => c.label === 'fix acceptance'))
  assert.ok(fixed.calls.some((c) => c.key.startsWith('review-') && /round: 3/.test(c.prompt)), 'the delta gets a final round')
  assert.match((await run({ answers: { 'acceptance-reviewer': reject } })).outcome.reason, /acceptance rejected twice/)
  assert.match((await run({ answers: { 'acceptance-reviewer': null } })).outcome.reason, /acceptance-reviewer gave no answer/)
  const failing = await run({ answers: { 'acceptance-reviewer': (c) => (c.n === 1 ? reject : DEFAULTS['acceptance-reviewer']),
    'review-docs': (c) => (/round: 3/.test(c.prompt) ? approve('docs', { verdict: 'CHANGES_REQUESTED' }) : approve('docs')) } })
  assert.match(failing.outcome.reason, /the acceptance fix did not pass a final review round/)
})

test('risk: anything but low, in the backlog or the pick, is high; only low risk with shadow off auto-merges', async () => {
  const off = { shadow: false }
  const low = await run({ args: off })
  assert.equal(low.outcome.mode, 'auto-merge')
  assert.match(low.calls.find((c) => c.key === 'shipper').prompt, /merge: true\./)
  for (const answers of [
    { picker: { ...DEFAULTS.picker, risk: 'medium' } },
    { 'ops:next-item.sh': { ...DEFAULTS['ops:next-item.sh'], risk: 'high' } },
    { picker: { ...DEFAULTS.picker, risk: undefined } },
  ]) {
    const { outcome, calls } = await run({ args: off, answers })
    assert.equal(outcome.mode, 'risk-high')
    assert.match(calls.find((c) => c.key === 'shipper').prompt, /risk-high: true\. merge: false\./)
  }
  const needsHuman = await run({ answers: { 'acceptance-reviewer': { verdict: 'NEEDS_HUMAN', criteria: [], reason: 'unclear AC' } } })
  assert.match(needsHuman.outcome.reason, /acceptance NEEDS_HUMAN: unclear AC/)
  const highNeedsHuman = await run({ answers: { picker: { ...DEFAULTS.picker, risk: 'high' },
    'acceptance-reviewer': { verdict: 'NEEDS_HUMAN', criteria: [], reason: 'unclear AC' } } })
  assert.equal(highNeedsHuman.outcome.outcome, 'SHIPPED', 'a high-risk item goes to the owner as a PR anyway')
})

test('ship: no PR stops; a PR with an error is recorded, not shipped again as blocked', async () => {
  assert.match((await run({ answers: { shipper: { mode: 'ship', prUrl: null, error: 'gh failed' } } })).outcome.reason, /shipper failed: gh failed/)
  const { outcome, calls } = await run({ answers: { shipper: { ...DEFAULTS.shipper, error: 'label missing' } } })
  assert.equal(outcome.outcome, 'SHIPPED_WITH_ERROR')
  assert.equal(calls.filter((c) => c.key === 'shipper').length, 1, 'no blocked-mode shipper on a published PR')
  const state = calls.filter((c) => c.key === 'ops:state.sh').map((c) => c.prompt).join('\n')
  assert.match(state, /'record' 'blocked' '0-1' 'https:\/\/github\.com\/o\/r\/pull\/7'/)
})

test('a BLOCKED item with a branch gets a draft PR and its stop stage recorded', async () => {
  const { outcome, calls } = await run({ answers: { architect: { blocked: true, reason: 'irreversible' } } })
  assert.equal(outcome.outcome, 'BLOCKED')
  const draft = calls.find((c) => c.key === 'shipper')
  assert.match(draft.prompt, /^You are running as the `shipper` agent[\s\S]*Mode: blocked\./)
  const state = calls.filter((c) => c.key === 'ops:state.sh').map((c) => c.prompt).join('\n')
  assert.match(state, /'record' 'blocked' '0-1' 'https:\/\/github\.com\/o\/r\/pull\/7' 'plan'/)
})

test('an unsafe value never reaches a factory script', async () => {
  const { outcome } = await run({ answers: { 'ops:preflight.sh': { ...DEFAULTS['ops:preflight.sh'], baseSha: undefined } } })
  assert.deepEqual(outcome.reasons, ['preflight returned no base commit'], 'no sha, no script call with it')
  const bad = await run({ answers: { shipper: { ...DEFAULTS.shipper, prUrl: 'https://x/pull/7; rm -rf /' } } })
  const state = bad.calls.filter((c) => c.key === 'ops:state.sh').map((c) => c.prompt).join('\n')
  assert.match(state, /'record' 'shipped' '0-1' '-'/, 'an odd PR URL is recorded as "-", the record is not lost')
  assert.doesNotMatch(state, /rm -rf/)
})

test('the agent budget: past 45 work-agent calls an agent answers nothing, and the stop names the budget', async () => {
  const h = await helpers({ answers: { implementer: { blocked: false, headSha: SHA('b') } } })
  for (let i = 0; i < 45; i++) assert.ok(await h.as('implementer', 'p'), `call ${i + 1} reaches the agent`)
  assert.ok(await h.as('factory-ops', 'Run exactly: scripts/factory/state.sh'), 'factory-ops is not budgeted')
  assert.ok(await h.as('shipper', 'p'), 'the shipper is not budgeted')
  const before = h.calls.length
  assert.equal(await h.as('implementer', 'p'), null, 'the 46th work-agent call')
  assert.equal(h.calls.length, before, 'it never reaches the agent')
  const stopped = await h.stopItem(null, 'implementer gave no answer')
  assert.equal(stopped.outcome, 'BLOCKED')
  assert.match(stopped.reason, /^agent budget of 45 calls exceeded — split the item \(last step: implementer gave no answer\)$/)
})

// ---------------------------------------------------------------- seed-bugs.js (backlog #0-170)

const SEED = readFileSync(join(dirname(FILE), 'seed-bugs.js'), 'utf8')
const SEED_ARGS = { pattern: 'P-10', commit: 'abc1234', runId: 'r1' }
// The branch of P-10, run r1: FNV-1a of "P-10\nr1" (seed-bugs.js, seedBranchOf; backlog #0-177).
const BRANCH = 'review/0684d0a2'
const SEEDED = { ok: true, branch: BRANCH, base: 'b'.repeat(40), head: 'c'.repeat(40), files: ['svc/src/main/java/A.java'] }
// seed-check.sh's hunks: the seeder's edit, lines 38-42 of A.java (backlog #0-181); TRUTH's line 40 is inside.
const CHECKED = { ok: true, files: ['svc/src/main/java/A.java'], hunks: [{ file: 'svc/src/main/java/A.java', start: 38, end: 42 }] }
const FOLDED = { ok: true, head: 'e'.repeat(40) }
// seed-compile.sh's answer: the planted module built (backlog #0-181).
const COMPILED = { ok: true, compiled: true, modules: 'svc' }
const RECORDED = { appended: true, file: '.ai/runs/benchmark/results.md' }
async function seed(answers, ...given) {
  const args = given.length ? given[0] : SEED_ARGS   // not a default parameter: a test passes undefined itself
  const fake = fakeAgent({ 'ops:seed-branch.sh': SEEDED, 'ops:seed-check.sh': CHECKED, 'ops:seed-fold.sh': FOLDED,
    'ops:seed-compile.sh': COMPILED, 'ops:seed-record.sh': RECORDED, 'ops:return-to-main.sh': { onMain: true }, ...answers })
  const outcome = await evaluate(strip(SEED), { args, agent: fake.agent, logs: [] })
  return { outcome, calls: fake.calls }
}
const TRUTH = { branch: BRANCH, pattern: 'P-10', dimension: 'performance', rule: 'PERF-01',
  file: 'svc/src/main/java/A.java', line: 40 }

// A clean run (backlog #0-180): a C- pattern, the rule's deliberate exception planted with its reason.
const CLEAN_ARGS = { pattern: 'C-01', commit: 'abc1234', runId: 'c1' }
const CLEAN_TRUTH = { branch: 'review/' + 'x', pattern: 'C-01', kind: 'clean', dimension: 'architecture', rule: 'ARC-23',
  file: 'svc/src/main/java/A.java', line: 40 }
const cleanSeed = async (answers) => {
  const first = await seed({ 'defect-seeder': CLEAN_TRUTH }, CLEAN_ARGS)
  const branch = first.calls.find((c) => c.key === 'ops:seed-branch.sh').prompt.match(/review\/[0-9a-f]{8}/)[0]
  return seed({ ...answers, 'defect-seeder': { ...CLEAN_TRUTH, branch }, 'ops:seed-branch.sh': { ...SEEDED, branch } }, CLEAN_ARGS)
}
const recordArgs = (calls) => [...calls.find((c) => c.key === 'ops:seed-record.sh').prompt.matchAll(/'([^']*)'/g)].map((m) => m[1])

test('seed-bugs: a clean run no dimension stops is a pass, recorded in its own table (#0-180)', async () => {
  const noted = approve('architecture', { nonBlocking: [{ issue: 'per replica on purpose', file: CLEAN_TRUTH.file, line: 41 }] })
  const elsewhere = approve('general', { verdict: 'CHANGES_REQUESTED', blocking: [{ issue: 'another file', file: 'svc/B.java', line: 3 }] })
  const { outcome, calls } = await cleanSeed({ 'review-architecture': noted, 'review-general': elsewhere })
  assert.equal(outcome.outcome, 'MEASURED')
  assert.equal(outcome.kind, 'clean')
  assert.deepEqual(outcome.falseAlarmBy, [])
  assert.deepEqual(outcome.raisedBy, ['architecture'])
  assert.deepEqual(outcome.blockingElsewhere, ['general'])
  assert.equal(outcome.caughtByExpected, undefined, 'a clean run has no catch to count')
  assert.deepEqual(recordArgs(calls), ['--clean', 'c1', 'C-01', 'ARC-23', 'architecture', '-', 'architecture', 'general', '-'])
  assert.match(outcome.cleanup, /\.ai\/runs\/benchmark\/clean\.md into \.ai\/audit\/benchmark\/clean\.md/)
})

test('seed-bugs: a clean run a dimension stops under its rule is its false alarm, by blocking or by NEEDS_HUMAN (#0-180)', async () => {
  const blocks = approve('architecture', { verdict: 'CHANGES_REQUESTED', blocking: [{ issue: 'no lock', file: CLEAN_TRUTH.file, line: 40 }] })
  const human = approve('security', { verdict: 'NEEDS_HUMAN', nonBlocking: [{ ruleId: 'ARC-23', issue: 'no lock?', file: CLEAN_TRUTH.file, line: 39 }] })
  const { outcome, calls } = await cleanSeed({ 'review-architecture': blocks, 'review-security': human })
  assert.deepEqual(outcome.falseAlarmBy.sort(), ['architecture', 'security'])
  assert.deepEqual(outcome.raisedBy, [])
  assert.equal(recordArgs(calls)[5], 'architecture,security')
})

test('seed-bugs: a stop at the plant under another rule is raised, not a false alarm (clean-c01)', async () => {
  const test = approve('general', { verdict: 'NEEDS_HUMAN', blocking: [{ ruleId: 'GEN-01', issue: 'no test', file: CLEAN_TRUTH.file, line: 41 }] })
  const other = approve('security', { verdict: 'CHANGES_REQUESTED', blocking: [{ issue: 'something else', file: CLEAN_TRUTH.file, line: 40 }] })
  const { outcome } = await cleanSeed({ 'review-general': test, 'review-security': other })
  assert.deepEqual(outcome.falseAlarmBy, [], 'another rule, or another dimension without a rule id, is not the exception\'s false alarm')
  assert.deepEqual(outcome.raisedBy.sort(), ['general', 'security'])
})

test('seed-bugs: a clean run matches the rule id trimmed, in any case, as a prefix, never a longer id (#0-180 r1)', async () => {
  const at = (dimension, ruleId) => approve(dimension, { verdict: 'CHANGES_REQUESTED', blocking: [{ ruleId, issue: 'stop', file: CLEAN_TRUTH.file, line: 40 }] })
  const { outcome } = await cleanSeed({
    'review-architecture': at('architecture', '   '),
    'review-security': at('security', ` ${CLEAN_TRUTH.rule.toLowerCase()} (exception) `),
    'review-general': at('general', `${CLEAN_TRUTH.rule}0`),
    'review-performance': at('performance', `PERF-01, not ${CLEAN_TRUTH.rule}`),
  })
  assert.deepEqual(outcome.falseAlarmBy.sort(), ['architecture', 'security'], 'a blank id falls back to the expected dimension')
  assert.deepEqual(outcome.raisedBy.sort(), ['general', 'performance'], 'a longer id, or one cited second, is another rule')
})

test('seed-bugs: the kind comes from the pattern id, never from the seeder (#0-180)', async () => {
  const first = await seed({ 'defect-seeder': CLEAN_TRUTH }, CLEAN_ARGS)
  const branch = first.calls.find((c) => c.key === 'ops:seed-branch.sh').prompt.match(/review\/[0-9a-f]{8}/)[0]
  const said = await seed({ 'defect-seeder': { ...CLEAN_TRUTH, branch, kind: 'defect' }, 'ops:seed-branch.sh': { ...SEEDED, branch } }, CLEAN_ARGS)
  assert.equal(said.outcome.outcome, 'FAILED')
  const { kind, ...unsaid } = CLEAN_TRUTH
  const silent = await seed({ 'defect-seeder': { ...unsaid, branch }, 'ops:seed-branch.sh': { ...SEEDED, branch } }, CLEAN_ARGS)
  assert.equal(silent.outcome.outcome, 'FAILED', 'a clean run needs kind: clean said, not assumed (review round 2)')
  assert.equal((await seed({ 'defect-seeder': TRUTH })).outcome.outcome, 'MEASURED', 'a defect run may leave kind out')
  const defect = await seed({ 'defect-seeder': { ...TRUTH, kind: 'clean' } })
  assert.equal(defect.outcome.outcome, 'FAILED')
  assert.ok(!defect.calls.some((c) => c.key.startsWith('review-')), 'no panel on a ground truth of the other kind')
})

test('seed-bugs: NEEDS_HUMAN with the planted line counts as blocking (#0-180 Also)', async () => {
  const human = approve('performance', { verdict: 'NEEDS_HUMAN', nonBlocking: [{ issue: 'N+1?', file: TRUTH.file, line: 41 }] })
  const { outcome } = await seed({ 'defect-seeder': TRUTH, 'review-performance': human })
  assert.equal(outcome.blockingByExpected, true)
  const elsewhere = approve('performance', { verdict: 'NEEDS_HUMAN', nonBlocking: [{ issue: 'other', file: 'svc/B.java', line: 1 }] })
  assert.equal((await seed({ 'defect-seeder': TRUTH, 'review-performance': elsewhere })).outcome.blockingByExpected, false)
})

test('seed-bugs: a blocked seeder is a failed run with its reason, not a skip', async () => {
  const { outcome, calls } = await seed({ 'defect-seeder': { blocked: true, reason: 'git -C /workspace show: refused' } })
  assert.equal(outcome.outcome, 'FAILED')
  assert.match(outcome.reason, /defect-seeder was blocked: git -C \/workspace show: refused/)
  assert.ok(!calls.some((c) => c.key.startsWith('review-')), 'no panel runs on a branch that was never made')
  const long = await seed({ 'defect-seeder': { blocked: true, reason: 'x'.repeat(5000) } })
  assert.ok(long.outcome.reason.length < 400, 'the reason is cut short')
})

test('seed-bugs: a skip says why, or the run failed', async () => {
  const fits = await seed({ 'defect-seeder': { skipped: true, reason: 'no repository loop in this change' } })
  assert.deepEqual(fits.outcome, { outcome: 'SKIPPED', reason: 'no repository loop in this change', cleanup: `git branch -D ${BRANCH}` })
  const silent = await seed({ 'defect-seeder': { skipped: true } })
  assert.equal(silent.outcome.outcome, 'FAILED')
  assert.match(silent.outcome.reason, /skipped without a reason/)
})

test('seed-bugs: a ground truth the Record phase cannot use fails the run', async () => {
  for (const truth of [{ ...TRUTH, branch: undefined }, { ...TRUTH, branch: 'main' }, { ...TRUTH, branch: 'review/0584cf0f' },
    { ...TRUTH, file: '' }, { ...TRUTH, file: 'svc/src/main/java/Other.java' }, { ...TRUTH, line: undefined },
    { ...TRUTH, rule: '' }, { ...TRUTH, rule: "PERF-01' 'x" }, { ...TRUTH, rule: 'perf-01' }, { ...TRUTH, dimension: 'frontend' }]) {
    const { outcome } = await seed({ 'defect-seeder': truth })
    assert.equal(outcome.outcome, 'FAILED', JSON.stringify(truth))
    assert.match(outcome.reason, /ground truth is incomplete/)
  }
  assert.equal((await seed({ 'defect-seeder': null })).outcome.outcome, 'FAILED')
  // A dimension or a rule id may hold a digit (k8s, K8S-08: #0-115's k8s.md); the run measures, it does not fail.
  const k8s = await seed({ 'defect-seeder': { ...TRUTH, dimension: 'k8s', rule: 'K8S-08' } })
  assert.equal(k8s.outcome.outcome, 'MEASURED', JSON.stringify(k8s.outcome))
  // A factory id has a letter after the dash (FAC-A02: #0-115's F1, #0-185); one with two still fails.
  const fac = await seed({ 'defect-seeder': { ...TRUTH, dimension: 'architecture', rule: 'FAC-A02' } })
  assert.equal(fac.outcome.outcome, 'MEASURED', JSON.stringify(fac.outcome))
  assert.equal((await seed({ 'defect-seeder': { ...TRUTH, dimension: 'architecture', rule: 'FAC-AB02' } })).outcome.outcome, 'FAILED')
})

test('seed-bugs: a planted defect is measured and recorded', async () => {
  const caught = approve('performance', { verdict: 'CHANGES_REQUESTED',
    blocking: [{ id: 'p-1', ruleId: 'PERF-01', file: TRUTH.file, line: 42, impact: 'N+1 per request' }] })
  const { outcome, calls } = await seed({ 'defect-seeder': TRUTH, 'review-performance': caught })
  assert.equal(outcome.outcome, 'MEASURED')
  assert.equal(outcome.caughtByExpected, true)
  assert.equal(outcome.blockingByExpected, true)
  assert.ok(calls.some((c) => c.key === 'ops:seed-record.sh'), 'the row is recorded')
  assert.equal(outcome.recorded, true)
  const missed = await seed({ 'defect-seeder': TRUTH })
  assert.equal(missed.outcome.caughtByExpected, false)
})

// The ground truth is the seeder's edit (backlog #0-181): seed-check.sh's hunks, plus at most two places the seeder left
// unedited on purpose; a finding within 5 lines of any of them is at the plant.
const A = 'svc/src/main/java/A.java'
const hunked = (hunks, files = [A]) => ({ 'ops:seed-check.sh': { ok: true, files, hunks } })
const finding = (dimension, line, file = A, extra = {}) => approve(dimension, { verdict: 'CHANGES_REQUESTED',
  blocking: [{ issue: 'stop', file, line, ...extra }] })

test('seed-bugs: a finding anywhere in the edit, or within 5 lines of it, is at the plant (#0-181)', async () => {
  // A method and its Javadoc, lines 30-42; the seeder named line 40 (clean-c01-r2: a note at the Javadoc, line 145,
  // seven lines above the named line 152, was out of the row).
  const { outcome } = await seed({ 'defect-seeder': TRUTH, ...hunked([{ file: A, start: 30, end: 42 }]),
    'review-performance': finding('performance', 25), 'review-docs': finding('docs', 47),
    'review-general': finding('general', 24), 'review-security': finding('security', 48) })
  assert.equal(outcome.caughtByExpected, true, 'performance at line 25: 5 above the hunk')
  assert.deepEqual(outcome.caughtBy.sort(), ['docs', 'performance'], 'lines 24 and 48 are 6 away: not at the plant')
  // Two hunks, the second in another file the seeder changed.
  const two = await seed({ 'defect-seeder': TRUTH, ...hunked([{ file: A, start: 40, end: 40 }, { file: 'svc/B.java', start: 7, end: 9 }],
    [A, 'svc/B.java']), 'review-docs': finding('docs', 8, 'svc/B.java') })
  assert.deepEqual(two.outcome.caughtBy, ['docs'])
  assert.deepEqual(two.outcome.onlyAtAlso, [], 'a hunk is the edit, not a named place')
})

test('seed-bugs: a clean run counts a stop at its Javadoc as a false alarm, not only at the named line (#0-181)', async () => {
  const javadoc = approve('architecture', { verdict: 'CHANGES_REQUESTED', blocking: [{ ruleId: 'ARC-23', issue: 'no lock', file: A, line: 31 }] })
  const first = await seed({ 'defect-seeder': CLEAN_TRUTH }, CLEAN_ARGS)
  const branch = first.calls.find((c) => c.key === 'ops:seed-branch.sh').prompt.match(/review\/[0-9a-f]{8}/)[0]
  const { outcome } = await seed({ 'defect-seeder': { ...CLEAN_TRUTH, branch }, 'ops:seed-branch.sh': { ...SEEDED, branch },
    ...hunked([{ file: A, start: 31, end: 40 }]), 'review-architecture': javadoc }, CLEAN_ARGS)
  assert.deepEqual(outcome.falseAlarmBy, ['architecture'], 'line 31 is 9 above the named line 40, inside the edit')
})

test('seed-bugs: a place the seeder left unedited counts, and the outcome says who reached only it (#0-181)', async () => {
  const truth = { ...TRUTH, also: [{ file: 'README.md', line: 120 }, { file: A, line: 7 }] }
  const { outcome, calls } = await seed({ 'defect-seeder': truth, 'review-docs': finding('docs', 123, 'README.md'),
    'review-performance': finding('performance', 41), 'review-general': finding('general', 3) })
  assert.match(calls.find((c) => c.key === 'ops:seed-check.sh').prompt, / 'performance' 'README\.md:120' 'svc\/src\/main\/java\/A\.java:7'$/,
    'each place reaches seed-check.sh, which checks it is a regular file at HEAD with the line')
  assert.deepEqual(outcome.caughtBy.sort(), ['docs', 'general', 'performance'])
  assert.deepEqual(outcome.onlyAtAlso.sort(), ['docs', 'general'], 'performance reached the edit itself')
  // A place in another file at a line the edit's file has in a hunk is not inside the edit.
  const other = await seed({ 'defect-seeder': { ...TRUTH, also: [{ file: 'README.md', line: 40 }] } })
  assert.equal(other.outcome.outcome, 'MEASURED', JSON.stringify(other.outcome))
})

test('seed-bugs: a truth the edit does not hold, or places that are not at most two plain ones, fail the run (#0-181)', async () => {
  for (const [name, answers, reason] of [
    ['the named line outside the edit', { 'defect-seeder': { ...TRUTH, line: 44 } }, /line is not in its edit/],
    ['no hunks', hunked([]), /line is not in its edit/],
    ['hunks missing', { 'ops:seed-check.sh': { ok: true, files: [A] } }, /line is not in its edit/],
    ['a hunk in a file the seeder did not change', hunked([{ file: A, start: 38, end: 42 }, { file: 'svc/C.java', start: 1, end: 1 }]), /line is not in its edit/],
    ['a hunk that ends before it starts', hunked([{ file: A, start: 38, end: 42 }, { file: A, start: 9, end: 5 }]), /line is not in its edit/],
    ['a hunk at line 0', hunked([{ file: A, start: 38, end: 42 }, { file: A, start: 0, end: 0 }]), /line is not in its edit/],
    ['a hunk as strings', hunked([{ file: A, start: '38', end: '42' }]), /line is not in its edit/],
    ['three places', { 'defect-seeder': { ...TRUTH, also: [1, 2, 3].map((line) => ({ file: A, line })) } }, /at most two/],
    ['a place above the tree', { 'defect-seeder': { ...TRUTH, also: [{ file: '../x', line: 1 }] } }, /at most two/],
    ['a place in a dot-dot directory', { 'defect-seeder': { ...TRUTH, also: [{ file: 'a/../b', line: 1 }] } }, /at most two/],
    ['an absolute place', { 'defect-seeder': { ...TRUTH, also: [{ file: '/etc/passwd', line: 1 }] } }, /at most two/],
    ['a place with a quote', { 'defect-seeder': { ...TRUTH, also: [{ file: "a' 'b", line: 1 }] } }, /at most two/],
    ['a place at line 0', { 'defect-seeder': { ...TRUTH, also: [{ file: A, line: 0 }] } }, /at most two/],
    ['places not a list', { 'defect-seeder': { ...TRUTH, also: { file: A, line: 1 } } }, /at most two/],
    ['a place inside the edit', { 'defect-seeder': { ...TRUTH, also: [{ file: A, line: 42 }] } }, /inside its edit/],
  ]) {
    const { outcome } = await seed({ 'defect-seeder': TRUTH, ...answers })
    assert.equal(outcome.outcome, 'FAILED', name)
    assert.match(outcome.reason, reason, name)
  }
  // A line beside a deletion is in the edit: a removed line leaves a hunk of one line where it was.
  const del = await seed({ 'defect-seeder': { ...TRUTH, line: 41 }, ...hunked([{ file: A, start: 40, end: 40 }]) })
  assert.equal(del.outcome.outcome, 'MEASURED', JSON.stringify(del.outcome))
})

test('seed-bugs: the branch comes from seed-branch.sh, never from the seeder, and the run ends on main (#0-173)', async () => {
  const { outcome, calls } = await seed({ 'defect-seeder': TRUTH })
  assert.equal(outcome.outcome, 'MEASURED')
  const at = (k) => calls.findIndex((c) => c.key === k)
  assert.ok(at('ops:seed-branch.sh') >= 0 && at('ops:seed-branch.sh') < at('defect-seeder'), 'the branch is made before the seeder runs')
  assert.match(calls[at('ops:seed-branch.sh')].prompt, /seed-branch\.sh 'review\/0684d0a2' 'abc1234'$/)
  assert.match(calls[at('defect-seeder')].prompt, /review\/0684d0a2 is checked out[\s\S]*svc\/src\/main\/java\/A\.java/)
  assert.match(calls[at('defect-seeder')].prompt, /Leave the edit uncommitted\./, 'the seeder commits nothing (#0-172)')
  const review = calls.find((c) => c.key === 'review-performance')
  assert.match(review.prompt, new RegExp(`mergeBase: ${SEEDED.base}`), 'the panel diffs against the seed base, not the old commit')
  assert.ok(at('defect-seeder') < at('ops:seed-check.sh') && at('ops:seed-check.sh') < at('review-performance'),
    'the tree is checked after the seeder, before the panel')
  assert.match(calls[at('ops:seed-check.sh')].prompt, new RegExp(`seed-check\\.sh 'review/0684d0a2' '${SEEDED.base}' '${SEEDED.head}' 'P-10' 'PERF-01' 'performance'$`),
    'the seeder\'s rule and dimension go to seed-check.sh, which holds them to the pattern\'s row (#0-180 r2)')
  assert.ok(at('ops:return-to-main.sh') > at('review-performance') && at('ops:return-to-main.sh') < at('ops:seed-record.sh'),
    'back on main before the row is written')
  assert.equal(calls.at(-1).key, 'ops:seed-record.sh')
  assert.equal(outcome.recorded, true)
  assert.match(outcome.cleanup, /^git branch -D review\/0684d0a2; after the series, copy its rows from \.ai\/runs\/benchmark\/results\.md/)
})

test('seed-bugs: nothing the panel is told names the pattern, the run or that a defect was planted (#0-177)', async () => {
  for (const args of [SEED_ARGS, { pattern: 'P-01', commit: 'abc1234', runId: 'sec-after-p01' }, 'P-12 abc1234 perf-after-p12']) {
    const pattern = typeof args === 'string' ? args.split(' ')[0] : args.pattern
    const runId = typeof args === 'string' ? args.split(' ')[2] : args.runId
    const { calls } = await seed({ 'defect-seeder': (({ prompt }) => ({ ...TRUTH, branch: prompt.match(/review\/[0-9a-f]{8}/)[0] })),
      'ops:seed-branch.sh': ({ prompt }) => ({ ...SEEDED, branch: prompt.match(/review\/[0-9a-f]{8}/)[0] }) }, args)
    const panel = calls.filter((c) => c.key.startsWith('review-'))
    // Each reviewer by name, k8s included (#0-115's k8s.md, review round 1), not only how many.
    assert.deepEqual(panel.map((c) => c.key).sort(),
      ['architecture', 'docs', 'general', 'k8s', 'migration', 'performance', 'security'].map((d) => `review-${d}`), JSON.stringify(args))
    for (const { prompt } of panel) {
      assert.match(prompt, /^Autopilot review\. Branch review\/[0-9a-f]{8}\. mergeBase: /, prompt)
      for (const tell of [/seed/i, /plant/i, /benchmark/i, /pattern/i, /P-\d/, new RegExp(runId)]) assert.doesNotMatch(prompt, tell, `${pattern}: ${prompt}`)
    }
    assert.match(calls.find((c) => c.key === 'ops:seed-branch.sh').prompt, /'review\/[0-9a-f]{8}'/)
  }
})

test('seed-bugs: the branch name is the same on a relaunch and differs between runs (#0-177)', async () => {
  const branchOf = async (args) => (await seed({ 'defect-seeder': TRUTH }, args)).calls.find((c) => c.key === 'ops:seed-branch.sh')
    .prompt.match(/review\/[0-9a-f]{8}/)[0]
  assert.equal(await branchOf(SEED_ARGS), BRANCH, 'FNV-1a of "P-10\\nr1"')
  assert.equal(await branchOf('P-10 abc1234 r1'), BRANCH)
  assert.equal(await branchOf({ ...SEED_ARGS, runId: 'r2' }), 'review/0584cf0f')
  assert.equal(await branchOf({ ...SEED_ARGS, pattern: 'P-11' }), 'review/7442af03')
})

test('seed-bugs: the seeder\'s edit is folded into the change after the check and before the panel (#0-177, #0-172)', async () => {
  const { calls } = await seed({ 'defect-seeder': TRUTH })
  const at = (k) => calls.findIndex((c) => c.key === k)
  assert.ok(at('ops:seed-check.sh') < at('ops:seed-fold.sh') && at('ops:seed-fold.sh') < at('review-general'))
  assert.match(calls[at('ops:seed-fold.sh')].prompt,
    new RegExp(`seed-fold\\.sh 'review/0684d0a2' '${SEEDED.base}' '${SEEDED.head}'$`))
  for (const answer of [null, { ok: false, reason: 'HEAD is not the change\'s commit' }, { ok: true }, { ok: true, head: 'abc' }]) {
    const run = await seed({ 'defect-seeder': TRUTH, 'ops:seed-fold.sh': answer })
    assert.equal(run.outcome.outcome, 'FAILED', JSON.stringify(answer))
    assert.match(run.outcome.reason, /the seeder's edit was not folded/)
    assert.ok(!run.calls.some((c) => c.key.startsWith('review-')), 'no panel on an unfolded branch')
    assert.equal(run.calls.at(-1).key, 'ops:return-to-main.sh')
  }
})

test('seed-bugs: the plant is compiled after the fold and before the panel, and one that does not build ends the run (#0-181)', async () => {
  const { outcome, calls } = await seed({ 'defect-seeder': TRUTH })
  assert.equal(outcome.outcome, 'MEASURED')
  assert.equal(outcome.compiled, true)
  assert.ok(!('notCompiled' in outcome))
  const at = (k) => calls.findIndex((c) => c.key === k)
  assert.ok(at('ops:seed-fold.sh') < at('ops:seed-compile.sh'), 'the folded commit is the one compiled')
  for (const dim of ['general', 'architecture', 'security', 'performance', 'migration', 'docs', 'k8s']) {
    assert.ok(at('ops:seed-compile.sh') < at(`review-${dim}`), `compiled before ${dim} reviews`)
  }
  // The change's head (without the defect) and the folded head: seed-compile.sh reads the edit as their diff.
  assert.match(calls[at('ops:seed-compile.sh')].prompt,
    new RegExp(`seed-compile\\.sh 'review/0684d0a2' '${SEEDED.head}' '${FOLDED.head}'$`))
  for (const answer of [null, { ok: false, reason: 'the plant does not compile (log x): [ERROR] A.java:[40,9] cannot find symbol' },
    { ok: false, reason: 'the build environment failed (log x): Cannot access central in offline mode' },
    { ok: true }, { ok: 'true', compiled: true }, { ok: true, compiled: 'true' }, { error: 'timed out', exitCode: 124 }]) {
    const run = await seed({ 'defect-seeder': TRUTH, 'ops:seed-compile.sh': answer })
    assert.equal(run.outcome.outcome, 'FAILED', JSON.stringify(answer))
    assert.match(run.outcome.reason, /^the plant does not build: /)
    if (answer?.reason) assert.ok(run.outcome.reason.includes(answer.reason), 'the script\'s reason is kept')
    if (answer?.error) assert.match(run.outcome.reason, /timed out/)
    assert.ok(!run.calls.some((c) => c.key.startsWith('review-')), 'no panel on a plant that does not build')
    assert.ok(!run.calls.some((c) => c.key === 'ops:seed-record.sh'), 'no row')
    assert.equal(run.outcome.cleanup, `git branch -D ${BRANCH}`)
    assert.equal(run.calls.at(-1).key, 'ops:return-to-main.sh')
  }
  // Nothing to compile (a POM in the edit, no Java): the panel runs.
  const skipped = await seed({ 'defect-seeder': TRUTH,
    'ops:seed-compile.sh': { ok: true, compiled: false, modules: '', reason: 'the edit changes a POM: not compiled' } })
  assert.equal(skipped.outcome.outcome, 'MEASURED')
  assert.ok(skipped.calls.some((c) => c.key === 'review-general'))
  // ... and the outcome says it was measured uncompiled, with why (FAC-A03, review round 1), a clean run's too.
  assert.equal(skipped.outcome.compiled, false)
  assert.equal(skipped.outcome.notCompiled, 'the edit changes a POM: not compiled')
  const cleanSkipped = await cleanSeed({ 'ops:seed-compile.sh': { ok: true, compiled: false, modules: '', reason: 'no Java file in the edit: nothing to compile' } })
  assert.equal(cleanSkipped.outcome.kind, 'clean')
  assert.equal(cleanSkipped.outcome.compiled, false)
  assert.match(cleanSkipped.outcome.notCompiled, /no Java file/)
})

test('seed-bugs: seed-record.sh accepts exactly the panel\'s dimensions (#0-177, review round 1)', () => {
  // Two lists, one in each language: a dimension added to PANEL alone would have every row naming it refused. And the
  // same dimensions as the audit's ALL and the rule files of the autopilot's RULE_FILE_OF, factory.md aside (#0-115's
  // k8s.md, review round 1): a new dimension added to one of the four would drift unseen in the others.
  const panel = SEED.match(/^const PANEL = \[([^\]]*)\]/m)[1].match(/'([a-z][a-z0-9]*)'/g).map((d) => d.slice(1, -1))
  const record = readFileSync(join(dirname(FILE), '../../scripts/factory/seed-record.sh'), 'utf8')
  const dims = record.match(/^DIMENSIONS=" ([a-z0-9 ]+) "$/m)[1].split(' ')
  assert.deepEqual([...dims].sort(), [...panel].sort())
  const audit = readFileSync(join(dirname(FILE), 'audit.js'), 'utf8')
  const all = audit.match(/^const ALL = \[([^\]]*)\]/m)[1].match(/'([a-z][a-z0-9]*)'/g).map((d) => d.slice(1, -1))
  assert.deepEqual([...all].sort(), [...panel].sort())
  const ruleFiles = SRC.match(/^const RULE_FILE_OF = \{([^}]*)\}/m)[1].match(/: '([a-z][a-z0-9]*)'/g).map((d) => d.slice(3, -1))
  assert.deepEqual([...new Set(ruleFiles)].filter((f) => f !== 'factory').sort(), [...panel].sort())
})

test('seed-bugs: the branch the workflow names is one the scripts accept (#0-177, review round 2)', async () => {
  // The format lives twice, seedBranchOf in the workflow and SEED_BRANCH_RE in _common.sh: a drift refuses every run.
  const common = readFileSync(join(dirname(FILE), '../../scripts/factory/_common.sh'), 'utf8')
  const accepted = new RegExp(common.match(/^SEED_BRANCH_RE='([^']+)'$/m)[1])
  for (const args of [SEED_ARGS, { pattern: 'P-01', commit: 'abc1234', runId: 'sec-after-p01' }, { pattern: 'P-18', commit: 'abc1234', runId: 'x' }]) {
    const { calls } = await seed({ 'defect-seeder': TRUTH }, args)
    const branch = calls.find((c) => c.key === 'ops:seed-branch.sh').prompt.match(/seed-branch\.sh '([^']+)'/)[1]
    assert.match(branch, accepted, JSON.stringify(args))
  }
  assert.doesNotMatch('seed/P-10-r1', accepted)
})

test('seed-bugs: the panel runs only on a tree seed-check.sh confirmed (#0-173, review round 1)', async () => {
  for (const answer of [null, { ok: false, reason: `the tree is on main, not on ${BRANCH}` },
    { ok: true, files: ['svc/src/main/java/Other.java'] }, { ok: true }, { ...CHECKED, files: [] }, { ...CHECKED, ok: 'true' }]) {
    const { outcome, calls } = await seed({ 'defect-seeder': TRUTH, 'ops:seed-check.sh': answer })
    assert.equal(outcome.outcome, 'FAILED', JSON.stringify(answer))
    assert.match(outcome.reason, /the seed branch is not as the seeder says/)
    assert.ok(!calls.some((c) => c.key.startsWith('review-')), 'no panel on an unconfirmed tree')
    assert.equal(calls.at(-1).key, 'ops:return-to-main.sh')
  }
})

test('seed-bugs: a run that cannot get back to main says where it left the tree (#0-173, review round 1)', async () => {
  const stuck = { onMain: false, branch: BRANCH, reason: 'working tree not clean: left as it is for the owner' }
  const measured = await seed({ 'defect-seeder': TRUTH, 'ops:return-to-main.sh': stuck })
  assert.equal(measured.outcome.outcome, 'MEASURED')
  assert.equal(measured.outcome.recorded, false)
  assert.equal(measured.outcome.leftOn, BRANCH)
  assert.match(measured.outcome.returnToMain, /not clean/)
  assert.ok(!measured.calls.some((c) => c.key === 'ops:seed-record.sh'), 'no row written off main')
  assert.match(measured.outcome.cleanup, /git branch -D review\/0684d0a2 once the tree is back on main/, 'names the branch (#0-176, review round 2)')
  const failed = await seed({ 'defect-seeder': { blocked: true, reason: 'x' }, 'ops:return-to-main.sh': stuck })
  assert.equal(failed.outcome.outcome, 'FAILED')
  assert.equal(failed.outcome.leftOn, BRANCH)
  const silent = await seed({ 'defect-seeder': TRUTH, 'ops:return-to-main.sh': null })
  assert.equal(silent.outcome.recorded, false, 'no answer is not "on main"')
  const ok = await seed({ 'defect-seeder': { blocked: true, reason: 'x' } })
  assert.ok(!('leftOn' in ok.outcome), 'nothing to say when it is back on main')
})

test('seed-bugs: a failed run that made the branch says how to delete it (#0-173, review round 2)', async () => {
  for (const answers of [{ 'defect-seeder': { blocked: true, reason: 'x' } }, { 'defect-seeder': { skipped: true, reason: 'y' } },
    { 'defect-seeder': TRUTH, 'ops:seed-check.sh': { ok: false, reason: 'z' } }, { 'ops:seed-branch.sh': { ...SEEDED, base: 'abc' } },
    { 'defect-seeder': TRUTH, 'ops:seed-fold.sh': { ok: false, reason: 'w' } },
    { 'defect-seeder': TRUTH, 'ops:seed-compile.sh': { ok: false, reason: 'v' } }]) {
    const { outcome } = await seed(answers)
    assert.equal(outcome.cleanup, `git branch -D ${BRANCH}`, JSON.stringify(answers))
  }
  for (const answer of [null, { ok: false, reason: 'the working tree is not clean' }]) {
    const { outcome } = await seed({ 'ops:seed-branch.sh': answer })
    assert.ok(!('cleanup' in outcome), 'no branch, nothing to delete')
  }
  const named = await seed({ 'ops:seed-branch.sh': { ...SEEDED, branch: `${BRANCH} x; rm` } })
  assert.equal(named.outcome.cleanup, `git branch -D ${BRANCH}`, 'the name the run asked for, never the answer\'s')
})

test('seed-bugs: no seed branch, no seeder; every outcome ends on main', async () => {
  for (const answer of [null, { ok: false, reason: 'the working tree is not clean' }, { ok: true, branch: 'review/x' },
    { ...SEEDED, branch: 'review/0584cf0f' }, { ...SEEDED, base: 'abc' }, { ...SEEDED, head: undefined }, { ...SEEDED, files: [] }]) {
    const { outcome, calls } = await seed({ 'ops:seed-branch.sh': answer })
    assert.equal(outcome.outcome, 'FAILED', JSON.stringify(answer))
    assert.ok(!calls.some((c) => c.key === 'defect-seeder'))
    assert.equal(calls.at(-1).key, 'ops:return-to-main.sh')
  }
  const notClean = await seed({ 'ops:seed-branch.sh': { ok: false, reason: 'the working tree is not clean' } })
  assert.match(notClean.outcome.reason, /no seed branch: the working tree is not clean/)
  for (const answer of [{ blocked: true, reason: 'x' }, { skipped: true, reason: 'y' }, { skipped: true }, { ...TRUTH, line: undefined }]) {
    const { calls } = await seed({ 'defect-seeder': answer })
    assert.equal(calls.at(-1).key, 'ops:return-to-main.sh', JSON.stringify(answer))
  }
})

test('seed-bugs: `/seed-bugs P-10 <sha> <run id>` passes one string, read as the three args (#0-174)', async () => {
  const fromObject = await seed({ 'defect-seeder': TRUTH })
  for (const words of ['P-10 abc1234 r1', '  P-10\tabc1234   r1\n']) {
    const { outcome, calls } = await seed({ 'defect-seeder': TRUTH }, words)
    assert.deepEqual(outcome, fromObject.outcome, JSON.stringify(words))
    assert.deepEqual(calls.map((c) => c.prompt), fromObject.calls.map((c) => c.prompt), JSON.stringify(words))
  }
  for (const args of ['P-10 abc1234', 'P-10 abc1234 r1 extra', '', 'P-10 abc1234 r1;rm', "P-10 abc1234 'r1'", undefined, null,
    {}, { pattern: 'P-10', commit: 'abc1234' }, { ...SEED_ARGS, runId: 'r 1' }]) {
    const { outcome, calls } = await seed({}, args)
    assert.equal(outcome.outcome, 'NOT_STARTED', String(JSON.stringify(args)))
    assert.match(outcome.reason, /pattern, commit, runId/)
    assert.equal(calls.length, 0, `nothing runs on ${JSON.stringify(args)}`)
  }
})

// The runtime validates an agent's answer against its `schema` (the fake agent does not): this checks the schemas
// themselves, with the subset of JSON Schema they use, against what the scripts print and what the agent answered.
// A keyword or type outside that subset throws, anywhere in the schema (review round 2 of #0-174): ignored, a later
// `required` or `enum` would pass here unchecked.
const KNOWN_KEYWORDS = new Set(['type', 'items', 'properties', 'additionalProperties', 'required', 'enum'])
const TYPE_OK = { object: (v) => v !== null && typeof v === 'object' && !Array.isArray(v), array: Array.isArray,
  string: (v) => typeof v === 'string', boolean: (v) => typeof v === 'boolean', number: (v) => typeof v === 'number' }
function knownSchema(schema) {
  const unknown = Object.keys(schema).filter((k) => !KNOWN_KEYWORDS.has(k))
  if (unknown.length) throw new Error(`conforms() does not know ${unknown.join(', ')}: extend it`)
  const types = Array.isArray(schema.type) ? schema.type : [schema.type]
  if (!types.length || !types.every((t) => t === 'null' || Object.hasOwn(TYPE_OK, t))) {
    throw new Error(`conforms() does not know the type ${JSON.stringify(schema.type)}: extend it`)
  }
  if (schema.items) knownSchema(schema.items)
  Object.values(schema.properties ?? {}).forEach(knownSchema)
}
function conforms(value, schema) {
  knownSchema(schema)
  const types = Array.isArray(schema.type) ? schema.type : [schema.type]
  if (value === null) return types.includes('null')
  const type = types.find((t) => t !== 'null' && TYPE_OK[t](value))
  if (!type) return false
  if (schema.enum && !schema.enum.includes(value)) return false
  if (type === 'array') return value.every((v) => conforms(v, schema.items))
  if (type !== 'object') return true
  if (!(schema.required ?? []).every((k) => Object.hasOwn(value, k))) return false
  return Object.entries(value).every(([k, v]) => k in (schema.properties ?? {}) ? conforms(v, schema.properties[k])
    : schema.additionalProperties !== false)
}

test('conforms() refuses a schema keyword or type it does not check (#0-174, review round 2; #0-176)', () => {
  for (const schema of [{ type: 'object', minProperties: 1 }, { type: 'string', pattern: 'a' }, { type: ['string', 'integer'] },
    { type: 'integer' }, { type: [] }, { type: 'object', properties: { files: { type: 'array', items: { type: 'string', pattern: 'x' } } } }]) {
    assert.throws(() => conforms({}, schema), /conforms\(\) does not know/, JSON.stringify(schema))
  }
})

test('seed-bugs: each factory script\'s answer is typed, so the agent cannot hand back strings (#0-174)', async () => {
  const { calls } = await seed({ 'defect-seeder': TRUTH })
  const schemaOf = (key) => calls.find((c) => c.key === key).schema
  const printed = {
    'ops:seed-branch.sh': [SEEDED, { ok: false, reason: 'the working tree is not clean' }],
    'ops:seed-check.sh': [CHECKED, { ok: false, reason: 'the tree is on main' }],
    'ops:seed-fold.sh': [FOLDED, { ok: false, reason: 'HEAD is not the change\'s commit' }],
    'ops:seed-compile.sh': [COMPILED, { ok: true, compiled: false, modules: '', reason: 'no Java file in the edit: nothing to compile' },
      { ok: false, reason: 'the plant does not compile (log x): [ERROR] A.java:[40,9] cannot find symbol' }],
    'ops:seed-record.sh': [RECORDED, { appended: false, reason: 'the run id r1 is in .ai/runs/benchmark/results.md already' }],
    'ops:return-to-main.sh': [{ onMain: true }, { onMain: true, left: BRANCH },
      { onMain: false, branch: BRANCH, reason: 'working tree not clean: left as it is for the owner' }],
  }
  for (const [key, answers] of Object.entries(printed)) {
    for (const answer of [...answers, { error: 'jq: command not found', exitCode: 127 }]) {
      assert.ok(conforms(answer, schemaOf(key)), `${key} accepts ${JSON.stringify(answer)}`)
    }
  }
  // What factory-ops answered in the run of 2026-10-25 (P-10 on 76379e806fb4, run perf-after-p10).
  const answered = {
    'ops:seed-branch.sh': [{ ...SEEDED, ok: 'true' }, { ...SEEDED, files: JSON.stringify(SEEDED.files) }],
    'ops:seed-check.sh': [{ ...CHECKED, ok: 'true' }, { ...CHECKED, files: JSON.stringify(CHECKED.files) },
      // the answer of a seed-check.sh before #0-172, which named the seeder's commit: the field is gone
      { ...CHECKED, commit: 'd'.repeat(40) }],
    'ops:return-to-main.sh': [{ parameter: '{"onMain": true, "left": "seed/P-10-r1"}' }, { onMain: 'true' }],
    // The same kind of answer for the scripts #0-177 added.
    'ops:seed-fold.sh': [{ ...FOLDED, ok: 'true' }],
    // #0-181's compile step, the same way.
    'ops:seed-compile.sh': [{ ...COMPILED, ok: 'true' }, { ...COMPILED, compiled: 'true' }, { ...COMPILED, log: 'x' }],
    'ops:seed-record.sh': [{ ...RECORDED, appended: 'true' }, { parameter: JSON.stringify(RECORDED) }],
  }
  for (const [key, answers] of Object.entries(answered)) {
    for (const answer of answers) assert.ok(!conforms(answer, schemaOf(key)), `${key} refuses ${JSON.stringify(answer)}`)
  }
})

test('conforms() checks required keys, enums and a type that allows null (#0-176)', () => {
  const schema = { type: 'object', required: ['v'], properties: { v: { type: 'string', enum: ['A', 'B'] }, n: { type: ['number', 'null'] } } }
  assert.ok(conforms({ v: 'A', n: null }, schema))
  assert.ok(conforms({ v: 'B', n: 3 }, schema))
  for (const value of [{}, { v: 'C' }, { v: 'A', n: '3' }, { v: null }, null]) assert.ok(!conforms(value, schema), JSON.stringify(value))
})

// A verdict as a reviewer writes it (review-procedure): blocking findings with an id, non-blocking ones often without.
const REAL_VERDICT = { dimension: 'performance', round: 1, verdict: 'CHANGES_REQUESTED',
  blocking: [{ id: 'perf-3c1e', ruleId: 'PERF-30', file: TRUTH.file, line: 330, issue: 'findAll() loads every row', impact: 'memory' }],
  nonBlocking: [{ ruleId: null, file: TRUTH.file, line: 12, issue: 'a nit' }, { ruleId: 'DOC-20', file: null, line: null, issue: 'x' }],
  resolved: [], upheldDisputes: [], outOfScope: [], ruleGap: [], unverified: ['a claim'] }

test('seed-bugs: the panel\'s verdicts are typed, so a reviewer cannot hand back strings (#0-176)', async () => {
  const { calls } = await seed({ 'defect-seeder': TRUTH })
  const schema = calls.find((c) => c.key === 'review-performance').schema
  // Every dimension of PANEL, k8s included (#0-115's k8s.md, review round 2), not a list of its own.
  const panel = SEED.match(/^const PANEL = \[([^\]]*)\]/m)[1].match(/'([a-z][a-z0-9]*)'/g).map((d) => d.slice(1, -1))
  assert.ok(panel.includes('k8s'))
  for (const dim of panel) {
    assert.deepEqual(calls.find((c) => c.key === `review-${dim}`).schema, schema, `review-${dim} gets the same schema`)
  }
  assert.ok(conforms(REAL_VERDICT, schema))
  assert.ok(conforms(approve('migration', { round: 1, outOfScope: [], ruleGap: [] }), schema))
  // What the panel answered in the run of 2026-10-25 (P-12 on 47b95294, run perf-after-p12): every value a string.
  const stringly = Object.fromEntries(Object.entries(REAL_VERDICT).map(([k, v]) => [k, typeof v === 'string' ? v : JSON.stringify(v)]))
  assert.ok(!conforms(stringly, schema))
  for (const bad of [{ ...REAL_VERDICT, verdict: 'LGTM' }, { ...REAL_VERDICT, blocking: [{ id: 'x', line: '330', issue: 'y' }] },
    { ...REAL_VERDICT, nonBlocking: undefined }]) assert.ok(!conforms(JSON.parse(JSON.stringify(bad)), schema), JSON.stringify(bad).slice(0, 80))
})

test('seed-bugs: a verdict that is not one counts as no answer, and the run still records (#0-176)', async () => {
  const stringly = { ...REAL_VERDICT, blocking: JSON.stringify(REAL_VERDICT.blocking), nonBlocking: '[]' }
  const { outcome, calls } = await seed({ 'defect-seeder': TRUTH, 'review-performance': stringly,
    'review-security': { ...REAL_VERDICT, dimension: 'security', blocking: [{ issue: 'no tenant predicate', file: TRUTH.file, line: 41 }] } })
  assert.equal(outcome.outcome, 'MEASURED')
  assert.deepEqual(outcome.noAnswer, ['performance'])
  assert.deepEqual(outcome.caughtBy, ['security'])
  assert.equal(outcome.caughtByExpected, false)
  assert.ok(calls.some((c) => c.key === 'ops:seed-record.sh'), 'the row is written')
  assert.match(calls.find((c) => c.key === 'ops:seed-record.sh').prompt, /seed-record\.sh 'r1' 'P-10' 'PERF-01' 'performance' 'no' 'no' 'security' 'performance'$/)
})

test('seed-bugs: an error after the branch exists ends the run on main and names the branch (#0-176)', async () => {
  const boom = () => { throw new Error('boom') }
  for (const answers of [{ 'defect-seeder': boom }, { 'defect-seeder': TRUTH, 'ops:seed-check.sh': boom },
    { 'defect-seeder': TRUTH, 'ops:seed-fold.sh': boom }, { 'defect-seeder': TRUTH, 'ops:seed-compile.sh': boom }]) {
    const { outcome, calls } = await seed(answers)
    assert.equal(outcome.outcome, 'FAILED', Object.keys(answers).join())
    assert.match(outcome.reason, /the run stopped on an error: boom/)
    assert.equal(outcome.cleanup, `git branch -D ${BRANCH}`)
    assert.equal(calls.at(-1).key, 'ops:return-to-main.sh')
  }
})

test('seed-bugs: a measure whose row cannot be written is kept, not failed (#0-176, review round 1)', async () => {
  const { outcome } = await seed({ 'defect-seeder': TRUTH, 'ops:seed-record.sh': () => { throw new Error('boom') } })
  assert.equal(outcome.outcome, 'MEASURED')
  assert.equal(outcome.recorded, false)
  assert.match(outcome.reason, /the row was not written: boom/)
  assert.deepEqual([outcome.pattern, outcome.expected, outcome.caughtByExpected], ['P-10', 'performance', false])
  assert.match(outcome.cleanup, /git branch -D review\/0684d0a2; record the row by hand in \.ai\/runs\/benchmark\/results\.md/)
  // Only `appended: true` is recorded (#0-171's "Also", #0-177): a refusal, an untyped answer or none is not.
  for (const answer of [{ appended: false, reason: 'the run id r1 is in .ai/runs/benchmark/results.md already' }, { appended: 'true' }, {}, null]) {
    const r = await seed({ 'defect-seeder': TRUTH, 'ops:seed-record.sh': answer })
    assert.equal(r.outcome.outcome, 'MEASURED', JSON.stringify(answer))
    assert.equal(r.outcome.recorded, false, JSON.stringify(answer))
  }
  const refused = await seed({ 'defect-seeder': TRUTH, 'ops:seed-record.sh': { appended: false, reason: 'the run id r1 is in x already' } })
  assert.match(refused.outcome.reason, /the row was not written: the run id r1 is in x already/)
})

test('seed-bugs: return-to-main.sh failing, even after another error, still ends with an outcome (#0-176, review round 1)', async () => {
  const boom = () => { throw new Error('boom') }
  for (const answers of [{ 'defect-seeder': { blocked: true, reason: 'x' } }, { 'defect-seeder': boom }, { 'defect-seeder': TRUTH }]) {
    const { outcome } = await seed({ ...answers, 'ops:return-to-main.sh': () => { throw new Error('no answer') } })
    assert.equal(outcome.leftOn, 'unknown', Object.keys(answers).join())
    assert.match(outcome.returnToMain, /return-to-main\.sh did not answer: no answer/)
  }
})

test('seed-bugs: its verdict schema types what backlog-autopilot.js\'s does, but for the noted relaxations (#0-176, review round 1)', async () => {
  const { VERDICT } = await helpers()
  const { calls } = await seed({ 'defect-seeder': TRUTH })
  const ours = calls.find((c) => c.key === 'review-performance').schema
  const typesOf = (t) => new Set(Array.isArray(t) ? t : [t])
  // seed-bugs.js does not read upheldDisputes; a measure keeps a finding with no id, impact or isRegression, and a
  // null ruleId or file (FINDING's comment): those are its relaxations, nothing else may differ.
  const NOT_READ = new Set(['upheldDisputes']), FINDING_NOT_READ = new Set(['isRegression'])
  for (const [key, theirs] of Object.entries(VERDICT.properties)) {
    if (NOT_READ.has(key)) continue
    assert.ok(ours.properties[key], `seed-bugs.js types ${key}`)
    if (key !== 'blocking' && key !== 'nonBlocking') assert.deepEqual(ours.properties[key], theirs, key)
  }
  const finding = ours.properties.blocking.items
  for (const [key, theirs] of Object.entries(VERDICT.properties.blocking.items.properties)) {
    if (FINDING_NOT_READ.has(key)) continue
    assert.ok(finding.properties[key], `seed-bugs.js's FINDING types ${key}`)
    for (const t of typesOf(theirs.type)) assert.ok(typesOf(finding.properties[key].type).has(t), `${key} still allows ${t}`)
  }
  // And the other way (review round 2 of #0-176): a key seed-bugs.js types that the autopilot's schema lacks is a drift
  // too, unless named here.
  const OURS_ONLY = new Set([]), FINDING_OURS_ONLY = new Set([])
  for (const key of Object.keys(ours.properties)) {
    assert.ok(key in VERDICT.properties || OURS_ONLY.has(key), `seed-bugs.js types ${key}, which backlog-autopilot.js's VERDICT does not`)
  }
  for (const key of Object.keys(finding.properties)) {
    assert.ok(key in VERDICT.properties.blocking.items.properties || FINDING_OURS_ONLY.has(key),
      `seed-bugs.js's FINDING types ${key}, which backlog-autopilot.js's does not`)
  }
  assert.deepEqual(finding.required, ['issue'])
  assert.deepEqual(ours.properties.nonBlocking.items, finding, 'non-blocking findings are typed like blocking ones')
})

// ---------------------------------------------------------------- backlog-autopilot.js: the factory scripts' answers

// Every ops('<script>', <argv>, <schema>, …) call of backlog-autopilot.js, read from its text: the schema argument
// (the third, split at the call's own commas, not those inside brackets, strings or templates).
function opsSchemaArgs(src) {
  const found = []
  const re = /(?<![\w.])ops\(/g
  for (let m; (m = re.exec(src));) {
    if (/function\s+$/.test(src.slice(Math.max(0, m.index - 12), m.index))) continue      // the definition
    if (/^\s*(\/\/|\/\*|\*)/.test(src.slice(src.lastIndexOf('\n', m.index) + 1, m.index))) continue   // a comment's words
    const parts = []; let depth = 0, quote = null, cur = ''
    for (let i = m.index + 4; i < src.length; i++) {
      const c = src[i]
      if (quote) { cur += c; if (c === '\\') { cur += src[++i]; continue } if (c === quote) quote = null; continue }
      if (c === "'" || c === '"' || c === '`') { quote = c; cur += c; continue }
      if ('([{'.includes(c)) depth++
      if (')]}'.includes(c)) { if (depth === 0) { parts.push(cur.trim()); break } depth-- }
      if (c === ',' && depth === 0) { parts.push(cur.trim()); cur = ''; continue }
      cur += c
    }
    found.push({ at: src.slice(0, m.index).split('\n').length, script: parts[0], schema: parts[2] })
  }
  return found
}

// The schemas of the helpers' scope, by name.
async function schemasNamed(names) {
  return evaluate(`${strip(SRC.slice(0, RUN_AT))}\nreturn { ${[...new Set(names)].join(', ')} }`,
    { args: {}, agent: fakeAgent({}).agent, logs: [] })
}

test('backlog-autopilot: no factory script\'s answer goes untyped (#0-175)', async () => {
  // The scan sees every factory script only if every one goes through ops(): factory-ops is called in one place
  // (review round 1: a direct as('factory-ops', …) would pass the scan unseen).
  assert.equal(SRC.match(/\bas\(\s*['"`]factory-ops['"`]/g)?.length, 1, "as('factory-ops', …) is called only inside ops()")
  const sites = opsSchemaArgs(SRC)
  assert.ok(sites.length >= 19, `the scan found ${sites.length} ops() calls: it no longer reads the script`)
  for (const s of sites) assert.match(s.schema ?? '', /^[A-Z_]+$/, `line ${s.at} (${s.script}): the schema is a named constant`)
  const schemas = await schemasNamed(sites.map((s) => s.schema))
  for (const s of sites) {
    const schema = schemas[s.schema]
    assert.notEqual(s.schema, 'ANY_OBJECT', `line ${s.at} (${s.script}): ANY_OBJECT lets the agent wrap or stringify the answer`)
    assert.equal(schema?.type, 'object', `line ${s.at} (${s.script}): ${s.schema} is an object schema`)
    assert.ok(Object.keys(schema.properties ?? {}).length > 0, `line ${s.at} (${s.script}): ${s.schema} names its fields`)
    assert.ok((schema.required ?? []).length > 0 || schema.additionalProperties === false,
      `line ${s.at} (${s.script}): ${s.schema} refuses a key of the agent's own (required fields, or no others)`)
  }
})

test('the scan of ops() calls finds an untyped one, and an argument with commas inside', () => {
  const sites = opsSchemaArgs("const r = await ops('a.sh', x ? [b, c] : [d], ANY_OBJECT, 'l')\n" +
    "function ops(script, argv, schema) {}\nops('b.sh', [`${e}, f`, g('h', i)], TYPED)\nnotops('c.sh', [], X)\n" +
    "// every ops() call is typed\nx.ops('d.sh', [], Y)\n  /* ops('e.sh', [], Z) */\n * ops('f.sh', [], W)\n" +
    "const u = 'https://x//y'; ops('g.sh', [], URL_TYPED)")
  assert.deepEqual(sites.map((s) => [s.script, s.schema]),
    [["'a.sh'", 'ANY_OBJECT'], ["'b.sh'", 'TYPED'], ["'g.sh'", 'URL_TYPED']])
})

test('backlog-autopilot: each factory script\'s answer accepts what it prints and refuses what the agent made of it (#0-175)', async () => {
  const S = await schemasNamed(['STATE_BRANCH', 'STATE_UNLOCKED', 'STATE_RECORDED', 'BACK_TO_MAIN', 'NOTIFIED', 'LOCAL_REVIEW', 'STARTED', 'RESUMED'])
  // What every script can also print: factory-ops' own error answer, and _common.sh's failure.
  const failures = [{ error: 'jq: command not found', exitCode: 127 }, { ok: false, reasons: ['jq is not installed'] }]
  const printed = {
    STATE_BRANCH: [{ branch: 'fix/0-191-deny-by-default-tests' }, { error: 'no run holds the lock' }],
    STATE_UNLOCKED: [{ unlocked: true }],
    STATE_RECORDED: [{ consecutiveBlocked: 0, shippedSinceAudit: 3, lastAudit: null,
      history: [{ t: '2026-10-10T09:36:08Z', item: '0-124', outcome: 'shipped', pr: 'https://github.com/o/r/pull/482' },
        { t: '2026-10-11T09:00:00Z', item: '0-8', outcome: 'blocked', pr: '', stage: 'review' }] },
    { consecutiveBlocked: 99, shippedSinceAudit: 0, lastAudit: null, history: [], note: 'state file was unreadable' },
    { consecutiveBlocked: 0, shippedSinceAudit: 0, lastAudit: '2026-10-20T10:00:00Z', history: [] },
    { error: 'state update failed; state file left unchanged' }],
    BACK_TO_MAIN: [{ onMain: true }, { onMain: true, left: 'fix/0-1-x' },
      { onMain: false, branch: 'fix/0-1-x', reason: 'working tree not clean: left as it is for the owner' }],
    NOTIFIED: [{ sent: true }, { sent: false, reason: 'FACTORY_NTFY_TOPIC not set' }, { sent: false, reason: 'curl failed' }],
    LOCAL_REVIEW: [{ ran: false, reason: 'Ollama not reachable' }, { ran: true, model: 'gemma3:27b', result: '{"verdict":"APPROVE"}' },
      { ran: true, model: 'gemma3:27b', result: { type: 'result' } },
      { ran: true, error: 'the working tree changed during the local review: discard the result' },
      { ran: false, reason: 'no parseable output' }],
    STARTED: [{ ok: true, branch: 'fix/0-25-queue-version', workDir: '.ai/work/0-25', head: 'd'.repeat(40) },
      { ok: false, reasons: ['the branch fix/0-25-queue-version exists already'] }],
    RESUMED: [{ ok: true, branch: 'fix/0-25-queue-version', item: '0-25', head: 'd'.repeat(40) },
      { ok: false, reasons: ['no local branch fix/0-25-queue-version to resume'] }],
  }
  for (const [name, answers] of Object.entries(printed)) {
    for (const answer of [...answers, ...failures]) assert.ok(conforms(answer, S[name]), `${name} accepts ${JSON.stringify(answer)}`)
  }
  // What factory-ops answered in run wf_8c632098-97c (2026-11-01, #0-191): the script's JSON as a string under a key of
  // its own; and the other way #0-174 saw, every value a string.
  const answered = {
    STATE_BRANCH: [{ output: '{"branch": "feat/0-191-deny-by-default-tests"}' }, { branch: 'fix/0-1-x', recorded: true }],
    STATE_UNLOCKED: [{ output: '{"unlocked":true}' }, { unlocked: 'true' }],
    STATE_RECORDED: [{ output: '{"consecutiveBlocked":0}' }, { consecutiveBlocked: '0' }, { history: '[]' }],
    BACK_TO_MAIN: [{ parameter: '{"onMain": true}' }, { onMain: 'true' }],
    NOTIFIED: [{ output: '{"sent":true}' }, { sent: 'true' }],
    LOCAL_REVIEW: [{ output: '{"ran":false}' }, { ran: 'false' }],
    STARTED: [{ output: '{"ok":true}' }, { ok: 'true', branch: 'fix/0-1-x' }],
    RESUMED: [{ output: '{"ok":true}' }, { ok: 'true', branch: 'fix/0-1-x' }, { ok: true, item: 25 }],
  }
  for (const [name, answers] of Object.entries(answered)) {
    for (const answer of answers) assert.ok(!conforms(answer, S[name]), `${name} refuses ${JSON.stringify(answer)}`)
  }
})

// ---- backlog #0-175, PR 2: every workflow's factory-script answers typed and closed, and kept equal to the scripts.
const AUDIT = readFileSync(join(dirname(FILE), 'audit.js'), 'utf8')
async function auditSchemas(names) {
  const at = AUDIT.indexOf('\nconst DATE = ')
  if (at < 0 || AUDIT.indexOf('\nconst DATE = ', at + 1) >= 0) throw new Error('audit.js: the marker "const DATE = " must appear once')
  return evaluate(`${strip(AUDIT.slice(0, at))}\nreturn { ${names.join(', ')} }`, { args: {}, agent: fakeAgent({}).agent, logs: [] })
}
const FAILURES = [{ error: 'jq: command not found', exitCode: 127 }, { ok: false, reasons: ['jq is not installed'] }]

test('the three workflows type a factory script\'s failure the same way (#0-175, PR 2)', () => {
  // A workflow cannot import, so each holds ERROR_FIELDS and answerOf (and failureOf, where it reads a failure); they
  // drifted once: seed-bugs.js's had no `ok` and `reasons`, so _common.sh's failure failed its schemas without a reason.
  const text = (src, name) => {
    const m = new RegExp(`^const ${name} = [\\s\\S]*?(?=\\n(?:const |\\/\\/|$))`, 'm').exec(src)
    assert.ok(m, `${name} is defined`)
    return m[0].replace(/\s+/g, ' ')
  }
  for (const name of ['ERROR_FIELDS', 'answerOf']) {
    assert.equal(text(AUDIT, name), text(SRC, name), `audit.js's ${name} is backlog-autopilot.js's`)
    assert.equal(text(SEED, name), text(SRC, name), `seed-bugs.js's ${name} is backlog-autopilot.js's`)
  }
  assert.equal(text(AUDIT, 'failureOf'), text(SRC, 'failureOf'), "audit.js's failureOf is backlog-autopilot.js's")
})

test('audit: no factory script\'s answer goes untyped (#0-175, PR 2)', async () => {
  assert.equal(AUDIT.match(/\bas\(\s*['"`]factory-ops['"`]/g)?.length, 1, "as('factory-ops', …) is called only inside ops()")
  const sites = opsSchemaArgs(AUDIT)
  assert.deepEqual(sites.map((s) => s.script).sort(), ["'audit-data.sh'", "'notify.sh'"], 'the scan found every ops() call')
  const schemas = await auditSchemas(sites.map((s) => s.schema))
  for (const s of sites) {
    assert.match(s.schema ?? '', /^[A-Z_]+$/, `${s.script}: the schema is a named constant`)
    assert.equal(schemas[s.schema].additionalProperties, false, `${s.script}: ${s.schema} refuses a key of the agent's own`)
  }
  const { AUDIT_DATA, NOTIFIED } = schemas
  const data = { file: '.ai/runs/audit-data.json', prs: 3, prsWithHumanLabels: 1, unverifiedHumanLabels: 0, owner: 'o',
    ownerIsAutopilot: false, unverifiedEscapes: 0, readyPrs: 2, cases: 1, transcriptsDir: '/home/dev/.claude/projects/x' }
  for (const answer of [data, { ...data, owner: null }, ...FAILURES]) assert.ok(conforms(answer, AUDIT_DATA), JSON.stringify(answer))
  for (const answer of [{ output: JSON.stringify(data) }, { ...data, prs: '3' }]) assert.ok(!conforms(answer, AUDIT_DATA), JSON.stringify(answer))
  for (const answer of [{ sent: true }, { sent: false, reason: 'curl failed' }, ...FAILURES]) assert.ok(conforms(answer, NOTIFIED), JSON.stringify(answer))
  assert.ok(!conforms({ output: '{"sent":true}' }, NOTIFIED))
})

test("audit: a failure of audit-data.sh stops with its reason, not as an audit of nothing (#0-175, PR 2)", async () => {
  for (const answer of FAILURES) {
    const fake = fakeAgent({ 'ops:audit-data.sh': answer })
    const outcome = await evaluate(strip(AUDIT), { args: { since: '2026-10-01', date: '2026-11-12' }, agent: fake.agent, logs: [] })
    assert.equal(outcome.outcome, 'FAILED', JSON.stringify(answer))
    assert.match(outcome.reason, /audit-data\.sh gave no data: (jq: command not found|jq is not installed)/)
  }
  // A field a decision rests on, missing: no "nothing to warn of", no "no pipeline case" (review round 1 of PR 2).
  const data = { file: 'f.json', prs: 3, prsWithHumanLabels: 1, unverifiedHumanLabels: 0, owner: 'o', ownerIsAutopilot: false,
    unverifiedEscapes: 0, readyPrs: 0, cases: 1, transcriptsDir: 'd' }
  for (const k of ['file', 'prs', 'prsWithHumanLabels', 'unverifiedHumanLabels', 'ownerIsAutopilot', 'unverifiedEscapes', 'cases']) {
    const { [k]: _, ...without } = data
    const fake = fakeAgent({ 'ops:audit-data.sh': without })
    const outcome = await evaluate(strip(AUDIT), { args: { since: '2026-10-01', date: '2026-11-12' }, agent: fake.agent, logs: [] })
    assert.equal(outcome.outcome, 'FAILED', k)
    assert.match(outcome.reason, new RegExp(`audit-data\\.sh gave no data: no ${k}$`), k)
    assert.ok(!fake.calls.some((c) => c.key.startsWith('audit-')), `${k}: no analyst on data that does not say it all`)
  }
})

test('backlog-autopilot: the four schemas once typed by required keys are closed, and accept what their script prints (#0-175, PR 2)', async () => {
  const S = await schemasNamed(['PREFLIGHT', 'TESTS', 'PATHS', 'NEXT'])
  for (const [name, schema] of Object.entries(S)) assert.equal(schema.additionalProperties, false, `${name} is closed`)
  const sha = 'a'.repeat(40)
  const paths = { base: sha, mergeBase: sha, head: 'b'.repeat(40), files: ['a.java'], delta: [], modules: ['incident-service'],
    areas: ['incident-service'], ruleFiles: ['general'], protectedTouched: [], migrationTouched: false, editedAppliedMigrations: [],
    k8sOrBuildTouched: false, pomSupplyChainChange: false, pomSupplyChainLines: '', allModules: false, deletedTests: [],
    disabledTestsAdded: 0, docsTouched: false, readyFlagAdded: false, buildConfigChanged: [], claudeMdOutsideBlocks: false,
    needsHuman: false }
  const printed = {
    PREFLIGHT: [{ ok: true, reasons: [], baseRef: 'origin/main', baseSha: sha, runId: '20261112-120000', today: '2026-11-12',
      state: { consecutiveBlocked: 0, shippedSinceAudit: 2, lastAudit: null, history: [] } },
    { ok: false, reasons: ['audit due'], baseRef: '', baseSha: '', runId: '', today: '2026-11-12', state: {} }],
    TESTS: [{ status: 'pass', exitCode: 0, modules: 'oncall-service', log: 'l', head: sha, artifact: 'a.json', summary: ['BUILD SUCCESS'] },
      { status: 'stop', exitCode: -1, modules: '', log: '', head: '', artifact: null, summary: ['invalid round: x'] }],
    PATHS: [paths, { error: 'no merge base with origin/main' }],
    NEXT: [{ ok: true, reasons: [], item: '#0-25', source: 'queue', eligible: true, reason: null, touches: 'oncall-service',
      modules: ['oncall-service'], followUpOf: null, position: 1, risk: 'low', complexity: 'low', type: 'bug', branchPrefix: 'fix', skipped: [] },
    { ok: true, reasons: [], item: null, source: 'queue', eligible: false, reason: 'queue done', skipped: [{ item: '#0-4', why: 'not ready' }] },
    { ok: false, reasons: ['gh pr list failed: cannot check locks'], item: null }],
  }
  for (const [name, answers] of Object.entries(printed)) {
    for (const answer of [...answers, ...FAILURES]) assert.ok(conforms(answer, S[name]), `${name} accepts ${JSON.stringify(answer)}`)
  }
  const answered = {
    PREFLIGHT: [{ output: '{"ok":true}' }, { ok: 'true' }],
    TESTS: [{ status: 'passed' }, { output: '{"status":"pass"}' }],
    PATHS: [{ ...paths, needsHuman: 'false' }, { ...paths, verdict: 'fine' }],
    NEXT: [{ output: '{"ok":true}' }, { ok: true, item: 25 }],
  }
  for (const [name, answers] of Object.entries(answered)) {
    for (const answer of answers) assert.ok(!conforms(answer, S[name]), `${name} refuses ${JSON.stringify(answer)}`)
  }
})

test('backlog-autopilot: a factory script\'s failure stops with its reason; changed-paths\'s never reads as nothing to check (#0-175, PR 2)', async () => {
  for (const answer of FAILURES) {
    const reason = answer.error ?? answer.reasons[0]
    const pre = await run({ answers: { 'ops:preflight.sh': answer } })
    assert.equal(pre.outcome.outcome, 'NOT_STARTED'); assert.ok(pre.outcome.reasons.some((r) => r.includes(reason)), 'preflight')
    // The preflight's own refusal keeps one reason per check (review round 1 of PR 2).
    const own = await run({ answers: { 'ops:preflight.sh': { ok: false, reasons: ['audit due', 'not in the devcontainer'] } } })
    assert.deepEqual(own.outcome.reasons, ['audit due', 'not in the devcontainer'])
    const next = await run({ answers: { 'ops:next-item.sh': answer } })
    assert.ok(next.outcome.reasons.some((r) => r.includes(reason)), 'next-item')
    const ownNext = await run({ answers: { 'ops:next-item.sh': { ok: false, reasons: ['gh pr list failed', 'a second reason'], item: null } } })
    assert.deepEqual(ownNext.outcome.reasons, ['gh pr list failed', 'a second reason'], "next-item's own reasons, one each")
    const tests = await run({ answers: { 'ops:run-tests.sh': answer } })
    assert.equal(tests.outcome.outcome, 'BLOCKED'); assert.match(tests.outcome.reason, new RegExp(`test gate gave no status: ${reason}`))
    assert.ok(!keys(tests.calls).includes('implementer-light') || tests.calls.filter((c) => c.key === 'implementer-light').length === 1,
      'no fix round on an answer that is not the gate\'s')
    // Each changed-paths.sh call on its own: the head check, then the path gate after a clean one (without `required`
    // keys, a failure there would read as "nothing needs a human"), then the rules for the diff.
    for (const label of ['head check', 'changed paths', 'rules for the diff']) {
      const only = ({ opts }) => (opts.label === label ? answer : DEFAULTS['ops:changed-paths.sh'])
      const paths = await run({ answers: { 'ops:changed-paths.sh': only } })
      assert.equal(paths.outcome.outcome, 'BLOCKED', label)
      assert.ok(paths.outcome.reason.includes(reason), `${label}: the stop says why (${paths.outcome.reason})`)
      assert.ok(!keys(paths.calls).some((k) => k.startsWith('review-')), `${label}: no panel on a diff nothing has checked`)
    }
  }
})

// The top-level keys of every jq object literal in `text` whose first key is one of `anchors` (a `${var:…}` expansion is
// not one). Strings are skipped, with their `\(…)` interpolations, so a brace or a comma inside one counts for nothing.
const OPENER = { '{': '}', '[': ']', '(': ')' }
function skipJqString(t, i) {
  for (i++; i < t.length; i++) {
    if (t[i] === '\\' && t[i + 1] === '(') { const j = skipJqCode(t, i + 2, ')'); if (j < 0) return -1; i = j - 1; continue }
    if (t[i] === '\\') { i++; continue }
    if (t[i] === '"') return i + 1
  }
  return -1
}
function skipJqCode(t, i, close) {
  for (; i < t.length; i++) {
    const c = t[i]
    if (c === close) return i + 1
    if (c === '"') { const j = skipJqString(t, i); if (j < 0) return -1; i = j - 1; continue }
    if (OPENER[c]) { const j = skipJqCode(t, i + 1, OPENER[c]); if (j < 0) return -1; i = j - 1 }
  }
  return -1
}
function jqObjectKeys(text, anchors) {
  const keys = new Set()
  for (const m of text.matchAll(new RegExp(`(?<![$\\w])\\{\\s*(?:${anchors.join('|')})\\s*:`, 'g'))) {
    const end = skipJqCode(text, m.index + 1, '}')
    if (end < 0) throw new Error(`an unbalanced jq object at offset ${m.index}`)
    const obj = text.slice(m.index, end)
    let seg = 1
    const take = (s) => { const k = /^\s*(?:"([^"]+)"|\$?([A-Za-z_]\w*))\s*(?::|$)/.exec(s); if (k) keys.add(k[1] ?? k[2]) }
    for (let i = 1; i < obj.length - 1; i++) {
      if (obj[i] === '"') { i = skipJqString(obj, i) - 1; continue }
      if (OPENER[obj[i]]) { i = skipJqCode(obj, i + 1, OPENER[obj[i]]) - 1; continue }
      if (obj[i] === ',') { take(obj.slice(seg, i)); seg = i + 1 }
    }
    take(obj.slice(seg, obj.length - 1))
  }
  return keys
}

test('the jq key scan reads nested objects, strings and interpolations as a script writes them', () => {
  const keys = jqObjectKeys(`echo "\${base:0:40}"; jq -n '{ok: true, reasons: [], item: ("#" + $id), why: "a, b {c: d}",
    msg: "\\(if $t == "" then "none, x" else $t end)", nested: {inner: 1}, $short}' + {skipped: []}`, ['ok', 'skipped', 'base'])
  assert.deepEqual([...keys].sort(), ['item', 'msg', 'nested', 'ok', 'reasons', 'short', 'skipped', 'why'])
  assert.throws(() => jqObjectKeys("jq -n '{ok: (1'", ['ok']), /unbalanced/)
})

test('every key a factory script prints is in the schema its workflow reads it with (#0-175, PR 2)', async () => {
  // A closed schema refuses an answer with a key it does not name: a field added to a script and not to the schema
  // would stop every run. So the keys are read from the scripts' own jq objects, not from examples written here.
  const auto = await schemasNamed(['PREFLIGHT', 'TESTS', 'PATHS', 'NEXT', 'STARTED', 'RESUMED', 'BACK_TO_MAIN'])
  const { AUDIT_DATA } = await auditSchemas(['AUDIT_DATA'])
  const script = (name) => readFileSync(join(dirname(FILE), '../../scripts/factory', name), 'utf8')
  for (const [name, anchors, schema, label] of [
    ['preflight.sh', ['ok'], auto.PREFLIGHT, 'PREFLIGHT'], ['run-tests.sh', ['status'], auto.TESTS, 'TESTS'],
    ['changed-paths.sh', ['base', 'error'], auto.PATHS, 'PATHS'], ['next-item.sh', ['ok', 'skipped'], auto.NEXT, 'NEXT'],
    ['start-item.sh', ['ok'], auto.STARTED, 'STARTED'], ['resume-item.sh', ['ok'], auto.RESUMED, 'RESUMED'],
    ['return-to-main.sh', ['onMain'], auto.BACK_TO_MAIN, 'BACK_TO_MAIN'], ['audit-data.sh', ['file'], AUDIT_DATA, 'AUDIT_DATA'],
  ]) {
    const printed = jqObjectKeys(script(name), anchors)
    assert.ok(printed.size >= 3, `${name}: the scan found ${printed.size} keys: it no longer reads the script`)
    const missing = [...printed].filter((k) => !(k in schema.properties))
    assert.deepEqual(missing, [], `${name} prints keys ${label} does not name`)
  }
})

// ---------------------------------------------------------------- /audit and /docs-audit from their words (#0-175, AC1)

// One whole run of another workflow's text: its outcome and its agent calls.
async function runOf(src, args, answers) {
  const fake = fakeAgent(answers)
  const outcome = await evaluate(strip(src), { args, agent: fake.agent, logs: [] })
  return { outcome, calls: fake.calls }
}
const AUDITED = {
  'ops:audit-data.sh': { file: '.ai/runs/audit-data.json', prs: 3, prsWithHumanLabels: 1, unverifiedHumanLabels: 0, owner: 'o',
    ownerIsAutopilot: false, unverifiedEscapes: 0, readyPrs: 0, cases: 1, transcriptsDir: 'd' },
  'audit-reviewers': ({ prompt }) => ({ dimension: prompt.match(/dimension `(\w+)`/)[1], findings: [], recommendations: [] }),
  'audit-pipeline': { cases: [], findings: [], recommendations: [] },
  'audit-synthesis': ({ prompt }) => ({ report: `.ai/audit/${prompt.match(/target (\w+)/)[1]}.md`, recommendations: 0 }),
}
const SINCE = '2026-10-01', TODAY = '2026-11-12'

test('audit: `/audit <since> <date> [target] [dimension…]` passes one string, read in the order of the keys (#0-175, AC1)', async () => {
  for (const [words, object] of [
    [`${SINCE} ${TODAY}`, { since: SINCE, date: TODAY }],
    [`  ${SINCE}\t${TODAY}\n`, { since: SINCE, date: TODAY }],
    [`${SINCE} ${TODAY} all`, { since: SINCE, date: TODAY, target: 'all' }],
    [`${SINCE} ${TODAY} pipeline`, { since: SINCE, date: TODAY, target: 'pipeline' }],
    [`${SINCE} ${TODAY} reviewers security docs`, { since: SINCE, date: TODAY, target: 'reviewers', dimensions: ['security', 'docs'] }],
  ]) {
    const fromWords = await runOf(AUDIT, words, AUDITED)
    const fromObject = await runOf(AUDIT, object, AUDITED)
    assert.notEqual(fromObject.outcome.outcome, 'NOT_STARTED', JSON.stringify(object))
    assert.deepEqual(fromWords.outcome, fromObject.outcome, JSON.stringify(words))
    assert.deepEqual(fromWords.calls.map((c) => c.prompt), fromObject.calls.map((c) => c.prompt), JSON.stringify(words))
  }
  const two = await runOf(AUDIT, `${SINCE} ${TODAY} reviewers security docs`, AUDITED)
  assert.deepEqual(two.calls.filter((c) => c.key === 'audit-reviewers').map((c) => c.label), ['audit security', 'audit docs'])
  assert.ok(!keys(two.calls).includes('audit-pipeline'), 'target reviewers: no pipeline analyst')
})

test('audit: a wrong count, a date that is not one, an unknown target or dimension start nothing (#0-175, AC1)', async () => {
  for (const [args, why] of [
    ['', /^pass args \{ since, date, target\?, dimensions\? \}, or the words "<since> <date>/], [SINCE, /^pass args/],
    [`${SINCE} yesterday`, /^pass args/], [`${SINCE};rm ${TODAY}`, /^pass args/], [undefined, /^pass args/], [null, /^pass args/],
    [{ since: SINCE }, /^pass args/], [{ since: SINCE, date: 20261112 }, /^pass args/],
    [`${SINCE} ${TODAY} security`, /^no audit defined for target security; pass args/],
    [`${SINCE} ${TODAY} reviewers secruity docs`, /^no review dimension secruity \(one of general, /],
    [{ since: SINCE, date: TODAY, dimensions: ['security', 'nope'] }, /^no review dimension nope /],
  ]) {
    const { outcome, calls } = await runOf(AUDIT, args, AUDITED)
    assert.equal(outcome.outcome, 'NOT_STARTED', String(JSON.stringify(args)))
    assert.match(outcome.reason, why, String(JSON.stringify(args)))
    assert.equal(calls.length, 0, `nothing runs on ${JSON.stringify(args)}`)
  }
})

const DOCS_AUDIT = readFileSync(join(dirname(FILE), 'docs-audit.js'), 'utf8')
const DOCS_AUDITED = { 'review-docs': { drifts: [{ file: 'README.md', level: 'B', issue: 'names a removed class' }] },
  'audit-synthesis': { report: `.ai/audit/${TODAY}-docs.md` } }

test('docs-audit: `/docs-audit <date>` passes one string, read as the date; anything else starts nothing (#0-175, AC1)', async () => {
  const fromObject = await runOf(DOCS_AUDIT, { date: TODAY }, DOCS_AUDITED)
  assert.equal(fromObject.outcome.outcome, 'REPORTED')
  assert.match(fromObject.calls.find((c) => c.key === 'audit-synthesis').prompt, new RegExp(`^Write \\.ai/audit/${TODAY}-docs\\.md:`))
  for (const words of [TODAY, `  ${TODAY}\n`]) {
    const fromWords = await runOf(DOCS_AUDIT, words, DOCS_AUDITED)
    assert.deepEqual(fromWords.outcome, fromObject.outcome, JSON.stringify(words))
    assert.deepEqual(fromWords.calls.map((c) => c.prompt), fromObject.calls.map((c) => c.prompt), JSON.stringify(words))
  }
  // The date names the report's file: one that is not a date (a path, a number) is refused, as a wrong count is.
  for (const args of ['', `${TODAY} extra`, 'tomorrow', '../../x', undefined, null, {}, { date: '../../x' }, { date: 20261112 }]) {
    const { outcome, calls } = await runOf(DOCS_AUDIT, args, DOCS_AUDITED)
    assert.equal(outcome.outcome, 'NOT_STARTED', String(JSON.stringify(args)))
    assert.match(outcome.reason, /^pass args \{ date \}, or the word "<date>" \(YYYY-MM-DD\)$/)
    assert.equal(calls.length, 0, `nothing runs on ${JSON.stringify(args)}`)
  }
})
