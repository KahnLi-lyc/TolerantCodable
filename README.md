# TolerantCodable

[简体中文](README.zh-Hans.md)

**Strict by default, tolerant on purpose, diagnosable.** Codable extensions for Swift 6.

- Fields you don't annotate keep Codable's strict semantics, so contract drift is never silently hidden.
- Only the fields you wrap tolerate drift: numeric strings, nulls, missing keys, bad array elements, mixed date formats and new enum values.
- Every fallback leaves a redacted, structured diagnostic (type, coding path, reason code, never the raw value).
- Built on the system `JSONDecoder`, with zero dependencies and zero warnings under strict concurrency.

## Installation

```swift
.package(url: "https://github.com/KahnLi-lyc/TolerantCodable.git", from: "0.1.0")
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
| `LYUnknownCaseDecodable` | New raw values | `unknownCase` | Wrong raw type, null, missing |

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

## Conversion helpers

| API | Notes |
|---|---|
| `T.decode(fromJSON: Data/String, atPath:)` | `atPath` such as `"data.items"` is resolved in a single pass, without an `Any` round trip |
| `T.decode(fromJSONObject: [String: Any] / [Any])` | Validates the Foundation object first |
| `value.jsonData()` / `jsonString(prettyPrinted:)` / `jsonObject()` | Encode to Data, text or Foundation objects |
| `LYJSONSerialization.parse/data/string` | Safe JSONSerialization wrapper: invalid objects throw instead of raising ObjC exceptions |

Every helper throws on failure. None of them return `nil`.

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

Multiple candidate keys, `Any` / `[String: Any]` properties, class inheritance, value transformers, and array indices in key paths.

## License

MIT
