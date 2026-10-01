"""Markdown → 可直接粘贴进微信公众号编辑器的内联样式 HTML。

为什么全部内联：公众号编辑器会丢弃 <style> 标签和 class，只有 style 属性能存活。
为什么列表序号用真实文本节点：公众号不支持 ::before 伪元素，也不认 list-style 的颜色。

输出的每一处 CSS 都与 MPStyle（macOS 排版工具）的 StyleKit 逐条对齐，
保证「同一个主题在两个工具里排出来的东西一样」。
"""

from __future__ import annotations

import parser as P
import theme as T


class StyleKit:
    def __init__(self, t: dict):
        self.t = t
        self.theme = T.normalize_color(t["themeColor"])
        self.body = T.normalize_color(t["textColor"])
        self.heading_color = T.normalize_color(T.effective_heading_color(t))
        self.muted = T.normalize_color(t["secondaryTextColor"])
        self.quote_text = T.normalize_color(t["quoteTextColor"])
        self.code_bg = T.normalize_color(t["codeBg"])
        self.card_bg = T.normalize_color(t["cardColor"])

    # ── 基础 ──

    def theme_tint(self, share: float) -> str:
        """主题色底纹。share 是主题色占比，越小越浅。"""
        return T.fade(self.theme, 1 - share)

    @property
    def border_color(self) -> str:
        return T.fade(self.theme, 0.88)

    @staticmethod
    def css(pairs: list[tuple[str, str | None]]) -> str:
        """拼成 style 属性的值。

        关键约束：属性本身用双引号包裹，值里绝不能出现双引号，
        否则会被浏览器提前截断、后面的声明全部失效。统一降级成单引号。
        """
        return "; ".join(f"{k}: {v}" for k, v in pairs if v is not None).replace('"', "'")

    @staticmethod
    def _px(v: float) -> str:
        return T.css_px(v)

    @staticmethod
    def _em(v: float) -> str:
        return T.css_em(v)

    # ── 正文 ──

    def paragraph(self, in_quote: bool = False, compact: bool = False) -> str:
        t = self.t
        if in_quote:
            return self.css([
                ("margin", f"{self._em(t['paragraphSpacing'] * 0.55)} 0"),
                ("font-size", self._px(T.px_round(t["fontSize"] * 0.96))),
                ("font-weight", str(t["bodyWeight"])),
                ("line-height", "1.75"),
                ("letter-spacing", self._em(t["letterSpacing"])),
                ("color", self.quote_text),
                ("text-align", "justify" if t["textAlignJustify"] else "left"),
            ])
        spacing = t["paragraphSpacing"] * 0.45 if compact else t["paragraphSpacing"]
        line_height = min(t["lineHeight"], 1.75) if compact else t["lineHeight"]
        return self.css([
            ("margin", f"{self._em(spacing)} 0"),
            ("font-size", self._px(t["fontSize"])),
            ("font-weight", str(t["bodyWeight"])),
            ("line-height", f"{line_height}"),
            ("letter-spacing", self._em(t["letterSpacing"])),
            ("color", self.body),
            ("text-align", "justify" if t["textAlignJustify"] else "left"),
        ])

    # ── 标题 ──

    def heading(self, level: int) -> str:
        t = self.t
        if level == 1:
            return self.css([
                ("margin", f"{self._em(t['h1Top'])} 0 {self._em(t['h1Bottom'])}"),
                ("padding", "0.2em 0 0.3em"),
                ("font-size", self._px(T.px_round(t["fontSize"] * t["h1Scale"]))),
                ("font-weight", str(t["headingWeight"])),
                ("line-height", "1.5"),
                ("letter-spacing", "0.02em"),
                ("color", self.heading_color),
                ("text-align", "left"),
            ])
        if level == 2:
            return self.css([
                ("margin", f"{self._em(t['h2Top'])} 0 {self._em(t['h2Bottom'])}"),
                ("padding", "0.32em 0 0.4em"),
                ("font-size", self._px(T.px_round(t["fontSize"] * t["h2Scale"]))),
                ("font-weight", str(t["headingWeight"])),
                ("line-height", f"{t['h2LineHeight']}"),
                ("letter-spacing", "0.02em"),
                ("color", self.heading_color),
                ("text-align", "left"),
            ])
        if level == 3:
            return self.css([
                ("margin", f"{self._em(t['h3Top'])} 0 {self._em(t['h3Bottom'])}"),
                ("padding", "0.22em 0 0.28em"),
                ("font-size", self._px(T.px_round(t["fontSize"] * t["h3Scale"]))),
                ("font-weight", str(t["headingWeight"])),
                ("line-height", f"{t['h3LineHeight']}"),
                ("letter-spacing", "0.02em"),
                ("color", self.heading_color),
                ("text-align", "left"),
            ])
        return self.css([
            ("margin", "1.3em 0 0.6em"),
            ("padding", "0.18em 0 0.22em"),
            ("font-size", self._px(T.px_round(t["fontSize"] * t["h4Scale"]))),
            ("font-weight", str(t["headingWeight"])),
            ("line-height", "1.5"),
            ("letter-spacing", "0.02em"),
            ("color", self.heading_color),
            ("text-align", "left"),
        ])

    # ── 列表 ──

    def list_item(self, depth: int) -> str:
        t = self.t
        indent = t["listIndent"] * (depth + 1)
        return self.css([
            ("margin", f"{self._em(t['listItemSpacing'])} 0 "
                       f"{self._em(t['listItemSpacing'])} {self._em(indent)}"),
            ("text-indent", self._em(-t["listIndent"])),
            ("font-size", self._px(t["fontSize"])),
            ("font-weight", str(t["bodyWeight"])),
            ("line-height", f"{t['listLineHeight']}"),
            ("letter-spacing", self._em(t["letterSpacing"])),
            ("color", self.body),
            ("text-align", "left"),
        ])

    def list_marker(self) -> str:
        return self.css([
            ("color", self.theme),
            ("font-weight", str(self.t["listMarkerWeight"])),
        ])

    # ── 引用 ──

    def blockquote(self, depth: int) -> str:
        t = self.t
        pad = 1.05 + depth * 0.9
        margin = t["paragraphSpacing"] * (0.6 if depth > 0 else 1)
        tint = t["quoteBgTint"] * (1 + depth * 0.8)
        return self.css([
            ("margin", f"{self._em(margin)} 0"),
            ("padding", f"{self._em(0.85)} {self._em(pad)}"),
            ("background-color", self.theme_tint(tint)),
            ("border-left", f"{self._px(t['quoteBarWidth'])} solid {self.theme}"),
            ("border-radius", f"0 {self._px(t['quoteRadius'])} {self._px(t['quoteRadius'])} 0"),
            ("box-sizing", "border-box"),
        ])

    # ── 代码 ──

    def code_block(self) -> str:
        t = self.t
        return self.css([
            ("margin", f"{self._em(t['paragraphSpacing'] * 1.2)} 0"),
            ("padding", "1em 1.15em"),
            ("background-color", self.code_bg),
            ("border-radius", self._px(t["codeRadius"])),
            ("font-size", self._px(T.px_round(t["fontSize"] * t["codeScale"]))),
            ("line-height", "1.7"),
            ("letter-spacing", "0"),
            ("color", "#2B2B2B"),
            ("font-family", t["monoFamily"]),
            ("white-space", "pre-wrap"),
            ("word-break", "break-word"),
            ("overflow-x", "auto"),
            ("display", "block"),
        ])

    def inline_code(self) -> str:
        t = self.t
        return self.css([
            ("background-color", self.theme_tint(0.10)),
            ("color", self.theme),
            ("padding", "0.12em 0.38em"),
            ("border-radius", "4px"),
            ("font-size", self._px(T.px_round(t["fontSize"] * 0.9))),
            ("font-family", t["monoFamily"]),
            ("letter-spacing", "0"),
        ])

    # ── 图片 ──

    def image(self) -> str:
        t = self.t
        return self.css([
            ("max-width", "100%"),
            ("height", "auto"),
            ("display", "block"),
            ("margin", f"{self._em(t['imageSpacing'])} auto"),
            ("border-radius", self._px(t["imageRadius"])),
            ("box-shadow", f"0 8px 25px {T.rgba('#000000', 0.1)}" if t["imageShadow"] else None),
        ])

    # ── 行内 ──

    def strong(self) -> str:
        return self.css([
            ("font-weight", str(self.t["boldWeight"])),
            ("color", T.normalize_color(T.effective_bold_color(self.t))),
        ])

    def emphasis(self) -> str:
        return self.css([("font-style", "italic")])

    def strike(self) -> str:
        return self.css([("text-decoration", "line-through"), ("color", self.muted)])

    def link(self) -> str:
        return self.css([
            ("color", self.theme),
            ("text-decoration", "none"),
            ("border-bottom", f"1px solid {T.fade(self.theme, 0.45)}"),
        ])

    # ── 分割线 ──

    def divider(self) -> str:
        t = self.t
        return self.css([
            ("height", "1px"),
            ("background-color", T.fade(self.theme, 0.86)),
            ("margin", f"{self._em(t['paragraphSpacing'] * 1.8)} 0"),
            ("font-size", "0"),
            ("line-height", "0"),
        ])

    # ── 表格 ──

    def table_wrapper(self) -> str:
        return self.css([
            ("margin", f"{self._em(self.t['paragraphSpacing'])} 0"),
            ("overflow-x", "auto"),
        ])

    def table(self) -> str:
        t = self.t
        return self.css([
            ("width", "100%"),
            ("border-collapse", "collapse"),
            ("border-spacing", "0"),
            ("font-size", self._px(T.px_round(t["fontSize"] * 0.93))),
            ("line-height", "1.6"),
        ])

    def table_header_cell(self, align: str) -> str:
        t = self.t
        return self.css([
            ("border", f"1px solid {self.border_color}"),
            ("background-color", self.theme_tint(0.08)),
            ("padding", "0.5em 0.7em"),
            ("color", self.theme),
            ("font-weight", str(t["boldWeight"])),
            ("font-size", self._px(T.px_round(t["fontSize"] * 0.93))),
            ("text-align", align),
        ])

    def table_cell(self, align: str) -> str:
        t = self.t
        return self.css([
            ("border", f"1px solid {self.border_color}"),
            ("padding", "0.5em 0.7em"),
            ("color", self.body),
            ("font-weight", str(t["bodyWeight"])),
            ("font-size", self._px(T.px_round(t["fontSize"] * 0.93))),
            ("text-align", align),
        ])

    # ── 滚动块 ──

    def long_text_container(self) -> str:
        t = self.t
        return self.css([
            ("max-height", self._px(t["longTextMaxHeight"])),
            ("overflow-y", "auto"),
            ("overflow-x", "hidden"),
            ("-webkit-overflow-scrolling", "touch"),
            ("background-color", T.normalize_color(t["longTextBg"])),
            ("border-radius", self._px(t["longTextRadius"])),
            ("padding", f"{self._em(t['longTextPadding'] * 0.2)} "
                        f"{self._em(t['longTextPadding'] * 1.2)}"),
            ("box-sizing", "border-box"),
            ("margin", f"{self._em(t['paragraphSpacing'])} 0"),
        ])

    def long_image_container(self) -> str:
        t = self.t
        return self.css([
            ("max-height", self._px(t["longImageMaxHeight"])),
            ("overflow-y", "auto"),
            ("overflow-x", "hidden"),
            ("-webkit-overflow-scrolling", "touch"),
            ("border-radius", self._px(t["longImageRadius"])),
            ("box-sizing", "border-box"),
            ("margin", f"{self._em(t['imageSpacing'])} 0"),
        ])

    def long_image(self) -> str:
        return self.css([
            ("display", "block"),
            ("width", "100%"),
            ("height", "auto"),
            ("border-radius", self._px(self.t["longImageRadius"])),
        ])

    def gallery_container(self) -> str:
        t = self.t
        return self.css([
            ("overflow-x", "auto"),
            ("overflow-y", "hidden"),
            ("-webkit-overflow-scrolling", "touch"),
            ("white-space", "nowrap"),
            ("margin", f"{self._em(t['imageSpacing'])} 0"),
            ("padding-bottom", "6px"),
            ("box-sizing", "border-box"),
        ])

    def gallery_image(self, is_last: bool) -> str:
        t = self.t
        return self.css([
            ("display", "inline-block"),
            ("width", T.css_percent(t["galleryImageWidth"])),
            ("height", "auto"),
            ("vertical-align", "top"),
            ("border-radius", self._px(t["galleryRadius"])),
            ("box-shadow", f"0 6px 18px {T.rgba('#000000', 0.1)}" if t["imageShadow"] else None),
            ("margin-right", "0" if is_last else self._px(t["galleryGap"])),
        ])

    def scroll_hint(self) -> str:
        t = self.t
        return self.css([
            ("margin", f"0.4em 0 {self._em(t['paragraphSpacing'])}"),
            ("font-size", self._px(T.px_round(t["fontSize"] * 0.8))),
            ("font-weight", str(t["bodyWeight"])),
            ("color", self.muted),
            ("text-align", "center"),
            ("letter-spacing", "0.05em"),
            ("line-height", "2"),
        ])

    # ── 外框 ──

    def card(self) -> str:
        t = self.t
        return self.css([
            ("background-color", self.card_bg),
            ("border-radius", self._px(t["cardRadius"])),
            ("padding", "8px 12px"),
            ("box-sizing", "border-box"),
            ("font-family", t["fontFamily"]),
            ("font-size", self._px(t["fontSize"])),
            ("color", self.body),
        ])

    def plain_wrapper(self) -> str:
        t = self.t
        return self.css([
            ("box-sizing", "border-box"),
            ("font-family", t["fontFamily"]),
            ("font-size", self._px(t["fontSize"])),
            ("color", self.body),
        ])


