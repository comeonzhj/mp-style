SHELL := /bin/bash

APP_NAME     := MPStyle
DISPLAY_NAME := 公众号排版工具
BUNDLE_ID    := com.comeonzhj.mpstyle
VERSION      := $(shell cat VERSION)
MIN_MACOS    := 13.0

BUILD_DIR    := build
APP_BUNDLE   := $(BUILD_DIR)/$(APP_NAME).app
APP_BIN      := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
INFO_PLIST   := $(APP_BUNDLE)/Contents/Info.plist

SWIFTC       := swiftc
# 目标架构。默认编出 arm64 + x86_64 的通用二进制，Intel Mac 也能跑。
# 只想要单架构可以用 make build ARCHS=arm64（编译时间大约减半）。
ARCHS        ?= arm64 x86_64
# -disable-sandbox：Swift 6 会用一个受限沙箱去启动宏插件服务进程（swift-plugin-server），
#   在本机这类受限环境里 sandbox_apply 会失败，导致 SwiftUI 的 @State 等宏展开报
#   "produced malformed response"。关掉子进程沙箱即可正常编译。
SWIFT_FLAGS  := -disable-sandbox -swift-version 5 -O -parse-as-library
FRAMEWORKS   := -framework SwiftUI -framework AppKit -framework WebKit

# 注意：这几个变量必须用递归展开（= 而非 :=）。
# $(shell find) 在 Makefile 解析时就求值，会早于 Sources/BuildInfo.swift 的生成，
# 导致 clean 之后第一次构建漏掉该文件。递归展开推迟到执行 recipe 时才求值。
ALL_SOURCES  = $(shell find Sources -name '*.swift' | sort)
# 核心层：不依赖任何 UI 框架，可被命令行测试直接复用
CORE_SOURCES = $(shell find Sources/Markdown Sources/Render Sources/Model -name '*.swift' | sort)
# UI 层：界面快照与剪贴板验证需要连同 UI 一起编译
UI_SOURCES   = $(shell find Sources/Markdown Sources/Render Sources/Model Sources/UI -name '*.swift' | sort)

TEST_BIN     := $(BUILD_DIR)/render-cli
SNAPSHOT_BIN := $(BUILD_DIR)/ui-snapshot
COPY_BIN     := $(BUILD_DIR)/copy-check
HARDENED_BIN := $(BUILD_DIR)/hardened-check
PUBLISH_BIN  := $(BUILD_DIR)/publish-check
# 草稿箱凭据文件。里面是 AppID / AppSecret，已在 .gitignore 里排除
ENV_FILE     ?= .env
# Skill 脚本用的 Python 3。缺失时 skills-test 会跳过而不是失败
SKILLS_PY    ?= python3

# 除 App 入口外的全部源码。命令行工具不能带上 MPStyleApp.swift，否则两个 @main 冲突。
LIB_SOURCES  = $(filter-out Sources/MPStyleApp.swift,$(ALL_SOURCES))

# ══════════════════════════════════════════════════════════════════════
#  签名与公证
# ══════════════════════════════════════════════════════════════════════
# 自动挑 Developer ID Application 证书。找不到就退回 ad-hoc：
# 本地能跑，但拷给别人会被 Gatekeeper 拦下（"已损坏，无法打开"）。
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
                  | grep -m1 "Developer ID Application" \
                  | sed -E 's/^[^"]*"([^"]*)".*/\1/')

# 从证书主题里取 Team ID（形如 UID=XXXXXXXXXX）
TEAM_ID       ?= $(shell security find-certificate -c "Developer ID Application" -p 2>/dev/null \
                  | openssl x509 -noout -subject 2>/dev/null \
                  | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p' | head -1)

# 公证凭据在钥匙串里的 profile 名。执行 `make credentials` 交互式写入一次即可。
# 密码不会经过命令行参数，避免泄漏到 `ps` 输出和 shell 历史。
NOTARY_PROFILE ?= $(BUNDLE_ID)

# 公证鉴权方式。默认走钥匙串 profile；如果显式传了 APPLE_ID/APP_PASSWORD，
# 就改用命令行直传 —— 无 GUI 的环境（CI、受限 shell）里写钥匙串会报
# "User interaction is not allowed"，此时直传是唯一可行路径。
#   make release APPLE_ID=you@example.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx
APPLE_ID      ?=
APP_PASSWORD  ?=
ifneq ($(strip $(APPLE_ID)),)
  NOTARY_AUTH := --apple-id "$(APPLE_ID)" --team-id "$(TEAM_ID)" --password "$(APP_PASSWORD)"
  NOTARY_DESC := 命令行直传（$(APPLE_ID)）
else
  NOTARY_AUTH := --keychain-profile "$(NOTARY_PROFILE)"
  NOTARY_DESC := 钥匙串 profile $(NOTARY_PROFILE)
endif

ifeq ($(strip $(SIGN_IDENTITY)),)
  SIGN_ARGS := --force --sign -
  SIGN_DESC := ad-hoc
  SIGN_OK   := 0
else
  # --options runtime 开启强化运行时，这是公证的硬性前提
  # --timestamp 打 Apple 可信时间戳，证书过期后旧签名依然有效
  SIGN_ARGS := --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)"
  SIGN_DESC := $(SIGN_IDENTITY)
  SIGN_OK   := 1
