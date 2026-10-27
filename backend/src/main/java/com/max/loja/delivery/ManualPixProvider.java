package com.max.loja.delivery;

import java.math.BigDecimal;

import org.springframework.stereotype.Component;

/** Pix para a chave da plataforma com o código de referência; o admin confirma o recebimento. */
@Component
class ManualPixProvider implements PaymentProvider {

    private final BillingProperties props;

    ManualPixProvider(BillingProperties props) {
        this.props = props;
    }

    @Override
    public Instructions charge(Long courierId, String reference, BigDecimal amount) {
        boolean configured = !props.pixKey().isBlank();
        return new Instructions("PIX_MANUAL", props.pixKey(), props.pixHolder(), reference, amount, configured
                ? "Pague com Pix para a chave acima e informe o código " + reference + " na mensagem. A assinatura é liberada assim"
                        + " que o pagamento for confirmado."
                : "Pagamento ainda não configurado. Fale com o suporte da plataforma informando o código " + reference + ".");
    }
}
