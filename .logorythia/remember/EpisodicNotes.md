### 2026-05-08 · MarkdownExtendedView 「再来」触发第八轮分块提交

**事件摘要**：用户以单字「再来」触发第八轮分块提交。工作区有 4 个文件未提交（3 个源码 + 4 个日志文件拆为两笔 add），拆为三笔 commit（`fix(layout)` / `perf(selection)` / `chore(log)`）并直接 `git push`。本轮聚焦表格分割线接合、公式边缘裁剪与选中性能重构。

**上下文标签**：`MarkdownExtendedView`, `git`, `commit`, `workflow`, `分块提交`, `SwiftUI`, `layout`, `performance`, `PreferenceKey`

**关键结论**：
- 第八轮延续极简触发词机制，累计二十笔 commit，工作流零摩擦运行。
- `TableAdaptiveLayout` 在 Grid 交叉场景下的接合修复表明：Grid 替代 VStack/HStack 后，边框连续性需额外关注 colspan 与纵横分割线交汇点。
- Block 公式 `inkPadding` 方案说明数学排版中「墨水边界」与「视图边界」的差异需显式处理，不能仅依赖容器裁剪。
- `SelectableMarkdownRenderer` 的 PreferenceKey 重构验证了「在回调中堆叠子级」是 SwiftUI 性能陷阱：状态外移 + `.background` 预收集是更稳健的坐标采集模式。

**反馈信号**：用户未对执行结果提出异议，极简指令模式继续生效。

**追踪指针**：
- `file:///Volumes/知阳/开发/Packges/MarkdownExtendedView/Sources/MarkdownExtendedView/Renderer/MarkdownRenderer.swift`
- `file:///Volumes/知阳/开发/Packges/MarkdownExtendedView/Sources/MarkdownExtendedView/Renderer/LaTeXView.swift`
- `file:///Volumes/知阳/开发/Packges/MarkdownExtendedView/Sources/MarkdownExtendedView/Renderer/Selection/SelectableMarkdownRenderer.swift`

---

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
