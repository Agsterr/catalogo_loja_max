package com.max.loja.shared;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.interfaces.RSAPrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.function.Supplier;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

/** Token OAuth2 de uma conta de serviço do Google (JWT assinado), guardado até perto de vencer. */
public class GoogleAccessToken {

    private final ObjectMapper json;
    private final Supplier<String> accountJson;
    private final String scope;
    private final HttpClient http;

    private String token;
    private Instant expiry = Instant.EPOCH;

    public GoogleAccessToken(ObjectMapper json, Supplier<String> accountJson, String scope, HttpClient http) {
        this.json = json;
        this.accountJson = accountJson;
        this.scope = scope;
        this.http = http;
    }

    public synchronized String get() throws IOException, InterruptedException {
        if (token != null && Instant.now().isBefore(expiry.minusSeconds(60))) {
            return token;
        }
        JsonNode account = json.readTree(accountJson.get());
        String tokenUri = account.path("token_uri").asText("https://oauth2.googleapis.com/token");
        try {
            Instant now = Instant.now();
            JWTClaimsSet claims = new JWTClaimsSet.Builder()
                    .issuer(account.path("client_email").asText())
                    .claim("scope", scope)
                    .audience(tokenUri)
                    .issueTime(Date.from(now))
                    .expirationTime(Date.from(now.plusSeconds(3600)))
                    .build();
            SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.RS256), claims);
            jwt.sign(new RSASSASigner(privateKey(account.path("private_key").asText())));
            String form = "grant_type=" + encode("urn:ietf:params:oauth:grant-type:jwt-bearer") + "&assertion=" + encode(jwt.serialize());
            HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(tokenUri)).timeout(Duration.ofSeconds(15))
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .POST(HttpRequest.BodyPublishers.ofString(form)).build(), HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() / 100 != 2) {
                throw new IllegalStateException("Google recusou a conta de serviço (" + res.statusCode() + "): " + res.body());
            }
            JsonNode body = json.readTree(res.body());
            token = body.path("access_token").asText();
            expiry = now.plusSeconds(body.path("expires_in").asLong(3600));
            return token;
        } catch (java.security.GeneralSecurityException | com.nimbusds.jose.JOSEException e) {
            throw new IllegalStateException("Chave da conta de serviço inválida", e);
        }
    }

    private static RSAPrivateKey privateKey(String pem) throws java.security.GeneralSecurityException {
        String body = pem.replace("-----BEGIN PRIVATE KEY-----", "").replace("-----END PRIVATE KEY-----", "").replaceAll("\\s", "");
        return (RSAPrivateKey) KeyFactory.getInstance("RSA")
                .generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(body)));
    }

    private static String encode(String v) {
        return URLEncoder.encode(v, StandardCharsets.UTF_8);
    }
}
