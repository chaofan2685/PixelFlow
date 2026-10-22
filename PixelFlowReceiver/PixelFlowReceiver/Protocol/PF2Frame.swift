import Foundation

/// PF2 传输协议帧。
///
/// 元信息帧: `PF2|M|<kind>|<total>|<chunkSize>|<b64len>|<sha256>|<grid>|<name>`
/// 数据帧:   `PF2|D|<idx>|<payload>`
///
/// `name` 恒为最后一个字段，解析时用「剩余字段重组」的方式取回，
/// 因此文件名里即使包含 `|` 也不会破坏协议。
/// 数据载荷是 base64 片段（`A-Za-z0-9+/=`），与分隔符 `|` 无交集。
enum PF2Frame {

    struct Meta: Equatable {
        enum Kind: String {
            case file = "f"
            case text = "t"
        }

        let kind: Kind
        let total: Int
        let chunkSize: Int
        let b64Length: Int
        /// 原始字节的 SHA-256（64 位小写十六进制）。`-` 表示发送端未提供校验值。
        let sha256: String
        let grid: Int
        let fileName: String

        var isVerifiable: Bool { sha256 != "-" && sha256.count == 64 }

        /// 用于判断「是不是同一趟传输」。
        var identity: String {
            "\(sha256)|\(total)|\(b64Length)|\(fileName)"
        }
    }

    case meta(Meta)
    case data(index: Int, payload: String)

    // 防御性上限，避免恶意/畸形帧导致内存爆炸
    private static let maxTotal = 500_000
    private static let maxChunkSize = 50_000
    private static let maxB64Length = 500_000_000

    static func parse(_ raw: String) -> PF2Frame? {
        guard raw.count >= 6, raw.hasPrefix("PF2|") else { return nil }

        let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }

        switch parts[1] {
        case "M":
            guard parts.count >= 9,
                  let kind = Meta.Kind(rawValue: String(parts[2])),
                  let total = Int(parts[3]),
                  let chunkSize = Int(parts[4]),
                  let b64Length = Int(parts[5]),
                  let grid = Int(parts[7]),
                  total >= 0, total <= maxTotal,
                  chunkSize > 0, chunkSize <= maxChunkSize,
                  b64Length >= 0, b64Length <= maxB64Length,
                  grid >= 1, grid <= 64
            else { return nil }

            let name = parts[8...].joined(separator: "|")
            return .meta(Meta(kind: kind,
                              total: total,
                              chunkSize: chunkSize,
                              b64Length: b64Length,
                              sha256: String(parts[6]),
                              grid: grid,
                              fileName: name.isEmpty ? "received.bin" : name))

        case "D":
            guard parts.count >= 4,
                  let idx = Int(parts[2]),
                  idx >= 1, idx <= maxTotal
            else { return nil }

            let payload = parts[3...].joined(separator: "|")
            return .data(index: idx, payload: payload)

        default:
            return nil
        }
    }
}
