package com.max.loja.catalog;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.media.ProductPhoto;
import com.max.loja.media.ProductPhotoService.PhotoResponse;
import com.max.loja.promotion.PricingService.Price;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class CatalogDtos {

    private CatalogDtos() {
    }

    public record CategoryRequest(@NotNull Department department, @NotBlank @Size(max = 80) String name,
                                  @Min(0) @Max(9999) int position, boolean active) {
    }

    public record CategoryResponse(Long id, Department department, String departmentLabel, String name, int position,
                                   boolean active) {

        public static CategoryResponse from(Category c) {
            return new CategoryResponse(c.getId(), c.getDepartment(), c.getDepartment().label(), c.getName(),
                    c.getPosition(), c.isActive());
        }
    }

    /**
     * Tamanho/cor. Com {@code id}: atualiza o existente (o estoque muda só por movimentação); sem: cria, com
     * {@code initialStock} lançado como entrada.
     */
    public record VariantRequest(Long id, @NotBlank @Size(max = 20) String size, @Size(max = 40) String color,
                                 @Size(max = 60) String sku, @Min(0) @Max(100000) int initialStock, boolean active) {
    }

    public record ProductRequest(
            @NotBlank @Size(max = 150) String name,
            @Size(max = 4000) String description,
            @NotNull Department department,
            Long categoryId,
            @Size(max = 80) String brand,
            @NotNull @DecimalMin("0.01") @Digits(integer = 8, fraction = 2) BigDecimal price,
            @DecimalMin("0.01") @Digits(integer = 8, fraction = 2) BigDecimal salePrice,
            @Min(0) @Max(10000) int minStock,
            boolean active,
            boolean featured,
            @NotEmpty @Size(max = 60) List<@Valid VariantRequest> variants) {
    }

    public record StockRequest(@NotNull StockMovement.Type type, @Min(0) @Max(100000) int quantity,
                               @Size(max = 200) String note) {
    }

    public record VariantResponse(Long id, String size, String color, String sku, int stock, boolean active) {

        static VariantResponse from(ProductVariant v) {
            return new VariantResponse(v.getId(), v.getSize(), v.getColor(), v.getSku(), v.getStock(), v.isActive());
        }
    }

    /** Produto completo (tela do produto e edição). */
    public record ProductResponse(Long id, String name, String description, Department department, String departmentLabel,
                                  Long categoryId, String categoryName, String brand, BigDecimal price,
                                  BigDecimal salePrice, BigDecimal finalPrice, int discountPercent, String promotion,
                                  int minStock, boolean active, boolean featured, int totalStock,
                                  List<VariantResponse> variants, List<PhotoResponse> photos, LocalDateTime createdAt) {

        static ProductResponse from(Product p, Price price, boolean onlyAvailable) {
            Category c = p.getCategory();
            return new ProductResponse(p.getId(), p.getName(), p.getDescription(), p.getDepartment(),
                    p.getDepartment().label(), c != null ? c.getId() : null, c != null ? c.getName() : null, p.getBrand(),
                    price.price(), p.getSalePrice(), price.finalPrice(), price.discountPercent(), price.promotion(),
                    p.getMinStock(), p.isActive(), p.isFeatured(), p.totalStock(),
                    p.getVariants().stream().filter(v -> !onlyAvailable || v.isActive()).map(VariantResponse::from).toList(),
                    p.getPhotos().stream().map(PhotoResponse::from).toList(), p.getCreatedAt());
        }
    }

    /** Cartão da vitrine (lista). */
    public record ProductCard(Long id, String name, Department department, String brand, BigDecimal price,
                              BigDecimal finalPrice, int discountPercent, String thumbUrl, boolean inStock,
                              boolean featured, int totalStock, boolean active) {

        static ProductCard from(Product p, Price price) {
            ProductPhoto cover = p.getPhotos().isEmpty() ? null : p.getPhotos().get(0);
            int stock = p.totalStock();
            return new ProductCard(p.getId(), p.getName(), p.getDepartment(), p.getBrand(), price.price(),
                    price.finalPrice(), price.discountPercent(), cover != null ? cover.getThumbUrl() : null, stock > 0,
                    p.isFeatured(), stock, p.isActive());
        }
    }

    public record MovementResponse(Long id, StockMovement.Type type, int quantity, int stockAfter, String note,
                                   Long orderId, LocalDateTime createdAt) {

        static MovementResponse from(StockMovement m) {
            return new MovementResponse(m.getId(), m.getType(), m.getQuantity(), m.getStockAfter(), m.getNote(),
                    m.getOrderId(), m.getCreatedAt());
        }
    }

    public record LowStockResponse(Long productId, String productName, Long variantId, String variant, int stock,
                                   int minStock) {

        static LowStockResponse from(ProductVariant v) {
            return new LowStockResponse(v.getProduct().getId(), v.getProduct().getName(), v.getId(), v.label(),
                    v.getStock(), v.getProduct().getMinStock());
        }
    }
}
