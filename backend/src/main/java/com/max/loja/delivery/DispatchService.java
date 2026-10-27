package com.max.loja.delivery;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.max.loja.event.StoreEvents;
import com.max.loja.order.CustomerOrder;
import com.max.loja.order.OrderService;
import com.max.loja.order.OrderStatus;
import com.max.loja.push.PushNotifier;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.Money;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.TenantContext;
import com.max.loja.shared.TenantRunner;
import com.max.loja.store.Store;
import com.max.loja.store.StoreRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Despacho: abre a corrida quando o pedido de entrega por entregador está pago e confirmado, avisa os entregadores
 * da região, cancela quando o pedido cai e expira as que ninguém aceitou. Os ouvintes rodam na transação do pedido.
 */
@Service
public class DispatchService {

    private static final Logger log = LoggerFactory.getLogger(DispatchService.class);

    private final DeliveryJobRepository jobs;
    private final OrderService orders;
    private final StoreRepository stores;
    private final CourierRepository couriers;
    private final DeliveryPricing pricing;
    private final DeliveryProperties props;
    private final PushNotifier push;
    private final ApplicationEventPublisher events;
    private final TenantRunner runner;
    private final JdbcTemplate jdbc;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    public DispatchService(DeliveryJobRepository jobs, OrderService orders, StoreRepository stores,
                           CourierRepository couriers, DeliveryPricing pricing, DeliveryProperties props, PushNotifier push,
                           ApplicationEventPublisher events, TenantRunner runner, JdbcTemplate jdbc, Clock clock) {
        this.jobs = jobs;
        this.orders = orders;
        this.stores = stores;
        this.couriers = couriers;
        this.pricing = pricing;
        this.props = props;
        this.push = push;
        this.events = events;
        this.runner = runner;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @EventListener
    void statusChanged(StoreEvents.OrderStatusChanged e) {
        if (e.to() == OrderStatus.CONFIRMED) {
            open(e.orderId());
        } else if (e.to() == OrderStatus.CANCELED) {
            cancelForOrder(e.orderId());
        }
    }

    @EventListener
    void paid(StoreEvents.OrderPaid e) {
        open(e.orderId());
    }

    /** Abre a corrida (uma só por pedido) quando o pedido de entregador está pago e confirmado. */
    private void open(Long orderId) {
        CustomerOrder o = orders.find(orderId);
        if (!o.isCourierDelivery() || !o.isPaid() || o.getStatus() != OrderStatus.CONFIRMED
                || jobs.findByOrderId(orderId).isPresent()) {
            return;
        }
        Store store = stores.findById(TenantContext.get()).orElseThrow(() -> new NotFoundException("Loja não encontrada"));
        if (store.getLatitude() == null || store.getLongitude() == null || o.getDeliveryLat() == null) {
            log.warn("Pedido {} sem coordenadas: corrida não aberta", o.getCode());
            return;
        }
        DeliveryJob job = new DeliveryJob();
        job.setOrderId(o.getId());
        job.setOrderCode(o.getCode());
        job.setTenantId(store.getId());
        job.setStoreName(store.getName());
        job.setPickupAddress(store.getPickupAddress());
        job.setPickupLat(store.getLatitude());
        job.setPickupLng(store.getLongitude());
        job.setCity(store.getCity());
        job.setDropoffAddress(o.getAddress());
        job.setDropoffLat(o.getDeliveryLat());
        job.setDropoffLng(o.getDeliveryLng());
        job.setCustomerName(o.getCustomer().getName());
        job.setCustomerPhone(o.getCustomer().getPhone());
        job.setItemCount(o.itemCount());
        job.setDistanceKm(o.getDeliveryDistanceKm());
        job.setCustomerFee(o.getDeliveryFee());
        job.setCourierFee(pricing.courierPay(o.getCourierFreight() == null ? o.getDeliveryFee() : o.getCourierFreight()));
        job.setFreightPayer(o.getDeliveryFee().signum() > 0 ? "CUSTOMER" : "STORE");
        job.setPickupCode(code());
        job.setDeliveryCode(code());
        job.setCreatedAt(LocalDateTime.now(clock));
        job.setExpiresAt(job.getCreatedAt().plus(props.offerTtl()));
        jobs.save(job);
        offer(job);
    }

    private void cancelForOrder(Long orderId) {
        DeliveryJob job = jobs.findByOrderId(orderId).orElse(null);
        if (job == null || !(job.getStatus() == JobStatus.OPEN || job.getStatus().active())) {
            return;
        }
        Long courierId = job.getCourierId();
        job.setStatus(JobStatus.CANCELED);
        job.setCanceledAt(LocalDateTime.now(clock));
        job.setCancelReason("Pedido cancelado");
        if (courierId != null) {
            push.toUser(courierId, "job-canceled:" + job.getId(), "Corrida cancelada",
                    "O pedido #" + job.getOrderCode() + " foi cancelado. Você não precisa mais ir.", data(job, "JOB_CANCELED"));
        }
    }

    /** Volta ao mural (o entregador desistiu ou a loja chamou de novo) e avisa a região. */
    void reopen(DeliveryJob job) {
        job.setStatus(JobStatus.OPEN);
        job.setCourierId(null);
        job.setAcceptedAt(null);
        job.setOffers(job.getOffers() + 1);
        job.setExpiresAt(LocalDateTime.now(clock).plus(props.offerTtl()));
        offer(job);
    }

    /** A loja chama de novo uma corrida que ninguém aceitou. */
    @Transactional
    public void retry(Long orderId) {
        orders.lock(orderId);
        DeliveryJob job = jobs.findByOrderId(orderId).orElseThrow(() -> new NotFoundException("Esta entrega não usa entregador"));
        if (job.getStatus() != JobStatus.EXPIRED) {
            throw new BusinessException("Esta corrida não está parada: " + job.getStatus().label().toLowerCase() + ".");
        }
        reopen(job);
    }

    /** Push para os entregadores online mais próximos da loja (fila com reenvio e deduplicação por aviso/celular). */
    private void offer(DeliveryJob job) {
        List<Long> ids = couriers.nearbyOnline(job.getPickupLat(), job.getPickupLng(),
                LocalDateTime.now(clock).minus(props.freshPosition()), props.pushLimit());
        push.toUsers(ids, "offer:" + job.getId() + ":" + job.getOffers(), "Nova entrega: " + Money.format(job.getCourierFee()),
                job.getStoreName() + " · " + job.getDistanceKm().toPlainString().replace('.', ',') + " km até o cliente",
                data(job, "JOB_OFFER"));
    }

    static Map<String, String> data(DeliveryJob job, String kind) {
        Map<String, String> data = new HashMap<>();
        data.put("type", "courier");
        data.put("kind", kind);
        data.put("jobId", String.valueOf(job.getId()));
        return data;
    }

    /**
     * Expira em lote as corridas que ninguém aceitou. {@code SKIP LOCKED}: várias instâncias da API podem rodar isto ao
     * mesmo tempo sem pegar a mesma corrida.
     */
    @Scheduled(fixedDelayString = "${app.delivery.expire-check-ms:60000}")
    public void expireOld() {
        List<long[]> expired = jdbc.query("""
                update delivery_job set status = 'EXPIRED' where id in (
                  select id from delivery_job where status = 'OPEN' and expires_at < ? order by id limit 50 for update skip locked)
                returning id, tenant_id""", (rs, i) -> new long[] {rs.getLong(1), rs.getLong(2)}, LocalDateTime.now(clock));
        for (long[] row : expired) {
            try {
                runner.run(row[1], () -> events.publishEvent(new StoreEvents.DeliveryExpired(row[0])));
            } catch (RuntimeException e) {
                log.warn("Aviso de corrida expirada {} falhou", row[0], e);
            }
        }
    }

    private String code() {
        return String.format("%04d", random.nextInt(10000));
    }
}
