# Incident Platform

[![CI](https://github.com/profitbuild/incident-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/profitbuild/incident-platform/actions/workflows/ci.yml)
[![Java](https://img.shields.io/badge/Java-21-ED8B00?logo=openjdk&logoColor=white)](https://openjdk.org/projects/jdk/21/)
[![Spring Boot](https://img.shields.io/badge/Spring_Boot-3.5-6DB33F?logo=springboot&logoColor=white)](https://spring.io/projects/spring-boot)
[![Kafka](https://img.shields.io/badge/Apache_Kafka-KRaft-231F20?logo=apachekafka&logoColor=white)](https://kafka.apache.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Kustomize-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![License](https://img.shields.io/badge/license-MIT-2563eb)](LICENSE)

A production-oriented microservices backend that automates the full lifecycle of production incidents — from alert ingestion through escalation to AI-generated postmortems. Built to demonstrate real-world engineering: event-driven architecture, multi-tenancy, observability, and Kubernetes-ready deployment.

(BONUS) Frontend companion: [incident-platform-frontend](https://github.com/lukaszplawiak/incident-platform-frontend) — Angular 21 SPA with real-time WebSocket dashboard.

[Overview](#overview) | [Architecture](#architecture) | [Design Decisions](#design-decisions) | [Tech Stack](#tech-stack) | [Resilience & Security](#resilience--security) | [Infrastructure Hardening](#infrastructure-hardening) | [Observability](#observability) | [CI/CD](#cicd) | [Running Locally](#running-locally) | [Running on Kubernetes](#running-on-kubernetes) | [End-to-End Test](#end-to-end-test) | [Running Tests](#running-tests) | [Project Structure](#project-structure)

---

## Overview

When a monitoring system detects a problem — high CPU, a security breach, a failed service — the platform ingests the alert, normalizes it from multiple sources, and deduplicates it to prevent noise. It then creates an actionable incident, tracks its full lifecycle from detection to resolution, and automatically notifies the on-call engineer via Slack DM and email (SMS is added on escalation). If no one responds in time, the incident escalates automatically through a configurable chain. Every state change is recorded in a centralized audit log, and resolved incidents trigger an AI-generated postmortem draft.

**The goal**: reduce the time between "something broke" and "someone is fixing it."

The system is built for **multiple tenants** — each organization's data is fully isolated at every layer: HTTP, Kafka, and database.

### What the platform covers

- **Alert ingestion** from Prometheus, Wazuh, and generic sources with normalization and 5-layer deduplication
- **Incident lifecycle** managed by a finite state machine: `OPEN → ACKNOWLEDGED → RESOLVED → CLOSED` (escalation is tracked separately as an `escalationLevel` attribute, not as a lifecycle state — an incident can be escalated while `ACKNOWLEDGED`)
- **Automatic escalation** through a severity-calibrated chain: PRIMARY → SECONDARY → MANAGER
- **Multi-channel notifications** via Slack Bot Token (direct messages), email (Mailtrap SMTP), and SMS
- **AI-generated postmortems** via Gemini API triggered automatically on incident resolution
- **Centralized audit log** — every event across all services assembled into a single chronological timeline per incident
- **Real-time updates** via WebSocket (STOMP) for live incident dashboards
- **Full observability** — Prometheus metrics, Grafana dashboards, structured JSON logs with MDC context collected in Loki

---

## Architecture

The platform follows a **microservices architecture** with event-driven communication via Apache Kafka. Each service has a single responsibility and communicates asynchronously.

```
Prometheus / Wazuh / Generic
           │
           ▼
  ┌─────────────────────┐
  │   ingestion-service  │  port 8081
  │                     │  Normalizes alerts, deduplicates via Redis
  │                     │  Rate limiting per tenant + per IP
  │                     │  Consumes incidents.lifecycle (dedup lifecycle)
  └──────────┬──────────┘
             │ Kafka: alerts.raw / alerts.resolved
             ▼
  ┌─────────────────────┐
  │   incident-service   │  port 8082
  │                     │  FSM-based lifecycle, PostgreSQL, CQRS
  │                     │  Transactional outbox → incidents.lifecycle
  │                     │  WebSocket real-time updates
  │                     │  Centralized audit log consumer
  └──────────┬──────────┘
             │ Kafka: incidents.lifecycle
             ├─────────────────────────────────┐
             ▼                                 ▼
  ┌────────────────────┐           ┌──────────────────────┐
  │ escalation-service │           │  notification-service  │
  │   port 8084        │           │      port 8083         │
  │                    │           │                        │
  │ 2-level chain:     │           │  Slack Bot Token (DM)  │
  │ PRIMARY→SECONDARY  │           │  Email (Mailtrap SMTP) │
  │ →MANAGER           │           │  SMS (simulated)       │
  │ Timeouts per       │           │  Strategy Pattern      │
  │ severity           │           │  OncallClient →        │
  └────────────────────┘           └──────────┬─────────────┘
                                              │ HTTP (service JWT)
                                              ▼
                                   ┌──────────────────────┐
                                   │    oncall-service     │  port 8086
                                   │                      │  On-call schedule mgmt
                                   │  PRIMARY / SECONDARY │  Who is on-call now?
                                   │  / MANAGER roles     │
                                   └──────────────────────┘
             │ Kafka: incidents.lifecycle (IncidentResolvedEvent)
             ▼
  ┌─────────────────────┐
  │  postmortem-service  │  port 8085
  │                     │  Gemini API integration
  │                     │  Auto-generated postmortem drafts
  └─────────────────────┘

  All services → Kafka: audit.events → incident-service audit consumer → audit_events table
  (each service: action's transaction → own audit outbox table → relay → Kafka)

  ┌─────────────────────┐
  │    auth-service      │  port 8087
  │                     │  Authentication, MFA (TOTP), JWT refresh
  │                     │  Users, Teams, Roles, TenantSettings
  │                     │  API Keys + Integration-based alert routing
  └─────────────────────┘
  (consumed by all services for JWT verification via shared library)
```

### Services

| Service | Port | Responsibility |
|---|---|---|
| auth-service | 8087 | Authentication, users, teams, API keys, MFA, integrations, tenant provisioning |
| ingestion-service | 8081 | Alert normalization, deduplication, rate limiting |
| incident-service | 8082 | Incident lifecycle FSM, WebSocket, audit log |
| notification-service | 8083 | Multi-channel notifications, on-call routing |
| escalation-service | 8084 | Severity-based auto-escalation chain |
| postmortem-service | 8085 | AI-generated postmortem drafts via Gemini |
| oncall-service | 8086 | On-call schedule management |

### Kafka Topics

| Topic | Producer | Consumers |
|---|---|---|
| `alerts.raw` | ingestion-service | incident-service |
| `alerts.resolved` | ingestion-service | incident-service |
| `incidents.lifecycle` | incident-service (via transactional outbox); escalation-service (`IncidentEscalatedEvent` on automatic escalation) | notification-service, escalation-service, postmortem-service, ingestion-service, incident-service (reads `IncidentEscalatedEvent` back to update `escalationLevel`) |
| `audit.events` | all services | incident-service (audit consumer) |
| `alerts.dead-letter` | ingestion-service | — |
| `incidents.dead-letter` | incident-service | — |
| `escalation.dead-letter` | escalation-service | — |
| `notification.dead-letter` | notification-service | — |
| `postmortem.dead-letter` | postmortem-service | — |

---

## Design Decisions

**Why a custom FSM instead of Spring State Machine?**
Spring State Machine adds significant complexity and weight. A simple `Map<IncidentStatus, Set<IncidentStatus>>` of allowed transitions is transparent, easily testable, and sufficient for this use case. The FSM is covered by 25 parameterized test cases for all allowed and forbidden transitions.

**Why CQRS without separate databases?**
Full CQRS with read replicas is overkill here. The lightweight split between `IncidentCommandService` and `IncidentQueryService` within the same PostgreSQL instance demonstrates understanding of the pattern without unnecessary infrastructure complexity.

**Why `@Scheduled` for escalation instead of Kafka Streams?**
Kafka Streams would require windowing, state stores, and a significantly more complex setup. `@Scheduled` with a PostgreSQL-backed `EscalationTask` table is transparent, testable with Mockito, and sufficient. ShedLock prevents duplicate execution when the service scales to multiple replicas.

**Why no Gemini SDK?**
Using the raw HTTP API via `RestClient` through a `GeminiClient` interface keeps the integration vendor-neutral — switching to a different AI provider requires changing exactly one class. It also makes the HTTP contract explicit and debuggable without additional Maven dependencies.

**Why HS512 for JWT instead of RS256 or Keycloak?**
HS512 with a shared secret is sufficient for a controlled environment where all services are owned by the same team. Service tokens are minted and cached per tenant and per target service by `ServiceTokenProvider` (a concrete class, not an interface) and verified in `JwtAuthFilter`; moving to RS256 or Keycloak means changing token issuance in `JwtUtils`/`ServiceTokenProvider` and verification in `JwtAuthFilter`, both in `shared`. The tradeoff is documented and understood: every service holds the same secret, so any service can mint a token for any tenant and audience (backlog #0-13 records the asymmetric-key / mTLS alternative).

**Why Slack Bot Token instead of Incoming Webhook?**
Incoming Webhooks can only post to a single channel. Bot Token (`xoxb-`) with `chat.postMessage` sends direct messages to the on-call engineer's Slack User ID, and — only if the tenant turns on broadcast for its workspace — also a post to that tenant's own default channel. Each tenant connects its own workspace: an admin pastes the bot token into `POST /api/v1/slack-workspace` (auth-service stores it encrypted; there is no "Add to Slack" OAuth flow yet), and notification-service reads it per notification over a service-token call to auth-service (backlog #0-21/#0-30). A tenant with no workspace simply gets no Slack channel. **No ACK from Slack for now** (backlog #0-35): Slack signs a button click with the signing secret of the App that posted the message, and with a pasted token that App is the tenant's own, while `SlackSignatureVerifier` checks one platform-wide `SLACK_SIGNING_SECRET`. Messages therefore carry no Acknowledge button; incidents are acknowledged in the app. The callback endpoint (`/api/v1/slack/actions` → `IncidentAckClient`) is kept for the OAuth "Add to Slack" install, where every workspace uses the platform's App and the platform secret is correct.

**Why a centralized audit log via Kafka instead of per-service history tables?**
Per-service history tables scatter the timeline across databases and require multi-service HTTP calls to reconstruct a full incident view. The `audit.events` topic acts as a single audit stream — any service publishes events and the consumer assembles them into a unified chronological view via one API endpoint. A producer does not send to Kafka from inside its database transaction: it writes the event to its own outbox table in that transaction, and a relay sends it afterwards, at least once; the consumer drops a resend by the event's id (backlog #0-84, every service that records audit events).

**Why per-record TenantContext in Kafka listeners instead of the consumer interceptor?**
`TenantKafkaConsumerInterceptor.onConsume()` receives an entire batch — setting TenantContext from the first record would contaminate subsequent records from different tenants. Resolving the tenant per record in each `@KafkaListener` (`TenantKafkaRecordResolver`: the payload's valid tenant, which the `X-Tenant-Id` header must match) guarantees correctness regardless of batch composition. The interceptor is kept as a validation layer only.

**Why Consumer-Driven Contracts for notification-service?**
The notification consumer deserializes Kafka messages to `JsonNode` and extracts only the fields it needs. This decouples the consumer from the exact producer schema — a producer adding new fields to `IncidentOpenedEvent` won't break notification-service.

**How does a consumer treat a record it cannot process?**
Every consumer listens in `MANUAL_IMMEDIATE` mode and decides each record's fate itself, through `DeadLetterPublisher` (`shared`, backlog #0-96). A record that fails the same way every time (a poison pill) is copied to the service's dead-letter topic and acknowledged only once Kafka has the copy; if Kafka does not take it, the record is `nack`ed and read again. A transient failure (`KafkaFailures`: the database unreachable, timed out or a lost version race, in any of the types Spring gives it) is `nack`ed and read again after 5 s; the records after it on the partition wait, so order is kept and consumer lag shows the stall. Leaving a record unacknowledged is never a retry: the next record's acknowledgement commits the offset past it (shown on a real broker by `DeadLetterPublisherKafkaIntegrationTest`), which is how the consumers used to lose records on a transient failure. Anything else is a poison pill (backlog #47). A dead-letter reason and its log line carry a message only when the platform wrote it content-free (a refused tenant, an unknown severity, unparseable JSON); any other exception is named by its type and the platform's line that threw it (`KafkaFailures.reason`), never its message, which may quote the record. Every wait is bounded: a copy waits at most 5 s in all (its own producer blocks at most 2 s for metadata), each consumer refuses to start unless a poll of such waits fits in half of `max.poll.interval.ms` (120 s; 300 s in notification-service), a record still failing after `kafka.consumer.redelivery-deadline` (30 min) is dead-lettered instead of holding its partition, and a copy's original payload is cut to 128 KiB so it always fits in a record. `ingestion-service` has an HTTP request, not a record: it starts a request's copies together, waits for them under one 5 s deadline and answers 503 with `Retry-After` if Kafka does not take them, so the sender retries; the dedup keys of alerts a lost copy was to keep are released first. Moving the consumers onto Spring Kafka's `DefaultErrorHandler` with a dead-letter recoverer, and replaying dead letters, is backlog #0-97.

**Why bucket4j backed by Redis instead of in-memory rate limiting?**
This reverses an earlier in-memory design. In-memory buckets were per-pod (each replica kept independent counters, so the effective limit multiplied with the replica count) and were held in unbounded maps keyed by tenant and IP — a memory-exhaustion vector, since the client IP comes from the caller-controlled `X-Forwarded-For` header. `RateLimitingService` now keeps bucket state in Redis through bucket4j's `ProxyManager` (`bucket4j-redis`): state is shared across replicas and expires automatically. The Redis call is protected by `@CircuitBreaker` (backlog #67) and fails open, matching the dedup layer's policy for the same dependency. auth-service has the two limiters that fail closed: the platform API's (`PlatformRateLimiter`, backlog #0-83) and the admin MFA reset's (`MfaResetRateLimiter`, backlog #0-88). Both guard rare, privileged security actions, so while Redis cannot be checked, tenant provisioning and admin MFA resets answer 503 — those writes depend on Redis, logins and every other auth-service API do not.

**Why auth-service is a modular monolith rather than split into auth + identity?**
All identity concerns (users, teams, API keys, integrations) are colocated with authentication to avoid distributed transaction complexity and HTTP latency on the login hot path. `AuthService.login()` reads `User` credentials in the same database transaction — after splitting this would require a Redis credential cache (Wzorzec B) and Outbox Pattern for invite flow. This is documented as a future backlog item in `AuthServiceApplication.java` with the exact migration plan.

**Why API Key authentication uses SHA-256 instead of Argon2?**
API keys have ~143 bits of entropy (24 bytes SecureRandom → base64). Brute-forcing a leaked SHA-256 hash requires 2^143 attempts — computationally infeasible regardless of hash speed. Argon2's memory-hard cost (100ms+) would add latency to every API request that uses key authentication. SHA-256 is the industry standard for high-entropy API key hashing (GitHub, Stripe, Twilio).

**Why Integration-based routing instead of label matching for alert → team routing?**
Label-based routing (RoutingRules matching on alert labels) requires DevOps teams to configure labels in Prometheus/Wazuh per alert. Integration-based routing (PagerDuty model) delegates routing responsibility to the platform: admin creates an Integration named "Prometheus Payment API" → assigns it to "backend-team" → gets an API key. Alertmanager uses that key — the source of the alert IS the routing decision. No per-alert label configuration needed.

**Why a separate oncall-service instead of extending notification-service?**
On-call schedule management is a distinct bounded context. A separate service allows independent scaling, independent deployment, and future extension (PagerDuty integration, calendar sync) without touching the notification pipeline.

**Why tenants are created by a platform operator through an API, not by a seed or configuration?**
A multi-tenant platform onboards customers while it runs. A Flyway seed gave every database the same admin with a known password (backlog #0-80), and a configuration entry per tenant would need a deployment change and a restart for each customer. Instead an admin of the reserved `platform-operator` tenant calls `POST /api/v1/platform/tenants`: the tenant row, its first admin (no password) and the invite email are written in one transaction, and the admin sets their own password by accepting the invite. It is the platform's one cross-tenant capability, kept narrow on purpose: create, reissue the first invite while the tenant has no admin, show and list metadata, suspend and resume a tenant (backlog #0-82), and, as the single exception inside a tenant that has an admin, the delayed, announced MFA recovery of its only admin (backlog #0-90); JWT only, no API keys, a recent MFA login with an established factor (backlog #0-83); audited in both tenants. It reverses backlog #0-16's "no cross-tenant create tenant endpoint" for customer tenants only; the operator tenant still bootstraps itself. Guide: [docs/tenant-provisioning.md](docs/tenant-provisioning.md).

---

## Tech Stack

| Category | Technology | Why |
|---|---|---|
| Language | Java 21 | Virtual threads, records, pattern matching |
| Framework | Spring Boot 3.5 | Production-grade auto-configuration, actuator |
| Messaging | Apache Kafka (KRaft) | Durable, ordered, replayable event stream |
| Database | PostgreSQL 16 + Flyway | ACID, versioned schema migrations |
| Cache / Dedup | Redis 8 (AOF) | Sub-millisecond SETNX dedup, AOF for durability |
| Security | Spring Security + JWT (HS512) | Stateless auth, service-to-service tokens |
| Real-time | WebSocket (STOMP) | Live incident dashboard updates |
| Email | Spring Mail + Mailtrap SMTP | Real SMTP integration, safe sandbox |
| Slack | Bot Token + chat.postMessage | DM + channel posts, per tenant; ACK-via-Slack returns with the OAuth install (backlog #0-35) |
| AI | Gemini API via RestClient | Vendor-neutral, no SDK lock-in |
| Resilience | Resilience4j | Circuit breakers on Redis (ingestion-service fail-open, auth-service's platform API and admin MFA reset limits fail-closed), Gemini, inter-service HTTP clients (oncall-service, incident ACK) and the Slack Web API (backlog #0-104, alert `SlackCircuitOpen`), retry with backoff (the oncall client's own retry is unverified, backlog #0-23; the Slack Web API calls' since backlog #0-103) |
| Rate Limiting | bucket4j + Redis | ingestion-service per tenant + per IP; auth-service's platform API per operator and in total (backlog #0-83), and the admin MFA reset per admin and per tenant (backlog #0-88); state shared across replicas via `bucket4j-redis` |
| API Docs | SpringDoc OpenAPI 3 | Auto-generated, available at `/swagger-ui.html` |
| Build | Maven multi-module | Shared dependency management, incremental builds |
| Observability | Micrometer + Prometheus + Grafana | HTTP metrics, JVM, Kafka lag, rate limit rejections |
| Logging | SLF4J + MDC, Spring Boot structured logging, Alloy + Loki | One JSON (ECS) object per line, `tenantId`, `requestId`, `userId`, `kafkaMessageId` as fields; collected in Loki for 15 days in docker-compose (backlog #0-94) |
| Containers | Docker Compose + Kubernetes (Kustomize) | Local infra + production-ready k8s overlays |
| CI / Security | GitHub Actions · Renovate · OWASP Dependency-Check · Snyk | Build, test, coverage, automated dependency updates, CVE scanning |
---

## Resilience & Security

### Alert Deduplication — 5 Independent Layers

No single layer failure results in duplicate incidents. Each layer independently catches what the others miss.

| Layer | Mechanism | Protects against |
|---|---|---|
| 1 | Redis SETNX, 5-minute TTL | Burst of duplicate alerts |
| 2 | Redis EXPIRE 7 days on `IncidentOpenedEvent` | Alert flood during active incident |
| 3 | Redis DEL on `IncidentResolvedEvent` | Stale dedup block after resolution |
| 4 | Redis AOF persistence | Dedup state loss on Redis restart |
| 5 | `incident-service` fingerprint check in PostgreSQL | Redis unavailability, race conditions |

### Escalation Chain

When an incident is not acknowledged, escalation follows a structured chain with timeouts calibrated to severity:

```
T+0:    Incident OPEN  → IncidentOpenedEvent                      → Email + Slack
T+5m*:  No ACK         → Level 1 (SECONDARY) IncidentEscalatedEvent → Email + Slack + SMS
T+10m*: Still no ACK   → Level 2 (MANAGER)   IncidentEscalatedEvent → Email + Slack + SMS
        (* CRITICAL — HIGH=15m, MEDIUM=30m, LOW=60m per level)
```

The channel set is chosen by **event type**, not by escalation level (`NotificationRouter`): `INCIDENT_OPENED` → Email + Slack, `INCIDENT_ESCALATED` → Email + Slack + SMS, `INCIDENT_ACKNOWLEDGED` → Slack, `INCIDENT_RESOLVED` → Email + Slack, `INCIDENT_CLOSED` → Email.

escalation-service resolves the SECONDARY (level 1) or MANAGER (level 2) on-call user through oncall-service and puts that user in `IncidentEscalatedEvent.escalateTo`. notification-service stores `escalateTo` and the escalation level on its outbox entry, and each escalation level is now queued and sent at most once per channel (idempotency is keyed on incident + tenant + event type + escalation level, so the level-2 notification is no longer discarded as a duplicate of level 1). `escalationLevel` is required and must be an integer in 1..2; anything else is routed to `notification.dead-letter` rather than queued. A malformed `escalateTo` is ignored with a warning, not dead-lettered. When an entry is sent, `NotificationRouter` notifies the `escalateTo` user: it looks up that user's current on-call entry in oncall-service (`GET /api/v1/oncall/current/by-user/{userId}`, tenant and user id matched together) and uses their email, Slack id and phone. If there is no target, or the target is not on call, the escalation goes to the tenant's PRIMARY on-call as before. Other event types notify the PRIMARY on-call, resolved with the incident's `teamId` when it has one (falling back to tenant-wide otherwise, backlog #0-12) — the same team-scoped lookup the escalation fallback uses. **Tenant content only reaches members of that tenant** (the on-call contact details are entered by the tenant and are not verified against membership yet, backlog #0-24): there is no fallback address. A channel the on-call user has no address for is skipped (a WARN and `notification.channel_skipped{channel,event_type}`; a Slack id must start with `U`, anything else is no Slack address), and if nobody in the tenant can be notified the queue entry becomes `UNDELIVERABLE`; it is counted in `notification.undeliverable{event_type,reason}`, audited for the tenant as `NOTIFICATION_UNDELIVERABLE` (a type of its own, distinct from `NOTIFICATION_FAILED`, a failed send), and for opened and escalated incidents the platform operator gets a content-free email (tenant id, incident id, event type, reason) at `NOTIFICATION_OPERATOR_ALERT_EMAIL`. That address has no default: if it is unset no email is sent and only the ERROR log and the metric remain, so set it for every environment (the Kubernetes ConfigMap `app-config` carries an empty `NOTIFICATION_OPERATOR_ALERT_EMAIL`; each overlay patches it — dev mirrors docker-compose's Mailpit address, staging/prod carry a placeholder to replace before a real deployment, backlog #0-26). Alerts are limited to one email per tenant and reason per `NOTIFICATION_OPERATOR_ALERT_MIN_INTERVAL` (default `PT15M`). If oncall-service cannot answer, the entry stays `PENDING` and is retried until the lookup has been failing for `NOTIFICATION_LOOKUP_RETRY_WINDOW` (default `PT10M`, measured from the first failed lookup and not from creation) before it becomes `UNDELIVERABLE`; a run of the scheduler loads at most `NOTIFICATION_SCHEDULER_BATCH_SIZE` entries (default `200`, oldest first) and stops after `NOTIFICATION_SCHEDULER_PROCESSING_BUDGET` (default `PT3M`; it must stay below the 4-minute lock, which is checked at startup). escalation-service's run stops after `ESCALATION_SCHEDULER_PROCESSING_BUDGET` (default `PT4M`, below its 5-minute lock) and postmortem-service's after `POSTMORTEM_GENERATING_PROCESSING_BUDGET` / `POSTMORTEM_RETRY_PROCESSING_BUDGET` (`PT3M` / `PT8M`, below 4 and 9 minutes), both checked at startup; the three services sync their paused tenants every `TENANT_PAUSE_SYNC_INTERVAL_MS` (default `10000`, backlog #0-82). SMTP calls have 5-second timeouts (`MAIL_SMTP_*_TIMEOUT_MS`). Slack is per tenant (backlog #0-21): each tenant's own workspace, bot token, default channel and broadcast flag (off by default) come from auth-service, cached for 60 s. A tenant without a workspace has Slack skipped like any other missing address. If auth-service cannot answer, only Slack is skipped and the other channels go out (counted in `service_client_fallback_total{client="slack-workspace"}`); when Slack was the only reachable channel the entry stays `PENDING` within the same retry window and then becomes `UNDELIVERABLE` with reason `SLACK_WORKSPACE_UNAVAILABLE`. A failed send is recorded by its reason, the platform's words (`NotificationFailureReason`: a rejected address, an unreachable mail server, a Slack code such as `not_in_channel`), never the mail server's or Slack's own text, and counted in `notification.channel.failed{channel,reason}` (a refused Slack broadcast under `channel="SLACK_BROADCAST"`, since it no longer stops the on-call DM) (backlog #0-93); Slack's `"ok": false`, which it answers with HTTP 200, is a failure (until #0-93 it was recorded as sent). A failed channel send is not retried later (backlog #0-32).

Each escalation level creates an independent `EscalationTask` in PostgreSQL. ACK at any point cancels all pending tasks. ShedLock prevents duplicate job execution across multiple replicas. The escalation level is written back to the incident by incident-service, which consumes `IncidentEscalatedEvent` from `incidents.lifecycle`.

### Multi-Layer DDoS Protection

| Layer | Mechanism | Status |
|---|---|---|
| 1 | Cloudflare | TODO — when public domain |
| 2 | Nginx Ingress per-IP rate limiting (20 req/s, 10 connections) | ✅ Implemented |
| 3 | bucket4j per-tenant + per-IP (application layer) | ✅ Implemented |
| 4 | Kafka consumer severity prioritization | ✅ Implemented |
| 5 | Micrometer: `rate_limit.tenant.rejected`, `rate_limit.ip.rejected` | ✅ Implemented |

### Security

- **JWT secret**: No default value — application refuses to start without `JWT_SECRET` set explicitly
- **Service-to-service auth**: `ServiceTokenProvider.getToken(tenantId, audience)` generates and caches one JWT per tenant and target service with `ROLE_SERVICE`; `JwtAuthFilter` authenticates it as a `ServicePrincipal` only in the service named in its `aud` claim (auth-service accepts only `aud=auth-service`, on its two internal endpoints: a tenant's Slack workspace — backlog #0-30 — and a tenant's status, read by every other service — backlog #0-82) and takes the tenant only from the signed `tenantId` claim, never from `X-Tenant-Id` — not exposed to end users. Client fallbacks that fail open are counted in `service_client_fallback_total{client,target,reason}`; `reason="auth"` means a 401/403, i.e. a misconfiguration and not an outage
- **Alert source authentication** (backlog #0-16): external alert sources — a tenant's Alertmanager, Wazuh, and the platform's own Alertmanager (as the reserved `platform-operator` tenant) — send an Integration API key (`Authorization: ApiKey ipl_…` or `Bearer ipl_…`). ingestion-service sends only its SHA-256 to auth-service's introspection endpoint, with a tenant-less *purpose token* that auth-service accepts on that one route and nowhere else, and caches active keys for at most 60 s (the revocation window). A definite "no" is `401`; "can't check right now" is `503` + `Retry-After`, because Alertmanager retries 5xx but drops every 4xx. A valid key of a tenant suspended read-only also gets `503`, with `Retry-After: 300` and `TENANT_READ_ONLY` (its alerts are paused, not refused); a tenant suspended in full gets `403` + `TENANT_SUSPENDED`, which is not counted as a failed authentication (backlog #0-82). A key cached as active before a suspension is caught by the status filter within 10 s. ingestion-service accepts no service tokens. Tenant ids `platform-operator` and `system` are reserved
- **Dev endpoints**: `DevTokenController` (`GET /dev/token`, an unauthenticated token for any tenant and role) is gated with `@Profile({"local", "dev"})`, plus a startup guard that refuses to run outside those profiles. The guard cannot help if a deployment sets the dev profile itself, which the k8s base ConfigMap did for every overlay, prod included (backlog #0-63). Now only `k8s/overlays/dev` sets `SPRING_PROFILES_ACTIVE`, docker-compose sets none, and CI fails if the rendered staging or prod overlay sets any Spring profile
- **Management port isolation**: Prometheus metrics and health endpoints on separate ports (8091–8097) — never co-located with the business API
- **API key security**: Gemini API key passed via `x-goog-api-key` HTTP header — never embedded in URLs where it could appear in access logs
- **Sensitive field redaction**: `GlobalExceptionHandler` redacts `password`, `secret`, `token`, `apiKey` from validation error responses
- **Slack Bot Token**: Minimal OAuth scopes (`chat:write`, `im:write`) — principle of least privilege
- **Request size limits**: `ingestion-service` rejects payloads over 1MB — protection against DoS via oversized alerts

### Concurrency Safety

- **Optimistic locking**: `@Version` on `Incident` entity — concurrent PATCH requests return `HTTP 409 Conflict` instead of silently overwriting
- **Notification idempotency**: `notification-service` checks `notification_queue` (incident + tenant + event type + escalation level) before enqueueing and `notification_log` (same key + channel) before sending — Kafka at-least-once delivery never causes duplicate Slack messages or emails. One accepted exception (backlog #0-103): a Slack post retried after a timeout or a 5xx (`SlackApiClient`, 3 attempts, its own 3 s connect / 5 s read timeouts; the scheduler checks at startup that its processing budget leaves the lock room for a send's worst case, so raising `SLACK_RETRY_MAX_ATTEMPTS`, `SLACK_RETRY_WAIT_MS`, `SLACK_CONNECT_TIMEOUT` or `SLACK_READ_TIMEOUT` may need a lower `NOTIFICATION_SCHEDULER_PROCESSING_BUDGET`, or the service refuses to start) may show twice, as Slack takes no idempotency key — a duplicate beats a lost incident message. The Slack calls sit behind a circuit breaker (backlog #0-104): once Slack keeps timing out or answering 5xx, Slack messages fail at once (`SLACK_UNAVAILABLE`, `circuit_open`) instead of costing every entry about 51 s, and are not resent (#0-32); alert `SlackCircuitOpen` while it keeps refusing them
- **Audit event resilience**: every service that records audit events (auth-, incident-, notification-, escalation-, postmortem-service) writes them to a transactional outbox, sent by a relay with backoff (backlog #0-84) — a Kafka outage blocks no request and loses no event

### Multi-Tenant Kafka — Per-Record Isolation

All Kafka topics are multi-tenant. A record's tenant is the `tenantId` in its payload; its `X-Tenant-Id` header is a copy, written by one helper (`TenantRecords`) that every sender uses, so code that does not parse the payload (MDC, metrics, dead-letter tooling) can read it (backlog #0-91). `TenantKafkaProducerInterceptor`, registered in every service that produces, only checks that the header is there and valid. Each `@KafkaListener` resolves the tenant per record (`TenantKafkaRecordResolver`: the payload's valid tenant, which the header must be there to match, else the record is dead-lettered and counted, backlog #0-92) and clears `TenantContext` in a `finally` block — guaranteeing no tenant leaks between records in the same batch. Every tenant id is a slug (`TenantIds`), so none can carry anything into a log line, a header or a metric tag.

---

## Infrastructure Hardening

What protects the platform around its application code, area by area, with what is still missing at the end.
It is an inventory from the security audit of 2026-09-30: every item says where it lives, so it can be checked
against the code. Application-level controls are described in detail in [Resilience & Security](#resilience--security);
the summary below only places them.

### GitHub and CI

What protects the pipeline itself: the `GITHUB_TOKEN`, the secrets and `main`. Part of it lives in
the workflow files, part in repository settings. What guards `main` is kept as files and checked by CI
(#0-113); the other settings no diff shows, so they are listed here too (checked 2026-10-18; check them
with `gh api repos/{owner}/{repo}/...` after changing anything in Settings).

**In the workflow files**

- **Token scope declared per workflow** (backlog #0-59): every workflow starts from
  `permissions: contents: read`, and only the job that needs more widens its own token —
  `detect-changes` adds `pull-requests: read` (`dorny/paths-filter` lists a PR's files through the
  API), the two Snyk jobs add `security-events: write` (SARIF upload). Every scope not listed is `none`.
- **No write scope for PR code**: jobs that run a PR's own code (build, tests, Docker builds, smoke
  test) keep the read-only token. That is why the coverage report goes to the job summary rather than
  a PR comment, which would need `pull-requests: write` (backlog #0-57).
- **`pull_request`, never `pull_request_target`**: a PR from a fork runs with a read-only token and
  without the repository's secrets.
- **Secrets only in an environment only `main` may use** (backlog #0-154, ADR-0035): `SNYK_TOKEN` and
  `NVD_API_KEY` are secrets of the environment `scans`, whose deployment branch policy allows `main` alone and
  which admins may not bypass; the repository holds no secret. The scan workflows run on `main`, on a schedule
  or by hand, never on a PR, and a dispatch on another branch is refused before any step: without it, that
  branch's own scripts, action and build would run next to the secret (the machine account's token may
  dispatch). The environment is a file in `.github/repository-settings/environments/` with the ruleset, and
  Lint Workflows refuses a job that reads a secret outside an environment whose file names it.
- **Actions pinned by commit SHA** (backlog #0-60): every `uses:` names the full 40-character
  commit, with its tag in a comment (`actions/checkout@<sha> # v4.4.0`). A tag can be repointed by
  whoever controls the action's repository, as in the `tj-actions/changed-files` compromise
  (CVE-2025-30066), and the next run would execute that code with the job's token and secrets; a SHA
  cannot. Renovate's `helpers:pinGitHubActionDigests` preset updates the SHA and the comment together.
- **No token left in `.git/config`** (backlog #0-60): every `actions/checkout` sets
  `persist-credentials: false`. No job pushes, so no later step needs the token that checkout would
  otherwise leave behind for it to read.
- **Every CI tool pinned, bumped by Renovate, and checked against its publisher** (backlog #0-147, ADR-0033):
  the Snyk CLI, kubeconform, actionlint, shellcheck, zizmor and betterleaks are each a release tag and a SHA-256 in their
  job's `env`, under a `# renovate:` comment. One script installs them all (`install-pinned-tool.sh`: download,
  compare the SHA-256, then unpack into the runner's temp directory, no `sudo`). Renovate bumps tag and SHA-256
  together, but computes the SHA-256 from what it downloaded itself, so CI's `check-pinned-tools.sh` checks every
  pin on every run: GitHub's own digest of the release asset, then the strongest proof each publisher gives,
  named by the pin's `verify=`: a GitHub artifact attestation (actionlint, zizmor), the asset in an immutable
  release's attestation (betterleaks: nothing about how it was built, but neither tag nor asset replaceable since,
  ADR-0036), a `sha256sums.txt.asc` signed
  by Snyk's code-signing key (committed under `.github/keys/`; once the key expires only a pin already on main before
  the expiry, whose signature predates it, still passes, so the jobs that hold `SNYK_TOKEN` decide it on the full
  history, and a weekly watch, `signing-keys.yml`, opens an issue when Snyk publishes a new, revoked or extended
  key: #0-152), the release's
  `CHECKSUMS` (kubeconform: same host,
  catches a swapped file, not a malicious release), or GitHub's digest alone (shellcheck signs nothing). Until
  #0-147 every bump was by hand and no tool was tracked. Since #0-149 `check-downloads.rb` refuses a download
  that would bypass the pins: curl, wget, a release asset's URL or `gh release download` in any workflow's or
  composite action's `run:` block, unless the line says why it is not one (`# not-a-download: <why>`, today the
  smoke test's health probe). It catches the honest mistake, not a determined one (another program, a script the
  step calls), which the owner's review of `.github/` still has to see. The runtimes are pinned too: Java 21 and
  Python 3.13 by their setup actions, and since #0-166 Ruby (ADR-0040): the nine `.github/scripts/*.rb` checks (and
  `run-blocks.rb`, the library three of them load) run on the version in `.ruby-version`, set up by
  `.github/actions/setup-ruby` (`ruby/setup-ruby`, pinned by SHA; Renovate bumps both), no longer on the runner's own
  Ruby, whose json gem once made a check pass a repeated key that it failed locally (PR #517). Since #0-163 Node too (ADR-0043): the
  JavaScript tests of Factory guards run on `.node-version`, set up by `.github/actions/setup-node` (`actions/setup-node`,
  pinned by SHA), with Node's built-in modules only (no npm, no `package.json`). lint-workflows'
  `check-runtime-setup.rb` fails a step that runs Ruby or Node before its action in its job, and any other use of
  `ruby/setup-ruby` or `actions/setup-node`; `.ruby-version` and `.node-version` are on the build-config list (a PR
  changing one needs the owner). Pinned is the version, not the binary: `setup-ruby` and `setup-node` download a
  build and verify nothing here, so, as for Java and Python, its integrity rests on the action; locally
  `ci-local.sh` takes the same versions from the official `ruby` and `node` images.
- **Scan tools pinned and verified before they receive a secret** (backlog #0-61): the Snyk CLI is
  the standalone binary at the version pinned in `snyk.yml`, checked against the SHA-256 kept next to
  it. A different binary stops the job before `SNYK_TOKEN` exists in any process. The token reaches
  only the scan step, as the `SNYK_TOKEN` environment variable the CLI reads itself; there is no
  `snyk auth`, which put the token in the process arguments and in a config file every later step
  could read. This replaced `npm install -g snyk`: whatever version npm served at that moment, a Node
  wrapper whose unbundled `@sentry/node ^7` dependency was resolved at install time. Pinned and
  checked as every CI tool is (above): a bump is trusted once Snyk's signature over its checksums
  verifies. That check runs in CI's Lint Workflows on the pull request, and again in both `snyk.yml`
  jobs before the CLI is installed: Lint Workflows is a required check of `main` (backlog #0-113), but
  the owner can merge around it, so the check stays where the token is used.
  `diff-cover` is pinned by version only (backlog #0-134).
- **Manifest validation pinned, binary and schemas** (backlog #0-76): kubeconform is the release
  pinned in `ci.yml` (as every CI tool is, above), and it
  validates against the schemas of one Kubernetes version (`KUBERNETES_VERSION` in the job's `env`,
  also the version of the kubectl that renders; ADR-0027) taken from a pinned commit of `yannh/kubernetes-json-schema`, so the result changes only
  with a change in this repository. It used to be whatever `releases/latest` served, piped into
  `tar` unchecked, validating against the newest Kubernetes from that repository's moving `master`;
  a replaced binary also runs before the checks that read the same renders (the Spring profile of
  #0-63, the mail of #0-42) and could have made them pass. kubectl, which writes the renders,
  is pinned by version only: `azure/setup-kubectl` checks nothing it downloads (backlog #0-135).
- **Workflows and actions linted, the linters pinned** (backlog #0-146, ADR-0032): the "Lint Workflows" job
  runs actionlint on every workflow on each push and PR: expressions, `needs`, how a workflow calls a local
  action (a misspelt input or output would otherwise fail silently), untrusted input used inline in a script, and
  every workflow `run:` block through shellcheck. The same pinned shellcheck checks every tracked `.sh` file (the
  CI checks, the autopilot's gates, the agents' hooks) and the composite actions' steps, which actionlint does not
  read (backlog #0-149, `check-shell.rb`): every severity, notes included, since the check that matters most in a
  guard, a variable left unquoted (SC2086), is a note; with `--norc`, so no `.shellcheckrc` (shellcheck looks for
  one above every script, and none is a protected path) can turn a check off. A finding that is meant is disabled
  at its line, with its reason. zizmor audits the same files, the composite actions' `action.yml` included, for
  security (backlog #0-147): dangerous triggers, credentials left by checkout, template injection, excessive
  permissions, unpinned actions, cache poisoning; its default persona, offline, any finding fails the job. Offline,
  its five audits that need GitHub's API do not run, impostor commits among them (a pinned SHA that exists only in a
  fork of the action: a known gap, backlog #0-62), and every suppression names its reason (inline, or `.github/zizmor.yml` for an audit turned off). All three
  are pinned as every CI tool is (above); not actionlint's `download-actionlint.bash` from its main branch, and not
  the runner's own shellcheck, so the result changes only with a change here.
- **The Maven distribution pinned and verified** (backlog #0-142, ADR-0031): `./mvnw` checks the zip it
  downloads against `distributionSha256Sum` in `.mvn/wrapper/maven-wrapper.properties` and refuses a mismatch.
  Central publishes no SHA-256 for it, and Renovate writes the sum of whatever it downloaded when it bumps
  Maven, so CI checks the sum itself: `check-maven-wrapper-sum.sh` downloads the zip, checks it against the
  SHA-512 Apache publishes on another host (`downloads.apache.org`), and compares its SHA-256 with the property.
  It runs whenever build-and-test's wrapper cache misses, which a bump always does. mvnw does not check a
  distribution it has already unpacked, so CI no longer keeps that in the monthly Maven repository cache, which
  restores older entries by prefix. It has a cache of its own instead, restored by its exact key (the
  properties, the checker and the two cache actions), written only by a push to `main` that ran the check. The
  Snyk and OWASP jobs restore that cache too. Both caches are written in one place,
  `.github/actions/restore-maven-caches` and `save-maven-caches`, and `check-maven-caches.rb` refuses a cache of
  `~/.m2` anywhere else, the distribution with `restore-keys` or another path, and a key that stops hashing what
  decides the check (backlog #0-145). The root `./mvnw` is the only wrapper: the copies six modules carried from the first
  commit, unpinned but unpacking into the same directory, are gone. A developer's existing `~/.m2/wrapper` is
  not checked again: delete `~/.m2/wrapper/dists/apache-maven-*` once and the next `./mvnw` downloads and
  checks it.
- **Every commit scanned for secrets** (backlog #0-109, ADR-0036): the "Secret Scan" job, a required check, runs
  pinned betterleaks with its default rules on every commit a pull request adds and every commit a push brings to
  `main` (what each commit adds, merge commits included, so a secret added and deleted again within a pull
  request fails it too, in the commit that added it). Generic passwords and keys count, the form of this project's own secrets (the JWT secret, the AES keys,
  the database passwords), which push protection (below) does not recognise. Nothing in the repository changes
  the rules: `secret-scan.sh` refuses a `.gitleaks.toml`/`.betterleaks.toml` and an ignore file; a finding that
  is no secret is allowed on its line with `gitleaks:allow` and its reason, and every commit that adds or removes
  one gets a warning naming it. Findings are annotations without the value. It runs after the push, like push protection: a pushed branch is already public, so a finding is a
  secret to rotate; what it stops is that secret reaching `main` unseen (before the push: #0-156). The 1170
  commits on `main` were scanned once when it was added (fixtures, placeholders and the Alertmanager dev token
  untracked in ff2b4da; nothing to rotate).

**In repository settings**

- Workflow permissions default: **read** — a fallback only, since every workflow declares its own.
  GitHub Actions may not approve pull requests.
- Workflows from first-time contributors' fork PRs wait for approval before they run.
- Secret scanning with **push protection**: a push containing a known provider's token (Slack, Google, GitHub,
  AWS, ...) is rejected, unless the pusher bypasses it with a reason; non-provider patterns are off. It does not
  see a generic password or key: the Secret Scan job (above) does.
- **What guards `main` is files, not UI settings** (backlog #0-113, ADR-0034): the ruleset `main`, the
  repository settings and the list of admins in `.github/repository-settings/`, applied by the owner with
  `.github/scripts/repository-settings.rb apply`. The ruleset: a pull request (no direct push, for anyone),
  one approval of the last push (a code owner's, `.github/CODEOWNERS` read from `main`, when the PR touches an
  owned path; until phase 3 `CODEOWNERS` opens with `* @lukaszplawiak`, so every PR needs the owner's, and the
  bot's token, whose own approval would otherwise count, merges nothing) with stale approvals
  dismissed, every `ci.yml` job and Factory guards as required checks, each pinned to GitHub Actions (a commit
  status of the same name does not count), no force-push or deletion. Its one bypass: the admin role, at merge
  only, so the owner can merge their own PR without a review, or with a red check when CI fails for an outside
  reason; GitHub records each bypass. A session gives the owner that merge command only once the PR's checks are
  green, or names the red job and its outside reason (CLAUDE.md "Working style"): on the owner's PRs a required
  check holds only through that (an "Enforced by" in the review rules' `factory.md`, should one be added, would rest
  on it; backlog #0-115). Only the owner is an admin (`repository.json` lists them, the check compares), and
  interactive Claude Code sessions, which use the owner's login, may not use the bypass
  nor change the ruleset (`.claude/settings.json` denies `gh pr merge --admin`, merges through the API, `gh api`
  on the rulesets, `gh repo edit`, `gh pr review` and `repository-settings.rb plan`/`apply`: the owner runs them, the merge with
  `--match-head-commit` so a commit pushed after their reading cannot ride along, #0-131).
  `delete_branch_on_merge` on, `allow_auto_merge` off (phase 3, after #0-116). Lint Workflows compares GitHub
  with the files on every PR and push (`repository-settings.rb check`, main's files for a PR that does not
  change them), so a setting changed in the UI turns CI red, and refuses a required check that no job of a
  pull request's workflows reports or that two jobs could. Its limit: CI's token sees neither the bypass
  actors, nor the repository settings, nor the admins, so those are compared only when the owner runs the
  check (its summary names what it skipped).
- Actions must be pinned to a full-length commit SHA (`sha_pinning_required`, backlog #0-60): a
  workflow with a tag-pinned `uses:` fails to start, so a tag no longer depends on review alone. It
  was turned on once `main` had no tag-pinned `uses:` left and its run was green (2026-09-29);
  turning it on earlier would have stopped every run on `main` from starting.
- Security scanning and dependency updates: see [Security Scanning](#security-scanning) and
  [Dependency Updates — Renovate](#dependency-updates--renovate) in CI/CD.

### AI factory (unattended agents)

Controls around the autopilot that implements `BACKLOG.md` items without a human in the loop
([docs/ai-factory.md](docs/ai-factory.md), backlog #0-113). The premise: an agent's instructions are not a
security boundary, so every rule that matters is also enforced outside the model.

- **Human-owned paths**, one list: `.ai/rules/protected-paths.md` (backlog #0-122) — `.ai/rules/`, `.ai/plan/`
  (the approved order of work), `.ai/audit/decisions.md`, `.claude/`, `.github/`, `architecture-tests/`,
  `AGENTS.md`, the gates' own files (`scripts/factory/`, `scripts/factory-admin/`, `.devcontainer/`) and the
  build configuration (`.mvn/`, `mvnw`, `mvnw.cmd`); `CLAUDE.md` outside its `agent-editable` blocks. They are
  denied to autopilot sessions for the file tools (`.claude/settings.autopilot.json`), guarded heuristically
  for the shell (`.claude/hooks/guard-protected-bash.sh`), stop an item before review when committed
  (`scripts/factory/changed-paths.sh`, which reads the list from the base commit and refuses to run without
  it), and need the owner's review on a PR (`.github/CODEOWNERS`, effective once the protection rule
  requires it). Factory scripts run only while identical to `main` (`guard-factory-scripts.sh`). The shell
  guard's `git grep` and label checks, and the reviewers' `git grep` check in `readonly-bash.sh`, refuse the
  command when the check itself fails (backlog #0-130), and so do the guards' other checks since #0-132: they match
  with bash's own regex over the whole command (`finds` in `_lib.sh`), so a grep that fails or is missing, or a
  first line that alone matches an allow pattern, no longer lets a call through.
- **Factory guards** (`.github/workflows/factory-guards.yml`): a PR that deletes, renames away or disables
  tests, removes assertions, adds a Maven plugin, repository or dependency, changes what verification runs
  (`.mvn/`, `mvnw`, skip properties, the coverage check's threshold, rule, goal, phase or includes), edits or deletes an applied Flyway migration, or marks a backlog item
  ready fails unless its author is the owner (the one admin of `repository.json` at the PR's base, `owner-login.sh`,
  backlog #0-237; not `github.repository_owner`, which in an organisation is the organisation) or the owner approved
  its current commit (only the owner's approval counts, not any organisation member's; with no owner readable, nothing
  passes). The same workflow
  validates the execution queue against the backlog (`scripts/factory/check-queue.sh`) and fails when the
  deny rules, the shell-write hook or CODEOWNERS stop covering an entry of the protected-path list
  (`.github/scripts/check-protected-paths.sh`; it runs the hook against every entry rather than reading its
  regex), and, the other way (#0-168), when the deny rules or the hook protect a path the list lacks: a copy
  cannot claim a protection the code reading the list does not apply. The list also names the autopilot's
  runtime state (`.git/`, `.ai/runs/LOCK`, `.ai/runs/state.json`, `.ai/runs/ops-calls/`, `.ai/STOP`), so
  dropping its deny or hook entry fails too.
- **The next item is chosen by code** (`scripts/factory/next-item.sh`), from the files on the run's base
  commit: only `ready` items, dependencies done, no open PR or branch, in the order of the owner-approved
  queue. An item whose `**Touches:**` names a protected path (or a bare `ci`) never starts and cannot be
  queued, whatever its Risk: the autopilot could only stop it at the implementer (#0-42's run, draft PR
  #477; backlog #0-122). Follow-ups an agent proposes enter as `proposed` and run only after the owner's
  `/ready`.
- **Skipping verification is refused** in autopilot sessions (`guard-tests.sh`: `-DskipTests`, `--no-verify`,
  `-fn`, `exec:` goals, another `settings.xml`, …), the test gate tests the committed HEAD of a clean tree (its
  `--working-tree` mode, which the manual `/review` uses on uncommitted changes, is refused while an autopilot
  run holds the lock) with
  its own Maven settings (`scripts/factory/maven-settings.xml`, no `~/.mavenrc`, no `MAVEN_OPTS`: nothing an
  agent's code can write in the home directory decides what runs), the file tools of an autopilot session
  write only inside the repository (`guard-write-in-repo.sh`), and applied Flyway migrations cannot be edited through the file tools in any session (`guard-migrations.sh`),
  except on a `/seed-bugs` run's `review/<8 hex>` branch with no autopilot lock, where the guard compares with the run's
  base, so a migration the merged change added can be edited there, in any session (backlog #0-172, ADR-0047).
  Every hook fails closed (backlog #0-162), because Claude Code runs a call after any exit status but 2: a helper
  (`_lib.sh`) that does not load, a crash (an `EXIT` trap turns any status but 0 and 2 into 2) and a JSON parser
  that fails or empty input (`json_get`/`json_checked`) refuse the call. Two exceptions, both in
  `guard-migrations.sh` and named in rule `FAC-S04`: without `jq` and `python3`, and with a base ref that does not
  exist, it warns and lets the edit through so that the owner's sessions do not break (CI's edited-migration
  check still compares with the PR's base). A hook
  that cannot start at all (missing, not executable) or times out is caught by Claude Code itself: every hook entry,
  in both settings files and in the agents' frontmatter, says `"onFailure": "block"` (ADR-0039), and Factory guards
  (`check-hook-entries.rb`, also skills' and commands' frontmatter) fails an entry without it, one in the background
  (`async`, which the field does not cover), one that is not a command hook of `.claude/hooks/` with plain
  arguments, or one whose hook has no row in the fail-closed table, and a file that repeats a key. The field needs
  Claude Code 2.1.295 or newer (an older one ignores it silently, spike of 2026-10-25): the autopilot's preflight
  refuses an older one.
  Hook tests: `.claude/hooks/test-hooks.sh`, with every hook in a fail-closed table (a hook without a row fails Factory guards).
- **Least privilege per agent**: reviewers, the architect, the auditors and the autopilot's picker run read-only Bash allow-lists
  and write scopes (`.claude/hooks/readonly-bash.sh`, `write-scope.sh`), in two layers: the agent's frontmatter and
  a twin in both settings files keyed on its `agent_type` (`--agent`), since Claude Code does not promise frontmatter
  hooks to the agents a `Workflow` spawns; Factory guards keeps the twins equal to the frontmatter and checks that
  every session-wide guard is still wired (`check-hook-entries.rb`, backlog #0-164, ADR-0041), and fails an agent
  whose `tools:` hold Bash or a file tool with no guard of that kind in its frontmatter (rule 6, backlog #0-186);
  the autopilot's implementer, implementer-light and shipper are its named exceptions, bounded by the
  autopilot session's denies and session-wide guards instead (the two implementers also run `foreground-bash.sh`,
  which refuses a command in the background, backlog #0-206: a budget guard, not a scope). The workflow starts an
  item in code (`scripts/factory/start-item.sh`, backlog #0-209) and switches a resumed run to the owner's branch in
  code (`scripts/factory/resume-item.sh`, #0-215), so the picker writes nothing: it has no file-writing tool, the
  `mkdir -p .ai/work/*` and `cp .ai/work/_template/* .ai/work/*` allow rules are gone, and its Bash is
  `readonly-bash.sh --picker` (read-only git, one `gh pr list` form, `ls .ai/work/0-<n>`; no branch, switch, commit or push,
  though it reads PR titles an outsider can write). The architect commits in one form only, `-m "<subject>"` with the
  attribution trailer: `-F`/`--file` would let it put any file it can read into a commit message the shipper pushes
  (backlog #0-203). The `/seed-bugs`
  defect-seeder runs the reviewers' read-only Bash (no branch, no commit, no redirect) and edits only the files of the
  change it plants in (`write-scope.sh --seed`, from the run's record `.ai/runs/SEED`); a factory script commits its
  edit (backlog #0-172, ADR-0047). They read files with the Read tool and
  search with `git grep`, and each refusal of the hook that a reading agent can hit names that alternative,
  per mode (backlog #0-123). No agent runs `kubectl` or `kubeconform` (backlog #0-182): the k8s reviewer reads the
  manifests as files, and CI renders and validates them. Its render could read what git does not track (a root or a
  base above `k8s/`, a `!!binary` path, an upper-case `KUSTOMIZATION.YML` each printed `docker/.env`), run a program
  (`--helm-command`) and fetch remote bases, and a guard of its allowed forms missed one in each review round; the
  hook refuses an unknown mode, so a stale `--k8s` fails closed (ADR-0045). In Bash every agent's search is `git grep`
  only (the hook's modes add other commands, never another search), with an allow-list of options checked on the command as bash splits it (so no abbreviated or quoted
  `--untracked`, `--no-index`, `-f` or `-O`, no `$` expansion, no unquoted glob before `--`, no line
  continuation, which bash joins before running; the latter is refused in every autopilot command): tracked files
  only, so a gitignored secret is never read and no program is run. Also refused (backlog #0-130): a newline inside
  a quoted word, git run by a path, a glob, an assignment or a program on a fixed list (`env`, `sh -c`,
  `command`, ...), and a glob where the subcommand goes (`git gr?p`, which a file named `grep` turns into grep). An interpreter run by its path or off that list (`/bin/sh -c "git grep …"`) and a git alias are
  not seen by the check (#0-132): there the allow-list below is the control. The
  autopilot session is `dontAsk`
  with an explicit allow-list; `WebSearch` is denied, and `WebFetch` only the verifier agent may use (an agent that
  reads untrusted text must not be able to send data out; backlog #0-160, ADR-0037).
- **The owner's review trusts nothing of the branch it reviews** (backlog #0-165): `/review` and `/accept`
  pre-approve exact commands only, since `git diff`/`git show` take `--output` (writes any file) and
  `--ext-diff`/`--textconv` (run a program) and text in a diff could steer the session into one; the reviewers read
  `.ai/rules/review/` from main (`git show refs/remotes/origin/main:…`, the full name, which a local branch called
  `origin/main` cannot shadow), never from the branch, which must not set the rules it is judged by; and before
  reviewing a branch someone else wrote, the owner reads its changes to `.claude/`, `CLAUDE.md` and `.ai/context/`
  (Claude Code picks up changed skills and agents during a session).
- **The verifier**: what the reviewers could not check (their `unverified` claims) goes, after the panel
  approves, to a `verifier` agent that never sees the diff: it reads only the test gate's
  artifacts in `.ai/runs/` (not its logs, nor a file with a second hard link; `read-scope.sh`, in its definition and
  session-wide on its `agent_type`) and fetches only `https` URLs under six path prefixes (OSV, GitHub advisories, Maven
  Central, Tomcat's and Spring's security pages), with no query string — `.claude/hooks/webfetch-allowlist.sh`,
  a session-level hook keyed on the agent's `agent_type`, refuses every other agent and URL in autopilot
  sessions; in the owner's sessions (`/review`, `--interactive`) it checks the verifier's fetches only, and every
  other fetch is the owner's to approve, as before. A refuted claim blocks like a finding; one it cannot settle stops the item for the
  owner, who accepts it by its id; every verdict is in the PR. **Weaker than before, knowingly**: WebFetch used to be absent from
  autopilot sessions; now a hook decides who uses it, and the autopilot's allow rules (by host, as Claude Code's
  rules match) would let any agent reach those six hosts if the hook failed open. Its tests and Factory
  guards' `check-web-access.sh` (only the verifier has WebFetch, every agent declares its tools, both settings
  run the hook, the hosts are allowed and open in the firewall) are what hold it; a URL path to an allowed
  host is still a channel, for the little the verifier can read.
- **Review rules for the factory itself** (backlog #0-161): a change to a path of the Owner-only list is
  judged by the security and architecture reviewers also against `.ai/rules/review/factory.md` — `FAC-S` (no
  agent that reads untrusted text may both reach a secret and send data out, the network and the allow-list,
  tools and scopes per agent, guards that fail closed, no secret within reach of an agent that can send, the
  owner's denies) and `FAC-A` (one list per control, agents' answers that fail closed, every stage in the PR
  record, guards at session level, a weakened layer named) — so a defect there can block like any `SEC-`
  finding. No autopilot item reaches those paths: in practice they judge the owner's `/review`. The rules for
  CI workflows (`.ai/context/security.md`, "CI workflows") still carry no ids (#0-136).
- **Network**: autopilot runs happen in the devcontainer (`.devcontainer/`), whose firewall allows only its
  own DNS resolver, the Anthropic API, GitHub, Maven Central, the verifier's advisory hosts (`osv.dev`,
  `api.osv.dev`, `tomcat.apache.org`, `spring.io`: open to the whole container, and by the IPs they resolve to,
  which a CDN or Google's front end shares with other sites — hence a short list) and the Docker host over IPv4, closes IPv6 to all
  but loopback, and blocks all traffic if its own setup fails (`FIREWALL SETUP FAILED`). It narrows exfiltration, it
  does not prevent it: the host's Docker (needed by Testcontainers) and GitHub itself remain channels.
- **Where a run starts**: the preflight refuses a run outside the devcontainer (`FACTORY_DEVCONTAINER` from its
  `containerEnv`), not under the bot's identity (`GIT_AUTHOR_NAME`, `GIT_COMMITTER_NAME` and `gh`'s login must be
  `FACTORY_BOT_LOGIN`, the two `GIT_*_EMAIL` its noreply address), with the firewall down (`example.com` not refused,
  as `init-firewall.sh`'s self-test checks, so a firewall flushed after the container started refuses too), or in a
  session that did not load `main`'s `settings.autopilot.json` and `settings.json`: the first carries a hash of both
  without that field (`scripts/factory/settings-hash.sh`), the session's env holds the value of the files it loaded,
  and the two are compared after the preflight's fast-forward; Factory guards keeps the field equal to the files
  (backlog #0-194, ADR-0052). Every signal can be set
  by hand: it stops a mistake, not an adversary.
- **Merge**: shadow mode does not rely on the agents — `gh pr merge` is denied to autopilot sessions and the only push
  a hook allows is `git push -u origin <type>/<branch>` of the run's own branch, which the workflow records in
  `.ai/runs/LOCK` (`state.sh branch`) once it has bound the picker's answer to the item (`<type>/<item>-…`, and on
  resume to the branch the owner gave). Only the factory-ops agent runs `scripts/factory/`
  (`guard-factory-scripts.sh`, on `agent_type`), one command per task: `factory-ops-bash.sh` refuses every call of a
  factory-ops run after its first allowed one (keyed on `agent_id`, backlog #0-169, ADR-0053), so text a script
  printed from the branch cannot steer it into `state.sh unlock`, `branch` or `record`; and the autopilot refuses an
  agent's writes to the lock itself and to the factory-ops runs' marks (`.ai/runs/ops-calls/`, #0-233) (the denies,
  `guard-protected-bash.sh`, git's `--output` included); not covered: code run through `./mvnw` (#0-116), a command
  shaped past the shell guard's text match, such as a quoted or spliced option word (#0-167, frozen until ADR-0055
  stage 6a), git's commands on the working tree, where the gitignored state lives (`git add` once `.gitignore` no
  longer names it, then `git rm`; `git mv`; `git switch` from a commit that tracks it): `git_runtime_unsafe` refuses
  their plain forms but none of `switch`, a heuristic until the state leaves the working tree (#0-236, ADR-0055 stage
  4), and a refused second factory-ops call, which is not recorded for the audit (#0-234). `rm`, `find`, an
  interpreter or a wrapper is kept out by the allow list ("An agent's prescribed commands run in its session" below,
  #0-235). Before #0-131 any feature branch was allowed, the owner's open PR included; and the bot account (Write)
  cannot push to `main` or merge around a red check or a code owner's path, whatever runs in the session: the ruleset
  of `main` (#0-113, above in "GitHub and CI"). A red `main` opens an `autopilot-stop` issue
  (`.github/workflows/main-guard.yml`), which the preflight honours. Both read main's CI result from a push to this
  repository only (backlog #0-148): a fork pull request from a branch named `main` matches a `main` branch filter, and
  it neither opens the issue nor counts as main's result in the preflight.
- **Owner labels are verified** (backlog #0-126): the audits count a `human:*` label only when the owner added it
  (the one admin of `repository.json` on main, read from GitHub by `owner-login.sh --github`, backlog #0-237;
  `scripts/factory/audit-data.sh` reads each PR's label events; a label by another account, with
  no event, or while the owner cannot be read counts for nothing, and so does every label while the autopilot runs on
  the owner's own login; the report names them), and agents take labels only from that data, never from
  `gh pr view`. That check is the control. As a second line, the shell guard refuses an autopilot session's
  `gh pr create`/`new`/`edit` and `gh issue create`/`new`/`edit` commands that set a label other than the shipper's
  (`autopilot`, `shadow`, `blocked`, `risk-high`) or remove one other than `blocked`, in the flag forms gh accepts, behind
  flags, by path, through another program, from a `--recover` file, or split by a newline inside a quoted word
  (`guard-protected-bash.sh`, plus deny rules); like the other shell guards it is a heuristic, and code the session
  runs is not seen by it (the known gap below).
- **Escape markers are verified** (backlog #0-129): the audits count a `**Fixes:** #0-N · **Escaped from:**
  <stage>` marker (a case, and a "hard fact" for confidence) only when the commit that first added the marker itself
  (not its line, which a status change rewrites) reached `main` in a pull request the owner opened (the one admin of
  `repository.json` on main, read from GitHub, `owner-login.sh`, backlog #0-237, so the move to an organisation
  changes nothing)
  (`audit-data.sh`, `gh api .../commits/<sha>/pulls`; the history read without replace refs, grafts, textconv or
  external diff drivers, and a shallow clone vouches for nothing), and it is a new case only when that commit is in
  the audited period (a copy of an old marker is not). A marker pushed
  without a PR, from another account's PR (the autopilot's, even merged by the owner), with the lookup failing, while
  the owner cannot be read, or while the autopilot runs on the owner's login counts for nothing and is listed as
  unverified; the commit's author, committer or signature proves nothing. Factory guards also fails a malformed
  marker, one the audits could not read, in any spelling (`check-escape-markers.sh`, backlog #0-128), with the
  pattern defined once in `scripts/factory/_marker.sh`. Since #0-131 the autopilot cannot push onto a branch of
  the owner's open PR, so a marker in an owner's PR is not one the bot slipped in.
- **The review rules' labels are true** (backlog #0-184, ADR-0046): a rule marked "Enforced by" is not reviewed by
  hand, so Factory guards fails one whose script runs in no required job on a pull request, only under an `if:` that
  leaves pull requests out, while continuing on error, or in the owner's step, and a label naming a script, test or
  guard that does not exist (`check-rule-claims.rb`); it also fails a rule file other than `factory.md` naming the
  seeded-defect measure, and a pattern citing a retired or missing rule id. It reads backticked names only.
- **An agent's prescribed commands run in its session** (backlog #0-207, ADR-0050): every agent with Bash names its
  command forms in a marked list (the picker, the implementers, the shipper, the defect-seeder), or is exempt with a
  reason (a read-only or factory-ops guard of its own), and Factory guards (`check-agent-commands.rb`) runs each form
  through the session's hooks and the agent's own, against the allow and deny rules of both settings files, and fails
  a form Claude Code refuses whatever a rule says (a recursive `cp`, an absolute path, a pipe or chain, an unquoted
  glob, `..`, `git -C`). It matches the rules' text, not Claude Code's own permission check, which only a `dontAsk`
  session shows (#0-214). The same check holds the allow list itself (backlog #0-235, ADR-0054): every `Bash(...)`
  allow rule of both settings files, and of the `allowed-tools` of a skill an autopilot agent preloads, starts with a
  prefix judged unable to remove or move a path it does not name (`SAFE_PREFIXES`, each as narrow as the rules it was
  judged on), holds no shell operator, or is an exemption with its reason (`./mvnw`, #0-116; `scripts/factory/`,
  factory-ops only; git's commands on the working tree, #0-236 at ADR-0055 stage 4). The runtime state
  (`.ai/runs/LOCK`, `state.json`, the factory-ops marks, `.ai/STOP`) is gitignored, so this is what keeps `rm -rf
  .ai/runs` out; `guard-protected-bash.sh` only sees a command that names a path. git's `add`, `rm`, `mv` and `switch`
  act on the working tree the state lives in, so they reach it without naming it: `git_runtime_unsafe` (`_lib.sh`,
  review rounds 1-3 of #0-235) refuses `git add -f` in every spelling and a `git add`/`rm`/`mv` path that resolves,
  from the repository's root, into the state or, for `mv`, above it (`.//.ai`, `.ai/runs//LOCK`; `git -C` and
  `--work-tree`, which would change that root, match no allow rule and are forms Claude Code refuses), but an agent
  that edits `.gitignore` makes a plain `git add .ai/runs` stage it, and no form of `git switch` is refused. That is a
  heuristic; the fix is the state out of the working tree (#0-236, ADR-0055 stage 4). The shell guard matches a
  protected path after resolving `//` and `/./`, so `git log --output=.ai/runs//LOCK` is refused too.
- **The autopilot moves to a build VM, off the owner's Mac** (backlog #0-238, ADR-0056, stage 2 of ADR-0055; until
  #0-238's AC5, three items run there, the devcontainer on the Mac stays the way back): the Lima instance
  `factory-build`, made from nothing by `scripts/factory-admin/build-vm/create.sh`, its contents from `provision.sh`
  alone. Every download is pinned and checked: Ubuntu's cloud image by sha256 (Lima), Node and the devcontainer CLI by
  sha256 and sha512 (`provision.sh`), and `verify-pins.sh` checks each pin against its publisher (Ubuntu's and Node's
  signed sums, npm's integrity). Nothing of the Mac is mounted (no `base:` template, `mounts: []`), no SSH agent and
  no VM port is forwarded to the Mac, nor X11, a network, the Mac's proxy variables or a copy of VM files onto the Mac: `create.sh` checks each on the
  started VM and deletes it otherwise, when a check cannot answer, or when anything fails before the clone is done (Lima merges the Mac's `~/.lima/_config/` files into every instance). The repository there is
  a clone of its own, with no gitignored file of the owner's (#0-202).
  The devcontainer runs inside it, with `dev` kept at uid 1000 (`updateRemoteUserUID: false`).
- **The build VM's Docker is rootless, and everything it sends is filtered** (backlog #0-116, #0-240, ADR-0057):
  Docker CE runs as the unprivileged user `factory` (the rootful daemon masked, `factory` in no docker group, Docker's
  apt key pinned by fingerprint), so root in any container a test starts is `factory` in the VM and cannot change the
  VM's firewall or `/etc`, nor read root's files. Root's chain `FACTORY-EGRESS`, matched on every uid from 1000 up
  (`factory`, its subordinate range, any later user; only system accounts are free), lets everything they send (the
  daemon, every container, the devcontainer's included) reach DNS and an allow-list only, refreshed every 30 minutes,
  rejects the gateway (the Mac's loopback services), the VM's network, link-local, the VM's own listeners but the
  ports Docker publishes, and IPv6;
  it is in place before `factory`'s session starts, which requires it, and fails closed. Root writes nothing under
  `factory`'s home (a link planted there would turn a root write into root for `factory`). `create.sh` checks all of it
  on every VM it makes, and it and Factory guards refuse a VM copy of the devcontainer's allow-list that differs from it either way.

**Known gaps**: a bypass actor or an admin added in the UI is seen only when the owner runs
`repository-settings.rb check` (#0-113, ADR-0034), and so is a secret added in the UI (ADR-0035); a scan that
cannot run on `main` (an expired token, an NVD outage) looks the same as one that found issues, and alerts no one
(#0-155); the devcontainer's firewall binds the agents' own
commands but not code they run, as Docker access (needed by Testcontainers) is root over the container
(#0-116, accepted for shadow mode, required before auto-merge): in the build VM that code is only the unprivileged
`factory`, with no route past the VM's allow-list or to the Mac (ADR-0057, which closed #0-240 there; a listener a
root service opens on the VM's ephemeral ports after its creation is reachable, checked only by `create.sh`, #0-242), but it still
reads what `factory` holds, the devcontainer's volumes with the bot's token and Claude Code's login (ADR-0055 stage 4),
and on the Mac, the way back until #0-238's AC5, all of the above stays as it was; secrets are scanned only after the push, when a
branch is already public, and an allow comment passes whatever its line holds (#0-156, ADR-0036); no Maven Enforcer
(#0-110); the shell guards are heuristics, the commit gates and the PR checks are the reliable lines; an owner's
session on a Claude Code older than 2.1.295 ignores the hooks' `onFailure` without a word, so there a hook that
cannot start or times out does not block (only the autopilot's preflight checks the version; ADR-0039);
an agent guard's session-level twin passes everything if Claude Code stops sending `agent_type` (its frontmatter
hook stays for that, ADR-0041), and the autopilot's implementer, implementer-light and shipper have no guard
of their own: in an interactive session (not the autopilot's) only that session's denies and hooks bound them
(#0-186); the reviewers read the rules from `origin/main` by instruction (`review-procedure`), which no hook
enforces (#0-165); `/research` and `/ship` still pre-approve `git diff *` (and `/research` `git log/show *`), and no
hook of the owner's session refuses `--output`, `--ext-diff`, `--textconv` (#0-167, frozen until ADR-0055 stage 6a);
the autopilot's settings allow the Grep and Glob tools, which no secret deny rule (`Read(…)` only) or hook names:
harmless while Claude Code gives them to no agent with Bash, unchecked if a version does (#0-225, frozen until
ADR-0055 stages 2 and 4: no secret file in the task container; in the build VM the clone holds none of the owner's,
ADR-0056, and the gitignored files a task itself creates there wait for stage 4).
Layers and their limits: docs/ai-factory.md, "What isolates what".

### Container images

- **The image packages a built jar, nothing else** (backlog #0-141, ADR-0030): each service's Dockerfile takes
  the jar Maven built, extracts it into Spring Boot's layers in a JRE stage and ships only the JRE image
  (`eclipse-temurin:<version>-jre-alpine`) with those layers: no JDK, Maven, sources or dependency cache. The
  build context is an allowlist (`.dockerignore`): only `<service>/target/<service>-*.jar` is sent, so no
  source, `.env` or local configuration can reach an image. In CI the jar is the one Job 1's `verify` tested.
- **No local secrets in a jar** (backlog #0-100): the root POM excludes `application-local.*` and
  `application-secrets.*` from every jar, `shared`'s included, and CI checks it with planted files (Job 1).
- **Tomcat patched past Spring Boot's BOM** (backlog #0-157): Spring Boot 3.5 gets no more releases, but Apache
  still patches Tomcat 10.1, so the root POM sets `tomcat.version` (10.1.61) for every service's embedded
  Tomcat. No Tomcat CVE is ignored in `.snyk` or suppressed in `owasp-suppressions.xml`. Nothing bumps the
  property automatically (#0-159): a person checks Apache's 10.1 security page, until the move to Spring Boot 4
  (#0-158) removes it.
- **Non-root, code not writable**: every image creates `appuser` and runs as `USER appuser`; the application's
  files are owned by root and not writable by that user, so the service cannot change its own code (until
  #0-141 the jar was owned by `appuser`).
- **Pinned base images**: the image carries an exact version tag, which Renovate updates (all Dockerfile
  updates grouped into one PR).
- **Container-aware JVM**: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`, so the heap follows the
  container's memory limit instead of the node's.

### Kubernetes

- **Secrets outside the ConfigMap**: `JWT_SECRET`, `MFA_ENCRYPTION_KEY`, `SLACK_ENCRYPTION_KEY`,
  `SLACK_SIGNING_SECRET`, `GEMINI_API_KEY` and `DB_PASSWORD` come from the `app-secrets` Secret, one `secretKeyRef`
  per key, and each Deployment receives only the keys it uses (the MFA and Slack encryption keys reach only
  auth-service; `DB_PASSWORD` the six services that use the database). The Postgres superuser's credentials are a
  separate `postgresql-admin` Secret that only the database reads. The overlays' `secrets.yml` hold placeholders
  for staging and prod, with External Secrets or Sealed Secrets as the intended source.
- **Narrow Ingress**: routes only `/api/v1/*` and `/ws`. Actuator endpoints, the management ports, Swagger and
  `/dev/**` are not routed.
- **Rate limiting at the edge**: per-client-IP limits on the Ingress (`limit-rps`, `limit-rpm`,
  `limit-connections`), in front of the application's own bucket4j limits.
- **Resource limits and probes**: every Deployment sets CPU and memory requests and limits, and readiness and
  liveness probes on the management port.
- **Mail catcher in dev only** (backlog #0-42, ADR-0026): `k8s/overlays/dev` runs Mailpit (non-root, read-only
  root filesystem, no capabilities) behind a `ClusterIP` Service, read through `kubectl port-forward`, because its
  UI has no authentication and shows invite and password-reset links; only dev turns SMTP auth and STARTTLS off.
  Base, staging and prod have no catcher, no overrides and a placeholder relay host. CI fails when Mailpit or an
  override reaches them, when anything exposes 8025 beyond the cluster, or when its image drifts from compose's
  (`.github/scripts/check-k8s-mail.rb`, with a mutation test). Inside the cluster any pod can still reach 8025,
  because there is no NetworkPolicy yet (backlog #0-65).
- **No dev profile outside dev** (backlog #0-63): only `k8s/overlays/dev` sets `SPRING_PROFILES_ACTIVE`, and CI
  fails if the rendered staging or prod overlay sets any Spring profile. The base used to set `dev` for every
  overlay, which would have exposed incident-service's unauthenticated `/dev/token` in prod.
- **No profile configuration or literal secret in a jar** (backlog #0-81): CI fails on a committed
  `application-<profile>.*` under `*/src/main/resources`, a base `application.*` with a
  `spring.config.activate.on-profile` document or a `spring.profiles.active` / `include` / `default` / `group` (in a jar it
  would apply everywhere, past the manifest check above), or a secret, encryption key, private key or API key there
  (any key ending in `secret`, `encryption-key`, `private-key`, `api-key`, kebab or camelCase) that is not a `${VAR}`
  without default (`.github/scripts/check-packaged-profiles.sh`; postmortem-service's `gemini.api-key` lost its
  placeholder default for it). The `test` profiles, with a hard-coded JWT secret and MFA
  key, used to ship in three services' jars and images; a run with that profile outside the manifests would have
  used them, which the check above cannot see.
- **Schema validation**: CI renders base and all three overlays and validates them with `kubeconform -strict`
  against the API schemas of the Kubernetes version pinned in `ci.yml`, binary and schemas pinned (backlog #0-76;
  "GitHub and CI" above).
- **Each overlay deploys its own environment** (backlog #0-29): CI fails when an overlay's render puts any resource
  in a namespace other than `incident-platform-<overlay>`, or when prod runs an untagged or `latest` image or a
  service tagged with an environment's name instead of a release (`.github/scripts/check-k8s-environments.rb`,
  with its mutation test). From the first commit of the manifests until #0-29, the staging and prod overlays held
  each other's `kustomization.yml`, so "deploying prod" put staging-tagged images, at staging's size, into
  `incident-platform-staging`.

### Data stores

- **Passwords and secrets at rest**: user passwords are Argon2 hashes; TOTP secrets and tenants' Slack bot tokens
  are encrypted with AES-GCM under two separate keys; Integration API keys are stored as SHA-256 hashes only;
  emailed credentials are never stored raw.
- **Schema changes only through migrations**: each service has its own Flyway history table and
  `ddl-auto: validate`, so an unmigrated change fails startup instead of altering the schema.
- **Redis persistence**: append-only file on, so revoked tokens and dedup keys survive a Redis restart.
- **No default database password**: `application.yml` reads `${DB_PASSWORD}` with no fallback, so a service
  without the password never connects with the dev one; when it is missing, Kubernetes (`secretKeyRef`) and
  compose (`${VAR:?}`) stop before the service starts. A CI step (`check-db-password-config.rb`, with a bypass
  test) fails unless every committed config sets the password to exactly `${DB_PASSWORD}` (backlog #0-66).
- **No superuser for the services**: they connect as `incident_app`, which owns the database but is not a superuser,
  cannot create roles or databases and is a member of no other role, so a SQL injection no longer reaches the
  container (`COPY ... TO PROGRAM`), the server's files or other roles directly. The image's superuser is for
  administration only and never touches anything outside `pg_catalog` in the database: service data, backups and restores go through an
  `incident_app` login, and the admin's `search_path` is `pg_catalog` (backlog #0-78,
  [docs/database-roles.md](docs/database-roles.md), "Working as the admin"). CI checks it twice: the "PostgreSQL Roles"
  job tests the init script and the migration of an older database against the real image, and after every
  migration has run as `incident_app` the smoke test checks the role's attributes and memberships and that
  `COPY ... TO PROGRAM` is refused.

### Application

Summary; details in [Resilience & Security](#security).

- **Authentication**: JWT HS512 with a secret of at least 64 bytes and no default; login brute-force protection
  (per tenant and email, 10-minute window, 15-minute lockout); TOTP MFA; revocation of refresh tokens.
- **No default accounts**: no migration seeds a user. A tenant's first admin is invited by email and sets their own
  password; the old seeded `admin@incidentplatform.com` / `changeme` is archived wherever its password was never
  changed (backlog #0-80).
- **Tenant provisioning**: the one cross-tenant capability. Only an admin of the `platform-operator` tenant with a
  JWT (no API key, service or purpose token) reaches `/api/v1/platform/**`, checked in auth-service's filter chain
  and on every method; it creates a tenant with an invited first admin, reissues that invite while the tenant has
  no admin, shows and lists tenants' metadata, suspends and resumes tenants, and asks for the MFA recovery of a
  customer tenant's only admin (both below), audited in the operator tenant. The Ingress routes it like
  every auth-service path, so that rule is its only protection (backlog #0-80,
  [docs/tenant-provisioning.md](docs/tenant-provisioning.md)). Since backlog #0-83 the caller's session must have
  completed MFA within 12 h, with a factor whose "MFA enabled" email went out at least 24 h ago (checked on the server per
  request, so logout or disabling MFA ends access at once). Writes are limited per operator and in total in Redis
  (fail-closed: 503 while Redis cannot be checked, unlike ingestion's fail-open limiter), and a provisioning
  spike (`PlatformTenantProvisioningSpike`) or a reached limit (`PlatformApiRateLimited`) alerts the operator
  by email; `PlatformApiRateLimitUnavailable` reports the Redis case.
- **SMTP requires STARTTLS**: auth-service and notification-service send mail only over STARTTLS
  (`mail.smtp.starttls.required`, backlog #0-124), so a relay that strips the capability gets no AUTH credentials and
  no content. Only the dev mail catchers (docker-compose, the Kubernetes dev overlay) turn it off.
- **MFA change notifications**: enabling or disabling MFA on any account emails the account's address (backlog
  #0-83), so an owner learns when someone else used their password to change the second factor. A password reset by
  email ends every session and unfinished login and revokes the personal API keys (backlog #0-89), but never
  touches the second factor (backlog #0-88), so a mailbox alone cannot undo MFA.
- **Admin MFA reset**: an admin of the tenant removes another user's factor, backup codes and every session
  (`POST /api/v1/users/{id}/mfa-reset`, backlog #0-88), for a lost phone or a factor someone else enrolled. Only
  from an admin session that passes the platform API's MFA rule (MFA within 12 h, a factor announced at least 24 h
  ago; a password-only session, a fresh factor or an API key gets 403), never on one's own account; the user gets
  an email of its own ("an administrator reset your MFA"), audited as `MFA_RESET_BY_ADMIN`. A deactivated user can be
  reset too (before reactivating an account with a stranger's factor). Limited per admin (10/h) and per tenant (30/h),
  counted only for a reset about to happen (after step-up, user lookup and factor check), fail-closed (503 while Redis cannot be checked); reaching it alerts the operator by
  email (`AdminMfaResetRateLimited`, critical). A single platform operator has no second
  admin: a one-off break-glass command of auth-service does the same reset, audited as `MFA_RESET_BREAK_GLASS` with
  the operator's name and reason, its event written to the audit outbox in the reset's transaction and sent
  before the command exits when Kafka is reachable
  ([docs/tenant-provisioning.md](docs/tenant-provisioning.md)). A customer tenant's only admin has the operator's
  MFA recovery instead (next item).
- **MFA recovery of a customer tenant's only admin** (backlog #0-90): the one action the platform takes inside a
  tenant that has an admin, the narrow exception to #0-80. An operator who passes the platform API's rule asks for
  it (`POST /api/v1/platform/tenants/{id}/mfa-recovery`, limited like the other platform writes) only for an
  active admin with MFA who is the tenant's only active admin, recording how the person was verified outside the
  account (method and note). Nothing happens then: the account is emailed a notice with a cancel link, and only
  once 72 h (configurable, never under 24 h) have passed since that email was actually sent does a scheduled job reset the factor, backup codes,
  sessions, personal API keys and the password (replaced by one nobody knows; the completion email carries a
  password-reset link), after checking again that no other admin exists and that the operator who asked is still
  an operator admin (a request from an account later deactivated does not run). A notice that never goes out
  expires the request. The account (single-use link, `POST /api/v1/auth/mfa-recovery/cancel`) or any operator can cancel.
  Audited in both tenants (`MFA_RECOVERY_*`; the operator's note only in the operator tenant), and every request
  and every cancellation by the account or on that final check alerts the operator by email
  (`PlatformMfaRecoveryRequested`, `PlatformMfaRecoveryCancelledByAccount`, `PlatformMfaRecoveryCancelledOnRecheck`,
  critical, counted only once their transaction commits; a second admin added during the wait may be the
  attacker's); an expired request raises `PlatformMfaRecoveryExpired` and one the scheduler keeps failing on
  `PlatformMfaRecoveryJobFailing`. The customer tenant's trail names an operator only as `platform-operator`. Prevention: tenant settings show `activeAdmins` and
  `singleAdmin`, so a tenant's admins see while one admin is all there is.
- **One definition of an active admin** (backlog #0-90): active, not archived, with an accepted invite. The "last
  admin" guard used to count an admin whose invite was pending, so the last admin who could log in could be
  demoted, deactivated or archived.
- **Tenant suspension** (backlog #0-82): an operator suspends a tenant (`POST /api/v1/platform/tenants/{id}/suspend`,
  `/resume`; a `SECURITY` reason requires `FULL`, also enforced by a CHECK; `platform-operator` itself cannot be
  suspended), in full (nothing works: every session ends at once, sign-ins, invites, password resets and API keys
  are refused, an access token already issued is refused in every service, and its live WebSocket sessions are
  closed) or read-only (reads go on,
  writes are 403 except account security: logout, password, MFA, and an admin revoking a key (one, or every key
  a user created) or an integration, deactivating a user or resetting their MFA, each listed with its HTTP method,
  reactivating a user refused; alerts are paused, not lost: ingestion-service answers them 503 +
  `Retry-After: 300` + `TENANT_READ_ONLY`, so Alertmanager retries them until the tenant is resumed; a full
  suspension's alerts get `403 TENANT_SUSPENDED`, not counted as a failed authentication of the sender's IP). The
  status lives in auth-service's `tenants` table (V30). Transitions take a row lock on the tenant (`FOR NO KEY UPDATE`,
  waits) before a status-guarded UPDATE, so two operators are serialised; sign-ins, invites and resets take a
  share lock on the same row, taken before any token is consumed (the suspension's order: tenant, then tokens), so a
  sign-in racing a full suspension either commits before the suspension's session cleanup or reads the suspension;
  it waits at most 3 s, then gets 503 + `Retry-After`; a suspension or resumption waits at most 5 s, and any
  request of auth-service that loses a lock (timeout, deadlock) gets 503 + `Retry-After`, not 500. A
  `TenantStatusFilter` from `shared`, added by `buildCommonSecurity` to every service's chain, refuses a suspended
  tenant's users and keys; auth-service answers it from its database, every other service asks auth-service
  (`GET /api/v1/internal/tenant-status`, a service token for that tenant, `aud=auth-service`) and keeps the answer
  10 s, one call per tenant at a time, so a suspension reaches every service within 10 s (step 2 of #0-82). If
  auth-service cannot answer, a service keeps each tenant's last known status however long the outage lasts
  (static stability), and gives full access only to a tenant it never had an answer for (fail-open, decided: an
  auth-service outage must not stop every tenant); counted and alerted (`TenantStatusLookupFailing`, and
  `TenantStatusLookupRejected`, critical, when auth-service refuses the service's token). CI fails a service that
  does not set `auth-service.base-url` (`check-tenant-status-config.sh`): without it the service would give every
  tenant full access. In incident-service a
  suspended tenant's STOMP `CONNECT` is refused and a sweep every 10 s closes the sessions it opened before; both
  read the status without waiting on auth-service, so its outage cannot tie up the WebSocket threads (alerts
  `WebSocketSessionUntracked` if a session cannot be tracked, `TenantStatusCacheFull` if the status cache is
  full).
  auth-service's public paths (login, refresh, MFA, invite, reset) check the status themselves, and a sign-in
  refused for it is audited (`USER_SIGN_IN_REFUSED_TENANT_SUSPENDED`, after the rollback) and counted
  (`auth_signin_refused_total`); past a few refusals per user in the brute-force window the answer is 429 with no
  event (a refusal rolls back, so its invite or reset token, or a right password, could be replayed without end). Nothing is deleted or revoked, so a resumed tenant works as before. Invites (and, in full,
  password-reset emails) wait while it lasts. The tenant's background work is paused in either mode and resumed
  with it (step 2b): notification-, escalation- and postmortem-service keep a table of paused tenants
  (`<service>_paused_tenants`), filled every 10 s by `PausedTenantsSync` (`shared`, ShedLock) from auth-service's own
  answer for the tenants with work waiting, never on a fail-open guess, so an auth-service outage neither pauses nor
  resumes anyone; their schedulers' queries leave those tenants out (in SQL, so a paused tenant's old rows cannot
  starve the others; the table name a constant checked against `tenant-pause.table` at startup) and ask `accessOf`
  per row in between (the status cache, asked of auth-service again when expired or never filled, so a restart does
  not let a suspended tenant's rows out), each batch's tenants looked up together first, 8 at a time and within
  the run's processing budget, so a slow auth-service does not delay the batch tenant after tenant. Nothing is sent, escalated or generated (no Gemini call) meanwhile; the
  Kafka consumers go on writing the rows, so resumption finds a consistent state. Escalation timers stop for the
  pause, measured from the suspension's own time (`suspended_at`, which auth-service now sends with the status as
  `since`), however late a service noticed it: the tenant could not acknowledge anything. Notifications are all sent
  on resumption, none dropped for age. The Slack ACK path (no button in messages since #0-21, back with #0-35) refuses
  a suspended tenant itself, as it reaches incident-service with a service token, which the status filter lets
  through. Alerts `TenantPauseSyncFailing` (runs failing) and `TenantPauseSyncStalled` (no instance completed a
  run in 5 minutes). Audited in both tenants, alerted on every change
  (`PlatformTenantSuspensionChanged`, critical). Every auth-service table holding a tenant's data has a foreign key
  to `tenants` (V31/V32, `ON DELETE RESTRICT`; not the auth email and audit outboxes), so no tenant can have data
  without the row that makes it suspendable; a token naming a tenant with no row (only one minted outside
  auth-service, e.g. `/dev/token`) still gets full access, counted and alerted (`PlatformTenantStatusRowMissing`),
  and its first write in auth-service is answered 403, not 500 (`UnrecordedTenantHandler`). V31 names every tenant
  id it had to record in a warning in auth-service's log. Deactivating a single user now also ends their sessions, and a
  refresh or a personal API key of a deactivated user is refused (until then deactivation only stopped new logins).
- **Audit trail through an outbox** (backlog #0-84, every service with audit events: auth-, incident-,
  notification-, escalation-, postmortem-service): an audit event is a row in the service's own outbox table,
  written in the transaction of the action it records, so a rolled-back action leaves no event, a committed one
  cannot lose it, and a Kafka outage stalls no request. There is no other path: `AuditEventPublisher` exists only
  in a service with an outbox table. A relay (ShedLock, one per service, taken only when a row is due) sends the
  rows in order, at least once; incident-service drops a resent event by its id
  (`audit_events.event_id`, unique per tenant, so one tenant's records cannot pre-empt another's), and treats
  only that and the Kafka-offset key as duplicates. It takes each record's tenant from its payload, which the
  `X-Tenant-Id` header must match (`TenantKafkaRecordResolver`, as every consumer does), and rejects a record
  whose two disagree or whose payload names none; a record it cannot store
  is acknowledged only once its dead-letter copy is in Kafka, and alerts (`AuditEventsRejected`, critical).
  The publisher refuses an event the trail could not store (no tenant, a payload over 256 KiB, a metadata key
  naming a secret) before it is written. A refusal whose transaction rolls back (a
  wrong TOTP) is audited after the rollback. An event about an action that cannot be undone and is already
  committed (a delivered notification, a fired escalation) is written after it; a failure to write one is logged
  and alerts (`AuditEventUnrecorded`, critical) rather than undoing nothing. An error goes into an event cut to
  500 characters on one line, and an unexpected exception by its type only, never its message (`AuditText`): the
  trail is the tenant's to read, and a client library's message can quote a URL with a token or a response body.
  A notification channel's own failure is recorded by the platform's reason (`NotificationFailureReason`, e.g.
  `EMAIL_RECIPIENT_REJECTED`, `SLACK_REJECTED (not_in_channel)`, with at most a checked provider code; also a
  `reason` field of its own in the `NOTIFICATION_FAILED` event), never the mail server's reply or Slack's response,
  which go to the log only (backlog #0-93). The producers fail a send after 5 s
  without Kafka's metadata (`KAFKA_PRODUCER_MAX_BLOCK_MS`) instead of Kafka's default 60 s, except
  escalation-service's, whose escalation event is sent once (#0-4). A backlog older than 10 minutes alerts the
  operator by email (`AuditOutboxBacklog`, critical, read from the table, so a stopped relay shows too).
- **No Kafka record let go unkept** (backlog #0-96): a consumer acknowledges a record only once it is processed or
  its dead-letter copy is acknowledged by Kafka (`DeadLetterPublisher.deadLetterThenAcknowledge`); a failed copy and
  a transient failure (`KafkaFailures`) are `nack`ed and read again, never left unacknowledged, which skipped them.
  A record without `X-Event-Type` is dead-lettered, no longer dropped. ingestion-service answers 503 with
  `Retry-After` when an alert it cannot process cannot be copied either. At least once: a copy can be stored twice,
  identified by its `sourceTopic`, `sourcePartition` and `sourceOffset`. Bounded so that no record can hold a
  partition, every tenant on it, for ever: 5 s per copy (a producer of its own, 2 s metadata block), a poll of
  copies within half of `max.poll.interval.ms` (checked at startup), a record failing past
  `kafka.consumer.redelivery-deadline` (30 min) dead-lettered and alerted (`KafkaRecordRedeliveryGaveUp`,
  critical), a copy's payload cut to 128 KiB. Retries are counted in `kafka.records.redelivery.requested{reason}`
  and alert after 15 minutes without a break (`KafkaRecordRedeliveryStuck`, high). An unexpected exception goes
  into the copy and the log by its type only (a driver's message can quote a row). ingestion-service waits for a
  request's copies together (one 5 s deadline, `max.block.ms` 5 s instead of Kafka's 60 s) and releases the dedup
  keys of alerts a lost copy was to keep; its copies' deadline counts from the wait, and no copy is started after one
  failed. Not bounded: a copy Kafka does not take at all, retried while Kafka is down. Accepted: a database outage
  longer than the redelivery deadline dead-letters the record at each partition's head, about one per partition per
  deadline; an audit event dead-lettered that way is missing from the trail until replayed by hand (#0-97), and
  raises both `AuditEventsRejected` and `KafkaRecordRedeliveryGaveUp`.
- **Structured logs** (backlog #0-94, step 1): every service writes one JSON object per line in Elastic Common
  Schema, to the console and to a log file if one is ever configured. It is Spring Boot's own structured logging,
  set for all seven by `shared`'s `StructuredLoggingDefaults`. Its encoder escapes every value, so a CR/LF from a
  Kafka header, a payload field or a library's exception message stays inside its line; before, each call site had
  to remember not to log a raw value. `tenantId`, `requestId`, `userId` and `kafkaMessageId` are fields of that
  object (the set is pinned by a test). A service whose logs would not be ECS refuses to start
  (`StructuredLoggingGuard`), whatever set the format: its configuration, an environment variable or ConfigMap
  outside this repository, `SPRING_APPLICATION_JSON`, a Logback file of its own, or a reshaped JSON object
  (`logging.structured.json.*`: a renamed or excluded `tenantId` would vanish from every line). Only
  `platform.logging.plain-text: true` lets plain text through, for a developer's `spring-boot:run` in the
  gitignored `application-local.yml`; CI fails on that switch, or a Logback file, in any tracked file
  (`check-structured-logging.sh`).
- **Log collection** (backlog #0-94, step 2, docker-compose): Alloy reads every `incident-*` container's output and
  ships it to Loki, kept 15 days (the compactor deletes older lines) and read in Grafana. Alloy reaches the Docker
  API only through `docker-socket-proxy` (GET on containers and networks, every other call refused, on an
  internal network with Alloy alone, pinned by digest), never through the socket, which is root on the host. Loki
  and Alloy answer without authentication, so neither publishes a port and both are on an internal `logs` network
  with only Grafana and Prometheus: no service, kafka-ui or pgAdmin can reach them. Prometheus is the one
  container on both `default` and `logs`: it scrapes Loki and Alloy but proxies neither, so reaching it gives no
  way to their data (it was reachable from `default` before). Loki's delete API is off, so
  nothing can erase lines before the retention does. Grafana, Loki's only reader, is not on the services' network
  either (it would be a way around the `logs` network), listens on `127.0.0.1` only and has an admin password with
  no default. The proxy, Loki and Alloy run read-only, with no capabilities and no privilege gain (Alloy as its
  image's `alloy` user, not root), each under a memory limit. Only the seven services' JSON is parsed, a level
  outside TRACE..ERROR becoming `OTHER`; another container's lines are kept as they are, so Postgres, Kafka and
  pgAdmin output is in Loki too, for 15 days, and can carry tenant values (a Postgres error quoting a row): it is
  read under the same rule as the services' lines, by whoever can log in to Grafana.
  `tenantId`, `requestId`, `userId` and `kafkaMessageId` are structured metadata, not labels, so no value from a
  request adds a stream. Docker keeps at most 3 x 10 MB of each container's log (`x-logging`). A pipeline that
  stops raises `LogPipelineDown`, `LogPipelineRestarting`, `LogPipelineNotScraped`, `LogsNotFlowing`, `LogDiscoveryFailing` or `LogsDropped`; the smoke
  test checks that every service's lines arrive parsed, that the proxy refuses writes, that the pipeline's
  networks are internal and hold exactly the containers they should, and that this hardening is in the compose
  file.
- **Tenant id and Kafka tenant** (backlogs #0-91, #0-92): every tenant id is a slug of 3-63 `[a-z0-9-]`
  (`TenantIds`), enforced by a `CHECK` on every table with a `tenant_id` in every service, when a token is issued and read
  (`JwtUtils`, `JwtAuthFilter`), on the `X-Tenant-Id` header of auth-service's public endpoints (400),
  in `TenantContext.set` and for every Kafka record: so no tenant id can carry a line break into a log line or
  a new series into a metric. A Kafka record's tenant is its payload's; the header is a copy written only by
  `TenantRecords` (no longer by the producer interceptor from the thread's context, which incident events
  depended on). Consumers refuse a record whose payload tenant is invalid or whose header is missing or disagrees, dead-letter
  it under no tenant, count it and alert (`KafkaRecordsTenantRejected`, critical); a record produced without a
  valid header is counted and alerts (`KafkaRecordsWithoutTenant`, high, webhook only). The MDC takes only a valid header
  (`_missing` / `_invalid` otherwise), and no metric is tagged with a value from a record (`kafka.records.received`
  lost its `tenant` tag: a forged, well-formed header could add series without bound). A scheduler or relay
  that reads a row back sets `TenantContext` inside that row's `try`, so a row `TenantContext` refuses fails
  alone instead of ending the batch for every tenant (found in review); the `CHECK` keeps such a row from
  being written at all.
- **API keys** (backlog #0-89): in auth-service a key reaches only the team routes, and only with the scope
  `teams:read` / `teams:write` (the role checks kept); every other route refuses it, so a key cannot invite users,
  change roles, create keys or integrations or change tenant settings (`ApiKeyAccess`, deny by default). A
  password reset, an admin MFA reset and the break-glass reset revoke the user's personal keys; a password change
  does on request (`revokePersonalApiKeys`). Creating a key, an integration's included, emails the account (a
  personal key its owner, a tenant key the admin who created it). Tenant and integration keys outlive their
  creator by design, so every key records who created it and from which session: an admin lists a user's keys
  (`GET /api/v1/api-keys?createdBy=`) and revokes all they created since a time
  (`POST /api/v1/api-keys/revoke-created-by`, or `revokeKeysCreatedSince` on the admin MFA reset; an archive
  records how many it kept). Tenant and integration keys created before V26 have no recorded creator. Every key is
  announced by its own email, showing its id (never merged, so one key cannot hide behind another's notice);
  a user may create at most 20 keys per hour, revoked ones included (429; `api-keys.creation-limit.per-user-per-hour`,
  env `API_KEY_CREATION_LIMIT_PER_USER_PER_HOUR`), which bounds those emails. Outside auth-service only ingestion-service accepts API keys, and only
  tenant keys (backlog #0-16).
- **Service identity**: service tokens carry the tenant as a signed claim and an `aud` naming the one service that
  accepts them; the only tenant-less token is the API-key introspection purpose token, accepted on one route.
- **Every route refuses an unauthenticated caller** (backlog #0-191, ADR-0048): `IncidentDenyByDefaultTest` and
  `IngestionDenyByDefaultTest` walk every route and method of their service's `RequestMappingHandlerMapping` through
  its real `SecurityConfig` and require 401 with no `Authorization`, 401 or 403 with a real purpose token, and 401
  with an unknown API key as `ApiKey ipl_…` and as `Bearer ipl_…`; a route added later is walked without anyone
  adding it, and the failure names each route that answered otherwise. Their exempt set is a literal with a reason
  per entry (`/error`; incident's is `/error` only), never `PUBLIC_PATHS`, so a new entry there that matches a route
  fails the test. incident's test also runs with no profile and checks that `DevSecurityConfig` is absent, and it
  reports a REST mapping under `/ws/`, which its chain permits for the WebSocket handshake (backlog #0-196).
  In auth-service `ApiKeyDenyByDefaultTest` (an all-scope admin key: 403) and `IntrospectionTokenDenyByDefaultTest`
  (an introspection token: 403) walk every route and method too (`TRACE` 400, the firewall's); their exempt set is a
  literal keyed by `<METHOD> <pattern>` with a reason per entry, never `PUBLIC_PATHS`, so `GET` of a public `POST`
  route is still walked; the routes a key may reach are a literal set of exact team patterns, and the key walk has a
  negative case (backlog #0-197).
  `OncallDenyByDefaultTest` and `PostmortemDenyByDefaultTest` (backlog #0-192) do the same with `/error` as their
  only exemption; `NotificationDenyByDefaultTest` exempts `/error` and `/api/v1/slack/actions`, checks that the Slack
  route answers 401 unsigned through the real `SlackSignatureVerifier` (and 200 correctly signed), and, as its one
  route is exempt, sends the three callers to a path no controller maps. These three, incident's test (#0-196) and
  ingestion's (#0-198) walk every method of a mapping with no method condition, read their exempt set with the same
  matching (a key ending in `/**` covers the patterns below it), and have a positive control: a valid user token
  gets an answer other than 401. ingestion's unknown-key walk also shows its mocked key lookup was asked for the
  key, as `ApiKey ipl_…` and as `Bearer ipl_…`, so its 401 is `ApiKeyAuthFilter`'s in the chain (#0-198).
- **Tenant isolation**: per request (`TenantContext`), per Kafka record, across async hand-offs and in every query.
- **HTTP**: stateless sessions, CORS allow-list, HSTS, `X-Frame-Options: DENY`, `nosniff`, Referrer-Policy;
  ingestion payloads capped at 1 MB; Slack requests verified by signature; WebSocket authenticated at `CONNECT`.
  Every chain built from `buildCommonSecurity` has a `CorsFilter` ahead of authentication: only a valid preflight
  (an allowed `Origin` and `Access-Control-Request-Method`) is answered without authentication, a foreign origin
  gets 403, and every other `OPTIONS` is authenticated like any method, so no explicit `OPTIONS` handler runs for an
  anonymous caller (backlog #0-199, ADR-0049; `SharedSecurityAutoConfigurationCorsTest`). Every service with its
  own chain pins it against its real `SecurityConfig`: an allowed preflight with no token on an authenticated route
  gets 200 with `Access-Control-Allow-Origin`, a bare `OPTIONS` gets 401 (`UserControllerSecurityTest.CorsPreflight`
  in auth-service, and the `CorsPreflight` class of `IncidentDenyByDefaultTest`, `IngestionDenyByDefaultTest`,
  `NotificationDenyByDefaultTest`, `OncallDenyByDefaultTest` and `PostmortemDenyByDefaultTest`, backlog #0-200);
  escalation-service runs the shared `defaultSecurityFilterChain`, which the shared test covers.
- **Actuator**: only `health`, `info` and `prometheus`, on a separate management port, health details only when
  authorized.

### Local stack (docker-compose)

Built for a developer machine, not for a shared host: well-known credentials are expected there (the
`docker/.env.example` values `incident_secret` and `postgres_admin_dev`, and pgAdmin's `admin`). Grafana is the
exception since it reads every tenant's logs (backlog #0-94 step 2): it is published on `127.0.0.1` only, its
admin password (`GRAFANA_ADMIN_PASSWORD`) has no default, and its image is pinned. What it does protect: the monitoring stack's secrets (the operator tenant's Integration API key, the
dead man's switch URL) live in `docker/secrets/`, which is gitignored as a whole and mounted read-only; every email
goes to Mailpit, never to a real address.

### Not done yet

Open items from the audit and earlier, most important first within each area. Each one is described in
[BACKLOG.md](BACKLOG.md).

- **Kubernetes**
  - Pods run without a `securityContext` and the namespace has no Pod Security Admission label: backlog #0-64.
  - No NetworkPolicy, so every pod reaches every data store and management port: backlog #0-65.
  - The Ingress has no TLS: backlog #0-75.
- **Data stores**
  - Redis has no password, Kafka no SASL/ACLs, and nothing uses TLS: backlog #0-66. Until then anyone who
    reaches the broker can produce records: one with a forged tenant is refused and dead-lettered (#0-92), but
    each one also fires the critical `KafkaRecordsTenantRejected` alert and writes a dead-letter record, so the
    alert can be set off on purpose, and a flood fills the dead-letter topic and the logs. The dead-letter
    topics' content is untrusted for the same reason (any field, the tenant and the `X-Tenant-Unresolved`
    marker included, can be forged): nothing reads them today, and a future reader or replayer must resolve
    the tenant again from the original payload, as a consumer does.
  - All seven services share one database role that owns every table, so neither grants nor Row-Level Security
    separate one service's tables from another's, and a SQL injection can plant a trigger, view or function that
    runs as a superuser if a superuser touches a service table, even under `SET ROLE`: backlog #0-67.
  - At the HPAs' maximum replicas during a rolling update, the services' connection pools exceed what Postgres
    allows them: backlog #0-79.
- **GitHub and CI**
  - No static analysis has ever run: Snyk Code is not enabled and CodeQL is not set up: backlog #0-68.
  - The Snyk dependency scan is red on every run, so a new finding changes nothing: backlog #0-69. What has a fix
    within Spring Boot 3.5 is overridden in the root POM (Jackson, the PostgreSQL driver, Netty, 2026-11-13); most of
    the rest is in lines whose open-source releases have ended (Spring 6.2, Security 6.5, spring-kafka 3.3), fixed
    only by Spring Boot 4 (#0-158).
  - Spring Boot 3.5 is out of open-source support, and the ignores in `.snyk` that wait for 4.x wait on a migration
    no one has decided: backlog #0-158.
  - The root POM's security version overrides (`tomcat.version`, `postgresql.version`, ...) are bumped by hand, and
    nothing fails when one is lower than what the Spring Boot parent manages: backlog #0-159.
  - No status check is required before merging to `main`: backlog #0-2.
  - Any Marketplace action is allowed to run (`allowed_actions: all`): backlog #0-62.
  - `diff-cover` is installed by version only, its package and dependencies unchecked: backlog #0-134.
  - kubectl, which renders the manifests that the k8s job's checks read, is downloaded by `azure/setup-kubectl`
    unverified, although Kubernetes signs it: backlog #0-135.
- **Container images**
  - Built images are not scanned and no SBOM is produced: backlog #0-70.
  - Mutable image tags in k8s and compose, and k8s third-party images not tracked by Renovate: backlog #0-71.
- **Application**
  - Swagger UI and the OpenAPI documents are public in every profile: backlog #0-73.
  - Whether `/dev/token` should also need an explicit switch besides the dev profile is open: backlog #0-77.
  - A suspended tenant's work that came due before a service could see the suspension (its status cache, up to
    10 s) has already gone; the pause covers everything after. The end of a pause is when the sync sees the
    resumption (up to about 20 s late), which lengthens a stopped escalation timer by as much: backlog #0-82. The sync
    asks auth-service once per tenant with waiting work, in every pausing service, every 10 s, and a long-paused
    tenant's backlog is re-read on each poll: fine now, a limit at thousands of tenants: backlog #0-102.
  - While auth-service is down, a service that has never had an answer for a tenant (after its own restart: every
    tenant) runs that tenant's background work, even if it is suspended in full: the per-row check fails open like
    the filter, and the sync records nothing it was not told (counted `tenant.pause.unconfirmed`, alerted
    `TenantStatusLookupFailing`); a tenant it knew to be paused stays paused: backlog #0-82.
  - A Slack ACK refused for suspension (a path with no button until #0-35) would be counted (`slack.ack.refused`)
    but the Slack user not told; like the status filter it fails open for a tenant never answered for while
    auth-service is down: backlog #0-82.
  - Outside auth-service a suspension takes up to 10 s (the status cache; the pause of its background work, up to
    about 20 s, is below), and during an auth-service outage a
    service gives full access to a tenant it never had a status for, e.g. every tenant after its own restart
    (fail-open by decision, alerted `TenantStatusLookupFailing`); a tenant resumed during the outage stays refused
    there until auth-service answers: backlog #0-82.
  - The bound on sign-ins refused for suspension (a few per user, then 429 without an audit event) lives in Redis
    and fails open like the other Redis limits: while Redis is down every refusal is audited, so a user replaying a
    refused invite or reset link can grow the tenant's audit trail; parallel refusals can also overshoot the bound a
    little (not atomic). Accepted: backlog #0-82.
  - A suspended tenant's live WebSocket session on an instance that has not cached its status yet stays open until
    the next sweeps (up to about 20 s); STOMP never waits on auth-service: backlog #0-82.
  - A tenant cannot be offboarded: its data stays in all seven services until someone edits the databases:
    backlog #0-101.
  - Operator MFA enrolment is not bound to the invite: an owner who misses the 24 h "MFA enabled" email, or whose
    mailbox the password thief also controls, does not stop the thief's factor: backlog #0-87.
  - Logs are collected only in docker-compose; Kubernetes has no log collection, and no Prometheus, Alertmanager
    or Grafana either: backlog #0-106. Nothing alerts on what a line says, nor on one service (or all seven) going
    silent: `LogsNotFlowing` fires only when no line at all arrives, and the proxy's own lines keep it quiet
    (#0-107). Whoever can log in to Grafana
    reads every tenant's lines (there is no access per tenant; locally Grafana is on `127.0.0.1` with a password of
    the developer's own); whoever controls Alloy can read every container's environment (secrets included) and
    files (archive, export) through the
    socket proxy, which cannot narrow `/containers` further (#0-94 step 2). One tenant's lines cannot be deleted
    before the 15 days are up (one Loki org, no tenant label): offboarding, #0-101. No trace id links one operation's
    lines across services (#0-94 step 3). Since step 1 they are JSON with
    every value escaped, so a value from outside can no longer split or forge a line; a service would refuse to
    start otherwise, unless a deployment outside this repository sets `PLATFORM_LOGGING_PLAINTEXT` on purpose
    (logged as a warning at every start). auth-service's break-glass command logs JSON too.
    An exception's message still reaches the log as the library wrote it (`error.message`,
    `error.stack_trace`): escaped, not filtered (backlog #0-188).
  - The MFA recovery of a customer tenant's only admin (#0-90) verifies the person by procedure only: the platform
    holds no contact of the tenant independent of the admin's own mailbox, and checks no DNS record itself:
    backlog #0-98. Whoever holds the admin's mailbox can cancel every such recovery, and whoever holds the
    admin's session can add a second admin, after which the platform keeps out; both page the operator and
    are left to a person (accepted; the operator's lever is suspending the tenant in full, #0-82).
  - The public token endpoints (`reset-password`, `accept-invite`, `mfa-recovery/cancel`) have no request limit:
    a token is 32 random bytes, single-use, so guessing is out of reach, but an unauthenticated flood still costs a
    lookup and a log line each: backlog #0-99.
  - A tenant id with data in other services but no data in auth-service can be provisioned, and its admin would
    see that data; the operator guide says to check first: backlog #0-85.
- **Project**
  - No `SECURITY.md`, no private vulnerability reporting, no Dependabot alerts: backlog #0-74.
- **Local stack**
  - Every port docker-compose publishes, except Grafana's (on `127.0.0.1` only; Loki, Alloy and the socket proxy
    publish none), is on all interfaces, Postgres included, where the admin is a
    superuser with the password from `docker/.env` (the template's is a known dev value): backlog #0-72. That
    includes Prometheus, unauthenticated with `--web.enable-lifecycle` (anyone can make it reload or quit); since
    #0-94 step 2 it is also on the `logs` network, where it only scrapes, so it must not get the admin API or a
    remote-write or federation path that would carry what it reaches there.

---

## Observability

### Metrics — Micrometer + Prometheus + Grafana

All services expose metrics via `/actuator/prometheus` on the management port (8091–8097), and the bundled `docker/prometheus.yml` has one scrape job per service — including auth-service on 8097. Prometheus scrapes every 15 seconds. Grafana dashboards cover:

- HTTP request rate and error rate per service
- JVM heap, non-heap memory, GC activity
- Rate limit rejections per tenant and per IP
- Kafka consumer lag per consumer group (via `kafka-exporter` — `KafkaConsumerLagHigh` and `KafkaConsumerLagCritical` alert rules)

Prometheus, Alertmanager, Grafana and `kafka-exporter` are included in `docker-compose.yml`. See [Running Locally](#running-locally) for startup order — the monitoring stack requires a pre-generated Alertmanager token.

### Distributed Tracing Context

Every log line is one JSON object in Elastic Common Schema (backlog #0-94), with the MDC context as fields:

```json
{"@timestamp":"2026-10-08T09:17:32.411Z","log":{"level":"INFO","logger":"com.incidentplatform.incident.service.IncidentCommandService"},"service":{"name":"incident-service"},"message":"Incident created: id=3f669983","tenantId":"test-tenant","requestId":"e87b7a28-...","userId":"11111111-...","ecs":{"version":"8.11"}}
```

Filter by field (`tenantId`, `requestId`, `userId`, `kafkaMessageId`, `service.name`, `log.level`) in any log store that reads JSON (Loki, ELK, CloudWatch). `requestId` is per service for now; a trace id that follows one operation across services is #0-94's step 3. Locally, `spring-boot:run` can print plain text instead (README "Step 2").

### Logs — Alloy + Loki + Grafana

In docker-compose, Alloy collects the output of every container named `incident-*` and sends it to Loki (backlog #0-94, step 2), where it is kept for 15 days. To read the logs, open Grafana → Explore → **Loki**:

```logql
{service="incident-service"}                            # one service (the compose service name)
{service=~".+-service", level="ERROR"}                  # every platform service's errors
{service=~".+-service"} | tenantId="acme"               # one tenant's lines (structured metadata)
{service=~".+-service"} | requestId="e87b7a28-..."      # one request
{service="notification-service"} | json | message=~"(?i).*slack.*"
```

`tenantId` and the other identifiers are what the line says, not authenticated facts: a service's own log lines are trustworthy because they go through the platform's encoder, but anything a service writes raw to stdout (a library's println) could carry a `tenantId` of its own. Treat them as a search aid, not as evidence of which tenant did what; that is the audit log's job.

The labels are `service`, `container` and `level` (only the seven services' lines are parsed for a level). `tenantId`, `requestId`, `userId` and `kafkaMessageId` are structured metadata, so a filter on them follows `|`. Lines that are not JSON (Postgres, Kafka, Redis) are kept as they are. A service started with `spring-boot:run` is not a container, so its lines stay in its terminal. Alloy reads the Docker API through `docker-socket-proxy`, which permits only GET on containers and networks. Loki and Alloy publish no port and are on an internal `logs` network with only Grafana and Prometheus; Loki's delete API is off. Prometheus scrapes both, for the `LogPipelineDown`, `LogPipelineRestarting`, `LogPipelineNotScraped`, `LogsNotFlowing`, `LogDiscoveryFailing` and `LogsDropped` alerts.

### Management Port Isolation

Health and metrics endpoints run on a dedicated port per service, never mixed with the business API:

| Service | API Port | Management Port |
|---|---|---|
| auth-service | 8087 | 8097 |
| ingestion-service | 8081 | 8091 |
| incident-service | 8082 | 8092 |
| notification-service | 8083 | 8093 |
| escalation-service | 8084 | 8094 |
| postmortem-service | 8085 | 8095 |
| oncall-service | 8086 | 8096 |

---

## CI/CD

GitHub Actions pipeline runs on every push and pull request to `main`.

A new push to a pull request cancels that PR's CI and Factory guards runs still in progress (backlog #0-231):
their result is stale and each started job is billed by the minute. A push to `main` is never cancelled,
neither running nor pending: each one takes a concurrency group of its own, since main-guard and the autopilot's
preflight read every push's own run (#0-148).

### Job 1 — Build, Test & Coverage

Runs on every push to `main`, and on every PR that changes more than Markdown (a PR touching only `.md`
files — the backlog, `/ready`, runbooks — skips it, and the smoke test too: nothing the build, its tests or
its check scripts read is Markdown; skipped at the job, so it still counts as passed for a required check):

```
Checkout → Java 21 setup (Temurin) → Restore the Maven caches → (on a miss of the distribution) Check its checksum → Compile → Run tests with JaCoCo → No jar holds a local config → Upload the service jars → (main) Save the Maven caches → Upload coverage reports → (PR) coverage summary → (PR) changed-lines coverage gate
```

- Compiles all 7 modules and runs the full test suite
- The only build of the code in CI (backlog #0-141, ADR-0030): the jars `verify` tested are uploaded as the `service-jars` artifact (1 day, uncompressed: a jar is a zip already; only when Job 4 will run), and Job 4 packages exactly those jars into the images
- Maven repository cache (backlog #0-141): restored from the newest entry of the month even when the POMs changed, so a dependency bump downloads only what is new (setup-java's own cache restores only an exact match, so every Renovate PR downloaded the whole tree again); saved on a push to `main` only, so pull requests (and the Snyk and OWASP workflows, which restore it by the same key) share main's entry instead of each storing its own
- Both Maven caches are restored through `.github/actions/restore-maven-caches` (here and in the Snyk and OWASP workflows) and saved through `save-maven-caches` (here, on `main`), the only place their paths and keys are written; `check-maven-caches.rb` (after its own cases) refuses any other cache of `~/.m2`, `~/.m2/wrapper` with another path or with `restore-keys`, a save to another path than the restore's, and a distribution key that stops hashing what decides the check (backlog #0-145)
- Maven distribution (backlog #0-142, ADR-0031): pinned by `distributionSha256Sum`; on a miss of its own exact-key cache, `check-maven-wrapper-sum.sh` (after its own cases, which run every time) checks the sum against Apache's SHA-512 before `./mvnw` downloads the zip and checks it again; saved on a push to `main` only, and kept out of the repository cache, whose prefix restore would bring back a distribution mvnw never checks
- `.mvn/maven.config` makes every `./mvnw` retry a 429, 500, 502, 503 or 504 from the repository (the resolver retries only 429 and 503 by default; on 2026-10-15 one 502 from Maven Central failed four runs)
- No jar holds a developer's `application-local.*` or `application-secrets.*` (backlog #0-100): CI plants both in every module, and `check-no-local-config-in-jars.sh` (after its own cases) fails if a service jar, or the `shared` jar nested in it, packaged one, or cannot be read
- JaCoCo coverage reports uploaded as artifacts (retained 14 days)
- Coverage gate in the build: **60%** line coverage per module (`jacoco:check`)
- On pull requests: at least **60%** of the changed Java lines must be covered (`diff-cover`); the uncovered lines are listed in the job summary
- On pull requests: JaCoCo per-file coverage breakdown in the job summary (informational)

### Job 2 — Detect Changes

A path filter (`dorny/paths-filter`) decides what the expensive downstream jobs must do:

- **`services`** — which services changed. A change to `shared/**`, `service-parent/**` or the root `pom.xml` lists all 7, and so does every push to `main`. The smoke test (Job 4) runs when it is not empty. Until backlog #0-141 it was also the matrix of a job that built each changed service's image on its own runner; the smoke test builds all 7 from the same jars, so that job was removed.
- **`infra`** — whether anything changed that could break the compose stack (`docker/**`, Dockerfiles, `.dockerignore`, `k8s/**`, `application*.yml`, the root `pom.xml` and each service's `pom.xml`).

### Job 3 — Validate Kubernetes Manifests

Always runs. Renders `k8s/base` and the `dev`, `staging` and `prod` overlays with `kubectl kustomize` and validates each rendered output with `kubeconform -strict` against the API schemas of the Kubernetes version pinned in the job (`KUBERNETES_VERSION`, also the kubectl that renders), from a pinned commit of the schema repository; kubeconform itself is a pinned release, checked against its SHA-256 before it runs (backlog #0-76). It also cross-checks that every service directory with a `Dockerfile` has a matching Deployment in the rendered base, that staging and prod set no Spring profile (backlog #0-63), that mail is caught by Mailpit in dev only (`check-k8s-mail.rb`, backlog #0-42), and that each overlay renders into its own namespace, with no prod image untagged or `latest`, and prod's services on a release tag rather than an environment's name (`check-k8s-environments.rb`, backlog #0-29; tags stay mutable until #0-71).

### Job 4 — Docker Compose Smoke Test

Builds the 7 images and boots them with PostgreSQL, Redis, Kafka and the log pipeline (docker-socket-proxy, Loki, Alloy) through `docker compose up`, curls each service's health endpoint, checks that auth-service's break-glass command still reaches `main` through the image's entrypoint (run without options, it must refuse with exit 1), checks the services' DB role, and checks that every service's lines reach Loki parsed (`.github/scripts/test-log-collection.sh`, backlog #0-94). Runs on every push to `main`, and on pull requests when `infra` changed or any service directory changed, unless the pull request changes Markdown only.

The one place in CI where images are built (backlog #0-141, ADR-0030), from Job 1's jars: the `service-jars` artifact is put back into each `<service>/target/`, and each Dockerfile only packages that jar, extracted into Spring Boot's layers (`jarmode=tools extract --layers`). So the job boots exactly what the tests ran against, and neither compiles nor downloads from Maven Central. It therefore starts once Job 1 is green, and does not run when Job 1 failed. The images are not pushed — no registry configured yet (next step: GitHub Container Registry, backlog #0-71; the image tested here is then the one to push).

### Job 5 — Lint Workflows

Always runs (seconds). First the pinned CI tools themselves: the tests of `install-pinned-tool.sh` and
`check-pinned-tools.sh`, then every tool pin in every workflow checked against its publisher (backlog #0-147,
ADR-0033). Then actionlint, with shellcheck for every workflow `run:` block, on every `.github/workflows/*.yml` and on
how they call the local actions in `.github/actions/`, one `::error` annotation per finding (backlog #0-146,
ADR-0032); shellcheck, the same binary, on every tracked `.sh` file and the composite actions' steps, every severity
(backlog #0-149, `check-shell.rb`); no download in a `run:` block outside `install-pinned-tool.sh` (backlog #0-149,
`check-downloads.rb`); each checker's own cases run first; and zizmor's security audit of the same files and the
actions, one annotation per finding not suppressed with its reason (backlog #0-147). Last, GitHub's ruleset of
`main`, the environments, repository settings and admins, and every secret a job reads, against `.github/repository-settings/` (`main`'s copy, on a PR that does
not change it), and every required check against the jobs that report one (backlog #0-113, ADR-0034,
`repository-settings.rb check`).

### Job 6 — Secret Scan

Always runs (seconds). Installs the pinned betterleaks (backlog #0-109, ADR-0036), runs the cases of
`secret-scan.sh` with it, then the scan: every commit from the pull request's base to its head, or from a push's
previous `main` to the new one, with betterleaks' default rules (no config or ignore file of the repository is
read: the script fails on one). One `::error` annotation per finding (rule, file, line, commit), never the value;
a line that holds no secret says so with `gitleaks:allow` and its reason. A required check of `main`.

### Security Scanning

Two dedicated workflows run independently from the main CI pipeline — security scans are slow
(NVD database download takes 2–15 minutes) and should not block every feature build.

**OWASP Dependency-Check** (`.github/workflows/owasp-dependency-check.yml`):

```
Checkout → Java 21 setup → Run dependency-check:aggregate → Upload HTML report as artifact
```

- Compares all Maven dependencies against the NVD CVE database
- Fails the build when any dependency has a CVSS score >= 7.0 (High or Critical)
- HTML report uploaded as artifact (retained 30 days) — downloadable from the Actions run
- Runs every Monday at 08:00 and on every `pom.xml` change merged to `main`
- Known CVEs that cannot be fixed (false positives or awaiting upstream release) are
  documented in `owasp-suppressions.xml` with a verdict, justification, and expiry date

**Snyk** (`.github/workflows/snyk.yml`):

```
Job A: Dependency scan → SARIF upload to GitHub Security tab
Job B: Code scan (SAST) → SARIF upload to GitHub Security tab (not running, backlog #0-68)
```

- **Dependency scan**: scans `pom.xml` against Snyk vulnerability database — adds fix
  suggestions and exploit maturity data on top of OWASP
- **Code scan (SAST)**: static analysis of Java source code for security issues —
  SQL injection, XXE, path traversal, insecure deserialization, hardcoded secrets
  — **not running yet**: every run ends in `403 Snyk Code is not enabled`, hidden by
  `continue-on-error`, so no SAST result has ever been produced (backlog #0-68)
- Results visible in **Security → Code scanning alerts** in GitHub without opening CI logs
- Dependency scan failures fail the workflow, but it is red on every run today, so a new finding changes
  nothing (backlog #0-69), and no check is required to merge (backlog #0-2); SAST findings are reported as
  alerts only (manual review required before enforcing)
- Unfixable CVEs documented in `.snyk` with reason and expiry date
- The CLI is a pinned standalone binary, checksum-verified before it runs, and the token reaches
  only the scan step (backlog #0-61, see [Infrastructure Hardening](#infrastructure-hardening))

Required secrets, in the environment `scans` (Settings → Environments; never repository secrets, ADR-0035):
`SNYK_TOKEN`, `NVD_API_KEY` (optional — speeds NVD download from ~15 min to ~2 min; the plugin reads it from the
environment variable, never a property, backlog #0-150).

### Dependency Updates — Renovate

Renovate Bot monitors `pom.xml`, Dockerfiles and GitHub Actions workflows and opens pull
requests automatically when newer versions are available.

Key configuration (`renovate.json`):

- **Schedule**: every weekend — avoids noise during the work week. It limits when Renovate *creates* a branch;
  an open PR is still updated at any time (`updateNotScheduled` defaults to `true`)
- **`rebaseWhen: conflicted`** (backlog #0-230): an open PR is rebased only when it conflicts with `main`, not
  every time `main` moves. Until 2026-11-12 it was `behind-base-branch`: every merge rebased every open Renovate PR
  and ran its full CI, 58% of the repository's Actions minutes (~8 200 of ~14 100 a month, measured over 18 days).
  A PR's CI result can therefore be older than `main`: before merging one, tick its rebase checkbox (or add the
  `rebase` label) and wait for the new run; `main`'s own CI checks the merge result either way (the ruleset does
  not require an up-to-date branch)
- **Major updates need approval** (backlog #0-230): no branch or PR until the update is ticked in the
  Dependency Dashboard issue. A major moves in compose, the tests and k8s at once, on a branch of our own
  (backlog #0-71), so the dashboard is the list of image majors still to do; a ticked major of a GitHub Action or
  a CI tool comes as an ordinary Renovate PR, merged on its own CI. `vulnerabilityAlerts` sets
  `dependencyDashboardApproval: false` so that a security fix is not held, but Renovate's docs do not say whether
  it wins over the major rule: a CVE whose only fix is a new major may wait in the dashboard (still reported by
  Snyk and OWASP Dependency-Check; #0-230 records the first case)
- **`minimumReleaseAge: 3 days`**: skips releases yanked within 72 hours
- **Spring Framework / Spring Boot**: grouped into one PR, 7-day delay — gives time for
  community reports before updating a core dependency
- **Google Cloud SDK**: 14-day delay — large SDK, higher risk on major updates
- **Vulnerability alerts**: when a CVE is published for any dependency, Renovate opens
  a PR immediately regardless of schedule (except, possibly, a fix that needs a new major: see "Major updates need
  approval" above)
- **Major updates**: always labelled `major-update`, never auto-merged, opened only after approval (above)
- **GitHub Actions** (`helpers:pinGitHubActionDigests`): keeps every `uses:` pinned to a commit SHA
  and updates the SHA and its `# vX.Y.Z` comment together; all action updates are grouped into one
  PR (backlog #0-60)
- **CI tools** (a `customManagers` regex, backlog #0-147): each tool pinned in a workflow's `env` under a
  `# renovate:` comment gets its own PR, 7 days after its release, with the tag and the SHA-256 changed together
  (datasource `github-release-attachments`); the PR is trusted only once Lint Workflows' `check-pinned-tools.sh`
  passes

Setup: install the Renovate GitHub App at https://github.com/apps/renovate and authorize
it for this repository. Renovate will open a "Configure Renovate" PR to confirm the setup.

### Pipeline Hardening

Token scopes, pinned actions and tools, repository settings: see
[Infrastructure Hardening](#infrastructure-hardening).

### Pipeline Status

The CI badge at the top of this README reflects the current status of the `main` branch pipeline.

---

## Running Locally

### Prerequisites

- Java 21
- Docker Desktop (minimum 4GB RAM allocated)
- `jq` — command-line JSON formatter (`brew install jq` on macOS)

### Step 1 — Start infrastructure

docker-compose needs `docker/.env`: `DB_PASSWORD`, `POSTGRES_ADMIN_PASSWORD` and `GRAFANA_ADMIN_PASSWORD` are
required, and compose refuses to start without them. The template's database values are for development only;
Grafana's is empty on purpose (it reads every tenant's logs, backlog #0-94), so set your own, at least 16
characters (`make dev-up` warns about a shorter one; compose itself refuses only an empty one).

```bash
cp docker/.env.example docker/.env      # once; Option B in Step 4 fills in the rest
openssl rand -base64 24                 # paste the output into docker/.env as GRAFANA_ADMIN_PASSWORD=<output>
                                        # (.env files do not run $(...): pasted as is, the text would be the password)
docker compose -f docker/docker-compose.yml up -d postgres redis kafka kafka-ui pgadmin
```

Wait until all containers are healthy:

```bash
docker compose -f docker/docker-compose.yml ps
```

Expected — all show `(healthy)` or `Up`:
```
incident-kafka      Up (healthy)
incident-postgres   Up (healthy)
incident-redis      Up (healthy)
```

On its first start (empty `postgres_data` volume), Postgres creates two roles: `postgres`, the superuser, for
administration only, and `incident_app`, the role every service connects as, which is not a superuser. Their
passwords come from `POSTGRES_ADMIN_PASSWORD` and `DB_PASSWORD` in `docker/.env`. A volume created before backlog
#0-78 still has a superuser `incident_app`, and its `docker/.env` has `POSTGRES_PASSWORD`, which `DB_PASSWORD`
replaced. To migrate it while keeping its data, or to start over, see
[docs/database-roles.md](docs/database-roles.md). Services run with `./mvnw spring-boot:run` (Option A) don't read
`docker/.env`; they need `spring.datasource.password` in `application-local.yml` (Step 2) or an exported
`DB_PASSWORD`, as `application.yml` has no default (backlog #0-66).

### Step 2 — Create application-local.yml for each service

Each service requires `src/main/resources/application-local.yml` — this file is excluded from git (contains secrets).

> **Important**: Use only standard ASCII hyphens (`-`) in YAML comments, not em dashes (`—`). Em dashes are multi-byte UTF-8 characters that prevent Spring Boot from loading the file.

**Create this file in all 7 services:**

```yaml
jwt:
  secret: local-development-secret-key-minimum-64-characters-long-absolutely-not-for-production-use-only

logging:
  structured:
    format:
      console: ""   # plain text locally; every deployment logs JSON (ECS), backlog #0-94
  level:
    com.incidentplatform: DEBUG

platform:
  logging:
    plain-text: true   # without it the service refuses to start with plain-text logs
```

**The six services that use the database** (all but ingestion-service) also need its password: there is
no default in `application.yml` (backlog #0-66). Use the same value as `DB_PASSWORD` in `docker/.env`.
If the file already has a `spring:` key (notification-service's mail settings), put `datasource:` under it
instead of adding a second `spring:`:

```yaml
spring:
  datasource:
    password: incident_secret   # = DB_PASSWORD in docker/.env
```

If a service stops at startup with `password authentication failed for user "incident_app"`, the password
is missing or wrong. Spring Boot does not report a missing value as such here, see
[docs/database-roles.md](docs/database-roles.md#a-missing-or-wrong-password).

**auth-service** additionally requires two encryption keys — one for MFA secrets, one for tenants' Slack bot tokens (separate on purpose, so one leaked key does not expose both; backlog #0-21). Each is 32 bytes, base64 (`openssl rand -base64 32`):

```yaml
jwt:
  secret: local-development-secret-key-minimum-64-characters-long-absolutely-not-for-production-use-only

mfa:
  encryption-key: dGVzdC1rZXktMzItYnl0ZXMtZm9yLWRldi1vbmx5ISE=

slack:
  encryption-key: bG9jYWwtc2xhY2sta2V5LWRldi1vbmx5LTMyYnl0ZSE=

logging:
  structured:
    format:
      console: ""   # plain text locally; every deployment logs JSON (ECS), backlog #0-94
  level:
    com.incidentplatform: DEBUG

platform:
  logging:
    plain-text: true   # without it the service refuses to start with plain-text logs
```

**incident-service** additionally needs WebSocket allowed origins:

```yaml
jwt:
  secret: local-development-secret-key-minimum-64-characters-long-absolutely-not-for-production-use-only

websocket:
  allowed-origins:
    - http://localhost:4200
    - http://localhost:3000

logging:
  structured:
    format:
      console: ""   # plain text locally; every deployment logs JSON (ECS), backlog #0-94
  level:
    com.incidentplatform: DEBUG

platform:
  logging:
    plain-text: true   # without it the service refuses to start with plain-text logs
```

**postmortem-service** additionally needs a Gemini API key:

```yaml
jwt:
  secret: local-development-secret-key-minimum-64-characters-long-absolutely-not-for-production-use-only

gemini:
  api-key: your-gemini-api-key-here

logging:
  structured:
    format:
      console: ""   # plain text locally; every deployment logs JSON (ECS), backlog #0-94
  level:
    com.incidentplatform: DEBUG

platform:
  logging:
    plain-text: true   # without it the service refuses to start with plain-text logs
```

Every service but auth-service reads from auth-service: each tenant's status (all six, backlog #0-82) and, in **notification-service**, each tenant's Slack workspace. `auth-service.base-url` defaults to `http://localhost:8087`, so nothing is needed locally unless auth-service runs elsewhere; then set it (or `AUTH_SERVICE_URL`) in every one of them:

```yaml
auth-service:
  base-url: http://localhost:8087
```

> The JWT secret must be at least 64 characters. The value above meets this requirement — copy it exactly.

### Step 3 — Build all modules

```bash
./mvnw clean install -DskipTests
```

The first `./mvnw` downloads Maven and refuses it unless its SHA-256 is the `distributionSha256Sum` in
`.mvn/wrapper/maven-wrapper.properties` (backlog #0-142). A Maven it unpacked before that sum existed is not
checked again; `rm -rf ~/.m2/wrapper/dists/apache-maven-*` once makes it download and check it.

### Step 4 — Start all services

#### Option A — Maven (development, hot reload)

```bash
# Terminal 1 — auth-service (users, teams, API keys, MFA)
./mvnw spring-boot:run -pl auth-service -Dspring-boot.run.profiles=local

# Terminal 2
./mvnw spring-boot:run -pl ingestion-service -Dspring-boot.run.profiles=local

# Terminal 3
./mvnw spring-boot:run -pl incident-service -Dspring-boot.run.profiles=local

# Terminal 4
./mvnw spring-boot:run -pl notification-service -Dspring-boot.run.profiles=local

# Terminal 5
./mvnw spring-boot:run -pl escalation-service -Dspring-boot.run.profiles=local

# Terminal 6
./mvnw spring-boot:run -pl postmortem-service -Dspring-boot.run.profiles=local

# Terminal 7
./mvnw spring-boot:run -pl oncall-service -Dspring-boot.run.profiles=local
```

#### Option B — Docker Compose (all services in containers)

```bash
cd docker
cp -n .env.example .env   # if Step 1 has not created it yet
# Edit .env — fill in JWT_SECRET, MFA_ENCRYPTION_KEY and SLACK_ENCRYPTION_KEY
# (DB_PASSWORD and POSTGRES_ADMIN_PASSWORD already have dev values;
# GRAFANA_ADMIN_PASSWORD is the one you set in Step 1):
#   JWT_SECRET=$(openssl rand -base64 64)
#   MFA_ENCRYPTION_KEY=$(openssl rand -base64 32)
#   SLACK_ENCRYPTION_KEY=$(openssl rand -base64 32)   # a different value
cd ..
make dev-up   # ./mvnw clean package -DskipTests, then docker compose up -d --build
```

> The service images package the jars Maven built in `<service>/target/` and compile nothing themselves
> (backlog #0-141): `make dev-up` builds the jars first and rebuilds the images from them. A plain
> `docker compose up --build` packages whatever jar is in `target/` (none fails the build, and so do two).

> **auth-service** requires `MFA_ENCRYPTION_KEY` and `SLACK_ENCRYPTION_KEY` — two different
> 32-byte base64 AES-256-GCM keys, for TOTP secrets and tenants' Slack bot tokens at rest. See `docker/.env.example` for all required variables.

> **Customer tenants**: no account and no customer tenant is seeded. A platform operator creates each one: accept
> the operator admin's invite and log in (Step 5, steps 2-3), enable MFA for that account and log in again with a
> code (the platform API requires a session that completed MFA; commands in the guide), then
> `POST /api/v1/platform/tenants` with
> `{"tenantId": "acme", "displayName": "Acme Corp", "adminEmail": "..."}`. The tenant's first admin gets an
> invite in Mailpit (http://localhost:8025) and accepts it with `POST /api/v1/auth/accept-invite`. Details:
> [docs/tenant-provisioning.md](docs/tenant-provisioning.md).

### Step 5 — (Optional) Start monitoring stack

The monitoring stack (Prometheus, Alertmanager, Grafana, kafka-exporter, the log pipeline
(docker-socket-proxy, Loki, Alloy), plus Mailpit and a heartbeat sink) watches the platform itself. Alertmanager sends the platform's own alerts three
ways (backlog #0-16, `docker/alertmanager.yml`):

- **Watchdog** (always firing) → a dead man's switch URL about every 2 minutes (the route sets
  1 minute, but Alertmanager only repeats on a `group_interval` tick after `repeat_interval` has
  passed, so in practice every other tick). Locally the `heartbeat-sink` container logs it; in a
  real deployment use a healthchecks.io / Dead Man's Snitch / Grafana IRM heartbeat, which pages
  when the pings stop — give it a period and grace time comfortably above 2 minutes (e.g. 5 min).
- **Critical platform alerts** → email to the operator (Mailpit locally), out of band, so they
  still arrive when ingestion-service, Kafka or notification-service is the thing that broke.
- **Everything** → ingestion-service, as incidents of the reserved `platform-operator` tenant.
  Alertmanager authenticates with that tenant's Integration API key, like any tenant's
  Alertmanager does.

Invite and password reset emails of every tenant ride out an SMTP outage (backlog #0-52). A request
only queues the email; auth-service creates the token when it sends it (only its hash is stored), so
the link is valid for its full lifetime — 7 days for an invite, 15 minutes for a reset — from the moment
it goes out. A failed send is retried after 1 min, 5 min, 30 min, 2 h and then every 6 h
(`INVITE_EMAIL_RETRY_BACKOFF`) until the request's own deadline (the same 7 days / 15 minutes after it was
made). When sends keep failing for 30 minutes with none succeeding, `AuthEmailDeliveryFailing` (critical)
fires; each email given up is reported by `AuthEmailPermanentlyFailed` (high) — resend the invite, or have
the user request a new reset. The same outbox sends the "two-factor authentication was enabled/disabled"
notices (backlog #0-83), the "an administrator reset your MFA" notice (#0-88) and one "API key created"
notice per key (#0-89): no token, no link, retried for at least 24 h (as long as the platform API's grace
period). An MFA_ENABLED notice that was never sent keeps that factor out of the platform API.

One-time setup (needs the services from Step 4 running). auth-service invites the operator
tenant's first admin about 30 s after startup when `OPERATOR_ADMIN_EMAIL` is set (`docker/.env` for
Option B, `platform.operator.bootstrap.admin-email` in auth-service's `application-local.yml` for
Option A). It then checks every hour until that admin has accepted, and sends a fresh invite if the
email permanently failed (e.g. SMTP was down) or the 7-day invite expired, so a lost invite needs
no restart and no database edit (backlog #0-49). While no admin can log in, auth-service reports
`platform_operator_admin_pending = 1` and `OperatorAdminNotActivated` fires after an hour. If the
tenant's users need a human (the log says so: e.g. `OPERATOR_ADMIN_EMAIL` was changed after the
first invite went to another address, which was never accepted), auth-service does not create a
second admin or delete anyone; remove the unaccepted user and the next check invites the
configured address:

```bash
# 1. Dead man's switch URL (local stand-in)
cp docker/deadmans-switch-url.example docker/secrets/deadmans-switch-url

# 2. Accept the operator admin's invite: open Mailpit (http://localhost:8025), copy the token from
#    the invite email, then set a password
curl -s -X POST http://localhost:8087/api/v1/auth/accept-invite \
  -H "Content-Type: application/json" \
  -d '{"token": "<invite token>", "password": "<password>"}'

# 3. Log in to the operator tenant
OP_LOGIN=$(curl -s -X POST http://localhost:8087/api/v1/auth/login \
  -H "X-Tenant-Id: platform-operator" -H "Content-Type: application/json" \
  -d '{"email": "ops@incident-platform.local", "password": "<password>"}')
OP_TOKEN=$(echo "$OP_LOGIN" | jq -r .accessToken)
OP_USER_ID=$(echo "$OP_LOGIN" | jq -r .userId)

# 4. Create the integration; its API key is shown once — store it as Alertmanager's secret
curl -s -X POST http://localhost:8087/api/v1/integrations \
  -H "Authorization: Bearer $OP_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "platform-alertmanager", "source": "prometheus"}' \
  | jq -r .apiKey | tr -d '\n' > docker/secrets/platform-operator-api-key

# 5. Put the operator admin on call (PRIMARY) for the operator tenant — see below
curl -s -X POST http://localhost:8086/api/v1/oncall/schedules \
  -H "Authorization: Bearer $OP_TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg u "$OP_USER_ID" '{userId: $u, userName: "Platform operator",
        email: "ops@incident-platform.local", role: "PRIMARY",
        startsAt: (now|todate), endsAt: ((now + 365*86400)|todate)}')"
```

Step 5 matters because the `platform-operator` tenant is an ordinary tenant for notifications:
an incident's content goes only to that tenant's on-call PRIMARY (backlog #0-18; the platform's
alerts carry no team, so the tenant-wide PRIMARY is used). Without an on-call entry every platform
incident is marked `UNDELIVERABLE`, and the operator only gets a content-free
"[PLATFORM] Notification undeliverable (NO_ONCALL)" email instead of the incident. The critical
alerts' direct email from Alertmanager does not depend on this. Renew or replace the entry before
`endsAt`, and in a real deployment schedule a rotation instead of one long entry.

Then start the monitoring stack:

```bash
docker compose -f docker/docker-compose.yml up -d alertmanager prometheus grafana kafka-exporter \
  docker-socket-proxy loki alloy
```

| Tool | URL | Credentials |
|---|---|---|
| Prometheus | http://localhost:9090 | — |
| Alertmanager | http://localhost:9093 | — |
| Grafana | http://localhost:3000 | admin / `GRAFANA_ADMIN_PASSWORD` |
| Mailpit (operator email, invites) | http://localhost:8025 | — |
| Heartbeat sink | `docker logs incident-heartbeat-sink` | — |
| Logs (Loki) | Grafana → Explore → Loki (no port of its own) | admin / `GRAFANA_ADMIN_PASSWORD` |

> Grafana's admin password is applied only when its `grafana_data` volume is first created. A volume from
> before backlog #0-94 step 2 still has `admin`: change it with
> `docker exec incident-grafana grafana cli admin reset-admin-password '<the value of GRAFANA_ADMIN_PASSWORD in docker/.env>'`.

> The monitoring stack is optional for local development — all 7 services run and process
> alerts without it.
>
> The key does not expire. To rotate it, create a new integration, overwrite
> `docker/secrets/platform-operator-api-key` (Alertmanager reads the file on every request, no
> restart), then delete the old integration. ingestion-service caches a key's validity for at most
> 60 s, so a revoked key stops working within a minute. If auth-service is down, ingest answers
> `503` + `Retry-After` and Alertmanager retries; a wrong or revoked key gets `401`, which it does
> not retry. A key of a tenant suspended read-only gets `503` + `Retry-After: 300` +
> `TENANT_READ_ONLY` (paused), one of a tenant suspended in full `403` + `TENANT_SUSPENDED`
> (backlog #0-82).

### Step 6 — Verify all services are up

```bash
for port in 8091 8092 8093 8094 8095 8096 8097; do
  echo -n "Port $port: "
  curl -s http://localhost:$port/actuator/health | jq -r .status
done
```

Expected:
```
Port 8091: UP
Port 8092: UP
Port 8093: UP
Port 8094: UP
Port 8095: UP
Port 8096: UP
Port 8097: UP
```

### Infrastructure URLs

| Tool | URL | Credentials |
|---|---|---|
| Kafka UI | http://localhost:8090 | — |
| pgAdmin | http://localhost:5050 | admin@incident.com / admin |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 (this machine only) | admin / `GRAFANA_ADMIN_PASSWORD` |

---

## Running on Kubernetes

> **Monitoring stack note**: Prometheus, Alertmanager, Grafana, kafka-exporter and the log
> pipeline (Loki, Alloy) are part of the `docker-compose.yml` setup only — they are not deployed
> in Kubernetes (backlog #0-106).
> In a production Kubernetes environment, monitoring is typically handled by a separate
> stack (e.g. `kube-prometheus-stack` via Helm), configured with the same routes as
> `docker/alertmanager.yml` and a `platform-operator` Integration API key as a Secret.

### Prerequisites

- Docker Desktop (minimum 6GB RAM allocated)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- `jq`

### Step 1 — Start Minikube

```bash
minikube start --cpus=4 --driver=docker
```

Verify the cluster is ready:

```bash
kubectl get nodes
# Expected: minikube   Ready   control-plane
```

### Step 2 — Point Docker to Minikube's daemon

```bash
eval $(minikube docker-env)
```

> Run this in every terminal where you build images. It affects only the current shell session.

### Step 3 — Build all Docker images

The images package the jars Maven builds (backlog #0-141), so build those first:

```bash
./mvnw clean package -DskipTests
for service in auth-service ingestion-service incident-service notification-service escalation-service postmortem-service oncall-service; do
  echo "Building $service..."
  docker build -t $service:dev -f $service/Dockerfile .
done
```

The first Maven build downloads all dependencies into `~/.m2` (once; later builds reuse it); the images themselves only package the jars, in seconds, and a change to the code alone rebuilds only each image's application layer.

Verify:
```bash
docker images | grep ":dev"
# Expected: 7 images listed
```

### Step 4 — Configure secrets

`k8s/overlays/dev/secrets.yml` contains base64-encoded values. The file ships with
placeholders — replace them with your own values before deploying.

**Required for basic operation** (incidents, escalation, audit log):

```bash
# JWT_SECRET — must be at least 64 characters
echo -n "local-development-secret-key-minimum-64-characters-long-not-for-production-k8s" | base64
```

**Required for AI postmortems** (postmortem-service):

```bash
# Get a free key at https://aistudio.google.com/
echo -n "your-gemini-api-key" | base64
```

**Required for Slack notifications** (notification-service):

```bash
# Create a Slack app at https://api.slack.com/apps
# Bot Token Scopes needed: chat:write, im:write
# The bot token is NOT a platform secret any more (backlog #0-21): each tenant
# admin installs their own via POST /api/v1/slack-workspace. Only the App's
# signing secret is platform-wide.
echo -n "your-slack-signing-secret" | base64
```

Replace the `data` values in `k8s/overlays/dev/secrets.yml` with your encoded output:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: incident-platform-dev
type: Opaque
data:
  JWT_SECRET: <base64-encoded-value>
  MFA_ENCRYPTION_KEY: <base64-encoded-value>    # auth-service — 32-byte AES-256-GCM key (the dev overlay ships a ready-made one)
  GEMINI_API_KEY: <base64-encoded-value>        # optional — postmortems disabled if missing
  SLACK_ENCRYPTION_KEY: <base64-encoded-value>  # auth-service — 32-byte AES-256-GCM key for tenants' Slack bot tokens, different from MFA_ENCRYPTION_KEY
  SLACK_SIGNING_SECRET: <base64-encoded-value>  # optional — Slack notifications disabled if missing
  DB_PASSWORD: <base64-encoded-value>           # password of incident_app, the services' DB role (backlog #0-78)
---
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-admin                        # the postgres superuser, for administration only
  namespace: incident-platform-dev
type: Opaque
data:
  username: <base64-encoded-value>              # postgres
  password: <base64-encoded-value>
```

Both database passwords are applied only when the PostgreSQL volume is first created. See
[docs/database-roles.md](docs/database-roles.md), including how to migrate a volume created before backlog #0-78.

> **Minimum setup**: only `JWT_SECRET` needs replacing to run the full incident lifecycle
> (ingestion → incident → escalation → audit log). Slack and Gemini are optional — the
> platform works without them, notifications fall back to logs.

### Step 5 — Deploy

```bash
kubectl apply -k k8s/overlays/dev
```

### Step 6 — Wait for all pods to be ready

```bash
kubectl get pods -n incident-platform-dev -w
```

Wait until all pods show `1/1 Running`. Init containers wait for PostgreSQL and Kafka — typically 2–5 minutes on first deploy. Press `Ctrl+C` when done.

Expected:
```
auth-service-xxx           1/1   Running   ...
escalation-service-xxx     1/1   Running   ...
incident-service-xxx       1/1   Running   ...
ingestion-service-xxx      1/1   Running   ...
kafka-0                    1/1   Running   ...
notification-service-xxx   1/1   Running   ...
oncall-service-xxx         1/1   Running   ...
postgresql-0               1/1   Running   ...
postmortem-service-xxx     1/1   Running   ...
redis-xxx                  1/1   Running   ...
```

### Step 7 — Configure local DNS

```bash
echo "127.0.0.1 incident-platform.local" | sudo tee -a /etc/hosts
```

### Step 8 — Start Minikube tunnel (keep this terminal open)

```bash
minikube tunnel
```

### Step 9 — Verify the cluster is reachable

```bash
curl -s -o /dev/null -w "%{http_code}" http://incident-platform.local/api/v1/incidents
# Expected: 403  (reachable — authentication required)
```

### Kubernetes Configuration Highlights

The `k8s/` directory uses **Kustomize** with environment overlays:

```
k8s/
├── base/               # Environment-agnostic manifests (Deployments, Services, HPA, PodDisruptionBudget, Ingress)
└── overlays/
    ├── dev/            # Minikube: 1 replica (HPAs at 1–1), 768Mi memory limit, relaxed probe delays (services only);
    │                   # Mailpit catches mail: kubectl -n incident-platform-dev port-forward svc/mailpit 8025
    ├── staging/
    └── prod/
```

Key features of the base configuration:

- **Rolling updates** — `maxUnavailable: 0`, `maxSurge: 1` — zero downtime deployments
- **Init containers** — each service waits for PostgreSQL and Kafka before starting
- **Health probes** — readiness and liveness on the management port (never the API port)
- **HorizontalPodAutoscaler** — CPU 70% and memory 80% targets; 1–3 replicas for auth, ingestion and incident-service, 1–2 for notification, escalation, postmortem and oncall-service. The HPAs own the replica counts: no Deployment sets `spec.replicas` (every `kubectl apply` would reset what the HPA scaled to), and each overlay patches `minReplicas`/`maxReplicas` instead (backlog #0-137, checked in CI by `check-k8s-environments.rb`):

  | Overlay | auth | incident | ingestion | notification, escalation, postmortem, oncall |
  |---|---|---|---|---|
  | dev | 1 | 1 | 1 | 1 |
  | staging | 1–3 | 2–3 | 2–3 | 1–2 |
  | prod | 2–3 | 3–5 | 3–5 | 2–2 |

  Prod never runs a service on one pod. The four at 2–2 gain availability, not throughput, from a second pod: for notification, escalation and postmortem one pod already consumes all three partitions of `incidents.lifecycle`, their `@Scheduled` jobs run on one pod at a time under ShedLock, and Slack, mail, SMS and Gemini set their pace; oncall-service serves HTTP only, to escalation and notification, so its load follows theirs. The ceilings bound the Postgres connections (backlog #0-79, `docs/database-roles.md`). The decision and the options it was chosen over: ADR-0028.
- **PodDisruptionBudget and spread over nodes** — each service has a budget of one pod (`maxUnavailable: 1`, `unhealthyPodEvictionPolicy: AlwaysAllow`, `k8s/base/<service>/pdb.yml`), so a node drain or a cluster upgrade moves its pods one at a time and never empties the floor above; a `minAvailable` at the floor would block every drain. Its pods spread over nodes (`topologySpreadConstraints` on `kubernetes.io/hostname`, `ScheduleAnyway`, so a one-node minikube still schedules), so one node failing takes at most part of the floor. Both in base, for every overlay (backlog #0-138, checked in CI by `check-k8s-environments.rb`, ADR-0029); zones wait for a known cluster (backlog #0-140).
- **ShedLock** — prevents duplicate scheduled job execution across replicas

---

## End-to-End Test

These steps work for both local and Kubernetes deployments. Replace the base URL as needed:
- **Local**: `http://localhost:808X`
- **Kubernetes**: `http://incident-platform.local`

### Step 1 — Generate a dev token

**Local:**
```bash
TOKEN=$(curl -s "http://localhost:8082/dev/token?tenantId=test-tenant" | jq -r .token)
echo "Token: ${TOKEN:0:50}..."
```

**Kubernetes** (dev overlay only: `/dev/token` exists only where the dev profile is set, backlog #0-63, and is intentionally not exposed via Ingress). Use port-forward to incident-service:
```bash
kubectl port-forward svc/incident-service 8082:8082 -n incident-platform-dev &
sleep 2
TOKEN=$(curl -s "http://localhost:8082/dev/token?tenantId=test-tenant" | jq -r .token)
echo "Token: ${TOKEN:0:50}..."
```

### Step 2 — Send a firing alert (simulating Prometheus/Alertmanager)

**Local:**
```bash
curl -s -X POST http://localhost:8081/api/v1/alerts/prometheus \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [{
      "status": "firing",
      "labels": {
        "alertname": "HighCPU",
        "severity": "critical",
        "instance": "server-01"
      },
      "annotations": {
        "summary": "CPU usage above 90%",
        "description": "Server server-01 CPU is at 95%"
      }
    }]
  }' | jq .
```

**Kubernetes:**
```bash
curl -s -X POST http://incident-platform.local/api/v1/alerts/prometheus \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [{
      "status": "firing",
      "labels": {
        "alertname": "HighCPU",
        "severity": "critical",
        "instance": "server-01"
      },
      "annotations": {
        "summary": "CPU usage above 90%",
        "description": "Server server-01 CPU is at 95%"
      }
    }]
  }' | jq .
```

Expected:
```json
{
  "received": 1,
  "processed": 1,
  "duplicates": 0,
  "fullySuccessful": true
}
```

### Step 3 — Verify the incident was created

**Local:**
```bash
curl -s http://localhost:8082/api/v1/incidents \
  -H "Authorization: Bearer $TOKEN" | jq '.content[]'
```

**Kubernetes** — the Ingress JWT_SECRET differs from the local secret. Generate a token via port-forward to get one signed by the cluster:
```bash
kubectl port-forward svc/incident-service 8082:8082 -n incident-platform-dev &
sleep 2
TOKEN_K8S=$(curl -s "http://localhost:8082/dev/token?tenantId=test-tenant" | jq -r .token)

curl -s http://incident-platform.local/api/v1/incidents \
  -H "Authorization: Bearer $TOKEN_K8S" | jq '.content[]'
```

Expected:
```json
{
  "id": "<incident-id>",
  "tenantId": "test-tenant",
  "status": "OPEN",
  "title": "CPU usage above 90%",
  "severity": "CRITICAL",
  "allowedTransitions": ["ACKNOWLEDGED"]
}
```

### Step 4 — Acknowledge the incident

```bash
INCIDENT_ID="<id from previous response>"

curl -s -X PATCH http://localhost:8082/api/v1/incidents/$INCIDENT_ID/status \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "ACKNOWLEDGED"}' | jq .
```

Expected:
```json
{
  "status": "ACKNOWLEDGED",
  "acknowledgedAt": "...",
  "mttaMinutes": 0,
  "allowedTransitions": ["RESOLVED"]
}
```

### Step 5 — Resolve the incident

```bash
curl -s -X PATCH http://localhost:8082/api/v1/incidents/$INCIDENT_ID/status \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "RESOLVED"}' | jq .
```

Expected:
```json
{
  "status": "RESOLVED",
  "resolvedAt": "...",
  "mttaMinutes": 0,
  "mttrMinutes": 1,
  "allowedTransitions": ["CLOSED"]
}
```

After resolving, `postmortem-service` automatically calls the Gemini API and generates a draft. Retrieve it with:

```bash
curl -s http://localhost:8085/api/v1/postmortems/incident/$INCIDENT_ID \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Step 6 — Check the audit log

```bash
curl -s http://localhost:8082/api/v1/incidents/$INCIDENT_ID/audit \
  -H "Authorization: Bearer $TOKEN" | jq '.[]'
```

Shows the full chronological timeline of every event across all services for this incident — created, acknowledged, resolved, notifications sent, postmortem generated.

### Step 7 — (Optional) Register an on-call schedule

For notifications and escalations to reach the right person:

```bash
curl -s -X POST http://localhost:8086/api/v1/oncall/schedules \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "11111111-1111-1111-1111-111111111111",
    "userName": "Jan Kowalski",
    "email": "jan@example.com",
    "slackUserId": "U0123456789",
    "role": "PRIMARY",
    "startsAt": "2026-01-01T00:00:00Z",
    "endsAt": "2026-12-31T23:59:59Z"
  }' | jq .
```

---

## Makefile commands

```bash
make dev-up          # Build the jars (make build), then start the whole docker-compose stack (infra, monitoring, log pipeline, services, rebuilt from those jars); needs Java 21 and the three passwords in docker/.env
make dev-down        # Stop all containers
make dev-reset       # Stop + remove volumes (clean database)
make grafana-password-check # Warn if GRAFANA_ADMIN_PASSWORD is under 16 characters, or Grafana still accepts admin/admin (a volume from before it); runs at the end of dev-up
make build           # Build all modules (skip tests)
make test            # Run all tests
make run-ingestion   # Start ingestion-service locally (profile=local)
make run-incident    # Start incident-service locally
make run-escalation  # Start escalation-service locally
make run-notification # Start notification-service locally
make run-postmortem  # Start postmortem-service locally
```

There is no `make` target for auth-service or oncall-service — start those with
`./mvnw spring-boot:run -pl auth-service -Dspring-boot.run.profiles=local` (or `oncall-service`).

---

## Running Tests

```bash
# All modules
./mvnw test -pl shared,auth-service,ingestion-service,incident-service,notification-service,escalation-service,postmortem-service,oncall-service

# Single module
./mvnw test -pl incident-service
./mvnw test -pl auth-service
```

### Test Coverage Highlights

| Test class | What it covers |
|---|---|
| `IncidentFsmTest` | 25 parameterized cases — all allowed and forbidden state transitions |
| `IncidentTest` | `recordEscalation` raises the level and moves `updatedAt`; the same or a lower level read late changes neither (backlog #0-118) |
| `IncidentCommandServiceTest` | Deduplication, severity escalation, optimistic lock, FSM validation; the escalation level recorded in a transaction of its own (backlog #0-96), a level not higher is not saved (backlog #0-118) |
| `IncidentEscalationLevelIntegrationTest` (incident-service, Postgres) | `recordEscalationLevel` commits before it returns, a REST change committed between its read and commit is thrown from the call, another tenant's incident is untouched (backlog #0-96), a lower level read late neither lowers it nor writes the row (backlog #0-118) |
| `AlertIngestionServiceTest` (ingestion-service) | Dead-letter copies awaited together from the wait, none started after a failed one, the payload copied once, dedup keys released when a copy is not stored and kept when it is (backlog #0-96) |
| `AlertIngestionControllerSecurityTest` (ingestion-service) | Roles per endpoint; 503 with `Retry-After: 10` and `INGESTION_UNAVAILABLE` when a dead-letter copy is not stored (backlog #0-96) |
| `IncidentQueryServiceTest` | Filter routing (Specification vs simple query), tenant scoping |
| `IncidentKafkaConsumerTest` | Per-record tenant isolation, TenantContext cleanup in `finally`, no cross-tenant leaks; a failure handed to `DeadLetterPublisher`, never acknowledged by the consumer itself (backlog #0-96) |
| `NotificationServiceTest` | Orchestration, fault isolation between channels, idempotency; a failed send recorded and counted by its reason, never the provider's text (backlog #0-93) |
| `NotificationExceptionTest`, `EmailNotificationChannelTest`, `SlackNotificationChannelSendTest`, `SlackApiClientTest` (notification-service) | A failure's text built from its reason and a checked provider code only; mail failures classified from the shapes JavaMail produces (authentication, rejected or malformed address, connection, timeout, 4xx deferral); Slack's `ok:false` a failure with its code on both `chat.postMessage` and `chat.update`, a refused token apart (`SLACK_AUTH_FAILED`), an unreadable answer and HTTP statuses classified on the send path too, nothing of the body kept; a refused broadcast does not stop the on-call DM; a malformed address or a refusal counted as the tenant's only when it is the recipient's (backlog #0-93) |
| `NotificationRouterTest` | Routing for all 5 event types, escalation-target lookup with PRIMARY fallback, UNDELIVERABLE when nobody is on call or no channel has an address, skipped channels |
| `SlackApiClientResilienceTest` (notification-service) | Through Spring's proxy, from `SlackNotificationChannel.send()`: with `application.yml`'s own retry and breaker settings, the circuit breaker opened by 5xx and by timeouts, then failing at once without calling Slack (the ACK update too), never opened by a 401, a 429 or an `ok:false`, closed by a successful trial call and reopened by a failed one (backlog #0-104); a 5xx and a read timeout retried (3 attempts), then `SLACK_UNAVAILABLE` from the fallback; a body trickling in past the read timeout cut too; a redirect not followed (the request carries the bot token); a 401 and an `ok:false` not retried; the ACK update retried too (backlog #0-103: the send path used to bypass the proxy) |
| `NotificationChannelPropertiesTest` | Operator alert address validation, `min-interval` default and rejection of zero or negative values; the Slack timeouts' defaults and rejection of zero or negative ones (backlog #0-103) |
| `SlackResilienceConfigTest` (notification-service) | `application.yml`'s `slack` breaker, built by Resilience4j's auto-configuration: counts only network errors and 5xx and ignores what a tenant's workspace answers (4xx, 429, `ok:false`), its time-based window, threshold and open state, no health indicator; the retry does not retry an open breaker (backlog #0-104) |
| `NotificationSchedulerDefaultsTest` (notification-service) | `application.yml`'s processing budget, Slack timeouts and Slack retry (as Resilience4j's auto-configuration builds it from the file) together fit the scheduler's 4-minute lock, so the shipped defaults start (backlog #0-103) |
| `StructuredLoggingDefaultsTest`, `StructuredLoggingGuardTest` (shared) | Every service's logs on a real `SpringApplication`: ECS fields and the pinned MDC key set, a CR/LF from outside kept inside one line (message, argument, MDC value, exception), the log file in ECS too; a start refused for a format set in `application.yml`, by an argument, through `SPRING_APPLICATION_JSON` or by a Logback file of its own (each reason on its own in the guard test); plain text only with `platform.logging.plain-text` (backlog #0-94) |
| `AuditOutboxTest` (shared, Postgres) | Audit outbox SQL: written in the caller's transaction, due order of its index, the lock-free due check, batch mark-sent, retry by the database's clock, purge in chunks up to a cap, table name checked by the constructor (backlog #0-84) |
| `AuditOutboxRelayTest` (shared) | Relay: no lock without a due row, pipelined batches, per-row tenant, Kafka failures pause it while a refused record does not, mark failures logged, scrape-time gauges, capped purge, settings incl. the 45-character table name (backlog #0-84) |
| `AuditOutboxConfigurationTest` (shared) | `audit.outbox.table` turns the outbox and the publisher on (events to the table); without it there is no publisher, and a service injecting one does not start; it wires with Spring Boot's own Kafka and Jackson beans; a bad table name stops the startup (backlog #0-84) |
| `UnrecordedAuditEventsTest` (shared) | `audit.event.unrecorded` registered at zero for every declared event type, so `AuditEventUnrecorded` sees the first failure (backlog #0-84) |
| `AuditOutboxPersistenceIntegrationTest` (notification-, escalation-, postmortem-service, Postgres) | The service's outbox migration takes the shared SQL and joins the JPA transaction; through the real service: the `notification_log` row, the level-2 escalation task, the postmortem's FAILED mark each commit or roll back with its audit event, under the action's tenant (backlog #0-84) |
| `AuditTextTest` (shared) | Error text for an audit event: cut to 500 characters on one line (control characters and U+2028/U+2029 too), never inside a surrogate pair; an unexpected exception by its type only (backlog #0-84) |
| `TenantIdsTest`, `TenantRecordsTest` (shared) | The one tenant id format (slug), refused without quoting the value; every tenant record built with its header (backlog #0-91/#0-92) |
| `TenantKafkaRecordResolverTest` (shared) | A record's tenant is its payload's; a header must match it; missing, invalid and mismatched tenants refused, counted (registered at zero) and never quoted (backlog #0-92); `trustedTenantOrNull` neither throws nor counts (backlog #0-96) |
| `TenantKafkaProducerInterceptorTest` (shared) | The interceptor writes no header any more: it counts records without a valid one, except a dead-letter record marked as tenant-less (`TenantRecords.withoutTenant`); the topic name alone exempts nothing (backlog #0-91) |
| `TenantKafkaConsumerInterceptorTest`, `TenantKafkaRecordInterceptorTest` (shared) | Validation only on the poll thread (nothing dropped or rewritten); the MDC takes only a valid header (`_missing` / `_invalid` otherwise) and no metric is tagged with a record's value (backlog #0-92) |
| Tenant-id CHECK guard (every service's Postgres integration test) | Every table with a `tenant_id` carries the slug `CHECK`; a new table without one fails (backlog #0-92) |
| Tenant foreign-key guard (`AuthRepositoryIntegrationTest`), `TenantForeignKeysMigrationTest`, `UnrecordedTenantHandlerTest` (auth-service) | Every auth-service table with a tenant's data has a validated foreign key to `tenants`, named in `UnrecordedTenantHandler`; V31 records each orphaned id (one per table seeded) and names it in a warning, its keys already refuse a new orphan before V32 validates them, and a tenants row with data cannot be deleted; a write refused by one of them is 403, any other integrity error the shared 500 (backlog #0-82) |
| `PausedTenantsTest` (shared, Postgres) | The paused-tenants SQL: a new pause starting at the suspension's time from auth-service, an unchanged one and a change of mode that keeps its start; full access and a bad tenant id refused; a resumption commits the service's hook with the row's deletion or rolls both back (backlog #0-82) |
| `PausedTenantsSyncTest`, `TenantWorkGuardTest`, `PausedTenantsConfigurationTest` (shared) | Pause sync: paused tenants and tenants with work asked together in id order, each once, a cut-short run continued by the next (paused tenants rotate too); `tenant.pause.sync.runs` counts completed runs only; only auth-service's own answer pauses or resumes (`confirmedStateOf`), so an outage changes nothing; one tenant's failure isolated; budget and lock; the per-row check uses `accessOf` (re-asked when expired or never cached), not `knownAccessOf`, and a batch's tenants are prefetched in parallel, at most 8 at a time, waiting at most its limit and never failing the run; the pause takes auth-service's suspension time; a `tenant-pause.table` other than the service's query table stops startup; `tenant-pause.table` without a `PausableWork` fails startup (backlog #0-82) |
| `TenantStatusProviderTest`, `AuthServiceTenantStatusProviderTest` (shared) | `confirmedStateOf`: auth-service's answer with its suspension time (`since`, ISO-8601 on the wire, left out for full access), the last one kept through an outage, and empty (not the fail-open FULL) for a tenant never answered for (backlog #0-82) |
| `SlackActionServiceTest` (notification-service) | The ACK path (no button until #0-35) of a suspended tenant (read-only or full) is refused before any lookup, counted (`slack.ack.refused`, registered at zero); an active tenant's goes to incident-service; an invalid tenant id in the button value is ignored (backlog #0-82); an unexpected exception from one channel's update fails only that channel, the others are still updated (backlog #0-93) |
| `EscalationPauseIntegrationTest`, `NotificationPauseIntegrationTest`, `PostmortemPauseIntegrationTest` (Postgres) | Each scheduler query leaves a paused tenant out, even its oldest rows under a batch of one; the candidates; escalation timers moved on by the pause to the second (running at the suspension, started during it, due after it but before a late sync paused the tenant, due before it; never moved earlier), notification lookup windows restarted; the sync end to end in the JPA transaction (backlog #0-82) |
| Scheduler and relay batches (`IncidentEventOutboxSchedulerTest`, `NotificationSchedulerTest`, `EscalationSchedulerTest`, `PostmortemRetrySchedulerTest`, `AuthEmailSchedulerTest`, `AuditOutboxRelayTest`) | A row whose tenant id `TenantContext` refuses fails alone; the next row is processed (backlog #0-92) |
| `DeadLetterPublisherTest` (shared) | `publishAndWait` returns only once Kafka has the dead-letter copy; a failure, a timeout or a send that throws at once is thrown (backlog #0-84); a record carries a valid tenant in its header or none, and its reason on one line (backlog #0-91/#0-92); a consumed record is acknowledged only after its copy is stored, nacked when it is not (stack trace logged once); a transient failure nacked without a copy and dead-lettered after its deadline; an unexpected exception recorded by type only; payloads cut on a character boundary; copies awaited under one deadline; the poll-interval budget; the dead-letter template's short metadata block (backlog #0-96) |
| `DeadLetterPublisherKafkaIntegrationTest` (shared, Kafka) | On a real broker in `MANUAL_IMMEDIATE`: a record left unacknowledged is skipped by the next acknowledgement and never comes back (a sentinel record shows it, no clock wait); a nacked one does; `DeadLetterPublisher` retries a transient failure and dead-letters a poison pill before acknowledging (backlog #0-96) |
| `RecordRedeliveriesTest` (shared) | Since when the record at a partition's head has been failing, per consumer group; another offset replaces it; a settled record is forgotten (backlog #0-96) |
| `KafkaFailuresTest` (shared) | A database outage in every type Spring gives it (incl. `DataAccessResourceFailureException`, `CannotCreateTransactionException`) is transient, at any cause depth; a record's own fault is not (backlog #0-96); `reason` keeps a content-free platform message and names any other exception by type and place, never its message |
| `AuditPersistenceIntegrationTest` (incident-service, Postgres) | V12–V14: event-id dedup per tenant, the consumer's constraint names, the CONCURRENTLY index valid, the outbox joining the JPA transaction (backlog #0-84) |
| `AuditEventTypesTest` (shared) | Audit event type values equal their names, are unique and fit the column; `NOTIFICATION_UNDELIVERABLE` is distinct from `NOTIFICATION_FAILED` |
| `OperatorAlertServiceTest` | Content-free operator email, per tenant and reason rate limit, no email when unconfigured, a send failure never fails the caller |
| `IncidentEventConsumerTest` (notification-service) | Tenant from the payload, header required and equal (backlog #0-92), TenantContext lifecycle, escalation level/target parsing, dead-lettering of invalid levels; a database outage nacked, an unexpected exception dead-lettered, a record without `X-Event-Type` dead-lettered (backlog #0-96) |
| `NotificationEscalationSchemaIntegrationTest` | V5/V6 migrations, `ddl-auto: validate`, tenant- and level-aware unique index and CHECK constraints, UNDELIVERABLE status and the first-lookup-failure column (Testcontainers, needs Docker) |
| `EscalationServiceTest` | Level 1/2 scheduling, ACK cancellation, idempotency, severity timeouts |
| `EscalationSchedulerTest` | Timer logic, level 2 scheduling after level 1, fault isolation (a task with an invalid tenant id fails alone, backlog #0-92); a suspended tenant's task held back untouched, the batch's tenants prefetched first, within the processing budget, a processing budget that stops a run before its ShedLock ends, refused at startup when too long (backlog #0-82) |
| `IncidentEventConsumerTest` (escalation-service) | Per-record tenant isolation, sequential records without leaks, a record without `X-Tenant-Id` dead-lettered (backlog #0-92); a database outage nacked, not dead-lettered; a record without `X-Event-Type` dead-lettered (backlog #0-96) |
| `PostmortemServiceTest` | Generation, Gemini failure handling, CRUD, audit event publishing |
| `PostmortemRetrySchedulerTest` | Retry logic for FAILED postmortems, max retry limit; what a failure records: a fixed text for Gemini, the type for anything else, never a message (backlog #0-84); a suspended tenant's postmortems held back on both paths, each batch's tenants prefetched first, within a processing budget per run, refused at startup when longer than its lock (backlog #0-82) |
| `AuditEventConsumerTest` (incident-service) | Audit events stored per record's tenant; duplicates by event id or offset; unstorable records dead-lettered, counted (counters registered at zero) and acknowledged only once Kafka has the copy (backlog #0-84); a failed save nacked when transient, rejected as `unexpected` otherwise (backlog #0-96) |
| `IncidentEventConsumerTest` (postmortem-service) | Tenant from the payload, header required and equal (a missing or mismatched header is dead-lettered), ignored event types; a database outage nacked, not dead-lettered; a record without `X-Event-Type` dead-lettered (backlog #0-96) |
| `JwtUtilsTest` | Token generation, validation, expiry, secret length validation; no token issued for a tenant id that is not a slug (backlog #0-92) |
| `TenantContextTest` | ThreadLocal isolation between threads, TenantAwareTaskDecorator propagation; an invalid tenant id refused before it reaches the MDC (backlog #0-92) |
| `OncallScheduleServiceTest` | Schedule creation, overlap detection, current on-call resolution |

---

## Project Structure

```
incident-platform/
├── shared/                        # Shared library (jar, not a runnable service)
│   └── src/main/java/
│       ├── audit/                 # AuditEventPublisher, AuditEventKafkaSender, AuditEventTypes, AuditOutbox + AuditOutboxRelay
│       ├── domain/                # Severity
│       ├── dto/                   # Shared DTOs: ErrorResponse, PagedResponse, AuditEventMessage
│       ├── events/                # Kafka event records: IncidentOpenedEvent, IncidentEscalatedEvent, ...
│       ├── exception/             # GlobalExceptionHandler, BusinessException, ResourceNotFoundException
│       ├── kafka/                 # TenantKafkaProducerInterceptor, TenantKafkaConsumerInterceptor,
│       │                          # TenantKafkaRecordResolver, TenantRecords, TenantResolutionException,
│       │                          # DeadLetterPublisher, DeadLetterNotStoredException, KafkaFailures,
│       │                          # RecordRedeliveries, UnreadableRecordException
│       ├── pause/                 # PausedTenants, PausedTenantsSync, PausableWork, TenantWorkGuard (+ prefetch),
│       │                          # PausedTenantsConfiguration (startup check of the table), PausedTenantsProperties
│       │                          # (suspended tenants' background work paused, #0-82 step 2b)
│       └── security/              # JwtUtils, JwtAuthFilter, TenantContext, TenantIds, InvalidTenantIdException,
│                                  # TenantAwareTaskDecorator, ServiceTokenProvider,
│                                  # TenantStatusFilter + TenantStatusProvider (tenant suspension, #0-82),
│                                  # AuthServiceTenantStatusProvider + TenantStatusResponse (status from auth-service),
│                                  # TenantAccessState (access + suspension time, step 2b)
│
├── auth-service/                  # port 8087 — identity and access management
│   └── src/main/java/
│       ├── api/                   # AuthController, UserController, TeamController,
│       │                          # ApiKeyController, IntegrationController, TenantSettingsController,
│       │                          # PlatformTenantController (operator tenant provisioning),
│       │                          # PlatformMfaRecoveryController, MfaRecoveryCancelController (#0-90)
│       ├── bootstrap/             # OperatorTenantBootstrap, TenantAdminReconciler
│       ├── config/                # SecurityConfig, PlatformAccess, PlatformAccessDeniedHandler,
│       │                          # MfaRecoveryProperties
│       ├── scheduler/             # AuthEmailScheduler, AuthTokenCleanupScheduler, MfaRecoveryScheduler
│       ├── ratelimit/             # BruteForceProtectionService, PlatformRateLimiter (+ Config)
│       ├── service/               # AuthService, UserService, TeamService, MfaService,
│       │                          # ApiKeyService, IntegrationService, TenantSettingsService
│       │                          # AuthTokenService, InviteService, ForgotPasswordService,
│       │                          # TenantProvisioningService, MfaSessionStatusService,
│       │                          # MfaRecoveryService (only admin's MFA recovery, #0-90),
│       │                          # TenantLifecycleService, TenantAccessService (suspension, #0-82)
│       ├── domain/                # User, Team, TeamMember, ApiKey, Integration,
│       │                          # AuthToken, MfaBackupCode, TenantSettings, Tenant, MfaRecoveryRequest
│       └── repository/            # JPA repositories for all domain entities
│
├── ingestion-service/             # port 8081 — alert ingestion
│   └── src/main/java/
│       ├── api/                   # AlertIngestionController (Prometheus, Wazuh, Generic endpoints)
│       ├── service/               # AlertIngestionService, DeduplicationService
│       ├── ratelimit/             # RateLimitingService (bucket4j + Redis), RateLimitingConfig, RedisRateLimitConfig
│       ├── normalizer/            # PrometheusNormalizer, WazuhNormalizer, GenericNormalizer
│       └── apikey/                # Integration API keys: introspection client into auth-service + 60 s cache
│
├── incident-service/              # port 8082 — incident lifecycle
│   └── src/main/java/
│       ├── api/                   # IncidentController, IncidentAuditController, DevTokenController
│       ├── service/               # IncidentCommandService, IncidentQueryService, IncidentEventPublisher
│       ├── domain/                # Incident, IncidentStatus, IncidentFsm, IncidentEventOutbox
│       ├── kafka/                 # IncidentKafkaConsumer, IncidentEscalationEventConsumer, AuditEventConsumer
│       └── config/                # WebSocketConfig, WebSocketProperties, SecurityConfig
│
├── notification-service/          # port 8083 — multi-channel notifications
│   └── src/main/java/
│       ├── channel/               # SlackNotificationChannel, EmailNotificationChannel, SmsNotificationChannel
│       ├── router/                # NotificationRouter (maps event types to channels)
│       ├── client/                # OncallClient (queries oncall-service), IncidentAckClient (ACK via Slack, inactive until backlog #0-35)
│       ├── slack/                 # SlackActionService, SlackSignatureVerifier, SlackMessageStore
│       ├── scheduler/             # NotificationScheduler, NotificationPausableWork (#0-82)
│       └── kafka/                 # IncidentEventConsumer
│
├── escalation-service/            # port 8084 — auto-escalation
│   └── src/main/java/
│       ├── service/               # EscalationService (task scheduling and cancellation)
│       ├── scheduler/             # EscalationScheduler (ShedLock @Scheduled), EscalationPausableWork (#0-82)
│       └── kafka/                 # IncidentEventConsumer
│
├── postmortem-service/            # port 8085 — AI postmortem generation
│   └── src/main/java/
│       ├── client/                # GeminiClient interface + GeminiClientImpl implementation
│       ├── service/               # PostmortemService
│       ├── scheduler/             # PostmortemRetryScheduler (retries FAILED postmortems), PostmortemPausableWork (#0-82)
│       └── kafka/                 # IncidentEventConsumer
│
├── oncall-service/                # port 8086 — on-call schedule management
│   └── src/main/java/
│       ├── api/                   # OncallScheduleController
│       └── service/               # OncallScheduleService (overlap detection, current on-call)
│
├── docker/
│   ├── docker-compose.yml         # Full stack: infrastructure, monitoring, log pipeline + all 7 application services
│   ├── .env.example               # Environment variable template — copy to .env and fill in
│   ├── prometheus.yml             # Scrape config for all 7 services (management ports 8091-8097) + kafka-exporter, loki, alloy
│   ├── prometheus.rules.yml       # Alert rules (scope: platform): Watchdog, infrastructure, ingestion, services (incl. the Slack breaker), Kafka lag, JVM, log pipeline (`logs`)
│   ├── prometheus.rules.test.yml  # promtool unit tests for the rules (run in CI)
│   ├── alertmanager.yml           # Routes: Watchdog → dead man's switch, critical → operator email, all → ingestion (ApiKey)
│   ├── deadmans-switch-url.example # Local heartbeat URL — copy to secrets/deadmans-switch-url
│   ├── secrets/                   # gitignored: platform-operator-api-key, deadmans-switch-url
│   ├── loki.yml                   # Loki: 15-day retention, no delete API, no port (backlog #0-94)
│   ├── alloy/config.alloy         # Alloy: Docker discovery via the socket proxy → ECS parsing → Loki
│   ├── grafana-password-check.sh  # make dev-up: warns about a weak or default Grafana admin password
│   └── grafana/
│       └── provisioning/          # Grafana datasources (Prometheus, Loki) and dashboards, auto-provisioned
│
└── k8s/
    ├── base/                      # Deployments, Services, HPA, PDB, Ingress, ConfigMap, Namespace
    │   ├── infrastructure/        # PostgreSQL StatefulSet, Kafka StatefulSet, Redis Deployment
    │   └── {service}/             # deployment.yml + service-hpa.yml + pdb.yml per service
    └── overlays/
        ├── dev/                   # Minikube: 1 replica, 768Mi memory, relaxed probe delays, secrets
        ├── staging/
        └── prod/
```

---

## Author

Built by Łukasz Pławiak as a portfolio project demonstrating production-oriented Java/Spring Boot backend development.

Frontend companion: [incident-platform-frontend](https://github.com/lukaszplawiak/incident-platform-frontend) — Angular 21 SPA with real-time WebSocket dashboard.