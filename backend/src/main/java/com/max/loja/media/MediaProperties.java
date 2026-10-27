package com.max.loja.media;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Onde ficam as fotos dos produtos. Com as cinco variáveis do R2 preenchidas, vão para o Cloudflare R2
 * (mesmo esquema do Gerenciamento Max); faltando qualquer uma, vão para o disco ({@code APP_MEDIA_PATH},
 * volume em produção) e são servidas em /api/public/media/**.
 *
 * @param storagePath         pasta local ({@code APP_MEDIA_PATH})
 * @param publicBaseUrl       endereço público da API, base das URLs das fotos no disco ({@code APP_PUBLIC_URL})
 * @param maxPhotosPerProduct limite de fotos por produto
 * @param r2Bucket            {@code R2_BUCKET}
 * @param r2Endpoint          {@code R2_ENDPOINT} (https://ACCOUNT_ID.r2.cloudflarestorage.com)
 * @param r2AccessKeyId       {@code R2_ACCESS_KEY_ID}
 * @param r2SecretAccessKey   {@code R2_SECRET_ACCESS_KEY}
 * @param r2PublicBaseUrl     {@code R2_PUBLIC_BASE_URL} (domínio público do bucket, ex.: https://pub-xxx.r2.dev)
 */
@ConfigurationProperties("app.media")
public record MediaProperties(String storagePath, String publicBaseUrl, int maxPhotosPerProduct, String r2Bucket,
                              String r2Endpoint, String r2AccessKeyId, String r2SecretAccessKey, String r2PublicBaseUrl) {

    public MediaProperties {
        if (storagePath == null || storagePath.isBlank()) {
            storagePath = "/app/media";
        }
        publicBaseUrl = trim(publicBaseUrl).replaceAll("/+$", "");
        if (maxPhotosPerProduct < 1) {
            maxPhotosPerProduct = 8;
        }
        r2Bucket = trim(r2Bucket);
        r2Endpoint = trim(r2Endpoint).replaceAll("/+$", "");
        r2AccessKeyId = trim(r2AccessKeyId);
        r2SecretAccessKey = trim(r2SecretAccessKey);
        r2PublicBaseUrl = trim(r2PublicBaseUrl).replaceAll("/+$", "");
    }

    public boolean r2Enabled() {
        return !r2Bucket.isEmpty() && !r2Endpoint.isEmpty() && !r2AccessKeyId.isEmpty()
                && !r2SecretAccessKey.isEmpty() && !r2PublicBaseUrl.isEmpty();
    }

    private static String trim(String s) {
        return s == null ? "" : s.trim();
    }
}
