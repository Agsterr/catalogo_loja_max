package com.max.loja.delivery;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Equipe da loja: chama de novo um entregador quando ninguém aceitou (a loja vem do token). */
@RestController
public class StoreDeliveryController {

    private final DispatchService dispatch;

    public StoreDeliveryController(DispatchService dispatch) {
        this.dispatch = dispatch;
    }

    /** Chama de novo (ou aumenta o bônus). {@code bonus}: valor extra, pago pela loja ao entregador na coleta (0 a 50). */
    @PostMapping("/api/store/orders/{id}/courier/retry")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void retry(@PathVariable Long id, @Valid @RequestBody(required = false) BonusRequest req) {
        dispatch.retry(id, req == null ? null : req.bonus());
    }

    public record BonusRequest(@jakarta.validation.constraints.DecimalMin("0") @jakarta.validation.constraints.DecimalMax("50")
                               java.math.BigDecimal bonus) {
    }
}
