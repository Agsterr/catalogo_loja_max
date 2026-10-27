package com.max.loja.auth;

import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AppUserRepository extends JpaRepository<AppUser, Long> {

    Optional<AppUser> findByEmailIgnoreCase(String email);

    boolean existsByEmailIgnoreCase(String email);

    List<AppUser> findByStoreIdAndActiveTrueOrderByName(Long storeId);

    /** Busca do admin da plataforma (todas as contas). */
    @Query("""
            select u from AppUser u where u.active = true
            and (:q = '' or lower(u.name) like lower(concat('%', :q, '%')) or lower(u.email) like lower(concat('%', :q, '%')))""")
    Page<AppUser> search(@Param("q") String q, Pageable page);
}
