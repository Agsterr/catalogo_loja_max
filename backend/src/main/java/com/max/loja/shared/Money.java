package com.max.loja.shared;

import java.math.BigDecimal;
import java.math.RoundingMode;

public final class Money {

    private Money() {
    }

    public static BigDecimal round(BigDecimal v) {
        return v.setScale(2, RoundingMode.HALF_UP);
    }

    /** Valor com {@code percent}% de desconto. */
    public static BigDecimal discount(BigDecimal price, int percent) {
        return round(price.multiply(BigDecimal.valueOf(100 - percent)).divide(BigDecimal.valueOf(100), 4, RoundingMode.HALF_UP));
    }

    public static String format(BigDecimal v) {
        return "R$ " + round(v).toPlainString().replace('.', ',');
    }
}
