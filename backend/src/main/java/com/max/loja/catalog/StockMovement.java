package com.max.loja.catalog;

import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import lombok.Getter;
import lombok.Setter;

/** Histórico do estoque de cada tamanho/cor. */
@Getter
@Setter
@Entity
public class StockMovement {

    public enum Type {
        /** Chegou mercadoria. */
        IN,
        /** Vendido num pedido. */
        SALE,
        /** Pedido cancelado: a peça volta. */
        RETURN,
        /** Contagem: o estoque passa a ser exatamente a quantidade informada. */
        ADJUST,
        /** Peça perdida/danificada. */
        LOSS
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long variantId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Type type;

    /** Variação (+ entrou, − saiu). */
    private int quantity;

    private int stockAfter;

    private String note;

    private Long orderId;

    private Long userId;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
