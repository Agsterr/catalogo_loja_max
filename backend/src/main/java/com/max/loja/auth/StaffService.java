package com.max.loja.auth;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.auth.AuthDtos.CreateStaffRequest;
import com.max.loja.auth.AuthDtos.UserResponse;
import com.max.loja.push.PushDeviceRepository;
import com.max.loja.security.AccountStatusService;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import org.springframework.data.domain.Sort;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Equipe (dono cria funcionários) e bloqueio de contas pela loja. */
@Service
public class StaffService {

    private final AppUserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final AccountStatusService statuses;
    private final PushDeviceRepository devices;
    private final Clock clock;

    public StaffService(AppUserRepository users, PasswordEncoder passwordEncoder, AccountStatusService statuses,
                        PushDeviceRepository devices, Clock clock) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.statuses = statuses;
        this.devices = devices;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<UserResponse> team() {
        return users.findByRoleInAndActiveTrueOrderByName(List.of(Role.OWNER, Role.STAFF)).stream()
                .map(UserResponse::from).toList();
    }

    @Transactional
    public UserResponse create(CreateStaffRequest req) {
        if (!req.role().isTeam()) {
            throw new BusinessException("Papel inválido para a equipe");
        }
        if (users.existsByEmailIgnoreCase(req.email().trim())) {
            throw new BusinessException("E-mail já cadastrado");
        }
        AppUser user = new AppUser();
        user.setName(req.name().trim());
        user.setEmail(req.email().trim().toLowerCase());
        user.setPasswordHash(passwordEncoder.encode(req.password()));
        user.setRole(req.role());
        user.setCreatedAt(LocalDateTime.now(clock));
        return UserResponse.from(users.save(user));
    }

    /** Desativa o funcionário: tokens dele param na hora e o celular dele deixa de receber os avisos da loja. */
    @Transactional
    public void remove(Long actorId, Long userId) {
        AppUser user = users.findById(userId).filter(u -> u.getRole() == Role.STAFF && u.isActive())
                .orElseThrow(() -> new NotFoundException("Funcionário não encontrado"));
        if (user.getId().equals(actorId)) {
            throw new BusinessException("Você não pode remover a si mesmo");
        }
        user.setActive(false);
        user.setEmail("removido-" + user.getId() + "@loja.invalid");
        user.revokeTokens();
        devices.deleteByUserId(user.getId());
        statuses.evict(user.getId());
    }

    @Transactional(readOnly = true)
    public PageResponse<UserResponse> customers(String q, Integer page, Integer size) {
        return PageResponse.of(users.searchCustomers(q == null ? "" : q.trim(),
                PageResponse.request(page, size, Sort.by("name"))), UserResponse::from);
    }

    /** Bloqueia um cliente (ex.: pedidos falsos). Tokens já emitidos param de valer na próxima requisição. */
    @Transactional
    public UserResponse block(Long customerId, String reason, boolean blocked) {
        AppUser user = users.findById(customerId).filter(u -> u.getRole() == Role.CUSTOMER && u.isActive())
                .orElseThrow(() -> new NotFoundException("Cliente não encontrado"));
        user.setBlocked(blocked);
        user.setBlockedReason(blocked ? AuthService.blankToNull(reason) : null);
        user.setBlockedAt(blocked ? LocalDateTime.now(clock) : null);
        statuses.evict(user.getId());
        return UserResponse.from(user);
    }
}
