package com.max.loja.delivery;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;

import com.max.loja.auth.AppUser;
import com.max.loja.auth.AppUserRepository;
import com.max.loja.order.CustomerOrder;
import com.max.loja.order.OrderService;
import com.max.loja.shared.NotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Acompanhamento ao vivo: a loja vê o entregador desde que ele aceita; o cliente, depois que ele coleta o pedido. Só a última
 * posição existe (nada de histórico de trajeto) e só enquanto a corrida está ativa.
 */
@Service
public class TrackingService {

    /** Entregador em movimento na cidade (km/h) e fator de rua sobre a linha reta: só para a previsão. */
    private static final double AVG_KMH = 20;
    private static final double STREET_FACTOR = 1.3;
    private static final Duration STALE_AFTER = Duration.ofMinutes(2);

    /**
     * {@code target}: para onde ele vai (LOJA ou CLIENTE). {@code stale}: a última posição é antiga (app fechado/sem sinal).
     * {@code etaMinutes} é uma estimativa pela distância em linha reta, não por rota.
     */
    public record Tracking(boolean active, String status, String statusLabel, String courierName, Double lat, Double lng,
                           LocalDateTime updatedAt, boolean stale, Double distanceKm, Integer etaMinutes, String target) {
    }

    private final DeliveryJobRepository jobs;
    private final AppUserRepository users;
    private final OrderService orders;
    private final Clock clock;

    public TrackingService(DeliveryJobRepository jobs, AppUserRepository users, OrderService orders, Clock clock) {
        this.jobs = jobs;
        this.users = users;
        this.orders = orders;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public Tracking forCustomer(Long customerId, Long orderId) {
        return build(orders.findForCustomer(customerId, orderId), false);
    }

    @Transactional(readOnly = true)
    public Tracking forTeam(Long orderId) {
        return build(orders.find(orderId), true);
    }

    private Tracking build(CustomerOrder order, boolean team) {
        DeliveryJob job = order.isCourierDelivery() ? jobs.findByOrderId(order.getId()).orElse(null) : null;
        if (job == null) {
            throw new NotFoundException("Este pedido não tem entregador");
        }
        boolean visible = job.getStatus() == JobStatus.PICKED_UP || (team && job.getStatus() == JobStatus.ACCEPTED);
        if (!visible) {
            return new Tracking(false, job.getStatus().name(), job.getStatus().label(), null, null, null, null, false, null, null, null);
        }
        String name = users.findById(job.getCourierId()).map(AppUser::getName).orElse(null);
        boolean toStore = job.getStatus() == JobStatus.ACCEPTED;
        Double distance = null;
        Integer eta = null;
        if (job.getCourierLat() != null) {
            double km = km(job.getCourierLat(), job.getCourierLng(), toStore ? job.getPickupLat() : job.getDropoffLat(),
                    toStore ? job.getPickupLng() : job.getDropoffLng());
            distance = Math.round(km * 10) / 10.0;
            eta = (int) Math.max(1, Math.ceil(km * STREET_FACTOR / AVG_KMH * 60));
        }
        boolean stale = job.getCourierAt() == null || job.getCourierAt().isBefore(LocalDateTime.now(clock).minus(STALE_AFTER));
        return new Tracking(true, job.getStatus().name(), job.getStatus().label(), name, job.getCourierLat(), job.getCourierLng(),
                job.getCourierAt(), stale, distance, eta, toStore ? "LOJA" : "CLIENTE");
    }

    static double km(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.pow(Math.sin(dLat / 2), 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.pow(Math.sin(dLng / 2), 2);
        return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}
