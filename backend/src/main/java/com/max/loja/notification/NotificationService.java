package com.max.loja.notification;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.max.loja.push.PushNotifier;
import com.max.loja.security.CurrentUser;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Sino + push, igual ao Gerenciamento Max: todo aviso fica no sino (o app consulta em segundo plano) e, com o
 * Firebase configurado, também vai para a fila de push dos celulares.
 */
@Service
public class NotificationService {

    public record NotificationResponse(Long id, Notification.Type type, Long orderId, Long productId, String title,
                                       String message, LocalDateTime createdAt, boolean read) {

        static NotificationResponse from(Notification n) {
            return new NotificationResponse(n.getId(), n.getType(), n.getOrderId(), n.getProductId(), n.getTitle(),
                    n.getMessage(), n.getCreatedAt(), n.getReadAt() != null);
        }
    }

    public record Inbox(long unread, List<NotificationResponse> items) {
    }

    /** O que o aviso aponta (o app abre o pedido ou o produto ao tocar). */
    public record Target(Long orderId, Long productId) {

        static Target order(Long id) {
            return new Target(id, null);
        }

        static Target product(Long id) {
            return new Target(null, id);
        }
    }

    private final NotificationRepository repository;
    private final PushNotifier push;
    private final Clock clock;

    public NotificationService(NotificationRepository repository, PushNotifier push, Clock clock) {
        this.repository = repository;
        this.push = push;
        this.clock = clock;
    }

    /** Aviso para a equipe toda. {@code dedupKey} não nulo impede repetir. */
    @Transactional
    public boolean toTeam(Notification.Type type, String title, String message, Target target, String dedupKey) {
        Notification n = save(type, null, title, message, target, dedupKey);
        if (n == null) {
            return false;
        }
        push.toTeam("n" + n.getId(), title, message, data("team", type, target));
        return true;
    }

    /** Aviso para um usuário (cliente). */
    @Transactional
    public boolean toUser(Long userId, Notification.Type type, String title, String message, Target target,
                          String dedupKey) {
        Notification n = save(type, userId, title, message, target, dedupKey);
        if (n == null) {
            return false;
        }
        push.toUser(userId, "n" + n.getId(), title, message, data("customer", type, target));
        return true;
    }

    /** Nulo se o aviso com essa chave já existia. */
    private Notification save(Notification.Type type, Long userId, String title, String message, Target target,
                         String dedupKey) {
        if (dedupKey != null && repository.existsByDedupKey(dedupKey)) {
            return null;
        }
        Notification n = new Notification();
        n.setType(type);
        n.setUserId(userId);
        n.setTitle(cut(title, 200));
        n.setMessage(cut(message, 500));
        n.setOrderId(target.orderId());
        n.setProductId(target.productId());
        n.setDedupKey(dedupKey);
        n.setCreatedAt(LocalDateTime.now(clock));
        return repository.save(n);
    }

    private static Map<String, String> data(String audience, Notification.Type type, Target target) {
        Map<String, String> data = new HashMap<>();
        data.put("type", type == Notification.Type.BACK_IN_STOCK ? "back_in_stock" : audience);
        data.put("kind", type.name());
        if (target.orderId() != null) {
            data.put("orderId", String.valueOf(target.orderId()));
        }
        if (target.productId() != null) {
            data.put("productId", String.valueOf(target.productId()));
        }
        return data;
    }

    @Transactional(readOnly = true)
    public Inbox inbox(CurrentUser me) {
        return new Inbox(repository.countUnread(me.id(), me.isTeam()),
                repository.findVisible(me.id(), me.isTeam(), PageRequest.of(0, 50)).stream()
                        .map(NotificationResponse::from).toList());
    }

    @Transactional
    public void markAllRead(CurrentUser me) {
        repository.markAllRead(me.id(), me.isTeam(), LocalDateTime.now(clock));
    }

    @Transactional
    public void markRead(CurrentUser me, Long id) {
        repository.markRead(id, me.id(), me.isTeam(), LocalDateTime.now(clock));
    }

    private static String cut(String s, int max) {
        return s.length() <= max ? s : s.substring(0, max - 1) + "…";
    }
}
