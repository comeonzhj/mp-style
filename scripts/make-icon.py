#!/usr/bin/env python3
"""生成应用图标 Resources/AppIcon.icns。

设计：主题蓝渐变的圆角方块 + 白色文本行（首行加粗代表标题）。
需要 Pillow。运行：python3 scripts/make-icon.py
"""

import os
import shutil
import subprocess
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("需要 Pillow：pip install Pillow", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "build", "AppIcon.iconset")
OUT = os.path.join(ROOT, "Resources", "AppIcon.icns")

S = 1024
TOP = (27, 99, 243)      # 主题色 #1B63F3
BOTTOM = (86, 148, 255)  # 亮一档，做出轻微渐变
RADIUS_RATIO = 0.2237    # macOS 圆角比例


def build_master() -> Image.Image:
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # 竖向渐变
    gradient = Image.new("RGB", (S, S))
    pen = ImageDraw.Draw(gradient)
    for y in range(S):
        t = y / (S - 1)
        color = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        pen.line([(0, y), (S, y)], fill=color)

    # 圆角遮罩
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, S - 1, S - 1], radius=int(S * RADIUS_RATIO), fill=255
    )
    canvas.paste(gradient, (0, 0), mask)

    # 白色文本行
    pen = ImageDraw.Draw(canvas)
    left = int(S * 0.235)
    right = int(S * 0.765)
    span = right - left
    bar = int(S * 0.068)
    gap = int(S * 0.082)

    # (宽度比例, 高度倍数)：第一行是标题，更粗更满
    rows = [
        (1.00, 1.55),
        (0.80, 1.00),
        (0.92, 1.00),
        (0.58, 1.00),
    ]

    heights = [bar * r[1] for r in rows]
    total = sum(heights) + gap * (len(rows) - 1)
    y = (S - total) / 2

    for (ratio, _), h in zip(rows, heights):
        width = span * ratio
        pen.rounded_rectangle(
            [left, y, left + width, y + h],
            radius=h / 2,
            fill=(255, 255, 255, 255),
        )
        y += h + gap

    return canvas


def main() -> int:
    master = build_master()

    if os.path.isdir(ICONSET):
        shutil.rmtree(ICONSET)
    os.makedirs(ICONSET)

    for size in (16, 32, 128, 256, 512):
        master.resize((size, size), Image.LANCZOS).save(
            os.path.join(ICONSET, f"icon_{size}x{size}.png")
        )
        master.resize((size * 2, size * 2), Image.LANCZOS).save(
            os.path.join(ICONSET, f"icon_{size}x{size}@2x.png")
        )

    result = subprocess.run(
        ["iconutil", "-c", "icns", ICONSET, "-o", OUT],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        return result.returncode

    print(f"已生成 {os.path.relpath(OUT, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
