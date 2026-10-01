"""主题规格（theme spec）。

主题是一份 JSON，字段名与 MPStyle（macOS 排版工具）的 ThemeConfig 完全一致，
所以三边可以互通：App 导出的主题能被本 Skill 直接使用，本 Skill 生成的主题
也能被 App 导入；萃取 Skill 输出的也是同一套格式。

设计取舍：只用标准库。这个 Skill 要在任何装了 Python 3 的机器上直接跑，
不该让用户先 pip install 一堆东西。
"""

from __future__ import annotations

import copy
import json
import math
import os

# ── 默认主题 ──────────────────────────────────────────────────────────
# 与 MPStyle 的 ThemeConfig() 默认值保持一致，改这里等于改「出厂排版」。

DEFAULT_FONT_FAMILY = (
    "-apple-system, BlinkMacSystemFont, 'PingFang SC', 'Hiragino Sans GB', "
    "'Microsoft YaHei', 'Helvetica Neue', Arial, sans-serif"
)
DEFAULT_MONO_FAMILY = (
    "SFMono-Regular, Menlo, Consolas, 'Liberation Mono', 'Courier New', monospace"
)

DEFAULT_THEME: dict = {
    # 主题色
    "themeColor": "#1B63F3",
    "textColor": "#333333",
    "secondaryTextColor": "#888888",
    "headingColorMode": "theme",          # theme | dark | custom
    "customHeadingColor": "#1D1D1F",

    # 正文
    "fontFamily": DEFAULT_FONT_FAMILY,
    "monoFamily": DEFAULT_MONO_FAMILY,
    "fontSize": 15,
    "bodyWeight": 100,
    "boldWeight": 500,
    "boldColorMode": "theme",             # theme | inherit | custom
    "customBoldColor": "#1B63F3",
    "lineHeight": 1.8,
    "letterSpacing": 0.1,
    "paragraphSpacing": 1.2,
    "textAlignJustify": True,

    # 标题
    "h1Scale": 1.60,
    "h2Scale": 1.333,
    "h3Scale": 1.13,
    "h4Scale": 1.00,
    "headingWeight": 600,
    "h1Top": 1.9,
    "h1Bottom": 1.0,
    "h2Top": 1.8,
    "h2Bottom": 1.0,
    "h2LineHeight": 1.60,
    "h3Top": 1.5,
    "h3Bottom": 0.7,
    "h3LineHeight": 1.45,

    # 列表
    "listIndent": 1.2,
    "listItemSpacing": 0.35,
    "listLineHeight": 1.70,
    "listMarkerWeight": 500,

    # 图片
    "imageRadius": 8,
    "imageShadow": True,
    "imageSpacing": 1.5,

    # 引用
    "quoteBarWidth": 3,
    "quoteRadius": 8,
    "quoteBgTint": 0.07,
    "quoteTextColor": "#555555",

    # 代码
    "codeBg": "#F7F8FA",
    "codeRadius": 8,
    "codeScale": 0.88,

    # 滚动块
    "longTextMaxHeight": 320,
    "longTextBg": "#F7F9FC",
    "longTextRadius": 8,
    "longTextPadding": 0.9,
    "longImageMaxHeight": 450,
    "longImageRadius": 8,
    "galleryImageWidth": 72,
    "galleryGap": 12,
    "galleryRadius": 8,
    "scrollHintEnabled": True,

    # 外框卡片
    "cardEnabled": True,
    "cardColor": "#F9F8F4",
    "cardRadius": 24,

    # 预览
    "previewWidth": 375,
}

# 主题规格里允许出现的键。多出来的键会被忽略并在 load 时提示，
# 用来兜住「手写 JSON 打错字段名」这类问题。
KNOWN_KEYS = set(DEFAULT_THEME)

# 主题目录：除内置 default.json 外，用户丢进来的任何 *.json 都能按名字引用
SKILL_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEME_DIRS = [
    os.path.join(SKILL_ROOT, "themes"),
    os.path.join(os.path.expanduser("~"), ".mp-wechat", "themes"),
]


def theme_search_paths() -> list[str]:
    return THEME_DIRS


def list_themes() -> list[dict]:
    """列出所有可用主题：{name, path, source}"""
    found: dict[str, dict] = {}
    for directory in THEME_DIRS:
        if not os.path.isdir(directory):
            continue
        for filename in sorted(os.listdir(directory)):
            if not filename.endswith(".json"):
                continue
            name = filename[:-5]
            path = os.path.join(directory, filename)
            found[name] = {"name": name, "path": path, "source": directory}
    return list(found.values())


def find_theme(name: str) -> str | None:
    """按名字找主题文件。也接受直接给路径。"""
    if os.path.isfile(name):
        return name
    for directory in THEME_DIRS:
        candidate = os.path.join(directory, f"{name}.json")
        if os.path.isfile(candidate):
            return candidate
    return None


