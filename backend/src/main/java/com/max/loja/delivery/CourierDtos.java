package com.max.loja.delivery;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public final class CourierDtos {

    private static final String PASSWORD = "^(?=.*[A-Za-z])(?=.*\\d).{8,72}$";
    private static final String PASSWORD_MSG = "A senha precisa ter de 8 a 72 caracteres, com letras e números";

    private CourierDtos() {
    }

    /** Cadastro do entregador pelo app (fica pendente até a plataforma aprovar). */
    public record RegisterRequest(
            @NotBlank @Size(max = 120) String name,
            @NotBlank @Email @Size(max = 180) String email,
            @NotBlank @Size(min = 8, max = 30) String phone,
            @NotBlank @Size(max = 20) String cpf,
            @NotBlank @Pattern(regexp = PASSWORD, message = PASSWORD_MSG) String password,
            @NotNull Vehicle vehicle,
            @Size(max = 12) String plate,
            @NotBlank @Size(max = 80) String city,
            @NotBlank @Pattern(regexp = "^[A-Za-z]{2}$") String state,
            @DecimalMin("-90") @DecimalMax("90") Double baseLat,
            @DecimalMin("-180") @DecimalMax("180") Double baseLng,
            @Min(1) @Max(50) Integer radiusKm) {
    }

    public record ProfileRequest(
            @NotBlank @Size(min = 8, max = 30) String phone,
            @NotNull Vehicle vehicle,
            @Size(max = 12) String plate,
            @NotBlank @Size(max = 80) String city,
            @NotBlank @Pattern(regexp = "^[A-Za-z]{2}$") String state,
            @DecimalMin("-90") @DecimalMax("90") Double baseLat,
            @DecimalMin("-180") @DecimalMax("180") Double baseLng,
            @NotNull @Min(1) @Max(50) Integer radiusKm) {
    }

    public record OnlineRequest(boolean online, @DecimalMin("-90") @DecimalMax("90") Double lat,
                                @DecimalMin("-180") @DecimalMax("180") Double lng) {
    }

    public record CodeRequest(@NotBlank @Size(max = 6) String code) {
    }

    public record CancelRequest(@Size(max = 300) String reason) {
    }

    public record ProfileResponse(Long id, String name, String email, String phone, Vehicle vehicle, String vehicleLabel,
                                  String plate, String city, String state, Double baseLat, Double baseLng, int radiusKm,
                                  CourierStatus status, String statusReason, boolean online, int deliveredCount,
                                  int canceledCount, LocalDateTime createdAt, String cpfMasked) {
    }

    /** Corrida no mural: sem o endereço nem o nome do cliente (só depois do aceite). */
    public record JobCard(Long id, String storeName, String pickupAddress, String city, Double distanceToStoreKm,
                          BigDecimal tripKm, BigDecimal fee, String freightPayer, int itemCount, LocalDateTime createdAt,
                          LocalDateTime expiresAt) {
    }

    /** Corrida aceita: endereço e telefone do cliente liberados. Os códigos nunca vêm aqui. */
    public record JobDetail(Long id, String orderCode, String status, String statusLabel, String storeName,
                            String pickupAddress, double pickupLat, double pickupLng, String dropoffAddress,
                            Double dropoffLat, Double dropoffLng, String customerName, String customerPhone,
                            BigDecimal tripKm, BigDecimal fee, String freightPayer, int itemCount, LocalDateTime acceptedAt,
                            LocalDateTime pickedUpAt, LocalDateTime deliveredAt) {
    }

    public record Money2(BigDecimal total, long count) {
    }

    public record EarningsResponse(Money2 today, Money2 week, Money2 month) {
    }

    /** Linha da lista do admin da plataforma. */
    public record AdminCourier(Long id, String name, String email, String phone, Vehicle vehicle, String plate,
                               String city, String state, CourierStatus status, String statusReason, boolean online,
                               int deliveredCount, int canceledCount, LocalDateTime createdAt) {
    }

    public record ReasonRequest(@Size(max = 300) String reason) {
    }

    /** Assinatura e entregas grátis: o que o app mostra e se pode aceitar corrida agora. */
    public record SubscriptionResponse(boolean subscribed, LocalDateTime paidUntil, int freeLeft, int freeLimit, BigDecimal price,
                                       boolean canAccept, PaymentProvider.Instructions pending) {
    }

    /** Cobrança de assinatura na lista do admin. */
    public record AdminPayment(Long id, Long courierId, String courierName, BigDecimal amount, String reference, String status,
                               String method, LocalDateTime createdAt, LocalDateTime confirmedAt) {
    }

    public record GrantRequest(@Min(1) @Max(366) int days) {
    }
}
