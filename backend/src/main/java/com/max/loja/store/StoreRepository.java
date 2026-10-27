package com.max.loja.store;

import java.util.Optional;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StoreRepository extends JpaRepository<Store, Long> {

    Optional<Store> findBySlug(String slug);

    boolean existsBySlug(String slug);

    /** Busca por nome ou endereço; {@code includeBlocked} só para o admin da plataforma. */
    @Query("""
            select s from Store s where (:includeBlocked = true or s.blocked = false)
            and (:q = '' or lower(s.name) like lower(concat('%', :q, '%')) or s.slug like lower(concat('%', :q, '%')))""")
    Page<Store> search(@Param("q") String q, @Param("includeBlocked") boolean includeBlocked, Pageable page);
}
