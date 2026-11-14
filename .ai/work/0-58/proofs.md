# Proofs: 0-58

Each acceptance criterion and the evidence that shows it (`.ai/rules/acceptance.md`). No pasted logs and
no secrets: the full output is in `.ai/runs/<item>/` (gitignored), named here.

| Criterion | Evidence | Kind |
|---|---|---|
| AC1 | `GlobalExceptionHandlerTest#resourceNotFound` asserts 404, body status 404, `RESOURCE_NOT_FOUND`, message equal to the exception's | test |
| AC2 | `GlobalExceptionHandlerTest#businessException` asserts a `BusinessException` with 409 / `SCHEDULE_OVERLAP` gives 409, body status 409, that code and its message | test |
| AC3 | `GlobalExceptionHandlerTest#validationErrors` asserts 400 `VALIDATION_FAILED` and exactly 7 entries in order: `password`, `userPassword`, `clientSecret`, `refreshToken`, `api_key` → `[REDACTED]`; `email` keeps `not-an-email`; `title` null stays null; messages kept | test |
| AC4 | `GlobalExceptionHandlerTest#constraintViolation` asserts 400 `VALIDATION_FAILED`, `name`/`count` with their messages in any order, rejectedValue null although the bean held `"   "` and `0` (real Hibernate Validator) | test |
| AC5 | `GlobalExceptionHandlerTest#typeMismatch` asserts 400 `INVALID_PARAMETER_TYPE`, message `Parameter 'incidentId' has invalid type`, without the rejected value | test |
| AC6 | `GlobalExceptionHandlerTest#authentication` (401 `UNAUTHORIZED`, fixed message, body without the exception text) and `#accessDenied` (403 `FORBIDDEN`, fixed message, body without the exception text) | test |
| AC7 | `GlobalExceptionHandlerTest#optimisticLocking` asserts 409 `OPTIMISTIC_LOCK_CONFLICT`, fixed message, no exception text | test |
| AC8 | `GlobalExceptionHandlerTest#unexpected` (500 `INTERNAL_SERVER_ERROR`, fixed message, body without the SQL text) and `#noResourceFoundRethrown` (`isSameAs(ex)`) | test |
| AC9 | `GlobalExceptionHandlerTest#requestIdFromMdc` (all 9 handlers' bodies carry `req-123`, the 500 message names it) and `#requestIdUnknown` (all 9 carry `unknown`); `@AfterEach clearMdc` | test |
| AC10 | `UnauthorizedEntryPointTest#writesJson401` asserts 401, `UTF-8`, `application/json`, and the read-back `ErrorResponse` status 401 / `UNAUTHORIZED` | test |
| AC11 | `UnauthorizedEntryPointTest#requestIdFromHeader`, `#requestIdFromMdc`, `#requestIdUnknown`, `#blankHeaderFallsBackToMdc` | test |
| AC12 | `UnauthorizedEntryPointTest#bodyHoldsNoExceptionText` asserts the response body does not contain the exception's text | test |
| AC13 | JaCoCo report of `shared` (from the `verify` run's `jacoco.exec`): `GlobalExceptionHandler` 90/90 lines, `UnauthorizedEntryPoint` 19/19 lines; no production line changed, no CI or POM change. `jacoco:check` and diff-cover: the autopilot's gate and CI (not run here, see handoff) | command |

Test run: `./mvnw -q test -pl shared -am -Dtest=GlobalExceptionHandlerTest,UnauthorizedEntryPointTest` — PASS,
18 tests. `./mvnw -q verify -pl shared -am` — every test passed but the two Docker-backed ones, which could not
pull their images in this sandbox. Notes in `.ai/runs/0-58/implementer-r0.log`; the gate's own log is the
authority.
