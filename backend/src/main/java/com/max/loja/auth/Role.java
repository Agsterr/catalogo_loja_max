package com.max.loja.auth;

public enum Role {
    /** Dono da loja: tudo, inclusive relatórios, equipe, promoções e dados da loja. */
    OWNER,
    /** Funcionário: pedidos, produtos, fotos e estoque. */
    STAFF,
    /** Cliente do app: vitrine, pedidos dele e avisos dele. */
    CUSTOMER;

    public boolean isTeam() {
        return this == OWNER || this == STAFF;
    }
}
