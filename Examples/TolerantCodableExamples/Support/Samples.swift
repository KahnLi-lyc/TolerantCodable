import Foundation

/// 读取打包在 App 中的样例 JSON。
enum Samples {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) else {
            preconditionFailure("Missing sample \(name).json")
        }
        return data
    }

    static func text(_ name: String) -> String {
        String(decoding: data(name), as: UTF8.self)
    }
}
