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
