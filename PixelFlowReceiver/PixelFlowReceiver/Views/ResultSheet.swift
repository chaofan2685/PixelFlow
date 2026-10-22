import SwiftUI
import UIKit

struct ResultSheet: View {
    let result: TransferResult
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var errorText: String?
    @State private var savedHint: String?

    private var isText: Bool { result.meta.kind == .text }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        summaryCard

                        if isText {
                            textCard
                        } else {
                            fileCard
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let savedHint {
                            Text(savedHint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("接收完成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onDone()
                        dismiss()
                    }
                }
            }
            #if DEBUG
            .task { await autoTriggerIfRequested() }
            #endif
        }
    }

    // MARK: - 卡片

    private var summaryCard: some View {
        VStack(spacing: 10) {
            Image(systemName: result.verified ? "checkmark.seal.fill" : "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(result.verified ? .green : .secondary)

            Text(result.verified ? "SHA-256 校验通过" : "已完成（发送端未提供校验值）")
                .font(.headline)

            Text("\(ExportHelper.humanSize(result.data.count)) · \(result.meta.total) 片")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("文本内容").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    UIPasteboard.general.string = result.text ?? ""
                    copied = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                }
            }

            Divider()

            Text(result.text ?? "")
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                ExportPresenter.share(text: result.text ?? "")
            } label: {
                Label("分享文本", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.accentColor.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fileCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.meta.fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ExportHelper.humanSize(result.data.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 10) {
                Button {
                    saveToFiles()
                } label: {
                    Label("存储到「文件」", systemImage: "folder.badge.plus")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }

                Button {
                    shareFile()
                } label: {
                    Label("分享…", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 动作

    private func makeFileURL() throws -> URL {
        try ExportHelper.writeTemporaryFile(name: result.meta.fileName, data: result.data)
    }

    private func saveToFiles() {
        errorText = nil
        savedHint = nil
        do {
            let url = try makeFileURL()
            ExportPresenter.exportToFiles(url: url) { done in
                if done {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    savedHint = "已保存到「文件」"
                }
            }
        } catch {
            errorText = "写入临时文件失败：\(error.localizedDescription)"
        }
    }

    private func shareFile() {
        errorText = nil
        savedHint = nil
        do {
            let url = try makeFileURL()
            ExportPresenter.share(url: url)
        } catch {
            errorText = "写入临时文件失败：\(error.localizedDescription)"
        }
    }

    #if DEBUG
    /// 模拟器验证用：`PF_AUTO_EXPORT=save|share` 会自动触发对应按钮，
    /// 用来确认导出面板能正常渲染内容（而不是一片灰）。
    private func autoTriggerIfRequested() async {
        guard !isText else { return }
        let mode = ProcessInfo.processInfo.environment["PF_AUTO_EXPORT"] ?? ""
        guard !mode.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 900_000_000)
        if mode == "save" { saveToFiles() } else { shareFile() }
    }
    #endif
}
