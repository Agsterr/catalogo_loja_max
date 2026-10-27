package com.max.loja.store;

import com.max.loja.media.StoreImageService;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import com.max.loja.store.StoreService.StoreCard;
import com.max.loja.store.StoreService.StoreRequest;
import com.max.loja.store.StoreService.StoreResponse;
import java.util.List;

import jakarta.validation.Valid;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
public class StoreController {

    private final StoreService service;
    private final StoreImageService images;

    public StoreController(StoreService service, StoreImageService images) {
        this.service = service;
        this.images = images;
    }

    /** Busca de lojas no app do cliente (bloqueadas não aparecem). */
    @GetMapping("/api/public/stores")
    public PageResponse<StoreCard> search(@RequestParam(required = false) String q,
                                          @RequestParam(required = false) String city,
                                          @RequestParam(required = false) String state,
                                          @RequestParam(required = false) Double lat,
                                          @RequestParam(required = false) Double lng,
                                          @RequestParam(required = false) Double radiusKm,
                                          @RequestParam(required = false) Integer page,
                                          @RequestParam(required = false) Integer size) {
        return service.search(cut(q), cut(city), state, lat, lng, radiusKm, page, size);
    }

    /** Cidades que têm loja (filtro "minha cidade" do app). */
    @GetMapping("/api/public/store-cities")
    public List<StoreService.CityCount> cities() {
        return service.cities();
    }

    private static String cut(String s) {
        return s == null || s.length() <= 60 ? s : s.substring(0, 60);
    }

    /** Dados da loja (o tenant já veio do slug, pelo {@code StoreTenantInterceptor}). */
    @GetMapping("/api/public/stores/{slug}")
    public StoreResponse store(@PathVariable String slug) {
        return service.response(service.current());
    }

    @GetMapping("/api/store/settings")
    public StoreResponse mine() {
        return service.response(service.current());
    }

    /** Logo ou capa da loja (dono). {@code kind}: logo ou capa. */
    @PostMapping(path = "/api/store/settings/{kind}", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @Transactional
    public StoreResponse uploadImage(@PathVariable String kind, @RequestParam("file") MultipartFile file) {
        Store store = service.current();
        images.replace(store, kind(kind), file);
        return service.response(store);
    }

    @DeleteMapping("/api/store/settings/{kind}")
    @Transactional
    public StoreResponse removeImage(@PathVariable String kind) {
        Store store = service.current();
        images.remove(store, kind(kind));
        return service.response(store);
    }

    private static StoreImageService.Kind kind(String kind) {
        return switch (kind) {
            case "logo" -> StoreImageService.Kind.LOGO;
            case "capa" -> StoreImageService.Kind.COVER;
            default -> throw new NotFoundException("Não encontrado");
        };
    }

    @PutMapping("/api/store/settings")
    public StoreResponse update(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody StoreRequest req) {
        return service.update(req, Long.valueOf(jwt.getSubject()));
    }
}
