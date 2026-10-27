package com.max.loja.delivery;

public enum CourierStatus {
    /** Cadastro feito, esperando a aprovação da plataforma. */
    PENDING,
    APPROVED,
    /** Bloqueado pela plataforma (não vê nem aceita corridas). */
    BLOCKED
}
