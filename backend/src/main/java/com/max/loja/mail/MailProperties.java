package com.max.loja.mail;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * @param resendApiKey {@code RESEND_API_KEY}; vazio = não envia (só registra no log)
 * @param from         remetente, em um domínio verificado no Resend ({@code MAIL_FROM})
 * @param siteUrl      endereço público do site, para os links dos e-mails
 */
@ConfigurationProperties("app.mail")
public record MailProperties(String resendApiKey, String from, String siteUrl) {

    public MailProperties {
        resendApiKey = resendApiKey == null ? "" : resendApiKey.trim();
        siteUrl = siteUrl == null ? "" : siteUrl.trim().replaceAll("/+$", "");
    }

    public boolean enabled() {
        return !resendApiKey.isEmpty();
    }
}
