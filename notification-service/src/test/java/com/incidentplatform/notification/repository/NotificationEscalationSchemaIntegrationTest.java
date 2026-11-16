package com.incidentplatform.notification.repository;

import com.incidentplatform.notification.domain.NotificationLog;
import com.incidentplatform.notification.domain.NotificationQueueEntry;
import com.incidentplatform.notification.domain.NotificationQueueStatus;
import com.incidentplatform.notification.domain.UndeliverableReason;
import com.incidentplatform.shared.domain.Severity;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Configuration;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.test.context.ContextConfiguration;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Real-Postgres tests for the escalation-level-aware idempotency keys added
 * by the {@code V5} migration.
 *
 * <h2>What a mocked repository cannot prove</h2>
 * <ul>
 *   <li>{@code V5} applies cleanly on top of {@code V1}–{@code V4}, and
 *       {@code ddl-auto: validate} accepts the new
 *       {@code escalation_level} / {@code escalate_to} columns on the
 *       entities. A slice test that fails to start would fail every test
 *       here.</li>
 *   <li>{@code uq_notification_queue_incident_tenant_event_level} really is
 *       keyed on {@code (incident_id, tenant_id, event_type,
 *       escalation_level)}: two levels of the same escalation coexist, a
 *       redelivered level is rejected, and another tenant's row with the
 *       same incident id neither blocks nor satisfies the check.</li>
 *   <li>The {@code CHECK (escalation_level >= 0)} constraints hold.</li>
 *   <li>The derived {@code exists...} queries the service relies on
 *       distinguish levels.</li>
 * </ul>
 *
 * <p>Regression context: idempotency used to be keyed on
 * {@code (incident_id, event_type)}, so the level-2 (MANAGER) escalation
 * notification was discarded as a duplicate of level 1.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ContextConfiguration(classes =
        NotificationEscalationSchemaIntegrationTest.JpaSliceConfig.class)
@Testcontainers
@DisplayName("notification escalation-level idempotency — real Postgres")
class NotificationEscalationSchemaIntegrationTest {

    /**
     * Minimal JPA configuration instead of the application class:
     * {@code NotificationServiceApplication} carries an explicit
     * {@code @ComponentScan}, which switches off {@code @DataJpaTest}'s
     * slice filtering and would load every controller, client and Kafka
     * bean — none of which this test needs. Flyway and the DataSource still
     * come from the {@code @DataJpaTest} auto-configuration, so the real
     * {@code db/migration} scripts run against the container.
     */
    @Configuration
    @EntityScan("com.incidentplatform.notification.domain")
    @EnableJpaRepositories("com.incidentplatform.notification.repository")
    static class JpaSliceConfig {
    }

    // postgres:16-alpine — same image as docker/docker-compose.yml and the
    // other Testcontainers-based tests in this codebase.
    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>("postgres:16-alpine").withReuse(true);

    private static final String TENANT_ID = "test-tenant";
    private static final String ESCALATED = "IncidentEscalatedEvent";
    private static final String OPENED = "IncidentOpenedEvent";

    @Autowired
    private NotificationQueueRepository queueRepository;

    @Autowired
    private NotificationLogRepository logRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private jakarta.persistence.EntityManager entityManager;

    private NotificationQueueEntry entry(UUID incidentId, String eventType,
                                         int level, UUID escalateTo) {
        return NotificationQueueEntry.pending(
                incidentId, TENANT_ID, eventType, Severity.CRITICAL,
                "High CPU", level, escalateTo);
    }

    private NotificationQueueEntry entry(UUID incidentId, String eventType,
                                         int level, UUID escalateTo, UUID teamId) {
        return NotificationQueueEntry.pending(
                incidentId, TENANT_ID, eventType, Severity.CRITICAL,
                "High CPU", level, escalateTo, teamId);
    }

