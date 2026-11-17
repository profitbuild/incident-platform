# Handoff: 0-23

Facts only. No reasoning about why the change is good: reviewers judge it themselves. Updated by the
implementer after every round.

## Changed
- notification-service `OncallClientImpl`: the three `@Retry(name = "oncall")` and the import removed; `@CircuitBreaker`s, fallbacks and metric calls untouched; class Javadoc section "Changed (backlog #0-23)".
- notification-service `SlackWorkspaceClientImpl`: `@Retry(name = "slack-workspace")` and the import removed; class Javadoc says circuit breaker with no retry.
- notification-service `application.yml`: `resilience4j.retry.instances.oncall` and `.slack-workspace` deleted with their comments; a note says the scheduler's PENDING window is the retry; the `slack` breaker comment reworded.
- test support `ApplicationYml.Initializer` (new nested `ApplicationContextInitializer`, calls `addLast`).
- new `OncallClientResilienceTest` (5 tests); `SlackWorkspaceClientResilienceTest` loads the shipped `application.yml`.
- README "Resilience" row and ADR-0016 (retry paragraph and the "#0-23 problem" parenthesis) reworded as settled facts.

## How to verify
- `./mvnw -q test -pl notification-service -am -Dtest=OncallClientResilienceTest` and `-Dtest=SlackWorkspaceClientResilienceTest`: one request per 503, fallback counter +1, no retry instance.
- `./mvnw -q verify -pl notification-service -am`: ran, passed.

## Tests changed and why
- `SlackWorkspaceClientResilienceTest`: the `@TestPropertySource` (max-attempts=1 and two breaker pins) was removed because AC4 requires the service's own configuration. No assertion dropped; `verify(1, ...)` added to `serverErrorGoesThroughFallback`; the breaker is reset in `@BeforeEach`.

## Deliberately out of scope
- `SlackApiClientResilienceTest`'s own initializer and ingestion-service's #0-23 comment: left as they are.

## Noticed, not touched
- none

## Follow-up needed

## Disputed
