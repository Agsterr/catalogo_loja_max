package com.max.loja.order;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class OrderDtos {

    private OrderDtos() {
    }

    public record ItemRequest(@NotNull Long variantId, @Min(1) @Max(20) int quantity) {
    }

    public record PlaceOrderRequest(@NotEmpty @Size(max = 30) List<@Valid ItemRequest> items,
                                    @NotNull DeliveryMethod deliveryMethod, @NotNull PaymentMethod paymentMethod,
                                    @Size(max = 400) String address, @Size(max = 500) String notes,
                                    Double deliveryLat, Double deliveryLng) {
    }

    public record StatusRequest(@NotNull OrderStatus status, @Size(max = 300) String note) {
    }

    public record CancelRequest(@Size(max = 300) String reason) {
    }

    public record ItemResponse(Long productId, Long variantId, String productName, String size, String color,
                               BigDecimal unitPrice, int quantity, BigDecimal total, String thumbUrl) {
    }

    public record EventResponse(OrderStatus status, String label, String note, boolean byCustomer, LocalDateTime createdAt) {
    }

    public record CustomerInfo(Long id, String name, String email, String phone) {
    }

    public record OrderResponse(Long id, String code, OrderStatus status, String statusLabel, List<OrderStatus> nextStatuses,
                                boolean canCancel, DeliveryMethod deliveryMethod, PaymentMethod paymentMethod, boolean paid,
                                String address, String notes, BigDecimal subtotal, BigDecimal discount,
                                BigDecimal deliveryFee, BigDecimal total, String cancelReason, LocalDateTime createdAt,
                                LocalDateTime updatedAt, CustomerInfo customer, List<ItemResponse> items,
                                List<EventResponse> events) {
    }

    public record OrderSummary(Long id, String code, OrderStatus status, String statusLabel, DeliveryMethod deliveryMethod,
                               boolean paid, BigDecimal total, int itemCount, String customerName, String firstItem,
                               String thumbUrl, LocalDateTime createdAt) {
    }
}
