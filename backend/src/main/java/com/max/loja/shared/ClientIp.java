package com.max.loja.shared;

import jakarta.servlet.http.HttpServletRequest;

public final class ClientIp {

    private ClientIp() {
    }

    /**
     * IP real do visitante atrás do Cloudflare/nginx. Os headers só são confiáveis porque a API não fica
     * exposta direto: o nginx do servidor sobrescreve X-Forwarded-For e o Cloudflare manda CF-Connecting-IP.
     */
    public static String of(HttpServletRequest http) {
        String cf = http.getHeader("CF-Connecting-IP");
        if (cf != null && !cf.isBlank()) {
            return cf.trim();
        }
        String xff = http.getHeader("X-Forwarded-For");
        if (xff != null && !xff.isBlank()) {
            return xff.split(",")[0].trim();
        }
        return http.getRemoteAddr();
    }
}