endif

# 没有 Developer ID 证书时统一用这段提示退出。
# 不封装成 define 变量：变量展开后行首的 @ 不会被 make 识别，命令会被原样丢给 shell。
# 直接内联，两处各写一遍，少一层魔法。

# 装修 DMG 用的 Python（需要 Pillow + dmgbuild）。
# 找不到就退回朴素布局 —— 不因为缺一个可选工具让整个发布流程失败。
# 安装：pip install dmgbuild Pillow
DMG_PY ?= $(shell for p in python3 .venv/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do \
            { command -v $$p >/dev/null 2>&1 || [ -x $$p ]; } || continue; \
            $$p -c "import dmgbuild, PIL" 2>/dev/null && { echo $$p; break; }; \
          done)

NOTARIZE_ZIP := $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-notarize.zip
DMG          := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
DMG_STAGE    := $(BUILD_DIR)/dmg-stage

.PHONY: all build buildinfo run test snapshot copy-check hardened-check publish-check skills-test \
        icon clean install uninstall info sign verify notarize notarize-dmg staple \
        dmg release credentials doctor

all: build

# ══════════════════════════════════════════════════════════════════════
#  构建
# ══════════════════════════════════════════════════════════════════════

## 生成 BuildInfo.swift（版本号 + 构建时间 + git hash）。
## 做成 .PHONY 是因为 git hash 会随提交变化，必须每次构建都重新生成。
buildinfo:
	@scripts/gen-buildinfo.sh

## 编译并组装 .app（自动签名）
build: buildinfo
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources $(BUILD_DIR)
	@echo "==> 编译 $(APP_NAME) v$(VERSION)　架构: $(ARCHS)"
	@for arch in $(ARCHS); do \
		echo "    · $$arch"; \
		$(SWIFTC) $(SWIFT_FLAGS) -target $$arch-apple-macos$(MIN_MACOS) \
			$(FRAMEWORKS) $(ALL_SOURCES) -o $(BUILD_DIR)/$(APP_NAME)-$$arch || exit 1; \
	done
	@lipo -create $(foreach a,$(ARCHS),$(BUILD_DIR)/$(APP_NAME)-$(a)) -output $(APP_BIN)
	@rm -f $(foreach a,$(ARCHS),$(BUILD_DIR)/$(APP_NAME)-$(a))
	@cp Resources/Info.plist $(INFO_PLIST)
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(INFO_PLIST) 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(INFO_PLIST) 2>/dev/null || true
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/; fi
	@$(MAKE) --no-print-directory sign
	@echo "==> 完成: $(APP_BUNDLE) ($$(du -sh $(APP_BUNDLE) | cut -f1), $$(lipo -archs $(APP_BIN)))"

## 对 .app 签名
sign:
	@xattr -cr $(APP_BUNDLE) 2>/dev/null || true
	@codesign $(SIGN_ARGS) $(APP_BUNDLE)
	@codesign --verify --strict $(APP_BUNDLE)
	@echo "==> 已签名: $(SIGN_DESC)"

## 构建并启动
run: build
	@echo "==> 启动"
	@open $(APP_BUNDLE)

# ══════════════════════════════════════════════════════════════════════
#  校验工具
# ══════════════════════════════════════════════════════════════════════

## 命令行渲染测试：把样例 Markdown 渲染成 HTML，便于脱离 GUI 校验排版
## 渲染校验：编译命令行工具跑一遍样例，断言排版规则
test: $(TEST_BIN)
	@mkdir -p Tests/out
	@$(TEST_BIN) Tests/sample.md Tests/out/preview.html
	@echo "==> 输出: Tests/out/preview.html"

