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
# -disable-sandbox：Swift 6 会用一个受限沙箱去启动宏插件服务进程（swift-plugin-server），
#   在本机这类受限环境里 sandbox_apply 会失败，导致 SwiftUI 的 @State 等宏展开报
#   "produced malformed response"。关掉子进程沙箱即可正常编译。
SWIFT_FLAGS  := -disable-sandbox -swift-version 5 -O -parse-as-library -target arm64-apple-macos$(MIN_MACOS)
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

.PHONY: all build run test snapshot copy-check icon clean install uninstall release info

all: build

## 生成 BuildInfo.swift（版本号注入）
Sources/BuildInfo.swift: VERSION scripts/gen-buildinfo.sh
	@scripts/gen-buildinfo.sh

## 编译并组装 .app
build: Sources/BuildInfo.swift
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	@echo "==> 编译 $(APP_NAME) v$(VERSION)"
	@$(SWIFTC) $(SWIFT_FLAGS) $(FRAMEWORKS) $(ALL_SOURCES) -o $(APP_BIN)
	@cp Resources/Info.plist $(INFO_PLIST)
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(INFO_PLIST) 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(INFO_PLIST) 2>/dev/null || true
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/; fi
	@codesign --force --deep --sign - $(APP_BUNDLE) 2>/dev/null || true
	@echo "==> 完成: $(APP_BUNDLE) ($$(du -sh $(APP_BUNDLE) | cut -f1))"

## 构建并启动
run: build
	@echo "==> 启动"
	@open $(APP_BUNDLE)

## 命令行渲染测试：把样例 Markdown 渲染成 HTML，便于脱离 GUI 校验排版
test: Sources/BuildInfo.swift
	@mkdir -p $(BUILD_DIR) Tests/out
	@echo "==> 编译渲染命令行工具"
	@$(SWIFTC) -disable-sandbox -swift-version 5 -O $(CORE_SOURCES) Tests/main.swift -o $(TEST_BIN)
	@$(TEST_BIN) Tests/sample.md Tests/out/preview.html
	@echo "==> 输出: Tests/out/preview.html"

## 界面快照：离屏渲染真实窗口，产出一张界面 PNG（开发期校验布局用）
snapshot: Sources/BuildInfo.swift
	@mkdir -p $(BUILD_DIR) Tests/out
	@echo "==> 编译界面快照工具"
	@$(SWIFTC) -disable-sandbox -swift-version 5 -O -parse-as-library \
		Sources/BuildInfo.swift $(UI_SOURCES) Tests/ui-snapshot/Snapshot.swift \
		-o $(SNAPSHOT_BIN) $(FRAMEWORKS)
	@$(SNAPSHOT_BIN) Tests/out/ui.png 1360 880 root 2.5
	@echo "==> 输出: Tests/out/ui.png"

## 剪贴板验证：把渲染结果写进系统剪贴板，检查 public.html 是否正确
copy-check: Sources/BuildInfo.swift
	@mkdir -p $(BUILD_DIR)
	@echo "==> 编译剪贴板验证工具"
	@$(SWIFTC) -disable-sandbox -swift-version 5 -O -parse-as-library \
		Sources/BuildInfo.swift $(UI_SOURCES) Tests/clipboard-check/CopyCheck.swift \
		-o $(COPY_BIN) $(FRAMEWORKS)
	@$(COPY_BIN) Tests/sample.md

## 生成应用图标（需要 python3 + Pillow，缺失时自动跳过）
icon:
	@python3 scripts/make-icon.py 2>/dev/null && echo "==> 图标已生成" || echo "==> 跳过图标（缺 Pillow）"

## 安装到 /Applications
install: build
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "==> 已安装到 /Applications/$(APP_NAME).app"

uninstall:
	@rm -rf /Applications/$(APP_NAME).app
	@echo "==> 已卸载"

## 打包为 zip 供分发
release: build
	@cd $(BUILD_DIR) && zip -qry $(APP_NAME)-$(VERSION).zip $(APP_NAME).app
	@echo "==> $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip"

info:
	@echo "版本    : $(VERSION)"
	@echo "Bundle  : $(BUNDLE_ID)"
	@echo "最低系统: macOS $(MIN_MACOS)"
	@echo "源码数  : $$(echo $(ALL_SOURCES) | wc -w | tr -d ' ')"

clean:
	@rm -rf $(BUILD_DIR) Tests/out Sources/BuildInfo.swift
	@echo "==> 已清理"
