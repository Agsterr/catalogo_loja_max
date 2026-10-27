package com.max.loja.shared;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;

/** Entregador sem entregas grátis e sem assinatura: HTTP 402 com {@code "code": "SUBSCRIPTION_REQUIRED"} (o app abre a assinatura). */
public class SubscriptionRequiredException extends RuntimeException {

    public static final String CODE = "SUBSCRIPTION_REQUIRED";

    public SubscriptionRequiredException(String message) {
        super(message);
    }

    public ProblemDetail toProblem() {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.PAYMENT_REQUIRED, getMessage());
        problem.setProperty("code", CODE);
        return problem;
    }
}