    @Test
    @DisplayName("queue: level 1 and level 2 of the same escalation can both be stored")
    void queueAllowsBothEscalationLevels() {
        final UUID incidentId = UUID.randomUUID();

        queueRepository.saveAndFlush(entry(incidentId, ESCALATED, 1, null));
        queueRepository.saveAndFlush(entry(incidentId, ESCALATED, 2, null));

        assertThat(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                incidentId, TENANT_ID, ESCALATED, 1)).isTrue();
        assertThat(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                incidentId, TENANT_ID, ESCALATED, 2)).isTrue();
        assertThat(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                incidentId, TENANT_ID, ESCALATED, 3)).isFalse();
    }

    @Test
    @DisplayName("queue: an UNDELIVERABLE entry is stored with its reason and is never picked up as PENDING (V6, backlog #0-18)")
    void queueStoresUndeliverableEntry() {
        final NotificationQueueEntry undeliverable = queueRepository.saveAndFlush(entry(
                UUID.randomUUID(), OPENED, 0, null));
        // Backlog #0-25: the status is reached through the conditional UPDATE, the
        // only way an existing entry changes (the entity has no mutators any more).
        assertThat(queueRepository.markUndeliverable(undeliverable.getId(), TENANT_ID,
                UndeliverableReason.NO_ONCALL.name(), Instant.now())).isEqualTo(1);
        // The UPDATE clears the persistence context (clearAutomatically), so findById
        // reads what Postgres stored, not the instance saved above.

        final NotificationQueueEntry reloaded =
                queueRepository.findById(undeliverable.getId()).orElseThrow();

        assertThat(reloaded.getStatus()).isEqualTo(NotificationQueueStatus.UNDELIVERABLE);
        assertThat(reloaded.getErrorMessage()).isEqualTo("NO_ONCALL");
        assertThat(reloaded.getProcessedAt()).isNotNull();
        assertThat(queueRepository.findPendingOlderThan(Instant.now().plusSeconds(60),
                org.springframework.data.domain.PageRequest.of(0, 50)))
                .extracting(NotificationQueueEntry::getId)
                .doesNotContain(undeliverable.getId());
    }

    @Test
    @DisplayName("queue: the first failed lookup is stored (V6) and later failures do not move it")
    void queueStoresTheFirstLookupFailureOnly() {
        final NotificationQueueEntry pending = queueRepository.saveAndFlush(
                entry(UUID.randomUUID(), OPENED, 0, null));
        assertThat(pending.getFirstLookupFailureAt()).isNull();

        // Backlog #0-25: recorded through the conditional UPDATE (the entity has no
        // mutators any more), which also refuses to move a time already stored.
        final Instant inMemory = Instant.now();
        assertThat(queueRepository.recordLookupFailure(pending.getId(), TENANT_ID, inMemory)).isEqualTo(1);

        final NotificationQueueEntry reloaded = queueRepository.findById(pending.getId()).orElseThrow();
        final Instant stored = reloaded.getFirstLookupFailureAt();
        // read back from Postgres: TIMESTAMPTZ keeps microseconds, so compare with a tolerance
        assertThat(stored).isBetween(inMemory.minusSeconds(1), inMemory.plusSeconds(1));

        assertThat(queueRepository.recordLookupFailure(pending.getId(), TENANT_ID,
                inMemory.plusSeconds(60))).isZero();

        assertThat(queueRepository.findById(pending.getId()).orElseThrow()
                .getFirstLookupFailureAt()).isEqualTo(stored);
    }

    @Test
    @DisplayName("queue: a row written the old way (no first_lookup_failure_at, old statuses) is valid after V6")
    void queueAcceptsRowsWrittenBeforeV6() {
        // Simulates a pod that still runs the pre-V6 code (it names only the columns it knows)
        // and rows that existed before the migration.
        for (final String status : new String[]{"PENDING", "SENT", "FAILED"}) {
            jdbcTemplate.update("INSERT INTO notification_queue "
                            + "(id, incident_id, tenant_id, event_type, severity, title, status) "
                            + "VALUES (?, ?, ?, ?, ?, ?, ?)",
                    UUID.randomUUID(), UUID.randomUUID(), TENANT_ID, OPENED,
                    "CRITICAL", "High CPU", status);
        }

        assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM notification_queue WHERE first_lookup_failure_at IS NULL",
                Integer.class)).isEqualTo(3);
        assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM notification_queue WHERE status = 'PENDING'",
                Integer.class)).isEqualTo(1);
    }

    @Test
    @DisplayName("queue: the status CHECK still rejects a value outside the allowed set")
    void queueStillRejectsUnknownStatus() {
        final NotificationQueueEntry saved = queueRepository.saveAndFlush(
                entry(UUID.randomUUID(), OPENED, 0, null));

        assertThatThrownBy(() -> jdbcTemplate.update(
                "UPDATE notification_queue SET status = 'BOGUS' WHERE id = ?", saved.getId()))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("queue: the same level of the same escalation is still unique")
    void queueRejectsDuplicateLevel() {
        final UUID incidentId = UUID.randomUUID();
        queueRepository.saveAndFlush(entry(incidentId, ESCALATED, 1, null));

        assertThatThrownBy(() -> queueRepository.saveAndFlush(
                entry(incidentId, ESCALATED, 1, null)))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("queue: non-escalation events (level 0) stay unique per incident and type")
    void queueKeepsNonEscalationEventsUnique() {
        final UUID incidentId = UUID.randomUUID();
        queueRepository.saveAndFlush(entry(incidentId, OPENED, 0, null));

        assertThatThrownBy(() -> queueRepository.saveAndFlush(
                entry(incidentId, OPENED, 0, null)))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("queue: idempotency is tenant-scoped — another tenant's row with the same incident id does not block or satisfy it")
    void queueIdempotencyIsTenantScoped() {
        final UUID incidentId = UUID.randomUUID();
        queueRepository.saveAndFlush(NotificationQueueEntry.pending(
                incidentId, "other-tenant", ESCALATED, Severity.CRITICAL,
                "High CPU", 1, null));

        // The other tenant's row must not count as "already queued" for us ...
        assertThat(queueRepository
                .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                        incidentId, TENANT_ID, ESCALATED, 1)).isFalse();
        // ... and must not prevent us from queueing our own.
        queueRepository.saveAndFlush(entry(incidentId, ESCALATED, 1, null));
        assertThat(queueRepository
                .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                        incidentId, TENANT_ID, ESCALATED, 1)).isTrue();
    }

    @Test
    @DisplayName("queue: a negative escalation level is rejected by the CHECK constraint")
    void queueRejectsNegativeEscalationLevel() {
        assertThatThrownBy(() -> queueRepository.saveAndFlush(
                entry(UUID.randomUUID(), ESCALATED, -1, null)))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("queue: escalation target and level round-trip")
    void queuePersistsEscalationContext() {
        final UUID incidentId = UUID.randomUUID();
        final UUID escalateTo = UUID.randomUUID();

        final NotificationQueueEntry saved = queueRepository.saveAndFlush(
                entry(incidentId, ESCALATED, 2, escalateTo));
        queueRepository.flush();

        final NotificationQueueEntry loaded =
                queueRepository.findById(saved.getId()).orElseThrow();
        assertThat(loaded.getEscalationLevel()).isEqualTo(2);
        assertThat(loaded.getEscalateTo()).isEqualTo(escalateTo);
    }

    @Test
    @DisplayName("queue: teamId round-trips through Postgres (V7, backlog #0-12)")
    void queuePersistsTeamId() {
        final UUID incidentId = UUID.randomUUID();
        final UUID teamId = UUID.randomUUID();

        final NotificationQueueEntry saved = queueRepository.saveAndFlush(
                entry(incidentId, OPENED, 0, null, teamId));
        entityManager.clear();

        final NotificationQueueEntry loaded =
                queueRepository.findById(saved.getId()).orElseThrow();
        assertThat(loaded.getTeamId()).isEqualTo(teamId);
    }

    @Test
    @DisplayName("queue: teamId is not part of the idempotency key (V7, backlog #0-12)")
    void queueTeamIdIsNotPartOfTheUniqueIndex() {
        final UUID incidentId = UUID.randomUUID();
        queueRepository.saveAndFlush(
                entry(incidentId, OPENED, 0, null, UUID.randomUUID()));

        // Same incident/tenant/event/level, a *different* teamId — still
        // rejected, proving teamId was not folded into
        // uq_notification_queue_incident_tenant_event_level.
        assertThatThrownBy(() -> queueRepository.saveAndFlush(
                entry(incidentId, OPENED, 0, null, UUID.randomUUID())))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("log: a level-2 send is not treated as already sent by level 1")
    void logDistinguishesEscalationLevels() {
        final UUID incidentId = UUID.randomUUID();
        logRepository.saveAndFlush(NotificationLog.sent(
                incidentId, TENANT_ID, ESCALATED, 1, "EMAIL",
                "secondary@example.com", "[ESCALATED] High CPU", "body"));

        assertThat(logRepository
                .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevelAndChannel(
                        incidentId, TENANT_ID, ESCALATED, 1, "EMAIL")).isTrue();
        assertThat(logRepository
                .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevelAndChannel(
                        incidentId, TENANT_ID, ESCALATED, 2, "EMAIL")).isFalse();
        assertThat(logRepository
                .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevelAndChannel(
                        incidentId, TENANT_ID, ESCALATED, 1, "SLACK")).isFalse();
    }

    @Test
    @DisplayName("log: idempotency is tenant-scoped")
    void logIdempotencyIsTenantScoped() {
        final UUID incidentId = UUID.randomUUID();
        logRepository.saveAndFlush(NotificationLog.sent(
                incidentId, "other-tenant", ESCALATED, 1, "EMAIL",
                "someone@example.com", "[ESCALATED] High CPU", "body"));

        assertThat(logRepository
                .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevelAndChannel(
                        incidentId, TENANT_ID, ESCALATED, 1, "EMAIL")).isFalse();
    }

    @Test
    @DisplayName("log: a negative escalation level is rejected by the CHECK constraint")
    void logRejectsNegativeEscalationLevel() {
        assertThatThrownBy(() -> logRepository.saveAndFlush(NotificationLog.sent(
                UUID.randomUUID(), TENANT_ID, ESCALATED, -1, "EMAIL",
                "someone@example.com", "subject", "body")))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
