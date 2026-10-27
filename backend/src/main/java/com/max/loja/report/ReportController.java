package com.max.loja.report;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

import com.max.loja.catalog.CatalogDtos.LowStockResponse;
import com.max.loja.catalog.StockService;
import com.max.loja.order.OrderStatus;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.Money;
import com.max.loja.shared.TenantContext;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Resumo de vendas do período (dono). Tudo somado no próprio PostgreSQL, com os índices por loja: não carrega
 * os pedidos na memória, então vale para anos de vendas. Pedidos cancelados não contam.
 */
@RestController
public class ReportController {

    public record TopProduct(Long productId, String name, long quantity, BigDecimal revenue) {
    }

    /** Vendas de um dia (gráfico). */
    public record Day(LocalDate date, long orders, BigDecimal revenue) {
    }

    public record Summary(LocalDate from, LocalDate to, long orders, BigDecimal revenue, BigDecimal paidRevenue,
                          BigDecimal averageTicket, long itemsSold, BigDecimal discounts, long newCustomers,
                          Map<OrderStatus, Long> byStatus, List<TopProduct> topProducts, List<Day> days, long pendingNow,
                          List<LowStockResponse> lowStock) {
    }

    private final JdbcTemplate jdbc;
    private final StockService stock;
    private final Clock clock;

    public ReportController(JdbcTemplate jdbc, StockService stock, Clock clock) {
        this.jdbc = jdbc;
        this.stock = stock;
        this.clock = clock;
    }

    @GetMapping("/api/store/reports/summary")
    @Transactional(readOnly = true)
    public Summary summary(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                           @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        LocalDate end = to != null ? to : LocalDate.now(clock);
        LocalDate start = from != null ? from : end.withDayOfMonth(1);
        if (start.isAfter(end) || start.plusYears(3).isBefore(end)) {
            throw new BusinessException("Período inválido (máximo de 3 anos)");
        }
        Long tenant = TenantContext.get();
        LocalDateTime a = start.atStartOfDay();
        LocalDateTime b = end.plusDays(1).atStartOfDay();
        String valid = "tenant_id = ? and created_at >= ? and created_at < ? and status <> 'CANCELED'";

        var totals = jdbc.queryForMap("""
                select count(*) as orders, coalesce(sum(total), 0) as revenue,
                       coalesce(sum(total) filter (where paid), 0) as paid, coalesce(sum(discount), 0) as discounts
                from orders where
                """ + " " + valid, tenant, a, b);
        long orders = ((Number) totals.get("orders")).longValue();
        BigDecimal revenue = (BigDecimal) totals.get("revenue");

        Long items = jdbc.queryForObject("""
                select coalesce(sum(i.quantity), 0) from order_item i join orders o on o.id = i.order_id
                where o.tenant_id = ? and o.created_at >= ? and o.created_at < ? and o.status <> 'CANCELED'""",
                Long.class, tenant, a, b);

        // clientes que fizeram o primeiro pedido nesta loja dentro do período
        Long newCustomers = jdbc.queryForObject("""
                select count(*) from (select customer_id, min(created_at) first from orders
                where tenant_id = ? and status <> 'CANCELED' group by customer_id) f where f.first >= ? and f.first < ?""",
                Long.class, tenant, a, b);

        Map<OrderStatus, Long> byStatus = new EnumMap<>(OrderStatus.class);
        jdbc.query("select status, count(*) from orders where tenant_id = ? and created_at >= ? and created_at < ? group by status",
                rs -> {
                    byStatus.put(OrderStatus.valueOf(rs.getString(1)), rs.getLong(2));
                }, tenant, a, b);

        List<TopProduct> top = jdbc.query("""
                select i.product_id, max(i.product_name), sum(i.quantity) q, sum(i.total)
                from order_item i join orders o on o.id = i.order_id
                where o.tenant_id = ? and o.created_at >= ? and o.created_at < ? and o.status <> 'CANCELED'
                group by i.product_id order by q desc, 2 limit 10""",
                (rs, i) -> new TopProduct(rs.getLong(1), rs.getString(2), rs.getLong(3), Money.round(rs.getBigDecimal(4))),
                tenant, a, b);

        List<Day> days = jdbc.query("""
                select cast(created_at as date) d, count(*), sum(total) from orders where
                """ + " " + valid
                + " group by d order by d",
                (rs, i) -> new Day(rs.getDate(1).toLocalDate(), rs.getLong(2), Money.round(rs.getBigDecimal(3))),
                tenant, a, b);

        Long pending = jdbc.queryForObject("select count(*) from orders where tenant_id = ? and status = 'PENDING'",
                Long.class, tenant);
        BigDecimal ticket = orders == 0 ? BigDecimal.ZERO
                : Money.round(revenue.divide(BigDecimal.valueOf(orders), 4, java.math.RoundingMode.HALF_UP));
        return new Summary(start, end, orders, Money.round(revenue), Money.round((BigDecimal) totals.get("paid")), ticket,
                items == null ? 0 : items, Money.round((BigDecimal) totals.get("discounts")),
                newCustomers == null ? 0 : newCustomers, byStatus, top, days, pending == null ? 0 : pending,
                stock.lowStock());
    }
}
