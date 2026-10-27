package com.max.loja.media;

import java.nio.file.Path;
import java.time.Duration;

import org.springframework.context.annotation.Configuration;
import org.springframework.http.CacheControl;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** Sem R2, as fotos dos produtos gravadas no disco são servidas em /api/public/media/** (nomes aleatórios, cache longo). */
@Configuration
class MediaWebConfig implements WebMvcConfigurer {

    private final MediaProperties props;

    MediaWebConfig(MediaProperties props) {
        this.props = props;
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        String location = Path.of(props.storagePath()).toAbsolutePath().normalize().toUri().toString();
        registry.addResourceHandler("/api/public/media/**")
                .addResourceLocations(location.endsWith("/") ? location : location + "/")
                .setCacheControl(CacheControl.maxAge(Duration.ofDays(365)).cachePublic().immutable());
    }
}
