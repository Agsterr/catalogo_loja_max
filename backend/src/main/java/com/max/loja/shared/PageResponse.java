package com.max.loja.shared;

import java.util.List;
import java.util.function.Function;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;

/**
 * Resposta paginada (vitrine, pedidos). {@code page} começa em 0; {@code hasMore} diz se vale pedir a
 * próxima página (rolagem infinita no app).
 */
public record PageResponse<T>(List<T> items, int page, int size, long total, boolean hasMore) {

    public static final int DEFAULT_SIZE = 20;
    public static final int MAX_SIZE = 100;

    public static <E, T> PageResponse<T> of(Page<E> page, Function<E, T> mapper) {
        return new PageResponse<>(page.getContent().stream().map(mapper).toList(), page.getNumber(), page.getSize(),
                page.getTotalElements(), page.hasNext());
    }

    /** Página pedida, com tamanho limitado (ninguém pede a tabela inteira de uma vez). */
    public static PageRequest request(Integer page, Integer size, Sort sort) {
        int s = size == null || size < 1 ? DEFAULT_SIZE : Math.min(size, MAX_SIZE);
        return PageRequest.of(Math.max(0, page == null ? 0 : page), s, sort);
    }
}
