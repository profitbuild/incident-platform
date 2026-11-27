package com.incidentplatform.auth.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.net.URLEncoder;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

/**
 * TOTP (Time-based One-Time Password) implementation per RFC 6238.
 *
 * <h2>Algorithm overview</h2>
 * <pre>
 * 1. secret (base32) → raw bytes (key)
 * 2. timeStep = floor(unixSeconds / 30)
 * 3. HMAC-SHA1(key, timeStep as 8-byte big-endian) → 20-byte hash
 * 4. Dynamic truncation: offset = hash[19] & 0x0F
 *    binary = (hash[offset..offset+4]) & 0x7FFFFFFF
 * 5. code = binary % 10^6  (6 digits, zero-padded)
 * </pre>
 *
 * <h2>Time window tolerance</h2>
 * Verifies codes for t-1, t, t+1 (±30 seconds).
 * This tolerates minor clock drift between server and authenticator app.
 *
 * <h2>Constant-time comparison</h2>
 * Uses {@link MessageDigest#isEqual} instead of {@link String#equals} to
 * prevent timing attacks — an attacker cannot determine how many digits
 * matched by measuring response time.
 *
 * <h2>No external dependencies</h2>
 * Uses only JDK crypto ({@code javax.crypto.Mac}, {@code HmacSHA1}) and
 * Apache Commons Codec ({@code Base32}) which is already on classpath via
 * Spring Boot's dependency on commons-codec.
 */
@Service
public class TotpService {

    private static final int    CODE_DIGITS  = 6;
    private static final int    TIME_STEP    = 30;      // seconds
    private static final int    WINDOW       = 1;       // ±1 time step
    private static final int    CODE_MODULUS = 1_000_000; // 10^6
    private static final int    SECRET_BYTES = 20;      // 160 bits — SHA-1 output size
    private static final int    BACKUP_CODE_COUNT  = 8;
    private static final int    BACKUP_CODE_LENGTH = 8;  // characters
    private static final String BACKUP_CODE_CHARS  =
            "abcdefghjkmnpqrstuvwxyz23456789"; // 32 chars, no confusables (0,1,i,l,o)

    private final String issuer;
    private final SecureRandom secureRandom = new SecureRandom();

    public TotpService(@Value("${mfa.totp.issuer:IncidentPlatform}") String issuer) {
        this.issuer = issuer;
    }

    // ── Secret generation ─────────────────────────────────────────────────

    /**
     * Generates a random base32-encoded TOTP secret.
     *
     * <p>20 bytes = 160 bits = SHA-1 output size. RFC 6238 recommends key length
     * matching HMAC output — using HmacSHA1, that is 160 bits.
     *
     * @return base32-encoded secret (e.g. "JBSWY3DPEHPK3PXP")
     */
    public String generateSecret() {
        final byte[] bytes = new byte[SECRET_BYTES];
        secureRandom.nextBytes(bytes);
        return base32Encode(bytes);
    }

    // ── QR code URL ───────────────────────────────────────────────────────

    /**
     * Generates an {@code otpauth://} URL for QR code display.
     *
     * <p>Format per Google Authenticator Key URI Format spec:
     * {@code otpauth://totp/{issuer}:{account}?secret={secret}&issuer={issuer}}
     *
     * @param secret    base32 TOTP secret
     * @param email     user's email (shown in authenticator app)
     * @param tenantId  tenant identifier
     * @return URL suitable for encoding into a QR code
     */
    public String generateQrUrl(String secret, String email, String tenantId) {
        final String label = URLEncoder.encode(
                issuer + " (" + tenantId + "):" + email,
                StandardCharsets.UTF_8);
        final String issuerEncoded = URLEncoder.encode(
                issuer + " (" + tenantId + ")",
                StandardCharsets.UTF_8);
        final String secretEncoded = URLEncoder.encode(secret, StandardCharsets.UTF_8);

        return "otpauth://totp/" + label
                + "?secret=" + secretEncoded
                + "&issuer=" + issuerEncoded
                + "&algorithm=SHA1"
                + "&digits=6"
                + "&period=30";
    }

    // ── TOTP verification ─────────────────────────────────────────────────

    /**
     * Verifies a 6-digit TOTP code against the given secret.
     *
     * <p>Checks the current time window and ±{@value #WINDOW} windows
     * to tolerate minor clock drift.
     *
     * <h2>Fixed (backlog #59): returns the matched time step, not just a boolean</h2>
     * Previously returned {@code boolean} — the caller learned only
     * "valid" or "invalid," with no way to detect or prevent a captured,
     * still-valid code being replayed by a second, independent
     * verification attempt within the same ~90s tolerance window. This
     * method has no state of its own to track that (a single secret
     * belongs to exactly one user, but this class is stateless by
     * design — see {@code MfaService.verifyTotpAndRecordUsage} for
     * where the actual per-user tracking now lives). Returning the
     * matched step lets the caller compare it against the last step it
     * previously accepted for that specific user and reject a replay,
     * while a code that matches no window at all is still simply
     * {@link Optional#empty()}, exactly as {@code false} was before.
     *
     * @param base32Secret base32-encoded TOTP secret (plain, not encrypted)
     * @param code         6-digit code from authenticator app
     * @return the matched time step (epochSeconds / {@value #TIME_STEP}),
     *         or {@link Optional#empty()} if the code matches no window
     */
    public Optional<Long> verify(String base32Secret, String code) {
        if (code == null || code.length() != CODE_DIGITS) {
            return Optional.empty();
        }

        final byte[] key = base32Decode(base32Secret);
        final long   timeStep = Instant.now().getEpochSecond() / TIME_STEP;

        for (long t = timeStep - WINDOW; t <= timeStep + WINDOW; t++) {
            final String expected = generateCode(key, t);
            // Constant-time comparison — prevents timing attacks
            if (MessageDigest.isEqual(
                    expected.getBytes(StandardCharsets.UTF_8),
                    code.getBytes(StandardCharsets.UTF_8))) {
                return Optional.of(t);
            }
        }
        return Optional.empty();
    }

