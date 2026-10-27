# PixelFlow

通过二维码在设备之间传输文件或文本的工具。**纯本地、不经过任何服务器**，适合无网络、air-gap、或不想登录账号的场景。

- **发送端**：网页（任意现代浏览器，电脑上使用）
- **接收端**：iOS 原生 App（推荐）或网页版（仅限 localhost / HTTPS）

---

## 文件结构

```
PixelFlow/
├── send.html               # 发送端（多码阵列）
├── index.html              # 接收端 · 网页版
├── qrcode.min.js           # 二维码生成（node-qrcode 浏览器构建）
├── sha256.js               # SHA-256（纯 JS，两端共用）
├── html5-qrcode.min.js     # 网页版扫码（本地化，无需联网）
└── PixelFlowReceiver/      # 接收端 · iOS 原生 App
    ├── PixelFlowReceiver.xcodeproj
    ├── install-to-device.sh           # 一键编译 + 安装 + 启动
    └── PixelFlowReceiver/
        ├── PixelFlowApp.swift
        ├── Protocol/PF2Frame.swift       # 协议解析
        ├── Protocol/TransferStore.swift  # 分片累积、校验、状态机
        ├── Camera/CameraController.swift # 多码识别
        ├── Camera/CameraPreview.swift    # 预览与识别框
        └── Views/                        # 界面与导出
```

## 快速开始

### 1. 发送端

直接用浏览器打开 `send.html`（发送端不需要摄像头，file:// 即可）。

1. 选择「文件传输」或「纯文字传输」
2. 选择码阵规模：`1×1` / `2×2`（默认）
3. 点「自动播放」，让手机对准屏幕

键盘快捷键（焦点不在输入框时）：

| 按键 | 作用 |
| --- | --- |
| `数字` + `字母/回车` | 直接跳到指定片（如敲 `12`，再按任意字母键或回车立即跳）；不按就等 2 秒自动跳 |
| `0` | 回到元信息步（第一步） |
| `Esc` | 取消正在输入的片号 |
| `←` / `→` | 上一步 / 下一步 |
| `空格` | 播放 / 暂停 |
| `Home` | 回到第一步 |

跳片提示会浮在页面顶部，不会遮住二维码。片号超出范围时会提示「没有第 N 片」并保持原步不动。

### 2. 接收端 · iOS App

需要 macOS + Xcode 26 以上，iPhone 系统 iOS 17+。**Xcode 版本不能低于手机的 iOS 版本**——本项目在 Xcode 27.1 / macOS 27.0.1 / iOS 27.2 上验证，低于这个组合的机器见下面的「换一台 Mac 编译安装」。

**前置条件**（这两步必须在手机和账号侧完成，命令行无法代劳）

1. **开启开发者模式**：iPhone → 设置 → 隐私与安全性 → 滚到最底部 → 开发者模式 → 打开 → 输入锁屏密码 → 重启 → 重启后确认「打开」
2. **Xcode 登录 Apple ID**：Xcode → 菜单 Settings（⌘,）→ Accounts → 左下角「+」→ Apple ID（免费账号即可，需要两步验证）

**方式 A · 一键安装（推荐）**

```bash
cd PixelFlowReceiver
./install-to-device.sh
```

脚本会依次检查：设备是否连线 → 开发者模式是否开启 → 是否有 Apple 开发证书 → 编译 → 安装 → 启动。任一前置条件不满足，它会直接告诉你该去哪里点什么，而不是抛一堆编译错误。

**首次运行：必须先在手机上信任开发者证书**

装完第一次点开 App，iOS 会拦一下，弹「**不受信任的开发者** —— 你的设备管理设置不允许在这台 iPhone 上使用开发者 “Apple Development: xxx@qq.com (XXXXXXXXXX)” 的 App」。这不是打包出错，App 已经装好了，只是这台手机还没信任过你的证书：

1. iPhone → **设置 → 通用 → VPN 与设备管理**（⚠️ 不是「隐私与安全性 → 开发者」，那个页面里没有这个入口）
2. 在「**开发者 App**」分组下点 `Apple Development: 你的邮箱` 那一行
3. 点「**信任**」→ 弹窗里再点一次「**信任**」
4. 回桌面点开 PixelFlow

信任只需做一次；证书在 7 天内重新安装（续期）不需要再信任。若「VPN 与设备管理」里看不到「开发者 App」分组：确认进入的是「通用」下的那个入口，或拔线重插 / 重启手机后再进一次——系统要联网校验证书后才会显示该分组。

**方式 B · 用 Xcode 图形界面**

```bash
open PixelFlowReceiver/PixelFlowReceiver.xcodeproj
```

