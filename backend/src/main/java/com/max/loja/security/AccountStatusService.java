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
 * Estado atual do usuário (existe, bloqueado — ele ou a loja dele —, versão dos tokens), consultado a cada requisição autenticada
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

    /** Bloqueio de loja afeta a equipe toda: limpa tudo. */
    public void evictAll() {
        cache.clear();
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
        // equipe de loja bloqueada pela plataforma também fica de fora
        List<Status> rows = jdbc.query("""
                select u.active, u.blocked, u.blocked_reason, u.token_version, u.role,
                       s.blocked as store_blocked, s.blocked_reason as store_reason
                from app_user u left join store s on s.id = u.store_id where u.id = ?""",
                (rs, i) -> {
                    if (!rs.getBoolean("active")) {
                        return Status.MISSING;
                    }
                    boolean storeBlocked = rs.getBoolean("store_blocked");
                    return new Status(true, rs.getBoolean("blocked") || storeBlocked,
                            rs.getBoolean("blocked") ? rs.getString("blocked_reason") : rs.getString("store_reason"),
                            rs.getInt("token_version"), rs.getString("role"));
                },
                userId);
        return rows.isEmpty() ? Status.MISSING : rows.get(0);
    }
}
