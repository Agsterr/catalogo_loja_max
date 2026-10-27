package com.max.loja.promotion;

import java.time.LocalDateTime;

import com.max.loja.catalog.Category;
import com.max.loja.catalog.Department;
import com.max.loja.catalog.Product;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.ManyToOne;
import lombok.Getter;
import lombok.Setter;

/**
 * Desconto por período. Vale para um produto, ou uma categoria, ou um departamento; sem nenhum dos três,
 * para a loja inteira. Com {@link #notifyCustomers} os clientes recebem push quando ela começa.
 */
@Getter
@Setter
@Entity
public class Promotion {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String title;

    private String description;

    private int discountPercent;

    @Enumerated(EnumType.STRING)
    private Department department;

    @ManyToOne(fetch = FetchType.LAZY)
    private Category category;

    @ManyToOne(fetch = FetchType.LAZY)
    private Product product;

    @Column(nullable = false)
    private LocalDateTime startsAt;

    @Column(nullable = false)
    private LocalDateTime endsAt;

    private boolean active = true;

    private boolean notifyCustomers = true;

    /** Quando o aviso aos clientes saiu (nulo = ainda não). */
    private LocalDateTime notifiedAt;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    public boolean runningAt(LocalDateTime now) {
        return active && !startsAt.isAfter(now) && endsAt.isAfter(now);
    }

    /** Vale para este produto? */
    public boolean appliesTo(Product p) {
        if (product != null) {
            return product.getId().equals(p.getId());
        }
        if (category != null) {
            return p.getCategory() != null && category.getId().equals(p.getCategory().getId());
        }
        return department == null || department == p.getDepartment();
    }

    public String scopeLabel() {
        if (product != null) {
            return product.getName();
        }
        if (category != null) {
            return category.getName();
        }
        return department != null ? department.label() : "Loja inteira";
    }
}