1. 选中项目 → **Signing & Capabilities** → **Team** 选择你的 Apple ID（Personal Team）
2. 如提示 Bundle ID 冲突，改成唯一的，例如 `com.你的名字.pixelflow`
3. 顶部选择你的 iPhone，按 **⌘R**
4. 首次运行后，在 iPhone **设置 → 通用 → VPN与设备管理** 里信任你的开发者证书

> 免费 Apple ID 签名的 App **7 天后过期**，到期后重新运行安装脚本（或按一次 ⌘R）即可续期。

**换一台 Mac 编译安装**

代码里没有绑死本机路径，任何 macOS + Xcode 机器都能编。但要先确认新机器够格：

| 项目 | 要求 |
| --- | --- |
| 芯片 | **Apple silicon**。Xcode 27 起只支持 Apple silicon；Intel Mac 最高装到 Xcode 26.x |
| 系统 | 装 Xcode 27 需要 **macOS Tahoe 26.6+**；只装 Xcode 26.0–26.3 需要 macOS 15.6+（26.4 起要求 macOS 26.2+） |
| Xcode | **不能低于手机系统**。手机是 iOS 27 就必须 Xcode 27；手机还是 iOS 26，Xcode 26 也能用 |

手机版本在「设置 → 通用 → 关于本机 → iOS 版本」看。Xcode 版本比手机旧时，真机会连不上（提示设备系统不受支持），这一步没法绕。

新机器只需补齐四件事，**不要**直接搬 `build/`（80 MB 的本机编译产物，里面是上一台机器的签名结果，搬过去也用不上）。

1. **拷项目**：有远端就 `git clone <url>`；没有就在旧机器上
   `rsync -av --exclude build --exclude .git ./ 用户名@新Mac.local:~/PixelFlow/`
2. **装 Xcode 并接受许可**
   ```bash
   xcode-select --install                       # 命令行工具，脚本依赖 /usr/bin/python3
   sudo xcode-select -s /Applications/Xcode.app # 不指向 Xcode.app，xcodebuild 会直接报错
   sudo xcodebuild -license accept              # 新装 Xcode 未接受许可时任何构建都会失败
   xcodebuild -version                          # 能打印版本号即可
   ```
3. **在这台 Mac 上登录同一个 Apple ID**：Xcode → Settings（⌘,）→ Accounts → 「+」→ Apple ID。
   **证书不跟着项目文件走**，必须在这台机器上生成一次：打开工程按一次 **⌘B**，Xcode 会自动申请 Apple Development 证书和描述文件。手机侧的「开发者模式」是设备级的，不用重开；但新 Mac 第一次插线时，手机上要允许「信任此电脑」。
4. **跑脚本**：`cd PixelFlowReceiver && ./install-to-device.sh`（第 0 步会自检 Xcode 版本、许可、`xcode-select` 路径和 python3，缺什么直接告诉你）
   钥匙串里有多张开发证书（多个 Apple ID）时，脚本默认取第一张，可能签成别人的 Team；用 `PF_IDENTITY=邮箱 PF_TEAM=TeamID ./install-to-device.sh` 明确指定。

签名证书换新了要不要重新信任？同一 Apple ID 在新 Mac 上会生成一张**新的** Apple Development 证书。同一台 iPhone 覆盖安装一般能直接打开；若又弹「不受信任的开发者」，再点一次「信任」即可（「开发者 App」里可能出现同名两项，都信任即可）。

想彻底避免：在旧 Mac 上打开「钥匙串访问」→ 找到 `Apple Development: 你的邮箱` → 右键「导出」存成 `.p12`（设置密码）→ 拷到新 Mac 双击导入，两台机器就用同一张证书签名了。

覆盖安装报 `ApplicationVerificationFailed` 时，先在手机上删掉旧 PixelFlow 再装，或按上面的方式统一证书。新 Mac 首次连真机需要联网下载 Developer Disk Image，会多等几分钟，属正常。

**遇到 `SwiftUIMacros.StateMacro ... produced malformed response`**

这不是代码问题，是本机 `sandbox-exec` 无法应用沙箱策略，导致 Swift 宏插件服务启动失败（Apple Silicon + 新版 macOS 上偶发）。工程里已用 `OTHER_SWIFT_FLAGS = $(inherited) -disable-sandbox` 规避。若你拿到的是不含该设置的工程副本，在 Target → Build Settings → **Other Swift Flags** 手动加一项 `-disable-sandbox` 即可。

**接收完成后**

收满全部帧会自动校验 SHA-256 并弹出结果页：

- 文件：**存储到「文件」**（直接唤起系统文稿选择器）或 **分享…**（系统分享面板，含隔空投送、拷贝到其他 App）
- 文本：**复制** 或 **分享文本**

