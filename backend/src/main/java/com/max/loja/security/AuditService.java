package com.max.loja.security;

import java.time.Clock;
import java.time.LocalDateTime;

import com.max.loja.shared.ClientIp;
import com.max.loja.shared.PageResponse;
import com.max.loja.shared.TenantContext;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

/**
 * Auditoria: quem entrou, quem errou a senha, trocas de senha, bloqueios e ações sensíveis da equipe.
 * O dono vê os eventos da loja; cada pessoa vê os acessos da própria conta.
 */
@Service
public class AuditService {

    public static final String LOGIN = "LOGIN";
    public static final String LOGIN_FAILED = "LOGIN_FAILED";
    public static final String LOGIN_LOCKED = "LOGIN_LOCKED";
    public static final String PASSWORD_CHANGED = "PASSWORD_CHANGED";
    public static final String PASSWORD_RESET = "PASSWORD_RESET";
    public static final String LOGOUT_ALL = "LOGOUT_ALL";
    public static final String TWO_FACTOR_ON = "TWO_FACTOR_ON";
    public static final String TWO_FACTOR_OFF = "TWO_FACTOR_OFF";
    public static final String ACCOUNT_DELETED = "ACCOUNT_DELETED";
    public static final String CUSTOMER_BLOCKED = "CUSTOMER_BLOCKED";
    public static final String CUSTOMER_UNBLOCKED = "CUSTOMER_UNBLOCKED";
    public static final String STAFF_CREATED = "STAFF_CREATED";
    public static final String STAFF_REMOVED = "STAFF_REMOVED";
    public static final String STORE_CREATED = "STORE_CREATED";
    public static final String STORE_SETTINGS = "STORE_SETTINGS";
    public static final String STORE_BLOCKED = "STORE_BLOCKED";
    public static final String STORE_UNBLOCKED = "STORE_UNBLOCKED";
    public static final String USER_BLOCKED = "USER_BLOCKED";
    public static final String USER_UNBLOCKED = "USER_UNBLOCKED";
    public static final String PRODUCT_DELETED = "PRODUCT_DELETED";
    public static final String PROMOTION_SAVED = "PROMOTION_SAVED";
    public static final String ORDER_CANCELED = "ORDER_CANCELED";

    public record EventResponse(Long id, String type, Long userId, String userName, String detail, String ip,
                                LocalDateTime createdAt) {
    }

    private final JdbcTemplate jdbc;
    private final Clock clock;

    public AuditService(JdbcTemplate jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    /** Grava mesmo se a transação de quem chamou for desfeita (ex.: login errado). Loja = a da requisição. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(String type, Long userId, String detail) {
        Long tenant = TenantContext.get();
        recordFor(tenant.equals(TenantContext.NONE) ? null : tenant, type, userId, detail);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordFor(Long tenantId, String type, Long userId, String detail) {
        jdbc.update("insert into security_event (tenant_id, user_id, type, detail, ip, created_at) values (?, ?, ?, ?, ?, ?)",
                tenantId, userId, type, detail == null ? null : detail.length() > 300 ? detail.substring(0, 300) : detail,
                ip(), LocalDateTime.now(clock));
    }

    /** Acessos e mudanças da própria conta. */
    @Transactional(readOnly = true)
    public PageResponse<EventResponse> ofUser(Long userId, Integer page, Integer size) {
        return page("e.user_id = ?", userId, page, size);
    }

    /** Eventos da loja (dono). */
    @Transactional(readOnly = true)
    public PageResponse<EventResponse> ofStore(Long tenantId, Integer page, Integer size) {
        return page("e.tenant_id = ?", tenantId, page, size);
    }

    private PageResponse<EventResponse> page(String where, Long arg, Integer page, Integer size) {
        PageRequest req = PageResponse.request(page, size, org.springframework.data.domain.Sort.unsorted());
        Long total = jdbc.queryForObject("select count(*) from security_event e where " + where, Long.class, arg);
        var items = jdbc.query("""
                select e.id, e.type, e.user_id, u.name, e.detail, e.ip, e.created_at
                from security_event e left join app_user u on u.id = e.user_id
                where %s order by e.id desc limit ? offset ?""".formatted(where),
                (rs, i) -> new EventResponse(rs.getLong(1), rs.getString(2), (Long) rs.getObject(3), rs.getString(4),
                        rs.getString(5), rs.getString(6), rs.getTimestamp(7).toLocalDateTime()),
                arg, req.getPageSize(), req.getOffset());
        return PageResponse.of(new PageImpl<>(items, req, total == null ? 0 : total), e -> e);
    }

    private static String ip() {
        if (RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes attrs) {
            return ClientIp.of(attrs.getRequest());
        }
        return null;
    }
}
