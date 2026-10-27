package com.max.loja.delivery;

import java.math.BigDecimal;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Map;

import com.max.loja.push.PushNotifier;
import com.max.loja.security.SecretBox;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.SubscriptionRequiredException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Entregas grátis e assinatura do entregador. As entregas grátis valem por APARELHO e por CPF (o menor saldo manda), então
 * trocar de e-mail ou de CPF no mesmo aparelho não renova. Depois delas, só com assinatura ativa.
 */
@Service
public class CourierBilling {

    /** Situação para o app: saldo grátis, assinatura e se pode aceitar corrida agora. */
    public record Standing(boolean subscribed, LocalDateTime paidUntil, int freeLeft, int freeLimit, BigDecimal price,
                           boolean canAccept) {
    }

    private final BillingProperties props;
    private final CourierSubscriptionRepository subscriptions;
    private final CourierPaymentRepository payments;
    private final CourierRepository couriers;
    private final PaymentProvider provider;
    private final SecretBox box;
    private final JdbcTemplate jdbc;
    private final PushNotifier push;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    public CourierBilling(BillingProperties props, CourierSubscriptionRepository subscriptions, CourierPaymentRepository payments,
                          CourierRepository couriers, PaymentProvider provider, SecretBox box, JdbcTemplate jdbc,
                          PushNotifier push, Clock clock) {
        this.props = props;
        this.subscriptions = subscriptions;
        this.payments = payments;
        this.couriers = couriers;
        this.provider = provider;
        this.box = box;
        this.jdbc = jdbc;
        this.push = push;
        this.clock = clock;
    }

    /** Impressão digital do ID do aparelho (o app manda o ID cru no cabeçalho {@code X-Device-Id}). */
    public String deviceHash(String raw) {
        if (raw == null || raw.trim().length() < 8 || raw.trim().length() > 200) {
            throw new BusinessException("Atualize o app do entregador para continuar.");
        }
        return box.blindIndex("device:" + raw.trim());
    }

    /** Registra o aparelho e liga ao entregador (um aparelho pode ter várias contas, mas divide as entregas grátis). */
    public void linkDevice(Long courierId, String deviceHash) {
        LocalDateTime now = LocalDateTime.now(clock);
        jdbc.update("""
                insert into courier_device (device_hash, first_seen_at, last_seen_at) values (?, ?, ?)
                on conflict (device_hash) do update set last_seen_at = excluded.last_seen_at""", deviceHash, now, now);
        jdbc.update("insert into courier_device_link (courier_id, device_hash, first_seen_at) values (?, ?, ?) on conflict do nothing",
                courierId, deviceHash, now);
    }

    /** Trava a linha do aparelho (contas diferentes no mesmo aparelho não aceitam ao mesmo tempo além do saldo). */
    public void lockDevice(String deviceHash) {
        jdbc.query("select device_hash from courier_device where device_hash = ? for update", rs -> {
        }, deviceHash);
    }

    @Transactional(readOnly = true)
    public Standing standing(Courier c, String deviceHash, long activeJobs) {
        LocalDateTime now = LocalDateTime.now(clock);
        LocalDateTime until = subscriptions.findById(c.getUserId()).map(CourierSubscription::getPaidUntil).orElse(null);
        boolean subscribed = until != null && until.isAfter(now);
        int limit = props.freeDeliveries();
        int deviceUsed = deviceHash == null ? 0 : deviceFreeUsed(deviceHash);
        int freeLeft = Math.max(0, Math.min(limit - c.getFreeUsed(), limit - deviceUsed));
        return new Standing(subscribed, until, freeLeft, limit, props.courierMonthly(),
                subscribed || freeLeft - activeJobs > 0);
    }

    /** Barra o aceite quando não há entrega grátis sobrando (já descontadas as corridas em andamento) nem assinatura. */
    public void requireCanAccept(Courier c, String deviceHash, long activeJobs) {
        Standing s = standing(c, deviceHash, activeJobs);
        if (s.canAccept()) {
            return;
        }
        boolean deviceSpent = deviceFreeUsed(deviceHash) >= props.freeDeliveries() && c.getFreeUsed() < props.freeDeliveries();
        throw new SubscriptionRequiredException((deviceSpent
                ? "Este aparelho já usou as " + props.freeDeliveries() + " entregas grátis."
                : "Suas " + props.freeDeliveries() + " entregas grátis acabaram.")
                + " Assine por R$ " + props.courierMonthly().toPlainString().replace('.', ',') + " por mês para continuar.");
    }

