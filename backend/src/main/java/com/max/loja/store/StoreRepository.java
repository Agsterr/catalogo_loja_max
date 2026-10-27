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

    /** Busca por nome (sem acento) ou endereço; {@code q} já vem de {@code Search.like}. Bloqueadas só para o admin. */
    @Query(value = """
            select * from store s where (:includeBlocked = true or s.blocked = false)
            and (:q = '%%' or unaccent(lower(s.name)) like :q or s.slug like :q)""",
            countQuery = """
            select count(*) from store s where (:includeBlocked = true or s.blocked = false)
            and (:q = '%%' or unaccent(lower(s.name)) like :q or s.slug like :q)""", nativeQuery = true)
    Page<Store> search(@Param("q") String q, @Param("includeBlocked") boolean includeBlocked, Pageable page);
}
