package com.max.loja.auth;

import java.time.LocalDateTime;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public final class AuthDtos {

    /** Senha: 8 a 100 caracteres, com pelo menos uma letra e um número. */
    static final String PASSWORD = "^(?=.*[A-Za-z])(?=.*\\d).{8,100}$";
    static final String PASSWORD_MSG = "use de 8 a 100 caracteres, com letras e números";

    private AuthDtos() {
    }

    /** Cadastro de cliente pelo app. */
    public record RegisterRequest(
            @NotBlank @Size(max = 120) String name,
            @NotBlank @Email @Size(max = 180) String email,
            @Size(max = 30) String phone,
            @NotBlank @Pattern(regexp = PASSWORD, message = PASSWORD_MSG) String password) {
    }

    /** {@code code}: código do app autenticador, só para quem ligou a verificação em duas etapas. */
    public record LoginRequest(@NotBlank @Size(max = 180) String email, @NotBlank @Size(max = 100) String password,
                               @Size(max = 10) String code) {
    }

    /** Lojista abre a loja na plataforma (vira o dono dela). */
    public record RegisterStoreRequest(
            @NotBlank @Size(max = 120) String storeName,
            @NotBlank @Pattern(regexp = "[a-z0-9-]{3,60}", message = "use letras minúsculas, números e hífen") String slug,
            @NotBlank @Size(max = 120) String ownerName,
            @NotBlank @Email @Size(max = 180) String email,
            @NotBlank @Pattern(regexp = PASSWORD, message = PASSWORD_MSG) String password) {
    }

    public record TwoFactorSetupResponse(String secret, String otpauthUri) {
    }

    public record TwoFactorCodeRequest(@NotBlank @Size(max = 10) String code) {
    }

    public record TwoFactorDisableRequest(@NotBlank String password, @NotBlank @Size(max = 10) String code) {
    }

    /** Conta da equipe criada pelo dono. */
    public record CreateStaffRequest(
            @NotBlank @Size(max = 120) String name,
            @NotBlank @Email @Size(max = 180) String email,
            @NotBlank @Pattern(regexp = PASSWORD, message = PASSWORD_MSG) String password,
            @NotNull Role role) {
    }

    public record UpdateProfileRequest(@NotBlank @Size(max = 120) String name, @Size(max = 30) String phone) {
    }

    public record ChangePasswordRequest(@NotBlank String currentPassword,
                                        @NotBlank @Pattern(regexp = PASSWORD, message = PASSWORD_MSG) String newPassword) {
    }

    public record ForgotPasswordRequest(@NotBlank @Email String email) {
    }

    public record ResetPasswordRequest(@NotBlank @Email String email, @NotBlank @Size(max = 20) String code,
                                       @NotBlank @Pattern(regexp = PASSWORD, message = PASSWORD_MSG) String password) {
    }

    public record BlockRequest(@Size(max = 300) String reason) {
    }

    public record DeleteAccountRequest(@NotBlank String password) {
    }

    public record TokenResponse(String token, UserResponse user) {
    }

    /** {@code storeSlug}/{@code storeName}: loja da equipe (nulos para cliente e admin da plataforma). */
    public record UserResponse(Long id, String name, String email, String phone, Role role, boolean blocked,
                               String blockedReason, LocalDateTime createdAt, Long storeId, String storeSlug,
                               String storeName, boolean twoFactorEnabled) {

        public static UserResponse from(AppUser u) {
            return from(u, null);
        }

        public static UserResponse from(AppUser u, com.max.loja.store.Store store) {
            return new UserResponse(u.getId(), u.getName(), u.getEmail(), u.getPhone(), u.getRole(), u.isBlocked(),
                    u.getBlockedReason(), u.getCreatedAt(), u.getStoreId(), store == null ? null : store.getSlug(),
                    store == null ? null : store.getName(), u.isTotpEnabled());
        }
    }
}
