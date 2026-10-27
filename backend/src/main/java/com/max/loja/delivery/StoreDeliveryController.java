package com.max.loja.delivery;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Equipe da loja: chama de novo um entregador quando ninguém aceitou (a loja vem do token). */
@RestController
public class StoreDeliveryController {

    private final DispatchService dispatch;

    public StoreDeliveryController(DispatchService dispatch) {
        this.dispatch = dispatch;
    }

    @PostMapping("/api/store/orders/{id}/courier/retry")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void retry(@PathVariable Long id) {
        dispatch.retry(id);
    }
}
