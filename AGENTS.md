# TolerantCodable 开发规范

本文件对参与本仓库的人与 AI 代理同等生效。

## 1. 项目事实

- 仓库：<https://github.com/KahnLi-lyc/TolerantCodable>，SwiftPM 单 Target 库 `TolerantCodable`。
- 平台：iOS 16 / macOS 13 / tvOS 16 / watchOS 9，`swift-tools-version: 6.1`，Swift 6 language mode。
- 依赖：零第三方依赖，只使用 Foundation 与 os。
- 公开类型统一使用 `LY` 前缀；模块名保持 `TolerantCodable`。

## 2. 语义原则

1. **默认严格**：未显式包装的字段保持 Codable 原有语义，结构错误必须抛出。
2. **显式容错**：只有 `@LYDefault`、`@LYLossyArray`、`@LYFlexibleDate`、`LYUnknownCaseDecodable` 会兜底；兜底值不能伪装成真实业务取值（未知枚举必须落到 `unknownCase`）。
3. **可诊断**：每次兼容处理都通过 `LYDiagnosticSink` 记录类型、路径和受控原因码；诊断不得包含原始值或 `debugDescription`。
4. **失败抛错**：便捷转换方法失败时抛出错误，不返回 nil 吞掉原因。
5. 快速路径只是性能优化，任意输入下的结果和诊断必须与兼容路径一致（见 `FastPathTests`）。

## 3. 并发规则

1. `-strict-concurrency=complete` 下零警告。
2. 禁止 `@unchecked Sendable`、`nonisolated(unsafe)`。
3. 可变共享状态只能放在 `OSAllocatedUnfairLock` 中；每次解码使用独立的 decoder 与收集器。
4. 不共享可变的 `DateFormatter`/`JSONDecoder` 实例。

## 4. 测试与提交

- 任何行为变更都要补 `Tests/TolerantCodableTests` 中的用例；修复缺陷先写能复现的失败用例。
- 提交前运行：`swift test`、iOS Simulator 上的 `xcodebuild test -scheme TolerantCodable`、`swiftformat --lint .`。
- 性能相关改动在 `../CodableBenchmark` 重跑并在 PR 中附结果。
- 提交信息使用 `feat:`、`fix:`、`test:`、`docs:`、`refactor:`、`chore:` 前缀。
