package com.max.loja.push;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/** Servidor falso no lugar do OAuth do Google e da API do Firebase Cloud Messaging. */
class FcmPushSenderTest {

    private final ObjectMapper json = new ObjectMapper();
    private final List<String> bodies = new CopyOnWriteArrayList<>();
    private HttpServer server;
    private String base;
    private volatile int status = 200;
    private volatile String reply = "{\"name\":\"projects/p/messages/1\"}";

    @BeforeEach
    void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/token", ex -> reply(ex, 200, "{\"access_token\":\"acesso\",\"expires_in\":3600}"));
        server.createContext("/v1/projects/", ex -> {
            bodies.add(ex.getRequestURI().getPath() + " " + ex.getRequestHeaders().getFirst("Authorization") + " "
                    + new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            reply(ex, status, reply);
        });
        server.start();
        base = "http://127.0.0.1:" + server.getAddress().getPort();
    }

    @AfterEach
    void stop() {
        server.stop(0);
    }

    private static void reply(HttpExchange ex, int code, String body) throws java.io.IOException {
        byte[] b = body.getBytes(StandardCharsets.UTF_8);
        ex.sendResponseHeaders(code, b.length == 0 ? -1 : b.length);
        if (b.length > 0) {
            ex.getResponseBody().write(b);
        }
        ex.close();
    }

    private FcmPushSender sender(boolean configured) throws Exception {
        if (!configured) {
            return new FcmPushSender(new PushProperties(""), json, base + "/v1/projects/");
        }
        KeyPairGenerator gen = KeyPairGenerator.getInstance("RSA");
        gen.initialize(2048);
        String pem = "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getMimeEncoder(64, "\n".getBytes()).encodeToString(gen.generateKeyPair().getPrivate().getEncoded())
                + "\n-----END PRIVATE KEY-----\n";
        String account = json.writeValueAsString(Map.of("project_id", "loja-max", "client_email", "fcm@loja-max.iam.gserviceaccount.com",
                "private_key", pem, "token_uri", base + "/token"));
        return new FcmPushSender(new PushProperties(account), json, base + "/v1/projects/");
    }

    @Test
    void sendsTheMessageToTheProjectWithTheDeepLinkData() throws Exception {
        FcmPushSender fcm = sender(true);
        PushSender.Result r = fcm.send("cel-1", "Promoção de inverno", "30% off em Roupas",
                Map.of("type", "promotion", "promotionId", "7"));
        assertThat(r).isEqualTo(PushSender.Result.SENT);
        String req = bodies.get(0);
        assertThat(req).startsWith("/v1/projects/loja-max/messages:send Bearer acesso ");
        var message = json.readTree(req.substring(req.indexOf('{'))).path("message");
        assertThat(message.path("token").asText()).isEqualTo("cel-1");
        assertThat(message.path("notification").path("title").asText()).isEqualTo("Promoção de inverno");
        assertThat(message.path("data").path("promotionId").asText()).isEqualTo("7");
        assertThat(message.path("android").path("notification").path("channel_id").asText()).isEqualTo("promocoes");
    }

    @Test
    void orderNoticesGoToTheOrdersChannel() throws Exception {
        assertThat(sender(true).send("cel-2", "Novo pedido #ABC123", "Ana · 2 itens", Map.of("type", "team", "orderId", "1")))
                .isEqualTo(PushSender.Result.SENT);
        String req = bodies.get(0);
        var message = json.readTree(req.substring(req.indexOf('{'))).path("message");
        assertThat(message.path("android").path("notification").path("channel_id").asText()).isEqualTo("pedidos");
    }

    @Test
    void unregisteredDeviceIsReportedSoItCanBeRemoved() throws Exception {
        status = 404;
        reply = "{\"error\":{\"status\":\"NOT_FOUND\",\"details\":[{\"errorCode\":\"UNREGISTERED\"}]}}";
        assertThat(sender(true).send("velho", "t", "b", Map.of())).isEqualTo(PushSender.Result.INVALID_TOKEN);
    }

    @Test
    void withoutFirebaseConfiguredNothingIsSent() throws Exception {
        assertThat(sender(false).send("cel", "t", "b", Map.of())).isEqualTo(PushSender.Result.DISABLED);
        assertThat(bodies).isEmpty();
    }
}
