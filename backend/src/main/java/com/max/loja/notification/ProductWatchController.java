package com.max.loja.notification;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProductWatchController {

    private final ProductWatchService service;

    public ProductWatchController(ProductWatchService service) {
        this.service = service;
    }

    @GetMapping("/api/me/watches")
    public List<Long> mine(@AuthenticationPrincipal Jwt jwt) {
        return service.mine(Long.valueOf(jwt.getSubject()));
    }

    @PostMapping("/api/me/watches/{productId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void watch(@AuthenticationPrincipal Jwt jwt, @PathVariable Long productId) {
        service.watch(Long.valueOf(jwt.getSubject()), productId);
    }

    @DeleteMapping("/api/me/watches/{productId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void unwatch(@AuthenticationPrincipal Jwt jwt, @PathVariable Long productId) {
        service.unwatch(Long.valueOf(jwt.getSubject()), productId);
    }
}
