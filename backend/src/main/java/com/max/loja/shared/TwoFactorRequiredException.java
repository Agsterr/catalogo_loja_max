package com.max.loja.shared;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;

/** Login certo, mas a conta tem verificação em duas etapas: o app pede o código (401, {@code code: TOTP_REQUIRED}). */
public class TwoFactorRequiredException extends RuntimeException {

    public static final String CODE = "TOTP_REQUIRED";

    public TwoFactorRequiredException() {
        super("Digite o código do seu app autenticador.");
    }

    public ProblemDetail toProblem() {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, getMessage());
        problem.setProperty("code", CODE);
        return problem;
    }
}
