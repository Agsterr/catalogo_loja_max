package com.max.loja.media;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.max.loja.catalog.Product;
import com.max.loja.catalog.ProductRepository;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;

/**
 * Fotos dos produtos: comprime no servidor (lado maior 1600px + miniatura de 480px, sem os dados EXIF/GPS da
 * câmera, que não sobrevivem à recompressão) e grava no Cloudflare R2 com nome aleatório.
 */
@Service
public class ProductPhotoService {

    private static final Logger log = LoggerFactory.getLogger(ProductPhotoService.class);

    public record PhotoResponse(Long id, String url, String thumbUrl, int width, int height, int position) {

        public static PhotoResponse from(ProductPhoto p) {
            return new PhotoResponse(p.getId(), p.getUrl(), p.getThumbUrl(), p.getWidth(), p.getHeight(), p.getPosition());
        }
    }

    private final ProductPhotoRepository photos;
    private final ProductRepository products;
    private final ImageProcessor images;
    private final MediaStorage storage;
    private final MediaProperties props;

    public ProductPhotoService(ProductPhotoRepository photos, ProductRepository products, ImageProcessor images,
                               MediaStorage storage, MediaProperties props) {
        this.photos = photos;
        this.products = products;
        this.images = images;
        this.storage = storage;
        this.props = props;
    }

    @Transactional(readOnly = true)
    public List<PhotoResponse> list(Long productId) {
        return photos.findByProductIdOrderByPositionAscIdAsc(productId).stream().map(PhotoResponse::from).toList();
    }

    @Transactional
    public PhotoResponse upload(Long productId, MultipartFile file) {
        Product product = products.findById(productId).orElseThrow(() -> new NotFoundException("Produto não encontrado"));
        if (file == null || file.isEmpty()) {
            throw new BusinessException("Escolha uma foto.");
        }
        long count = photos.countByProductId(productId);
        if (count >= props.maxPhotosPerProduct()) {
            throw new BusinessException("Cada produto pode ter até " + props.maxPhotosPerProduct() + " fotos.");
        }
        ImageProcessor.Processed processed;
        try {
            processed = images.process(file.getBytes());
        } catch (IOException e) {
            throw new BusinessException("Não foi possível ler a foto. Tente de novo.");
        }
        String base = "produtos/" + productId + "/" + UUID.randomUUID();
        String key = base + ".jpg";
        String thumbKey = base + "-p.jpg";
        String url = storage.put(key, processed.image(), "image/jpeg");
        String thumbUrl;
        try {
            thumbUrl = storage.put(thumbKey, processed.thumb(), "image/jpeg");
        } catch (RuntimeException e) {
            storage.delete(key);
            throw e;
        }
        // se a transação não fechar, os arquivos não ficam órfãos no R2
        deleteOnRollback(List.of(key, thumbKey));

        ProductPhoto photo = new ProductPhoto();
        photo.setProduct(product);
        photo.setStorageKey(key);
        photo.setUrl(url);
        photo.setThumbKey(thumbKey);
        photo.setThumbUrl(thumbUrl);
        photo.setWidth(processed.width());
        photo.setHeight(processed.height());
        photo.setPosition((int) count);
        return PhotoResponse.from(photos.save(photo));
    }

    /** Nova ordem das fotos (a primeira vira a capa). Fotos fora da lista vão para o fim. */
    @Transactional
    public List<PhotoResponse> reorder(Long productId, List<Long> ids) {
        List<ProductPhoto> list = new ArrayList<>(photos.findByProductIdOrderByPositionAscIdAsc(productId));
        list.sort((a, b) -> Integer.compare(indexOf(ids, a.getId()), indexOf(ids, b.getId())));
        for (int i = 0; i < list.size(); i++) {
            list.get(i).setPosition(i);
        }
        return list.stream().map(PhotoResponse::from).toList();
    }

    @Transactional
    public void delete(Long photoId) {
        ProductPhoto photo = photos.findById(photoId).orElseThrow(() -> new NotFoundException("Foto não encontrada"));
        photos.delete(photo);
        deleteAfterCommit(List.of(photo.getStorageKey(), photo.getThumbKey()));
    }

    /** Arquivos dos produtos excluídos (chamado na mesma transação, apaga depois do commit). */
    public void deleteFilesAfterCommit(Long productId) {
        List<String> keys = new ArrayList<>();
        for (ProductPhoto p : photos.findByProductIdOrderByPositionAscIdAsc(productId)) {
            keys.add(p.getStorageKey());
            keys.add(p.getThumbKey());
        }
        deleteAfterCommit(keys);
    }

    private static int indexOf(List<Long> ids, Long id) {
        int i = ids.indexOf(id);
        return i < 0 ? Integer.MAX_VALUE : i;
    }

    private void deleteAfterCommit(List<String> keys) {
        if (keys.isEmpty()) {
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                keys.forEach(storage::delete);
            }
        });
    }

    private void deleteOnRollback(List<String> keys) {
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCompletion(int status) {
                if (status != STATUS_COMMITTED) {
                    log.warn("Upload desfeito; apagando {} arquivos", keys.size());
                    keys.forEach(storage::delete);
                }
            }
        });
    }
}
