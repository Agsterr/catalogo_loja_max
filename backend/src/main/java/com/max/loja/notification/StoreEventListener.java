package com.max.loja.notification;

import java.util.Map;

import com.max.loja.auth.AppUser;
import com.max.loja.auth.AppUserRepository;
import com.max.loja.delivery.DeliveryJob;
import com.max.loja.delivery.DeliveryJobRepository;
import com.max.loja.event.StoreEvents;
import com.max.loja.notification.NotificationService.Target;
import com.max.loja.order.CustomerOrder;
import com.max.loja.order.DeliveryMethod;
import com.max.loja.order.OrderService;
import com.max.loja.order.OrderStatus;
import com.max.loja.promotion.Promotion;
import com.max.loja.shared.Money;
import com.max.loja.promotion.PromotionRepository;
import com.max.loja.push.PushNotifier;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Transforma os fatos da loja em avisos (sino + push). Roda na mesma transação de quem publicou: se o pedido
 * não gravar, o aviso também não existe.
 */
@Component
class StoreEventListener {

    private final NotificationService notifications;
    private final OrderService orders;
    private final ProductWatchService watches;
    private final PromotionRepository promotions;
    private final PushNotifier push;
    private final DeliveryJobRepository jobs;
    private final AppUserRepository users;

    StoreEventListener(NotificationService notifications, OrderService orders, ProductWatchService watches,
                       PromotionRepository promotions, PushNotifier push, DeliveryJobRepository jobs, AppUserRepository users) {
        this.jobs = jobs;
        this.users = users;
        this.notifications = notifications;
        this.orders = orders;
        this.watches = watches;
        this.promotions = promotions;
        this.push = push;
    }

    @EventListener
    void orderPlaced(StoreEvents.OrderPlaced e) {
        CustomerOrder o = orders.find(e.orderId());
        notifications.toTeam(Notification.Type.NEW_ORDER, "Novo pedido #" + o.getCode(),
                o.getCustomer().getName() + " · " + OrderService.describe(o), Target.order(o.getId()), "new-order:" + o.getId());
        notifications.toUser(o.getCustomer().getId(), Notification.Type.ORDER_STATUS, "Pedido #" + o.getCode() + " recebido",
                "A loja vai confirmar em breve. " + OrderService.describe(o), Target.order(o.getId()), null);
    }

    @EventListener
    void statusChanged(StoreEvents.OrderStatusChanged e) {
        CustomerOrder o = orders.find(e.orderId());
        if (e.byCustomer()) {
            if (e.to() == OrderStatus.CANCELED) {
                notifications.toTeam(Notification.Type.ORDER_CANCELED, "Pedido #" + o.getCode() + " cancelado pelo cliente",
                        o.getCustomer().getName() + " · " + OrderService.describe(o) + ". As peças voltaram ao estoque.",
                        Target.order(o.getId()), "canceled:" + o.getId());
            }
            return;
        }
        String title = "Pedido #" + o.getCode() + " · " + o.getStatus().label().toLowerCase();
        String message = switch (e.to()) {
            case CONFIRMED -> o.getDeliveryMethod() == DeliveryMethod.PICKUP
                    ? "A loja confirmou seu pedido e está separando as peças."
                    : "A loja confirmou seu pedido e está preparando a entrega.";
            case READY -> "Pode vir buscar! Seu pedido está pronto para retirada.";
            case SHIPPED -> "Seu pedido saiu para entrega.";
            case DELIVERED -> "Pedido entregue. Obrigado pela compra!";
            case CANCELED -> "A loja cancelou seu pedido" + (o.getCancelReason() != null ? ": " + o.getCancelReason() : ".");
            case PENDING -> "Pedido recebido.";
        };
        notifications.toUser(o.getCustomer().getId(), Notification.Type.ORDER_STATUS, title, message,
                Target.order(o.getId()), "status:" + o.getId() + ":" + e.to());
    }

    @EventListener
    void paid(StoreEvents.OrderPaid e) {
        CustomerOrder o = orders.find(e.orderId());
        notifications.toUser(o.getCustomer().getId(), Notification.Type.ORDER_PAID, "Pagamento confirmado",
                "Recebemos o pagamento do pedido #" + o.getCode() + ".", Target.order(o.getId()), "paid:" + o.getId());
    }

