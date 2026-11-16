package com.incidentplatform.notification.service;

import com.incidentplatform.notification.channel.NotificationChannel;
import com.incidentplatform.notification.channel.NotificationException;
import com.incidentplatform.notification.channel.NotificationFailureReason;
import com.incidentplatform.notification.domain.NotificationQueueEntry;
import com.incidentplatform.notification.domain.UndeliverableReason;
import com.incidentplatform.notification.domain.NotificationQueueStatus;
import com.incidentplatform.notification.dto.NotificationRequest;
import com.incidentplatform.notification.repository.NotificationLogRepository;
import com.incidentplatform.notification.repository.NotificationQueueRepository;
import com.incidentplatform.notification.router.NotificationRouter;
import com.incidentplatform.shared.domain.Severity;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;

/**
 * Backlog #42 note: processEntry() no longer writes to logRepository/
 * queueRepository directly — it delegates through
 * NotificationPersistenceService (a new mock here). ProcessEntry's tests
 * below verify persistenceService interactions instead of repository
 * saves directly. Enqueue's tests are unchanged — enqueue() still writes
 * to queueRepository directly (a single fast DB operation with no
 * external I/O, deliberately left as-is — see NotificationService's own
 * Javadoc for why).
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("NotificationService")
class NotificationServiceTest {

    @Mock private NotificationRouter router;
    @Mock private NotificationLogRepository logRepository;
    @Mock private NotificationQueueRepository queueRepository;
    @Mock private NotificationPersistenceService persistenceService;
    @Mock private NotificationChannel emailChannel;
    @Mock private NotificationChannel slackChannel;
    @Mock private OperatorAlertService operatorAlertService;

    private SimpleMeterRegistry meterRegistry;
    private NotificationService notificationService;

    private static final String TENANT_ID = "test-tenant";
    private static final UUID INCIDENT_ID = UUID.randomUUID();
    private static final String EVENT_TYPE = "IncidentOpenedEvent";
    private static final String ESCALATED_EVENT_TYPE = "IncidentEscalatedEvent";

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        notificationService = new NotificationService(
                router, logRepository, queueRepository, persistenceService,
                operatorAlertService, meterRegistry);
    }

    // ── enqueue ───────────────────────────────────────────────────────────

    @Nested
    @DisplayName("enqueue")
    class Enqueue {

        @Test
        @DisplayName("should write PENDING queue entry")
        void shouldWritePendingEntry() {
            given(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                    INCIDENT_ID, TENANT_ID, EVENT_TYPE, 0)).willReturn(false);
            given(queueRepository.save(any())).willAnswer(i -> i.getArgument(0));

            notificationService.enqueue(
                    EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", 0, null, null);

            final ArgumentCaptor<NotificationQueueEntry> captor =
                    ArgumentCaptor.forClass(NotificationQueueEntry.class);
            then(queueRepository).should().save(captor.capture());

            final NotificationQueueEntry saved = captor.getValue();
            assertThat(saved.getIncidentId()).isEqualTo(INCIDENT_ID);
            assertThat(saved.getTenantId()).isEqualTo(TENANT_ID);
            assertThat(saved.getEventType()).isEqualTo(EVENT_TYPE);
            assertThat(saved.getSeverity()).isEqualTo(Severity.CRITICAL);
            assertThat(saved.getStatus()).isEqualTo(NotificationQueueStatus.PENDING);
        }

        @Test
        @DisplayName("should be idempotent — skip if already queued")
        void shouldSkipIfAlreadyQueued() {
            given(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                    INCIDENT_ID, TENANT_ID, EVENT_TYPE, 0)).willReturn(true);

            notificationService.enqueue(
                    EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", 0, null, null);

            then(queueRepository).should(never()).save(any());
        }

        @Test
        @DisplayName("should store the escalation level and target on the entry")
        void shouldStoreEscalationContext() {
            final UUID escalateTo = UUID.randomUUID();
            given(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                    INCIDENT_ID, TENANT_ID, ESCALATED_EVENT_TYPE, 2)).willReturn(false);
            given(queueRepository.save(any())).willAnswer(i -> i.getArgument(0));

            notificationService.enqueue(
                    ESCALATED_EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", 2, escalateTo, null);

            final ArgumentCaptor<NotificationQueueEntry> captor =
                    ArgumentCaptor.forClass(NotificationQueueEntry.class);
            then(queueRepository).should().save(captor.capture());
            assertThat(captor.getValue().getEscalationLevel()).isEqualTo(2);
            assertThat(captor.getValue().getEscalateTo()).isEqualTo(escalateTo);
        }

        @Test
        @DisplayName("should store the teamId on the entry (backlog #0-12)")
        void shouldStoreTeamId() {
            final UUID teamId = UUID.randomUUID();
            given(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                    INCIDENT_ID, TENANT_ID, EVENT_TYPE, 0)).willReturn(false);
            given(queueRepository.save(any())).willAnswer(i -> i.getArgument(0));

            notificationService.enqueue(
                    EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", 0, null, teamId);

            final ArgumentCaptor<NotificationQueueEntry> captor =
                    ArgumentCaptor.forClass(NotificationQueueEntry.class);
            then(queueRepository).should().save(captor.capture());
            assertThat(captor.getValue().getTeamId()).isEqualTo(teamId);
        }

        /**
         * Regression test: idempotency used to be keyed on
         * (incidentId, eventType) only, so once the level-1 escalation was
         * queued the level-2 (MANAGER) escalation for the same incident was
         * discarded as a duplicate and never sent.
         */
        @Test
        @DisplayName("should queue a level-2 escalation even though level 1 already exists")
        void shouldQueueLevel2EvenWhenLevel1Exists() {
            // Level 1 is already queued for this incident, but the idempotency
            // check must only consider the entry's own level (2).
            given(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                    INCIDENT_ID, TENANT_ID, ESCALATED_EVENT_TYPE, 2)).willReturn(false);
            given(queueRepository.save(any())).willAnswer(i -> i.getArgument(0));

            notificationService.enqueue(
                    ESCALATED_EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", 2, null, null);

            then(queueRepository).should().save(any());
            then(queueRepository).should(never())
                    .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                            INCIDENT_ID, TENANT_ID, ESCALATED_EVENT_TYPE, 1);
        }

        @Test
        @DisplayName("should still skip a redelivered escalation of the same level")
        void shouldSkipRedeliveredEscalationOfSameLevel() {
            given(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                    INCIDENT_ID, TENANT_ID, ESCALATED_EVENT_TYPE, 1)).willReturn(true);

            notificationService.enqueue(
                    ESCALATED_EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", 1, null, null);

            then(queueRepository).should(never()).save(any());
        }

        @Test
        @DisplayName("should not call router or channels — fast path only")
        void shouldNotCallRouterOrChannels() {
            given(queueRepository.existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                    INCIDENT_ID, TENANT_ID, EVENT_TYPE, 0)).willReturn(false);
            given(queueRepository.save(any())).willAnswer(i -> i.getArgument(0));

            notificationService.enqueue(
                    EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", 0, null, null);

            then(router).shouldHaveNoInteractions();
            then(emailChannel).shouldHaveNoInteractions();
            then(slackChannel).shouldHaveNoInteractions();
        }
    }

    // ── processEntry ──────────────────────────────────────────────────────

    @Nested
    @DisplayName("processEntry")
    class ProcessEntry {

        @Test
        @DisplayName("should send through each routed channel")
        void shouldSendThroughEachChannel() {
            final NotificationQueueEntry entry = buildPendingEntry();
            final NotificationRequest emailRequest = buildRequest("EMAIL");
            final NotificationRequest slackRequest = buildRequest("SLACK");

            given(emailChannel.channelName()).willReturn("EMAIL");
            given(slackChannel.channelName()).willReturn("SLACK");
            given(router.route(EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", null, null))
                    .willReturn(NotificationRouter.Routing.send(List.of(
                            new NotificationRouter.ChannelRequest(emailChannel, emailRequest),
                            new NotificationRouter.ChannelRequest(slackChannel, slackRequest)
                    )));

            notificationService.processEntry(entry);

            then(emailChannel).should(times(1)).send(emailRequest);
            then(slackChannel).should(times(1)).send(slackRequest);
        }

        @Test
        @DisplayName("should record a SENT log entry after successful send")
        void shouldRecordSentLog() {
            final NotificationQueueEntry entry = buildPendingEntry();
            final NotificationRequest request = buildRequest("EMAIL");
            given(emailChannel.channelName()).willReturn("EMAIL");
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.send(List.of(
                            new NotificationRouter.ChannelRequest(emailChannel, request))));

            notificationService.processEntry(entry);

            then(persistenceService).should().recordChannelSent(
                    eq(INCIDENT_ID), eq(TENANT_ID), eq(EVENT_TYPE), eq(0), eq("EMAIL"),
                    eq(request.recipient()), eq(request.subject()), eq(request.message()));
        }

        @Test
        @DisplayName("should mark queue entry SENT after processing, via persistenceService")
        void shouldMarkQueueEntrySent() {
            final NotificationQueueEntry entry = buildPendingEntry();
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.nothingToSend());

            notificationService.processEntry(entry);

            then(persistenceService).should().markSent(entry);
        }

        /**
         * Backlog #0-84: the delivered notification's log row and audit event
         * are one write now, made after the send. Its failure is not a failed
         * send (it used to land in the send's catch and record one), and does
         * not fail the entry: the other channels are still tried.
         */
        @Test
        @DisplayName("a delivered notification that cannot be recorded is counted, not recorded as failed")
        void deliveredButUnrecorded() {
            final NotificationQueueEntry entry = buildPendingEntry();
            final NotificationRequest emailRequest = buildRequest("EMAIL");
            final NotificationRequest slackRequest = buildRequest("SLACK");
            given(emailChannel.channelName()).willReturn("EMAIL");
            given(slackChannel.channelName()).willReturn("SLACK");
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.send(List.of(
                            new NotificationRouter.ChannelRequest(emailChannel, emailRequest),
                            new NotificationRouter.ChannelRequest(slackChannel, slackRequest)
                    )));
            willThrow(new IllegalStateException("database down")).given(persistenceService)
                    .recordChannelSent(any(), any(), any(), anyInt(), eq("EMAIL"), any(), any(), any());

            notificationService.processEntry(entry);

            then(persistenceService).should(never())
                    .recordChannelFailed(any(), any(), any(), anyInt(), any(), any(), any(), any());
            then(slackChannel).should().send(slackRequest);
            then(persistenceService).should().recordChannelSent(
                    eq(INCIDENT_ID), eq(TENANT_ID), eq(EVENT_TYPE), eq(0), eq("SLACK"),
                    eq(slackRequest.recipient()), any(), any());
            then(persistenceService).should().markSent(entry);
            assertThat(meterRegistry.counter("audit.event.unrecorded", "event_type", "NOTIFICATION_SENT").count())
                    .isEqualTo(1.0);
        }

        /**
         * Found in review: a failure to record a failed send left the loop,
         * so the remaining channels were never tried.
         */
        @Test
        @DisplayName("a failed send that cannot be recorded is counted, and the other channels are still tried")
        void failedButUnrecorded() {
            final NotificationQueueEntry entry = buildPendingEntry();
            final NotificationRequest emailRequest = buildRequest("EMAIL");
            final NotificationRequest slackRequest = buildRequest("SLACK");
            given(emailChannel.channelName()).willReturn("EMAIL");
            given(slackChannel.channelName()).willReturn("SLACK");
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.send(List.of(
                            new NotificationRouter.ChannelRequest(emailChannel, emailRequest),
                            new NotificationRouter.ChannelRequest(slackChannel, slackRequest)
                    )));
            willThrow(new NotificationException("EMAIL", "test@test.com",
                    NotificationFailureReason.EMAIL_TRANSPORT_UNAVAILABLE, null))
                    .given(emailChannel).send(emailRequest);
            willThrow(new IllegalStateException("database down")).given(persistenceService)
                    .recordChannelFailed(any(), any(), any(), anyInt(), eq("EMAIL"), any(), any(), any());

            notificationService.processEntry(entry);

            then(slackChannel).should().send(slackRequest);
            then(persistenceService).should().markSent(entry);
            assertThat(meterRegistry.counter("audit.event.unrecorded", "event_type", "NOTIFICATION_FAILED").count())
                    .isEqualTo(1.0);
        }

        @Test
        @DisplayName("an unexpected send error is recorded as a failed send, by its type only (found in review)")
        void unexpectedSendError() {
            final NotificationQueueEntry entry = buildPendingEntry();
            final NotificationRequest emailRequest = buildRequest("EMAIL");
            given(emailChannel.channelName()).willReturn("EMAIL");
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.send(List.of(
                            new NotificationRouter.ChannelRequest(emailChannel, emailRequest))));
            willThrow(new IllegalStateException("GET https://hooks.example/T0/secret-path failed"))
                    .given(emailChannel).send(emailRequest);

            notificationService.processEntry(entry);

            then(persistenceService).should().recordChannelFailed(
                    eq(INCIDENT_ID), eq(TENANT_ID), eq(EVENT_TYPE), eq(0), eq("EMAIL"),
                    eq(emailRequest.recipient()), eq("UNEXPECTED"), eq("Unexpected error: IllegalStateException"));
            assertThat(meterRegistry.counter("notification.channel.failed", "channel", "EMAIL",
                    "reason", "UNEXPECTED").count()).isEqualTo(1.0);
            then(persistenceService).should(never())
                    .recordChannelSent(any(), any(), any(), anyInt(), any(), any(), any(), any());
            then(persistenceService).should().markSent(entry);
        }

        /**
         * Backlog #0-93 (review): operators alert on ERROR, so a failure that is
         * the platform's (permanent() false) must be logged at ERROR, and one the
         * tenant has to fix (permanent() true) at WARN, with the provider's own
         * error attached as the exception and never in the message.
         */
        @Test
        @DisplayName("a failure is logged at WARN when it is the tenant's to fix, ERROR when the platform's, the "
                + "provider's error attached")
        void logLevelFollowsPermanence() {
            final ch.qos.logback.classic.Logger logger =
                    (ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(NotificationService.class);
            final ch.qos.logback.core.read.ListAppender<ch.qos.logback.classic.spi.ILoggingEvent> appender =
                    new ch.qos.logback.core.read.ListAppender<>();
            appender.start();
            logger.addAppender(appender);
            try {
                for (final NotificationFailureReason reason : List.of(
                        NotificationFailureReason.EMAIL_RECIPIENT_REJECTED,
                        NotificationFailureReason.EMAIL_AUTHENTICATION_FAILED)) {
                    final NotificationRequest emailRequest = buildRequest("EMAIL");
                    given(emailChannel.channelName()).willReturn("EMAIL");
                    given(router.route(any(), any(), any(), any(), any(), any(), any()))
                            .willReturn(NotificationRouter.Routing.send(List.of(
                                    new NotificationRouter.ChannelRequest(emailChannel, emailRequest))));
                    willThrow(new NotificationException("EMAIL", "test@test.com", reason,
                            new IllegalStateException("535 relay smtp.internal said no")))
                            .given(emailChannel).send(emailRequest);

                    notificationService.processEntry(buildPendingEntry());
                }
            } finally {
                logger.detachAppender(appender);
            }

            final var failures = appender.list.stream()
                    .filter(e -> e.getFormattedMessage().startsWith("Notification failed:")).toList();
            assertThat(failures).hasSize(2);
            assertThat(failures.get(0).getLevel()).isEqualTo(ch.qos.logback.classic.Level.WARN);
            assertThat(failures.get(0).getFormattedMessage()).contains("EMAIL_RECIPIENT_REJECTED")
                    .doesNotContain("smtp.internal");
            assertThat(failures.get(1).getLevel()).isEqualTo(ch.qos.logback.classic.Level.ERROR);
            assertThat(failures.get(1).getFormattedMessage()).contains("EMAIL_AUTHENTICATION_FAILED");
            assertThat(failures).allSatisfy(e -> assertThat(e.getThrowableProxy()).isNotNull());
        }

        @Test
        @DisplayName("should record a FAILED log and continue when channel throws")
        void shouldRecordFailedLogOnChannelException() {
            final NotificationQueueEntry entry = buildPendingEntry();
            final NotificationRequest emailRequest = buildRequest("EMAIL");
            final NotificationRequest slackRequest = buildRequest("SLACK");

            given(emailChannel.channelName()).willReturn("EMAIL");
            given(slackChannel.channelName()).willReturn("SLACK");
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.send(List.of(
                            new NotificationRouter.ChannelRequest(emailChannel, emailRequest),
                            new NotificationRouter.ChannelRequest(slackChannel, slackRequest)
                    )));

            // The cause is what the mail library said; it must not be recorded (backlog #0-93).
            willThrow(new NotificationException("EMAIL", "test@test.com",
                    NotificationFailureReason.EMAIL_RECIPIENT_REJECTED,
                    new IllegalStateException("550 5.1.1 <test@test.com> unknown; relay smtp.internal:587")))
                    .given(emailChannel).send(emailRequest);

            notificationService.processEntry(entry);

            // Slack still called despite email failure
            then(slackChannel).should(times(1)).send(slackRequest);

            then(persistenceService).should().recordChannelFailed(
                    eq(INCIDENT_ID), eq(TENANT_ID), eq(EVENT_TYPE), eq(0), eq("EMAIL"),
                    eq(emailRequest.recipient()), eq("EMAIL_RECIPIENT_REJECTED"),
                    eq("EMAIL_RECIPIENT_REJECTED: The mail server rejected the recipient address"));
            assertThat(meterRegistry.counter("notification.channel.failed", "channel", "EMAIL",
                    "reason", "EMAIL_RECIPIENT_REJECTED").count()).isEqualTo(1.0);
            then(persistenceService).should().recordChannelSent(
                    eq(INCIDENT_ID), eq(TENANT_ID), eq(EVENT_TYPE), eq(0), eq("SLACK"),
                    eq(slackRequest.recipient()), any(), any());

            // Queue entry still marked SENT — individual failures recorded in log
            then(persistenceService).should().markSent(entry);
        }

        @Test
        @DisplayName("should skip channel if already logged — idempotency")
        void shouldSkipIfAlreadySent() {
            final NotificationQueueEntry entry = buildPendingEntry();
            final NotificationRequest request = buildRequest("EMAIL");
            given(emailChannel.channelName()).willReturn("EMAIL");
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.send(List.of(
                            new NotificationRouter.ChannelRequest(emailChannel, request))));
            given(logRepository
                    .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevelAndChannel(
                            INCIDENT_ID, TENANT_ID, EVENT_TYPE, 0, "EMAIL")).willReturn(true);

            notificationService.processEntry(entry);

            then(emailChannel).should(never()).send(any());
            then(persistenceService).should(never())
                    .recordChannelSent(any(), any(), any(), anyInt(), any(), any(), any(), any());
        }

        @Test
        @DisplayName("should pass the entry's escalateTo to the router (backlog #0-1)")
        void shouldPassEscalateToToRouter() {
            final UUID escalateTo = UUID.randomUUID();
            final NotificationQueueEntry entry = buildEscalationEntry(1, escalateTo);
            given(router.route(ESCALATED_EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", escalateTo, null))
                    .willReturn(NotificationRouter.Routing.nothingToSend());

            notificationService.processEntry(entry);

            then(router).should().route(ESCALATED_EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", escalateTo, null);
        }

        @Test
        @DisplayName("should pass the entry's teamId to the router (backlog #0-12)")
        void shouldPassTeamIdToRouter() {
            final UUID teamId = UUID.randomUUID();
            final NotificationQueueEntry entry = NotificationQueueEntry.pending(
                    INCIDENT_ID, TENANT_ID, EVENT_TYPE,
                    Severity.CRITICAL, "High CPU", 0, null, teamId);
            given(router.route(EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", null, teamId))
                    .willReturn(NotificationRouter.Routing.nothingToSend());

            notificationService.processEntry(entry);

            then(router).should().route(EVENT_TYPE, INCIDENT_ID, TENANT_ID,
                    Severity.CRITICAL, "High CPU", null, teamId);
        }

        @Test
        @DisplayName("should send a level-2 escalation on a channel already used by level 1")
        void shouldSendLevel2OnChannelUsedByLevel1() {
            final NotificationQueueEntry entry = buildEscalationEntry(2);
            final NotificationRequest request = buildRequest("EMAIL");
            given(emailChannel.channelName()).willReturn("EMAIL");
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.send(List.of(
                            new NotificationRouter.ChannelRequest(emailChannel, request))));
            // Level 1 already sent EMAIL for this incident + event type, but
            // the idempotency check only looks at this entry's own level (2).
            given(logRepository
                    .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevelAndChannel(
                            INCIDENT_ID, TENANT_ID, ESCALATED_EVENT_TYPE, 2, "EMAIL"))
                    .willReturn(false);

            notificationService.processEntry(entry);

            then(logRepository).should(never())
                    .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevelAndChannel(
                            INCIDENT_ID, TENANT_ID, ESCALATED_EVENT_TYPE, 1, "EMAIL");
            then(emailChannel).should().send(request);
            then(persistenceService).should().recordChannelSent(
                    eq(INCIDENT_ID), eq(TENANT_ID), eq(ESCALATED_EVENT_TYPE),
                    eq(2), eq("EMAIL"), eq(request.recipient()),
                    eq(request.subject()), eq(request.message()));
        }

        @Test
        @DisplayName("should mark SENT and not call channels when router returns empty")
        void shouldMarkSentWhenNoChannels() {
            final NotificationQueueEntry entry = buildPendingEntry();
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.nothingToSend());

            notificationService.processEntry(entry);

            then(emailChannel).shouldHaveNoInteractions();
            then(persistenceService).should().markSent(entry);
        }

        /**
         * Regression test for backlog #42's core fix: verifies
         * processEntry() itself no longer touches logRepository/
         * queueRepository for writes at all — every write goes through
         * persistenceService, which is what makes it possible for
         * NotificationPersistenceService's own short transactions to be
         * genuinely independent of the (no longer existing) outer one.
         */
        @Test
        @DisplayName("never calls logRepository.save or queueRepository.save directly")
        void neverCallsRepositoriesDirectlyForWrites() {
            final NotificationQueueEntry entry = buildPendingEntry();
            final NotificationRequest request = buildRequest("EMAIL");
            given(emailChannel.channelName()).willReturn("EMAIL");
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.send(List.of(
                            new NotificationRouter.ChannelRequest(emailChannel, request))));

            notificationService.processEntry(entry);

            then(logRepository).should(never()).save(any());
            then(queueRepository).should(never()).save(any());
        }
    }

    // ── undeliverable (backlog #0-18) ─────────────────────────────────────

    @Nested
    @DisplayName("undeliverable — nobody in the tenant can be notified (backlog #0-18)")
    class Undeliverable {

        private double count(String eventType, UndeliverableReason reason) {
            return meterRegistry.counter("notification.undeliverable",
                    "event_type", eventType, "reason", reason.name()).count();
        }

        @Test
        @DisplayName("parks the entry (its audit event written with it), counts it, tells the operator, sends nothing")
        void parksAndAlertsForAnOpenedIncident() {
            final NotificationQueueEntry entry = buildPendingEntry();
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.undeliverable(
                            UndeliverableReason.NO_ONCALL));
            parks(entry, UndeliverableReason.NO_ONCALL);

            notificationService.processEntry(entry);

            then(persistenceService).should()
                    .markUndeliverable(entry, UndeliverableReason.NO_ONCALL);
            then(persistenceService).should(never()).markSent(any());
            then(persistenceService).should(never())
                    .recordChannelSent(any(), any(), any(), anyInt(), any(), any(), any(), any());
            then(operatorAlertService).should().undeliverable(
                    INCIDENT_ID, TENANT_ID, EVENT_TYPE, UndeliverableReason.NO_ONCALL);
            assertThat(count(EVENT_TYPE, UndeliverableReason.NO_ONCALL)).isEqualTo(1.0);
        }

        @Test
        @DisplayName("counts every skipped channel — a missing address is never silent")
        void countsSkippedChannels() {
            final NotificationQueueEntry entry = buildPendingEntry();
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.undeliverable(
                            UndeliverableReason.NO_REACHABLE_CHANNEL, List.of("SLACK", "SMS")));

            notificationService.processEntry(entry);

            assertThat(meterRegistry.counter("notification.channel_skipped",
                    "channel", "SLACK", "event_type", EVENT_TYPE).count()).isEqualTo(1.0);
            assertThat(meterRegistry.counter("notification.channel_skipped",
                    "channel", "SMS", "event_type", EVENT_TYPE).count()).isEqualTo(1.0);
        }

        @Test
        @DisplayName("tells the operator for an escalation too")
        void alertsForAnEscalation() {
            final NotificationQueueEntry entry = buildEscalationEntry(1, UUID.randomUUID());
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.undeliverable(
                            UndeliverableReason.NO_REACHABLE_CHANNEL));
            parks(entry, UndeliverableReason.NO_REACHABLE_CHANNEL);

            notificationService.processEntry(entry);

            then(operatorAlertService).should().undeliverable(
                    INCIDENT_ID, TENANT_ID, ESCALATED_EVENT_TYPE,
                    UndeliverableReason.NO_REACHABLE_CHANNEL);
        }

        @Test
        @DisplayName("does not alert the operator for an event nobody has to act on, but still parks and counts it")
        void noAlertForResolved() {
            final NotificationQueueEntry entry = NotificationQueueEntry.pending(
                    INCIDENT_ID, TENANT_ID, "IncidentResolvedEvent",
                    Severity.CRITICAL, "High CPU");
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.undeliverable(
                            UndeliverableReason.NO_ONCALL));
            parks(entry, UndeliverableReason.NO_ONCALL);

            notificationService.processEntry(entry);

            then(persistenceService).should()
                    .markUndeliverable(entry, UndeliverableReason.NO_ONCALL);
            then(operatorAlertService).shouldHaveNoInteractions();
            assertThat(count("IncidentResolvedEvent", UndeliverableReason.NO_ONCALL))
                    .isEqualTo(1.0);
        }

        @Test
        @DisplayName("nothing to send (no channel configured) is still marked SENT, not undeliverable")
        void nothingToSendIsSent() {
            final NotificationQueueEntry entry = buildPendingEntry();
            given(router.route(any(), any(), any(), any(), any(), any(), any()))
                    .willReturn(NotificationRouter.Routing.nothingToSend());

            notificationService.processEntry(entry);

            then(persistenceService).should().markSent(entry);
            then(persistenceService).should(never()).markUndeliverable(any(), any());
            then(operatorAlertService).shouldHaveNoInteractions();
        }

        /**
         * Found in review: a failed write of the UNDELIVERABLE status (and its
         * audit event) used to skip the operator alert, though nobody had been
         * notified either way. The failure still reaches the caller.
         */
        @Test
        @DisplayName("the operator is alerted even when the UNDELIVERABLE write fails, which is rethrown")
        void alertsWhenUndeliverableWriteFails() {
            final NotificationQueueEntry entry = buildPendingEntry();
            willThrow(new IllegalStateException("database down")).given(persistenceService)
                    .markUndeliverable(entry, UndeliverableReason.NO_ONCALL);

            assertThatThrownBy(() ->
                    notificationService.markUndeliverable(entry, UndeliverableReason.NO_ONCALL))
                    .hasMessage("database down");

            then(operatorAlertService).should().undeliverable(
                    INCIDENT_ID, TENANT_ID, EVENT_TYPE, UndeliverableReason.NO_ONCALL);
            assertThat(count(EVENT_TYPE, UndeliverableReason.NO_ONCALL)).isZero();
        }

        @Test
        @DisplayName("an alert failure never hides the failed UNDELIVERABLE write (found in review)")
        void writeFailureNotMaskedByAlertFailure() {
            final NotificationQueueEntry entry = buildPendingEntry();
            final IllegalStateException writeFailure = new IllegalStateException("database down");
            willThrow(writeFailure).given(persistenceService)
                    .markUndeliverable(entry, UndeliverableReason.NO_ONCALL);
            willThrow(new IllegalStateException("smtp down")).given(operatorAlertService)
                    .undeliverable(any(), any(), any(), any());

            assertThatThrownBy(() -> notificationService.markUndeliverable(entry, UndeliverableReason.NO_ONCALL))
                    .isSameAs(writeFailure)
                    .satisfies(e -> assertThat(e.getSuppressed()).extracting(Throwable::getMessage)
                            .containsExactly("smtp down"));
        }

        @Test
        @DisplayName("markUndeliverable is callable by the scheduler for an oncall-service outage (backlog #0-19)")
        void markUndeliverableForOutage() {
            final NotificationQueueEntry entry = buildEscalationEntry(2, UUID.randomUUID());
            parks(entry, UndeliverableReason.ONCALL_UNAVAILABLE);

            notificationService.markUndeliverable(entry, UndeliverableReason.ONCALL_UNAVAILABLE);

            then(persistenceService).should()
                    .markUndeliverable(entry, UndeliverableReason.ONCALL_UNAVAILABLE);
            then(operatorAlertService).should().undeliverable(
                    INCIDENT_ID, TENANT_ID, ESCALATED_EVENT_TYPE,
                    UndeliverableReason.ONCALL_UNAVAILABLE);
        }

        /**
         * Backlog #0-25 (AC3): the entry was no longer PENDING, so the
         * conditional UPDATE changed nothing. Someone else closed it; this run
         * did not find it undeliverable, so nobody is alerted and nothing is
         * counted as undeliverable (the stale write is counted by the
         * persistence service).
         */
        @Test
        @DisplayName("an entry no longer PENDING raises no operator alert and is not counted as undeliverable")
        void markUndeliverableOnAStaleRowRaisesNoOperatorAlert() {
            final NotificationQueueEntry entry = buildPendingEntry();
            given(persistenceService.markUndeliverable(entry, UndeliverableReason.NO_ONCALL)).willReturn(false);

            notificationService.markUndeliverable(entry, UndeliverableReason.NO_ONCALL);

            then(operatorAlertService).shouldHaveNoInteractions();
            assertThat(count(EVENT_TYPE, UndeliverableReason.NO_ONCALL)).isZero();
        }

        /** The UNDELIVERABLE write changed the row (backlog #0-25: it returns whether it did). */
        private void parks(NotificationQueueEntry entry, UndeliverableReason reason) {
            given(persistenceService.markUndeliverable(entry, reason)).willReturn(true);
        }
    }

    // ── helpers ───────────────────────────────────────────────────────────

    private NotificationQueueEntry buildPendingEntry() {
        return NotificationQueueEntry.pending(
                INCIDENT_ID, TENANT_ID, EVENT_TYPE,
                Severity.CRITICAL, "High CPU");
    }

    private NotificationQueueEntry buildEscalationEntry(int escalationLevel) {
        return buildEscalationEntry(escalationLevel, null);
    }

    private NotificationQueueEntry buildEscalationEntry(int escalationLevel, UUID escalateTo) {
        return NotificationQueueEntry.pending(
                INCIDENT_ID, TENANT_ID, ESCALATED_EVENT_TYPE,
                Severity.CRITICAL, "High CPU", escalationLevel, escalateTo);
    }

    private NotificationRequest buildRequest(String channel) {
        return new NotificationRequest(
                INCIDENT_ID, TENANT_ID, EVENT_TYPE,
                "oncall@test-tenant.example.com",
                "[CRITICAL] High CPU Usage",
                "New CRITICAL incident detected",
                Severity.CRITICAL, "High CPU Usage");
    }
}