import SwiftUI
import TolerantCodable

/// 契约测试：用接口 fixture 解码，任何兼容处理都视为后端字段漂移。
struct ContractExample: View {
    var body: some View {
        List {
            check("products_clean")
            check("products_dirty")
            Section {
                Text("""
                在单元测试或 CI 中对接口 fixture 调用 decodeExpectingNoDiagnostics：线上依旧容错，测试环境则能第一时间发现字段类型变化、新增枚举值或缺失字段。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("严格契约")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func check(_ sample: String) -> some View {
        Section("\(sample).json") {
            switch Result(catching: { try LYJSONCoder().decodeExpectingNoDiagnostics([Product].self, from: Samples.data(sample)) }) {
            case let .success(products):
                Label("通过：\(products.count) 个商品，没有兼容处理", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("contract-\(sample)-passed")
            case let .failure(error as LYUnexpectedDiagnosticsError):
                Label("未通过：\(error.diagnostics.count) 条兼容处理", systemImage: "xmark.seal.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("contract-\(sample)-failed")
                ForEach(Array(error.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    Text("\(diagnostic.codingPath.joined(separator: ".")) · \(diagnostic.reason)").font(.caption.monospaced())
                }
            case let .failure(error):
                CodeBlock(text: describe(error))
            }
        }
    }
}
