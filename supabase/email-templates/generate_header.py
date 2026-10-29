import io
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = r"c:\barangay_safety_app"
ICON_PATH = os.path.join(ROOT, "assets", "images", "app_icon.png")
OUT_PATH = os.path.join(ROOT, "supabase", "email-templates", "_reset-password-header.png")

# After generating, upload OUT_PATH to the `email-assets` public bucket in
# Supabase Storage, overwriting the same path so reset-password.html's <img
# src> URL never needs to change:
#   https://your-project-ref.supabase.co/storage/v1/object/public/email-assets/reset-password-header.png
# (Not embedded as base64 in the HTML — Gmail silently drops base64-embedded
# images in HTML mail, confirmed by an actual failed test send. See
# reset-password.html's header comment for the full story.)

# ── Canvas ────────────────────────────────────────────────────────────────
# Rendered at 2x the intended CSS display size (480x160 shown -> 960x320
# rendered) — sharp enough on a phone screen, and small enough to load fast
# as a hosted image.
W, H = 960, 320
SCALE = 2  # for reference: 480x160 display size

# ── True gradient, drawn pixel-by-pixel — not CSS ───────────────────────
# CSS linear-gradient() has spotty support across email clients (Gmail's
# apps in particular often collapse it to a flat fill, which is exactly
# what the pasted screenshot showed). Baking the gradient into a PNG and
# shipping it as a real image sidesteps that entirely: an <img> tag renders
# identically everywhere an image renders at all.
#
# Top-left brighter (#3B82F6, Tailwind blue-500) -> bottom-right the app's
# own primaryDark (#1D4ED8) from lib/utils/constants.dart, diagonal to match
# the depth/light-source direction the real app icon already uses.
TOP = (0x3B, 0x82, 0xF6)
BOTTOM = (0x1D, 0x4E, 0xD8)

img = Image.new("RGB", (W, H))
px = img.load()
diag = math.hypot(W, H)
for y in range(H):
    for x in range(0, W, 2):  # step 2, mirror next pixel — halves draw time, invisible at this smoothness
        t = ((x + y) / diag)
        t = max(0.0, min(1.0, t))
        r = round(TOP[0] + (BOTTOM[0] - TOP[0]) * t)
        g = round(TOP[1] + (BOTTOM[1] - TOP[1]) * t)
        b = round(TOP[2] + (BOTTOM[2] - TOP[2]) * t)
        px[x, y] = (r, g, b)
        if x + 1 < W:
            px[x + 1, y] = (r, g, b)

# Subtle radial lightening behind where the icon will sit, so it doesn't
# look pasted flat onto the gradient — the same soft-glow trick the app's
# own splash screen and dashboard headers use elsewhere in this project.
glow = Image.new("L", (W, H), 0)
gd = ImageDraw.Draw(glow)
cx, cy = W // 2, int(H * 0.42)
r = 175
gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=70)
glow = glow.filter(ImageFilter.GaussianBlur(60))
white_layer = Image.new("RGB", (W, H), (255, 255, 255))
img = Image.composite(white_layer, img, glow)

img = img.convert("RGBA")

# ── The real app icon, with a soft drop shadow ──────────────────────────
icon = Image.open(ICON_PATH).convert("RGBA")
icon_size = 172
icon = icon.resize((icon_size, icon_size), Image.LANCZOS)

# Shadow: the icon's own alpha shape, blurred and offset — not a plain box,
# so it follows the icon's actual (already-rounded) silhouette.
shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
shadow_alpha = icon.split()[3].point(lambda a: int(a * 0.35))
shadow_shape = Image.new("RGBA", icon.size, (0, 0, 0, 0))
shadow_shape.putalpha(shadow_alpha)
icon_cx = W // 2
icon_cy = int(H * 0.42)
shadow.paste(shadow_shape, (icon_cx - icon_size // 2, icon_cy - icon_size // 2 + 9), shadow_shape)
shadow = shadow.filter(ImageFilter.GaussianBlur(9))
img = Image.alpha_composite(img, shadow)

img.paste(icon, (icon_cx - icon_size // 2, icon_cy - icon_size // 2), icon)

img = img.convert("RGB")

# ── Export, kept small for fast loading as a hosted image ───────────────
# Truecolor PNG first, for comparison.
buf_true = io.BytesIO()
img.save(buf_true, format="PNG", optimize=True)
print(f"truecolor PNG: {len(buf_true.getvalue())/1024:.1f} KB")

# Palette (indexed-color) PNG — a smooth gradient plus one icon has very few
# effectively-distinct colors once quantized, so this compresses far better
# than truecolor for exactly this kind of image. 256 colors is enough that
# the gradient still reads as smooth rather than banded.
quantized = img.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)
buf = io.BytesIO()
quantized.save(buf, format="PNG", optimize=True)
size_kb = len(buf.getvalue()) / 1024
print(f"palette PNG: {size_kb:.1f} KB")

if size_kb > 45:
    img2 = img.resize((W // 2, H // 2), Image.LANCZOS)
    quantized2 = img2.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)
    buf = io.BytesIO()
    quantized2.save(buf, format="PNG", optimize=True)
    size_kb = len(buf.getvalue()) / 1024
    print(f"resized-down palette PNG: {size_kb:.1f} KB")

with open(OUT_PATH, "wb") as f:
    f.write(buf.getvalue())

print("done ->", OUT_PATH)
print("now upload this file to the `email-assets` bucket in Supabase Storage,")
print("overwriting supabase/email-templates/reset-password-header.png")
