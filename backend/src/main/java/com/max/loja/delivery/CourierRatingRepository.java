package com.max.loja.delivery;

import org.springframework.data.jpa.repository.JpaRepository;

public interface CourierRatingRepository extends JpaRepository<CourierRating, Long> {

    boolean existsByOrderId(Long orderId);
}
