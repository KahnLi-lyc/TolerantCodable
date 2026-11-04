import SwiftUI
import TolerantCodable

/// 同一模型分别解码干净数据和脏数据，对比结果与诊断。
struct WrappersExample: View {
    @State private var dirty = false

    private var sample: String {
        dirty ? "products_dirty" : "products_clean"
    }

    private var outcome: Result<(value: [Product], diagnostics: [LYDecodingDiagnostic]), any Error> {
        Result { try LYJSONCoder().decodeWithDiagnostics([Product].self, from: Samples.data(sample)) }
    }

    var body: some View {
        List {
            Section {
                Picker("数据", selection: $dirty) {
                    Text("干净数据").tag(false)
                    Text("脏数据").tag(true)
                }
                .pickerStyle(.segmented)
            }
            switch outcome {
            case let .success(result):
                DiagnosticsSection(diagnostics: result.diagnostics)
                Section("结果") {
                    ForEach(result.value) { product in
                        ProductRow(product: product)
                    }
                }
            case let .failure(error):
                Section("错误") { CodeBlock(text: describe(error)) }
            }
            Section {
                DisclosureGroup("输入 \(sample).json") {
                    CodeBlock(text: Samples.text(sample))
                }
            }
        }
        .navigationTitle("包装器")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProductRow: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(product.id) · \(product.title.isEmpty ? "（空标题）" : product.title)").font(.headline)
            CodeBlock(text: """
            price    \(product.price)
            onSale   \(product.onSale)
            tags     \(product.tags)
            stock    \(product.stock.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })
            rating   \(product.rating.map { "\($0)" } ?? "nil")
            updated  \(product.updatedAt.formatted(.iso8601))
            status   \(product.status.rawValue)\(product.status.isKnown ? "" : "（未知）")
            """)
        }
    }
}
