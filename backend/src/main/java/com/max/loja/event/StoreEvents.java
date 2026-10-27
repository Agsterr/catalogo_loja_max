package com.max.loja.event;

import com.max.loja.order.OrderStatus;

/**
 * Fatos da loja publicados pelos serviços ({@code ApplicationEventPublisher}). Os ouvintes rodam na mesma
 * transação do fato: o aviso do sino e a fila de push só existem se o pedido/estoque foi gravado de verdade.
 */
public final class StoreEvents {

    private StoreEvents() {
    }

    /** Cliente fez um pedido. */
    public record OrderPlaced(Long orderId) {
    }

    /**
     * Pedido mudou de status. {@code byCustomer} = o próprio cliente (ex.: cancelou pelo app);
     * senão foi a equipe ({@code actorId}).
     */
    public record OrderStatusChanged(Long orderId, OrderStatus from, OrderStatus to, boolean byCustomer, Long actorId) {
    }

    /** Pagamento do pedido confirmado pela equipe. */
    public record OrderPaid(Long orderId) {
    }

    /** Um tamanho/cor chegou no estoque mínimo (ou acabou) depois de uma saída. */
    public record StockLow(Long productId, Long variantId, String productName, String variant, int stock) {
    }

    /** Tamanho/cor que tinha acabado voltou ao estoque. */
    public record BackInStock(Long productId, String productName, String variant) {
    }

    /** Promoção começou (aviso aos clientes que aceitam promoções). */
    public record PromotionStarted(Long promotionId) {
    }

    /** Um entregador aceitou a corrida do pedido. */
    public record DeliveryAccepted(Long jobId) {
    }

    /** O entregador desistiu antes de coletar: a corrida voltou ao mural. */
    public record DeliveryReopened(Long jobId) {
    }

    /** Ninguém aceitou a corrida a tempo. */
    public record DeliveryExpired(Long jobId) {
    }

    /** Entregador concluiu a entrega. */
    public record DeliveryDone(Long jobId) {
    }
}