## 渲染命令行工具（test 与 skills-test 共用，避免重复编译）
$(TEST_BIN): buildinfo
	@mkdir -p $(BUILD_DIR)
	@echo "==> 编译渲染命令行工具"
	@$(SWIFTC) -disable-sandbox -swift-version 5 -O $(CORE_SOURCES) Tests/main.swift -o $@

## 界面快照：离屏渲染真实窗口，产出一张界面 PNG（开发期校验布局用）
snapshot: buildinfo
	@mkdir -p $(BUILD_DIR) Tests/out
	@echo "==> 编译界面快照工具"
	@$(SWIFTC) -disable-sandbox -swift-version 5 -O -parse-as-library \
		Sources/BuildInfo.swift $(UI_SOURCES) Tests/ui-snapshot/Snapshot.swift \
		-o $(SNAPSHOT_BIN) $(FRAMEWORKS)
	@$(SNAPSHOT_BIN) Tests/out/ui.png 1360 880 root 2.5
	@echo "==> 输出: Tests/out/ui.png"

## 剪贴板验证：把渲染结果写进系统剪贴板，检查 public.html 是否正确
copy-check: buildinfo
	@mkdir -p $(BUILD_DIR)
	@echo "==> 编译剪贴板验证工具"
	@$(SWIFTC) -disable-sandbox -swift-version 5 -O -parse-as-library \
		Sources/BuildInfo.swift $(UI_SOURCES) Tests/clipboard-check/CopyCheck.swift \
		-o $(COPY_BIN) $(FRAMEWORKS)
	@$(COPY_BIN) Tests/sample.md

## 草稿箱连通性验证：用真实账号跑一遍「渲染 → 传图 → 建草稿」
## 需要 $(ENV_FILE) 里有 AppID / AppSecret
publish-check:
	@mkdir -p $(BUILD_DIR)
	@test -f "$(ENV_FILE)" || { \
		echo "✗ 找不到 $(ENV_FILE)。需要两行：AppID=xxx 与 AppSecret=xxx"; \
		echo "  该文件已被 .gitignore 排除，不会被提交。"; \
		exit 1; }
	@echo "==> 编译草稿箱验证工具"
	@$(SWIFTC) $(SWIFT_FLAGS) -target $$(uname -m)-apple-macos$(MIN_MACOS) \
		$(FRAMEWORKS) $(LIB_SOURCES) Tests/publish-check/PublishCheck.swift \
		-o $(PUBLISH_BIN)
	@$(PUBLISH_BIN) $(ENV_FILE)

## 校验 Agent Skills：语法 + 与 Swift 渲染器的输出一致性
##
## 两个渲染器服务于同一套主题规格，只改一边就会让「同一个主题在 App 和 Skill 里
## 排出来不一样」，这种偏差肉眼很难发现，所以守在这里。
skills-test: $(TEST_BIN)
	@command -v $(SKILLS_PY) >/dev/null 2>&1 || { \
		echo "✗ 找不到 $(SKILLS_PY)，跳过（Skill 需要 Python 3）"; exit 0; }
	@echo "==> 校验 Skill 脚本语法"
	@$(SKILLS_PY) -m compileall -q skills/ >/dev/null
	@find skills -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "==> 校验两个渲染器输出一致"
	@mkdir -p $(BUILD_DIR)
	@$(SKILLS_PY) skills/mp-wechat-style/scripts/mp-render.py \
		Tests/sample.md --fragment -o $(BUILD_DIR)/skill-render.html >/dev/null
	@$(TEST_BIN) Tests/sample.md $(BUILD_DIR)/swift-render.html >/dev/null
	@$(SKILLS_PY) scripts/check-render-parity.py \
		$(BUILD_DIR)/swift-render.html $(BUILD_DIR)/skill-render.html

## 生成应用图标（需要 python3 + Pillow，缺失时自动跳过）
icon:
	@python3 scripts/make-icon.py 2>/dev/null && echo "==> 图标已生成" || echo "==> 跳过图标（缺 Pillow）"

