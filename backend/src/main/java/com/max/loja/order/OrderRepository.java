package com.max.loja.order;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import jakarta.persistence.LockModeType;

public interface OrderRepository extends JpaRepository<CustomerOrder, Long>, JpaSpecificationExecutor<CustomerOrder> {

    Page<CustomerOrder> findByCustomerId(Long customerId, Pageable page);

    Optional<CustomerOrder> findByIdAndCustomerId(Long id, Long customerId);

    boolean existsByCode(String code);

    long countByCustomerIdAndStatus(Long customerId, OrderStatus status);

    long countByCustomerIdAndCreatedAtAfter(Long customerId, LocalDateTime since);

    /** Trava o pedido: equipe e cliente mexendo ao mesmo tempo não devolvem o estoque duas vezes. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select o from CustomerOrder o where o.id = :id")
    Optional<CustomerOrder> lock(@Param("id") Long id);

    @Query("select o from CustomerOrder o where o.createdAt >= :from and o.createdAt < :to and o.status <> com.max.loja.order.OrderStatus.CANCELED")
    List<CustomerOrder> findValidBetween(@Param("from") LocalDateTime from, @Param("to") LocalDateTime to);

    long countByStatus(OrderStatus status);
}
