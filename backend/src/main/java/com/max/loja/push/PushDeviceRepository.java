package com.max.loja.push;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

public interface PushDeviceRepository extends JpaRepository<PushDevice, Long> {

    Optional<PushDevice> findByToken(String token);

    List<PushDevice> findByApp(String app);

    List<PushDevice> findByUserIdIn(Collection<Long> userIds);

    /** Celulares de clientes que aceitam promoções. */
    List<PushDevice> findByAppAndPromoNotificationsTrue(String app);

    @Modifying
    @Query("delete from PushDevice d where d.userId = :userId")
    void deleteByUserId(Long userId);
}
