export const meta = {
  name: 'backlog-autopilot',
  description: 'Takes one ready backlog item from pick to pull request: plan, implement, test gate, review panel, verification, acceptance, ship. Shadow mode by default.',
  phases: ['Preflight', 'Pick', 'Plan', 'Implement', 'Review', 'Acceptance', 'Ship'],
}

// ============================================================================================
// Backlog autopilot — one item per run. Run it in an autopilot session:
//   claude --settings .claude/settings.autopilot.json      then   /backlog-autopilot
// Which item: decided in code by scripts/factory/next-item.sh — a ready follow-up of a done item first,
// then the approved queue (.ai/plan/queue.md), strictly row by row, or priority order while there is no
// queue. One item at a time; the autopilot never runs two.
// Rules: the implementer always reads the core rule files (general, architecture, security); the
// architect's plan selects the rules of the other files that apply; after implementing, a rule file the
// diff calls for (changed-paths.sh "ruleFiles") from which the plan listed no rule triggers a self-check
// before the panel sees the change. The panel always judges against its full files.
// Scope: the item's Touches, the architect's planned modules and the areas the diff reached are compared
// and recorded in the PR (.ai/rules/planning.md, "Touches") — a measurement, never a gate.
// Args (all optional), as the command's words (backlog #0-175, AC1):
//   /backlog-autopilot                          the next item
//   /backlog-autopilot #0-25                    this item (as args { item })
//   /backlog-autopilot #0-25 fix/0-25-…         resume this item on its branch (as args { item, branch })
// or as an object, whose keys are below; shadow, maxRounds, localReview and acceptUnverifiable are object-only:
//   item:     '#0-25'           take this item instead (it must still be `ready` on main, deps done, no lock)
//   branch:   'fix/0-25-…'      resume an existing branch (after a BLOCKED item was resolved, or a
//                               branch from scripts/factory-admin/local-implement.sh): skips pick/plan/implement
//   shadow:   true (default)    open the PR, never merge. Set false only in phase 3 (docs/ai-factory.md:
//                               after backlog #0-116 and #0-153).
//   maxRounds: 3                review rounds before the item is BLOCKED
//   localReview: false          advisory second opinion from a local model (scripts/factory/local-review.sh)
//   acceptUnverifiable: ['ver-1a2b3c4d']   with branch only: the ids of the claims the verifier could not settle
//                               that the owner read in the draft PR ("Unverified claims") and accepts; they ship
//                               listed as accepted by the owner, never as verified. Ids, not a flag: a resume
//                               runs the panel again, and a claim it raises for the first time stops the item
//                               again instead of passing unread (backlog #0-160, review round 1)
//
// Tested by .github/scripts/test-autopilot-workflow.mjs (backlog #0-163), which evaluates this text with a fake agent():
// it reads the helpers up to the `// ---- run` marker below, so keep the `helpers` and `run` marker lines, each once.
//
// The script decides; agents only do. Every branch below is code, every limit is a constant, and a
// missing or malformed answer from an agent stops the item (fail closed) instead of counting as "OK".
// The script has no shell: deterministic steps run through the `factory-ops` agent, which may only run
// scripts/factory/*.sh and returns their JSON unchanged.
//
// VERIFY BEFORE THE FIRST RUN (run /workflow-authoring to load the script reference):
//   1. AGENT_TYPE_OPTION — the agent() option that selects a custom agent from .claude/agents/. The public
//      docs checked on 2026-10-05 mention "agent type" but not the option's name. The isolation check in
//      Preflight stops the run if the option is wrong (a reviewer that can edit files is not a reviewer).
//   2. parallel() — that it takes an array of functions returning agent() promises, as used in runAll().
// ============================================================================================

const AGENT_TYPE_OPTION = 'agentType'
// Fixed (backlog #0-175, AC1): Claude Code hands the script the command's words as one string, so
// `/backlog-autopilot #0-25` read no args.item and ran the queue's next item instead. The words are read as seed-bugs.js
// reads its own (#0-174): one word is the item, two are the item and the branch to resume, and both are then checked as
// the object's values are (the item's form, the branch's rule, the branch's item). No word is the next item; three or
// more is no run (null, refused before the preflight, so before the first agent): no field is read from a word by guess.
const WORDS = typeof args === 'string' ? args.trim().split(/\s+/).filter(Boolean) : null
const params = !WORDS ? (args ?? {})
  : WORDS.length === 0 ? {}
  : WORDS.length === 1 ? { item: WORDS[0] }
  : WORDS.length === 2 ? { item: WORDS[0], branch: WORDS[1] }
  : null
const USAGE = 'pass no words (the next item), "#0-N" (that item) or "#0-N <branch>" (resume it on its branch), or args { item, branch, … }'
const SHADOW = params?.shadow !== false
const MAX_ROUNDS = Math.min(Math.max(params?.maxRounds ?? 3, 1), 3)
const MAX_TEST_FIXES = 2          // fix-tests attempts per gate before the item is BLOCKED
const MAX_AGENT_CALLS = 45        // budget per item; a runaway item stops instead of eating the limit

const PANEL_ALWAYS = ['general', 'architecture', 'security', 'performance', 'docs']
const CORE_RULE_FILES = ['general', 'architecture', 'security']          // the implementer always reads these in full
const RULE_FILE_OF = { GEN: 'general', ARC: 'architecture', SEC: 'security', PERF: 'performance', MIG: 'migration', K8S: 'k8s', DOC: 'docs',
  // factory.md (FAC-S for security, FAC-A for architecture; backlog #0-161). No plan lists one today: the architect
  // does not read factory.md, as no item reaches its paths. Mapped so that an FAC- id that ever reaches a plan is
  // counted as its file, not dropped by ruleFilesOf (review of #0-161).
  FAC: 'factory' }

let calls = 0                     // work agents only; ops, shipper and notifications are not budgeted
let budgetExceeded = false
let runId = 'unknown'
const base = { ref: 'origin/main', sha: null }
const CLAIM_ID = /^ver-[0-9a-f]{8}$/
const ACCEPT_UNVERIFIABLE = new Set(Array.isArray(params?.acceptUnverifiable) && params?.branch ? params.acceptUnverifiable : [])
const record = { item: null, source: null, implementer: null, plannedRules: [], selfCheck: null, scope: null,
  rounds: [], acceptance: null, tests: [], nonBlocking: [], adrs: [], local: null, verification: [] }

// ---------------------------------------------------------------- helpers

const UNBUDGETED = new Set(['factory-ops', 'shipper'])

// Why the latest agent call ended without an answer, named in the stop reason (backlog #0-206). Cleared at every
// call, so a tolerated `null` (the local second opinion) is not named in a later, unrelated stop (review round 1).
let noAnswer = null

// Fixed (backlog #0-206): an agent that ends without its structured answer (its maxTurns spent, the runtime's
// error) made agent() throw, and the exception ended the whole workflow before any caller's `stopItem` ran: runs
// wf_bc03d7e8-742 (the architect, 40 turns) and wf_c1597fde-23e (the implementer, 120 turns) left `.ai/runs/LOCK`
// with no state recorded, no draft PR and no notification. Every agent call goes through here, so here it becomes
// the `null` every caller already stops on ("… gave no answer"), and the reason is kept for the stop. The calls
// inside stopItem are covered the same way: a shipper that fails still lets `state.sh record` release the lock. If
// factory-ops itself fails on that `record` (or on `unlock`), the lock stays and the run's outcome still returns; the
// next preflight then refuses to start (a lock held), so it fails closed, and the cause is in this run's log.
async function as(type, prompt, { bare = false, ...opts } = {}) {
  noAnswer = null
  if (!UNBUDGETED.has(type)) {
    calls += 1
    if (calls > MAX_AGENT_CALLS) { budgetExceeded = true; return null }
  }
  const label = opts.label ?? type
  // `bare`: no pointer to the agent's definition file, for a question whose answer must come from the agent's own
  // instructions, not from reading that file (the isolation check, review round 1 of #0-248).
  const preamble = bare ? `Autopilot run ${runId}.\n\n`
    : `You are running as the \`${type}\` agent defined in .claude/agents/${type}.md. ` +
      `If your instructions are not that definition, read the file and follow it exactly. Autopilot run ${runId}.\n\n`
  try {
    return await agent(preamble + prompt, { ...opts, [AGENT_TYPE_OPTION]: type, label })
  } catch (e) {
    const why = String(e?.message ?? e).replace(/\s+/g, ' ').trim().slice(0, 300) || 'no reason given'
    noAnswer = `${label}: ${why}`
    log(`${label} ended without an answer: ${why}`)
    return null
  }
}

