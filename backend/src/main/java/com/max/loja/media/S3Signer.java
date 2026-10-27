package com.max.loja.media;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Assinatura AWS Signature V4 (a mesma que o Cloudflare R2 aceita). Feita à mão para não trazer o
 * AWS SDK inteiro: a API roda com metaspace de 128 MB e só precisa de PUT e DELETE de objetos.
 */
final class S3Signer {

    private static final HexFormat HEX = HexFormat.of();

    private S3Signer() {
    }

    /**
     * Valor do header Authorization.
     *
     * @param headers headers assinados (nomes em minúsculas), incluindo {@code host},
     *                {@code x-amz-date} e {@code x-amz-content-sha256}
     */
    static String authorization(String method, URI uri, Map<String, String> headers, String payloadSha256,
                                String region, String accessKey, String secretKey) {
        TreeMap<String, String> sorted = new TreeMap<>(headers);
        String amzDate = sorted.get("x-amz-date");
        String date = amzDate.substring(0, 8);
        String canonicalHeaders = sorted.entrySet().stream()
                .map(e -> e.getKey() + ":" + e.getValue().trim() + "\n")
                .collect(Collectors.joining());
        String signedHeaders = String.join(";", sorted.keySet());
        String canonicalRequest = String.join("\n", method, canonicalPath(uri.getRawPath()),
                uri.getRawQuery() == null ? "" : uri.getRawQuery(), canonicalHeaders, signedHeaders, payloadSha256);
        String scope = date + "/" + region + "/s3/aws4_request";
        String stringToSign = String.join("\n", "AWS4-HMAC-SHA256", amzDate, scope,
                sha256Hex(canonicalRequest.getBytes(StandardCharsets.UTF_8)));

        byte[] key = hmac(("AWS4" + secretKey).getBytes(StandardCharsets.UTF_8), date);
        key = hmac(key, region);
        key = hmac(key, "s3");
        key = hmac(key, "aws4_request");
        String signature = HEX.formatHex(hmac(key, stringToSign));
        return "AWS4-HMAC-SHA256 Credential=" + accessKey + "/" + scope + ",SignedHeaders=" + signedHeaders
                + ",Signature=" + signature;
    }

    static String sha256Hex(byte[] data) {
        try {
            return HEX.formatHex(MessageDigest.getInstance("SHA-256").digest(data));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Codifica cada segmento do caminho (letras, números e "-_.~" ficam como estão). */
    static String encodeKey(String key) {
        StringBuilder sb = new StringBuilder();
        for (byte b : key.getBytes(StandardCharsets.UTF_8)) {
            char c = (char) (b & 0xff);
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
                    || c == '-' || c == '_' || c == '.' || c == '~' || c == '/') {
                sb.append(c);
            } else {
                sb.append('%').append(String.format("%02X", b & 0xff));
            }
        }
        return sb.toString();
    }

    private static String canonicalPath(String rawPath) {
        return rawPath == null || rawPath.isEmpty() ? "/" : rawPath;
    }

    private static byte[] hmac(byte[] key, String data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }
}
