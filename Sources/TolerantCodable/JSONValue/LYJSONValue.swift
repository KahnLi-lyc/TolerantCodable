import Foundation

/// 类型安全、可跨并发边界传递的 JSON 值，用于承载结构不固定的字段，替代 `Any` / `[String: Any]`。
/// 解码本身是严格的：只接受合法 JSON，不做任何兜底。超出 Int64 的整数以 `.double` 保存，可能丢失精度。
public enum LYJSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([LYJSONValue])
    case object([String: LYJSONValue])
}

// MARK: - Codable

extension LYJSONValue: Codable {
    /// 解码顺序：null → Bool → Int64 → Double → String → 数组 → 对象，保证 `true` 与 `1` 不混淆。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([LYJSONValue].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: LYJSONValue].self))
        }
    }

    /// 按原始种类写回。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

// MARK: - Literals

extension LYJSONValue: ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    public init(integerLiteral value: Int64) {
        self = .integer(value)
    }

    public init(floatLiteral value: Double) {
        self = .double(value)
    }

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(arrayLiteral elements: LYJSONValue...) {
        self = .array(elements)
    }

    public init(dictionaryLiteral elements: (String, LYJSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Accessors

public extension LYJSONValue {
    /// 是否为 JSON null。
    var isNull: Bool {
        self == .null
    }

    /// 精确取值：仅 `.bool` 返回值。
    var boolValue: Bool? {
        if case let .bool(value) = self { value } else { nil }
    }

    /// 精确取值：仅 `.integer` 返回值。
    var int64Value: Int64? {
        if case let .integer(value) = self { value } else { nil }
    }

    /// 精确取值：`.double` 与 `.integer` 都返回 Double。
    var doubleValue: Double? {
        switch self {
        case let .double(value): value
        case let .integer(value): Double(value)
        default: nil
        }
    }

    /// 精确取值：仅 `.string` 返回值；需要宽松转换时使用 LYScalar。
    var stringValue: String? {
        if case let .string(value) = self { value } else { nil }
    }

    /// 精确取值：仅 `.array` 返回值。
    var arrayValue: [LYJSONValue]? {
        if case let .array(value) = self { value } else { nil }
    }

    /// 精确取值：仅 `.object` 返回值。
    var objectValue: [String: LYJSONValue]? {
        if case let .object(value) = self { value } else { nil }
    }

    /// 对象取键；不是对象或键不存在时返回 nil。
    subscript(key: String) -> LYJSONValue? {
        objectValue?[key]
    }

    /// 数组取下标；不是数组或越界时返回 nil。
    subscript(index: Int) -> LYJSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// 按点分路径取值，例如 `"data.items.0.name"`；纯数字段在数组上表示下标，在对象上表示键。
    /// 空路径返回自身；含空段、键不存在或越界时返回 nil。
    subscript(path path: String) -> LYJSONValue? {
        guard !path.isEmpty else { return self }
        var current = self
        for segment in path.split(separator: ".", omittingEmptySubsequences: false) {
            guard !segment.isEmpty else { return nil }
            switch current {
            case let .object(object):
                guard let next = object[String(segment)] else { return nil }
                current = next
            case let .array(array):
                guard let index = lyPathIndex(segment), array.indices.contains(index) else { return nil }
                current = array[index]
            default:
                return nil
            }
        }
        return current
    }

    /// 顶层值的种类。
    var kind: LYConversionError.Kind {
        switch self {
        case .null: .null
        case .bool: .bool
        case .integer, .double: .number
        case .string: .string
        case .array: .array
        case .object: .object
        }
    }
}

// MARK: - Decoding models

public extension LYJSONValue {
    /// 把当前值解码为模型；中间经过 Data，诊断与按路径解码规则与 LYJSONCoder 一致。
    func decode<T: Decodable>(
        _ type: T.Type = T.self,
        atPath path: String = "",
        coder: LYJSONCoder = LYJSONCoder(),
        context: LYCodingContext = .init()
    ) throws -> T {
        try coder.decode(type, from: JSONEncoder().encode(self), atPath: path, context: context)
    }
}

// MARK: - Description

extension LYJSONValue: CustomStringConvertible {
    /// 紧凑、排序键的 JSON 文本，便于调试。
    public var description: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "<invalid>"
    }
}

/// 路径段是否为规范的非负整数下标：只含 ASCII 数字，且除 "0" 外不以 0 开头。
func lyPathIndex(_ segment: some StringProtocol) -> Int? {
    guard !segment.isEmpty, segment.allSatisfy({ $0.isASCII && $0.isNumber }),
          segment == "0" || segment.first != "0"
    else { return nil }
    return Int(segment)
}
