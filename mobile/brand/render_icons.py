"""Gera os ícones e a arte da tela de abertura dos dois apps (Loja Max e Loja Max Lojista).

    python3 mobile/brand/render_icons.py

Depois, em cada app: dart run flutter_launcher_icons && dart run flutter_native_splash:create
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(os.environ.get('FLUTTER_ROOT', '/opt/flutter'), 'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
BRAND = (176, 48, 106)      # #B0306A
SALE = (215, 38, 61)        # #D7263D
DARK = (58, 14, 38)         # #3A0E26 (lojista)

APPS = {
    # app: (pasta, glifo do Material Icons, cor 1, cor 2)
    'cliente': ('../cliente/assets', 0xe59a, BRAND, SALE),        # shopping_bag
    'lojista': ('../lojista/assets', 0xe60c, DARK, BRAND),        # storefront
}


def gradient(size, c1, c2):
    img = Image.new('RGB', (size, size))
    d = ImageDraw.Draw(img)
    for i in range(size * 2):
        t = i / (size * 2)
        color = tuple(int(c1[k] * (1 - t) + c2[k] * t) for k in range(3))
        d.line([(i, 0), (0, i)], fill=color, width=2)
    return img


def glyph(size, code, scale, color=(255, 255, 255, 255)):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(size * scale))
    ch = chr(code)
    box = d.textbbox((0, 0), ch, font=font)
    x = (size - (box[2] - box[0])) / 2 - box[0]
    y = (size - (box[3] - box[1])) / 2 - box[1]
    d.text((x, y), ch, font=font, fill=color)
    return img


for app, (out, code, c1, c2) in APPS.items():
    out = os.path.join(HERE, out)
    os.makedirs(out, exist_ok=True)
    # ícone completo (iOS e Android antigo): fundo em degradê + símbolo branco
    icon = gradient(1024, c1, c2).convert('RGBA')
    icon.alpha_composite(glyph(1024, code, 0.62))
    icon.convert('RGB').save(os.path.join(out, 'icon.png'))
    # ícone adaptativo do Android: fundo e frente separados (a frente fica na área segura de 66%)
    gradient(1024, c1, c2).save(os.path.join(out, 'icon_background.png'))
    glyph(1024, code, 0.42).save(os.path.join(out, 'icon_foreground.png'))
    glyph(1024, code, 0.42, (0, 0, 0, 255)).save(os.path.join(out, 'icon_monochrome.png'))
    # tela de abertura: símbolo branco (o fundo é a cor sólida do app)
    glyph(768, code, 0.5).save(os.path.join(out, 'splash_logo.png'))
    glyph(1152, code, 0.33).save(os.path.join(out, 'splash_android12.png'))
    print(app, 'ok')
