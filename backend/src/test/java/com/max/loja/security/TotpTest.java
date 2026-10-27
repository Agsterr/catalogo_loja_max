package com.max.loja.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.Test;

class TotpTest {

    /** Vetores do RFC 6238 (SHA-1, segredo "12345678901234567890"), últimos 6 dígitos. */
    @Test
    void matchesRfcVectors() {
        String secret = Totp.base32("12345678901234567890".getBytes(StandardCharsets.US_ASCII));
        assertThat(Totp.code(secret, 59 / 30)).isEqualTo("287082");
        assertThat(Totp.code(secret, 1111111109L / 30)).isEqualTo("081804");
        assertThat(Totp.code(secret, 2000000000L / 30)).isEqualTo("279037");
    }

    @Test
    void acceptsNeighbourStepAndRejectsOthers() {
        String secret = Totp.newSecret();
        long now = 1_800_000_000L;
        assertThat(Totp.verify(secret, Totp.code(secret, now / 30), now)).isTrue();
        assertThat(Totp.verify(secret, Totp.code(secret, now / 30 - 1), now)).isTrue();
        assertThat(Totp.verify(secret, Totp.code(secret, now / 30 - 3), now)).isFalse();
        assertThat(Totp.verify(secret, "12ab56", now)).isFalse();
        assertThat(Totp.fromBase32(Totp.base32(new byte[] {1, 2, 3, 4, 5}))).containsExactly(1, 2, 3, 4, 5);
    }

    @Test
    void secretBoxRoundTripsAndUsesFreshNonce() {
        SecretBox box = new SecretBox("", new JwtProperties("x".repeat(40), java.time.Duration.ofHours(1)));
        String a = box.encrypt("SEGREDO");
        assertThat(box.decrypt(a)).isEqualTo("SEGREDO");
        assertThat(box.encrypt("SEGREDO")).isNotEqualTo(a);
    }
}
