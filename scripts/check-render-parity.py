#!/usr/bin/env python3
"""校验 Python 渲染器与 Swift 渲染器输出一致。

两个渲染器服务于同一套主题规格：App 用 Swift，Agent Skill 用 Python。
它们必须对同一份 Markdown 产出完全相同的内联样式和正文文本。
只改一边就会造成「同一个主题在 App 和 Skill 里排出来不一样」，
而这种偏差肉眼很难发现，所以放进 CI 守住。

用法:
    check-render-parity.py <swift 输出.html> <python 输出.html>
"""

from __future__ import annotations

import html as html_mod
import re
import sys


def styles(text: str) -> list[str]:
    """按出现顺序取出所有内联样式。"""
    return re.findall(r'style="([^"]*)"', text)


def body_markup(text: str) -> str:
    """取出正文区域。Swift 那侧是完整预览页，正文在 <div id="content"> 里。"""
    match = re.search(r'<div id="content">(.*?)</div></div></div>', text, re.S)
    return match.group(1) if match else text


def visible_text(markup: str) -> str:
    """去掉标签与空白后的可见文本，用来比对内容而不受排版空白影响。"""
    stripped = re.sub(r"<[^>]+>", "\x00", markup)
    return re.sub(r"[\x00\s]+", "", html_mod.unescape(stripped))


def first_difference(a: str, b: str, limit: int = 140) -> str:
    for index, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return (f"位置 {index}\n"
                    f"    Swift : ...{a[max(0, index - 30):index + limit]}...\n"
                    f"    Python: ...{b[max(0, index - 30):index + limit]}...")
    if len(a) != len(b):
        longer, shorter = (a, b) if len(a) > len(b) else (b, a)
        return f"前缀相同但长度不同（{len(a)} vs {len(b)}），多出：{longer[len(shorter):][:limit]!r}"
    return ""


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    swift, python = (open(path, encoding="utf-8").read() for path in sys.argv[1:3])

    failures: list[str] = []

    swift_styles, python_styles = styles(swift), styles(python)
    if len(swift_styles) != len(python_styles):
        failures.append(f"内联样式条数不同：Swift {len(swift_styles)} 条，Python {len(python_styles)} 条")
    mismatched = [i for i, (x, y) in enumerate(zip(swift_styles, python_styles)) if x != y]
    if mismatched:
        index = mismatched[0]
        failures.append(
            f"{len(mismatched)} 条样式不一致，第一条在第 {index} 条：\n"
            f"    Swift : {swift_styles[index]}\n"
            f"    Python: {python_styles[index]}"
        )

    swift_text = visible_text(body_markup(swift))
    python_text = visible_text(body_markup(python))
    if swift_text != python_text:
        failures.append("正文可见文本不一致：\n    " + first_difference(swift_text, python_text))

    print(f"内联样式  Swift {len(swift_styles)} 条  Python {len(python_styles)} 条")
    print(f"正文字符  Swift {len(swift_text)}    Python {len(python_text)}")

    if failures:
        print()
        for item in failures:
            print(f"✗ {item}")
        return 1

    print("✓ 两个渲染器输出一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
