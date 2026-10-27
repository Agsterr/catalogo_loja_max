package com.max.loja.catalog;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.ManyToOne;
import lombok.Getter;
import lombok.Setter;

/** Tamanho + cor de um produto, com estoque próprio. Bijuteria sem tamanho usa "Único". */
@Getter
@Setter
@Entity
public class ProductVariant {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

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
