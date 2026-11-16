package com.incidentplatform.notification.repository;

import com.incidentplatform.notification.domain.NotificationLog;
import com.incidentplatform.notification.domain.NotificationQueueEntry;
import com.incidentplatform.notification.domain.UndeliverableReason;
import com.incidentplatform.notification.service.NotificationPersistenceService;
import com.incidentplatform.shared.audit.AuditEventPublisher;
import com.incidentplatform.shared.audit.AuditEventTypes;
import com.incidentplatform.shared.audit.AuditOutbox;
import com.incidentplatform.shared.domain.Severity;
import com.incidentplatform.shared.security.TenantIds;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.core.env.Environment;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.Duration;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.willAnswer;
import static org.mockito.BDDMockito.willThrow;

/**
 * notification-service's audit outbox on a real Postgres (backlog #0-84, second
 * step): Flyway runs every migration up to V8, the shared
 * {@link AuditOutbox} SQL fits the table, and its writes join the service's
 * JPA transaction, so an audit event commits or rolls back with the action
 * it records. A mocked publisher cannot show either.
 *
 * <p>{@link NotificationPersistenceService} writes each {@code notification_log}
 * row and its audit event in one transaction: with the audit write failing,
 * the row is gone too, and with it succeeding both are there. The publisher
 * here is a mock that writes to the real outbox (the real one is built only by
 * {@code AuditOutboxConfiguration}, which needs Kafka and ShedLock), so a
 * transaction that did not span both writes would show.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ContextConfiguration(classes = AuditOutboxPersistenceIntegrationTest.JpaSliceConfig.class)
@Testcontainers
@DisplayName("notification-service audit outbox (Postgres, backlog #0-84)")
class AuditOutboxPersistenceIntegrationTest {

    /**
     * Tables of this schema with a tenant_id column but no CHECK holding the
     * platform's tenant id pattern ({@code TenantIds.SLUG}, the one parameter);
     * backlog #0-92.
     */
    private static final String TENANT_ID_COLUMNS_WITHOUT_SLUG_CHECK = """
            SELECT c.table_name FROM information_schema.columns c
            JOIN information_schema.tables t
              ON t.table_schema = c.table_schema AND t.table_name = c.table_name
             AND t.table_type = 'BASE TABLE'
            WHERE c.table_schema = current_schema() AND c.column_name = 'tenant_id'
              AND NOT EXISTS (
                SELECT 1 FROM pg_constraint k
                WHERE k.conrelid = (quote_ident(c.table_schema) || '.' || quote_ident(c.table_name))::regclass
                  AND k.contype = 'c'
                  AND position(? IN pg_get_constraintdef(k.oid)) > 0)
            ORDER BY c.table_name
            """;

    /**
     * Minimal JPA configuration instead of the application class, whose
     * explicit {@code @ComponentScan} would load every bean of the service.
     * Flyway and the DataSource still come from {@code @DataJpaTest}, so the
     * real {@code db/migration} scripts run against the container.
     */
    @Configuration
    @Import(NotificationPersistenceService.class)
    @EntityScan("com.incidentplatform.notification.domain")
    @EnableJpaRepositories("com.incidentplatform.notification.repository")
    static class JpaSliceConfig {

        /** {@link NotificationPersistenceService} counts stale queue writes (backlog #0-25). */
        @Bean
        MeterRegistry meterRegistry() {
            return new SimpleMeterRegistry();
        }
    }

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired private JdbcTemplate jdbcTemplate;
    @Autowired private PlatformTransactionManager transactionManager;
    @Autowired private EntityManager entityManager;
    @Autowired private Environment environment;
    @Autowired private NotificationPersistenceService persistenceService;
    @MockitoBean private AuditEventPublisher auditEventPublisher;

    /**
     * Some tests commit outbox rows (their own transactions, outside the test
     * one), and {@code outboxTableFitsSharedSql} asserts on the whole table:
     * emptied before each test so no result depends on test order (found in
     * review). Inside a test's transaction the delete is rolled back with it,
     * but hides the committed rows from that test all the same.
     */
    @BeforeEach
    void emptyOutbox() {
        jdbcTemplate.update("DELETE FROM notification_audit_outbox");
    }

    /**
     * The outbox on the table the service's application.yml names: a
     * hard-coded name would let a typo in the property pass every test and
     * fail every audited action at runtime.
     */
    private AuditOutbox configuredOutbox() {
        final String table = environment.getRequiredProperty("audit.outbox.table");
        assertThat(table).isEqualTo("notification_audit_outbox");
        return new AuditOutbox(jdbcTemplate, table);
    }

    private NotificationLog action() {
        return NotificationLog.sent(UUID.randomUUID(), "acme", "INCIDENT_OPENED", 0,
                "EMAIL", "oncall@acme.example", "Subject", "Message");
    }

    @Test
    @DisplayName("V8's table takes the shared outbox SQL: write, due, sent, failed, backlog")
    void outboxTableFitsSharedSql() {
        final AuditOutbox outbox = configuredOutbox();
        final UUID sent = UUID.randomUUID();
        final UUID failed = UUID.randomUUID();

        outbox.enqueue(sent, "acme", "NOTIFICATION_SENT", "{\"eventId\":\"" + sent + "\"}");
        outbox.enqueue(failed, "acme", "NOTIFICATION_SENT", "{}");

        assertThat(jdbcTemplate.queryForMap("SELECT status, attempts, tenant_id FROM notification_audit_outbox WHERE id = ?", sent))
                .containsEntry("status", "PENDING")
                .containsEntry("attempts", 0)
                .containsEntry("tenant_id", "acme");
        assertThat(outbox.anyDue()).isTrue();
        assertThat(outbox.due(10)).extracting(AuditOutbox.Pending::id).containsExactlyInAnyOrder(sent, failed);
        assertThat(outbox.markSent(List.of(sent))).isEqualTo(1);
        assertThat(outbox.markFailed(failed, Duration.ofSeconds(60), "down")).isTrue();
        assertThat(outbox.anyDue()).isFalse();
        assertThat(outbox.backlog().pending()).isEqualTo(1);
        assertThatThrownBy(() -> jdbcTemplate.update("UPDATE notification_audit_outbox SET status = 'LOST' WHERE id = ?", sent))
                .as("the status check").isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("the outbox write joins the service's JPA transaction: the event and the action roll back together")
    void outboxJoinsJpaTransaction() {
        final AuditOutbox outbox = configuredOutbox();
        final UUID eventId = UUID.randomUUID();
        final NotificationLog action = action();
        final TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);

        transaction.executeWithoutResult(status -> {
            entityManager.persist(action);
            entityManager.flush();
            outbox.enqueue(eventId, "acme", "NOTIFICATION_SENT", "{}");
            status.setRollbackOnly();
        });

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM notification_audit_outbox WHERE id = ?",
                Integer.class, eventId)).isZero();
        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM notification_log WHERE incident_id = ?",
                Integer.class, action.getIncidentId())).isZero();

        transaction.executeWithoutResult(status -> {
            entityManager.persist(action());
            outbox.enqueue(eventId, "acme", "NOTIFICATION_SENT", "{}");
        });
        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM notification_audit_outbox WHERE id = ?",
                Integer.class, eventId)).as("committed with the action").isEqualTo(1);
    }

    private int logRows(UUID incidentId) {
        return jdbcTemplate.queryForObject("SELECT count(*) FROM notification_log WHERE incident_id = ?",
                Integer.class, incidentId);
    }

    private int outboxRows(String tenantId) {
        return jdbcTemplate.queryForObject("SELECT count(*) FROM notification_audit_outbox WHERE tenant_id = ?",
                Integer.class, tenantId);
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    @DisplayName("recordChannelSent commits the log row and its audit event together")
    void sentRowAndAuditCommitTogether() {
        final AuditOutbox outbox = configuredOutbox();
        willAnswer(invocation -> {
            outbox.enqueue(UUID.randomUUID(), invocation.getArgument(1), invocation.getArgument(2), "{}");
            return null;
        }).given(auditEventPublisher).publishIncident(any(), anyString(), anyString(), anyString(), anyString(), any());
        final UUID incidentId = UUID.randomUUID();

        persistenceService.recordChannelSent(incidentId, "tenant-sent", "INCIDENT_OPENED", 0,
                "EMAIL", "oncall@acme.example", "Subject", "Message");

        assertThat(logRows(incidentId)).isEqualTo(1);
        assertThat(outboxRows("tenant-sent")).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject("SELECT tenant_id FROM notification_log WHERE incident_id = ?",
                String.class, incidentId))
                .as("the event's tenant is the log row's (found in review: nothing checked it)")
                .isEqualTo("tenant-sent");
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    @DisplayName("a failed audit write rolls back the log row it records (sent and failed alike)")
    void auditFailureRollsBackLogRow() {
        willThrow(new IllegalArgumentException("unstorable")).given(auditEventPublisher)
                .publishIncident(any(), anyString(), eq(AuditEventTypes.NOTIFICATION_SENT), anyString(), anyString(),
                        any());
        willThrow(new IllegalArgumentException("unstorable")).given(auditEventPublisher)
                .publishIncident(any(), anyString(), eq(AuditEventTypes.NOTIFICATION_FAILED), anyString(),
                        anyString(), any());
        final UUID sent = UUID.randomUUID();
        final UUID failed = UUID.randomUUID();

        assertThatThrownBy(() -> persistenceService.recordChannelSent(sent, "acme", "INCIDENT_OPENED", 0,
                "EMAIL", "oncall@acme.example", "Subject", "Message")).hasMessage("unstorable");
        assertThatThrownBy(() -> persistenceService.recordChannelFailed(failed, "acme", "INCIDENT_OPENED", 0,
                "EMAIL", "oncall@acme.example", "EMAIL_TRANSPORT_UNAVAILABLE",
                "EMAIL_TRANSPORT_UNAVAILABLE: The mail server could not be reached")).hasMessage("unstorable");

        assertThat(logRows(sent)).isZero();
        assertThat(logRows(failed)).isZero();
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    @DisplayName("a failed NOTIFICATION_UNDELIVERABLE write rolls the UNDELIVERABLE status back (found in review)")
    void auditFailureRollsBackUndeliverable() {
        final NotificationQueueEntry entry = NotificationQueueEntry.pending(
                UUID.randomUUID(), "acme", "INCIDENT_OPENED", Severity.HIGH, "Disk full");
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> entityManager.persist(entry));
        willThrow(new IllegalArgumentException("unstorable")).given(auditEventPublisher)
                .publishIncident(any(), anyString(), eq(AuditEventTypes.NOTIFICATION_UNDELIVERABLE), anyString(),
                        anyString(), any());

        assertThatThrownBy(() -> persistenceService.markUndeliverable(entry, UndeliverableReason.NO_ONCALL))
                .hasMessage("unstorable");

        assertThat(jdbcTemplate.queryForObject("SELECT status FROM notification_queue WHERE id = ?",
                String.class, entry.getId())).isEqualTo("PENDING");
    }

    /**
     * Backlog #0-92 (found in review): every table of this service with a
     * tenant_id carries the slug CHECK (V9); a scheduler that reads a row
     * back sets TenantContext from it, which refuses anything else. A new
     * table without the constraint fails here.
     */
    @Test
    @DisplayName("every table with a tenant_id carries the tenant id slug CHECK (V9, backlog #0-92)")
    void everyTenantIdColumnChecked() {
        assertThat(jdbcTemplate.queryForList(TENANT_ID_COLUMNS_WITHOUT_SLUG_CHECK, String.class,
                TenantIds.SLUG)).isEmpty();
        assertThat(jdbcTemplate.queryForObject(
                "SELECT count(*) FROM information_schema.columns WHERE table_schema = current_schema() "
                        + "AND column_name = 'tenant_id'", Integer.class)).isGreaterThanOrEqualTo(4);
    }
}
