package com.max.loja.store;

import java.math.BigDecimal;

import com.max.loja.security.AuditService;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import com.max.loja.shared.TenantContext;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class StoreService {

    public record StoreRequest(@NotBlank @Size(max = 120) String name, @Size(max = 30) String whatsapp,
                               @Size(max = 80) String instagram, @Size(max = 300) String pickupAddress,
                               boolean pickupEnabled, boolean deliveryEnabled,
                               @NotNull @DecimalMin("0") @Digits(integer = 8, fraction = 2) BigDecimal deliveryFee,
                               @DecimalMin("0") @Digits(integer = 8, fraction = 2) BigDecimal freeDeliveryFrom) {
    }

    public record StoreResponse(Long id, String slug, String name, String whatsapp, String instagram, String pickupAddress,
                                boolean pickupEnabled, boolean deliveryEnabled, BigDecimal deliveryFee,
                                BigDecimal freeDeliveryFrom) {

        public static StoreResponse from(Store s) {
            return new StoreResponse(s.getId(), s.getSlug(), s.getName(), s.getWhatsapp(), s.getInstagram(),
                    s.getPickupAddress(), s.isPickupEnabled(), s.isDeliveryEnabled(), s.getDeliveryFee(),
                    s.getFreeDeliveryFrom());
        }
    }

    /** Cartão da busca de lojas no app do cliente. */
    public record StoreCard(Long id, String slug, String name, String instagram) {

        static StoreCard from(Store s) {
            return new StoreCard(s.getId(), s.getSlug(), s.getName(), s.getInstagram());
        }
    }

    private final StoreRepository stores;
    private final AuditService audit;

    public StoreService(StoreRepository stores, AuditService audit) {
        this.stores = stores;
        this.audit = audit;
    }

    /** Loja da requisição (JWT da equipe ou slug da URL). */
    @Transactional(readOnly = true)
    public Store current() {
        return stores.findById(TenantContext.get()).orElseThrow(() -> new NotFoundException("Loja não encontrada"));
    }

    @Transactional(readOnly = true)
    public PageResponse<StoreCard> search(String q, Integer page, Integer size) {
        return PageResponse.of(stores.search(q == null ? "" : q.trim(), false, PageResponse.request(page, size, Sort.by("name"))),
                StoreCard::from);
    }

    @Transactional
    public StoreResponse update(StoreRequest req, Long actorId) {
        if (!req.pickupEnabled() && !req.deliveryEnabled()) {
            throw new BusinessException("Deixe pelo menos retirada ou entrega ligada");
        }
        Store s = current();
        s.setName(req.name().trim());
        s.setWhatsapp(blank(req.whatsapp()));
        s.setInstagram(blank(req.instagram()));
        s.setPickupAddress(blank(req.pickupAddress()));
        s.setPickupEnabled(req.pickupEnabled());
        s.setDeliveryEnabled(req.deliveryEnabled());
        s.setDeliveryFee(req.deliveryFee());
        s.setFreeDeliveryFrom(req.freeDeliveryFrom());
        audit.record(AuditService.STORE_SETTINGS, actorId, null);
        return StoreResponse.from(s);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
