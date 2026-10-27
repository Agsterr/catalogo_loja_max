package com.max.loja.catalog;

/** Seções da loja. */
public enum Department {
    ROUPAS("Roupas"),
    CALCADOS("Calçados"),
    BIJUTERIAS("Bijuterias");

    private final String label;

    Department(String label) {
        this.label = label;
    }

    public String label() {
        return label;
    }
}