    // ── Backup codes ──────────────────────────────────────────────────────

    /**
     * Generates {@value #BACKUP_CODE_COUNT} single-use backup codes.
     *
     * <p>Each code is {@value #BACKUP_CODE_LENGTH} characters from a
     * 32-character alphabet that excludes visually confusable characters
     * (0, 1, i, l, o). Entropy: log2(32^8) ≈ 40 bits per code —
     * sufficient for single-use codes with Argon2 hashing.
     *
     * @return list of plain text backup codes — shown to user ONCE, never stored
     */
    public List<String> generateBackupCodes() {
        final List<String> codes = new ArrayList<>(BACKUP_CODE_COUNT);
        for (int i = 0; i < BACKUP_CODE_COUNT; i++) {
            codes.add(generateSingleBackupCode());
        }
        return codes;
    }

    // ── RFC 6238 core ─────────────────────────────────────────────────────

    /**
     * Generates a TOTP code for a given time step per RFC 6238.
     */
    private String generateCode(byte[] key, long timeStep) {
        try {
            // Step 1: HOTP — HMAC-SHA1(key, counter)
            final byte[] data = ByteBuffer.allocate(8).putLong(timeStep).array();
            final Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(key, "RAW"));
            final byte[] hash = mac.doFinal(data);

            // Step 2: Dynamic truncation per RFC 4226 §5.3
            // offset = low-order 4 bits of last byte
            final int offset = hash[hash.length - 1] & 0x0F;
            final int binary =
                    ((hash[offset]     & 0x7F) << 24) |  // mask high bit (unsigned)
                            ((hash[offset + 1] & 0xFF) << 16) |
                            ((hash[offset + 2] & 0xFF) << 8)  |
                            (hash[offset + 3] & 0xFF);

            // Step 3: Compute HOTP value — zero-padded to CODE_DIGITS digits
            return String.format("%0" + CODE_DIGITS + "d", binary % CODE_MODULUS);

        } catch (Exception e) {
            // Fixed (backlog #61): was a generic RuntimeException with a
            // vague message. HmacSHA1 is guaranteed available in every
            // JVM — the same "this cannot actually happen" guarantee
            // AuthTokenService.hash() relies on for SHA-256 — so this
            // now matches that exact style (IllegalStateException, a
            // specific "X not available" message) instead of two
            // different, inconsistent idioms for the identical class of
            // situation within the same module.
            throw new IllegalStateException("HmacSHA1 not available", e);
        }
    }

    private String generateSingleBackupCode() {
        final StringBuilder sb = new StringBuilder(BACKUP_CODE_LENGTH);
        for (int i = 0; i < BACKUP_CODE_LENGTH; i++) {
            sb.append(BACKUP_CODE_CHARS.charAt(
                    secureRandom.nextInt(BACKUP_CODE_CHARS.length())));
        }
        return sb.toString();
    }

    // ── Base32 encoding/decoding (RFC 4648) ───────────────────────────────
    // Implemented without external dependencies.
    // Base32 alphabet: A-Z 2-7 (32 characters, no confusables).

    private static final String BASE32_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    /**
     * Encodes bytes to base32 string per RFC 4648 §6.
     * Used for secret generation — output is compatible with Google Authenticator.
     */
    static String base32Encode(byte[] data) {
        final StringBuilder sb = new StringBuilder();
        int buffer = 0, bitsLeft = 0;
        for (final byte b : data) {
            buffer = (buffer << 8) | (b & 0xFF);
            bitsLeft += 8;
            while (bitsLeft >= 5) {
                bitsLeft -= 5;
                sb.append(BASE32_CHARS.charAt((buffer >> bitsLeft) & 0x1F));
            }
        }
        if (bitsLeft > 0) {
            buffer <<= (5 - bitsLeft);
            sb.append(BASE32_CHARS.charAt(buffer & 0x1F));
        }
        return sb.toString();
    }

    /**
     * Decodes a base32 string to bytes per RFC 4648 §6.
     * Used at verify time — decodes secret from authenticator app input.
     */
    static byte[] base32Decode(String base32) {
        // Locale.ROOT: under a Turkish default a secret's "i" would become "İ", outside the base32 alphabet (backlog #0-323)
        final String upper = base32.toUpperCase(Locale.ROOT).replaceAll("[=\\s]", "");
        final byte[] output = new byte[upper.length() * 5 / 8];
        int buffer = 0, bitsLeft = 0, index = 0;
        for (final char c : upper.toCharArray()) {
            final int val = BASE32_CHARS.indexOf(c);
            if (val < 0) continue; // skip non-base32 chars (spaces, dashes)
            buffer = (buffer << 5) | val;
            bitsLeft += 5;
            if (bitsLeft >= 8) {
                bitsLeft -= 8;
                if (index < output.length) {
                    output[index++] = (byte) ((buffer >> bitsLeft) & 0xFF);
                }
            }
        }
        return output;
    }
}