两个导出入口都通过 UIKit 直接 present（`UIActivityViewController` / `UIDocumentPickerViewController`）。系统分享面板不能在 SwiftUI 的 `.sheet` 里以子控制器方式承载，否则只会渲染出一个灰色空窗口。

### 3. 接收端 · 网页版（备选）

浏览器只在**安全上下文**下才授予摄像头权限，因此：

```bash
cd PixelFlow
python3 -m http.server 8000
# 然后访问 http://localhost:8000/index.html
```

`file://` 打开、或通过局域网 IP + http 访问，**摄像头都会被拒绝**。手机上基本只有原生 App 这一条路——这正是做原生接收端的原因。

---

## 传输协议 PF2

自定义文本协议，`|` 分隔。

| 帧类型 | 格式 |
| --- | --- |
| 元信息 | `PF2\|M\|<kind>\|<total>\|<chunkSize>\|<b64len>\|<sha256>\|<grid>\|<name>` |
| 数据 | `PF2\|D\|<idx>\|<payload>` |

| 字段 | 含义 |
| --- | --- |
| `kind` | `f` 文件 / `t` 文本 |
| `total` | 数据分片总数 |
| `chunkSize` | 每片字符数 |
| `b64len` | 完整 base64 字符串长度 |
| `sha256` | 原始字节的 SHA-256（64 位十六进制），`-` 表示不校验 |
| `grid` | 码阵规模 K（1 / 4） |
| `name` | 文件名，**恒为最后一个字段** |

设计要点：

- **分隔符安全**：数据载荷是 base64（`A-Za-z0-9+/=`），与 `|` 无交集；文件名放在最后，解析时用「剩余字段重组」取回，所以文件名里即使有 `|` 也不会破坏协议。
- **完整性校验**：接收端重组后先比对 `b64len`，再算 SHA-256 与元信息比对，坏数据会被明确拦下，而不是静默产出损坏文件。
- **分片参数写入元信息**：中途改分片大小不会导致新旧分片错位拼接。
- **多码阵列**：多码模式下元信息码（<strong>M</strong>）固定占左上角格位，每一步都重复播一次——接收端随时能重新同步，手机中途对准也能接上；其余格位装数据码（2×2 每步 3 个数据码）。
- **末步补满**：最后一步通常只剩 2 片，会空出半屏白。相机对「画面突然变亮」最敏感（自动曝光会把这一帧压暗），而这一步一轮只出现一次，于是尾片成了最容易漏的码。现在末尾空格会用整轮最后几片补齐（左上角的 <strong>M</strong> 不动），末步还会多停 2.2 倍时间（默认 200 ms → 440 ms）。所以最后一步看到同一个码重复出现是正常现象。
- **断点语义**：接收端检测到不同 `sha256` 会提示并自动切换到新传输，无需手动重置。

## 性能

净吞吐 ≈ `(K−1) × chunkSize × 0.75 ÷ 停留时间`（左上角一格被元信息码占用；K=1 时不成阵列，按 1 码算；末步多停 2.2 倍，摊到整轮约 −3%）。以下是估算值（实际通常能达到理论的 70–85%）：

| 配置 | 净吞吐 | 100 KB | 1 MB |
| --- | --- | --- | --- |
| 1×1 · 700 B · 200 ms | ~2.6 KB/s | ~39 s | ~6.6 min |
| 2×2 · 700 B · 200 ms（默认） | ~7.6 KB/s | ~13 s | ~2.3 min |
| 2×2 · 700 B · 400 ms（求稳） | ~3.8 KB/s | ~26 s | ~4.5 min |

旧版是单码 + 300 ms，理论与实际都在 0.3–1.2 KB/s 量级，这就是「手机上感觉特别慢」的根因。

调参建议：

- 屏幕离手机 **15–25 cm**，屏幕亮度拉满，避免反光
- 手机端可上下滑动变焦放大
- 「每步停留」滑到 200 ms 以下（最短 50 ms）时，多数手机来不及在一步内解出 4 个码，缺片反而更多；距离远或光线差时调回 300–600 ms 更稳
- 码阵从 2×2 换到 1×1，每格更大、更好解，但吞吐降到三分之一
- 分片太多时，接收端会显示「还缺哪几片」，在发送端点击对应数字即可定点补发

## 依赖

| 库 | 用途 | 许可 |
| --- | --- | --- |
| [node-qrcode](https://github.com/soldair/node-qrcode) | 二维码生成 | MIT |
| [html5-qrcode](https://github.com/mebjas/html5-qrcode) | 网页版扫码 | Apache-2.0 |

iOS 端只使用系统框架（AVFoundation / Vision 无关，扫码走 `AVCaptureMetadataOutput`），无第三方依赖。

## 许可证

MIT
