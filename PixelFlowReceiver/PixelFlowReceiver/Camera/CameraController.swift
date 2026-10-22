import AVFoundation
import Combine
import UIKit

/// 相机 + 多码识别。
///
/// 用 `AVCaptureMetadataOutput` 而不是 Vision：它是硬件/系统级解码路径，
/// 延迟更低、功耗更小，而且**一帧可以同时返回多个二维码**——
/// 这正是多码阵列提速的前提。
final class CameraController: NSObject, ObservableObject {

    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var torchAvailable = false
    @Published private(set) var torchOn = false

    /// 一批解出的二维码原始字符串（同一帧内的所有码）
    var onPayloads: (([String]) -> Void)?
    /// 识别到的二维码矩形（metadata 归一化坐标），用于画框提示
    var onRects: (([CGRect]) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.pixelflow.camera.session")
    private let detectQueue = DispatchQueue(label: "com.pixelflow.camera.detect", qos: .userInitiated)

    private let output = AVCaptureMetadataOutput()
    private var device: AVCaptureDevice?
    private var configured = false
    private var lastRectPush = Date.distantPast

    // MARK: - 权限与生命周期

    func requestAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.start() } else { self?.permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureIfNeeded()
            } catch {
                DispatchQueue.main.async { self.permissionDenied = true }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - 配置

    private func configureIfNeeded() throws {
        guard !configured else { return }

        guard let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "PixelFlow", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到后置摄像头"])
        }
        device = back

        // 优先选 720p 高帧率格式：分辨率够解 QR，帧率越高越不容易漏帧
        try selectBestFormat(for: back)

        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        let input = try AVCaptureDeviceInput(device: back)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "PixelFlow", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "无法添加相机输入"])
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw NSError(domain: "PixelFlow", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "无法添加识别输出"])
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: detectQueue)

        // 必须等 output 加入 session 后才能设置 metadataObjectTypes
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        } else {
            session.commitConfiguration()
            throw NSError(domain: "PixelFlow", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "设备不支持二维码识别"])
        }

        session.commitConfiguration()
        configured = true

        DispatchQueue.main.async { self.torchAvailable = back.hasTorch }
        try? applyContinuousFocus(back)
    }

    private func selectBestFormat(for device: AVCaptureDevice) throws {
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width == 1280, dims.height == 720 else { return false }
            return format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 59 }
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if let best = candidates.last {
            device.activeFormat = best
            // 60fps：屏幕刷新是 60Hz，帧率对齐能显著减少「撕裂帧」概率
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
        } else if let fallback = device.formats.first(where: {
            let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return d.width == 1280 && d.height == 720
        }) {
            device.activeFormat = fallback
        }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .none
            }
        }
    }

    private func applyContinuousFocus(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        // 屏幕光比较亮，降低低光增益可以缩短曝光时间、减轻运动模糊
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = false
        }
    }

    // MARK: - 手电筒 / 变焦

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let next = !self.torchOn
                device.torchMode = next ? .on : .off
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.torchOn = next }
            } catch {
                // 忽略：部分设备在高温/低电下会拒绝开启手电筒
            }
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        let clamped = max(device.minAvailableVideoZoomFactor,
                          min(factor, min(6, device.maxAvailableVideoZoomFactor)))
        sessionQueue.async {
            try? device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        }
    }
}

// MARK: - 多码回调

extension CameraController: AVCaptureMetadataOutputObjectsDelegate {

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {

        guard !metadataObjects.isEmpty else { return }

        var payloads: [String] = []
        var rects: [CGRect] = []
        payloads.reserveCapacity(metadataObjects.count)

        for object in metadataObjects {
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  code.type == .qr,
                  let value = code.stringValue,
                  !value.isEmpty
            else { continue }
            payloads.append(value)
            rects.append(code.bounds)
        }

        guard !payloads.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onPayloads?(payloads)
        }

        // 画框提示限流到 ~12Hz，避免无谓的主线程压力
        let now = Date()
        if now.timeIntervalSince(lastRectPush) > 0.08 {
            lastRectPush = now
            let snapshot = rects
            DispatchQueue.main.async { [weak self] in
                self?.onRects?(snapshot)
            }
        }
    }
}
