package com.max.loja;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.imageio.ImageIO;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.max.loja.push.PushOutboxWorker;
import com.max.loja.push.PushSender;
import com.max.loja.shared.RateLimiter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultMatcher;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * Fluxo ponta a ponta contra um PostgreSQL real (padrão: localhost:5432/loja_test, configurável via
 * TEST_DB_URL / DB_USER / DB_PASSWORD). Firebase "ligado" com envio simulado.
 */
@SpringBootTest(properties = {
        "spring.datasource.url=${TEST_DB_URL:jdbc:postgresql://localhost:5432/loja_test}",
        "spring.datasource.username=${DB_USER:loja}", "spring.datasource.password=${DB_PASSWORD:loja}",
        "app.push.service-account-json={\"project_id\":\"teste\"}", "app.push.worker-ms=3600000",
        "app.push.promotions-cron=-",
        "app.owner.email=dono@loja.test", "app.owner.password=SenhaDoDono123"})
@AutoConfigureMockMvc
class StoreFlowIntegrationTest {

    private static final Path MEDIA = createMediaDir();

    @DynamicPropertySource
    static void media(DynamicPropertyRegistry registry) {
        registry.add("app.media.storage-path", MEDIA::toString);
    }

    @Autowired
    MockMvc mvc;

    @Autowired
    ObjectMapper json;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    RateLimiter rateLimiter;

    /** Hora da loja (a promoção é cadastrada no fuso dela). */
    @Autowired
    java.time.Clock clock;

    @Autowired
    PushOutboxWorker pushWorker;

    @MockitoBean
    PushSender push;

    @BeforeEach
    void setUp() {
        rateLimiter.reset();
        when(push.send(anyString(), anyString(), anyString(), any())).thenReturn(PushSender.Result.SENT);
    }

