# Handoff: 0-58

Facts only. No reasoning about why the change is good: reviewers judge it themselves. Updated by the
implementer after every round.

## Changed
- `shared/src/test/java/com/incidentplatform/shared/exception/GlobalExceptionHandlerTest.java`: new, 12 tests.
  Each `@ExceptionHandler` method is called on `new GlobalExceptionHandler()` with a real exception
  (`BeanPropertyBindingResult` + `MethodArgumentNotValidException`, a real Hibernate `Validator` for
  `ConstraintViolationException`, a `MethodParameter` of a real private method). `@AfterEach MDC.clear()`.
- `shared/src/test/java/com/incidentplatform/shared/security/UnauthorizedEntryPointTest.java`: new, 6 tests.
  `MockHttpServletRequest`/`MockHttpServletResponse`, body read back with
  `new ObjectMapper().registerModule(new JavaTimeModule())`. `@AfterEach MDC.clear()`.
- No production code, POM, CI or configuration change.

## How to verify
- `./mvnw -q test -pl shared -am -Dtest=GlobalExceptionHandlerTest,UnauthorizedEntryPointTest`: run here,
  12 + 6 tests, 0 failures (surefire reports in `shared/target/surefire-reports/`).
- `./mvnw -q verify -pl shared -am`: run here; every test passed except `AuditOutboxTest` and
  `DeadLetterPublisherKafkaIntegrationTest`, which errored with `ContainerFetchException`: the sandbox could
  not pull `postgres:16-alpine` / `apache/kafka:3.9.2` (`connection refused` to the registry). Neither test
  is touched by this change. The failure stopped the build before `jacoco:report`/`jacoco:check`, so the
  report was rendered from that run's `jacoco.exec` with `./mvnw -q jacoco:report -pl shared`:
  - `GlobalExceptionHandler`: 90 of 90 lines (100%), 9 of 10 branches (the one missed: `fieldName == null`
    in `isSensitiveField`).
  - `UnauthorizedEntryPoint`: 19 of 19 lines (100%), 6 of 6 branches.
  - `jacoco:check` and diff-cover were not run here (the first stops at the Docker-backed tests in this
    sandbox; diff-cover runs in CI). The diff changes no production line.

## Tests changed and why
- None: no existing test changed.

## Deliberately out of scope
- `apiKey` / `privateKey` not being redacted by `GlobalExceptionHandler.isSensitiveField` (the set holds
  camelCase names, the field name is lower-cased): backlog #0-245. No field with either name is in the
  fixtures, and neither direction is asserted.

## Noticed, not touched
- The plan named the 3-argument `NoResourceFoundException(HttpMethod, String, String)` constructor; the
  Spring version on this branch (Boot 3.5.16) has only `NoResourceFoundException(HttpMethod, String)`, which
  the test uses.

## Follow-up needed

## Disputed
