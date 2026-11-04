import SwiftUI
import TolerantCodable

/// 单次解析，只解码路径指向的子节点；纯数字段在数组上表示下标。
struct PathExample: View {
    private enum Target: String, CaseIterable {
        case json = "LYJSONValue"
        case product = "Product"
        case products = "[Product]"
    }

    @State private var path = "data.page.items.1"
    @State private var target = Target.product
    private let presets = ["data.page.items", "data.page.items.1", "data.page.items.0.title", "data.page.total", "data.page.items.5", "data.missing"]

    var body: some View {
        List {
            Section("路径") {
                TextField("data.page.items.0", text: $path)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("path-field")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(presets, id: \.self) { preset in
                            Button(preset) { path = preset }.buttonStyle(.bordered).font(.caption.monospaced())
                        }
                    }
                }
                Picker("解码为", selection: $target) {
                    ForEach(Target.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch decode() {
            case let .success((text, diagnostics)):
                DiagnosticsSection(diagnostics: diagnostics)
                Section("结果") { CodeBlock(text: text).accessibilityIdentifier("path-result") }
            case let .failure(error):
                Section("错误") { CodeBlock(text: describe(error)).accessibilityIdentifier("path-error") }
            }
            Section {
                DisclosureGroup("输入 envelope.json") {
                    CodeBlock(text: Samples.text("envelope"))
                }
            }
        }
        .navigationTitle("按路径解码")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func decode() -> Result<(String, [LYDecodingDiagnostic]), any Error> {
        Result {
            let coder = LYJSONCoder()
            let data = Samples.data("envelope")
            switch target {
            case .json:
                let result = try coder.decodeWithDiagnostics(LYJSONValue.self, from: data, atPath: path)
                return try (result.value.jsonData().lyPrettyJSONString(), result.diagnostics)
            case .product:
                let result = try coder.decodeWithDiagnostics(Product.self, from: data, atPath: path)
                return try (result.value.jsonString(prettyPrinted: true), result.diagnostics)
            case .products:
                let result = try coder.decodeWithDiagnostics([Product].self, from: data, atPath: path)
                return try (result.value.jsonString(prettyPrinted: true), result.diagnostics)
            }
        }
    }
}
