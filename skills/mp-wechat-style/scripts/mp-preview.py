#!/usr/bin/env python3
"""生成预览页并在浏览器里打开。

预览页用的是**最终会发布出去的那份 HTML**，所以看到什么，公众号里就是什么。

用法:
    mp-preview.py <文章.md> [--theme 名字] [--no-open]

产出 <文章>.preview.html，并用系统默认浏览器打开。
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import webbrowser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import theme as theme_mod        # noqa: E402
from renderer import Renderer    # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description="生成公众号排版预览页")
    ap.add_argument("input", help="Markdown 文件路径")
    ap.add_argument("--theme", default=None, help="主题名或主题 JSON 路径")
    ap.add_argument("-o", "--output", help="预览页输出路径")
    ap.add_argument("--no-open", action="store_true", help="只生成，不打开浏览器")
    args = ap.parse_args()

    markdown = sys.stdin.read() if args.input == "-" \
        else open(args.input, encoding="utf-8").read()

    renderer = Renderer(theme_mod.load(args.theme))
    page = renderer.preview_page(renderer.render(markdown), title="排版预览")

    if args.output:
        out = args.output
    elif args.input == "-":
        out = os.path.abspath("preview.html")
    else:
        stem, _ = os.path.splitext(os.path.abspath(args.input))
        out = stem + ".preview.html"

    with open(out, "w", encoding="utf-8") as handle:
        handle.write(page)
    print(f"预览页: {out}")

    if not args.no_open:
        if sys.platform == "darwin":
            subprocess.run(["open", out], check=False)
        else:
            webbrowser.open(f"file://{out}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
