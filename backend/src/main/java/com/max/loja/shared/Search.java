package com.max.loja.shared;

import java.text.Normalizer;
import java.util.Locale;

import jakarta.persistence.criteria.CriteriaBuilder;
import jakarta.persistence.criteria.Expression;

/** Busca sem acento e sem diferença de maiúsculas: "calca" acha "Calça" (extensão unaccent do PostgreSQL). */
public final class Search {

    private Search() {
    }

    /** Termo para LIKE: sem acento, minúsculo, sem curingas digitados, entre %. */
    public static String like(String q) {
        String plain = Normalizer.normalize(q.trim(), Normalizer.Form.NFD).replaceAll("\\p{M}", "");
        return "%" + plain.toLowerCase(Locale.ROOT).replace("%", "").replace("_", "") + "%";
    }

    /** {@code unaccent(lower(campo))} para comparar com {@link #like}. */
    public static Expression<String> plain(CriteriaBuilder cb, Expression<String> field) {
        return cb.function("unaccent", String.class, cb.lower(field));
    }
}
