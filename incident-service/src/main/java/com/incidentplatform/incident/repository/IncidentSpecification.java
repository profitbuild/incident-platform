package com.incidentplatform.incident.repository;

import com.incidentplatform.incident.domain.Incident;
import com.incidentplatform.incident.domain.IncidentStatus;
import com.incidentplatform.incident.dto.IncidentFilter;
import jakarta.persistence.criteria.Predicate;
import org.springframework.data.jpa.domain.Specification;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class IncidentSpecification {

    private IncidentSpecification() {
        throw new UnsupportedOperationException("Utility class");
    }

    public static Specification<Incident> withFilter(String tenantId,
                                                     IncidentFilter filter) {
        return (root, query, criteriaBuilder) -> {
            final List<Predicate> predicates = new ArrayList<>();

            predicates.add(criteriaBuilder.equal(
                    root.get("tenantId"), tenantId));

            if (filter.status() != null) {
                predicates.add(criteriaBuilder.equal(
                        root.get("status"), filter.status()));
            }

            if (filter.severity() != null) {
                predicates.add(criteriaBuilder.equal(
                        root.get("severity"), filter.severity()));
            }

            if (filter.sourceType() != null) {
                predicates.add(criteriaBuilder.equal(
                        root.get("sourceType"), filter.sourceType()));
            }

            if (filter.source() != null && !filter.source().isBlank()) {
                // lower() on both sides: criteriaBuilder.lower() pushes LOWER()
                // to the database, filter.source().toLowerCase(Locale.ROOT) normalises the
                // parameter in Java. Together they make the filter case-insensitive
                // even if a row was inserted via a path that bypassed the
                // UnifiedAlertDto compact-constructor normalisation (e.g. a direct
                // SQL INSERT, a data-import script, or a test fixture).
                // The V7 migration adds a CHECK (source = lower(source)) constraint
                // as a second layer of defence — see that migration for rationale.
                predicates.add(criteriaBuilder.equal(
                        criteriaBuilder.lower(root.get("source")),
                        filter.source().toLowerCase(Locale.ROOT)));
            }

            if (filter.teamId() != null) {
                predicates.add(criteriaBuilder.equal(
                        root.get("teamId"), filter.teamId()));
            }

            if (query != null && query.getResultType() != Long.class) {
                query.orderBy(criteriaBuilder.desc(root.get("createdAt")));
            }

            return criteriaBuilder.and(
                    predicates.toArray(new Predicate[0]));
        };
    }

    public static Specification<Incident> active() {
        return (root, query, criteriaBuilder) ->
                criteriaBuilder.notEqual(
                        root.get("status"), IncidentStatus.CLOSED);
    }
}