package com.max.loja.order;

import java.util.Set;

/** Ciclo do pedido. Retirada: PENDING → CONFIRMED → READY → DELIVERED. Entrega: ... CONFIRMED → SHIPPED → DELIVERED. */
public enum OrderStatus {
    PENDING("Aguardando confirmação"),
    CONFIRMED("Confirmado"),
    READY("Pronto para retirar"),
    SHIPPED("Saiu para entrega"),
    DELIVERED("Entregue"),
    CANCELED("Cancelado");

    private final String label;

    OrderStatus(String label) {
        this.label = label;
    }

    public String label() {
        return label;
    }

    public boolean finished() {
        return this == DELIVERED || this == CANCELED;
    }

    /** Próximos status possíveis para a equipe. */
    public Set<OrderStatus> next(DeliveryMethod method) {
        return switch (this) {
            case PENDING -> Set.of(CONFIRMED, CANCELED);
            case CONFIRMED -> Set.of(method == DeliveryMethod.PICKUP ? READY : SHIPPED, CANCELED);
            case READY, SHIPPED -> Set.of(DELIVERED, CANCELED);
            case DELIVERED, CANCELED -> Set.of();
        };
    }

    /** O cliente só cancela pelo app antes da loja separar o pedido. */
    public boolean customerCanCancel() {
        return this == PENDING || this == CONFIRMED;
    }
}
