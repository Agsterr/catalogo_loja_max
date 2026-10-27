package com.max.loja.store;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
class StoreWebConfig implements WebMvcConfigurer {

    private final StoreTenantInterceptor tenantInterceptor;

    StoreWebConfig(StoreTenantInterceptor tenantInterceptor) {
        this.tenantInterceptor = tenantInterceptor;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(tenantInterceptor).addPathPatterns("/api/public/stores/{slug}", "/api/public/stores/{slug}/**",
                "/api/stores/{slug}/**");
    }
}