def load(name: str | None = None) -> dict:
    """读取主题。name 为空时返回内置默认主题。

    支持三种写法：
      - None / "default"      → 内置默认
      - "小绿书"               → themes/小绿书.json
      - "/path/to/theme.json" → 直接指定文件
    """
    if not name or name == "default":
        path = find_theme("default")
        if path is None:
            return copy.deepcopy(DEFAULT_THEME)
        name = path

    path = find_theme(name)
    if path is None:
        raise FileNotFoundError(
            f"找不到主题 {name!r}。可用主题：" +
            ", ".join(t["name"] for t in list_themes()) or "(无)"
        )

    with open(path, encoding="utf-8") as handle:
        raw = json.load(handle)

    # 支持两种写法：直接就是主题对象，或者包一层 {"name": ..., "theme": {...}}
    if "theme" in raw and isinstance(raw["theme"], dict):
        raw = raw["theme"]

    return normalize(raw)


def _coerce(default, value):
    """把外部值对齐到默认值的类型。对不上返回 None 表示丢弃。

    数值之间必须互相兼容：默认值写的是 int（比如 cardRadius: 24），
    但 JSON 里 0 也可能被解析成 float（0.0）。若按 `type(x) == type(y)` 严格比较，
    这类字段会被静默丢掉，改了半天主题发现没生效，还找不到原因。

    bool 要单独挡住 —— Python 里 bool 是 int 的子类，不挡的话 True 会被当成 1。
    """
    if isinstance(value, bool):
        # 默认是数值字段时，JSON 里的 true 不该被当成 1 混进去
        return value if isinstance(default, bool) else None
    if isinstance(default, bool):
        return None
    if isinstance(default, (int, float)) and isinstance(value, (int, float)):
        return type(default)(value)
    if isinstance(value, type(default)):
        return value
    return None


def normalize(raw: dict) -> dict:
    """把外部主题对齐到完整字段集：缺的补默认，类型不对的丢弃。"""
    theme = copy.deepcopy(DEFAULT_THEME)
    for key, value in raw.items():
        if key not in KNOWN_KEYS:
            continue
        coerced = _coerce(DEFAULT_THEME[key], value)
        if coerced is not None:
            theme[key] = coerced
    return theme


def save(theme: dict, path: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(theme, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


# ── 派生值 ────────────────────────────────────────────────────────────

def px_round(value: float) -> float:
    """取整到 0.5px，和 App 的 ThemeConfig.px 保持一致。
    Swift 的 .rounded() 是「四舍五入、远离零」，Python 的 round() 是银行家舍入，
    所以这里显式用 floor(x + 0.5)。"""
    return math.floor(value * 2 + 0.5) / 2


def css_px(value: float) -> str:
    r = math.floor(value * 100 + 0.5) / 100
    return f"{int(r)}px" if r == int(r) else f"{r}px"


def css_em(value: float) -> str:
    r = math.floor(value * 1000 + 0.5) / 1000
    return f"{int(r)}em" if r == int(r) else f"{r}em"


def css_percent(value: float) -> str:
    r = math.floor(value * 100 + 0.5) / 100
    return f"{int(r)}%" if r == int(r) else f"{r}%"


def normalize_color(value: str) -> str:
    """把颜色规整成 #RRGGBB。失败时给出中性灰而不是抛异常 —— 排版工具不该因为
    一个颜色写错就整篇渲染不出来。"""
    text = (value or "").strip()
    if text.startswith("#"):
        text = text[1:]
    if len(text) == 3 and all(c in "0123456789abcdefABCDEF" for c in text):
        return "#" + "".join(c * 2 for c in text).upper()
    if len(text) == 6 and all(c in "0123456789abcdefABCDEF" for c in text):
        return "#" + text.upper()
    return "#333333"


def _channels(color: str) -> tuple[int, int, int]:
    text = normalize_color(color)[1:]
    return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)


def fade(color: str, to: float) -> str:
    """把颜色按比例混向白色。to=0 保持原色，to=1 变纯白。"""
    ratio = min(max(to, 0.0), 1.0)
    r, g, b = _channels(color)
    mix = lambda c: int(round(c + (255 - c) * ratio))
    return "#{:02X}{:02X}{:02X}".format(mix(r), mix(g), mix(b))


def rgba(color: str, alpha: float) -> str:
    r, g, b = _channels(color)
    a = min(max(alpha, 0.0), 1.0)
    text = f"{a:g}"
    return f"rgba({r}, {g}, {b}, {text})"


def effective_heading_color(theme: dict) -> str:
    mode = theme.get("headingColorMode", "theme")
    if mode == "dark":
        return "#1D1D1F"
    if mode == "custom":
        return theme.get("customHeadingColor", "#1D1D1F")
    return theme.get("themeColor", "#1B63F3")


def effective_bold_color(theme: dict) -> str:
    mode = theme.get("boldColorMode", "theme")
    if mode == "inherit":
        return theme.get("textColor", "#333333")
    if mode == "custom":
        return theme.get("customBoldColor", "#1B63F3")
    return theme.get("themeColor", "#1B63F3")
