import Foundation

extension CodingUserInfoKey {
    /// LYJSONCoder 按路径解码时传入的路径段序列。
    static var lyDecodingPath: CodingUserInfoKey {
        guard let key = CodingUserInfoKey(rawValue: "TolerantCodable.decodingPath") else {
            preconditionFailure("Invalid decoding path userInfo key")
        }
        return key
    }
}

/// 沿 userInfo 中的路径逐级进入嵌套节点，在目标处解码 T；codingPath 保留完整路径，诊断与错误均可定位。
/// 纯数字段（如 `0`）遇到数组时按下标进入，遇到对象时按键 `"0"` 进入。
struct LYPathDecodable<T: Decodable>: Decodable {
    let value: T

    init(from decoder: any Decoder) throws {
        guard let path = decoder.userInfo[.lyDecodingPath] as? [String], !path.isEmpty else {
            value = try decoder.singleValueContainer().decode(T.self)
            return
        }
        value = try Self.descend(decoder, path[...])
    }

    private static func descend(_ decoder: any Decoder, _ path: ArraySlice<String>) throws -> T {
        guard let segment = path.first else { return try decoder.singleValueContainer().decode(T.self) }
        let rest = path.dropFirst()
        if let index = lyPathIndex(segment), var array = try? decoder.unkeyedContainer() {
            while array.currentIndex < index, !array.isAtEnd {
                _ = try array.superDecoder()
            }
            guard !array.isAtEnd else {
                throw DecodingError.valueNotFound(T.self, .init(
                    codingPath: array.codingPath + [LYAnyKey(index: index)],
                    debugDescription: "Key path index out of range"
                ))
            }
            // 通过容器解码目标，保留 JSONDecoder 对 Date/Data 的策略拦截。
            return try rest.isEmpty ? array.decode(T.self) : descend(array.superDecoder(), rest)
        }
        let container = try decoder.container(keyedBy: LYAnyKey.self)
        let key = LYAnyKey(segment)
        if rest.isEmpty { return try container.decode(T.self, forKey: key) }
        guard container.contains(key) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: container.codingPath, debugDescription: "Key path segment not found"))
        }
        return try descend(container.superDecoder(forKey: key), rest)
    }
}
