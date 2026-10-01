#!/usr/bin/env python3
"""Markdown → 公众号内联样式 HTML。

用法:
    mp-render.py <文章.md> [-o out.html] [--theme 名字或路径] [--fragment]

默认输出完整可独立打开的 HTML 页面，便于直接看效果；
加 --fragment 则只输出可粘贴的 HTML 片段。
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import theme as theme_mod            # noqa: E402
from renderer import Renderer        # noqa: E402
import parser as parser_mod          # noqa: E402


def build_renderer(theme_name: str | None) -> Renderer:
    return Renderer(theme_mod.load(theme_name))


def main() -> int:
    ap = argparse.ArgumentParser(description="Markdown → 公众号内联样式 HTML")
    ap.add_argument("input", help="Markdown 文件路径，- 表示读 stdin")
    ap.add_argument("-o", "--output", help="输出文件。留空则写到 stdout")
    ap.add_argument("--theme", default=None, help="主题名或主题 JSON 路径")
    ap.add_argument("--fragment", action="store_true",
                    help="只输出 HTML 片段（可粘贴进公众号），不套预览页骨架")
    ap.add_argument("--stats", action="store_true", help="额外打印统计信息到 stderr")
    args = ap.parse_args()

    markdown = sys.stdin.read() if args.input == "-" \
        else open(args.input, encoding="utf-8").read()

    renderer = build_renderer(args.theme)
    fragment = renderer.render(markdown)
    result = fragment if args.fragment else renderer.preview_page(fragment)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(result)
        print(f"已写出 {args.output}（{len(result)} 字符）")
    else:
        sys.stdout.write(result)

    if args.stats:
        nodes = parser_mod.parse_blocks(markdown)
        counts: dict[str, int] = {}
        def walk(items):
            for node in items:
                counts[node["kind"]] = counts.get(node["kind"], 0) + 1
                if node["kind"] == "blockquote":
                    walk(node["children"])
                elif node["kind"] == "list":
                    for item in node["items"]:
                        walk(item["children"])
        walk(nodes)
        summary = "  ".join(f"{k}={v}" for k, v in sorted(counts.items()))
        print(f"[stats] {summary}", file=sys.stderr)
        print(f"[stats] HTML {len(fragment)} 字符", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
