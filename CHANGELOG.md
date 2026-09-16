# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.0] - 2026-09-16

### 新增
- 首个可用版本。原生 SwiftUI 单窗口应用（无 Electron、无运行时依赖，二进制约 200KB）。
- 三栏布局：左 Markdown 编辑区 / 中手机宽度实时预览 / 右参数面板。
- Markdown 解析器：ATX 标题、段落、有序 / 无序 / 嵌套列表、任务列表、引用（可嵌套）、
  围栏代码块、行内代码、加粗、斜体、删除线、链接、图片、分割线、GFM 表格。中文段落换行自动不加空格。
- 渲染器输出**全内联样式** HTML（不含任何 class / style 标签），可直接粘贴进微信公众号编辑器。
- 一键复制：同时写入 `public.html` 与 `public.utf8-plain-text` 两种剪贴板类型。
- 可调参数：主题色、正文字号、正文字重、加粗字重、行高、字距、段间距、图片圆角、
  各级标题缩放比、列表缩进、背景卡片开关。配置自动持久化到 UserDefaults。
- 内置 6 套主题色预设。

### 分发
- Developer ID 签名 + Apple 公证 + 票据装订，全流程由 `make release` 一条命令完成。
- 开启强化运行时（hardened runtime）并打 Apple 可信时间戳。
- `.app` 与 `.dmg` 双产物，均已公证装订 —— 别人下载后双击即可打开，
  断网首次启动也不会被 Gatekeeper 拦。
- 新增 `make hardened-check`：验证强化运行时下 WKWebView 的 JavaScript 仍能执行。
  预览面板依赖 `evaluateJavaScript` 注入内容，被 JIT 限制拦掉会静默变空白，
  因此这一项已固化进发布流程。结论是不需要任何额外 entitlements。
- 新增 `make doctor` 环境自检、`make credentials` 交互式存入公证凭据
  （密码走 `read -s`，不进命令行参数）。

### 排版规则（基于参考文章 `mp.weixin.qq.com/s/Jdg8uvL_qSvPAu3zjY7gNg`）
- 正文 `font-weight: 100`，行高 1.8，字距 0.1em，颜色 `#333333`，两端对齐。
- 加粗 `font-weight: 500` + 主题色。
- H2 移除原本的左侧渐变竖条，颜色改为主题色（默认 `#1B63F3`）。
- 新增 H3：与 H2 同构，字号更小、行高更紧。
- 有序 / 无序列表相对正文增加缩进，序号与圆点使用主题色，采用悬挂缩进。
- 图片统一 8px 圆角 + `0 8px 25px rgba(0,0,0,.1)` 柔和阴影。
- 引用块：主题色左边线 + 主题色浅色底 + 右侧圆角。
- 代码块：浅灰底 8px 圆角，等宽字体；行内代码用主题色浅底 + 主题色文字。
