package com.max.loja.notification;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.shared.NotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** "Avise-me quando chegar": quem pediu recebe aviso quando o produto esgotado volta ao estoque. */
@Service
public class ProductWatchService {

    private final JdbcTemplate jdbc;
    private final Clock clock;

    public ProductWatchService(JdbcTemplate jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<Long> mine(Long userId) {
        return jdbc.queryForList("select product_id from product_watch where user_id = ? order by created_at desc",
                Long.class, userId);
    }

    @Transactional
    public void watch(Long userId, Long productId) {
        Integer exists = jdbc.queryForObject("select count(*) from product where id = ? and active", Integer.class, productId);
        if (exists == null || exists == 0) {
            throw new NotFoundException("Produto não encontrado");
        }
        jdbc.update("insert into product_watch (user_id, product_id, created_at) values (?, ?, ?) on conflict do nothing",
                userId, productId, LocalDateTime.now(clock));
    }

    @Transactional
    public void unwatch(Long userId, Long productId) {
        jdbc.update("delete from product_watch where user_id = ? and product_id = ?", userId, productId);
    }

    /** Quem estava esperando o produto (a lista é esvaziada: o aviso sai uma vez). */
    @Transactional
    public List<Long> takeWatchers(Long productId) {
        List<Long> ids = jdbc.queryForList("""
                select w.user_id from product_watch w join app_user u on u.id = w.user_id
                where w.product_id = ? and u.active and not u.blocked""", Long.class, productId);
        jdbc.update("delete from product_watch where product_id = ?", productId);
        return ids;
    }
}
