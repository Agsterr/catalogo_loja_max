package com.max.loja.security;

import java.nio.ByteBuffer;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** Códigos de 6 dígitos que mudam a cada 30 s (RFC 6238), os mesmos do Google Authenticator / Authy. */
public final class Totp {

    private static final String BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    private static final SecureRandom RANDOM = new SecureRandom();

    private Totp() {
    }

    /** Segredo novo (160 bits) em base32. */
    public static String newSecret() {
        byte[] raw = new byte[20];
        RANDOM.nextBytes(raw);
        return base32(raw);
    }

    /** Aceita o código atual e o vizinho (relógio do celular um pouco adiantado/atrasado). */
    public static boolean verify(String secret, String code, long epochSeconds) {
        if (code == null || !code.trim().matches("\\d{6}")) {
            return false;
        }
        long step = epochSeconds / 30;
        for (long s = step - 1; s <= step + 1; s++) {
            if (constantTimeEquals(code(secret, s), code.trim())) {
                return true;
            }
        }
        return false;
    }

    public static String code(String secret, long step) {
        try {
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(fromBase32(secret), "HmacSHA1"));
            byte[] h = mac.doFinal(ByteBuffer.allocate(8).putLong(step).array());
            int offset = h[h.length - 1] & 0x0f;
            int bin = ((h[offset] & 0x7f) << 24) | ((h[offset + 1] & 0xff) << 16) | ((h[offset + 2] & 0xff) << 8)
                    | (h[offset + 3] & 0xff);
            return String.format("%06d", bin % 1_000_000);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Link que o app autenticador entende. */
    public static String uri(String issuer, String account, String secret) {
        String label = (issuer + ":" + account).replace(" ", "%20");
        return "otpauth://totp/" + label + "?secret=" + secret + "&issuer=" + issuer.replace(" ", "%20")
                + "&algorithm=SHA1&digits=6&period=30";
    }

    static String base32(byte[] data) {
        StringBuilder sb = new StringBuilder();
        int buffer = 0;
        int bits = 0;
        for (byte b : data) {
            buffer = (buffer << 8) | (b & 0xff);
            bits += 8;
            while (bits >= 5) {
                sb.append(BASE32.charAt((buffer >> (bits - 5)) & 31));
                bits -= 5;
            }
        }
        if (bits > 0) {
            sb.append(BASE32.charAt((buffer << (5 - bits)) & 31));
        }
        return sb.toString();
    }

    static byte[] fromBase32(String s) {
        String clean = s.replace("=", "").replace(" ", "").toUpperCase();
        ByteBuffer out = ByteBuffer.allocate(clean.length() * 5 / 8);
        int buffer = 0;
        int bits = 0;
        for (char c : clean.toCharArray()) {
            int v = BASE32.indexOf(c);
            if (v < 0) {
                throw new IllegalArgumentException("base32 inválido");
            }
            buffer = (buffer << 5) | v;
            bits += 5;
            if (bits >= 8) {
                out.put((byte) ((buffer >> (bits - 8)) & 0xff));
                bits -= 8;
            }
        }
        return java.util.Arrays.copyOf(out.array(), out.position());
    }

    private static boolean constantTimeEquals(String a, String b) {
        return java.security.MessageDigest.isEqual(a.getBytes(), b.getBytes());
    }
}
