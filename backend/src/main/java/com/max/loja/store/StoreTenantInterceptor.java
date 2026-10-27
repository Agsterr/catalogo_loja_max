package com.max.loja.store;

import java.util.Map;

import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.TenantContext;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.HandlerMapping;

/**
 * Nas rotas do cliente ({@code /api/public/stores/{slug}/**} e {@code /api/stores/{slug}/**}) a loja vem do
 * endereço na URL. Loja bloqueada, sem mensalidade em dia ou inexistente responde 404.
 */
@Component
class StoreTenantInterceptor implements HandlerInterceptor {

    private final StoreRepository stores;
    private final StoreBilling billing;

    StoreTenantInterceptor(StoreRepository stores, StoreBilling billing) {
        this.stores = stores;
        this.billing = billing;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        @SuppressWarnings("unchecked")
        var vars = (Map<String, String>) request.getAttribute(HandlerMapping.URI_TEMPLATE_VARIABLES_ATTRIBUTE);
        String slug = vars != null ? vars.get("slug") : null;
        if (slug != null) {
            Long storeId = stores.findBySlug(slug).filter(s -> !s.isBlocked())
                    .filter(billing::visible) // mensalidade vencida além da tolerância: fica oculta até renovar
                    .orElseThrow(() -> new NotFoundException("Loja não encontrada")).getId();
            TenantContext.set(storeId);
        }
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) {
        TenantContext.clear();
    }
}
