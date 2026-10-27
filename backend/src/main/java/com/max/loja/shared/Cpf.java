package com.max.loja.shared;

/** CPF: só dígitos e conferência dos dois dígitos verificadores. */
public final class Cpf {

    private Cpf() {
    }

    /** Só os 11 dígitos, ou {@code null} se o CPF for inválido. */
    public static String normalize(String raw) {
        if (raw == null) {
            return null;
        }
        String d = raw.replaceAll("\\D", "");
        if (d.length() != 11 || d.chars().distinct().count() == 1) {
            return null;
        }
        return check(d, 9) == d.charAt(9) - '0' && check(d, 10) == d.charAt(10) - '0' ? d : null;
    }

    private static int check(String d, int len) {
        int sum = 0;
        for (int i = 0; i < len; i++) {
            sum += (d.charAt(i) - '0') * (len + 1 - i);
        }
        int r = (sum * 10) % 11;
        return r == 10 ? 0 : r;
    }

    /** "***.456.789-**": o app mostra sem expor o número todo. */
    public static String mask(String digits) {
        return digits == null || digits.length() != 11 ? null : "***." + digits.substring(3, 6) + "." + digits.substring(6, 9) + "-**";
    }
}
