# Proofs: <item id>

Each acceptance criterion and the evidence that shows it (`.ai/rules/acceptance.md`). No pasted logs and
no secrets: the full output is in `.ai/runs/<item>/` (gitignored), named here.

| Criterion | Evidence | Kind |
|---|---|---|
| AC1 | `<Class>#<method>` asserts <outcome> | test |
| AC2 | `.github/scripts/check-<x>.sh` fails without the change (its test case: `<name>`) | CI check |

Test run: `./mvnw verify -pl <modules>` — PASS, <n> tests, log `.ai/runs/<item>/tests-r<round>.log`.
