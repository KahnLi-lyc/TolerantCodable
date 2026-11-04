import Foundation

/// 任意字符串键或数组下标，用于路径解码与动态键容器。
struct LYAnyKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    /// 与 JSONDecoder 一致，下标键的文本为 "Index N"。
    init(index: Int) {
        stringValue = "Index \(index)"
        intValue = index
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.init(index: intValue)
    }
}
