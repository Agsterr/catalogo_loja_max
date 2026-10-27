package com.max.loja.promotion;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.catalog.Product;
import com.max.loja.shared.Money;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Preço final de cada produto: o menor entre o preço "por" fixo e o das promoções em andamento. */
@Service
public class PricingService {

    /** {@code discountPercent} é sobre o preço cheio (0 = sem desconto); {@code promotion} é o título da promoção usada. */
    public record Price(BigDecimal price, BigDecimal finalPrice, int discountPercent, String promotion) {

        public boolean onSale() {
            return finalPrice.compareTo(price) < 0;
        }
    }

    private final PromotionRepository promotions;
    private final Clock clock;

    public PricingService(PromotionRepository promotions, Clock clock) {
        this.promotions = promotions;
        this.clock = clock;
    }

    /** Promoções valendo agora (carregue uma vez por requisição e use em {@link #price(Product, List)}). */
    @Transactional(readOnly = true)
    public List<Promotion> running() {
        return promotions.findRunning(LocalDateTime.now(clock));
    }

    public Price price(Product p, List<Promotion> running) {
        BigDecimal best = p.getSalePrice() != null && p.getSalePrice().compareTo(p.getPrice()) < 0 ? p.getSalePrice() : p.getPrice();
        String title = null;
        for (Promotion promo : running) {
            if (promo.appliesTo(p)) {
                BigDecimal v = Money.discount(p.getPrice(), promo.getDiscountPercent());
                if (v.compareTo(best) < 0) {
                    best = v;
                    title = promo.getTitle();
                }
            }
        }
        best = Money.round(best);
        int percent = best.compareTo(p.getPrice()) < 0
                ? BigDecimal.ONE.subtract(best.divide(p.getPrice(), 4, java.math.RoundingMode.HALF_UP))
                        .multiply(BigDecimal.valueOf(100)).setScale(0, java.math.RoundingMode.HALF_UP).intValue()
                : 0;
        return new Price(Money.round(p.getPrice()), best, percent, title);
    }
}
