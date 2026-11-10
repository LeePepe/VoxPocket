#!/usr/bin/env python3
"""从批准的 Pocket Wave 参数生成 Icon Composer 前景层；不生成材质或预烘焙阴影。"""

import argparse
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "design/app-icon/source.json"
ASSETS = ROOT / "VoxPocket/VoxPocket/AppIcon.icon/Assets"

APPROVED_POUCH_PATH = (
    "M 40 130 "
    "C 40 116, 52 108, 66 112 "
    "L 114 126 "
    "C 123 129, 133 129, 142 126 "
    "L 190 112 "
    "C 204 108, 216 116, 216 130 "
    "L 216 168 "
    "C 216 198, 192 220, 162 220 "
    "L 94 220 "
    "C 64 220, 40 198, 40 168 Z"
)
APPROVED_CARD_PATH = (
    "M 90 34 "
    "L 166 34 "
    "A 34 34 0 0 1 200 68 "
    "L 200 112 "
    "L 190 112 "
    "L 142 126 "
    "C 133 129, 123 129, 114 126 "
    "L 66 112 "
    "L 56 112 "
    "L 56 68 "
    "A 34 34 0 0 1 90 34 Z"
)
APPROVED_SONIC_BARS = [
    [82, 70, 12, 26],
    [102, 56, 12, 48],
    [122, 46, 12, 66],
    [142, 58, 12, 44],
    [162, 72, 12, 24],
]
APPROVED_SONIC_ARC = [92, 172, 72, 12]
APPEARANCES = ("light", "dark", "mono")
LAYER_SPECS = (
    ("pouch", "a-l1", 3),
    ("card", "a-l2", 2),
    ("sonic", "a-l3", 3),
)


def _fmt_num(value):
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def rrect_d(x, y, w, h, r):
    """将圆角矩形展开为闭合路径，供 Icon Composer 精确计算边缘高光。"""
    r = min(r, w / 2, h / 2)
    return (
        f"M {_fmt_num(x + r)} {_fmt_num(y)} "
        f"L {_fmt_num(x + w - r)} {_fmt_num(y)} "
        f"A {_fmt_num(r)} {_fmt_num(r)} 0 0 1 {_fmt_num(x + w)} {_fmt_num(y + r)} "
        f"L {_fmt_num(x + w)} {_fmt_num(y + h - r)} "
        f"A {_fmt_num(r)} {_fmt_num(r)} 0 0 1 {_fmt_num(x + w - r)} {_fmt_num(y + h)} "
        f"L {_fmt_num(x + r)} {_fmt_num(y + h)} "
        f"A {_fmt_num(r)} {_fmt_num(r)} 0 0 1 {_fmt_num(x)} {_fmt_num(y + h - r)} "
        f"L {_fmt_num(x)} {_fmt_num(y + r)} "
        f"A {_fmt_num(r)} {_fmt_num(r)} 0 0 1 {_fmt_num(x + r)} {_fmt_num(y)} Z"
    )


def _validate_gradient(gradient, expected_id, stop_count):
    if not isinstance(gradient, dict):
        raise ValueError(f"Missing gradient definition for {expected_id}")
    if gradient.get("id") != expected_id:
        raise ValueError(f"Expected gradient id {expected_id}")
    for coord in ("x1", "y1", "x2", "y2"):
        val = gradient.get(coord)
        if not isinstance(val, str) or not re.fullmatch(r"\d{1,3}%", val):
            raise ValueError(f"Invalid gradient coordinate {coord}: {val!r}")
    offsets = gradient.get("offsets")
    if (not isinstance(offsets, list) or len(offsets) != stop_count or
            any(not isinstance(o, str) or not re.fullmatch(r"\d{1,3}%", o) for o in offsets)):
        raise ValueError(f"Invalid gradient offsets for {expected_id}")


def _validate_box(box, canvas):
    if not isinstance(box, list) or len(box) != 4:
        raise ValueError("Expected [x, y, w, h] box")
    for item in box:
        if isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(item) or item <= 0:
            raise ValueError(f"Invalid box coordinate: {item!r}")
    x, y, w, h = box
    if x + w > canvas or y + h > canvas:
        raise ValueError("Box exceeds canvas bounds")


