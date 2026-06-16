#!/bin/bash
# Session Cove 一键安装脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/koersliven/Session-cove/main/scripts/quick-install.sh | bash

APP_NAME="Session Cove"
REPO="koersliven/Session-cove"
INSTALL_DIR="/Applications"

echo ""
echo "🏝  Session Cove 安装器"
echo "========================"
echo ""

# ── macOS 版本检查 ──
SW_VER=$(sw_vers -productVersion 2>/dev/null)
MAJOR=$(echo "$SW_VER" | cut -d. -f1)
if [ -z "$MAJOR" ] || [ "$MAJOR" -lt 14 ]; then
    echo "❌ 需要 macOS 14 (Sonoma) 或更高版本，当前: ${SW_VER:-未知}"
    exit 1
fi

# ── 获取最新 release（用 python3 解析 JSON，比 grep+sed 可靠） ──
echo "📡 正在获取最新版本..."
RELEASE_JSON=$(curl -sf "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null)

if [ -z "$RELEASE_JSON" ]; then
    echo "❌ 无法获取版本信息"
    echo ""
    echo "   可能原因："
    echo "   1. 网络连接问题 — 请检查是否能够访问 github.com"
    echo "   2. GitHub API 限流 — 企业网络出口 IP 可能被限制"
    echo ""
    echo "   手动安装：https://github.com/$REPO/releases/latest"
    exit 1
fi

# 尝试用 python3 解析（macOS 自带），失败则用 grep 降级
if command -v python3 &>/dev/null; then
    VERSION=$(echo "$RELEASE_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
t=d.get('tag_name','')
print(t.lstrip('v'))
" 2>/dev/null)
    DMG_URL=$(echo "$RELEASE_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for a in d.get('assets',[]):
    if a['name'].endswith('.dmg'):
        print(a['browser_download_url'])
        break
" 2>/dev/null)
else
    VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/')
    DMG_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep '\.dmg"' | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
fi

if [ -z "$VERSION" ] || [ -z "$DMG_URL" ]; then
    echo "❌ 解析版本信息失败"
    echo "   请手动安装：https://github.com/$REPO/releases/latest"
    exit 1
fi

echo "   最新版本: v$VERSION"
echo "   DMG: $DMG_URL"
echo ""

# ── 下载 DMG ──
TMP_DMG=$(mktemp -t session-cove-XXXXXX).dmg
echo "⬇️  正在下载 ($(echo "scale=1; $(curl -sI "$DMG_URL" | grep -i content-length | awk '{print $2}' | tr -d '\r') / 1048576" | bc 2>/dev/null || echo "?") MB)..."

HTTP_CODE=$(curl -fSL --progress-bar -w "%{http_code}" "$DMG_URL" -o "$TMP_DMG" 2>&1 | tail -1)

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ]; then
    echo ""
    echo "❌ 下载失败 (HTTP $HTTP_CODE)"
    echo "   请手动下载：https://github.com/$REPO/releases/latest"
    rm -f "$TMP_DMG"
    exit 1
fi
echo ""

# ── 关闭已运行的 Session Cove ──
if pgrep -q SessionCove 2>/dev/null; then
    echo "⏹  正在关闭当前运行的 Session Cove..."
    pkill -f "/Applications/Session Cove.app/" 2>/dev/null || true
    # 等进程退出，但最多等 5 秒
    for i in 1 2 3 4 5; do
        pgrep -q SessionCove 2>/dev/null || break
        sleep 1
    done
fi

# ── 挂载 DMG（用固定路径避免空格问题）──
echo "📦 正在安装..."

MOUNT_DIR="/tmp/session-cove-install-$$"
rm -rf "$MOUNT_DIR" 2>/dev/null
mkdir -p "$MOUNT_DIR"

ATTACH_OUT=$(hdiutil attach "$TMP_DMG" -nobrowse -mountpoint "$MOUNT_DIR" 2>&1)
ATTACH_EXIT=$?

if [ $ATTACH_EXIT -ne 0 ]; then
    echo "❌ DMG 挂载失败"
    echo "   $ATTACH_OUT"
    rm -f "$TMP_DMG"
    exit 1
fi

echo "   挂载点: $MOUNT_DIR"

# ── 复制到 /Applications ──
rm -rf "$INSTALL_DIR/$APP_NAME.app"

if ! cp -R "$MOUNT_DIR/$APP_NAME.app" "$INSTALL_DIR/"; then
    echo "❌ 复制到 /Applications 失败"
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null
    rm -f "$TMP_DMG"
    exit 1
fi

# ── 清除 quarantine + ad-hoc 签名 ──
xattr -cr "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
codesign --force --deep --sign - "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

# ── 卸载 DMG + 清理 ──
hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
rm -f "$TMP_DMG"

echo ""
echo "✅ Session Cove v$VERSION 安装成功！"
echo ""

# ── 启动 ──
echo "🚀 正在启动..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "   首次启动会自动配置 Claude Code 的 Hook。"
echo "   如果使用 iTerm2，请在弹窗中允许自动化权限。"
echo ""
echo "   🏝  享受你的像素港口吧！"
echo ""
