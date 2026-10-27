package com.max.loja.order;

import java.math.BigDecimal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import com.max.loja.shared.TenantEntity;
import lombok.Getter;
import lombok.Setter;

/** Item do pedido com nome, tamanho e preço copiados na hora da compra (mudar o produto depois não altera o pedido). */
@Getter
@Setter
@Entity
public class OrderItem extends TenantEntity {

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    private CustomerOrder order;

    @Column(nullable = false)
    private Long productId;

    @Column(nullable = false)
    private Long variantId;

    @Column(nullable = false)
    private String productName;

    @Column(nullable = false)
    private String size;

    @Column(nullable = false)
    private String color = "";

    @Column(nullable = false)
    private BigDecimal unitPrice;

    private int quantity;

    @Column(nullable = false)
    private BigDecimal total;
}
