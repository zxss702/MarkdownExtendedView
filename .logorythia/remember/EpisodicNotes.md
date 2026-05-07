### 2026-05-08 · MarkdownExtendedView 「再来」触发第七轮分块提交

**事件摘要**：用户以单字「再来」触发第七轮分块提交。工作区有 4 个文件未提交，拆为两笔 commit（`fix(layout)` / `docs`）并直接 `git push`。本轮聚焦 SwiftUI 布局修复与性能清理。

**上下文标签**：`MarkdownExtendedView`, `git`, `commit`, `workflow`, `分块提交`, `SwiftUI`, `layout`, `performance`

**关键结论**：
- 第七轮延续极简触发词机制，累计十六笔 commit，工作流零摩擦运行。
- 超宽表格不再依赖 `FixedSize` 硬截断，改用 `TableAdaptiveLayout` 进行自适应处理，更贴合 SwiftUI 声明式布局。
- Block 级 LaTeX 公式通过 `BlockFormulaKey` 在 FlowLayout 中占位获取正确宽度，避免折行溢出。
- `SelectableMarkdownRenderer` 中多余 content 背景视图叠层的清理表明：拖选性能对视图层级极度敏感，后续改动需警惕隐性叠层增加。

**反馈信号**：用户未对执行结果提出异议，极简指令模式继续生效。

**追踪指针**：
- `file:///Volumes/知阳/开发/Packges/MarkdownExtendedView/Sources/MarkdownExtendedView/Renderer/MarkdownRenderer.swift`
- `file:///Volumes/知阳/开发/Packges/MarkdownExtendedView/Sources/MarkdownExtendedView/Renderer/Selection/SelectableMarkdownRenderer.swift`
