package com.max.loja.auth;

import java.time.Clock;

import com.max.loja.auth.AuthDtos.TwoFactorSetupResponse;
import com.max.loja.security.AuditService;
import com.max.loja.security.SecretBox;
import com.max.loja.security.Totp;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Verificação em duas etapas com app autenticador (Google Authenticator, Authy...). Recomendada para dono e
 * equipe; vale para qualquer conta. O segredo fica cifrado no banco e só é mostrado uma vez, na configuração.
 */
@Service
public class TwoFactorService {

    static final String ISSUER = "Loja Max";

    private final AppUserRepository users;
    private final SecretBox box;
    private final PasswordEncoder passwordEncoder;
    private final AuditService audit;
    private final Clock clock;

    public TwoFactorService(AppUserRepository users, SecretBox box, PasswordEncoder passwordEncoder, AuditService audit,
                            Clock clock) {
        this.users = users;
        this.box = box;
        this.passwordEncoder = passwordEncoder;
        this.audit = audit;
        this.clock = clock;
    }

    /** Gera um segredo novo (ainda desligado até confirmar com um código). */
    @Transactional
    public TwoFactorSetupResponse setup(Long userId) {
        AppUser user = find(userId);
        if (user.isTotpEnabled()) {
            throw new BusinessException("A verificação em duas etapas já está ligada.");
        }
        String secret = Totp.newSecret();
        user.setTotpSecret(box.encrypt(secret));
        return new TwoFactorSetupResponse(secret, Totp.uri(ISSUER, user.getEmail(), secret));
    }

    /** Liga depois que a pessoa digita um código certo (prova que o autenticador foi configurado). */
    @Transactional
    public void enable(Long userId, String code) {
        AppUser user = find(userId);
        if (user.getTotpSecret() == null) {
            throw new BusinessException("Comece pela configuração.");
        }
        if (!verify(user, code)) {
            throw new BusinessException("Código inválido. Confira a hora do celular e tente de novo.");
        }
        user.setTotpEnabled(true);
        audit.recordFor(user.getStoreId(), AuditService.TWO_FACTOR_ON, userId, null);
    }

    @Transactional
    public void disable(Long userId, String password, String code) {
        AppUser user = find(userId);
        if (!passwordEncoder.matches(password, user.getPasswordHash()) || !verify(user, code)) {
            throw new BusinessException("Senha ou código inválido.");
        }
        clear(user);
        audit.recordFor(user.getStoreId(), AuditService.TWO_FACTOR_OFF, userId, null);
    }

    /** Admin da plataforma desliga para quem perdeu o celular. */
    @Transactional
    public void reset(Long userId) {
        AppUser user = find(userId);
        clear(user);
        audit.recordFor(user.getStoreId(), AuditService.TWO_FACTOR_OFF, userId, "pelo admin da plataforma");
    }

    boolean verify(AppUser user, String code) {
        return user.getTotpSecret() != null && Totp.verify(box.decrypt(user.getTotpSecret()), code, clock.instant().getEpochSecond());
    }

    private static void clear(AppUser user) {
        user.setTotpEnabled(false);
        user.setTotpSecret(null);
    }

    private AppUser find(Long userId) {
        return users.findById(userId).filter(AppUser::isActive)
                .orElseThrow(() -> new NotFoundException("Usuário não encontrado"));
    }
}