# ── 渲染器 ────────────────────────────────────────────────────────────

CUSTOM_HINTS = {
    "long-text": ("↓", "上下滑动查看"),
    "long-image": ("↓", "上下滑动查看"),
    "more-images": ("", "左右滑动查看更多 →"),
}


class Renderer:
    def __init__(self, theme: dict):
        self.t = theme
        self.kit = StyleKit(theme)

    # ── 对外 ──

    def render(self, markdown: str) -> str:
        body = self._blocks(P.parse_blocks(markdown), quote_depth=0,
                            list_depth=0, in_scroll=False)
        wrapper = self.kit.card() if self.t["cardEnabled"] else self.kit.plain_wrapper()
        return f'<section style="{wrapper}">\n{body}\n</section>'

    def preview_page(self, content: str = "", title: str = "预览") -> str:
        width = int(self.t["previewWidth"])
        font = self.t["fontFamily"].replace('"', "'")
        inner = content or ('<div id="empty">粘贴 Markdown 后这里会实时显示排版效果</div>')
        return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{P.escape_html(title)}</title>
<style>
  html, body {{ margin: 0; padding: 0; background: #EEF0F3; }}
  #stage {{ display: flex; justify-content: center; padding: 22px 14px 70px; }}
  #page {{
    width: {width}px; max-width: 100%;
    background: #FFFFFF; border-radius: 16px;
    box-shadow: 0 10px 34px rgba(0,0,0,.10);
    overflow: hidden;
  }}
  #content {{
    padding: 22px 18px 44px;
    box-sizing: border-box;
    font-family: {font};
    font-size: {T.css_px(self.t['fontSize'])};
    color: {T.normalize_color(self.t['textColor'])};
    -webkit-font-smoothing: antialiased;
    word-wrap: break-word;
  }}
  #content *, #content *::before, #content *::after {{ box-sizing: border-box; }}
  #content img {{ max-width: 100%; }}
  #content table {{ border-collapse: collapse; }}
  #empty {{ color: #A8AFB8; font-size: 13px; text-align: center; padding: 90px 20px; line-height: 2; }}
  ::-webkit-scrollbar {{ width: 8px; height: 8px; }}
  ::-webkit-scrollbar-thumb {{ background: #C9CED6; border-radius: 4px; }}
  ::-webkit-scrollbar-track {{ background: transparent; }}
</style>
</head>
<body>
  <div id="stage"><div id="page"><div id="content">{inner}</div></div></div>
</body>
</html>
"""

    # ── 块级 ──

    def _blocks(self, nodes, quote_depth, list_depth, in_scroll) -> str:
        return "\n".join(
            self._block(n, quote_depth, list_depth, in_scroll) for n in nodes
        )

    def _block(self, node, quote_depth, list_depth, in_scroll) -> str:
        kind = node["kind"]

        if kind == "heading":
            level = max(1, min(node["level"], 6))
            style = self.kit.heading(min(level, 4))
            text = self._inlines(P.parse_inlines(node["text"]), quote_depth, list_depth)
            return f'<h{level} style="{style}">{text}</h{level}>'

        if kind == "paragraph":
            inlines = P.parse_inlines(node["text"])
            # 整段只有一张图时直接输出 img，避免 p 的外边距造成双倍间距
            if len(inlines) == 1 and inlines[0]["kind"] == "image":
                return self._inlines(inlines, quote_depth, list_depth)
            style = self.kit.paragraph(in_quote=quote_depth > 0, compact=in_scroll)
            return f'<p style="{style}">{self._inlines(inlines, quote_depth, list_depth)}</p>'

        if kind == "list":
            return self._list(node, quote_depth, list_depth, in_scroll)

        if kind == "blockquote":
            body = self._blocks(node["children"], quote_depth + 1, list_depth, in_scroll)
            return f'<section style="{self.kit.blockquote(quote_depth)}">\n{body}\n</section>'

        if kind == "code":
            style = self.kit.code_block()
            inner = ('font-family: inherit; font-size: inherit; '
                     'color: inherit; letter-spacing: 0;')
            return (f'<pre style="{style}"><code style="{inner}">'
                    f'{P.escape_html(node["code"])}</code></pre>')

        if kind == "table":
            return self._table(node, quote_depth, list_depth)

        if kind == "hr":
            return f'<section style="{self.kit.divider()}"></section>'

        if kind == "custom":
            return self._custom(node, quote_depth, list_depth)

        return ""

    def _list(self, node, quote_depth, list_depth, in_scroll) -> str:
        parts: list[str] = []
        for index, item in enumerate(node["items"]):
            number = node["start"] + index if node["ordered"] else 1
            marker = self._marker(node["ordered"], number, list_depth, item.get("checked"))
            style = self.kit.list_item(list_depth)
            inner = f'<span style="{self.kit.list_marker()}">{marker}</span>'
            if item["text"]:
                inlines = P.parse_inlines(item["text"])
                inner += "&nbsp;" + self._inlines(inlines, quote_depth, list_depth)
            parts.append(f'<section style="{style}">{inner}</section>')
            if item["children"]:
                parts.append(self._blocks(item["children"], quote_depth,
                                          list_depth + 1, in_scroll))
        return "\n".join(parts)

    @staticmethod
    def _marker(ordered: bool, number: int, level: int, checked) -> str:
        if checked is not None:
            return "☑" if checked else "☐"
        cycle = level % 3
        if ordered:
            if cycle == 0:
                return f"{number}."
            if cycle == 1:
                return f"{_alpha(number)}."
            return f"{_roman(number)}."
        return ("•", "◦", "▪")[cycle]

    def _custom(self, node, quote_depth, list_depth) -> str:
        tag = node["tag"]
        content = node["content"]

        if tag == "long-text":
            body = self._long_text(content, quote_depth, list_depth)
        elif tag == "long-image":
            body = self._long_image(content, quote_depth, list_depth)
        else:
            body = self._gallery(content, quote_depth, list_depth)

        if not self.t["scrollHintEnabled"] or not body:
            return body
        prefix, label = CUSTOM_HINTS[tag]
        hint = f"{prefix} {label}" if prefix else label
        return f'{body}\n<p style="{self.kit.scroll_hint()}">{hint}</p>'

    def _long_text(self, content, quote_depth, list_depth) -> str:
        if not content.strip():
            return ""
        body = self._blocks(P.parse_blocks(content), quote_depth, list_depth, True)
        return f'<section style="{self.kit.long_text_container()}">\n{body}\n</section>'

    def _long_image(self, content, quote_depth, list_depth) -> str:
        images = P.extract_images(content)
        if not images:
            return self._long_text(content, quote_depth, list_depth)
        alt, url = images[0]
        img = (f'<img src="{P.escape_attr(url)}" alt="{P.escape_attr(alt)}" '
               f'style="{self.kit.long_image()}">')
        return f'<section style="{self.kit.long_image_container()}">{img}</section>'

    def _gallery(self, content, quote_depth, list_depth) -> str:
        images = P.extract_images(content)
        if not images:
            return self._long_text(content, quote_depth, list_depth)
        # img 之间不能有换行或空格，inline-block 元素间的空白会渲染成可见间隙
        parts = [f'<section style="{self.kit.gallery_container()}">']
        for index, (alt, url) in enumerate(images):
            is_last = index == len(images) - 1
            parts.append(f'<img src="{P.escape_attr(url)}" alt="{P.escape_attr(alt)}" '
                         f'style="{self.kit.gallery_image(is_last)}">')
        parts.append("</section>")
        return "".join(parts)

    def _table(self, node, quote_depth, list_depth) -> str:
        def align_at(index: int) -> str:
            return node["aligns"][index] if index < len(node["aligns"]) else "left"

        head = "<thead><tr>"
        for index, cell in enumerate(node["headers"]):
            style = self.kit.table_header_cell(align_at(index))
            head += (f'<th style="{style}">'
                     f'{self._inlines(P.parse_inlines(cell), quote_depth, list_depth)}</th>')
        head += "</tr></thead>"

        body = "<tbody>"
        headers_count = len(node["headers"])
        for row in node["rows"]:
            body += "<tr>"
            for index in range(headers_count):
                cell = row[index] if index < len(row) else ""
                style = self.kit.table_cell(align_at(index))
                body += (f'<td style="{style}">'
                         f'{self._inlines(P.parse_inlines(cell), quote_depth, list_depth)}</td>')
            body += "</tr>"
        body += "</tbody>"

        return (f'<section style="{self.kit.table_wrapper()}">'
                f'<table style="{self.kit.table()}">{head}{body}</table></section>')

    # ── 行内 ──

    def _inlines(self, nodes, quote_depth, list_depth) -> str:
        out: list[str] = []
        for node in nodes:
            kind = node["kind"]
            if kind == "text":
                out.append(P.escape_html(node["text"]))
            elif kind == "strong":
                out.append(f'<strong style="{self.kit.strong()}">'
                           f'{self._inlines(node["text"], quote_depth, list_depth)}</strong>')
            elif kind == "emph":
                out.append(f'<em style="{self.kit.emphasis()}">'
                           f'{self._inlines(node["text"], quote_depth, list_depth)}</em>')
            elif kind == "code":
                out.append(f'<code style="{self.kit.inline_code()}">'
                           f'{P.escape_html(node["text"])}</code>')
            elif kind == "strike":
                out.append(f'<span style="{self.kit.strike()}">'
                           f'{self._inlines(node["text"], quote_depth, list_depth)}</span>')
            elif kind == "link":
                out.append(f'<a href="{P.escape_attr(node["url"])}" '
                           f'style="{self.kit.link()}">'
                           f'{self._inlines(node["text"], quote_depth, list_depth)}</a>')
            elif kind == "image":
                out.append(f'<img src="{P.escape_attr(node["url"])}" '
                           f'alt="{P.escape_attr(node.get("alt", ""))}" '
                           f'style="{self.kit.image()}">')
            elif kind == "br":
                out.append("<br>")
        return "".join(out)


def _alpha(n: int) -> str:
    if n <= 0:
        return "a"
    result = ""
    while n > 0:
        n, rem = divmod(n - 1, 26)
        result = chr(97 + rem) + result
    return result


def _roman(n: int) -> str:
    if n <= 0 or n >= 4000:
        return str(n)
    table = [
        (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"),
        (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
        (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
    ]
    out = ""
    for unit, symbol in table:
        while n >= unit:
            out += symbol
            n -= unit
    return out


# ── 纯文本降级 ────────────────────────────────────────────────────────

def plain_text(markdown: str) -> str:
    """把 Markdown 降级成纯文本，作为剪贴板的 text/plain 回退内容。
    粘贴到不支持富文本的地方时，至少能得到可读的文字。"""
    lines: list[str] = []
    _plain_blocks(P.parse_blocks(markdown), lines, indent=0)
    return "\n\n".join(lines)


def _plain_blocks(nodes, out: list[str], indent: int) -> None:
    pad = " " * indent
    for node in nodes:
        kind = node["kind"]

        if kind == "heading":
            out.append(pad + P._flatten(P.parse_inlines(node["text"])))
            if node["level"] <= 2:
                out.append(pad + "─" * 24)

        elif kind == "paragraph":
            out.append(pad + P._flatten(P.parse_inlines(node["text"])))

        elif kind == "list":
            for index, item in enumerate(node["items"]):
                if node["ordered"]:
                    bullet = f"{node['start'] + index}."
                else:
                    bullet = "•"
                box = {True: "[x] ", False: "[ ] ", None: ""}[item.get("checked")]
                out.append(pad + f"{bullet} {box}"
                           + P._flatten(P.parse_inlines(item["text"])))
                if item["children"]:
                    _plain_blocks(item["children"], out, indent + 2)

        elif kind == "blockquote":
            inner: list[str] = []
            _plain_blocks(node["children"], inner, 0)
            out.append("\n".join(f"{pad}> {line}" for line in inner))

        elif kind == "code":
            out.append("\n".join(f"{pad}    {line}" for line in node["code"].split("\n")))

        elif kind == "table":
            out.append(pad + " | ".join(node["headers"]))
            for row in node["rows"]:
                out.append(pad + " | ".join(row))

        elif kind == "hr":
            out.append(pad + "-" * 40)

        elif kind == "custom":
            if node["tag"] == "long-text":
                _plain_blocks(P.parse_blocks(node["content"]), out, indent)
            else:
                images = P.extract_images(node["content"])
                if not images:
                    out.append(pad + f"[{node['tag']}] " + node["content"])
                for alt, url in images:
                    out.append(pad + f"[{alt or '图片'}] {url}")
