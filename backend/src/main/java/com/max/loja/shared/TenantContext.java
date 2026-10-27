package com.max.loja.shared;

/**
 * Guarda a loja (tenant) da requisição atual. Preenchido pelo {@code TenantFilter}
 * (equipe logada) ou pelo {@code StoreTenantInterceptor} (rotas /api/public/stores/{slug} e /api/stores/{slug}).
 */
public final class TenantContext {

    /** Valor usado quando não há tenant: não corresponde a nenhuma loja, então nada vaza. */
    public static final Long NONE = 0L;

    private static final ThreadLocal<Long> CURRENT = new ThreadLocal<>();

    private TenantContext() {
    }

    public static void set(Long tenantId) {
        CURRENT.set(tenantId);
    }

    public static Long get() {
        Long tenantId = CURRENT.get();
        return tenantId != null ? tenantId : NONE;
    }

    public static void clear() {
        CURRENT.remove();
    }
}