def load_source(path=SOURCE):
    source = json.loads(path.read_text())
    shape = source.get("geometry")
    if not isinstance(shape, dict):
        raise ValueError("Missing geometry object")
    canvas = shape.get("canvas")
    if isinstance(canvas, bool) or not isinstance(canvas, (int, float)) or not math.isfinite(canvas) or canvas != 256:
        raise ValueError("Expected a 256-unit master canvas")

    pouch = shape.get("pouch")
    card = shape.get("card")
    sonic = shape.get("sonic")
    if not isinstance(pouch, dict) or not isinstance(card, dict) or not isinstance(sonic, dict):
        raise ValueError("Expected pouch, card, and sonic geometry definitions")

    if pouch.get("d") != APPROVED_POUCH_PATH:
        raise ValueError("Unexpected pouch path topology")
    if card.get("d") != APPROVED_CARD_PATH:
        raise ValueError("Unexpected V-clipped capture card topology")

    _validate_gradient(pouch.get("gradient"), "g1", 3)
    _validate_gradient(card.get("gradient"), "g2", 2)
    _validate_gradient(sonic.get("gradient"), "g3", 3)

    if pouch.get("mono_opacity") != 0.62 or card.get("mono_opacity") != 0.34 or sonic.get("mono_opacity") != 1.0:
        raise ValueError("Expected approved 3-tier mono glass opacities (0.62, 0.34, 1.0)")

    radius = sonic.get("radius")
    if isinstance(radius, bool) or not isinstance(radius, (int, float)) or not math.isfinite(radius) or radius != 6:
        raise ValueError("Expected sonic bar corner radius 6")

    bars = sonic.get("bars")
    if not isinstance(bars, list) or bars != APPROVED_SONIC_BARS:
        raise ValueError("Unexpected sonic bars geometry")
    for bar in bars:
        _validate_box(bar, canvas)

    arc = sonic.get("arc")
    if not isinstance(arc, list) or arc != APPROVED_SONIC_ARC:
        raise ValueError("Unexpected sonic stitch arc geometry")
    _validate_box(arc, canvas)

    palettes = source.get("palettes")
    if not isinstance(palettes, dict) or set(palettes) != {"pouch", "card", "sonic"}:
        raise ValueError("Expected pouch, card, and sonic palettes")

    for layer_key, _, stop_count in LAYER_SPECS:
        layer_palettes = palettes[layer_key]
        if not isinstance(layer_palettes, dict) or set(layer_palettes) != set(APPEARANCES):
            raise ValueError(f"Expected light, dark, and mono palettes for {layer_key}")
        for colors in layer_palettes.values():
            if (not isinstance(colors, list) or len(colors) != stop_count or
                    any(not isinstance(c, str) or not re.fullmatch(r"#[0-9A-F]{6}", c) for c in colors)):
                raise ValueError(f"Expected {stop_count} hexadecimal color stops for {layer_key}")

    return source


def _linear_gradient_svg(gradient, colors):
    stops = "".join(
        f'<stop offset="{offset}" stop-color="{color}"/>'
        for offset, color in zip(gradient["offsets"], colors)
    )
    return (
        f'<linearGradient id="{gradient["id"]}" '
        f'x1="{gradient["x1"]}" y1="{gradient["y1"]}" '
        f'x2="{gradient["x2"]}" y2="{gradient["y2"]}">{stops}</linearGradient>'
    )


def _svg_wrap(defs, body):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 256 256">\n'
        f"<defs>{defs}</defs>\n"
        f"{body}\n"
        "</svg>\n"
    )


def layer_svg(source, layer_key, appearance):
    """生成单个图层在指定外观下的原生 SVG。"""
    geom = source["geometry"][layer_key]
    gradient = geom["gradient"]
    colors = source["palettes"][layer_key][appearance]
    defs = _linear_gradient_svg(gradient, colors)

    if layer_key in ("pouch", "card"):
        path_d = geom["d"]
    elif layer_key == "sonic":
        radius = geom["radius"]
        bar_paths = [rrect_d(*bar, radius) for bar in geom["bars"]]
        arc_path = rrect_d(*geom["arc"], radius)
        path_d = " ".join(bar_paths + [arc_path])
    else:
        raise ValueError(f"Unknown layer key: {layer_key}")

    opacity_attr = ""
    if appearance == "mono" and geom["mono_opacity"] < 1.0:
        opacity_attr = f' fill-opacity="{geom["mono_opacity"]}"'

    body = f'<path d="{path_d}" fill="url(#{gradient["id"]})"{opacity_attr}/>'
    return _svg_wrap(defs, body)


def expected_assets(source):
    return {
        f"{prefix}-{appearance}.svg": layer_svg(source, layer_key, appearance)
        for layer_key, prefix, _ in LAYER_SPECS
        for appearance in APPEARANCES
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="只验证已提交的生成资源")
    args = parser.parse_args()
    assets = expected_assets(load_source())
    if args.check:
        stale = [name for name, text in assets.items()
                 if not (ASSETS / name).exists() or (ASSETS / name).read_text() != text]
        extra = sorted(p.name for p in ASSETS.glob("*.svg") if p.name not in assets)
        if stale or extra:
            details = []
            if stale:
                details.append("stale/missing: " + ", ".join(stale))
            if extra:
                details.append("unexpected: " + ", ".join(extra))
            parser.error("Icon asset mismatch (" + "; ".join(details) + ")")
        print(f"Verified {len(assets)} generated icon layers")
        return
    ASSETS.mkdir(parents=True, exist_ok=True)
    for existing in ASSETS.glob("*.svg"):
        if existing.name not in assets:
            existing.unlink()
    for name, text in assets.items():
        (ASSETS / name).write_text(text)
    print(f"Generated {len(assets)} icon layers")


if __name__ == "__main__":
    main()

