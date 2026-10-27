package com.max.loja.promotion;

import java.util.List;

import com.max.loja.promotion.PromotionService.PromotionRequest;
import com.max.loja.promotion.PromotionService.PromotionResponse;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PromotionController {

    private final PromotionService service;

    public PromotionController(PromotionService service) {
        this.service = service;
    }

    @GetMapping("/api/public/stores/{slug}/promotions")
    public List<PromotionResponse> running(@PathVariable String slug) {
        return service.running();
    }

    @GetMapping("/api/store/promotions")
    public List<PromotionResponse> all() {
        return service.all();
    }

    @PostMapping("/api/store/promotions")
    @ResponseStatus(HttpStatus.CREATED)
    public PromotionResponse create(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody PromotionRequest req) {
        return service.save(null, req, Long.valueOf(jwt.getSubject()));
    }

    @PutMapping("/api/store/promotions/{id}")
    public PromotionResponse update(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id,
                                    @Valid @RequestBody PromotionRequest req) {
        return service.save(id, req, Long.valueOf(jwt.getSubject()));
    }

    @DeleteMapping("/api/store/promotions/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        service.delete(id);
    }
}
