import SwiftUI
import TolerantCodable

/// 等宽、可选中的 JSON / 结果文本块。
struct CodeBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 诊断列表；标题带条数，供 UI 测试读取。
struct DiagnosticsSection: View {
    let diagnostics: [LYDecodingDiagnostic]

    var body: some View {
        Section {
            if diagnostics.isEmpty {
                Text("没有兼容处理，数据与模型完全一致").foregroundStyle(.secondary)
            }
            ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(diagnostic.kind.rawValue)
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .background(color(for: diagnostic.kind).opacity(0.2), in: Capsule())
                        Text(diagnostic.reason).font(.caption.monospaced())
                    }
                    Text(diagnostic.codingPath.joined(separator: " › "))
                        .font(.caption2.monospaced())
                    Text(diagnostic.targetType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("诊断 \(diagnostics.count) 条").accessibilityIdentifier("diagnostic-count")
        }
    }

    private func color(for kind: LYDecodingDiagnostic.Kind) -> Color {
        switch kind {
        case .conversion: .blue
        case .fallback: .orange
        case .discard: .red
        case .failure: .purple
        case .suppressed: .gray
        }
    }
}

/// 把错误转成简短、可读的描述；DecodingError 只展示种类与路径。
func describe(_ error: any Error) -> String {
    func path(_ context: DecodingError.Context) -> String {
        context.codingPath.isEmpty ? "根节点" : context.codingPath.map(\.stringValue).joined(separator: ".")
    }
    switch error {
    case let DecodingError.keyNotFound(key, context):
        return "keyNotFound: \(key.stringValue) @ \(path(context))"
    case let DecodingError.typeMismatch(type, context):
        return "typeMismatch: \(type) @ \(path(context))"
    case let DecodingError.valueNotFound(type, context):
        return "valueNotFound: \(type) @ \(path(context))"
    case let DecodingError.dataCorrupted(context):
        return "dataCorrupted @ \(path(context))"
    case let error as LYConversionError:
        return "LYConversionError.\(error)"
    case let error as LYUnexpectedDiagnosticsError:
        return "LYUnexpectedDiagnosticsError: \(error.diagnostics.count) 条兼容处理"
    default:
        return String(describing: error)
    }
}
