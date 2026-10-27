package com.max.loja.push;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * Fila de avisos no banco (outbox), igual à do Gerenciamento Max: o aviso é gravado na transação do evento
 * (pedido, estoque, promoção) e o {@link PushOutboxWorker} entrega pelo Firebase, com novas tentativas e
 * confirmação de recebimento pelo app.
 */
@Repository
public class PushOutbox {

    public static final String PENDING = "PENDING";
    public static final String SENT = "SENT";
    public static final String RECEIVED = "RECEIVED";
    public static final String DEAD = "DEAD";
    public static final String INVALID = "INVALID";
    public static final String EXPIRED = "EXPIRED";

    /** Aviso que ainda precisa sair. */
    public record Due(long id, String publicId, long deviceId, String token, String title, String body,
                      String data, int attempts) {
    }

    private final JdbcTemplate jdbc;
    private final ObjectMapper json;

    public PushOutbox(JdbcTemplate jdbc, ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** Grava o aviso; a mesma chave não entra duas vezes (devolve false se já existia). */
    public boolean enqueue(Long tenantId, long deviceId, String token, String title, String body, Map<String, String> data,
                           String dedupeKey, LocalDateTime now) {
        String payload;
        try {
            payload = json.writeValueAsString(data);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException(e);
        }
        return jdbc.update("""
                insert into push_outbox (public_id, tenant_id, device_id, device_token, title, body, data, dedupe_key, created_at,
                                         next_attempt_at)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) on conflict do nothing""",
                UUID.randomUUID().toString(), tenantId, deviceId, token, cut(title, 200), cut(body, 500), payload,
                cut(dedupeKey, 200), now, now) > 0;
    }

    /** Pega os avisos vencidos, travando as linhas (vários servidores não enviam o mesmo aviso). */
    public List<Due> claimDue(int limit, LocalDateTime now) {
        return jdbc.query("""
                select id, public_id, device_id, device_token, title, body, data, attempts
                from push_outbox where status = 'PENDING' and next_attempt_at <= ?
                order by id limit ? for update skip locked""",
                (rs, i) -> new Due(rs.getLong("id"), rs.getString("public_id"),
                        rs.getLong("device_id"), rs.getString("device_token"), rs.getString("title"),
                        rs.getString("body"), rs.getString("data"), rs.getInt("attempts")),
                now, limit);
    }

    public void markSent(long id, LocalDateTime now) {
        jdbc.update("update push_outbox set status = 'SENT', sent_at = ?, attempts = attempts + 1, last_error = null where id = ?",
                now, id);
    }

    /** Falhou: tenta de novo depois (espera crescente) ou desiste (DEAD) depois de várias tentativas. */
    public void markFailed(long id, int attemptsSoFar, LocalDateTime now, String error) {
        int attempts = attemptsSoFar + 1;
        if (attempts >= MAX_ATTEMPTS) {
            jdbc.update("update push_outbox set status = 'DEAD', attempts = ?, last_error = ? where id = ?",
                    attempts, cut(error, 300), id);
            return;
        }
        jdbc.update("update push_outbox set attempts = ?, next_attempt_at = ?, last_error = ? where id = ?",
                attempts, now.plus(backoff(attempts)), cut(error, 300), id);
    }

    public void markInvalid(long id) {
        jdbc.update("update push_outbox set status = 'INVALID', last_error = 'celular não aceita mais avisos' where id = ?", id);
    }

    /** Aviso parado há mais de um dia deixou de ter valor. */
    public int expireOld(LocalDateTime before) {
        return jdbc.update("update push_outbox set status = 'EXPIRED' where status = 'PENDING' and created_at < ?", before);
    }

    /** Remove da fila o que já foi resolvido há mais de 30 dias. */
    public int purge(LocalDateTime before) {
        return jdbc.update("delete from push_outbox where status <> 'PENDING' and created_at < ?", before);
    }

    /** O app avisa que recebeu: vale só com o código do aviso e o do celular, que o servidor mandou. */
    public boolean ack(String publicId, String token, LocalDateTime now) {
        return jdbc.update("""
                update push_outbox set status = 'RECEIVED', received_at = ?
                where public_id = ? and device_token = ? and status in ('SENT', 'PENDING')""", now, publicId, token) > 0;
    }

    public void removeDevice(long deviceId) {
        jdbc.update("delete from push_device where id = ?", deviceId);
    }

    public static final int MAX_ATTEMPTS = 5;

    /** 1 min, 5 min, 30 min, 2 h. */
    static java.time.Duration backoff(int attempts) {
        return switch (attempts) {
            case 1 -> java.time.Duration.ofMinutes(1);
            case 2 -> java.time.Duration.ofMinutes(5);
            case 3 -> java.time.Duration.ofMinutes(30);
            default -> java.time.Duration.ofHours(2);
        };
    }

    private static String cut(String s, int max) {
        if (s == null) {
            return "";
        }
        return s.length() <= max ? s : s.substring(0, max - 1) + "…";
    }
}
