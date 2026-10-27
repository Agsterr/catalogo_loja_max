package com.max.loja.platform;

import com.max.loja.auth.AppUser;
import com.max.loja.auth.AppUserRepository;
import com.max.loja.auth.Role;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Cria (ou atualiza a senha do) administrador da plataforma a partir de {@code PLATFORM_ADMIN_EMAIL} e
 * {@code PLATFORM_ADMIN_PASSWORD}. A senha nunca fica no repositório: vem do .env do servidor.
 */
@Component
class PlatformAdminInitializer implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(PlatformAdminInitializer.class);

    private final AppUserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final String email;
    private final String password;

    PlatformAdminInitializer(AppUserRepository users, PasswordEncoder passwordEncoder,
                             @Value("${app.platform-admin.email}") String email,
                             @Value("${app.platform-admin.password}") String password) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.email = email == null ? "" : email.trim().toLowerCase();
        this.password = password == null ? "" : password;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (email.isEmpty() || password.isEmpty()) {
            return;
        }
        if (password.length() < 12) {
            log.error("PLATFORM_ADMIN_PASSWORD precisa ter pelo menos 12 caracteres; admin não criado");
            return;
        }
        AppUser admin = users.findByEmailIgnoreCase(email).orElseGet(AppUser::new);
        boolean created = admin.getId() == null;
        if (!created && admin.getRole() != Role.PLATFORM_ADMIN) {
            log.error("PLATFORM_ADMIN_EMAIL já pertence a outra conta; nada foi alterado");
            return;
        }
        if (created || !passwordEncoder.matches(password, admin.getPasswordHash())) {
            if (!created) {
                admin.revokeTokens();
            }
            admin.setPasswordHash(passwordEncoder.encode(password));
        }
        admin.setEmail(email);
        admin.setName(admin.getName() == null ? "Administrador" : admin.getName());
        admin.setRole(Role.PLATFORM_ADMIN);
        admin.setStoreId(null);
        admin.setActive(true);
        users.save(admin);
        log.info(created ? "Admin da plataforma criado: {}" : "Admin da plataforma conferido: {}", email);
    }
}
