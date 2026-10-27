package com.max.loja.shared;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;

/** Usuário bloqueado pela loja: HTTP 403 com {@code "code": "ACCOUNT_BLOCKED"} (o app mostra a tela de bloqueio). */
public class AccountBlockedException extends RuntimeException {

    public static final String CODE = "ACCOUNT_BLOCKED";

    public AccountBlockedException(String reason) {
        super(reason == null || reason.isBlank() ? "Sua conta foi bloqueada." : reason);
    }

    public ProblemDetail toProblem() {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, getMessage());
        problem.setProperty("code", CODE);
        return problem;
    }
}
