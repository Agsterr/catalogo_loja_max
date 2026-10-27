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
 * endereço na URL. Loja bloqueada ou inexistente responde 404.
 */
@Component
class StoreTenantInterceptor implements HandlerInterceptor {

    private final StoreRepository stores;

    StoreTenantInterceptor(StoreRepository stores) {
        this.stores = stores;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        @SuppressWarnings("unchecked")
        var vars = (Map<String, String>) request.getAttribute(HandlerMapping.URI_TEMPLATE_VARIABLES_ATTRIBUTE);
        String slug = vars != null ? vars.get("slug") : null;
        if (slug != null) {
            Long storeId = stores.findBySlug(slug).filter(s -> !s.isBlocked())
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
