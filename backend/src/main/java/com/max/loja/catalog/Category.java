package com.max.loja.catalog;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import com.max.loja.shared.TenantEntity;
import lombok.Getter;
import lombok.Setter;

/** Categoria dentro de um departamento (ex.: Roupas › Vestidos, Calçados › Tênis, Bijuterias › Brincos). */
@Getter
@Setter
@Entity
public class Category extends TenantEntity {

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Department department;

    @Column(nullable = false)
    private String name;

    private int position;

    private boolean active = true;
}
