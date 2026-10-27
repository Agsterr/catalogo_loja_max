package com.max.loja.delivery;

import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import lombok.Getter;
import lombok.Setter;

/** Perfil do entregador (a conta é um {@code AppUser} com papel COURIER). Não é por loja. */
@Getter
@Setter
@Entity
public class Courier {

    @Id
    private Long userId;

    @Column(nullable = false)
    private String phone;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Vehicle vehicle;

    private String plate;

    @Column(nullable = false)
    private String city;

    @Column(nullable = false)
    private String state;

    /** Ponto de referência da região onde atua (casa/base) e raio em km. */
    private Double baseLat;
    private Double baseLng;
    private int radiusKm = 10;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private CourierStatus status = CourierStatus.PENDING;

    private String statusReason;
    private boolean online;

    /** Última posição enviada pelo app (vale por {@code app.delivery.fresh-position}). */
    private Double lastLat;
    private Double lastLng;
    private LocalDateTime lastSeenAt;

    private int deliveredCount;
    private int canceledCount;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    private LocalDateTime approvedAt;

    public boolean approved() {
        return status == CourierStatus.APPROVED;
    }
}
