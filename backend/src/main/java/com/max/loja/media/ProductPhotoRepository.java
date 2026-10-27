package com.max.loja.media;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ProductPhotoRepository extends JpaRepository<ProductPhoto, Long> {

    List<ProductPhoto> findByProductIdOrderByPositionAscIdAsc(Long productId);

    long countByProductId(Long productId);
}
