package com.max.loja.auth;

import com.max.loja.push.PushDeviceRepository;
import com.max.loja.security.AccountStatusService;
import com.max.loja.security.AuditService;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Exclusão de conta pelo próprio cliente (exigência da Google Play e da App Store / LGPD). Os pedidos ficam
 * para a contabilidade da loja, mas sem os dados pessoais: nome, e-mail, telefone e endereços são apagados.
 */
@Service
public class AccountDeletionService {

    private final AppUserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final PushDeviceRepository devices;
    private final AccountStatusService statuses;
    private final JdbcTemplate jdbc;
    private final AuditService audit;

    public AccountDeletionService(AppUserRepository users, PasswordEncoder passwordEncoder, PushDeviceRepository devices,
                                  AccountStatusService statuses, JdbcTemplate jdbc, AuditService audit) {
        this.audit = audit;
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.devices = devices;
        this.statuses = statuses;
        this.jdbc = jdbc;
    }

    @Transactional
    public void delete(Long userId, String password) {
        AppUser user = users.findById(userId).filter(AppUser::isActive)
                .orElseThrow(() -> new NotFoundException("Usuário não encontrado"));
        if (!passwordEncoder.matches(password, user.getPasswordHash())) {
            throw new BusinessException("Senha incorreta.");
        }
        if (user.getRole() == Role.OWNER || user.getRole() == Role.PLATFORM_ADMIN) {
            throw new BusinessException("Esta conta não pode ser excluída pelo app. Fale com o suporte.");
        }
        jdbc.update("update orders set address = null, notes = null where customer_id = ?", userId);
        jdbc.update("delete from notification where user_id = ?", userId);
        jdbc.update("delete from password_reset where user_id = ?", userId);
        devices.deleteByUserId(userId);
        user.setActive(false);
        user.setName("Conta excluída");
        user.setEmail("excluido-" + userId + "@loja.invalid");
        user.setPhone(null);
        user.setPasswordHash("!");
        user.revokeTokens();
        statuses.evict(userId);
        audit.recordFor(user.getStoreId(), AuditService.ACCOUNT_DELETED, userId, null);
    }
}
