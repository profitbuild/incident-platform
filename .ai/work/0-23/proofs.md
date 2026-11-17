# Proofs: 0-23

| Criterion | Evidence | Kind |
|---|---|---|
| AC1 | `OncallClientResilienceTest#noRetryInstanceConfigured`, `#*ServerErrorMakesOneRequest` | test |
| AC2 | `OncallClientResilienceTest#noRetryInstanceConfigured`, `SlackWorkspaceClientResilienceTest#serverErrorGoesThroughFallback` | test |
| AC3 | `OncallClientResilienceTest#getCurrentOncallServerErrorMakesOneRequest`, `#findBySlackUserIdServerErrorMakesOneRequest`, `#findCurrentByUserIdServerErrorMakesOneRequest`, `#clientIsProxied` | test |
| AC4 | `SlackWorkspaceClientResilienceTest#serverErrorGoesThroughFallback` (no max-attempts, `verify(1, ...)`) | test |
| AC5 | Javadoc of both clients, application.yml comments, README Resilience row, ADR-0016 | docs review |
| AC6 | `./mvnw -q verify -pl notification-service -am` | build |

Test run: `./mvnw -q verify -pl notification-service -am` — PASS; output not stored under `.ai/runs/0-23/`.
