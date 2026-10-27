package com.max.loja.catalog;

import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import com.max.loja.shared.TenantEntity;
import lombok.Getter;
import lombok.Setter;

/** Histórico do estoque de cada tamanho/cor. */
@Getter
@Setter
@Entity
public class StockMovement extends TenantEntity {

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
