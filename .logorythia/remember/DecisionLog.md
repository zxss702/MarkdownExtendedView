### 2026-05-11 · 弃用 ObjectIdentifier 字典查找，改为渲染管线显式传递

**决策主题**：`ObjectIdentifier(markup as AnyObject)` 字典查找全部失效导致图片/公式/代码引用渲染退化。

**结论**：
- 移除所有基于 `ObjectIdentifier` 的缓存查找（`featuresMap`、`codeHighlights`、`latexSegments`），改为渲染管线显式传递或内联计算。

**背景**：
- 用户报告回归：图片渲染成 `[\(image.plainText)]` 回退文本，公式和代码引用也不渲染。
- 根因诊断：`buildInlineText` 中 `snapshot.featuresMap[ObjectIdentifier(parent as AnyObject)]` 始终返回 nil。
- 调试确认：对 Paragraph、Image、Text 等 5 个不同的 `any Markup` 实例，`ObjectIdentifier(markup as AnyObject)` 全部返回同一个假值，且与 `MarkdownBlockNode.markup` 的 ObjectIdentifier 也不同。

**备选方案**：
- A. 继续用 ObjectIdentifier 但换缓存策略：根因是协议存在体 identity 不稳定，无法修复。
- B. 改用内存地址 / UnsafePointer：Swift 6 下地址不稳定，且不安全。
- C. **采用**：弃用 ObjectIdentifier 字典查找，通过渲染管线显式传递特征/数据。

**理由**：
- `MarkdownBlockNode` 已持有 `features`、`id`（UUID）等稳定标识，无需额外查找。
- blockquote/list 内嵌套的非顶层 block 使用 `computeInlineFeatures` helper 在渲染时局部计算——代价轻微，远优于原 4 次递归遍历。

**影响范围**：
- `MarkdownRenderSnapshot.swift`：`codeHighlights` key 类型从 `ObjectIdentifier` 改为 `UUID`（`MarkdownBlockNode.id`）；`precomputeCodeHighlights` 遍历 `blocks` 而非递归 markup 树。
- `MarkdownRenderer.swift`：
  - `renderBlock` / `renderParagraph` / `renderHeading` / `renderCodeBlock` / `renderRegularCodeBlock` 增加 `features` / `highlightedLines` 参数传递。
  - `buildInlineText` 直接使用传入的 `features`，不再查找 `snapshot.featuresMap`。
  - `renderTextWithLaTeX` 移除 ObjectIdentifier 查找，直接内联计算 segments。
  - 新增 `computeInlineFeatures` helper 处理嵌套 block 的特征计算。
  - `body` 中从 `snapshot.blocks` 取出 `block.features` 和 `snapshot.codeHighlights[block.id]` 传递给 `renderBlock`。
- `MarkdownExtendedViewOptimization_agent_test.swift`：隔离测试改用 `paragraph.features` 和 `snapshot.codeHighlights[codeBlockNode.id]`，不再通过 ObjectIdentifier 查找。

**后续动作**：已提交。全部 102 项测试通过。

---

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

---

### 2026-05-08 · Grid 表格合并列与横纵分割线接合修复

**决策主题**：使用 Grid 渲染表格时，合并列（colspan）与横纵交叉场景下的分割线接合问题。

**结论**：
- 优化 `TableAdaptiveLayout`，在水平与垂直交叉场景中确保网格分割线正确接合，包含 `colspan` 的单元格不再破坏边框连续性。

**背景**：
- 表格迁移至 `Grid` 后，跨列单元格导致部分水平与垂直分割线断开或错位。

**备选方案**：
- A. 回退到 VStack/HStack 嵌套：丧失 Grid 的自适应列宽能力。
- B. 手动绘制分割线：增加渲染复杂度，与 SwiftUI 原生边框体系冲突。

**理由**：
- `TableAdaptiveLayout` 已在现有 Grid 体系内，只需补充交叉场景的几何计算，无需回退或引入自定义绘制。

**影响范围**：
- `MarkdownRenderer.swift`：表格自适应布局分支的接合逻辑。

**后续动作**：无。

---

### 2026-05-08 · Block 级 LaTeX 公式边缘裁剪修复

**决策主题**：Block 级公式中长高符号（如积分号、求和号）在渲染区域边缘被裁剪。

**结论**：
- 为 `MathView` 的 `ascent` 与 `descent` 增加 `inkPadding`，预留墨水火印边距。

**背景**：
- 长积分号或斜体字母在 Block 公式的高度边界处被硬裁剪，影响可读性。

**备选方案**：
- A. 增大外层容器尺寸：无法精确匹配不同公式的高度差异，可能导致过多空白。
- B. 在排版阶段缩小字号：牺牲可读性。

**理由**：
- `inkPadding` 在排版引擎内部处理，精确作用于墨水边界，对整体布局影响最小。

**影响范围**：
- `LaTeXView.swift`：`MathView` 排版参数。

**后续动作**：无。

---

### 2026-05-08 · SelectableMarkdownRenderer PreferenceKey 归并点重构

**决策主题**：`SelectableMarkdownRenderer` 中 `backgroundPreferenceValue` 回调内再次堆叠子级导致的性能与逻辑问题。

**结论**：
- 将状态分离，改用 `.background` 几何视图获取所需数据，彻底消除在 `backgroundPreferenceValue` 回调中堆叠子级的做法。

**背景**：
- 拖选性能对视图层级极度敏感，多级叠层会显著拖慢文本选中响应。

**备选方案**：
- A. 保留原结构但减少叠层：治标不治本，PreferenceKey 归并逻辑仍耦合在回调内。
- B. 完全移除 PreferenceKey：会破坏选中区域的坐标收集能力。

**理由**：
- 状态分离后，几何数据通过 `.background` 在视图构建阶段即完成收集，不再在 PreferenceKey 回调中触发额外子视图创建，兼顾性能与功能。

**影响范围**：
- `SelectableMarkdownRenderer.swift`：PreferenceKey 归并与几何收集逻辑。

**后续动作**：无。
