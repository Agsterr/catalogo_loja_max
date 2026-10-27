package com.max.loja.push;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.max.loja.shared.GoogleAccessToken;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/** Firebase Cloud Messaging (API HTTP v1) com a conta de serviço do projeto. */
@Component
class FcmPushSender implements PushSender {

    private static final Logger log = LoggerFactory.getLogger(FcmPushSender.class);
    private static final String SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
    private static final String DEFAULT_API = "https://fcm.googleapis.com/v1/projects/";

    private final PushProperties props;
    private final ObjectMapper json;
    private final String api;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    private final GoogleAccessToken tokens;

    @Autowired
    FcmPushSender(PushProperties props, ObjectMapper json) {
        this(props, json, DEFAULT_API);
    }

    /** Endereço da API configurável só para os testes (servidor falso). */
    FcmPushSender(PushProperties props, ObjectMapper json, String api) {
        this.props = props;
        this.json = json;
        this.api = api;
        this.tokens = new GoogleAccessToken(json, props::serviceAccountJson, SCOPE, http);
    }

    @Override
    public Result send(String token, String title, String body, Map<String, String> data) {
        if (!props.configured()) {
            return Result.DISABLED;
        }
        try {
            String project = json.readTree(props.serviceAccountJson()).path("project_id").asText();
            ObjectNode message = json.createObjectNode();
            ObjectNode m = message.putObject("message");
            m.put("token", token);
            m.putObject("notification").put("title", title).put("body", body);
            ObjectNode d = m.putObject("data");
            data.forEach(d::put);
            // canal do Android: "pedidos" (pedidos/estoque) ou "promocoes" — o app cria os dois
            String channel = "promotion".equals(data.get("type")) || "back_in_stock".equals(data.get("type"))
                    ? "promocoes" : "pedidos";
            m.putObject("android").put("priority", "HIGH").putObject("notification").put("channel_id", channel);
            HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(api + project + "/messages:send"))
                    .timeout(Duration.ofSeconds(15))
                    .header("Authorization", "Bearer " + tokens.get())
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(message))).build(),
                    HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() / 100 == 2) {
                return Result.SENT;
            }
            if (res.statusCode() == 404 || (res.statusCode() == 400 && isBadToken(res.body()))) {
                return Result.INVALID_TOKEN;
            }
            log.warn("FCM respondeu {}: {}", res.statusCode(), res.body());
            return Result.FAILED;
        } catch (IOException e) {
            log.warn("Falha ao enviar push: {}", e.getMessage());
            return Result.FAILED;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return Result.FAILED;
        }
    }

    private boolean isBadToken(String body) {
        try {
            JsonNode details = json.readTree(body).path("error").path("details");
            for (JsonNode d : details) {
                String code = d.path("errorCode").asText();
                if (code.equals("UNREGISTERED")) {
                    return true;
                }
            }
        } catch (IOException ignored) {
            // corpo inesperado: trata como falha comum
        }
        return false;
    }
}
