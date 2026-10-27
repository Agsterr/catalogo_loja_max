package com.max.loja.catalog;

import java.util.List;

import com.max.loja.catalog.CatalogDtos.CategoryRequest;
import com.max.loja.catalog.CatalogDtos.CategoryResponse;
import com.max.loja.catalog.CatalogDtos.LowStockResponse;
import com.max.loja.catalog.CatalogDtos.MovementResponse;
import com.max.loja.catalog.CatalogDtos.ProductCard;
import com.max.loja.catalog.CatalogDtos.ProductRequest;
import com.max.loja.catalog.CatalogDtos.ProductResponse;
import com.max.loja.catalog.CatalogDtos.StockRequest;
import com.max.loja.catalog.CatalogDtos.VariantResponse;
import com.max.loja.shared.PageResponse;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class CatalogController {

    public record DeleteResponse(boolean deleted) {
    }

    private final ProductService products;
    private final StockService stock;

    public CatalogController(ProductService products, StockService stock) {
        this.products = products;
        this.stock = stock;
    }

    // --- vitrine da loja {slug} (pública: dá para olhar sem conta) ---

    @GetMapping("/api/public/stores/{slug}/categories")
    public List<CategoryResponse> publicCategories(@PathVariable String slug) {
        return products.categories(false);
    }

    @GetMapping("/api/public/stores/{slug}/products")
    public PageResponse<ProductCard> publicProducts(@PathVariable String slug,
                                                    @RequestParam(required = false) Department department,
                                                    @RequestParam(required = false) Long categoryId,
                                                    @RequestParam(required = false) String q,
                                                    @RequestParam(defaultValue = "false") boolean onSale,
                                                    @RequestParam(defaultValue = "false") boolean featured,
                                                    @RequestParam(required = false) String sort,
                                                    @RequestParam(required = false) Integer page,
                                                    @RequestParam(required = false) Integer size) {
        return products.search(new ProductService.Filter(department, categoryId, cut(q), onSale, featured, false, sort),
                page, size);
    }

    @GetMapping("/api/public/stores/{slug}/products/{id}")
    public ProductResponse publicProduct(@PathVariable String slug, @PathVariable Long id) {
        return products.get(id, false);
    }

    // --- gestão (equipe) ---

    @GetMapping("/api/store/categories")
    public List<CategoryResponse> categories() {
        return products.categories(true);
    }

    @PostMapping("/api/store/categories")
    @ResponseStatus(HttpStatus.CREATED)
    public CategoryResponse createCategory(@Valid @RequestBody CategoryRequest req) {
        return products.saveCategory(null, req);
    }

    @PutMapping("/api/store/categories/{id}")
    public CategoryResponse updateCategory(@PathVariable Long id, @Valid @RequestBody CategoryRequest req) {
        return products.saveCategory(id, req);
    }

    @GetMapping("/api/store/products")
    public PageResponse<ProductCard> storeProducts(@RequestParam(required = false) Department department,
                                                   @RequestParam(required = false) Long categoryId,
                                                   @RequestParam(required = false) String q,
                                                   @RequestParam(required = false) String sort,
                                                   @RequestParam(required = false) Integer page,
                                                   @RequestParam(required = false) Integer size) {
        return products.search(new ProductService.Filter(department, categoryId, cut(q), false, false, true, sort),
                page, size);
    }

    @GetMapping("/api/store/products/{id}")
    public ProductResponse storeProduct(@PathVariable Long id) {
        return products.get(id, true);
    }

    @PostMapping("/api/store/products")
    @ResponseStatus(HttpStatus.CREATED)
    public ProductResponse create(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody ProductRequest req) {
        return products.create(req, Long.valueOf(jwt.getSubject()));
    }

    @PutMapping("/api/store/products/{id}")
    public ProductResponse update(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id,
                                  @Valid @RequestBody ProductRequest req) {
        return products.update(id, req, Long.valueOf(jwt.getSubject()));
    }

    @DeleteMapping("/api/store/products/{id}")
    public DeleteResponse delete(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id) {
        return new DeleteResponse(products.delete(id, Long.valueOf(jwt.getSubject())));
    }

    @PostMapping("/api/store/variants/{variantId}/stock")
    public VariantResponse move(@AuthenticationPrincipal Jwt jwt, @PathVariable Long variantId,
                                @Valid @RequestBody StockRequest req) {
        return stock.move(variantId, req, Long.valueOf(jwt.getSubject()));
    }

    @GetMapping("/api/store/variants/{variantId}/stock")
    public PageResponse<MovementResponse> history(@PathVariable Long variantId, @RequestParam(required = false) Integer page,
                                                  @RequestParam(required = false) Integer size) {
        return stock.history(variantId, page, size);
    }

    @GetMapping("/api/store/stock/low")
    public List<LowStockResponse> lowStock() {
        return stock.lowStock();
    }

    private static String cut(String q) {
        return q == null ? null : q.length() > 80 ? q.substring(0, 80) : q;
    }
}