    @Test
    void customerBuysAndStoreHandlesTheOrderWithNotifications() throws Exception {
        String owner = login("dono@loja.test", "SenhaDoDono123");
        call(owner, post("/api/me/push-token"), Map.of("token", "cel-dono-" + UUID.randomUUID()), status().isNoContent());

        long category = id(call(owner, post("/api/store/categories"),
                Map.of("department", "CALCADOS", "name", "Tênis " + UUID.randomUUID(), "position", 1, "active", true),
                status().isCreated()));
        JsonNode product = call(owner, post("/api/store/products"), product("Tênis Runner", "CALCADOS", category, 200,
                        List.of(variant(null, "37", "Preto", 2), variant(null, "38", "Preto", 5))),
                status().isCreated());
        long productId = product.get("id").asLong();
        long v37 = product.get("variants").get(0).get("id").asLong();
        long v38 = product.get("variants").get(1).get("id").asLong();
        assertThat(product.get("totalStock").asInt()).isEqualTo(7);

        // foto: comprimida e gravada (disco nos testes; R2 em produção)
        JsonNode photo = json.readTree(mvc.perform(multipart("/api/store/products/" + productId + "/photos")
                        .file(new MockMultipartFile("file", "tenis.png", "image/png", png(2400, 1600)))
                        .header("Authorization", "Bearer " + owner))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        assertThat(photo.get("width").asInt()).isEqualTo(1600);
        assertThat(photo.get("url").asText()).contains("/api/public/media/produtos/" + productId + "/");

        // promoção do departamento: 25% off
        call(owner, post("/api/store/promotions"), Map.of("title", "Semana do tênis", "discountPercent", 25,
                "department", "CALCADOS", "startsAt", LocalDateTime.now(clock).minusHours(1).toString(),
                "endsAt", LocalDateTime.now(clock).plusDays(3).toString(), "active", true, "notifyCustomers", true),
                status().isCreated());

        // --- cliente ---
        JsonNode card = call(null, get("/api/public/products?department=CALCADOS&onSale=true&size=100"), null, status().isOk());
        JsonNode mine = find(card.get("items"), productId);
        assertThat(mine.get("finalPrice").decimalValue()).isEqualByComparingTo("150.00");
        assertThat(mine.get("discountPercent").asInt()).isEqualTo(25);
        assertThat(mine.get("thumbUrl").asText()).endsWith("-p.jpg");

        String ana = register("Ana Cliente");
        call(ana, post("/api/me/push-token"), Map.of("token", "cel-ana-" + UUID.randomUUID()), status().isNoContent());
        JsonNode order = call(ana, post("/api/orders"), Map.of(
                        "items", List.of(Map.of("variantId", v37, "quantity", 2), Map.of("variantId", v38, "quantity", 1)),
                        "deliveryMethod", "PICKUP", "paymentMethod", "PIX"),
                status().isCreated());
        long orderId = order.get("id").asLong();
        assertThat(order.get("status").asText()).isEqualTo("PENDING");
        assertThat(order.get("total").decimalValue()).isEqualByComparingTo("450.00");
        assertThat(order.get("discount").decimalValue()).isEqualByComparingTo("150.00");
        assertThat(order.get("canCancel").asBoolean()).isTrue();

        // estoque baixou; o 37 esgotou → aviso para a equipe
        JsonNode after = call(owner, get("/api/store/products/" + productId), null, status().isOk());
        assertThat(after.get("variants").get(0).get("stock").asInt()).isZero();
        assertThat(after.get("variants").get(1).get("stock").asInt()).isEqualTo(4);

        JsonNode inbox = call(owner, get("/api/notifications"), null, status().isOk());
        List<String> types = inbox.get("items").findValuesAsText("type");
        assertThat(types).contains("NEW_ORDER", "OUT_OF_STOCK");

        // sem estoque: outro pedido do 37 não passa
        String bia = register("Bia Cliente");
        call(bia, post("/api/orders"), Map.of("items", List.of(Map.of("variantId", v37, "quantity", 1)),
                "deliveryMethod", "PICKUP", "paymentMethod", "CASH"), status().isUnprocessableEntity());
        // Bia pede para ser avisada quando o produto voltar
        call(bia, post("/api/me/watches/" + productId), null, status().isNoContent());

        // outro cliente não vê o pedido da Ana; cliente não entra na gestão
        call(bia, get("/api/orders/" + orderId), null, status().isNotFound());
        call(bia, get("/api/store/orders"), null, status().isForbidden());
        call(null, get("/api/orders"), null, status().isUnauthorized());

        // equipe confirma e deixa pronto: a Ana recebe os avisos
        call(owner, post("/api/store/orders/" + orderId + "/status"), Map.of("status", "CONFIRMED"), status().isOk());
        call(owner, post("/api/store/orders/" + orderId + "/status"), Map.of("status", "SHIPPED"),
                status().isUnprocessableEntity()); // retirada não "sai para entrega"
        JsonNode ready = call(owner, post("/api/store/orders/" + orderId + "/status"), Map.of("status", "READY"), status().isOk());
        assertThat(ready.get("customer").get("name").asText()).isEqualTo("Ana Cliente");
        call(owner, post("/api/store/orders/" + orderId + "/paid"), Map.of("paid", true), status().isOk());

        JsonNode anaInbox = call(ana, get("/api/notifications"), null, status().isOk());
        assertThat(anaInbox.get("items").findValuesAsText("title"))
                .anyMatch(t -> t.contains("pronto para retirar"))
                .contains("Pagamento confirmado");
        assertThat(anaInbox.get("items").findValuesAsText("type")).doesNotContain("NEW_ORDER");

        // o pedido pronto não pode mais ser cancelado pelo app
        call(ana, post("/api/orders/" + orderId + "/cancel"), Map.of(), status().isUnprocessableEntity());
        JsonNode timeline = call(ana, get("/api/orders/" + orderId), null, status().isOk()).get("events");
        assertThat(timeline.findValuesAsText("status")).containsExactly("PENDING", "CONFIRMED", "READY");

        // loja cancela: peças voltam; o 37 volta ao estoque e a Bia é avisada
        call(owner, post("/api/store/orders/" + orderId + "/status"), Map.of("status", "CANCELED", "note", "Cliente desistiu"),
                status().isOk());
        JsonNode restored = call(owner, get("/api/store/products/" + productId), null, status().isOk());
        assertThat(restored.get("variants").get(0).get("stock").asInt()).isEqualTo(2);
        assertThat(call(bia, get("/api/notifications"), null, status().isOk()).get("items").findValuesAsText("type"))
                .contains("BACK_IN_STOCK");
        assertThat(call(bia, get("/api/me/watches"), null, status().isOk())).isEmpty();

        // fila de push: avisos da equipe e da cliente entregues e confirmados
        pushWorker.drain();
        Integer sent = jdbc.queryForObject("select count(*) from push_outbox where status = 'SENT'", Integer.class);
        assertThat(sent).isPositive();
        Map<String, Object> one = jdbc.queryForMap("select public_id, device_token from push_outbox where status = 'SENT' limit 1");
        call(null, post("/api/push/ack"), Map.of("id", one.get("public_id"), "token", one.get("device_token")),
                status().isNoContent());
        assertThat(jdbc.queryForObject("select status from push_outbox where public_id = ?", String.class, one.get("public_id")))
                .isEqualTo("RECEIVED");

        JsonNode report = call(owner, get("/api/store/reports/summary"), null, status().isOk());
        assertThat(report.has("revenue")).isTrue();
        call(ana, get("/api/store/reports/summary"), null, status().isForbidden());
    }

    @Test
    void customerCancelsPendingOrderAndStockReturns() throws Exception {
        String owner = login("dono@loja.test", "SenhaDoDono123");
        call(owner, post("/api/me/push-token"), Map.of("token", "cel-dono2-" + UUID.randomUUID()), status().isNoContent());
        JsonNode product = call(owner, post("/api/store/products"), product("Brinco Argola", "BIJUTERIAS", null, 39.9,
                List.of(variant(null, "Único", "Dourado", 3))), status().isCreated());
        long variant = product.get("variants").get(0).get("id").asLong();

        String cli = register("Carla Cliente");
        long orderId = id(call(cli, post("/api/orders"), Map.of("items", List.of(Map.of("variantId", variant, "quantity", 3)),
                "deliveryMethod", "DELIVERY", "paymentMethod", "CARD", "address", "Rua das Flores, 123 - Centro"),
                status().isCreated()));
        call(cli, post("/api/orders/" + orderId + "/cancel"), Map.of("reason", "Comprei errado"), status().isOk());

        JsonNode p = call(owner, get("/api/store/products/" + product.get("id").asLong()), null, status().isOk());
        assertThat(p.get("variants").get(0).get("stock").asInt()).isEqualTo(3);
        assertThat(call(owner, get("/api/notifications"), null, status().isOk()).get("items").findValuesAsText("title"))
                .anyMatch(t -> t.contains("cancelado pelo cliente"));

        // entrega sem endereço não passa
        call(cli, post("/api/orders"), Map.of("items", List.of(Map.of("variantId", variant, "quantity", 1)),
                "deliveryMethod", "DELIVERY", "paymentMethod", "CARD"), status().isUnprocessableEntity());
    }

    @Test
    void securityBlocksRevokesAndLocks() throws Exception {
        String owner = login("dono@loja.test", "SenhaDoDono123");
        String email = "seg-" + UUID.randomUUID() + "@cliente.test";
        JsonNode reg = call(null, post("/api/auth/register"),
                Map.of("name", "Davi", "email", email, "password", "Senha1234"), status().isCreated());
        String token = reg.get("token").asText();
        long userId = reg.get("user").get("id").asLong();

        // senha fraca recusada
        call(null, post("/api/auth/register"), Map.of("name", "X", "email", "fraca-" + UUID.randomUUID() + "@c.test",
                "password", "12345678"), status().isBadRequest());

        // trocar a senha derruba o token antigo
        JsonNode changed = call(token, post("/api/me/password"),
                Map.of("currentPassword", "Senha1234", "newPassword", "NovaSenha99"), status().isOk());
        call(token, get("/api/me"), null, status().isUnauthorized());
        String fresh = changed.get("token").asText();
        call(fresh, get("/api/me"), null, status().isOk());

        // "sair de todos os aparelhos"
        call(fresh, post("/api/me/logout-all"), null, status().isNoContent());
        call(fresh, get("/api/me"), null, status().isUnauthorized());

        // bloqueio pela loja vale na hora, inclusive no login
        String again = login(email, "NovaSenha99");
        call(owner, post("/api/store/customers/" + userId + "/block"), Map.of("reason", "Pedidos falsos"), status().isOk());
        assertThat(call(again, get("/api/me"), null, status().isForbidden()).get("code").asText())
                .isEqualTo("ACCOUNT_BLOCKED");
        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("email", email, "password", "NovaSenha99"))))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ACCOUNT_BLOCKED"));
        call(owner, post("/api/store/customers/" + userId + "/unblock"), null, status().isOk());

        // senhas erradas seguidas travam o login daquele e-mail
        for (int i = 0; i < 5; i++) {
            call(null, post("/api/auth/login"), Map.of("email", email, "password", "errada" + i), status().isUnauthorized());
        }
        call(null, post("/api/auth/login"), Map.of("email", email, "password", "NovaSenha99"), status().isTooManyRequests());

        // funcionário não mexe em promoções nem na equipe
        call(owner, post("/api/store/users"), Map.of("name", "Fernanda", "email", "func-" + UUID.randomUUID() + "@loja.test",
                "password", "Funcionaria1", "role", "STAFF"), status().isCreated());
        String staffEmail = jdbc.queryForObject("select email from app_user where role = 'STAFF' order by id desc limit 1",
                String.class);
        String staff = login(staffEmail, "Funcionaria1");
        call(staff, get("/api/store/orders"), null, status().isOk());
        call(staff, get("/api/store/promotions"), null, status().isForbidden());
        call(staff, get("/api/store/users"), null, status().isForbidden());

        // token adulterado não entra
        call(owner.substring(0, owner.length() - 3) + "abc", get("/api/me"), null, status().isUnauthorized());
    }

    @Test
    void forgotPasswordAlwaysAnswersTheSameAndResetWorksWithTheCode() throws Exception {
        call(null, post("/api/auth/forgot-password"), Map.of("email", "ninguem-" + UUID.randomUUID() + "@x.test"),
                status().isNoContent());
        call(null, post("/api/auth/reset-password"), Map.of("email", "ninguem@x.test", "code", "ABCDEFGH",
                "password", "Senha12345"), status().isUnprocessableEntity());
    }

    // --- ajudantes ---

    private String login(String email, String password) throws Exception {
        return call(null, post("/api/auth/login"), Map.of("email", email, "password", password), status().isOk())
                .get("token").asText();
    }

    private String register(String name) throws Exception {
        return call(null, post("/api/auth/register"), Map.of("name", name, "email",
                "c-" + UUID.randomUUID() + "@cliente.test", "phone", "11999990000", "password", "Senha1234"),
                status().isCreated()).get("token").asText();
    }

    private static Map<String, Object> product(String name, String department, Long categoryId, double price,
                                               List<Map<String, Object>> variants) {
        Map<String, Object> m = new HashMap<>();
        m.put("name", name + " " + UUID.randomUUID().toString().substring(0, 6));
        m.put("department", department);
        m.put("categoryId", categoryId);
        m.put("price", price);
        m.put("minStock", 1);
        m.put("active", true);
        m.put("featured", false);
        m.put("variants", variants);
        return m;
    }

    private static Map<String, Object> variant(Long id, String size, String color, int stock) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("size", size);
        m.put("color", color);
        m.put("initialStock", stock);
        m.put("active", true);
        return m;
    }

    private JsonNode call(String token, MockHttpServletRequestBuilder req, Object body, ResultMatcher expected)
            throws Exception {
        if (token != null) {
            req.header("Authorization", "Bearer " + token);
        }
        if (body != null) {
            req.contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body));
        }
        String res = mvc.perform(req).andExpect(expected).andReturn().getResponse().getContentAsString();
        return res.isEmpty() ? json.nullNode() : json.readTree(res);
    }

    private static long id(JsonNode n) {
        return n.get("id").asLong();
    }

    private static JsonNode find(JsonNode items, long id) {
        for (JsonNode n : items) {
            if (n.get("id").asLong() == id) {
                return n;
            }
        }
        throw new AssertionError("produto " + id + " não está na lista");
    }

    private static byte[] png(int w, int h) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB), "png", out);
        return out.toByteArray();
    }

    private static Path createMediaDir() {
        try {
            return Files.createTempDirectory("loja-media");
        } catch (java.io.IOException e) {
            throw new IllegalStateException(e);
        }
    }
}
