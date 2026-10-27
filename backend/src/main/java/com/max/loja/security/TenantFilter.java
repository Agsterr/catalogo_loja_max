package com.max.loja.security;

import java.io.IOException;

import com.max.loja.shared.TenantContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.filter.OncePerRequestFilter;

/** Define a loja (tenant) da equipe a partir do claim {@code tenant} do JWT. */
class TenantFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (SecurityContextHolder.getContext().getAuthentication() instanceof JwtAuthenticationToken token) {
            // Sem claim (cliente, admin da plataforma): fica em TenantContext.NONE ou no slug da URL
            Number tenant = token.getToken().getClaim(JwtService.TENANT_CLAIM);
            if (tenant != null) {
                TenantContext.set(tenant.longValue());
            }
        }
        try {
            chain.doFilter(request, response);
        } finally {
            TenantContext.clear();
        }
    }
}
