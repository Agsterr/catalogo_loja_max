package com.max.loja.media;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

import javax.imageio.ImageIO;

import com.max.loja.shared.BusinessException;
import org.junit.jupiter.api.Test;

class ImageProcessorTest {

    private final ImageProcessor processor = new ImageProcessor();

    @Test
    void shrinksToMaxSideAndMakesThumbnail() throws IOException {
        ImageProcessor.Processed p = processor.process(png(3000, 2000));

        assertThat(p.width()).isEqualTo(1600);
        assertThat(p.height()).isEqualTo(1067);
        BufferedImage thumb = ImageIO.read(new ByteArrayInputStream(p.thumb()));
        assertThat(Math.max(thumb.getWidth(), thumb.getHeight())).isEqualTo(ImageProcessor.THUMB_SIDE);
        assertThat(ImageIO.read(new ByteArrayInputStream(p.image())).getWidth()).isEqualTo(1600);
    }

    @Test
    void neverEnlargesSmallPhotos() throws IOException {
        ImageProcessor.Processed p = processor.process(png(800, 600));
        assertThat(p.width()).isEqualTo(800);
        assertThat(p.height()).isEqualTo(600);
    }

    @Test
    void rotatesUsingExifOrientation() throws IOException {
        byte[] jpeg = withExifOrientation(jpeg(400, 200), 6);
        assertThat(ImageProcessor.jpegOrientation(jpeg)).isEqualTo(6);

        ImageProcessor.Processed p = processor.process(jpeg);
        assertThat(p.width()).isEqualTo(200);
        assertThat(p.height()).isEqualTo(400);
    }

    @Test
    void rejectsFilesThatAreNotPhotos() {
        assertThatThrownBy(() -> processor.process("não é imagem".getBytes(StandardCharsets.UTF_8)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("JPG ou PNG");
    }

    private static byte[] png(int w, int h) throws IOException {
        return encode(new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB), "png");
    }

    private static byte[] jpeg(int w, int h) throws IOException {
        return encode(new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB), "jpeg");
    }

    private static byte[] encode(BufferedImage img, String format) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(img, format, out);
        return out.toByteArray();
    }

    /** Insere um segmento APP1/EXIF mínimo (big-endian) com a tag Orientation logo após o SOI. */
    private static byte[] withExifOrientation(byte[] jpeg, int orientation) {
        byte[] tiff = {'M', 'M', 0, 42, 0, 0, 0, 8, 0, 1,
                0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, (byte) orientation, 0, 0,
                0, 0, 0, 0};
        byte[] exif = new byte[6 + tiff.length];
        System.arraycopy("Exif\0\0".getBytes(StandardCharsets.ISO_8859_1), 0, exif, 0, 6);
        System.arraycopy(tiff, 0, exif, 6, tiff.length);
        int len = exif.length + 2;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(0xFF);
        out.write(0xD8);
        out.write(0xFF);
        out.write(0xE1);
        out.write(len >> 8);
        out.write(len & 0xff);
        out.writeBytes(exif);
        out.write(jpeg, 2, jpeg.length - 2);
        return out.toByteArray();
    }
}
