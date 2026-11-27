package com.incidentplatform.ingestion.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.incidentplatform.ingestion.normalizer.AlertNormalizer;
import com.incidentplatform.ingestion.normalizer.NormalizationException;
import com.incidentplatform.ingestion.normalizer.NormalizationResult;
import com.incidentplatform.ingestion.normalizer.UnknownSourceException;
import com.incidentplatform.shared.dto.UnifiedAlertDto;
import com.incidentplatform.shared.events.ResolvedAlertNotification;
import com.incidentplatform.shared.kafka.DeadLetterNotStoredException;
import com.incidentplatform.shared.kafka.DeadLetterPublisher;
import com.incidentplatform.shared.kafka.KafkaFailures;
import com.incidentplatform.shared.security.TenantIds;
import com.incidentplatform.shared.security.UserPrincipal;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
public class AlertIngestionService {

    private static final Logger log =
            LoggerFactory.getLogger(AlertIngestionService.class);

    private final Map<String, AlertNormalizer> normalizersBySource;
    private final DeduplicationService deduplicationService;
    private final AlertKafkaProducer kafkaProducer;
    private final DeadLetterPublisher deadLetterPublisher;
    private final Clock clock;

    @Autowired
    public AlertIngestionService(
            List<AlertNormalizer> normalizers,
            DeduplicationService deduplicationService,
            AlertKafkaProducer kafkaProducer,
            DeadLetterPublisher deadLetterPublisher) {
        this(normalizers, deduplicationService, kafkaProducer, deadLetterPublisher, Clock.systemUTC());
    }

    /** With the clock the dead-letter copies' deadline is read from (backlog #0-96; tests). */
    AlertIngestionService(
            List<AlertNormalizer> normalizers,
            DeduplicationService deduplicationService,
            AlertKafkaProducer kafkaProducer,
            DeadLetterPublisher deadLetterPublisher,
            Clock clock) {
        this.clock = clock;
        this.normalizersBySource = normalizers.stream()
                .collect(Collectors.toUnmodifiableMap(
                        AlertNormalizer::getSourceName,
                        Function.identity()
                ));
        this.deduplicationService = deduplicationService;
        this.kafkaProducer = kafkaProducer;
        this.deadLetterPublisher = deadLetterPublisher;

        log.info("AlertIngestionService initialized with normalizers: {}",
                normalizersBySource.keySet());
    }

