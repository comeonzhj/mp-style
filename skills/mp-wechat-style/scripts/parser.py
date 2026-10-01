"""Markdown 解析。

块级 AST 用 dict 表示，kind 取值：
    heading / paragraph / list / blockquote / code / table / hr / custom

行内 AST 同样是 dict，kind 取值：
    text / strong / emph / code / strike / link / image / br

实现取舍：只覆盖公众号场景真正用得上的语法，不做完整 CommonMark 兼容。
行为上刻意对齐 MPStyle 的排版工具，保证两边产出同一套样式：
  - 软换行：中英文之间按需补空格，避免出现「中文 中文」这种突兀间隙
  - 列表序号、勾选框都是真实文本节点（公众号不支持 ::before）
  - 缩进用 text-indent 负值做悬挂，折行才能对齐
"""

from __future__ import annotations

import re

# ── 正则 ──────────────────────────────────────────────────────────────

RE_HEADING = re.compile(r"^ {0,3}(#{1,6})(?:\s+(.*?))?\s*#*\s*$")
RE_FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})\s*([\w+#-]*)\s*$")
RE_HR = re.compile(r"^ {0,3}(?:(?:\*\s*){3,}|(?:-\s*){3,}|(?:_\s*){3,})$")
RE_QUOTE = re.compile(r"^ {0,3}>\s?(.*)$")
RE_LIST = re.compile(r"^(\s*)([-*+]|\d{1,9}[.)])(\s+)(.*)$")
RE_TASK = re.compile(r"^\[([ xX])\]\s+(.*)$")
RE_TABLE_DELIM = re.compile(r"^\s*\|?\s*:?-{1,}:?\s*(?:\|\s*:?-{1,}:?\s*)*\|?\s*$")
RE_CUSTOM_OPEN = re.compile(r"^\s*<(long-text|long-image|more-images)>\s*$")
RE_CUSTOM_CLOSE = re.compile(r"^\s*</(long-text|long-image|more-images)>\s*$")
RE_CUSTOM_INLINE = re.compile(
    r"^\s*<(long-text|long-image|more-images)>(.*?)</\1>\s*$", re.DOTALL
)
RE_HTML_IMG = re.compile(r"""<img[^>]*?src=["']([^"']+)["'][^>]*>""", re.IGNORECASE)

CJK_RANGES = (
    (0x2E80, 0x2EFF), (0x3000, 0x303F), (0x3040, 0x30FF), (0x3100, 0x312F),
    (0x31C0, 0x31EF), (0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF),
    (0xFE30, 0xFE4F), (0xFF00, 0xFFEF),
)


def is_cjk(ch: str) -> bool:
    if not ch:
        return False
    code = ord(ch)
    return any(low <= code <= high for low, high in CJK_RANGES)


def is_blank(line: str) -> bool:
    return not line.strip()


# ── 块级解析 ──────────────────────────────────────────────────────────

def parse_blocks(text: str) -> list[dict]:
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    nodes, _ = _parse_range(lines, 0, len(lines))
    return nodes


def _parse_range(lines: list[str], start: int, end: int) -> tuple[list[dict], int]:
    nodes: list[dict] = []
    i = start
    while i < end:
        line = lines[i]
        if is_blank(line):
            i += 1
            continue

        # 定制滚动块。放在最前面判断，避免标签被别的规则吞掉。
        inline = RE_CUSTOM_INLINE.match(line)
        if inline:
            nodes.append({"kind": "custom", "tag": inline.group(1),
                          "content": inline.group(2).strip()})
            i += 1
            continue
        opening = RE_CUSTOM_OPEN.match(line)
        if opening:
            node, i = _parse_custom(lines, i, end, opening.group(1))
            nodes.append(node)
            continue

        fence = RE_FENCE.match(line)
        if fence:
            node, i = _parse_code(lines, i, end, fence)
            nodes.append(node)
            continue

        heading = RE_HEADING.match(line)
        if heading:
            nodes.append({"kind": "heading",
                          "level": len(heading.group(1)),
                          "text": (heading.group(2) or "").strip()})
            i += 1
            continue

        if RE_HR.match(line):
            nodes.append({"kind": "hr"})
            i += 1
            continue

        if RE_QUOTE.match(line):
            node, i = _parse_quote(lines, i, end)
            nodes.append(node)
            continue

        if RE_LIST.match(line):
            node, i = _parse_list(lines, i, end)
            nodes.append(node)
            continue

        if _looks_like_table(lines, i, end):
            node, i = _parse_table(lines, i, end)
            nodes.append(node)
            continue

        node, i = _parse_paragraph(lines, i, end)
        nodes.append(node)

    return nodes, i


def _parse_custom(lines, i, end, tag):
    i += 1
    body: list[str] = []
    while i < end:
        close = RE_CUSTOM_CLOSE.match(lines[i])
        if close and close.group(1) == tag:
            i += 1
            break
        body.append(lines[i])
        i += 1
    while body and is_blank(body[0]):
        body.pop(0)
    while body and is_blank(body[-1]):
        body.pop()
    return {"kind": "custom", "tag": tag, "content": "\n".join(body)}, i


def _parse_code(lines, i, end, fence):
    marker, lang = fence.group(1), fence.group(2)
    char, length = marker[0], len(marker)
    i += 1
    body: list[str] = []
    while i < end:
        line = lines[i]
        if re.match(rf"^ {{0,3}}{re.escape(char)}{{{length},}}\s*$", line):
            i += 1
            break
        body.append(line)
        i += 1
    return {"kind": "code", "code": "\n".join(body), "lang": lang or None}, i


def _parse_quote(lines, i, end):
    body: list[str] = []
    while i < end:
        match = RE_QUOTE.match(lines[i])
        if match:
            body.append(match.group(1))
            i += 1
        elif is_blank(lines[i]):
            # 引用块内的空行：后面还有 > 就继续，否则结束
            if i + 1 < end and RE_QUOTE.match(lines[i + 1]):
                body.append("")
                i += 1
            else:
                break
        else:
            break
    children, _ = _parse_range(body, 0, len(body))
    return {"kind": "blockquote", "children": children}, i


def _parse_list(lines, i, end):
    first = RE_LIST.match(lines[i])
    ordered = first.group(2)[0].isdigit()
    start = int(re.match(r"\d+", first.group(2)).group()) if ordered else 1
    base_indent = len(first.group(1).expandtabs(4))

    items: list[dict] = []
    while i < end:
        match = RE_LIST.match(lines[i])
        if not match:
            break
        indent = len(match.group(1).expandtabs(4))
        if indent != base_indent:
            break
        same_kind = match.group(2)[0].isdigit() == ordered
        if not same_kind:
            break

        content_indent = indent + len(match.group(2)) + len(match.group(3))
        head = match.group(4)
        checked = None
        task = RE_TASK.match(head)
        if task:
            checked = task.group(1).lower() == "x"
            head = task.group(2)

        i += 1
        # 收集本项自己的后续行：缩进超过标记宽度的都算，
        # 空行先记着，后面没有同项内容就丢弃
        continuation: list[str] = []
        pending_blanks: list[str] = []
        while i < end:
            line = lines[i]
            if is_blank(line):
                pending_blanks.append("")
                i += 1
                continue
            line_indent = len(line) - len(line.lstrip())
            if line_indent >= content_indent:
                continuation.extend(pending_blanks)
                pending_blanks = []
                continuation.append(line[content_indent:])
                i += 1
                continue
            # 同级的下一个列表项
            nxt = RE_LIST.match(line)
            if nxt and len(nxt.group(1).expandtabs(4)) == base_indent \
                    and nxt.group(2)[0].isdigit() == ordered:
                break
            break

        children: list[dict] = []
        if continuation:
            children, _ = _parse_range(continuation, 0, len(continuation))
            # 首块是段落且缩进层级相同 → 并进本项的正文
            if children and children[0]["kind"] == "paragraph" and not head:
                head = children.pop(0)["text"]

        items.append({"text": head, "checked": checked, "children": children})

    return {"kind": "list", "ordered": ordered, "start": start, "items": items}, i


def _split_row(line: str) -> list[str]:
    text = line.strip()
    if text.startswith("|"):
        text = text[1:]
    if text.endswith("|"):
        text = text[:-1]
    return [cell.strip() for cell in text.split("|")]


def _looks_like_table(lines, i, end) -> bool:
    if i + 1 >= end:
        return False
    if "|" not in lines[i]:
        return False
    if not RE_TABLE_DELIM.match(lines[i + 1]):
        return False
    # 分隔行必须真的是分隔行，不能只是恰好像
    return "-" in lines[i + 1]


def _parse_table(lines, i, end):
    headers = _split_row(lines[i])
    aligns: list[str] = []
    for cell in _split_row(lines[i + 1]):
        left, right = cell.startswith(":"), cell.endswith(":")
        if left and right:
            aligns.append("center")
        elif right:
            aligns.append("right")
        else:
            aligns.append("left")
    i += 2
    rows: list[list[str]] = []
    while i < end and not is_blank(lines[i]) and "|" in lines[i]:
        rows.append(_split_row(lines[i]))
        i += 1
    return {"kind": "table", "headers": headers, "aligns": aligns, "rows": rows}, i


def _interrupts(line: str) -> bool:
    if is_blank(line):
        return True
    return bool(RE_HEADING.match(line) or RE_FENCE.match(line) or RE_HR.match(line)
                or RE_QUOTE.match(line) or RE_LIST.match(line)
                or RE_CUSTOM_OPEN.match(line) or RE_CUSTOM_INLINE.match(line))


def _parse_paragraph(lines, i, end):
    body = [lines[i].strip()]
    i += 1
    while i < end and not _interrupts(lines[i]):
        body.append(lines[i].strip())
        i += 1
    return {"kind": "paragraph", "text": "\n".join(body)}, i


# ── 行内解析 ──────────────────────────────────────────────────────────

ESCAPABLE = set(r"\`*_{}[]()#+-.!~>|")
RE_AUTOLINK = re.compile(r"^<((?:https?|mailto):[^>\s]+)>", re.IGNORECASE)
RE_BARE_URL = re.compile(r"^(https?://[^\s<>\"'）】」》]+|www\.[^\s<>\"'）】」》]+)", re.IGNORECASE)
TRAILING_PUNCT = "。，、；：！？）》」』】”’.,;:!?)>"


def parse_inlines(text: str) -> list[dict]:
    nodes: list[dict] = []
    buffer: list[str] = []

    def flush():
        if buffer:
            nodes.append({"kind": "text", "text": "".join(buffer)})
            buffer.clear()

    i, n = 0, len(text)
    while i < n:
        ch = text[i]

        # 反斜杠转义
        if ch == "\\" and i + 1 < n and text[i + 1] in ESCAPABLE:
            buffer.append(text[i + 1])
            i += 2
            continue
        # 硬换行：行尾两空格 + 换行，或反斜杠 + 换行
        if ch == "\\" and i + 1 < n and text[i + 1] == "\n":
            flush()
            nodes.append({"kind": "br"})
            i += 2
            continue
        if ch == "\n":
            if buffer and "".join(buffer).endswith("  "):
                # 去掉行尾的空格
                joined = "".join(buffer).rstrip(" ")
                buffer.clear()
                if joined:
                    buffer.append(joined)
                flush()
                nodes.append({"kind": "br"})
            else:
                if buffer:
                    tail = "".join(buffer)[-1:]
                    nxt = text[i + 1] if i + 1 < n else ""
                    if not (is_cjk(tail) and is_cjk(nxt)):
                        buffer.append(" ")
                flush()
            i += 1
            continue

        # 代码段
        if ch == "`":
            # 反引号串长度必须只从 text[i:] 里算。用 len(text) 去减会把 i 也算进去，
            # 导致非行首的代码段匹配不到闭合反引号、整段退化成普通文本。
            run = len(text[i:]) - len(text[i:].lstrip("`"))
            closer = text.find("`" * run, i + run)
            if closer != -1:
                code = text[i + run:closer].strip()
                flush()
                nodes.append({"kind": "code", "text": code})
                i = closer + run
                continue

        # 图片
        if ch == "!" and i + 1 < n and text[i + 1] == "[":
            parsed = _parse_link_like(text, i + 1)
            if parsed:
                label, url, consumed = parsed
                flush()
                nodes.append({"kind": "image", "alt": _flatten(parse_inlines(label)), "url": url})
                i = consumed
                continue

        # 链接
        if ch == "[":
            parsed = _parse_link_like(text, i)
            if parsed:
                label, url, consumed = parsed
                flush()
                nodes.append({"kind": "link", "text": parse_inlines(label), "url": url})
                i = consumed
                continue

        # 自动链接
        if ch == "<":
            match = RE_AUTOLINK.match(text[i:])
            if match:
                url = match.group(1)
                flush()
                nodes.append({"kind": "link",
                              "text": [{"kind": "text", "text": url}],
                              "url": url})
                i += match.end()
                continue

        # 删除线
        if text.startswith("~~", i):
            end = text.find("~~", i + 2)
            if end > i + 2:
                flush()
                nodes.append({"kind": "strike",
                              "text": parse_inlines(text[i + 2:end])})
                i = end + 2
                continue

        # 粗斜体必须在加粗之前判断：`***x***` 若先命中 `**`，
        # 会在第 2 个字符处开始找闭合、把 `*x` 当成内容。
        if text.startswith("***", i) or text.startswith("___", i):
            delim = text[i:i + 3]
            end = text.find(delim, i + 3)
            if end > i + 3:
                flush()
                inner = parse_inlines(text[i + 3:end])
                nodes.append({"kind": "strong", "text": [{"kind": "emph", "text": inner}]})
                i = end + 3
                continue

        # 加粗
        if text.startswith("**", i) or text.startswith("__", i):
            delim = text[i:i + 2]
            end = text.find(delim, i + 2)
            if end > i + 2:
                flush()
                nodes.append({"kind": "strong",
                              "text": parse_inlines(text[i + 2:end])})
                i = end + 2
                continue

        # 斜体
        if ch in "*_":
            end = text.find(ch, i + 1)
            if end > i + 1 and not text.startswith(ch * 2, i):
                flush()
                nodes.append({"kind": "emph", "text": parse_inlines(text[i + 1:end])})
                i = end + 1
                continue

        # 裸链接
        match = RE_BARE_URL.match(text[i:])
        if match:
            url = match.group(1)
            while url and url[-1] in TRAILING_PUNCT:
                url = url[:-1]
            if url:
                flush()
                href = url if url.lower().startswith("http") else f"http://{url}"
                nodes.append({"kind": "link",
                              "text": [{"kind": "text", "text": url}],
                              "url": href})
                i += len(url)
                continue

        buffer.append(ch)
        i += 1

    flush()
    return nodes


def _parse_link_like(text: str, open_index: int):
    """解析 `[label](url)`。open_index 指向 `[`。返回 (label, url, 新位置)。"""
    depth, i = 0, open_index
    while i < len(text):
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if depth == 0:
                break
        i += 1
    if i >= len(text) or text[i] != "]":
        return None

    label = text[open_index + 1:i]
    if i + 1 >= len(text) or text[i + 1] != "(":
        return None

    j, paren = i + 2, 1
    while j < len(text):
        if text[j] == "(":
            paren += 1
        elif text[j] == ")":
            paren -= 1
            if paren == 0:
                break
        j += 1
    if j >= len(text):
        return None

    target = text[i + 2:j].strip()
    # 去掉可选的 title
    match = re.match(r'^(\S+?)(?:\s+["\'].*["\'])?$', target)
    url = match.group(1) if match else target
    return label, url, j + 1


def _flatten(nodes: list[dict]) -> str:
    out = []
    for node in nodes:
        if node["kind"] == "text":
            out.append(node["text"])
        elif node["kind"] in ("strong", "emph", "strike", "link"):
            out.append(_flatten(node["text"]))
        elif node["kind"] == "code":
            out.append(node["text"])
        elif node["kind"] == "image":
            out.append(node.get("alt", ""))
        elif node["kind"] == "br":
            out.append("\n")
    return "".join(out)


# ── 转义 ──────────────────────────────────────────────────────────────

def escape_html(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def escape_attr(text: str) -> str:
    return escape_html(text).replace('"', "&quot;").replace("'", "&#39;")


def extract_images(content: str) -> list[tuple[str, str]]:
    """从滚动块内容里提取图片，返回 [(alt, url)]。

    支持三种写法：`![alt](url)`、`<img src="url">`、一行一个裸 URL。
    """
    result: list[tuple[str, str]] = []
    for raw_line in content.split("\n"):
        line = raw_line.strip()
        if not line:
            continue

        found = False
        for node in parse_inlines(line):
            if node["kind"] == "image":
                result.append((node.get("alt", ""), node["url"]))
                found = True
        if found:
            continue

        match = RE_HTML_IMG.search(line)
        if match:
            result.append(("", match.group(1)))
            continue

        if line.startswith("http://") or line.startswith("https://"):
            result.append(("", line))

    return result


def first_heading(markdown: str) -> str:
    """取正文第一个标题的纯文本，用作发布时的默认标题。"""
    for node in parse_blocks(markdown):
        if node["kind"] == "heading":
            text = _flatten(parse_inlines(node["text"])).strip()
            if text:
                return text
    for node in parse_blocks(markdown):
        if node["kind"] == "paragraph":
            text = _flatten(parse_inlines(node["text"])).strip()
            if text:
                return text[:60]
    return "未命名文章"
