package com.max.loja.catalog;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import com.max.loja.media.ProductPhoto;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
@Entity
public class Product {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    private String description;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Department department;

    @ManyToOne(fetch = FetchType.LAZY)
    private Category category;

    private String brand;

    @Column(nullable = false)
    private BigDecimal price;

    /** Preço promocional fixo ("de R$ X por R$ Y"); nulo = sem. */
    private BigDecimal salePrice;

    /** Abaixo disso (por tamanho/cor) a equipe recebe aviso de estoque baixo. */
    private int minStock = 1;

    private boolean active = true;

    /** Aparece em destaque na vitrine. */
    private boolean featured;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(nullable = false)
    private LocalDateTime updatedAt = LocalDateTime.now();

    @OneToMany(mappedBy = "product", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("id")
    private List<ProductVariant> variants = new ArrayList<>();

    @OneToMany(mappedBy = "product")
    @OrderBy("position, id")
    private List<ProductPhoto> photos = new ArrayList<>();

    public int totalStock() {
        return variants.stream().filter(ProductVariant::isActive).mapToInt(ProductVariant::getStock).sum();
    }
}
