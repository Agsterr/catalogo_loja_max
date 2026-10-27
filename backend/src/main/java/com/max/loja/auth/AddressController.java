package com.max.loja.auth;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.shared.BusinessException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Endereços salvos do cliente (valem em todas as lojas): escolhe com um toque ao fechar o pedido. */
@RestController
public class AddressController {

    static final int MAX = 10;

    public record AddressRequest(@NotBlank @Size(max = 40) String label, @NotBlank @Size(min = 10, max = 400) String address) {
    }

    public record AddressResponse(Long id, String label, String address) {
    }

    private final JdbcTemplate jdbc;
    private final Clock clock;

    public AddressController(JdbcTemplate jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @GetMapping("/api/me/addresses")
    public List<AddressResponse> mine(@AuthenticationPrincipal Jwt jwt) {
        return jdbc.query("select id, label, address from customer_address where user_id = ? order by id desc",
                (rs, i) -> new AddressResponse(rs.getLong(1), rs.getString(2), rs.getString(3)), id(jwt));
    }

    @PostMapping("/api/me/addresses")
    @ResponseStatus(HttpStatus.CREATED)
    @Transactional
    public AddressResponse add(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody AddressRequest req) {
        Integer count = jdbc.queryForObject("select count(*) from customer_address where user_id = ?", Integer.class, id(jwt));
        if (count != null && count >= MAX) {
            throw new BusinessException("Você já tem " + MAX + " endereços salvos. Apague um para salvar outro.");
        }
        Long newId = jdbc.queryForObject(
                "insert into customer_address (user_id, label, address, created_at) values (?, ?, ?, ?) returning id",
                Long.class, id(jwt), req.label().trim(), req.address().trim(), LocalDateTime.now(clock));
        return new AddressResponse(newId, req.label().trim(), req.address().trim());
    }

    /** Só apaga endereço do próprio usuário. */
    @DeleteMapping("/api/me/addresses/{addressId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void remove(@AuthenticationPrincipal Jwt jwt, @PathVariable Long addressId) {
        jdbc.update("delete from customer_address where id = ? and user_id = ?", addressId, id(jwt));
    }

    private static Long id(Jwt jwt) {
        return Long.valueOf(jwt.getSubject());
    }
}
