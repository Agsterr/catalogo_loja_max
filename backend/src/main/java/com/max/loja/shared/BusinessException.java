package com.max.loja.shared;

/** Regra de negócio violada (ex.: sem estoque). Vira HTTP 422. */
public class BusinessException extends RuntimeException {

    public BusinessException(String message) {
        super(message);
    }
}