## 强化运行时自检：确认开启 hardened runtime 之后 WKWebView 的 JavaScript 仍能执行。
## 预览面板依赖 evaluateJavaScript 注入内容，万一被 JIT 限制拦掉会静默变空白，
## 所以发布前必须过这一关。有 Developer ID 时用发布同款签名参数复测。
hardened-check:
	@mkdir -p $(BUILD_DIR)
	@echo "==> 编译强化运行时自检工具"
	@$(SWIFTC) -disable-sandbox -swift-version 5 -O -parse-as-library \
		Tests/hardened-check/HardenedCheck.swift -o $(HARDENED_BIN) \
		-framework WebKit -framework AppKit
	@if [ "$(SIGN_OK)" = "1" ]; then \
		cp -f $(HARDENED_BIN) $(HARDENED_BIN).signed; \
		codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(HARDENED_BIN).signed; \
		echo "==> 用发布同款签名参数复测"; \
		$(HARDENED_BIN).signed; \
	else \
		echo "==> 无 Developer ID 证书，只跑未签名基线"; \
		$(HARDENED_BIN); \
	fi

# ══════════════════════════════════════════════════════════════════════
#  签名 / 公证 / 分发
# ══════════════════════════════════════════════════════════════════════

## 查看签名详情
verify:
	@echo "==> 签名信息"
	@codesign -dv --verbose=4 $(APP_BUNDLE) 2>&1 \
		| grep -E "Identifier|TeamIdentifier|Authority|TeamName|Timestamp|flags" || true
	@echo "==> 严格校验"
	@codesign --verify --strict --verbose=2 $(APP_BUNDLE) && echo "签名有效"
	@echo "==> Gatekeeper 评估"
	@spctl -a -vvv -t exec $(APP_BUNDLE) 2>&1 || true

## 一次性把公证凭据存进钥匙串（交互式输入，密码不经过命令行参数与 shell 历史）
credentials:
	@scripts/store-notary-credentials.sh "$(NOTARY_PROFILE)"

## 提交 Apple 公证（会自动等待结果）
notarize:
	@test "$(SIGN_OK)" = "1" || { \
		echo "✗ 没找到 Developer ID Application 证书，无法产出可分发的版本。"; \
		echo "  本地开发用 make build 即可（会自动退回 ad-hoc 签名）。"; \
		exit 1; }
	@rm -f $(NOTARIZE_ZIP)
	@echo "==> 打包待公证"
	@ditto -c -k --keepParent $(APP_BUNDLE) $(NOTARIZE_ZIP)
	@echo "==> 提交公证（通常 1~5 分钟）｜鉴权：$(NOTARY_DESC)"
	@xcrun notarytool submit $(NOTARIZE_ZIP) $(NOTARY_AUTH) --wait
	@rm -f $(NOTARIZE_ZIP)

## 公证并装订 DMG
##
## 提交前必须先确认 DMG 没有被挂载或占用 —— Apple 的预检要完整读一遍文件，
## 一旦有残留挂载卷或 diskimage 进程持有它，notarytool 会卡在
## "initiating connection to the Apple notary service" 且永远不返回，也不报错。
notarize-dmg:
	@test -f $(DMG) || { echo "✗ 还没有 $(DMG)，先跑 make dmg"; exit 1; }
	@if [ -n "$$(lsof $(DMG) 2>/dev/null)" ]; then \
		echo "✗ $(DMG) 正被占用，Apple 预检会读不到文件而卡死："; \
		lsof $(DMG); \
		echo "  常见原因：残留挂载卷（diskutil unmount / hdiutil detach）"; \
		echo "           或残留 diskimage 进程（kill 掉即可）"; \
		exit 1; \
	fi
	@hdiutil verify $(DMG) >/dev/null && echo "==> DMG 校验通过"
	@echo "==> 提交公证｜鉴权：$(NOTARY_DESC)"
	@xcrun notarytool submit $(DMG) $(NOTARY_AUTH) --wait
	@xcrun stapler staple $(DMG)
	@xcrun stapler validate $(DMG)

## 装订公证票据到 .app
staple:
	@xcrun stapler staple $(APP_BUNDLE)
	@xcrun stapler validate $(APP_BUNDLE)

