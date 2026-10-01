#!/usr/bin/env python3
"""从公众号文章里萃取出主题规格（theme spec）。

思路：公众号文章的排版全部写在**内联样式**里（编辑器会丢掉 <style> 和 class），
所以拿到 #js_content 的 HTML 就等于拿到了完整排版信息，不需要猜。
本脚本把每种元素的样式统计出来取众数，再反推成 theme.json 的字段。

反推的核心是「按角色找基准，再用比例推导」：
    p 的 font-size 定为正文基准 → h2 字号除以它得到 h2Scale
    p 的 margin-bottom 除以字号得到段落间距（em）
    letter-spacing 若是 px 则换算成 em

用法:
    extract.py <文章.html> [-o theme.json] [--name 主题名]
    extract.py --url <文章链接> [-o theme.json]     # 自己驱动内置浏览器
"""

from __future__ import annotations

import argparse
import collections
import colorsys
import html as html_mod
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from html.parser import HTMLParser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# 默认主题的位置，按可靠性排序探测：
#   1. 同级目录 —— 仓库布局（skills/mp-wechat-style）或两个 Skill 并排安装
#   2. WorkBuddy 技能目录
#   3. 用户主题目录
# 全部找不到时退回下面的内置默认值，功能不受影响，只是拿不到用户改过的 default。
def _theme_candidates() -> list[str]:
    here = os.path.dirname(os.path.abspath(__file__))
    sibling = os.path.dirname(os.path.dirname(here))   # .../skills
    return [
        os.path.join(sibling, "mp-wechat-style", "themes", "default.json"),
        os.path.expanduser("~/.workbuddy/skills/mp-wechat-style/themes/default.json"),
        os.path.expanduser("~/.mp-wechat/themes/default.json"),
    ]

# 公众号文案里常见的中性色，不参与主题色评选
NEUTRAL_MAX_SATURATION = 0.12


# ── 极简 DOM ──────────────────────────────────────────────────────────

class Node:
    __slots__ = ("tag", "attrs", "children", "parent", "text")

    def __init__(self, tag: str, attrs: dict, parent: "Node | None"):
        self.tag = tag
        self.attrs = attrs
        self.children: list["Node"] = []
        self.parent = parent
        self.text = ""

    def style(self) -> dict[str, str]:
        return parse_style(self.attrs.get("style", ""))

    def walk(self):
        yield self
        for child in self.children:
            yield from child.walk()

    def find_all(self, tag: str) -> list["Node"]:
        return [n for n in self.walk() if n.tag == tag]

    def inner_text(self) -> str:
        parts = [self.text]
        for child in self.children:
            parts.append(child.inner_text())
        return "".join(parts).strip()


VOID_TAGS = {"br", "img", "hr", "input", "meta", "link", "source", "wbr"}


class TreeBuilder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", {}, None)
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = Node(tag, {k: (v or "") for k, v in attrs}, self.stack[-1])
        self.stack[-1].children.append(node)
        if tag not in VOID_TAGS:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        node = Node(tag, {k: (v or "") for k, v in attrs}, self.stack[-1])
        self.stack[-1].children.append(node)

    def handle_endtag(self, tag):
        for index in range(len(self.stack) - 1, 0, -1):
            if self.stack[index].tag == tag:
                del self.stack[index:]
                return

    def handle_data(self, data):
        if data.strip():
            self.stack[-1].text += data


def parse_html(source: str) -> Node:
    builder = TreeBuilder()
    builder.feed(source)
    return builder.root


# ── 样式解析 ──────────────────────────────────────────────────────────

