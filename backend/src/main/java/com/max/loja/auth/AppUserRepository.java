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

    List<AppUser> findByRoleInAndActiveTrueOrderByName(List<Role> roles);

    @Query("""
            select u from AppUser u where u.role = com.max.loja.auth.Role.CUSTOMER and u.active = true
            and (:q = '' or lower(u.name) like lower(concat('%', :q, '%')) or lower(u.email) like lower(concat('%', :q, '%'))
                 or u.phone like concat('%', :q, '%'))""")
    Page<AppUser> searchCustomers(@Param("q") String q, Pageable page);
}
