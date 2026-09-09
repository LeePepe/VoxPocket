#!/usr/bin/env python3
"""使用 Xcode 内置 Icon Composer 渲染器验证原生 macOS 图标；不启动或安装 App。"""

import argparse
import json
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ICON = ROOT / "VoxPocket/VoxPocket/AppIcon.icon"
RENDITIONS = ("Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark")
SIZES = (16, 32, 64, 128, 1024)


def check_png(path, size):
    if not path.is_file():
        raise SystemExit(f"Native renderer did not create {path.name}")
    with path.open("rb") as image:
        header = image.read(24)
    if (len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or
            header[12:16] != b"IHDR" or struct.unpack(">II", header[16:24]) != (size, size)):
        raise SystemExit(f"Invalid native PNG size/header: {path.name}")


def native_tool():
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    tool = developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"
    if not tool.is_file():
        raise SystemExit("Icon Composer's export tool is missing from selected Xcode")
    return tool


def export_images(tool, output):
    for appearance in RENDITIONS:
        for size in SIZES:
            command = [str(tool), str(ICON), "--export-image", "--output-file",
                       str(output / f"{appearance}-{size}.png"), "--platform", "macOS",
                       "--rendition", appearance, "--width", str(size), "--height", str(size),
                       "--scale", "1"]
            if appearance.startswith("Tinted"):
                command += ["--tint-color", "0.60", "--tint-strength", "0.65"]
            result = subprocess.run(command, capture_output=True, text=True, timeout=45)
            if result.returncode:
                raise SystemExit(f"Native rendering failed: {appearance}/{size}\n{result.stderr}")
            check_png(output / f"{appearance}-{size}.png", size)
        print(f"Rendered {appearance}: {', '.join(map(str, SIZES))}px", flush=True)


def write_gallery(output):
    cards = []
    for appearance in RENDITIONS:
        samples = "".join(f'<div><img src="{appearance}-{s}.png" width="{s}" height="{s}" '
                          f'alt="{appearance} {s}px"><small>{s}px</small></div>' for s in (16, 32, 64))
        cards.append(f'<article><h2>{appearance}</h2><div class="surface {appearance}">'
                     f'<img src="{appearance}-1024.png" width="220" height="220" '
                     f'alt="{appearance} 原生渲染"></div><div class="sizes">{samples}</div></article>')
    document = '''<!doctype html><html lang="zh-Hans"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>VoxPocket 原生图标</title>
<style>body{margin:0;background:#101218;color:#edf0f8;font-family:-apple-system,sans-serif}main{max-width:1140px;margin:auto;padding:36px}h1{font-size:30px;font-weight:550;margin:0 0 12px}p{font-size:14px;color:#b9c0cd;line-height:1.6}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin-top:24px}article{border:1px solid #343944;background:#1b1e26;border-radius:18px;padding:20px}h2{font-size:15px;font-weight:500;margin:0 0 18px}.surface{padding:10px;display:flex;justify-content:center;background:#2d3442;border-radius:14px}.Default,.ClearLight,.TintedLight{background:#dce5f1}.sizes{height:92px;display:flex;align-items:flex-end;justify-content:center;gap:28px;margin-top:20px}.sizes>div{display:flex;flex-direction:column;align-items:center;gap:8px}small{font-size:11px;color:#b9c0cd}img{display:block}footer{margin-top:22px;font-size:12px;color:#b9c0cd;line-height:1.8}@media(max-width:760px){.grid{grid-template-columns:1fr}main{padding:24px}}</style>
<main><h1>VoxPocket · 原生浮雕三椭圆</h1><p>加粗描边 + 分层材质 · Apple Icon Composer 原生导出，不是网页模拟玻璃。</p><section class="grid">'''
    document += "".join(cards)
    document += ('</section><footer>大图使用原生 1024px 导出，16/32/64px 为各尺寸独立原生渲染。'
                 '底板仅用于显示透明像素，不代表真实桌面壁纸下的实时合成。'
                 '未安装替换应用。</footer></main></html>')
    (output / "index.html").write_text(document)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/icon-preview")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    tool = native_tool()
    export_images(tool, output)
    write_gallery(output)
    metadata = {
        "renderer": json.loads(subprocess.check_output([str(tool), "--version"], text=True)),
        "macOS": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
        "platform": "macOS", "renditions": RENDITIONS, "sizes": SIZES,
    }
    (output / "render-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Native preview: {output / 'index.html'}")


if __name__ == "__main__":
    main()