def parse_style(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for chunk in text.split(";"):
        if ":" not in chunk:
            continue
        key, _, value = chunk.partition(":")
        key, value = key.strip().lower(), value.strip()
        if key and value and value != "initial":
            result[key] = value
    return result


RE_RGB = re.compile(r"rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.]+))?\s*\)")

NAMED_COLORS = {
    "black": "#000000", "white": "#FFFFFF", "red": "#FF0000", "green": "#008000",
    "blue": "#0000FF", "gray": "#808080", "grey": "#808080", "silver": "#C0C0C0",
    "orange": "#FFA500", "purple": "#800080", "navy": "#000080", "teal": "#008080",
    "maroon": "#800000", "olive": "#808000", "yellow": "#FFFF00", "lime": "#00FF00",
    "aqua": "#00FFFF", "fuchsia": "#FF00FF", "transparent": "",
}


def parse_color(value: str, over_white: bool = False) -> str | None:
    """把任意 CSS 颜色规整成 #RRGGBB。

    公众号文章大量使用低透明度的黑/白叠加来做底纹（`rgba(26,26,24,0.02)` 这类），
    直接丢弃会漏掉整个卡片底色和代码底色。取 over_white=True 时把它合成到白底上，
    得到实际呈现的实色。
    """
    text = (value or "").strip().lower()
    if not text:
        return None

    match = RE_RGB.match(text)
    if match:
        r, g, b = (float(match.group(i)) for i in (1, 2, 3))
        alpha = float(match.group(4)) if match.group(4) else 1.0
        if alpha < 0.999 and not over_white:
            return None
        # 与白底做 alpha 合成
        r = r * alpha + 255 * (1 - alpha)
        g = g * alpha + 255 * (1 - alpha)
        b = b * alpha + 255 * (1 - alpha)
        clamp = lambda v: max(0, min(255, int(round(v))))
        return "#{:02X}{:02X}{:02X}".format(clamp(r), clamp(g), clamp(b))

    if text.startswith("#"):
        body = text[1:]
        if len(body) == 3:
            return "#" + "".join(c * 2 for c in body).upper()
        if len(body) in (6, 8):
            return "#" + body[:6].upper()

    if text in NAMED_COLORS:
        return NAMED_COLORS[text] or None
    return None


def parse_background(value: str) -> str | None:
    """解析 background / background-color。可能是简写，取其中的颜色部分。"""
    text = (value or "").strip()
    if not text or text == "none":
        return None
    match = RE_RGB.search(text)
    if match:
        return parse_color(match.group(0), over_white=True)
    for token in text.replace(",", " ").split():
        if token.startswith("#"):
            return parse_color(token, over_white=True)
        if token.lower() in NAMED_COLORS:
            return parse_color(token, over_white=True)
    return None


def parse_length(value: str, base: float = 0.0) -> float | None:
    """把 CSS 长度规整成 px。em / rem 按 base 换算。"""
    text = (value or "").strip().lower()
    match = re.match(r"^(-?[\d.]+)\s*(px|em|rem|pt|%)?$", text)
    if not match:
        return None
    number = float(match.group(1))
    unit = match.group(2) or "px"
    if unit == "px":
        return number
    if unit in ("em", "rem"):
        return number * (base or 16)
    if unit == "pt":
        return number * 4 / 3
    if unit == "%":
        return number / 100 * (base or 16)
    return number


def saturation(color: str) -> float:
    text = color.lstrip("#")
    r, g, b = (int(text[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hsv(r, g, b)[1]


def luminance(color: str) -> float:
    text = color.lstrip("#")
    r, g, b = (int(text[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


# ── 统计 ──────────────────────────────────────────────────────────────

class Collector:
    """按标签收集样式取值并计数，最后取众数。"""

    def __init__(self, root: Node):
        self.by_tag: dict[str, list[dict[str, str]]] = collections.defaultdict(list)
        self.root = root
        for node in root.walk():
            if node.tag in ("#root", "span", "br", "html", "head", "body", "script"):
                continue
            self.by_tag[node.tag].append(node.style())

    def mode(self, tag: str, prop: str, min_count: int = 1) -> str | None:
        values = [s[prop] for s in self.by_tag.get(tag, []) if prop in s]
        if len(values) < min_count:
            return None
        return collections.Counter(values).most_common(1)[0][0]

    def coverage(self, tag: str, prop: str) -> float:
        """该属性在同类元素里的出现比例。

        用来区分「设计上就没写」和「写得少」。比如 92 个段落里只有 1 个声明了
        letter-spacing，那是局部特例，不代表整体字距；反过来如果 80% 都声明了，
        那它就是这个设计的固有部分。
        """
        total = len(self.by_tag.get(tag, []))
        if not total:
            return 0.0
        return sum(1 for s in self.by_tag.get(tag, []) if prop in s) / total

    def mode_bg(self, tag: str, min_count: int = 1) -> str | None:
        """取底色众数。公众号有时写 background-color，有时写 background 简写，都要认。"""
        values: list[str] = []
        for style in self.by_tag.get(tag, []):
            raw = style.get("background-color") or style.get("background")
            if not raw:
                continue
            color = parse_background(raw)
            if color:
                values.append(color)
        if len(values) < min_count:
            return None
        return collections.Counter(values).most_common(1)[0][0]

    def mode_color(self, tag: str, prop: str = "color") -> str | None:
        values = [parse_color(s[prop]) for s in self.by_tag.get(tag, []) if prop in s]
        values = [v for v in values if v]
        if not values:
            return None
        return collections.Counter(values).most_common(1)[0][0]

    def mode_length(self, tag: str, prop: str, base: float = 0.0) -> float | None:
        values = [parse_length(s[prop], base) for s in self.by_tag.get(tag, []) if prop in s]
        values = [v for v in values if v is not None]
        if not values:
            return None
        return collections.Counter(round(v, 2) for v in values).most_common(1)[0][0]

    def all_colors(self) -> collections.Counter:
        counter: collections.Counter = collections.Counter()
        for styles in self.by_tag.values():
            for style in styles:
                for prop in ("color", "background-color", "border-left-color",
                             "border-top-color", "border-bottom-color", "border-color"):
                    if prop in style:
                        color = parse_color(style[prop])
                        if color:
                            counter[color] += 1
        return counter


# ── 反推主题 ──────────────────────────────────────────────────────────

def extract(html_text: str, base_theme: dict) -> tuple[dict, list[str]]:
    theme = dict(base_theme)
    notes: list[str] = []

    root = parse_html(html_text)
    # 优先只看正文容器，避免页头页脚的样式污染统计
    content = next(
        (n for n in root.walk() if n.attrs.get("id") == "js_content"),
        root,
    )
    col = Collector(content)

    # ── 正文基准 ──
    body_size = col.mode_length("p", "font-size") \
        or col.mode_length("section", "font-size") or 15.0
    if col.mode_length("p", "font-size") is None:
        notes.append("没找到带 font-size 的段落，正文字号沿用默认值")
    theme["fontSize"] = body_size

    body_color = col.mode_color("p") or base_theme["textColor"]
    theme["textColor"] = body_color

    weight = col.mode("p", "font-weight")
    if weight:
        try:
            theme["bodyWeight"] = int(float(weight))
        except ValueError:
            pass
    else:
        # 没声明字重时浏览器按 400 渲染，照抄这个事实而不是套用我们默认的 100
        theme["bodyWeight"] = 400
        notes.append("正文没有声明 font-weight，按浏览器默认的 400 处理")

    line_height = col.mode("p", "line-height")
    if line_height:
        value = parse_length(line_height, body_size)
        if value is not None and value > 0:
            # 无单位的行高是倍数，直接可用；带 px 的换算成倍数
            theme["lineHeight"] = round(value, 2) if "px" not in line_height \
                else round(value / body_size, 2)

    # 字距只有少数段落声明时说明它不是这套设计的一部分，归零而不是跟着特例走
    if col.coverage("p", "letter-spacing") >= 0.2:
        spacing = col.mode("p", "letter-spacing")
        value = parse_length(spacing or "", body_size)
        if value is not None:
            theme["letterSpacing"] = round(value / body_size, 3)
    else:
        theme["letterSpacing"] = 0

    align = col.mode("p", "text-align")
    if col.coverage("p", "text-align") >= 0.3 and align:
        theme["textAlignJustify"] = align == "justify"
    else:
        theme["textAlignJustify"] = False

    font = col.mode("p", "font-family")
    if font:
        theme["fontFamily"] = _quote_fonts(font)
    mono = col.mode("code", "font-family") or col.mode("pre", "font-family")
    if mono:
        theme["monoFamily"] = _quote_fonts(mono)
        if font and mono == font:
            theme["fontFamily"] = _quote_fonts(font)

    margin = _margin_bottom(col, "p", body_size)
    if margin:
        theme["paragraphSpacing"] = round(margin / body_size, 2)

    # ── 标题 ──
    for level, scale_key, top_key, bottom_key in (
        (1, "h1Scale", "h1Top", "h1Bottom"),
        (2, "h2Scale", "h2Top", "h2Bottom"),
        (3, "h3Scale", "h3Top", "h3Bottom"),
        (4, "h4Scale", None, None),
    ):
        size = col.mode_length(f"h{level}", "font-size")
        if not size or size <= 0:
            continue
        theme[scale_key] = round(size / body_size, 3)
        if top_key:
            top = _margin_side(col, f"h{level}", body_size, "top")
            bottom = _margin_side(col, f"h{level}", body_size, "bottom")
            if top is not None:
                theme[top_key] = round(top / body_size, 2)
            if bottom is not None:
                theme[bottom_key] = round(bottom / body_size, 2)

    heading_weight = col.mode("h2", "font-weight") or col.mode("h1", "font-weight")
    if heading_weight:
        try:
            theme["headingWeight"] = int(float(heading_weight))
        except ValueError:
            pass

    heading_lh = col.mode("h2", "line-height")
    if heading_lh:
        value = parse_length(heading_lh, body_size)
        if value:
            theme["h2LineHeight"] = round(value, 2) if "px" not in heading_lh \
                else round(value / theme.get("fontSize", body_size) * body_size / body_size, 2)
    heading_lh3 = col.mode("h3", "line-height")
    if heading_lh3:
        value = parse_length(heading_lh3, body_size)
        if value:
            theme["h3LineHeight"] = round(value, 2) if "px" not in heading_lh3 \
                else round(value / body_size, 2)

    heading_color = col.mode_color("h2") or col.mode_color("h1")

    # ── 加粗 ──
    bold_weight = col.mode("strong", "font-weight")
    if bold_weight:
        try:
            theme["boldWeight"] = int(float(bold_weight))
        except ValueError:
            pass
    bold_color = col.mode_color("strong")
    if bold_color:
        if _close(bold_color, body_color):
            theme["boldColorMode"] = "inherit"
        else:
            theme["boldColorMode"] = "custom"
            theme["customBoldColor"] = bold_color

    # ── 代码 ──
    code_size = col.mode_length("code", "font-size")
    if code_size:
        theme["codeScale"] = round(code_size / body_size, 3)
    code_bg = col.mode_bg("code") or col.mode_bg("pre")
    if code_bg:
        theme["codeBg"] = code_bg

    # ── 引用 ──
    bar = col.mode_length("blockquote", "border-left-width")
    if bar:
        theme["quoteBarWidth"] = round(bar, 1)
    quote_radius = col.mode_length("blockquote", "border-top-right-radius") \
        or col.mode_length("blockquote", "border-radius")
    if quote_radius:
        theme["quoteRadius"] = round(quote_radius, 1)
    quote_text = col.mode_color("blockquote")
    if quote_text:
        theme["quoteTextColor"] = quote_text

    # ── 图片 ──
    radius = col.mode_length("img", "border-radius")
    if radius is not None:
        theme["imageRadius"] = round(radius, 1)
    img_shadow = col.mode("img", "box-shadow")
    theme["imageShadow"] = bool(img_shadow and img_shadow != "none")

    # ── 外框卡片 ──
    card_bg, card_radius = _detect_card(content)
    if card_bg:
        theme["cardColor"] = card_bg
        theme["cardEnabled"] = True
        # 卡片检测到了但没写圆角，说明原设计就是直角，不要沿用我们的默认圆角
        theme["cardRadius"] = round(card_radius, 1)

    secondary = _pick_secondary(col, body_color)
    if secondary:
        theme["secondaryTextColor"] = secondary

    # ── 主题色 ──
    accent = _pick_accent(col, body_color, heading_color)
    if accent:
        theme["themeColor"] = accent
    if heading_color:
        if _close(heading_color, accent or ""):
            theme["headingColorMode"] = "theme"
        elif _close(heading_color, "#1D1D1F"):
            theme["headingColorMode"] = "dark"
        else:
            theme["headingColorMode"] = "custom"
            theme["customHeadingColor"] = heading_color

    return theme, notes


def _quote_fonts(stack: str) -> str:
    """把公众号输出的字体栈规整成带引号的 CSS 值。

    编辑器会把 "JetBrains Mono" 写成 &quot;JetBrains Mono&quot;，解析后已经还原成普通引号，
    但引号是双引号时会截断 style 属性，统一换成单引号。
    """
    text = stack.replace('"', "'").replace("&quot;", "'")
    return re.sub(r"\s*,\s*", ", ", text.strip())


def _margin_side(col: Collector, tag: str, base: float, side: str) -> float | None:
    for prop in (f"margin-{side}", "margin"):
        raw = col.mode(tag, prop)
        if not raw:
            continue
        parts = raw.split()
        if prop == "margin":
            if len(parts) == 1:
                value = parts[0]
            elif side == "top":
                value = parts[0]
            else:
                value = parts[2] if len(parts) >= 3 else parts[0]
        else:
            value = parts[0]
        parsed = parse_length(value, base)
        if parsed is not None:
            return parsed
    return None


def _margin_bottom(col: Collector, tag: str, base: float) -> float | None:
    return _margin_side(col, tag, base, "bottom")


def _detect_card(content: Node):
    """找最外层带可见底色的 section，那就是文章的外框卡片。

    注意容差要压到 2：很多文章用 rgba(26,26,24,0.02) 这种极淡的叠加做卡片，
    合成出来是 #FAFAFA，跟纯白只差 5。用默认容差会把它当成白色跳过，
    于是错取到更内层的色块。
    """
    for node in content.walk():
        if node.tag != "section":
            continue
        style = node.style()
        raw = style.get("background-color") or style.get("background")
        if not raw:
            continue
        color = parse_background(raw)
        if not color or _close(color, "#FFFFFF", tolerance=2):
            continue
        radius = parse_length(style.get("border-radius", ""), 16)
        return color, (radius or 0.0)
    return None, None


def _pick_secondary(col: Collector, body_color: str) -> str | None:
    """次级文字色：段落里比正文明显更浅、且不止出现一次的那个颜色。

    只出现一次的多半是某处的局部装饰色，不能代表「次级文字」这个语义。
    """
    counter: collections.Counter = collections.Counter()
    for style in col.by_tag.get("p", []):
        color = parse_color(style.get("color", ""))
        if color and not _close(color, body_color, 30) and luminance(color) > 0.45:
            counter[color] += 1
    if not counter:
        return None
    color, count = counter.most_common(1)[0]
    return color if count >= 2 else None


def _close(a: str, b: str, tolerance: int = 12) -> bool:
    if not a or not b:
        return False
    try:
        pa = tuple(int(a.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
        pb = tuple(int(b.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return False
    return all(abs(x - y) <= tolerance for x, y in zip(pa, pb))


def _pick_accent(col: Collector, body_color: str, heading_color: str | None) -> str | None:
    """挑主题色。

    公众号文章里颜色很多，真正算「主题色」的是那个用来做强调的饱和度较高的颜色。
    标题色优先（它承担视觉识别），其次是链接色，最后才看整体分布。
    """
    if heading_color and saturation(heading_color) > NEUTRAL_MAX_SATURATION \
            and not _close(heading_color, body_color):
        return heading_color

    for tag, weight in (("a", 2.0), ("h2", 3.0), ("strong", 1.5), ("code", 1.0)):
        color = col.mode_color(tag)
        if color and saturation(color) > NEUTRAL_MAX_SATURATION \
                and not _close(color, body_color):
            return color

    scored = [
        (saturation(c) * n, c) for c, n in col.all_colors().items()
        if saturation(c) > NEUTRAL_MAX_SATURATION and luminance(c) < 0.85
    ]
    if scored:
        return max(scored)[1]
    return None


# ── 取 HTML ──────────────────────────────────────────────────────────

def fetch_with_builtin_browser(url: str) -> str | None:
    """用 WorkBuddy 内置浏览器的 CLI 取正文 HTML。

    公众号正文大量依赖 JS 渲染，直接 curl 拿到的可能不完整，
    这也是这里坚持用真浏览器的原因。
    """
    if not shutil.which("agent-browser"):
        return None

    def run(*args):
        return subprocess.run(["agent-browser", *args],
                              capture_output=True, text=True, timeout=90)

    try:
        run("open", url)
        # wait 可能在不收敛的页面上挂住，失败就跳过，直接取内容
        run("wait", "--load", "networkidle")

        result = run("get", "html", "#js_content")
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout

        # #js_content 不在时退一步取整个 body
        result = run("get", "html", "body")
        return result.stdout if result.returncode == 0 and result.stdout.strip() else None
    except Exception:
        return None
    finally:
        # 无论成败都要关，否则会留下后台 Chromium 进程
        try:
            run("close")
        except Exception:
            pass


def main() -> int:
    ap = argparse.ArgumentParser(description="从公众号文章萃取主题规格")
    ap.add_argument("input", nargs="?", help="保存好的文章 HTML 文件")
    ap.add_argument("--url", help="文章链接。自己驱动内置浏览器抓取")
    ap.add_argument("-o", "--output", help="主题输出路径，默认 stdout")
    ap.add_argument("--name", help="主题名，会写进 JSON 的 _name 字段便于识别")
    ap.add_argument("--base", default=None, help="基准主题：在其上覆盖萃取结果")
    ap.add_argument("--quiet", action="store_true", help="不打印诊断信息")
    args = ap.parse_args()

    html_text: str | None = None
    if args.url:
        html_text = fetch_with_builtin_browser(args.url)
        if html_text is None:
            print("✗ 抓取失败。", file=sys.stderr)
            if not shutil.which("agent-browser"):
                print("  没找到 agent-browser。先装：npm i -g agent-browser && agent-browser install",
                      file=sys.stderr)
            else:
                print("  可以手动取：agent-browser open <url> && "
                      "agent-browser get html '#js_content' > article.html",
                      file=sys.stderr)
            return 1
    elif args.input:
        html_text = open(args.input, encoding="utf-8").read()
    else:
        html_text = sys.stdin.read()

    if not html_text.strip():
        print("✗ 输入是空的", file=sys.stderr)
        return 1

    base = _load_base(args.base)
    theme, notes = extract(html_text, base)

    if args.name:
        theme = {"_name": args.name, **theme}

    payload = json.dumps(theme, ensure_ascii=False, indent=2)
    if args.output:
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(payload + "\n")

    if not args.quiet:
        _report(theme, notes, args.output)
    elif args.output:
        print(f"已写出 {args.output}")

    if not args.output:
        print(payload)
    return 0


def _load_base(path: str | None) -> dict:
    """基准主题。优先用 mp-wechat-style 的默认主题，拿不到就用等价内置值。"""
    candidates = [path] if path else _theme_candidates()
    for candidate in candidates:
        if candidate and os.path.isfile(candidate):
            with open(candidate, encoding="utf-8") as handle:
                return json.load(handle)
    return BUILTIN_BASE


# 拿不到 mp-wechat-style 的 default.json 时的等价兜底。
# 刻意在本地复制一份而不是跨 Skill import：两个 Skill 各自独立分发，
# 不假设对方和自己装在同一台机器、同一个目录下。
BUILTIN_BASE = {
    "themeColor": "#1B63F3", "textColor": "#333333",
    "secondaryTextColor": "#888888", "headingColorMode": "theme",
    "customHeadingColor": "#1D1D1F",
    "fontFamily": "-apple-system, BlinkMacSystemFont, 'PingFang SC', "
                  "'Hiragino Sans GB', 'Microsoft YaHei', sans-serif",
    "monoFamily": "SFMono-Regular, Menlo, Consolas, monospace",
    "fontSize": 15, "bodyWeight": 100, "boldWeight": 500,
    "boldColorMode": "theme", "customBoldColor": "#1B63F3",
    "lineHeight": 1.8, "letterSpacing": 0.1, "paragraphSpacing": 1.2,
    "textAlignJustify": True,
    "h1Scale": 1.6, "h2Scale": 1.333, "h3Scale": 1.13, "h4Scale": 1.0,
    "headingWeight": 600, "h1Top": 1.9, "h1Bottom": 1.0,
    "h2Top": 1.8, "h2Bottom": 1.0, "h2LineHeight": 1.6,
    "h3Top": 1.5, "h3Bottom": 0.7, "h3LineHeight": 1.45,
    "listIndent": 1.2, "listItemSpacing": 0.35, "listLineHeight": 1.7,
    "listMarkerWeight": 500,
    "imageRadius": 8, "imageShadow": True, "imageSpacing": 1.5,
    "quoteBarWidth": 3, "quoteRadius": 8, "quoteBgTint": 0.07,
    "quoteTextColor": "#555555",
    "codeBg": "#F7F8FA", "codeRadius": 8, "codeScale": 0.88,
    "longTextMaxHeight": 320, "longTextBg": "#F7F9FC", "longTextRadius": 8,
    "longTextPadding": 0.9, "longImageMaxHeight": 450, "longImageRadius": 8,
    "galleryImageWidth": 72, "galleryGap": 12, "galleryRadius": 8,
    "scrollHintEnabled": True,
    "cardEnabled": True, "cardColor": "#F9F8F4", "cardRadius": 24,
    "previewWidth": 375,
}


def _report(theme: dict, notes: list[str], output: str | None) -> None:
    def show(label: str, *keys: str) -> None:
        parts = [f"{k}={theme[k]}" for k in keys if k in theme]
        print(f"  {label:<10} " + "  ".join(parts))

    print("── 萃取结果 ─────────────────────────────")
    show("主题色", "themeColor")
    show("正文", "textColor", "fontSize", "bodyWeight", "lineHeight", "letterSpacing")
    show("加粗", "boldWeight", "boldColorMode")
    show("标题", "headingColorMode", "customHeadingColor", "h1Scale", "h2Scale", "h3Scale")
    show("代码", "codeScale", "codeBg")
    show("图片", "imageRadius")
    show("外框", "cardEnabled", "cardColor", "cardRadius")
    if notes:
        print("── 提示 ─────────────────────────────────")
        for note in notes:
            print(f"  ! {note}")
    if output:
        print(f"── 已写出 {output}")
    print()
    print("建议先渲染一份自己的文章看效果：")
    print(f"  python3 mp-wechat-style/scripts/mp-preview.py 你的文章.md --theme {output or '主题.json'}")


if __name__ == "__main__":
    sys.exit(main())
