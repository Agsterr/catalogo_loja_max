package com.max.loja.auth;

import java.time.Clock;
import java.time.LocalDateTime;

import com.max.loja.auth.AuthDtos.ChangePasswordRequest;
import com.max.loja.auth.AuthDtos.LoginRequest;
import com.max.loja.auth.AuthDtos.RegisterRequest;
import com.max.loja.auth.AuthDtos.TokenResponse;
import com.max.loja.auth.AuthDtos.UpdateProfileRequest;
import com.max.loja.auth.AuthDtos.UserResponse;
import com.max.loja.security.AccountStatusService;
import com.max.loja.security.JwtService;
import com.max.loja.security.LoginProperties;
import com.max.loja.shared.AccountBlockedException;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthService.class);
    /** Hash de uma senha qualquer: o login de e-mail inexistente gasta o mesmo tempo (não revela quem tem conta). */
    private final String dummyHash;

    private final AppUserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final AccountStatusService statuses;
    private final LoginProperties loginProps;
    private final Clock clock;

    public AuthService(AppUserRepository users, PasswordEncoder passwordEncoder, JwtService jwtService,
                       AccountStatusService statuses, LoginProperties loginProps, Clock clock) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.statuses = statuses;
        this.loginProps = loginProps;
        this.clock = clock;
        this.dummyHash = passwordEncoder.encode("senha-que-ninguem-usa-1");
    }

    /** Cliente cria a conta pelo app. A equipe é criada pelo dono ({@link StaffService}). */
    @Transactional
    public TokenResponse register(RegisterRequest req) {
        if (users.existsByEmailIgnoreCase(req.email().trim())) {
            throw new BusinessException("E-mail já cadastrado. Entre com a sua senha ou use \"Esqueci minha senha\".");
        }
        AppUser user = new AppUser();
        user.setName(req.name().trim());
        user.setEmail(req.email().trim().toLowerCase());
        user.setPhone(blankToNull(req.phone()));
        user.setPasswordHash(passwordEncoder.encode(req.password()));
        user.setRole(Role.CUSTOMER);
        user.setCreatedAt(LocalDateTime.now(clock));
        return token(users.save(user));
    }

    /**
     * Confere a senha. Erros seguidos travam o e-mail por {@code app.security.login-lock}; a resposta para
     * e-mail inexistente e senha errada é a mesma.
     */
    @Transactional(noRollbackFor = {BadCredentialsException.class, ResponseStatusException.class})
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
            user.setFailedLogins(user.getFailedLogins() + 1);
            if (user.getFailedLogins() >= loginProps.maxLoginFailures()) {
                user.setLockedUntil(now.plus(loginProps.loginLock()));
                user.setFailedLogins(0);
                log.warn("Login travado por tentativas erradas: usuário {}", user.getId());
            }
            throw new BadCredentialsException("E-mail ou senha inválidos");
        }
        if (user.isBlocked()) {
            throw new AccountBlockedException(user.getBlockedReason());
        }
        user.setFailedLogins(0);
        user.setLockedUntil(null);
        return token(user);
    }

    @Transactional(readOnly = true)
    public UserResponse me(Long userId) {
        return UserResponse.from(find(userId));
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
        return UserResponse.from(user);
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
        return token(user);
    }

    /** "Sair de todos os aparelhos": todo token emitido até agora deixa de valer. */
    @Transactional(propagation = Propagation.REQUIRED)
    public void logoutEverywhere(Long userId) {
        find(userId).revokeTokens();
        statuses.evict(userId);
    }

    private AppUser find(Long userId) {
        return users.findById(userId).filter(AppUser::isActive)
                .orElseThrow(() -> new NotFoundException("Usuário não encontrado"));
    }

    private TokenResponse token(AppUser user) {
        return new TokenResponse(jwtService.issue(user), UserResponse.from(user));
    }

    static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
