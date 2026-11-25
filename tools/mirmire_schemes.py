#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Adds Mirmire's colour themes to app/studio/studio_tokens.gd as backgrounds (schemes).

Each one starts from Cartouche's closest scheme (Anthracite for a dark theme, Light grey for a light one) and
recolours every colour in it to the theme's hue, keeping its lightness and alpha, so text, switches, panels and
materials stay as readable as in the scheme they came from. The wall is mapped between two of the theme's colours,
and the pixel veil moves in the theme's accents. The file's hash is updated, as its test expects.

Run it again after changing a palette below: it replaces the schemes it added before.

Usage: python3 tools/mirmire_schemes.py
"""
import colorsys
import hashlib
import pathlib
import re

TOKENS = pathlib.Path(__file__).resolve().parent.parent / "app/studio/studio_tokens.gd"

# Mirmire's themes, as the app defines them (ui/theme/AppTheme.kt): key, base scheme, and colours.
THEMES = [
    ("MIRMIRE", "ANTHRACITE", {"tint": "#121417", "ink": "#F2F4F7", "mute": "#9AA3AF", "wall_low": "#0A0B0D",
                               "wall_high": "#1C2A3A", "clear": "#0A0B0D", "veil": ["#1A9FFF", "#4CD37F"], "spread": "waves"}),
    ("BLUE_CONSOLE", "ANTHRACITE", {"tint": "#07142E", "ink": "#F2F6FF", "mute": "#A9BCDD", "wall_low": "#020A1F",
                                    "wall_high": "#163A78", "clear": "#020A1F", "veil": ["#3D8BFF", "#9FC4FF"], "spread": "waves"}),
    ("GREEN_CONSOLE", "ANTHRACITE", {"tint": "#0D110E", "ink": "#EFF5EF", "mute": "#9DB3A0", "wall_low": "#050706",
                                     "wall_high": "#1E3A22", "clear": "#050706", "veil": ["#45D64F", "#B4E86A"], "spread": "pixels"}),
    ("PEARL_CONSOLE", "LIGHT_GREY", {"tint": "#EDF1F4", "ink": "#2A3138", "mute": "#66737F", "wall_low": "#C9D6E0",
                                     "wall_high": "#FFFFFF", "clear": "#F5F7F9", "veil": ["#1E9FD8", "#34BEED"], "spread": "waves"}),
    ("COMIC", "LIGHT_GREY", {"tint": "#FFF3D6", "ink": "#1C1B1F", "mute": "#4A4030", "wall_low": "#F5E3BB",
                             "wall_high": "#FFF8E1", "clear": "#FFF8E1", "veil": ["#D32F2F", "#1565C0", "#F9A825"], "spread": "pixels"}),
]
# How much of the theme's own saturation a recoloured colour takes.
TINT_STRENGTH = 0.85
# The base schemes' text colours, swapped for the theme's own.
BASE_INK = {"ANTHRACITE": ("#ede7de", "#8f877c"), "LIGHT_GREY": ("#1e2024", "#797b7e")}


def rgba(hex_value: str) -> tuple[float, float, float, float]:
    h = hex_value.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    return r, g, b, a


def to_hex(r: float, g: float, b: float, a: float) -> str:
    out = "#" + "".join(f"{round(max(0.0, min(1.0, c)) * 255):02x}" for c in (r, g, b))
    return out + (f"{round(a * 255):02x}" if a < 0.999 else "")


def recolour(hex_value: str, tint: str) -> str:
    r, g, b, a = rgba(hex_value)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    th, tl, ts = colorsys.rgb_to_hls(*rgba(tint)[:3])
    # The theme's hue at the colour's own lightness; greys and the base's warm tint both take it.
    nr, ng, nb = colorsys.hls_to_rgb(th, l, min(1.0, max(s * 0.3, ts * TINT_STRENGTH)) if 0.03 < l < 0.97 else 0.0)
    return to_hex(nr, ng, nb, a)


def scheme_line(lines: list[str], index: int) -> str:
    start = next(i for i, line in enumerate(lines) if line.startswith("const SCHEMES"))
    return lines[start + 1 + index]


def make(base: str, theme: dict) -> str:
    out = base.rstrip(",")
    ink, mute = BASE_INK[theme["base"]]
    out = out.replace(f'Color("{ink}', f'Color("{theme["ink"].lower()}').replace(f'Color("{mute}', f'Color("{theme["mute"].lower()}')
    # Every other literal colour takes the theme's hue.
    keep = {theme["ink"].lower(), theme["mute"].lower()}
    out = re.sub(r'Color\("(#[0-9a-fA-F]{3,8})"\)',
                 lambda m: m.group(0) if m.group(1).lower()[:7] in keep else f'Color("{recolour(m.group(1), theme["tint"])}")', out)
    out = re.sub(r'Color\(([0-9.]+), ([0-9.]+), ([0-9.]+), ([0-9.]+)\)',
                 lambda m: f'Color("{recolour(to_hex(*(float(x) for x in m.groups())), theme["tint"])}")', out)

    def put(key: str, value: str) -> None:
        nonlocal out
        out, n = re.subn(rf'(&"{key}": )(\[[^\]]*\]|&"\w+"|Color\([^)]*\)|[0-9.]+|true|false)', lambda m: m.group(1) + value, out, count=1)
        assert n == 1, key

    put("wall", '&"mapped"')
    put("wall_low", f'Color("{theme["wall_low"].lower()}")')
    put("wall_high", f'Color("{theme["wall_high"].lower()}")')
    put("clear", f'Color("{theme["clear"].lower()}")')
    low, high = rgba(theme["wall_low"]), rgba(theme["wall_high"])
    put("veil_base", f'Color("{to_hex(*((x + y) / 2 for x, y in zip(low[:3], high[:3])), 1.0)}")')
    put("veil_colours", "[" + ", ".join(f'Color("{c.lower()}")' for c in theme["veil"]) + "]")
    put("veil_spread", f'&"{theme["spread"]}"')
    return out + ","


def main() -> None:
    text = TOKENS.read_text()
    lines = text.split("\n")
    enum_at = next(i for i, line in enumerate(lines) if line.startswith("enum Scheme {"))
    names = [n.strip() for n in lines[enum_at][len("enum Scheme {"):].rstrip("}").split(",")]
    original = names[:names.index("ANTHRACITE") + 1]
    start = next(i for i, line in enumerate(lines) if line.startswith("const SCHEMES"))
    # Drop what an earlier run added, so the file only ever holds Cartouche's schemes and ours once.
    schemes = lines[start + 1:start + 1 + len(names)]
    schemes = schemes[:len(original)]
    added = []
    for key, base_key, theme in THEMES:
        theme = {**theme, "base": base_key}
        added.append("\t" + make(schemes[original.index(base_key)].lstrip("\t"), theme))
    lines[enum_at] = "enum Scheme { " + ", ".join(original + [k for k, _, _ in THEMES]) + " }"
    lines[start + 1:start + 1 + len(names)] = schemes + added
    kept = [line for line in lines if not line.startswith("const SHA256 := ")]
    digest = hashlib.sha256("\n".join(kept).encode()).hexdigest()
    lines = [f'const SHA256 := "{digest}"' if line.startswith("const SHA256 := ") else line for line in lines]
    TOKENS.write_text("\n".join(lines))
    print(f"{len(THEMES)} Mirmire schemes written; hash {digest}")


if __name__ == "__main__":
    main()
