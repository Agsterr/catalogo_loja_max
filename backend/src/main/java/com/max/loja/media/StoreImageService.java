package com.max.loja.media;

import java.io.IOException;
import java.util.UUID;

import com.max.loja.shared.BusinessException;
import com.max.loja.store.Store;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;

/** Logo e capa da loja: mesma compressão das fotos dos produtos, gravadas no R2 (ou disco). */
@Service
public class StoreImageService {

    public enum Kind { LOGO, COVER }

    private final ImageProcessor images;
    private final MediaStorage storage;

    public StoreImageService(ImageProcessor images, MediaStorage storage) {
        this.images = images;
        this.storage = storage;
    }

    /** Troca a imagem (a antiga sai do R2 depois do commit). Chamar dentro de uma transação. */
    public void replace(Store store, Kind kind, MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException("Escolha uma imagem.");
        }
        ImageProcessor.Processed processed;
        try {
            processed = images.process(file.getBytes());
        } catch (IOException e) {
            throw new BusinessException("Não foi possível ler a imagem. Tente de novo.");
        }
        String key = "lojas/" + store.getId() + "/" + kind.name().toLowerCase() + "-" + UUID.randomUUID() + ".jpg";
        // logo usa a versão reduzida (480 px); capa, a grande
        String url = storage.put(key, kind == Kind.LOGO ? processed.thumb() : processed.image(), "image/jpeg");
        String old = kind == Kind.LOGO ? store.getLogoKey() : store.getCoverKey();
        if (kind == Kind.LOGO) {
            store.setLogoKey(key);
            store.setLogoUrl(url);
        } else {
            store.setCoverKey(key);
            store.setCoverUrl(url);
        }
        afterCommit(old, key);
    }

    public void remove(Store store, Kind kind) {
        String old = kind == Kind.LOGO ? store.getLogoKey() : store.getCoverKey();
        if (kind == Kind.LOGO) {
            store.setLogoKey(null);
            store.setLogoUrl(null);
        } else {
            store.setCoverKey(null);
            store.setCoverUrl(null);
        }
        afterCommit(old, null);
    }

    /** Commit: apaga a antiga. Rollback: apaga a nova (não sobra arquivo órfão). */
    private void afterCommit(String old, String fresh) {
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCompletion(int status) {
                if (status == STATUS_COMMITTED) {
                    if (old != null) {
                        storage.delete(old);
                    }
                } else if (fresh != null) {
                    storage.delete(fresh);
                }
            }
        });
    }
}
