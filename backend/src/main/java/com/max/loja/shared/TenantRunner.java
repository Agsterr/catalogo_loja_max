package com.max.loja.shared;

import java.util.function.Supplier;

import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Roda um trabalho numa transação NOVA já "dentro" de uma loja. O Hibernate fixa a loja (tenant) quando abre a sessão,
 * então trocar o {@link TenantContext} no meio de uma transação não vale: quem age em nome de várias lojas (entregador,
 * agendador) passa por aqui.
 */
@Component
public class TenantRunner {

    private final TransactionTemplate tx;

    public TenantRunner(PlatformTransactionManager manager) {
        this.tx = new TransactionTemplate(manager);
        this.tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public <T> T call(Long tenantId, Supplier<T> work) {
        Long previous = TenantContext.get();
        TenantContext.set(tenantId);
        try {
            return tx.execute(status -> work.get());
        } finally {
            if (TenantContext.NONE.equals(previous)) {
                TenantContext.clear();
            } else {
                TenantContext.set(previous);
            }
        }
    }

    public void run(Long tenantId, Runnable work) {
        call(tenantId, () -> {
            work.run();
            return null;
        });
    }
}
