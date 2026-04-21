仓库基线信息：Swift Package Manager 管理的跨平台 Swift 包，主目标为 `MarkdownExtendedView`，测试目标为 `MarkdownExtendedViewTests`。采用 SwiftUI 视图体系，支持 macOS/iOS 原生字体与渲染。

标准命令体系：常规 SPM 工作流，`swift build` 构建，`swift test` 运行测试。

目录职责映射：
- `Sources/MarkdownExtendedView/`：主库源码。
  - `Configuration/`：功能配置（如 `Features.swift`）。
  - `Theme/`：主题系统（`Theme.swift`）。
  - `Renderer/`：Markdown 渲染核心（`MarkdownRenderer.swift`、`LaTeXView.swift`）。
  - `Views/`：原子视图组件（`MarkdownView.swift`、`MermaidView.swift`、`HighlightedCodeView.swift`、`MarkdownImageView.swift`、`SafariView.swift`、`TappableLinkView.swift`）。
- `Tests/MarkdownExtendedViewTests/`：单元测试与功能测试。
- `Package.swift`：依赖管理与包配置。
- `README.md`：对外文档。

关键配置入口：`Package.swift` 定义依赖（如 `ExtendedSwiftMath`）；`Features.swift` 曾用于特性开关，现已移除，默认全量启用。
