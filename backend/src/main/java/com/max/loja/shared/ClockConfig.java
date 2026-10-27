package com.max.loja.shared;

import java.time.Clock;
import java.time.ZoneId;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class ClockConfig {

    /** Relógio no fuso da loja: {@code LocalDateTime.now(clock)} é a hora local (testes podem trocar o bean). */
    @Bean
    Clock clock(@Value("${app.timezone}") String zone) {
        return Clock.system(ZoneId.of(zone));
    }
}
