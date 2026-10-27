package com.max.loja.store;

import com.max.loja.shared.PageResponse;
import com.max.loja.store.StoreService.StoreCard;
import com.max.loja.store.StoreService.StoreRequest;
import com.max.loja.store.StoreService.StoreResponse;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class StoreController {

    private final StoreService service;

    public StoreController(StoreService service) {
        this.service = service;
    }

    /** Busca de lojas no app do cliente (bloqueadas não aparecem). */
    @GetMapping("/api/public/stores")
    public PageResponse<StoreCard> search(@RequestParam(required = false) String q,
                                          @RequestParam(required = false) Integer page,
                                          @RequestParam(required = false) Integer size) {
        return service.search(q == null || q.length() <= 60 ? q : q.substring(0, 60), page, size);
    }

    /** Dados da loja (o tenant já veio do slug, pelo {@code StoreTenantInterceptor}). */
    @GetMapping("/api/public/stores/{slug}")
    public StoreResponse store(@PathVariable String slug) {
        return StoreResponse.from(service.current());
    }

    @GetMapping("/api/store/settings")
    public StoreResponse mine() {
        return StoreResponse.from(service.current());
    }

    @PutMapping("/api/store/settings")
    public StoreResponse update(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody StoreRequest req) {
        return service.update(req, Long.valueOf(jwt.getSubject()));
    }
}
