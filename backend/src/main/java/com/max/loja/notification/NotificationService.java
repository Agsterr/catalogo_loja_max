package com.max.loja.notification;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import com.max.loja.push.PushNotifier;
import com.max.loja.security.CurrentUser;
import com.max.loja.shared.PageResponse;
import com.max.loja.shared.TenantContext;
import com.max.loja.store.Store;
import com.max.loja.store.StoreRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Sino + push, igual ao Gerenciamento Max: todo aviso fica no sino (o app consulta em segundo plano) e, com o
 * Firebase configurado, também vai para a fila de push dos celulares.
 */
@Service
public class NotificationService {

    /** {@code storeSlug}: o app abre o pedido/produto na loja certa. */
    public record NotificationResponse(Long id, Notification.Type type, Long orderId, Long productId, String title,
                                       String message, LocalDateTime createdAt, boolean read, String storeSlug,
                                       String storeName) {

        static NotificationResponse from(Notification n, Store store) {
            return new NotificationResponse(n.getId(), n.getType(), n.getOrderId(), n.getProductId(), n.getTitle(),
                    n.getMessage(), n.getCreatedAt(), n.getReadAt() != null, store == null ? null : store.getSlug(),
                    store == null ? null : store.getName());
        }
    }

    /** Página do sino; {@code unread} conta todos os não lidos (não só os da página). */
    public record Inbox(long unread, List<NotificationResponse> items, int page, boolean hasMore) {
    }

    /** O que o aviso aponta (o app abre o pedido ou o produto ao tocar). */
    public record Target(Long orderId, Long productId) {

        static Target order(Long id) {
            return new Target(id, null);
        }

        public static Target none() {
            return new Target(null, null);
        }

        static Target product(Long id) {
            return new Target(null, id);
        }
    }

    private final NotificationRepository repository;
    private final StoreRepository stores;
    private final PushNotifier push;
    private final Clock clock;

    public NotificationService(NotificationRepository repository, StoreRepository stores, PushNotifier push, Clock clock) {
        this.repository = repository;
        this.stores = stores;
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
        n.setStoreId(TenantContext.get());
        n.setUserId(userId);
        n.setTitle(cut(title, 200));
        n.setMessage(cut(message, 500));
        n.setOrderId(target.orderId());
        n.setProductId(target.productId());
        n.setDedupKey(dedupKey);
        n.setCreatedAt(LocalDateTime.now(clock));
        return repository.save(n);
    }

    private Map<String, String> data(String audience, Notification.Type type, Target target) {
        Map<String, String> data = new HashMap<>();
        data.put("type", type == Notification.Type.BACK_IN_STOCK ? "back_in_stock" : audience);
        data.put("kind", type.name());
        stores.findById(TenantContext.get()).ifPresent(s -> data.put("slug", s.getSlug()));
        if (target.orderId() != null) {
            data.put("orderId", String.valueOf(target.orderId()));
        }
        if (target.productId() != null) {
            data.put("productId", String.valueOf(target.productId()));
        }
        return data;
    }

    @Transactional(readOnly = true)
    public Inbox inbox(CurrentUser me, Integer page, Integer size) {
        Page<Notification> result = repository.findVisible(me.id(), storeOf(me),
                PageResponse.request(page, size, Sort.unsorted()));
        Map<Long, Store> byId = new HashMap<>();
        stores.findAllById(result.getContent().stream().map(Notification::getStoreId).collect(Collectors.toSet()))
                .forEach(s -> byId.put(s.getId(), s));
        return new Inbox(repository.countUnread(me.id(), storeOf(me)),
                result.getContent().stream().map(n -> NotificationResponse.from(n, byId.get(n.getStoreId()))).toList(),
                result.getNumber(), result.hasNext());
    }

    @Transactional
    public void markAllRead(CurrentUser me) {
        repository.markAllRead(me.id(), storeOf(me), LocalDateTime.now(clock));
    }

    @Transactional
    public void markRead(CurrentUser me, Long id) {
        repository.markRead(id, me.id(), storeOf(me), LocalDateTime.now(clock));
    }

    /** Equipe vê o sino da loja do token; cliente (sem loja) vê os dele de todas. */
    private static Long storeOf(CurrentUser me) {
        return me.isTeam() ? TenantContext.get() : null;
    }

    private static String cut(String s, int max) {
        return s.length() <= max ? s : s.substring(0, max - 1) + "…";
    }
}
