import Foundation
import CryptoKit
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct TransferResult: Identifiable {
    let id = UUID()
    let meta: PF2Frame.Meta
    let data: Data
    let verified: Bool

    var text: String? {
        guard meta.kind == .text else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// 接收端状态机：累积分片、校验完整性、产出结果。
/// 所有方法都应在主线程调用（相机回调已切到主线程）。
final class TransferStore: ObservableObject {

    enum Phase: Equatable {
        case waitingMeta
        case receiving
        case complete
        case failed(String)
    }

    @Published private(set) var phase: Phase = .waitingMeta
    @Published private(set) var meta: PF2Frame.Meta?
    @Published private(set) var receivedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var bytesPerSecond: Double = 0
    @Published private(set) var notice: String?
    @Published var result: TransferResult?
    @Published private(set) var archived: TransferResult?

    private var chunks: [String?] = []
    private var receivedCharCount = 0
    private var startedAt: Date?
    private var candidateMeta: PF2Frame.Meta?

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, Double(receivedCount) / Double(totalCount))
    }

    var isComplete: Bool { phase == .complete }

    // MARK: - 输入

    func ingest(_ payloads: [String]) {
        guard !payloads.isEmpty else { return }
        var changed = false

        for raw in payloads {
            guard let frame = PF2Frame.parse(raw) else { continue }
            switch frame {
            case .meta(let m):
                if handleMeta(m) { changed = true }
            case .data(let idx, let payload):
                if handleData(index: idx, payload: payload) { changed = true }
            }
        }

        if changed { refreshSpeed() }
    }

    private func handleMeta(_ m: PF2Frame.Meta) -> Bool {
        if let current = meta {
            if current.identity == m.identity { return false }

            // 已完成时遇到新传输：直接切换
            if phase == .complete {
                begin(m)
                notice = "检测到新传输，已自动切换"
                return true
            }

            // 传输中遇到不同传输：需连续看到两次才切换，避免偶发误识别冲掉进度
            if candidateMeta?.identity == m.identity {
                begin(m)
                notice = "检测到新传输，已自动切换"
                return true
            }
            candidateMeta = m
            notice = "检测到另一路传输，再见一次即切换"
            return false
        }

        begin(m)
        return true
    }

    private func begin(_ m: PF2Frame.Meta) {
        meta = m
        totalCount = m.total
        chunks = Array(repeating: nil, count: max(0, m.total) + 1)
        receivedCount = 0
        receivedCharCount = 0
        candidateMeta = nil
        startedAt = Date()
        bytesPerSecond = 0
        result = nil
        archived = nil

        if m.total == 0 {
            phase = .receiving
            finish()
        } else {
            phase = .receiving
        }
    }

    private func handleData(index: Int, payload: String) -> Bool {
        guard meta != nil, phase != .complete,
              index >= 1, index < chunks.count
        else { return false }
        guard chunks[index] == nil else { return false }

        chunks[index] = payload
        receivedCount += 1
        receivedCharCount += payload.count

        if receivedCount == totalCount { finish() }
        return true
    }

    private func refreshSpeed() {
        guard let start = startedAt else { return }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0.35 else { return }
        // base64 的 4 字符 ≈ 3 字节
        bytesPerSecond = Double(receivedCharCount) * 0.75 / elapsed
    }

    // MARK: - 完成与校验

    private func finish() {
        guard let m = meta else { return }

        var joined = ""
        joined.reserveCapacity(m.b64Length)
        if m.total > 0 {
            for i in 1...m.total {
                guard let piece = chunks[i] else { return }
                joined += piece
            }
        }

        guard joined.count == m.b64Length else {
            phase = .failed("长度校验失败：收到 \(joined.count) 字符，协议声明 \(m.b64Length)")
            return
        }

        guard let data = Data(base64Encoded: joined) else {
            phase = .failed("Base64 解码失败，数据可能已损坏")
            return
        }

        var verified = false
        if m.isVerifiable {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex == m.sha256.lowercased() else {
                phase = .failed("SHA-256 校验失败，数据在传输中损坏了")
                return
            }
            verified = true
        }

        phase = .complete
        result = TransferResult(meta: m, data: data, verified: verified)
        archived = result
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    // MARK: - 辅助

    /// 缺失分片（仅在需要展示时调用，避免每帧全量扫描）
    func missingIndices(limit: Int = 60) -> [Int] {
        guard phase == .receiving, totalCount > 0, totalCount <= 20_000 else { return [] }
        var out: [Int] = []
        for i in 1...totalCount where chunks[i] == nil {
            out.append(i)
            if out.count >= limit { break }
        }
        return out
    }

    func missingCount() -> Int {
        guard totalCount > 0 else { return 0 }
        return max(0, totalCount - receivedCount)
    }

    func reset() {
        phase = .waitingMeta
        meta = nil
        chunks = []
        receivedCount = 0
        receivedCharCount = 0
        totalCount = 0
        bytesPerSecond = 0
        startedAt = nil
        candidateMeta = nil
        notice = nil
        result = nil
        archived = nil
    }

    func dismissResult() {
        result = nil
    }

    func reopenResult() {
        result = archived
    }
}
