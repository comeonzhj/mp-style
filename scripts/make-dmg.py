#!/usr/bin/env python3
"""生成带拖拽引导的 DMG。

用 dmgbuild 直接写 .DS_Store（窗口尺寸、图标坐标、背景图），
**不经过 AppleScript 驱动 Finder**。后者需要「自动化」权限，
在无 GUI 授权或 CI 环境下会直接报 -10004 权限违例。

用法: scripts/make-dmg.py <输出.dmg> <版本号> [App 路径]
"""

import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("需要 Pillow：pip install Pillow", file=sys.stderr)
    sys.exit(1)

try:
    import dmgbuild
except ImportError:
    print("需要 dmgbuild：pip install dmgbuild", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "build", "dmg-assets")

APP_NAME = "MPStyle"
APP_DISPLAY = "公众号排版工具"

# 窗口内容区尺寸（逻辑像素），背景图与图标坐标都基于这套坐标系
WIN_W, WIN_H = 660, 430
SCALE = 2

# 两个图标的中心点（窗口坐标，原点在左上角）
APP_ICON_POS = (170, 206)
DROP_ICON_POS = (490, 206)
ICON_SIZE = 128

# 主题色
BLUE = (27, 99, 243)
INK = (29, 29, 31)
GRAY = (138, 145, 156)
LINE = (206, 214, 226)


def load_font(size, weight="regular"):
    """按可用性依次尝试中文字体，避免依赖某个特定系统的字体路径。"""
    candidates = {
        "regular": [
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/System/Library/Fonts/STHeiti Light.ttc",
            "/System/Library/Fonts/Supplemental/Songti.ttc",
        ],
        "bold": [
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/System/Library/Fonts/Supplemental/Songti.ttc",
        ],
    }[weight]
    for path in candidates:
        if not os.path.exists(path):
            continue
        for index in (1, 0, 2):
            try:
                return ImageFont.truetype(path, size, index=index)
            except Exception:
                continue
    return ImageFont.load_default()


def centered(draw, text, font, y, fill):
    """在画布上水平居中。画布是逻辑尺寸 × SCALE，所以宽度也要跟着放大。"""
    width = WIN_W * SCALE
    left, _, right, _ = draw.textbbox((0, 0), text, font=font)
    draw.text(((width - (right - left)) / 2 - left, y), text, font=font, fill=fill)


def build_background(version, out_path):
    w, h = WIN_W * SCALE, WIN_H * SCALE
    img = Image.new("RGB", (w, h), (255, 255, 255))
    draw = ImageDraw.Draw(img)

    # 自上而下由纯白过渡到极浅冷灰，给窗口一点层次
    for y in range(h):
        t = y / (h - 1)
        v = int(255 - 9 * t)
        draw.line([(0, y), (w, y)], fill=(v, v, min(255, v + 3)))

    f_title = load_font(30 * SCALE, "bold")
    f_sub = load_font(13 * SCALE, "regular")
    f_foot = load_font(13 * SCALE, "regular")

    centered(draw, APP_DISPLAY, f_title, 44 * SCALE, INK)
    centered(draw, f"Markdown → 微信公众号富文本　v{version}", f_sub, 92 * SCALE, GRAY)

    # 两个图标背后的柔和落位圈，让空白处有视觉锚点
    for cx, cy in (APP_ICON_POS, DROP_ICON_POS):
        r = (ICON_SIZE / 2 + 18) * SCALE
        draw.ellipse([(cx * SCALE - r, cy * SCALE - r), (cx * SCALE + r, cy * SCALE + r)],
                     fill=(246, 249, 254))

    # 中间的箭头
    y = APP_ICON_POS[1] * SCALE
    x1, x2 = 268 * SCALE, 392 * SCALE
    shaft = 5 * SCALE
    head = 15 * SCALE
    draw.rounded_rectangle([x1, y - shaft / 2, x2 - head * 0.6, y + shaft / 2],
                           radius=shaft / 2, fill=BLUE)
    draw.polygon([(x2 - head, y - head * 0.78),
                  (x2, y),
                  (x2 - head, y + head * 0.78)], fill=BLUE)

    centered(draw, "拖动左侧图标到「应用程序」文件夹即可安装", f_foot, 366 * SCALE, GRAY)

    img.save(out_path, "PNG")
    return out_path


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2

    out_dmg = os.path.abspath(sys.argv[1])
    version = sys.argv[2]
    app_path = os.path.abspath(sys.argv[3]) if len(sys.argv) > 3 \
        else os.path.join(ROOT, "build", f"{APP_NAME}.app")

    if not os.path.isdir(app_path):
        print(f"找不到 App：{app_path}", file=sys.stderr)
        return 1

    os.makedirs(ASSETS, exist_ok=True)
    bg = build_background(version, os.path.join(ASSETS, "background.png"))

    os.makedirs(os.path.dirname(out_dmg), exist_ok=True)
    if os.path.exists(out_dmg):
        os.remove(out_dmg)

    settings = {
        "filename": out_dmg,
        "volume_name": f"{APP_DISPLAY} {version}",
        "format": "UDZO",
        "files": [app_path],
        "symlinks": {"Applications": "/Applications"},
        "icon_locations": {
            f"{APP_NAME}.app": APP_ICON_POS,
            "Applications": DROP_ICON_POS,
        },
        "background": bg,
        "window_rect": ((240, 140), (WIN_W, WIN_H)),
        "default_view": "icon-view",
        "icon_size": ICON_SIZE,
        "text_size": 12,
        "label_pos": "bottom",
        "arrange_by": "none",
        "grid_spacing": 100,
        "grid_offset": (0, 0),
        "show_status_bar": False,
        "show_tab_view": False,
        "show_toolbar": False,
        "show_pathbar": False,
        "show_sidebar": False,
    }

    dmgbuild.build_dmg(out_dmg, settings["volume_name"], settings=settings)
    print(f"已生成 {os.path.relpath(out_dmg, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
