# #0-23 The `oncall` and `slack-workspace` `@Retry` never fires

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
- [start] started by start-item.sh; branch `refactor/0-23-remove-dead-oncall-slack-retry`; base `37b90840a4b887e78cb5a0a651ef17a526fb049f`
NEXT: architect
- [architect] plan: drop `@Retry` from OncallClientImpl (3) and SlackWorkspaceClientImpl and their `resilience4j.retry.instances` (oncall, slack-workspace) from application.yml, breakers and fallbacks untouched (IncidentAckClient / escalation OncallServiceClient shape); new OncallClientResilienceTest (AOP + CB + Retry auto-config, WireMock, application.yml loaded via ApplicationYml, breaker reset per test) proves one request per 503 per lookup, today's outcome and +1 fallback metric; SlackWorkspaceClientResilienceTest drops its TestPropertySource pins, loads application.yml, resets the breaker, verifies one request; comments of both clients and application.yml (incl. the `slack` breaker's "question of backlog #0-23"), README Resilience row and ADR-0016 lines 49-50 and 64 say the scheduler's PENDING window is the lookups' retry; ADR: none; modules: notification-service, root; rules: GEN-01, GEN-08, GEN-20, GEN-24, ARC-02, ARC-05, ARC-28, SEC-15, PERF-40, DOC-10, DOC-11
NEXT: implementer
- [implementer r0] removed both @Retry and their retry instances; OncallClientResilienceTest new, SlackWorkspaceClientResilienceTest on shipped application.yml; docs reworded; `./mvnw -q verify -pl notification-service -am` passed
- [implementer rules] GEN-01: OncallClientResilienceTest verify(1, ...) x3, SlackWorkspaceClientResilienceTest#serverErrorGoesThroughFallback
- [implementer rules] GEN-08: pins removed per AC4, assertions kept and strengthened (handoff.md)
- [implementer rules] GEN-07: breaker reset in @BeforeEach, counter increments asserted
- [implementer rules] GEN-20, DOC-10, DOC-11: Javadoc of both clients, application.yml comments, README row, ADR-0016
- [implementer rules] GEN-24: not applicable: SlackApiClientResilienceTest and ingestion-service untouched
- [implementer rules] ARC-02: ApplicationYml reused, only a nested Initializer added
- [implementer rules] ARC-05, ARC-28, SEC-15, PERF-40: fallbacks and timeouts unchanged; scheduler PENDING window stated as the retry