    /** Conta a entrega nas grátis (do CPF e do aparelho) quando não há assinatura ativa. Chamar com o entregador já travado. */
    public void recordDelivery(Courier c, String deviceHash) {
        LocalDateTime until = subscriptions.findById(c.getUserId()).map(CourierSubscription::getPaidUntil).orElse(null);
        if (until != null && until.isAfter(LocalDateTime.now(clock))) {
            return;
        }
        c.setFreeUsed(c.getFreeUsed() + 1);
        jdbc.update("update courier_device set free_used = free_used + 1 where device_hash = ?", deviceHash);
    }

    private int deviceFreeUsed(String deviceHash) {
        Integer used = jdbc.query("select free_used from courier_device where device_hash = ?",
                rs -> rs.next() ? rs.getInt(1) : 0, deviceHash);
        return used == null ? 0 : used;
    }

    // --- assinatura ---

    /** Gera (ou reaproveita) a cobrança da mensalidade e devolve como pagar. */
    @Transactional
    public PaymentProvider.Instructions checkout(Long courierId) {
        couriers.findById(courierId).orElseThrow(() -> new NotFoundException("Cadastro de entregador não encontrado"));
        LocalDateTime now = LocalDateTime.now(clock);
        CourierPayment p = payments.findFirstByCourierIdAndStatusAndCreatedAtAfterOrderByIdDesc(courierId, CourierPayment.PENDING,
                now.minusDays(7)).orElseGet(() -> {
            CourierPayment n = new CourierPayment();
            n.setCourierId(courierId);
            n.setAmount(props.courierMonthly());
            n.setReference("LM" + courierId + "-" + String.format("%05d", random.nextInt(100000)));
            n.setPeriodDays(props.periodDays());
            n.setCreatedAt(now);
            return payments.save(n);
        });
        return provider.charge(courierId, p.getReference(), p.getAmount());
    }

    /** Pagamento recebido: estende a assinatura (idempotente; chamado pelo admin, ou pelo webhook de um provedor). */
    @Transactional
    public void confirm(Long paymentId, Long adminId) {
        CourierPayment p = payments.lock(paymentId).orElseThrow(() -> new NotFoundException("Pagamento não encontrado"));
        if (CourierPayment.CONFIRMED.equals(p.getStatus())) {
            return;
        }
        p.setStatus(CourierPayment.CONFIRMED);
        p.setConfirmedAt(LocalDateTime.now(clock));
        p.setConfirmedBy(adminId);
        extend(p.getCourierId(), p.getPeriodDays());
    }

    /** Cortesia/ajuste do admin: libera {@code days} dias sem pagamento. */
    @Transactional
    public void grant(Long courierId, int days, Long adminId) {
        couriers.findById(courierId).orElseThrow(() -> new NotFoundException("Cadastro de entregador não encontrado"));
        if (days < 1 || days > 366) {
            throw new BusinessException("Informe de 1 a 366 dias");
        }
        LocalDateTime now = LocalDateTime.now(clock);
        CourierPayment p = new CourierPayment();
        p.setCourierId(courierId);
        p.setAmount(BigDecimal.ZERO);
        p.setReference("ADM" + courierId + "-" + now.toLocalDate().toString().replace("-", "") + "-" + random.nextInt(1000));
        p.setStatus(CourierPayment.CONFIRMED);
        p.setMethod("ADMIN");
        p.setPeriodDays(days);
        p.setCreatedAt(now);
        p.setConfirmedAt(now);
        p.setConfirmedBy(adminId);
        payments.save(p);
        extend(courierId, days);
    }

    private void extend(Long courierId, int days) {
        LocalDateTime now = LocalDateTime.now(clock);
        CourierSubscription s = subscriptions.findById(courierId).orElseGet(() -> {
            CourierSubscription n = new CourierSubscription();
            n.setCourierId(courierId);
            n.setPaidUntil(now);
            return n;
        });
        LocalDateTime from = s.getPaidUntil().isAfter(now) ? s.getPaidUntil() : now;
        s.setPaidUntil(from.plusDays(days));
        subscriptions.save(s);
        push.toUser(courierId, "courier-sub:" + courierId + ":" + s.getPaidUntil().toLocalDate() + ":" + System.currentTimeMillis() / 1000,
                "Assinatura ativa", "Você pode aceitar corridas até " + s.getPaidUntil().toLocalDate().format(
                        java.time.format.DateTimeFormatter.ofPattern("dd/MM/yyyy")) + ".",
                Map.of("type", "courier", "kind", "COURIER_STATUS"));
    }
}
