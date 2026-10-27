package com.max.loja.push;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

import com.max.loja.auth.AppUser;
import com.max.loja.auth.AppUserRepository;
import com.max.loja.shared.TenantContext;
import org.springframework.stereotype.Service;

/**
 * Coloca na fila os avisos para os celulares: da equipe (pedido novo, cliente cancelou, estoque baixo) e dos
 * clientes (status do pedido, promoção, produto que voltou). A entrega é do {@link PushOutboxWorker}.
 * Sem Firebase configurado nada entra na fila (os apps seguem consultando o sino em segundo plano).
 */
@Service
public class PushNotifier {

    public static final String STAFF = "STAFF";
    public static final String CLIENT = "CLIENT";

    private final PushOutbox outbox;
    private final PushDeviceRepository devices;
    private final AppUserRepository users;
    private final PushProperties props;
    private final Clock clock;

    public PushNotifier(PushOutbox outbox, PushDeviceRepository devices, AppUserRepository users, PushProperties props,
                        Clock clock) {
        this.outbox = outbox;
        this.devices = devices;
        this.users = users;
        this.props = props;
        this.clock = clock;
    }

    /** A equipe ativa desta loja (dono e funcionários) com o app logado. {@code event} identifica o aviso (não repete). */
    public int toTeam(String event, String title, String body, Map<String, String> data) {
        if (!props.configured()) {
            return 0;
        }
        List<PushDevice> staff = devices.findTeamOf(TenantContext.get());
        Set<Long> eligible = users.findAllById(staff.stream().map(PushDevice::getUserId).filter(Objects::nonNull)
                        .collect(Collectors.toSet())).stream()
                .filter(u -> u.isActive() && !u.isBlocked() && u.getRole().isTeam())
                .map(AppUser::getId).collect(Collectors.toSet());
        return enqueue(staff.stream().filter(d -> eligible.contains(d.getUserId())).toList(), event, title, body, data);
    }

    /** Celulares de um usuário (cliente: status do pedido dele, produto que ele pediu para avisar). */
    public int toUser(Long userId, String event, String title, String body, Map<String, String> data) {
        if (!props.configured()) {
            return 0;
        }
        return enqueue(devices.findByUserIdIn(List.of(userId)), event, title, body, data);
    }

    /** Promoção: celulares que seguem esta loja e aceitam promoções (com ou sem login). */
    public int promotion(String event, String title, String body, Map<String, String> data) {
        if (!props.configured()) {
            return 0;
        }
        return enqueue(devices.findPromotionTargets(TenantContext.get()), event, title, body, data);
    }

    private int enqueue(List<PushDevice> targets, String event, String title, String body, Map<String, String> data) {
        LocalDateTime now = LocalDateTime.now(clock);
        int queued = 0;
        for (PushDevice d : targets) {
            if (outbox.enqueue(TenantContext.get(), d.getId(), d.getToken(), title, body, data, event + ":" + d.getId(), now)) {
                queued++;
            }
        }
        return queued;
    }
}
