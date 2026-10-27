package com.max.loja.catalog;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import com.max.loja.shared.TenantEntity;
import lombok.Getter;
import lombok.Setter;

/** Tamanho + cor de um produto, com estoque próprio. Bijuteria sem tamanho usa "Único". */
@Getter
@Setter
@Entity
public class ProductVariant extends TenantEntity {

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    private Product product;

    @Column(nullable = false)
    private String size;

    @Column(nullable = false)
    private String color = "";

    private String sku;

    private int stock;

    private boolean active = true;

    public String label() {
        return color.isBlank() ? size : size + " · " + color;
    }
}
