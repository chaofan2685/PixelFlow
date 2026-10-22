import SwiftUI
import AVFoundation
import Combine
import UIKit

struct ScannerView: View {

    @StateObject private var store = TransferStore()
    @StateObject private var camera = CameraController()

    @State private var rects: [CGRect] = []
    @State private var missing: [Int] = []
    @State private var baseZoom: CGFloat = 1
    @State private var showDebugPanel = false
    @State private var debugText = ""
    @State private var demoMode = false

    private let ticker = Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isRunning {
                CameraPreview(session: camera.session, rects: rects)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            scrims

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                panel
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .animation(.easeInOut(duration: 0.22), value: camera.isRunning)
        .statusBarHidden(false)
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    camera.setZoom(baseZoom * value.magnification)
                }
                .onEnded { value in
                    baseZoom = min(6, max(1, baseZoom * value.magnification))
                    camera.setZoom(baseZoom)
                }
        )
        .onAppear(perform: bootstrap)
        .onDisappear {
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: store.phase) { _, newPhase in
            switch newPhase {
            case .complete:
                camera.stop()
                UIApplication.shared.isIdleTimerDisabled = false
            case .waitingMeta, .receiving:
                UIApplication.shared.isIdleTimerDisabled = true
                if !demoMode && !camera.isRunning { camera.start() }
            case .failed:
                break
            }
        }
        .onReceive(ticker) { _ in
            refreshMissing()
        }
        .sheet(item: $store.result) { result in
            ResultSheet(result: result) { store.dismissResult() }
        }
        .sheet(isPresented: $showDebugPanel) {
            debugPanel
        }
    }

    // MARK: - 组装

    private func bootstrap() {
        camera.onPayloads = { payloads in
            store.ingest(payloads)
        }
        camera.onRects = { newRects in
            rects = newRects
        }
        UIApplication.shared.isIdleTimerDisabled = true
        #if DEBUG
        demoMode = loadDemoFramesIfNeeded()
        #endif
        if !demoMode { camera.requestAccessAndStart() }
    }

    #if DEBUG
    /// 调试钩子：模拟器没有摄像头，可用环境变量注入帧来验证解析与界面。
    /// `PF_DEMO_FRAMES=/path/to/case.json`，文件形如 {"meta": "...", "frames": [...]}；
    /// `PF_DEMO_COUNT` 可只注入前 N 片，用于观察「接收中」状态。
    private func loadDemoFramesIfNeeded() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["PF_DEMO_FRAMES"],
              let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = obj["meta"] as? String,
              let frames = obj["frames"] as? [String]
        else { return false }

        let limit = Int(env["PF_DEMO_COUNT"] ?? "") ?? frames.count
        var batch = [meta]
        // 打乱顺序并重复一遍，模拟真实扫描（乱序 + 重复识别）
        var rest = Array(frames.prefix(max(0, limit)))
        rest.shuffle()
        batch.append(contentsOf: rest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            store.ingest(batch)
        }
        return true
    }
    #endif

    private func refreshMissing() {
        guard store.phase == .receiving else {
            if !missing.isEmpty { missing = [] }
            return
        }
        let fresh = store.missingIndices(limit: 24)
        if fresh != missing { missing = fresh }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("PixelFlow")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("PF2 · 多码接收")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if let m = store.meta, store.phase == .receiving {
                Text("\(m.grid) 码阵")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.14), in: Capsule())
            }

            Spacer()

            if camera.torchAvailable {
                circleButton(system: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                             tint: camera.torchOn ? .yellow : .white) {
                    camera.toggleTorch()
                }
            }

            if store.meta != nil {
                circleButton(system: "arrow.counterclockwise", tint: .white) {
                    store.reset()
                }
            }

            #if DEBUG
            circleButton(system: "ladybug.fill", tint: .white.opacity(0.7)) {
                showDebugPanel = true
            }
            #endif
        }
        .padding(.top, 6)
    }

    private func circleButton(system: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.35), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部面板

    private var panel: some View {
        VStack(spacing: 13) {
            if camera.permissionDenied {
                permissionCard
            } else {
                switch store.phase {
                case .waitingMeta: waitingCard
                case .receiving: receivingCard
                case .complete: completeCard
                case .failed(let message): failedCard(message)
                }
            }

            if let notice = store.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.10))
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("需要相机权限", systemImage: "camera.fill")
                .font(.headline)
            Text("PixelFlow 只在本机识别二维码，画面不会离开这台设备。请在「设置」中允许访问相机后重试。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("重试") {
                    camera.requestAccessAndStart()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waitingCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text("对准屏幕上的二维码阵列")
                    .font(.headline)
                Text("电脑屏幕亮度调到最高，手机距离屏幕 15–25 cm，让所有小方块完整入框。左上角的 M 码是协议头，会自动识别。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var receivingCard: some View {
        VStack(spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.meta?.fileName ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        Text("\(store.receivedCount) / \(store.totalCount) 片")
                            .font(.caption)
                            .monospacedDigit()
                        if store.bytesPerSecond > 200 {
                            Text("·").font(.caption).foregroundStyle(.secondary)
                            Text("\(Int(store.bytesPerSecond / 1024)) KB/s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        if let eta = etaText {
                            Text("·").font(.caption).foregroundStyle(.secondary)
                            Text(eta)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(store.progress * 100))%")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }

            ProgressView(value: store.progress)
                .progressViewStyle(.linear)
                .tint(.green)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            if !missing.isEmpty {
                missingRow
            }
        }
    }

    private var missingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("还缺 \(store.missingCount()) 片")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Spacer()

                Text("在发送端点这些数字可补发")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                ForEach(missing.prefix(7), id: \.self) { index in
                    Text("\(index)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(.orange)
                }
                if missing.count > 7 {
                    Text("+\(missing.count - 7)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.26), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 24)
        }
    }

    private var completeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("接收完成")
                    .font(.headline)
                Text(store.archived.map { ExportHelper.humanSize($0.data.count) } ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("查看") { store.reopenResult() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func failedCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("接收失败", systemImage: "exclamationmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("重新接收") { store.reset() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrims: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.62), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var etaText: String? {
        guard let m = store.meta, store.bytesPerSecond > 300,
              store.totalCount > store.receivedCount else { return nil }
        let remainingChunks = Double(store.totalCount - store.receivedCount)
        let remainingBytes = remainingChunks * Double(m.chunkSize) * 0.75
        let seconds = remainingBytes / store.bytesPerSecond
        if seconds < 1 { return "即将完成" }
        if seconds < 60 { return "约 \(Int(seconds.rounded())) 秒" }
        return "约 \(Int((seconds / 60).rounded(.up))) 分钟"
    }

    /// 仅在 DEBUG 构建中可通过右上角按钮打开；Release 下入口被编译掉，面板保留但不占用交互。
    private var debugPanel: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("模拟器里没有摄像头。把发送端生成的帧文本（每行一条）粘贴进来，可直接验证解析、重组与 SHA-256 校验。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $debugText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxHeight: .infinity)
                    .padding(6)
                    .background(Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Button("清空") { debugText = "" }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("喂入数据") {
                        let lines = debugText.split(separator: "\n").map(String.init)
                        store.ingest(lines)
                        showDebugPanel = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .navigationTitle("帧注入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showDebugPanel = false }
                }
            }
        }
    }
}
