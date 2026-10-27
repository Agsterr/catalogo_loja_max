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

    public record LoginRequest(@NotBlank @Size(max = 180) String email, @NotBlank @Size(max = 100) String password) {
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

    public record UserResponse(Long id, String name, String email, String phone, Role role, boolean blocked,
                               String blockedReason, LocalDateTime createdAt) {

        public static UserResponse from(AppUser u) {
            return new UserResponse(u.getId(), u.getName(), u.getEmail(), u.getPhone(), u.getRole(), u.isBlocked(),
                    u.getBlockedReason(), u.getCreatedAt());
        }
    }
}
