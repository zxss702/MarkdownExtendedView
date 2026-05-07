### 2026-05-08 · 超宽表格与 Block 级 LaTeX 公式布局溢出修复

**决策主题**：超宽表格与 Block 级 LaTeX 公式在 SwiftUI 流式布局中的溢出问题。

**结论**：
- 引入 `TableAdaptiveLayout` 替代 `FixedSize` 硬截断，使超宽表格内容可自适应折行。
- 为 Block 级公式注入 `BlockFormulaKey`，让 FlowLayout 在排版前获得正确宽度占位，避免溢出。

**背景**：
- `FixedSize` 硬截断导致超宽表格内容被裁切，无法完整显示。
- Block 公式在流式布局中因未正确占位而折行溢出，破坏阅读连续性。

**备选方案**：
- A. 继续用 `FixedSize` 但增大外层容器宽度：无法根治不同内容尺寸下的溢出。
- B. 用 `GeometryReader` 手动计算宽度：增加层级复杂性与性能损耗，违背声明式布局原则。

**理由**：
- `TableAdaptiveLayout` 与 `BlockFormulaKey` 均轻量且与现有 SwiftUI 布局体系兼容，无需引入 GeometryReader。
- 占位键方案对 FlowLayout 侵入最小，仅扩展布局数据契约，不改变渲染管线。

**影响范围**：
- `MarkdownRenderer.swift`：表格渲染逻辑增加自适应分支。
- `LaTeXView.swift`：Block 公式附加 `BlockFormulaKey` 锚点。
- `SelectableMarkdownRenderer.swift`：同步清理多余 content 背景视图叠层。

**后续动作**：无。
