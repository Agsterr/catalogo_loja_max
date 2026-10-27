package com.max.loja.auth;

public enum Role {
    /** Dono da loja: tudo da loja dele, inclusive relatórios, equipe, promoções e dados da loja. */
    OWNER,
    /** Funcionário: pedidos, produtos, fotos e estoque. */
    STAFF,
    /** Cliente do app: conta única para todas as lojas; vitrine, pedidos dele e avisos dele. */
    CUSTOMER,
    /** Entregador: pega corridas de várias lojas (app do entregador); só depois de aprovado pela plataforma. */
    COURIER,
    /** Administrador da plataforma (fora das lojas): bloqueia lojas e usuários. */
    PLATFORM_ADMIN;

    public boolean isTeam() {
        return this == OWNER || this == STAFF;
    }
}
