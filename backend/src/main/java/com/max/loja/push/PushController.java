package com.max.loja.push;

import java.time.Clock;
import java.time.LocalDateTime;

import com.max.loja.security.CurrentUser;
import com.max.loja.shared.ClientIp;
import com.max.loja.shared.RateLimiter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Cadastro dos celulares que recebem push e confirmação de recebimento dos avisos. */
@RestController
public class PushController {

    public record TokenRequest(@NotBlank @Size(max = 512) String token, Boolean promoNotifications) {
    }

    public record PreferencesRequest(@NotBlank @Size(max = 512) String token, boolean promoNotifications) {
    }

    public record AckRequest(@NotBlank @Size(max = 64) String id, @NotBlank @Size(max = 512) String token) {
    }

    private final PushDeviceRepository devices;
    private final PushOutbox outbox;
    private final RateLimiter rateLimiter;
    private final Clock clock;

    public PushController(PushDeviceRepository devices, PushOutbox outbox, RateLimiter rateLimiter, Clock clock) {
        this.devices = devices;
        this.outbox = outbox;
        this.rateLimiter = rateLimiter;
        this.clock = clock;
    }

    /**
     * Usuário logado (ou o código do celular mudou): este celular passa a receber os avisos dele. Equipe recebe os
     * avisos da loja; cliente, os dos pedidos dele e as promoções.
     */
    @PostMapping("/api/me/push-token")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    public void register(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody TokenRequest req) {
        CurrentUser me = CurrentUser.of(jwt);
        PushDevice d = devices.findByToken(req.token()).orElseGet(PushDevice::new);
        d.setToken(req.token());
        d.setApp(me.isTeam() ? PushNotifier.STAFF : PushNotifier.CLIENT);
        d.setUserId(me.id());
        if (req.promoNotifications() != null) {
            d.setPromoNotifications(req.promoNotifications());
        }
        d.setUpdatedAt(LocalDateTime.now(clock));
        devices.save(d);
    }

    /**
     * App do cliente aberto sem login: só recebe promoções. Não mexe em celular já ligado a uma conta (ninguém
     * desvincula o celular de outra pessoa mandando o código dele aqui).
     */
    @PostMapping("/api/public/push/register")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    public void registerAnonymous(@Valid @RequestBody TokenRequest req, HttpServletRequest http) {
        rateLimiter.check("push-ip:" + ClientIp.of(http), 20);
        PushDevice d = devices.findByToken(req.token()).orElseGet(PushDevice::new);
        if (d.getUserId() != null) {
            return;
        }
        d.setToken(req.token());
        d.setApp(PushNotifier.CLIENT);
        if (req.promoNotifications() != null) {
            d.setPromoNotifications(req.promoNotifications());
        }
        d.setUpdatedAt(LocalDateTime.now(clock));
        devices.save(d);
    }

    /** Liga/desliga os avisos de promoções deste celular. */
    @PutMapping("/api/me/push-preferences")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    public void preferences(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody PreferencesRequest req) {
        Long me = Long.valueOf(jwt.getSubject());
        devices.findByToken(req.token()).filter(d -> me.equals(d.getUserId()))
                .ifPresent(d -> d.setPromoNotifications(req.promoNotifications()));
    }

    /** Saiu do app: este celular deixa de receber os avisos da conta. */
    @PostMapping("/api/me/push-token/remove")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    public void unregister(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody TokenRequest req) {
        devices.findByToken(req.token())
                .filter(d -> Long.valueOf(jwt.getSubject()).equals(d.getUserId()))
                .ifPresent(devices::delete);
    }

    /**
     * Confirmação de recebimento: o app devolve o código do aviso e o do celular. Aberta (o app pode estar
     * em segundo plano, sem login), mas só vale com os dois códigos que o servidor mandou.
     */
    @PostMapping("/api/push/ack")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void ack(@Valid @RequestBody AckRequest req) {
        outbox.ack(req.id(), req.token(), LocalDateTime.now(clock));
    }
}
