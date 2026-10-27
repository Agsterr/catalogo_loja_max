package com.max.loja.delivery;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface DeliveryJobRepository extends JpaRepository<DeliveryJob, Long> {

    Optional<DeliveryJob> findByOrderId(Long orderId);

    List<DeliveryJob> findByCourierIdAndStatusInOrderByAcceptedAtDesc(Long courierId, Collection<JobStatus> statuses);

    Page<DeliveryJob> findByCourierIdAndStatusInOrderByIdDesc(Long courierId, Collection<JobStatus> statuses, Pageable page);

    @Query("select count(j) from DeliveryJob j where j.courierId = :courierId and j.status in (com.max.loja.delivery.JobStatus.ACCEPTED, com.max.loja.delivery.JobStatus.PICKED_UP)")
    long countActive(@Param("courierId") Long courierId);

    /**
     * Mural: corridas abertas dentro do raio do ponto (pré-filtro por caixa de coordenadas, que usa o índice parcial) do
     * mais perto para o mais longe.
     */
    @Query(value = """
            select * from delivery_job j where j.status = 'OPEN' and j.expires_at > :now
            and j.pickup_lat between :minLat and :maxLat and j.pickup_lng between :minLng and :maxLng
            and geo_km(:lat, :lng, j.pickup_lat, j.pickup_lng) <= :radius
            order by geo_km(:lat, :lng, j.pickup_lat, j.pickup_lng), j.id""",
            countQuery = """
            select count(*) from delivery_job j where j.status = 'OPEN' and j.expires_at > :now
            and j.pickup_lat between :minLat and :maxLat and j.pickup_lng between :minLng and :maxLng
            and geo_km(:lat, :lng, j.pickup_lat, j.pickup_lng) <= :radius""", nativeQuery = true)
    Page<DeliveryJob> openNear(@Param("lat") double lat, @Param("lng") double lng, @Param("radius") double radiusKm,
                               @Param("minLat") double minLat, @Param("maxLat") double maxLat,
                               @Param("minLng") double minLng, @Param("maxLng") double maxLng,
                               @Param("now") LocalDateTime now, Pageable page);

    /** Aceite atômico: só um entregador consegue (as outras tentativas voltam 0 linhas). */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query(value = """
            update delivery_job set status = 'ACCEPTED', courier_id = :courier, accepted_at = :now
            where id = :id and status = 'OPEN' and expires_at > :now""", nativeQuery = true)
    int accept(@Param("id") Long id, @Param("courier") Long courierId, @Param("now") LocalDateTime now);

    /** Ganhos: soma e quantidade das entregas concluídas desde {@code since}. */
    @Query(value = """
            select coalesce(sum(courier_fee), 0) as total, count(*) as count from delivery_job
            where courier_id = :courier and status = 'DELIVERED' and delivered_at >= :since""", nativeQuery = true)
    Earnings earnings(@Param("courier") Long courierId, @Param("since") LocalDateTime since);

    interface Earnings {
        java.math.BigDecimal getTotal();

        long getCount();
    }
}
