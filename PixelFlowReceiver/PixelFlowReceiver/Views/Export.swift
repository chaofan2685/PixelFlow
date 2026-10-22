import SwiftUI
import UIKit

enum ExportHelper {

    static func sanitize(_ name: String) -> String {
        var s = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 去掉控制字符，避免出现不可见文件名
        s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .map(Character.init))

        if s.isEmpty || s == "." || s == ".." { s = "received.bin" }

        if s.count > 160 {
            let ext = (s as NSString).pathExtension
            if ext.isEmpty {
                s = String(s.prefix(120))
            } else {
                let base = String(s.dropLast(ext.count + 1))
                s = String(base.prefix(120)) + "." + ext
            }
        }
        return s
    }

    /// 每次导出前清掉久远的残留文件，避免临时目录无限堆积。
    /// 只删 5 分钟以前的——正在被分享面板引用的文件不能被删，否则隔空投送会失效。
    static func prepareExportDirectory(keeping keepName: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelFlow", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let cutoff = Date().addingTimeInterval(-300)
        if let olds = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            for url in olds {
                if let keepName, url.lastPathComponent == keepName { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if modified < cutoff { try? FileManager.default.removeItem(at: url) }
            }
        }
        return dir
    }

    static func writeTemporaryFile(name: String, data: Data) throws -> URL {
        let safeName = sanitize(name)
        let dir = try prepareExportDirectory(keeping: safeName)
        let url = dir.appendingPathComponent(safeName)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func humanSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.2f MB", Double(bytes) / 1048576)
    }
}

// MARK: - 模态呈现

/// `UIActivityViewController` 必须以“被 present 的模态控制器”形式出现。
/// 如果把它塞进 SwiftUI 的 `.sheet`（`UIViewControllerRepresentable`），
/// 它只是个被嵌入的子控制器，拿不到正常的 modal 生命周期，结果是弹出一个灰色空窗口。
/// 因此这里绕开 SwiftUI 的 sheet，直接找到最顶层控制器自己 present。
@MainActor
enum ExportPresenter {

    /// 系统分享面板：包含「存储到文件」、隔空投送、拷贝到其他 App 等。
    static func share(url: URL, onFinish: ((Bool) -> Void)? = nil) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            onFinish?(completed)
        }
        present(vc)
    }

    /// 文本分享（不落盘）。
    static func share(text: String, onFinish: ((Bool) -> Void)? = nil) {
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            onFinish?(completed)
        }
        present(vc)
    }

    /// 直接唤起「存储到文件」的文稿选择器，比在分享面板里多点一层更直接。
    static func exportToFiles(url: URL, onFinish: ((Bool) -> Void)? = nil) {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = DocumentExporter.shared
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        DocumentExporter.shared.onFinish = onFinish
        present(picker)
    }

    private static func present(_ vc: UIViewController) {
        guard let host = topViewController() else {
            NSLog("[PixelFlow] 找不到可用的宿主控制器，无法呈现导出面板")
            return
        }
        // iPad / 横屏下 UIActivityViewController 走 popover，必须给锚点，否则会崩
        if let pop = vc.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY,
                                    width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        host.present(vc, animated: true)
    }

    /// 从 key window 一路下钻：已 presented 的控制器 → 导航栈顶 → 选中 tab。
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first,
              let root = window.rootViewController
        else { return nil }
        return findTop(from: root)
    }

    private static func findTop(from vc: UIViewController) -> UIViewController {
        if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
            return findTop(from: visible)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return findTop(from: selected)
        }
        if let presented = vc.presentedViewController, !presented.isBeingDismissed {
            return findTop(from: presented)
        }
        return vc
    }
}

/// `UIDocumentPickerViewController.delegate` 是 weak，必须有个强引用替他活到回调。
final class DocumentExporter: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentExporter()
    var onFinish: ((Bool) -> Void)?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onFinish?(true)
        onFinish = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onFinish?(false)
        onFinish = nil
    }
}
