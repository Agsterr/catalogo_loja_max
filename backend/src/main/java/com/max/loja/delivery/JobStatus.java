package com.max.loja.delivery;

/** Ciclo da corrida: OPEN (no mural) → ACCEPTED → PICKED_UP → DELIVERED; ou EXPIRED / CANCELED. */
public enum JobStatus {
    OPEN("Procurando entregador"),
    ACCEPTED("Entregador a caminho da loja"),
    PICKED_UP("Entregador a caminho do cliente"),
    DELIVERED("Entregue"),
    EXPIRED("Nenhum entregador aceitou"),
    CANCELED("Cancelada");

    private final String label;

    JobStatus(String label) {
        this.label = label;
    }

    public String label() {
        return label;
    }

    public boolean active() {
        return this == ACCEPTED || this == PICKED_UP;
    }
}
