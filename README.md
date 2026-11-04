# TolerantCodable

[简体中文](README.zh-Hans.md)

**Strict by default, tolerant on purpose, diagnosable.** Codable extensions for Swift 6.

- Fields you don't annotate keep Codable's strict semantics, so contract drift is never silently hidden.
- Only the fields you wrap tolerate drift: numeric strings, nulls, missing keys, bad array elements, mixed date formats and new enum values.
- Every fallback leaves a redacted, structured diagnostic (type, coding path, reason code, never the raw value).
- Built on the system `JSONDecoder`, with zero dependencies and zero warnings under strict concurrency.

## Installation

```swift
.package(url: "https://github.com/KahnLi-lyc/TolerantCodable.git", from: "0.2.0")
```

Requirements: iOS 16 / macOS 13 / tvOS 16 / watchOS 9, Swift 6.

## Quick start

```swift
import TolerantCodable

enum Role: String, Codable, LYUnknownCaseDecodable {
    case owner, member
    case unknown
    static var unknownCase: Self { .unknown }
}

struct Member: Codable {
    let id: String                                        // strict: missing or mistyped throws
    @LYDefault<LYDefaults.Int> var age: Int               // "30" → 30, null/missing → 0
    @LYDefault<LYDefaults.False> var verified: Bool       // 1 / "true" → true
    @LYLossyArray var tags: [String]                      // drops bad elements
    @LYFlexibleDate var joinedAt: Date                    // timestamps or ISO 8601
    var role: Role                                        // new values → .unknown
}

let members = try [Member].decode(fromJSON: data, atPath: "data.items")
```

## Wrapper semantics

| Type | Accepts | Falls back to | Still strict |
|---|---|---|---|
| `@LYDefault<P>` | Whitelisted scalar conversions: string ⇄ number, Bool from 0/1/"true". Integers go through Decimal, so Int64 precision is kept. NaN, inf and hex are rejected. | `P.defaultValue` | — (use for fields that can degrade safely) |
| `@LYLossyArray` | Per-element decoding | Bad elements are dropped; `[]` when missing, null or not an array | Each element still follows its own Decodable contract |
| `@LYFlexibleDate` | Second/millisecond timestamps, numeric strings, `yyyy-MM-dd`, `T` or space separator, with or without a zone, any number of fraction digits | Unix epoch | Invalid calendar dates, hour 24 and bad offsets fall back |
| `@LYLossyDictionary` | Per-entry decoding; raw JSON keys are converted to `Key` (`LosslessStringConvertible`) | Bad keys and values are dropped; `[:]` when missing, null or not an object | Each value still follows its own Decodable contract |
| `@LYLossyOptional` | Mistyped values | `nil` (missing and null are plain nil and not reported) | — ; encoding omits the key when nil |
| `LYUnknownCaseDecodable` | New raw values | `unknownCase` | Wrong raw type, null, missing |

Shorthands for common providers: `@LYDefaultString`, `@LYDefaultInt`, `@LYDefaultInt64`, `@LYDefaultDouble`, `@LYDefaultFloat`, `@LYDefaultDecimal`, `@LYDefaultFalse`, `@LYDefaultTrue`, `@LYDefaultEmptyArray<E>`, `@LYDefaultEmptyDictionary<K, V>`.

Custom defaults:

```swift
enum Anonymous: LYDefaultValueProvider { static var defaultValue: String { "anonymous" } }
@LYDefault<Anonymous> var nickname: String
```

An initial value written on the declaration (`= 5`) does not take part in decoding. The fallback always comes from the provider.

## Unknown enum values

- Unrecognized values decode as `unknownCase`. **Never map them to a real case**: treat them with least privilege and show neutral text.
- `knownCases` excludes the fallback. Use it for pickers, subscriptions and contract checks.
- `unknownCase` is decode-only. Never send it back as a request value.

## Diagnostics

```swift
let coder = LYJSONCoder(configuration: .init(onDiagnostic: { diagnostic in
    print(diagnostic.kind, diagnostic.codingPath, diagnostic.reason)   // never contains raw values
}))
let page = try coder.decode(Page.self, from: data, context: .init(endpoint: "/members", requestID: requestID))
```

- `kind` is one of `conversion`, `fallback`, `discard`, `failure` or `suppressed`.
- At most 50 records are kept per decode, and the final failure is always kept.
- With a plain `JSONDecoder`, inject a collector: `decoder.userInfo[.lyDiagnostics] = LYDiagnosticCollector()`. Without one, fallbacks are silent.

## Contract tests and presets

