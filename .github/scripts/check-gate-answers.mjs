// ============================================================
// The test gate's answers against `factory`'s own check of them (backlog #0-280).
//
//   node .github/scripts/check-gate-answers.mjs <factory checkout> <answer.json>...
//
// scripts/factory/run-tests.sh prints one JSON object; `factory`'s dispatcher refuses any answer its
// `checkGateAnswer` (dispatcher/src/adapter.mjs, against schemas/gate.schema.json) refuses, so a field added to the
// script here, renamed or dropped on one path, would stop every task's gate once the flow reads it (#0-301).
// test-run-tests.sh hands this every answer its cases made, the real output of each path, and Lint Workflows the
// checkout of `factory` at the adapter's `factoryVersion` that #0-278's step made, whose tag is provision.sh's
// FACTORY_COMMIT: the code the build VM runs, never `factory@main`.
//
// It runs that code of `factory`, as #0-278's step runs `checkAdapter` (ADR-0061, amended for #0-278 and #0-280: one
// clone, one validator, the owner's choice A(a); a tag is the admin's alone and cannot move, and the job's token is
// read-only). So there is no second validator here, and no subset of JSON Schema to drift from the dispatcher's.
//
// Before any answer, a canary: an answer with a field no contract holds must be refused, or what was imported is not a
// checker of the contract (a stub, a schema that takes anything), and nothing it passed means anything. That canary is
// written here, so it could be refused for a reason of its own (a field `factory` came to require); after the answers,
// the first one the checker took, given one field more, must be refused too, or the contract takes fields it does not
// name and an answer with a new field would pass here and in the dispatcher alike (review round 1 of #0-280). A refusal is
// the module's own AdapterError; any other error is a check that did not happen.
// Exit 0: every answer keeps the contract; 1: one does not; 2: usage; 3: the contract could not be checked (no such
// checkout, no checkGateAnswer or AdapterError exported, the canary taken, an answer unreadable or not JSON).
// Node's built-in modules only (ADR-0043).
// ============================================================
import { readFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const [checkout, ...answerPaths] = process.argv.slice(2)
if (checkout === undefined || answerPaths.length === 0) {
  console.error('usage: check-gate-answers.mjs <factory checkout> <answer.json>...')
  process.exit(2)
}

// The shape of a stop, from run-tests.sh, plus one field no gate contract holds.
const CANARY = { status: 'stop', exitCode: -1, modules: '', log: '', head: '', artifact: null, summary: ['canary'],
  notAGateField: true }

class NotChecked extends Error {}

async function checker(dir) {
  const module = join(resolve(dir), 'dispatcher', 'src', 'adapter.mjs')
  let exports
  try {
    exports = await import(pathToFileURL(module).href)
  } catch (error) {
    throw new NotChecked(`cannot load factory's dispatcher/src/adapter.mjs from ${dir} (${error.code ?? error.name})`)
  }
  const { checkGateAnswer, AdapterError } = exports
  if (typeof checkGateAnswer !== 'function' || typeof AdapterError !== 'function') {
    throw new NotChecked('factory\'s adapter.mjs exports no checkGateAnswer and AdapterError')
  }
  try {
    checkGateAnswer(structuredClone(CANARY))
  } catch (error) {
    if (error instanceof AdapterError) return { checkGateAnswer, AdapterError }
    throw new NotChecked(`factory's checkGateAnswer failed on the canary with ${error.name}, not a refusal`)
  }
  throw new NotChecked('factory\'s checkGateAnswer took an answer with a field no contract holds: it checks nothing')
}

function readAnswer(path) {
  let text
  try {
    text = readFileSync(path, 'utf8')
  } catch (error) {
    throw new NotChecked(`cannot read the answer ${path} (${error.code ?? error.name})`)
  }
  try {
    return JSON.parse(text)
  } catch {
    throw new NotChecked(`the answer ${path} is not JSON`)
  }
}

let refused = 0
try {
  const { checkGateAnswer, AdapterError } = await checker(checkout)
  let taken = null
  for (const path of answerPaths) {
    const answer = readAnswer(path)
    try {
      checkGateAnswer(answer)
      taken ??= answer
    } catch (error) {
      if (!(error instanceof AdapterError)) throw new NotChecked(`factory's checkGateAnswer failed on ${path} with ${error.name}`)
      // factory's refusal names where the answer breaks the schema, never a value (SEC-31); the answer is ours.
      console.log(`::error::the test gate's answer ${path} breaks factory's contract: ${error.message} `
        + `(${JSON.stringify(answer).slice(0, 300)})`)
      refused += 1
    }
  }
  if (taken !== null) {
    try {
      checkGateAnswer({ ...structuredClone(taken), notAGateField: true })
    } catch (error) {
      if (!(error instanceof AdapterError)) throw new NotChecked(`factory's checkGateAnswer failed on a taken answer with one field more, with ${error.name}`)
      taken = null
    }
    if (taken !== null) throw new NotChecked('factory\'s checkGateAnswer took an answer it took before with one field more: the contract does not close its fields')
  }
} catch (error) {
  // Any failure but a refusal is a check that did not happen: exit 3, never 1, which a test reads as "refused".
  const why = error instanceof NotChecked ? error.message : `${error.name} while checking`
  console.log(`::error::the gate contract could not be checked: ${why} (backlog #0-280)`)
  process.exit(3)
}
if (refused > 0) {
  console.log(`${refused} of ${answerPaths.length} answer(s) break the gate contract (backlog #0-280)`)
  process.exit(1)
}
console.log(`all ${answerPaths.length} answer(s) keep factory's gate contract`)
