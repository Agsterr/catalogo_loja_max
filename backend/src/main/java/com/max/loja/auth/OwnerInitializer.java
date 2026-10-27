package com.max.loja.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Cria (ou atualiza a senha do) dono da loja a partir de {@code STORE_OWNER_EMAIL} e {@code STORE_OWNER_PASSWORD}.
 * A senha nunca fica no repositório: vem do .env do servidor / secrets do GitHub.
 */
@Component
class OwnerInitializer implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(OwnerInitializer.class);

    private final AppUserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final String name;
    private final String email;
    private final String password;

    OwnerInitializer(AppUserRepository users, PasswordEncoder passwordEncoder, @Value("${app.owner.name}") String name,
                     @Value("${app.owner.email}") String email, @Value("${app.owner.password}") String password) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.name = name;
        this.email = email == null ? "" : email.trim().toLowerCase();
        this.password = password == null ? "" : password;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (email.isEmpty() || password.isEmpty()) {
            return;
        }
        if (password.length() < 8) {
            log.error("STORE_OWNER_PASSWORD precisa ter pelo menos 8 caracteres; dono da loja não criado");
            return;
        }
        AppUser owner = users.findByEmailIgnoreCase(email).orElseGet(AppUser::new);
        boolean created = owner.getId() == null;
        if (!created && owner.getRole() != Role.OWNER) {
            log.error("STORE_OWNER_EMAIL já pertence a uma conta que não é de dono; nada foi alterado");
            return;
        }
        if (created || !passwordEncoder.matches(password, owner.getPasswordHash())) {
            if (!created) {
                owner.revokeTokens();
            }
            owner.setPasswordHash(passwordEncoder.encode(password));
        }
        owner.setEmail(email);
        owner.setName(owner.getName() == null ? name : owner.getName());
        owner.setRole(Role.OWNER);
        owner.setActive(true);
        users.save(owner);
        log.info(created ? "Dono da loja criado: {}" : "Dono da loja conferido: {}", email);
    }
}
