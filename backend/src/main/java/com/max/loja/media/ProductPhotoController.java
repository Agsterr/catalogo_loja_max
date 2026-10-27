package com.max.loja.media;

import java.util.List;

import com.max.loja.media.ProductPhotoService.PhotoResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/** Fotos dos produtos (equipe). */
@RestController
public class ProductPhotoController {

    public record ReorderRequest(@NotNull List<Long> ids) {
    }

    private final ProductPhotoService service;

    public ProductPhotoController(ProductPhotoService service) {
        this.service = service;
    }

    @GetMapping("/api/store/products/{productId}/photos")
    public List<PhotoResponse> list(@PathVariable Long productId) {
        return service.list(productId);
    }

    @PostMapping(path = "/api/store/products/{productId}/photos", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public PhotoResponse upload(@PathVariable Long productId, @RequestParam("file") MultipartFile file,
                                @RequestParam(required = false) @Size(max = 40) String color) {
        return service.upload(productId, file, color);
    }

    public record ColorRequest(@Size(max = 40) String color) {
    }

    @PutMapping("/api/store/photos/{photoId}/color")
    public PhotoResponse color(@PathVariable Long photoId, @Valid @RequestBody ColorRequest req) {
        return service.setColor(photoId, req.color());
    }

    @PutMapping("/api/store/products/{productId}/photos/order")
    public List<PhotoResponse> reorder(@PathVariable Long productId, @RequestBody ReorderRequest req) {
        return service.reorder(productId, req.ids());
    }

    @DeleteMapping("/api/store/photos/{photoId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long photoId) {
        service.delete(photoId);
    }
}
