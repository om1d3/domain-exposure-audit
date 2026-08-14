#!/usr/bin/env python3
"""
assets/logo.py — make the logo files for domain-exposure-audit.

The mark is a shield that tapers to a map pin, with a house shape cut out of
the centre. The shape holds the purpose of the tool: it finds the path from a
domain name to your house, and it helps you to close that path.

One set of coordinates makes each file. Therefore the SVG and the PNG files
cannot become different from each other.

    python3 assets/logo.py

The script writes these files into the same directory:
    logo.svg              512 x 512, the tile and the mark
    logo-mono.svg         512 x 512, one colour, no background
    logo-512.png          for the Forgejo repository avatar
    logo-256.png          for a README file
    logo-128.png          small size
    favicon-64.png        very small size
    social-preview.png    1280 x 640, for the GitHub social preview
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONTS = Path("/mnt/skills/examples/canvas-design/canvas-fonts")

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

TILE = (14, 22, 33)           # very dark blue
TEAL_TOP = (110, 231, 219)
TEAL_BOTTOM = (17, 148, 137)
TEXT = (233, 241, 247)
TEXT_DIM = (138, 160, 180)
TEXT_FAINT = (86, 112, 138)

# ---------------------------------------------------------------------------
# Geometry, in a 512 x 512 box
# ---------------------------------------------------------------------------
# The shape is symmetrical about x = 256. The tip is at the bottom. The shape
# moves up by SHIFT_Y, because the eye sees the centre of a pin above the
# centre of its box.

SHIFT_Y = -14

# Each item is one cubic curve: the two control points and the end point.
SHIELD = [
    ((196, 112), (158, 128), (144, 150)),
    ((140, 210), (146, 276), (168, 322)),
    ((196, 372), (228, 402), (256, 424)),
    ((284, 402), (316, 372), (344, 322)),
    ((366, 276), (372, 210), (368, 150)),
    ((354, 128), (316, 112), (256, 112)),
]
SHIELD_START = (256, 112)

# The house that the tool cuts out of the shield.
HOUSE = [(256, 164), (326, 234), (326, 296), (186, 296), (186, 234)]


def cubic(p0, p1, p2, p3, steps=48):
    """Give a list of points along one cubic curve."""
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0]
        y = u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1]
        out.append((x, y))
    return out


def shield_points(scale=1.0, dx=0.0, dy=0.0):
    """Give the outline of the shield as a list of points."""
    pts = []
    cur = SHIELD_START
    for c1, c2, end in SHIELD:
        pts.extend(cubic(cur, c1, c2, end)[:-1])
        cur = end
    return [((x) * scale + dx, (y + SHIFT_Y) * scale + dy) for x, y in pts]


def house_points(scale=1.0, dx=0.0, dy=0.0):
    return [(x * scale + dx, (y + SHIFT_Y) * scale + dy) for x, y in HOUSE]


# ---------------------------------------------------------------------------
# PNG output
# ---------------------------------------------------------------------------

SS = 4      # The script draws large, then makes the image small. The edges
            # are then smooth.


def gradient(size, top, bottom):
    """Make an image that changes colour from the top to the bottom."""
    w, h = size
    img = Image.new("RGB", (1, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return img.resize((w, h), Image.NEAREST)


def draw_mark(size, scale, dx, dy, arcs=True):
    """Draw the mark. Give back an RGBA image with a clear background."""
    w = h = 0
    if isinstance(size, tuple):
        w, h = size
    else:
        w = h = size

    big = (w * SS, h * SS)
    mask = Image.new("L", big, 0)
    md = ImageDraw.Draw(mask)
    md.polygon(shield_points(scale * SS, dx * SS, dy * SS), fill=255)
    md.polygon(house_points(scale * SS, dx * SS, dy * SS), fill=0)

    grad = gradient(big, TEAL_TOP, TEAL_BOTTOM).convert("RGBA")
    grad.putalpha(mask)

    if arcs:
        # Two faint circles behind the mark. They show that the tool looks for
        # data again and again.
        ring = Image.new("RGBA", big, (0, 0, 0, 0))
        rd = ImageDraw.Draw(ring)
        cx = (256 * scale + dx) * SS
        cy = ((235 + SHIFT_Y) * scale + dy) * SS
        for r, a in ((196, 26), (248, 16)):
            rr = r * scale * SS
            rd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                       outline=(110, 231, 219, a), width=int(3 * scale * SS))
        ring = ring.resize((w, h), Image.LANCZOS)
        out = ring
    else:
        out = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    out.alpha_composite(grad.resize((w, h), Image.LANCZOS))
    return out


def make_avatar(px):
    """Make one square avatar file."""
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    # The tile has round corners.
    tile = Image.new("RGBA", (px * SS, px * SS), (0, 0, 0, 0))
    td = ImageDraw.Draw(tile)
    td.rounded_rectangle([0, 0, px * SS - 1, px * SS - 1],
                         radius=int(px * SS * 0.227), fill=TILE + (255,))
    img.alpha_composite(tile.resize((px, px), Image.LANCZOS))
    img.alpha_composite(draw_mark(px, px / 512, 0, 0))
    img.save(HERE / f"logo-{px}.png")
    return img


def make_favicon(px=64):
    img = Image.new("RGBA", (px, px), TILE + (255,))
    img.alpha_composite(draw_mark(px, px / 512, 0, 0, arcs=False))
    img.save(HERE / f"favicon-{px}.png")


def font(name, size):
    p = FONTS / name
    if p.exists():
        return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def make_social(w=1280, h=640):
    """Make the wide image for the GitHub social preview."""
    img = Image.new("RGBA", (w, h), TILE + (255,))
    d = ImageDraw.Draw(img)

    # A faint grid. It suggests a table of data.
    for x in range(0, w, 40):
        d.line([(x, 0), (x, h)], fill=(20, 31, 45), width=1)
    for y in range(0, h, 40):
        d.line([(0, y), (w, y)], fill=(20, 31, 45), width=1)

    # The mark on the left.
    mark_px = 300
    mark = draw_mark(mark_px, mark_px / 512, 0, 0)
    img.alpha_composite(mark, (110, (h - mark_px) // 2))

    x = 470
    f_title = font("GeistMono-Bold.ttf", 52)
    f_tag = font("GeistMono-Regular.ttf", 27)
    f_small = font("GeistMono-Regular.ttf", 20)

    title = "domain-exposure-audit"
    tag = "Find the public data about your domains."
    checks = "RDAP  DNS  Certificate Transparency  origin IP  archives"

    # Put the block of text in the middle, from top to bottom.
    hh = 52 + 26 + 27 + 34 + 20
    y = (h - hh) // 2

    d.text((x, y), title, font=f_title, fill=TEXT)
    y += 52 + 26
    d.text((x, y), tag, font=f_tag, fill=TEXT_DIM)
    y += 27 + 34
    d.text((x, y), checks, font=f_small, fill=TEXT_FAINT)

    # A teal line under the text.
    d.rounded_rectangle([x, y + 46, x + 96, y + 50], radius=2,
                        fill=TEAL_BOTTOM + (255,))

    img.convert("RGB").save(HERE / "social-preview.png", quality=95)


# ---------------------------------------------------------------------------
# SVG output
# ---------------------------------------------------------------------------

def svg_path(points):
    d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in points) + " Z"
    return d


def make_svg():
    shield = svg_path(shield_points())
    house = svg_path(house_points())
    cx, cy = 256, 235 + SHIFT_Y

    with open(HERE / "logo.svg", "w") as f:
        f.write(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="domain-exposure-audit">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#6EE7DB"/>
      <stop offset="1" stop-color="#119489"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="116" fill="#0E1621"/>
  <g fill="none" stroke="#6EE7DB" stroke-width="3">
    <circle cx="{cx}" cy="{cy}" r="196" opacity="0.10"/>
    <circle cx="{cx}" cy="{cy}" r="248" opacity="0.06"/>
  </g>
  <path fill="url(#g)" fill-rule="evenodd" d="{shield} {house}"/>
</svg>
''')

    with open(HERE / "logo-mono.svg", "w") as f:
        f.write(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="domain-exposure-audit">
  <path fill="currentColor" fill-rule="evenodd" d="{shield} {house}"/>
</svg>
''')


if __name__ == "__main__":
    make_svg()
    for px in (512, 256, 128):
        make_avatar(px)
    make_favicon(64)
    make_social()
    print("The script wrote these files:")
    for p in sorted(HERE.glob("*")):
        if p.name != "logo.py":
            print(f"  {p.name}")
