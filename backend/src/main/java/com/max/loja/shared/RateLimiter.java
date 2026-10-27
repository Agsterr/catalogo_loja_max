package com.max.loja.shared;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.HexFormat;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

/**
 * Limite de tentativas por chave (IP, e-mail...) em janela deslizante: login, cadastro, "esqueci a senha",
 * código de redefinição, celular anônimo. Fica no banco ({@code rate_limit_hit}), então vale com várias
 * instâncias da API. A chave é gravada como hash (e-mail e IP não ficam em texto).
 */
@Component
public class RateLimiter {

    public static final int DEFAULT_MAX = 10;
    public static final Duration WINDOW = Duration.ofMinutes(10);

    private final JdbcTemplate jdbc;
    private final Clock clock;

    public RateLimiter(JdbcTemplate jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    public void check(String key) {
        check(key, DEFAULT_MAX);
    }

    /** @throws ResponseStatusException 429 quando passou de {@code max} na janela */
    public void check(String key, int max) {
        String hashed = hash(key);
        LocalDateTime now = LocalDateTime.now(clock);
        Integer hits = jdbc.queryForObject("select count(*) from rate_limit_hit where key = ? and created_at > ?",
                Integer.class, hashed, now.minus(WINDOW));
        if (hits != null && hits >= max) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "Muitas tentativas. Aguarde alguns minutos e tente de novo.");
        }
        jdbc.update("insert into rate_limit_hit (key, created_at) values (?, ?)", hashed, now);
    }

    /** Apaga as tentativas que já saíram da janela. */
    @Scheduled(fixedDelay = 3_600_000, initialDelay = 600_000)
    public void purge() {
        jdbc.update("delete from rate_limit_hit where created_at < ?", LocalDateTime.now(clock).minus(WINDOW.multipliedBy(2)));
    }

    /** Só para os testes. */
    public void reset() {
        jdbc.update("delete from rate_limit_hit");
    }

    private static String hash(String key) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(key.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
