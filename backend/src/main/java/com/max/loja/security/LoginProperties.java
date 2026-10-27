package com.max.loja.security;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * @param maxLoginFailures tentativas erradas seguidas antes de travar o login daquele e-mail
 * @param loginLock        quanto tempo fica travado
 */
@ConfigurationProperties("app.security")
public record LoginProperties(int maxLoginFailures, Duration loginLock) {

    public LoginProperties {
        if (maxLoginFailures < 1) {
            maxLoginFailures = 5;
        }
        if (loginLock == null) {
            loginLock = Duration.ofMinutes(15);
        }
    }
}
