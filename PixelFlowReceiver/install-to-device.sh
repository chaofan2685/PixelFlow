#!/bin/bash
#
# PixelFlow 接收端 · 一键安装到已连接的 iPhone
#
# 用法：
#   ./install-to-device.sh                 # 自动选择唯一连线的 iPhone
#   ./install-to-device.sh <UDID>          # 指定设备
#   ./install-to-device.sh --list          # 只列出可用设备
#
# 前置条件：
#   1. iPhone 已开启「开发者模式」：设置 → 隐私与安全性 → 开发者模式
#   2. Xcode 里登录过 Apple ID，且本机已有 Apple Development 证书
#      （Xcode → Settings → Accounts；证书可在 钥匙串访问 → 我的证书 中看到）
#
# 说明：编译用 generic/platform=iOS，不依赖手机在线；安装阶段才需要手机解锁并连上。
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

UNLOCK_HINT="在 iPhone 上操作：
  1. 按一下侧边按钮点亮屏幕，上滑解锁（保持亮屏，别让它自动锁屏）
  2. 如果手机弹出「信任此电脑 / 允许访问照片…」一律点允许
  3. 回到电脑重新运行本脚本
（安装阶段必须解锁：iOS 只有在解锁状态才允许挂载开发者磁盘镜像）"

# ---------- 0. 环境自检 ----------
for tool in xcodebuild xcrun security openssl; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少命令：$tool" "请先安装 Xcode（App Store）并执行：sudo xcode-select -s /Applications/Xcode.app"
done
[ -d "$PROJECT" ] || die "找不到工程文件：$PROJECT" "请在 $PROJECT_DIR 下运行本脚本"

# ---------- 1. 找设备 ----------
info "查找已连线的 iPhone…"

WANT_UDID=""
if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
    LIST_ONLY=1
else
    LIST_ONLY=0
    [ $# -ge 1 ] && WANT_UDID="$1"
fi

DEV_JSON="$(mktemp -t pfdev)"
xcrun devicectl list devices --json-output "$DEV_JSON" >/dev/null 2>&1

# 输出：每行 "UDID<TAB>名称<TAB>隧道状态<TAB>配对状态"
# 注意：锁屏时 tunnelState 会掉成 disconnected，但设备仍然是「配对可用」的，
# 所以不能用隧道状态当作「设备不存在」的判据。
DEV_ROWS="$(/usr/bin/python3 - "$DEV_JSON" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for d in data.get('result', {}).get('devices', []):
    hw = d.get('hardwareProperties') or {}
    cn = d.get('connectionProperties') or {}
    dp = d.get('deviceProperties') or {}
    if hw.get('reality') != 'physical':
        continue
    if hw.get('platform') != 'iOS':
        continue
    udid = hw.get('udid') or ''
    if not udid:
        continue
    name = dp.get('name') or hw.get('marketingName') or udid
    state = cn.get('tunnelState') or 'disconnected'
    pairing = cn.get('pairingState') or 'unknown'
    print('\t'.join([udid, name, state, pairing]))
PY
)"

if [ -z "$DEV_ROWS" ]; then
    # 兜底：老路子，等设备被 xcodebuild 识别
    DEST_LIST="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
        | grep 'platform:iOS,' | grep -v Simulator | grep -v placeholder || true)"
    if [ -n "$DEST_LIST" ]; then
        DEV_ROWS="$(echo "$DEST_LIST" | sed -E 's/.*id:([^,]+),[[:space:]]*name:([^,}]+).*/\1\t\2\tconnected\tpaired/')"
    fi
fi

if [ -z "$DEV_ROWS" ]; then
    die "没有检测到已连接的 iPhone" "请检查：
  • 数据线已连接，iPhone 已解锁并点过「信任此电脑」
  • 打开 Xcode → Window → Devices and Simulators，确认左侧能看到设备
  • 换一根能传数据的线（有些线只能充电）"
fi

if [ "$LIST_ONLY" -eq 1 ]; then
    printf '%s\n' "$DEV_ROWS" | awk -F'\t' '{printf "  %-42s %-26s %s\n", $1, $2, ($3=="connected" ? "已连接" : "已配对（未连接，可能锁屏）")}'
    exit 0
fi

if [ -n "$WANT_UDID" ]; then
    LINE="$(printf '%s\n' "$DEV_ROWS" | awk -F'\t' -v u="$WANT_UDID" '$1==u || $2==u' | head -1)"
    [ -z "$LINE" ] && die "找不到 UDID 为 $WANT_UDID 的设备" "当前可用：
