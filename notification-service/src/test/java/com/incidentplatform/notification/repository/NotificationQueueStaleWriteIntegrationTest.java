package com.incidentplatform.notification.repository;

import com.incidentplatform.notification.config.NotificationSchedulerProperties;
import com.incidentplatform.notification.domain.NotificationQueueEntry;
import com.incidentplatform.notification.domain.UndeliverableReason;
import com.incidentplatform.notification.scheduler.NotificationScheduler;
import com.incidentplatform.notification.service.NotificationPersistenceService;
import com.incidentplatform.notification.service.NotificationService;
import com.incidentplatform.notification.slack.SlackMessageStore;
import com.incidentplatform.shared.audit.AuditEventPublisher;
import com.incidentplatform.shared.audit.AuditEventTypes;
import com.incidentplatform.shared.domain.Severity;
import com.incidentplatform.shared.pause.TenantWorkGuard;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.EnumSource;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.BDDMockito.willAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;

/**
 * Backlog #0-25 (ADR-0059) on a real Postgres: every change of an existing
 * {@code notification_queue} row is a conditional UPDATE from PENDING, scoped
 * by id and tenant, and a write that finds the row already closed changes
 * nothing. Before, each transition changed a loaded entity and {@code save()}d
 * it, a merge that wrote every column as it was loaded: a stale writer (the
 * scheduler's catch-all after a committed UNDELIVERABLE, a run that outlived
 * its ShedLock) overwrote a terminal status, and a scheduler entry loaded
 * before {@code restartLookupRetryWindows} wrote the old first failure back.
 *
 * <p>Rows are compared with what Postgres stored before, never with an
 * in-memory {@code Instant} ({@code TIMESTAMPTZ} rounds to microseconds).
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ContextConfiguration(classes = NotificationQueueStaleWriteIntegrationTest.JpaSliceConfig.class)
@Testcontainers
@DisplayName("notification_queue stale writes change nothing (Postgres, backlog #0-25)")
class NotificationQueueStaleWriteIntegrationTest {

    /** The shape of {@code AuditOutboxPersistenceIntegrationTest}'s slice. */
    @Configuration
    @Import(NotificationPersistenceService.class)
    @EntityScan("com.incidentplatform.notification.domain")
    @EnableJpaRepositories("com.incidentplatform.notification.repository")
    static class JpaSliceConfig {

        @Bean
        MeterRegistry meterRegistry() {
            return new SimpleMeterRegistry();
        }
    }

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    private static final String TENANT_ID = "acme";
    private static final String OTHER_TENANT_ID = "globex";
    private static final String ROW = "SELECT status, error_message, processed_at, first_lookup_failure_at "
            + "FROM notification_queue WHERE id = ?";

    @Autowired private NotificationQueueRepository queueRepository;
    @Autowired private NotificationPersistenceService persistenceService;
    @Autowired private JdbcTemplate jdbcTemplate;
    @Autowired private MeterRegistry meterRegistry;
    @MockitoBean private AuditEventPublisher auditEventPublisher;

    /** The four writes of an existing entry, by the tag they are counted under. */
    enum Operation {
        SENT("sent"), FAILED("failed"), UNDELIVERABLE("undeliverable"), LOOKUP("lookup");

        final String tag;

        Operation(String tag) {
            this.tag = tag;
        }
    }

    /**
     * The scheduler test commits its row (no test transaction), and the
     * scheduler reads every PENDING row: emptied before and after so no
     * result depends on test order. The registry is the context's, shared by
     * every test of the class, so its counters start again from zero too.
     */
    @BeforeEach
    void startEmpty() {
        jdbcTemplate.update("DELETE FROM notification_queue");
        meterRegistry.clear();
    }

    @AfterEach
    void removeCommittedRows() {
        jdbcTemplate.update("DELETE FROM notification_queue");
    }

    private NotificationQueueEntry pending() {
        return queueRepository.saveAndFlush(NotificationQueueEntry.pending(
                UUID.randomUUID(), TENANT_ID, "INCIDENT_OPENED", Severity.HIGH, "Disk full"));
    }

    private Map<String, Object> row(UUID id) {
        return jdbcTemplate.queryForMap(ROW, id);
    }

    private int update(Operation operation, UUID id, String tenantId) {
        final Instant now = Instant.now();
        return switch (operation) {
            case SENT -> queueRepository.markSent(id, tenantId, now);
            case FAILED -> queueRepository.markFailed(id, tenantId, "Unexpected error: RuntimeException", now);
            case UNDELIVERABLE -> queueRepository.markUndeliverable(id, tenantId, "NO_ONCALL", now);
            case LOOKUP -> queueRepository.recordLookupFailure(id, tenantId, now);
        };
    }

    private boolean write(Operation operation, NotificationQueueEntry entry) {
        return switch (operation) {
            case SENT -> persistenceService.markSent(entry);
            case FAILED -> persistenceService.markFailed(entry, "Unexpected error: RuntimeException");
            case UNDELIVERABLE -> persistenceService.markUndeliverable(entry, UndeliverableReason.NO_ONCALL);
            case LOOKUP -> persistenceService.recordLookupFailure(entry);
        };
    }

    private double staleWrites(Operation operation) {
        return meterRegistry.counter("notification.queue.stale_write", "operation", operation.tag).count();
    }

    @ParameterizedTest(name = "{0}")
    @EnumSource(Operation.class)
    @DisplayName("each write changes a PENDING row: row count 1, its columns stored")
    void eachTransitionChangesAPendingRow(Operation operation) {
        assertThat(update(operation, pending().getId(), TENANT_ID)).as("row count").isEqualTo(1);

        final NotificationQueueEntry entry = pending();
        assertThat(write(operation, entry)).isTrue();

        final Map<String, Object> row = row(entry.getId());
        switch (operation) {
            case SENT -> assertThat(row).containsEntry("status", "SENT").containsEntry("error_message", null)
                    .containsEntry("first_lookup_failure_at", null);
            case FAILED -> assertThat(row).containsEntry("status", "FAILED")
                    .containsEntry("error_message", "Unexpected error: RuntimeException");
            case UNDELIVERABLE -> assertThat(row).containsEntry("status", "UNDELIVERABLE")
                    .containsEntry("error_message", "NO_ONCALL");
            case LOOKUP -> assertThat(row).containsEntry("status", "PENDING")
                    .containsEntry("processed_at", null);
        }
        if (operation == Operation.LOOKUP) {
            assertThat(row.get("first_lookup_failure_at")).isNotNull();
        } else {
            assertThat(row.get("processed_at")).isNotNull();
        }
        assertThat(staleWrites(operation)).isZero();
    }

    static Stream<Arguments> writesOnTerminalRows() {
        return Arrays.stream(Operation.values()).flatMap(operation -> Stream.of(
                        Operation.SENT, Operation.FAILED, Operation.UNDELIVERABLE)
                .map(terminal -> Arguments.of(operation, terminal)));
    }

    /** AC1: on a row already SENT, FAILED or UNDELIVERABLE each write changes nothing. */
    @ParameterizedTest(name = "{0} on {1}")
    @MethodSource("writesOnTerminalRows")
    @DisplayName("no write changes a row already SENT, FAILED or UNDELIVERABLE: row count 0, the row as it was")
    void noTransitionChangesATerminalRow(Operation operation, Operation terminal) {
        final NotificationQueueEntry entry = pending();
        assertThat(update(terminal, entry.getId(), TENANT_ID)).isEqualTo(1);
        final Map<String, Object> closed = row(entry.getId());
        assertThat(closed.get("status")).isEqualTo(terminal.name());

        assertThat(update(operation, entry.getId(), TENANT_ID)).as("row count").isZero();
        assertThat(row(entry.getId())).isEqualTo(closed);

        assertThat(write(operation, entry)).isFalse();
        assertThat(row(entry.getId())).isEqualTo(closed);
        assertThat(staleWrites(operation)).isEqualTo(1.0);
        if (operation == Operation.UNDELIVERABLE) {
            then(auditEventPublisher).should(never()).publishIncident(any(), anyString(),
                    eq(AuditEventTypes.NOTIFICATION_UNDELIVERABLE), anyString(), anyString(), any());
        }
    }

    /** SEC-06: the right id with another tenant's id changes nothing. */
    @Test
    @DisplayName("a write with the entry's id but another tenant changes nothing")
    void aTransitionWithAnotherTenantChangesNothing() {
        final NotificationQueueEntry entry = pending();
        final Map<String, Object> before = row(entry.getId());

        for (final Operation operation : Operation.values()) {
            assertThat(update(operation, entry.getId(), OTHER_TENANT_ID)).as(operation.name()).isZero();
        }

        assertThat(row(entry.getId())).isEqualTo(before).containsEntry("status", "PENDING");
    }

    /** AC4: a first failure already stored is never moved. */
    @Test
    @DisplayName("recordLookupFailure keeps a first failure already stored")
    void recordLookupFailureKeepsAnExistingTimestamp() {
        final NotificationQueueEntry entry = pending();
        assertThat(queueRepository.recordLookupFailure(entry.getId(), TENANT_ID,
                Instant.now().minus(Duration.ofMinutes(5)))).isEqualTo(1);
        final Object stored = row(entry.getId()).get("first_lookup_failure_at");

        assertThat(persistenceService.recordLookupFailure(entry)).isFalse();

        assertThat(row(entry.getId()).get("first_lookup_failure_at")).isEqualTo(stored);
        assertThat(staleWrites(Operation.LOOKUP)).isEqualTo(1.0);
    }

    /**
     * AC4: an entry loaded with a first failure T, before the tenant's
     * resumption restarted its window, never writes T back.
     */
    @Test
    @DisplayName("a restart by restartLookupRetryWindows is not undone by a write of an entry loaded before it")
    void restartIsNotUndoneByAStaleSchedulerWrite() {
        final UUID id = pending().getId();
        assertThat(queueRepository.recordLookupFailure(id, TENANT_ID,
                Instant.now().minus(Duration.ofHours(1)))).isEqualTo(1);
        final NotificationQueueEntry loaded = queueRepository.findById(id).orElseThrow();
        final Timestamp first = (Timestamp) row(id).get("first_lookup_failure_at");
        assertThat(loaded.getFirstLookupFailureAt()).isNotNull();

        assertThat(queueRepository.restartLookupRetryWindows(TENANT_ID)).isEqualTo(1);
        assertThat(row(id).get("first_lookup_failure_at")).isNull();

        // the scheduler's next lookup failure for the entry it loaded before the restart
        assertThat(persistenceService.recordLookupFailure(loaded)).isTrue();
        final Timestamp again = (Timestamp) row(id).get("first_lookup_failure_at");
        assertThat(again).isNotEqualTo(first).isAfter(first);

        // restarted once more, then the loaded entry is marked SENT
        assertThat(queueRepository.restartLookupRetryWindows(TENANT_ID)).isEqualTo(1);
        assertThat(persistenceService.markSent(loaded)).isTrue();
        assertThat(row(id)).containsEntry("status", "SENT").containsEntry("first_lookup_failure_at", null);
    }

    /**
     * AC2: {@code processEntry} commits UNDELIVERABLE and then throws (the
     * operator alert failing after the write). The scheduler's catch-all
     * {@code markFailed} used to merge the entry it had loaded, overwriting
     * the UNDELIVERABLE with FAILED; now it changes nothing. No test
     * transaction, so each write commits as in production.
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    @DisplayName("the scheduler's catch-all after a committed UNDELIVERABLE leaves it UNDELIVERABLE, unchanged")
    void catchAllAfterCommittedUndeliverableLeavesItUndeliverable() {
        final UUID id = pending().getId();
        final NotificationService notificationService = mock(NotificationService.class);
        final TenantWorkGuard workGuard = mock(TenantWorkGuard.class);
        given(workGuard.mayRun(TENANT_ID)).willReturn(true);
        final AtomicReference<Map<String, Object>> afterUndeliverable = new AtomicReference<>();
        willAnswer(invocation -> {
            final NotificationQueueEntry entry = invocation.getArgument(0);
            assertThat(persistenceService.markUndeliverable(entry, UndeliverableReason.NO_ONCALL)).isTrue();
            afterUndeliverable.set(row(entry.getId()));
            throw new IllegalStateException("operator alert failed");
        }).given(notificationService).processEntry(any());
        final NotificationScheduler scheduler = new NotificationScheduler(queueRepository, notificationService,
                persistenceService, mock(SlackMessageStore.class), workGuard,
                new NotificationSchedulerProperties(Duration.ZERO, Duration.ofDays(7), Duration.ofMinutes(10),
                        Duration.ofMinutes(1), 50),
                List.of());

        scheduler.processPendingNotifications();

        then(notificationService).should().processEntry(any());
        assertThat(afterUndeliverable.get()).containsEntry("status", "UNDELIVERABLE")
                .containsEntry("error_message", "NO_ONCALL");
        assertThat(row(id)).isEqualTo(afterUndeliverable.get());
        assertThat(staleWrites(Operation.FAILED)).isEqualTo(1.0);
    }
}
