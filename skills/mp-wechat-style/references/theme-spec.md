# 主题规格

一份主题就是一个 JSON 文件，描述「文章长什么样」。字段名与 MPStyle 桌面应用的
`ThemeConfig` 完全一致，所以三边可以互通：

```
mp-wechat-style（本 Skill）  ─┐
MPStyle.app 导出/导入         ─┼─→  同一份 theme.json
mp-wechat-extract 的产出     ─┘
```

## 放置位置

按优先级查找：

| 位置 | 用途 |
|---|---|
| `<skill>/themes/*.json` | 内置主题，跟着 Skill 一起分发 |
| `~/.mp-wechat/themes/*.json` | 你自己的主题，跨项目复用 |

也可以直接用路径：`--theme /path/to/theme.json`。

引用时写文件名去掉 `.json`，例如 `themes/小绿书.json` → `--theme 小绿书`。

## 最小可用主题

**所有字段都可省略**，缺的自动补默认值。一个只改主题色的最小主题：

```json
{
  "themeColor": "#07C160"
}
```

## 完整字段

### 颜色

| 字段 | 默认 | 说明 |
|---|---|---|
| `themeColor` | `#1B63F3` | 主题色。标题、加粗、列表序号、引用边线、链接都取它 |
| `textColor` | `#333333` | 正文颜色 |
| `secondaryTextColor` | `#888888` | 次级文字：删除线、滚动提示 |
| `headingColorMode` | `theme` | `theme` 跟随主题色 / `dark` 固定深色 / `custom` 用 `customHeadingColor` |
| `customHeadingColor` | `#1D1D1F` | 上面选 `custom` 时生效 |

### 正文

| 字段 | 默认 | 说明 |
|---|---|---|
| `fontFamily` | 系统字体栈 | 正文与卡片容器的字体 |
| `monoFamily` | 等宽字体栈 | 代码块与行内代码的字体 |
| `fontSize` | `15` | 正文字号（px），其余字号都以它为基准缩放 |
| `bodyWeight` | `100` | 正文字重。100 是细体，是这套排版的识别度来源 |
| `lineHeight` | `1.8` | 正文行高 |
| `letterSpacing` | `0.1` | 字距（em） |
| `paragraphSpacing` | `1.2` | 段间距（em） |
| `textAlignJustify` | `true` | 两端对齐 |

### 加粗

| 字段 | 默认 | 说明 |
|---|---|---|
| `boldWeight` | `500` | 加粗字重（400~900） |
| `boldColorMode` | `theme` | `theme` 跟随主题色 / `inherit` 只加粗不变色 / `custom` 用 `customBoldColor` |
| `customBoldColor` | `#1B63F3` | 上面选 `custom` 时生效 |

### 标题

| 字段 | 默认 | 说明 |
|---|---|---|
| `h1Scale` ~ `h4Scale` | `1.60 / 1.333 / 1.13 / 1.00` | 各级标题相对正文的缩放 |
| `headingWeight` | `600` | 标题字重 |
| `h1Top` / `h1Bottom` | `1.9 / 1.0` | 一级标题上下边距（em） |
| `h2Top` / `h2Bottom` | `1.8 / 1.0` | 二级标题上下边距（em） |
| `h2LineHeight` | `1.60` | 二级标题行高 |
| `h3Top` / `h3Bottom` | `1.5 / 0.7` | 三级标题上下边距（em） |
| `h3LineHeight` | `1.45` | 三级标题行高 |

### 列表

| 字段 | 默认 | 说明 |
|---|---|---|
| `listIndent` | `1.2` | 相对正文的缩进（em），同时用作悬挂缩进量 |
| `listItemSpacing` | `0.35` | 列表项之间的间距（em） |
| `listLineHeight` | `1.70` | 列表行高 |
| `listMarkerWeight` | `500` | 序号 / 圆点的字重 |

### 图片

| 字段 | 默认 | 说明 |
|---|---|---|
| `imageRadius` | `8` | 圆角（px） |
| `imageShadow` | `true` | 是否加柔和阴影 |
| `imageSpacing` | `1.5` | 图片上下边距（em） |

### 引用

| 字段 | 默认 | 说明 |
|---|---|---|
| `quoteBarWidth` | `3` | 左侧竖条宽度（px） |
| `quoteRadius` | `8` | 右侧圆角（px） |
| `quoteBgTint` | `0.07` | 底色 = 主题色按该比例混入白色，越小越浅 |
| `quoteTextColor` | `#555555` | 引用内文字颜色 |

### 代码

| 字段 | 默认 | 说明 |
|---|---|---|
| `codeBg` | `#F7F8FA` | 代码块底色 |
| `codeRadius` | `8` | 代码块圆角（px） |
| `codeScale` | `0.88` | 代码字号相对正文的缩放 |

### 滚动块

| 字段 | 默认 | 说明 |
|---|---|---|
| `longTextMaxHeight` | `320` | `<long-text>` 限高（px），超出后内部滚动 |
| `longTextBg` | `#F7F9FC` | 长文本块底色 |
| `longTextRadius` | `8` | 长文本块圆角（px） |
| `longTextPadding` | `0.9` | 长文本块内边距（em） |
| `longImageMaxHeight` | `450` | `<long-image>` 限高（px） |
| `longImageRadius` | `8` | 长图圆角（px） |
| `galleryImageWidth` | `72` | `<more-images>` 单张图占容器宽度百分比 |
| `galleryGap` | `12` | 横滑图片间距（px） |
| `galleryRadius` | `8` | 横滑图片圆角（px） |
| `scrollHintEnabled` | `true` | 是否显示「↓ 上下滑动查看」提示 |

### 外框卡片

| 字段 | 默认 | 说明 |
|---|---|---|
| `cardEnabled` | `true` | 是否给整篇套一层米白圆角卡片 |
| `cardColor` | `#F9F8F4` | 卡片底色 |
| `cardRadius` | `24` | 卡片圆角（px） |

### 预览

| 字段 | 默认 | 说明 |
|---|---|---|
| `previewWidth` | `375` | 预览页宽度。`375` 模拟手机，`677` 模拟公众号编辑区 |

## 派生规则

改基准值比逐个改细节更省事。几个自动推导的规则：

- 各级标题字号 = `fontSize × hNScale`，结果取整到 0.5px
- 代码字号 = `fontSize × codeScale`
- 引用内字号 = `fontSize × 0.96`，行高固定 1.75
- 引用底色 = `themeColor` 按 `quoteBgTint` 混入白色；嵌套时加深 80%
- 表格字号 = `fontSize × 0.93`
- 滚动提示字号 = `fontSize × 0.8`

所以把 `fontSize` 从 15 调到 17，整篇的字号层级会等比放大，不用逐个改。

## 校验

写错了不会崩，只会被忽略并保留默认值。检查实际生效的结果：

```bash
python3 scripts/mp-render.py 文章.md --theme 你的主题 --fragment | head -c 400
```

或者让脚本报出被忽略的字段：

```bash
python3 -c "
import sys; sys.path.insert(0, 'scripts')
import theme as t
raw = __import__('json').load(open('你的主题.json'))
bad = [k for k in raw if k not in t.KNOWN_KEYS]
print('未知字段:', bad or '无')
"
```
