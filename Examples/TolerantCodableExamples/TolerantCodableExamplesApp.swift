import SwiftUI

@main
struct TolerantCodableExamplesApp: App {
    var body: some Scene {
        WindowGroup {
            ExampleList()
        }
    }
}

/// 示例目录。
struct ExampleList: View {
    var body: some View {
        NavigationStack {
            List {
                Section("解码") {
                    row("包装器", "Default · LossyArray · LossyDictionary · LossyOptional · FlexibleDate", id: "wrappers") { WrappersExample() }
                    row("未知枚举", "unknownCase · knownCases · isKnown", id: "enum") { UnknownEnumExample() }
                    row("按路径解码", "data.page.items.0", id: "path") { PathExample() }
                    row("严格契约", "decodeExpectingNoDiagnostics", id: "contract") { ContractExample() }
                }
                Section("转换") {
                    row("Socket 载荷与互转", "decode(fromAny:) · lyJSONString · converted(to:)", id: "conversion") { ConversionExample() }
                    row("LYJSONValue", "动态字段 · 路径下标 · LYScalar", id: "json-value") { JSONValueExample() }
                }
            }
            .navigationTitle("TolerantCodable")
        }
    }

    private func row(_ title: String, _ subtitle: String, id: String, destination: @escaping () -> some View) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("example-\(id)")
    }
}
