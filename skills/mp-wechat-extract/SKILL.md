---
name: mp-wechat-extract
version: 1.0.0
description: 从微信公众号文章链接里萃取出排版主题，输出为可被 mp-wechat-style 直接使用的主题 JSON。当用户想复刻某篇公众号文章的排版、想扒别人的公众号样式、想提取文章字体字号配色、想把某篇文章的视觉风格用到自己的文章上时使用。
---

# 公众号排版萃取

给一个公众号文章链接，还原出它的排版规格，产出一份标准主题 JSON，
交给 `mp-wechat-style` 就能把同样的视觉用在自己的文章上。

## 为什么能萃取得准

公众号编辑器会丢弃 `<style>` 标签和 class，只保留**内联样式**。
所以你看到的每一个字号、颜色、间距，全都明明白白写在 `style` 属性里 ——
拿到 `#js_content` 的 HTML 就等于拿到了完整的排版规格，不需要靠截图猜。

## 用内置浏览器抓取

**必须用真浏览器取 HTML，不要用 curl 直接抓。** 公众号正文依赖 JS 渲染，
直接抓到的 HTML 常常缺少 `visibility` 处理后的内容。

用 WorkBuddy 内置的 `agent-browser`：

```bash
agent-browser open "<文章链接>"
agent-browser wait --load networkidle
agent-browser get html "#js_content" > /tmp/article.html
agent-browser close
```

三条关键点：

- `wait` 可能在不收敛的页面上挂住。卡住就退到 `agent-browser wait --load load`，
  或者干脆跳过等待直接 `get html`
- 取正文用 `get html "#js_content"`。`snapshot` 只给文字，样式全丢，对萃取没用
- **任务结束必须 `agent-browser close`**，无论中间是否出错，否则会留下后台进程

也可以用脚本一条命令跑完：

```bash
python3 ~/.workbuddy/skills/mp-wechat-extract/scripts/extract.py \
  --url "<文章链接>" -o 主题名.json --name "主题名"
```

## 萃取 + 应用

```bash
SKILL=~/.workbuddy/skills/mp-wechat-extract
STYLE=~/.workbuddy/skills/mp-wechat-style

# 1. 抓 HTML
agent-browser open "https://mp.weixin.qq.com/s/xxxx"
agent-browser wait --load networkidle
agent-browser get html "#js_content" > /tmp/article.html
agent-browser close

# 2. 萃取成主题
python3 $SKILL/scripts/extract.py /tmp/article.html -o 我的主题.json --name "我的主题"

# 3. 装到主题目录，之后按名引用
cp 我的主题.json ~/.mp-wechat/themes/

# 4. 用自己的文章看效果
python3 $STYLE/scripts/mp-preview.py 我的文章.md --theme 我的主题
```

第 4 步别省。萃取是统计推断，出来的东西一定要用**自己的文章**过一眼 ——
你自己的文章里有列表、引用、代码块，原文里未必有，那些部分会落到默认值上。

## 反推逻辑

不是简单抄第一个元素的样式，而是**每种元素统计众数，再用比例推导**：

| 主题字段 | 从哪儿来 |
|---|---|
| `fontSize` | 段落 `font-size` 的众数 |
| `bodyWeight` | 段落 `font-weight`。没声明就按浏览器默认的 400 |
| `lineHeight` | 段落 `line-height`。带 px 的按字号换算成倍数 |
| `letterSpacing` | 段落 `letter-spacing` 换算成 em。**只有少数段落声明时归零** |
| `paragraphSpacing` | 段落 `margin-bottom` ÷ 字号 |
| `fontFamily` / `monoFamily` | 段落 / 代码的字体栈 |
| `h2Scale` 等 | 标题字号 ÷ 正文字号 |
| `h2Top` / `h2Bottom` | 标题 margin ÷ 字号 |
| `themeColor` | 按角色加权选饱和度最高的强调色：标题 > 链接 > 加粗 > 代码 |
| `boldColorMode` | 加粗色接近正文色 → `inherit`；否则 `custom` |
| `headingColorMode` | 标题色等于主题色 → `theme`；否则 `custom` |
| `codeBg` / `codeScale` | 行内代码的底色与字号比 |
| `cardColor` | 最外层带底色的 `section` |
| `imageRadius` / `imageShadow` | 图片的圆角与阴影 |

### 两个容易做错的地方

**低透明度叠加色要合成，不能丢。** 现代排版大量用 `rgba(26,26,24,0.02)`
这种极淡叠加做底纹，肉眼看到的是合成后的 `#FAFAFA`。直接按「半透明」丢弃，
卡片底色和代码底色就全丢了。脚本会把它合成到白底上。

**孤例不能当规律。** 92 个段落里只有 1 个声明了 `letter-spacing`，
那是局部特例。脚本会先看该属性的**覆盖率**，低于 20% 就当这套设计没用到它。

## 已知边界

- 复杂版式（用 flex 拼的多栏、绝对定位的信息图）还原不出来 ——
  那些不是「排版」而是「设计」，只能当图片处理
- 逐个元素的特殊装饰（某一段单独换个颜色）会被众数抹平
- 引用块、列表、表格在原文里没出现时，对应字段沿用默认值
- 图片的边框样式不提取（转换成阴影语义没有对应字段）

## 目录结构

```
mp-wechat-extract/
├── SKILL.md
├── scripts/
│   └── extract.py        HTML → 主题 JSON（也可 --url 自己驱动浏览器）
└── references/
    └── theme-spec.md     → 指向 mp-wechat-style 的主题规格说明
```
