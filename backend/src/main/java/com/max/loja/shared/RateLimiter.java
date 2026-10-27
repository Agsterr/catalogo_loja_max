package com.max.loja.shared;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

/**
 * Limite de tentativas por chave (IP, e-mail...) em janela deslizante: login, cadastro, "esqueci a senha" e
 * cadastro anônimo de celular. Em memória: simples e suficiente para uma única instância da API.
 */
@Component
public class RateLimiter {

    public static final int DEFAULT_MAX = 10;
    public static final Duration WINDOW = Duration.ofMinutes(10);

    private final Map<String, Deque<Instant>> attempts = new ConcurrentHashMap<>();
    private final Clock clock;

    public RateLimiter(Clock clock) {
        this.clock = clock;
    }

    public void check(String key) {
        check(key, DEFAULT_MAX);
    }

    /** @throws ResponseStatusException 429 quando passou de {@code max} na janela */
    public void check(String key, int max) {
        Instant now = clock.instant();
        Deque<Instant> list = attempts.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (list) {
            while (!list.isEmpty() && list.peekFirst().isBefore(now.minus(WINDOW))) {
                list.pollFirst();
            }
            if (list.size() >= max) {
                throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                        "Muitas tentativas. Aguarde alguns minutos e tente de novo.");
            }
            list.addLast(now);
        }
        if (attempts.size() > 10_000) {
            attempts.entrySet().removeIf(e -> e.getValue().isEmpty());
        }
    }

    /** Só para os testes. */
    public void reset() {
        attempts.clear();
    }
}
