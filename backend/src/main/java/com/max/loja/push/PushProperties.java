package com.max.loja.push;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * @param serviceAccountJson JSON da conta de serviço do Firebase (texto ou base64); vazio = push desligado
 */
@ConfigurationProperties("app.push")
public record PushProperties(String serviceAccountJson) {

    public PushProperties {
        String v = serviceAccountJson == null ? "" : serviceAccountJson.trim();
        serviceAccountJson = v.isEmpty() || v.startsWith("{") ? v
                : new String(Base64.getMimeDecoder().decode(v), StandardCharsets.UTF_8);
    }

    public boolean configured() {
        return !serviceAccountJson.isEmpty();
    }
}