function runAll(thunks) {
  return parallel(thunks)
}

// Arguments reach a shell: only ids, refs and shas that match a strict pattern are passed, quoted.
const SAFE = /^[A-Za-z0-9._\/:-]+$/
// The branch of a backlog item, `<type>/0-<n>-<slug>`, with the item as the first group: the picker's branch must hold
// the item it took, and a resume reads its item from the branch the owner gave. scripts/factory/_common.sh holds the
// same rule as ITEM_BRANCH_RE for start-item.sh and resume-item.sh (this script cannot read a file), and
// test-autopilot-workflow.mjs fails when the two differ (backlog #0-216: four copies, nothing comparing them).
const ITEM_BRANCH = /^[a-z]+\/(0-[0-9]+)-[A-Za-z0-9._-]+$/
// The picker's part of a new item's branch (backlog #0-195): lowercase words joined by hyphens, as picker.md asks. The
// prefix is code's: next-item.sh reads it from the item's **Type:** on the base commit (_backlog.sh, BRANCH_PREFIX_OF).
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+){0,7}$/
const PREFIX = /^[a-z]+$/
function q(value) {
  const s = String(value)
  if (!SAFE.test(s)) throw new Error(`unsafe argument for a factory script: ${s}`)
  return `'${s}'`
}
function ops(script, argv, schema, label) {
  let command
  try {
    command = [`scripts/factory/${script}`, ...argv.map(q)].join(' ')
  } catch (e) {
    log(`refused to call ${script}: ${e.message}`)
    return Promise.resolve(null)          // callers treat null as "no result" and stop the item
  }
  return as('factory-ops', `Run exactly: ${command}`, { schema, label: label ?? script })
}

// The type of an item inside an agent's answer whose fields no code reads (a plan, a disputed finding): never the
// schema of a factory script's answer, see answerOf below.
const ANY_OBJECT = { type: 'object' }

// Each factory script's answer has its fields typed and nothing else: what the script prints, factory-ops' own error
// answer, or _common.sh's failure ({"ok":false,"reasons":[…]}: no jq, not inside the repository), which then reaches
// the stop reason instead of failing the schema without one (#0-175's "Also" of review round 3 of #0-177).
// Fixed (backlog #0-175): with the bare `{ type: 'object' }` (seed-bugs.js's #0-174, one workflow later), the
// agent answered state.sh's {"branch": …} as a string under a key of its own, so run wf_8c632098-97c (2026-11-01,
// #0-191) stopped at "could not record the run's branch" on a branch it had recorded; its `unlock` came back the same
// way, unread ({"output": "{\"unlocked\":true}"}). `additionalProperties: false` refuses a wrapper key and a
// typed field a string, so the runtime asks again. The check that no ops() call goes untyped: test-autopilot-workflow.mjs.
const ERROR_FIELDS = { error: { type: 'string' }, exitCode: { type: 'number' }, ok: { type: 'boolean' },
  reasons: { type: 'array', items: { type: 'string' } } }
const answerOf = (fields) => ({ type: 'object', additionalProperties: false, properties: { ...fields, ...ERROR_FIELDS } })
// Why a factory script's answer is not its own: factory-ops' error, or _common.sh's failure; null when neither.
const failureOf = (a) => a?.error ?? (Array.isArray(a?.reasons) && a.reasons.length ? a.reasons.join('; ') : null)
const STATE_BRANCH = answerOf({ branch: { type: 'string' } })
const STATE_UNLOCKED = answerOf({ unlocked: { type: 'boolean' } })
// `record` prints the whole state file (_common.sh writes it; state-reset.sh sets lastAudit, a time). Its history
// (up to 200 entries) is unread here: typed loosely, so one entry the agent copies wrong does not fail the last call
// of a shipped run (review round 1).
const STATE_RECORDED = answerOf({ consecutiveBlocked: { type: 'number' }, shippedSinceAudit: { type: 'number' },
  lastAudit: { type: ['string', 'null'] }, note: { type: 'string' }, history: { type: 'array', items: ANY_OBJECT } })
const BACK_TO_MAIN = answerOf({ onMain: { type: 'boolean' }, left: { type: 'string' }, branch: { type: 'string' },
  reason: { type: 'string' } })
const NOTIFIED = answerOf({ sent: { type: 'boolean' }, reason: { type: 'string' } })
const STARTED = answerOf({ branch: { type: 'string' }, workDir: { type: 'string' }, head: { type: 'string' } })
const RESUMED = answerOf({ branch: { type: 'string' }, item: { type: 'string' }, head: { type: 'string' } })
// `result` is the local model's answer: `claude -p --output-format json`'s text, or its whole output if it has none.
const LOCAL_REVIEW = answerOf({ ran: { type: 'boolean' }, model: { type: 'string' }, result: { type: ['string', 'object'] },
  reason: { type: 'string' } })

// The four below were typed by `required` keys only, so a key of the agent's own passed, and _common.sh's failure was
// refused without its reason (backlog #0-175, PR 2). Closed now, with every field the script prints: a test reads the
// keys of each script's jq output and fails when one is not here (test-autopilot-workflow.mjs), and the code checks the
// fields it relies on, since none is required any more.
const PREFLIGHT = answerOf({ ok: { type: 'boolean' }, reasons: { type: 'array', items: { type: 'string' } },
  baseRef: { type: 'string' }, baseSha: { type: 'string' }, runId: { type: 'string' }, today: { type: 'string' },
  state: { type: 'object' } })
const ISOLATION = {
  type: 'object', required: ['tools', 'opening'],
  properties: { tools: { type: 'array', items: { type: 'string' } }, opening: { type: 'string' } },
}
// The opening words of review-general's definition (.claude/agents/review-general.md, the first line of its body;
// test-autopilot-workflow.mjs fails when the two differ). The isolation check asked the agent whether its
// instructions were that definition, and trusted a yes or no: with Claude Code 2.1.325 in the build VM the agent
// answered no twice, its definition loaded (its transcript shows it), as the text never names itself review-general
// (runs wf_1e3befc7-a08 and wf_477d7545-796, backlog #0-248). It quotes the opening of its instructions now, a fact
// to compare, not a judgement, and the workflow looks for this phrase in it, not at its start: a runtime may put a
// preamble of its own before the definition (review round 1). The question goes without as()'s preamble, which
// points at the definition's file: an agent told to read it could copy the phrase from there. What stays: the phrase
// tells review-general from another read-only definition, and an agent that can read the repository could still
// find it unasked; the barrier is the tool check (no editing tool), as an agent of the wrong type has Edit and Write.
// That check takes the agent's own list and names four tools: an MCP tool that writes files is not one of them
// (named in #0-248).
const REVIEW_GENERAL_OPENING = 'You are the general reviewer'
const PICK = {
  type: 'object', required: ['none'],
  properties: { none: { type: 'boolean' }, failed: { type: 'boolean' }, reason: { type: 'string' }, itemId: { type: 'string' }, title: { type: 'string' },
    type: { type: 'string' }, risk: { type: 'string' }, complexity: { type: 'string' }, branch: { type: 'string' },
    slug: { type: 'string' }, workDir: { type: 'string' }, acceptanceCriteria: { type: 'array', items: { type: 'string' } } },
}
const PLAN = {
  type: 'object', required: ['blocked'],
  properties: { blocked: { type: 'boolean' }, reason: { type: ['string', 'null'] }, plan: ANY_OBJECT,
    adrs: { type: 'array', items: { type: 'string' } }, risks: { type: 'array', items: { type: 'string' } },
    areas: ANY_OBJECT, modules: { type: 'array', items: { type: 'string' } },
    rules: { type: 'array', items: { type: 'object', required: ['id'], properties: { id: { type: 'string' }, why: { type: 'string' } } } } },
}
const IMPL = {
  type: 'object', required: ['blocked', 'headSha'],
  properties: { blocked: { type: 'boolean' }, reason: { type: ['string', 'null'] }, headSha: { type: 'string' },
    commits: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' },
    fixed: { type: 'array', items: { type: 'string' } },
    disputed: { type: 'array', items: ANY_OBJECT }, noticedNotTouched: { type: 'array', items: { type: 'string' } } },
}
const TESTS = answerOf({ status: { type: 'string', enum: ['pass', 'fixable', 'stop'] }, exitCode: { type: 'number' },
  modules: { type: 'string' }, log: { type: 'string' }, head: { type: 'string' }, artifact: { type: ['string', 'null'] },
  summary: { type: 'array', items: { type: 'string' } } })
