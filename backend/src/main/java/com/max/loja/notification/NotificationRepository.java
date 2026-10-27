package com.max.loja.notification;

import java.time.LocalDateTime;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface NotificationRepository extends JpaRepository<Notification, Long> {

    /** Equipe: avisos da loja dela (gerais e os só dela). Cliente ({@code storeId} nulo): os dele, de todas as lojas. */
    String VISIBLE = """
            (:storeId is null and n.userId = :userId)
            or (n.storeId = :storeId and (n.userId is null or n.userId = :userId))""";

    @Query("select n from Notification n where " + VISIBLE + " order by n.createdAt desc, n.id desc")
    Page<Notification> findVisible(@Param("userId") Long userId, @Param("storeId") Long storeId, Pageable page);

    @Query("select count(n) from Notification n where n.readAt is null and (" + VISIBLE + ")")
    long countUnread(@Param("userId") Long userId, @Param("storeId") Long storeId);

    boolean existsByDedupKey(String dedupKey);

    @Modifying
    @Query("update Notification n set n.readAt = :now where n.readAt is null and (" + VISIBLE + ")")
    int markAllRead(@Param("userId") Long userId, @Param("storeId") Long storeId, @Param("now") LocalDateTime now);

    @Modifying
    @Query("update Notification n set n.readAt = :now where n.id = :id and n.readAt is null and (" + VISIBLE + ")")
    int markRead(@Param("id") Long id, @Param("userId") Long userId, @Param("storeId") Long storeId,
                 @Param("now") LocalDateTime now);
}
