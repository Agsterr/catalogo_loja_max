package com.max.loja.promotion;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PromotionRepository extends JpaRepository<Promotion, Long> {

    @Query("""
            select p from Promotion p left join fetch p.product left join fetch p.category
            where p.active = true and p.startsAt <= :now and p.endsAt > :now order by p.discountPercent desc""")
    List<Promotion> findRunning(@Param("now") LocalDateTime now);

    /** Começaram, ainda valem e os clientes ainda não foram avisados. */
    @Query("""
            select p from Promotion p where p.active = true and p.notifyCustomers = true and p.notifiedAt is null
            and p.startsAt <= :now and p.endsAt > :now order by p.id""")
    List<Promotion> findToAnnounce(@Param("now") LocalDateTime now);

    List<Promotion> findAllByOrderByStartsAtDesc();
}
