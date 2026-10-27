package com.max.loja.promotion;

import java.util.List;

import com.max.loja.promotion.PromotionService.PromotionRequest;
import com.max.loja.promotion.PromotionService.PromotionResponse;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
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

    @GetMapping("/api/public/promotions")
    public List<PromotionResponse> running() {
        return service.running();
    }

    @GetMapping("/api/store/promotions")
    public List<PromotionResponse> all() {
        return service.all();
    }

    @PostMapping("/api/store/promotions")
    @ResponseStatus(HttpStatus.CREATED)
    public PromotionResponse create(@Valid @RequestBody PromotionRequest req) {
        return service.save(null, req);
    }

    @PutMapping("/api/store/promotions/{id}")
    public PromotionResponse update(@PathVariable Long id, @Valid @RequestBody PromotionRequest req) {
        return service.save(id, req);
    }

    @DeleteMapping("/api/store/promotions/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        service.delete(id);
    }
}