    /**
     * Ingests an alert payload from an external monitoring system.
     *
     * <p>Changed (backlog #0-96): an alert that cannot be processed is copied
     * to the dead-letter topic and this method waits until Kafka has the copy.
     * It used to send it and move on, so a failed send lost the alert with
     * only an ERROR line, while the sender was told it was handled. Now the
     * request fails instead ({@link DeadLetterNotStoredException}, a 503 with
     * {@code Retry-After}) and the sender retries the whole payload: alerts
     * of the same payload already sent are then caught by deduplication, and
     * a dead-letter copy whose acknowledgement was lost may be stored twice
     * (at-least-once). Resolved notifications of the payload are sent again;
     * incident-service's auto-resolve is a no-op for an incident already
     * resolved.
     *
     * <p>Found in review: the copies of one request are started together and
     * awaited together, under one {@link DeadLetterPublisher#DEAD_LETTER_TIMEOUT}
     * (they used to be awaited one by one, each up to the producer's 60 s
     * metadata block); a payload whose alerts fail to serialize is copied once,
     * not once per alert; and when a copy is not stored, the dedup keys of the
     * alerts it was to keep are released, or the sender's retry would be
     * answered as a duplicate and the alert lost after all.
     *
     * @param teamId  resolved from the Integration ApiKey via
     *                {@code ApiKeyLookupServiceImpl.resolveTeamId()}.
     *                Null when authenticated with JWT or Integration has no team.
     *                Propagated to every {@link com.incidentplatform.shared.dto.UnifiedAlertDto}
     *                so incident-service can set {@code Incident.team_id}.
     * @throws DeadLetterNotStoredException if an alert that could not be
     *         processed could not be copied to the dead-letter topic either
     */
    public IngestionSummary ingest(String source,
                                   JsonNode rawPayload,
                                   String tenantId,
                                   UUID teamId) {
        // Backlog #0-92 (found in review): the tenant comes from the
        // authenticated key or token, so this is a programming error; checked
        // before anything is normalized or a dedup key is set, so a refusal
        // leaves no key behind that would turn a later retry into a duplicate.
        TenantIds.requireValid(tenantId);
        log.info("Starting ingestion: source={}, tenant={}, teamId={}",
                source, tenantId, teamId);

        final AlertNormalizer normalizer = findNormalizer(source);

        int processed = 0;
        int duplicates = 0;
        int resolved = 0;
        int deadLetter = 0;

        NormalizationResult result;
        try {
            result = normalizer.normalize(rawPayload, tenantId, teamId);
        } catch (NormalizationException e) {
            log.error("Normalization failed for entire payload: source={}, " +
                    "tenant={}, reason={}", source, tenantId, e.getReason());
            deadLetterPublisher.publishAndWait(rawPayload, source, tenantId, e.getReason());
            return IngestionSummary.of(1, 0, 0, 0, 1, false);
        }

        // Fixed: previously computed as result.firingAlerts().size() +
        // result.resolvedAlerts().size() — but those two lists are already
        // truncated by the time they reach here (see
        // NormalizationResult.totalReceived's Javadoc for the full
        // account). Using totalReceived reports the true, pre-truncation
        // count instead of silently reporting the smaller, already-capped
        // number as if it were the whole payload.
        final int received = result.totalReceived();

        // Fixed (backlog #69): PrometheusNormalizer now isolates a
        // malformed alert from the rest of its batch instead of letting
        // it abort normalization for the whole payload (see
        // NormalizationResult's own Javadoc for the full account). Each
        // one collected here is dead-lettered on its own, through the
        // same dead-letter copies (DeadLetterCopies) already used below for
        // serialization failures — this is simply a second source
        // reaching it, not a new mechanism — so the rest of this batch's
        // valid alerts are still processed normally in the loops below,
        // unaffected by however many malformed alerts came alongside them.
        // Backlog #0-96: started here, awaited together before the response.
        final DeadLetterCopies copies = new DeadLetterCopies(source, tenantId, rawPayload);
        for (NormalizationResult.MalformedAlert malformed : result.malformedAlerts()) {
            copies.add(deadLetterPublisher.publishAsync(
                    malformed.rawAlert(), source, tenantId,
                    "Alert normalization failed: " + malformed.reason()));
            deadLetter++;
        }

        for (UnifiedAlertDto alert : result.firingAlerts()) {
            try {
                if (deduplicationService.isDuplicate(alert)) {
                    duplicates++;
                    continue;
                }
                // Fixed (backlog #24): if the send subsequently fails
                // (broker unreachable — logged/counted inside
                // AlertKafkaProducer's own .whenComplete), release the
                // dedup key isDuplicate just set above. Without this, a
                // Kafka outage doesn't just lose the current alert — it
                // also silently rejects every retry of it as a "duplicate"
                // for the rest of the dedup TTL, since the key stays set
                // even though the alert was never actually delivered. See
                // DeduplicationService.releaseDedupKey's Javadoc for the
                // full account. This is a separate .whenComplete from
                // AlertKafkaProducer's own — that one handles metrics and
                // logging, this one handles the dedup-key compensation;
                // kept apart deliberately rather than merged into one
                // handler, so each class owns only its own concern.
                final CompletableFuture<?> sent;
                try {
                    sent = kafkaProducer.publishFiring(alert);
                } catch (RuntimeException synchronousFailure) {
                    // Thrown before anything was sent (other than the
                    // serialization failure caught below, which is
                    // dead-lettered): the key goes too, as for a failed
                    // send (found in review: it stayed set).
                    if (!(synchronousFailure instanceof AlertKafkaProducer.AlertPublishException)) {
                        deduplicationService.releaseDedupKey(alert);
                    }
                    throw synchronousFailure;
                }
                sent.whenComplete((sendResult, ex) -> {
                    if (ex != null) {
                        deduplicationService.releaseDedupKey(alert);
                    }
                });
                processed++;
            } catch (AlertKafkaProducer.AlertPublishException e) {
                // Despite the class name, this can only be thrown from a JSON
                // serialization failure inside AlertKafkaProducer — a genuinely
                // poison-pill scenario (this exact alert object will never
                // serialize, retrying won't help), which is why DLQ is the
                // right response here. It is NOT thrown for real Kafka send
                // failures (broker down, etc.) — those happen asynchronously
                // and never propagate to this catch block; see
                // AlertKafkaProducer's Javadoc for why and how those are
                // handled instead (a counter + log, no DLQ — a Kafka-based
                // DLQ can't help when Kafka itself is unreachable).
                // By type and place (backlog #0-96, found in review): the
                // cause is Jackson's, whose message can quote the alert.
                log.error("Failed to serialize firing alert for Kafka — " +
                                "routing to DLQ: alertId={}, source={}, tenant={}, cause={}",
                        alert.alertId(), source, tenantId, KafkaFailures.describe(e.getCause()));
                // Backlog #0-96: its dedup key stays set only once the copy is
                // stored (released in copies.await otherwise).
                // AlertPublishException's message is the platform's own (the
                // alert's id), never Jackson's, which would quote the alert.
                // Kept first: a copy failing at once releases it with the rest.
                copies.keepsAlert(alert);
                copies.rawPayload("Alert serialization failed: " + e.getMessage());
                deadLetter++;
            }
        }

        for (ResolvedAlertNotification notification : result.resolvedAlerts()) {
            try {
                kafkaProducer.publishResolved(notification);
                resolved++;
            } catch (AlertKafkaProducer.AlertPublishException e) {
                // Same caveat as above — serialization failure only, not a
                // real Kafka send failure.
                log.error("Failed to serialize resolved notification for Kafka — " +
                                "routing to DLQ: eventId={}, tenant={}, cause={}",
                        notification.eventId(), tenantId, KafkaFailures.describe(e.getCause()));
                copies.rawPayload("Resolved notification serialization failed: " + e.getMessage());
                deadLetter++;
            }
        }

        copies.await();

        final IngestionSummary summary = IngestionSummary.of(
                received, processed, duplicates, resolved, deadLetter,
                result.isTruncated());

        if (result.isTruncated()) {
            // Distinct from the dead-letter WARN below — truncation means
            // some alerts in the payload never even got a chance to be
            // processed, duplicated, or dead-lettered; they were dropped
            // before any of that logic ran at all. Logged here (not just
            // inside PrometheusNormalizer, which already logs its own WARN
            // at truncation time) so a search over AlertIngestionService's
            // own logs surfaces this, not just the normalizer's.
            log.warn("Ingestion payload was truncated — some alerts were " +
                            "never processed: source={}, tenant={}, " +
                            "totalReceived={}, actuallyHandled={}",
                    source, tenantId, received, result.totalProcessed());
        }

        if (summary.hasDeadLetterAlerts()) {
            log.warn("Ingestion completed with DLQ alerts: source={}, tenant={}, " +
                    "summary={}", source, tenantId, summary);
        } else {
            log.info("Ingestion completed successfully: source={}, tenant={}, " +
                    "summary={}", source, tenantId, summary);
        }

        return summary;
    }