$(printf '%s\n' "$DEV_ROWS" | awk -F'\t' '{printf "  %s  %s\n", $1, $2}')"
else
    COUNT="$(printf '%s\n' "$DEV_ROWS" | wc -l | tr -d ' ')"
    if [ "$COUNT" -gt 1 ]; then
        # 多台时优先唯一「已连接」的那台
        LINE="$(printf '%s\n' "$DEV_ROWS" | awk -F'\t' '$3=="connected"')"
        COUNT_READY="$(printf '%s\n' "$LINE" | grep -c . || true)"
        if [ "$COUNT_READY" -ne 1 ]; then
            die "检测到多台设备，请指定 UDID" "$(printf '%s\n' "$DEV_ROWS" | awk -F'\t' '{printf "  %s  %s（%s）\n", $1, $2, $3}')"
        fi
    else
        LINE="$DEV_ROWS"
    fi
fi

TARGET_UDID="$(printf '%s' "$LINE" | cut -f1)"
TARGET_NAME="$(printf '%s' "$LINE" | cut -f2)"
TARGET_STATE="$(printf '%s' "$LINE" | cut -f3)"

# 隧道是按需建立的：锁屏时这里显示 disconnected，但解锁后安装仍会成功，
# 所以不把它当错误，真正的判据是下面的「开发者镜像是否就绪」。
ok "设备：$TARGET_NAME ($TARGET_UDID)"
if [ "$TARGET_STATE" != "connected" ]; then
    printf '\033[2m  （隧道暂时未建立，锁屏状态下正常；安装前解锁即可）\033[0m\n'
fi

# ---------- 2. 设备状态（开发者模式 / 开发者镜像） ----------
read_device_flags() {
    local dst="$1" json
    json="$(mktemp -t pfdet)"
    xcrun devicectl device info details --device "$dst" --json-output "$json" >/dev/null 2>&1
    /usr/bin/python3 - "$json" <<'PY' 2>/dev/null
import json, sys
try:
    r = json.load(open(sys.argv[1])).get('result', {})
except Exception:
    print('unknown unknown')
    sys.exit(0)
dp = r.get('deviceProperties') or {}
dm = str(dp.get('developerModeStatus') or 'unknown').lower()
ddi = dp.get('ddiServicesAvailable')
print(dm, 'yes' if ddi else 'no')
PY
    rm -f "$json"
}

info "检查开发者模式与开发者镜像…"
read -r DEV_MODE DDI_READY <<<"$(read_device_flags "$TARGET_UDID")"

if [ "$DEV_MODE" = "disabled" ]; then
    die "iPhone 的开发者模式未开启，安装会被系统直接拒绝" "在 iPhone 上操作（无法用命令代劳）：
  1. 设置 → 隐私与安全性 → 滑到最底部 → 开发者模式
  2. 打开开关，输入锁屏密码
  3. 系统会要求「重新启动」，重启后会出现确认弹窗，点「打开」
  4. 回到电脑重新运行本脚本"
fi
ok "开发者模式已开启"

if [ "$DDI_READY" != "yes" ]; then
    warn "手机当前是锁屏状态（开发者镜像未挂载），编译会照常进行，安装前请解锁"
fi

# ---------- 3. 签名身份与 Team ID ----------
info "查找 Apple 开发证书…"
IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E 'Apple Development|iPhone Developer' | head -1)"

if [ -z "$IDENTITY_LINE" ]; then
    die "本机没有 Apple 签发的开发证书，无法为 iOS 签名" "在 Xcode 里登录 Apple ID（免费账号即可）：
  1. 打开 Xcode → 菜单 Settings（⌘,）→ Accounts
  2. 点左下角「+」→ 选 Apple ID → 输入账号密码（需要两步验证）
  3. 打开工程，选中 Target → Signing & Capabilities
     → Team 选你的名字（Personal Team）→ 勾选 Automatically manage signing
  4. 让 Xcode 编译一次（⌘B），它会自动申请证书和描述文件
  5. 完成后回到终端重新运行本脚本"
fi

IDENTITY_NAME="$(printf '%s' "$IDENTITY_LINE" | sed -E 's/^ *[0-9]+\) [A-F0-9]+ //; s/^"//; s/"$//')"

# Team ID 必须以证书的 OU 字段为准。
# 证书 CN 括号里那串（如 "... (HYCYFDH9W3)"）可能是 App ID 前缀，和 Team ID 不是一回事；
# 早先按括号解析会把 DEVELOPMENT_TEAM 传错，Xcode 于是报「No Accounts / No profiles」。
team_from_cert() {
    local name="$1" pem
    pem="$(security find-certificate -c "$name" -p 2>/dev/null)" || return 0
    [ -z "$pem" ] && return 0
    printf '%s' "$pem" | openssl x509 -noout -subject 2>/dev/null \
        | sed -nE 's/.*OU=([A-Z0-9]{10}).*/\1/p' | head -1
}

