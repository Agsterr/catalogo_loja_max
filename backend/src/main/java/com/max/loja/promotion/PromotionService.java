package com.max.loja.promotion;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.catalog.CategoryRepository;
import com.max.loja.catalog.Department;
import com.max.loja.catalog.ProductRepository;
import com.max.loja.event.StoreEvents;
import com.max.loja.security.AuditService;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PromotionService {

    public record PromotionRequest(@NotBlank @Size(max = 120) String title, @Size(max = 500) String description,
                                   @Min(1) @Max(90) int discountPercent, Department department, Long categoryId,
                                   Long productId, @NotNull LocalDateTime startsAt, @NotNull LocalDateTime endsAt,
                                   boolean active, boolean notifyCustomers) {
    }

    public record PromotionResponse(Long id, String title, String description, int discountPercent, Department department,
                                    Long categoryId, Long productId, String scope, LocalDateTime startsAt,
                                    LocalDateTime endsAt, boolean active, boolean running, boolean notifyCustomers,
                                    LocalDateTime notifiedAt) {
    }

    private final PromotionRepository promotions;
    private final CategoryRepository categories;
    private final ProductRepository products;
    private final ApplicationEventPublisher events;
    private final Clock clock;
    private final AuditService audit;

    public PromotionService(PromotionRepository promotions, CategoryRepository categories, ProductRepository products,
                            ApplicationEventPublisher events, Clock clock, AuditService audit) {
        this.audit = audit;
        this.promotions = promotions;
        this.categories = categories;
        this.products = products;
        this.events = events;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<PromotionResponse> all() {
        return promotions.findAllByOrderByStartsAtDesc().stream().map(this::response).toList();
    }

    /** Vitrine: promoções valendo agora. */
    @Transactional(readOnly = true)
    public List<PromotionResponse> running() {
        return promotions.findRunning(LocalDateTime.now(clock)).stream().map(this::response).toList();
    }

    @Transactional
    public PromotionResponse save(Long id, PromotionRequest req, Long actorId) {
        if (!req.endsAt().isAfter(req.startsAt())) {
            throw new BusinessException("O fim precisa ser depois do início");
        }
        int scopes = (req.department() != null ? 1 : 0) + (req.categoryId() != null ? 1 : 0) + (req.productId() != null ? 1 : 0);
        if (scopes > 1) {
            throw new BusinessException("Escolha só um: produto, categoria ou departamento (nenhum = loja inteira)");
        }
        Promotion p = id == null ? new Promotion()
                : promotions.findById(id).orElseThrow(() -> new NotFoundException("Promoção não encontrada"));
        if (id == null) {
            p.setCreatedAt(LocalDateTime.now(clock));
        }
        p.setTitle(req.title().trim());
        p.setDescription(req.description() == null || req.description().isBlank() ? null : req.description().trim());
        p.setDiscountPercent(req.discountPercent());
        p.setDepartment(req.department());
        p.setCategory(req.categoryId() == null ? null
                : categories.findById(req.categoryId()).orElseThrow(() -> new NotFoundException("Categoria não encontrada")));
        p.setProduct(req.productId() == null ? null
                : products.findById(req.productId()).orElseThrow(() -> new NotFoundException("Produto não encontrado")));
        // mudou o período para o futuro: avisa de novo quando começar
        if (p.getNotifiedAt() != null && req.startsAt().isAfter(p.getNotifiedAt())) {
            p.setNotifiedAt(null);
        }
        p.setStartsAt(req.startsAt());
        p.setEndsAt(req.endsAt());
        p.setActive(req.active());
        p.setNotifyCustomers(req.notifyCustomers());
        promotions.save(p);
        audit.record(AuditService.PROMOTION_SAVED, actorId, p.getTitle() + " (" + p.getDiscountPercent() + "%)");
        announceStarted();
        return response(p);
    }

    @Transactional
    public void delete(Long id) {
        promotions.delete(promotions.findById(id).orElseThrow(() -> new NotFoundException("Promoção não encontrada")));
    }

    /** Promoções que começaram e ainda não foram anunciadas: publica o evento (push para os clientes) uma vez. */
    @Transactional
    public int announceStarted() {
        LocalDateTime now = LocalDateTime.now(clock);
        List<Promotion> due = promotions.findToAnnounce(now);
        for (Promotion p : due) {
            p.setNotifiedAt(now);
            events.publishEvent(new StoreEvents.PromotionStarted(p.getId()));
        }
        return due.size();
    }

    private PromotionResponse response(Promotion p) {
        return new PromotionResponse(p.getId(), p.getTitle(), p.getDescription(), p.getDiscountPercent(), p.getDepartment(),
                p.getCategory() != null ? p.getCategory().getId() : null, p.getProduct() != null ? p.getProduct().getId() : null,
                p.scopeLabel(), p.getStartsAt(), p.getEndsAt(), p.isActive(), p.runningAt(LocalDateTime.now(clock)),
                p.isNotifyCustomers(), p.getNotifiedAt());
    }
}
