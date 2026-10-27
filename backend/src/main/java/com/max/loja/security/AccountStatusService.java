package com.max.loja.security;

import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Estado atual do usuário (existe, bloqueado, versão dos tokens), consultado a cada requisição autenticada
 * para que bloqueio, troca de senha e exclusão valham também para tokens JWT já emitidos. Cache curto em
 * memória; quem muda o estado chama {@link #evict}.
 */
@Service
public class AccountStatusService {

    public record Status(boolean exists, boolean blocked, String blockedReason, int tokenVersion, String role) {

        static final Status MISSING = new Status(false, false, null, -1, null);
    }

    private record Cached(Status status, long expiresAt) {
    }

    private static final Duration TTL = Duration.ofSeconds(10);
    private static final int MAX_ENTRIES = 5_000;

    private final JdbcTemplate jdbc;
    private final Map<Long, Cached> cache = new ConcurrentHashMap<>();

    public AccountStatusService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Status of(Long userId) {
        long now = System.currentTimeMillis();
        Cached cached = cache.get(userId);
        if (cached != null && cached.expiresAt > now) {
            return cached.status;
        }
        Status status = load(userId);
        if (cache.size() >= MAX_ENTRIES) {
            cache.clear();
        }
        cache.put(userId, new Cached(status, now + TTL.toMillis()));
        return status;
    }

    /** Limpa agora e de novo após o commit, para não recachear o estado antigo nesse intervalo. */
    public void evict(Long userId) {
        cache.remove(userId);
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    cache.remove(userId);
                }
            });
        }
    }

    private Status load(Long userId) {
        List<Status> rows = jdbc.query("select active, blocked, blocked_reason, token_version, role from app_user where id = ?",
                (rs, i) -> rs.getBoolean("active")
                        ? new Status(true, rs.getBoolean("blocked"), rs.getString("blocked_reason"), rs.getInt("token_version"),
                                rs.getString("role"))
                        : Status.MISSING,
                userId);
        return rows.isEmpty() ? Status.MISSING : rows.get(0);
    }
}
