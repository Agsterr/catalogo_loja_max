package com.max.loja.catalog;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import com.max.loja.catalog.CatalogDtos.CategoryRequest;
import com.max.loja.catalog.CatalogDtos.CategoryResponse;
import com.max.loja.catalog.CatalogDtos.ProductCard;
import com.max.loja.catalog.CatalogDtos.ProductRequest;
import com.max.loja.catalog.CatalogDtos.ProductResponse;
import com.max.loja.catalog.CatalogDtos.VariantRequest;
import com.max.loja.media.ProductPhotoService;
import com.max.loja.promotion.PricingService;
import com.max.loja.promotion.Promotion;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import jakarta.persistence.criteria.Predicate;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProductService {

    /** Filtros da vitrine. {@code sort}: novidades (padrão), menor-preco, maior-preco, nome. */
    public record Filter(Department department, Long categoryId, String q, boolean onSale, boolean featured,
                         boolean includeInactive, String sort) {
    }

    private final ProductRepository products;
    private final CategoryRepository categories;
    private final StockService stock;
    private final PricingService pricing;
    private final ProductPhotoService photos;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    public ProductService(ProductRepository products, CategoryRepository categories, StockService stock,
                          PricingService pricing, ProductPhotoService photos, JdbcTemplate jdbc, Clock clock) {
        this.products = products;
        this.categories = categories;
        this.stock = stock;
        this.pricing = pricing;
        this.photos = photos;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    // --- vitrine ---

    @Transactional(readOnly = true)
    public PageResponse<ProductCard> search(Filter f, Integer page, Integer size) {
        List<Promotion> running = pricing.running();
        Sort sort = switch (f.sort() == null ? "" : f.sort()) {
            case "menor-preco" -> Sort.by("price").ascending();
            case "maior-preco" -> Sort.by("price").descending();
            case "nome" -> Sort.by("name");
            default -> Sort.by(Sort.Order.desc("featured"), Sort.Order.desc("createdAt"));
        };
        Page<Product> result = products.findAll(spec(f, running), PageResponse.request(page, size, sort.and(Sort.by("id"))));
        return PageResponse.of(result, p -> ProductCard.from(p, pricing.price(p, running)));
    }

    private static Specification<Product> spec(Filter f, List<Promotion> running) {
        return (root, query, cb) -> {
            List<Predicate> where = new ArrayList<>();
            if (!f.includeInactive()) {
                where.add(cb.isTrue(root.get("active")));
            }
            if (f.department() != null) {
                where.add(cb.equal(root.get("department"), f.department()));
            }
            if (f.categoryId() != null) {
                where.add(cb.equal(root.get("category").get("id"), f.categoryId()));
            }
            if (f.featured()) {
                where.add(cb.isTrue(root.get("featured")));
            }
            if (f.q() != null && !f.q().isBlank()) {
                String like = "%" + f.q().trim().toLowerCase(Locale.ROOT).replace("%", "").replace("_", "") + "%";
                where.add(cb.or(cb.like(cb.lower(root.get("name")), like), cb.like(cb.lower(root.get("brand")), like)));
            }
            if (f.onSale()) {
                // promoções em andamento já carregadas: viram condições simples (sem subconsulta)
                List<Predicate> sale = new ArrayList<>();
                sale.add(cb.isNotNull(root.get("salePrice")));
                for (Promotion p : running) {
                    if (p.getProduct() != null) {
                        sale.add(cb.equal(root.get("id"), p.getProduct().getId()));
                    } else if (p.getCategory() != null) {
                        sale.add(cb.equal(root.get("category").get("id"), p.getCategory().getId()));
                    } else if (p.getDepartment() != null) {
                        sale.add(cb.equal(root.get("department"), p.getDepartment()));
                    } else {
                        sale.add(cb.conjunction());
                    }
                }
                where.add(cb.or(sale.toArray(Predicate[]::new)));
            }
            return cb.and(where.toArray(Predicate[]::new));
        };
    }

    @Transactional(readOnly = true)
    public ProductResponse get(Long id, boolean includeInactive) {
        Product p = products.findById(id).filter(x -> includeInactive || x.isActive())
                .orElseThrow(() -> new NotFoundException("Produto não encontrado"));
        return ProductResponse.from(p, pricing.price(p, pricing.running()), !includeInactive);
    }

    // --- gestão ---

    @Transactional
    public ProductResponse create(ProductRequest req, Long userId) {
        Product p = new Product();
        p.setCreatedAt(LocalDateTime.now(clock));
        apply(p, req);
        products.save(p);
        applyVariants(p, req.variants(), userId);
        return ProductResponse.from(p, pricing.price(p, pricing.running()), false);
    }

    @Transactional
    public ProductResponse update(Long id, ProductRequest req, Long userId) {
        Product p = products.findById(id).orElseThrow(() -> new NotFoundException("Produto não encontrado"));
        apply(p, req);
        applyVariants(p, req.variants(), userId);
        return ProductResponse.from(p, pricing.price(p, pricing.running()), false);
    }

    /** Exclui se nunca foi vendido; senão só desativa (o histórico dos pedidos aponta para ele). */
    @Transactional
    public boolean delete(Long id) {
        Product p = products.findById(id).orElseThrow(() -> new NotFoundException("Produto não encontrado"));
        Integer sold = jdbc.queryForObject("select count(*) from order_item where product_id = ?", Integer.class, id);
        if (sold != null && sold > 0) {
            p.setActive(false);
            return false;
        }
        photos.deleteFilesAfterCommit(id);
        jdbc.update("delete from product_photo where product_id = ?", id);
        products.delete(p);
        return true;
    }

    private void apply(Product p, ProductRequest req) {
        if (req.salePrice() != null && req.salePrice().compareTo(req.price()) >= 0) {
            throw new BusinessException("O preço promocional precisa ser menor que o preço normal");
        }
        Category category = null;
        if (req.categoryId() != null) {
            category = categories.findById(req.categoryId()).orElseThrow(() -> new NotFoundException("Categoria não encontrada"));
            if (category.getDepartment() != req.department()) {
                throw new BusinessException("A categoria " + category.getName() + " é de " + category.getDepartment().label());
            }
        }
        p.setName(req.name().trim());
        p.setDescription(req.description() == null || req.description().isBlank() ? null : req.description().trim());
        p.setDepartment(req.department());
        p.setCategory(category);
        p.setBrand(req.brand() == null || req.brand().isBlank() ? null : req.brand().trim());
        p.setPrice(req.price());
        p.setSalePrice(req.salePrice());
        p.setMinStock(req.minStock());
        p.setActive(req.active());
        p.setFeatured(req.featured());
        p.setUpdatedAt(LocalDateTime.now(clock));
    }

    /** Tamanhos/cores enviados substituem a lista: os que sumiram são desativados (podem estar em pedidos). */
    private void applyVariants(Product p, List<VariantRequest> list, Long userId) {
        Map<Long, ProductVariant> existing = new HashMap<>();
        p.getVariants().forEach(v -> existing.put(v.getId(), v));
        Set<String> seen = new HashSet<>();
        Set<Long> kept = new HashSet<>();
        for (VariantRequest r : list) {
            String size = r.size().trim();
            String color = r.color() == null ? "" : r.color().trim();
            if (!seen.add((size + "|" + color).toLowerCase(Locale.ROOT))) {
                throw new BusinessException("Tamanho " + size + (color.isEmpty() ? "" : " " + color) + " repetido");
            }
            ProductVariant v;
            if (r.id() != null) {
                v = existing.get(r.id());
                if (v == null) {
                    throw new BusinessException("Tamanho/cor não pertence a este produto");
                }
                kept.add(v.getId());
            } else {
                v = new ProductVariant();
                v.setProduct(p);
                p.getVariants().add(v);
            }
            v.setSize(size);
            v.setColor(color);
            v.setSku(r.sku() == null || r.sku().isBlank() ? null : r.sku().trim());
            v.setActive(r.active());
            if (r.id() == null) {
                products.flush(); // gera o id para o histórico do estoque
                if (r.initialStock() > 0) {
                    stock.apply(v, r.initialStock(), StockMovement.Type.IN, "Estoque inicial", null, userId);
                }
            }
        }
        existing.values().stream().filter(v -> !kept.contains(v.getId())).forEach(v -> v.setActive(false));
    }

    // --- categorias ---

    @Transactional(readOnly = true)
    public List<CategoryResponse> categories(boolean includeInactive) {
        return (includeInactive ? categories.findAllByOrderByDepartmentAscPositionAscNameAsc()
                : categories.findByActiveTrueOrderByDepartmentAscPositionAscNameAsc()).stream()
                .map(CategoryResponse::from).toList();
    }

    @Transactional
    public CategoryResponse saveCategory(Long id, CategoryRequest req) {
        Category c = id == null ? new Category()
                : categories.findById(id).orElseThrow(() -> new NotFoundException("Categoria não encontrada"));
        if (id != null && c.getDepartment() != req.department()) {
            Integer used = jdbc.queryForObject("select count(*) from product where category_id = ?", Integer.class, id);
            if (used != null && used > 0) {
                throw new BusinessException("A categoria tem produtos; não dá para trocar o departamento");
            }
        }
        c.setDepartment(req.department());
        c.setName(req.name().trim());
        c.setPosition(req.position());
        c.setActive(req.active());
        return CategoryResponse.from(categories.save(c));
    }
}
