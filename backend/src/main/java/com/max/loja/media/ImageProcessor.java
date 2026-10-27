package com.max.loja.media;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Iterator;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReadParam;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.MemoryCacheImageOutputStream;

import com.max.loja.shared.BusinessException;
import org.springframework.stereotype.Component;

/**
 * Redimensiona e comprime as fotos no upload (lado maior {@value #MAX_SIDE}px, JPEG ~80%) e gera a
 * miniatura. Só ImageIO do próprio Java; uma foto por vez para caber no -Xmx256m do servidor.
 */
@Component
class ImageProcessor {

    static final int MAX_SIDE = 1600;
    static final int THUMB_SIDE = 480;
    private static final long MAX_PIXELS = 50_000_000L;

    record Processed(byte[] image, int width, int height, byte[] thumb) {
    }

    private final Semaphore oneAtATime = new Semaphore(1);

    Processed process(byte[] data) {
        try {
            if (!oneAtATime.tryAcquire(30, TimeUnit.SECONDS)) {
                throw new BusinessException("Servidor ocupado com outra foto. Tente de novo em instantes.");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new BusinessException("Envio interrompido. Tente de novo.");
        }
        try {
            BufferedImage source = read(data);
            BufferedImage image = orient(scale(source, MAX_SIDE), jpegOrientation(data));
            source = null;
            BufferedImage thumb = scale(image, THUMB_SIDE);
            return new Processed(jpeg(image, 0.8f), image.getWidth(), image.getHeight(), jpeg(thumb, 0.75f));
        } catch (IOException e) {
            throw new BusinessException("Não foi possível ler a foto. Envie um arquivo JPG ou PNG.");
        } finally {
            oneAtATime.release();
        }
    }

    /** Só JPEG e PNG (confere o conteúdo, não a extensão). Fotos enormes são lidas já reduzidas. */
    private static BufferedImage read(byte[] data) throws IOException {
        try (ImageInputStream in = ImageIO.createImageInputStream(new ByteArrayInputStream(data))) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(in);
            if (!readers.hasNext()) {
                throw new BusinessException("Formato não suportado. Envie uma foto JPG ou PNG.");
            }
            ImageReader reader = readers.next();
            try {
                String format = reader.getFormatName().toLowerCase();
                if (!format.equals("jpeg") && !format.equals("png")) {
                    throw new BusinessException("Formato não suportado. Envie uma foto JPG ou PNG.");
                }
                reader.setInput(in, true, true);
                int w = reader.getWidth(0), h = reader.getHeight(0);
                if ((long) w * h > MAX_PIXELS) {
                    throw new BusinessException("Foto grande demais. Envie uma de até 50 megapixels.");
                }
                ImageReadParam param = reader.getDefaultReadParam();
                int step = Math.max(1, Math.max(w, h) / (MAX_SIDE * 2));
                param.setSourceSubsampling(step, step, 0, 0);
                return reader.read(0, param);
            } finally {
                reader.dispose();
            }
        }
    }

    /** Reduz (nunca amplia) para caber em max×max, em etapas para não serrilhar; fundo branco no lugar da transparência. */
    static BufferedImage scale(BufferedImage src, int max) {
        int w = src.getWidth(), h = src.getHeight();
        double ratio = Math.min(1.0, (double) max / Math.max(w, h));
        int targetW = Math.max(1, (int) Math.round(w * ratio)), targetH = Math.max(1, (int) Math.round(h * ratio));
        BufferedImage current = src;
        do {
            int nextW = Math.max(targetW, current.getWidth() / 2);
            int nextH = Math.max(targetH, current.getHeight() / 2);
            if (current != src && nextW == current.getWidth() && nextH == current.getHeight()) {
                break;
            }
            BufferedImage next = new BufferedImage(nextW, nextH, BufferedImage.TYPE_INT_RGB);
            Graphics2D g = next.createGraphics();
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            g.drawImage(current, 0, 0, nextW, nextH, Color.WHITE, null);
            g.dispose();
            current = next;
        } while (current.getWidth() > targetW || current.getHeight() > targetH);
        return current;
    }

    /** Gira conforme a orientação EXIF da câmera (3 = 180°, 6 = 90° horário, 8 = 90° anti-horário). */
    static BufferedImage orient(BufferedImage img, int orientation) {
        if (orientation != 3 && orientation != 6 && orientation != 8) {
            return img;
        }
        int w = img.getWidth(), h = img.getHeight();
        boolean swap = orientation != 3;
        BufferedImage out = new BufferedImage(swap ? h : w, swap ? w : h, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = out.createGraphics();
        switch (orientation) {
            case 3 -> { g.translate(w, h); g.rotate(Math.PI); }
            case 6 -> { g.translate(h, 0); g.rotate(Math.PI / 2); }
            default -> { g.translate(0, w); g.rotate(-Math.PI / 2); }
        }
        g.drawImage(img, 0, 0, null);
        g.dispose();
        return out;
    }

    /** Lê a tag Orientation (0x0112) do EXIF de um JPEG; 1 quando não há. */
    static int jpegOrientation(byte[] d) {
        if (d.length < 4 || (d[0] & 0xff) != 0xFF || (d[1] & 0xff) != 0xD8) {
            return 1;
        }
        int i = 2;
        while (i + 4 <= d.length && (d[i] & 0xff) == 0xFF) {
            int marker = d[i + 1] & 0xff;
            int len = ((d[i + 2] & 0xff) << 8) | (d[i + 3] & 0xff);
            if (marker == 0xDA || len < 2) {
                break;
            }
            int start = i + 4;
            if (marker == 0xE1 && start + 14 <= d.length && d[start] == 'E' && d[start + 1] == 'x'
                    && d[start + 2] == 'i' && d[start + 3] == 'f') {
                int tiff = start + 6;
                boolean le = d[tiff] == 'I';
                int ifd = tiff + read(d, tiff + 4, 4, le);
                if (ifd + 2 > d.length) {
                    return 1;
                }
                int entries = read(d, ifd, 2, le);
                for (int e = 0; e < entries; e++) {
                    int entry = ifd + 2 + e * 12;
                    if (entry + 12 > d.length) {
                        break;
                    }
                    if (read(d, entry, 2, le) == 0x0112) {
                        return read(d, entry + 8, 2, le);
                    }
                }
                return 1;
            }
            i += 2 + len;
        }
        return 1;
    }

    private static int read(byte[] d, int pos, int size, boolean littleEndian) {
        int v = 0;
        for (int k = 0; k < size; k++) {
            int b = d[pos + (littleEndian ? size - 1 - k : k)] & 0xff;
            v = (v << 8) | b;
        }
        return v;
    }

    static byte[] jpeg(BufferedImage img, float quality) throws IOException {
        ImageWriter writer = ImageIO.getImageWritersByFormatName("jpeg").next();
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (MemoryCacheImageOutputStream out = new MemoryCacheImageOutputStream(bytes)) {
            writer.setOutput(out);
            ImageWriteParam param = writer.getDefaultWriteParam();
            param.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
            param.setCompressionQuality(quality);
            writer.write(null, new IIOImage(img, null, null), param);
        } finally {
            writer.dispose();
        }
        return bytes.toByteArray();
    }
}