const STRINGS = { type: 'array', items: { type: 'string' } }
const PATHS = answerOf({ base: { type: 'string' }, mergeBase: { type: 'string' }, head: { type: 'string' }, files: STRINGS,
  delta: STRINGS, modules: STRINGS, areas: STRINGS, ruleFiles: STRINGS, protectedTouched: STRINGS,
  migrationTouched: { type: 'boolean' }, editedAppliedMigrations: STRINGS, k8sOrBuildTouched: { type: 'boolean' },
  pomSupplyChainChange: { type: 'boolean' }, pomSupplyChainLines: { type: 'string' }, allModules: { type: 'boolean' },
  deletedTests: STRINGS, disabledTestsAdded: { type: 'number' }, docsTouched: { type: 'boolean' },
  readyFlagAdded: { type: 'boolean' }, buildConfigChanged: STRINGS, claudeMdOutsideBlocks: { type: 'boolean' },
  needsHuman: { type: 'boolean' } })
const FINDING = {
  type: 'object', required: ['id', 'ruleId', 'issue', 'impact'],
  properties: { id: { type: 'string' }, ruleId: { type: 'string' }, file: { type: 'string' }, line: { type: ['number', 'null'] },
    issue: { type: 'string' }, impact: { type: 'string' }, fix: { type: 'string' }, isRegression: { type: 'boolean' } },
}
const VERDICT = {
  type: 'object', required: ['dimension', 'verdict', 'blocking', 'nonBlocking', 'resolved', 'upheldDisputes'],
  properties: {
    dimension: { type: 'string' }, round: { type: 'number' },
    verdict: { type: 'string', enum: ['APPROVE', 'CHANGES_REQUESTED', 'NEEDS_HUMAN'] },
    blocking: { type: 'array', items: FINDING }, nonBlocking: { type: 'array', items: ANY_OBJECT },
    resolved: { type: 'array', items: { type: 'string' } }, upheldDisputes: { type: 'array', items: ANY_OBJECT },
    outOfScope: { type: 'array', items: { type: 'string' } }, ruleGap: { type: 'array', items: { type: 'string' } },
    unverified: { type: 'array', items: { type: 'string' } },
  },
}
// The verifier's answer: one entry per claim, by its index (.claude/agents/verifier.md).
const VERIFICATION = {
  type: 'object', required: ['items'],
  properties: { items: { type: 'array', items: { type: 'object', required: ['index', 'verdict', 'why'],
    properties: { index: { type: 'number' }, verdict: { type: 'string', enum: ['verified', 'refuted', 'unverifiable'] },
      source: { type: ['string', 'null'] }, quote: { type: ['string', 'null'] }, why: { type: 'string' } } } } },
}
const ACCEPT = {
  type: 'object', required: ['verdict', 'criteria'],
  properties: { item: { type: 'string' }, verdict: { type: 'string', enum: ['ACCEPT', 'REJECT', 'NEEDS_HUMAN'] },
    criteria: { type: 'array', items: ANY_OBJECT }, scopeCreep: { type: 'array', items: { type: 'string' } },
    reason: { type: 'string' } },
}
const SHIP = {
  type: 'object', required: ['mode'],
  properties: { mode: { type: 'string' }, prNumber: { type: ['number', 'null'] }, prUrl: { type: ['string', 'null'] },
    merged: { type: 'string' }, labelsMissing: { type: 'array', items: { type: 'string' } },
    followUpsCreated: { type: 'array', items: { type: 'string' } }, error: { type: ['string', 'null'] } },
}
const NEXT = answerOf({ ok: { type: 'boolean' }, reasons: { type: 'array', items: { type: 'string' } },
  item: { type: ['string', 'null'] }, source: { type: 'string' }, eligible: { type: 'boolean' },
  reason: { type: ['string', 'null'] }, touches: { type: 'string' }, modules: { type: 'array', items: { type: 'string' } },
  followUpOf: { type: ['string', 'null'] }, position: { type: ['number', 'null'] }, skipped: { type: 'array', items: ANY_OBJECT },
  risk: { type: 'string' }, complexity: { type: 'string' }, type: { type: 'string' }, branchPrefix: { type: ['string', 'null'] } })

async function notStarted(reasons, outcome = 'NOT_STARTED') {
  await ops('state.sh', ['unlock'], STATE_UNLOCKED, 'state')
  await ops('return-to-main.sh', [], BACK_TO_MAIN, 'back to main')
  return outcome === 'NOT_STARTED' ? { outcome, reasons } : { outcome, reason: reasons.join('; ') }
}

async function notify(event, detail) {
  // Event and detail are identifiers only (no free text reaches the shell).
  await ops('notify.sh', [event, detail ?? '-'], NOTIFIED, 'notify')
}

// The phase the run is in, recorded with a BLOCKED item so the audit sees where the pipeline stopped it
// (.ai/rules/audit.md, "Stop stage"). Fixed (backlog #0-122): the state history held only "blocked", with no stage.
let stage = 'preflight'
function enterPhase(name) {
  stage = name.toLowerCase()
  phase(name)
}
// A PR URL as a state.sh argument: one q() would refuse becomes "-", so the record (lock release, breaker
// count) is never lost to an odd URL (backlog #0-122, review round 1).
const prArg = (url) => (url && SAFE.test(url) ? url : '-')

// `item` is the picker's answer once it named a branch; `{ itemId, id }` alone (the picker failed, backlog #0-206)
// records the stop against the item with no draft PR, as there is no branch of the run to push; null, before any
// item, only releases the lock.
async function stopItem(item, reason) {
  if (budgetExceeded) reason = `agent budget of ${MAX_AGENT_CALLS} calls exceeded — split the item (last step: ${reason})`
  if (noAnswer && !reason.includes(noAnswer)) reason = `${reason} (last agent call without an answer: ${noAnswer})`
  log(`BLOCKED ${item?.itemId ?? ''}: ${reason}`)
  if (item?.branch) {
    const draft = await as('shipper', [
      `Mode: blocked. Item ${item.itemId} ("${item.title}"), branch ${item.branch}, run ${runId}.`,
      `Reason: ${reason}`,
      `Review record so far (JSON): ${JSON.stringify(record)}`,
    ].join('\n'), { schema: SHIP })
    await ops('state.sh', ['record', 'blocked', item.id, prArg(draft?.prUrl), stage], STATE_RECORDED, 'state')
  } else if (item?.id) {
    await ops('state.sh', ['record', 'blocked', item.id, '-', stage], STATE_RECORDED, 'state')
    await ops('return-to-main.sh', [], BACK_TO_MAIN, 'back to main')
  } else {
    await ops('state.sh', ['unlock'], STATE_UNLOCKED, 'state')
    await ops('return-to-main.sh', [], BACK_TO_MAIN, 'back to main')
  }
  await notify('blocked', item?.id ?? 'run')
  return { outcome: 'BLOCKED', item: item?.itemId ?? null, reason, agentCalls: calls }
}

