package com.max.loja.store;

import java.time.LocalDateTime;
import java.util.Optional;

import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StorePaymentRepository extends JpaRepository<StorePayment, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from StorePayment p where p.id = :id")
    Optional<StorePayment> lock(@Param("id") Long id);

    Optional<StorePayment> findFirstByStoreIdAndStatusAndCreatedAtAfterOrderByIdDesc(Long storeId, String status, LocalDateTime after);

    Page<StorePayment> findByStatusOrderByIdDesc(String status, Pageable page);

    boolean existsByStoreIdAndStatusAndAmountGreaterThan(Long storeId, String status, java.math.BigDecimal amount);
}
