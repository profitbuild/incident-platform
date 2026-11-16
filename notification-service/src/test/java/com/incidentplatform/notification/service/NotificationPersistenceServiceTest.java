package com.incidentplatform.notification.service;

import com.incidentplatform.notification.domain.NotificationLog;
import com.incidentplatform.notification.domain.NotificationLogStatus;
import com.incidentplatform.notification.domain.NotificationQueueEntry;
import com.incidentplatform.notification.repository.NotificationLogRepository;
import com.incidentplatform.notification.domain.UndeliverableReason;
import com.incidentplatform.notification.repository.NotificationQueueRepository;
import com.incidentplatform.shared.audit.AuditEventPublisher;
import com.incidentplatform.shared.audit.AuditEventTypes;
import com.incidentplatform.shared.domain.Severity;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.Mockito.never;

/**
 * Backlog #42. This class did not exist before — extracted from
 * {@code NotificationService.processEntry(...)}'s previously-inline
 * repository writes, specifically so each write could happen in its own
 * short transaction with no external I/O in progress while it's open.
 * See this class's own Javadoc for the full account.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("NotificationPersistenceService")
class NotificationPersistenceServiceTest {

    @Mock private NotificationQueueRepository queueRepository;
    @Mock private NotificationLogRepository logRepository;
    @Mock private AuditEventPublisher auditEventPublisher;

    private NotificationPersistenceService persistenceService;

    private static final String TENANT_ID = "test-tenant";
    private static final UUID INCIDENT_ID = UUID.randomUUID();
    private static final String EVENT_TYPE = "IncidentOpenedEvent";

    private SimpleMeterRegistry meterRegistry;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        persistenceService = new NotificationPersistenceService(
                queueRepository, logRepository, auditEventPublisher, meterRegistry);
    }

    private NotificationQueueEntry buildEntry() {
        return NotificationQueueEntry.pending(
                INCIDENT_ID, TENANT_ID, EVENT_TYPE, Severity.CRITICAL, "High CPU");
    }

    private double staleWrites(String operation) {
        return meterRegistry.counter("notification.queue.stale_write", "operation", operation).count();
    }

    // Backlog #0-25: the entry is no longer changed in memory and save()d; each
    // transition is the repository's conditional UPDATE by id and tenant.

    @Test
    @DisplayName("markSent marks the entry SENT through the conditional UPDATE of its id and tenant")
    void marksSentAndPersists() {
        final NotificationQueueEntry entry = buildEntry();
        given(queueRepository.markSent(eq(entry.getId()), eq(TENANT_ID), any(Instant.class))).willReturn(1);

        assertThat(persistenceService.markSent(entry)).isTrue();

        then(queueRepository).should().markSent(eq(entry.getId()), eq(TENANT_ID), any(Instant.class));
        then(queueRepository).should(never()).save(any());
        assertThat(staleWrites("sent")).isZero();
    }

    @Test
    @DisplayName("markFailed marks the entry FAILED, with its error, through the conditional UPDATE")
    void marksFailedAndPersists() {
        final NotificationQueueEntry entry = buildEntry();
        given(queueRepository.markFailed(eq(entry.getId()), eq(TENANT_ID), eq("oncall-service unreachable"),
                any(Instant.class))).willReturn(1);

        assertThat(persistenceService.markFailed(entry, "oncall-service unreachable")).isTrue();

        then(queueRepository).should(never()).save(any());
        assertThat(staleWrites("failed")).isZero();
    }

    @Test
    @DisplayName("recordLookupFailure stores the first failed lookup through the conditional UPDATE")
    void recordsLookupFailure() {
        final NotificationQueueEntry entry = buildEntry();
        given(queueRepository.recordLookupFailure(eq(entry.getId()), eq(TENANT_ID), any(Instant.class)))
                .willReturn(1);

        assertThat(persistenceService.recordLookupFailure(entry)).isTrue();

        then(queueRepository).should(never()).save(any());
        assertThat(staleWrites("lookup")).isZero();
    }

    /** Backlog #0-25 (AC3): 0 rows changed is false and counted with the operation's tag, 1 row is not. */
    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"sent", "failed", "lookup"})
    @DisplayName("a write that changes no row returns false and is counted per operation")
    void staleWriteIsCountedPerOperation(String operation) {
        final NotificationQueueEntry entry = buildEntry();
        final java.util.function.Supplier<Boolean> write = switch (operation) {
            case "sent" -> {
                given(queueRepository.markSent(eq(entry.getId()), eq(TENANT_ID), any(Instant.class)))
                        .willReturn(0, 1);
                yield () -> persistenceService.markSent(entry);
            }
            case "failed" -> {
                given(queueRepository.markFailed(eq(entry.getId()), eq(TENANT_ID), eq("boom"), any(Instant.class)))
                        .willReturn(0, 1);
                yield () -> persistenceService.markFailed(entry, "boom");
            }
            case "lookup" -> {
                given(queueRepository.recordLookupFailure(eq(entry.getId()), eq(TENANT_ID), any(Instant.class)))
                        .willReturn(0, 1);
                yield () -> persistenceService.recordLookupFailure(entry);
            }
            default -> throw new IllegalArgumentException(operation);
        };

        assertThat(write.get()).as("0 rows").isFalse();
        assertThat(staleWrites(operation)).isEqualTo(1.0);

        assertThat(write.get()).as("1 row").isTrue();
        assertThat(staleWrites(operation)).as("not counted again").isEqualTo(1.0);
        assertThat(meterRegistry.find("notification.queue.stale_write").counters())
                .as("no other operation's tag").hasSize(1);
    }

    /** Backlog #0-25 (AC3): an entry another writer already closed gets no NOTIFICATION_UNDELIVERABLE. */
    @Test
    @DisplayName("markUndeliverable on an entry no longer PENDING writes no audit event and counts the stale write")
    void markUndeliverableOnAStaleRowWritesNoAuditEvent() {
        final NotificationQueueEntry entry = buildEntry();
        given(queueRepository.markUndeliverable(eq(entry.getId()), eq(TENANT_ID), eq("NO_ONCALL"),
                any(Instant.class))).willReturn(0);

        assertThat(persistenceService.markUndeliverable(entry, UndeliverableReason.NO_ONCALL)).isFalse();

        then(auditEventPublisher).shouldHaveNoInteractions();
        assertThat(staleWrites("undeliverable")).isEqualTo(1.0);
    }

    @Test
    @DisplayName("recordChannelSent persists a SENT NotificationLog with the given fields")
    void recordsChannelSent() {
        persistenceService.recordChannelSent(
                INCIDENT_ID, TENANT_ID, EVENT_TYPE, 0, "EMAIL",
                "oncall@example.com", "[CRITICAL] High CPU", "Body text");

        final ArgumentCaptor<NotificationLog> captor =
                ArgumentCaptor.forClass(NotificationLog.class);
        then(logRepository).should().save(captor.capture());

        final NotificationLog saved = captor.getValue();
        assertThat(saved.getStatus()).isEqualTo(NotificationLogStatus.SENT);
        assertThat(saved.getIncidentId()).isEqualTo(INCIDENT_ID);
        assertThat(saved.getChannel()).isEqualTo("EMAIL");
        assertThat(saved.getRecipient()).isEqualTo("oncall@example.com");
        assertThat(saved.getEscalationLevel()).isZero();
        then(auditEventPublisher).should().publishIncident(INCIDENT_ID, TENANT_ID,
                AuditEventTypes.NOTIFICATION_SENT, "notification-service",
                "Notification sent via EMAIL to oncall@example.com",
                Map.of("channel", "EMAIL", "recipient", "oncall@example.com", "eventType", EVENT_TYPE));
    }

    @Test
    @DisplayName("recordChannelSent stores the escalation level so level 2 is not mistaken for level 1")
    void recordsChannelSentWithEscalationLevel() {
        persistenceService.recordChannelSent(
                INCIDENT_ID, TENANT_ID, "IncidentEscalatedEvent", 2, "EMAIL",
                "manager@example.com", "[ESCALATED] High CPU", "Body text");

        final ArgumentCaptor<NotificationLog> captor =
                ArgumentCaptor.forClass(NotificationLog.class);
        then(logRepository).should().save(captor.capture());
        assertThat(captor.getValue().getEscalationLevel()).isEqualTo(2);
    }

    @Test
    @DisplayName("recordChannelFailed persists a FAILED NotificationLog with the error, and the reason in the audit event")
    void recordsChannelFailed() {
        persistenceService.recordChannelFailed(
                INCIDENT_ID, TENANT_ID, EVENT_TYPE, 0, "EMAIL",
                "oncall@example.com", "EMAIL_FAILED", "SMTP connection refused");

        final ArgumentCaptor<NotificationLog> captor =
                ArgumentCaptor.forClass(NotificationLog.class);
        then(logRepository).should().save(captor.capture());

        final NotificationLog saved = captor.getValue();
        assertThat(saved.getStatus()).isEqualTo(NotificationLogStatus.FAILED);
        assertThat(saved.getErrorMessage()).isEqualTo("SMTP connection refused");
        then(auditEventPublisher).should().publishIncident(INCIDENT_ID, TENANT_ID,
                AuditEventTypes.NOTIFICATION_FAILED, "notification-service",
                "Notification failed via EMAIL to oncall@example.com: SMTP connection refused",
                Map.of("channel", "EMAIL", "recipient", "oncall@example.com", "reason", "EMAIL_FAILED",
                        "error", "SMTP connection refused"));
    }

    /**
     * Found while moving the audit event here (backlog #0-84): an exception
     * without a message made {@code Map.of} throw, which the old direct send
     * swallowed and the outbox would turn into a failed entry.
     */
    @Test
    @DisplayName("recordChannelFailed with no error message records 'unknown' rather than throwing")
    void recordsChannelFailedWithoutMessage() {
        persistenceService.recordChannelFailed(
                INCIDENT_ID, TENANT_ID, EVENT_TYPE, 0, "EMAIL", "oncall@example.com", null, null);

        final ArgumentCaptor<NotificationLog> captor = ArgumentCaptor.forClass(NotificationLog.class);
        then(logRepository).should().save(captor.capture());
        assertThat(captor.getValue().getErrorMessage()).isEqualTo("unknown");
        then(auditEventPublisher).should().publishIncident(eq(INCIDENT_ID), eq(TENANT_ID),
                eq(AuditEventTypes.NOTIFICATION_FAILED), eq("notification-service"), any(),
                eq(Map.of("channel", "EMAIL", "recipient", "oncall@example.com", "reason", "unknown",
                        "error", "unknown")));
    }

    /**
     * Found in review: an unbounded message could make the audit event too
     * large to store, failing this write. The log row keeps it whole.
     */
    @Test
    @DisplayName("recordChannelFailed keeps the whole error in the log row, cut and on one line in the audit event")
    void auditErrorCut() {
        final String error = "line one\n" + "x".repeat(10_000);

        persistenceService.recordChannelFailed(
                INCIDENT_ID, TENANT_ID, EVENT_TYPE, 0, "EMAIL", "oncall@example.com", "EMAIL_FAILED", error);

        final ArgumentCaptor<NotificationLog> logRow = ArgumentCaptor.forClass(NotificationLog.class);
        then(logRepository).should().save(logRow.capture());
        assertThat(logRow.getValue().getErrorMessage()).isEqualTo(error);
        @SuppressWarnings("unchecked")
        final ArgumentCaptor<Map<String, Object>> metadata = ArgumentCaptor.forClass(Map.class);
        then(auditEventPublisher).should().publishIncident(eq(INCIDENT_ID), eq(TENANT_ID),
                eq(AuditEventTypes.NOTIFICATION_FAILED), eq("notification-service"), any(), metadata.capture());
        assertThat((String) metadata.getValue().get("error"))
                .hasSize(500).startsWith("line one x").doesNotContain("\n");
    }

    @Test
    @DisplayName("markUndeliverable parks the entry and records NOTIFICATION_UNDELIVERABLE")
    void marksUndeliverableAndAudits() {
        final NotificationQueueEntry entry = buildEntry();
        given(queueRepository.markUndeliverable(eq(entry.getId()), eq(TENANT_ID), eq("NO_ONCALL"),
                any(Instant.class))).willReturn(1);

        assertThat(persistenceService.markUndeliverable(entry, UndeliverableReason.NO_ONCALL)).isTrue();

        then(queueRepository).should(never()).save(any());
        assertThat(staleWrites("undeliverable")).isZero();
        then(auditEventPublisher).should().publishIncident(eq(INCIDENT_ID), eq(TENANT_ID),
                eq(AuditEventTypes.NOTIFICATION_UNDELIVERABLE), eq("notification-service"), any(),
                eq(Map.of("eventType", EVENT_TYPE, "reason", "NO_ONCALL")));
    }
}