    public List<String> getAvailableSources() {
        return List.copyOf(normalizersBySource.keySet());
    }

    /**
     * The dead-letter copies of one request (backlog #0-96): started as the
     * alerts are handled, awaited together, the raw payload copied at most
     * once, and the dedup keys of the alerts a copy was to keep released when
     * it is not stored.
     *
     * <p>Found in the second review: the deadline is counted from
     * {@link #await}, not from the first copy's start, or a slow loop between
     * them (Redis, the alerts' own sends) used up the time and answered 503
     * for copies Kafka was still taking; and no copy is started once one has
     * failed (each start may block for Kafka's metadata, up to
     * {@code DEAD_LETTER_MAX_BLOCK}, so N malformed alerts used to block N
     * times while Kafka was down).
     */
    private final class DeadLetterCopies {

        private final String source;
        private final String tenantId;
        private final JsonNode rawPayload;
        private final List<CompletableFuture<Void>> started = new ArrayList<>();
        private final List<UnifiedAlertDto> kept = new ArrayList<>();
        private boolean rawPayloadCopied;

        DeadLetterCopies(String source, String tenantId, JsonNode rawPayload) {
            this.source = source;
            this.tenantId = tenantId;
            this.rawPayload = rawPayload;
        }

        /** @throws DeadLetterNotStoredException at once when this copy already failed */
        void add(CompletableFuture<Void> copy) {
            started.add(copy);
            // Only the new copy (found in review: every add scanned every
            // copy). While Kafka is down a copy fails as it starts, after at
            // most DEAD_LETTER_MAX_BLOCK, so the next alert starts none; an
            // earlier copy failing later is caught by await.
            if (copy.isCompletedExceptionally()) {
                fail(copy);
            }
        }

        /** The whole payload, once per request, whatever the number of alerts it stands for. */
        void rawPayload(String reason) {
            if (!rawPayloadCopied) {
                rawPayloadCopied = true;
                add(deadLetterPublisher.publishAsync(rawPayload, source, tenantId, reason));
            }
        }

        /** An alert whose dedup key was set and is kept only through a copy. */
        void keepsAlert(UnifiedAlertDto alert) {
            kept.add(alert);
        }

        /** @throws DeadLetterNotStoredException after releasing the kept alerts' dedup keys */
        void await() {
            if (started.isEmpty()) {
                return;
            }
            try {
                deadLetterPublisher.await(started, clock.instant());
            } catch (DeadLetterNotStoredException e) {
                kept.forEach(deduplicationService::releaseDedupKey);
                throw e;
            }
        }

        private void fail(CompletableFuture<Void> failed) {
            kept.forEach(deduplicationService::releaseDedupKey);
            try {
                failed.join();
            } catch (CompletionException e) {
                throw e.getCause() instanceof DeadLetterNotStoredException notStored
                        ? notStored
                        : new DeadLetterNotStoredException("Dead-letter record not stored", e.getCause());
            }
            throw new IllegalStateException("A failed copy completed normally");
        }
    }

    private AlertNormalizer findNormalizer(String source) {
        final AlertNormalizer normalizer = normalizersBySource.get(
                source.toLowerCase(Locale.ROOT));
        if (normalizer == null) {
            throw new UnknownSourceException(source,
                    List.copyOf(normalizersBySource.keySet()));
        }
        return normalizer;
    }
}