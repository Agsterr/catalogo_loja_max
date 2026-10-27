package com.max.loja.push;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PushDeviceRepository extends JpaRepository<PushDevice, Long> {

    Optional<PushDevice> findByToken(String token);

    /** Celulares da equipe desta loja. */
    @Query("""
            select d from PushDevice d, com.max.loja.auth.AppUser u where u.id = d.userId and d.app = 'STAFF'
            and u.storeId = :storeId""")
    List<PushDevice> findTeamOf(@Param("storeId") Long storeId);

    List<PushDevice> findByUserIdIn(Collection<Long> userIds);

    /** Celulares de clientes que seguem a loja (abriram a vitrine dela) e aceitam promoções. */
    @Query(value = """
            select d.* from push_device d join push_device_store f on f.device_id = d.id
            where f.tenant_id = :storeId and d.app = 'CLIENT' and d.promo_notifications""", nativeQuery = true)
    List<PushDevice> findPromotionTargets(@Param("storeId") Long storeId);

    @Modifying
    @Query("delete from PushDevice d where d.userId = :userId")
    void deleteByUserId(Long userId);
}
