package com.max.loja.platform;

import java.time.Clock;
import java.time.LocalDateTime;

import com.max.loja.auth.AppUser;
import com.max.loja.auth.AppUserRepository;
import com.max.loja.auth.AuthDtos.BlockRequest;
import com.max.loja.auth.AuthDtos.UserResponse;
import com.max.loja.auth.Role;
import com.max.loja.auth.TwoFactorService;
import com.max.loja.security.AccountStatusService;
import com.max.loja.security.AuditService;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import com.max.loja.shared.Search;
import com.max.loja.store.Store;
import com.max.loja.store.StoreRepository;
import jakarta.validation.Valid;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Administração da plataforma: lojas e contas (bloqueio vale na hora, inclusive para tokens já emitidos). */
@RestController
public class PlatformController {

    public record StoreAdminResponse(Long id, String slug, String name, boolean blocked, String blockedReason,
                                     LocalDateTime createdAt, long products, long orders) {
    }

    private final StoreRepository stores;
    private final AppUserRepository users;
    private final AccountStatusService statuses;
    private final TwoFactorService twoFactor;
    private final AuditService audit;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    public PlatformController(StoreRepository stores, AppUserRepository users, AccountStatusService statuses,
                              TwoFactorService twoFactor, AuditService audit, JdbcTemplate jdbc, Clock clock) {
        this.stores = stores;
        this.users = users;
        this.statuses = statuses;
        this.twoFactor = twoFactor;
        this.audit = audit;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @GetMapping("/api/platform/stores")
    @Transactional(readOnly = true)
    public PageResponse<StoreAdminResponse> stores(@RequestParam(required = false) String q,
                                                   @RequestParam(required = false) Integer page,
                                                   @RequestParam(required = false) Integer size) {
        return PageResponse.of(stores.search(Search.like(q == null ? "" : q), true, PageResponse.request(page, size, Sort.by("name"))),
                this::response);
    }

    @PostMapping("/api/platform/stores/{id}/block")
    @Transactional
    public StoreAdminResponse blockStore(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id,
                                         @Valid @RequestBody BlockRequest req) {
        Store s = store(id);
        s.setBlocked(true);
        s.setBlockedReason(req.reason() == null || req.reason().isBlank() ? null : req.reason().trim());
        s.setBlockedAt(LocalDateTime.now(clock));
        statuses.evictAll();
        audit.recordFor(id, AuditService.STORE_BLOCKED, Long.valueOf(jwt.getSubject()), s.getBlockedReason());
        return response(s);
    }

    @PostMapping("/api/platform/stores/{id}/unblock")
    @Transactional
    public StoreAdminResponse unblockStore(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id) {
        Store s = store(id);
        s.setBlocked(false);
        s.setBlockedReason(null);
        s.setBlockedAt(null);
        statuses.evictAll();
        audit.recordFor(id, AuditService.STORE_UNBLOCKED, Long.valueOf(jwt.getSubject()), null);
        return response(s);
    }

    @GetMapping("/api/platform/users")
    @Transactional(readOnly = true)
    public PageResponse<UserResponse> users(@RequestParam(required = false) String q,
                                            @RequestParam(required = false) Integer page,
                                            @RequestParam(required = false) Integer size) {
        return PageResponse.of(users.search(q == null ? "" : q.trim(), PageResponse.request(page, size, Sort.by("name"))),
                UserResponse::from);
    }

    @PostMapping("/api/platform/users/{id}/block")
    @Transactional
    public UserResponse blockUser(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id, @Valid @RequestBody BlockRequest req) {
        AppUser u = user(id);
        if (u.getRole() == Role.PLATFORM_ADMIN) {
            throw new BusinessException("Não dá para bloquear um administrador da plataforma");
        }
        u.setBlocked(true);
        u.setBlockedReason(req.reason() == null || req.reason().isBlank() ? null : req.reason().trim());
        u.setBlockedAt(LocalDateTime.now(clock));
        statuses.evict(id);
        audit.recordFor(u.getStoreId(), AuditService.USER_BLOCKED, Long.valueOf(jwt.getSubject()), u.getEmail());
        return UserResponse.from(u);
    }

    @PostMapping("/api/platform/users/{id}/unblock")
    @Transactional
    public UserResponse unblockUser(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id) {
        AppUser u = user(id);
        u.setBlocked(false);
        u.setBlockedReason(null);
        u.setBlockedAt(null);
        statuses.evict(id);
        audit.recordFor(u.getStoreId(), AuditService.USER_UNBLOCKED, Long.valueOf(jwt.getSubject()), u.getEmail());
        return UserResponse.from(u);
    }

    /** Quem perdeu o celular do autenticador. */
    @PostMapping("/api/platform/users/{id}/reset-2fa")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void resetTwoFactor(@PathVariable Long id) {
        twoFactor.reset(id);
    }

    private StoreAdminResponse response(Store s) {
        Long products = jdbc.queryForObject("select count(*) from product where tenant_id = ?", Long.class, s.getId());
        Long orders = jdbc.queryForObject("select count(*) from orders where tenant_id = ?", Long.class, s.getId());
        return new StoreAdminResponse(s.getId(), s.getSlug(), s.getName(), s.isBlocked(), s.getBlockedReason(),
                s.getCreatedAt(), products == null ? 0 : products, orders == null ? 0 : orders);
    }

    private Store store(Long id) {
        return stores.findById(id).orElseThrow(() -> new NotFoundException("Loja não encontrada"));
    }

    private AppUser user(Long id) {
        return users.findById(id).filter(AppUser::isActive).orElseThrow(() -> new NotFoundException("Usuário não encontrado"));
    }
}
