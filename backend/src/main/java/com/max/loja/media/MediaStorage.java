package com.max.loja.media;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/** Grava e apaga arquivos de mídia no Cloudflare R2 ou, sem R2 configurado, no disco local. */
@Service
public class MediaStorage {

    private static final Logger log = LoggerFactory.getLogger(MediaStorage.class);
    private static final DateTimeFormatter AMZ_DATE = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'");
    /** Os nomes são aleatórios e nunca reaproveitados: o navegador pode guardar para sempre. */
    private static final String CACHE = "public, max-age=31536000, immutable";

    private final MediaProperties props;
    private final String localBaseUrl;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    public MediaStorage(MediaProperties props) {
        this.props = props;
        this.localBaseUrl = props.publicBaseUrl() + "/api/public/media/";
        log.info("Fotos dos produtos: {}", props.r2Enabled() ? "Cloudflare R2 (" + props.r2Bucket() + ")"
                : "disco local (" + props.storagePath() + ")");
    }

    public boolean usingR2() {
        return props.r2Enabled();
    }

    /** Grava e devolve a URL pública. */
    public String put(String key, byte[] data, String contentType) {
        if (props.r2Enabled()) {
            send("PUT", key, data, contentType);
            return props.r2PublicBaseUrl() + "/" + S3Signer.encodeKey(key);
        }
        try {
            Path file = localFile(key);
            Files.createDirectories(file.getParent());
            Files.write(file, data);
        } catch (IOException e) {
            throw new UncheckedIOException("Não foi possível gravar a foto", e);
        }
        return localBaseUrl + key;
    }

    /** Apaga (melhor esforço: arquivo que sobrou não quebra nada). */
    public void delete(String key) {
        try {
            if (props.r2Enabled()) {
                send("DELETE", key, new byte[0], null);
            } else {
                Files.deleteIfExists(localFile(key));
            }
        } catch (RuntimeException | IOException e) {
            log.warn("Não foi possível apagar a mídia {}: {}", key, e.getMessage());
        }
    }

    Path localFile(String key) {
        Path root = Path.of(props.storagePath()).toAbsolutePath().normalize();
        Path file = root.resolve(key).normalize();
        if (!file.startsWith(root)) {
            throw new IllegalArgumentException("Caminho inválido");
        }
        return file;
    }

    private void send(String method, String key, byte[] data, String contentType) {
        URI uri = URI.create(props.r2Endpoint() + "/" + props.r2Bucket() + "/" + S3Signer.encodeKey(key));
        String payloadHash = S3Signer.sha256Hex(data);
        String amzDate = AMZ_DATE.format(ZonedDateTime.now(ZoneOffset.UTC));
        String host = uri.getPort() > 0 ? uri.getHost() + ":" + uri.getPort() : uri.getHost();
        String auth = S3Signer.authorization(method, uri,
                Map.of("host", host, "x-amz-date", amzDate, "x-amz-content-sha256", payloadHash),
                payloadHash, "auto", props.r2AccessKeyId(), props.r2SecretAccessKey());
        HttpRequest.Builder req = HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(30))
                .header("x-amz-date", amzDate)
                .header("x-amz-content-sha256", payloadHash)
                .header("Authorization", auth)
                .method(method, data.length == 0 ? HttpRequest.BodyPublishers.noBody()
                        : HttpRequest.BodyPublishers.ofByteArray(data));
        if (contentType != null) {
            req.header("Content-Type", contentType).header("Cache-Control", CACHE);
        }
        try {
            HttpResponse<String> res = http.send(req.build(), HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() / 100 != 2) {
                // o corpo do erro do R2 não contém segredo (só código e mensagem)
                throw new IllegalStateException("R2 respondeu " + res.statusCode() + ": "
                        + res.body().substring(0, Math.min(300, res.body().length())));
            }
        } catch (IOException e) {
            throw new UncheckedIOException("Falha ao falar com o R2", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Envio ao R2 interrompido", e);
        }
    }
}