## 打成 DMG（带拖拽安装引导界面）
##
## 注意两件事：
## 1. 这里刻意不依赖 build —— 若在公证、装订之后再重新编译签名，
##    cdhash 会变化，已装订的公证票据立刻失效。DMG 必须基于当前那份已装订的 .app。
## 2. DMG 必须单独签名。公证 ≠ 签名，只公证不签名的 DMG 会被 spctl 判为
##    "no usable signature"。而且签名会覆盖/清掉已有票据，所以顺序只能是
##    建 DMG → 签名 → 公证 → 装订。
dmg:
	@test -d $(APP_BUNDLE) || { echo "✗ 还没有 $(APP_BUNDLE)，先跑 make build"; exit 1; }
	@rm -f $(DMG)
	@if [ -n "$(DMG_PY)" ]; then \
		echo "==> 用 dmgbuild 生成带引导界面的 DMG"; \
		$(DMG_PY) scripts/make-dmg.py $(DMG) $(VERSION) $(APP_BUNDLE); \
	else \
		echo "==> 未装 dmgbuild，生成朴素 DMG（pip install dmgbuild Pillow 可启用引导界面）"; \
		rm -rf $(DMG_STAGE); mkdir -p $(DMG_STAGE); \
		cp -R $(APP_BUNDLE) $(DMG_STAGE)/; \
		ln -s /Applications $(DMG_STAGE)/Applications; \
		hdiutil create -volname "$(DISPLAY_NAME) $(VERSION)" -srcfolder $(DMG_STAGE) \
			-ov -format UDZO -quiet $(DMG); \
		rm -rf $(DMG_STAGE); \
	fi
	@if [ "$(SIGN_OK)" = "1" ]; then \
		codesign --force --timestamp --sign "$(SIGN_IDENTITY)" $(DMG); \
	fi
	@echo "==> $(DMG) ($$(du -sh $(DMG) | cut -f1))"

## 一键发布：签名 → 公证 App → 装订 → 打 DMG → 公证 DMG → 装订 → Gatekeeper 评估
release:
	@test "$(SIGN_OK)" = "1" || { \
		echo "✗ 没找到 Developer ID Application 证书，无法产出可分发的版本。"; \
		echo "  本地开发用 make build 即可（会自动退回 ad-hoc 签名）。"; \
		exit 1; }
	@echo "═══ 1/7 强化运行时自检"
	@$(MAKE) --no-print-directory hardened-check
	@echo "═══ 2/7 构建 + 签名"
	@$(MAKE) --no-print-directory build
	@echo "═══ 3/7 公证 .app"
	@$(MAKE) --no-print-directory notarize
	@echo "═══ 4/7 装订票据到 .app"
	@$(MAKE) --no-print-directory staple
	@echo "═══ 5/7 生成 DMG"
	@$(MAKE) --no-print-directory dmg
	@echo "═══ 6/7 公证 DMG"
	@$(MAKE) --no-print-directory notarize-dmg
	@echo "═══ 7/7 Gatekeeper 评估"
	@echo "-- .app（决定别人能不能打开的那一项）"
	@spctl -a -vvv -t exec $(APP_BUNDLE)
	@echo "-- DMG"
	@spctl -a -vvv -t install $(DMG) || true
	@echo "-- 公证票据"
	@xcrun stapler validate $(APP_BUNDLE) >/dev/null && echo "  ✓ .app 已装订"
	@xcrun stapler validate $(DMG) >/dev/null && echo "  ✓ DMG 已装订"
	@echo
	@echo "完成。分发文件："
	@echo "  $(DMG)                                （磁盘映像，推荐）"
	@echo "  $(APP_BUNDLE)                         （已公证并装订，可直接压缩分发）"

## 环境自检：证书、Team ID、公证凭据是否就绪
doctor:
	@echo "── 代码签名证书 ──────────────────────"
	@security find-identity -v -p codesigning 2>/dev/null || echo "（无）"
	@echo
	@echo "── 本次构建将使用的身份 ──────────────"
	@echo "  $(SIGN_DESC)"
	@echo "  Team ID: $(if $(TEAM_ID),$(TEAM_ID),（未取到）)"
	@echo
	@echo "── 公证凭据 ──────────────────────────"
	@xcrun notarytool history --keychain-profile "$(NOTARY_PROFILE)" 2>&1 | head -3

# ══════════════════════════════════════════════════════════════════════
#  其它
# ══════════════════════════════════════════════════════════════════════

## 安装到 /Applications
install: build
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "==> 已安装到 /Applications/$(APP_NAME).app"

uninstall:
	@rm -rf /Applications/$(APP_NAME).app
	@echo "==> 已卸载"

info:
	@echo "版本    : $(VERSION)"
	@echo "Bundle  : $(BUNDLE_ID)"
	@echo "架构    : $(ARCHS)"
	@echo "最低系统: macOS $(MIN_MACOS)"
	@echo "签名身份: $(SIGN_DESC)"
	@echo "DMG 工具: $(if $(DMG_PY),$(DMG_PY),未装 dmgbuild，将生成朴素 DMG)"
	@echo "源码数  : $$(echo $(ALL_SOURCES) | wc -w | tr -d ' ')"

clean:
	@rm -rf $(BUILD_DIR) Tests/out Sources/BuildInfo.swift
	@echo "==> 已清理"
