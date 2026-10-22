#!/bin/bash
#
# PixelFlow 接收端 · 一键安装到已连接的 iPhone
#
# 用法：
#   ./install-to-device.sh            # 自动选择唯一连线的 iPhone
#   ./install-to-device.sh <UDID>     # 指定设备
#
# 前置条件（两项都必须满足，脚本会先检查并给出提示）：
#   1. iPhone 已开启「开发者模式」：设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启 → 重启后确认
#   2. Xcode 已登录 Apple ID：Xcode → Settings → Accounts → 「+」→ Apple ID
#
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR" || exit 1

SCHEME="PixelFlowReceiver"
PROJECT="PixelFlowReceiver.xcodeproj"
BUNDLE_ID="com.pixelflow.receiver"
BUILD_DIR="build/device"

info() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m! %s\033[0m\n' "$1"; }
die()  {
    printf '\033[31m✗ %s\033[0m\n' "$1" >&2
    [ -n "${2:-}" ] && printf '\n%s\n' "$2" >&2
    exit 1
}

# ---------- 1. 找到设备 ----------
info "查找已连线的 iPhone…"
DEST_LIST="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
    | grep 'platform:iOS,' | grep -v Simulator | grep -v placeholder)"

[ -z "$DEST_LIST" ] && die "没有检测到已连接的 iPhone" \
"请检查：
  • 数据线已连接，iPhone 已解锁并点过「信任此电脑」
  • 打开 Xcode → Window → Devices and Simulators，确认左侧能看到设备"

if [ $# -ge 1 ]; then
    TARGET_UDID="$1"
    LINE="$(echo "$DEST_LIST" | grep "$TARGET_UDID")"
    [ -z "$LINE" ] && die "找不到 UDID 为 $TARGET_UDID 的设备"
else
    COUNT="$(echo "$DEST_LIST" | wc -l | tr -d ' ')"
    if [ "$COUNT" -gt 1 ]; then
        die "检测到多台设备，请指定 UDID" "$(echo "$DEST_LIST" | sed 's/^/  /')"
    fi
    LINE="$DEST_LIST"
fi

TARGET_UDID="$(echo "$LINE" | sed -E 's/.*id:([^,]+).*/\1/' | tr -d ' ')"
TARGET_NAME="$(echo "$LINE" | sed -E 's/.*name:[[:space:]]*([^}]*).*/\1/' | sed -E 's/[[:space:]]+$//')"
ok "设备：$TARGET_NAME ($TARGET_UDID)"

# ---------- 2. 开发者模式 ----------
info "检查开发者模式…"
DEV_INFO="$(xcrun devicectl device info details --device "$TARGET_UDID" 2>&1)"
if echo "$DEV_INFO" | grep -q "Developer Mode Status: Disabled"; then
    die "iPhone 的开发者模式未开启，安装会被系统直接拒绝" \
"在 iPhone 上操作（无法用命令代劳，必须手动点）：
  1. 设置 → 隐私与安全性 → 滑到最底部 → 开发者模式
  2. 打开开关，输入锁屏密码
  3. 系统会要求「重新启动」，重启后会出现确认弹窗，点「打开」
  4. 回到电脑重新运行本脚本"

elif echo "$DEV_INFO" | grep -q "Developer Mode is turned off"; then
    die "iPhone 的开发者模式未开启，安装会被系统直接拒绝" \
"在 iPhone 上操作：
  1. 设置 → 隐私与安全性 → 滑到最底部 → 开发者模式
  2. 打开开关 → 输入锁屏密码 → 重启 → 重启后确认「打开」
  3. 回到电脑重新运行本脚本"
fi
ok "开发者模式已开启"

# ---------- 3. 签名身份 ----------
info "查找 Apple 开发证书…"
IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E 'Apple Development|iPhone Developer' | head -1)"

if [ -z "$IDENTITY_LINE" ]; then
    die "本机没有 Apple 签发的开发证书，无法为 iOS 签名" \
"在 Xcode 里登录 Apple ID（免费账号即可）：
  1. 打开 Xcode → 菜单 Settings（⌘,）→ Accounts
  2. 点左下角「+」→ 选 Apple ID → 输入你的 Apple ID 和密码（需要两步验证）
  3. 登录后选中该账号，点右下角「Download Manual Profiles」可先不点
  4. 回到 Xcode 打开工程，选中 Target → Signing & Capabilities
     → Team 选择你的名字（Personal Team）→ 勾选 Automatically manage signing
  5. Xcode 会自动申请证书和描述文件（第一次会弹钥匙串授权，点「允许」）
  6. 完成后回到终端重新运行本脚本"
fi

TEAM_ID="$(echo "$IDENTITY_LINE" | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p')"
[ -z "$TEAM_ID" ] && die "无法从证书中解析 Team ID" "证书信息：$IDENTITY_LINE"
ok "签名身份：$(echo "$IDENTITY_LINE" | sed -E 's/^ *[0-9]+\) [A-F0-9]+ //')  Team=$TEAM_ID"

# ---------- 4. 编译 ----------
info "编译 Release 版本（首次会向 Apple 申请描述文件，可能稍慢）…"
rm -rf "$BUILD_DIR"

BUILD_LOG="$(mktemp)"
xcodebuild -project "$PROJECT" \
           -scheme "$SCHEME" \
           -configuration Release \
           -destination "platform=iOS,id=$TARGET_UDID" \
           -derivedDataPath "$BUILD_DIR" \
           -allowProvisioningUpdates \
           DEVELOPMENT_TEAM="$TEAM_ID" \
           CODE_SIGN_STYLE=Automatic \
           build > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?

APP_PATH="$BUILD_DIR/Build/Products/Release-iphoneos/$SCHEME.app"

if [ $BUILD_STATUS -ne 0 ] || [ ! -d "$APP_PATH" ]; then
    echo
    grep -E "error:|Signing for|No profiles|requires a development team" "$BUILD_LOG" | sort -u | head -12
    die "编译或签名失败" "完整日志：$BUILD_LOG"
fi
ok "编译完成：$APP_PATH"

# ---------- 5. 安装 ----------
info "安装到设备…"
if ! xcrun devicectl device install app --device "$TARGET_UDID" "$APP_PATH" 2>&1 | tee /tmp/pf_install.log | grep -qiE "installed|Installing"; then
    if ! grep -qi "installed" /tmp/pf_install.log; then
        die "安装失败" "$(tail -5 /tmp/pf_install.log)"
    fi
fi
ok "安装成功"

# ---------- 6. 启动 ----------
info "启动 App…"
if xcrun devicectl device process launch --device "$TARGET_UDID" "$BUNDLE_ID" >/dev/null 2>&1; then
    ok "已启动，看手机屏幕"
else
    warn "已安装但自动启动失败，请在手机上手动点开 PixelFlow"
fi

printf '\n'
ok "全部完成"
printf '\033[2m提示：免费 Apple ID 签名的有效期是 7 天，到期后 App 打不开，重新运行本脚本即可续期。\033[0m\n'
