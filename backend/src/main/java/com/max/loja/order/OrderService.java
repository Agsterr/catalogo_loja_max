package com.max.loja.order;

import java.math.BigDecimal;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import com.max.loja.auth.AppUser;
import com.max.loja.auth.AppUserRepository;
import com.max.loja.catalog.ProductVariant;
import com.max.loja.delivery.CourierRepository;
import com.max.loja.delivery.DeliveryJob;
import com.max.loja.delivery.DeliveryJobRepository;
import com.max.loja.delivery.JobStatus;
import com.max.loja.catalog.ProductVariantRepository;
import com.max.loja.catalog.StockMovement;
import com.max.loja.catalog.StockService;
import com.max.loja.event.StoreEvents;
import com.max.loja.media.ProductPhoto;
import com.max.loja.media.ProductPhotoRepository;
import com.max.loja.order.OrderDtos.CourierInfo;
import com.max.loja.order.OrderDtos.CustomerInfo;
import com.max.loja.order.OrderDtos.EventResponse;
import com.max.loja.order.OrderDtos.ItemRequest;
import com.max.loja.order.OrderDtos.ItemResponse;
import com.max.loja.order.OrderDtos.OrderResponse;
import com.max.loja.order.OrderDtos.OrderSummary;
import com.max.loja.order.OrderDtos.PlaceOrderRequest;
import com.max.loja.promotion.PricingService;
import com.max.loja.promotion.Promotion;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.Money;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import com.max.loja.shared.Search;
import com.max.loja.auth.StaffService;
import com.max.loja.store.Store;
import com.max.loja.store.StoreService;
import jakarta.persistence.criteria.Predicate;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OrderService {

    /** Proteção contra pedidos falsos em massa: pedidos aguardando confirmação por cliente e pedidos por dia. */
    static final int MAX_PENDING_PER_CUSTOMER = 5;
    static final int MAX_ORDERS_PER_DAY = 20;
    private static final String CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    private final OrderRepository orders;
    private final ProductVariantRepository variants;
    private final AppUserRepository users;
    private final StockService stock;
    private final PricingService pricing;
    private final StoreService stores;
    private final StaffService staff;
    private final ProductPhotoRepository photos;
    private final DeliveryJobRepository jobs;
    private final CourierRepository couriers;
    private final ApplicationEventPublisher events;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    public OrderService(OrderRepository orders, ProductVariantRepository variants, AppUserRepository users,
                        StockService stock, PricingService pricing, StoreService stores, StaffService staff,
                        ProductPhotoRepository photos, DeliveryJobRepository jobs, CourierRepository couriers,
                        ApplicationEventPublisher events, Clock clock) {
        this.jobs = jobs;
        this.couriers = couriers;
        this.orders = orders;
        this.variants = variants;
        this.users = users;
        this.stock = stock;
        this.pricing = pricing;
        this.stores = stores;
        this.staff = staff;
        this.photos = photos;
        this.events = events;
        this.clock = clock;
    }

    // --- cliente ---

    /**
     * Fecha o pedido: trava os tamanhos/cores, confere estoque, calcula o preço do momento (promoções) e baixa o
     * estoque na mesma transação. Preço e quantidade vêm do servidor, nunca do app.
     */
    @Transactional
    public OrderResponse place(Long customerId, PlaceOrderRequest req) {
        AppUser customer = users.findById(customerId).orElseThrow(() -> new NotFoundException("Cliente não encontrado"));
        LocalDateTime now = LocalDateTime.now(clock);
        if (orders.countByCustomerIdAndStatus(customerId, OrderStatus.PENDING) >= MAX_PENDING_PER_CUSTOMER) {
            throw new BusinessException("Você já tem pedidos aguardando confirmação. Aguarde a loja confirmar.");
        }
        if (orders.countByCustomerIdAndCreatedAtAfter(customerId, now.minusDays(1)) >= MAX_ORDERS_PER_DAY) {
            throw new BusinessException("Limite de pedidos do dia atingido. Fale com a loja pelo WhatsApp.");
        }
        // bloqueado por esta loja (pedidos falsos etc.): não compra aqui, mas segue comprando nas outras
        staff.blockReason(customerId).ifPresent(reason -> {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, reason.isBlank()
                    ? "Esta loja não está aceitando pedidos da sua conta. Fale com ela pelo WhatsApp."
                    : "Esta loja bloqueou seus pedidos: " + reason);
        });
        Store store = stores.current();
        String address = req.address() == null ? null : req.address().trim();
        if (req.deliveryMethod() == DeliveryMethod.DELIVERY) {
            if (!store.isDeliveryEnabled()) {
                throw new BusinessException("A loja não está fazendo entregas no momento.");
            }
            if (address == null || address.length() < 10) {
                throw new BusinessException("Informe o endereço completo para a entrega.");
            }
        } else {
            if (!store.isPickupEnabled()) {
                throw new BusinessException("A loja não está com retirada no momento.");
            }
            address = null;
        }

        // junta o mesmo tamanho/cor que veio em linhas diferentes
        Map<Long, Integer> wanted = new LinkedHashMap<>();
        for (ItemRequest i : req.items()) {
            wanted.merge(i.variantId(), i.quantity(), Integer::sum);
        }
        Map<Long, ProductVariant> locked = new LinkedHashMap<>();
        variants.lockAll(wanted.keySet()).forEach(v -> locked.put(v.getId(), v));
        List<Promotion> running = pricing.running();

        CustomerOrder order = new CustomerOrder();
        order.setCustomer(customer);
        order.setCode(newCode());
        order.setDeliveryMethod(req.deliveryMethod());
        order.setPaymentMethod(req.paymentMethod());
        order.setAddress(address);
        order.setNotes(req.notes() == null || req.notes().isBlank() ? null : req.notes().trim());
        order.setCreatedAt(now);
        order.setUpdatedAt(now);

        BigDecimal subtotal = BigDecimal.ZERO;
        BigDecimal saved = BigDecimal.ZERO;
        for (Map.Entry<Long, Integer> e : wanted.entrySet()) {
            ProductVariant v = locked.get(e.getKey());
            if (v == null || !v.isActive() || !v.getProduct().isActive()) {
                throw new BusinessException("Um dos produtos do carrinho não está mais à venda. Atualize o carrinho.");
            }
            int qty = e.getValue();
            if (qty > 20) {
                throw new BusinessException("Máximo de 20 unidades por tamanho/cor.");
            }
            if (v.getStock() < qty) {
                throw new BusinessException(v.getStock() == 0
                        ? v.getProduct().getName() + " (" + v.label() + ") esgotou."
                        : "Só restam " + v.getStock() + " de " + v.getProduct().getName() + " (" + v.label() + ").");
            }
            PricingService.Price price = pricing.price(v.getProduct(), running);
            OrderItem item = new OrderItem();
            item.setOrder(order);
            item.setProductId(v.getProduct().getId());
            item.setVariantId(v.getId());
            item.setProductName(v.getProduct().getName());
            item.setSize(v.getSize());
            item.setColor(v.getColor());
            item.setUnitPrice(price.finalPrice());
            item.setQuantity(qty);
            item.setTotal(Money.round(price.finalPrice().multiply(BigDecimal.valueOf(qty))));
            order.getItems().add(item);
            subtotal = subtotal.add(item.getTotal());
            saved = saved.add(price.price().subtract(price.finalPrice()).multiply(BigDecimal.valueOf(qty)));
        }
        BigDecimal fee = BigDecimal.ZERO;
        if (req.deliveryMethod() == DeliveryMethod.DELIVERY) {
            StoreService.DeliveryQuote quote = stores.deliveryQuote(store, req.deliveryLat(), req.deliveryLng(), subtotal);
            if (!quote.available()) {
                throw new BusinessException(quote.message());
            }
            fee = quote.fee();
            if (store.isCourierDelivery()) {
                if (req.paymentMethod() == PaymentMethod.CASH) {
                    throw new BusinessException("Entrega por entregador só aceita pagamento antecipado (Pix ou cartão).");
                }
                order.setCourierDelivery(true);
                order.setDeliveryLat(req.deliveryLat());
                order.setDeliveryLng(req.deliveryLng());
                order.setDeliveryDistanceKm(BigDecimal.valueOf(quote.distanceKm()));
                order.setCourierFreight(quote.freight());
            }
        }
        order.setSubtotal(Money.round(subtotal));
        order.setDiscount(Money.round(saved));
        order.setDeliveryFee(Money.round(fee));
        // entregador da plataforma: o frete é pago direto a ele, então o total do pedido (o que a loja recebe) é só dos produtos
        order.setTotal(Money.round(order.isCourierDelivery() ? subtotal : subtotal.add(fee)));
        addEvent(order, OrderStatus.PENDING, null, customerId, now);
        orders.save(order);

        for (OrderItem item : order.getItems()) {
            stock.apply(locked.get(item.getVariantId()), -item.getQuantity(), StockMovement.Type.SALE,
                    "Pedido " + order.getCode(), order.getId(), customerId);
        }
        events.publishEvent(new StoreEvents.OrderPlaced(order.getId()));
        return response(order, false);
    }

    @Transactional(readOnly = true)
    public PageResponse<OrderSummary> myOrders(Long customerId, Integer page, Integer size) {
        return PageResponse.of(orders.findByCustomerId(customerId, PageResponse.request(page, size, Sort.by(Sort.Order.desc("id")))),
                this::summary);
    }

    /** Só o dono do pedido vê: pedido de outro cliente responde 404 (não revela que existe). */
    @Transactional(readOnly = true)
    public OrderResponse myOrder(Long customerId, Long orderId) {
        return response(orders.findByIdAndCustomerId(orderId, customerId)
                .orElseThrow(() -> new NotFoundException("Pedido não encontrado")), false);
    }

    @Transactional
    public OrderResponse cancelByCustomer(Long customerId, Long orderId, String reason) {
        CustomerOrder order = orders.lock(orderId).filter(o -> o.getCustomer().getId().equals(customerId))
                .orElseThrow(() -> new NotFoundException("Pedido não encontrado"));
        if (!order.getStatus().customerCanCancel()) {
            throw new BusinessException("Este pedido já está " + order.getStatus().label().toLowerCase()
                    + ". Para cancelar, fale com a loja.");
        }
        cancel(order, reason == null || reason.isBlank() ? "Cancelado pelo cliente" : reason.trim(), customerId, true);
        return response(order, false);
    }

    // --- equipe ---

    @Transactional(readOnly = true)
    public PageResponse<OrderSummary> storeOrders(OrderStatus status, boolean open, String q, Integer page, Integer size) {
        Specification<CustomerOrder> spec = (root, query, cb) -> {
            List<Predicate> where = new ArrayList<>();
            if (status != null) {
                where.add(cb.equal(root.get("status"), status));
            } else if (open) {
                where.add(root.get("status").in(OrderStatus.DELIVERED, OrderStatus.CANCELED).not());
            }
            if (q != null && !q.isBlank()) {
                String like = Search.like(q);
                var customer = root.join("customer");
                where.add(cb.or(cb.like(cb.lower(root.get("code")), like), cb.like(Search.plain(cb, customer.get("name")), like),
                        cb.like(customer.get("phone"), like)));
            }
            return cb.and(where.toArray(Predicate[]::new));
        };
        return PageResponse.of(orders.findAll(spec, PageResponse.request(page, size, Sort.by(Sort.Order.desc("id")))),
                this::summary);
    }

    @Transactional(readOnly = true)
    public OrderResponse storeOrder(Long orderId) {
        return response(find(orderId), true);
    }

    @Transactional
    public OrderResponse changeStatus(Long orderId, OrderStatus to, String note, Long actorId) {
        CustomerOrder order = orders.lock(orderId).orElseThrow(() -> new NotFoundException("Pedido não encontrado"));
        OrderStatus from = order.getStatus();
        if (!from.next(order.getDeliveryMethod()).contains(to)) {
            throw new BusinessException("Não dá para passar de \"" + from.label() + "\" para \"" + to.label() + "\".");
        }
        if (order.isCourierDelivery() && (to == OrderStatus.SHIPPED || to == OrderStatus.DELIVERED)) {
            throw new BusinessException("Esta entrega é feita por um entregador da plataforma: ele confirma a coleta e a entrega.");
        }
        if (to == OrderStatus.CANCELED) {
            cancel(order, note == null || note.isBlank() ? "Cancelado pela loja" : note.trim(), actorId, false);
        } else {
            LocalDateTime now = LocalDateTime.now(clock);
            order.setStatus(to);
            order.setUpdatedAt(now);
            addEvent(order, to, note, actorId, now);
            events.publishEvent(new StoreEvents.OrderStatusChanged(order.getId(), from, to, false, actorId));
        }
        return response(order, true);
    }

    /**
     * Passo dado pelo entregador (coleta → "saiu para entrega", entrega → "entregue"). Chamado dentro da transação do
     * tenant do pedido, depois de travar o pedido.
     */
    public void courierStep(CustomerOrder order, OrderStatus to, Long courierUserId, String courierName) {
        OrderStatus from = order.getStatus();
        if (!from.next(order.getDeliveryMethod()).contains(to)) {
            throw new BusinessException("Este pedido está \"" + from.label().toLowerCase() + "\" e não pode ir para \""
                    + to.label().toLowerCase() + "\".");
        }
        LocalDateTime now = LocalDateTime.now(clock);
        order.setStatus(to);
        order.setUpdatedAt(now);
        addEvent(order, to, "Entregador: " + courierName, courierUserId, now);
        events.publishEvent(new StoreEvents.OrderStatusChanged(order.getId(), from, to, false, courierUserId));
    }

    @Transactional
    public OrderResponse markPaid(Long orderId, boolean paid) {
        CustomerOrder order = orders.lock(orderId).orElseThrow(() -> new NotFoundException("Pedido não encontrado"));
        if (order.getStatus() == OrderStatus.CANCELED) {
            throw new BusinessException("Pedido cancelado.");
        }
        boolean changed = order.isPaid() != paid;
        order.setPaid(paid);
        order.setUpdatedAt(LocalDateTime.now(clock));
        if (changed && paid) {
            events.publishEvent(new StoreEvents.OrderPaid(order.getId()));
        }
        return response(order, true);
    }

    /** Cancela e devolve as peças ao estoque. */
    private void cancel(CustomerOrder order, String reason, Long actorId, boolean byCustomer) {
        OrderStatus from = order.getStatus();
        LocalDateTime now = LocalDateTime.now(clock);
        Map<Long, ProductVariant> locked = new LinkedHashMap<>();
        variants.lockAll(order.getItems().stream().map(OrderItem::getVariantId).distinct().toList())
                .forEach(v -> locked.put(v.getId(), v));
        for (OrderItem item : order.getItems()) {
            ProductVariant v = locked.get(item.getVariantId());
            if (v != null) {
                stock.apply(v, item.getQuantity(), StockMovement.Type.RETURN, "Pedido " + order.getCode() + " cancelado",
                        order.getId(), actorId);
            }
        }
        order.setStatus(OrderStatus.CANCELED);
        order.setCancelReason(reason.length() > 300 ? reason.substring(0, 300) : reason);
        order.setUpdatedAt(now);
        addEvent(order, OrderStatus.CANCELED, reason, actorId, now);
        events.publishEvent(new StoreEvents.OrderStatusChanged(order.getId(), from, OrderStatus.CANCELED, byCustomer, actorId));
    }

    /** Pedido travado para alterar (mesma ordem de lock em todos os caminhos: pedido primeiro). */
    public CustomerOrder lock(Long orderId) {
        return orders.lock(orderId).orElseThrow(() -> new NotFoundException("Pedido não encontrado"));
    }

    @Transactional(readOnly = true)
    public CustomerOrder find(Long orderId) {
        return orders.findById(orderId).orElseThrow(() -> new NotFoundException("Pedido não encontrado"));
    }

    private static void addEvent(CustomerOrder order, OrderStatus status, String note, Long userId, LocalDateTime at) {
        OrderEvent e = new OrderEvent();
        e.setOrder(order);
        e.setStatus(status);
        e.setNote(note == null || note.isBlank() ? null : note.trim());
        e.setUserId(userId);
        e.setCreatedAt(at);
        order.getEvents().add(e);
    }

    private String newCode() {
        for (int attempt = 0; attempt < 10; attempt++) {
            StringBuilder sb = new StringBuilder(6);
            for (int i = 0; i < 6; i++) {
                sb.append(CODE_ALPHABET.charAt(random.nextInt(CODE_ALPHABET.length())));
            }
            if (!orders.existsByCode(sb.toString())) {
                return sb.toString();
            }
        }
        throw new IllegalStateException("Não foi possível gerar o código do pedido");
    }

    // --- respostas ---

    private OrderSummary summary(CustomerOrder o) {
        OrderItem first = o.getItems().isEmpty() ? null : o.getItems().get(0);
        return new OrderSummary(o.getId(), o.getCode(), o.getStatus(), o.getStatus().label(), o.getDeliveryMethod(),
                o.isPaid(), o.getTotal(), o.itemCount(), o.getCustomer().getName(),
                first == null ? null : first.getProductName(), first == null ? null : cover(first.getProductId()),
                o.getCreatedAt());
    }

    OrderResponse response(CustomerOrder o, boolean forTeam) {
        AppUser c = o.getCustomer();
        Long customerId = c.getId();
        List<ItemResponse> items = o.getItems().stream().map(i -> new ItemResponse(i.getProductId(), i.getVariantId(),
                i.getProductName(), i.getSize(), i.getColor(), i.getUnitPrice(), i.getQuantity(), i.getTotal(),
                cover(i.getProductId()))).toList();
        List<EventResponse> timeline = o.getEvents().stream().map(e -> new EventResponse(e.getStatus(), e.getStatus().label(),
                e.getNote(), Objects.equals(e.getUserId(), customerId), e.getCreatedAt())).toList();
        return new OrderResponse(o.getId(), o.getCode(), o.getStatus(), o.getStatus().label(),
                forTeam ? teamNext(o) : List.of(),
                !forTeam && o.getStatus().customerCanCancel(), o.getDeliveryMethod(), o.getPaymentMethod(), o.isPaid(),
                o.getAddress(), o.getNotes(), o.getSubtotal(), o.getDiscount(), o.getDeliveryFee(), o.getTotal(),
                o.getCancelReason(), o.getCreatedAt(), o.getUpdatedAt(),
                forTeam ? new CustomerInfo(customerId, c.getName(), c.getEmail(), c.getPhone()) : null, items, timeline,
                courierInfo(o, forTeam));
    }

    /** Próximos status da equipe; num pedido de entregador, coleta e entrega são dele (e depois de coletado não cancela). */
    private List<OrderStatus> teamNext(CustomerOrder o) {
        java.util.Set<OrderStatus> next = new java.util.TreeSet<>(o.getStatus().next(o.getDeliveryMethod()));
        if (o.isCourierDelivery()) {
            next.remove(OrderStatus.SHIPPED);
            next.remove(OrderStatus.DELIVERED);
            if (o.getStatus() == OrderStatus.SHIPPED) {
                next.remove(OrderStatus.CANCELED);
            }
        }
        return List.copyOf(next);
    }

    private CourierInfo courierInfo(CustomerOrder o, boolean forTeam) {
        if (!o.isCourierDelivery()) {
            return null;
        }
        DeliveryJob job = jobs.findByOrderId(o.getId()).orElse(null);
        if (job == null) {
            // ainda não abriu: falta o pagamento e/ou a confirmação da loja
            String wait = !o.isPaid() ? "Aguardando o pagamento" : "Aguardando a loja confirmar";
            return new CourierInfo("WAITING", wait, null, null, null, null, null, null, false, o.getCourierFreight(),
                    o.getDeliveryFee().signum() > 0 ? "CUSTOMER" : "STORE");
        }
        var courier = job.getCourierId() == null ? null : couriers.findById(job.getCourierId()).orElse(null);
        String name = courier == null ? null : users.findById(courier.getUserId()).map(AppUser::getName).orElse(null);
        boolean shown = job.getStatus().active();
        return new CourierInfo(job.getStatus().name(), job.getStatus().label(), shown || job.getStatus() == JobStatus.DELIVERED ? name : null,
                shown ? courier.getPhone() : null, shown && courier != null ? courier.getVehicle().label() : null,
                forTeam && shown ? job.getPickupCode() : null, !forTeam && job.getStatus().active() ? job.getDeliveryCode() : null,
                job.getStatus() == JobStatus.OPEN ? job.getExpiresAt() : null, forTeam && job.getStatus() == JobStatus.EXPIRED,
                o.getCourierFreight(), job.getFreightPayer());
    }

    private String cover(Long productId) {
        List<ProductPhoto> list = photos.findByProductIdOrderByPositionAscIdAsc(productId);
        return list.isEmpty() ? null : list.get(0).getThumbUrl();
    }

    /** Resumo do pedido para os avisos ("2 itens · R$ 189,90"). */
    public static String describe(CustomerOrder o) {
        int n = o.itemCount();
        return (n == 1 ? "1 item" : n + " itens") + " · " + Money.format(o.getTotal())
                + (o.getDeliveryMethod() == DeliveryMethod.DELIVERY ? " · entrega" : " · retirada");
    }

    /** Usado pelos avisos para nomear o produto do primeiro item. */
    public static String firstProduct(CustomerOrder o) {
        return o.getItems().isEmpty() ? "" : o.getItems().get(0).getProductName();
    }
}
