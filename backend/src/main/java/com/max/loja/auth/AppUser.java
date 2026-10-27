package com.max.loja.auth;

import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

/** Usuário: equipe da loja e clientes no mesmo cadastro, separados pelo papel. */
@Getter
@Setter
@Entity
@Table(name = "app_user")
public class AppUser {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false, unique = true)
    private String email;

    private String phone;

    @Column(nullable = false)
    private String passwordHash;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Role role;

    private boolean active = true;

    /** Bloqueado pelo dono da loja. */
    private boolean blocked;
    private String blockedReason;
    private LocalDateTime blockedAt;

    /** Vai no JWT (claim {@code ver}); aumentar invalida todos os tokens já emitidos. */
    private int tokenVersion;

    /** Tentativas de login erradas seguidas; ao passar do limite trava até {@link #lockedUntil}. */
    private int failedLogins;
    private LocalDateTime lockedUntil;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    public void revokeTokens() {
        tokenVersion++;
    }
}
