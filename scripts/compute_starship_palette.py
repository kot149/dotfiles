"""
Compute starship palette in OKLCH (perceptually uniform), convert to sRGB hex.

Design:
- White-text segments: L=0.55, C=0.13 (uniform perceived lightness/chroma).
- Dark-text segments (macos_bg): L=0.80, C=0.02.
- Neutrals (cmd_bg, bun_bg): C=0.00, varying L.
- Hue assignment driven by color-theory roles:
    * Cool slate anchor (h=250) for system/utility (os, time, cmd_duration,
      powershell, zsh, windows, python — Python brand is also blue).
    * Warm complement (h=50-70) for directory and bash — opposite the slate
      anchor across the wheel, creating dominant contrast axis.
    * Bridge purple (h=300) for git — analogous between blue and red.
    * Green (h=145) for node — triadic w.r.t. the blue/orange axis.
    * Brand-locked hues for ubuntu (40), debian (20), rust (35), status (25).
- Variants (powershell darker, bash darker, status more saturated) shift
  L or C from the base while keeping hue.
"""
import math


def oklch_to_hex(L: float, C: float, h_deg: float) -> str:
    h = math.radians(h_deg)
    a = C * math.cos(h)
    b = C * math.sin(h)
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    lr, mr, sr = l_ ** 3, m_ ** 3, s_ ** 3
    r =  4.0767416621 * lr - 3.3077115913 * mr + 0.2309699292 * sr
    g = -1.2684380046 * lr + 2.6097574011 * mr - 0.3413193965 * sr
    bl = -0.0041960863 * lr - 0.7034186147 * mr + 1.7076147010 * sr

    def to_srgb(u: float) -> int:
        u = max(0.0, min(1.0, u))
        v = 12.92 * u if u <= 0.0031308 else 1.055 * (u ** (1 / 2.4)) - 0.055
        return round(max(0.0, min(1.0, v)) * 255)

    return "#{:02x}{:02x}{:02x}".format(to_srgb(r), to_srgb(g), to_srgb(bl))


def relative_luminance(hex_color: str) -> float:
    r, g, b = (int(hex_color[i:i+2], 16) / 255 for i in (1, 3, 5))
    def lin(u):
        return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(fg_hex: str, bg_hex: str) -> float:
    l1, l2 = relative_luminance(fg_hex), relative_luminance(bg_hex)
    a, b = max(l1, l2), min(l1, l2)
    return (a + 0.05) / (b + 0.05)


L_TEXT = 0.56   # white-text segments
C_TEXT = 0.10   # moderate chroma — between vivid and muted
L_DARK = 0.78   # dark-text segments (macos, dir)
L_DEEP = 0.34   # darker variant (powershell, bash)
L_NEUT = 0.52   # neutral gray utilities

# (slot, L, C, hue, note)
PALETTE = [
    # Monochromatic blue palette — all hues confined to h ∈ [225, 280].
    # Differentiation comes from L (lightness hierarchy) and small hue
    # shifts within the blue family (cyan-blue 225 ↔ slate 250 ↔
    # violet-blue 280).

    # System anchor — near-neutral cool gray-blue
    ("os_bg",           L_TEXT, 0.03,   245,  "neutral cool gray-blue"),
    ("time_bg",         L_TEXT, 0.02,   245,  "neutral cool gray-blue"),
    ("cmd_duration_bg", 0.60,   0.02,   245,  "neutral cool, slightly lighter"),

    # OS row — small hue shifts within blue family
    ("windows_bg",      L_TEXT, C_TEXT, 250,  "Microsoft blue (anchor)"),
    ("macos_bg",        L_DARK, 0.02,   245,  "Apple silver-blue, dark text"),
    ("ubuntu_bg",       L_TEXT, C_TEXT, 275,  "shifted to violet-blue"),
    ("debian_bg",       L_TEXT, C_TEXT, 280,  "shifted to deep violet-blue"),

    # Shell row
    ("shell_bg",        L_NEUT, 0.00,   245,  "neutral fallback"),
    ("powershell_bg",   L_DEEP, 0.08,   250,  "deep navy"),
    ("cmd_bg",          L_NEUT, 0.00,   245,  "pure neutral gray"),
    ("zsh_bg",          L_TEXT, C_TEXT, 255,  "indigo-blue"),
    ("bash_bg",         L_DEEP, 0.07,   235,  "deep cerulean"),

    # Directory — light powder blue (paired with dark dir_fg)
    ("dir_bg",          L_DARK, 0.09,   235,  "light powder blue, dark text"),
    ("dir_fg",          0.18,   0.03,   245,  "dark blue text for dir"),

    # Git — violet-blue (still inside blue family)
    ("git_bg",          L_TEXT, C_TEXT, 275,  "violet-blue"),

    # Language row — varied within blue family
    ("python_bg",       L_TEXT, C_TEXT, 250,  "Python blue (anchor)"),
    ("node_bg",         L_TEXT, C_TEXT, 225,  "cyan-blue"),
    ("bun_bg",          0.35,   0.02,   245,  "near-neutral dark blue"),
    ("rust_bg",         L_TEXT, C_TEXT, 270,  "blue-purple"),

    # Status — high chroma blue; pops via saturation rather than hue
    ("status_bg",       L_TEXT, 0.20,   250,  "vivid blue, alert via saturation"),
]


print(f"{'name':<18} {'hex':<9} {'L':>5} {'C':>5} {'h':>4}  contrast(#fff)  note")
print("-" * 90)
for name, L, C, h, note in PALETTE:
    hx = oklch_to_hex(L, C, h)
    fg = "#0b1010" if name in ("macos_bg", "dir_bg") else "#ffffff"
    cr = contrast(fg, hx)
    print(f"{name:<18} {hx:<9} {L:>5.2f} {C:>5.2f} {h:>4}  {cr:>6.2f}         {note}")

print()
print("# --- toml snippet ---")
for name, L, C, h, _ in PALETTE:
    print(f"{name} = '{oklch_to_hex(L, C, h)}'")
