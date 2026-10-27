package com.max.loja.notification;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface NotificationRepository extends JpaRepository<Notification, Long> {

    /** {@code team}: avisos da equipe toda mais os só deste usuário; cliente: só os dele. */
    @Query("""
            select n from Notification n where n.userId = :userId or (:team = true and n.userId is null)
            order by n.createdAt desc, n.id desc""")
    List<Notification> findVisible(@Param("userId") Long userId, @Param("team") boolean team, Pageable page);

    @Query("""
            select count(n) from Notification n where n.readAt is null
            and (n.userId = :userId or (:team = true and n.userId is null))""")
    long countUnread(@Param("userId") Long userId, @Param("team") boolean team);

    boolean existsByDedupKey(String dedupKey);

    @Modifying
    @Query("""
            update Notification n set n.readAt = :now where n.readAt is null
            and (n.userId = :userId or (:team = true and n.userId is null))""")
    int markAllRead(@Param("userId") Long userId, @Param("team") boolean team, @Param("now") LocalDateTime now);

    @Modifying
    @Query("""
            update Notification n set n.readAt = :now where n.id = :id and n.readAt is null
            and (n.userId = :userId or (:team = true and n.userId is null))""")
    int markRead(@Param("id") Long id, @Param("userId") Long userId, @Param("team") boolean team,
                 @Param("now") LocalDateTime now);
}
