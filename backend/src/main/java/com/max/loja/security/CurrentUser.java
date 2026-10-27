package com.max.loja.security;

import com.max.loja.auth.Role;
import org.springframework.security.oauth2.jwt.Jwt;

/** Quem está chamando, lido do JWT já validado. */
public record CurrentUser(Long id, Role role) {

    public static CurrentUser of(Jwt jwt) {
        return new CurrentUser(Long.valueOf(jwt.getSubject()), Role.valueOf(jwt.getClaimAsString(JwtService.ROLE_CLAIM)));
    }

    public boolean isTeam() {
        return role.isTeam();
    }
}
