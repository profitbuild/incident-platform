package com.incidentplatform.shared.domain;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

import java.util.Locale;

// Enum reprezentujący poziom severity incydentu/alertu.
// Centralna definicja domenowa używana przez wszystkie serwisy —
// eliminuje duplikację switch/String w każdym serwisie osobno.
//
// Jackson serializuje enum do String przez @JsonValue (name()) i
// deserializuje przez @JsonCreator (fromString) — kompatybilne z
// istniejącym formatem JSON i schematem bazy danych (VARCHAR).
//
// Exhaustive switch wymusza obsługę nowych wartości przez kompilator —
// dodanie nowego severity bez aktualizacji switchów = błąd kompilacji.
public enum Severity {

    LOW(1),
    MEDIUM(2),
    HIGH(3),
    CRITICAL(4);

    private final int weight;

    Severity(int weight) {
        this.weight = weight;
    }

    public int weight() {
        return weight;
    }

    // Porównuje czy ten poziom severity jest wyższy niż podany.
    // Używany przy deduplikacji alertów — aktualizujemy severity incydentu
    // tylko gdy nowy alert ma wyższy priorytet niż istniejący.
    public boolean isHigherThan(Severity other) {
        return this.weight > other.weight;
    }

    // @JsonValue — Jackson serializuje enum jako jego name() (np. "CRITICAL")
    // Zachowuje kompatybilność z istniejącym formatem JSON i kolumną VARCHAR w bazie.
    @JsonValue
    public String toJson() {
        return this.name();
    }

    @JsonCreator
    public static Severity fromString(String value) {
        if (value == null) {
            throw new IllegalArgumentException("Severity value cannot be null");
        }
        // Locale.ROOT: under a Turkish default "critical" would upper-case to "CRİTİCAL" (backlog #0-323)
        return switch (value.toUpperCase(Locale.ROOT)) {
            case "CRITICAL" -> CRITICAL;
            case "HIGH"     -> HIGH;
            case "MEDIUM"   -> MEDIUM;
            case "LOW"      -> LOW;
            default -> throw new IllegalArgumentException(
                    "Unknown severity value: '" + value + "'. " +
                            "Allowed values: CRITICAL, HIGH, MEDIUM, LOW");
        };
    }
}