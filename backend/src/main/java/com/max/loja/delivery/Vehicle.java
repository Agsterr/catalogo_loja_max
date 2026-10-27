package com.max.loja.delivery;

public enum Vehicle {
    MOTO("Moto"), BIKE("Bicicleta"), CARRO("Carro"), A_PE("A pé");

    private final String label;

    Vehicle(String label) {
        this.label = label;
    }

    public String label() {
        return label;
    }
}
