import Foundation

/// 兼容秒/毫秒时间戳及常用 UTC/ISO8601 日期格式，非法值回退 Unix epoch。
@propertyWrapper
public struct LYFlexibleDate: Codable, Equatable, Hashable, Sendable {
    /// 解码后的绝对时间。
    public var wrappedValue: Date

    /// 默认值为 1970-01-01 00:00:00 UTC。
    public init(wrappedValue: Date = Date(timeIntervalSince1970: 0)) {
        self.wrappedValue = wrappedValue
    }

    /// 数字绝对值达到 1e12 时按毫秒解释；无时区文本使用 UTC。
    /// 只有非标准输入（数字、纯日期、空格分隔或无时区）才记录 conversion，标准 ISO8601 静默。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let parsed: (date: Date, canonical: Bool)?
        if let number = try? container.decode(Double.self) {
            parsed = Self.timestamp(number).map { ($0, false) }
        } else if let text = try? container.decode(String.self) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Double(trimmed) {
                parsed = Self.timestamp(number).map { ($0, false) }
            } else {
                parsed = Self.parse(trimmed)
            }
        } else {
            parsed = nil
        }
        wrappedValue = parsed?.date ?? Date(timeIntervalSince1970: 0)
        if let parsed {
            if !parsed.canonical { decoder.lyRecord(.conversion, target: Date.self, reason: "compatible_date") }
        } else {
            decoder.lyRecord(.fallback, target: Date.self, reason: "invalid_date")
        }
    }

    /// 统一输出 ISO8601 UTC 文本，与 decoder 的全局 Date 策略无关。
    public func encode(to encoder: any Encoder) throws {
        guard wrappedValue.timeIntervalSince1970.isFinite else {
            throw EncodingError.invalidValue(
                wrappedValue,
                .init(codingPath: encoder.codingPath, debugDescription: "Date must be finite")
            )
        }
        var container = encoder.singleValueContainer()
        let seconds = wrappedValue.timeIntervalSince1970
        let hasFraction = seconds.rounded(.towardZero) != seconds
        try container.encode(Self.formatter(fractional: hasFraction).string(from: wrappedValue))
    }

    private static func timestamp(_ value: Double) -> Date? {
        guard value.isFinite else { return nil }
        let seconds = abs(value) >= 1e12 ? value / 1000 : value
        let date = Date(timeIntervalSince1970: seconds)
        return date.timeIntervalSinceReferenceDate.isFinite ? date : nil
    }

    /// 独立 formatter 避免跨线程共享可变 Foundation 格式器；仅编码使用。
    private static func formatter(fractional: Bool = false) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    /// 分组：年、月、日、分隔符、时、分、秒、小数秒、时区、符号、时区小时、时区分钟。
    /// 正则只编译一次；NSRegularExpression 不可变且可跨线程匹配。
    private static let pattern = try? NSRegularExpression(
        pattern: #"^([0-9]{4})-([0-9]{2})-([0-9]{2})(?:([T ])([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]+))?(Z|([+-])([0-9]{2}):?([0-9]{2}))?)?$"#
    )

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// 直接用正则分量计算时间：校验 Gregorian 日历分量，阻止 2 月 30 日被规范化为 3 月，不依赖 DateFormatter。
    private static func parse(_ text: String) -> (date: Date, canonical: Bool)? {
        guard let pattern,
              let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        func group(_ index: Int) -> Substring? {
            Range(match.range(at: index), in: text).map { text[$0] }
        }
        func number(_ index: Int) -> Int? {
            group(index).flatMap { Int($0) }
        }
        guard let year = number(1), year >= 1, let month = number(2), let day = number(3) else { return nil }
        let hour = number(5) ?? 0, minute = number(6) ?? 0, second = number(7) ?? 0
        let offsetHour = number(11) ?? 0, offsetMinute = number(12) ?? 0
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute), (0 ... 59).contains(second),
              (0 ... 23).contains(offsetHour), (0 ... 59).contains(offsetMinute)
        else { return nil }
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let base = utcCalendar.date(from: parts),
              utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: base) == parts
        else { return nil }
        // 小数秒保留到纳秒；更多位数只截断，不四舍五入。
        let fraction = group(8).map { Double("0." + $0.prefix(9)) ?? 0 } ?? 0
        let sign: Double = group(10) == "-" ? -1 : 1
        let offset = sign * Double(offsetHour * 3600 + offsetMinute * 60)
        let canonical = group(4) == "T" && group(9) != nil
        return (base.addingTimeInterval(fraction - offset), canonical)
    }
}

public extension KeyedDecodingContainer {
    /// 合成 Decodable 缺少日期字段时回退 Unix epoch。
    func decode(_ type: LYFlexibleDate.Type, forKey key: Key) throws -> LYFlexibleDate {
        guard contains(key) else {
            if let decoder = try? superDecoder(forKey: key) {
                decoder.lyRecord(.fallback, target: Date.self, reason: "missing_key")
            }
            return LYFlexibleDate()
        }
        return try LYFlexibleDate(from: superDecoder(forKey: key))
    }
}
