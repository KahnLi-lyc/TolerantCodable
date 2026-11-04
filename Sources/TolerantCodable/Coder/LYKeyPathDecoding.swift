import Foundation

extension CodingUserInfoKey {
    /// LYJSONCoder 按路径解码时传入的对象键序列。
    static var lyDecodingPath: CodingUserInfoKey {
        guard let key = CodingUserInfoKey(rawValue: "TolerantCodable.decodingPath") else {
            preconditionFailure("Invalid decoding path userInfo key")
        }
        return key
    }
}

/// 任意字符串键，用于沿路径逐层进入嵌套对象。
struct LYAnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

/// 沿 userInfo 中的路径逐层取嵌套容器，在目标键处解码 T；codingPath 保留完整路径，诊断与错误均可定位。
struct LYPathDecodable<T: Decodable>: Decodable {
    let value: T

    init(from decoder: any Decoder) throws {
        guard let path = decoder.userInfo[.lyDecodingPath] as? [String], let last = path.last else {
            value = try decoder.singleValueContainer().decode(T.self)
            return
        }
        var container = try decoder.container(keyedBy: LYAnyKey.self)
        for key in path.dropLast() {
            container = try container.nestedContainer(keyedBy: LYAnyKey.self, forKey: LYAnyKey(key))
        }
        value = try container.decode(T.self, forKey: LYAnyKey(last))
    }
}
