# 基准样式提取记录

来源：`https://mp.weixin.qq.com/s/Jdg8uvL_qSvPAu3zjY7gNg`（《WorkBuddy+DeepSeek-V4.1做设计，一绝！》）
提取方式：ego-lite 打开页面，读取 `#js_content` 各元素 `getComputedStyle`。

## 原始计算样式

### 容器
```css
font-family: "PingFang SC NEW", system-ui, -apple-system, "Helvetica Neue", "Hiragino Sans GB", "Microsoft YaHei UI", "Microsoft YaHei", Arial, sans-serif;
font-size: 17px;
line-height: 27.2px;
color: rgba(0,0,0,.9);
letter-spacing: .544px;
text-align: justify;
```

### 正文段落 `p`
```css
margin: 1.2em 0;
letter-spacing: 0.1em;   /* = 1.5px @15px */
color: #333333;
text-align: justify;
line-height: 1.8;
font-size: 15px;
```
> 段落实际字号 15px，行高 1.8（≠ 容器继承的 17px/27.2px）。

### 二级标题 `h2`
```css
padding: .4em 0 .5em .8em;
margin: 1.8em 0 1em;
color: #1d1d1f;
font-size: 20px;
font-weight: 600;
text-align: left;
border-left: 3px solid;
border-image: linear-gradient(#007aff, #5856d6) 1 / 1 / 0 stretch;   /* ← 待移除 */
```
行高实测 32px（1.6）。

### 图片 `img`
```css
max-width: 100%;
border-radius: 8px;
margin: 1.5em auto;
display: block;
box-shadow: 0 8px 25px rgba(0,0,0,0.1);
```
外层 `figure`：`margin: 1.5em 0; text-align: center; line-height: 1.6; font-size: 15px; color: #555555;`

### 列表 `ol` / `li`
```css
/* ol */
list-style: none;
padding: 0;
margin: 1.2em 0;
color: #333333;
font-size: 15px;

/* li */
margin: .4em 0;
padding: 0;
line-height: 1.7;
font-size: 15px;
```
> 原文的 `list-style: none` + 序号是**字面文本**「1. 」，所以列表实际没有缩进。本次要改成「比正文多一点点缩进 + 主题色序号」。

### 内容卡片 `section`
```css
background-color: #F9F8F4;
border-radius: 24px;
padding: 8px 12px;
max-width: 680px;
margin: 0 auto;
box-shadow: 0 6px 25px rgba(0,0,0,.06);
```
整篇正文包在一层米白圆角卡片里。

### 原文未出现的元素
`blockquote` / `code` / `pre` / `h3` / `strong` 原文均为 0 个，需按同一套视觉语言（米白底、柔和阴影、8px 圆角、细字重）自行补全。

## 本次改造规则

| 元素 | 规则 |
|---|---|
| 正文 | `font-weight: 100`（细体），其余沿用原文 |
| 加粗 | `font-weight: 500` + 主题色 |
| H2 | 去掉左侧渐变 border，颜色 = 主题色（默认 `#1B63F3`） |
| H3 | 新增，H2 同款但字号更小、行高更紧 |
| 有序/无序列表 | 缩进略大于正文，序号/圆点用主题色 |
| 图片 | 统一圆角 + 阴影（沿用原文 8px / `0 8px 25px rgba(0,0,0,.1)`） |
| 引用 / 代码块 / 行内代码 | 按同一视觉语言补全 |
