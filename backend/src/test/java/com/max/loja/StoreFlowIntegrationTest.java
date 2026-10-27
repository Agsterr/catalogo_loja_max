package com.max.loja;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
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
import com.max.loja.security.Totp;
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
 * TEST_DB_URL / DB_USER / DB_PASSWORD). Firebase "ligado" com envio simulado. Cada teste abre as próprias lojas.
 */
@SpringBootTest(properties = {
        "spring.datasource.url=${TEST_DB_URL:jdbc:postgresql://localhost:5432/loja_test}",
        "spring.datasource.username=${DB_USER:loja}", "spring.datasource.password=${DB_PASSWORD:loja}",
        "app.push.service-account-json={\"project_id\":\"teste\"}", "app.push.worker-ms=3600000",
        "app.push.promotions-cron=-",
        "app.platform-admin.email=admin@plataforma.test", "app.platform-admin.password=SenhaDoAdmin123",
        "app.billing.free-deliveries=1", "app.billing.pix-key=pix@plataforma.test", "app.billing.pix-holder=Loja Max"})
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

    @Autowired
    com.max.loja.delivery.DispatchService dispatch;

    @MockitoBean
    PushSender push;

    record Shop(String slug, String owner) {

        String base() {
            return "/api/public/stores/" + slug;
        }

        String orders() {
            return "/api/stores/" + slug + "/orders";
        }
    }

    @BeforeEach
    void setUp() {
        rateLimiter.reset();
        when(push.send(anyString(), anyString(), anyString(), any())).thenReturn(PushSender.Result.SENT);
    }

    @Test
    void customerBuysAndStoreHandlesTheOrderWithNotifications() throws Exception {
        Shop shop = openStore("Moda da Ana");
        String owner = shop.owner();
        call(owner, post("/api/me/push-token"), Map.of("token", "cel-dono-" + UUID.randomUUID()), status().isNoContent());

        long category = id(call(owner, post("/api/store/categories"),
                Map.of("department", "CALCADOS", "name", "Tênis", "position", 1, "active", true), status().isCreated()));
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

        // --- cliente: acha a loja na busca e abre a vitrine ---
        JsonNode found = call(null, get("/api/public/stores?q=" + shop.slug()), null, status().isOk());
        assertThat(found.get("items").findValuesAsText("slug")).contains(shop.slug());
        JsonNode card = call(null, get(shop.base() + "/products?department=CALCADOS&onSale=true"), null, status().isOk());
        JsonNode mine = find(card.get("items"), productId);
        assertThat(mine.get("finalPrice").decimalValue()).isEqualByComparingTo("150.00");
        assertThat(mine.get("discountPercent").asInt()).isEqualTo(25);
        assertThat(mine.get("thumbUrl").asText()).endsWith("-p.jpg");

        String ana = register("Ana Cliente");
        call(ana, post("/api/me/push-token"), Map.of("token", "cel-ana-" + UUID.randomUUID()), status().isNoContent());
        JsonNode order = call(ana, post(shop.orders()), Map.of(
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
        assertThat(inbox.get("items").findValuesAsText("type")).contains("NEW_ORDER", "OUT_OF_STOCK");

        // sem estoque: outro pedido do 37 não passa
        String bia = register("Bia Cliente");
        call(bia, post(shop.orders()), Map.of("items", List.of(Map.of("variantId", v37, "quantity", 1)),
                "deliveryMethod", "PICKUP", "paymentMethod", "CASH"), status().isUnprocessableEntity());
        // Bia pede para ser avisada quando o produto voltar
        call(bia, post("/api/me/watches/" + productId), null, status().isNoContent());

        // outro cliente não vê o pedido da Ana; cliente não entra na gestão
        call(bia, get(shop.orders() + "/" + orderId), null, status().isNotFound());
        call(bia, get("/api/store/orders"), null, status().isForbidden());
        call(null, get(shop.orders()), null, status().isUnauthorized());

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
        assertThat(anaInbox.get("items").findValuesAsText("storeSlug")).containsOnly(shop.slug());

        // o pedido pronto não pode mais ser cancelado pelo app
        call(ana, post(shop.orders() + "/" + orderId + "/cancel"), Map.of(), status().isUnprocessableEntity());
        JsonNode timeline = call(ana, get(shop.orders() + "/" + orderId), null, status().isOk()).get("events");
        assertThat(timeline.findValuesAsText("status")).containsExactly("PENDING", "CONFIRMED", "READY");

        // loja cancela: peças voltam; o 37 volta ao estoque e a Bia é avisada
        call(owner, post("/api/store/orders/" + orderId + "/status"), Map.of("status", "CANCELED", "note", "Cliente desistiu"),
                status().isOk());
        JsonNode restored = call(owner, get("/api/store/products/" + productId), null, status().isOk());
        assertThat(restored.get("variants").get(0).get("stock").asInt()).isEqualTo(2);
        assertThat(call(bia, get("/api/notifications"), null, status().isOk()).get("items").findValuesAsText("type"))
                .contains("BACK_IN_STOCK");
        assertThat(call(bia, get("/api/me/watches"), null, status().isOk())).isEmpty();

        // histórico do estoque paginado
        JsonNode history = call(owner, get("/api/store/variants/" + v37 + "/stock?size=2"), null, status().isOk());
        assertThat(history.get("items")).hasSize(2);
        assertThat(history.get("hasMore").asBoolean()).isTrue();

        // fila de push: avisos da equipe e da cliente entregues e confirmados
        pushWorker.drain();
        Integer sent = jdbc.queryForObject("select count(*) from push_outbox where status = 'SENT'", Integer.class);
        assertThat(sent).isPositive();
        Map<String, Object> one = jdbc.queryForMap("select public_id, device_token from push_outbox where status = 'SENT' limit 1");
        call(null, post("/api/push/ack"), Map.of("id", one.get("public_id"), "token", one.get("device_token")),
                status().isNoContent());
        assertThat(jdbc.queryForObject("select status from push_outbox where public_id = ?", String.class, one.get("public_id")))
                .isEqualTo("RECEIVED");

        // resumo calculado no banco (o pedido cancelado não conta)
        JsonNode report = call(owner, get("/api/store/reports/summary"), null, status().isOk());
        assertThat(report.get("orders").asLong()).isZero();
        assertThat(report.get("byStatus").get("CANCELED").asLong()).isEqualTo(1);
        call(ana, get("/api/store/reports/summary"), null, status().isForbidden());

        // clientes da loja: só quem comprou aqui
        JsonNode customers = call(owner, get("/api/store/customers"), null, status().isOk());
        assertThat(customers.get("items").findValuesAsText("name")).containsExactly("Ana Cliente");
    }

    @Test
    void storesNeverSeeEachOthersData() throws Exception {
        Shop a = openStore("Loja A");
        Shop b = openStore("Loja B");
        JsonNode product = call(a.owner(), post("/api/store/products"), product("Colar Pérola", "BIJUTERIAS", null, 80,
                List.of(variant(null, "Único", "", 3))), status().isCreated());
        long productId = product.get("id").asLong();
        long variantId = product.get("variants").get(0).get("id").asLong();
        String cli = register("Cliente das duas");
        long orderId = id(call(cli, post(a.orders()), Map.of("items", List.of(Map.of("variantId", variantId, "quantity", 1)),
                "deliveryMethod", "PICKUP", "paymentMethod", "PIX"), status().isCreated()));

        // a equipe da B não acha produto, pedido, estoque nem avisos da A
        call(b.owner(), get("/api/store/products/" + productId), null, status().isNotFound());
        call(b.owner(), put("/api/store/products/" + productId), product("Roubado", "BIJUTERIAS", null, 1,
                List.of(variant(null, "Único", "", 0))), status().isNotFound());
        call(b.owner(), get("/api/store/orders/" + orderId), null, status().isNotFound());
        call(b.owner(), post("/api/store/orders/" + orderId + "/status"), Map.of("status", "CANCELED"), status().isNotFound());
        call(b.owner(), post("/api/store/variants/" + variantId + "/stock"), Map.of("type", "IN", "quantity", 5),
                status().isNotFound());
        assertThat(call(b.owner(), get("/api/store/products"), null, status().isOk()).get("total").asLong()).isZero();
        assertThat(call(b.owner(), get("/api/store/orders?open=false"), null, status().isOk()).get("total").asLong()).isZero();
        assertThat(call(b.owner(), get("/api/notifications"), null, status().isOk()).get("items")).isEmpty();
        assertThat(call(b.owner(), get("/api/store/customers"), null, status().isOk()).get("items")).isEmpty();

        // na vitrine da B o produto da A não existe, e não dá para comprar a peça da A pela B
        call(null, get(b.base() + "/products/" + productId), null, status().isNotFound());
        call(cli, post(b.orders()), Map.of("items", List.of(Map.of("variantId", variantId, "quantity", 1)),
                "deliveryMethod", "PICKUP", "paymentMethod", "PIX"), status().isUnprocessableEntity());
        // pedido da A não aparece pela B
        call(cli, get(b.orders() + "/" + orderId), null, status().isNotFound());

        // bloqueio da B vale só na B
        long cliId = jdbc.queryForObject("select customer_id from orders where id = ?", Long.class, orderId);
        call(b.owner(), post("/api/store/customers/" + cliId + "/block"), Map.of("reason", "teste"), status().isNoContent());
        JsonNode bProduct = call(b.owner(), post("/api/store/products"), product("Brinco", "BIJUTERIAS", null, 20,
                List.of(variant(null, "Único", "", 3))), status().isCreated());
        call(cli, post(b.orders()), Map.of("items", List.of(Map.of("variantId", bProduct.get("variants").get(0).get("id").asLong(),
                "quantity", 1)), "deliveryMethod", "PICKUP", "paymentMethod", "PIX"), status().isForbidden());
        call(cli, post(a.orders()), Map.of("items", List.of(Map.of("variantId", variantId, "quantity", 1)),
                "deliveryMethod", "PICKUP", "paymentMethod", "PIX"), status().isCreated());

        // admin da plataforma bloqueia a A: some da vitrine e a equipe dela cai na hora
        String admin = login("admin@plataforma.test", "SenhaDoAdmin123");
        long aId = jdbc.queryForObject("select id from store where slug = ?", Long.class, a.slug());
        call(admin, post("/api/platform/stores/" + aId + "/block"), Map.of("reason", "Fraude"), status().isOk());
        call(null, get(a.base()), null, status().isNotFound());
        assertThat(call(a.owner(), get("/api/store/orders"), null, status().isForbidden()).get("code").asText())
                .isEqualTo("ACCOUNT_BLOCKED");
        call(b.owner(), get("/api/store/orders"), null, status().isOk());
        call(a.owner(), get("/api/platform/stores"), null, status().isForbidden());
        call(admin, post("/api/platform/stores/" + aId + "/unblock"), null, status().isOk());
        call(null, get(a.base()), null, status().isOk());
    }

    @Test
    void customerCancelsPendingOrderAndStockReturns() throws Exception {
        Shop shop = openStore("Bijus da Carla");
        call(shop.owner(), post("/api/me/push-token"), Map.of("token", "cel-dono2-" + UUID.randomUUID()), status().isNoContent());
        JsonNode product = call(shop.owner(), post("/api/store/products"), product("Brinco Argola", "BIJUTERIAS", null, 39.9,
                List.of(variant(null, "Único", "Dourado", 3))), status().isCreated());
        long variant = product.get("variants").get(0).get("id").asLong();

        String cli = register("Carla Cliente");
        long orderId = id(call(cli, post(shop.orders()), Map.of("items", List.of(Map.of("variantId", variant, "quantity", 3)),
                "deliveryMethod", "DELIVERY", "paymentMethod", "CARD", "address", "Rua das Flores, 123 - Centro"),
                status().isCreated()));
        call(cli, post(shop.orders() + "/" + orderId + "/cancel"), Map.of("reason", "Comprei errado"), status().isOk());

        JsonNode p = call(shop.owner(), get("/api/store/products/" + product.get("id").asLong()), null, status().isOk());
        assertThat(p.get("variants").get(0).get("stock").asInt()).isEqualTo(3);
        assertThat(call(shop.owner(), get("/api/notifications"), null, status().isOk()).get("items").findValuesAsText("title"))
                .anyMatch(t -> t.contains("cancelado pelo cliente"));

        // entrega sem endereço não passa
        call(cli, post(shop.orders()), Map.of("items", List.of(Map.of("variantId", variant, "quantity", 1)),
                "deliveryMethod", "DELIVERY", "paymentMethod", "CARD"), status().isUnprocessableEntity());

        // sino paginado
        JsonNode page = call(shop.owner(), get("/api/notifications?size=1"), null, status().isOk());
        assertThat(page.get("items")).hasSize(1);
        assertThat(page.get("hasMore").asBoolean()).isTrue();
    }

    @Test
    void securityBlocksRevokesLocksAndAudits() throws Exception {
        Shop shop = openStore("Segura Moda");
        String owner = shop.owner();
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

        // bloqueio geral (admin da plataforma) vale na hora, inclusive no login
        String again = login(email, "NovaSenha99");
        String admin = login("admin@plataforma.test", "SenhaDoAdmin123");
        call(admin, post("/api/platform/users/" + userId + "/block"), Map.of("reason", "Pedidos falsos"), status().isOk());
        assertThat(call(again, get("/api/me"), null, status().isForbidden()).get("code").asText()).isEqualTo("ACCOUNT_BLOCKED");
        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("email", email, "password", "NovaSenha99"))))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("ACCOUNT_BLOCKED"));
        call(admin, post("/api/platform/users/" + userId + "/unblock"), null, status().isOk());

        // senhas erradas seguidas travam o login daquele e-mail
        for (int i = 0; i < 5; i++) {
            call(null, post("/api/auth/login"), Map.of("email", email, "password", "errada" + i), status().isUnauthorized());
        }
        call(null, post("/api/auth/login"), Map.of("email", email, "password", "NovaSenha99"), status().isTooManyRequests());

        // a própria pessoa vê os acessos dela
        JsonNode mine = call(admin, get("/api/me/security-events"), null, status().isOk());
        assertThat(mine.get("items").findValuesAsText("type")).contains("LOGIN");
        assertThat(jdbc.queryForObject("select count(*) from security_event where user_id = ? and type = 'LOGIN_LOCKED'",
                Integer.class, userId)).isEqualTo(1);

        // funcionário não mexe em promoções, equipe nem auditoria
        String staffEmail = "func-" + UUID.randomUUID() + "@loja.test";
        call(owner, post("/api/store/users"), Map.of("name", "Fernanda", "email", staffEmail,
                "password", "Funcionaria1", "role", "STAFF"), status().isCreated());
        String staff = login(staffEmail, "Funcionaria1");
        call(staff, get("/api/store/orders"), null, status().isOk());
        call(staff, get("/api/store/promotions"), null, status().isForbidden());
        call(staff, get("/api/store/users"), null, status().isForbidden());
        call(staff, get("/api/store/audit"), null, status().isForbidden());
        JsonNode audit = call(owner, get("/api/store/audit"), null, status().isOk());
        assertThat(audit.get("items").findValuesAsText("type")).contains("STORE_CREATED", "STAFF_CREATED", "LOGIN");

        // token adulterado não entra
        call(owner.substring(0, owner.length() - 3) + "abc", get("/api/me"), null, status().isUnauthorized());
    }

    @Test
    void twoFactorProtectsTheLogin() throws Exception {
        Shop shop = openStore("Loja Dupla");
        String email = jdbc.queryForObject("select u.email from app_user u join store s on s.id = u.store_id where s.slug = ?",
                String.class, shop.slug());
        JsonNode setup = call(shop.owner(), post("/api/me/2fa/setup"), null, status().isOk());
        String secret = setup.get("secret").asText();
        assertThat(setup.get("otpauthUri").asText()).startsWith("otpauth://totp/");
        call(shop.owner(), post("/api/me/2fa/enable"), Map.of("code", "000000"), status().isUnprocessableEntity());
        call(shop.owner(), post("/api/me/2fa/enable"), Map.of("code", code(secret)), status().isNoContent());
        // segredo fica cifrado no banco
        assertThat(jdbc.queryForObject("select totp_secret from app_user where email = ?", String.class, email)).doesNotContain(secret);

        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("email", email, "password", "SenhaDona123"))))
                .andExpect(status().isUnauthorized()).andExpect(jsonPath("$.code").value("TOTP_REQUIRED"));
        call(null, post("/api/auth/login"), Map.of("email", email, "password", "SenhaDona123", "code", "123456"),
                status().isUnauthorized());
        JsonNode ok = call(null, post("/api/auth/login"), Map.of("email", email, "password", "SenhaDona123", "code", code(secret)),
                status().isOk());
        assertThat(ok.get("user").get("twoFactorEnabled").asBoolean()).isTrue();
        assertThat(ok.get("user").get("storeSlug").asText()).isEqualTo(shop.slug());
    }

    @Test
    void forgotPasswordAlwaysAnswersTheSameAndResetWorksWithTheCode() throws Exception {
        call(null, post("/api/auth/forgot-password"), Map.of("email", "ninguem-" + UUID.randomUUID() + "@x.test"),
                status().isNoContent());
        call(null, post("/api/auth/reset-password"), Map.of("email", "ninguem@x.test", "code", "ABCDEFGH",
                "password", "Senha12345"), status().isUnprocessableEntity());
        // endereço de loja repetido não passa
        Shop shop = openStore("Repetida");
        call(null, post("/api/auth/register-store"), Map.of("storeName", "Outra", "slug", shop.slug(), "ownerName", "X",
                "email", "x-" + UUID.randomUUID() + "@x.test", "password", "SenhaDona123"), status().isUnprocessableEntity());
    }

    @Test
    void storefrontImprovements() throws Exception {
        Shop shop = openStore("Moda Ação");
        String owner = shop.owner();
        // busca sem acento (produtos e lojas)
        JsonNode product = call(owner, post("/api/store/products"), withChart(product("Calça Jeans Básica", "ROUPAS", null, 120,
                List.of(variant(null, "40", "Azul", 5), variant(null, "42", "Preto", 2))), "40: cintura 70 cm"), status().isCreated());
        long productId = product.get("id").asLong();
        assertThat(product.get("sizeChart").asText()).isEqualTo("40: cintura 70 cm");
        assertThat(call(null, get(shop.base() + "/products?q=calca"), null, status().isOk()).get("total").asLong()).isEqualTo(1);
        assertThat(call(null, get("/api/public/stores?q=acao"), null, status().isOk()).get("items").findValuesAsText("slug"))
                .contains(shop.slug());

        // foto ligada a uma cor
        JsonNode photo = json.readTree(mvc.perform(multipart("/api/store/products/" + productId + "/photos")
                        .file(new MockMultipartFile("file", "azul.png", "image/png", png(800, 600))).param("color", "Azul")
                        .header("Authorization", "Bearer " + owner))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        assertThat(photo.get("color").asText()).isEqualTo("Azul");
        call(owner, put("/api/store/photos/" + photo.get("id").asLong() + "/color"), Map.of("color", "Preto"), status().isOk());

        // loja: descrição, horário (7 dias), logo e capa
        List<Map<String, String>> week = new java.util.ArrayList<>();
        for (int i = 0; i < 7; i++) {
            week.add(i == 6 ? Map.of("open", "", "close", "") : Map.of("open", "00:00", "close", "23:59"));
        }
        Map<String, Object> settings = new HashMap<>();
        settings.put("name", "Moda Ação");
        settings.put("description", "Roupas femininas");
        settings.put("pickupEnabled", true);
        settings.put("deliveryEnabled", true);
        settings.put("deliveryFee", 10);
        settings.put("openingHours", week);
        JsonNode saved = call(owner, put("/api/store/settings"), settings, status().isOk());
        assertThat(saved.get("hours")).hasSize(7);
        assertThat(saved.get("hours").get(6).asText()).endsWith("fechado");
        assertThat(saved.get("status").has("label")).isTrue();
        settings.put("openingHours", List.of(Map.of("open", "09:00", "close", "18:00")));
        call(owner, put("/api/store/settings"), settings, status().isBadRequest()); // precisa dos 7 dias
        JsonNode withLogo = json.readTree(mvc.perform(multipart("/api/store/settings/logo")
                        .file(new MockMultipartFile("file", "logo.png", "image/png", png(600, 600)))
                        .header("Authorization", "Bearer " + owner))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        assertThat(withLogo.get("logoUrl").asText()).contains("/lojas/");
        JsonNode card = null;
        for (JsonNode c : call(null, get("/api/public/stores?q=" + shop.slug()), null, status().isOk()).get("items")) {
            card = c;
        }
        assertThat(card.get("logoUrl").asText()).contains("/lojas/");
        call(owner, org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete("/api/store/settings/logo"), null,
                status().isOk());

        // localização: cidade/UF e distância ("lojas perto de mim")
        String cidade = "Cidade" + shop.slug().substring(5).replace("-", "x");
        settings.remove("openingHours");
        settings.put("city", cidade);
        settings.put("state", "sp");
        settings.put("latitude", -23.5505);
        settings.put("longitude", -46.6333);
        JsonNode located = call(owner, put("/api/store/settings"), settings, status().isOk());
        assertThat(located.get("state").asText()).isEqualTo("SP");
        JsonNode inCity = call(null, get("/api/public/stores?city=" + cidade.toLowerCase()), null, status().isOk());
        assertThat(inCity.get("items").findValuesAsText("slug")).containsExactly(shop.slug());
        JsonNode near = call(null, get("/api/public/stores?lat=-23.56&lng=-46.64&radiusKm=5&city=" + cidade), null, status().isOk());
        assertThat(near.get("items").get(0).get("distanceKm").asDouble()).isBetween(0.5, 3.0);
        assertThat(call(null, get("/api/public/stores?lat=-22.90&lng=-43.17&radiusKm=5&city=" + cidade), null, status().isOk())
                .get("total").asLong()).isZero(); // Rio de Janeiro: fora do raio
        assertThat(call(null, get("/api/public/store-cities"), null, status().isOk()).findValuesAsText("city")).contains(cidade);
        settings.put("latitude", 99);
        call(owner, put("/api/store/settings"), settings, status().isBadRequest());

        // entrega por distância: até 3 km R$ 8, até 8 km R$ 15, além disso não entrega; frete grátis a partir de R$ 200
        settings.put("latitude", -23.5505);
        settings.put("deliveryZones", List.of(Map.of("upToKm", 8, "fee", 15), Map.of("upToKm", 3, "fee", 8)));
        settings.put("freeDeliveryFrom", 200);
        JsonNode zoned = call(owner, put("/api/store/settings"), settings, status().isOk());
        assertThat(zoned.get("deliveryZones").get(0).get("upToKm").asDouble()).isEqualTo(3.0); // guardadas em ordem
        String quoteUrl = shop.base() + "/delivery-quote?subtotal=100&";
        assertThat(call(null, get(quoteUrl + "lat=-23.56&lng=-46.64"), null, status().isOk()).get("fee").decimalValue())
                .isEqualByComparingTo("8"); // ~1,4 km
        assertThat(call(null, get(quoteUrl + "lat=-23.59&lng=-46.68"), null, status().isOk()).get("fee").decimalValue())
                .isEqualByComparingTo("15"); // ~6,6 km: faixa dos 8 km
        assertThat(call(null, get(quoteUrl + "lat=-22.90&lng=-43.17"), null, status().isOk()).get("available").asBoolean()).isFalse();
        assertThat(call(null, get(quoteUrl.replace("subtotal=100", "subtotal=300") + "lat=-23.56&lng=-46.64"), null, status().isOk())
                .get("fee").decimalValue()).isEqualByComparingTo("0");
        assertThat(call(null, get(quoteUrl.substring(0, quoteUrl.length() - 1)), null, status().isOk()).get("needsLocation").asBoolean())
                .isTrue();
        JsonNode dummy = product.get("variants").get(0);
        String bruna = register("Bruna");
        Map<String, Object> delivery = new HashMap<>(Map.of("items", List.of(Map.of("variantId", dummy.get("id").asLong(), "quantity", 1)),
                "deliveryMethod", "DELIVERY", "paymentMethod", "PIX", "address", "Rua das Flores, 123 - Centro"));
        call(bruna, post(shop.orders()), delivery, status().isUnprocessableEntity()); // sem localização
        delivery.put("deliveryLat", -22.90);
        delivery.put("deliveryLng", -43.17);
        call(bruna, post(shop.orders()), delivery, status().isUnprocessableEntity()); // fora da área
        delivery.put("deliveryLat", -23.56);
        delivery.put("deliveryLng", -46.64);
        JsonNode placed = call(bruna, post(shop.orders()), delivery, status().isCreated());
        assertThat(placed.get("deliveryFee").decimalValue()).isEqualByComparingTo("8");

        // conferência do carrinho: preço de agora, estoque e peça de outra loja
        long v42 = product.get("variants").get(1).get("id").asLong();
        Shop other = openStore("Outra");
        JsonNode quote = call(null, post(shop.base() + "/cart/quote"),
                Map.of("items", List.of(Map.of("variantId", v42, "quantity", 5))), status().isOk());
        assertThat(quote.get("items").get(0).get("quantity").asInt()).isEqualTo(2); // só 2 em estoque
        assertThat(quote.get("subtotal").decimalValue()).isEqualByComparingTo("240.00");
        JsonNode foreign = call(null, post(other.base() + "/cart/quote"),
                Map.of("items", List.of(Map.of("variantId", v42, "quantity", 1))), status().isOk());
        assertThat(foreign.get("items").get(0).get("available").asBoolean()).isFalse();

        // endereços salvos (do cliente; um não apaga o do outro)
        String ana = register("Ana");
        String bia = register("Bia");
        long addr = id(call(ana, post("/api/me/addresses"), Map.of("label", "Casa", "address", "Rua das Flores, 123 - Centro"),
                status().isCreated()));
        assertThat(call(ana, get("/api/me/addresses"), null, status().isOk())).hasSize(1);
        call(bia, org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete("/api/me/addresses/" + addr), null,
                status().isNoContent());
        assertThat(call(ana, get("/api/me/addresses"), null, status().isOk())).hasSize(1);
        call(ana, post("/api/me/addresses"), Map.of("label", "X", "address", "curto"), status().isBadRequest());

        // preferência de promoções lida do servidor
        call(ana, post("/api/me/push-token"), Map.of("token", "cel-pref"), status().isNoContent());
        call(ana, put("/api/me/push-preferences"), Map.of("token", "cel-pref", "promoNotifications", false), status().isNoContent());
        assertThat(call(ana, get("/api/me/push-preferences?token=cel-pref"), null, status().isOk())
                .get("promoNotifications").asBoolean()).isFalse();

        // planilhas: só o dono; texto que parece fórmula vem protegido
        String csv = mvc.perform(get("/api/store/reports/stock.csv").header("Authorization", "Bearer " + owner))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
        assertThat(csv).contains("Calça Jeans Básica").contains("Produto;Departamento");
        call(ana, get("/api/store/reports/stock.csv"), null, status().isForbidden());
        mvc.perform(get("/api/store/reports/orders.csv").header("Authorization", "Bearer " + owner)).andExpect(status().isOk());
    }

    private static Map<String, Object> withChart(Map<String, Object> product, String chart) {
        product.put("sizeChart", chart);
        return product;
    }

    // --- ajudantes ---

    private Shop openStore(String name) throws Exception {
        String slug = "loja-" + UUID.randomUUID().toString().substring(0, 8);
        JsonNode res = call(null, post("/api/auth/register-store"), Map.of("storeName", name, "slug", slug,
                "ownerName", "Dona " + name, "email", "dona-" + slug + "@loja.test", "password", "SenhaDona123"),
                status().isCreated());
        rateLimiter.reset();
        return new Shop(slug, res.get("token").asText());
    }

    @Test
    void courierDeliversAnOrderEndToEnd() throws Exception {
        jdbc.update("delete from delivery_job"); // o banco de teste é compartilhado: corridas de execuções anteriores sujariam o mural
        Shop shop = openStore("Loja Moto");
        String owner = shop.owner();
        Map<String, Object> settings = new HashMap<>();
        settings.put("name", "Loja Moto");
        settings.put("pickupEnabled", true);
        settings.put("deliveryEnabled", true);
        settings.put("deliveryFee", 0);
        settings.put("city", "Cidade Teste");
        settings.put("state", "SP");
        settings.put("courierDelivery", true);
        call(owner, put("/api/store/settings"), settings, status().isUnprocessableEntity()); // falta marcar onde a loja fica
        settings.put("latitude", -23.5505);
        settings.put("longitude", -46.6333);
        assertThat(call(owner, put("/api/store/settings"), settings, status().isOk()).get("courierDelivery").asBoolean()).isTrue();
        JsonNode product = call(owner, post("/api/store/products"), product("Camiseta", "ROUPAS", null, 80,
                List.of(variant(null, "M", "Preto", 9))), status().isCreated());
        long variant = product.get("variants").get(0).get("id").asLong();

        // entregadores: cadastro pendente → sem acesso até a plataforma aprovar
        String deviceA = "aparelho-A-" + UUID.randomUUID();
        String deviceB = "aparelho-B-" + UUID.randomUUID();
        String cpfZe = newCpf();
        String ze = registerCourier("Zé Moto", -23.56, -46.64, deviceA, cpfZe, status().isCreated()).get("token").asText();
        String bia = registerCourier("Bia Bike", -23.57, -46.65, deviceB);
        // antifraude: mesmo CPF, CPF inválido e cadastro sem o ID do aparelho são recusados
        registerCourier("Zé de novo", -23.56, -46.64, deviceB, cpfZe, status().isUnprocessableEntity());
        registerCourier("CPF ruim", -23.56, -46.64, deviceB, "11111111111", status().isUnprocessableEntity());
        registerCourier("Sem aparelho", -23.56, -46.64, null, newCpf(), status().isUnprocessableEntity());
        call(ze, get("/api/courier/jobs/open"), null, status().isForbidden());
        String admin = login("admin@plataforma.test", "SenhaDoAdmin123");
        call(ze, get("/api/courier/jobs/open"), null, status().isForbidden());
        call(admin, post("/api/platform/couriers/" + id(call(ze, get("/api/courier/me"), null, status().isOk())) + "/approve"), null,
                status().isNoContent());
        call(admin, post("/api/platform/couriers/" + id(call(bia, get("/api/courier/me"), null, status().isOk())) + "/approve"), null,
                status().isNoContent());
        call(ze, withDevice(post("/api/courier/online"), deviceA), Map.of("online", true, "lat", -23.56, "lng", -46.64), status().isOk());
        call(bia, withDevice(post("/api/courier/online"), deviceB), Map.of("online", true, "lat", -23.57, "lng", -46.65), status().isOk());
        call(ze, get("/api/courier/jobs/open"), null, status().isOk());
        call(shop.owner(), get("/api/courier/me"), null, status().isForbidden()); // lojista não é entregador

        // pedido com entrega: precisa da localização, não aceita dinheiro, taxa vem da distância
        String carla = register("Carla");
        Map<String, Object> req = new HashMap<>(Map.of("items", List.of(Map.of("variantId", variant, "quantity", 1)),
                "deliveryMethod", "DELIVERY", "paymentMethod", "PIX", "address", "Rua das Flores, 123 - Centro"));
        call(carla, post(shop.orders()), req, status().isUnprocessableEntity());
        req.put("deliveryLat", -23.56);
        req.put("deliveryLng", -46.64);
        req.put("paymentMethod", "CASH");
        call(carla, post(shop.orders()), req, status().isUnprocessableEntity());
        req.put("paymentMethod", "PIX");
        JsonNode order = call(carla, post(shop.orders()), req, status().isCreated());
        long orderId = id(order);
        assertThat(order.get("deliveryFee").decimalValue()).isEqualByComparingTo("6.00"); // ~1,3 km: vale o mínimo da corrida
        assertThat(order.get("total").decimalValue()).isEqualByComparingTo("80.00"); // o frete vai direto ao entregador, fora do total
        assertThat(order.get("courier").get("freightPayer").asText()).isEqualTo("CUSTOMER");
        assertThat(order.get("courier").get("status").asText()).isEqualTo("WAITING");

        // a loja confirma, mas sem pagamento não abre corrida; a coleta/entrega são do entregador
        call(owner, post("/api/store/orders/" + orderId + "/status"), Map.of("status", "CONFIRMED"), status().isOk());
        assertThat(call(ze, get("/api/courier/jobs/open"), null, status().isOk()).get("total").asLong()).isZero();
        call(owner, post("/api/store/orders/" + orderId + "/status"), Map.of("status", "SHIPPED"), status().isUnprocessableEntity());
        call(owner, post("/api/store/orders/" + orderId + "/paid"), Map.of("paid", true), status().isOk());
        JsonNode open = call(ze, get("/api/courier/jobs/open"), null, status().isOk());
        assertThat(open.get("total").asLong()).isEqualTo(1);
        JsonNode card = open.get("items").get(0);
        assertThat(card.get("fee").decimalValue()).isEqualByComparingTo("6.00");
        assertThat(card.has("dropoffAddress")).isFalse(); // endereço do cliente só depois do aceite
        long jobId = id(card);

        // só um aceita
        JsonNode accepted = call(ze, withDevice(post("/api/courier/jobs/" + jobId + "/accept"), deviceA), null, status().isOk());
        assertThat(accepted.get("dropoffAddress").asText()).contains("Rua das Flores");
        call(bia, withDevice(post("/api/courier/jobs/" + jobId + "/accept"), deviceB), null, status().isConflict());
        assertThat(call(bia, get("/api/courier/jobs/open"), null, status().isOk()).get("total").asLong()).isZero();
        call(bia, post("/api/courier/jobs/" + jobId + "/pickup"), Map.of("code", "0000"), status().isNotFound()); // não é dela

        // códigos: a loja vê o de coleta, o cliente o de entrega, o entregador digita os dois
        JsonNode forStore = call(owner, get("/api/store/orders/" + orderId), null, status().isOk());
        JsonNode forCustomer = call(carla, get(shop.orders() + "/" + orderId), null, status().isOk());
        String pickupCode = forStore.get("courier").get("pickupCode").asText();
        String deliveryCode = forCustomer.get("courier").get("deliveryCode").asText();
        assertThat(forStore.get("courier").get("courierName").asText()).isEqualTo("Zé Moto");
        assertThat(forStore.get("courier").get("deliveryCode").isNull()).isTrue();
        assertThat(forCustomer.get("courier").get("pickupCode").isNull()).isTrue();
        call(ze, withDevice(post("/api/courier/jobs/" + jobId + "/deliver"), deviceA), Map.of("code", deliveryCode), status().isUnprocessableEntity()); // antes de coletar
        call(ze, post("/api/courier/jobs/" + jobId + "/pickup"), Map.of("code", wrong(pickupCode)), status().isUnprocessableEntity());
        call(ze, post("/api/courier/jobs/" + jobId + "/pickup"), Map.of("code", pickupCode), status().isOk());
        assertThat(call(owner, get("/api/store/orders/" + orderId), null, status().isOk()).get("status").asText()).isEqualTo("SHIPPED");
        call(ze, withDevice(post("/api/courier/jobs/" + jobId + "/deliver"), deviceA), Map.of("code", deliveryCode), status().isOk());
        assertThat(call(carla, get(shop.orders() + "/" + orderId), null, status().isOk()).get("status").asText()).isEqualTo("DELIVERED");
        JsonNode earnings = call(ze, get("/api/courier/earnings"), null, status().isOk());
        assertThat(earnings.get("today").get("count").asLong()).isEqualTo(1);
        assertThat(earnings.get("today").get("total").decimalValue()).isEqualByComparingTo("6.00");

        // entregas grátis acabaram (1 por aparelho/CPF neste teste): o Zé precisa assinar; quem troca de conta no mesmo aparelho também
        call(ze, get("/api/courier/subscription"), null, status().isOk());
        assertThat(call(ze, withDevice(get("/api/courier/subscription"), deviceA), null, status().isOk()).get("freeLeft").asInt()).isZero();
        req.put("deliveryLat", -23.56);
        long second = id(call(carla, post(shop.orders()), req, status().isCreated()));
        call(owner, post("/api/store/orders/" + second + "/paid"), Map.of("paid", true), status().isOk());
        call(owner, post("/api/store/orders/" + second + "/status"), Map.of("status", "CONFIRMED"), status().isOk());
        long job2 = id(call(ze, get("/api/courier/jobs/open"), null, status().isOk()).get("items").get(0));
        JsonNode needSub = call(ze, withDevice(post("/api/courier/jobs/" + job2 + "/accept"), deviceA), null, status().isPaymentRequired());
        assertThat(needSub.get("code").asText()).isEqualTo("SUBSCRIPTION_REQUIRED");
        String caio = registerCourier("Caio Novo", -23.56, -46.64, deviceA); // e-mail e CPF novos, mesmo aparelho
        call(admin, post("/api/platform/couriers/" + id(call(caio, get("/api/courier/me"), null, status().isOk())) + "/approve"), null,
                status().isNoContent());
        call(caio, withDevice(post("/api/courier/jobs/" + job2 + "/accept"), deviceA), null, status().isPaymentRequired());

        // aparelho novo tem as dele: a Bia aceita e desiste, ninguém aceita, a loja chama de novo; cancelar derruba a corrida
        call(bia, withDevice(post("/api/courier/jobs/" + job2 + "/accept"), deviceB), null, status().isOk());
        call(bia, post("/api/courier/jobs/" + job2 + "/cancel"), null, status().isNoContent());
        assertThat(call(ze, get("/api/courier/jobs/open"), null, status().isOk()).get("total").asLong()).isEqualTo(1);
        jdbc.update("update delivery_job set expires_at = ? where id = ?", LocalDateTime.now(clock).minusMinutes(1), job2);
        dispatch.expireOld();
        assertThat(call(owner, get("/api/store/orders/" + second), null, status().isOk()).get("courier").get("canRetry").asBoolean()).isTrue();
        call(owner, post("/api/store/orders/" + second + "/courier/retry"), null, status().isNoContent());
        assertThat(call(ze, get("/api/courier/jobs/open"), null, status().isOk()).get("total").asLong()).isEqualTo(1);

        // assinatura: o Zé gera a cobrança (a plataforma só mostra como pagar), o admin confirma e ele volta a aceitar
        JsonNode pay = call(ze, post("/api/courier/subscription/checkout"), null, status().isOk());
        assertThat(pay.get("pixKey").asText()).isEqualTo("pix@plataforma.test");
        assertThat(pay.get("amount").decimalValue()).isEqualByComparingTo("24.99");
        assertThat(call(ze, post("/api/courier/subscription/checkout"), null, status().isOk()).get("reference").asText())
                .isEqualTo(pay.get("reference").asText()); // reaproveita a cobrança em aberto
        JsonNode pending = call(admin, get("/api/platform/courier-payments"), null, status().isOk());
        JsonNode mine = null;
        for (JsonNode p : pending.get("items")) {
            if (p.get("reference").asText().equals(pay.get("reference").asText())) {
                mine = p;
            }
        }
        assertThat(mine).isNotNull();
        call(ze, withDevice(post("/api/courier/jobs/" + job2 + "/accept"), deviceA), null, status().isPaymentRequired());
        call(admin, post("/api/platform/courier-payments/" + id(mine) + "/confirm"), null, status().isNoContent());
        call(admin, post("/api/platform/courier-payments/" + id(mine) + "/confirm"), null, status().isNoContent()); // idempotente
        JsonNode sub = call(ze, withDevice(get("/api/courier/subscription"), deviceA), null, status().isOk());
        assertThat(sub.get("subscribed").asBoolean()).isTrue();
        call(ze, withDevice(post("/api/courier/jobs/" + job2 + "/accept"), deviceA), null, status().isOk());
        call(owner, post("/api/store/orders/" + second + "/status"), Map.of("status", "CANCELED"), status().isOk());
        assertThat(call(ze, get("/api/courier/jobs/active"), null, status().isOk())).isEmpty(); // pedido cancelado derruba a corrida

        // excluir a conta do entregador apaga os dados pessoais dele (e tira ele do mural)
        call(bia, post("/api/me/delete"), Map.of("password", "Senha1234"), status().isNoContent());
        assertThat(jdbc.queryForObject("select count(*) from courier where phone = '-' and status = 'BLOCKED'", Integer.class))
                .isGreaterThanOrEqualTo(1);

        // outra loja não mexe na corrida da primeira
        Shop other = openStore("Outra Loja");
        call(other.owner(), post("/api/store/orders/" + second + "/courier/retry"), null, status().isNotFound());
    }

    private int cpfSeq = 100000000;

    /** CPF válido e novo a cada chamada (o banco de teste é compartilhado e o CPF é único). */
    private String newCpf() {
        String base = String.valueOf(cpfSeq++ + (int) (System.nanoTime() % 800000));
        int[] d = new int[11];
        for (int i = 0; i < 9; i++) {
            d[i] = base.charAt(i) - '0';
        }
        for (int len = 9; len <= 10; len++) {
            int sum = 0;
            for (int i = 0; i < len; i++) {
                sum += d[i] * (len + 1 - i);
            }
            int r = (sum * 10) % 11;
            d[len] = r == 10 ? 0 : r;
        }
        StringBuilder sb = new StringBuilder();
        for (int x : d) {
            sb.append(x);
        }
        return sb.toString();
    }

    private String registerCourier(String name, double lat, double lng, String device) throws Exception {
        return registerCourier(name, lat, lng, device, newCpf(), status().isCreated()).get("token").asText();
    }

    private JsonNode registerCourier(String name, double lat, double lng, String device, String cpf, ResultMatcher expected)
            throws Exception {
        rateLimiter.reset(); // o cadastro de entregador é limitado por IP (5 por janela)
        Map<String, Object> body = new HashMap<>();
        body.put("name", name);
        body.put("email", "e-" + UUID.randomUUID() + "@entregador.test");
        body.put("phone", "11988887777");
        body.put("cpf", cpf);
        body.put("password", "Senha1234");
        body.put("vehicle", "MOTO");
        body.put("city", "Cidade Teste");
        body.put("state", "sp");
        body.put("baseLat", lat);
        body.put("baseLng", lng);
        body.put("radiusKm", 10);
        var req = post("/api/auth/register-courier");
        if (device != null) {
            req.header("X-Device-Id", device);
        }
        return call(null, req, body, expected);
    }

    private static MockHttpServletRequestBuilder withDevice(MockHttpServletRequestBuilder req, String device) {
        return req.header("X-Device-Id", device);
    }

    private static String wrong(String code) {
        return code.equals("0000") ? "1111" : "0000";
    }

    private String code(String secret) {
        return Totp.code(secret, clock.instant().getEpochSecond() / 30);
    }

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
        m.put("name", name);
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
