package com.max.loja.catalog;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ProductVariantRepository extends JpaRepository<ProductVariant, Long> {

    /** Trava as linhas (em ordem de id, sem deadlock) para dois pedidos não venderem a mesma última peça. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select v from ProductVariant v join fetch v.product where v.id in :ids order by v.id")
    List<ProductVariant> lockAll(@Param("ids") Collection<Long> ids);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select v from ProductVariant v join fetch v.product where v.id = :id")
    Optional<ProductVariant> lock(@Param("id") Long id);

    /** Tamanhos/cores ativos de produtos ativos no estoque mínimo ou abaixo. */
    @Query("""
            select v from ProductVariant v join fetch v.product p
            where v.active = true and p.active = true and v.stock <= p.minStock order by v.stock, p.name""")
    List<ProductVariant> findLowStock();
}
