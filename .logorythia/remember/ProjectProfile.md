仓库基线信息：Swift Package Manager 管理的跨平台 Swift 包，主目标为 `MarkdownExtendedView`，测试目标为 `MarkdownExtendedViewTests`。采用 SwiftUI 视图体系，支持 macOS/iOS 原生字体与渲染。

标准命令体系：常规 SPM 工作流，`swift build` 构建，`swift test` 运行测试。

目录职责映射：
- `Sources/MarkdownExtendedView/`：主库源码。
  - `Configuration/`：功能配置（如 `Features.swift`）。
  - `Theme/`：主题系统（`Theme.swift`）。
  - `Renderer/`：Markdown 渲染核心（`MarkdownRenderer.swift`、`LaTeXView.swift`）。含 `TableAdaptiveLayout`（超宽表格自适应）与 `BlockFormulaKey`（Block 公式 FlowLayout 宽度占位）。
    - `Selection/`：文本/公式选中逻辑（`SelectableMarkdownRenderer.swift`、`SelectionDocument.swift`、`SelectionDocumentBuilder.swift`），支持 LaTeX 公式 `FormulaSelectionData` 锚点提取与选中 Snapshot 生成。
  - `Views/`：原子视图组件（`MarkdownView.swift`、`MermaidView.swift`、`HighlightedCodeView.swift`、`MarkdownImageView.swift`、`SafariView.swift`、`TappableLinkView.swift`）。
  - `SwiftMath/`：内置数学排版引擎（原 `ExtendedSwiftMath` 外部依赖已移除并内嵌）。
    - `MathBundle/`：字体资源与 bundling（`MathFont.swift`）。
    - `MathRender/`：核心排版与渲染（`MTFontManager`、`MTMathAtomFactory`、`MTMathList`、`MTMathListDisplay`、`MTTypesetter`）。
- `Tests/MarkdownExtendedViewTests/`：单元测试与功能测试。
- `Package.swift`：依赖管理与包配置。
- `README.md`：对外文档。

关键配置入口：`Package.swift` 已移除 `ExtendedSwiftMath` 外部依赖，`SwiftMath` 以内置源码形式存在；`Features.swift` 曾用于特性开关，现已移除，默认全量启用。

工程约束：
- `SwiftMath` 为内置 fork，非外部包；并发安全正从 `NSLock` + `nonisolated(unsafe)` 逐步迁移至 `Mutex` + `@unchecked Sendable`（已覆盖 `MTFontV2.lazy mathTable`、`MTMathAtomFactory` 字典缓存、`RWLock` 底层），修改源码时需同步处理以避免 Swift 6 编译警告。
- `SelectableMarkdownRenderer` 的 content 背景视图叠层需保持精简，多余叠层会显著拖慢文本拖选性能。已重构 PreferenceKey 归并点：状态分离后通过 `.background` 几何视图预收集数据，避免在 `backgroundPreferenceValue` 回调中再次堆叠子级。
- **选区在内容/几何变更时自动清空**：`SelectionLayoutInput` 包含 `containerSize` 字段并参与 `==` 判断，几何变更可触发重算；`updateLayout` 中非拖拽状态下直接清空选区（`selectedRange = nil`），而非钳制到新文档，防止选择错位。
- **渲染管线中禁用 `ObjectIdentifier(markup as AnyObject)` 做字典 key**：`any Markup` 协议存在体的 ObjectIdentifier 不稳定——不同类实例（Paragraph、Image、Text 等）可能返回同一个假值，与 `MarkdownBlockNode.markup` 的 ObjectIdentifier 也不同。所有特征/缓存信息通过渲染管线显式传递，而非基于 ObjectIdentifier 的字典查找。
  - `MarkdownBlockFeatures`（特征掩码）由 `MarkdownBlockNode.features` 直接持有，渲染时沿 `renderBlock` → `renderParagraph/renderHeading` → `renderInlineChildren` → `buildInlineText` 管线传递。
  - `codeHighlights`（语法高亮令牌）key 类型已从 `ObjectIdentifier` 改为 `UUID`（即 `MarkdownBlockNode.id`），通过渲染管线传递。
  - `latexSegments`（LaTeX 段缓存）已移除 ObjectIdentifier 查找，仅保留内联计算（本有 fallback）。
  - 对 blockquote/list 内嵌套的非顶层 block，使用 `computeInlineFeatures` helper 在渲染时局部计算特征掩码。
