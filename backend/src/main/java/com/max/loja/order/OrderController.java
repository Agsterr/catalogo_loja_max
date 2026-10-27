package com.max.loja.order;

import com.max.loja.order.OrderDtos.CancelRequest;
import com.max.loja.order.OrderDtos.OrderResponse;
import com.max.loja.order.OrderDtos.OrderSummary;
import com.max.loja.order.OrderDtos.PlaceOrderRequest;
import com.max.loja.order.OrderDtos.StatusRequest;
import com.max.loja.shared.PageResponse;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class OrderController {

    public record PaidRequest(boolean paid) {
    }

    private final OrderService service;

    public OrderController(OrderService service) {
        this.service = service;
    }

    // --- cliente (só os pedidos dele) ---

    @PostMapping("/api/orders")
    @ResponseStatus(HttpStatus.CREATED)
    public OrderResponse place(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody PlaceOrderRequest req) {
        return service.place(id(jwt), req);
    }

    @GetMapping("/api/orders")
    public PageResponse<OrderSummary> mine(@AuthenticationPrincipal Jwt jwt, @RequestParam(required = false) Integer page,
                                           @RequestParam(required = false) Integer size) {
        return service.myOrders(id(jwt), page, size);
    }

    @GetMapping("/api/orders/{orderId}")
    public OrderResponse myOrder(@AuthenticationPrincipal Jwt jwt, @PathVariable Long orderId) {
        return service.myOrder(id(jwt), orderId);
    }

    @PostMapping("/api/orders/{orderId}/cancel")
    public OrderResponse cancel(@AuthenticationPrincipal Jwt jwt, @PathVariable Long orderId,
                                @Valid @RequestBody(required = false) CancelRequest req) {
        return service.cancelByCustomer(id(jwt), orderId, req == null ? null : req.reason());
    }

    // --- equipe ---

    /** {@code open=true} (padrão): só os que ainda não terminaram. */
    @GetMapping("/api/store/orders")
    public PageResponse<OrderSummary> storeOrders(@RequestParam(required = false) OrderStatus status,
                                                  @RequestParam(defaultValue = "true") boolean open,
                                                  @RequestParam(required = false) String q,
                                                  @RequestParam(required = false) Integer page,
                                                  @RequestParam(required = false) Integer size) {
        return service.storeOrders(status, open, q == null || q.length() <= 60 ? q : q.substring(0, 60), page, size);
    }

    @GetMapping("/api/store/orders/{orderId}")
    public OrderResponse storeOrder(@PathVariable Long orderId) {
        return service.storeOrder(orderId);
    }

    @PostMapping("/api/store/orders/{orderId}/status")
    public OrderResponse status(@AuthenticationPrincipal Jwt jwt, @PathVariable Long orderId,
                                @Valid @RequestBody StatusRequest req) {
        return service.changeStatus(orderId, req.status(), req.note(), id(jwt));
    }

    @PostMapping("/api/store/orders/{orderId}/paid")
    public OrderResponse paid(@PathVariable Long orderId, @RequestBody PaidRequest req) {
        return service.markPaid(orderId, req.paid());
    }

    private static Long id(Jwt jwt) {
        return Long.valueOf(jwt.getSubject());
    }
}