TEAM_ID="$(team_from_cert "$IDENTITY_NAME")"
if [ -z "$TEAM_ID" ]; then
    TEAM_ID="$(team_from_cert "Apple Development")"
fi
if [ -z "$TEAM_ID" ]; then
    warn "无法从证书解析 Team ID，尝试改用括号内的值"
    TEAM_ID="$(printf '%s' "$IDENTITY_NAME" | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p')"
fi
[ -z "$TEAM_ID" ] && die "无法确定 Team ID" "证书信息：$IDENTITY_LINE"

ok "签名身份：$IDENTITY_NAME"
ok "Team：$TEAM_ID"

# 工程里若写死了另一个 Team，命令行参数会覆盖它，这里只做提示
PBX_TEAM="$(grep -m1 -E 'DEVELOPMENT_TEAM' "$PROJECT/project.pbxproj" 2>/dev/null | sed -E 's/.*= *([A-Z0-9]+);.*/\1/')"
if [ -n "$PBX_TEAM" ] && [ "$PBX_TEAM" != "$TEAM_ID" ]; then
    warn "工程里写的 Team 是 ${PBX_TEAM}，本次按证书的 ${TEAM_ID} 编译"
fi

# ---------- 4. 编译 ----------
info "编译 Release 版本…"
# 不清空 derivedData：增量编译快得多（几秒），也避免批量删除的噪音
BUILD_LOG="$(mktemp -t pfbuild)"

# 用 generic/platform=iOS：编译阶段完全不依赖手机是否在线/解锁，
# 也就不会出现「Timed out waiting for all destinations」这种超时失败。
build_generic() {
    xcodebuild -project "$PROJECT" \
               -scheme "$SCHEME" \
               -configuration Release \
               -destination "generic/platform=iOS" \
               -derivedDataPath "$BUILD_DIR" \
               -allowProvisioningUpdates \
               DEVELOPMENT_TEAM="$TEAM_ID" \
               CODE_SIGN_STYLE=Automatic \
               build > "$BUILD_LOG" 2>&1
}

APP_PATH="$BUILD_DIR/Build/Products/Release-iphoneos/$SCHEME.app"

# 描述文件里是否含这台设备（免费账号的描述文件只列已注册设备）
profile_has_device() {
    [ -f "$APP_PATH/embedded.mobileprovision" ] || return 1
    security cms -D -i "$APP_PATH/embedded.mobileprovision" 2>/dev/null | grep -q "$TARGET_UDID"
}

if ! build_generic || [ ! -d "$APP_PATH" ]; then
    echo
    grep -E "error:" "$BUILD_LOG" | sed -E 's/^.*error: /  /' | sort -u | head -8
    if grep -q "No Accounts" "$BUILD_LOG"; then
        die "Xcode 里没有登录 Apple ID，无法自动管理签名" "打开 Xcode → Settings → Accounts → 「+」登录 Apple ID，然后重跑本脚本。"
    fi
    if grep -qE "No profiles for|requires a development team" "$BUILD_LOG"; then
        die "找不到可用的描述文件" "在 Xcode 里打开工程编译一次（⌘B），让它自动生成描述文件，然后重跑本脚本。"
    fi
    die "编译失败" "完整日志：$BUILD_LOG"
fi
ok "编译完成：$APP_PATH"

# 设备没在描述文件里时，用设备目标再编一次，让 Xcode 把它注册进去
if ! profile_has_device; then
    warn "描述文件里没有这台设备，尝试让 Xcode 注册后再编一次…"
    if [ "$DDI_READY" != "yes" ]; then
        die "无法把设备注册进描述文件：手机处于锁屏状态" "$UNLOCK_HINT"
    fi
    xcodebuild -project "$PROJECT" \
               -scheme "$SCHEME" \
               -configuration Release \
               -destination "platform=iOS,id=$TARGET_UDID" \
               -destination-timeout 90 \
               -derivedDataPath "$BUILD_DIR" \
               -allowProvisioningUpdates \
               DEVELOPMENT_TEAM="$TEAM_ID" \
               CODE_SIGN_STYLE=Automatic \
               build > "$BUILD_LOG" 2>&1 || true
    if ! profile_has_device; then
        grep -E "error:" "$BUILD_LOG" | sed -E 's/^.*error: /  /' | sort -u | head -8
        die "这台 iPhone 不在描述文件的设备列表里" "免费 Apple ID 最多注册有限台设备。请在 Xcode 里打开工程 →
  Target → Signing & Capabilities → 确认 Team 后让 Xcode 编译一次（⌘B），
  或在 Devices and Simulators 里确认设备可用，然后重跑本脚本。
