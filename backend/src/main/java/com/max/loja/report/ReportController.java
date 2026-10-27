package com.max.loja.report;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.max.loja.catalog.CatalogDtos.LowStockResponse;
import com.max.loja.catalog.StockService;
import com.max.loja.order.CustomerOrder;
import com.max.loja.order.OrderItem;
import com.max.loja.order.OrderRepository;
import com.max.loja.order.OrderStatus;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.Money;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Resumo de vendas do período (dono). Pedidos cancelados não contam. */
@RestController
public class ReportController {

    public record TopProduct(Long productId, String name, int quantity, BigDecimal revenue) {
    }

    public record Summary(LocalDate from, LocalDate to, long orders, BigDecimal revenue, BigDecimal paidRevenue,
                          BigDecimal averageTicket, int itemsSold, Map<OrderStatus, Long> byStatus,
                          List<TopProduct> topProducts, long pendingNow, List<LowStockResponse> lowStock) {
    }

    private final OrderRepository orders;
    private final StockService stock;
    private final Clock clock;

    public ReportController(OrderRepository orders, StockService stock, Clock clock) {
        this.orders = orders;
        this.stock = stock;
        this.clock = clock;
    }

    @GetMapping("/api/store/reports/summary")
    @Transactional(readOnly = true)
    public Summary summary(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                           @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        LocalDate end = to != null ? to : LocalDate.now(clock);
        LocalDate start = from != null ? from : end.withDayOfMonth(1);
        if (start.isAfter(end) || start.plusDays(400).isBefore(end)) {
            throw new BusinessException("Período inválido (máximo de 400 dias)");
        }
        List<CustomerOrder> list = orders.findValidBetween(start.atStartOfDay(), end.plusDays(1).atStartOfDay());
        BigDecimal revenue = BigDecimal.ZERO;
        BigDecimal paid = BigDecimal.ZERO;
        int items = 0;
        Map<OrderStatus, Long> byStatus = new HashMap<>();
        Map<Long, TopProduct> top = new HashMap<>();
        for (CustomerOrder o : list) {
            revenue = revenue.add(o.getTotal());
            if (o.isPaid()) {
                paid = paid.add(o.getTotal());
            }
            byStatus.merge(o.getStatus(), 1L, Long::sum);
            for (OrderItem i : o.getItems()) {
                items += i.getQuantity();
                top.merge(i.getProductId(), new TopProduct(i.getProductId(), i.getProductName(), i.getQuantity(), i.getTotal()),
                        (a, b) -> new TopProduct(a.productId(), a.name(), a.quantity() + b.quantity(), a.revenue().add(b.revenue())));
            }
        }
        BigDecimal ticket = list.isEmpty() ? BigDecimal.ZERO
                : Money.round(revenue.divide(BigDecimal.valueOf(list.size()), 4, java.math.RoundingMode.HALF_UP));
        List<TopProduct> ranking = top.values().stream()
                .sorted(Comparator.comparingInt(TopProduct::quantity).reversed().thenComparing(TopProduct::name))
                .limit(10).toList();
        return new Summary(start, end, list.size(), Money.round(revenue), Money.round(paid), ticket, items, byStatus,
                ranking, orders.countByStatus(OrderStatus.PENDING), stock.lowStock());
    }
}