// Rule ids the architect selected → the rule files they come from (GEN-03 → general).
function ruleFilesOf(rules) {
  return [...new Set((rules ?? []).map((r) => RULE_FILE_OF[String(r.id ?? '').split('-')[0]]).filter(Boolean))]
}

// Three predictions of the same reach, made at different times from different knowledge: the item's
// Touches (at /ready), the architect's modules (just before implementing), the diff (after). A prediction
// "holds" when the diff stays within it; predicting more than happened is not a miss. Which prediction
// failed says which stage was off (.ai/rules/audit.md, "Signals"). Measured, never a gate.
// The categories below are read by scripts/factory/audit-data.sh (backlog #0-121), which counts every category
// except consistent, within-plan, within-touches and not-measured as a pipeline case: a new category here must be
// added there (as clean or as a miss), to the Signals table and the "Pipeline audit" case list in .ai/rules/audit.md.
function scopeOf(touches, planned, actual) {
  const set = (x) => (Array.isArray(x) && x.length ? [...new Set(x)].sort() : null)
  const t = set(touches), p = set(planned), a = set(actual)
  const outside = (pred) => (pred && a ? a.filter((m) => !pred.includes(m)) : [])
  const holds = (pred) => outside(pred).length === 0
  const same = (x, y) => x.length === y.length && x.every((v, i) => v === y[i])
  let category
  if (!a || (!t && !p)) category = 'not-measured'            // the diff reached no module, or nothing was predicted
  else if (!t) category = holds(p) ? 'within-plan' : 'diff-outside-plan'
  else if (!p) category = holds(t) ? 'within-touches' : 'diff-outside-touches'
  else if (holds(t) && holds(p)) category = 'consistent'
  else if (holds(p)) category = 'backlog-estimate-off'        // the architect corrected the estimate
  else if (holds(t)) category = 'plan-off'                    // the plan narrowed it wrongly; the estimate held
  else if (same(t, p)) category = 'implementation-drift'      // both predictions agreed, the diff went beyond
  else category = 'unclear-item'                              // the predictions disagreed and both missed
  return { touches: t, plan: p, actual: a ?? [], category, outsideTouches: outside(t), outsidePlan: outside(p) }
}

function valid(v) {
  return v && typeof v.verdict === 'string' && Array.isArray(v.blocking) && Array.isArray(v.resolved)
    && Array.isArray(v.upheldDisputes) && v.blocking.every((f) => f.id && f.ruleId && f.impact)
}

// Test gate: run, let the implementer fix a fixable failure up to MAX_TEST_FIXES times.
async function testGate(item, round) {
  for (let attempt = 0; attempt <= MAX_TEST_FIXES; attempt++) {
    const t = await ops('run-tests.sh', [item.id, `${round}-${attempt}`, base.ref], TESTS, `tests r${round}`)
    if (!t) return { ok: false, reason: 'test gate returned no result' }
    if (!['pass', 'fixable', 'stop'].includes(t.status)) return { ok: false, reason: `test gate gave no status: ${String(failureOf(t) ?? 'no reason given').slice(0, 300)}` }
    if (t.status === 'stop') return { ok: false, reason: `test gate stopped (log ${t.log}): ${(t.summary ?? []).slice(-3).join(' | ')}` }
    const head = await ops('changed-paths.sh', [base.ref], PATHS, 'head check')
    if (!head || !t.head || t.head !== head.head) {
      const why = failureOf(head)
      return { ok: false, reason: why ? `changed-paths could not read the branch HEAD: ${String(why).slice(0, 300)}` : `the tested commit (${t.head}) is not the branch HEAD (${head?.head}): something changed the tree during the gate` }
    }
    record.tests.push({ round, attempt, status: t.status, modules: t.modules, artifact: t.artifact ?? null })
    // A pass without its artifact would send the reviewers back to "the gate passed" (backlog #0-160).
    if (t.status === 'pass' && !t.artifact) return { ok: false, reason: `the test gate passed without its artifact (log ${t.log})` }
    if (t.status === 'pass') return { ok: true, head: t.head, artifact: t.artifact }
    if (attempt === MAX_TEST_FIXES) break
    const fix = await as(IMPL_TYPE, [
      `Mode: fix-tests. Item ${item.itemId}, branch ${item.branch}, round ${round}.`,
      `The test gate failed (log ${t.log}). Summary:\n${(t.summary ?? []).join('\n')}`,
    ].join('\n'), { schema: IMPL, label: `fix tests r${round}` })
    if (!fix || fix.blocked) return { ok: false, reason: fix?.reason ?? 'implementer gave no answer while fixing tests' }
  }
  return { ok: false, reason: `tests still failing after ${MAX_TEST_FIXES} fix attempts` }
}

// Paths only the owner may change, edited migrations, removed tests, POM supply chain.
async function pathGate(previousSha) {
  const p = await ops('changed-paths.sh', previousSha ? [base.ref, previousSha] : [base.ref], PATHS, 'changed paths')
  if (!p) return { ok: false, reason: 'changed-paths returned no result' }
  // Fail closed: with no `required` keys, an answer that is not the script's own (_common.sh's failure) must not read
  // as "nothing needs a human".
  if (typeof p.needsHuman !== 'boolean' || !Array.isArray(p.files)) {
    return { ok: false, reason: `changed-paths gave no answer of its own: ${String(failureOf(p) ?? 'no needsHuman').slice(0, 300)}` }
  }
  if (p.needsHuman) {
    const why = [
      p.protectedTouched?.length ? `human-owned paths changed: ${p.protectedTouched.join(', ')}` : null,
      p.editedAppliedMigrations?.length ? `applied migrations edited: ${p.editedAppliedMigrations.join(', ')}` : null,
      p.pomSupplyChainChange ? 'POM adds a plugin, repository or dependency' : null,
      p.deletedTests?.length ? `tests deleted: ${p.deletedTests.join(', ')}` : null,
      p.disabledTestsAdded ? `${p.disabledTestsAdded} @Disabled added` : null,
      p.readyFlagAdded ? 'a backlog item was marked ready' : null,
      p.buildConfigChanged?.length ? `build configuration changed: ${p.buildConfigChanged.join(', ')}` : null,
      p.claudeMdOutsideBlocks ? 'CLAUDE.md changed outside its agent-editable blocks' : null,
    ].filter(Boolean).join('; ')
    return { ok: false, reason: `NEEDS_HUMAN — ${why}`, paths: p }
  }
  return { ok: true, paths: p }
}

async function reviewRound(item, round, dimensions, mergeBase, previousSha, previous, gateArtifact) {
  const answers = await runAll(dimensions.map((dim) => () => as(`review-${dim}`, [
    `Autopilot review. Item ${item.itemId} ("${item.title}"), branch ${item.branch}.`,
    `mergeBase: ${mergeBase}. round: ${round}.`,
    round > 1 ? `previousRoundSha: ${previousSha}. Your blocking findings of the previous round: ${JSON.stringify(previous[dim] ?? [])}` : '',
    // The gate's artifact, not only its verdict (backlog #0-160): tests, coverage and dependency tree of this HEAD.
    `The test gate passed (./mvnw verify, affected modules, JaCoCo check). Its artifact: ${gateArtifact} — read it, check its head equals \`git rev-parse HEAD\`, and use its numbers and dependency tree instead of marking them unverified.`,
    `Acceptance criteria of the item:\n${(item.acceptanceCriteria ?? []).join('\n')}`,
    `Answer with the verdict JSON only.`,
  ].filter(Boolean).join('\n'), { schema: VERDICT, label: `${dim} r${round}` })))
  // The dimension of each verdict is the one we asked for (by position), never what the reviewer wrote.
  const verdicts = answers.map((v, i) => (v && v.dimension === dimensions[i] ? v : null))
  record.rounds.push({ round, dimensions, verdicts })
  return verdicts
}

