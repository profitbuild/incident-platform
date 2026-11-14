# #0-58 `GlobalExceptionHandler` and `UnauthorizedEntryPoint` have no tests of their own in `shared`

Append-only. One line per step: `- [<stage> r<round>] <result>` — never rewrite an earlier line. The
autopilot reads the last `NEXT:` line to resume an interrupted run.

- [picker] picked; branch `<prefix>/<item-id>-<slug>`; base `<sha>`
- [architect] plan: <one line>; ADR: <none | NNNN (Proposed)>
- [implementer r0] commits <sha>..<sha>; <n> files; tests: <classes>
- [tests r0] PASS | FAIL (exit <code>, log `.ai/runs/<item>/tests-r0.log`)
- [review r1] general APPROVE · architecture APPROVE · security CHANGES_REQUESTED (sec-7f3a) · …
- [implementer r1] fixed sec-7f3a in <sha>
- [acceptance] ACCEPT | REJECT (AC2 missing evidence) | NEEDS_HUMAN (<reason>)
NEXT: <stage>
- [start] started by start-item.sh; branch `refactor/0-58-shared-exception-handler-tests`; base `9b824cf551713b8af8a8c24b9b018185ec77312b`
NEXT: architect
- [architect] plan: two test-only classes in shared, GlobalExceptionHandlerTest (exception pkg: handler called directly with real Spring exceptions, real BeanPropertyBindingResult and a real jakarta Validator for violations, MDC set/cleared) and UnauthorizedEntryPointTest (security pkg: MockHttpServletRequest/Response, ObjectMapper with JavaTimeModule, as ApiKeyAuthFilterTest/TenantStatusFilterTest); no production or POM change; ADR: none; modules: shared; rules: GEN-01, GEN-02, GEN-03, GEN-07, GEN-08, GEN-20, GEN-22, GEN-24, SEC-30, SEC-31, SEC-50
NEXT: implementer
- [implementer r0] commits d46dcc3e (tests) + work files; 2 files; tests: GlobalExceptionHandlerTest (12), UnauthorizedEntryPointTest (6), all pass; JaCoCo GlobalExceptionHandler 90/90, UnauthorizedEntryPoint 19/19 lines; verify's two Docker-backed tests could not pull their images here
- [implementer rules] GEN-01: every handler's status, body status, errorCode and message asserted exactly; BusinessException uses 409 (GlobalExceptionHandlerTest#businessException)
- [implementer rules] GEN-02: #noResourceFoundRethrown, #requestIdUnknown, #validationErrors (null rejected value), UnauthorizedEntryPointTest#blankHeaderFallsBackToMdc, #requestIdUnknown
- [implementer rules] GEN-03: exact values (tuple containsExactly, isEqualTo on message/requestId/status), no bare isNotNull as the outcome
- [implementer rules] GEN-07: @AfterEach MDC.clear() in both classes; containsExactlyInAnyOrder for the violation Set; explicit constraint messages (no locale dependence); timestamp never compared
- [implementer rules] GEN-08: no existing test changed; no apiKey/privateKey fixture or assertion
- [implementer rules] GEN-20: class Javadoc of both tests cites backlog #0-58 and ADR-0018
- [implementer rules] GEN-22: GlobalExceptionHandlerTest in shared/exception, UnauthorizedEntryPointTest in shared/security
- [implementer rules] GEN-24: diff is the two test files and .ai/work/0-58 only
- [implementer rules] SEC-30: redaction fixtures are "fake-password-value", "fake-secret-value", "fake-token-value", "fake-key-value"
- [implementer rules] SEC-31: GlobalExceptionHandlerTest#authentication/#accessDenied/#optimisticLocking/#unexpected and UnauthorizedEntryPointTest#bodyHoldsNoExceptionText assert the distinct exception text is absent
- [implementer rules] SEC-50: not applicable: no POM change
- [implementer r1] fix-tests: no code change; gate's 3 errors (AuditOutboxTest, PausedTenantsTest, DeadLetterPublisherKafkaIntegrationTest) are ContainerFetchException, image pull refused by the network (connection refused to the registry CDN); none touched by this diff; this item's 18 tests passed in the gate run; blocked on the environment
