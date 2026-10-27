package com.max.loja.delivery;

import java.time.LocalDateTime;
import java.util.Optional;

import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CourierPaymentRepository extends JpaRepository<CourierPayment, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from CourierPayment p where p.id = :id")
    Optional<CourierPayment> lock(@Param("id") Long id);

    /** Cobrança em aberto recente do entregador (reaproveitada, para ele não gerar uma por toque). */
    Optional<CourierPayment> findFirstByCourierIdAndStatusAndCreatedAtAfterOrderByIdDesc(Long courierId, String status,
                                                                                         LocalDateTime after);

    Page<CourierPayment> findByStatusOrderByIdDesc(String status, Pageable page);
}
