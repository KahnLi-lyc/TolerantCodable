import SwiftUI
import TolerantCodable

/// 未知原始值落到 unknownCase，已知值不受影响。
struct UnknownEnumExample: View {
    private let input = #"["active", "sold_out", "archived", "draft", "deleted"]"#

    var body: some View {
        List {
            Section("输入") { CodeBlock(text: input) }
            switch Result(catching: { try LYJSONCoder().decodeWithDiagnostics([ProductStatus].self, from: Data(input.utf8)) }) {
            case let .success(result):
                Section("结果") {
                    ForEach(Array(result.value.enumerated()), id: \.offset) { _, status in
                        LabeledContent(status.rawValue, value: status.isKnown ? "已识别" : "unknownCase")
                    }
                }
                Section("ProductStatus.knownCases") {
                    CodeBlock(text: ProductStatus.knownCases.map(\.rawValue).joined(separator: ", "))
                }
                DiagnosticsSection(diagnostics: result.diagnostics)
            case let .failure(error):
                Section("错误") { CodeBlock(text: describe(error)) }
            }
            Section {
                Text("原始值类型不符（例如数字）、null 或缺失字段仍按 Codable 规则抛错；只有无法识别的字符串 / 整数才兜底。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("未知枚举")
        .navigationBarTitleDisplayMode(.inline)
    }
}
