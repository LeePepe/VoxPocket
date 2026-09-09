#!/usr/bin/env python3
"""从批准的参数生成 Icon Composer 前景层；不生成材质或预烘焙阴影。"""

import argparse
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "design/app-icon/source.json"
ASSETS = ROOT / "VoxPocket/VoxPocket/AppIcon.icon/Assets"


def load_source(path=SOURCE):
    source = json.loads(path.read_text())
    shape = source["geometry"]
    for key in ("canvas", "center", "rx", "ry", "stroke"):
        value = shape[key]
        if not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
            raise ValueError(f"Invalid geometry field: {key}")
    if shape["canvas"] != 256 or shape["center"] != 128:
        raise ValueError("Expected a centered 256-unit master")
    if shape["stroke"] >= 2 * min(shape["rx"], shape["ry"]):
        raise ValueError("Stroke would erase the hollow center")
    if max(shape["rx"], shape["ry"]) + shape["stroke"] / 2 >= shape["center"]:
        raise ValueError("Ring exceeds the canvas")
    if shape["samples"] != 64 or shape["angles"] != [-60, 0, 60]:
        raise ValueError("Unexpected approved ring topology")
    if set(source["palettes"]) != {"light", "dark", "mono"}:
        raise ValueError("Expected light, dark and mono palettes")
    for colors in source["palettes"].values():
        if len(colors) != 5 or any(not re.fullmatch(r"#[0-9A-F]{6}", c) for c in colors):
            raise ValueError("Expected five hexadecimal color stops")
    return source


def offset_sample(shape, t, distance):
    """返回椭圆等距轮廓的位置与切线，保证浮雕边缘不呈多边形切面。"""
    rx, ry, center = shape["rx"], shape["ry"], shape["center"]
    cosine, sine = math.cos(t), math.sin(t)
    norm = math.hypot(ry * cosine, rx * sine)
    norm_prime = (rx * rx - ry * ry) * sine * cosine / norm
    nx, ny = ry * cosine / norm, rx * sine / norm
    dx = -ry * sine / norm - ry * cosine * norm_prime / norm ** 2
    dy = rx * cosine / norm - rx * sine * norm_prime / norm ** 2
    point = (center + rx * cosine + distance * nx,
             center + ry * sine + distance * ny)
    tangent = (-rx * sine + distance * dx, ry * cosine + distance * dy)
    return point, tangent


def closed_path(shape, distance):
    step = 2 * math.pi / shape["samples"]
    head, _ = offset_sample(shape, 0, distance)
    parts = [f"M{head[0]:.5f},{head[1]:.5f}"]
    for index in range(shape["samples"]):
        start, ds = offset_sample(shape, index * step, distance)
        end, de = offset_sample(shape, (index + 1) * step, distance)
        c1 = tuple(start[axis] + ds[axis] * step / 3 for axis in (0, 1))
        c2 = tuple(end[axis] - de[axis] * step / 3 for axis in (0, 1))
        parts.append(f"C{c1[0]:.5f},{c1[1]:.5f} {c2[0]:.5f},{c2[1]:.5f} "
                     f"{end[0]:.5f},{end[1]:.5f}")
    return "".join(parts) + "Z"


def ring_svg(shape, colors, angle):
    """描边扩展为带孔填充轮廓，便于 Composer 用边界生成原生浮雕。"""
    path = (closed_path(shape, shape["stroke"] / 2) +
            closed_path(shape, -shape["stroke"] / 2))
    stops = "".join(
        f'<stop offset="{index * 25}%" stop-color="{color}"/>'
        for index, color in enumerate(colors)
    )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        'viewBox="0 0 256 256">\n'
        '<defs><linearGradient id="spectrum" x1="0%" y1="100%" '
        f'x2="100%" y2="0%">{stops}</linearGradient></defs>\n'
        f'<path transform="rotate({angle} 128 128)" fill="url(#spectrum)" '
        f'fill-rule="evenodd" d="{path}"/>\n</svg>\n'
    )


def expected_assets(source):
    return {
        f"orbit-{index + 1:02d}-{appearance}.svg": ring_svg(source["geometry"], colors, angle)
        for index, angle in enumerate(source["geometry"]["angles"])
        for appearance, colors in source["palettes"].items()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="只验证已提交的生成资源")
    args = parser.parse_args()
    assets = expected_assets(load_source())
    if args.check:
        stale = [name for name, text in assets.items()
                 if not (ASSETS / name).exists() or (ASSETS / name).read_text() != text]
        if stale:
            parser.error("Stale icon layers: " + ", ".join(stale))
        print(f"Verified {len(assets)} generated icon layers")
        return
    ASSETS.mkdir(parents=True, exist_ok=True)
    for name, text in assets.items():
        (ASSETS / name).write_text(text)
    print(f"Generated {len(assets)} icon layers")


if __name__ == "__main__":
    main()
