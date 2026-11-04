import Foundation

/// 服务端可扩展的枚举：无法识别的原始值解码为 unknownCase，而不是让整个模型失败。
/// 原始值类型不符、null 或缺失字段仍按 Codable 原有规则抛错；兜底会以 `unknown_enum_case` 记录诊断。
///
/// ```swift
/// enum Role: String, Codable, LYUnknownCaseDecodable {
///     case owner, member
///     case unknown
///     static var unknownCase: Self { .unknown }
/// }
/// ```
public protocol LYUnknownCaseDecodable: RawRepresentable, Decodable, Equatable where RawValue: Decodable {
    /// 兜底 case；只表示客户端无法识别的服务端值，不应作为请求值发送。
    static var unknownCase: Self { get }
}

public extension LYUnknownCaseDecodable where RawValue == String {
    /// 比标准库 RawRepresentable 默认实现更具体，合成与手写的 decode 均会选中此实现。
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Self(rawValue: raw) else {
            self = .unknownCase
            decoder.lyRecord(.fallback, target: Self.self, reason: "unknown_enum_case")
            return
        }
        self = value
    }
}

public extension LYUnknownCaseDecodable where RawValue == Int {
    /// Int 原始值枚举的同构兜底。
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        guard let value = Self(rawValue: raw) else {
            self = .unknownCase
            decoder.lyRecord(.fallback, target: Self.self, reason: "unknown_enum_case")
            return
        }
        self = value
    }
}

public extension LYUnknownCaseDecodable {
    /// 是否为客户端已识别的取值。
    var isKnown: Bool {
        self != .unknownCase
    }
}

public extension LYUnknownCaseDecodable where Self: CaseIterable {
    /// 排除 unknownCase 的可选值，用于选择器、订阅和契约比对。
    static var knownCases: [Self] {
        allCases.filter(\.isKnown)
    }
}
