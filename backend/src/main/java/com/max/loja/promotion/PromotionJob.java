package com.max.loja.promotion;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.shared.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** A cada poucos minutos, em cada loja: promoções agendadas que começaram viram aviso para os clientes. */
@Component
class PromotionJob {

    private static final Logger log = LoggerFactory.getLogger(PromotionJob.class);

    private final PromotionService service;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    PromotionJob(PromotionService service, JdbcTemplate jdbc, Clock clock) {
        this.service = service;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @Scheduled(cron = "${app.push.promotions-cron}")
    void run() {
        // só lojas com promoção para anunciar (uma consulta leve antes de entrar em cada loja)
        List<Long> stores = jdbc.queryForList("""
                select distinct p.tenant_id from promotion p join store s on s.id = p.tenant_id
                where not s.blocked and p.active and p.notify_customers and p.notified_at is null
                and p.starts_at <= ? and p.ends_at > ?""", Long.class, LocalDateTime.now(clock), LocalDateTime.now(clock));
        int total = 0;
        for (Long id : stores) {
            try {
                TenantContext.set(id);
                total += service.announceStarted();
            } catch (RuntimeException e) {
                log.warn("Promoções da loja {} falharam: {}", id, e.getMessage());
            } finally {
                TenantContext.clear();
            }
        }
        if (total > 0) {
            log.info("Promoções anunciadas: {}", total);
        }
    }
}
