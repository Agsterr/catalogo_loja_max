package com.max.loja.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.HexFormat;
import java.util.List;

import com.max.loja.mail.MailSender;
import com.max.loja.security.AccountStatusService;
import com.max.loja.security.AuditService;
import com.max.loja.shared.BusinessException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.util.HtmlUtils;

/**
 * "Esqueci minha senha": manda por e-mail um código que vale 1 hora e um único uso. O código vai só no e-mail;
 * no banco fica o hash. A resposta é sempre a mesma, exista ou não a conta (não revela quem tem cadastro).
 */
@Service
public class PasswordResetService {

    private static final Logger log = LoggerFactory.getLogger(PasswordResetService.class);
    static final long VALID_MINUTES = 60;
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final int CODE_LENGTH = 8;

    private final AppUserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final JdbcTemplate jdbc;
    private final MailSender mail;
    private final Clock clock;
    private final AccountStatusService statuses;
    private final AuditService audit;
    private final SecureRandom random = new SecureRandom();

    public PasswordResetService(AppUserRepository users, PasswordEncoder passwordEncoder, JdbcTemplate jdbc,
                                MailSender mail, Clock clock,
                                AccountStatusService statuses, AuditService audit) {
        this.statuses = statuses;
        this.audit = audit;
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.jdbc = jdbc;
        this.mail = mail;
        this.clock = clock;
    }

    @Transactional
    public void request(String email) {
        AppUser user = users.findByEmailIgnoreCase(email.trim())
                .filter(AppUser::isActive)
                .filter(u -> !u.isBlocked())
                // a senha do admin da plataforma só muda no servidor (PLATFORM_ADMIN_PASSWORD)
                .filter(u -> u.getRole() != Role.PLATFORM_ADMIN)
                .orElse(null);
        if (user == null) {
            return;
        }
        String code = newCode();

        jdbc.update("delete from password_reset where user_id = ? and used_at is null", user.getId());
        jdbc.update("insert into password_reset (user_id, token_hash, expires_at) values (?, ?, ?)", user.getId(),
                hash(code), LocalDateTime.now(clock).plusMinutes(VALID_MINUTES));

        String firstName = user.getName().split(" ")[0];
        String text = "Olá, " + firstName + "!\n\n"
                + "Recebemos um pedido para redefinir a senha da sua conta na Loja Max. Digite este código no app "
                + "(vale por 1 hora):\n\n" + code + "\n\nSe não foi você, ignore este e-mail: sua senha continua a mesma.";
        String html = "<p>Olá, " + HtmlUtils.htmlEscape(firstName) + "!</p>"
                + "<p>Recebemos um pedido para redefinir a senha da sua conta na <strong>Loja Max</strong>. "
                + "Digite este código no app:</p>"
                + "<p style=\"font-size:28px;font-weight:bold;letter-spacing:6px;color:#B0306A\">" + code + "</p>"
                + "<p>O código vale por 1 hora. Se não foi você, ignore este e-mail: sua senha continua a mesma.</p>";
        try {
            mail.send(user.getEmail(), "Redefinir sua senha — Loja Max", html, text);
        } catch (MailSender.MailException e) {
            // não revela ao usuário se deu certo; o erro fica no log para o administrador
            log.error("Falha ao enviar e-mail de recuperação de senha: {}", e.getMessage());
        }
    }

    @Transactional
    public void reset(String email, String code, String newPassword) {
        List<Long[]> rows = jdbc.query("""
                select id, user_id from password_reset
                where token_hash = ? and used_at is null and expires_at > ?
                and user_id = (select id from app_user where lower(email) = lower(?))""",
                (rs, i) -> new Long[] {rs.getLong(1), rs.getLong(2)}, hash(normalize(code)), LocalDateTime.now(clock),
                email.trim());
        if (rows.isEmpty()) {
            throw new BusinessException("Código inválido ou vencido. Peça um novo em \"Esqueci minha senha\".");
        }
        Long[] row = rows.get(0);
        AppUser user = users.findById(row[1]).orElseThrow(() -> new BusinessException("Código inválido ou vencido."));
        user.setPasswordHash(passwordEncoder.encode(newPassword));
        // quem tinha a senha antiga (ou um token roubado) sai de todos os aparelhos
        user.revokeTokens();
        user.setFailedLogins(0);
        user.setLockedUntil(null);
        statuses.evict(user.getId());
        audit.recordFor(user.getStoreId(), AuditService.PASSWORD_RESET, user.getId(), "pelo código do e-mail");
        jdbc.update("update password_reset set used_at = ? where id = ?", LocalDateTime.now(clock), row[0]);
        jdbc.update("delete from password_reset where user_id = ? and used_at is null", user.getId());
    }

    /** Código de 8 caracteres sem letras que confundem (0/O, 1/I): ~40 bits, com limite de tentativas por IP e e-mail. */
    private String newCode() {
        StringBuilder sb = new StringBuilder(CODE_LENGTH);
        for (int i = 0; i < CODE_LENGTH; i++) {
            sb.append(ALPHABET.charAt(random.nextInt(ALPHABET.length())));
        }
        return sb.toString();
    }

    private static String normalize(String code) {
        return code.trim().toUpperCase().replace(" ", "").replace("-", "");
    }

    private static String hash(String token) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
