import Foundation

// 常用 LYDefault 组合的简写，例如 `@LYDefaultString var name: String`、`@LYDefaultEmptyArray<Item> var items: [Item]`。

/// 缺失或无法兼容时为空字符串。
public typealias LYDefaultString = LYDefault<LYDefaults.String>
/// 缺失或无法兼容时为 0。
public typealias LYDefaultInt = LYDefault<LYDefaults.Int>
/// 缺失或无法兼容时为 0。
public typealias LYDefaultInt64 = LYDefault<LYDefaults.Int64>
/// 缺失或无法兼容时为 0。
public typealias LYDefaultDouble = LYDefault<LYDefaults.Double>
/// 缺失或无法兼容时为 0。
public typealias LYDefaultFloat = LYDefault<LYDefaults.Float>
/// 缺失或无法兼容时为 0。
public typealias LYDefaultDecimal = LYDefault<LYDefaults.Decimal>
/// 缺失或无法兼容时为 false。
public typealias LYDefaultFalse = LYDefault<LYDefaults.False>
/// 缺失或无法兼容时为 true。
public typealias LYDefaultTrue = LYDefault<LYDefaults.True>
/// 缺失或无法兼容时为空数组；元素仍严格解码，需要丢弃坏元素时使用 LYLossyArray。
public typealias LYDefaultEmptyArray<Element: Decodable> = LYDefault<LYDefaults.EmptyArray<Element>>
/// 缺失或无法兼容时为空字典；条目仍严格解码，需要丢弃坏条目时使用 LYLossyDictionary。
public typealias LYDefaultEmptyDictionary<Key: Decodable & Hashable, Value: Decodable> = LYDefault<LYDefaults.EmptyDictionary<Key, Value>>