- `decodeWithDiagnostics` returns the value together with the diagnostics of that call.
- `decodeExpectingNoDiagnostics` throws `LYUnexpectedDiagnosticsError` whenever any tolerance kicks in. Run it against API fixtures in unit tests or CI: production stays tolerant, while tests catch backend drift immediately.
- `LYCodingConfiguration.snakeCase` uses `.convertFromSnakeCase` / `.convertToSnakeCase`. Key paths then match the converted camelCase keys (`"userInfo"`, not `"user_info"`).

## Conversion helpers

Every helper throws on failure. None of them return `nil`. Errors carry type names and JSON kinds only, never raw values.

| API | Notes |
|---|---|
| `T.decode(fromJSON: Data/String, atPath:)` | Paths such as `"data.items"` or `"data.items.0.name"` are resolved in a single pass, without an `Any` round trip |
| `T.decode(fromJSONObject: [String: Any] / [Any])` | Validates the Foundation object first |
| `T.decode(fromAny: Any?)` | Payloads of unknown shape (sockets, push, bridges): Data / String / dictionary / array / LYJSONValue |
| `value.jsonData()` / `jsonString(prettyPrinted:)` / `jsonObject()` | Encode to Data, text or Foundation objects |
| `value.jsonDictionary()` / `jsonArray()` / `jsonValue()` | Encode to `[String: Any]`, `[Any]` or `LYJSONValue`; throws when the root kind differs |
| `value.converted(to: Entity.self)` | Model-to-model conversion (DTO → entity) with diagnostics |
| `dict.lyJSONString()` / `lyJSONData()`, same on `[Any]` | Validate and serialize Foundation collections |
| `string.lyJSONObject()` / `lyJSONDictionary()` / `lyJSONArray()`, same on Data | Parse and check the root kind |
| `data.lyPrettyJSONString()` | Re-indent with sorted keys for logs |
| `LYJSONSerialization.parse/parseObject/parseArray/data/string/data(fromAny:)` | Safe JSONSerialization wrapper: invalid objects throw instead of raising ObjC exceptions |
| `LYScalar.int/int64/double/float/decimal/bool/string(from:)` | Lenient scalar conversion with exactly the same whitelist as `@LYDefault` |

## LYJSONValue

Use `LYJSONValue` for fields whose shape is not fixed, instead of `Any` / `[String: Any]`. It is a `Sendable`, `Hashable`, `Codable` enum, so it crosses concurrency boundaries safely.

```swift
struct LiveEvent: Codable {
    let type: String
    let payload: LYJSONValue
}

let event = try LiveEvent.decode(fromJSON: data)
event.payload[path: "sender.name"]                // .string("Kahn")
try LYScalar.int(from: event.payload["count"])    // "3" → 3
let gift = try event.payload.decode(Gift.self)
```

Decoding order is null → Bool → Int64 → Double → String → array → object, so `true` and `1` never mix. Integers beyond Int64 are stored as `.double`. `LYJSONValue(any:)` and `foundationObject` bridge to Foundation objects and tell Bool apart from numbers.

## Example app

`Examples/TolerantCodableExamples.xcodeproj` is an iOS 16 SwiftUI app with one page per feature: wrappers (clean vs. dirty data with diagnostics), unknown enums, key paths, contract checks, socket payload conversion and LYJSONValue. It is generated by XcodeGen from `Examples/project.yml` and depends on the package at the repository root.

## Compared with SmartCodable and BetterCodable

| | TolerantCodable | SmartCodable | BetterCodable |
|---|---|---|---|
| Approach | Explicitly wrapped fields | Custom decoder, tolerant everywhere | Explicitly wrapped fields |
| Decoder | System JSONDecoder | JSONSerialization → JSONValue tree → custom decoder | System JSONDecoder |
| Unknown enum | `unknownCase` | Declared initial value, which is a real case | Up to you |
| Failure | Throws DecodingError plus diagnostics | Returns nil | Throws DecodingError |
| Diagnostics | Structured, redacted | Logs | None |

## Performance

Measured on an Apple M1 Max, macOS 27, Swift 6.4.2, release build, median of 30 rounds. Each record has 20 fields, and each run decodes 100 records. See `CodableBenchmark`.

| Scenario | Native strict | TolerantCodable | SmartCodable |
|---|---|---|---|
| Clean data | 1.20 ms | 2.55 ms (2.1x) | 19.96 ms (16.6x) |
| Dirty data | fails | 3.21 ms | 19.97 ms |
| Decode `data.items` by path | 1.17 ms (needs a wrapper model) | 2.55 ms | 19.96 ms |

These numbers come from macOS only. iOS 16 ships the older system JSONDecoder, so on-device results may differ.

## Not supported yet

Multiple candidate keys, class inheritance and value transformers. Key path segments cannot be escaped yet, so keys that contain `.` are not reachable by path.

## License

MIT
