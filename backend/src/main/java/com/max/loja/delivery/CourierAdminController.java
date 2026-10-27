package com.max.loja.delivery;

import com.max.loja.delivery.CourierDtos.AdminCourier;
import com.max.loja.delivery.CourierDtos.ReasonRequest;
import com.max.loja.shared.PageResponse;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Administrador da plataforma: aprova e bloqueia entregadores (a rota inteira exige PLATFORM_ADMIN). */
@RestController
public class CourierAdminController {

    private final CourierService service;

    public CourierAdminController(CourierService service) {
        this.service = service;
    }

    @GetMapping("/api/platform/couriers")
    public PageResponse<AdminCourier> list(@RequestParam(required = false) CourierStatus status,
                                           @RequestParam(required = false) String q, @RequestParam(required = false) Integer page,
                                           @RequestParam(required = false) Integer size) {
        return service.adminList(status, q, page, size);
    }

    @PostMapping("/api/platform/couriers/{id}/approve")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void approve(@PathVariable Long id) {
        service.setStatus(id, CourierStatus.APPROVED, null);
    }

    @PostMapping("/api/platform/couriers/{id}/block")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void block(@PathVariable Long id, @Valid @RequestBody(required = false) ReasonRequest req) {
        service.setStatus(id, CourierStatus.BLOCKED, req == null ? null : req.reason());
    }
}
