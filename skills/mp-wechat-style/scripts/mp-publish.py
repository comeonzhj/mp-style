#!/usr/bin/env python3
"""把排版结果发布到微信公众号草稿箱。

只依赖标准库。走的是公众号开放接口：
    1. cgi-bin/token               获取 access_token
    2. cgi-bin/media/uploadimg     把正文外链图片换到公众号图床
    3. cgi-bin/material/add_material  上传封面（草稿必须有封面）
    4. cgi-bin/draft/add           写入草稿箱

凭据来源，按优先级：
    --app-id/--app-secret  →  环境变量 MP_APP_ID/MP_APP_SECRET  →  .env 文件

用法:
    mp-publish.py <文章.md> --cover 封面.jpg [--title 标题] [--theme 名字]

⚠️ 公众号后台必须把本机公网 IP 加进「IP 白名单」，否则接口一律拒绝。
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import parser as P                        # noqa: E402
import theme as theme_mod                 # noqa: E402
from renderer import Renderer             # noqa: E402

BASE = "https://api.weixin.qq.com"
TIMEOUT = 60

# errcode → (给用户看的说明, 怎么办)
ERROR_HINTS = {
    40001: ("AppSecret 不正确",
            "去「公众号后台 → 设置与开发 → 基本配置」重新复制 AppSecret。"
            "AppSecret 只在生成时显示一次，忘了就重置。"),
    40125: ("AppSecret 不正确",
            "去「公众号后台 → 设置与开发 → 基本配置」重新复制 AppSecret。"),
    40164: ("当前网络 IP 不在公众号白名单内",
            "去「公众号后台 → 设置与开发 → 基本配置 → IP 白名单」把 {ip} 加进去。"
            "动态 IP 每次变更都要重新添加；用服务器发布的话填服务器的固定 IP。"),
    48001: ("该账号没有草稿箱接口权限",
            "草稿箱接口需要已认证的公众号。未认证的订阅号没有这个权限，"
            "只能改用 mp-copy.py 复制后手动粘贴。"),
    45009: ("接口调用超过当日限额", "等第二天额度重置，或在后台确认接口调用量。"),
    53500: ("草稿数量已达上限", "先去后台草稿箱删几篇。"),
    40007: ("素材 ID 不合法", "封面图可能上传失败，重新跑一次。"),
}


class APIError(Exception):
    def __init__(self, code: int, message: str):
        self.code = code
        self.message = message
        super().__init__(self.render())

    def render(self) -> str:
        hint = ERROR_HINTS.get(self.code)
        if hint:
            title, action = hint
            action = action.replace("{ip}", _guess_ip(self.message) or "你的公网 IP")
            return f"{title}（errcode {self.code}）\n  → {action}"
        if self.message:
            return f"微信接口错误（errcode {self.code}）：{self.message}"
        return f"微信接口错误（errcode {self.code}）"


def _guess_ip(message: str) -> str | None:
    """微信会在 errmsg 里带上调用方 IP，抓出来直接给用户抄。"""
    for token in message.replace(",", " ").replace(":", " ").split():
        parts = token.split(".")
        if len(parts) == 4 and all(p.isdigit() and 0 <= int(p) <= 255 for p in parts):
            return token
    return None


# ── HTTP ──────────────────────────────────────────────────────────────

def _decode(raw: bytes) -> dict:
    try:
        data = json.loads(raw.decode("utf-8"))
    except Exception:
        raise APIError(-1, f"响应不是合法 JSON：{raw[:200]!r}")
    if isinstance(data, dict) and data.get("errcode"):
        raise APIError(int(data["errcode"]), str(data.get("errmsg", "")))
    return data


def http_get(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=TIMEOUT) as resp:
        return _decode(resp.read())


def http_post_json(url: str, payload: dict) -> dict:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url, data=body, method="POST",
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT) as resp:
        return _decode(resp.read())


def http_post_file(url: str, field: str, data: bytes, filename: str) -> dict:
    boundary = "----mpstyle" + uuid.uuid4().hex
    content_type = mimetypes.guess_type(filename)[0] or "image/jpeg"
    body = b"".join([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'.encode(),
        f"Content-Type: {content_type}\r\n\r\n".encode(),
        data,
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    request = urllib.request.Request(
        url, data=body, method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT) as resp:
        return _decode(resp.read())


# ── 封面兜底 ──────────────────────────────────────────────────────────

def make_solid_png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """没提供封面时现场生成一张纯色图。

    草稿接口强制要求封面，给一张能过的图总比直接失败好。
    想要好看的封面就自己传 --cover。
    """
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    row = b"\x00" + bytes(rgb) * width
    raw = row * height
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


# ── 凭据 ──────────────────────────────────────────────────────────────

QUOTES = [("'", "'"), ('"', '"'), ("\u2018", "\u2019"), ("\u201c", "\u201d")]


def read_env_file(path: str) -> dict:
    """读 .env。值可能被单引号 / 双引号 / 智能引号包起来，统一去壳 ——
    引号没剥干净会让 AppID 多出两个字符，接口直接报 invalid appid。"""
    values: dict[str, str] = {}
    if not os.path.isfile(path):
        return values
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            value = value.strip()
            for open_q, close_q in QUOTES:
                if len(value) >= 2 and value.startswith(open_q) and value.endswith(close_q):
                    value = value[1:-1].strip()
                    break
            values[key.strip()] = value
    return values


def resolve_credentials(args) -> tuple[str, str]:
    env_file = read_env_file(args.env)
    app_id = (args.app_id or os.environ.get("MP_APP_ID")
              or env_file.get("AppID") or env_file.get("MP_APP_ID") or "")
    secret = (args.app_secret or os.environ.get("MP_APP_SECRET")
              or env_file.get("AppSecret") or env_file.get("MP_APP_SECRET") or "")
    return app_id.strip(), secret.strip()


# ── 主流程 ────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description="发布 Markdown 到公众号草稿箱")
    ap.add_argument("input", help="Markdown 文件路径")
    ap.add_argument("--theme", default=None, help="主题名或主题 JSON 路径")
    ap.add_argument("--cover", default=None, help="封面图路径（建议 900×383）")
    ap.add_argument("--title", default=None, help="标题，留空取正文第一个标题")
    ap.add_argument("--author", default="", help="作者")
    ap.add_argument("--digest", default="", help="摘要，留空由微信自动截取")
    ap.add_argument("--source-url", default="", help="阅读原文链接")
    ap.add_argument("--app-id", default=None, help="公众号 AppID")
    ap.add_argument("--app-secret", default=None, help="公众号 AppSecret")
    ap.add_argument("--env", default=".env", help="凭据文件路径，默认 ./.env")
    ap.add_argument("--no-localize", action="store_true",
                    help="跳过外链图片本地化（草稿发布后图片可能裂）")
    ap.add_argument("--dry-run", action="store_true",
                    help="只跑到上传图片为止，不创建草稿")
    args = ap.parse_args()

    markdown = open(args.input, encoding="utf-8").read()
    app_id, secret = resolve_credentials(args)

    if not app_id or not secret:
        print("✗ 拿不到 AppID / AppSecret。", file=sys.stderr)
        print("  用 --app-id/--app-secret，或设 MP_APP_ID/MP_APP_SECRET 环境变量，"
              "或准备一份 .env（键名 AppID / AppSecret）。", file=sys.stderr)
        return 1

    renderer = Renderer(theme_mod.load(args.theme))
    content = renderer.render(markdown)
    title = args.title or P.first_heading(markdown)

    print(f"标题    : {title}")
    print(f"正文字符: {len(content)}")
    print()

    try:
        print("① 获取 access_token")
        token = http_get(
            f"{BASE}/cgi-bin/token?grant_type=client_credential"
            f"&appid={urllib.parse.quote(app_id)}&secret={urllib.parse.quote(secret)}"
        )["access_token"]
        print("   ✓ 鉴权通过")

        if not args.no_localize:
            content = localize_images(content, token)
        else:
            print("② 跳过图片本地化")

        print("③ 上传封面")
        cover_data, cover_name = load_cover(args, renderer)
        media_id = http_post_file(
            f"{BASE}/cgi-bin/material/add_material?access_token={token}&type=image",
            "media", cover_data, cover_name,
        )["media_id"]
        print(f"   ✓ media_id {media_id}")

        if args.dry_run:
            print()
            print("--dry-run：到此为止，未创建草稿。")
            return 0

        print("④ 写入草稿箱")
        article = {
            "title": title,
            "content": content,
            "thumb_media_id": media_id,
            "need_open_comment": 0,
            "only_fans_can_comment": 0,
        }
        for key, value in (("author", args.author), ("digest", args.digest),
                           ("content_source_url", args.source_url)):
            if value:
                article[key] = value

        draft_id = http_post_json(
            f"{BASE}/cgi-bin/draft/add?access_token={token}",
            {"articles": [article]},
        )["media_id"]

        print()
        print("═══════════════════════════════════════")
        print("  草稿创建成功")
        print(f"  media_id : {draft_id}")
        print("  去「公众号后台 → 内容与互动 → 草稿箱」查看")
        print("═══════════════════════════════════════")
        return 0

    except APIError as error:
        print()
        print(f"✗ {error}", file=sys.stderr)
        return 1
    except urllib.error.URLError as error:
        print()
        print(f"✗ 网络错误：{error.reason}", file=sys.stderr)
        return 1


def load_cover(args, renderer: Renderer) -> tuple[bytes, str]:
    if args.cover:
        with open(args.cover, "rb") as handle:
            return handle.read(), os.path.basename(args.cover)
    rgb = _hex_to_rgb(theme_mod.effective_heading_color(renderer.t))
    print("   ! 未提供 --cover，生成一张纯色封面兜底")
    return make_solid_png(900, 383, rgb), "cover.png"


def _hex_to_rgb(color: str) -> tuple[int, int, int]:
    text = theme_mod.normalize_color(color)[1:]
    return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)


def localize_images(content: str, token: str) -> str:
    """把正文里的外链图片下载后传到公众号图床，替换成 mmbiz 地址。

    公众号对外站图片有防盗链，直接引用外链的草稿发布后会变成裂图。
    """
    found = re.findall(r'<img\b[^>]*?\bsrc="([^"]+)"', content, re.IGNORECASE)

    seen, ordered = set(), []
    for src in found:
        if src.startswith("data:") or src in seen:
            continue
        seen.add(src)
        ordered.append(src)

    if not ordered:
        print("② 正文里没有图片")
        return content

    print(f"② 本地化 {len(ordered)} 张正文图片")
    mapping: dict[str, str] = {}
    for index, src in enumerate(ordered, 1):
        if "mmbiz.qpic.cn" in src or "mmbiz.qlogo.cn" in src:
            print(f"   [{index}/{len(ordered)}] 已在公众号图床，跳过")
            continue
        try:
            url = "https:" + src if src.startswith("//") else src
            request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(request, timeout=TIMEOUT) as resp:
                data = resp.read()
            if len(data) >= 1024 * 1024:
                print(f"   [{index}/{len(ordered)}] 超过 1MB，微信会拒绝，跳过")
                continue
            name = os.path.basename(urllib.parse.urlparse(url).path) or "image.jpg"
            uploaded = http_post_file(
                f"{BASE}/cgi-bin/media/uploadimg?access_token={token}",
                "media", data, name,
            )["url"]
            mapping[src] = uploaded
            print(f"   [{index}/{len(ordered)}] ✓")
        except Exception as error:                      # 单张失败不该中断整篇
            print(f"   [{index}/{len(ordered)}] 失败：{error}")

    for old, new in sorted(mapping.items(), key=lambda kv: -len(kv[0])):
        content = content.replace(f'src="{old}"', f'src="{new}"')
    return content


if __name__ == "__main__":
    sys.exit(main())
