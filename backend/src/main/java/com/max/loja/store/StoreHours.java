package com.max.loja.store;

import java.time.DayOfWeek;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.List;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.max.loja.shared.BusinessException;
import jakarta.validation.constraints.Pattern;

/** Horário de funcionamento: 7 dias (segunda a domingo); dia sem horário = fechado. */
public final class StoreHours {

    private static final String TIME = "^$|^([01]\\d|2[0-3]):[0-5]\\d$";

    /** Um dia: abre e fecha no formato HH:mm (vazios = fechado). */
    public record Day(@Pattern(regexp = TIME) String open, @Pattern(regexp = TIME) String close) {

        boolean closed() {
            return open == null || close == null || open.isBlank() || close.isBlank();
        }
    }

    /** Situação agora, para a vitrine: "Aberta agora · fecha às 18:00" / "Fechada · abre amanhã às 09:00". */
    public record Status(boolean open, String label) {
    }

    private static final String[] NAMES = {"segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"};

    private StoreHours() {
    }

    static List<Day> parse(String json, ObjectMapper mapper) {
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            return mapper.readValue(json, new TypeReference<List<Day>>() { });
        } catch (JsonProcessingException e) {
            return null;
        }
    }

    static String write(List<Day> days, ObjectMapper mapper) {
        if (days == null) {
            return null;
        }
        if (days.size() != 7) {
            throw new BusinessException("Informe o horário dos 7 dias da semana");
        }
        for (Day d : days) {
            if (!d.closed() && !LocalTime.parse(d.close()).isAfter(LocalTime.parse(d.open()))) {
                throw new BusinessException("O horário de fechar precisa ser depois do de abrir");
            }
        }
        try {
            return mapper.writeValueAsString(days);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    static Status status(List<Day> days, LocalDateTime now) {
        if (days == null || days.size() != 7) {
            return null;
        }
        int today = now.getDayOfWeek().getValue() - 1;
        Day d = days.get(today);
        LocalTime time = now.toLocalTime();
        if (!d.closed()) {
            LocalTime open = LocalTime.parse(d.open());
            LocalTime close = LocalTime.parse(d.close());
            if (!time.isBefore(open) && time.isBefore(close)) {
                return new Status(true, "Aberta agora · fecha às " + d.close());
            }
            if (time.isBefore(open)) {
                return new Status(false, "Fechada · abre hoje às " + d.open());
            }
        }
        for (int i = 1; i <= 7; i++) {
            Day next = days.get((today + i) % 7);
            if (!next.closed()) {
                String when = i == 1 ? "amanhã" : NAMES[(today + i) % 7];
                return new Status(false, "Fechada · abre " + when + " às " + next.open());
            }
        }
        return new Status(false, "Fechada");
    }

    /** Linhas para mostrar ("Seg: 09:00–18:00", "Dom: fechado"). */
    static List<String> lines(List<Day> days) {
        List<String> out = new ArrayList<>();
        if (days == null) {
            return out;
        }
        for (int i = 0; i < days.size() && i < 7; i++) {
            Day d = days.get(i);
            String name = DayOfWeek.of(i + 1).getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.forLanguageTag("pt-BR"));
            out.add(Character.toUpperCase(name.charAt(0)) + name.substring(1).replace(".", "") + ": "
                    + (d.closed() ? "fechado" : d.open() + "–" + d.close()));
        }
        return out;
    }
}
