# Agent Skills

两个把「公众号排版」这件事交给 AI 助手做的 Skill。纯 Python 标准库，
装了 Python 3 就能跑，**不依赖同仓库里的那个 macOS 应用**。

| Skill | 做什么 |
|---|---|
| [`mp-wechat-style`](mp-wechat-style/SKILL.md) | Markdown 排版 → 预览 / 一键复制 / 发布到草稿箱 |
| [`mp-wechat-extract`](mp-wechat-extract/SKILL.md) | 给一篇公众号文章链接，还原它的排版成主题 JSON |

两者共用同一套**主题规格**（字段名与 App 的 `ThemeConfig` 一致），
所以 App 里的参数、Skill 生成的主题、从别人文章萃取出的风格，三者可以互相流转。

## 安装

```bash
scripts/install-skills.sh                    # 装到 ~/.workbuddy/skills
SKILLS_DIR=~/.claude/skills scripts/install-skills.sh   # 装到别处
scripts/install-skills.sh --link             # 软链模式，改仓库代码即时生效
```

## 快速试一下

```bash
SKILL=~/.workbuddy/skills/mp-wechat-style

# 排版并预览
python3 $SKILL/scripts/mp-preview.py 文章.md

# 复制到剪贴板，去公众号编辑器 ⌘V 粘贴
python3 $SKILL/scripts/mp-copy.py 文章.md

# 直接进草稿箱（需要 AppID / AppSecret，且 IP 在白名单里）
python3 $SKILL/scripts/mp-publish.py 文章.md --cover 封面.jpg
```

## 萃取别人的排版

```bash
# 用内置浏览器取文章正文（公众号正文靠 JS 渲染，别用 curl）
agent-browser open "https://mp.weixin.qq.com/s/xxxx"
agent-browser wait --load networkidle
agent-browser get html "#js_content" > /tmp/article.html
agent-browser close

# 萃取出主题
python3 ~/.workbuddy/skills/mp-wechat-extract/scripts/extract.py \
  /tmp/article.html -o ~/.mp-wechat/themes/某某风格.json --name "某某风格"

# 用自己的文章看效果
python3 $SKILL/scripts/mp-preview.py 我的文章.md --theme 某某风格
```

也可以一条命令跑完抓取加萃取：`extract.py --url "<链接>"`。

## 为什么 Skills 版和 App 版长得一样

Skill 里的 Python 渲染器是 App 那套 Swift 渲染器的完整移植，两者必须对同一份 Markdown
产出相同的内联样式。仓库根目录的 `make skills-test` 会逐条比对两份输出，
已经进了 CI —— 只改一边会立刻红。

当前基线：112 条内联样式、1043 字正文，逐条一致。

## 目录

```
skills/
├── mp-wechat-style/
│   ├── SKILL.md
│   ├── scripts/
│   │   ├── theme.py         主题规格读写与颜色推导
│   │   ├── parser.py        Markdown 解析（块级 + 行内）
│   │   ├── renderer.py      样式层 + HTML 输出
│   │   ├── mp-render.py     CLI: Markdown → HTML
│   │   ├── mp-preview.py    CLI: 生成预览页并打开
│   │   ├── mp-copy.py       CLI: 复制到剪贴板
│   │   └── mp-publish.py    CLI: 发布到草稿箱
│   ├── themes/default.json  默认主题
│   └── references/theme-spec.md
└── mp-wechat-extract/
    ├── SKILL.md
    ├── scripts/extract.py   HTML → 主题 JSON
    └── references/theme-spec.md
```
