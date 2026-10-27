package com.max.loja.mail;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/** Envia pela API HTTP do Resend. Sem chave configurada, só registra no log que não enviou. */
@Component
class ResendMailSender implements MailSender {

    private static final Logger log = LoggerFactory.getLogger(ResendMailSender.class);
    private static final URI ENDPOINT = URI.create("https://api.resend.com/emails");

    private final MailProperties props;
    private final ObjectMapper json;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    ResendMailSender(MailProperties props, ObjectMapper json) {
        this.props = props;
        this.json = json;
    }

    @Override
    public void send(String to, String subject, String html, String text) {
        if (!props.enabled()) {
            log.warn("E-mail NÃO enviado (RESEND_API_KEY ausente): para={} assunto={}", to, subject);
            log.debug("Conteúdo do e-mail não enviado: {}", text);
            return;
        }
        try {
            String body = json.writeValueAsString(
                    Map.of("from", props.from(), "to", new String[] {to}, "subject", subject, "html", html, "text", text));
            HttpRequest request = HttpRequest.newBuilder(ENDPOINT)
                    .timeout(Duration.ofSeconds(10))
                    .header("Authorization", "Bearer " + props.resendApiKey())
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            HttpResponse<String> res = http.send(request, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() / 100 != 2) {
                throw new MailException("Resend respondeu " + res.statusCode() + ": " + res.body());
            }
        } catch (JsonProcessingException e) {
            throw new MailException("Não foi possível montar o e-mail", e);
        } catch (IOException e) {
            throw new MailException("Falha ao falar com o Resend", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new MailException("Envio de e-mail interrompido", e);
        }
    }
}
