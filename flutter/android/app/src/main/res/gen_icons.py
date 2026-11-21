"""Generate RemoteDesk launcher icons.

Draws a monitor screen with a small link node (white) on brand blue. Run with
the bundled Python that ships Pillow:

    python gen_icons.py

Outputs:
  mipmap-*/ic_launcher.png        legacy square icon
  mipmap-*/ic_launcher_round.png  legacy round icon
  mipmap-*/ic_launcher_foreground.png  adaptive foreground (transparent)
"""

from PIL import Image, ImageDraw

BRAND = (11, 107, 255, 255)      # #0B6BFF
WHITE = (255, 255, 255, 255)
SS = 8                           # supersampling factor

LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def draw_glyph(draw, box, color):
    """Monitor outline with a rounded screen and a link dot, inside `box`."""
    x0, y0, x1, y1 = box
    w = x1 - x0
    h = y1 - y0
    # screen body: 92% width, 66% height, vertically centred a bit high
    sw = w * 0.92
    sh = h * 0.62
    sx = x0 + (w - sw) / 2
    sy = y0 + (h - sh) / 2 - h * 0.06
    stroke = max(2, int(w * 0.075))
    radius = w * 0.14
    draw.rounded_rectangle([sx, sy, sx + sw, sy + sh], radius=radius,
                           outline=color, width=stroke)
    # stand
    stand_w = sw * 0.30
    draw.rectangle([sx + (sw - stand_w) / 2, sy + sh, sx + (sw + stand_w) / 2,
                    sy + sh + h * 0.09], fill=color)
    base_w = sw * 0.52
    draw.rounded_rectangle([sx + (sw - base_w) / 2, sy + sh + h * 0.09,
                            sx + (sw + base_w) / 2, sy + sh + h * 0.14],
                           radius=w * 0.02, fill=color)
    # link dot inside the screen
    d = sw * 0.20
    cx = sx + sw * 0.5
    cy = sy + sh * 0.5
    draw.ellipse([cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2], fill=color)


def render_square(size, path):
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = size * SS * 0.02
    d.rounded_rectangle([pad, pad, size * SS - pad, size * SS - pad],
                        radius=size * SS * 0.22, fill=BRAND)
    inset = size * SS * 0.16
    draw_glyph(d, (inset, inset, size * SS - inset, size * SS - inset), WHITE)
    img.resize((size, size), Image.LANCZOS).save(path)


def render_round(size, path):
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, size * SS - 1, size * SS - 1], fill=BRAND)
    inset = size * SS * 0.20
    draw_glyph(d, (inset, inset, size * SS - inset, size * SS - inset), WHITE)
    img.resize((size, size), Image.LANCZOS).save(path)


def render_foreground(size, path):
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # adaptive icons: only the inner 72/108 of the canvas is guaranteed visible
    inset = size * SS * (18 / 108)
    draw_glyph(d, (inset, inset, size * SS - inset, size * SS - inset), WHITE)
    img.resize((size, size), Image.LANCZOS).save(path)


def main():
    for density, size in LEGACY.items():
        folder = "mipmap-" + density
        render_square(size, folder + "/ic_launcher.png")
        render_round(size, folder + "/ic_launcher_round.png")
        print("legacy", folder, size)
    for density, size in FOREGROUND.items():
        folder = "mipmap-" + density
        render_foreground(size, folder + "/ic_launcher_foreground.png")
        print("foreground", folder, size)


if __name__ == "__main__":
    main()
