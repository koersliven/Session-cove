#!/bin/bash
set -e

# Session Cove 一键安装脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/koersliven/Session-cove/main/scripts/quick-install.sh | bash

APP_NAME="Session Cove"
REPO="koersliven/Session-cove"
INSTALL_DIR="/Applications"

echo ""
echo "🏝  Session Cove 安装器"
echo "========================"
echo ""

# 检查 macOS 版本
SW_VER=$(sw_vers -productVersion)
MAJOR=$(echo "$SW_VER" | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then
    echo "❌ 需要 macOS 14 (Sonoma) 或更高版本，当前: $SW_VER"
    exit 1
fi

# 获取最新 release 信息
echo "📡 正在获取最新版本..."
RELEASE_JSON=$(curl -sf "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null)
if [ -z "$RELEASE_JSON" ]; then
    echo "❌ 无法连接 GitHub，请检查网络"
    exit 1
fi

VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/')
DMG_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep '\.dmg"' | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')

if [ -z "$DMG_URL" ]; then
    echo "❌ 未找到 DMG 下载地址，请手动安装："
    echo "   https://github.com/$REPO/releases/latest"
    exit 1
fi

echo "   最新版本: v$VERSION"
echo ""

# 下载 DMG
TMP_DMG=$(mktemp -t session-cove-XXXXXX).dmg
echo "⬇️  正在下载 DMG..."
curl -fSL --progress-bar "$DMG_URL" -o "$TMP_DMG"
echo ""

# 关闭已运行的 Session Cove
if pgrep -f "SessionCove" > /dev/null 2>&1; then
    echo "⏹  正在关闭当前运行的 Session Cove..."
    pkill -f "SessionCove" 2>/dev/null || true
    sleep 1
fi

# 挂载 DMG
echo "📦 正在安装..."
MOUNT_DIR=$(hdiutil attach "$TMP_DMG" -nobrowse -mountrandom /tmp 2>/dev/null | tail -1 | awk '{print $NF}')
if [ -z "$MOUNT_DIR" ]; then
    echo "❌ DMG 挂载失败"
    rm -f "$TMP_DMG"
    exit 1
fi

# 复制到 /Applications
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$MOUNT_DIR/$APP_NAME.app" "$INSTALL_DIR/"

# 清除 quarantine + ad-hoc 签名
xattr -cr "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null
codesign --force --deep --sign - "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null

# 卸载 DMG + 清理
hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null
rm -f "$TMP_DMG"

echo ""
echo "✅ Session Cove v$VERSION 安装成功！"
echo ""
echo "   位置: $INSTALL_DIR/$APP_NAME.app"
echo ""

# 启动
echo "🚀 正在启动..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "   首次启动会自动配置 Claude Code 的 Hook。"
echo "   如果使用 iTerm2，请在弹窗中允许自动化权限。"
echo ""
echo "   享受你的像素港口吧！🏝"
echo ""
