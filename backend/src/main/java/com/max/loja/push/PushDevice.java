package com.max.loja.push;

import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import lombok.Getter;
import lombok.Setter;

/** Celular que recebe push: da equipe (avisos da loja) ou de cliente (pedidos dele e promoções). */
@Getter
@Setter
@Entity
public class PushDevice {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 512, unique = true)
    private String token;

    /** Dono do celular; nulo = app aberto sem login (só promoções). */
    private Long userId;

    /** {@link PushNotifier#STAFF} ou {@link PushNotifier#CLIENT}. */
    @Column(nullable = false, length = 10)
    private String app = PushNotifier.CLIENT;

    private boolean promoNotifications = true;

    @Column(nullable = false)
    private LocalDateTime updatedAt = LocalDateTime.now();
}