// Verification (backlog #0-160): what the panel could not check is checked, not dropped. The claims are the
// `unverified` lists of each dimension's latest verdict (a dimension not asked again in a later round keeps its
// last word), deduplicated; the verifier gets only them, the commit and the gate's artifact — never the diff —
// and may fetch from an allow-list only (webfetch-allowlist.sh, ADR-0037). An answer missing for a claim, or a
// verified/refuted one without its source and quote, counts as unverifiable (fail closed).
function openClaims() {
  const last = {}
  for (const r of record.rounds) for (const v of r.verdicts) if (v) last[v.dimension] = v
  const claims = new Map()
  for (const v of Object.values(last)) {
    for (const raw of v.unverified ?? []) {
      const claim = String(raw).trim()
      if (!claim) continue
      const key = claimKey(claim)
      if (claims.has(key)) claims.get(key).dimensions.push(v.dimension)
      else claims.set(key, { claim, dimensions: [v.dimension] })
    }
  }
  return [...claims.values()]
}

// The one normal form of a claim: deduplication and the id use it both, so the same claim respaced in a later
// round keeps its id (review round 2: the id hashed the raw spelling, and acceptUnverifiable then missed it).
const claimKey = (claim) => String(claim).trim().toLowerCase().replace(/\s+/g, ' ')

// A stable id for a claim, so the same refutation in the next round reads as "no progress" and the owner's
// acceptUnverifiable matches the claim they read.
function claimId(claim) {
  let h = 5381
  for (const ch of claimKey(claim)) h = ((h * 33) ^ ch.codePointAt(0)) >>> 0
  return `ver-${h.toString(16).padStart(8, '0').slice(0, 8)}`
}

async function verifyClaims(item, round, head, artifact) {
  const claims = openClaims()
  if (!claims.length) { record.verification.push({ round, head, items: [] }); return { ok: true, items: [] } }
  const answer = await as('verifier', [
    `Verify the claims the review panel could not check. Item ${item.itemId}, round ${round}, commit ${head}.`,
    `The test gate's artifact of this commit: ${artifact}.`,
    `Claims (JSON; answer each by its index):`,
    JSON.stringify(claims.map((c, index) => ({ index, claim: c.claim }))),
    `Answer with the verification JSON only.`,
  ].join('\n'), { schema: VERIFICATION, label: `verify r${round}` })
  if (!answer) return { ok: false, reason: 'verifier gave no answer' }
  const byIndex = new Map(answer.items.map((a) => [a.index, a]))
  const items = claims.map((c, index) => {
    const a = byIndex.get(index)
    const sourced = Boolean(a?.source && a?.quote)
    const verdict = a && (a.verdict === 'unverifiable' || sourced) ? a.verdict : 'unverifiable'
    const why = !a ? 'the verifier gave no answer for this claim'
      : verdict !== a.verdict ? `answered ${a.verdict} without a source and a quote` : a.why
    return { index, id: claimId(c.claim), claim: c.claim, dimensions: c.dimensions, verdict, source: a?.source ?? null, quote: a?.quote ?? null, why }
  })
  items.filter((i) => i.verdict === 'unverifiable' && ACCEPT_UNVERIFIABLE.has(i.id)).forEach((i) => { i.acceptedByOwner = true })
  record.verification.push({ round, head, items })
  return { ok: true, items }
}

const refutedFindings = (items) => items.filter((i) => i.verdict === 'refuted').map((i) => ({
  dimension: 'verification', id: i.id, ruleId: 'VERIFY', issue: `refuted: ${i.claim}`, raisedBy: i.dimensions,
  impact: i.why, fix: `the source says otherwise: ${i.source} — "${i.quote}"`,
}))
const unsettledReason = (items) => {
  const open = items.filter((i) => i.verdict === 'unverifiable' && !i.acceptedByOwner)
  return open.length
    ? `NEEDS_HUMAN — the verifier could not settle ${open.length} claim(s) of the panel (the owner accepts them by resuming with acceptUnverifiable: [ids]): ${open.map((i) => `${i.id} ${i.claim} (${i.why})`).join(' | ').slice(0, 900)}`
    : null
}

// ---------------------------------------------------------------- run

// Words the script cannot read are no run: refused before the preflight, so nothing is locked, moved or notified.
if (!params) return { outcome: 'NOT_STARTED', reasons: [`${WORDS.length} words: ${USAGE}`] }

enterPhase('Preflight')
const pre = await ops('preflight.sh', [], PREFLIGHT, 'preflight')
if (!pre) return { outcome: 'NOT_STARTED', reasons: ['preflight returned no result (is factory-ops loading? check AGENT_TYPE_OPTION)'] }
if (pre.ok !== true) {
  await notify('not-started', '-')
  // The preflight's own reasons as it gave them, one per check; failureOf only for an answer that is not its own.
  const reasons = Array.isArray(pre.reasons) && pre.reasons.length ? pre.reasons : [failureOf(pre) ?? 'preflight refused without a reason']
  return { outcome: 'NOT_STARTED', reasons }
}
runId = pre.runId
// Every comparison uses the commit the preflight recorded, never a ref the session could move.
if (!/^[0-9a-f]{40}$/.test(pre.baseSha ?? '')) return { outcome: 'NOT_STARTED', reasons: ['preflight returned no base commit'] }
base.ref = pre.baseSha
base.sha = pre.baseSha

// A reviewer that can edit files is not a reviewer: if the custom agent type did not apply, stop here.
const iso = await as('review-general',
  'Isolation check, no review, read no file: list the names of the tools available to you in this session, and copy the first 500 characters of your own system instructions exactly as written. Answer JSON only.',
  { schema: ISOLATION, label: 'isolation check', bare: true })
const toolsListed = Array.isArray(iso?.tools) && iso.tools.every((t) => typeof t === 'string')
const canEdit = toolsListed && iso.tools.some((t) => /^(Edit|Write|MultiEdit|NotebookEdit)$/.test(t))
const ownDefinition = typeof iso?.opening === 'string' && iso.opening.includes(REVIEW_GENERAL_OPENING)
if (!iso || !toolsListed || canEdit || !ownDefinition) {
  await ops('state.sh', ['unlock'], STATE_UNLOCKED, 'state')
  const why = !iso ? 'no answer'
    : !toolsListed ? 'the reviewer did not list its tools'
      : canEdit ? `the reviewer can edit files (tools: ${iso.tools.join(', ')}): the custom agent type did not apply, check AGENT_TYPE_OPTION in .claude/workflows/backlog-autopilot.js`
        : `the reviewer's instructions are not review-general's (they open: ${JSON.stringify((iso.opening ?? '').slice(0, 120))}): check AGENT_TYPE_OPTION, or REVIEW_GENERAL_OPENING against .claude/agents/review-general.md`
  return { outcome: 'NOT_STARTED', reasons: [`agent isolation check failed: ${why}`] }
}

