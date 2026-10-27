package com.max.loja.media;

import java.time.LocalDateTime;

import com.max.loja.catalog.Product;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.ManyToOne;
import lombok.Getter;
import lombok.Setter;

/** Foto de um produto (no R2 ou no disco), com miniatura para a vitrine. A primeira é a capa. */
@Getter
@Setter
@Entity
public class ProductPhoto {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    private Product product;

    @Column(nullable = false)
    private String storageKey;

    @Column(nullable = false)
    private String url;

    @Column(nullable = false)
    private String thumbKey;

    @Column(nullable = false)
    private String thumbUrl;

    private int width;

    private int height;

    private int position;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
