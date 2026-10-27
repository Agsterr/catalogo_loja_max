package com.max.loja.store;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import com.max.loja.delivery.PaymentProvider;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Mensalidade da loja: o dono vê o plano e paga; o admin da plataforma confirma e dá cortesia. */
@RestController
public class StoreBillingController {

    public record GrantRequest(@Min(1) @Max(366) int days) {
    }

    public record AdminStorePayment(Long id, Long storeId, String storeName, BigDecimal amount, String reference, String status,
                                    LocalDateTime createdAt) {
    }

    private final StoreBilling billing;
    private final StorePaymentRepository payments;
    private final StoreRepository stores;
    private final StoreService storeService;

    public StoreBillingController(StoreBilling billing, StorePaymentRepository payments, StoreRepository stores, StoreService storeService) {
        this.billing = billing;
        this.payments = payments;
        this.stores = stores;
        this.storeService = storeService;
    }

    /** Situação da mensalidade da loja do dono (a loja vem do token). */
    @GetMapping("/api/store/plan")
    public StoreBilling.Plan plan() {
        return billing.plan(storeService.current().getId());
    }

    @PostMapping("/api/store/plan/checkout")
    public PaymentProvider.Instructions checkout() {
        return billing.checkout(storeService.current().getId());
    }

    // --- admin da plataforma ---

    @GetMapping("/api/platform/store-payments")
    public PageResponse<AdminStorePayment> list(@RequestParam(required = false) Integer page, @RequestParam(required = false) Integer size) {
        var result = payments.findByStatusOrderByIdDesc(StorePayment.PENDING, PageResponse.request(page, size, Sort.unsorted()));
        var names = new java.util.HashMap<Long, String>();
        stores.findAllById(result.getContent().stream().map(StorePayment::getStoreId).toList()).forEach(s -> names.put(s.getId(), s.getName()));
        return PageResponse.of(result, p -> new AdminStorePayment(p.getId(), p.getStoreId(), names.get(p.getStoreId()), p.getAmount(),
                p.getReference(), p.getStatus(), p.getCreatedAt()));
    }

    @PostMapping("/api/platform/store-payments/{id}/confirm")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void confirm(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id) {
        billing.confirm(id, Long.valueOf(jwt.getSubject()));
    }

    @PostMapping("/api/platform/stores/{id}/grant")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void grant(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id, @Valid @RequestBody GrantRequest req) {
        stores.findById(id).orElseThrow(() -> new NotFoundException("Loja não encontrada"));
        billing.grant(id, req.days(), Long.valueOf(jwt.getSubject()));
    }
}
