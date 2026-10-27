package com.max.loja.catalog;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.catalog.CatalogDtos.LowStockResponse;
import com.max.loja.catalog.CatalogDtos.MovementResponse;
import com.max.loja.catalog.CatalogDtos.VariantResponse;
import com.max.loja.event.StoreEvents;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Toda mudança de estoque passa por aqui: grava o histórico e avisa a equipe quando um tamanho/cor chega no
 * mínimo (evento {@link StoreEvents.StockLow}) e os clientes que pediram "avise-me" quando
 * um tamanho/cor esgotado volta ({@link StoreEvents.BackInStock}).
 */
@Service
public class StockService {

    private final ProductVariantRepository variants;
    private final StockMovementRepository movements;
    private final ApplicationEventPublisher events;
    private final Clock clock;

    public StockService(ProductVariantRepository variants, StockMovementRepository movements,
                        ApplicationEventPublisher events, Clock clock) {
        this.variants = variants;
        this.movements = movements;
        this.events = events;
        this.clock = clock;
    }

    /** Lançamento manual da equipe (entrada, acerto de contagem, perda). */
    @Transactional
    public VariantResponse move(Long variantId, CatalogDtos.StockRequest req, Long userId) {
        ProductVariant v = variants.lock(variantId).orElseThrow(() -> new NotFoundException("Tamanho/cor não encontrado"));
        int delta = switch (req.type()) {
            case IN -> req.quantity();
            case LOSS -> -req.quantity();
            case ADJUST -> req.quantity() - v.getStock();
            case SALE, RETURN -> throw new BusinessException("Vendas e devoluções entram pelos pedidos");
        };
        if (req.type() != StockMovement.Type.ADJUST && req.quantity() == 0) {
            throw new BusinessException("Informe a quantidade");
        }
        apply(v, delta, req.type(), req.note(), null, userId);
        return VariantResponse.from(v);
    }

    /** Aplica a variação já com a linha travada. Nunca deixa o estoque negativo. */
    public void apply(ProductVariant v, int delta, StockMovement.Type type, String note, Long orderId, Long userId) {
        int before = v.getStock();
        int after = before + delta;
        if (after < 0) {
            throw new BusinessException("Estoque insuficiente de " + v.getProduct().getName() + " (" + v.label()
                    + "): restam " + before);
        }
        v.setStock(after);
        StockMovement m = new StockMovement();
        m.setVariantId(v.getId());
        m.setType(type);
        m.setQuantity(delta);
        m.setStockAfter(after);
        m.setNote(note == null || note.isBlank() ? null : note.trim());
        m.setOrderId(orderId);
        m.setUserId(userId);
        m.setCreatedAt(LocalDateTime.now(clock));
        movements.save(m);

        Product p = v.getProduct();
        if (delta < 0 && v.isActive() && p.isActive() && after <= p.getMinStock() && before > p.getMinStock()
                || delta < 0 && after == 0 && before > 0) {
            events.publishEvent(new StoreEvents.StockLow(p.getId(), v.getId(), p.getName(), v.label(), after));
        }
        if (delta > 0 && before == 0 && p.isActive() && v.isActive()) {
            events.publishEvent(new StoreEvents.BackInStock(p.getId(), p.getName(), v.label()));
        }
    }

    @Transactional(readOnly = true)
    public PageResponse<MovementResponse> history(Long variantId, Integer page, Integer size) {
        variants.findById(variantId).orElseThrow(() -> new NotFoundException("Tamanho/cor não encontrado"));
        return PageResponse.of(movements.findByVariantId(variantId,
                PageResponse.request(page, size, Sort.by(Sort.Order.desc("id")))),
                MovementResponse::from);
    }

    @Transactional(readOnly = true)
    public List<LowStockResponse> lowStock() {
        return variants.findLowStock().stream().map(LowStockResponse::from).toList();
    }
}
