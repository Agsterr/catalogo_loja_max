package com.max.loja.delivery;

import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import lombok.Getter;
import lombok.Setter;

/** Avaliação do entregador pelo cliente (1 a 5 estrelas), uma por pedido entregue. */
@Getter
@Setter
@Entity
public class CourierRating {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private Long orderId;

    @Column(nullable = false)
    private Long courierId;

    @Column(nullable = false)
    private Long storeId;

    @Column(nullable = false)
    private Long customerId;

    @Column(nullable = false)
    private int stars;

    private String comment;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
