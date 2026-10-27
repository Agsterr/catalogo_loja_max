package com.max.loja.store;

import java.math.BigDecimal;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;

import com.max.loja.delivery.BillingProperties;
import com.max.loja.delivery.PaymentProvider;
import com.max.loja.notification.Notification;
import com.max.loja.notification.NotificationService;
import com.max.loja.push.PushNotifier;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.TenantRunner;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Mensalidade da loja (o app do cliente é grátis; quem paga é a loja). Teste grátis ao abrir a loja; depois a loja precisa
 * estar paga para aparecer aos clientes. Vencida, tem alguns dias de tolerância e então fica oculta (a equipe continua
 * entrando no app para pagar). O pagamento é confirmado pelo admin hoje; um provedor automático entra atrás de
 * {@link PaymentProvider}.
 */
@Service
public class StoreBilling {

    private static final Logger log = LoggerFactory.getLogger(StoreBilling.class);

    /** {@code state}: TRIAL, ACTIVE (paga), GRACE (vencida, ainda visível) ou SUSPENDED (oculta para os clientes). */
    public record Plan(String state, LocalDateTime accessUntil, LocalDateTime hiddenAfter, long daysLeft, BigDecimal price,
                       boolean visible, int trialDays) {
    }

    private final BillingProperties props;
    private final StoreRepository stores;
    private final StorePaymentRepository payments;
    private final PaymentProvider provider;
    private final NotificationService notifications;
    private final PushNotifier push;
    private final TenantRunner runner;
    private final JdbcTemplate jdbc;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    public StoreBilling(BillingProperties props, StoreRepository stores, StorePaymentRepository payments, PaymentProvider provider,
                        NotificationService notifications, PushNotifier push, TenantRunner runner, JdbcTemplate jdbc, Clock clock) {
        this.props = props;
        this.stores = stores;
        this.payments = payments;
        this.provider = provider;
        this.notifications = notifications;
        this.push = push;
        this.runner = runner;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    /** Fim do teste grátis de uma loja que abre agora. */
    public LocalDateTime trialEnd() {
        return LocalDateTime.now(clock).plusDays(props.storeTrialDays());
    }

    /** Antes disto (agora menos a tolerância) a loja já está oculta para os clientes. */
    public LocalDateTime visibleCutoff() {
        return LocalDateTime.now(clock).minusDays(props.storeGraceDays());
    }

    public boolean visible(Store s) {
        return s.getAccessUntil().isAfter(visibleCutoff());
    }

    @Transactional(readOnly = true)
    public Plan plan(Long storeId) {
        Store s = store(storeId);
        LocalDateTime now = LocalDateTime.now(clock);
        boolean everPaid = payments.existsByStoreIdAndStatusAndAmountGreaterThan(storeId, StorePayment.CONFIRMED, BigDecimal.ZERO);
        LocalDateTime hiddenAfter = s.getAccessUntil().plusDays(props.storeGraceDays());
        String state = s.getAccessUntil().isAfter(now) ? (everPaid ? "ACTIVE" : "TRIAL") : hiddenAfter.isAfter(now) ? "GRACE" : "SUSPENDED";
        long daysLeft = ChronoUnit.DAYS.between(now.toLocalDate(), s.getAccessUntil().toLocalDate());
        return new Plan(state, s.getAccessUntil(), hiddenAfter, daysLeft, props.storeMonthly(), hiddenAfter.isAfter(now), props.storeTrialDays());
    }

    /** Gera (ou reaproveita) a cobrança da mensalidade e devolve como pagar. */
    @Transactional
    public PaymentProvider.Instructions checkout(Long storeId) {
        store(storeId);
        LocalDateTime now = LocalDateTime.now(clock);
        StorePayment p = payments.findFirstByStoreIdAndStatusAndCreatedAtAfterOrderByIdDesc(storeId, StorePayment.PENDING,
                now.minusDays(7)).orElseGet(() -> {
            StorePayment n = new StorePayment();
            n.setStoreId(storeId);
            n.setAmount(props.storeMonthly());
            n.setReference("LJ" + storeId + "-" + String.format("%05d", random.nextInt(100000)));
            n.setPeriodDays(30);
            n.setCreatedAt(now);
            return payments.save(n);
        });
        return provider.charge(storeId, p.getReference(), p.getAmount());
    }

    /** Pagamento recebido: estende o acesso (idempotente; admin hoje, webhook de provedor depois). */
    @Transactional
    public void confirm(Long paymentId, Long adminId) {
        StorePayment p = payments.lock(paymentId).orElseThrow(() -> new NotFoundException("Pagamento não encontrado"));
        if (StorePayment.CONFIRMED.equals(p.getStatus())) {
            return;
        }
        p.setStatus(StorePayment.CONFIRMED);
        p.setConfirmedAt(LocalDateTime.now(clock));
        p.setConfirmedBy(adminId);
        Store s = extend(p.getStoreId(), p.getPeriodDays());
        notifyPaid(s);
    }

    /** Cortesia/ajuste do admin: libera dias sem pagamento. */
    @Transactional
    public void grant(Long storeId, int days, Long adminId) {
        if (days < 1 || days > 366) {
            throw new BusinessException("Informe de 1 a 366 dias");
        }
        LocalDateTime now = LocalDateTime.now(clock);
        StorePayment p = new StorePayment();
        p.setStoreId(storeId);
        p.setAmount(BigDecimal.ZERO);
        p.setReference("ADM" + storeId + "-" + now.toLocalDate().toString().replace("-", "") + "-" + random.nextInt(1000));
        p.setStatus(StorePayment.CONFIRMED);
        p.setMethod("ADMIN");
        p.setPeriodDays(days);
        p.setCreatedAt(now);
        p.setConfirmedAt(now);
        p.setConfirmedBy(adminId);
        payments.save(p);
        notifyPaid(extend(storeId, days));
    }

    private Store extend(Long storeId, int days) {
        Store s = store(storeId);
        LocalDateTime now = LocalDateTime.now(clock);
        s.setAccessUntil((s.getAccessUntil().isAfter(now) ? s.getAccessUntil() : now).plusDays(days));
        return s;
    }

    private void notifyPaid(Store s) {
        runner.run(s.getId(), () -> push.toTeam("plan-paid:" + s.getId() + ":" + System.currentTimeMillis() / 1000, "Mensalidade confirmada",
                "Sua loja está liberada até " + s.getAccessUntil().toLocalDate().format(java.time.format.DateTimeFormatter.ofPattern("dd/MM/yyyy")) + ".",
                Map.of("type", "team", "kind", "PLAN")));
    }

    /**
     * Avisos diários às 9h: faltam 7, 3 e 1 dia, venceu (entra a tolerância) e a loja foi ocultada. Cada aviso é único por
     * vencimento e etapa, então rodar duas vezes (ou em duas instâncias) não repete.
     */
    @Scheduled(cron = "${app.billing.reminders-cron:0 0 9 * * *}")
    public void remind() {
        LocalDateTime now = LocalDateTime.now(clock);
        List<Long> ids = jdbc.queryForList("""
                select id from store where blocked = false and access_until < ? and access_until > ?""", Long.class,
                now.plusDays(8), now.minusDays(props.storeGraceDays() + 2L));
        for (Long id : ids) {
            try {
                runner.run(id, () -> remindOne(id));
            } catch (RuntimeException e) {
                log.warn("Aviso de mensalidade da loja {} falhou", id, e);
            }
        }
    }

    private void remindOne(Long id) {
        Store s = store(id);
        LocalDate today = LocalDate.now(clock);
        long days = ChronoUnit.DAYS.between(today, s.getAccessUntil().toLocalDate());
        String title;
        String body;
        String stage;
        if (days == 7 || days == 3 || days == 1) {
            stage = "d" + days;
            title = "Sua mensalidade vence em " + days + (days == 1 ? " dia" : " dias");
            body = "Renove em Mais > Plano e mensalidade para a loja continuar aparecendo para os clientes.";
        } else if (days == 0) {
            stage = "d0";
            title = "Sua mensalidade vence hoje";
            body = "Renove em Mais > Plano e mensalidade. Depois do vencimento você tem " + props.storeGraceDays() + " dias antes de a loja ficar oculta.";
        } else if (days < 0 && visible(s) && days == -1) {
            stage = "grace";
            title = "Mensalidade vencida";
            body = "A loja ainda aparece por alguns dias. Renove em Mais > Plano e mensalidade.";
        } else if (!visible(s) && s.getAccessUntil().plusDays(props.storeGraceDays()).toLocalDate().plusDays(1).equals(today)) {
            stage = "hidden";
            title = "Sua loja está oculta para os clientes";
            body = "A mensalidade venceu. Renove em Mais > Plano e mensalidade e a loja volta na hora.";
        } else {
            return;
        }
        notifications.toTeam(Notification.Type.PLAN, title, body, NotificationService.Target.none(),
                "plan:" + s.getId() + ":" + s.getAccessUntil().toLocalDate() + ":" + stage);
    }

    @Transactional(readOnly = true)
    public List<StorePayment> pending() {
        return payments.findByStatusOrderByIdDesc(StorePayment.PENDING, org.springframework.data.domain.PageRequest.of(0, 100)).getContent();
    }

    private Store store(Long id) {
        return stores.findById(id).orElseThrow(() -> new NotFoundException("Loja não encontrada"));
    }
}
