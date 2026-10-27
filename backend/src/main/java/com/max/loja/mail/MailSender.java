package com.max.loja.mail;

/** Envio de e-mail transacional (recuperar senha, avisos). */
public interface MailSender {

    /** @throws MailException se o provedor recusar ou não responder */
    void send(String to, String subject, String html, String text);

    class MailException extends RuntimeException {

        public MailException(String message) {
            super(message);
        }

        public MailException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
