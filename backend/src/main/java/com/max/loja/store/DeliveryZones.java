package com.max.loja.store;

import java.math.BigDecimal;
import java.util.Comparator;
import java.util.List;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.max.loja.shared.BusinessException;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotNull;

/** Entrega por distância: até X km custa Y; além da última faixa a loja não entrega. */
public final class DeliveryZones {

    public static final int MAX_ZONES = 6;

    public record Zone(@NotNull @DecimalMin("0.1") @DecimalMax("100") Double upToKm,
                       @NotNull @DecimalMin("0") @Digits(integer = 8, fraction = 2) BigDecimal fee) {
    }

    private DeliveryZones() {
    }

    static List<Zone> parse(String json, ObjectMapper mapper) {
        if (json == null || json.isBlank()) {
            return List.of();
        }
        try {
            return mapper.readValue(json, new TypeReference<List<Zone>>() { });
        } catch (JsonProcessingException e) {
            return List.of();
        }
    }

    /** Valida (sem faixas repetidas) e guarda em ordem de distância; vazio/nulo = taxa fixa. */
    static String write(List<Zone> zones, ObjectMapper mapper) {
        if (zones == null || zones.isEmpty()) {
            return null;
        }
        if (zones.size() > MAX_ZONES) {
            throw new BusinessException("No máximo " + MAX_ZONES + " faixas de entrega");
        }
        List<Zone> sorted = zones.stream().sorted(Comparator.comparing(Zone::upToKm)).toList();
        for (int i = 1; i < sorted.size(); i++) {
            if (sorted.get(i).upToKm().equals(sorted.get(i - 1).upToKm())) {
                throw new BusinessException("Duas faixas de entrega com a mesma distância");
            }
        }
        try {
            return mapper.writeValueAsString(sorted);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }
}
