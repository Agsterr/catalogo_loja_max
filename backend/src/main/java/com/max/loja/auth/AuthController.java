package com.max.loja.auth;

import java.util.List;

import com.max.loja.auth.AuthDtos.BlockRequest;
import com.max.loja.auth.AuthDtos.ChangePasswordRequest;
import com.max.loja.auth.AuthDtos.CreateStaffRequest;
import com.max.loja.auth.AuthDtos.DeleteAccountRequest;
import com.max.loja.auth.AuthDtos.ForgotPasswordRequest;
import com.max.loja.auth.AuthDtos.LoginRequest;
import com.max.loja.auth.AuthDtos.RegisterRequest;
import com.max.loja.auth.AuthDtos.ResetPasswordRequest;
import com.max.loja.auth.AuthDtos.TokenResponse;
import com.max.loja.auth.AuthDtos.UpdateProfileRequest;
import com.max.loja.auth.AuthDtos.UserResponse;
import com.max.loja.shared.ClientIp;
import com.max.loja.shared.PageResponse;
import com.max.loja.shared.RateLimiter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AuthController {

    private final AuthService service;
    private final StaffService staff;
    private final AccountDeletionService deletion;
    private final PasswordResetService passwordReset;
    private final RateLimiter rateLimiter;

    public AuthController(AuthService service, StaffService staff, AccountDeletionService deletion,
                          PasswordResetService passwordReset, RateLimiter rateLimiter) {
        this.service = service;
        this.staff = staff;
        this.deletion = deletion;
        this.passwordReset = passwordReset;
        this.rateLimiter = rateLimiter;
    }

    // --- públicos (com limite de tentativas por IP e por e-mail) ---

    @PostMapping("/api/auth/register")
    @ResponseStatus(HttpStatus.CREATED)
    public TokenResponse register(@Valid @RequestBody RegisterRequest req, HttpServletRequest http) {
        rateLimiter.check("register-ip:" + ClientIp.of(http));
        return service.register(req);
    }

    @PostMapping("/api/auth/login")
    public TokenResponse login(@Valid @RequestBody LoginRequest req, HttpServletRequest http) {
        rateLimiter.check("login-ip:" + ClientIp.of(http), 30);
        return service.login(req);
    }

    /** Sempre 204, exista ou não a conta. */
    @PostMapping("/api/auth/forgot-password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void forgotPassword(@Valid @RequestBody ForgotPasswordRequest req, HttpServletRequest http) {
        rateLimiter.check("reset-ip:" + ClientIp.of(http));
        rateLimiter.check("reset-mail:" + req.email().trim().toLowerCase(), 3);
        passwordReset.request(req.email());
    }

    @PostMapping("/api/auth/reset-password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void resetPassword(@Valid @RequestBody ResetPasswordRequest req, HttpServletRequest http) {
        rateLimiter.check("reset-ip:" + ClientIp.of(http));
        rateLimiter.check("reset-code:" + req.email().trim().toLowerCase(), 5);
        passwordReset.reset(req.email(), req.code(), req.password());
    }

    // --- conta do usuário logado ---

    @GetMapping("/api/me")
    public UserResponse me(@AuthenticationPrincipal Jwt jwt) {
        return service.me(id(jwt));
    }

    @PutMapping("/api/me")
    public UserResponse updateMe(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody UpdateProfileRequest req) {
        return service.updateProfile(id(jwt), req);
    }

    /** Token novo com validade renovada; os apps chamam ao abrir para manter o login. */
    @PostMapping("/api/me/token")
    public TokenResponse refresh(@AuthenticationPrincipal Jwt jwt) {
        return service.refresh(id(jwt));
    }

    @PostMapping("/api/me/password")
    public TokenResponse changePassword(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody ChangePasswordRequest req,
                                        HttpServletRequest http) {
        rateLimiter.check("password-user:" + id(jwt), 5);
        return service.changePassword(id(jwt), req);
    }

    @PostMapping("/api/me/logout-all")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logoutAll(@AuthenticationPrincipal Jwt jwt) {
        service.logoutEverywhere(id(jwt));
    }

    @PostMapping("/api/me/delete")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteMe(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody DeleteAccountRequest req) {
        rateLimiter.check("delete-user:" + id(jwt), 5);
        deletion.delete(id(jwt), req.password());
    }

    // --- gestão: equipe (dono) e clientes ---

    @GetMapping("/api/store/users")
    public List<UserResponse> team() {
        return staff.team();
    }

    @PostMapping("/api/store/users")
    @ResponseStatus(HttpStatus.CREATED)
    public UserResponse createStaff(@Valid @RequestBody CreateStaffRequest req) {
        return staff.create(req);
    }

    @DeleteMapping("/api/store/users/{userId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void removeStaff(@AuthenticationPrincipal Jwt jwt, @PathVariable Long userId) {
        staff.remove(id(jwt), userId);
    }

    @GetMapping("/api/store/customers")
    public PageResponse<UserResponse> customers(@RequestParam(required = false) String q,
                                                @RequestParam(required = false) Integer page,
                                                @RequestParam(required = false) Integer size) {
        return staff.customers(q, page, size);
    }

    @PostMapping("/api/store/customers/{customerId}/block")
    public UserResponse block(@PathVariable Long customerId, @Valid @RequestBody BlockRequest req) {
        return staff.block(customerId, req.reason(), true);
    }

    @PostMapping("/api/store/customers/{customerId}/unblock")
    public UserResponse unblock(@PathVariable Long customerId) {
        return staff.block(customerId, null, false);
    }

    private static Long id(Jwt jwt) {
        return Long.valueOf(jwt.getSubject());
    }
}
