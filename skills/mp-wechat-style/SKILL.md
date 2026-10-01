---
name: mp-wechat-style
version: 1.0.0
description: 把 Markdown 文章排版成微信公众号富文本。生成预览页供确认视觉效果，一键复制到剪贴板供粘贴，或直接发布到公众号草稿箱。支持通过主题 JSON 自定义视觉风格，主题可与 mp-wechat-extract 萃取的结果互通。当用户要给公众号排版文章、需要 Markdown 转公众号格式、要预览排版效果、要复制到公众号、要发布到草稿箱、要自定义公众号排版主题时使用。
---

# 公众号排版

把 Markdown 排成公众号能直接用的富文本。全程只用 Python 标准库，不依赖任何外部服务。

## 为什么需要专门排版

公众号编辑器会丢弃 `<style>` 标签和 class，只保留**内联样式**。所以直接把 Markdown
渲染成 HTML 粘进去会丢光样式。这个 Skill 输出的每一处 CSS 都写在 `style` 属性里，
粘进去样式是完整的。

另外公众号不支持 `::before` 伪元素，所以列表序号、任务勾选框都输出成真实文本节点；
列表缩进用 `text-indent` 负值做悬挂，折行才能对齐。

## 三个能力

| 脚本 | 作用 |
|---|---|
| `scripts/mp-render.py` | Markdown → HTML（片段或完整预览页） |
| `scripts/mp-preview.py` | 生成预览页并在浏览器打开 |
| `scripts/mp-copy.py` | 写进系统剪贴板，去公众号编辑器 ⌘V 粘贴 |
| `scripts/mp-publish.py` | 直接发布到公众号草稿箱 |

## 典型流程

```bash
SKILL=~/.workbuddy/skills/mp-wechat-style

# 1. 排版 + 预览，先看效果
python3 $SKILL/scripts/mp-preview.py 文章.md

# 2. 效果满意，二选一：

#    A. 手动粘贴（无需任何凭据，最省事）
python3 $SKILL/scripts/mp-copy.py 文章.md

#    B. 直接进草稿箱
python3 $SKILL/scripts/mp-publish.py 文章.md --cover 封面.jpg
```

**先预览再发布。** 排版是视觉工作，不看一眼就发出去大概率要返工。

## 支持的语法

标题 `#`~`######`、段落、软换行、硬换行（行尾两空格或 `\`）、
**加粗**、*斜体*、***粗斜体***、~~删除线~~、`行内代码`、围栏代码块、
有序 / 无序 / 嵌套 / 任务列表、引用（可嵌套）、GFM 表格、图片、链接、
裸链接、自动链接、分割线、反斜杠转义。

### 三个定制滚动块

用来折叠「读者需要但会打断阅读节奏」的内容：

```
<long-text>…</long-text>       大段文字放进限高容器，内部上下滚动
<long-image>…</long-image>     长图限高后上下滚动
<more-images>…</more-images>   多图横向排列，左右滑动
```

- 支持多行与单行两种写法：`<long-text>内容直接写在中间</long-text>`
- 标签名大小写不敏感
- 没写结束标签时会一直读到文件结尾，不丢内容
- 图片兼容 `![alt](url)`、`<img src="url">`、一行一个裸 URL
- 内容比限高短时容器自适应，不会出现空滚动条（用的是 `max-height`）

## 主题

默认主题就是 MPStyle 桌面应用那套：正文细体 `font-weight: 100`、行高 1.8、
字距 0.1em、主题色标题、米白圆角外框。

```bash
python3 $SKILL/scripts/mp-render.py 文章.md --theme 小绿书
python3 $SKILL/scripts/mp-render.py 文章.md --theme ~/我的主题.json
```

主题放两个地方，按名引用：

| 位置 | 用途 |
|---|---|
| `<skill>/themes/*.json` | 内置主题 |
| `~/.mp-wechat/themes/*.json` | 自己的主题，跨项目复用 |

完整字段说明见 [`references/theme-spec.md`](references/theme-spec.md)。
所有字段都可省略，缺的补默认值。想让排版跟着文章内容变风格时，
只需改一个 `themeColor` 就能换掉整套配色。

## 发布到草稿箱

```bash
python3 $SKILL/scripts/mp-publish.py 文章.md \
  --cover 封面.jpg \
  --title "文章标题" \
  --author "作者" \
  --digest "摘要" \
  --source-url "https://..."
```

凭据来源按优先级：`--app-id`/`--app-secret` → 环境变量 `MP_APP_ID`/`MP_APP_SECRET`
→ 当前目录的 `.env`（键名 `AppID` / `AppSecret`）。

### 发布前必须确认的两件事

**1. IP 白名单。** 公众号接口要求调用方 IP 在白名单里，否则一律返回 40164。
去「公众号后台 → 设置与开发 → 基本配置 → IP 白名单」加上本机公网 IP。
接口报错时会把 IP 直接写在提示里，照着加即可。动态 IP 每次变更都要重新加。

**2. 草稿箱接口需要已认证的公众号。** 未认证的订阅号会返回 48001，
没有这个权限，只能走 `mp-copy.py` 复制后手动粘贴。

### 封面是必填的

草稿接口强制要求封面。不传 `--cover` 时会现场生成一张纯色图兜底，
能过接口但不好看，正式发文还是自己准备一张（建议 900×383）。

### 正文图片会自动本地化

公众号对外站图片有防盗链，直接引用外链的草稿发布后会变成裂图。
脚本会把正文里的图片下载后上传到公众号图床再替换地址。
单张失败不中断整篇，会在日志里标出来。加 `--no-localize` 可跳过。

### 先验凭据再发文

```bash
python3 $SKILL/scripts/mp-publish.py 文章.md --cover 封面.jpg --dry-run
```

`--dry-run` 跑到上传封面为止，不创建草稿。用来确认 AppID/AppSecret/IP 白名单都对。

## 出问题时

| 现象 | 原因 |
|---|---|
| `invalid appid` | AppID 或 AppSecret 取值时把引号带进来了。检查 `.env` 里的引号是否成对 |
| `40164` | IP 不在白名单，按提示里的 IP 去后台添加 |
| `48001` | 公众号未认证，没有草稿箱权限 |
| 预览正常但粘贴后没样式 | 用了 `--print` 拿到的片段手动粘贴，缺了剪贴板的 `public.html` 类型。改用 `mp-copy.py` |
| 代码块里出现多余空行 | Markdown 围栏内首尾不要留空行 |

## 目录结构

```
mp-wechat-style/
├── SKILL.md
├── scripts/
│   ├── theme.py         主题规格读写与颜色推导
│   ├── parser.py        Markdown 解析（块级 + 行内）
│   ├── renderer.py      样式层 + HTML 输出
│   ├── mp-render.py     CLI: Markdown → HTML
│   ├── mp-preview.py    CLI: 生成预览页并打开
│   ├── mp-copy.py       CLI: 复制到剪贴板
│   └── mp-publish.py    CLI: 发布到草稿箱
├── themes/
│   └── default.json     默认主题
└── references/
    └── theme-spec.md    主题规格完整字段说明
```
