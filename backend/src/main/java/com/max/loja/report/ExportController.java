package com.max.loja.report;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import com.max.loja.shared.BusinessException;
import com.max.loja.shared.TenantContext;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Planilhas (CSV, abre no Excel/Google Planilhas) de vendas e de estoque — só do dono. */
@RestController
public class ExportController {

    private static final int MAX_ROWS = 50_000;

    private final JdbcTemplate jdbc;
    private final Clock clock;

    public ExportController(JdbcTemplate jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @GetMapping("/api/store/reports/orders.csv")
    @Transactional(readOnly = true)
    public ResponseEntity<byte[]> orders(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                         @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        LocalDate end = to != null ? to : LocalDate.now(clock);
        LocalDate start = from != null ? from : end.withDayOfMonth(1);
        if (start.isAfter(end) || start.plusYears(3).isBefore(end)) {
            throw new BusinessException("Período inválido (máximo de 3 anos)");
        }
        List<Map<String, Object>> rows = jdbc.queryForList("""
                select o.code, o.created_at, o.status, o.delivery_method, o.payment_method, o.paid, o.subtotal, o.discount,
                       o.delivery_fee, o.total, u.name as customer, coalesce(u.phone, '') as phone
                from orders o join app_user u on u.id = o.customer_id
                where o.tenant_id = ? and o.created_at >= ? and o.created_at < ? order by o.id limit ?""",
                TenantContext.get(), start.atStartOfDay(), end.plusDays(1).atStartOfDay(), MAX_ROWS);
        StringBuilder sb = new StringBuilder("Pedido;Data;Status;Entrega;Pagamento;Pago;Produtos;Desconto;Frete;Total;Cliente;Telefone\n");
        for (Map<String, Object> r : rows) {
            sb.append(cell(r.get("code"))).append(';').append(cell(String.valueOf(r.get("created_at")).substring(0, 16)))
                    .append(';').append(cell(r.get("status"))).append(';').append(cell(r.get("delivery_method")))
                    .append(';').append(cell(r.get("payment_method"))).append(';').append(Boolean.TRUE.equals(r.get("paid")) ? "sim" : "não")
                    .append(';').append(num(r.get("subtotal"))).append(';').append(num(r.get("discount")))
                    .append(';').append(num(r.get("delivery_fee"))).append(';').append(num(r.get("total")))
                    .append(';').append(cell(r.get("customer"))).append(';').append(cell(r.get("phone"))).append('\n');
        }
        return csv("vendas-" + start + "-a-" + end + ".csv", sb);
    }

    @GetMapping("/api/store/reports/stock.csv")
    @Transactional(readOnly = true)
    public ResponseEntity<byte[]> stock() {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                select p.name, p.department, coalesce(c.name, '') as category, v.size, v.color, coalesce(v.sku, '') as sku,
                       p.price, v.stock, p.min_stock, v.active and p.active as sellable
                from product_variant v join product p on p.id = v.product_id left join category c on c.id = p.category_id
                where v.tenant_id = ? order by p.name, v.size limit ?""", TenantContext.get(), MAX_ROWS);
        StringBuilder sb = new StringBuilder("Produto;Departamento;Categoria;Tamanho;Cor;SKU;Preço;Estoque;Mínimo;À venda\n");
        for (Map<String, Object> r : rows) {
            sb.append(cell(r.get("name"))).append(';').append(cell(r.get("department"))).append(';').append(cell(r.get("category")))
                    .append(';').append(cell(r.get("size"))).append(';').append(cell(r.get("color"))).append(';').append(cell(r.get("sku")))
                    .append(';').append(num(r.get("price"))).append(';').append(r.get("stock")).append(';').append(r.get("min_stock"))
                    .append(';').append(Boolean.TRUE.equals(r.get("sellable")) ? "sim" : "não").append('\n');
        }
        return csv("estoque-" + LocalDate.now(clock) + ".csv", sb);
    }

    private static ResponseEntity<byte[]> csv(String filename, StringBuilder body) {
        // BOM para o Excel entender os acentos
        byte[] bytes = ("﻿" + body).getBytes(StandardCharsets.UTF_8);
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + filename + "\"")
                .contentType(new MediaType("text", "csv", StandardCharsets.UTF_8)).body(bytes);
    }

    /** Valor de célula: aspas dobradas e, contra injeção de fórmula no Excel, prefixo ' em texto que começa com = + - @. */
    static String cell(Object value) {
        String s = value == null ? "" : String.valueOf(value);
        if (!s.isEmpty() && "=+-@\t\r".indexOf(s.charAt(0)) >= 0) {
            s = "'" + s;
        }
        return "\"" + s.replace("\"", "\"\"") + "\"";
    }

    private static String num(Object value) {
        return value == null ? "" : String.valueOf(value).replace('.', ',');
    }
}
