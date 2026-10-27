package com.max.loja.delivery;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CourierRepository extends JpaRepository<Courier, Long> {

    /** Trava só o entregador (não há disputa entre entregadores diferentes). */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from Courier c where c.userId = :id")
    Optional<Courier> lock(@Param("id") Long id);

    @Query(value = """
            select c.* from courier c join app_user u on u.id = c.user_id
            where (:status = '' or c.status = :status)
            and (:q = '%%' or lower(u.name) like :q or lower(c.city) like :q or lower(u.email) like :q)""",
            countQuery = """
            select count(*) from courier c join app_user u on u.id = c.user_id
            where (:status = '' or c.status = :status)
            and (:q = '%%' or lower(u.name) like :q or lower(c.city) like :q or lower(u.email) like :q)""",
            nativeQuery = true)
    Page<Courier> search(@Param("status") String status, @Param("q") String q, Pageable page);

    /**
     * Entregadores online e aprovados cujo raio alcança a loja, do mais perto para o mais longe. A posição de referência é
     * a última enviada pelo app (se recente) ou a base cadastrada.
     */
    @Query(value = """
            select x.user_id from (
              select c.user_id, c.radius_km,
                     coalesce(case when c.last_seen_at > :fresh then c.last_lat end, c.base_lat) as lat,
                     coalesce(case when c.last_seen_at > :fresh then c.last_lng end, c.base_lng) as lng
              from courier c where c.status = 'APPROVED' and c.online) x
            where x.lat is not null and geo_km(x.lat, x.lng, :lat, :lng) <= x.radius_km
            order by geo_km(x.lat, x.lng, :lat, :lng) limit :lim""", nativeQuery = true)
    List<Long> nearbyOnline(@Param("lat") double lat, @Param("lng") double lng, @Param("fresh") LocalDateTime fresh,
                            @Param("lim") int limit);
}
