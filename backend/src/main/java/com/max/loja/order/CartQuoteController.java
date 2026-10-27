package com.max.loja.order;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import com.max.loja.catalog.ProductVariant;
import com.max.loja.catalog.ProductVariantRepository;
import com.max.loja.order.OrderDtos.ItemRequest;
import com.max.loja.promotion.PricingService;
import com.max.loja.promotion.Promotion;
import com.max.loja.shared.Money;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * Confere o carrinho com a loja antes de fechar: preço de agora (a promoção pode ter acabado), estoque e peças
 * que saíram de venda. Só consulta; quem vale é o pedido.
 */
@RestController
public class CartQuoteController {

    public record QuoteRequest(@NotEmpty @Size(max = 30) List<@Valid ItemRequest> items) {
    }

    /** {@code available}: pode comprar; {@code stock}: quanto tem; {@code quantity}: o que cabe no estoque. */
    public record QuoteLine(Long variantId, boolean available, int stock, int quantity, BigDecimal unitPrice,
                            BigDecimal price, int discountPercent) {
    }

    public record Quote(List<QuoteLine> items, BigDecimal subtotal) {
    }

    private final ProductVariantRepository variants;
    private final PricingService pricing;

    public CartQuoteController(ProductVariantRepository variants, PricingService pricing) {
        this.variants = variants;
        this.pricing = pricing;
    }

    @PostMapping("/api/public/stores/{slug}/cart/quote")
    @Transactional(readOnly = true)
    public Quote quote(@PathVariable String slug, @Valid @RequestBody QuoteRequest req) {
        // só os tamanhos/cores desta loja (filtro do tenant); de outra loja voltam como indisponíveis
        Map<Long, ProductVariant> found = variants.findAllById(req.items().stream().map(ItemRequest::variantId).toList())
                .stream().collect(Collectors.toMap(ProductVariant::getId, Function.identity()));
        List<Promotion> running = pricing.running();
        List<QuoteLine> lines = new ArrayList<>();
        BigDecimal subtotal = BigDecimal.ZERO;
        for (ItemRequest item : req.items()) {
            ProductVariant v = found.get(item.variantId());
            if (v == null || !v.isActive() || !v.getProduct().isActive()) {
                lines.add(new QuoteLine(item.variantId(), false, 0, 0, null, null, 0));
                continue;
            }
            PricingService.Price price = pricing.price(v.getProduct(), running);
            int qty = Math.min(item.quantity(), v.getStock());
            lines.add(new QuoteLine(v.getId(), v.getStock() > 0, v.getStock(), qty, price.finalPrice(), price.price(),
                    price.discountPercent()));
            subtotal = subtotal.add(price.finalPrice().multiply(BigDecimal.valueOf(qty)));
        }
        return new Quote(lines, Money.round(subtotal));
    }
}
