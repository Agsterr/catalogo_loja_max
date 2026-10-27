package com.max.loja.delivery;

import java.time.Clock;
import java.time.LocalDateTime;

import com.max.loja.order.CustomerOrder;
import com.max.loja.order.OrderService;
import com.max.loja.order.OrderStatus;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** O cliente avalia o entregador (1 a 5 estrelas) uma vez por pedido entregue. A média aparece para loja, cliente e admin. */
@Service
public class CourierRatingService {

    public record Result(Double ratingAvg, int ratingCount) {
    }

    private final CourierRatingRepository ratings;
    private final CourierRepository couriers;
    private final DeliveryJobRepository jobs;
    private final OrderService orders;
    private final Clock clock;

    public CourierRatingService(CourierRatingRepository ratings, CourierRepository couriers, DeliveryJobRepository jobs,
                                OrderService orders, Clock clock) {
        this.ratings = ratings;
        this.couriers = couriers;
        this.jobs = jobs;
        this.orders = orders;
        this.clock = clock;
    }

    @Transactional
    public Result rate(Long customerId, Long orderId, int stars, String comment) {
        CustomerOrder order = orders.findForCustomer(customerId, orderId);
        DeliveryJob job = order.isCourierDelivery() ? jobs.findByOrderId(orderId).orElse(null) : null;
        if (job == null || job.getCourierId() == null || order.getStatus() != OrderStatus.DELIVERED || job.getStatus() != JobStatus.DELIVERED) {
            throw new BusinessException("Você pode avaliar o entregador depois que o pedido for entregue.");
        }
        if (ratings.existsByOrderId(orderId)) {
            throw new BusinessException("Você já avaliou este entregador.");
        }
        Courier courier = couriers.lock(job.getCourierId()).orElseThrow(() -> new NotFoundException("Entregador não encontrado"));
        CourierRating r = new CourierRating();
        r.setOrderId(orderId);
        r.setCourierId(courier.getUserId());
        r.setStoreId(TenantContext.get());
        r.setCustomerId(customerId);
        r.setStars(stars);
        r.setComment(comment == null || comment.isBlank() ? null : comment.trim());
        r.setCreatedAt(LocalDateTime.now(clock));
        ratings.save(r);
        courier.setRatingSum(courier.getRatingSum() + stars);
        courier.setRatingCount(courier.getRatingCount() + 1);
        return new Result(courier.ratingAvg(), courier.getRatingCount());
    }
}
