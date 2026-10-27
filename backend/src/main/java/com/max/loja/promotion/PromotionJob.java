package com.max.loja.promotion;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** A cada poucos minutos: promoções agendadas que começaram viram aviso para os clientes. */
@Component
class PromotionJob {

    private static final Logger log = LoggerFactory.getLogger(PromotionJob.class);

    private final PromotionService service;

    PromotionJob(PromotionService service) {
        this.service = service;
    }

    @Scheduled(cron = "${app.push.promotions-cron}")
    void run() {
        int n = service.announceStarted();
        if (n > 0) {
            log.info("Promoções anunciadas: {}", n);
        }
    }
}
