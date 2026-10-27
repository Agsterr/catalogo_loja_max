package com.max.loja.auth;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.auth.AuthDtos.CreateStaffRequest;
import com.max.loja.auth.AuthDtos.UserResponse;
import com.max.loja.push.PushDeviceRepository;
import com.max.loja.security.AccountStatusService;
import com.max.loja.security.AuditService;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import com.max.loja.shared.TenantContext;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Equipe da loja e clientes que compraram nela (com bloqueio só nesta loja). */
@Service
public class StaffService {

    /** Cliente visto pela loja: só quem já fez pedido aqui. {@code blocked} = bloqueado por esta loja. */
    public record CustomerResponse(Long id, String name, String email, String phone, long orders, boolean blocked,
                                   String blockedReason, LocalDateTime createdAt) {
    }

    private final AppUserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final AccountStatusService statuses;
    private final PushDeviceRepository devices;
    private final AuditService audit;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    public StaffService(AppUserRepository users, PasswordEncoder passwordEncoder, AccountStatusService statuses,
                        PushDeviceRepository devices, AuditService audit, JdbcTemplate jdbc, Clock clock) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.statuses = statuses;
        this.devices = devices;
        this.audit = audit;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<UserResponse> team() {
        return users.findByStoreIdAndActiveTrueOrderByName(TenantContext.get()).stream().map(UserResponse::from).toList();
    }

    @Transactional
    public UserResponse create(CreateStaffRequest req) {
        if (req.role() != Role.STAFF && req.role() != Role.OWNER) {
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
        user.setStoreId(TenantContext.get());
        user.setCreatedAt(LocalDateTime.now(clock));
        users.save(user);
        audit.record(AuditService.STAFF_CREATED, user.getId(), user.getEmail() + " (" + user.getRole() + ")");
        return UserResponse.from(user);
    }

    /** Desativa o funcionário: tokens dele param na hora e o celular dele deixa de receber os avisos da loja. */
    @Transactional
    public void remove(Long actorId, Long userId) {
        AppUser user = users.findById(userId)
                .filter(u -> u.getRole() == Role.STAFF && u.isActive() && TenantContext.get().equals(u.getStoreId()))
                .orElseThrow(() -> new NotFoundException("Funcionário não encontrado"));
        if (user.getId().equals(actorId)) {
            throw new BusinessException("Você não pode remover a si mesmo");
        }
        String email = user.getEmail();
        user.setActive(false);
        user.setEmail("removido-" + user.getId() + "@loja.invalid");
        user.revokeTokens();
        devices.deleteByUserId(user.getId());
        statuses.evict(user.getId());
        audit.record(AuditService.STAFF_REMOVED, actorId, email);
    }

    @Transactional(readOnly = true)
    public PageResponse<CustomerResponse> customers(String q, Integer page, Integer size) {
        Long tenant = TenantContext.get();
        String like = "%" + (q == null ? "" : q.trim().toLowerCase().replace("%", "")) + "%";
        PageRequest req = PageResponse.request(page, size, Sort.unsorted());
        String from = """
                from app_user u join (select customer_id, count(*) n from orders where tenant_id = ? group by customer_id) o
                  on o.customer_id = u.id
                left join store_customer_block b on b.user_id = u.id and b.tenant_id = ?
                where u.active and (lower(u.name) like ? or lower(u.email) like ? or coalesce(u.phone, '') like ?)""";
        Long total = jdbc.queryForObject("select count(*) " + from, Long.class, tenant, tenant, like, like, like);
        List<CustomerResponse> items = jdbc.query("""
                select u.id, u.name, u.email, u.phone, o.n, b.user_id is not null as blocked, b.reason, u.created_at
                """ + from + " order by u.name, u.id limit ? offset ?",
                (rs, i) -> new CustomerResponse(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4),
                        rs.getLong(5), rs.getBoolean(6), rs.getString(7), rs.getTimestamp(8).toLocalDateTime()),
                tenant, tenant, like, like, like, req.getPageSize(), req.getOffset());
        return PageResponse.of(new PageImpl<>(items, req, total == null ? 0 : total), c -> c);
    }

    /**
     * Bloqueia um cliente só nesta loja (ex.: pedidos falsos): ele continua comprando nas outras. Bloqueio geral
     * é do admin da plataforma.
     */
    @Transactional
    public void block(Long actorId, Long customerId, String reason, boolean blocked) {
        AppUser user = users.findById(customerId).filter(u -> u.getRole() == Role.CUSTOMER && u.isActive())
                .orElseThrow(() -> new NotFoundException("Cliente não encontrado"));
        Long tenant = TenantContext.get();
        if (blocked) {
            jdbc.update("""
                    insert into store_customer_block (tenant_id, user_id, reason, created_at) values (?, ?, ?, ?)
                    on conflict (tenant_id, user_id) do update set reason = excluded.reason""",
                    tenant, user.getId(), AuthService.blankToNull(reason), LocalDateTime.now(clock));
        } else {
            jdbc.update("delete from store_customer_block where tenant_id = ? and user_id = ?", tenant, user.getId());
        }
        audit.record(blocked ? AuditService.CUSTOMER_BLOCKED : AuditService.CUSTOMER_UNBLOCKED, actorId,
                user.getEmail() + (reason == null || reason.isBlank() ? "" : ": " + reason.trim()));
    }

    /** Motivo do bloqueio deste cliente nesta loja; nulo = pode comprar. */
    @Transactional(readOnly = true)
    public java.util.Optional<String> blockReason(Long customerId) {
        List<String> r = jdbc.query("select coalesce(reason, '') from store_customer_block where tenant_id = ? and user_id = ?",
                (rs, i) -> rs.getString(1), TenantContext.get(), customerId);
        return r.stream().findFirst();
    }
}
