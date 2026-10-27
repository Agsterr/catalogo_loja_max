package com.max.loja.auth;

import java.time.Clock;
import java.time.LocalDateTime;

import com.max.loja.auth.AuthDtos.ChangePasswordRequest;
import com.max.loja.auth.AuthDtos.LoginRequest;
import com.max.loja.auth.AuthDtos.RegisterRequest;
import com.max.loja.auth.AuthDtos.RegisterStoreRequest;
import com.max.loja.auth.AuthDtos.TokenResponse;
import com.max.loja.auth.AuthDtos.UpdateProfileRequest;
import com.max.loja.auth.AuthDtos.UserResponse;
import com.max.loja.security.AccountStatusService;
import com.max.loja.security.AuditService;
import com.max.loja.security.JwtService;
import com.max.loja.security.LoginProperties;
import com.max.loja.shared.AccountBlockedException;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.TwoFactorRequiredException;
import com.max.loja.store.Store;
import com.max.loja.store.StoreRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthService.class);

    private final AppUserRepository users;
    private final StoreRepository stores;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final AccountStatusService statuses;
    private final TwoFactorService twoFactor;
    private final AuditService audit;
    private final LoginProperties loginProps;
    private final Clock clock;
    /** Hash de uma senha qualquer: o login de e-mail inexistente gasta o mesmo tempo (não revela quem tem conta). */
    private final String dummyHash;

    public AuthService(AppUserRepository users, StoreRepository stores, PasswordEncoder passwordEncoder,
                       JwtService jwtService, AccountStatusService statuses, TwoFactorService twoFactor,
                       AuditService audit, LoginProperties loginProps, Clock clock) {
        this.users = users;
        this.stores = stores;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.statuses = statuses;
        this.twoFactor = twoFactor;
        this.audit = audit;
        this.loginProps = loginProps;
        this.clock = clock;
        this.dummyHash = passwordEncoder.encode("senha-que-ninguem-usa-1");
    }

    /** Cliente cria a conta pelo app: uma conta só, vale em todas as lojas da plataforma. */
    @Transactional
    public TokenResponse register(RegisterRequest req) {
        ensureEmailFree(req.email());
        AppUser user = newUser(req.name(), req.email(), req.password(), Role.CUSTOMER, null);
        user.setPhone(blankToNull(req.phone()));
        return token(user);
    }

    /** Lojista abre a loja: cria a loja (tenant) e o dono dela. */
    @Transactional
    public TokenResponse registerStore(RegisterStoreRequest req) {
        if (stores.existsBySlug(req.slug())) {
            throw new BusinessException("Esse endereço de loja já está em uso");
        }
        ensureEmailFree(req.email());
        Store store = new Store();
        store.setName(req.storeName().trim());
        store.setSlug(req.slug());
        store.setCreatedAt(LocalDateTime.now(clock));
        stores.save(store);
        AppUser owner = newUser(req.ownerName(), req.email(), req.password(), Role.OWNER, store.getId());
        audit.recordFor(store.getId(), AuditService.STORE_CREATED, owner.getId(), store.getSlug());
        return token(owner);
    }

    /**
     * Confere a senha (e o código do autenticador, se ligado). Erros seguidos travam o e-mail por
     * {@code app.security.login-lock}; a resposta para e-mail inexistente e senha errada é a mesma.
     */
    @Transactional(noRollbackFor = {BadCredentialsException.class, ResponseStatusException.class,
            TwoFactorRequiredException.class, AccountBlockedException.class})
    public TokenResponse login(LoginRequest req) {
        LocalDateTime now = LocalDateTime.now(clock);
        AppUser user = users.findByEmailIgnoreCase(req.email().trim()).filter(AppUser::isActive).orElse(null);
        if (user == null) {
            passwordEncoder.matches(req.password(), dummyHash);
            throw new BadCredentialsException("E-mail ou senha inválidos");
        }
        if (user.getLockedUntil() != null && user.getLockedUntil().isAfter(now)) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "Muitas tentativas erradas. Tente de novo em alguns minutos ou use \"Esqueci minha senha\".");
        }
        if (!passwordEncoder.matches(req.password(), user.getPasswordHash())) {
            failed(user, now, "senha errada");
            throw new BadCredentialsException("E-mail ou senha inválidos");
        }
        if (user.isTotpEnabled()) {
            if (req.code() == null || req.code().isBlank()) {
                throw new TwoFactorRequiredException();
            }
            if (!twoFactor.verify(user, req.code())) {
                failed(user, now, "código do autenticador errado");
                throw new BadCredentialsException("Código do autenticador inválido");
            }
        }
        if (user.isBlocked()) {
            throw new AccountBlockedException(user.getBlockedReason());
        }
        Store store = storeOf(user);
        if (store != null && store.isBlocked()) {
            throw new AccountBlockedException(store.getBlockedReason() == null ? "Esta loja foi bloqueada."
                    : store.getBlockedReason());
        }
        user.setFailedLogins(0);
        user.setLockedUntil(null);
        audit.recordFor(user.getStoreId(), AuditService.LOGIN, user.getId(), null);
        return token(user);
    }

    private void failed(AppUser user, LocalDateTime now, String why) {
        user.setFailedLogins(user.getFailedLogins() + 1);
        audit.recordFor(user.getStoreId(), AuditService.LOGIN_FAILED, user.getId(), why);
        if (user.getFailedLogins() >= loginProps.maxLoginFailures()) {
            user.setLockedUntil(now.plus(loginProps.loginLock()));
            user.setFailedLogins(0);
            audit.recordFor(user.getStoreId(), AuditService.LOGIN_LOCKED, user.getId(), null);
            log.warn("Login travado por tentativas erradas: usuário {}", user.getId());
        }
    }

    @Transactional(readOnly = true)
    public UserResponse me(Long userId) {
        AppUser user = find(userId);
        return UserResponse.from(user, storeOf(user));
    }

    /** Token novo com validade renovada; os apps chamam ao abrir para manter o login. */
    @Transactional(readOnly = true)
    public TokenResponse refresh(Long userId) {
        return token(find(userId));
    }

    @Transactional
    public UserResponse updateProfile(Long userId, UpdateProfileRequest req) {
        AppUser user = find(userId);
        user.setName(req.name().trim());
        user.setPhone(blankToNull(req.phone()));
        return UserResponse.from(user, storeOf(user));
    }

    /** Troca a senha e derruba as outras sessões; devolve um token novo para este aparelho continuar entrando. */
    @Transactional
    public TokenResponse changePassword(Long userId, ChangePasswordRequest req) {
        AppUser user = find(userId);
        if (!passwordEncoder.matches(req.currentPassword(), user.getPasswordHash())) {
            throw new BusinessException("Senha atual incorreta.");
        }
        user.setPasswordHash(passwordEncoder.encode(req.newPassword()));
        user.revokeTokens();
        statuses.evict(userId);
        audit.recordFor(user.getStoreId(), AuditService.PASSWORD_CHANGED, userId, null);
        return token(user);
    }

    /** "Sair de todos os aparelhos": todo token emitido até agora deixa de valer. */
    @Transactional
    public void logoutEverywhere(Long userId) {
        AppUser user = find(userId);
        user.revokeTokens();
        statuses.evict(userId);
        audit.recordFor(user.getStoreId(), AuditService.LOGOUT_ALL, userId, null);
    }

    private AppUser find(Long userId) {
        return users.findById(userId).filter(AppUser::isActive)
                .orElseThrow(() -> new NotFoundException("Usuário não encontrado"));
    }

    private Store storeOf(AppUser user) {
        return user.getStoreId() == null ? null : stores.findById(user.getStoreId()).orElse(null);
    }

    private void ensureEmailFree(String email) {
        if (users.existsByEmailIgnoreCase(email.trim())) {
            throw new BusinessException("E-mail já cadastrado. Entre com a sua senha ou use \"Esqueci minha senha\".");
        }
    }

    private AppUser newUser(String name, String email, String password, Role role, Long storeId) {
        AppUser user = new AppUser();
        user.setName(name.trim());
        user.setEmail(email.trim().toLowerCase());
        user.setPasswordHash(passwordEncoder.encode(password));
        user.setRole(role);
        user.setStoreId(storeId);
        user.setCreatedAt(LocalDateTime.now(clock));
        return users.save(user);
    }

    private TokenResponse token(AppUser user) {
        return new TokenResponse(jwtService.issue(user), UserResponse.from(user, storeOf(user)));
    }

    static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