let item
let next = null
let resumeId = null            // on resume, the item the owner's branch names (backlog #0-215)
let plannedModules = null      // the architect's prediction of the modules the change reaches
enterPhase('Pick')
if (!params.branch) {
  // The choice is code: next-item.sh reads the queue, the backlog and the locks on the base commit.
  const wanted = params.item ? String(params.item).replace(/^#/, '') : null
  if (params.acceptUnverifiable !== undefined) return notStarted(['acceptUnverifiable needs branch: the owner accepts claims of a draft PR they read'])
  if (wanted !== null && !/^0-\d+$/.test(wanted)) return notStarted([`the item must look like #0-25, got ${String(params.item).slice(0, 40)}`])
  next = await ops('next-item.sh', wanted ? [base.sha, wanted] : [base.sha], NEXT, 'next item')
  if (!next) return notStarted(['next-item returned no result'])
  if (next.ok !== true) {
    // next-item.sh's own reasons as it gave them, as the preflight's; failureOf only for an answer that is not its own.
    return notStarted(Array.isArray(next.reasons) && next.reasons.length ? next.reasons : [failureOf(next) ?? 'next-item refused without a reason'])
  }
  if (!next.item || next.eligible === false) {
    const skipped = (next.skipped ?? []).map((s) => `${s.item}: ${s.why}`).join('; ')
    return notStarted([`${next.reason ?? 'nothing can start'}${skipped ? ` (${skipped})` : ''}`], 'NOTHING_TO_DO')
  }
  if (!/^#0-\d+$/.test(next.item)) return notStarted([`next-item returned a malformed item: ${String(next.item).slice(0, 40)}`])
  if (!PREFIX.test(String(next.branchPrefix ?? ''))) return notStarted([`next-item returned no branch prefix for ${next.item}: ${String(next.branchPrefix).slice(0, 40)}`])
  record.source = next.source === 'queue' ? `queue row ${next.position}` : next.source === 'follow-up' ? `follow-up of #${next.followUpOf}` : next.source
  log(`next item ${next.item} (${record.source})`)
}
if (params.branch) {
  const accepted = params.acceptUnverifiable
  if (accepted !== undefined && (!Array.isArray(accepted) || !accepted.length || !accepted.every((id) => CLAIM_ID.test(String(id))))) {
    return notStarted([`acceptUnverifiable must be a list of claim ids from the draft PR (ver-<8 hex>), got ${JSON.stringify(accepted).slice(0, 80)}`])
  }
  // The switch to the owner's branch is code (backlog #0-215), as the start of an item is (#0-209): the picker's Bash is
  // read-only (readonly-bash.sh --picker). Fixed: the picker ran `git switch <branch>` itself, so its session held the
  // autopilot's git write rules (`git switch *` matches `-c` too), and no guard could tell the owner's branch from
  // another item's. A refusal changes nothing (the tree stays on main) and stops the item at `pick`, recorded and
  // notified, as a picker that failed; the item is the one the branch names.
  resumeId = (ITEM_BRANCH.exec(String(params.branch)) ?? [])[1]
  if (!resumeId) return notStarted([`branch must be an item's branch (<type>/0-<n>-<slug>), got ${String(params.branch).slice(0, 80)}`])
  if (params.item !== undefined && String(params.item).replace(/^#/, '') !== resumeId) {
    return notStarted([`item ${String(params.item).slice(0, 40)} is not the item of the branch ${params.branch} (#${resumeId})`])
  }
  const resumed = await ops('resume-item.sh', [base.sha, params.branch], RESUMED, 'resume')
  if (!resumed || resumed.ok !== true || resumed.branch !== params.branch || resumed.item !== resumeId) {
    const why = resumed?.error ?? (Array.isArray(resumed?.reasons) && resumed.reasons.length ? resumed.reasons.join('; ') : null)
    return stopItem({ itemId: `#${resumeId}`, id: resumeId }, `could not resume #${resumeId} on ${params.branch}: ${String(why ?? 'no answer').slice(0, 300)}`)
  }
  item = await as('picker', [
    `Resume mode: the workflow switched to the existing branch ${params.branch} (resume-item.sh); do not switch or create a branch. Item #${resumeId}.`,
    `Validate the item exactly as in "Check the item" except the lock check (its own draft PR may be open), and answer the same JSON with that branch.`,
    `Base ref ${base.ref} (${base.sha}). Run ${runId}.`,
  ].join('\n'), { schema: PICK })
} else {
  item = await as('picker', [
    `Base ref ${base.ref} (${base.sha}). Run ${runId}. Take item ${next.item} (chosen by next-item.sh: ${record.source}).`,
    `Check it and name the slug of its branch: the branch is ${next.branchPrefix}/${next.item.replace(/^#/, '')}-<slug>, the prefix from its Type (next-item.sh); answer \`slug\`, not \`branch\`, and do not create the branch: the workflow starts the item (scripts/factory/start-item.sh).`,
  ].join('\n'), { schema: PICK })
}
if (!item) return stopItem(null, 'picker gave no answer')
// Fixed (backlog #0-206): a picker whose command was refused answered `none`, which ends the run as NOTHING_TO_DO
// with no state and no notification; refused after `git switch -c`, its branch stayed behind and next-item.sh's
// branch lock skipped the item from then on, without a word (run wf_da30d2f5-240, #0-197). A failure of the
// picker's own session is not an empty queue: it stops the item at `pick`, recorded and notified. Recorded as
// `blocked`, it counts toward consecutiveBlocked on purpose: repeated picker failures are the factory's own fault, and
// the breaker should stop the autopilot on them as on any other block.
if (item.failed) {
  const wantedId = (next?.item ?? resumeId ?? '').replace(/^#/, '')
  // On resume the branch is the owner's (params.branch). Outside resume the picker creates no branch since backlog #0-209
  // (start-item.sh does, below, and removes it on a refusal); a branch it names anyway is still said, as a defence.
  const left = !params.branch && item.branch && SAFE.test(item.branch) ? `; the branch ${item.branch} was left: next-item.sh skips the item while it exists` : ''
  const why = `picker failed: ${String(item.reason ?? 'no reason given').slice(0, 300)}${left}`
  return stopItem(/^0-\d+$/.test(wantedId) ? { itemId: `#${wantedId}`, id: wantedId } : null, why)
}
if (item.none) {
  await ops('state.sh', ['unlock'], STATE_UNLOCKED, 'state')
  await ops('return-to-main.sh', [], BACK_TO_MAIN, 'back to main')
  return { outcome: 'NOTHING_TO_DO', reason: item.reason }
}
// Fail closed on an incomplete answer; `id` is the bare number used in script arguments and paths.
item.id = String(item.itemId ?? '').replace(/^#/, '')
// A new item's branch is composed here (backlog #0-195): the prefix from next-item.sh (its **Type:** on the base
// commit), the item, the picker's slug. Fixed: the picker named the whole branch from picker.md's table, and four
// runs gave a `security` item `feat/` (one shipped as PR #587; one ended the run when the picker tried to rename the
// branch). A branch the picker names anyway is not used. On resume the branch is the owner's, as given.
if (!params.branch) {
  if (!SLUG.test(String(item.slug ?? ''))) {
    return stopItem(null, `picker gave no usable slug for ${String(item.itemId ?? next.item).slice(0, 20)} (lowercase words joined by hyphens), got ${JSON.stringify(item.slug ?? null).slice(0, 80)} (no state recorded, check the branches)`)
  }
  item.branch = /^0-\d+$/.test(item.id) ? `${next.branchPrefix}/${item.id}-${item.slug}` : undefined
}
if (!/^0-\d+$/.test(item.id) || !item.branch || !SAFE.test(item.branch) || !Array.isArray(item.acceptanceCriteria) || !item.acceptanceCriteria.length) {
  return stopItem(null, `picker answer incomplete or malformed (no state recorded, check the branches): ${JSON.stringify(item).slice(0, 300)}`)
}
if (next && item.itemId !== next.item) {
  return stopItem(null, `picker prepared ${item.itemId} instead of ${next.item} (no state recorded, check the branches)`)
}
// The run's own branch, recorded in the lock: the only branch guard-git-push.sh lets the shipper push (backlog
// #0-131). Bound to what the script already knows (review round 1): the item's own (`<type>/<item>-`), and on resume
// the branch the owner gave, which the picker repeats. Without it nothing could be pushed, not even a draft PR: stop.
if ((ITEM_BRANCH.exec(item.branch) ?? [])[1] !== item.id) {
  return stopItem(null, `picker named the branch ${item.branch} for ${item.itemId}: an item's branch is <type>/${item.id}-<slug> (no state recorded, check the branches)`)
}
if (params.branch && item.branch !== params.branch) {
  return stopItem(null, `picker answered the branch ${item.branch}, not ${params.branch} the run resumes (no state recorded, check the branches)`)
}
// The item starts in code (backlog #0-209): its branch from the base commit, the whole work template, its status field
// and one commit, by start-item.sh, which refuses with nothing left behind. Fixed: the picker did these steps with
// commands it composed, and each refusal cost a turn (run 20261106-203806 of #0-197 stopped on a `cp -r`, #0-207); one
// after `git switch -c` left the branch that locks the item (#0-206). A start that fails is the factory's own: stopped at
// `pick`, recorded and notified, as a picker that failed.
if (!params.branch) {
  const started = await ops('start-item.sh', [base.sha, item.id, item.branch, runId], STARTED, 'start item')
  // The work directory is the item's own, never what an answer names (review round 1): one that says another fails.
  const workDir = `.ai/work/${item.id}`
  if (!started || started.ok !== true || started.branch !== item.branch || started.workDir !== workDir) {
    const why = started?.error ?? (Array.isArray(started?.reasons) && started.reasons.length ? started.reasons.join('; ') : null)
    return stopItem({ itemId: item.itemId, id: item.id }, `could not start ${item.itemId} on ${item.branch}: ${String(why ?? 'no answer').slice(0, 300)}`)
  }
  item.workDir = workDir
}
const pinned = await ops('state.sh', ['branch', item.branch], STATE_BRANCH, 'state')
if (!pinned || pinned.branch !== item.branch) {
  const why = pinned?.error ?? (Array.isArray(pinned?.reasons) && pinned.reasons.length ? pinned.reasons.join('; ') : null)
  return stopItem(null, `could not record the run's branch ${item.branch} (no state recorded, check the branches): ${String(why ?? 'no answer').slice(0, 200)}`)
}
record.item = item.itemId
// Complexity: low → the lighter implementer (same definition, Sonnet); anything else, or missing → Opus.
// Read from the base commit by next-item.sh when it chose the item; the picker's copy only on resume.
const isLow = (v) => String(v ?? '').trim().toLowerCase() === 'low'
const IMPL_TYPE = (next ? isLow(next.complexity) && isLow(item.complexity) : isLow(item.complexity)) ? 'implementer-light' : 'implementer'
record.implementer = IMPL_TYPE

if (!params.branch) {
  enterPhase('Plan')
  const plan = await as('architect', [
    `Plan item ${item.itemId} ("${item.title}") on branch ${item.branch}. Work dir ${item.workDir}. Risk ${item.risk}, complexity ${item.complexity}.`,
    `Acceptance criteria:\n${(item.acceptanceCriteria ?? []).join('\n')}`,
  ].join('\n'), { schema: PLAN })
  if (!plan) return stopItem(item, 'architect gave no answer')
  if (plan.blocked) return stopItem(item, `architect: ${plan.reason}`)
  record.adrs = plan.adrs ?? []
  record.plannedRules = (plan.rules ?? []).map((r) => r.id).filter(Boolean)
  plannedModules = plan.modules ?? null

  enterPhase('Implement')
  const impl = await as(IMPL_TYPE, [
    `Mode: implement. Item ${item.itemId} ("${item.title}"), branch ${item.branch}, work dir ${item.workDir}.`,
    `Plan (also in progress.md): ${JSON.stringify(plan.plan)}`,
    `Rules the architect selected for this change (read each one; the core files ${CORE_RULE_FILES.join(', ')} are yours to read in full anyway): ${JSON.stringify(plan.rules ?? [])}`,
    `Acceptance criteria:\n${(item.acceptanceCriteria ?? []).join('\n')}`,
  ].join('\n'), { schema: IMPL })
  if (!impl) return stopItem(item, 'implementer gave no answer')
  if (impl.blocked) return stopItem(item, `implementer: ${impl.reason}`)

  // Safety net for a plan that missed an area: a rule file the diff calls for, from which the plan listed
  // no rule at all (and that is not core), is read in full and checked by the implementer before the
  // panel sees the change. Once, after implementing; later fix rounds are judged by the panel.
  const reach = await ops('changed-paths.sh', [base.ref], PATHS, 'rules for the diff')
  if (!reach || !Array.isArray(reach.ruleFiles)) {
    const why = failureOf(reach)
    return stopItem(item, `changed-paths returned no rule files (rules for the diff)${why ? `: ${String(why).slice(0, 300)}` : ''}`)
  }
  const covered = new Set([...CORE_RULE_FILES, ...ruleFilesOf(plan.rules)])
  const missing = (reach.ruleFiles ?? []).filter((f) => !covered.has(f))
  record.selfCheck = missing
  if (missing.length) {
    const check = await as(IMPL_TYPE, [
      `Mode: self-check. Item ${item.itemId}, branch ${item.branch}.`,
      `Your diff reaches areas from whose rule files the plan listed nothing. Read these rule files in full and check your change against every rule in them: ${missing.map((f) => `.ai/rules/review/${f}.md`).join(', ')}.`,
      `Fix what violates a rule (commit), and record the result in progress.md as your rules say.`,
    ].join('\n'), { schema: IMPL, label: `self-check ${missing.join(',')}` })
    if (!check) return stopItem(item, 'implementer gave no answer to the self-check')
    if (check.blocked) return stopItem(item, `implementer (self-check): ${check.reason}`)
  }
}

enterPhase('Review')
let previousSha = null
let lastHead = null           // HEAD the panel last reviewed
let previous = {}            // dimension -> blocking findings of the previous round
let lastIds = null
let mergeBase = null
let dimensions = null
let approved = false
let lastPaths = null          // the path gate's view of the last reviewed HEAD
let lastGate = null           // the test gate of the last reviewed HEAD (its artifact goes to acceptance)

for (let round = 1; round <= MAX_ROUNDS; round++) {
  // Path gate first: a plugin or build change on the branch must be flagged before `mvn verify` runs it.
  const pg = await pathGate(previousSha)
  if (!pg.ok) return stopItem(item, pg.reason)
  const gate = await testGate(item, round)
  if (!gate.ok) return stopItem(item, gate.reason)
  mergeBase = pg.paths.mergeBase
  lastPaths = pg.paths
  const head = pg.paths.head

  if (round === 1) {
    dimensions = [...PANEL_ALWAYS]
    if (pg.paths.migrationTouched) dimensions.push('migration')
    if (pg.paths.k8sOrBuildTouched) dimensions.push('k8s')
    if (params.localReview) {
      record.local = await ops('local-review.sh', [item.id, base.ref], LOCAL_REVIEW, 'local second opinion')
    }
  }

  lastHead = head
  lastGate = gate
  const verdicts = await reviewRound(item, round, dimensions, mergeBase, previousSha, previous, gate.artifact)
  if (verdicts.some((v) => !valid(v))) return stopItem(item, `a reviewer returned no valid verdict in round ${round} (fail closed)`)
  verdicts.forEach((v) => {
    record.nonBlocking.push(...(v.nonBlocking ?? []).map((f) => ({ dimension: v.dimension, ...f })))
    record.nonBlocking.push(...(v.outOfScope ?? []).map((s) => ({ dimension: v.dimension, outOfScope: s })))
  })

  const needsHuman = verdicts.filter((v) => v.verdict === 'NEEDS_HUMAN')
  if (needsHuman.length) return stopItem(item, `NEEDS_HUMAN from ${needsHuman.map((v) => v.dimension).join(', ')}`)
  const upheld = verdicts.filter((v) => v.upheldDisputes.length)
  if (upheld.length) return stopItem(item, `dispute upheld by ${upheld.map((v) => v.dimension).join(', ')}: the owner decides`)

  const failing = verdicts.filter((v) => v.verdict === 'CHANGES_REQUESTED' || v.blocking.length)
  const findings = failing.flatMap((v) => v.blocking.map((f) => ({ dimension: v.dimension, ...f })))
  let refuted = []
  if (failing.length === 0) {
    // The panel approved: its unverified claims are checked before the item goes on (backlog #0-160).
    const ver = await verifyClaims(item, round, head, gate.artifact)
    if (!ver.ok) return stopItem(item, ver.reason)
    refuted = refutedFindings(ver.items)
    if (!refuted.length) {
      const why = unsettledReason(ver.items)
      if (why) return stopItem(item, why)
      approved = true; break
    }
    // A refuted claim blocks like a blocking finding; the dimensions that raised it review the fix.
    findings.push(...refuted)
  }

  const ids = findings.map((f) => f.id).sort().join(',')
  if (ids === lastIds) return stopItem(item, `no progress: the same blocking findings (${ids}) came back after a fix round`)
  lastIds = ids
  if (round === MAX_ROUNDS) break

  const fix = await as(IMPL_TYPE, [
    `Mode: fix-review. Item ${item.itemId}, branch ${item.branch}, round ${round}.`,
    `Fix exactly these blocking findings, by id, nothing else (dispute in handoff.md if you disagree):`,
    JSON.stringify(findings),
  ].join('\n'), { schema: IMPL, label: `fix r${round}` })
  if (!fix) return stopItem(item, 'implementer gave no answer to the review findings')
  if (fix.blocked) return stopItem(item, `implementer: ${fix.reason}`)

  previousSha = head
  previous = Object.fromEntries(failing.map((v) => [v.dimension, [...v.blocking]]))
  // A refuted claim goes back to the dimensions that raised it, as their own finding to resolve (review round 1).
  for (const f of refuted) for (const d of f.raisedBy) (previous[d] ??= []).push(f)
  // Round 2+: the reviewers that blocked, plus security and general on every delta — a fix for one
  // dimension can break another, and a tenant leak in a fix must not ship as an outOfScope sentence.
  dimensions = [...new Set([...failing.map((v) => v.dimension), ...refuted.flatMap((f) => f.raisedBy), 'security', 'general'])]
}
if (!approved) return stopItem(item, `review did not converge in ${MAX_ROUNDS} rounds${lastIds?.includes('ver-') ? ' (a claim of the panel was refuted by the verifier)' : ''}`)

enterPhase('Acceptance')
let acc = await as('acceptance-reviewer', [
  `Autopilot acceptance. Item ${item.itemId} ("${item.title}"), branch ${item.branch}, mergeBase ${mergeBase}, base ref ${base.ref}.`,
  `Risk: ${item.risk}. The test gate's artifact of this HEAD: ${lastGate?.artifact}.`,
  `Answer with the acceptance JSON only.`,
].join('\n'), { schema: ACCEPT })
if (!acc) return stopItem(item, 'acceptance-reviewer gave no answer')

if (acc.verdict === 'REJECT') {
  const fix = await as(IMPL_TYPE, [
    `Mode: fix-acceptance. Item ${item.itemId}, branch ${item.branch}.`,
    `Unmet criteria: ${JSON.stringify(acc.criteria.filter((c) => !c.met))}`,
  ].join('\n'), { schema: IMPL, label: 'fix acceptance' })
  if (!fix || fix.blocked) return stopItem(item, fix?.reason ?? 'implementer gave no answer to the acceptance review')
  const pg = await pathGate(lastHead)
  if (!pg.ok) return stopItem(item, pg.reason)
  lastPaths = pg.paths
  const gate = await testGate(item, 'acc')
  if (!gate.ok) return stopItem(item, gate.reason)
  // The fix changed code after the panel approved: every reviewer of round 1 sees that delta once,
  // under round-3 rules (only correctness and security can still block).
  const round1 = record.rounds[0]?.verdicts?.map((v) => v.dimension) ?? PANEL_ALWAYS
  const delta = await reviewRound(item, 3, round1, mergeBase, lastHead, {}, gate.artifact)
  lastGate = gate
  if (delta.some((v) => !valid(v) || v.verdict !== 'APPROVE')) return stopItem(item, 'the acceptance fix did not pass a final review round')
  // No fix round is left: a refuted claim stops the item, an unsettled one waits for the owner.
  const ver = await verifyClaims(item, 'acc', gate.head, gate.artifact)
  if (!ver.ok) return stopItem(item, ver.reason)
  if (refutedFindings(ver.items).length) return stopItem(item, `the verifier refuted a claim of the final review round: ${refutedFindings(ver.items).map((f) => f.issue).join(' | ').slice(0, 900)}`)
  const unsettled = unsettledReason(ver.items)
  if (unsettled) return stopItem(item, unsettled)
  acc = await as('acceptance-reviewer', `Autopilot acceptance, second and last time. Item ${item.itemId}, branch ${item.branch}, mergeBase ${mergeBase}. The test gate's artifact of this HEAD: ${lastGate.artifact}. Answer with the acceptance JSON only.`, { schema: ACCEPT })
  if (!acc || acc.verdict === 'REJECT') return stopItem(item, 'acceptance rejected twice')
}
record.acceptance = acc

// Touches, plan and diff, compared: information for the PR and the audit, never a gate.
record.scope = scopeOf(next?.modules, plannedModules, lastPaths?.areas)

// Anything but an explicit "low" — in the backlog on main (next-item.sh) and in the picker's answer — is high.
const riskHigh = !isLow(item.risk) || (next !== null && !isLow(next.risk))
if (acc.verdict === 'NEEDS_HUMAN' && !riskHigh) return stopItem(item, `acceptance NEEDS_HUMAN: ${acc.reason}`)

enterPhase('Ship')
const merge = !SHADOW && !riskHigh && acc.verdict === 'ACCEPT'
const shipped = await as('shipper', [
  `Mode: ship. Item ${item.itemId} ("${item.title}"), branch ${item.branch}, run ${runId}.`,
  `shadow: ${SHADOW}. risk-high: ${riskHigh}. merge: ${merge}.`,
  `Review record (JSON, put it in the PR as the ship-record skill says): ${JSON.stringify(record)}`,
].join('\n'), { schema: SHIP })
if (!shipped || !shipped.prUrl) return stopItem(item, `shipper failed: ${shipped?.error ?? 'no answer'}`)
if (shipped.error) {
  // The PR exists; do not run blocked mode on a published PR. Record it and leave the decision to the owner.
  await ops('state.sh', ['record', 'blocked', item.id, prArg(shipped.prUrl), stage], STATE_RECORDED, 'state')
  await notify('ship-error', String(shipped.prNumber ?? item.id))
  return { outcome: 'SHIPPED_WITH_ERROR', item: item.itemId, pr: shipped.prUrl, error: shipped.error, agentCalls: calls }
}

await ops('state.sh', ['record', 'shipped', item.id, prArg(shipped.prUrl)], STATE_RECORDED, 'state')
await notify(SHADOW || riskHigh ? 'pr-ready' : 'pr-auto-merge', String(shipped.prNumber ?? item.id))
// Follow-ups wait for the owner's /ready; tell the owner they exist.
const followUps = (shipped.followUpsCreated ?? []).map((f) => String(f).replace(/^#/, '')).filter((f) => /^0-\d+$/.test(f))
for (const f of followUps) await notify('follow-up-proposed', f)

return {
  outcome: 'SHIPPED', item: item.itemId, pr: shipped.prUrl, mode: SHADOW ? 'shadow' : riskHigh ? 'risk-high' : 'auto-merge',
  rounds: record.rounds.length, agentCalls: calls, nonBlocking: record.nonBlocking.length,
  picked: record.source, followUps: followUps.map((f) => `#${f}`), scope: record.scope,
}