    @EventListener
    void stockLow(StoreEvents.StockLow e) {
        boolean out = e.stock() == 0;
        notifications.toTeam(out ? Notification.Type.OUT_OF_STOCK : Notification.Type.LOW_STOCK,
                out ? "Esgotou: " + e.productName() : "Estoque baixo: " + e.productName(),
                e.variant() + (out ? " acabou." : ": restam " + e.stock() + "."), Target.product(e.productId()), null);
    }

    @EventListener
    void backInStock(StoreEvents.BackInStock e) {
        for (Long userId : watches.takeWatchers(e.productId())) {
            notifications.toUser(userId, Notification.Type.BACK_IN_STOCK, "Chegou! " + e.productName(),
                    e.variant() + " voltou ao estoque. Corra, as peças são poucas!", Target.product(e.productId()), null);
        }
    }

    @EventListener
    void promotionStarted(StoreEvents.PromotionStarted e) {
        Promotion p = promotions.findById(e.promotionId()).orElse(null);
        if (p == null) {
            return;
        }
        String body = p.getDiscountPercent() + "% off em " + p.scopeLabel()
                + (p.getDescription() != null ? " · " + p.getDescription() : "");
        Map<String, String> data = new java.util.HashMap<>();
        data.put("type", "promotion");
        data.put("promotionId", String.valueOf(p.getId()));
        if (p.getProduct() != null) {
            data.put("productId", String.valueOf(p.getProduct().getId()));
        }
        push.promotion("promo:" + p.getId(), p.getTitle(), body, data);
    }

    @EventListener
    void deliveryAccepted(StoreEvents.DeliveryAccepted e) {
        DeliveryJob j = jobs.findById(e.jobId()).orElse(null);
        if (j == null) {
            return;
        }
        String who = users.findById(j.getCourierId()).map(AppUser::getName).orElse("O entregador");
        boolean storePays = "STORE".equals(j.getFreightPayer());
        notifications.toTeam(Notification.Type.DELIVERY_ASSIGNED, "Entregador a caminho · #" + j.getOrderCode(),
                who + " aceitou a entrega. Passe o código de coleta que está no pedido quando ele chegar."
                        + (storePays ? " O frete de " + Money.format(j.getCourierFee()) + " é por conta da loja: pague ao entregador na coleta." : ""),
                Target.order(j.getOrderId()), "delivery-accepted:" + j.getId() + ":" + j.getOffers());
        CustomerOrder o = orders.find(j.getOrderId());
        notifications.toUser(o.getCustomer().getId(), Notification.Type.ORDER_STATUS, "Entregador a caminho da loja · #" + j.getOrderCode(),
                who + " vai levar seu pedido. Na entrega, diga o código que está no pedido"
                        + (storePays ? "." : " e pague o frete de " + Money.format(j.getCustomerFee()) + " ao entregador (dinheiro ou Pix)."),
                Target.order(j.getOrderId()),
                "delivery-accepted-customer:" + j.getId() + ":" + j.getOffers());
    }

    @EventListener
    void deliveryReopened(StoreEvents.DeliveryReopened e) {
        DeliveryJob j = jobs.findById(e.jobId()).orElse(null);
        if (j != null) {
            notifications.toTeam(Notification.Type.DELIVERY_PROBLEM, "O entregador desistiu · #" + j.getOrderCode(),
                    "Já estamos chamando outro entregador para o pedido.", Target.order(j.getOrderId()),
                    "delivery-reopened:" + j.getId() + ":" + j.getOffers());
        }
    }

    @EventListener
    void deliveryExpired(StoreEvents.DeliveryExpired e) {
        DeliveryJob j = jobs.findById(e.jobId()).orElse(null);
        if (j != null) {
            notifications.toTeam(Notification.Type.DELIVERY_PROBLEM, "Nenhum entregador aceitou · #" + j.getOrderCode(),
                    "Abra o pedido para chamar de novo, ou faça a entrega por conta própria ou cancele.",
                    Target.order(j.getOrderId()), "delivery-expired:" + j.getId() + ":" + j.getOffers());
        }
    }

    @EventListener
    void deliveryDone(StoreEvents.DeliveryDone e) {
        DeliveryJob j = jobs.findById(e.jobId()).orElse(null);
        if (j != null) {
            notifications.toTeam(Notification.Type.DELIVERY_DONE, "Entrega concluída · #" + j.getOrderCode(),
                    "O pedido foi entregue ao cliente.", Target.order(j.getOrderId()), "delivery-done:" + j.getId());
        }
    }
}
