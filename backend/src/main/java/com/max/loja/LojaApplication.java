package com.max.loja;

import java.util.TimeZone;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@ConfigurationPropertiesScan
@EnableScheduling
public class LojaApplication {

    public static void main(String[] args) {
        // Datas dos pedidos e promoções ficam na hora local da loja
        String zone = System.getenv().getOrDefault("APP_TIMEZONE", "America/Sao_Paulo");
        TimeZone.setDefault(TimeZone.getTimeZone(zone));
        SpringApplication.run(LojaApplication.class, args);
    }
}