完整日志：$BUILD_LOG"
    fi
fi

# ---------- 5. 安装 ----------
info "安装到设备…"

INSTALL_LOG="$(mktemp -t pfinstall)"
if ! xcrun devicectl device install app --device "$TARGET_UDID" "$APP_PATH" > "$INSTALL_LOG" 2>&1; then
    if grep -qE "10003|still locked|The device is currently locked" "$INSTALL_LOG"; then
        die "iPhone 处于锁屏状态，iOS 不允许安装" "$UNLOCK_HINT"
    fi
    if grep -qE "10002|12040|developer disk image" "$INSTALL_LOG"; then
        die "开发者镜像挂载失败" "先解锁手机并保持亮屏，再重跑本脚本。
$(tail -3 "$INSTALL_LOG")"
    fi
    if grep -qiE "MismatchedApplicationIdentifierEntitlement|does not include|not authorized|profile" "$INSTALL_LOG"; then
        die "描述文件与设备/签名不匹配" "$(tail -6 "$INSTALL_LOG")"
    fi
    die "安装失败" "$(tail -8 "$INSTALL_LOG")"
fi
ok "安装成功"

# ---------- 6. 启动 ----------
# 免费 Apple ID 签名的 App 首次安装一定会被系统拦一次：
#   "Unable to launch ... its profile has not been explicitly trusted by the user"
# 这不是打包问题 —— App 已经装好了，只是这台 iPhone 还没信任开发者证书。
# 信任只能在手机上点，苹果没有开放命令行接口，所以这里把步骤讲清楚并支持重试。
print_trust_guide() {
    cat <<EOF

  在 iPhone 上花 10 秒完成（只需一次，以后续期不用再做）：
    1. 设置 → 通用 → VPN 与设备管理
    2. 在「开发者 App」里点这一行：${IDENTITY_NAME}
    3. 点「信任」→ 弹窗里再点一次「信任」
    4. 回桌面点开 PixelFlow

  看不到「开发者 App」分组？
    • 确认「设置 → 通用 → VPN 与设备管理」这个入口（不是「隐私与安全性 → 开发者」）
    • 拔线重插或重启手机后再进一次，系统要联网校验证书才会显示该分组

EOF
}

is_trust_error() {
    grep -qiE "explicitly trusted|not trusted|invalid code signature|inadequate entitlements" "$1"
}

info "启动 App…"
LAUNCH_LOG="$(mktemp -t pflaunch)"
launch_app() {
    xcrun devicectl device process launch \
        --device "$TARGET_UDID" \
        --terminate-existing \
        "$BUNDLE_ID" > "$LAUNCH_LOG" 2>&1
}

TRUSTED=0
if launch_app; then
    TRUSTED=1
    ok "已启动，看手机屏幕"
elif is_trust_error "$LAUNCH_LOG"; then
    warn "App 已装好，但这台 iPhone 还没信任该开发者证书 —— 这是 iOS 的安全门槛，不是安装失败"
    printf '\n  设置 → 通用 → VPN 与设备管理 → 开发者 App → 点「%s」→ 信任（弹窗里再点一次信任）\n' "$IDENTITY_NAME"
    # 交互式终端下等用户点完再重试；非交互（CI / 管道）直接给出结论
    if [ -t 0 ]; then
        for attempt in 1 2 3; do
            printf '\033[36m▸ 点完「信任」后按回车，我再启动一次（第 %s/3 次，Ctrl-C 可跳过）\033[0m' "$attempt"
            read -r REPLY_INPUT || break
            if launch_app; then
                TRUSTED=1
                ok "启动成功"
                break
            fi
            if is_trust_error "$LAUNCH_LOG"; then
                warn "还是未信任状态，检查一下是不是点漏了第 3 步的弹窗"
            else
                warn "启动仍未成功，可以手动点开 App"
                tail -2 "$LAUNCH_LOG" | sed 's/^/  /'
                break
            fi
        done
    fi
else
    warn "已安装但自动启动失败，请在手机上手动点开 PixelFlow"
    tail -2 "$LAUNCH_LOG" | sed 's/^/  /'
fi

printf '\n'
if [ "$TRUSTED" -eq 1 ]; then
    ok "全部完成"
else
    warn "安装完成 · 还差手机上「信任」这一步（做完就能用了）"
    print_trust_guide
fi
printf '\033[2m提示：免费 Apple ID 签名的有效期是 7 天，到期后 App 打不开，重新运行本脚本即可续期（续期不需要重新信任证书）。\033[0m\n'
