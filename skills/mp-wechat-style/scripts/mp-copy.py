#!/usr/bin/env python3
"""把排版结果写进系统剪贴板，直接到公众号编辑器 ⌘V 粘贴。

剪贴板同时写入 public.html 与 text/plain：前者让公众号拿到完整样式，
后者作为降级，粘到纯文本框里也不会丢内容。

macOS 用 osascript 走 AppKit 的 NSPasteboard。默认走系统剪贴板，
也可以只导出 HTML 文件供手动处理。

用法:
    mp-copy.py <文章.md> [--theme 名字] [--text-only] [--print]
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import theme as theme_mod                        # noqa: E402
from renderer import Renderer, plain_text         # noqa: E402

# 走 JXA 拿 AppKit 的 NSPasteboard。正文通过临时文件传入，
# 避免把长 HTML 塞进命令行参数触发长度上限。
JXA = r"""
ObjC.import('AppKit');
ObjC.import('Foundation');

function run(argv) {
  const htmlPath = argv[0];
  const textPath = argv[1];

  const text = $.NSString.stringWithContentsOfFileEncodingError(
      textPath, $.NSUTF8StringEncoding, null);
  const html = $.NSString.stringWithContentsOfFileEncodingError(
      htmlPath, $.NSUTF8StringEncoding, null);

  const pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;

  if (html) {
    pb.setDataForType(html.dataUsingEncoding($.NSUTF8StringEncoding), 'public.html');
  }
  if (text) {
    pb.setStringForType(text, $.NSPasteboardTypeString);
  }
  return 'ok';
}
"""


def copy_to_clipboard(html: str, text: str) -> bool:
    if sys.platform != "darwin":
        print("当前系统不是 macOS，跳过剪贴板写入。用 --print 导出 HTML 自行处理。",
              file=sys.stderr)
        return False

    with tempfile.TemporaryDirectory() as tmp:
        html_path = os.path.join(tmp, "article.html")
        text_path = os.path.join(tmp, "article.txt")
        script_path = os.path.join(tmp, "copy.js")
        with open(html_path, "w", encoding="utf-8") as handle:
            handle.write(html)
        with open(text_path, "w", encoding="utf-8") as handle:
            handle.write(text)
        with open(script_path, "w", encoding="utf-8") as handle:
            handle.write(JXA)

        result = subprocess.run(
            ["osascript", "-l", "JavaScript", script_path, html_path, text_path],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(f"写入剪贴板失败: {result.stderr.strip()}", file=sys.stderr)
            return False
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description="把排版结果复制到剪贴板")
    ap.add_argument("input", help="Markdown 文件路径，- 表示读 stdin")
    ap.add_argument("--theme", default=None, help="主题名或主题 JSON 路径")
    ap.add_argument("--print", dest="do_print", action="store_true",
                    help="额外把 HTML 片段打印到 stdout")
    ap.add_argument("--text-only", action="store_true", help="只复制纯文本")
    args = ap.parse_args()

    markdown = sys.stdin.read() if args.input == "-" \
        else open(args.input, encoding="utf-8").read()

    renderer = Renderer(theme_mod.load(args.theme))
    html = renderer.render(markdown)
    text = plain_text(markdown)

    if args.do_print:
        sys.stdout.write(html + "\n")

    if args.text_only:
        ok = copy_to_clipboard("", text)
    else:
        ok = copy_to_clipboard(html, text)

    if ok:
        print(f"已复制（HTML {len(html)} 字符 / 纯文本 {len(text)} 字符）")
        print("去公众号编辑器按 ⌘V 粘贴即可。")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
